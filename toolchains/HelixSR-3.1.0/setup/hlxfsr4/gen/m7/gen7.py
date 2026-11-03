# gen7.py OUT.hlsl : FP16 middle-7 (1080p layout): thread per Q pixel, direct 3x3 C0 loop over taps,
# L1->L2 loop over L1 output pair, pixel-shuffle loop over sub-pixels. Weights in uint4 tables.
import numpy as np, sys, os
out=sys.argv[1]
w=np.load(os.environ['W7'])
# model constants (decoded from AMD's shaders): ultra = C0 shift 9, L2 /128 with residual A/2 + B, output RH/2 + PS/256
U=os.environ.get('MODEL')=='ultra'; SC0=512.0 if U else 256.0; SL2=128.0 if U else 64.0; RA,RB=(0.5,1.0) if U else (1.0,2.0)
f16=lambda x: np.float16(x)
def pk(a,b): return int(np.array([f16(a),f16(b)]).view(np.uint32)[0])
hf=lambda x: repr(float(f16(x)))
def h2(a,b): return 'half2(%s,%s)'%(hf(a),hf(b))
PERM=[c for k in range(4) for c in (4*k,4*k+2,4*k+1,4*k+3)]
import os
ORD=[int(x) for x in np.load(__import__('os').path.join(__import__('os').path.dirname(__import__('os').path.abspath(__file__)), 'order_p7.npy'))] if os.environ.get('SKIP') else list(range(64))
# tables
TC=[]            # [t][q=PERM slot 0..15][o pair 0..7]  (C0 /256)
for t in range(9):
    for q in range(16):
        i=PERM[q]
        for o in range(8): TC.append(pk(w['WC'][2*o,t,i]/SC0,w['WC'][2*o+1,t,i]/SC0))
# L1 input order: j<16: c channel j (c pairs natural: pair j>>1 slot j&1); j>=16: B in PERM order slot q -> channel PERM[q]
inch=list(range(16))+[16+PERM[q] for q in range(16)]
# L2 output pair m: m<8 -> channels (PERM[2m],PERM[2m+1]); m>=8 -> 16+same
L2ch=[(PERM[2*m],PERM[2*m+1]) for m in range(8)]+[(16+PERM[2*m],16+PERM[2*m+1]) for m in range(8)]
TL=[]            # per o in 0..31: [L1: 32 dwords over inch] [L2: for h.x (ch 2o): 16 dwords over m][for h.y: 16]
for o in range(32):
    for j in range(32): TL.append(pk(w['W1'][ORD[2*o],inch[j]]/128.0,w['W1'][ORD[2*o+1],inch[j]]/128.0))
    for cc in (ORD[2*o],ORD[2*o+1]):
        for m in range(16): TL.append(pk(w['W2'][L2ch[m][0],cc]/SL2,w['W2'][L2ch[m][1],cc]/SL2))
TB1=[pk(w['B1'][ORD[2*o]]/128.0,w['B1'][ORD[2*o+1]]/128.0) for o in range(32)]
# PS: input g pairs = L2 pairs m (slot s -> channel L2ch[m][s]); outputs PERM pairs (to match r_H unpack + store)
TP=[]            # [s=py*2+px][m in 0..15][slot 0..1][out pair 0..7]
for s in range(4):
    py,px=divmod(s,2)
    for m in range(16):
        for sl in range(2):
            ci=L2ch[m][sl]
            for o in range(8): TP.append(pk(w['WP'][py,px,PERM[2*o],ci]/256.0,w['WP'][py,px,PERM[2*o+1],ci]/256.0))
