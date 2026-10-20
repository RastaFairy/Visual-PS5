# Minimal OpenGL 4.6 triangle

The smallest public EGL/OpenGL program, and the starting point for a new
application:

- an OpenGL 4.6 Core context,
- `#version 460 core` shaders,
- one vertex buffer and one draw into the window at the SDK's display size.

It uses no private driver headers.

Build it against an installed SDK with `Makefile.installed` (set
`PS5_OPENGL_PREFIX` to the SDK's `sdk/` directory), or against the source tree
with `Makefile` after `make sdk`. `tools/verify-installed-sdk.sh` also links it
through Make, pkg-config and CMake. The result is a linked executable, not a
packaged app: package it as a native title folder as described in
[Using the SDK](../../docs/consumer-build.md).

The directory keeps its original `core33-` name because build tools and tests
refer to it.
