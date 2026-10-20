# Display modes

The release SDK is built once with **runtime display modes** (`PS5_DYNAMIC_SCANOUT=1`
on a 2160p120 capacity build). An application chooses its size and refresh rate
while it runs, so a single build serves every TV and monitor.

| Mode | Size | Refresh | Notes |
| --- | --- | --- | --- |
| 1080p | 1920×1080 | 60 / 120 Hz | Startup default (`ps5_opengl_display.h`) |
| 1440p | 2560×1440 | 60 / 120 Hz | |
| 2160p | 3840×2160 | 60 / 120 Hz | Four times the 1080p pixel count |

The PS5 scales the presented image to the connected display's own mode: a 4K
render looks sharp on a 1080p TV, and a 1080p render is upscaled on a 4K TV.

## API

`#include <ps5_opengl_display_modes.h>` (present only in runtime-mode SDKs;
test with `__has_include` to support older fixed-profile SDKs too).

```c
EGLBoolean eglSetDisplayModePS5(EGLDisplay display, EGLint width, EGLint height);
EGLBoolean eglSetDisplayRefreshPS5(EGLDisplay display, EGLint refresh_hz);
EGLBoolean eglGetDisplayModePS5(EGLDisplay display, EGLint *width, EGLint *height,
                                EGLint *refresh_hz);
```

- Sizes: 1920×1080, 2560×1440 or 3840×2160; rates: 60 or 120.
- The setters succeed only while EGL is terminated and no presentation or GPU
  batch is outstanding; otherwise they fail with `EGL_BAD_ACCESS`. Other sizes
  or rates fail with `EGL_BAD_PARAMETER`.
- A display without 120 Hz output keeps presenting at 60 Hz;
  `eglGetDisplayModePS5` reports the accepted rate once a window surface has
  presented its first frame.
- The functions are also available through `eglGetProcAddress`.

## Starting in a mode

```c
EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
eglSetDisplayModePS5(display, 3840, 2160);
eglSetDisplayRefreshPS5(display, 60);
eglInitialize(display, &major, &minor);
/* choose a config, create the window surface and context as usual */
```

The window surface reports the chosen size through `EGL_WIDTH`/`EGL_HEIGHT`.

## Changing modes while running

Every GL object belongs to the context, so a mode change is a full EGL restart:

1. Delete the application's GL objects (or be ready to recreate them).
2. `eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)`,
   `eglDestroyContext`, `eglDestroySurface`, then `eglTerminate`.
3. `eglSetDisplayModePS5` / `eglSetDisplayRefreshPS5`.
4. `eglInitialize`, recreate the surface and context, and rebuild GL objects.

Leaving a 120 Hz mode waits five seconds before the next presenter opens (the
[lifecycle safeguard](lifecycle-reopen.md)); 60 Hz restarts do not wait.

## Application metadata for 120 Hz

The console grants 120 Hz output only to titles that declare it: set bits
`0x80040` in `attribute3` of the title's `sce_sys/param.json`. Without them,
`sceVideoOutConfigureOutput` refuses the high-refresh mode and presentation stays
at 60 Hz (`eglGetDisplayModePS5` reports 60). `tools/native-display-metadata.py
--fps 120 <param.json>` sets the bits, and the example packaging does so
automatically for runtime display-mode SDKs. Declaring the capability does not
force 120 Hz; the app still chooses its rate with `eglSetDisplayRefreshPS5`.

## Capacity

Display buffers and arena offsets stay at the 2160p size in every mode, so the
runtime-mode SDK reserves the same memory as a fixed 4K120 build.