def table(name,v):
    while len(v)%4: v=v+[0]
    return 'static const uint4 %s[%d]={%s};'%(name,len(v)//4,','.join('uint4(%du,%du,%du,%du)'%tuple(v[i:i+4]) for i in range(0,len(v),4)))
L=[]; e=L.append
e('RWByteAddressBuffer Scratch : register(u13); ByteAddressBuffer Init : register(t21);')
e(table('TC',TC)); e(table('TL',TL)); e(table('TP',TP))
e('static const uint TB1[32]={%s};'%','.join('%du'%x for x in TB1))
e('half2 H(uint u){ return asfloat16(uint16_t2(u&0xffff,u>>16)); }')
e('uint P(half2 v){ return uint(asuint16(v.x))|(uint(asuint16(v.y))<<16); }')
e('half2 O(half2 v, uint z){ return H(P(v)^z); }')
e('uint Pb(int16_t2 v){ return uint(uint16_t(v.x))|(uint(uint16_t(v.y))<<16); }')
e('uint B4b(int16_t2 a, int16_t2 b){ return (Pb(a)&0x00ff00ffu)|((Pb(b)&0x00ff00ffu)<<8); }')
e('half2 R(half2 v,int lo,int hi){ return clamp(round(v),half2(lo,lo),half2(hi,hi)); }')
e('int16_t2 Bt(half2 v){ return asint16(v+half2(1536,1536)); }')
e('half2 UA(uint x, uint z){ return O(H(((x^0x80808080u)&0x00ff00ffu)|0x64006400u)-half2(1152,1152),z); }')
e('half2 UB(uint x, uint z){ return O(H((((x^0x80808080u)>>8)&0x00ff00ffu)|0x64006400u)-half2(1152,1152),z); }')
e('[WaveSize(32)] [numthreads(64,1,1)] void main(uint3 g:SV_GroupID, uint tid:SV_GroupIndex){')
e(' uint x=g.x*64+tid, y=g.y;')
e(' uint Z=WaveReadLaneFirst(tid&31u);')
e(' if(x>=480u) return;')
e(' uint base=7712*y+16*x;')
for o in range(8): e(' half2 a%d=%s;'%(o,h2(w['BC'][2*o]/SC0,w['BC'][2*o+1]/SC0)))
e(' [loop] for(uint t=Z;t<9u+Z;t++){')
e('  uint ky=t/3u, kx=t-3u*ky;')
if os.environ.get('F16IO'):
    e('  uint fa=33418048+15424*(y+ky)+32*(x+kx); uint4 r0=Scratch.Load4(fa), r1=Scratch.Load4(fa+16);')
    e('  if((x==0u&&kx==0u)||(x==479u&&kx==2u)||(y==0u&&ky==0u)||(y==269u&&ky==2u)){ r0=0; r1=0; }')
else:
    e('  uint4 r=Scratch.Load4(base+7712*ky+16*kx);')
e('  uint tb=t*32u;')
for k in range(4):
    if os.environ.get('F16IO'): e('  half2 dA%d=H(r%d[%d]), dB%d=H(r%d[%d]);'%(k,(2*k)//4,(2*k)%4,k,(2*k+1)//4,(2*k+1)%4))
    else:
        e('  half2 dA%d=UA(r[%d],Z), dB%d=UB(r[%d],Z);'%(k,k,k,k))
for q in range(16):
    k=q//4; v='d%s%d.%s'%('AABB'[q%4],k,'xyxy'[q%4])
    for o4 in range(2):
        e('  { uint4 W=TC[tb+%d];'%(q*2+o4))
        for oo in range(4): o=4*o4+oo; e('   a%d=%s%s*H(W[%d])+a%d;'%(o,v,v[-1],oo,o))
        e('  }')
e(' }')
for o in range(8): e((' half2 c%d=a%d;' if os.environ.get('CONT') else ' half2 c%d=R(a%d,-128,127);')%(o,o))
if os.environ.get('F16IO'):
    e(' uint ca=15424*(y+1)+32*(x+1); uint4 rb0=Scratch.Load4(37613376+ca), rb1=Scratch.Load4(37613376+ca+16), ra0=Scratch.Load4(33418048+ca), ra1=Scratch.Load4(33418048+ca+16);')
else:
    e(' uint4 rb=Scratch.Load4(base+2097664+7712+16);'); e(' uint4 ra=Scratch.Load4(base+7712+16);')
for k in range(4):
    if os.environ.get('F16IO'):
        a_,b_=divmod(2*k,4); c_,d_=divmod(2*k+1,4)
        e(' half2 bA%d=H(rb%d[%d]), bB%d=H(rb%d[%d]), xA%d=H(ra%d[%d]), xB%d=H(ra%d[%d]);'%(k,a_,b_,k,c_,d_,k,a_,b_,k,c_,d_))
    else:
        e(' half2 bA%d=UA(rb[%d],Z), bB%d=UB(rb[%d],Z), xA%d=UA(ra[%d],Z), xB%d=UB(ra[%d],Z);'%((k,k)*4))
# in-register L1 inputs: j<16 -> c pairs natural ; j>=16 -> B PERM q=j-16 -> b%s%d
def inj(j):
    if j<16: return 'c%d.%s'%(j>>1,'xy'[j&1])
    q=j-16; return 'b%s%d.%s'%('AABB'[q%4],q//4,'xyxy'[q%4])
# L2 accum init: m<8 -> A pair m + bias ; m>=8 -> 2*B pair + bias.  pair m of PERM == (dA/dB of k=m//2)
for m in range(16):
    k=(m%8)//2; src=('x%s%d' if m<8 else 'b%s%d')%('AB'[m%2],k)
    c0,c1=L2ch[m]
    r=RA if m<8 else RB; e(' half2 z%d=%s*half2(%s,%s)+%s;'%(m,src,r,r,h2(w['B2'][c0]/SL2,w['B2'][c1]/SL2)))
e(' [loop] for(uint o=Z;o<32u+Z;o++){')
e('  uint wb=o*16u;')
e('  half2 s=H(TB1[o]);')
for j4 in range(8):
    e('  { uint4 W=TL[wb+%d];'%j4)
    for jj in range(4):
        j=4*j4+jj; v=inj(j); e('   s=%s%s*H(W[%d])+s;'%(v,v[-1],jj))
    e('  }')
e('  half2 h=max(s,half2(0,0));' if os.environ.get('CONT') else '  half2 h=R(s,0,127);')
for hs,comp in ((0,'x'),(1,'y')):
    if os.environ.get('SKIP'): e('  if(WaveActiveAnyTrue(h.%s!=0)){'%comp)
    for m4 in range(4):
        e('  { uint4 W=TL[wb+%d];'%(8+hs*4+m4))
        for mm in range(4): m=4*m4+mm; e('   z%d=h.%s%s*H(W[%d])+z%d;'%(m,comp,comp,mm,m))
        e('  }')
    if os.environ.get('SKIP'): e('  }')
e(' }')
for m in range(16): e(' half2 g%d=R(z%d,-128,127);'%(m,m))
e(' [loop] for(uint s=Z;s<4u+Z;s++){')
e('  uint py=s>>1, px=s&1u;')
e('  uint ho=15392*(2*y+py+1)+16*(2*x+px+1);')
e('  uint4 rr=Scratch.Load4(8342464+ho);')
e('  uint pb=s*64u;')
for k in range(4): e('  half2 u%d=UA(rr[%d],Z), u%d=UB(rr[%d],Z);'%(2*k,k,2*k+1,k))
if U:
    for k in range(8): e('  u%d*=half2(0.5,0.5);'%k)
for k in range(8):
    pass
e('  { half2 bb;')
for o in range(8): e('   u%d+=%s;'%(o,h2(w['BP'][PERM[2*o]]/256.0,w['BP'][PERM[2*o+1]]/256.0)))
e('  }')
for m in range(16):
    if m%4==0: e('  if(Z==0u){')
    for sl in range(2):
        v='g%d.%s'%(m,'xy'[sl])
        for o4 in range(2):
            e('  { uint4 W=TP[pb+%d];'%((m*2+sl)*2+o4))
            for oo in range(4): o=4*o4+oo; e('   u%d=%s%s*H(W[%d])+u%d;'%(o,v,v[-1],oo,o))
            e('  }')
    if m%4==3: e('  }')
e('  Scratch.Store4(16684928+ho,uint4(%s));'%','.join('B4b(Bt(R(u%d,-128,127)),Bt(R(u%d,-128,127)))'%(2*k,2*k+1) for k in range(4)))
e(' }')
e('}')
open(out,'w').write('\n'.join(L)+'\n'); print(out,len(L),'lines',len(TC),len(TL),len(TP))
