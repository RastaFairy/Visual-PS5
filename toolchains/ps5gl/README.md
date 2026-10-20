# PS5GL

An OpenGL-shaped API for PS5 homebrew titles, built on top of [ps5link](https://github.com/Rufidj/ps5link-sdk)'s `ps5gpu.c` (a small renderer that drives AGC - the PS5 GPU's low-level interface - directly). It exists so code written against desktop OpenGL, such as [BennuGD2](https://github.com/Rufidj/BennuGD2)'s `libmod_3d` and its `vendor/sdl-gpu` 2D renderer, needs less rewriting to target this hardware.

Tested on a jailbroken PS5 on firmware 9.00 with etaHEN, using the same toolchain as the [SM64 PS5 port](https://github.com/Rufidj/sm64-ps5).

## What actually works, confirmed on hardware

- Real vertex/index buffers, VAOs, generic attributes, `glDrawArrays`/`glDrawElements`, instancing (done on the CPU - no GPU instancing exists on this backend).
- Textures: upload, sampling, wrap/filter state, sampler objects.
- Blend modes: alpha blending, and a **multiply** mode used to combine two textures across two draws (see "The multi-texture ceiling" below).
- **Real framebuffers**: `glGenFramebuffers`/`glFramebufferTexture2D`/`glBindFramebuffer` back an actual render-to-texture target in `ps5gpu.c` (`ps5gpu_target_create`), for both a colour attachment (the ordinary case) and a depth-only attachment (the shadow-map idiom - see its own caveat below). Confirmed by reading back rendered pixels directly from GPU memory on hardware.
- A `compat/` layer that lets real, unmodified `.c` files from BennuGD2/`libmod_3d` and `vendor/sdl-gpu` compile against this backend - see "The compat layer" below.

## What doesn't (yet)

- **No GLSL compiler.** There is no PSSL/AGC shader compiler anywhere in this toolchain - confirmed by testing every angle available (Mesa's RADV/ACO needs real AMD hardware or a from-source Mesa build; `llvm-spirv` only supports OpenCL's extended instruction set, not GLSL's). `glCompileShader` always "succeeds" without compiling anything; the only way to make a program do something other than the built-in texture×colour draw is `ps5gl_program_use_precompiled()`, handing it a hand-written AGC container.
- **The multi-texture ceiling.** AMD GCN/RDNA (PS5's GPU family) delivers at most 16 dwords of shader "user data" directly per stage. One texture + one sampler is 12 dwords - fits. Two of each is 24 - it does not, and there is no indirect descriptor-table path built yet to get around it. So a single pixel program cannot read two textures at once; `PS5GPU_BLEND_MULTIPLY` sidesteps this by drawing the same geometry twice.
- Cube maps, 3D textures, compute shaders, tessellation: declared (so calling code compiles) but not implemented - `ps5gpu.c` has no resource path for any of them.
- Multiple render targets, a caller-supplied separate depth attachment: not implemented - one colour target with its own depth buffer is what `ps5gpu_target_create()` gives you.

## The compat layer

`compat/` lets real BennuGD2/`libmod_3d` source compile against this backend with **zero changes to that source** - only the compiler's include path changes for a PS5 build. It provides:

- `GL/glew.h`, `GL/gl.h`, `GL/glext.h` - PS5GL's own `gl*` entry points are plain functions, so there is nothing for a real GLEW to load; this just satisfies the `#include`.
- `SDL2/SDL.h`, `SDL2/SDL_image.h` - a real, if narrow, slice of SDL2: surfaces, RWops, window/context calls (all no-ops - `ps5gpu_init()` already owns the one display, no window involved), and enough of the legacy pixel-format API (`SDL_Color`, `Rmask`/`Gmask`/..., `SDL_CreateRGBSurface`) for `vendor/sdl-gpu`'s own GL3/GL4 backend to compile. Image decode/encode is real, backed by `stb_image`/`stb_image_write` instead of libpng/libjpeg.

Every file in `compat/` is guarded on `__PROSPERO__` (the macro `prospero-clang` predefines) - adding this directory to a non-PS5 build's include path fails loudly at the first `#include` instead of silently misbehaving.

**Confirmed against real BennuGD2/libmod_3d source**: 78 of 80 of `libmod_3d`'s own `.c` files compile clean against this layer (the other two need `libmod_3d`'s own core header or are the author's own unfinished pseudocode). `vendor/sdl-gpu`'s actual GL3/GL4 renderer - `renderer_OpenGL_3.c`, `renderer_OpenGL_4.c`, `SDL_gpu.c`, `SDL_gpu_matrix.c`, `SDL_gpu_renderer.c`, `SDL_gpu_shapes.c` - compiles clean too (the files that don't are its *other* renderer backends - GLES, legacy GL1/2 - which a PS5 build wouldn't select anyway).

## Layout

```
backend/    ps5gpu.c/h - the renderer itself, plus its precompiled AGC shader containers
include/    ps5gl.h - the public API
src/        ps5gl.c - the implementation, ps5gl_sdl_compat.c - the SDL/SDL_image/GLEW shims
compat/     the include-path shims described above
test/       the milestone-2 test (drawing through the real gl* API)
test_fbo/          milestone 4: real framebuffers, colour attachment
test_rendertarget/ milestone 3: the raw ps5gpu_target_create() proof, before the GL wrapper existed
test_depthfbo/     milestone 5: depth-only framebuffers (the shadow-map idiom)
```

Each `test_*/` folder is a self-contained, disposable throwaway title - built, tested once on real hardware, then deleted from the console (never leave test titles installed - see the console housekeeping notes in this project's own history). Local copies stay for reference.

## Building

Needs [ps5-payload-sdk](https://github.com/ps5-payload-dev/sdk) (for `prospero-clang`), [ps5link](https://github.com/Rufidj/ps5link-sdk) (for `link_real`/`crt1_ps5.o`), the [.NET SDK](https://dotnet.microsoft.com/) + a [SharpProspero](https://github.com/SvenGDK/SharpProspero) checkout (for signing), and - like every ps5link title - a copy of `libc.prx` from a game dump for your firmware (Sony's; not included here, see ps5link's own README for why).

```sh
cd test_fbo
PS5_PAYLOAD_SDK=/path/to/ps5-payload-sdk-pacbrew \
PS5LINK=/path/to/ps5link-sdk \
SHARPPROSPERO=/path/to/SharpProspero \
SM64=/path/to/sm64-ps5/ps5 \
LIBC_PRX=/path/to/libc.prx \
./build.sh
```

Copy the resulting `out/<TITLE_ID>/` folder to `/data/homebrew/<TITLE_ID>/` on the console over FTP; [ShadowMountPlus](https://github.com/drakmor/ShadowMountPlus) registers it on the home screen.
