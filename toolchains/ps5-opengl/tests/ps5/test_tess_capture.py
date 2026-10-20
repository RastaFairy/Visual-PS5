#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

"""Two-pass tessellation + geometry: the driver's capture and replay shaders
must compile and package through the real compiler; no native execution."""
import hashlib
import os
import resource
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PSBC = ROOT / "third_party/opengnm-psbc"
LIB = PSBC / "libpsbc.a"
DRIVER = (ROOT / "src/gallium/ps5/ps5_screen.c").read_text()


def function(source, signature):
    start = source.index(signature)
    return source[start:source.index("\n}", start) + 3] + "\n"


helpers = "\n".join(line for line in DRIVER.splitlines()
                    if line.startswith(("#define PS5_TESS_CAPTURE_MAX_SLOTS ",
                                        "#define PS5_TESS_CAPTURE_MAX_BYTES "))) + "\n"
assert helpers.count("#define") == 2
helpers += function((PSBC / "src/compiler/nir/nir_passthrough_tcs.c").read_text(),
                    "nir_shader *\nnir_create_passthrough_tcs_impl(")
for signature in ("static bool\nps5_lower_default_tess_levels(",
                  "static nir_shader *\nps5_default_tcs_nir(",
                  "static bool\nps5_tess_capture_slots(",
                  "static nir_shader *\nps5_tess_capture_tes_nir(",
                  "static nir_shader *\nps5_tess_capture_vs_nir(",
                  "static nir_shader *\nps5_tess_capture_fs_nir("):
    helpers += function(DRIVER, signature)

