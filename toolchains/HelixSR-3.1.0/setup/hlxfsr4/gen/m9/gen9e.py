# gen9e.py OUT.hlsl : own post v4 (lane redistribution after C0, per-strip colour tile, 8x4 tile stores).
# from gen9d: own post v3. Thread = 2x2 H-sites. C0 = FP16 Winograd F(2x2,3x3) (from f1/gen2.py),
# W1/W2/head per site with scalar weight tables, colour from a per-wave log-colour tile in LDS (no group barrier),
# exactly 9 taps per subpixel. Layout via env SH/WH/HH/HP (default 1080p).
import numpy as np, sys, os
out=sys.argv[1]
DIAG=os.environ.get('DIAG','')
SH=int(os.environ.get('SH','15392')); WH=int(os.environ.get('WH','960')); HH=int(os.environ.get('HH','540')); HP=int(os.environ.get('HP','16684928'))
TCW,TCH=35,8
w=np.load(os.environ['W9'])
# modes (decoded from AMD's post variants): ultra = C0 shift 7, L2 sum /128 (residual weight unchanged);
# AE = exposure from t17, no exposure write-back; NL = colour used linearly, output without exp conversion
H32=os.environ.get('H32', '0')=='1'; UM=os.environ.get('MODEL')=='ultra'; AE=os.environ.get('AE')=='1'; NL=os.environ.get('NL')=='1'; CURVE=int(os.environ.get('CURVE','0')) if NL else 0; LINC=NL and not CURVE; S0=128.0 if UM else 256.0; S2=128.0 if UM else 64.0
f16=lambda x: np.float16(x)
def pk(a,b): return int(np.array([f16(a),f16(b)]).view(np.uint32)[0])
hf=lambda x: repr(float(f16(x)))
def h2(a,b): return 'half2(%s,%s)'%(hf(a),hf(b))
PERM=[c for k in range(4) for c in (4*k,4*k+2,4*k+1,4*k+3)]
OCR_OC = '   float3 b3=asfloat(uint3(vv[0],vv[1],vv[2])); float3 o3=b3;' + ('' if LINC else ({0: ' if(rcas_enabled==0u) %s=max((exp2(%s*12.288703918457031)-1.0)*0.006666666828095913,0.0)/e;', 1: ' if(rcas_enabled==0u) %s=senc3(max((exp2(%s*12.288703918457031)-1.0)*0.006666666828095913,0.0));', 2: ' if(rcas_enabled==0u) %s=penc3(max((exp2(%s*12.288703918457031)-1.0)*0.006666666828095913,0.0));'}[CURVE]) % ('o3', 'b3')) + ' o3=min(max(o3,0.0),64000.0);'  # (the OCR output colour line, shared with ROW16)
G=np.array([[1,0,0],[.5,.5,.5],[.5,-.5,.5],[0,0,1]])
W0=w['W0'].reshape(16,3,3,16)/S0
U=np.einsum('ea,oabi,fb->efio',G,W0,G)
TU=[]
for k in range(4):
    for i in range(4):
        for j in range(4):
            for q in range(4):
                c=PERM[4*k+q]
                for o in range(8): TU.append(pk(U[i,j,c,2*o],U[i,j,c,2*o+1]))
TW=[]
for o in range(16):
    for j in range(16): TW.append(pk(w['W1'][2*o,j]/256.0,w['W1'][2*o+1,j]/256.0))
    for cc in (2*o,2*o+1):
        for m in range(8): TW.append(pk(w['W2'][PERM[2*m],cc]/S2,w['W2'][PERM[2*m+1],cc]/S2))
TB1=[pk(w['B1'][2*o]/256.0,w['B1'][2*o+1]/256.0) for o in range(16)]
TH=[]
for n in range(16):
    sp,j=divmod(n,4)
    for q in range(16): TH.append(pk(w['WH'][sp,2*j,PERM[q]]/1024.0,w['WH'][sp,2*j+1,PERM[q]]/1024.0))
