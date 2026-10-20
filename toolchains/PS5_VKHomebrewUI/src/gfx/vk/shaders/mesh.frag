#version 450
// ps5-homebrew-ui - Vulkan fragment shader for filled polygons.
// Copyright (C) 2026 BlackBearReloaded
// Copyright (C) 2026 Mihawk
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Vulkan twin of kMeshFragment in src/gfx/gl_batch.cpp.

layout(location = 0) in vec4 v_color;
layout(location = 0) out vec4 frag_color;

void main()
{
    frag_color = v_color;
}
