#version 450
// ps5-homebrew-ui - Vulkan full-screen triangle for the backdrops and the blur.
// Copyright (C) 2026 BlackBearReloaded
// Copyright (C) 2026 Mihawk
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Vulkan twin of kVertex in src/gfx/backdrop.cpp and kBlurVertex in
// src/gfx/gl_renderer.cpp. One triangle covers the target; no vertex buffer.
// v_uv (0, 0) lands on the first row in memory under both APIs, so the blur
// reads its source the way it is stored.

layout(location = 0) out vec2 v_uv;

void main()
{
    vec2 p = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
    v_uv = p;
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