code = r'''
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "psbc_compile.h"
#include "ps5_agc_package.h"
#include "compiler/nir/nir_builder.h"
#include "compiler/nir/nir_xfb_info.h"
#include "amd/common/sid.h"
''' + helpers + r'''

static nir_variable *io(nir_builder *b, nir_variable_mode mode,
                        const struct glsl_type *type, unsigned slot) {
    nir_variable *v=nir_variable_create(b->shader,mode,type,NULL);
    v->data.location=slot;
    if(glsl_get_base_type(glsl_without_array(type))!=GLSL_TYPE_FLOAT)
        v->data.interpolation=INTERP_MODE_FLAT;
    return v;
}
static nir_def *element(nir_builder *b, nir_variable *v, unsigned i) {
    return nir_load_deref(b,nir_build_deref_array_imm(b,nir_build_deref_var(b,v),i));
}
static nir_shader *lowered(nir_builder *b) {
    /* The same lowering st/mesa applies before the driver sees a shader. */
    nir_lower_io_passes(b->shader,false);
    nir_shader_gather_info(b->shader,nir_shader_get_entrypoint(b->shader));
    nir_validate_shader(b->shader,"host shader");
    assert(b->shader->info.io_lowered);
    return b->shader;
}
static nir_shader *vertex(void) {
    nir_builder b=nir_builder_init_simple_shader(MESA_SHADER_VERTEX,
        psbc_get_nir_options(PSBC_STAGE_VERTEX),"vs");
    nir_store_var(&b,io(&b,nir_var_shader_out,glsl_vec4_type(),VARYING_SLOT_POS),
        nir_load_var(&b,io(&b,nir_var_shader_in,glsl_vec4_type(),VERT_ATTRIB_GENERIC0)),15);
    return lowered(&b);
}
/* The CTS grid evaluation shader: position from the tessellation coordinate
 * and an integer grid position. */
static nir_shader *evaluation(bool point_size, bool wide) {
    nir_builder b=nir_builder_init_simple_shader(MESA_SHADER_TESS_EVAL,
        psbc_get_nir_options(PSBC_STAGE_TESS_EVAL),"tes");
    b.shader->info.tess._primitive_mode=TESS_PRIMITIVE_QUADS;
    b.shader->info.tess.spacing=TESS_SPACING_EQUAL;
    b.shader->info.tess.ccw=true;
    nir_def *coord=nir_load_tess_coord(&b);
    nir_def *x=nir_channel(&b,coord,0), *y=nir_channel(&b,coord,1);
    nir_store_var(&b,io(&b,nir_var_shader_out,glsl_vec4_type(),VARYING_SLOT_POS),
        nir_vec4(&b,nir_fadd_imm(&b,nir_fmul_imm(&b,x,2),-1),
                    nir_fadd_imm(&b,nir_fmul_imm(&b,y,2),-1),
                    nir_imm_float(&b,0),nir_imm_float(&b,1)),15);
    nir_store_var(&b,io(&b,nir_var_shader_out,glsl_ivec2_type(),VARYING_SLOT_VAR0),
        nir_f2i32(&b,nir_fround_even(&b,nir_fmul_imm(&b,nir_vec2(&b,x,y),64))),3);
    if(point_size)
        nir_store_var(&b,io(&b,nir_var_shader_out,glsl_float_type(),VARYING_SLOT_PSIZ),
                      nir_fadd_imm(&b,x,1),1);
    if(wide)
        nir_store_var(&b,io(&b,nir_var_shader_out,glsl_dvec2_type(),VARYING_SLOT_VAR3),
                      nir_f2f64(&b,nir_vec2(&b,x,y)),3);
    return lowered(&b);
}
/* An instanced strip-emitting geometry shader in the shape of the CTS limits
 * cases: every invocation emits "vertices" vertices from the input triangle. */
static nir_shader *geometry(unsigned invocations, unsigned vertices,
                            bool point_size, bool wide) {
    nir_builder b=nir_builder_init_simple_shader(MESA_SHADER_GEOMETRY,
        psbc_get_nir_options(PSBC_STAGE_GEOMETRY),"gs");
    b.shader->info.gs.input_primitive=MESA_PRIM_TRIANGLES;
    b.shader->info.gs.output_primitive=MESA_PRIM_TRIANGLE_STRIP;
    b.shader->info.gs.vertices_in=3;
    b.shader->info.gs.vertices_out=vertices;
    b.shader->info.gs.invocations=invocations;
    b.shader->info.gs.active_stream_mask=1;
    nir_variable *in_position=io(&b,nir_var_shader_in,
        glsl_array_type(glsl_vec4_type(),3,0),VARYING_SLOT_POS);
    nir_variable *in_grid=io(&b,nir_var_shader_in,
        glsl_array_type(glsl_ivec2_type(),3,0),VARYING_SLOT_VAR0);
    nir_variable *out_position=io(&b,nir_var_shader_out,glsl_vec4_type(),VARYING_SLOT_POS);
    nir_variable *out_color=io(&b,nir_var_shader_out,glsl_vec4_type(),VARYING_SLOT_VAR1);
    nir_def *low=nir_fmin(&b,element(&b,in_position,0),
        nir_fmin(&b,element(&b,in_position,1),element(&b,in_position,2)));
    nir_def *grid=nir_i2f32(&b,nir_imin(&b,element(&b,in_grid,0),element(&b,in_grid,2)));
    nir_def *slice=nir_i2f32(&b,nir_load_invocation_id(&b));
    if(point_size) {
        nir_variable *in_size=io(&b,nir_var_shader_in,
            glsl_array_type(glsl_float_type(),3,0),VARYING_SLOT_PSIZ);
        slice=nir_fadd(&b,slice,element(&b,in_size,1));
    }
    if(wide) {
        nir_variable *in_wide=io(&b,nir_var_shader_in,
            glsl_array_type(glsl_dvec2_type(),3,0),VARYING_SLOT_VAR3);
        slice=nir_fadd(&b,slice,nir_f2f32(&b,nir_channel(&b,element(&b,in_wide,0),0)));
    }
    for(unsigned i=0;i<vertices;++i) {
        nir_def *offset=nir_vec4(&b,nir_imm_float(&b,i/2*0.001f),
            nir_fmul_imm(&b,nir_fadd_imm(&b,slice,i&1),0.001f),
            nir_imm_float(&b,0),nir_imm_float(&b,0));
        nir_store_var(&b,out_position,nir_fadd(&b,low,offset),15);
        nir_store_var(&b,out_color,nir_vec4(&b,nir_channel(&b,grid,0),
            nir_channel(&b,grid,1),slice,nir_imm_float(&b,1)),15);
        nir_emit_vertex(&b,0);
    }
    nir_end_primitive(&b,0);
    return lowered(&b);
}
/* Seventeen input slots do not fit the sixteen vertex attributes. */
static nir_shader *many_inputs(void) {
    nir_builder b=nir_builder_init_simple_shader(MESA_SHADER_GEOMETRY,
        psbc_get_nir_options(PSBC_STAGE_GEOMETRY),"gs-many");
    b.shader->info.gs.input_primitive=MESA_PRIM_TRIANGLES;
    b.shader->info.gs.output_primitive=MESA_PRIM_TRIANGLE_STRIP;
    b.shader->info.gs.vertices_in=3;
    b.shader->info.gs.vertices_out=3;
    b.shader->info.gs.invocations=2;
    b.shader->info.gs.active_stream_mask=1;
    nir_def *sum=nir_imm_vec4(&b,0,0,0,1);
    for(unsigned i=0;i<17;++i)
        sum=nir_fadd(&b,sum,element(&b,io(&b,nir_var_shader_in,
            glsl_array_type(glsl_vec4_type(),3,0),VARYING_SLOT_VAR0+i),0));
    nir_store_var(&b,io(&b,nir_var_shader_out,glsl_vec4_type(),VARYING_SLOT_POS),sum,15);
    nir_emit_vertex(&b,0);
    nir_end_primitive(&b,0);
    return lowered(&b);
}
static uint32_t context_value(const PsbcShaderMetadata *metadata, uint16_t offset) {
    for(unsigned i=0;i<metadata->context_register_count;++i)
        if(metadata->context_registers[i].offset==offset)
            return metadata->context_registers[i].value;
    assert(!"missing context register"); return 0;
}
static void package(const PsbcShaderOutput *output, uint32_t ring_itemsize) {
    uint8_t *data=NULL; size_t size=0;
    assert(output->machine_code_size);
    assert(!ps5_agc_package_build(output,ring_itemsize,&data,&size) && size);
    free(data);
}

int main(void) {
    psbc_init();
    const float levels[6]={64,64,64,64,64,64};
    nir_shader *vs=vertex();
    nir_shader *tcs=ps5_default_tcs_nir(vs->info.outputs_written,1,levels);
    assert(tcs);
    /* invocations x vertices: the three CTS limits shapes and one with a
     * point-size and a double-precision input. 4x16 fits one subgroup; 4x128
     * and 32x16 do not. */
    static const struct { unsigned invocations, vertices; bool point_size, wide; } shapes[]={
        {4,16,false,false},{4,128,false,false},{32,16,false,false},{4,16,true,true},
    };
    for(unsigned s=0;s<sizeof(shapes)/sizeof(shapes[0]);++s) {
        const bool point_size=shapes[s].point_size, wide=shapes[s].wide;
        nir_shader *tes=evaluation(point_size,wide);
        nir_shader *gs=geometry(shapes[s].invocations,shapes[s].vertices,point_size,wide);
        const unsigned expected=2+point_size+wide;
        uint8_t slots[PS5_TESS_CAPTURE_MAX_SLOTS];
        unsigned count=0;
        assert(ps5_tess_capture_slots(gs,slots,&count) && count==expected);
        assert(slots[0]==VARYING_SLOT_POS);
        /* st/mesa lowers a dvec2 to four 32-bit components of one slot. */
        assert(slots[count-1]==(wide ? VARYING_SLOT_VAR3 : VARYING_SLOT_VAR0));
        assert(!point_size || slots[1]==VARYING_SLOT_PSIZ);

        /* Pass 1: the evaluation shader captures whole slots. */
        nir_shader *capture=ps5_tess_capture_tes_nir(tes,slots,count);
        assert(capture && capture!=tes && !tes->xfb_info);
        nir_validate_shader(capture,"capture TES");
        const nir_xfb_info *xfb=capture->xfb_info;
        assert(xfb && xfb->buffers_written==1 && xfb->streams_written==1);
        assert(xfb->buffers[0].stride==count*16u && xfb->output_count==count);
        for(unsigned i=0;i<count;++i) {
            const nir_xfb_output_info *o=&xfb->outputs[i];
            unsigned slot=UINT32_MAX;
            for(unsigned j=0;j<count;++j) if(slots[j]==o->location) slot=j;
            assert(slot!=UINT32_MAX && o->buffer==0 && o->component_offset==0);
            assert(o->offset==slot*16u);
            assert(o->component_mask==(o->location==VARYING_SLOT_VAR0 ? 3 :
                                       o->location==VARYING_SLOT_PSIZ ? 1 : 15));
        }
        PsbcTessellationCompileOptions options={
            .input_patch_vertices=1,.offchip_workgroup_capacity_dwords=8192,.address32_hi=2
        };
        options.vertex.target=PSBC_TARGET_PS5;
        options.vertex.stage=PSBC_STAGE_VERTEX;
        options.vertex.entrypoint="main";
        options.vertex.optimise=true;
        options.vertex.ngg=true;
        options.vertex.address32_hi=2;
        options.vertex.primitive_type=4;
        options.vertex.ps5_global_streamout=true;
        options.vertex.ps5_global_primitive_query=true;
        options.vertex.vertex_attribute_count=1;
        options.vertex.vertex_attributes[0]=(PsbcVertexAttribute){
            .format=PSBC_VERTEX_FORMAT_R32G32B32A32_FLOAT,.stride=16,.alignment=4};
        PsbcTessellationOutput out={0};
        PsbcResult result=psbc_compile_nir_tessellation_pipeline(vs,tcs,capture,NULL,&options,&out);
        printf("capture pipeline %ux%u result=%d\n",shapes[s].invocations,shapes[s].vertices,result);
        assert(result==PSBC_RESULT_OK && out.runtime.valid);
        const PsbcShaderMetadata *m=&out.tes.metadata;
        assert(m->streamout_valid && m->streamout_enabled_stream_buffers_mask==1);
        assert(m->streamout_strides_dwords[0]==count*4u);
        assert(m->hardware_stage==PSBC_HW_STAGE_NGG);
        package(&out.hs,0); package(&out.tes,0);
        psbc_free_tessellation_output(&out);

        /* Pass 2: the replay vertex shader feeds the unchanged geometry shader. */
        nir_shader *replay=ps5_tess_capture_vs_nir(slots,count);
        assert(replay && replay->info.io_lowered);
        nir_validate_shader(replay,"replay VS");
        assert(replay->info.inputs_read==BITFIELD64_RANGE(VERT_ATTRIB_GENERIC0,count));
        uint64_t written=0;
        for(unsigned i=0;i<count;++i) written|=BITFIELD64_BIT(slots[i]);
        assert(replay->info.outputs_written==written);
        PsbcCompileOptions pair={
            .target=PSBC_TARGET_PS5,.stage=PSBC_STAGE_GEOMETRY,.entrypoint="main",
            .optimise=true,.ngg=true,.primitive_type=4,.address32_hi=2,
            .ps5_global_primitive_query=true,.vertex_attribute_count=count,
        };
        for(unsigned i=0;i<count;++i)
            pair.vertex_attributes[i]=(PsbcVertexAttribute){
                .location=i,.format=PSBC_VERTEX_FORMAT_R32G32B32A32_FLOAT,
                .offset=i*16u,.stride=count*16u,.alignment=4};
        PsbcShaderOutput merged={0};
        result=psbc_compile_nir_geometry_pipeline(replay,gs,&pair,&merged);
        printf("replay pipeline %ux%u result=%d\n",shapes[s].invocations,shapes[s].vertices,result);
        assert(result==PSBC_RESULT_OK);
        assert(merged.metadata.hardware_stage==PSBC_HW_STAGE_NGG);
        assert(merged.metadata.vertex_buffer_table_valid);
        const uint32_t instance=context_value(&merged.metadata,0x2e4);
        const bool per_instance=shapes[s].invocations*shapes[s].vertices>128;
        assert(G_028B90_CNT(instance)==shapes[s].invocations);
        /* Without a tessellator the per-instance subgroup mode is available. */
        assert(G_028B90_EN_MAX_VERT_OUT_PER_GS_INSTANCE(instance)==per_instance);
        package(&merged,1);
        psbc_free_output(&merged);

        /* The standalone replay shader is also compiled by the draw path. */
        PsbcCompileOptions alone={
            .target=PSBC_TARGET_PS5,.stage=PSBC_STAGE_VERTEX,.entrypoint="main",
            .optimise=true,.ngg=true,.primitive_type=4,.address32_hi=2,
            .vertex_attribute_count=count,
        };
        memcpy(alone.vertex_attributes,pair.vertex_attributes,sizeof(alone.vertex_attributes));
        PsbcShaderOutput single={0};
        assert(psbc_compile_nir(replay,&alone,&single)==PSBC_RESULT_OK);
        package(&single,0);
        psbc_free_output(&single);
        ralloc_free(replay); ralloc_free(capture); ralloc_free(gs); ralloc_free(tes);
    }
    puts("PASS capture and replay pipelines compile for 4x16, 4x128, 32x16, point size and fp64");

    /* Interfaces that cannot be replayed are refused, leaving the draw to the
     * linked pipeline. */
    {
        nir_shader *gs=many_inputs();
        uint8_t slots[PS5_TESS_CAPTURE_MAX_SLOTS]; unsigned count=0;
        assert(!ps5_tess_capture_slots(gs,slots,&count));
        ralloc_free(gs);
        /* A slot the evaluation shader never writes captures nothing. */
        nir_shader *tes=evaluation(false,false);
        const uint8_t missing[1]={VARYING_SLOT_VAR7};
        assert(!ps5_tess_capture_tes_nir(tes,missing,1));
        ralloc_free(tes);
        puts("PASS more than 16 slots and unwritten interfaces refused");
    }
    /* The capture pass draws with a fragment shader that reads nothing. */
    {
        nir_shader *fs=ps5_tess_capture_fs_nir();
        nir_validate_shader(fs,"capture FS");
        assert(!fs->info.inputs_read && !fs->info.outputs_written);
        PsbcCompileOptions options={
            .target=PSBC_TARGET_PS5,.stage=PSBC_STAGE_FRAGMENT,.entrypoint="main",
            .optimise=true,.address32_hi=2,
        };
        PsbcShaderOutput out={0};
        assert(psbc_compile_nir(fs,&options,&out)==PSBC_RESULT_OK);
        assert(!out.metadata.input_semantic_count);
        package(&out,0);
        psbc_free_output(&out);
        ralloc_free(fs);
        puts("PASS empty capture fragment shader");
    }
    ralloc_free(tcs); ralloc_free(vs);
    psbc_shutdown();
    return 0;
}
'''


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(command, log, timeout, cwd):
    with log.open("w") as stream:
        stream.write("command: " + repr(command) + "\n")
        stream.flush()
        try:
            result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                    timeout=timeout, env={**os.environ, "NIR_DEBUG": "validate"})
            status = result.returncode
        except subprocess.TimeoutExpired:
            status = 124
        stream.write(f"\nexit={status}\n")
    print(str(log) + "\n" + "\n".join(log.read_text().splitlines()[1:]), flush=True)
    return status


