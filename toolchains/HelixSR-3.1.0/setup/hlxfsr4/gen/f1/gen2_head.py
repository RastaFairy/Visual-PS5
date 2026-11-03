# kernels/f1/gen2.py as of FSR412-Lite-dev 2a115f5 (GCN / GCNQS / WG2: the Vega first layer)
# gen2.py OUT.hlsl : compact FP16 Winograd first pass (1080p layout). Weights in static const uint4 tables
# (scalar loads), loops for C0 (over input dword k) and W1->W2 (over W1 output pair o); tail unrolled.
import numpy as np, sys, os
SH=int(os.environ.get('SH','15392'))
out=sys.argv[1]
w=np.load(os.environ['W1F'])
f16=lambda x: np.float16(x)
def pk(a,b): return int(np.array([f16(a),f16(b)]).view(np.uint32)[0])
hf=lambda x: repr(float(f16(x)))
def h2(a,b): return 'half2(%s,%s)'%(hf(a),hf(b))
PERM=[c for k in range(4) for c in (4*k,4*k+2,4*k+1,4*k+3)]   # pair m=(PERM[2m],PERM[2m+1])
G=np.array([[1,0,0],[.5,.5,.5],[.5,-.5,.5],[0,0,1]])
UM=os.environ.get('MODEL')=='ultra'; S0=256.0 if UM else 128.0; S1=256.0 if UM else 512.0  # decoded: ultra C0 shift 8, W1 shift 8, tail scales /2
U=np.einsum('ea,oabi,fb->efio',G,w['W0']/S0,G)                   # [i,j,in,out]
At=[[1,1,1,0],[0,1,-1,-1]]
# --- tables (dwords)
TU=[]   # [k][e=i*4+j][q=0..3 -> ch PERM[4k+q]][o]
for k in range(4):
    for i in range(4):
        for j in range(4):
            for q in range(4):
                c=PERM[4*k+q]
                for o in range(8): TU.append(pk(U[i,j,c,2*o],U[i,j,c,2*o+1]))
turow=lambda ee,q,o4: ee*8+q*2+o4
TW=[]   # [o][W1 c=0..15][W2 m=0..7 for c=2o][W2 m for c=2o+1]
for o in range(16):
    for c in range(16): TW.append(pk(w['W1'][2*o,c]/S1,w['W1'][2*o+1,c]/S1))
    for cc in (2*o,2*o+1):
        for m in range(8): TW.append(pk(w['W2'][PERM[2*m],cc]/64.0,w['W2'][PERM[2*m+1],cc]/64.0))
sc=lambda c: (1/64.0 if c<16 else 1/128.0)*(0.5 if UM else 1.0)
TT=[]   # [pl][m][k][mi][si]
for pl in range(2):
    for m in range(8):
        c0,c1=16*pl+PERM[2*m],16*pl+PERM[2*m+1]
        for k in range(4):
            for mi in range(8):
                for si in range(2):
                    ci=PERM[2*mi+si]; TT.append(pk(w['WT'][c0,k,ci]*sc(c0),w['WT'][c1,k,ci]*sc(c1)))
