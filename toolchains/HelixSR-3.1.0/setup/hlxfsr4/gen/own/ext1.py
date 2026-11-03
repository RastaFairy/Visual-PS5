# from kernels/own (stock IR, weights, output as arguments)
import re,json,numpy as np,sys
T=open(sys.argv[1]).read()
D=dict(re.findall(r'^  (%\d+) = (.*?)(?:  ;.*)?$',T,re.M))
DOT=re.compile(r'call i32 @dx\.op\.dot4AddPacked\.i32\(i32 163, i32 ([%\w-]+), i32 ([%\w-]+), i32 ([%\w-]+)\)')
def chain(v):
    terms=[]
    while v in D and DOT.match(D[v]):
        a,x,w=DOT.match(D[v]).groups(); terms.append((x,w)); v=a
    return v,terms[::-1]
def strip(v):
    # follow clamp/requant to the leaf value; return (leaf, ops)
    ops=[]
    while v in D:
        e=D[v]
        m=re.match(r'call i32 @dx\.op\.binary\.i32\(i32 3[78], i32 (%\w+), i32 -?\d+\)',e)
        if m: v=m.group(1); continue
        m=re.match(r'and i32 (%\w+), (255|65280|16711680)$',e)
        if m: v=m.group(1); continue
        m=re.match(r'shl i32 (%\w+), (8|16|24)$',e)
        if m: v=m.group(1); continue
        m=re.match(r'ashr i32 (%\w+), (\d+)$',e)
        if m: ops.append(('ashr',int(m.group(2)))); v=m.group(1); continue
        m=re.match(r'add i32 (%\w+), (%\w+)$',e)
        if m and m.group(2) in D and re.match(r'and i32 %\w+, 1$',D[m.group(2)]): v=m.group(1); continue
        m=re.match(r'add i32 (%\w+), (63|255|127|31|15)$',e)
        if m: v=m.group(1); continue
        m=re.match(r'phi i32 \[ (%\w+), %91 \]',e)
        if m: v=m.group(1); continue
        break
    return v,ops
def word_bytes(w):
    # w = or chain of 4 byte fields -> list of 4 leaves ordered by byte
    leaves={}
    def walk(v):
        e=D.get(v,'')
        m=re.match(r'or i32 (%\w+), (%\w+)$',e)
        if m: walk(m.group(1)); walk(m.group(2)); return
        sh=0
        m=re.match(r'shl i32 (%\w+), (8|16|24)$',e)
        if m: sh=int(m.group(2))//8
        else:
            m2=re.match(r'and i32 (%\w+), (65280|16711680)$',e)
            if m2:
                e2=D.get(m2.group(1),''); m3=re.match(r'shl i32 (%\w+), (8|16)$',e2); sh=int(m3.group(2))//8
        leaves[sh]=strip(v)
    walk(w); return [leaves.get(i) for i in range(4)]
# --- C0 (fast path block %91): 16 chains of 36
ends=[v for v,e in D.items() if DOT.match(e) and not any(v==DOT.match(x).group(1) for x in [D[k] for k in D if DOT.match(D[k])][:0])]
accs=set(DOT.match(e).group(1) for e in D.values() if DOT.match(e))
ends=[v for v,e in D.items() if DOT.match(e) and v not in accs]
EV={}
for v,e in D.items():
    m=re.match(r'extractvalue %dx\.types\.ResRet\.i32 (%\w+), (\d)$',e)
    if m: EV[v]=(m.group(1),int(m.group(2)))
