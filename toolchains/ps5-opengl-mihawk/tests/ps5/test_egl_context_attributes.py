#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

"""Exercise the real EGL context attribute parser: flags, robustness, no-error."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "src/egl/ps5_egl.c").read_text()
begin = source.index("struct ps5_egl_context_request {")
parser = source[begin:source.index("EGLAPI EGLContext EGLAPIENTRY\neglCreateContext(", begin)]
code = r"""
#include <assert.h>
#include <string.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#define ST_CONTEXT_FLAG_DEBUG 1u
#define ST_CONTEXT_FLAG_FORWARD_COMPATIBLE 2u
#define ST_CONTEXT_FLAG_NO_ERROR 4u
#define PIPE_CONTEXT_ROBUST_BUFFER_ACCESS 16u
#define PIPE_CONTEXT_LOSE_CONTEXT_ON_RESET 32u
""" + parser + r"""
static EGLint parse(const EGLint *list, struct ps5_egl_context_request *request) {
    return ps5_context_attributes(list, request);
}
int main(void) {
    struct ps5_egl_context_request r;
    assert(parse(NULL, &r) == EGL_SUCCESS && !r.major && !r.st_flags && !r.pipe_flags);
    const EGLint core46[] = {EGL_CONTEXT_MAJOR_VERSION_KHR, 4, EGL_CONTEXT_MINOR_VERSION_KHR, 6,
        EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR,
        EGL_CONTEXT_FLAGS_KHR, EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR | EGL_CONTEXT_OPENGL_ROBUST_ACCESS_BIT_KHR,
        EGL_CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY_KHR, EGL_LOSE_CONTEXT_ON_RESET_KHR, EGL_NONE};
    assert(parse(core46, &r) == EGL_SUCCESS && r.major == 4 && r.minor == 6);
    assert(r.profile_mask == EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR);
    assert(r.st_flags == ST_CONTEXT_FLAG_DEBUG);
    assert(r.pipe_flags == (PIPE_CONTEXT_ROBUST_BUFFER_ACCESS | PIPE_CONTEXT_LOSE_CONTEXT_ON_RESET));
    /* The EXT names; no notification is the default strategy. */
    const EGLint ext[] = {EGL_CONTEXT_OPENGL_ROBUST_ACCESS_EXT, EGL_TRUE,
        EGL_CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY_EXT, EGL_NO_RESET_NOTIFICATION_KHR, EGL_NONE};
    assert(parse(ext, &r) == EGL_SUCCESS && r.pipe_flags == PIPE_CONTEXT_ROBUST_BUFFER_ACCESS);
    const EGLint forward[] = {EGL_CONTEXT_FLAGS_KHR, EGL_CONTEXT_OPENGL_FORWARD_COMPATIBLE_BIT_KHR, EGL_NONE};
    assert(parse(forward, &r) == EGL_SUCCESS && r.st_flags == ST_CONTEXT_FLAG_FORWARD_COMPATIBLE);
    const EGLint no_error[] = {EGL_CONTEXT_OPENGL_NO_ERROR_KHR, EGL_TRUE, EGL_NONE};
    assert(parse(no_error, &r) == EGL_SUCCESS && r.st_flags == ST_CONTEXT_FLAG_NO_ERROR && !r.pipe_flags);
    const EGLint off[] = {EGL_CONTEXT_OPENGL_NO_ERROR_KHR, EGL_FALSE,
        EGL_CONTEXT_OPENGL_ROBUST_ACCESS_EXT, EGL_FALSE, EGL_NONE};
    assert(parse(off, &r) == EGL_SUCCESS && !r.st_flags && !r.pipe_flags);
    /* No-error excludes debug and robust access. */
    const EGLint no_error_debug[] = {EGL_CONTEXT_OPENGL_NO_ERROR_KHR, EGL_TRUE,
        EGL_CONTEXT_FLAGS_KHR, EGL_CONTEXT_OPENGL_DEBUG_BIT_KHR, EGL_NONE};
    assert(parse(no_error_debug, &r) == EGL_BAD_MATCH);
    const EGLint no_error_robust[] = {EGL_CONTEXT_OPENGL_ROBUST_ACCESS_EXT, EGL_TRUE,
        EGL_CONTEXT_OPENGL_NO_ERROR_KHR, EGL_TRUE, EGL_NONE};
    assert(parse(no_error_robust, &r) == EGL_BAD_MATCH);
    /* Unknown names, flag bits and values are refused. */
    const EGLint unknown[] = {EGL_WIDTH, 1, EGL_NONE};
    const EGLint bad_flag[] = {EGL_CONTEXT_FLAGS_KHR, 8, EGL_NONE};
    const EGLint bad_strategy[] = {EGL_CONTEXT_OPENGL_RESET_NOTIFICATION_STRATEGY_KHR, 1, EGL_NONE};
    const EGLint bad_no_error[] = {EGL_CONTEXT_OPENGL_NO_ERROR_KHR, 2, EGL_NONE};
    const EGLint bad_robust[] = {EGL_CONTEXT_OPENGL_ROBUST_ACCESS_EXT, 2, EGL_NONE};
    assert(parse(unknown, &r) == EGL_BAD_ATTRIBUTE && parse(bad_flag, &r) == EGL_BAD_ATTRIBUTE);
    assert(parse(bad_strategy, &r) == EGL_BAD_ATTRIBUTE && parse(bad_no_error, &r) == EGL_BAD_ATTRIBUTE);
    assert(parse(bad_robust, &r) == EGL_BAD_ATTRIBUTE);
    return 0;
}
"""
driver = (root / "src/gallium/ps5/ps5_screen.c").read_text()
create = driver[driver.index("ps5_context_create(struct pipe_screen *screen, void *priv, unsigned flags)"):][:900]
assert "PIPE_CONTEXT_ROBUST_BUFFER_ACCESS" in create and "PIPE_CONTEXT_LOSE_CONTEXT_ON_RESET" in create
assert "attribs.context_flags = pipe_flags;" in source
assert '"EGL_KHR_create_context EGL_KHR_create_context_no_error "' in source
assert '"EGL_EXT_create_context_robustness EGL_KHR_no_config_context "' in source
with tempfile.TemporaryDirectory() as temporary:
    executable = Path(temporary) / "egl-context-attributes"
    subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror",
                    "-I" + str(root / "third_party/mesa-26.2.0/include"),
                    "-x", "c", "-o", str(executable), "-"], input=code, text=True, check=True)
    subprocess.run([str(executable)], check=True)
print("PASS: EGL context attributes map debug, forward-compatible, robust-access, reset-notification "
      "and no-error requests and refuse invalid combinations")
