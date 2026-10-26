import sys, json, itertools
from der import load_rttm
def pseudo_words(ref, step=0.3, drop_overlap=True):
    words=[]
    for spk,a,b in ref:
        t=a
        while t < b-0.05:
            e=min(b,t+step)
            # mot dit pendant qu'un autre locuteur parle : impossible à trancher
            # par diarisation (le transcript le mélange), on l'écarte du score
            ov=any(s!=spk and x<e and y>t for s,x,y in ref) if drop_overlap else False
            if not ov: words.append((t, e, spk))
            t+=step
    return words
def align(words, segs, tol, sandwich=False):
    segs=sorted(segs,key=lambda s:s[1]); out=[]; prev=None
    for a,b,_ in words:
        best=0; cand=[]
        for s,x,y in segs:
            ov=max(0,min(b,y)-max(a,x))
            if ov>best: best=ov; cand=[(s,x,y)]
            elif ov==best and ov>0: cand.append((s,x,y))
        if cand:
            pick=next((c[0] for c in cand if c[0]==prev), None) or min(cand,key=lambda c:c[1])[0]
            out.append(pick); prev=pick; continue
        # trou : plus proche
        d=[(0 if (a<y and b>x) else (x-b if b<=x else a-y), s, x, y) for s,x,y in segs]
        dist,s,x,y=min(d, key=lambda t:t[0])
        if dist<=tol: out.append(s); prev=s; continue
        if sandwich:
            before=[t for t in segs if t[2]<=a]; after=[t for t in segs if t[1]>=b]
            if before and after and before[-1][0]==after[0][0] and (a-before[-1][2])<6 and (after[0][1]-b)<6:
                out.append(before[-1][0]); continue
        out.append(None)
    return out
def score(ref_words, labels):
    hs=sorted({l for l in labels if l}); rs=sorted({w[2] for w in ref_words})
    n=max(len(hs),len(rs)); cnt={}
    for (a,b,r),l in zip(ref_words,labels):
        if l: cnt[(l,r)]=cnt.get((l,r),0)+(b-a)
    best=None;bv=-1
    for perm in itertools.permutations(rs+[None]*(max(0,len(hs)-len(rs))), len(hs)):
        v=sum(cnt.get((h,r),0) for h,r in zip(hs,perm) if r)
        if v>bv: bv=v;best=dict(zip(hs,perm))
    ok=wrong=none=0
    for (a,b,r),l in zip(ref_words,labels):
        if l is None: none+=1
        elif best.get(l)==r: ok+=1
        else: wrong+=1
    N=len(labels); return 100*ok/N,100*wrong/N,100*none/N
if __name__=='__main__':
    ref=load_rttm(sys.argv[1]); data=json.load(open(sys.argv[2]))['variants']; W=pseudo_words(ref)
    for var in ['default','overlapSegments']:
        segs=[(s,float(a),float(b)) for s,a,b in data[var]]
        for label,tol,sw in [('tol 1s (actuel)',1.0,False),('tol 3s',3.0,False),('tol 3s+sandwich',3.0,True),('toujours le plus proche',1e9,False)]:
            ok,wr,no=score(W,align(W,segs,tol,sw))
            print(f"{var:16s} {label:26s} correct {ok:5.1f}%  faux {wr:5.1f}%  non attribué {no:5.1f}%")
