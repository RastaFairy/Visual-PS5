# from kernels/m9 (input .ll and output .npz as arguments)
# extract post-pass network weights from stock IR (literal weights)
import re,numpy as np
import sys
T=open(sys.argv[1]).read()
D=dict(re.findall(r'^  (%\d+) = (.*?)(?:\s+;.*)?$',T,re.M))
DOT=re.compile(r'call i32 @dx\.op\.dot4AddPacked\.i32\(i32 163, i32 ([%\w-]+), i32 ([%\w-]+), i32 ([%\w-]+)\)')
def chain(v):
    xs=[]
    while v in D and DOT.match(D[v]):
        a,x,w=DOT.match(D[v]).groups(); xs.append((x,int(w))); v=a
    return v,xs[::-1]
def sb(w): return [((w>>(8*k))&255)-256*(((w>>(8*k))&255)>127) for k in range(4)]
def leaf(v):
    # follow requant/clamp/phi back to a dot chain end
    seen=0
    while v in D and seen<40:
        seen+=1; e=D[v]
        if DOT.match(e): return v
        m=re.match(r'phi i32 \[ (%\d+), %56 \]',e) or re.match(r'phi i32 \[ ([%\w-]+), %\d+ \]',e)
        if m: v=m.group(1); continue
        m=re.match(r'call i32 @dx\.op\.binary\.i32\(i32 3[78], i32 (%\d+), i32 -?\d+\)',e)
        if m: v=m.group(1); continue
        m=re.match(r'(?:ashr|lshr|shl|and|add|fptosi float|sitofp i32)\s*(?:i32|float)?\s*(%\d+)',e)
        if m: v=m.group(1); continue
        m=re.match(r'call float @dx\.op\.unary\.f32\(i32 26, float (%\d+)\)',e)
        if m: v=m.group(1); continue
        m=re.match(r'f(?:mul|add) fast float (%\d+), (%\d+)',e)
        if m:
            a,b=m.group(1),m.group(2)
            # prefer the branch that reaches a dot chain via sitofp
            for c in (a,b):
                if 'sitofp' in D.get(c,'') and DOT.match(D.get(D[c].split()[2],'') or ''): return D[c].split()[2]
            v=a if 'fmul' in D.get(a,'') or 'sitofp' in D.get(a,'') else b; continue
        m=re.match(r'fmul fast float (%\d+), [\d.e+-]+',e)
        if m: v=m.group(1); continue
        break
    return v
def word_bytes(w):
    out={}
    def walk(v):
        e=D.get(v,'')
        m=re.match(r'or i32 (%\d+), (%\d+)$',e)
        if m: walk(m.group(1)); walk(m.group(2)); return
        m=re.match(r'shl i32 (%\d+), (8|16|24)$',e); sh=0
        if m: sh=int(m.group(2))//8
        m2=re.match(r'and i32 (%\d+), (255|65280|16711680)$',e)
        if m2:
            sh={'255':0,'65280':1,'16711680':2}[m2.group(2)]
            e2=D.get(m2.group(1),''); m3=re.match(r'shl i32 (%\d+), (8|16)$',e2)
            out[sh]=leaf(m3.group(1) if m3 else m2.group(1)); return
        out[sh]=leaf(m.group(1) if m else v)
    walk(w); return [out.get(k) for k in range(4)]
ends=[v for v,e in D.items() if DOT.match(e) and v not in {DOT.match(x).group(1) for x in D.values() if DOT.match(x)}]
order=lambda vs: sorted(vs,key=lambda v:int(v[1:]))
c0=order([v for v in ends if len(chain(v)[1])==36])
# C0 tap loads -> tap index by load order
loads=[]; W0=np.zeros((16,9,16),np.int64); B0=np.zeros(16,np.int64)
for o,v in enumerate(c0):
    b,xs=chain(v); B0[o]=int(b)
    for k,(x,w) in enumerate(xs):
        t,j=divmod(k,4)
        for bb in range(4): W0[o,t,4*j+bb]=sb(w)[bb]
# W1: chains len4 whose inputs are C0 output words
c0w=[x for x,_ in chain(order([v for v in ends if len(chain(v)[1])==4 and int(v[1:])<1900 and int(v[1:])>1700])[0])[1]]
print('W1 input words',c0w, [word_bytes(x) for x in c0w][:2])
def layer(chs, inwords, inmap):
    # chs: chain ends (output order); inwords: expected input words; inmap: word -> list of 4 source channels
    W=np.zeros((len(chs),4*len(inwords)),np.int64); B=np.zeros(len(chs),np.int64)
    for o,v in enumerate(chs):
        b,xs=chain(v); B[o]=int(b); assert [x for x,_ in xs]==inwords,(v,[x for x,_ in xs])
        for k,(x,w) in enumerate(xs):
            for bb in range(4): W[o,inmap[x][bb]]=sb(w)[bb]
    return W,B
c0map={}
for k,x in enumerate(c0w):
    c0map[x]=[c0.index(l) for l in word_bytes(x)]
w1=order([v for v in ends if len(chain(v)[1])==4 and [x for x,_ in chain(v)[1]]==c0w])
W1,B1=layer(w1,c0w,c0map); print('W1',W1.shape,B1[:4])
w2=order([v for v in ends if len(chain(v)[1])==8])
w1w=[x for x,_ in chain(w2[0])[1]]
w1map={x:[w1.index(l) for l in word_bytes(x)] for x in w1w}
W2,B2=layer(w2,w1w,w1map); print('W2',W2.shape,B2[:4],'w1 word0',word_bytes(w1w[0]))
rw=['%2348','%2404','%2460','%2516']
print('r words',[word_bytes(x) for x in rw][:2])
rmap={x:[4*k+b for b in range(4)] for k,x in enumerate(rw)}; print('w2 order',w2[:5])
hd=order([v for v in ends if len(chain(v)[1])==4 and [x for x,_ in chain(v)[1]]==rw])
print('head chains',len(hd))
WH,BH=layer(hd,rw,rmap); WH=WH.reshape(4,8,16); BH=BH.reshape(4,8)
print('head biases per subpixel',BH.tolist())
np.savez(sys.argv[2],W0=W0,B0=B0,W1=W1,B1=B1,W2=W2,B2=B2,WH=WH,BH=BH)
