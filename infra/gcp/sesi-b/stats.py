import sys,csv,statistics as st
rows=[r for r in csv.reader(open(sys.argv[1])) if len(r)==8]
def q(v,p):
    v=sorted(v); k=(len(v)-1)*p; f=int(k); c=min(f+1,len(v)-1); return v[f]+(v[c]-v[f])*(k-f)
g={}
for r in rows: g.setdefault((r[0],r[1]),[]).append(r)
print("label,proto,n,metric,median_ms,p90_ms,codes")
for (l,p),rs in g.items():
    for idx,m in [(3,'connect'),(4,'appconnect'),(5,'ttfb'),(6,'total')]:
        if p=='http' and m=='appconnect': continue
        v=[float(r[idx])*1000 for r in rs]
        print(f"{l},{p},{len(v)},{m},{q(v,.5):.1f},{q(v,.9):.1f},{'/'.join(sorted(set(r[7] for r in rs)))}")
