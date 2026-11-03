# Build neuron graph from partial-evaluated stores
import numpy as np
from pe import Sym,is_sym
def sb(w,k): v=(w>>(8*k))&255; return v-256 if v>127 else v
class G:
    def __init__(s): s.N={}; s.order=[]
    def lin(s,v):
        # returns (const, dict unit->coef) for an integer linear expression (dot chains, adds of consts)
        if not is_sym(v): return v,{}
        if v.op=='dot':
            acc,x,w=v.a; c,t=s.lin(acc); t=dict(t)
            for k,u in enumerate(s.bytes_of(x)):
                t[u]=t.get(u,0)+sb(w,k)
            return c,t
        if v.op=='add' and not is_sym(v.a[1]):
            c,t=s.lin(v.a[0]); return c+v.a[1],t
        raise ValueError('lin? %s'%v.op)
    def bytes_of(s,x):
        if is_sym(x) and x.op=='in': return [('in',x.a[0],k) for k in range(4)]
        out=[None]*4
        def walk(e):
            if is_sym(e) and e.op=='or': walk(e.a[0]); walk(e.a[1]); return
            # and(X,255) | and(shl(X,8),65280) | and(shl(X,16),16711680) | shl(X,24)
            sh=0; X=e
            if is_sym(e) and e.op=='and': X=e.a[0]
            if is_sym(X) and X.op=='shl': sh=X.a[1]//8; X=X.a[0]
            out[sh]=('n',s.neuron(X))
        walk(x); assert all(o is not None for o in out),out; return out
    def byte_src(s,e):
        # sign-extended byte extraction: ashr(shl(W,24-8k),24) or ashr(W,24)
        if e.op=='ashr' and e.a[1]==24:
            inner=e.a[0]
            if is_sym(inner) and inner.op=='shl': W,k=inner.a[0],(24-inner.a[1])//8
            else: W,k=inner,3
            return s.bytes_of(W)[k]
        raise ValueError('byte? %s'%e.op)
    def neuron(s,X):
        if X.id in s.N: return X.id
        # clamp: min(max(Y,-128),127) or max then min
        e=X; lo=hi=None
        while is_sym(e) and e.op in('min','max') and not is_sym(e.a[1]):
            if e.op=='min': hi=e.a[1]
            else: lo=e.a[1]
            e=e.a[0]
        d=dict(lo=lo,hi=hi)
        if e.op=='ashr':                      # integer requant
            s_=e.a[1]; add=e.a[0]            # add(add(L,c), and(lshr(L,s),1))
            L=add.a[0].a[0]
            relu=False
            if is_sym(L) and L.op=='max' and L.a[1]==0: relu=True; L=L.a[0]
            c,t=s.lin(L); d.update(kind='int',shift=s_,relu=relu,bias=c,terms=t)
        elif e.op=='f2i':                     # float residual: round(((i2f(L)*a)+(i2f(byte)*b))*c)
            r=e.a[0]; assert r.op=='round'; m=r.a[0]; assert m.op=='fmul'; sc=m.a[1]; f=m.a[0]; assert f.op=='fadd'
            parts={}
            for p in f.a:
                assert p.op=='fmul'; q=p.a[0]; assert q.op=='i2f'
                inner=q.a[0]
                if inner.op=='dot' or (inner.op=='add' and is_sym(inner.a[0]) and inner.a[0].op=='dot'): parts['lin']=(inner,p.a[1])
                else: parts['res']=(s.byte_src(inner),p.a[1])
            c,t=s.lin(parts['lin'][0])
            d.update(kind='res',scale=sc,lin_scale=parts['lin'][1],res=parts['res'][0],res_scale=parts['res'][1],bias=c,terms=t)
        else: raise ValueError('neuron? %s'%e.op)
        s.N[X.id]=d; s.order.append(X.id); return X.id
