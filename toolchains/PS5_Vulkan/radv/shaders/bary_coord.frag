#version 450
#extension GL_EXT_fragment_shader_barycentric : require
// PS5 Vulkan - RADV smoke test: the barycentric coordinates the pixel shader is given
// (VK_KHR_fragment_shader_barycentric), as red, green and blue; the survey compares them with the primitive's
// own vertices (docs/BARYCENTRIC_GFX101.md).
// Copyright (C) 2026 Mihawk-99
// SPDX-License-Identifier: GPL-3.0-or-later
layout(location = 0) out vec4 colour;
void main()
{
    colour = vec4(gl_BaryCoordEXT, 1.0);
}
