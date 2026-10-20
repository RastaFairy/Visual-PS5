#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

"""Exercise the actual runtime display-mode API and its idle/ownership guards."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
egl = (root / 'src/egl/ps5_egl.c').read_text()
native = (root / 'src/platform/ps5_agc_native_runtime.c').read_text()
header = (root / 'src/platform/ps5_scanout.h').read_text()


def block(source, first_line):
    start = source.index(first_line)
    return source[start:source.index('\n#endif\n', start)]


api = block(egl, '/* Display-mode changes need a fully terminated display')
start = native.index('/* Display modes change only with no port')
idle = native[start:native.index('\n}\n', start) + 3]
# The runtime is a separate object in the SDK: EGL sees only a weak symbol.
runtime = r'''
#include "ps5_scanout.h"
int runtime_video_handle = -1, runtime_video_registered, runtime_gpu_present_buffer = -1;
int runtime_batch_active, runtime_batch_faulted;
unsigned runtime_batch_count, runtime_pending_batches;
int ps5_agc_gate2_display_idle(void);
''' + idle + r'''
void other_dimensions(unsigned *w, unsigned *h) { *w = PS5_SCANOUT_WIDTH; *h = PS5_SCANOUT_HEIGHT; }
'''
code = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "ps5_scanout.h"
#define EGLAPI
#define EGLAPIENTRY
#define EGL_TRUE 1
#define EGL_FALSE 0
#define EGL_BAD_DISPLAY 1
#define EGL_BAD_ACCESS 2
#define EGL_BAD_PARAMETER 3
typedef int EGLint;
typedef int EGLBoolean;
typedef void *EGLDisplay;
static struct { bool initialized; void *screen; unsigned contexts, surfaces; } ps5_display;
static void *ps5_window_surface;
static unsigned locks;
static int error;
#define PS5_EGL_LOCK() (++locks)
static bool ps5_valid_display(void *p, bool initialized) {
    assert(!initialized && locks); return p == &ps5_display;
}
static void ps5_set_error(int value) { error = value; }
unsigned ps5_scanout_width = PS5_SCANOUT_DEFAULT_WIDTH;
unsigned ps5_scanout_height = PS5_SCANOUT_DEFAULT_HEIGHT;
unsigned ps5_scanout_fps = PS5_SCANOUT_DEFAULT_FPS;
unsigned ps5_scanout_active_fps = PS5_SCANOUT_DEFAULT_FPS;
extern int runtime_video_handle, runtime_video_registered, runtime_gpu_present_buffer;
extern int runtime_batch_active, runtime_batch_faulted;
extern unsigned runtime_batch_count, runtime_pending_batches;
int ps5_agc_gate2_display_idle(void) __attribute__((weak));
void other_dimensions(unsigned *, unsigned *);
''' + api + r'''
static void reset_owners(void) {
    ps5_display.screen = NULL; ps5_display.contexts = ps5_display.surfaces = 0;
    ps5_display.initialized = false; ps5_window_surface = NULL;
    runtime_video_handle = runtime_gpu_present_buffer = -1;
    runtime_video_registered = runtime_batch_active = runtime_batch_faulted = 0;
    runtime_batch_count = runtime_pending_batches = 0;
}
int main(void) {
    const unsigned modes[][2] = {{1920,1080},{2560,1440},{3840,2160}};
    EGLint w = 0, h = 0, hz = 0;
    /* One SDK starts at 1080p60 with 2160p capacity. */
    assert(PS5_SCANOUT_WIDTH == 1920 && PS5_SCANOUT_HEIGHT == 1080 && !PS5_SCANOUT_HFR_REQUESTED);
    assert(eglGetDisplayModePS5(&ps5_display, &w, &h, &hz) && w == 1920 && h == 1080 && hz == 60);
    for (unsigned cycle = 0; cycle < 100; ++cycle) for (unsigned mode = 0; mode < 3; ++mode) {
        assert(eglSetDisplayModePS5(&ps5_display, modes[mode][0], modes[mode][1]));
        assert(PS5_SCANOUT_WIDTH == modes[mode][0] && PS5_SCANOUT_HEIGHT == modes[mode][1]);
        unsigned cw, ch; other_dimensions(&cw, &ch);
        assert(cw == PS5_SCANOUT_WIDTH && ch == PS5_SCANOUT_HEIGHT);
        assert(PS5_SCANOUT_TILED_BYTES <= PS5_SCANOUT_BYTES);
        assert(PS5_SCANOUT_BYTES == 0x2000000 && PS5_SCANOUT_POOL_BYTES == 0x4000000);
        const EGLint rate = cycle & 1 ? 120 : 60;
        assert(eglSetDisplayRefreshPS5(&ps5_display, rate));
        assert(PS5_SCANOUT_HFR_REQUESTED == (rate == 120));
        assert(eglGetDisplayModePS5(&ps5_display, &w, &h, &hz) &&
               w == (EGLint)modes[mode][0] && h == (EGLint)modes[mode][1] && hz == rate);
        ps5_display.initialized = true;
        assert(!eglSetDisplayModePS5(&ps5_display, 1920, 1080) && error == EGL_BAD_ACCESS);
        assert(!eglSetDisplayRefreshPS5(&ps5_display, 60) && error == EGL_BAD_ACCESS);
        assert(eglGetDisplayModePS5(&ps5_display, NULL, NULL, NULL)); /* queries stay legal */
        ps5_display.initialized = false;
        assert(PS5_SCANOUT_WIDTH == cw && PS5_SCANOUT_HEIGHT == ch);
    }
    assert(eglSetDisplayModePS5(&ps5_display, 3840, 2160));
    for (unsigned busy = 0; busy < 12; ++busy) {
        if (busy == 0) ps5_display.screen = &ps5_display;
        if (busy == 1) ps5_display.contexts = 1;
        if (busy == 2) ps5_display.surfaces = 1;
        if (busy == 3) ps5_window_surface = &ps5_display;
        if (busy == 4) runtime_video_handle = 1;
        if (busy == 5) runtime_video_registered = 1;
        if (busy == 6) runtime_gpu_present_buffer = 0;
        if (busy == 7) runtime_batch_active = 1;
        if (busy == 8) runtime_batch_count = 1;
        if (busy == 9) runtime_batch_faulted = 1;
        if (busy == 10) runtime_pending_batches = 1;
        if (busy == 11) ps5_display.initialized = true;
        assert(!eglSetDisplayModePS5(&ps5_display, 1920, 1080) && error == EGL_BAD_ACCESS);
        assert(!eglSetDisplayRefreshPS5(&ps5_display, 120) && error == EGL_BAD_ACCESS);
        assert(PS5_SCANOUT_WIDTH == 3840 && PS5_SCANOUT_HEIGHT == 2160);
        reset_owners();
    }
    assert(ps5_agc_gate2_display_idle());
    const int invalid[][2] = {{0,0},{-1920,1080},{1920,1440},{2560,2160},{3840,1080},
                              {4096,2160},{1280,720},{INT32_MAX,INT32_MAX}};
    for (unsigned i = 0; i < sizeof(invalid) / sizeof(invalid[0]); ++i) {
        assert(!eglSetDisplayModePS5(&ps5_display, invalid[i][0], invalid[i][1]) &&
               error == EGL_BAD_PARAMETER);
        assert(PS5_SCANOUT_WIDTH == 3840 && PS5_SCANOUT_HEIGHT == 2160);
    }
    const int rates[] = {0, 30, 59, 61, 90, 144, -60};
    for (unsigned i = 0; i < sizeof(rates) / sizeof(rates[0]); ++i)
        assert(!eglSetDisplayRefreshPS5(&ps5_display, rates[i]) && error == EGL_BAD_PARAMETER);
    assert(!eglSetDisplayModePS5(NULL, 1920, 1080) && error == EGL_BAD_DISPLAY);
    assert(!eglSetDisplayRefreshPS5(NULL, 60) && error == EGL_BAD_DISPLAY);
    assert(!eglGetDisplayModePS5(NULL, &w, &h, &hz) && error == EGL_BAD_DISPLAY);
    assert(PS5_SCANOUT_WIDTH == 3840 && PS5_SCANOUT_HEIGHT == 2160);
    return 0;
}
'''
with tempfile.TemporaryDirectory() as temp:
    work = Path(temp)
    (work / 'ps5_scanout.h').write_text(header)
    (work / 'modes.c').write_text(code)
    (work / 'consumer.c').write_text(runtime)
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-DPS5_DYNAMIC_SCANOUT=1',
                    '-DPS5_SCANOUT_HEIGHT=2160', '-DPS5_SCANOUT_FPS=120',
                    '-DPS5_GPU_PRESENT_BATCH=1', '-DPS5_MULTIDRAW_BATCH=1',
                    '-fsanitize=address,undefined', '-fno-sanitize-recover=all',
                    str(work / 'modes.c'), str(work / 'consumer.c'), '-o', str(work / 'modes')],
                   check=True)
    subprocess.run([str(work / 'modes')], check=True)
    # Without the capacity profile the build must refuse runtime modes.
    probe = subprocess.run(['cc', '-std=c11', '-fsyntax-only', '-DPS5_DYNAMIC_SCANOUT=1',
                            '-DPS5_SCANOUT_HEIGHT=1080', '-x', 'c', str(work / 'consumer.c')],
                           capture_output=True, text=True)
    assert probe.returncode != 0 and 'capacity profile' in probe.stderr

for name in ('eglSetDisplayModePS5', 'eglSetDisplayRefreshPS5', 'eglGetDisplayModePS5'):
    assert '(__eglMustCastToProperFunctionPointerType)' + name + ';' in egl
assert 'resource.width0 = PS5_EGL_WIDTH;' in egl and 'resource.height0 = PS5_EGL_HEIGHT;' in egl
assert 'DISPLAY_WIDTH, DISPLAY_HEIGHT, 0, 0, 0);' in native
assert 'if (runtime_video_configure_output() == 0)\n            ps5_scanout_active_fps = 120u;' in native
assert 'else if (runtime_video_restore_output() != 0)' in native
assert '#define PS5_RENDER_WIDTH PS5_SCANOUT_WIDTH' in (root / 'src/gallium/ps5/ps5_screen.h').read_text()
print('PASS: display modes 1080p/1440p/2160p at 60/120 Hz, 300 switches, 2160p capacity, '
      'invalid modes/rates and every ownership guard (ASan/UBSan)')
