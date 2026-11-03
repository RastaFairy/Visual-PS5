#!/usr/bin/env python3
"""Generate experimental two/three-pass locally translated k5x shaders.

Preserve arithmetic order. Checkpoint raw live registers and shared-memory words
at a top-level control-flow boundary; no generated shader bodies are checked in.
"""
import os
import re
from pathlib import Path


def generate(source: Path, output: Path):
    body=(source/'k5x_body.h').read_text()
    config=(source/'k5x_cfg.h').read_text()
    hlsl=(source/'k5x.hlsl').read_text()
    if '#define PX_SMEM_WORDS 4096' not in config or '#define PX_BLOCK_X 256' not in config:
        raise ValueError('Unexpected tile/shared-memory layout')
    if any(flag in config for flag in ['PX_LDS_ROW4','PX_LDS_ROW8']):
        raise ValueError('Split checkpoint requires raw FP32 shared memory')
    entry='void k5x_body(uint3 tid, uint3 ctaid) {'
    start=body.index('    if (rb0) {')
    cut=body.index('    if (rb60) {')
    if body.count(entry)!=1 or body.count('    if (rb60) {')!=1:
        raise ValueError('Unexpected generated control-flow graph')
    declarations=body[:start]
    before,after=body[start:cut],body[cut:]
    if 'PX_SURF_STORE' in before or 'return;' in before:
        raise ValueError('Checkpoint must precede surface writes and returns')
    pattern=r'\b(x_(?:rd|rs|r|f|p)\d+|rb\d+)'
    assigned=set(re.findall(pattern+r'\s*=(?!=)',before))
    used=set(re.findall(pattern+r'\b',after))
    live=sorted(assigned&used)
    if len(live)!=52:
        raise ValueError(f'Expected 52 conservative live values; found {len(live)}')
    state_words=sum(2 if name.startswith('x_rd') else 1 for name in live)
    words=4096+256*state_words
    stores=[]; loads=[]; slot=0
    for name in live:
        location=f'((_hx_base+4096u+{slot}u*256u+tid.x)*4u)'
        if name.startswith('x_rd'):
            stores.append(f'HX_SPLIT.Store({location},(uint){name});')
            stores.append(f'HX_SPLIT.Store({location}+1024u,(uint)({name}>>32));')
            loads.append(f'{name}=(uint64_t)HX_SPLIT.Load({location})|((uint64_t)HX_SPLIT.Load({location}+1024u)<<32);')
            slot+=2
        elif name.startswith(('rb','x_p')):
            stores.append(f'HX_SPLIT.Store({location},(uint){name});')
            loads.append(f'{name}=HX_SPLIT.Load({location})!=0u;')
            slot+=1
        else:
            stores.append(f'HX_SPLIT.Store({location},{name});')
            loads.append(f'{name}=HX_SPLIT.Load({location});')
            slot+=1
    group=f'uint _hx_base=((ctaid.z*PXGRID.y+ctaid.y)*PXGRID.x+ctaid.x)*{words}u;\n'
    zero='[unroll] for(uint _j=0u;_j<16u;++_j) { uint _i=tid.x+256u*_j; SMW[_i]=0u; }\nPX_BARRIER();\n'
    export='PX_BARRIER();\n[unroll] for(uint _j=0u;_j<16u;++_j) { uint _i=tid.x+256u*_j; HX_SPLIT.Store((_hx_base+_i)*4u,SMW[_i]); }\n'
    restore='[unroll] for(uint _j=0u;_j<16u;++_j) { uint _i=tid.x+256u*_j; SMW[_i]=HX_SPLIT.Load((_hx_base+_i)*4u); }\nPX_BARRIER();\n'
    phases=[declarations+group+zero+before+export+'\n'.join(stores)+'\n}\n',
            declarations+group+'\n'.join(loads)+'\n'+restore+after]
    output.mkdir(parents=True,exist_ok=True)
    for index,phase in enumerate(phases):
        name=f'k5x_s{index}'
        (output/f'{name}_body.h').write_text(phase.replace(entry,f'void {name}_body(uint3 tid, uint3 ctaid) {{'))
        text=hlsl.replace('"k5x_cfg.h"',f'"{name}_cfg.h"').replace('"k5x_body.h"',f'"{name}_body.h"')
        text=text.replace('k5x_body(tid, gid)',f'{name}_body(tid, gid)')
        text=text.replace('#include "'+name+'_body.h"','RWByteAddressBuffer HX_SPLIT : register(u2);\n#include "'+name+'_body.h"')
        signature='DescriptorTable(UAV(u0, numDescriptors = 2))'
        if text.count(signature)!=1:
            raise ValueError('Unexpected root signature')
        text=text.replace(signature,signature+', UAV(u2)')
        (output/f'{name}.hlsl').write_text(text)
        (output/f'{name}_cfg.h').write_text(config)
    return {'shared_words':4096,'state_words':state_words,'words_per_cta':words,'live_values':live,'block_threads':256}


