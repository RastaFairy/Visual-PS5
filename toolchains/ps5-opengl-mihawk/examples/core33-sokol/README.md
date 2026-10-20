# Sokol integration

Runs unmodified [Sokol](https://github.com/floooh/sokol) `sokol_gfx.h` at
`48c85905aeaa1350feb17515961aecb6c75447d8` (zlib license) with its GL backend
and debug validation. The EGL entry point, scene and pixel oracle are
project-owned.

The SDK ships OpenGL 4.6 headers. `main.c` undefines two 4.x header macros
before including Sokol, which selects Sokol's existing GL 3.3 paths, as an
application with a 3.3-only loader would get. No GL function is stubbed and no
Sokol code is changed; the SDK's OpenGL 4.6 driver runs those paths unchanged.

`main.c` renders three frames at 320x240, 640x480 and 320x240, recreating the
renderer and resources each time. The frames draw an indexed, textured quad with
instancing, uniforms, nearest samplers, alpha blending and scissor, and compare
every pixel with a CPU oracle before the app exits.

```sh
make source-fetch
make sdk
bash tools/test-sokol-host.sh       # host software Mesa
make sokol                          # PPSA99005 folder
```

Acceptance criteria and the native run procedure are in
[example validation](../../docs/example-validation.md#sokol).
