import sys, json
from der import load_rttm, der
from wordsim import pseudo_words, align, score
m=sys.argv[1]; maxdist=float(sys.argv[2]) if len(sys.argv)>2 else 9
ref=load_rttm(f'ami/{m}.rttm'); data=json.load(open(f'out_{m}.json'))['variants']
base=[(s,float(a),float(b)) for s,a,b in data['default']]
extra=json.load(open(f'extra_{m}.json'))['extra']
add=[(s,float(a),float(b)) for s,a,b,d1,d2 in extra if float(d1)<=maxdist]
W=pseudo_words(ref)
for name,hyp in [('actuel',base),('+ réassignation par voix',base+add)]:
    r=der(ref,hyp); ok,wr,no=score(W,align(W,hyp,1.0))
    print(f"{m} {name:26s} DER {r['DER']:5.1f}% (miss {r['miss']:4.1f} conf {r['conf']:4.1f}) | mots: correct {ok:5.1f}% faux {wr:5.1f}% non attribué {no:4.1f}%")
