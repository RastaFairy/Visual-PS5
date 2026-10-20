#version 450
#extension GL_EXT_fragment_shader_barycentric : require
// PS5 Vulkan - RADV smoke test: the two vertices of a line read per vertex, as red and green
// (docs/BARYCENTRIC_GFX101.md).
// Copyright (C) 2026 Mihawk-99
// SPDX-License-Identifier: GPL-3.0-or-later
layout(location = 0) pervertexEXT in uint vertex_id[];
layout(location = 0) out vec4 colour;
void main()
{
    colour = vec4(float(vertex_id[0]), float(vertex_id[1]), 0.0, 255.0) / 255.0;
}
