#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

"""Check the existing app-heap wrappers, not the platform allocator implementation."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = (root / "native-app/app_heap.c").read_text()
wrappers = source[source.index("void *__real_malloc(size_t size);"):]
code = r'''
#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
static unsigned maps, unmaps, creates, real_calls[6], owned_calls[6];
static int mode, allocation_failure;
static void *pool;
static size_t used;
#define MIB (1024u*1024u)
/* Modes 0-2: the default 128 MiB heap. Modes 3-4: a 512 MiB heap, which is
 * taken from direct memory (3) or, failing that, from halving mmap sizes (4). */
static void *test_map(void *p,size_t n,int prot,int flags,int fd,off_t offset) {
    assert(!p && prot == (PROT_READ|PROT_WRITE));
    assert(flags == (MAP_PRIVATE|MAP_ANON) && fd == -1 && offset == 0);
    assert(mode != 3);
    assert(n == (mode == 4 ? (512u*MIB) >> maps : 128u*MIB));
    ++maps;
    if (mode == 1 || (mode == 4 && n != 128u*MIB)) return MAP_FAILED;
    pool=mmap(p,n,prot,flags,fd,offset); assert(pool != MAP_FAILED); return pool;
}
static unsigned direct_allocations, direct_maps;
int64_t sceKernelGetDirectMemorySize(void) { assert(mode >= 3); return INT64_C(1) << 33; }
int32_t sceKernelAllocateDirectMemory(int64_t start,int64_t end,size_t n,size_t alignment,
                                      int type,int64_t *physical) {
    assert(mode >= 3 && !start && end == INT64_C(1) << 33 && n == 512u*MIB);
    assert(alignment == 2u*MIB && type == 12 && physical);
    ++direct_allocations;
    if (mode == 4) return -1;
    *physical=0x40000000; return 0;
}
int32_t sceKernelMapDirectMemory(void **address,size_t n,int prot,int flags,
                                 int64_t physical,size_t alignment) {
    assert(mode == 3 && address && !*address && n == 512u*MIB);
    assert(prot == (PROT_READ|PROT_WRITE) && !flags && physical == 0x40000000 && alignment == 2u*MIB);
    ++direct_maps;
    pool=mmap(NULL,n,prot,MAP_PRIVATE|MAP_ANON,-1,0); assert(pool != MAP_FAILED);
    *address=pool; return 0;
}
static int test_unmap(void *p,size_t n) { assert(p == pool); ++unmaps; return munmap(p,n); }
#define mmap test_map
#define munmap test_unmap
''' + wrappers + r'''
#undef mmap
#undef munmap
/* Fresh blocks hold garbage, as recycled heap memory does. The foreign heap
 * reports 16 usable bytes for every block, so none is smaller. */
static void *dirty(void *p,size_t n) { if (p) memset(p,0xcc,n); return p; }
static size_t foreign(size_t n) { return n < 16 ? 16 : n; }
void *__real_malloc(size_t n) { ++real_calls[0]; return dirty(malloc(foreign(n)),foreign(n)); }
void *__real_calloc(size_t n,size_t s) { ++real_calls[1]; return calloc(n,s); }
void *__real_realloc(void *p,size_t n) {
    ++real_calls[2];
    char *q=dirty(malloc(foreign(n)),foreign(n)); assert(q); memcpy(q,p,16); free(p); return q;
}
void __real_free(void *p) { ++real_calls[3]; assert(!ps5_heap_owns(p)); free(p); }
int __real_posix_memalign(void **p,size_t a,size_t n) {
    ++real_calls[4];
    int result=posix_memalign(p,a,foreign(n)); if (!result) dirty(*p,foreign(n)); return result;
}
size_t __real_malloc_usable_size(const void *p) { assert(p && !ps5_heap_owns(p)); ++real_calls[5]; return 16; }
void *sceLibcMspaceCreate(const char *name,void *base,size_t n,unsigned flags) {
    assert(!strcmp(name,"PS5-OpenGL") && base == pool && n == PS5_OPENGL_HEAP_SIZE && !flags);
    ++creates;
    /* Reentrant allocation during initialization must stay on the real heap. */
    void *p=__wrap_malloc(7); assert(p && !ps5_heap_owns(p)); __wrap_free(p);
    return mode == 2 ? NULL : base;
}
static void *allocate(size_t n,size_t alignment) {
    if (allocation_failure || n > PS5_OPENGL_HEAP_SIZE) return NULL;
    used=(used+sizeof(size_t)+alignment-1)&~(alignment-1);
    assert(used <= PS5_OPENGL_HEAP_SIZE-n);
    void *p=(char *)pool+used; used += n ? n : 1;
    memcpy((char *)p-sizeof(size_t),&n,sizeof(n));
    return p;
}
void *sceLibcMspaceMalloc(void *space,size_t n) { assert(space == pool); ++owned_calls[0]; return dirty(allocate(n,16),n); }
void *sceLibcMspaceCalloc(void *space,size_t n,size_t s) {
    assert(space == pool); ++owned_calls[1];
    if (s && n > SIZE_MAX/s) return NULL;
    void *p=allocate(n*s,16); if (p) memset(p,0,n*s); return p;
}
void *sceLibcMspaceRealloc(void *space,void *p,size_t n) {
    assert(space == pool && ps5_heap_owns(p)); ++owned_calls[2];
    if (allocation_failure || !n) return NULL;
    void *q=dirty(allocate(n,16),n);
    if (q) {
        size_t before=sceLibcMspaceMallocUsableSize(p);
        memcpy(q,p,before<n ? before : n);
    }
    return q;
}
void sceLibcMspaceFree(void *space,void *p) { assert(space == pool && ps5_heap_owns(p)); ++owned_calls[3]; }
int sceLibcMspacePosixMemalign(void *space,void **p,size_t a,size_t n) {
    assert(space == pool); ++owned_calls[4];
    if (a < sizeof(void *) || (a&(a-1))) return EINVAL;
    void *q=dirty(allocate(n,a),n); if (!q) return ENOMEM; *p=q; return 0;
}
size_t sceLibcMspaceMallocUsableSize(const void *p) {
    assert(ps5_heap_owns(p)); ++owned_calls[5];
    size_t n; memcpy(&n,(const char *)p-sizeof(size_t),sizeof(n)); return n;
}
int main(int argc,char **argv) {
    assert(argc == 2); mode=atoi(argv[1]);
    void *p=__wrap_malloc(16); assert(p);
    const unsigned char fresh = ps5_opengl_heap_zero_fill ? 0 : 0xcc;
#define FRESH(q,first,last) for (unsigned i=first;i<last;++i) assert(((unsigned char *)(q))[i] == fresh)
    FRESH(p,0,16);
    const int owned = mode == 0 || mode >= 3;
    const unsigned expected_maps = mode == 3 ? 0 : mode == 4 ? 3 : 1;
    assert(ps5_heap_owns(p) == owned);
    assert(maps == expected_maps && creates == (mode != 1) && unmaps == (mode == 2));
    assert(direct_allocations == (mode >= 3) && direct_maps == (mode == 3));
    if (owned) assert(PS5_OPENGL_HEAP_SIZE == (mode == 3 ? 512u*MIB : 128u*MIB));
    memset(p,0xa5,16);
    void *q=__wrap_realloc(p,32); assert(q);
    FRESH(q,16,32);
    if (owned) {
        assert(q != p && atomic_load(&ps5_heap_live_bytes) == 32);
        for (unsigned i=0;i<16;++i) assert(((unsigned char *)q)[i] == 0xa5);
        q=__wrap_realloc(q,8); assert(q && atomic_load(&ps5_heap_live_bytes) == 8);
    }
    __wrap_free(q);
    q=__wrap_calloc(4,4); assert(q);
    for (unsigned i=0;i<16;++i) assert(((unsigned char *)q)[i] == 0);
    __wrap_free(q);
    assert(!__wrap_posix_memalign(&q,64,16) && !((uintptr_t)q%64));
    FRESH(q,0,16);
    assert(__wrap_malloc_usable_size(q) == 16); __wrap_free(q);
    q=__wrap_realloc(NULL,8); assert(q); __wrap_free(q); __wrap_free(NULL);
    /* Foreign allocations keep their original realloc/free/usable-size owner. */
    p=__real_malloc(16); assert(p && !ps5_heap_owns(p));
    assert(__wrap_malloc_usable_size(p) == 16);
    p=__wrap_realloc(p,32); assert(p); FRESH(p,16,32); __wrap_free(p);
    if (owned) {
        assert(!atomic_load(&ps5_heap_live_bytes) && !atomic_load(&ps5_heap_blocks));
        assert(atomic_load(&ps5_heap_peak_bytes) == 32);
        for (unsigned i=0;i<6;++i) assert(owned_calls[i]);
        unsigned real_malloc=real_calls[0], real_memalign=real_calls[4];
        p=__wrap_malloc(16); assert(p && ps5_heap_owns(p)); allocation_failure=1;
        memset(p,0x5a,16);
        /* An exhausted owned heap spills to the libc heap; every block is
         * still freed and resized by the heap that owns its address. */
        q=__wrap_malloc(16);
        assert(q && !ps5_heap_owns(q) && real_calls[0] == real_malloc+1);
        FRESH(q,0,16);
        __wrap_free(q);
        q=__wrap_realloc(p,32); /* moves the owned block to the libc heap */
        assert(q && !ps5_heap_owns(q) && real_calls[0] == real_malloc+2);
        for (unsigned i=0;i<16;++i) assert(((unsigned char *)q)[i] == 0x5a);
        FRESH(q,16,32);
        assert(!atomic_load(&ps5_heap_live_bytes) && !atomic_load(&ps5_heap_blocks));
        __wrap_free(q);
        q=NULL;
        assert(!__wrap_posix_memalign(&q,64,16) && q && !ps5_heap_owns(q));
        assert(!((uintptr_t)q%64) && real_calls[4] == real_memalign+1);
        FRESH(q,0,16);
        __wrap_free(q);
        assert(atomic_load(&ps5_heap_failures) == 3);
        allocation_failure=0;
        p=__wrap_malloc(16); assert(p && !__wrap_realloc(p,0));
        assert(atomic_load(&ps5_heap_ambiguous_zero_reallocs) == 1);
        __wrap_free(p); /* This mock's realloc(p,0) leaves p alive. */
        ps5_opengl_heap_snapshot("host",0);
        assert(!ps5_heap_owns(NULL));
        assert(!ps5_heap_owns((void *)((uintptr_t)pool-1)));
        assert(!ps5_heap_owns((void *)((uintptr_t)pool+PS5_OPENGL_HEAP_SIZE)));
        assert(munmap(pool,PS5_OPENGL_HEAP_SIZE) == 0); /* Host-only teardown. */
    } else {
        for (unsigned i=0;i<6;++i) assert(!owned_calls[i] && real_calls[i]);
        assert(atomic_load(&ps5_heap_state) == -1 && !ps5_heap_base);
        assert(!atomic_load(&ps5_heap_live_bytes) && !atomic_load(&ps5_heap_blocks));
    }
    /* Failure is not repeatedly retried by every allocation. */
    assert(maps == expected_maps && direct_allocations == (mode >= 3));
    puts("app-heap: PASS wrapper routing, initialization/reentrancy/failure, owned and foreign allocations");
}
'''
default_size = "const size_t ps5_opengl_heap_size = 128u * 1024u * 1024u;"
assert code.count(default_size) == 1
# A title that reserves more than the flexible-memory budget, as the CTS runner does.
large = code.replace(default_size, "const size_t ps5_opengl_heap_size = 512u * 1024u * 1024u;")
default_fill = "const int ps5_opengl_heap_zero_fill = 0;"
assert code.count(default_fill) == 1
# A title that asks for zero-filled heap memory, as the CTS runner does.
zero = code.replace(default_fill, "const int ps5_opengl_heap_zero_fill = 1;")
with tempfile.TemporaryDirectory() as temporary:
    for name, program, modes in (("app-heap", code, (0, 1, 2)), ("app-heap-large", large, (3, 4)),
                                 ("app-heap-zero", zero, (0, 1, 2))):
        executable = str(Path(temporary) / name)
        subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror",
                        "-fsanitize=address,undefined", "-g", "-x", "c", "-o", executable, "-"],
                       input=program, text=True, check=True)
        for mode in modes:
            subprocess.run([executable, str(mode)], cwd=temporary, check=True)
