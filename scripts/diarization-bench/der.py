import sys, json, itertools, numpy as np
def load_rttm(p):
    segs=[]
    for l in open(p):
        f=l.split()
        if f[0]=='SPEAKER': segs.append((f[7], float(f[3]), float(f[3])+float(f[4])))
    return segs
def mat(segs, T, res=0.01):
    spk=sorted({s for s,_,_ in segs}); idx={s:i for i,s in enumerate(spk)}
    M=np.zeros((len(spk), T), dtype=np.int8)
    for s,a,b in segs: M[idx[s], int(a/res):int(np.ceil(b/res))]=1
    return spk, M
def der(ref, hyp, collar=0.25, res=0.01):
    T=int(max(max(b for _,_,b in ref), max((b for _,_,b in hyp), default=0))/res)+2
    rs,R=mat(ref,T); hs,H=mat(hyp,T) if hyp else ([],np.zeros((0,T),dtype=np.int8))
    # masque collar autour des frontières de référence
    keep=np.ones(T,bool)
    for _,a,b in ref:
        for t in (a,b):
            keep[max(0,int((t-collar)/res)):int((t+collar)/res)+1]=False
    R=R[:,keep]; H=H[:,keep]
    nref=R.sum(0); nhyp=H.sum(0)
    # meilleure correspondance (force brute, ≤ 7 locuteurs)
    ov=np.array([[ (R[i]&H[j]).sum() for j in range(len(hs))] for i in range(len(rs))]) if len(hs) else np.zeros((len(rs),0))
    best=0; 
    n=max(len(rs),len(hs)); pad=np.zeros((n,n)); pad[:len(rs),:len(hs)]=ov
    for perm in itertools.permutations(range(n)):
        v=sum(pad[i,perm[i]] for i in range(n)); best=max(best,v)
    total=nref.sum()
    miss=np.maximum(0,nref-nhyp).sum(); fa=np.maximum(0,nhyp-nref).sum()
    correct=best  # frames où locuteur mappé correct (approx. sans overlap fin)
    conf=np.minimum(nref,nhyp).sum()-correct
    return dict(DER=100*(miss+fa+conf)/total, miss=100*miss/total, fa=100*fa/total, conf=100*conf/total, nhyp=len(hs), nref=len(rs))
if __name__=='__main__':
    ref=load_rttm(sys.argv[1]); data=json.load(open(sys.argv[2]))['variants']
    for name,segs in data.items():
        hyp=[(s,float(a),float(b)) for s,a,b in segs]
        r=der(ref,hyp)
        print(f"{name:16s} DER {r['DER']:5.1f}%  miss {r['miss']:4.1f}  fa {r['fa']:4.1f}  conf {r['conf']:4.1f}  speakers {r['nhyp']}/{r['nref']}")