def table(name,v):
    while len(v)%4: v=v+[0]
    return 'static const uint4 %s[%d]={%s};'%(name,len(v)//4,','.join('uint4(%du,%du,%du,%du)'%tuple(v[i:i+4]) for i in range(0,len(v),4)))
L=[]; e=L.append
e('cbuffer MLSR_Optimized_Constants : register(b1) { float2 inv_size; float2 scale; float2 inv_scale; float2 jitter; float2 mv_scale; float2 tex_size; float2 max_renderSize; float2 fMVJC; uint width; uint height; uint reset; uint width_lr; uint height_lr; float preExposure; float previous_preExposure; uint rcas_enabled; float rcas_sharpness; float pad; };')
e('float3 sdec3(float3 c){ return float3(c.x<0.040449999272823334?c.x*0.07739938050508499:exp2(log2((c.x+0.054999999701976776)*0.9478673338890076)*2.4000000953674316), c.y<0.040449999272823334?c.y*0.07739938050508499:exp2(log2((c.y+0.054999999701976776)*0.9478673338890076)*2.4000000953674316), c.z<0.040449999272823334?c.z*0.07739938050508499:exp2(log2((c.z+0.054999999701976776)*0.9478673338890076)*2.4000000953674316)); }')
e('float3 senc3(float3 l){ return float3(l.x<0.0031308000907301903?l.x*12.920000076293945:exp2(log2(l.x)*0.4166666567325592)*1.0549999475479126+(-0.054999999701976776), l.y<0.0031308000907301903?l.y*12.920000076293945:exp2(log2(l.y)*0.4166666567325592)*1.0549999475479126+(-0.054999999701976776), l.z<0.0031308000907301903?l.z*12.920000076293945:exp2(log2(l.z)*0.4166666567325592)*1.0549999475479126+(-0.054999999701976776)); }')
e('float3 pq1(float3 c){ return exp2(log2(min(max(c,0.0),1.0))*0.012683313339948654); }')
e('float3 pq2(float3 t){ return max(exp2(log2(max(t+(-0.8359375),0.0)/(18.8515625-(t*18.6875)))*6.277394771575928)*33.33333206176758,0.0); }')
e('float3 penc3(float3 l){ float3 y=exp2(log2(max(l*0.029999999329447746,1.000000013351432e-10))*0.1593017578125); return max(exp2(log2(((y*18.8515625)+0.8359375)/((y*18.6875)+1.0))*78.84375),0.0); }')
e('Texture2D<float3> r_input_color : register(t3); Texture2D<float> r_input_exposure : register(%s);' % ('t17' if AE else 't6') + ' Texture2D<half3> r_reprojected_color : register(t9);')
e('RWByteAddressBuffer Scratch : register(u13); RWTexture2D<float3> rw_history_color : register(u1); RWTexture2D<float3> rw_mlsr_output_color : register(u2); RWTexture2D<half4> rw_recurrent_0 : register(u6); RWTexture2D<float> rw_auto_exposure_texture : register(u9);')
e(table('TU',TU)); e(table('TW',TW)); e(table('TH',TH))
e('static const uint TB1[16]={%s};'%','.join('%du'%x for x in TB1))
if os.environ.get('GCNHEAD')=='1': e('static const uint TBH[16]={%s};'%','.join('%du'%pk(w['BH'][n//4,2*(n%4)]/1024.0,w['BH'][n//4,2*(n%4)+1]/1024.0) for n in range(16)))
if os.environ.get('STG'): e('groupshared uint SHM[2][1024];')
elif os.environ.get('CT3'): e('groupshared float%s CT3[2][%d];'%('4' if os.environ.get('CT3')=='4' else '3', TCW*TCH))   # CT3: a texel's 3 colours together (one LDS read per tap; =4: padded to 16 bytes)
else: e('groupshared float CT[2][3][%d];'%(TCW*TCH))
e('half2 H(uint u){ return asfloat16(uint16_t2(u&0xffff,u>>16)); }')
e('uint P(half2 v){ return uint(asuint16(v.x))|(uint(asuint16(v.y))<<16); }')
e('half2 O(half2 v, uint z){ return H(P(v)^z); }')
e('half2 R(half2 v,int lo,int hi){ return clamp(round(v),half2(lo,lo),half2(hi,hi)); }')
e('half2 UA(uint x, uint z){ return O(H(((x^0x80808080u)&0x00ff00ffu)|0x64006400u)-half2(1152,1152),z); }')
e('int16_t2 Bt(half2 v){ return asint16(v+half2(1536,1536)); }')
e('uint Pb(int16_t2 v){ return uint(uint16_t(v.x))|(uint(uint16_t(v.y))<<16); }')
e('uint B4b(int16_t2 a, int16_t2 b){ return (Pb(a)&0x00ff00ffu)|((Pb(b)&0x00ff00ffu)<<8); }')
e('half2 UB(uint x, uint z){ return O(H((((x^0x80808080u)>>8)&0x00ff00ffu)|0x64006400u)-half2(1152,1152),z); }')
e('[WaveSize(32)] [numthreads(64,1,1)] void main(uint3 g:SV_GroupID, uint tid:SV_GroupIndex){')
e(' uint wv=tid>>5, ln=tid&31u; uint Z=WaveReadLaneFirst(ln);')
e(' uint qx=g.x*8+(tid&7u), qy=g.y*8+(tid>>3);')
e(' float ex=r_input_exposure.Load(int3(0,0,0));' + ('' if AE else ' ex=(ex==0.0)?1.0:ex;'))
if not AE: e(' if(g.x==0&&g.y==0&&tid==0) rw_auto_exposure_texture[uint2(1,0)]=ex;')
e(' if(g.y*16+8*wv>=%du) return;'%HH)
# ---- per-wave log-colour tile
e(' float e=ex/preExposure; float e150=e*150.0;')
e(' float ox=inv_scale.x*0.5-0.5+jitter.x, oy=inv_scale.y*0.5-0.5+jitter.y;')
e(' uint DX0=g.x*32;')
# ---- C0 Winograd over 4x4 input sites
e(' uint base=%d+%d*(2*qy)+16*(2*qx);'%(HP,SH))
e(' bool edge=(qx==0||qy==0||2*qx+2>=%du||2*qy+2>=%du);'%(WH,HH))
e(' uint vm=0;')
for a in range(4):
    for b in range(4): e(' if(uint(int(2*qy)-1+%d)<%du&&uint(int(2*qx)-1+%d)<%du) vm|=%du;'%(a,HH,b,WH,1<<(4*a+b)))
OSPLIT=int(os.environ.get('OSPLIT','2'))
# GCN builds (Vega under RADV; need W64SAFE=1 W64LDS=1, see tools/make_gcn_fp16.py). Same arithmetic as without them.
GCNC0=os.environ.get('GCNC0')=='1'       # C0: plane A unpacked, transformed and accumulated before plane B (same M update order)
GCNHEAD=os.environ.get('GCNHEAD')=='1'   # head + colour per subpixel in a loop (head weights stay scalar loads)
GCNST=os.environ.get('GCNST')=='1'       # each lane stores its own subpixels (no V staging / lane shuffle); needs GCNHEAD
assert not (GCNC0 or GCNHEAD) or (os.environ.get('W64SAFE') and os.environ.get('W64LDS') and not os.environ.get('CPK') and not os.environ.get('STG'))
assert not GCNST or GCNHEAD
for ee in []: pass
CPK=os.environ.get('CPK')
if CPK:
    for k_ in range(4):
        for q in range(2): e(' uint cp0%d_%d, cp1%d_%d;'%(q,k_,q,k_))
else:
  for o in range(8):
    for q in range(2): e(' half2 c0%d_%d, c1%d_%d;'%(q,o,q,o))
for hh in range(OSPLIT):
    OS=[o for o in range(8) if o*OSPLIT//8==hh]
    e(' {')
    for ee in range(16):
        for o in OS: e('  half2 M%d_%d=%s;'%(ee,o,h2(w['B0'][2*o]/S0,w['B0'][2*o+1]/S0) if ee==5 else 'half2(0,0)'))
    e('  [loop] for(uint k=Z;k<%s+Z;k++){'%('0u' if 'nonet' in DIAG else '4u'))
    for a_ in range(4):
        for b_ in range(4): e('   uint x%d%d=Scratch.Load(base+%d+4*k);'%(a_,b_,SH*a_+16*b_))
    e('   if(edge){')
    for a_ in range(4):
        for b_ in range(4): e('    if(((vm>>%d)&1u)==0u) x%d%d=0;'%(4*a_+b_,a_,b_))
    e('   }')
    if GCNC0:
     e('   uint tb=k*128;')
     for P_ in 'AB':
         for a_ in range(4):
             for b_ in range(4): e('   half2 d%s%d%d=U%s(x%d%d,Z);'%(P_,a_,b_,P_,a_,b_))
         for b_ in range(4):
             e('   half2 t%s0%d=d%s0%d-d%s2%d, t%s1%d=d%s1%d+d%s2%d, t%s2%d=d%s2%d-d%s1%d, t%s3%d=d%s1%d-d%s3%d;'%((P_,b_,P_,b_,P_,b_)*4))
         for i in range(4):
             e('   half2 v%s%d0=t%s%d0-t%s%d2, v%s%d1=t%s%d1+t%s%d2, v%s%d2=t%s%d2-t%s%d1, v%s%d3=t%s%d1-t%s%d3;'%((P_,i,P_,i,P_,i)*4))
         for i in range(4):
             for j in range(4):
                 ee=4*i+j
                 for q in range(4):
                     if 'AABB'[q]!=P_: continue
                     src='v%s%d%d.%s'%('AABB'[q],i,j,'xyxy'[q])
                     for o4 in range(2):
                         oo_=[o for o in range(4*o4,4*o4+4) if o in OS]
                         if not oo_: continue
                         e('   { uint4 W=TU[tb+%d];'%(ee*8+q*2+o4))
                         for o in oo_: e('    M%d_%d=%s%s*H(W[%d])+M%d_%d;'%(ee,o,src,src[-1],o-4*o4,ee,o))
                         e('   }')
    else:
     for a_ in range(4):
         for b_ in range(4): e('   half2 dA%d%d=UA(x%d%d,Z), dB%d%d=UB(x%d%d,Z);'%(a_,b_,a_,b_,a_,b_,a_,b_))
     for P_ in 'AB':
         for b_ in range(4):
             e('   half2 t%s0%d=d%s0%d-d%s2%d, t%s1%d=d%s1%d+d%s2%d, t%s2%d=d%s2%d-d%s1%d, t%s3%d=d%s1%d-d%s3%d;'%((P_,b_,P_,b_,P_,b_)*4))
         for i in range(4):
             e('   half2 v%s%d0=t%s%d0-t%s%d2, v%s%d1=t%s%d1+t%s%d2, v%s%d2=t%s%d2-t%s%d1, v%s%d3=t%s%d1-t%s%d3;'%((P_,i,P_,i,P_,i)*4))
     e('   uint tb=k*128;')
     for i in range(4):
         for j in range(4):
             ee=4*i+j
             for q in range(4):
                 src='v%s%d%d.%s'%('AABB'[q],i,j,'xyxy'[q])
                 for o4 in range(2):
                     oo_=[o for o in range(4*o4,4*o4+4) if o in OS]
                     if not oo_: continue
                     e('   { uint4 W=TU[tb+%d];'%(ee*8+q*2+o4))
                     for o in oo_: e('    M%d_%d=%s%s*H(W[%d])+M%d_%d;'%(ee,o,src,src[-1],o-4*o4,ee,o))
                     e('   }')
    e('  }')
    for o in OS:
        for i in range(4):
            e('  half2 T%d0_%d=M%d_%d+M%d_%d+M%d_%d, T%d1_%d=M%d_%d-M%d_%d-M%d_%d;'%(i,o,4*i,o,4*i+1,o,4*i+2,o,i,o,4*i+1,o,4*i+2,o,4*i+3,o))
        for q in range(2):
            pre='half2 ' if CPK else ''
            e('  %sc0%d_%d=R(T0%d_%d+T1%d_%d+T2%d_%d,-128,127);'%(pre,q,o,q,o,q,o,q,o))
            e('  %sc1%d_%d=R(T1%d_%d-T2%d_%d-T3%d_%d,-128,127);'%(pre,q,o,q,o,q,o,q,o))
    if CPK:
        for k_ in sorted({o//2 for o in OS}):
            for p_ in range(2):
                for q in range(2): e('  cp%d%d_%d=B4b(Bt(c%d%d_%d),Bt(c%d%d_%d));'%(p_,q,k_,p_,q,2*k_,p_,q,2*k_+1))
    e(' }')
e(' float kk=-1.4426950408889634;')
# ---- per site
e(' uint L=ln, lsx=L&15u, lsy=L>>4;')
e(' [loop] for(uint st=Z;st<4u+Z;st++){')
e('  uint SL=(lsx>>1)+8u*st; bool qo=(lsx&1u)!=0u, po=lsy!=0u;')
if CPK:
  for k_ in range(4):
    e('  uint csp_%d; { uint a0=WaveReadLaneAt(cp00_%d,SL), a1=WaveReadLaneAt(cp01_%d,SL), a2=WaveReadLaneAt(cp10_%d,SL), a3=WaveReadLaneAt(cp11_%d,SL); csp_%d=po?(qo?a3:a2):(qo?a1:a0); }'%(k_,k_,k_,k_,k_,k_))
    e('  half2 cs_%d=UA(csp_%d,Z), cs_%d=UB(csp_%d,Z);'%(2*k_,k_,2*k_+1,k_))
else:
  for o in range(8):
    e('  half2 cs_%d; { uint a0=WaveReadLaneAt(P(c00_%d),SL), a1=WaveReadLaneAt(P(c01_%d),SL), a2=WaveReadLaneAt(P(c10_%d),SL), a3=WaveReadLaneAt(P(c11_%d),SL); cs_%d=H(po?(qo?a3:a2):(qo?a1:a0)); }'%(o,o,o,o,o,o))
e('  uint X=g.x*16+lsx, Y=g.y*16+8*wv+2*st+lsy; uint DYi=2*(g.y*16+8*wv+2*st);')
# strip tile
VY=(lambda d: '((jitter.y+(-0.5))+inv_scale.y*(float(%s)+0.5))' % d) if NL else (lambda d: '(oy+inv_scale.y*float(%s))' % d)
e('  int iuo=int(round(ox+inv_scale.x*float(DX0)))-1, ivo=int(round(%s))-1;' % VY('DYi'))
e('  int tcols=min(int(round(ox+inv_scale.x*float(DX0+31)))+2-iuo,%d), trows=min(int(round(%s))+2-ivo,%d);'%(TCW,VY('DYi+3'),TCH))
e('  [loop] for(int tr=0;tr<trows;tr++){ int j=clamp(ivo+tr,0,int(height_lr)-1);')
e('   [unroll] for(int cc=0;cc<%d;cc+=32){ int c=cc+int(L); if(c<tcols){ int i=clamp(iuo+c,0,int(width_lr)-1);'%TCW)
e(('    float3 col=r_input_color.Load(int3(i,j,0)); float3 lc=%s;' % ('col' if LINC else {0: 'max(log2(1.0+col*e150)*0.08137547969818115,0.0)', 1: 'max(log2(1.0+sdec3(col)*150.0)*0.08137547969818115,0.0)', 2: 'max(log2(1.0+pq2(pq1(col))*150.0)*0.08137547969818115,0.0)'}[CURVE])) if 'notile' not in DIAG else '    float3 lc=float3(i,j,0)*0.01;')
e(('    uint ti=uint(tr*%d+c); '+("SHM[wv][ti]=asuint(lc.x); SHM[wv][280+ti]=asuint(lc.y); SHM[wv][560+ti]=asuint(lc.z);" if os.environ.get('STG') else (("CT3[wv][ti]=float4(lc,0.0);" if os.environ.get('CT3')=='4' else "CT3[wv][ti]=lc;") if os.environ.get('CT3') else "CT[wv][0][ti]=lc.x; CT[wv][1][ti]=lc.y; CT[wv][2][ti]=lc.z;"))+' } } }')%TCW)
e('  uint4 rc=Scratch.Load4(%d+%d*(Y+1)+16*(X+1));'%(HP,SH))
for k in range(4): e('  half2 xA%d=UA(rc[%d],Z), xB%d=UB(rc[%d],Z);'%(k,k,k,k))
for m in range(8):
    src='x%s%d'%('AB'[m%2],m//2)
    e('  half2 z%d=%s*half2(0.5,0.5)+%s;'%(m,src,h2(w['B2'][PERM[2*m]]/S2,w['B2'][PERM[2*m+1]]/S2)))
MU=int(os.environ.get('MU','1')); PF=os.environ.get('PF')
if PF:
    e('  uint4 Wc0=TW[0],Wc1=TW[1],Wc2=TW[2],Wc3=TW[3],Wc4=TW[4],Wc5=TW[5],Wc6=TW[6],Wc7=TW[7]; uint Bc=TB1[0];')
    e('  [loop] for(uint o=Z;o<%s+Z;o++){'%('0u' if 'nonet' in DIAG else '16u'))
    e('   uint on=min(o+1u,15u)*8u; uint4 Wn0=TW[on],Wn1=TW[on+1],Wn2=TW[on+2],Wn3=TW[on+3],Wn4=TW[on+4],Wn5=TW[on+5],Wn6=TW[on+6],Wn7=TW[on+7]; uint Bn=TB1[min(o+1u,15u)];')
    e('   half2 sacc=H(Bc);')
    for j4 in range(4):
        for jj in range(4):
            j=4*j4+jj; v='cs_%d.%s'%(j>>1,'xy'[j&1]); e('   sacc=%s%s*H(Wc%d[%d])+sacc;'%(v,v[-1],j4,jj))
    e('   half2 hh=R(sacc,0,127);')
    for hs,comp in ((0,'x'),(1,'y')):
        for m4 in range(2):
            for mm in range(4): m=4*m4+mm; e('   z%d=hh.%s%s*H(Wc%d[%d])+z%d;'%(m,comp,comp,4+hs*2+m4,mm,m))
    e('   Wc0=Wn0;Wc1=Wn1;Wc2=Wn2;Wc3=Wn3;Wc4=Wn4;Wc5=Wn5;Wc6=Wn6;Wc7=Wn7;Bc=Bn;')
else:
 e('  [loop] for(uint o0=Z;o0<%s+Z;o0+=%du){'%('0u' if 'nonet' in DIAG else '16u',MU))
 for uu in range(MU):
    e('  { uint o=o0+%du;'%uu)
    e('   uint wb=o*8u; half2 sacc=H(TB1[o]);')
    for j4 in range(4):
        e('   { uint4 W=TW[wb+%d];'%j4)
        for jj in range(4):
            j=4*j4+jj; v='cs_%d.%s'%(j>>1,'xy'[j&1]); e('    sacc=%s%s*H(W[%d])+sacc;'%(v,v[-1],jj))
        e('   }')
    e('   half2 hh=R(sacc,0,127);')
    for hs,comp in ((0,'x'),(1,'y')):
        for m4 in range(2):
            e('   { uint4 W=TW[wb+%d];'%(4+hs*2+m4))
            for mm in range(4): m=4*m4+mm; e('    z%d=hh.%s%s*H(W[%d])+z%d;'%(m,comp,comp,mm,m))
            e('   }')
    e('  }')
e('  }')
for m in range(8): e('  half2 r%d=R(z%d,-128,127);'%(m,m))
if GCNHEAD:
    assert not H32 and not os.environ.get('PK16') and not os.environ.get('OCR') and not os.environ.get('ROW16')
    if not GCNST: e('  uint V[4][8];')
    e('  [loop] for(uint sp=Z;sp<4u+Z;sp++){ uint spx=sp&1u, spy=sp>>1;')
    for j in range(4):
        e('   half2 hj%d=H(TBH[sp*4u+%du]);'%(j,j))
        for q4 in range(4):
            e('   { uint4 W=TH[(sp*4u+%du)*4u+%du];'%(j,q4))
            for qq in range(4):
                qi=4*q4+qq; v='r%d.%s'%(qi//2,'xy'[qi&1]); e('    hj%d=%s%s*H(W[%d])+hj%d;'%(j,v,v[-1],qq,j))
            e('   }')
    e('   float4 sg=1.0/(1.0+exp2(float4(hj0.x,hj0.y,hj1.x,hj1.y)*kk));')
    e('   float ep=exp2(float(hj2.x)*-kk), en=exp2(float(hj2.x)*kk); float rho=(ep-en)/(en+ep);')
    e('   float sx=2.0/(1.0+exp2(float(hj2.y)*kk)), sy=2.0/(1.0+exp2(float(hj3.x)*kk)), al=1.0/(1.0+exp2(float(hj3.y)*kk));')
    e('   float sx2=sx*sx, sy2=sy*sy, cxy=2.0*rho*sx*sy;')
    e('   uint DXp=2*X+spx, DYp=2*Y+spy;')
    e('   float u=ox+inv_scale.x*float(DXp), v=%s; int iu=int(round(u)), iv=int(round(v));' % ('(jitter.y+(-0.5))+inv_scale.y*(float(DYp)+0.5)' if NL else 'oy+inv_scale.y*float(DYp)'))
    e('   float3 num=0; float den=0;')
    e('   [unroll] for(int a=-1;a<=1;a++){ int j=iv+a; float dy=(float(j)-v)*scale.y; int rowi=(j-ivo)*%d;'%TCW)
    e('    [unroll] for(int b=-1;b<=1;b++){ int i=iu+b; float dx=(float(i)-u)*scale.x;')
    e('     float Q=(dy*cxy+dx*sx2)*dx+dy*dy*sy2; float wt=(j<0||i<0)?0.0:exp2(Q*-3.265493392944336);')
    e('     uint ti=uint(rowi+i-iuo); %s den+=wt; } }' % ("num+=wt*CT3[wv][ti].xyz;" if os.environ.get('CT3') else "num+=wt*float3(CT[wv][0][ti],CT[wv][1][ti],CT[wv][2][ti]);"))
    e('   float3 rec=num/den;')
    e('   float3 hcol=float3(r_reprojected_color.Load(int3(DXp,DYp,0)));')
    e('   float3 bl=(1.0-al)*rec+al*hcol;')
    e('   float3 oc=bl;' + ('' if LINC else ({0: ' if(rcas_enabled==0u) %s=max((exp2(%s*12.288703918457031)-1.0)*0.006666666828095913,0.0)/e;', 1: ' if(rcas_enabled==0u) %s=senc3(max((exp2(%s*12.288703918457031)-1.0)*0.006666666828095913,0.0));', 2: ' if(rcas_enabled==0u) %s=penc3(max((exp2(%s*12.288703918457031)-1.0)*0.006666666828095913,0.0));'}[CURVE]) % ('oc', 'bl')))
    e('   oc=min(max(oc,0.0),64000.0);')
    if GCNST:   # each lane writes its own subpixel (images are tiled: no lane shuffle for the stores); O(.,Z) keeps the
                # shader's own fp32 -> fp16 rounding (a bare half store let the compiler leave the conversion to the image format)
        e('   uint2 D=uint2(DXp,DYp); if(%s && D.y<%du){ rw_history_color[D]=bl; rw_mlsr_output_color[D]=oc; rw_recurrent_0[D]=half4(O(half2(sg.xy),Z),O(half2(sg.zw),Z)); }'%('(oc.x==-12345.0)' if 'nostore' in DIAG else 'true',2*HH))
    else:
        e('   V[sp][0]=asuint(bl.x); V[sp][1]=asuint(bl.y); V[sp][2]=asuint(bl.z); V[sp][3]=asuint(oc.x); V[sp][4]=asuint(oc.y); V[sp][5]=asuint(oc.z); V[sp][6]=P(half2(sg.xy)); V[sp][7]=P(half2(sg.zw));')
    e('  }')
else:
 for n in range(16):
     sp,j=divmod(n,4)
     if H32: e('  float2 hv%d=float2(%s,%s);'%(n,repr(float(np.float32(w['BH'][sp,2*j]/1024.0))),repr(float(np.float32(w['BH'][sp,2*j+1]/1024.0)))))
     else: e('  half2 hv%d=%s;'%(n,h2(w['BH'][sp,2*j]/1024.0,w['BH'][sp,2*j+1]/1024.0)))
     for q4 in range(4):
         e('  { uint4 W=TH[%d];'%(n*4+q4))
         for qq in range(4):
             qi=4*q4+qq; v='r%d.%s'%(qi//2,'xy'[qi&1])
             if H32: e('   hv%d=mad(float2(float(%s),float(%s)),float2(H(W[%d])),hv%d);'%(n,v,v,qq,n))   # exact: int8 x int8/1024 in fp32, as AMD's integer head
             else: e('   hv%d=%s%s*H(W[%d])+hv%d;'%(n,v,v[-1],qq,n))
         e('  }')
 e('  uint V[4][%d];'%(5 if (os.environ.get('PK16') or os.environ.get('OCR')) else 8))
 for sp in range(4):
     spy,spx=divmod(sp,2); n0=sp*4
     e('  {')
     e('   float4 sg=1.0/(1.0+exp2(float4(hv%d.x,hv%d.y,hv%d.x,hv%d.y)*kk));'%(n0,n0,n0+1,n0+1))
     e('   float ep=exp2(float(hv%d.x)*-kk), en=exp2(float(hv%d.x)*kk); float rho=(ep-en)/(en+ep);'%(n0+2,n0+2))
     e('   float sx=2.0/(1.0+exp2(float(hv%d.y)*kk)), sy=2.0/(1.0+exp2(float(hv%d.x)*kk)), al=1.0/(1.0+exp2(float(hv%d.y)*kk));'%(n0+2,n0+3,n0+3))
     e('   float sx2=sx*sx, sy2=sy*sy, cxy=2.0*rho*sx*sy;')
     e('   uint DXp=2*X+%d, DYp=2*Y+%d;'%(spx,spy))
     # NL: AMD's non-linear post forms the vertical position as (jitter-0.5)+scale*(y+0.5); same value, different rounding,
     # and exact .5 cases pick a different tap row, so match it
     e('   float u=ox+inv_scale.x*float(DXp), v=%s; int iu=int(round(u)), iv=int(round(v));' % ('(jitter.y+(-0.5))+inv_scale.y*(float(DYp)+0.5)' if NL else 'oy+inv_scale.y*float(DYp)'))
     e('   float3 num=0; float den=0;')
     e('   [unroll] for(int a=%s;a<=%s;a++){ int j=iv+a; float dy=(float(j)-v)*scale.y; int rowi=(j-ivo)*%d;'%((('0','0') if 'noreco' in DIAG else ('-1','1'))+(TCW,)))   # (noreco: timing only, 1 tap)
     e('    [unroll] for(int b=%s;b<=%s;b++){ int i=iu+b; float dx=(float(i)-u)*scale.x;' % (('0','0') if 'noreco' in DIAG else ('-1','1')))
     e('     float Q=(dy*cxy+dx*sx2)*dx+dy*dy*sy2; float wt=(j<0||i<0)?0.0:exp2(Q*-3.265493392944336);')
     e('     uint ti=uint(rowi+i-iuo); '+("num+=wt*asfloat(uint3(SHM[wv][ti],SHM[wv][280+ti],SHM[wv][560+ti]));" if os.environ.get('STG') else (("num+=wt*CT3[wv][ti].xyz;") if os.environ.get('CT3') else "num+=wt*float3(CT[wv][0][ti],CT[wv][1][ti],CT[wv][2][ti]);"))+' den+=wt; } }')
     e('   float3 rec=num/den;')
     e('   float3 hcol=float3(r_reprojected_color.Load(int3(DXp,DYp,0)));')
     e('   float3 bl=(1.0-al)*rec+al*hcol;')
     e('   float3 oc=bl;' + ('' if LINC else ({0: ' if(rcas_enabled==0u) %s=max((exp2(%s*12.288703918457031)-1.0)*0.006666666828095913,0.0)/e;', 1: ' if(rcas_enabled==0u) %s=senc3(max((exp2(%s*12.288703918457031)-1.0)*0.006666666828095913,0.0));', 2: ' if(rcas_enabled==0u) %s=penc3(max((exp2(%s*12.288703918457031)-1.0)*0.006666666828095913,0.0));'}[CURVE]) % ('oc', 'bl')))
     e('   oc=min(max(oc,0.0),64000.0);')
     if os.environ.get('OCR'): e('   V[%d][0]=asuint(bl.x); V[%d][1]=asuint(bl.y); V[%d][2]=asuint(bl.z); V[%d][3]=P(half2(sg.xy)); V[%d][4]=P(half2(sg.zw));'%((sp,)*5))
     elif os.environ.get('PK16'): e('   V[%d][0]=P(half2(bl.xy)); V[%d][1]=P(half2(bl.z,oc.x)); V[%d][2]=P(half2(oc.yz)); V[%d][3]=P(half2(sg.xy)); V[%d][4]=P(half2(sg.zw));'%((sp,)*5))
     else: e('   V[%d][0]=asuint(bl.x); V[%d][1]=asuint(bl.y); V[%d][2]=asuint(bl.z); V[%d][3]=asuint(oc.x); V[%d][4]=asuint(oc.y); V[%d][5]=asuint(oc.z); V[%d][6]=P(half2(sg.xy)); V[%d][7]=P(half2(sg.zw));'%((sp,)*8))
     e('  }')
     if os.environ.get('ROW16') and spx==1:
         dy=spy
         NV16 = 5 if os.environ.get('OCR') else 8
         e('  [unroll] for(uint hh=0;hh<2u;hh++){ uint SS=8u*hh+((L&15u)>>1)+16u*(L>>4); bool odd=(L&1u)!=0u; uint vv[%d];'%NV16)
         e('   [unroll] for(uint c=0;c<%du;c++){ uint b0=WaveReadLaneAt(V[%d][c],SS), b1=WaveReadLaneAt(V[%d][c],SS); vv[c]=odd?b1:b0; }'%(NV16,2*dy,2*dy+1))
         e('   uint2 D=uint2(DX0+16u*hh+(L&15u), DYi+2u*(L>>4)+%du);'%dy)
         if os.environ.get('OCR'):   # (OCR: the output colour from the blend after the shuffle, as OCR's tile stores do)
             e(OCR_OC)
             e('   if(%s && D.y<%du){ rw_history_color[D]=b3; rw_mlsr_output_color[D]=o3; rw_recurrent_0[D]=half4(H(vv[3]),H(vv[4])); } }'%('(b3.x==-12345.0)' if 'nostore' in DIAG else 'true',2*HH))
         else:
             e('   if(%s && D.y<%du){ rw_history_color[D]=asfloat(uint3(vv[0],vv[1],vv[2])); rw_mlsr_output_color[D]=asfloat(uint3(vv[3],vv[4],vv[5])); rw_recurrent_0[D]=half4(H(vv[6]),H(vv[7])); } }'%('(asfloat(vv[3])==-12345.0)' if 'nostore' in DIAG else 'true',2*HH))
# tile stores: store k covers px (8k+(L&7), L>>3) of the 32x4 strip
if GCNST: pass
elif os.environ.get('STG'):
    for sp in range(4):
        spy,spx=divmod(sp,2)
        e('  { uint pp=((2u*lsy+%du)*32u+2u*lsx+%du)*8u; SHM[wv][pp]=V[%d][0]; SHM[wv][pp+1]=V[%d][1]; SHM[wv][pp+2]=V[%d][2]; SHM[wv][pp+3]=V[%d][3]; SHM[wv][pp+4]=V[%d][4]; SHM[wv][pp+5]=V[%d][5]; SHM[wv][pp+6]=V[%d][6]; SHM[wv][pp+7]=V[%d][7]; }'%((spy,spx)+(sp,)*8))
    e('  [unroll] for(uint k=0;k<4u;k++){ uint pp=((L>>3)*32u+8u*k+(L&7u))*8u; uint vv[8];')
    e('   [unroll] for(uint c=0;c<8u;c++) vv[c]=SHM[wv][pp+c];')
    e('   uint2 D=uint2(DX0+8u*k+(L&7u), DYi+(L>>3));')
    e('   if(%s && D.y<%du){ rw_history_color[D]=asfloat(uint3(vv[0],vv[1],vv[2])); rw_mlsr_output_color[D]=asfloat(uint3(vv[3],vv[4],vv[5])); rw_recurrent_0[D]=half4(H(vv[6]),H(vv[7])); }'%('(asfloat(vv[3])==-12345.0)' if 'nostore' in DIAG else 'true',2*HH))
    e('  }')
elif not os.environ.get('ROW16'):
 e('  uint tdx=L&1u, tdy=(L>>3)&1u; uint ssy=L>>4;')
 e('  [unroll] for(uint k=0;k<4u;k++){')
 e('   uint SS=4u*k+((L&7u)>>1)+16u*ssy; uint vv[%d];'%(5 if (os.environ.get('PK16') or os.environ.get('OCR')) else 8))
 NV=5 if (os.environ.get('PK16') or os.environ.get('OCR')) else 8
 e('   [unroll] for(uint c=0;c<%du;c++){'%NV+' uint b0=WaveReadLaneAt(V[0][c],SS), b1=WaveReadLaneAt(V[1][c],SS), b2=WaveReadLaneAt(V[2][c],SS), b3=WaveReadLaneAt(V[3][c],SS); vv[c]=tdy!=0u?(tdx!=0u?b3:b2):(tdx!=0u?b1:b0); }')
 e('   uint2 D=uint2(DX0+8u*k+(L&7u), DYi+(L>>3));')
 if os.environ.get('OCR'):
     e('   float3 b3=asfloat(uint3(vv[0],vv[1],vv[2])); float3 o3=b3;' + ('' if LINC else ({0: ' if(rcas_enabled==0u) %s=max((exp2(%s*12.288703918457031)-1.0)*0.006666666828095913,0.0)/e;', 1: ' if(rcas_enabled==0u) %s=senc3(max((exp2(%s*12.288703918457031)-1.0)*0.006666666828095913,0.0));', 2: ' if(rcas_enabled==0u) %s=penc3(max((exp2(%s*12.288703918457031)-1.0)*0.006666666828095913,0.0));'}[CURVE]) % ('o3', 'b3')) + ' o3=min(max(o3,0.0),64000.0);')
     e('   if(%s && D.y<%du){ rw_history_color[D]=b3; rw_mlsr_output_color[D]=o3; rw_recurrent_0[D]=half4(H(vv[3]),H(vv[4])); }'%('(b3.x==-12345.0)' if 'nostore' in DIAG else 'true',2*HH))
 elif os.environ.get('PK16'):
     e('   half2 p0=H(vv[0]),p1=H(vv[1]),p2=H(vv[2]);')
     e('   if(%s && D.y<%du){ rw_history_color[D]=float3(p0.x,p0.y,p1.x); rw_mlsr_output_color[D]=float3(p1.y,p2.x,p2.y); rw_recurrent_0[D]=half4(H(vv[3]),H(vv[4])); }'%('(p0.x==-12345.0)' if 'nostore' in DIAG else 'true',2*HH))
 else:
     e('   if(%s && D.y<%du){ rw_history_color[D]=asfloat(uint3(vv[0],vv[1],vv[2])); rw_mlsr_output_color[D]=asfloat(uint3(vv[3],vv[4],vv[5])); rw_recurrent_0[D]=half4(H(vv[6]),H(vv[7])); }'%('(asfloat(vv[3])==-12345.0)' if 'nostore' in DIAG else 'true',2*HH))
 e('  }')
e(' }')
e('}')
if os.environ.get('W64SAFE'):
    # W64SAFE=1: any wave size (wave64-only GPUs: Vega, Radeon VII). A 64-thread group is two 32-lane halves; in wave64
    # both halves share one wave, so every lane shuffle adds the half's base lane. No [WaveSize] attribute. Same math.
    import re as _re
    L=[l.replace('[WaveSize(32)] ','') for l in L]
    i=next(k for k,l in enumerate(L) if 'uint Z=WaveReadLaneFirst(ln);' in l)
    L[i]=L[i]+' uint LB=WaveGetLaneIndex()&~31u;'
    L=[_re.sub(r',(SL|SS)\)',r',\1+LB)',l) if 'WaveReadLaneAt' in l else l for l in L]
    if os.environ.get('W64LDS'):
        # W64LDS=1: lane shuffles through one LDS word per thread instead of WaveReadLaneAt (in wave64 AMD's compiler
        # turns a per-lane-index WaveReadLaneAt into a waterfall loop, a HelixSR lesson). A wave runs in lockstep, so
        # every lane's write lands before any lane reads; the two 32-lane halves use disjoint slots. Same values.
        i=next(k for k,l in enumerate(L) if l.startswith('[numthreads(64,1,1)] void main'))
        L[i:i]=['groupshared uint SX[64];', 'uint XCH(uint v,uint s,uint t){ SX[t]=v; return SX[s]; }']
        j=next(k for k,l in enumerate(L) if 'uint LB=WaveGetLaneIndex()&~31u;' in l)
        L[j]=L[j].replace('uint LB=WaveGetLaneIndex()&~31u;','uint LB=tid&~31u;')
        L=[_re.sub(r'WaveReadLaneAt\(([^;]*?),((?:SL|SS)\+LB)\)',r'XCH(\1,\2,tid)',l) if 'WaveReadLaneAt' in l else l for l in L]
        assert not any('WaveReadLaneAt' in l for l in L)
open(out,'w').write('\n'.join(L)+'\n'); print(out,len(L),'lines')
