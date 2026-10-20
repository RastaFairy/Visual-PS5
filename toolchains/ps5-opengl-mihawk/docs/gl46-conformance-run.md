# OpenGL 4.6 conformance test run

**Run completed: October 1, 2026.** SDK 1.0.0 passes the complete Khronos
OpenGL 4.6 conformance test run on one PlayStation 5: **122,799 results —
98,590 Pass, 24,205 NotSupported, 4 compatibility warnings and no failure.**
The results were not submitted to Khronos: this is the project's own run of the
Khronos test suite, **not Khronos certification**.

The exported results, the runner's summary and the justification of every
NotSupported result are in
[validation/2026-10-01-gl46-conformance](../validation/2026-10-01-gl46-conformance/README.md);
`make test` verifies them.

## What ran

- The test suite is VK-GL-CTS `opengl-cts-4.6.8.1` with unmodified test code.
  The local changes are the PS5 build target, the platform port, the runner
  entry point and `fputc` in place of `putc` in the framework's debug output;
  `conformance/vk-gl-cts/verify-source.sh` checks the tree against the release
  plus exactly these.
- The sessions and their command lines are the ones `cts-runner --type=gl46`
  produces: the OpenGL ES 3.0 and 3.1 functional tests under OpenGL 4.5, the
  context-creation groups, the single-configuration group and four runs of the
  OpenGL 4.6 group (64x64, 113x47, and two with a framebuffer object as the
  default framebuffer, 64x16384 and 16384x64).
- All 11 sessions ran in one launch of one binary, with no crash, hang or
  resumed session. A changed driver means a new complete run; no result is
  carried over from an earlier binary.

| # | Session | Results | Pass | NotSupported | Warnings |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1 | OpenGL ES 3.0 tests, 256x256 | 1,325 | 1,325 | 0 | 0 |
| 2 | OpenGL ES 3.1 tests, 256x256 | 31,248 | 30,866 | 382 | 0 |
| 3-6 | Context creation, OpenGL 3.0 to 4.5 | 22 | 3 | 19 | 0 |
| 7 | OpenGL 4.6 single configuration | 11,348 | 5,056 | 6,292 | 0 |
| 8 | OpenGL 4.6, 64x64 | 19,714 | 15,335 | 4,378 | 1 |
| 9 | OpenGL 4.6, 113x47 | 19,714 | 15,335 | 4,378 | 1 |
| 10 | OpenGL 4.6, framebuffer object 64x16384 | 19,714 | 15,335 | 4,378 | 1 |
| 11 | OpenGL 4.6, framebuffer object 16384x64 | 19,714 | 15,335 | 4,378 | 1 |
| | **Total** | **122,799** | **98,590** | **24,205** | **4** |

The warning is `KHR-GL46.direct_state_access.framebuffers_check_status`, once per
OpenGL 4.6 session: the test accepts a framebuffer with mixed sample counts or
mixed layered attachments as complete and reports that as a compatibility warning.

## NotSupported results

A test reports NotSupported when what it needs is not part of the
implementation. A [rule table](../tools/cts-notsupported-report.py) assigns
every such result to a class and the run is rejected if one is left over.

| Class | Results | Meaning |
| --- | ---: | --- |
| Optional extension | 22,748 | Tests of extensions outside OpenGL 4.6: sparse textures and buffers, shader subgroups, fragment shading rate, mesh shaders and others |
| Not applicable | 871 | The test itself excludes the combination: OpenGL ES only cases, `texelFetch` on targets GLSL does not define, formats that are not required to be renderable |
| Sample count | 532 | More than 4 samples, or a multisampled default framebuffer |
| Minimum limit | 35 | The test needs more than the minimum OpenGL 4.6 requires for a limit this implementation sets at that minimum, or a larger surface than the session's |
| Surface type | 19 | See below |

### The 19 window-surface cases

Nineteen context-creation cases (`KHR-NoContext.*`: debug output, robust buffer
access, context flags, reset notification and no-error contexts) create their
own context and refuse any surface type other than a window. The conformant EGL
configuration offers pbuffers only, because a window on this platform is the
fixed-size display, so the runner selects pbuffers and these cases report
NotSupported. The functions are implemented.

They were run in addition, on the same binary, with
`PS5_CTS_OFFSCREEN_WINDOW=1`: the port then gives such a case the same offscreen
surface as its window. All 22 cases of those four sessions pass. This
supplementary run is recorded next to the official one and is not part of it.

## What the run changed

The campaign found and fixed these defects before the final run:

- Tessellation state, the provoking vertex, the guard band and the order of
  transform feedback output from tessellation and geometry shaders.
- Tessellation with a geometry shader: the GPU dropped part of the output of
  geometry shaders that emit many vertices per primitive. Such draws now run in
  two passes: the tessellated primitives are captured with transform feedback
  and drawn again as the geometry shader's input.
- Depth and stencil written by a draw could stay in the GPU's cache and replace
  a later clear or readback done on the CPU.
- Storage buffer slots without a buffer, transform feedback buffers described
  only by a stride, the sample ID of a lowered sample mask, small clipped blits
  and the stride of stencil-only texture uploads.
- EGL now creates robust-access, reset-notification and no-error contexts.

## Test runner notes

- The session list comes from upstream's `cts-runner` code, and the native CTS
  application executes each session with exactly those arguments.
  `tools/cts-runner-results.py` writes the run summary in the runner's format.
- Its heap returns zero-filled memory. `KHR-GL46.fragment_shading_rate.*`
  cases, which end as NotSupported here, delete object names held in members
  they never initialize; with heap garbage those calls delete unrelated live
  objects and change the result of a later case at random.
- Logs are buffered during the run and written when a session ends.

## Scope

The result belongs to the tested binary, the CTS application built from the
SDK 1.0.0 source at the commit the evidence records, and to one console. Release
archives are built separately from the same source. The run says nothing about
performance, about applications outside the test suite, or about window
presentation, which it does not exercise. See the [limitations](limitations.md).
