# Textured cubes benchmark

A draw-submission benchmark: rotating, lit, depth-tested cubes with two
procedural textures. It draws the same scene two ways:

- one draw per object,
- one `glDrawArraysInstanced` call, with a per-instance placement attribute
  instead of per-object uniforms.

This compares ordinary and instanced submission cost. It is a low-poly workload,
not a measure of full-game FPS or GPU throughput. The shaders use
`#version 330 core`, which the SDK's OpenGL 4.6 driver runs unchanged.

```sh
make cubes                          # PPSA99005 folder from the source runtime
make test-cubes                     # host software Mesa reference
```

`profile.h` adds a longer matched profile, selected as the
`egl_public_core33_cubes_profile` target. Workloads, receipts, profile options
and the audit tools are in
[example validation](../../docs/example-validation.md#textured-cubes-benchmark).
Measured results are in [performance](../../docs/performance.md).
