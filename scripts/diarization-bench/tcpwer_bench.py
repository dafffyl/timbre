"""Mesure tcpWER / cpWER / WER de la chaîne « Whisper + diarisation + alignement ».

usage : tcpwer_bench.py REUNION [REUNION…]   (fichiers attendus : ami_ref.seglst.json,
whisper_<REUNION>.json = sortie whisper-cli -ml 1, out_<REUNION>.json = diarisation)
"""
import json, re, sys
from meeteval.io import SegLST
from meeteval.wer import cpwer, tcpwer

FILLERS = {'UH', 'UM', 'UHM', 'ERM', 'ER', 'MM', 'MMM', 'HMM', 'HM', 'MHM', 'MMHMM', 'UHHUH', 'MMHM'}
STRIP_FILLERS = False

def strip_fillers(text):
    return ' '.join(w for w in text.split() if w.upper().replace('-', '') not in FILLERS)

def norm(w):
    w = re.sub(r"[^A-Za-z0-9' ]", "", w).upper().strip()
    return w

def whisper_words(path):
    """Mots reconstitués depuis les jetons de whisper-cli (-ojf) : un jeton qui
    commence par une espace ouvre un mot, les autres (« 's », ponctuation) le
    prolongent ; les jetons spéciaux ([_BEG_], [_TT_…]) sont ignorés."""
    d = json.load(open(path))
    out = []
    for seg in d['transcription']:
        for tok in seg['tokens']:
            raw = tok['text']
            if raw.startswith('[_') or not raw.strip():
                continue
            a, b = tok['offsets']['from'] / 1000, tok['offsets']['to'] / 1000
            if raw.startswith(' ') or not out:
                if norm(raw): out.append([a, max(a, b), norm(raw)])
            else:
                out[-1][1] = max(out[-1][1], b, a); out[-1][2] += norm(raw)
    return [tuple(w) for w in out if w[2]]

def parakeet_words(path):
    """Mots depuis les jetons Parakeet (un jeton qui commence par une espace ou « ▁ » ouvre un mot)."""
    d = json.load(open(path))
    out = []
    for tok in d['tokens']:
        raw = tok['token']
        t = norm(raw.replace('\u2581', ' '))
        if not t: continue
        if raw.startswith(' ') or raw.startswith('\u2581') or not out:
            out.append([tok['start'], max(tok['start'], tok['end']), t])
        else:
            out[-1][1] = max(out[-1][1], tok['end']); out[-1][2] += t
    return [tuple(w) for w in out]

def align(words, segs, tol=1.0):
    """Même règle que SpeakerAlignment (recouvrement max, sinon plus proche à ≤ tol s)."""
    segs = sorted(segs, key=lambda s: s[1]); res = []; prev = None
    for a, b, _ in words:
        best = 0; cand = []
        for s, x, y in segs:
            ov = max(0, min(b, y) - max(a, x))
            if ov > best: best, cand = ov, [(s, x, y)]
            elif ov == best and ov > 0: cand.append((s, x, y))
        if cand:
            pick = next((c[0] for c in cand if c[0] == prev), None) or min(cand, key=lambda c: c[1])[0]
            res.append(pick); prev = pick; continue
        dist, s = min(((0 if (a < y and b > x) else (x - b if b <= x else a - y)), s) for s, x, y in segs)
        if dist <= tol: res.append(s); prev = s
        else: res.append('UNK')
    return res

def to_seglst(session, words, labels):
    out = []; cur = None
    for (a, b, t), l in zip(words, labels):
        if cur and cur['speaker'] == l and a - cur['end_time'] < 2.0 and b - cur['start_time'] < 15.0:
            cur['words'] += ' ' + t; cur['end_time'] = b
        else:
            cur = {'session_id': session, 'speaker': l, 'start_time': a, 'end_time': b, 'words': t}; out.append(cur)
    if STRIP_FILLERS:
        for seg in out: seg['words'] = strip_fillers(seg['words'])
        out = [seg for seg in out if seg['words']]
    return out

def score(ref, hyp, name):
    c = cpwer(ref, hyp); t = tcpwer(ref, hyp, collar=5)
    cw = list(c.values())[0]; tw = list(t.values())[0]
    print(f"  {name:34s} cpWER {100*cw.error_rate:5.1f}%   tcpWER {100*tw.error_rate:5.1f}%   (mots réf. {cw.length})")
    return cw.error_rate, tw.error_rate

if __name__ == '__main__':
    allref = json.load(open('ami_ref.seglst.json'))
    asr = 'whisper'
    args = sys.argv[1:]
    if args and args[0] in ('whisper', 'parakeet'): asr, args = args[0], args[1:]
    if args and args[0] == '--sans-hesitations': STRIP_FILLERS, args = True, args[1:]
    for m in args:
        ref = [r for r in allref if r['session_id'] == m]
        if STRIP_FILLERS:
            ref = [{**r, 'words': strip_fillers(r['words'])} for r in ref]
            ref = [r for r in ref if r['words']]
        ref = SegLST(ref)
        refw = [(r['speaker'], r['start_time'], r['end_time']) for r in ref]
        words = whisper_words(f'whisper_{m}.json') if asr == 'whisper' else parakeet_words(f'parakeet_{m}.json')
        dj = json.load(open(f'out_{m}.json'))['variants']['default']
        dsegs = [(s, float(a), float(b)) for s, a, b in dj]
        print(f"== {m} [{asr}]: {len(words)} mots")
        # 1) WER pur : tout le monde = un seul locuteur (qualité de la transcription seule)
        ref1 = SegLST([{**r, 'speaker': 'A'} for r in ref])
        score(ref1, SegLST(to_seglst(m, words, ['A'] * len(words))), f"{asr} seul (1 locuteur)")
        # 2) borne haute : Whisper + diarisation parfaite (locuteur du segment de référence)
        orc = align(words, refw, tol=1.0)
        score(ref, SegLST(to_seglst(m, words, orc)), f"{asr} + diarisation parfaite")
        # 3) chaîne actuelle : Whisper + FluidAudio + alignement de l'app
        cur = align(words, dsegs, tol=1.0)
        score(ref, SegLST(to_seglst(m, words, cur)), "Chaîne actuelle (Timbre)")
