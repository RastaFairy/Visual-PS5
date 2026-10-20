// PS5 OpenGL - OpenGL implementation for PlayStation 5.
// Copyright (C) 2026 BlackBearReloaded
// SPDX-License-Identifier: GPL-3.0-or-later

// Runtime display modes. Installed only in SDKs built with
// PS5_DYNAMIC_SCANOUT=1, where one SDK presents at any supported size and
// refresh rate; ps5_opengl_display.h then describes the startup mode
// (1920x1080 at 60 Hz). The PS5 scales the output to whatever the TV accepts.
//
// Change the mode only while EGL is terminated: before the first
// eglInitialize, or after destroying every context and surface and calling
// eglTerminate. GL objects do not survive that restart.
//
//   EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
//   eglSetDisplayModePS5(display, 3840, 2160);
//   eglSetDisplayRefreshPS5(display, 60);
//   eglInitialize(display, &major, &minor);   // ...then create the surface
//
// The functions are also reachable through eglGetProcAddress.

#pragma once

#include <EGL/egl.h>

#define PS5_OPENGL_DYNAMIC_DISPLAY 1
#define PS5_OPENGL_MAX_WIDTH 3840
#define PS5_OPENGL_MAX_HEIGHT 2160
#define PS5_OPENGL_MAX_FPS 120

#ifdef __cplusplus
extern "C" {
#endif

// width x height: 1920x1080, 2560x1440 or 3840x2160. EGL_BAD_ACCESS while EGL
// or a presentation still runs; EGL_BAD_PARAMETER for other sizes.
EGLBoolean eglSetDisplayModePS5(EGLDisplay display, EGLint width, EGLint height);

// 60 or 120. A display that cannot show 120 Hz keeps presenting at 60 Hz.
// Swap interval 1 paces frames to the selected rate.
EGLBoolean eglSetDisplayRefreshPS5(EGLDisplay display, EGLint refresh_hz);

// The selected size and the refresh rate the output accepted (final once a
// window surface has presented its first frame). Any pointer may be NULL.
EGLBoolean eglGetDisplayModePS5(EGLDisplay display, EGLint *width, EGLint *height,
                                EGLint *refresh_hz);

#ifdef __cplusplus
}
#endif
