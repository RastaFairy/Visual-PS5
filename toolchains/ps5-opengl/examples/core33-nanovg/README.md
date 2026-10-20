# NanoVG integration

Runs unmodified [NanoVG](https://github.com/memononen/nanovg) at
`ce3bf745eb2d2dbc14a50bf2446783f691ac4353` (zlib license) with its GL3 backend,
keeping antialiasing, stencil strokes, UBOs and debug checks. Only the EGL entry
point, build glue and test content are project-owned. NanoVG's GL3 backend
targets 3.3 Core, which the SDK's OpenGL 4.6 driver runs unchanged.

`main.c` renders three frames at 320x240 and 640x480, recreating the renderer
between them. The frames cover premultiplied blending, a stencil-cut hole,
self-intersecting stencil strokes, shader clipping, a nearest-filtered image and
a gradient. Each frame is checked against pixel probes, then the app exits.

```sh
make source-fetch
make sdk
bash tools/test-nanovg-host.sh      # host software Mesa
make nanovg                         # PPSA99005 folder
```

Acceptance criteria and the native run procedure are in
[example validation](../../docs/example-validation.md#nanovg).