# Reviewed checkpoint shapes per output-kernel family: shared-memory words, live neural words at the reconstruction
# boundary, first-half pixel words carried into the second half. k5nx (dfn_3x3_256, below a 1.49 ratio: Ultra Quality,
# DLAA) carries two groups of ten filter-parameter fragments and no upsampled feature words.
REVIEWED={'k5x':(4096,18,8),'k5fx':(4096,18,8),'k5nx':(5140,20,None)}
K5NX_TRANSFER=[f'x_r{b+o}' for b in (*range(1970,2011,10),*range(2030,2071,10)) for o in (0,1)]


def zero_shared(words):
    """Zero the thread group's shared memory (256 threads) before the first pass reads it."""
    if words==4096:   # k5x / k5fx: the original text (byte-identical builds)
        return '[unroll] for(uint _j=0u;_j<16u;++_j) { uint _i=tid.x+256u*_j; SMW[_i]=0u; }\nPX_BARRIER();\n'
    n=(words+255)//256
    return (f'[unroll] for(uint _j=0u;_j<{n}u;++_j) {{ uint _i=tid.x+256u*_j; if (_i<{words}u) SMW[_i]=0u; }}\n'
            'PX_BARRIER();\n')


def generate_coefficients(source: Path, output: Path, kernel: str='k5x'):
    """kernel: the output-kernel family (k5x = dfn_mid, k5fx = dfn_fastpath, k5nx = dfn_3x3_256; the same structure,
    other registers)."""
    k=kernel
    body=(source/f'{k}_body.h').read_text()
    config=(source/f'{k}_cfg.h').read_text()
    hlsl=(source/f'{k}.hlsl').read_text()
    if k not in REVIEWED: raise ValueError(f'No reviewed checkpoint shape for {k}')
    smem,state,_=REVIEWED[k]
    if f'#define PX_SMEM_WORDS {smem}\n' not in config or '#define PX_BLOCK_X 256' not in config:
        raise ValueError('Unexpected neural tile layout')
    entry=f'void {k}_body(uint3 tid, uint3 ctaid) {{'
    start=body.index('    if (rb0) {')
    # the barrier after the last MMAs, before the reconstruction reads its arguments (param +456 = GAME_COLOR)
    markers=list(re.finditer(r'        PX_BARRIER\(\);\n        x_rd\d+ = PX_PARAM64\(456u\);',body))
    if len(markers)!=1: raise ValueError('Neural/reconstruction boundary absent')
    cut=markers[0].start()+len('        PX_BARRIER();\n')
    declarations,before,after=body[:start],body[start:cut],body[cut:]
    if 'PX_SURF_STORE' in before or before.count('{')-before.count('}')!=1:
        raise ValueError('Unexpected boundary effects or scope')
    variable=r'\b(x_(?:rd|rs|r|f|p)\d+|rb\d+)'
    tainted=set()
    def remove_memory(match):
        text=match[0]
        if any(tag in text for tag in ['PX_GLD','PX_STS','LDS32(','px_ldmatrix','pxr_arows']):
            tainted.update(re.findall(variable+r'\s*=(?!=)',text))
            for call in re.findall(r'pxr_tile\(([^;]+)\)',text):
                tainted.update(s.strip() for s in call.split(',')[:2])
            return ''
        return text
    geometry=re.sub(r'(?m)^        \{[^{}]*\}',remove_memory,before)
    geometry=re.sub(r'(?m)^\s*compact_[46]\([^;]+;\s*$', '',geometry)
    geometry=geometry.replace('        PX_BARRIER();','')
    if any(tag in geometry for tag in ['PX_GLD','PX_STS','LDS32(','px_ldmatrix','pxr_tile','PX_BARRIER']):
        raise ValueError('Unremoved neural side effect in reconstruction prefix')
    assignments=re.findall(variable+r'\s*=\s*([^;]*);',before)
    for _ in range(len(assignments)+1):
        previous=len(tainted)
        for name,expression in assignments:
            if tainted.intersection(re.findall(variable,expression)):
                tainted.add(name)
        if len(tainted)==previous: break
    for condition in re.findall(r'if\s*\(([^)]+)\)',geometry):
        if tainted.intersection(re.findall(variable,condition)):
            raise ValueError('Recomputed geometry depends on neural data')
    assigned=set(re.findall(variable+r'\s*=(?!=)',before))
    live=assigned&set(re.findall(variable,after))
    transfer=sorted(tainted&live)
    # reviewed shape: the 10 layer-B D fragments still live (n tiles 0..4, two words each) and the 8 upsampled feature
    # words; for k5x exactly x_r1002/1003 .. x_r1042/1043 and x_r2504..x_r2511
    layer_b=[a.strip() for call in re.findall(r'pxr_tile\(([^;]+?)\)',before) for a in call.split(',')[:2]]
    d_regs=sorted(set(layer_b[-12:])-set(layer_b[-2:]))   # last pxr_tile group = layer B; its 6th n tile is unused later
    if len(transfer)!=state or not set(d_regs)<=set(transfer) or len(d_regs)!=10:
        raise ValueError(f'Unreviewed neural live state: {transfer}')
    if k=='k5x' and transfer!=sorted([f'x_r{b+o}' for b in range(1002,1043,10) for o in [0,1]]+[f'x_r{i}' for i in range(2504,2512)]):
        raise ValueError(f'Unreviewed neural live state: {transfer}')
    if k=='k5nx' and transfer!=sorted(K5NX_TRANSFER):
        raise ValueError(f'Unreviewed neural live state: {transfer}')
    # slots 0..9: the filter parameters (layer-B D fragments in tile order), 10..17: the remaining words
    transfer=sorted(d_regs,key=lambda v:int(v[3:]))+sorted(set(transfer)-set(d_regs),key=lambda v:int(v[3:]))
    if k=='k5x':
        transfer=sorted(transfer)   # k5x keeps its original (string-sorted) slot order: byte-identical builds
    # Packed halves are checkpointed unchanged; geometry is recomputed from
    # parameters and thread/group IDs. Preserve edge-path neural state too.
    words=256*len(transfer)
    group=f'uint _hx_base=((ctaid.z*PXGRID.y+ctaid.y)*PXGRID.x+ctaid.x)*{words}u;\n'
    stores=[f'HX_SPLIT.Store((_hx_base+{i}u*256u+tid.x)*4u,{name});' for i,name in enumerate(transfer)]
    loads=[f'{name}=HX_SPLIT.Load((_hx_base+{i}u*256u+tid.x)*4u);' for i,name in enumerate(transfer)]
    zero=zero_shared(smem)
    phases=[declarations+group+zero+before+'\n'.join(stores)+'\n}\n}\n',
            declarations+group+zero+geometry+'\n'.join(loads)+'\n'+after]
    output.mkdir(parents=True,exist_ok=True)
    for index,phase in enumerate(phases):
        name=f'{k}_s{index}'
        (output/f'{name}_body.h').write_text(phase.replace(entry,f'void {name}_body(uint3 tid, uint3 ctaid) {{'))
        text=hlsl.replace(f'"{k}_cfg.h"',f'"{name}_cfg.h"').replace(f'"{k}_body.h"',f'"{name}_body.h"')
        text=text.replace(f'{k}_body(tid, gid)',f'{name}_body(tid, gid)')
        text=text.replace('#include "'+name+'_body.h"','RWByteAddressBuffer HX_SPLIT : register(u2);\n#include "'+name+'_body.h"')
        signature='DescriptorTable(UAV(u0, numDescriptors = 2))'
        if text.count(signature)!=1: raise ValueError('Unexpected root signature')
        (output/f'{name}.hlsl').write_text(text.replace(signature,signature+', UAV(u2)'))
        (output/f'{name}_cfg.h').write_text(config)
    return {'shared_words':0,'state_words':len(transfer),'words_per_cta':words,'live_values':transfer,
            'recomputed_values':sorted(live-set(transfer)),'block_threads':256,'geometry_recomputed':True,'kernel':k}


