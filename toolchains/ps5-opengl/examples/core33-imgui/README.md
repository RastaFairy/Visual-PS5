# Dear ImGui integration

Runs unmodified [Dear ImGui](https://github.com/ocornut/imgui/tree/v1.91.9b)
v1.91.9b (commit `f5befd2d29e66809cd1110a152e375a7f1981f06`, MIT) with its
upstream OpenGL3 backend. The code shows:

- EGL window and context setup.
- The backend's supported custom-loader option, with no backend patch. The SDK
  exports every public GL function, so no private GPU header is needed.
- Font upload, draw-list rendering and presentation.

ImGui's backend targets a 3.3 Core context and `#version 330 core` shaders; the
SDK's OpenGL 4.6 driver runs them unchanged.

| File | Purpose |
| --- | --- |
| `main.cpp` | Renderer check: six frames at 320x240 and 640x480 compared with a pixel oracle, then exit |
| `tv_demo.h` | Fullscreen interactive demo: text, shapes, widgets and D-pad/Cross/Circle navigation |
| `lifecycle.cpp` | Three complete EGL sessions in one process |
| `benchmark.h`, `benchmark_timing.h` | Window and offscreen timing modes |

```sh
make source-fetch
make sdk
make imgui-demo                     # interactive TV demo as PPSA99005
bash tools/test-imgui-host.sh       # renderer check on host software Mesa
```

Acceptance criteria, native run procedures and benchmarks are in
[example validation](../../docs/example-validation.md#dear-imgui).
