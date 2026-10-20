#version 450
// ps5-homebrew-ui - Vulkan blur for the frosted glass copy.
// Copyright (C) 2026 BlackBearReloaded
// Copyright (C) 2026 Mihawk
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Vulkan twin of kBlurFragment in src/gfx/gl_renderer.cpp: change both
// together. Nine-tap Gaussian from five bilinear fetches (weights after Rakos).

layout(set = 0, binding = 0) uniform sampler2D u_texture;

layout(push_constant) uniform Push
{
    vec2 step;
}
pc;

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_color;

void main()
{
    vec4 c = texture(u_texture, v_uv) * 0.227027;
    c += (texture(u_texture, v_uv + pc.step * 1.384615) +
          texture(u_texture, v_uv - pc.step * 1.384615)) * 0.316216;
    c += (texture(u_texture, v_uv + pc.step * 3.230769) +
          texture(u_texture, v_uv - pc.step * 3.230769)) * 0.070270;
    frag_color = vec4(c.rgb, 1.0);
}