_VAR=r'\b(x_(?:rd|rs|r|f|p)\d+|rb\d+)'
_ASSIGN=re.compile(r'((?:x_(?:rd|rs|r|f|p)\d+|rb\d+))\s*=(?!=)(.*);$')
_COND_ASSIGN=re.compile(r'if \((.*)\) ((?:x_(?:rd|rs|r|f|p)\d+|rb\d+))\s*=(?!=)(.*);$')
_MEM=['PX_STS','LDS32(','PX_TEX_FETCH','PX_GLD','px_ldmatrix']


def _is_memory(text):
    return any(tag in text for tag in _MEM) or ('PX_TEX_LEVEL' in text and 'PX_TEX_LEVEL(0,' not in text)


def _top_blocks(text):
    """The top-level blocks '    if (rbN) {' ... of a generated body region (text starts at one)."""
    starts=[m.start() for m in re.finditer(r'(?m)^    if \(rb\d+\) \{',text)]
    if not starts or starts[0]!=0: raise ValueError('Region does not start at a top-level block')
    return [text[a:b] for a,b in zip(starts,starts[1:]+[len(text)])]


def _control_taint(prefix):
    """Values that depend on shared memory, texture fetches or global loads, directly or through control flow:
    a block whose guard flag is tainted taints everything it assigns; a one-line conditional assignment with a tainted
    condition taints its target. Returns (tainted, geometry): geometry is the prefix without tainted blocks, memory
    statements, surface stores and barriers, i.e. what every later pass can recompute from thread and group IDs."""
    blocks=_top_blocks(prefix)
    tainted=set()
    for _ in range(1000):
        before=len(tainted)
        for b in blocks:
            guard=re.match(r'    if \((rb\d+)\) \{',b)[1]
            if guard in tainted:
                tainted.update(re.findall(_VAR+r'\s*=(?!=)',b)); continue
            for sub in re.findall(r'(?m)^        \{[^{}]*\}',b):
                if _is_memory(sub): tainted.update(re.findall(_VAR+r'\s*=(?!=)',sub))
            for line in b.split('\n'):
                s=line.strip()
                m=_COND_ASSIGN.match(s)
                if m:
                    if tainted.intersection(re.findall(_VAR,m[1]+' '+m[3])): tainted.add(m[2])
                    continue
                m=_ASSIGN.match(s)
                if m and tainted.intersection(re.findall(_VAR,m[2])): tainted.add(m[1])
        if len(tainted)==before: break
    else:
        raise ValueError('Taint analysis did not converge')
    kept=[]
    for b in blocks:
        if re.match(r'    if \((rb\d+)\) \{',b)[1] in tainted: continue
        g=re.sub(r'(?m)^        \{[^{}]*\}',lambda m:'' if _is_memory(m[0]) else m[0],b)
        kept.append(re.sub(r'(?m)^\s*PX_SURF_STORE[14]\([^;]+;\s*$','',g).replace('        PX_BARRIER();',''))
    geometry=''.join(kept)
    if any(tag in geometry for tag in [*_MEM,'PX_SURF_STORE','PX_BARRIER']):
        raise ValueError('Recomputed geometry keeps memory, image or barrier effects')
    for line in geometry.split('\n'):
        s=line.strip()
        m=_COND_ASSIGN.match(s)
        if m and tainted.intersection(re.findall(_VAR,m[1])) and m[2] not in tainted:
            raise ValueError('Untainted value under tainted control: '+s)
        if re.match(r'if \(',s) and not m and tainted.intersection(re.findall(_VAR,s)):
            raise ValueError('Unexpected tainted control in geometry: '+s)
    return tainted,geometry


