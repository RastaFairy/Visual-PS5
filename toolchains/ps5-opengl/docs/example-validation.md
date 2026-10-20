# Example validation procedures

The examples double as renderer-compatibility checks and benchmarks. This page
keeps their acceptance criteria, native run procedures and measurement
methodology. Each example's README covers what it shows and how to build it.

## Textured cubes benchmark

Source: [examples/core33-cubes](../examples/core33-cubes/README.md).

Standard OpenGL 3.3 shaders, perspective, directional lighting, depth testing,
two procedural textures and rotating cubes. No assets or additional dependencies.
The native app presents on the TV; automated validation uses numerical probes,
not screenshots or Remote Play.

Run `make cubes` to build PPSA99005 using the current source runtime; this does
not modify the installed SDK. Follow the normal folder deployment and testing
protocol. Host reference: `make test-cubes` (requires the existing SDK headers
and host software Mesa).

Three 1080p workloads render 1, 8 or 32 cubes (12 triangles per cube), first
using ordinary draws (`mode=0`), then one `glDrawArraysInstanced` (`mode=1`).
Both paths use the same shaders, lighting, geometry, alternating materials and
object positions. Instancing reads a per-instance placement attribute instead
of changing object uniforms. The two textures stay bound in both modes.
Each workload has two warm-up frames and eight measured frames. The short low-poly scene measures
draw-call overhead, **not a full game's expected FPS or maximum GPU throughput**.
Different object counts also change coverage; it is not a fixed-fill-rate test.

Frame timings include color/depth clear, draws, one `glFinish`, and EGL swap.
Numerical depth/texture checks run before and after each workload, outside the
timed interval: 668 probes in total. Host tests deliberately disable depth,
upload the wrong texture or omit instances and require these checks to fail. Do not use host timings
as PS5 results. CPU wall-time throughput is not a TV refresh-rate measurement.

Audit a saved native receipt:

```sh
python3 tools/summarize-cubes.py results/your-cycle-opengl.log
```

Require all probes, all 48 measured frames, cleanup, exact-title teardown and
healthy post-run services. Eligible ordinary draws use bounded batching by
default; see [Performance](performance.md) for measured results and
the synchronous diagnostic opt-out. This reduces submission overhead but does
not convert ordinary draws into instancing. Applications must group compatible
objects themselves to use the instanced path.
The audit tool also accepts the original ordinary-only baseline receipts.

### Opt-in matched profile

The historical benchmark and its receipt format remain the default. A separate
`egl_public_core33_cubes_profile.o` target measures one chosen workload for **30
seconds per draw mode**, after 30 warm-up frames. It uses the same two 2x2
procedural textures, lighting, positions and frame-indexed rotation in ordinary
and instanced paths. Choose 32, 128 (default), or 512 visible cubes. Larger counts
shrink the grid spacing and cubes to keep an approximately constant screen
footprint; this isolates draw overhead more usefully than adding offscreen cubes.
It remains a low-poly workload, not a texture-bandwidth test or a real game.

Two completion modes are explicitly identified in every profile receipt:

- `PS5_CUBES_SWAP_COMPLETED=0`: issue draws, `glFinish`, then swap. This retains
  the historical pre-swap completion boundary in a longer matched profile.
- `PS5_CUBES_SWAP_COMPLETED=1` (native target default): issue draws and swap, then
  check EGL/GL errors and native draw status. The inspected PS5 EGL implementation
  uses `ST_FLUSH_WAIT` and native presentation inside swap. This mode permits
  batching presentation with the draws. It is **not** a general claim that EGL
  swap on every platform completes GPU work. The host pbuffer adds a post-swap
  `glFinish` and labels its receipts `host=1`.