c0=[v for v in ends if len(chain(v)[1])==36]
print('c0 ends',c0[:3],len(c0))
b,terms=chain(c0[0]); print('bias',b,D.get(b,'')[:60]); print([ (EV.get(x),w) for x,w in terms[:6]])
# phi mapping of c0 ends into %1549..
for v in ['%1549','%1550','%1564']: print(v,D[v][:90])
w1=[v for v in ends if len(chain(v)[1])==4 and v not in c0]
w1=[v for v in w1 if int(v[1:])>1547 and int(v[1:])<2200]
print('w1',len(w1),w1[:3]); b,terms=chain(w1[0]); print('bias',b,D.get(b,'')[:70])
for x,w in terms: print(x,w,[ (l, o) for l,o in [lb if lb else (None,None) for lb in word_bytes(x)]])
w2=[v for v in ends if len(chain(v)[1])==8 and int(v[1:])<2400]
print('w2',len(w2),w2[:3]); b,terms=chain(w2[0]); print('bias',b,D.get(b,'')[:70])
print([ [l for l,o in word_bytes(x)] for x,w in terms][:3])
# residual: which W2 chain pairs with which input byte: %2352 = sitofp %2201 ... first word of residual uses %2201,%2209,%2217,%2225
print('w2 order',w2)
tl=[v for v in ends if len(chain(v)[1])==16]
print('tail',len(tl),tl[:2]); b,terms=chain(tl[0]); print('bias',b,D.get(b,'')[:80]); print(terms[:3])
for x,w in terms[:2]: print(x,D.get(x,'')[:100], w, D.get(w,'')[:100])
def lds_idx(v):
    # load i32 from gep with index expr; decode constants px',py',word from the add chain
    g=re.match(r'load i32, i32 addrspace\(3\)\* (%\w+)',D[v]).group(1)
    idx=re.search(r'i32 0, i32 (%\w+)$',D[g]).group(1)
    w=int(re.match(r'add i32 (\d+), ',D[idx]).group(1)); m4=re.match(r'add i32 \d+, (%\w+)',D[idx]).group(1)
    s=re.match(r'mul i32 (%\w+), 4',D[m4]).group(1); py=D[s]; m2=re.match(r'add i32 (\S+), (%\w+)',py)
    pyv=m2.group(1); s2=re.match(r'mul i32 (%\w+), 2',D[m2.group(2)]).group(1); m3=re.match(r'add i32 (\S+), (%\w+)',D[s2])
    return (m3.group(1),pyv,w)
def wsrc(v):
    r,c=EV[v]; adr=re.search(r'i32 (%\w+|\d+), i32 undef',D[r]).group(1)
    return (adr,D.get(adr,'')[:70],c)
for x,w in chain(tl[0])[1]: print(lds_idx(x), wsrc(w))
print('tail ends order',tl)
for v in ['%2682','%2750','%2818','%2886']: print(v,D[v][:90])
for e in tl:
    b,terms=chain(e); x,w=terms[0]; print(e,'bias',EV.get(b),'w0',wsrc(w)[0],D[wsrc(w)[0]][:40], D.get(D[wsrc(w)[0]].split()[2].rstrip(','),'')[:60])
for v in ['%3198','%3231']: print(v,[l for l,o in word_bytes(v)])
for v in ['%3174','%3166','%3170']: print(v,D[v][:80])
INIT=np.fromfile(sys.argv[2],np.uint8)
def i32at(o): return int(np.frombuffer(INIT[o:o+4].tobytes(),np.int32)[0])
def sb(word,b): v=(int(word)>>(8*b))&255; return v-256 if v>127 else v
def bias_of(v):  # bias extract -> (load offset, comp)
    r,c=EV[v]; off=int(re.search(r'i32 (\d+), i32 undef',D[r]).group(1)); return (off+4*c)
W0=np.zeros((16,3,3,16),np.int32); B0=np.zeros(16,np.int64)
for e in c0:
    b,terms=chain(e); c=(bias_of(b)-3456)//4; B0[c]=i32at(bias_of(b))
    loads=[]
    for x,w in terms:
        r,j=EV[x]
        if r not in loads: loads.append(r)
        k=loads.index(r)
        for bb in range(4): W0[c,k//3,k%3,4*j+bb]=sb(w,bb)
W1=np.zeros((32,16),np.int32); B1=np.zeros(32,np.int64)
for e in w1:
    b,terms=chain(e); o=bias_of(b); c=(o-4096)//4; B1[c]=i32at(o)
    for j,(x,w) in enumerate(terms):
        for bb in range(4): W1[c,4*j+bb]=sb(w,bb)
W2=np.zeros((16,32),np.int32); B2=np.zeros(16,np.int64)
for e in w2:
    b,terms=chain(e); o=bias_of(b); c=(o-4736)//4; B2[c]=i32at(o)
    for j,(x,w) in enumerate(terms):
        for bb in range(4): W2[c,4*j+bb]=sb(w,bb)
WT=np.zeros((32,4,16),np.int32); BT=np.zeros(32,np.int64)
for c in range(32):
    BT[c]=i32at(6912+4*c)
    for k in range(4):
        for i in range(16): WT[c,k,i]=np.int8(INIT[4864+512*k+16*c+i])
np.savez(sys.argv[3],W0=W0,B0=B0,W1=W1,B1=B1,W2=W2,B2=B2,WT=WT,BT=BT)
print('saved', B0[:4], B1[:4], B2[:4], BT[:4], np.abs(W0).max(), np.abs(WT).max())
