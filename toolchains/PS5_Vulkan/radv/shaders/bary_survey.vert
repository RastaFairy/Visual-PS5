#version 450
// PS5 Vulkan - RADV smoke test: the barycentric survey's geometry (docs/BARYCENTRIC_GFX101.md). Every vertex names
// itself (its index plus one); CASE picks how the primitives are laid out so the order the pixel shader reads
// them in can be compared with the order they were drawn in:
//   0  triangle list, 16 triangles in a 4 x 4 grid, each with its corners in the same order
//   1  triangle list, the same grid, each triangle's corners in another of the six orders
//   2  triangle strip, 16 triangles along a band
//   3  triangle fan, 16 triangles round a centre
//   4  line list, 16 lines in the grid, every other one drawn right to left
//   5  line strip, 16 lines along a zigzag
// Copyright (C) 2026 Mihawk-99
// SPDX-License-Identifier: GPL-3.0-or-later
layout(constant_id = 0) const uint CASE = 0;
layout(location = 0) out uint vertex_id;
layout(location = 1) flat out uint provoking_id;   // the same value, read flat: the provoking vertex's
void main()
{
    const vec2 corners[3] = vec2[](vec2(8.0, 8.0), vec2(8.0, 56.0), vec2(56.0, 40.0));
    const uint orders[18] = uint[](0, 1, 2, 1, 2, 0, 2, 0, 1, 0, 2, 1, 2, 1, 0, 1, 0, 2);
    const uint v = uint(gl_VertexIndex);
    vec2 pixel;
    if (CASE == 4u) {
        const uint p = v / 2u, i = v % 2u;
        const uint end = ((p % 2u) == 0u) ? i : 1u - i;
        pixel = vec2(float(p % 4u), float(p / 4u)) * 64.0 + vec2(8.0 + 48.0 * float(end), 8.0 + 3.0 * float(p));
    } else if (CASE == 5u) {
        pixel = vec2(8.0 + 14.0 * float(v), (v % 2u) == 0u ? 60.0 : 180.0);
    } else if (CASE <= 1u) {
        const uint p = v / 3u, i = v % 3u;
        const uint k = CASE == 0u ? i : orders[(p % 6u) * 3u + i];
        pixel = vec2(float(p % 4u), float(p / 4u)) * 64.0 + corners[k];
    } else if (CASE == 2u) {
        pixel = vec2(8.0 + 28.0 * float(v / 2u), (v % 2u) == 0u ? 40.0 : 120.0);
    } else if (v == 0u) {
        pixel = vec2(128.0, 128.0);
    } else {
        const float angle = float(v - 1u) * 0.39269908;
        pixel = vec2(128.0, 128.0) + 110.0 * vec2(cos(angle), sin(angle));
    }
    gl_Position = vec4(pixel / 128.0 - 1.0, 0.0, 1.0);
    vertex_id = v + 1u;
    provoking_id = v + 1u;
}