Both modes retain before/after texture/depth probes and checked cleanup. Native
profiles additionally verify the actual driver draw-counter delta, including
oracle and warm-up frames. The first excluded oracle frame calibrates its
completed delta after swap: public draws (`ordinary ? objects : 1`) for CPU
color clear, or public draws plus one for the internal GPU color-clear draw.
Every subsequent oracle, warm-up and measured frame must retire exactly that
calibrated count. The total per mode is
`(measured_frames + 30 + 2) * native_draws_per_frame`.
Schema v2 records the calibrated count and `clear_path=cpu|gpu|host`, plus each
measured frame's actual delta. Host counters are zero. The parser requires all
counts to agree; a changing clear path fails the run. No status query splits
clear from drawing inside a timed frame.

Frame samples are buffered and printed after the measured interval and final
oracle. A fixed 16,384-frame capacity fails explicitly instead of silently
truncating a measurement. The first measured interval starts at the last warm-up
completion; the last is the first completed frame reaching the requested time.
Application logging does not occur in that loop. Driver logging is independent:
use identical frozen logging settings and record them with the runtime identity.
The first paired native case keeps `PS5_RUNTIME_QUIET` unset to preserve runtime
close/batch receipts, and labels timings as instrumented. The native Make path
does not expose that macro; this profile adds no quiet-mode plumbing.

#### Build and audit

After preparing the repository's normal dependencies, the existing native folder
builder discovers the new target without changes to deployment tools:

```sh
PS5_CUBES_OBJECTS=128 PS5_CUBES_SECONDS=30 PS5_CUBES_SWAP_COMPLETED=1 \
  bash tools/build-native-test-app.sh egl_public_core33_cubes_profile
```

Without `PS5_OPENGL_PREFIX`, this cube target uses the **source runtime** through
`tests/ps5/native-app.mk`. Set `PS5_OPENGL_PREFIX=/path/to/frozen/sdk` to validate
its manifest and link the installed SDK without rebuilding that runtime.
Freeze the resulting native folder and runtime hashes for each comparison. The
profile object always rebuilds when requested, so changing its variables cannot
silently reuse the other completion mode. Runtime build/deployment ownership
and the existing lock protocol still apply.

After one coordinated native run:

```sh
python3 tools/summarize-cubes-profile.py results/profile-opengl.log \
  --objects 128 --seconds 30 --swap-completed 1 --budget-hz 59.94
```

Profile mode uses the actual EGL window size from the selected SDK: 1920x1080,
2560x1440 or 3840x2160. Pass `--height 1440` or `--height 2160` to require that
size in the receipt auditor (default: 1080). Unsupported sizes and mismatched
receipts fail. This queries the render surface, not the negotiated HDMI signal.

The report includes clear, submission, finish, swap, active-frame and completed
frame-interval means, nearest-rank p50/p95/p99/max, and budget misses. Completed
FPS uses the entire measured interval including inter-frame loop overhead.
Submission is draw **API wall time**, which can contain driver waits; it is not
an isolated CPU utilization or GPU timer. Budget frequency is an analysis input,
not a display-mode setter. Use nominal 60/120 or a separately established actual
rate such as 59.94/119.88. These counts are not observed HDMI missed refreshes.
Fewer than 100 samples gets an explicit p99 sample-size caveat.

Compare a frozen explicit-finish receipt with the normal-swap candidate:

```sh
python3 tools/summarize-cubes-profile.py candidate-opengl.log \
  --objects 128 --seconds 30 --swap-completed 1 --budget-hz 59.94 \
  --compare baseline-opengl.log --compare-swap-completed 0
```

For comparisons between runtime versions using the same completion mode, omit
`--compare-swap-completed`. The checker requires matching scene, duration,
warm-up, host/native scope and budget; output records both receipt SHA-256 values.
Keep a separate artifact/SDK/configuration manifest with each receipt: a log
digest does not identify its runtime. Compare one changed variable at a time.

#### Host checks and scope

```sh
PS5_OPENGL_PREFIX=/path/to/existing/sdk bash tools/test-cubes-host.sh
python3 -m unittest discover -s tools -p test_cubes_profile.py
```

