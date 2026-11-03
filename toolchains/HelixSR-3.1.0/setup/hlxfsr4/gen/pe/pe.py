# Partial evaluator for FSR4 ML pass DXIL (.ll text). Concrete: thread ids, init buffer, cbuffer, local arrays.
# Symbolic: scratch loads (words). Builds neuron graph from dot4 + requant patterns.
import re,sys,numpy as np
class Sym:            # symbolic int value
    __slots__=('op','a','id')
    cnt=0
    def __init__(s,op,a): s.op=op; s.a=a; Sym.cnt+=1; s.id=Sym.cnt
    def __repr__(s): return 'S%d:%s'%(s.id,s.op)
def is_sym(v): return isinstance(v,Sym)
M32=0xffffffff
def s32(x): x&=M32; return x-(1<<32) if x>>31 else x
class Interp:
    def __init__(s,path,init,cb,tid,gid,scratch_base_sym=True):
        s.T=open(path).read()
        body=s.T[s.T.index('define void @'):]
        body=body[:body.index('\n}\n')]
        s.blocks={}; cur='%0'; s.blocks[cur]=[]
        for l in body.split('\n')[1:]:
            m=re.match(r'^; <label>:(\d+)',l)
            if m: cur='%'+m.group(1); s.blocks[cur]=[]; continue
            l=l.split(';')[0].rstrip()
            if l.strip(): s.blocks[cur].append(l.strip())
        s.init=init; s.cb=cb; s.tid=tid; s.gid=gid
        s.V={}; s.mem={}; s.loads=[]; s.stores=[]; s.dots=[]; s.scr=None
    def val(s,t):
        t=t.strip()
        if t.startswith('%'): return s.V[t]
        if t in('undef','false'): return 0
        if t=='true': return 1
        if t.startswith('0x'):
            return float(np.frombuffer(np.uint64(int(t,16)).tobytes(),np.float64)[0])
        try: return int(t)
        except: return float(t)
    def run(s,maxsteps=10**7):
        b='%0'; prev=None; steps=0
        while True:
            # phis
            ins=s.blocks[b]; i=0; newv={}
            while i<len(ins) and ' = phi ' in ins[i]:
                m=re.match(r'(%\w+) = phi \S+ (.*)$',ins[i])
                for pair in re.findall(r'\[ ([^,]+), (%\w+) \]',m.group(2)):
                    if pair[1]==prev: newv[m.group(1)]=s.val(pair[0])
                i+=1
            s.V.update(newv)
            for l in ins[i:]:
                steps+=1
                if l.startswith('br '):
                    m=re.match(r'br i1 (\S+), label (%\w+), label (%\w+)',l)
                    if m:
                        c=s.val(m.group(1)); assert not is_sym(c),('symbolic branch',l)
                        nb=m.group(2) if c else m.group(3)
                    else: nb=re.match(r'br label (%\w+)',l).group(1)
                    prev=b; b=nb; break
                if l.startswith('ret'): return
                s.exec(l)
            else: raise RuntimeError('fallthrough '+b)
    def exec(s,l):
        m=re.match(r'(%\w+) = (.*)$',l)
        if not m:
            if 'rawBufferStore' in l:
                a=re.findall(r'i32 ([%\w-]+)',l); h=re.search(r'Handle (%\w+)',l).group(1)
                args=re.search(r'\((.*)\)',l).group(1).split(',')
                addr=s.val(args[2].split()[-1]); vals=[s.val(x.split()[-1]) for x in args[4:8]]
                mask=int(args[8].split()[-1])
                s.stores.append((h,addr,[v for k,v in enumerate(vals) if mask>>k&1])); return
            if l.startswith('store '):
                mm=re.match(r'store i32 ([%\w-]+), i32\* (%\w+)',l); s.mem[s.V[mm.group(2)]]=s.val(mm.group(1)); return
            if 'textureStore' in l: s.stores.append(('tex',l,None)); return
            raise RuntimeError('unhandled '+l)
        d,e=m.groups(); V=s.V
        if e.startswith('alloca'): V[d]=('arr',d); return
        mm=re.match(r'getelementptr .*?\* (%\w+), i32 0, i32 ([%\w-]+)',e)
        if mm: V[d]=(V[mm.group(1)][1],s.val(mm.group(2))); return
        mm=re.match(r'load i32, i32\* (%\w+)',e)
        if mm: V[d]=s.mem[V[mm.group(1)]]; return
        mm=re.match(r'call %dx.types.Handle @dx.op.createHandle\(i32 57, i8 (\d), i32 \d+, i32 (\d+)',e)
        if mm: V[d]=('h',int(mm.group(1)),int(mm.group(2))); return
        mm=re.match(r'call i32 @dx.op.threadId.i32\(i32 93, i32 (\d)\)',e)
        if mm: V[d]=s.gid[int(mm.group(1))]; return
        mm=re.match(r'call i32 @dx.op.groupId.i32\(i32 94, i32 (\d)\)',e)
        if mm: V[d]=0 if int(mm.group(1))==2 else s.gid[int(mm.group(1))]//64; return
        mm=re.match(r'call i32 @dx.op.threadIdInGroup.i32\(i32 95, i32 (\d)\)',e)
        if mm: V[d]=s.tid[int(mm.group(1))]; return
        mm=re.match(r'call %dx.types.CBufRet.(i32|f32) @dx.op.cbufferLoadLegacy.\w+\(i32 59, %dx.types.Handle (%\w+), i32 (\d+)\)',e)
        if mm:
            r=int(mm.group(3)); raw=s.cb[16*r:16*r+16]
            V[d]=list(raw.view(np.int32 if mm.group(1)=='i32' else np.float32).tolist()); return
        mm=re.match(r'call %dx.types.ResRet.i32 @dx.op.rawBufferLoad.i32\(i32 139, %dx.types.Handle (%\w+), i32 ([%\w-]+), i32 undef, i8 (\d+)',e)
        if mm:
            h=V[mm.group(1)]; addr=s.val(mm.group(2)); n=bin(int(mm.group(3))).count('1')
            if h[1]==0 and h[2]==21:   # init SRV
                V[d]=[int(np.frombuffer(s.init[addr+4*k:addr+4*k+4].tobytes(),np.int32)[0]) for k in range(n)]+[0]*(4-n)
            else:
                assert not is_sym(addr)
                if s.scr is not None: w=[int(np.frombuffer(s.scr[addr+4*k:addr+4*k+4].tobytes(),np.int32)[0]) for k in range(n)]+[0]*(4-n)
                else: w=[Sym('in',(addr+4*k,)) for k in range(n)]+[0]*(4-n)
                V[d]=w; s.loads.append(addr)
            return
        mm=re.match(r'extractvalue %dx.types.\w+(?:\.\w+)? (%\w+), (\d)',e)
        if mm: V[d]=V[mm.group(1)][int(mm.group(2))]; return
        mm=re.match(r'call i32 @dx.op.dot4AddPacked.i32\(i32 163, i32 ([%\w-]+), i32 ([%\w-]+), i32 ([%\w-]+)\)',e)
        if mm:
            acc,x,w=(s.val(t) for t in mm.groups())
            if not is_sym(acc) and not is_sym(x) and not is_sym(w):
                V[d]=s32(acc+sum(((((x>>(8*k))&255)^128)-128)*((((w>>(8*k))&255)^128)-128) for k in range(4))); return
            if is_sym(w) and not is_sym(x): x,w=w,x
            assert not is_sym(w),'symbolic weight'
            V[d]=Sym('dot',(acc,x,w)); return
        mm=re.match(r'(add|sub|mul|shl|lshr|ashr|and|or|xor)(?: nuw| nsw| exact)* i32 ([%\w-]+), ([%\w-]+)$',e)
        if mm:
            op=mm.group(1); a=s.val(mm.group(2)); b=s.val(mm.group(3))
            if not is_sym(a) and not is_sym(b):
                f={'add':lambda:a+b,'sub':lambda:a-b,'mul':lambda:a*b,'shl':lambda:a<<b,'lshr':lambda:(a&M32)>>b,'ashr':lambda:s32(a)>>b,'and':lambda:a&b,'or':lambda:a|b,'xor':lambda:a^b}[op]
                V[d]=s32(f()); return
            V[d]=Sym(op,(a,b)); return
        mm=re.match(r'call i32 @dx.op.binary.i32\(i32 (3[78]), i32 ([%\w-]+), i32 ([%\w-]+)\)',e)
        if mm:
            a=s.val(mm.group(2)); b=s.val(mm.group(3)); op='max' if mm.group(1)=='37' else 'min'
            if not is_sym(a) and not is_sym(b): V[d]=max(a,b) if op=='max' else min(a,b); return
            V[d]=Sym(op,(a,b)); return
        mm=re.match(r'call i32 @dx.op.tertiary.i32\(i32 49, i32 ([%\w-]+), i32 ([%\w-]+), i32 ([%\w-]+)\)',e)
        if mm:
            a,b,c=(s.val(t) for t in mm.groups())
            if not any(map(is_sym,(a,b,c))): V[d]=s32(a*b+c); return
            V[d]=Sym('mad',(a,b,c)); return
        mm=re.match(r'icmp (\w+) i32 ([%\w-]+), ([%\w-]+)',e)
        if mm:
            a=s.val(mm.group(2)); b=s.val(mm.group(3)); assert not is_sym(a) and not is_sym(b),l
            op=mm.group(1); ua,ub=a&M32,b&M32
            V[d]=int({'eq':a==b,'ne':a!=b,'ugt':ua>ub,'uge':ua>=ub,'ult':ua<ub,'ule':ua<=ub,'sgt':a>b,'sge':a>=b,'slt':a<b,'sle':a<=b}[op]); return
        mm=re.match(r'(or|and|xor) i1 ([%\w-]+), ([%\w-]+)',e)
        if mm:
            a=s.val(mm.group(2)); b=s.val(mm.group(3)); V[d]={'or':a|b,'and':a&b,'xor':a^b}[mm.group(1)]; return
        mm=re.match(r'select i1 ([%\w-]+), \w+ ([%\w.+-]+), \w+ ([%\w.+-]+)',e)
        if mm:
            c=s.val(mm.group(1)); assert not is_sym(c),l; V[d]=s.val(mm.group(2) if c else mm.group(3)); return
        mm=re.match(r'sitofp i32 ([%\w-]+) to float',e)
        if mm: a=s.val(mm.group(1)); V[d]=Sym('i2f',(a,)) if is_sym(a) else float(a); return
        mm=re.match(r'uitofp i32 ([%\w-]+) to float',e)
        if mm: a=s.val(mm.group(1)); V[d]=Sym('u2f',(a,)) if is_sym(a) else float(a&M32); return
        mm=re.match(r'fptosi float ([%\w-]+) to i32',e)
        if mm: a=s.val(mm.group(1)); V[d]=Sym('f2i',(a,)) if is_sym(a) else int(a); return
        mm=re.match(r'f(mul|add|sub|div)(?: fast)? float ([%\w.+-]+), ([%\w.+-]+)',e)
        if mm:
            a=s.val(mm.group(2)); b=s.val(mm.group(3))
            if not is_sym(a) and not is_sym(b): V[d]={'mul':a*b,'add':a+b,'sub':a-b,'div':a/b if b else float('inf')}[mm.group(1)]; return
            V[d]=Sym('f'+mm.group(1),(a,b)); return
        mm=re.match(r'call float @dx.op.unary.f32\(i32 (\d+), float ([%\w.+-]+)\)',e)
        if mm:
            a=s.val(mm.group(2)); op={'26':'round'}.get(mm.group(1),'u'+mm.group(1))
            if not is_sym(a) and op=='round': V[d]=float(np.round(a)); return
            V[d]=Sym(op,(a,)); return
        raise RuntimeError('unhandled: '+l)