def table(name,v):
    assert len(v)%4==0
    return 'static const uint4 %s[%d]={%s};'%(name,len(v)//4,','.join('uint4(%du,%du,%du,%du)'%tuple(v[i:i+4]) for i in range(0,len(v),4)))
L=[]; e=L.append
e('RWByteAddressBuffer Scratch : register(u13); ByteAddressBuffer Init : register(t21);')
e(table('TU',TU)); e(table('TW',TW)); e(table('TT',TT))
e('half2 H(uint u){ return asfloat16(uint16_t2(u&0xffff,u>>16)); }')
e('uint P(half2 v){ return uint(asuint16(v.x))|(uint(asuint16(v.y))<<16); }')
e('half2 O(half2 v, uint z){ return H(P(v)^z); }')
e('uint Pb(int16_t2 v){ return uint(uint16_t(v.x))|(uint(uint16_t(v.y))<<16); }')
e('uint B4b(int16_t2 a, int16_t2 b){ return (Pb(a)&0x00ff00ffu)|((Pb(b)&0x00ff00ffu)<<8); }')
e('half2 R(half2 v,int lo,int hi){ return clamp(round(v),half2(lo,lo),half2(hi,hi)); }')
e('int16_t2 Bt(half2 v){ return asint16(v+half2(1536,1536)); }')
e('[WaveSize(32)] [numthreads(32,1,1)] void main(uint3 g:SV_GroupID, uint tid:SV_GroupIndex){')
e(' uint qx=g.x*16+(tid&15), qy=g.y*2+(tid>>4);')
e(' uint Z=WaveReadLaneFirst(tid);')
e(' uint base=15392*(2*qy)+16*(2*qx);')
if os.environ.get('F16IN'): e(' uint fbase=50054784+30784*(2*qy)+32*(2*qx);')
e(' bool edge=(g.x==0||g.x==29||g.y==0||g.y==134);')
e(' uint vm=0;')
for a in range(4):
    for b in range(4): e(' if(uint(int(2*qy)-1+%d)<540u&&uint(int(2*qx)-1+%d)<960u) vm|=%du;'%(a,b,1<<(4*a+b)))
# OSPLIT=2: run the C0 loop twice, over output pairs 0-3 then 4-7 (64 live accumulators instead of 128; inputs are
# reloaded and re-transformed). Each accumulator sees the same operations in the same order: exact.
OSPLIT=int(os.environ.get('OSPLIT','1')); assert OSPLIT in (1,2,4)
def c0(OS,O4):
 for ee in range(16):
    for o in OS: e(' half2 M%d_%d=%s;'%(ee,o,h2(w['B0'][2*o]/S0,w['B0'][2*o+1]/S0) if ee==5 else 'half2(0,0)'))
 e(' [loop] for(uint k=Z;k<4u+Z;k++){')
 if os.environ.get('F16IN'):
     for a in range(4):
         for b in range(4): e('  uint2 x%d%d=Scratch.Load2(fbase+%d+8*k);'%(a,b,30784*a+32*b))
     e('  if(edge){')
     for a in range(4):
         for b in range(4): e('   if(((vm>>%d)&1u)==0u) x%d%d=0;'%(4*a+b,a,b))
     e('  }')
     for a in range(4):
         for b in range(4): e('  half2 dA%d%d=H(x%d%d.x), dB%d%d=H(x%d%d.y);'%(a,b,a,b,a,b,a,b))
 else:
     for a in range(4):
         for b in range(4): e('  uint x%d%d=Scratch.Load(base+%d+4*k);'%(a,b,SH*a+16*b))
     e('  if(edge){')
     for a in range(4):
         for b in range(4): e('   if(((vm>>%d)&1u)==0u) x%d%d=0;'%(4*a+b,a,b))
     e('  }')
     for a in range(4):
         for b in range(4):
             e('  uint y%d%d=x%d%d^0x80808080u;'%(a,b,a,b))
             e('  half2 dA%d%d=O(H((y%d%d&0x00ff00ffu)|0x64006400u)-half2(1152,1152),Z);'%(a,b,a,b))
             e('  half2 dB%d%d=O(H(((y%d%d>>8)&0x00ff00ffu)|0x64006400u)-half2(1152,1152),Z);'%(a,b,a,b))
 for P_ in 'AB':
     for b in range(4):
         e('  half2 t%s0%d=d%s0%d-d%s2%d, t%s1%d=d%s1%d+d%s2%d, t%s2%d=d%s2%d-d%s1%d, t%s3%d=d%s1%d-d%s3%d;'%((P_,b,P_,b,P_,b)*4))
     for i in range(4):
         e('  half2 v%s%d0=t%s%d0-t%s%d2, v%s%d1=t%s%d1+t%s%d2, v%s%d2=t%s%d2-t%s%d1, v%s%d3=t%s%d1-t%s%d3;'%((P_,i,P_,i,P_,i)*4))
 e('  uint tb=k*128;')
 for i in range(4):
     for j in range(4):
         ee=4*i+j
         for q in range(4):
             src='v%s%d%d.%s'%('AABB'[q],i,j,'xyxy'[q])
             for o4 in O4:
                 e('  { uint4 W=TU[tb+%d];'%turow(ee,q,o4))
                 for oo in range(4):
                     o=4*o4+oo
                     if o not in OS: continue
                     e('   M%d_%d=%s%s*H(W[%d])+M%d_%d;'%(ee,o,src,src[-1],oo,ee,o))
                 e('  }')
 e(' }')

 # output transform: row-wise T then At
 for o in OS:
     for i in range(4):
         e(' half2 T%d0_%d=M%d_%d+M%d_%d+M%d_%d, T%d1_%d=M%d_%d-M%d_%d-M%d_%d;'%(i,o,4*i,o,4*i+1,o,4*i+2,o,i,o,4*i+1,o,4*i+2,o,4*i+3,o))
     for q in range(2):
         if os.environ.get('CONT'):
             e(' half2 q0%d_%d=T0%d_%d+T1%d_%d+T2%d_%d;'%(q,o,q,o,q,o,q,o)); e(' half2 q1%d_%d=T1%d_%d-T2%d_%d-T3%d_%d;'%(q,o,q,o,q,o,q,o))
         else:
             e(' half2 q0%d_%d=R(T0%d_%d+T1%d_%d+T2%d_%d,-128,127);'%(q,o,q,o,q,o,q,o))
             e(' half2 q1%d_%d=R(T1%d_%d-T2%d_%d-T3%d_%d,-128,127);'%(q,o,q,o,q,o,q,o))
def c0_gcn(OS,O4):   # GCN=1: plane A unpacked, transformed and accumulated before plane B (half the transform values
 # live on GCN wave64); every M still takes its updates in the order q = 0, 1, 2, 3: same fp16 sums
 for ee in range(16):
    for o in OS: e(' half2 M%d_%d=%s;'%(ee,o,h2(w['B0'][2*o]/S0,w['B0'][2*o+1]/S0) if ee==5 else 'half2(0,0)'))
 e(' [loop] for(uint k=Z;k<4u+Z;k++){')
 if os.environ.get('F16IN'):
     for a in range(4):
         for b in range(4): e('  uint2 x%d%d=Scratch.Load2(fbase+%d+8*k);'%(a,b,30784*a+32*b))
     e('  if(edge){')
     for a in range(4):
         for b in range(4): e('   if(((vm>>%d)&1u)==0u) x%d%d=0;'%(4*a+b,a,b))
     e('  }')
     for a in range(4):
         for b in range(4): e('  half2 dA%d%d=H(x%d%d.x), dB%d%d=H(x%d%d.y);'%(a,b,a,b,a,b,a,b))
 else:
     for a in range(4):
         for b in range(4): e('  uint x%d%d=Scratch.Load(base+%d+4*k);'%(a,b,SH*a+16*b))
     e('  if(edge){')
     for a in range(4):
         for b in range(4): e('   if(((vm>>%d)&1u)==0u) x%d%d=0;'%(4*a+b,a,b))
     e('  }')
     for a in range(4):
         for b in range(4): e('  uint y%d%d=x%d%d^0x80808080u;'%(a,b,a,b))
 e('  uint tb=k*128;')
 for P_ in 'AB':
     for a in range(4):
         for b in range(4):
             if P_=='A': e('  half2 dA%d%d=O(H((y%d%d&0x00ff00ffu)|0x64006400u)-half2(1152,1152),Z);'%(a,b,a,b))
             else: e('  half2 dB%d%d=O(H(((y%d%d>>8)&0x00ff00ffu)|0x64006400u)-half2(1152,1152),Z);'%(a,b,a,b))
     for b in range(4):
         e('  half2 t%s0%d=d%s0%d-d%s2%d, t%s1%d=d%s1%d+d%s2%d, t%s2%d=d%s2%d-d%s1%d, t%s3%d=d%s1%d-d%s3%d;'%((P_,b,P_,b,P_,b)*4))
     for i in range(4):
         e('  half2 v%s%d0=t%s%d0-t%s%d2, v%s%d1=t%s%d1+t%s%d2, v%s%d2=t%s%d2-t%s%d1, v%s%d3=t%s%d1-t%s%d3;'%((P_,i,P_,i,P_,i)*4))
     for i in range(4):
         for j in range(4):
             ee=4*i+j
             for q in range(4):
                 if 'AABB'[q]!=P_: continue
                 src='v%s%d%d.%s'%('AABB'[q],i,j,'xyxy'[q])
                 for o4 in O4:
                     e('  { uint4 W=TU[tb+%d];'%turow(ee,q,o4))
                     for oo in range(4):
                         o=4*o4+oo
                         if o not in OS: continue
                         e('   M%d_%d=%s%s*H(W[%d])+M%d_%d;'%(ee,o,src,src[-1],oo,ee,o))
                     e('  }')
 e(' }')

 # output transform: row-wise T then At
 for o in OS:
     for i in range(4):
         e(' half2 T%d0_%d=M%d_%d+M%d_%d+M%d_%d, T%d1_%d=M%d_%d-M%d_%d-M%d_%d;'%(i,o,4*i,o,4*i+1,o,4*i+2,o,i,o,4*i+1,o,4*i+2,o,4*i+3,o))
     for q in range(2):
         if os.environ.get('CONT'):
             e(' half2 q0%d_%d=T0%d_%d+T1%d_%d+T2%d_%d;'%(q,o,q,o,q,o,q,o)); e(' half2 q1%d_%d=T1%d_%d-T2%d_%d-T3%d_%d;'%(q,o,q,o,q,o,q,o))
         else:
             e(' half2 q0%d_%d=R(T0%d_%d+T1%d_%d+T2%d_%d,-128,127);'%(q,o,q,o,q,o,q,o))
             e(' half2 q1%d_%d=R(T1%d_%d-T2%d_%d-T3%d_%d,-128,127);'%(q,o,q,o,q,o,q,o))
             if GCNQS: e(' QS[tid0*32u+%du]=P(q0%d_%d); QS[tid0*32u+%du]=P(q1%d_%d);'%((2*0+q)*8+o,q,o,(2*1+q)*8+o,q,o))   # site (p,q) = q{p}{q}: index (2p+q)*8+o
GCN=os.environ.get('GCN')=='1'; assert not GCN or not os.environ.get('F16IN')
# GCNQS=1 (with GCN=1, 64-thread groups): C0 results staged in LDS (each thread its own 32 words, 8 KB) instead of
# registers through the later C0 splits and the W1/W2 loop; the same bits come back
GCNQS=os.environ.get('GCNQS','0'); assert GCNQS in ('0','1','2') and (GCNQS=='0' or (GCN and os.environ.get('WG2')))
# GCNQS=2: staged only while the later C0 splits run, read back once before the W1/W2 loop (=1 reads LDS in the loop: slow)
GCNQS={'0':0,'1':1,'2':2}[GCNQS]
for oh in range(OSPLIT):
    OSr=range(8//OSPLIT*oh,8//OSPLIT*(oh+1)); (c0_gcn if GCN else c0)(OSr, sorted({o//4 for o in OSr}))
if GCNQS==2:
    for p_ in range(2):
        for q_ in range(2): e(' ' + ' '.join('q%d%d_%d=H(QS[tid0*32u+%du]);'%(p_,q_,o,(2*p_+q_)*8+o) for o in range(8)))
SITES=['00','01','10','11']
# W2 init: centre/2 + bias, centre reloaded
for s in SITES:
    p,q=int(s[0]),int(s[1])
    if os.environ.get('F16IN'):
        e(' uint4 cf0%s=Scratch.Load4(fbase+%d), cf1%s=Scratch.Load4(fbase+%d);'%(s,30784*(1+p)+32*(1+q),s,30784*(1+p)+32*(1+q)+16))
        for m in range(8):
            e(' half2 z%s_%d=H(cf%d%s[%d])*half2(0.5,0.5)+%s;'%(s,m,m//4,s,m%4,h2(w['B2'][PERM[2*m]]/64.0,w['B2'][PERM[2*m+1]]/64.0)))
        continue
    e(' uint4 c%s=Scratch.Load4(base+%d)^0x80808080u;'%(s,SH*(1+p)+16*(1+q)))
    for k in range(4):
        for t_,expr in ((0,'(c%s[%d]&0x00ff00ffu)'%(s,k)),(1,'((c%s[%d]>>8)&0x00ff00ffu)'%(s,k))):
            m=2*k+t_
            e(' half2 z%s_%d=O(H(%s|0x64006400u)-half2(1152,1152),Z)*half2(0.5,0.5)+%s;'%(s,m,expr,h2(w['B2'][PERM[2*m]]/64.0,w['B2'][PERM[2*m+1]]/64.0)))
# ZPHI32=1: carry the W2 accumulators across the o loop as packed uint. SM <= 6.8 DXIL carries each half of a half2 as
# its own loop value, and AMD's Windows compiler repacks them at the top and splits them at the bottom of every trip.
ZPHI32=bool(os.environ.get('ZPHI32'))
if ZPHI32:
    for s in SITES:
        for m in range(8): e(' uint zu%s_%d=P(z%s_%d);'%(s,m,s,m))
e(' [loop] for(uint o=Z;o<16u+Z;o++){')
e('  uint wb=o*8;')
if ZPHI32:
    for s in SITES:
        for m in range(8): e('  half2 z%s_%d=H(zu%s_%d);'%(s,m,s,m))
e('  half2 B1=H(TW[wb][0]);') if False else None
for s in SITES: e('  half2 a%s=half2(0,0);'%s)
for c4 in range(4):
    e('  { uint4 W=TW[wb+%d];'%c4)
    for cc in range(4):
        c=4*c4+cc; comp='xy'[c&1]
        for s in SITES: e(('   a%s=H(QS[tid0*32u+%du]).%s%s*H(W[%d])+a%s;'%(s,(2*int(s[0])+int(s[1]))*8+(c>>1),comp,comp,cc,s)) if GCNQS==1 else '   a%s=q%s_%d.%s%s*H(W[%d])+a%s;'%(s,s,c>>1,comp,comp,cc,s))
    e('  }')
e('  half2 b1=H(TB1[o]);')
for s in SITES: e(('  half2 h%s=max(a%s+b1,half2(0,0));' if os.environ.get('CONT') else '  half2 h%s=R(a%s+b1,0,127);')%(s,s))
for half_,comp in ((0,'x'),(1,'y')):
    if os.environ.get('SKIP'): e('  if(WaveActiveAnyTrue(h00.%s!=0||h01.%s!=0||h10.%s!=0||h11.%s!=0)){'%((comp,)*4))
    for m4 in range(2):
        e('  { uint4 W=TW[wb+%d];'%(4+half_*2+m4))
        for mm in range(4):
            m=4*m4+mm
            for s in SITES: e('   z%s_%d=h%s.%s%s*H(W[%d])+z%s_%d;'%(s,m,s,comp,comp,mm,s,m))
        e('  }')
    if os.environ.get('SKIP'): e('  }')
if ZPHI32:
    for s in SITES:
        for m in range(8): e('  zu%s_%d=P(z%s_%d);'%(s,m,s,m))
e(' }')
if ZPHI32:
    for s in SITES:
        for m in range(8): e(' z%s_%d=H(zu%s_%d);'%(s,m,s,m))
for s in SITES:
    p,q=int(s[0]),int(s[1])
    for m in range(8): e(' half2 r%s_%d=R(z%s_%d,-128,127); int16_t2 rb%s_%d=Bt(r%s_%d);'%(s,m,s,m,s,m,s,m))
    e(' Scratch.Store4(8342464+15392*(2*qy+%d+1)+16*(2*qx+%d+1),uint4(%s));'%(p,q,','.join('B4b(rb%s_%d,rb%s_%d)'%(s,2*k,s,2*k+1) for k in range(4))))
# tail unrolled: k order px+2py -> site (py,px)
for pl in range(2):
    for m in range(8):
        c0,c1=16*pl+PERM[2*m],16*pl+PERM[2*m+1]
        e(' half2 u%d_%d=%s;'%(pl,m,h2(w['BT'][c0]*sc(c0),w['BT'][c1]*sc(c1))))
        for k in range(4):
            s='%d%d'%(k>>1,k&1)
            for mi4 in range(4):
                idx=((pl*8+m)*4+k)*4+mi4
                e(' { uint4 W=TT[%d];'%idx)
                for t in range(4):
                    mi=2*mi4+(t>>1); si=t&1; comp='xy'[si]
                    e('  u%d_%d=r%s_%d.%s%s*H(W[%d])+u%d_%d;'%(pl,m,s,mi,comp,comp,t,pl,m))
                e(' }')
    if os.environ.get('F16IO'):
        vals=['P(R(u%d_%d,-128,127))'%(pl,m) for m in range(8)]
        e(' { uint qa=%d+15424*(qy+1)+32*(qx+1); Scratch.Store4(qa,uint4(%s)); Scratch.Store4(qa+16,uint4(%s)); }'%(25027392+4195328*pl,','.join(vals[:4]),','.join(vals[4:])))
    else:
        e(' Scratch.Store4(%d+7712*(qy+1)+16*(qx+1),uint4(%s));'%(16684928+2097664*pl,','.join('B4b(Bt(R(u%d_%d,-128,127)),Bt(R(u%d_%d,-128,127)))'%(pl,2*k,pl,2*k+1) for k in range(4))))
e('}')
TB1=[pk(w['B1'][2*o]/S1,w['B1'][2*o+1]/S1) for o in range(16)]
L.insert(4,'static const uint TB1[16]={%s};'%','.join('%du'%x for x in TB1))
L=[l for l in L if l is not None]
if GCNQS: L.insert(5,'groupshared uint QS[64*32];')
if os.environ.get('WG2'):
    # WG2=1: 64-thread groups (runtime pass kind first2: groups (out_w/64, out_h/16)), two old 32-thread groups stacked
    # in y, for wave64-only GPUs (Vega, Radeon VII), where a 32-thread group leaves half of every wave idle. No
    # [WaveSize]; per-pixel math unchanged. The tensor constants (b0) give the old group count for the last row.
    hd='[WaveSize(32)] [numthreads(32,1,1)] void main(uint3 g:SV_GroupID, uint tid:SV_GroupIndex){'
    i=L.index(hd)
    L[i:i+1]=['cbuffer T : register(b0) { uint4 t[9]; };',
              '[numthreads(64,1,1)] void main(uint3 g0:SV_GroupID, uint tid0:SV_GroupIndex){',
              ' uint tid=tid0&31u; uint3 g=uint3(g0.x,g0.y*2u+(tid0>>5),0u);',
              ' if(g.y>=(2u*t[0].y+7u)/8u) return;  // past the old dispatch: groups (out_w/64, out_h/8)']
open(out,'w').write('\n'.join(L)+'\n'); print(out,len(L),'lines')
