# Banc d'essai de la diarisation

Mesure FluidAudio (pipeline offline « Pyannote Community-1 ») sur des
réunions annotées, hors de l'app. Résultats et conclusions :
`docs/spikes/diarization-ami-far-field.md`.

## Données (AMI, CC-BY-4.0)

Enregistrement complet du **micro distant** (`Array1-01`, proxy d'un téléphone
posé sur la table) et annotations de locuteurs :

```bash
M=ES2004a   # aussi IS1009a, TS3003a, EN2002a (jeu de test AMI)
curl -o ami/$M.Array1-01.wav "https://groups.inf.ed.ac.uk/ami/AMICorpusMirror/amicorpus/$M/audio/$M.Array1-01.wav"
curl -o ami/$M.rttm "https://raw.githubusercontent.com/BUTSpeechFIT/AMI-diarization-setup/main/only_words/rttms/test/$M.rttm"
```

## Lancer

```bash
cd scripts/diarization-bench && swift build -c release
N=$(awk '{print $8}' ami/$M.rttm | sort -u | wc -l)
.build/release/diarbench ami/$M.Array1-01.wav "$PWD/models" out_$M.json $N   # variantes de config
python3 der.py ami/$M.rttm out_$M.json                                      # DER par variante
python3 wordsim.py ami/$M.rttm out_$M.json                                  # attribution des mots (règles de repli)
.build/release/reassign ami/$M.Array1-01.wav ami/$M.rttm out_$M.json extra_$M.json default
python3 eval_extra.py $M                                                    # essai « réassignation par voix »
```

Le premier lancement télécharge les modèles (~500 Mo, `models/`). `ami/`,
`models/` et `out_*.json` ne sont pas versionnés.

## Limites

- `der.py` : DER par trames de 10 ms, collar 0,25 s, chevauchements comptés,
  correspondance locuteurs par force brute — proche de `pyannote.metrics`
  mais pas identique.
- `wordsim.py` : « mots » = tranches de 0,3 s de la parole annotée, **hors
  passages où plusieurs personnes parlent** (indécidables par diarisation :
  le transcript les mélange). Ce n'est pas la sortie réelle de Whisper.
- AMI : anglais, 4 locuteurs autour d'une table, micro en réseau — pas le cas
  « 2 personnes, téléphone posé » ; à compléter avec des enregistrements
  réels (voir `DebugAudioRetention`).
