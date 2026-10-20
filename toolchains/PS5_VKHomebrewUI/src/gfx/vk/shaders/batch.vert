#version 450
// ps5-homebrew-ui - Vulkan batch vertex shader: one quad per draw list instance.
// Copyright (C) 2026 BlackBearReloaded
// Copyright (C) 2026 Mihawk
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Vulkan twin of kVertex in src/gfx/gl_batch.cpp: change both together.
// Uniforms are push constants, gl_VertexID is gl_VertexIndex, and the last
// line takes the target's row order from flip (see vk_renderer.hpp).

layout(location = 0) in vec4 a_rect;
layout(location = 1) in vec4 a_top;
layout(location = 2) in vec4 a_bottom;
layout(location = 3) in vec4 a_border;
layout(location = 4) in vec4 a_params;
layout(location = 5) in vec4 a_extra;

layout(push_constant) uniform Push
{
    vec4 viewport; // scale, offset x, offset y
    vec2 surface;
    float flip; // 1: the target is stored top row first, -1: bottom row first
}
pc;

layout(location = 0) out vec2 v_local;
layout(location = 1) out vec2 v_virtual;
layout(location = 2) out vec2 v_uv;
layout(location = 3) out float v_t;
layout(location = 4) flat out vec2 v_half;
layout(location = 5) flat out vec4 v_top;
layout(location = 6) flat out vec4 v_bottom;
layout(location = 7) flat out vec4 v_border;
layout(location = 8) flat out vec4 v_params;
layout(location = 9) flat out vec4 v_extra;

const vec2 kCorners[6] = vec2[6](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0),
                                 vec2(1.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0));

void main()
{
    vec2 corner = kCorners[gl_VertexIndex];
    int shape = int(a_params.w + 0.5);
    vec2 size = a_rect.zw;
    // Grow shapes by their softness plus one output pixel for anti-aliasing;
    // glyph and image quads map texels exactly and are not grown.
    float pad = (shape == 1 || shape == 3) ? 0.0 : a_params.z + 1.0 / pc.viewport.x;
    vec2 local = mix(vec2(-pad), size + vec2(pad), corner);
    vec2 centred = local - 0.5 * size;
    vec2 virt = a_rect.xy + local;
    // Rounded rectangles, shadows and triangles may turn about their centre: the quad
    // rotates, the distance field keeps working in the unrotated frame.
    bool box = shape == 0 || shape == 2 || shape == 5;
    if (box && a_extra.x != 0.0)
    {
        float c = cos(a_extra.x);
        float s = sin(a_extra.x);
        virt = a_rect.xy + 0.5 * size + vec2(c * centred.x - s * centred.y,
                                             s * centred.x + c * centred.y);
    }
    v_virtual = virt;
    v_local = centred;
    v_half = 0.5 * size;
    v_t = (shape == 0 && a_extra.y > 0.5) ? clamp(local.x / max(size.x, 1e-3), 0.0, 1.0)
                                          : clamp(local.y / max(size.y, 1e-3), 0.0, 1.0);
    v_uv = mix(a_extra.xy, a_extra.zw, corner);
    v_top = a_top;
    v_bottom = a_bottom;
    v_border = a_border;
    v_params = a_params;
    v_extra = a_extra;
    vec2 surface = virt * pc.viewport.x + pc.viewport.yz;
    vec2 ndc = surface / pc.surface * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, pc.flip * ndc.y, 0.0, 1.0);
}
