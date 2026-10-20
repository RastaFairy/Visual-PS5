#version 450
// ps5-homebrew-ui - Vulkan vertex shader for filled polygons.
// Copyright (C) 2026 BlackBearReloaded
// Copyright (C) 2026 Mihawk
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Vulkan twin of kMeshVertex in src/gfx/gl_batch.cpp: change both
// together. It shares the batch's push constants.

layout(location = 0) in vec2 a_position;
layout(location = 1) in vec4 a_color;

layout(push_constant) uniform Push
{
    vec4 viewport; // scale, offset x, offset y
    vec2 surface;
    float flip; // 1: the target is stored top row first, -1: bottom row first
}
pc;

layout(location = 0) out vec4 v_color;

void main()
{
    vec2 surface = a_position * pc.viewport.x + pc.viewport.yz;
    vec2 ndc = surface / pc.surface * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, pc.flip * ndc.y, 0.0, 1.0);
    v_color = a_color;
}
