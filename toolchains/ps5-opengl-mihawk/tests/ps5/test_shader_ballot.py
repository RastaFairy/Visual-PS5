#!/usr/bin/env python3
"""Check the advertised ballot capability against the real PSBC backend."""

import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
screen = (ROOT / "src/gallium/ps5/ps5_screen.c").read_text()
assert "caps->shader_ballot = PS5_ENABLE_GLSL_460_CANDIDATE;" in screen

code = r'''
#include <assert.h>
#include <stdio.h>
#include "compiler/nir/nir_builder.h"
#include "psbc_compile.h"

int main(void) {
    psbc_init();
    nir_builder b = nir_builder_init_simple_shader(
        MESA_SHADER_FRAGMENT, psbc_get_nir_options(PSBC_STAGE_FRAGMENT),
        "shader-ballot");
    nir_def *lane = nir_load_subgroup_invocation(&b);
    nir_def *value = nir_iadd_imm(&b, lane, 100);
    nir_def *read = nir_read_invocation(&b, value, nir_iand_imm(&b, lane, 3));
    nir_store_output(&b, nir_vec4(&b, nir_u2f32(&b, lane),
                                  nir_u2f32(&b, read),
                                  nir_imm_float(&b, 0),
                                  nir_imm_float(&b, 1)),
                     nir_imm_int(&b, 0), .write_mask = 15,
                     .io_semantics = {.location = FRAG_RESULT_DATA0,
                                      .num_slots = 1});
    nir_shader_gather_info(b.shader, nir_shader_get_entrypoint(b.shader));
    PsbcCompileOptions options = {
        .target = PSBC_TARGET_PS5,
        .stage = PSBC_STAGE_FRAGMENT,
        .entrypoint = "main",
        .optimise = true,
        .spi_shader_col_format = 4,
    };
    PsbcShaderOutput out = {0};
    assert(psbc_compile_nir(b.shader, &options, &out) == PSBC_RESULT_OK);
    assert(out.machine_code_size);
    printf("PASS shader ballot: lane-id and read-invocation compile (%zu bytes)\n",
           out.machine_code_size);
    psbc_free_output(&out);
    ralloc_free(b.shader);
    psbc_shutdown();
}
'''

with tempfile.TemporaryDirectory() as temporary:
    temporary = Path(temporary)
    obj = temporary / "shader-ballot.o"
    executable = temporary / "shader-ballot"
    psbc = ROOT / "third_party/opengnm-psbc"
    subprocess.run([
        "clang-18", "-std=gnu11", "-Wall", "-Werror",
        "-DHAVE_ENDIAN_H=1", "-DHAVE_FUNC_ATTRIBUTE_PACKED=1",
        "-DHAVE_PTHREAD=1", "-DHAVE_STRUCT_TIMESPEC=1", "-D_GNU_SOURCE",
        "-I", str(psbc / "include/mesa"), "-I", str(psbc / "include"),
        "-I", str(psbc / "src"), "-I", str(psbc / "src/gallium/include"),
        "-I", str(psbc / "libpsbc"), "-x", "c", "-c", "-o", str(obj), "-",
    ], input=code, text=True, check=True)
    subprocess.run(["g++", "-o", str(executable), str(obj),
                    str(psbc / "libpsbc.a"), "-pthread", "-lm"], check=True)
    subprocess.run([str(executable)], check=True)
