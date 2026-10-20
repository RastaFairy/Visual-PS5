# Upstream Sokol cube

A native adaptation of Sokol's
[cube-glfw.c](https://github.com/floooh/sokol-samples/blob/8afa83928ce1870efeb0d513e7c4dce4f5db7b3e/glfw/cube-glfw.c)
sample: a rotating, depth-tested, back-face-culled cube, drawn for 180 frames at
1920x1080 before the app exits. It shows how an existing desktop sample moves to
the SDK. `prepare.py` generates the adapted source from the pinned upstream
checkouts and leaves those checkouts unchanged.

The adaptation makes six exact changes:

- a native window glue include (`native_glue.h`) in place of GLFW,
- the vecmath include path,
- a wrapped entry point,
- GLSL 410 shaders declared as 330 Core, with no shader logic changed,
- one sample instead of four,
- an error-recording logger.

Geometry, transforms, buffers, uniforms, pipeline state and draw calls are
upstream's. There is no interactive input.

```sh
python3 tools/fetch-sources.py --sokol-samples
make test-sokol-cube                # host software Mesa
make sokol-cube                     # PPSA99005 folder
```

The sample is MIT-licensed by Andre Weissflog; its bundled vecmath is used under
Mattias Gustavsson's MIT option. See [notices](../../THIRD_PARTY_NOTICES.md).
Pixel checks, readback options and history are in
[example validation](../../docs/example-validation.md#sokol-cube).
