#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

"""Compute publishes only unpublished CPU writes and defers invalidation to CPU access."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'src/gallium/ps5/ps5_screen.c').read_text()


def function(signature):
    start = source.index(signature)
    return source[start:source.index('\n}\n', start) + 3]


publish = function('static void\nps5_publish_compute_resource(')
invalidate = function('static void\nps5_invalidate_gpu_writes(')
launch = function('static void\nps5_launch_grid(')
# Publication precedes the dispatch; completion marks writable bindings.
assert launch.index('ps5_publish_compute_resource(buffers[i]') < \
    launch.index('ps5_agc_compute_dispatch(') < launch.index('resource->gpu_written = true;')
assert 'ps5_flush_gpu_data(table->data, PS5_COMPUTE_DESCRIPTOR_BYTES);' in launch
assert 'if (i < PS5_COMPUTE_STORAGE_SLOTS)\n         written[written_count++] = bound->buffer;' in launch
drain = function('static void\nps5_draw_batch_drain_buffer(')
assert drain.index('ps5_invalidate_gpu_writes(buffer);') > drain.index('ps5_draw_batch_retire_one_locked(true)')
# Queued dispatches run before the synchronous fallback, pin a private table
# copy plus every resource in a batch slot, and mark writes only once queued.
queue = function('static bool\nps5_queue_compute(')
assert launch.index('ps5_queue_compute(') < launch.index('ps5_agc_compute_dispatch(')
assert 'external_cpu_access)\n         return false;' in queue
assert queue.index('memcpy(copy->data, source->data, PS5_COMPUTE_DESCRIPTOR_BYTES);') < \
    queue.index('ps5_flush_gpu_data(copy->data, PS5_COMPUTE_DESCRIPTOR_BYTES);') < \
    queue.index('ps5_agc_compute_queue(') < queue.index('pinned->storage[2] = table;') < \
    queue.index('pinned->retained[pinned->retained_count++], buffers[i]') < \
    queue.index('->gpu_written = true;')
assert queue.index('if (status) {') < queue.index('pinned->storage[2] = table;')
assert queue.index('pinned->compute = true;') > queue.index('if (status) {')
# A memory barrier submits only when a pending batch entry is not a queued dispatch.
barrier = function('static void\nps5_memory_barrier(')
assert barrier.index('ps5_draw_batch_compute_only()') < barrier.index('ps5_draw_batch_submit();')
only = function('static bool\nps5_draw_batch_compute_only(')
assert 'compute &= ps5_deferred.slots[slot].compute;' in only
# CPU readback of indirect arguments waits for queued writers first.
assert launch.index('ps5_draw_batch_drain_buffer(grid->indirect);') < \
    launch.index('ps5_resource_gpu_info(grid->indirect')

code = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#define PS5_DEFERRED_DRAW_BATCH 1
enum { PIPE_BUFFER, PIPE_TEXTURE_2D };
struct pipe_resource { unsigned target; };
struct ps5_resource { struct pipe_resource base; uint8_t *data; size_t allocation_size;
    uint64_t texture_publication_epoch; size_t texture_published_bytes;
    bool external_cpu_access, gpu_written; };
static uint64_t ps5_texture_publication_epoch = 1;
static unsigned flushes, texture_publications;
static const void *flushed; static size_t flushed_bytes;
static void ps5_flush_gpu_data(const void *p, size_t n) { ++flushes; flushed = p; flushed_bytes = n; }
static void ps5_flush_texture_backing(void *batch, unsigned slot, struct ps5_resource *t,
                                      size_t bytes, bool stencil) {
    assert(!batch && !slot && !stencil && bytes == t->allocation_size); ++texture_publications;
}
''' + invalidate + publish + r'''
int main(void) {
    static uint8_t memory[4096];
    struct ps5_resource b = {.base = {PIPE_BUFFER}, .data = memory, .allocation_size = 4096};
    /* Never-published buffer: whole allocation once, then reused. */
    ps5_publish_compute_resource(&b.base, 64, 128);
    assert(flushes == 1 && flushed == memory && flushed_bytes == 4096);
    ps5_publish_compute_resource(&b.base, 64, 128);
    assert(flushes == 1);
    /* A CPU drain resets the resource epoch; a global drain bumps the epoch. */
    b.texture_publication_epoch = 0;
    ps5_publish_compute_resource(&b.base, 0, 16);
    assert(flushes == 2);
    ++ps5_texture_publication_epoch;
    ps5_publish_compute_resource(&b.base, 0, 16);
    assert(flushes == 3);
    ps5_publish_compute_resource(&b.base, 0, 16);
    assert(flushes == 3);
    /* Persistent/exported mappings publish their bound range every time. */
    b.external_cpu_access = true;
    ps5_publish_compute_resource(&b.base, 64, 128);
    ps5_publish_compute_resource(&b.base, 64, 128);
    assert(flushes == 5 && flushed == memory + 64 && flushed_bytes == 128);
    /* Textures use the shared texture publication rule. */
    struct ps5_resource t = {.base = {PIPE_TEXTURE_2D}, .data = memory, .allocation_size = 4096};
    ps5_publish_compute_resource(&t.base, 0, 0);
    assert(texture_publications == 1 && flushes == 5);
    /* GPU writes invalidate once, at the next CPU access. */
    ps5_invalidate_gpu_writes(&t);
    ps5_invalidate_gpu_writes(NULL);
    assert(flushes == 5);
    t.gpu_written = true;
    ps5_invalidate_gpu_writes(&t);
    assert(flushes == 6 && flushed == memory && flushed_bytes == 4096 && !t.gpu_written);
    ps5_invalidate_gpu_writes(&t);
    assert(flushes == 6);
    return 0;
}
'''
with tempfile.TemporaryDirectory() as temporary:
    exe = str(Path(temporary) / 'compute-publication')
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror',
                    '-fsanitize=address,undefined', '-x', 'c', '-', '-o', exe],
                   input=code, text=True, check=True)
    subprocess.run([exe], check=True)
print('PASS: compute publishes unpublished CPU writes once, exported ranges per use; '
      'GPU writes invalidate once at the next CPU access')