# Reviewed cut points of the k5nx reconstruction (after these output stores): each cut is at the end of one of the
# four repeated (large + small block) groups. Cuts inside a group (after store 8, 24, ...) carry shared-memory state
# across the boundary and fail the image gate.
K5NX_CUTS=(16,32,48)


def generate_parts(source: Path, output: Path, kernel: str='k5nx', cuts=K5NX_CUTS):
    """Neural pass + the reconstruction cut into len(cuts) + 1 passes at output-store boundaries. Each later pass
    recomputes the geometry and reloads the tainted values still live after its cut (_control_taint); the neural
    checkpoint keeps slots 0 .. state - 1 and the reconstruction state reuses one region after it (each thread reads
    its own words before writing them)."""
    k=kernel
    if k!='k5nx' or tuple(cuts)!=K5NX_CUTS: raise ValueError('Unreviewed reconstruction cuts')
    layout=generate_coefficients(source,output,k)
    neural=layout['state_words']
    body=(output/f'{k}_s1_body.h').read_text()
    start=body.index('    if (rb0) {')
    stores=[m.start() for m in re.finditer(r'PX_SURF_STORE4\(',body)]
    if len(stores)!=64: raise ValueError('Unexpected output store count')
    block=re.compile(r'\n    if \(rb\d+\) \{')
    offsets=[block.search(body,stores[n-1]).start()+1 for n in cuts]
    transfers=[]
    for c in offsets:
        tainted,_=_control_taint(body[start:c])
        live=set(re.findall(_VAR+r'\s*=(?!=)',body[start:c]))&set(re.findall(_VAR,body[c:]))
        transfers.append(sorted(tainted&live,key=lambda v:(v[:4],int(re.sub(r'\D','',v)))))
    size=lambda t:sum(2 if v.startswith('x_rd') else 1 for v in t)
    region=max(size(t) for t in transfers)
    words=(neural+region)*256
    def checkpoint(t,load):
        ops,slot=[],neural
        for v in t:
            at=f'(_hx_base+{slot}u*256u+tid.x)*4u'
            if v.startswith('x_rd'):
                ops.append(f'{v}=(uint64_t)HX_SPLIT.Load({at})|((uint64_t)HX_SPLIT.Load({at}+1024u)<<32);' if load else
                           f'HX_SPLIT.Store({at},(uint){v}); HX_SPLIT.Store({at}+1024u,(uint)({v}>>32));')
                slot+=2
            elif v.startswith(('rb','x_p')):
                ops.append(f'{v}=HX_SPLIT.Load({at})!=0u;' if load else f'HX_SPLIT.Store({at},(uint){v});'); slot+=1
            else:
                ops.append(f'{v}=HX_SPLIT.Load({at});' if load else f'HX_SPLIT.Store({at},{v});'); slot+=1
        return '\n'.join(ops)+'\n'
    stride=lambda text:re.subn(r'(uint _hx_base=[^\n]*\*)\d+u;',lambda m:m[1]+f'{words}u;',text,count=1)
    head,n=stride(body[:start])
    if n!=1: raise ValueError('Checkpoint group stride absent')
    bounds=[start,*offsets,len(body)]
    hlsl=(output/f'{k}_s1.hlsl').read_text(); config=(output/f'{k}_s1_cfg.h').read_text()
    for i in range(len(bounds)-1):
        name=f'{k}_s{i+1}'
        text=head
        if i: text+=_control_taint(body[start:bounds[i]])[1]+checkpoint(transfers[i-1],True)
        text+=body[bounds[i]:bounds[i+1]]
        if i<len(offsets): text+=checkpoint(transfers[i],False)+'}\n'
        (output/f'{name}_body.h').write_text(text.replace(f'void {k}_s1_body(',f'void {name}_body('))
        (output/f'{name}.hlsl').write_text(hlsl.replace(f'{k}_s1',name))
        (output/f'{name}_cfg.h').write_text(config)
    s0,n=stride((output/f'{k}_s0_body.h').read_text())
    if n!=1: raise ValueError('Checkpoint group stride absent')
    (output/f'{k}_s0_body.h').write_text(s0)
    layout.update(words_per_cta=words,state_words=neural+region,passes=len(bounds),reconstruction_cuts=list(cuts),
                  reconstruction_state=transfers)
    return layout