The host lane preserves the historical and UV checks, tests both profile modes
at 128 cubes, the 512-cube upper limit and 1440p/2160p profiles, and requires deliberate depth,
texture and missing-instance faults to fail the new path. Short host profiles
run one second per mode; use `--host --seconds 1` to audit them. They validate
the workload, timing accounting and oracles, not PS5 throughput or retirement.
Parser tests also reject incomplete/reordered samples, bad phase sums, missing
native completion/counts, mismatched comparisons and invalid timing budgets.
The host script also runs the real profile loop against a mock native counter,
checking both clear paths and lost/extra draws at every frame in both modes.

The historical benchmark remains 1920x1080. Neither benchmark selects a display
mode. Host profile tests can set `PS5_CUBES_HOST_HEIGHT=1080|1440|2160`; native
profiles obtain their dimensions from EGL. Neither path alone establishes HDMI
pacing, suspend/recovery, release acceptance or physical-controller behavior.

## Dear ImGui

Source: [examples/core33-imgui](../examples/core33-imgui/README.md).

This example provides a six-frame numerical renderer oracle, an interactive
TV demo and window/offscreen benchmarks. See [high-refresh builds](#high-refresh-window-benchmark-opt-in)
and the [SDK-specific measurements](performance.md) for performance.

Uses unmodified [Dear ImGui](https://github.com/ocornut/imgui/tree/v1.91.9b)
v1.91.9b, commit `f5befd2d29e66809cd1110a152e375a7f1981f06` (MIT), including
its upstream OpenGL3 backend. Source stays in the ignored dependency checkout.

```sh
make source-fetch
make sdk
bash tools/build-native-test-app.sh egl_public_core33_imgui
bash tools/test-imgui-host.sh
python3 tests/ps5/test_imgui_egl_cleanup.py
```

The builder verifies the dependency commit/clean tree and installed SDK
manifest, compiles with the native boilerplate's Clang 18 wrapper, and links
only the installed GL package. The backend's supported custom-loader option
uses exported public GL functions; no backend source patch or private GPU
header is needed. Relocatable linking uses plain `ld.lld-18` because the SDK
link wrapper injects a final-executable linker script even for `-r`.

Run with `tools/Run-NativeOpenGLGate.ps1`, frozen hashes/commits,
`-ExpectedGate egl_public_core33_imgui.o -Incremental -ObservationSeconds 60
-ObservationStopText '[ps5-imgui] finished'`.

Acceptance: six passing frames at 320x240 and 640x480, device-object
recreation, 60 exact/toleranced color probes, font alpha coverage, and restored
GL bindings/enables/blend/viewport/scissor/polygon state. Shapes, clipped
geometry, a moving uploaded image, text, and standard widgets all use ImGui's
draw lists and renderer. The validated image is also presented, but screenshots
are not the oracle. Require completion status 0 and clean native teardown,
post-health, and exact-token release. EGL cleanup failures also fail the app;
the host regression injects each cleanup error and checks that all cleanup
calls are still attempted and earlier rendering failures remain failures.

The same six-frame oracle runs on host software Mesa (EGL pbuffer instead of
the native window). The default bitmap font has binary coverage at 1x; only
2x requires partial alpha. Frames 1 and 4 separate the two overlapping quads
into distinct draw commands, while the other frames keep upstream batching.
Frames 2 and 5 attach renderbuffers to compare direct tiled storage with the
texture staging path. The first nongray text pixel is logged on failure.
Pixel mismatches collect the rest of the bounded batch but preserve failure;
GL/setup/presentation errors stop immediately.

This is one renderer integration, not CTS coverage, a complete input backend,
or a claim that every existing OpenGL application is compatible.

### Same-process EGL lifecycle check

`bash tools/test-imgui-host.sh --lifecycle` runs the complete six-frame example
three times in one process. The native target is
`bash tools/build-native-test-app.sh egl_public_core33_imgui_lifecycle`.
It reuses the existing oracle without changing the renderer or driver: each
session initializes EGL, creates its surface/context, renders six checked frames,
destroys everything and terminates EGL. Host and native commit `b0235c5` pass
18 frames/180 probes, including three successful presenter closes and clean title
teardown. Busy unregister remains. Stop observation only on
`[ps5-imgui-lifecycle] finished`, not an inner session's completion marker.
This is bounded recreation coverage, not exhaustive leak or device-loss testing.

### Visible TV demo

```sh
bash tools/test-imgui-host.sh --tv-demo
bash tools/build-native-test-app.sh egl_public_core33_imgui_tv
```

The separate `imgui_tv` target preserves the six-frame validation oracle and
uses the same installed SDK and unmodified upstream renderer. It draws directly
to the 1920x1080 EGL window: large text, an animated circle, blended rectangles,
a triangle, a speed slider, and palette buttons. D-pad navigates/adjusts, Cross
selects, and Circle backs out of a widget. No controller is required to watch.
The native controller ABI subset is based on the independently authored
`ps5-input-investigation/include/ps5_pad.hpp`; only standard current-state
input is used, with disconnected/intercepted input neutralized.

Each launch runs for five minutes at a maximum requested 30 FPS, then releases
GL/EGL and controller resources. Use the existing locked native-folder runner
with `-ExpectedGate egl_public_core33_imgui_tv.o -Incremental
-ObservationSeconds 330`, recording its usual commit/hash pins. It closes the
title at the end of that bounded window. The installed folder is still
`/data/homebrew/PPSA99005`; no application ELF is sent to elfldr.

Host acceptance: 12 full-HD frames across simulated elapsed times 0..275 seconds,
ten exact shape readbacks, two gamepad-driven checkbox changes, and successful
EGL cleanup. Hardware acceptance: shape readbacks at frames 0/10 and every
30-second progress interval, sustained frame receipts, TV-visible animation,
and clean teardown. The separate 30-second profiling mode retains two probes.
Controller hardware interaction requires observing a widget change, not merely
opening a pad handle. No CTS rerun is needed for this example-only change.
The control is the previously validated six-frame ImGui app and frozen SDK;
only the example is changed. The recorded run used firmware 6.02. Managed runs
require an explicit `-Ps5Host` and the [testing prerequisites](testing.md).
Stop on any render/presentation error or uncertain console health.

Benchmark and validation claims belong to the exact SDK identities documented
in [Performance](performance.md) and [Validation](validation.md).

The demo's requested frame cap is not achieved throughput. Numerical readbacks,
controller-driven widget changes and physical display observation establish
different properties; record which were checked for the tested executable.
Raw device receipts remain local.

### Matched windowed benchmark

`PS5_IMGUI_WINDOW_BENCHMARK=1` extends the original TV demo, not the offscreen
scene below. Keep the separate frozen GPU-presentation SDK selected; the native
builder always rebuilds the example when changing its benchmark flags:

```sh
bash tools/test-imgui-host.sh --window-benchmark
PS5_IMGUI_PROFILE=1 PS5_IMGUI_WINDOW_BENCHMARK=1 PS5_IMGUI_WINDOW_TARGET=60 \
  bash tools/build-native-test-app.sh egl_public_core33_imgui_tv
python3 tools/summarize-imgui-profile.py RECEIPT --window-target 60
```

The native run excludes 30 warm-up frames and measures the next 30 seconds.
It preserves the two warm-up pixel probes and the original clear/draw/swap
ordering, with no added timed readback or `glFinish`. Active time includes swap;
completed frame intervals additionally include pacing and loop overhead. Both
have nearest-rank percentiles and missed-budget counts (0.25 ms tolerance for
frame pacing). The 60 FPS target uses the original swap pacing; target 30 adds
bounded deadline pacing. Controller changes invalidate a native benchmark.
Host checks run ten measured frames without pacing and retain simulated input.

Use the usual frozen, locked `imgui_tv` cycle with a 60-second observation cap.
Require the new harness to reproduce 59–60.5 FPS at 1080p before extending it.
Separate SDK builds can select `PS5_SCANOUT_HEIGHT=1080`, `1440` or `2160` when
running `toolchain/install-ps5-opengl-gl46.sh SEPARATE_PREFIX`. Select that
frozen prefix with `PS5_OPENGL_PREFIX` for the app build. All layers use matching
render dimensions and display-buffer strides. The scene stays logically
1920x1080 and scales to the queried surface. Host checks select the same size
with `PS5_IMGUI_HOST_HEIGHT`; the auditor uses `--window-height`.
Profiled native SDKs additionally support `--output-status`, requiring matching
registration/offset receipts and two raw VideoOut status snapshots. The default
60 Hz build requests no output reconfiguration; high-refresh builds are separate.
No independent physical output-mode or GPU-timer claim follows from the
application timing. The accepted release SDK remains unchanged.

#### High-refresh window benchmark (opt-in)

After the [normal dependency and SDK build](building.md), build a
separate runtime and native app; do not overwrite a frozen validation SDK:

```sh
PS5_DRAW_PROFILE=1 PS5_GPU_PRESENT_BATCH=1 \
  PS5_SCANOUT_HEIGHT=2160 PS5_SCANOUT_FPS=120 \
  bash toolchain/install-ps5-opengl-gl46.sh build/sdk/ps5-opengl-gl46-2160p120
PS5_OPENGL_PREFIX="$PWD/build/sdk/ps5-opengl-gl46-2160p120" \
  PS5_IMGUI_PROFILE=1 PS5_IMGUI_WINDOW_BENCHMARK=1 PS5_IMGUI_WINDOW_TARGET=120 \
  bash tools/build-native-test-app.sh egl_public_core33_imgui_tv
python3 tools/summarize-imgui-profile.py RECEIPT \
  --window-target 120 --window-height 2160 --prepare-profile
```

Use the same locked native-folder protocol, `PPSA99005` and 60-second observation
cap as above. The builder supplies the benchmark's high-refresh title metadata;
the runtime checks output support, requests fixed 120 Hz and restores normal
output at shutdown. Do not change console Settings or retry an unsupported mode.
For 1080p or 1440p, change the runtime height, separate prefix and auditor height
together. Every rebuild creates a new candidate requiring its own verified run.

The original scene averages ~119.88 FPS at all three render sizes on the recorded
firmware-6.02 console; frame intervals still vary. Both VideoOut APIs report
3840x2160 at 119.88 Hz even for the lower render sizes. These are not three
independently verified HDMI modes. No fresh physical display/input check is claimed.
Target 90 changes only the app flag to `PS5_IMGUI_WINDOW_TARGET=90` and the auditor
target to 90, retaining the 120 Hz SDK. It uses application pacing, not VRR or
native 90 Hz. The latest 4K90 candidate has not been measured; do not infer a
completed twelve-target matrix from the three new 120 FPS results.

To audit the HDMI negotiation separately, retain the exact runner receipt and
its adjacent `-klog.log`, `-result.json` and `-runner.json` files:

```sh
python3 tools/summarize-display.py PATH/PPSA99005-TIMESTAMP-opengl.log --height 2160
```

The audit requires one clean native-title cycle, a stable captured high-refresh
mode and restoration to 60 Hz. It reports `verified-match`, `verified-mismatch`
or `inconclusive`; a successfully measured mismatch is not a failed renderer.
A 3840x2160 render buffer or VideoOut status alone does not prove 4K HDMI output.
The HDMI log is still console-side evidence: TV/capture-device signal information
is a separate check, and a capture card can constrain negotiation. Do not change
console Settings or force a mode unsupported by the connected display path.

### Bounded offscreen performance matrix

```sh
bash tools/test-imgui-host.sh --benchmark
# Select a separately frozen SDK via PS5_OPENGL_PREFIX; do not replace the accepted SDK.
bash tools/build-native-test-app.sh egl_public_core33_imgui_benchmark
python3 tools/summarize-imgui-benchmark.py RECEIPT
```

The distinct lightweight UI workload measures 1080p, 1440p and 2160p at target
rates of 30/60/90/120 FPS in one launch. Each case warms for at most 30 frames
or one second (at least two completed frames), then runs
30 measured seconds; `glFinish` confirms GPU completion per frame. Three pixels
(clear, opaque geometry, alpha overlap) are checked before and after measurement.
The host check shortens each case to two warm-up and six measured frames without
pacing; its timing is not a PS5 performance prediction.

Only a static preview at the SDK's 1080p, 1440p or 2160p window size is presented
between cases. The measured rendering
uses offscreen RGBA8 buffers: **no 1440p/4K or 90/120 Hz display claim** follows
from these results. See the [measurement scope](performance.md).
Use the locked native-folder runner with gate `egl_public_core33_imgui_benchmark.o`,
`-Headless -Incremental -ObservationSeconds 450` and its normal commit/hash pins.
No screenshots or controller input are required. Stop on correctness, retirement
or lifecycle failure; missing an FPS target alone is an ordinary benchmark result.

## NanoVG

Source: [examples/core33-nanovg](../examples/core33-nanovg/README.md).

Uses unmodified [NanoVG](https://github.com/memononen/nanovg) at
`ce3bf745eb2d2dbc14a50bf2446783f691ac4353` (zlib license). Only EGL/native
entry-point, build glue, and deterministic test content are project-owned.
The GL3 backend keeps antialiasing, stencil strokes, UBOs, and debug checks.

```sh
make source-fetch
make sdk
bash tools/test-nanovg-host.sh
make nanovg
```

Three frames exercise 320x240 / 640x480 targets and renderer recreation:
premultiplied blending, a stencil-cut hole, stencil strokes with a
self-intersection, shader clipping, a nearest-filtered image, and a gradient.
Acceptance requires 45 toleranced pixel probes, an entirely cleared stencil
buffer after every frame, no logged GL/backend errors, status 0, and clean
resource/EGL teardown. The same oracle runs first on host software Mesa.
The image is presented, but screenshots are not required.

Use the locked native gate wrapper with `egl_public_core33_nanovg.o`, frozen
hashes, 60-second observation, and stop text `[ps5-nanovg] finished`.
This is supplemental renderer compatibility evidence, not official CTS coverage.

## Sokol

Source: [examples/core33-sokol](../examples/core33-sokol/README.md).

Uses unmodified [Sokol](https://github.com/floooh/sokol) `sokol_gfx.h` at
`48c85905aeaa1350feb17515961aecb6c75447d8` (zlib license), with its GL backend
and debug validation enabled. EGL entry point, scene and numeric oracle are
project-owned. The SDK contains modern Khronos headers; two 4.x header macros
are undefined before including Sokol to select its existing 3.3 fallback
paths, as with a 3.3-only external loader. No GL functions are stubbed and no
upstream algorithms are changed. The host script rejects imports outside the
344-command Core 3.3 list; it does not merely rely on a version string.

```sh
make source-fetch
make sdk
bash tools/test-sokol-host.sh
make sokol
```

Three frames at 320x240 / 640x480 / 320x240 recreate the renderer and resources,
upload an indexed quad, update an instance buffer, and draw two textured
instances with uniforms, nearest samplers, alpha blending and hardware scissor.
Every RGBA component is compared with an independent CPU oracle (1,843,200
components total, tolerance 2). All frames, resource states, GL/EGL cleanup,
and Sokol warnings/errors must pass. The same scene/oracle runs first on host
software Mesa. Blits present the checked images; screenshots are unnecessary.

Run the locked native gate wrapper with `egl_public_core33_sokol.o`, frozen
hashes, 60-second observation and stop text `[ps5-sokol] finished`.
This is renderer compatibility evidence, not official CTS coverage.

## Sokol cube

Source: [examples/core33-sokol-cube](../examples/core33-sokol-cube/README.md).

Bounded native adaptation of [cube-glfw.c](https://github.com/floooh/sokol-samples/blob/8afa83928ce1870efeb0d513e7c4dce4f5db7b3e/glfw/cube-glfw.c):
180 rotating, depth-tested and back-face-culled frames at 1920x1080.
This is a small existing 3D sample, not a GLFW port or a game benchmark.

The September 7 final SDK passes all 180 frames and 2,596 pixel checks with
`PS5_SOKOL_HEAP_READBACK=1`, including the original large allocation before
shader setup. The lower-memory scanline mode remains the default example.
See [release validation](validation.md); historical diagnosis follows.

```sh
python3 tools/fetch-sources.py --sokol-samples
make test-sokol-cube
PS5_OPENGL_PREFIX=/absolute/path/to/candidate-sdk make sokol-cube
```

The standard native builder produces the PPSA99005 folder. Use the documented
bounded folder-upload/launch protocol; never send its graphics executable to a loader.

The generator verifies both pinned upstream checkouts and leaves them unchanged.
Its six exact adaptations are: native window glue include, vecmath include path,
wrapped entry point, GLSL 410 to 330 Core (no shader logic change), four samples
to one, and an error-recording logger. Geometry, transforms, vertex/index buffers,
uniforms, pipeline state and draw calls are retained. Platform glue replaces the
800x600 desktop window with the native fullscreen EGL surface and limits the loop;
there is no interactive input. The software-Mesa host uses a single-buffered
pbuffer with explicit front-buffer selection; the native window is unchanged.

At frames 0/44/89/134/179, 17 RGBA8 scanline readbacks are compared with independent CPU
ray/unit-box intersections using the intended transform. A 31x17 grid checks
foreground face colors and background, excluding ambiguous cube-edge probes;
color tolerance is two byte values. The host checks 2,596 pixels over five poses
and rejects an intentionally erased cube. Readbacks do not prove TV scanout or
input health. The readback buffer is 7,680 bytes, not a full 8,294,400-byte image.
The first native candidate aborted during GLSL built-in initialization after
allocation failure, before drawing. With the small buffer, native commit `a81c24d`
passes all 180 frames and 2,596 probes, EGL cleanup and title teardown. This supports
test-buffer memory pressure as the trigger; larger application-memory robustness
remains unvalidated. Busy VideoOut unregister followed by successful close remains.

The optional `PS5_SOKOL_MAPPED_READBACK=1 make sokol-cube` control restores the
full-frame readback using an anonymous CPU mapping, rounded to the native 16 KiB
page size and released with `munmap`. It changes no GL/shader/driver path and does
not replace `malloc`, expand the app's resource budget or access other memory.
Run `bash tools/test-sokol-cube-host.sh --mapped` first; it also checks a simulated
allocation failure exits before rendering and cleans up EGL. Native `1c74dee`
accepts the mapping and completes shader setup, but its first full-frame readback
returns `GL_OUT_OF_MEMORY`; the app closes normally. Driver `c53925e` moves large
color/depth staging to owned CPU mappings: the unchanged full-frame control then
passes 180 frames and all 2,596 probes with clean teardown. The small checker
remains the default; this does not establish general application-heap robustness.

`PS5_SOKOL_HEAP_READBACK=1 make sokol-cube` restores the original 8,294,400-byte
`malloc` before shader setup (mutually exclusive with mapped readback).
Use `bash tools/test-sokol-cube-host.sh --heap` for its host oracle. The native
builder now shares the CTS app's existing 128 MiB process-lifetime heap wrapper.
Native `dd8d228` passes shader setup, 180 frames and all 2,596 probes with this
original large-malloc pattern. No allocator is added to the host reference or
silently injected by the standalone installed graphics SDK. This is not maximum
heap-capacity or exhaustive OOM-recovery validation.

The sample is MIT-licensed by Andre Weissflog; its bundled vecmath is used under
Mattias Gustavsson's MIT option. See [notices](../THIRD_PARTY_NOTICES.md).
