#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile the actual constant-buffer setter with Mesa's reference-counting contract.

A slot may hold the last reference to the buffer that is set on it again. The
setter must take the new reference before it drops the slot's old one, as the
vertex-buffer setter does. The stub below is pipe_reference_described from Mesa
26.2 (src/gallium/auxiliary/util/u_inlines.h), assertions included. The previous
order, run through the same stub, must fail the assertion."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = (root / 'src/gallium/ps5/ps5_screen.c').read_text()
start = source.index('static void\nps5_set_constant_buffer(')
function = source[start:source.index('\n}\n', start) + 3]

KEEP = '''   struct pipe_resource *previous = state->buffer;
   state->buffer = NULL;
'''
DROP_FIRST = '''   struct pipe_resource *previous = NULL;
   pipe_resource_reference(&state->buffer, NULL);
'''
assert function.count(KEEP) == 1
assert function.rstrip().endswith('release:\n   pipe_resource_reference(&previous, NULL);\n}')
previous = function.replace(KEEP, DROP_FIRST).replace(
    'ps5_set_constant_buffer(', 'ps5_set_constant_buffer_previous(')

PRELUDE = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define PS5_ENABLE_UBO_CANDIDATE 1
#define PS5_ENABLE_GEOMETRY_CANDIDATE 1
#define PS5_ENABLE_TESSELLATION_CANDIDATE 1
#define PS5_MAX_CONSTANT_BUFFERS 13
#define PS5_MAX_CONSTANT_BUFFER_SIZE 0x10000u
#define PS5_DIRECT_ALIGNMENT 0x4000u
#define PS5_CONSTANT_DATA_OFFSET 16u
#define PS5_GEOMETRY_CONSTANT_SLOT 2
#define PS5_TESS_CTRL_CONSTANT_SLOT 3
#define PS5_TESS_EVAL_CONSTANT_SLOT 4
typedef enum { MESA_SHADER_VERTEX, MESA_SHADER_TESS_CTRL, MESA_SHADER_TESS_EVAL,
               MESA_SHADER_GEOMETRY, MESA_SHADER_FRAGMENT, MESA_SHADER_COMPUTE } mesa_shader_stage;
enum { PIPE_BUFFER };
struct pipe_reference { int64_t count; };
struct pipe_screen;
struct pipe_resource { struct pipe_reference reference; struct pipe_screen *screen; unsigned target; };
struct pipe_screen { void (*resource_destroy)(struct pipe_screen *, struct pipe_resource *); };
struct pipe_constant_buffer { struct pipe_resource *buffer; unsigned buffer_offset, buffer_size; const void *user_buffer; };
struct pipe_context { struct pipe_screen *screen; };
struct ps5_resource { struct pipe_resource base; uint8_t *data; size_t size; };
struct ps5_constant_state { bool valid, copied; unsigned size, offset; struct pipe_resource *buffer; };
struct ps5_context { struct pipe_context base; struct ps5_constant_state constants[5][PS5_MAX_CONSTANT_BUFFERS];
                     struct pipe_resource *descriptor_storage[2]; };
static size_t ps5_copied_constant_offset(unsigned slot) { (void)slot; return PS5_CONSTANT_DATA_OFFSET; }

/* pipe_reference_described, Mesa 26.2 u_inlines.h, with the same assertions */
static bool pipe_reference_described(struct pipe_reference *dst, struct pipe_reference *src)
{
   if (dst != src) {
      if (src) {
         int64_t count = ++src->count;
         assert(count != 1); /* src had to be referenced */
         (void)count;
      }
      if (dst) {
         int64_t count = --dst->count;
         assert(count != -1); /* dst had to be referenced */
         if (!count)
            return true;
      }
   }
   return false;
}
static int destroyed;
static void pipe_resource_reference(struct pipe_resource **dst, struct pipe_resource *src)
{
   struct pipe_resource *old = *dst;
   if (pipe_reference_described(old ? &old->reference : NULL, src ? &src->reference : NULL))
      old->screen->resource_destroy(old->screen, old);
   *dst = src;
}
static void destroy(struct pipe_screen *screen, struct pipe_resource *resource)
{
   (void)screen;
   ++destroyed;
   resource->reference.count = 0;
}
static struct pipe_screen screen = { destroy };
'''

CASES = r'''
int main(void)
{
   static struct ps5_context context;
   struct pipe_context *base = &context.base;
   static uint8_t memory[256];
   struct ps5_resource a = { { {1}, &screen, PIPE_BUFFER }, memory, sizeof(memory) };
   struct ps5_resource b = { { {1}, &screen, PIPE_BUFFER }, memory, sizeof(memory) };
   struct pipe_constant_buffer cb = { &a.base, 16, 64, NULL };
   struct ps5_constant_state *slot = &context.constants[1][1];
   context.base.screen = &screen;

   /* bind a: the slot takes its own reference */
   SETTER(base, MESA_SHADER_FRAGMENT, 1, &cb);
   assert(a.base.reference.count == 2 && slot->valid && slot->buffer == &a.base && slot->offset == 16);

   /* the caller drops its reference: the slot's is the last */
   a.base.reference.count = 1;
   /* the same buffer again */
   SETTER(base, MESA_SHADER_FRAGMENT, 1, &cb);
   assert(destroyed == 0 && a.base.reference.count == 1 && slot->valid && slot->buffer == &a.base);

   /* a rejected update (unaligned offset) clears the slot and releases the buffer once */
   cb.buffer_offset = 8;
   SETTER(base, MESA_SHADER_FRAGMENT, 1, &cb);
   assert(destroyed == 1 && a.base.reference.count == 0 && !slot->valid && !slot->buffer);

   /* replacing b by NULL releases only the slot's reference */
   cb = (struct pipe_constant_buffer){ &b.base, 0, 64, NULL };
   SETTER(base, MESA_SHADER_VERTEX, 2, &cb);
   assert(b.base.reference.count == 2);
   SETTER(base, MESA_SHADER_VERTEX, 2, NULL);
   assert(destroyed == 1 && b.base.reference.count == 1 && !context.constants[0][2].valid);
   puts("ok");
   return 0;
}
'''

with tempfile.TemporaryDirectory() as temporary:
    directory = Path(temporary)

    def build(name, body, setter):
        exe = str(directory / name)
        subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-label',
                        '-DSETTER=' + setter, '-x', 'c', '-', '-o', exe],
                       input=PRELUDE + body + CASES, text=True, check=True)
        return exe

    subprocess.run([build('current', function, 'ps5_set_constant_buffer')], check=True)
    old = subprocess.run([build('previous', previous, 'ps5_set_constant_buffer_previous')],
                         capture_output=True, text=True)
    assert old.returncode != 0 and 'count != 1' in old.stderr, (old.returncode, old.stderr)
print('PASS: a constant buffer set again while its slot holds the last reference keeps it; '
      'the previous order trips the reference assertion')
