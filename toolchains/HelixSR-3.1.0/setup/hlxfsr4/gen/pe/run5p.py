# from the middle-5 extraction tools (INIT, SHADER, OUT, CB from the environment)
import sys,numpy as np,collections
sys.setrecursionlimit(100000)
from pe import *
import os
R=os.path.dirname(os.path.abspath(__file__))+'/'
import os; init=np.fromfile(os.environ['INIT'],np.uint8)
cb=np.fromfile(os.environ['CB'],np.uint8)
I=Interp(os.environ['SHADER'],init,cb,(0,0,0),(200,100,0))
I.run()
print('loads',len(I.loads),'stores',len(I.stores),'syms',Sym.cnt)
ops=collections.Counter()
seen=set()
def walk(v):
    if not is_sym(v) or v.id in seen: return
    seen.add(v.id); ops[v.op]+=1
    for a in v.a:
        if isinstance(a,(list,tuple)):
            for b in a: walk(b)
        else: walk(a)
for h,addr,vals in I.stores:
    for v in vals: walk(v)
print(ops.most_common(20))
print('store addrs',[ (a - (7712*101+16*201)) for h,a,v in I.stores])
print('load rel addrs',sorted(set(a-16684928-(7712*100+16*200) for a in I.loads))[:20])
from graph import G
g=G()
outs=[]
for h,addr,vals in I.stores:
    for v in vals: outs.append(g.bytes_of(v))
print('neurons',len(g.N))
import collections
kinds=collections.Counter((d['kind'],d.get('shift'),d.get('relu'),len(d['terms'])) for d in g.N.values()); print(kinds)
c0=[k for k in g.order if g.N[k]['kind']=='int' and not g.N[k]['relu']]
l1=[k for k in g.order if g.N[k]['kind']=='int' and g.N[k]['relu']]
l2=[k for k in g.order if g.N[k]['kind']=='res']
print('C0 lo/hi',g.N[c0[0]]['lo'],g.N[c0[0]]['hi'],'L1 lo/hi',g.N[l1[0]]['lo'],g.N[l1[0]]['hi'],'L2',g.N[l2[0]]['lo'],g.N[l2[0]]['hi'])
base=16684928+7712*100+16*200
def uname(u):
    if u[0]=='in': return ('in', u[1]-base, u[2])
    if u[1] in c0: return ('c0',c0.index(u[1]))
    if u[1] in l1: return ('l1',l1.index(u[1]))
    return u
print('C0 units sample',sorted(set(uname(u)[1] for u in g.N[c0[0]]['terms']))[:12])
print('L1 units',sorted(set((uname(u)[0],uname(u)[1]) for u in g.N[l1[0]]['terms']))[:40])
n=g.N[l2[0]]; print('L2 scale',n['scale'],'lin_scale',n['lin_scale'],'res_scale',n['res_scale'],'res unit',uname(n['res']))
print('L2 res units', [ (uname(g.N[k]['res']), g.N[k]['res_scale']) for k in l2][:20])
print('out bytes', [[uname(u) for u in o] for o in outs][:8])
# ---- export matrices
q1c=16684928+2097664+7712*101+16*201; q0c=16684928+7712*101+16*201
def ch_q(u, cen):  # input unit -> channel index within a 16-ch plane centre
    return 4*((u[1]-cen)//4)+u[2]
WC=np.zeros((16,9,16),np.int64); BC=np.zeros(16,np.int64)
for o,k in enumerate(c0):
    n=g.N[k]; BC[o]=n['bias']
    for u,wv in n['terms'].items():
        rel=u[1]-(16684928+7712*100+16*200); row,colb=divmod(rel,7712); kx,wd=divmod(colb,16)
        WC[o,3*row+kx,4*(wd//4)+u[2]]+=wv
W1=np.zeros((64,32),np.int64); B1=np.zeros(64,np.int64)
for o,k in enumerate(l1):
    n=g.N[k]; B1[o]=n['bias']
    for u,wv in n['terms'].items():
        j=c0.index(u[1]) if u[0]=='n' else 16+ch_q(u,q1c)
        W1[o,j]+=wv
W2=np.zeros((32,64),np.int64); B2=np.zeros(32,np.int64); RS=np.zeros(32); RSRC=np.zeros(32,np.int64); LSA=np.zeros(32)
outpos={}
for w_,o in enumerate(outs):
    for kb,u in enumerate(o): outpos[u[1]]=4*w_+kb
for k in l2:
    n=g.N[k]; o=outpos[k]; B2[o]=n['bias']
    for u,wv in n['terms'].items(): W2[o,l1.index(u[1])]+=wv
    u=n['res']; RS[o]=n['res_scale']*n['scale']; RSRC[o]=ch_q(u,q0c) if u[1]-q0c<16 and u[1]>=q0c else 16+ch_q(u,q1c)
    LSA[o]=n['lin_scale']*n['scale']
np.savez(os.environ['OUT'],WC=WC,BC=BC,W1=W1,B1=B1,W2=W2,B2=B2,RS=RS,RSRC=RSRC,LS=LSA)
print('RS',sorted(set(RS.tolist())),'RSRC',RSRC.tolist())
print('LS',sorted(set(LSA.tolist())))
