#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile the compiler's vertex-input state setter and check binding alignments.

radv keeps one byte of alignment per vertex buffer binding. The setter must
store the smallest alignment among a binding's attributes in that byte only.
Addressing the byte array through a 32-bit pointer, as the setter once did,
clears the next three bindings, can raise a binding's alignment above one of
its attributes, and writes past the array for bindings 29 to 31. The previous
body, run through the same cases, must fail them."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = (root / 'third_party/opengnm-psbc/libpsbc/psbc_compile.c').read_text()
start = source.index('static bool psbc_apply_vertex_input_state(')
function = source[start:source.index('\n}\n', start) + 3]
assert 'uint8_t *align = &gfx->vi.vertex_binding_align[attribute->binding];' in function
assert 'uint32_t *align' not in function

CURRENT = '''
        /* One byte per binding: the smallest alignment among its attributes. */
        uint8_t *align = &gfx->vi.vertex_binding_align[attribute->binding];
        const uint8_t attribute_align = (uint8_t)MIN2(attribute->alignment, 128u);
        *align = *align ? MIN2(*align, attribute_align) : attribute_align;
'''
PREVIOUS = '''
        uint32_t *align = (uint32_t *)&gfx->vi.vertex_binding_align[attribute->binding];
        *align = *align ? MIN2(*align, attribute->alignment) : attribute->alignment;
'''
assert CURRENT in function
previous = function.replace(CURRENT, PREVIOUS).replace(
    'psbc_apply_vertex_input_state(', 'previous_apply_vertex_input_state(')

PRELUDE = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define MAX_VBS 32
#define MAX_VERTEX_ATTRIBS 32
#define PSBC_MAX_VERTEX_ATTRIBUTES 32
#define MIN2(a, b) ((a) < (b) ? (a) : (b))
#define BITFIELD_BIT(b) (1u << (b))
enum pipe_format { PIPE_FORMAT_NONE, PIPE_FORMAT_R32_FLOAT };
enum { PSBC_TARGET_PS5 = 1 };
typedef struct { uint32_t location, binding, format, offset, stride, alignment, instance_divisor; } PsbcVertexAttribute;
typedef struct { int target; uint32_t vertex_attribute_count; PsbcVertexAttribute vertex_attributes[PSBC_MAX_VERTEX_ATTRIBUTES]; } PsbcCompileOptions;
/* The vertex-input part of radv_graphics_state_key (radv_shader.h), followed
 * by a guard where the next member sits. */
struct radv_graphics_state_key {
   struct {
      uint32_t attributes_valid;
      uint32_t instance_rate_inputs;
      uint32_t instance_rate_divisors[MAX_VERTEX_ATTRIBS];
      uint8_t vertex_attribute_formats[MAX_VERTEX_ATTRIBS];
      uint32_t vertex_attribute_bindings[MAX_VERTEX_ATTRIBS];
      uint32_t vertex_attribute_offsets[MAX_VERTEX_ATTRIBS];
      uint32_t vertex_attribute_strides[MAX_VERTEX_ATTRIBS];
      uint8_t vertex_binding_align[MAX_VBS];
   } vi;
   uint32_t guard;
};
static enum pipe_format psbc_vertex_pipe_format(uint32_t format) { return format ? PIPE_FORMAT_R32_FLOAT : PIPE_FORMAT_NONE; }
'''

CASES = r'''
typedef bool (*setter)(const PsbcCompileOptions *, struct radv_graphics_state_key *);
static PsbcVertexAttribute attribute(uint32_t location, uint32_t binding, uint32_t alignment)
{
   return (PsbcVertexAttribute){ location, binding, 1, 0, 16, alignment, 0 };
}
/* Returns the number of failed expectations. */
static unsigned run(setter apply)
{
   unsigned failures = 0;
   PsbcCompileOptions options;
   struct radv_graphics_state_key key;
#define RESET() do { memset(&options, 0, sizeof(options)); options.target = PSBC_TARGET_PS5; \
                     memset(&key, 0, sizeof(key)); key.guard = 0xa5a5a5a5u; } while (0)
#define EXPECT(condition) do { if (!(condition)) ++failures; } while (0)

   /* Interleaved attributes of one binding: the smallest alignment wins. */
   RESET();
   options.vertex_attribute_count = 3;
   options.vertex_attributes[0] = attribute(0, 0, 4);
   options.vertex_attributes[1] = attribute(1, 0, 1);
   options.vertex_attributes[2] = attribute(2, 0, 2);
   EXPECT(apply(&options, &key) && key.vi.vertex_binding_align[0] == 1);

   /* A lower binding set after a higher one keeps the higher one's value. */
   RESET();
   options.vertex_attribute_count = 2;
   options.vertex_attributes[0] = attribute(0, 1, 4);
   options.vertex_attributes[1] = attribute(1, 0, 2);
   EXPECT(apply(&options, &key) && key.vi.vertex_binding_align[0] == 2 &&
          key.vi.vertex_binding_align[1] == 4);

   /* A neighbouring binding must not raise this binding's alignment. */
   RESET();
   options.vertex_attribute_count = 3;
   options.vertex_attributes[0] = attribute(0, 0, 1);
   options.vertex_attributes[1] = attribute(1, 1, 4);
   options.vertex_attributes[2] = attribute(2, 0, 4);
   EXPECT(apply(&options, &key) && key.vi.vertex_binding_align[0] == 1 &&
          key.vi.vertex_binding_align[1] == 4);

   /* The last bindings stay inside the array. */
   RESET();
   options.vertex_attribute_count = 3;
   options.vertex_attributes[0] = attribute(0, 31, 4);
   options.vertex_attributes[1] = attribute(1, 30, 2);
   options.vertex_attributes[2] = attribute(2, 29, 1);
   EXPECT(apply(&options, &key) && key.vi.vertex_binding_align[29] == 1 &&
          key.vi.vertex_binding_align[30] == 2 && key.vi.vertex_binding_align[31] == 4);
   EXPECT(key.guard == 0xa5a5a5a5u);

   /* An alignment wider than a byte stays a nonzero power of two. */
   RESET();
   options.vertex_attribute_count = 1;
   options.vertex_attributes[0] = attribute(0, 5, 256);
   EXPECT(apply(&options, &key) && key.vi.vertex_binding_align[5] == 128);

   /* Rejections are unchanged. */
   RESET();
   options.vertex_attribute_count = 1;
   options.vertex_attributes[0] = attribute(0, MAX_VBS, 4);
   EXPECT(!apply(&options, &key));
   options.vertex_attributes[0] = attribute(0, 0, 0);
   EXPECT(!apply(&options, &key));
   return failures;
}
int main(void)
{
   assert(run(psbc_apply_vertex_input_state) == 0);
   /* The 32-bit pointer fails the ordering, neighbour and bounds cases. */
   unsigned previous = run(previous_apply_vertex_input_state);
   printf("previous-failures=%u\n", previous);
   assert(previous >= 3);
   return 0;
}
'''

with tempfile.TemporaryDirectory() as temporary:
    exe = str(Path(temporary) / 'vertex-binding-alignment')
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-fno-strict-aliasing',
                    '-x', 'c', '-', '-o', exe],
                   input=PRELUDE + function + previous + CASES, text=True, check=True)
    subprocess.run([exe], check=True)
print('PASS: one byte per binding holds the smallest attribute alignment; neighbours and the '
      'bytes after the array are untouched; the 32-bit pointer fails those cases')