if __name__ == "__main__":
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    with tempfile.TemporaryDirectory(prefix="tess-capture-") as directory:
        attempt = Path(directory)
        print("Two-pass tessellation + geometry shader regression (host only)", flush=True)
        before = digest(LIB)
        cfile = attempt / "probe.c"
        cfile.write_text(code)
        obj, executable = attempt / "probe.o", attempt / "probe"
        command = ["clang-18", "-std=gnu11", "-O1", "-g", "-Wall", "-Werror",
                   "-DHAVE_ENDIAN_H=1", "-DHAVE_FUNC_ATTRIBUTE_PACKED=1", "-DHAVE_PTHREAD=1",
                   "-DHAVE_STRUCT_TIMESPEC=1", "-DHAVE_FUNC_ATTRIBUTE_UNUSED=1", "-D_GNU_SOURCE"]
        for include in ("include/mesa", "include", "src", "libpsbc", "src/amd/common",
                        "src/compiler/nir", "src/compiler"):
            command += ["-I", str(PSBC / include)]
        command += ["-I", str(ROOT / "src/platform")]
        status = run(command + ["-c", str(cfile), "-o", str(obj)], attempt / "compile.log", 45, attempt)
        package_obj = attempt / "package.o"
        if not status:
            status = run(command + ["-c", str(ROOT / "src/platform/ps5_agc_package.c"),
                                    "-o", str(package_obj)], attempt / "package-compile.log", 45, attempt)
        if not status:
            status = run(["g++", "-o", str(executable), str(obj), str(package_obj), str(LIB),
                          "-pthread", "-lm"], attempt / "link.log", 45, attempt)
        if not status:
            status = run([str(executable)], attempt / "run.log", 60, attempt)
        assert digest(LIB) == before, "host archive changed during probe"
        print(f"RESULT exit={status}; archive unchanged (host only)", flush=True)
        sys.exit(1 if status else 0)
