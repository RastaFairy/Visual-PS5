# Fragment shader barycentrics on the PS5's parameter cache

`VK_KHR_fragment_shader_barycentric` reads a primitive's vertices in the order the primitive defines. The PS5's parameter
cache hands them over in another. This file is what was measured, how the driver puts the order right, what it does not
cover, and how to run it again. The measurements are appended to [HARDWARE_FINDINGS.md](HARDWARE_FINDINGS.md) under
2026-10-12; the driver change is in the Mesa fork (`../PS5_Mesa`, `src/amd/vulkan/nir/radv_nir_lower_fs_vertex_order.c`).

## What the hardware does

Measured with the RADV smoke title (PPSA99014), `radv/radv_smoke.c`'s `test_barycentric_survey`, with the extension reported
by an environment switch of that day (`RADV_PS5_STRICT_VERTEX_ORDER`, gone now). A pixel shader (`radv/shaders/bary.frag`)
writes the three values it reads per vertex (`vertex_id[0..2]`) as red, green and blue; every vertex names itself.

- **The slots are a cyclic rotation of the primitive's own order.** Winding is always kept: 1,144 texels a triangle, 16
  triangles a case, never a reflection.
- **The first slot holds the vertex furthest left on the screen, then furthest up**, whatever order the primitive was drawn in.
  Six orders of the same three corners (list), a 16-triangle fan round a centre, a strip: all of them. A triangle drawn with its
  leftmost corner first reads in order; the same corner third reads `201`, second `120`.
- It does not depend on the primitive's index in the draw (16 identical triangles all read the same), on NGG
  (`RADV_DEBUG=nongg` gave the same table), or on `SPI_PS_INPUT_CNTL.ROTATE_PC_PTR` (set by RADV for these inputs; the first
  measurement, 2026-09-27, said the same).
- **The provoking vertex argument is not delivered.** `SPI_SHADER_PGM_RSRC1_PS.LOAD_PROVOKING_VTX` (GFX10.3+) was set and the
  SGPR read back 0 in every quad of every triangle. `gl_BaryCoord` through RADV's own lowering was therefore rotated the same
  way (`survey gl_BaryCoord, list, six orders`: 6 of 16 triangles in order).
- **A flat input is right.** The provoking vertex's value arrives in an ordinary flat input whatever the rotation, which is
  what makes the fix below possible.

## What the driver does

The extension is reported (`ac_compiler_info.emulate_ps_strict_vertex_order`, set by the PS5 winsys), and both stages play a part:

1. The last pre-rasterization stage (a vertex or tessellation evaluation shader) writes two outputs, in the last two varying
   locations (`VAR30`, `VAR31`): a hash of the vertex's clip-space position, once flat and once per vertex. The hash's lowest
   bit says whether the provoking vertex is the last (`nir_load_provoking_vtx_in_prim_amd` in a vertex shader).
2. The pixel shader reads the flat tag and the three per-vertex tags, takes the slot whose tag is the flat one, and reads its
   per-vertex inputs and builds its barycentric coordinates from the slots after it, modulo the primitive's vertex count
   (1, 2 or 3); indices past a line's or a point's last vertex repeat it, as the CTS expects.

The hash is a multiply-and-shift mix of the four position components. A plain xor of products was tried first and lost the sign
bit of `(-1, -1)` and `(1, 1)`, the corners of the CTS's own quad: found by the CTS, not by the survey.

The pieces: `radv_nir_lower_fs_vertex_order.c` (both passes and the shared slot computation), `radv_nir_lower_fs_barycentric.c`
(the barycentric lowering takes the slot from the same place), `radv_pipeline_graphics.c` (where each half runs: with the other
stage in a pipeline, or alone in a pipeline library when the device enabled the feature, `radv_compiler_info.key.ps5_vertex_tags`).

## What it does not do

- **Geometry and mesh shaders** as the last pre-rasterization stage: no tags are written, so per-vertex reads there keep the
  hardware's order. Tessellation evaluation shaders are served.
- **The last two varying locations** belong to the driver when a pixel shader reads per-vertex inputs or barycentrics. A program
  using them as well loses them.
- A vertex shader writing a position other than in its last block (not seen) is left without tags.

## Evidence

CTS: `dEQP-VK.fragment_shading_barycentric.*`, the pinned mustpass group, run on the console as PPSA99015 through
`tools/run-cts.py --mustpass fragment-shading-barycentric`. See the numbers in [CTS_GAPS.md](CTS_GAPS.md) and the run record
in the phase log; the smoke title's own survey is the quick check (`RADV_SMOKE_ONLY=barycentric` in `radv-smoke-env.txt`).
