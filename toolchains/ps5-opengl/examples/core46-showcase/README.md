# OpenGL 4.6 showcase

The project's demo app. Every SDK release attaches it, built against that SDK, as
`ps5-opengl-showcase-<version>-PPSA99005.zip`: extract it and upload the
`PPSA99005` folder to `/data/homebrew/`. It appears on the home screen as
**PS5 OpenGL Showcase** with its own icon, backgrounds and selection music
(`sce_sys/` in this directory).

A GPU-driven scene that exercises the modern OpenGL 4.6 feature set at
**3840x2160 and 120 FPS** on a display that takes 4K at 120 Hz (119.9 FPS
measured on PS5 with SDK 1.0.0), using only public OpenGL/EGL interfaces:

- **Compute particles:** 262,144 particles in a shader storage buffer, advected by
  a flow field in a compute shader and respawned along a glowing torus knot, drawn
  as vertex-pulled camera-facing quads with additive HDR blending.
- **GPU-driven instancing:** a compute pass animates 8,192 gems and chrome cubes,
  culls them against the view frustum and appends survivors to two indirect
  commands with atomics; one `glMultiDrawElementsIndirectCount` draws both, and
  the vertex shader picks each material with `gl_DrawID` and `gl_BaseInstance`.
- **Lighting:** GGX physically based shading with three orbiting coloured lights,
  an iridescent knot with light pulses, faceted gems from screen-space derivatives
  and a procedural aurora sky with stars.
- **Texturing:** a mipmapped floor grid sampled with 16x anisotropic filtering
  (`GL_TEXTURE_MAX_ANISOTROPY`, core in 4.6).
- **Post-processing:** an RGBA16F HDR target, a bloom chain of fullscreen passes
  (prefilter, 6 downsample and tent upsample levels), ACES tone mapping, vignette
  and film grain.
- **HUD:** resolution, live frame rate and feature list drawn in the composite
  shader from a 5x7 bitmap-font texture.
- **Display modes:** asks for 4K at 120 Hz with `eglSetDisplayModePS5` and
  `eglSetDisplayRefreshPS5` when the SDK provides them (0.5.0 and later), and
  shows the accepted refresh rate in the HUD. A display without 120 Hz runs at 60.

Everything is created with direct state access (`glCreate*`, `glNamed*`).

## Reaching 4K120

- **Declare high frame rate.** The title's `param.json` carries the `attribute3`
  bits `0x80040`; without them the console refuses 120 Hz output and the driver
  stays at 60 Hz. The example packaging sets them for runtime display-mode SDKs.
- **Compute is cheap to issue.** A dispatch is queued behind earlier draws in the
  driver's batch without a CPU wait, so it costs about 25-35 us of CPU. SDKs up to
  0.5.0 ran each dispatch synchronously (about 1.1 ms), which is why bloom uses
  fullscreen passes. Build with `SHOWCASE_CFLAGS=-DSHOWCASE_COMPUTE_BLOOM=1` for
  the 11-dispatch compute bloom: 0.37 ms of CPU per frame at 120 FPS, against
  12.6 ms and 48 FPS with the synchronous path.

The log prints the CPU time per stage every two seconds, for example
`cpu-ms compute=0.03 scene=5.11 bloom=0.35 composite=2.36 present=0.48`.

## Build

With a downloaded SDK 0.5.0 (or `make sdk-gl46` first):

```sh
PS5_OPENGL_PREFIX=/path/to/ps5-opengl-sdk-0.5.0/sdk make showcase
```

Deploy `build/native-app/PPSA99005/dist/PPSA99005` and launch it as a registered
title. It runs until closed and logs `[ps5-gl46-showcase] ... fps=...` every five
seconds. Compile-time options: `SHOWCASE_WIDTH`/`SHOWCASE_HEIGHT` (display mode),
`SHOWCASE_PARTICLES`, `SHOWCASE_SECONDS` (0 runs until closed),
`SHOWCASE_COMPUTE_BLOOM` and `SHOWCASE_CAPTURE_FRAME` (writes that frame to
`SHOWCASE_CAPTURE_PATH`, `/app0/showcase.ppm` by default, to check the picture
without looking at the display), passed through `SHOWCASE_CFLAGS`.

On a connection that carries 120 Hz only at 1080p the console scales the 4K
picture down and the frame rate drops to about 95 FPS.

## Host preview

The same source renders off-screen with desktop Mesa, which is how the scene was
tuned:

```sh
cc -std=c11 -O2 -DSHOWCASE_HOST_PREVIEW=120 -DSHOWCASE_WIDTH=1920 -DSHOWCASE_HEIGHT=1080 \
   examples/core46-showcase/main.c -o showcase -lEGL -lGL -lm
EGL_PLATFORM=surfaceless MESA_GL_VERSION_OVERRIDE=4.6 ./showcase   # writes showcase.ppm
```

## Releasing

`sce_sys/param.json` holds the demo app's name and its content version. The
content version is what a console reports for an installed app and what the
[homebrew catalog](https://homebrew.page) reads to tell that a release is
newer, so each release raises it: release `X.Y.Z` carries `0X.00Y.00Z`.
`make demo` refuses a release version whose content version does not match.
