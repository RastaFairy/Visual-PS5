# OpenGL 4.6 compute cubes

A visible 30-second animation of 256 cubes driven entirely through public
OpenGL/EGL interfaces. A GLSL 4.60 compute shader writes per-instance state to
an SSBO; the graphics pipeline consumes it after an explicit memory barrier and
renders the scene with one indirect instanced draw per frame. Resources use the
OpenGL direct-state-access API.

Build the native `PPSA99005` folder with a downloaded SDK (without
`PS5_OPENGL_PREFIX` it links the source-tree runtime instead):

```sh
PS5_OPENGL_PREFIX=/path/to/ps5-opengl-sdk-<version>/sdk make gl46-demo
```

The [showcase](../core46-showcase/README.md) builds on the same compute-to-draw
pattern at a larger scale.

Deploy and launch the generated folder through the native-title protocol. A
successful natural completion logs `[ps5-gl46-demo] ... result=PASS`.