def generate_halves(source: Path, output: Path, kernel: str='k5x'):
    k=kernel
    layout=generate_coefficients(source,output,k)
    body=(output/f'{k}_s1_body.h').read_text()
    start=body.index('    if (rb0) {')
    # the second half starts with the first block after the middle output store (k5x: the eighth of sixteen, rb84;
    # k5nx: the 32nd of 64)
    stores=[m.start() for m in re.finditer(r'PX_SURF_STORE4\(',body)]
    if len(stores)!=(64 if k=='k5nx' else 16): raise ValueError('Unexpected output store count')
    nxt=re.compile(r'\n    if \(rb\d+\) \{').search(body,stores[len(stores)//2-1])
    if not nxt: raise ValueError('Second-half block absent')
    cut=nxt.start()+1
    if k=='k5x' and cut!=body.index('    if (rb84) {'): raise ValueError('k5x half boundary moved')
    prefix,after=body[start:cut],body[cut:]
    variable=r'\b(x_(?:rd|rs|r|f|p)\d+|rb\d+)'
    tainted=set()
    def prune(match):
        text=match[0]
        remove=any(tag in text for tag in ['PX_STS','LDS32(','PX_TEX_FETCH'])
        remove |= 'PX_TEX_LEVEL' in text and 'PX_TEX_LEVEL(0,' not in text
        if remove:
            tainted.update(re.findall(variable+r'\s*=(?!=)',text))
            return ''
        return text
    geometry=re.sub(r'(?m)^        \{[^{}]*\}',prune,prefix)
    geometry=re.sub(r'(?m)^\s*PX_SURF_STORE[14]\([^;]+;\s*$', '',geometry)
    geometry=geometry.replace('        PX_BARRIER();','')
    if any(tag in geometry for tag in ['PX_STS','LDS32(','PX_TEX_FETCH','PX_SURF_STORE','PX_BARRIER']):
        raise ValueError('Reconstruction prefix still has image/shared-memory effects')
    assignments=re.findall(variable+r'\s*=\s*([^;]*);',prefix)
    for _ in range(len(assignments)+1):
        previous=len(tainted)
        for name,expression in assignments:
            if tainted.intersection(re.findall(variable,expression)): tainted.add(name)
        if len(tainted)==previous: break
    for condition in re.findall(r'if\s*\(([^)]+)\)',geometry):
        if tainted.intersection(re.findall(variable,condition)):
            raise ValueError('Recomputed second-half control depends on removed pixel data')
    assigned=set(re.findall(variable+r'\s*=(?!=)',prefix))
    live=assigned&set(re.findall(variable,after))
    transfer=sorted(tainted&live)
    reviewed=REVIEWED[k][2]
    if os.environ.get('HX_SPLIT_PROBE'): print(f'{k} first-half pixel state ({len(transfer)}): {transfer}')
    if len(transfer)!=reviewed or (k=='k5x' and transfer!=[f'x_r{i}' for i in range(2522,2530)]):
        raise ValueError('Unreviewed first-half pixel state: '+str(transfer))
    original_words=layout['words_per_cta']
    words=original_words+256*len(transfer)
    base=layout['state_words']   # the neural slots come first
    stores=[f'HX_SPLIT.Store((_hx_base+{base+i}u*256u+tid.x)*4u,{name});' for i,name in enumerate(transfer)]
    loads=[f'{name}=HX_SPLIT.Load((_hx_base+{base+i}u*256u+tid.x)*4u);' for i,name in enumerate(transfer)]
    first=body[:cut]+'\n'.join(stores)+'\n}\n'
    second=body[:start]+geometry+'\n'.join(loads)+'\n'+after
    second=second.replace(f'void {k}_s1_body(', f'void {k}_s2_body(')
    phases=[(output/f'{k}_s0_body.h').read_text(),first,second]
    for i,phase in enumerate(phases):
        phase,count=re.subn(r'(uint _hx_base=[^\n]*\*)'+str(original_words)+r'u;',
                            lambda m:m[1]+str(words)+'u;',phase)
        if count!=1: raise ValueError('Checkpoint group stride absent')
        (output/f'{k}_s{i}_body.h').write_text(phase)
    hlsl=(output/f'{k}_s1.hlsl').read_text().replace(f'{k}_s1',f'{k}_s2')
    (output/f'{k}_s2.hlsl').write_text(hlsl)
    (output/f'{k}_s2_cfg.h').write_text((output/f'{k}_s1_cfg.h').read_text())
    layout.update(words_per_cta=words,state_words=base+len(transfer),passes=3,reconstruction_state=transfer)
    return layout
