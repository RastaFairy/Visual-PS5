# The Vulkan backend

PS5_VKHomebrewUI draws the kit with Vulkan as well as OpenGL. The shell, the
designs, the components and the sample content see only `gfx::Renderer`
(`src/gfx/renderer.hpp`): the frame's layers and the texture calls.
`gfx::GlRenderer` (`src/gfx/gl_renderer.hpp`) plays them with OpenGL, as
upstream does; `gfx::VkRenderer` (`src/gfx/vk/vk_renderer.hpp`) plays them with
Vulkan. A program links one of the two.

The Vulkan backend is what
[PS5_VulkanTemplate](https://github.com/mihawk-99/PS5_VulkanTemplate) uses, so a
title made with it draws the kit through RADV beside its own 3D scene.

## Using it

```cpp
#include "gfx/vk/vk_renderer.hpp"

gfx::VkRenderer renderer;
gfx::VkRendererConfig config;
config.physical_device = physical_device;
config.device = device;
config.queue = graphics_queue;          // uploads and render_to_texture submit here and wait
config.queue_family = graphics_family;
config.frames_in_flight = 2;
config.render_pass = render_pass;       // the pass the UI is drawn in, or null and
config.subpass = 0;                     // color_format (+ depth/stencil formats) for
config.samples = VK_SAMPLE_COUNT_1_BIT; // dynamic rendering
renderer.init(config);

ui::FontRef regular{&face, renderer.create_font_texture(face)};

// every frame, after waiting for frame slot `frame`:
renderer.begin();
renderer.backdrop(sky);
renderer.draw(list);
renderer.prepare(cmd, frame);           // outside any pass: uploads, glass copies
vkCmdBeginRenderPass(cmd, ...);         // or vkCmdBeginRendering
renderer.draw(cmd, width, height);
vkCmdEndRenderPass(cmd);
```

- **Only Vulkan 1.0 features** are needed (dynamic rendering only when the
  caller draws that way). Each texture has a descriptor set of its own, the six
  font atlases share one set, and what OpenGL took as uniforms are push
  constants.
- **The caller's pass** can be anything with one colour attachment: the
  pipelines are built for `config.render_pass` and `config.subpass`, or for
  dynamic rendering into the formats given. A depth attachment in the pass is
  fine; the UI neither tests nor writes depth.
- **Frames in flight**: each slot has its own instance and mesh buffers, and
  `prepare` rewrites them, so the caller waits for the slot's previous
  submission first (Sascha Willems' base class does, in `prepareFrame`).
  Textures freed with `destroy_texture` go once no frame in flight can use
  them.
- **Glass**: OpenGL makes each glass copy in the middle of the frame. Vulkan
  records the copies in `prepare`, before the caller's pass, so each `glass()`
  of a frame gets a target of its own (up to four) and every list samples the
  copy queued last before it, as under OpenGL. Two banks of targets, used by
  alternate frames, let a list queued before any `glass()` see the last copy of
  the frame before, again as under OpenGL.
- **Row order**: targets the renderer draws into (`render_to_texture`, the
  glass copies) are stored bottom row first, as OpenGL stores them, so
  `gfx::kCanvasUv` and the glass coordinates are the same for both backends.
  The caller's pass is drawn top row first, as Vulkan presents it. The shaders
  take the target's row order as a push constant (`flip`).
- **Uploads** (`create_texture`, `create_font_texture`) and `render_to_texture`
  submit to the queue and wait for it: they belong at start-up or between
  frames, never between `prepare` and `draw`.

## The shaders

`src/gfx/vk/shaders/` holds the GLSL, each file the twin of an OpenGL shader
named in its header; change both together. `tools/compile-vk-shaders.sh`
compiles them into the `.inc` arrays `vk_renderer.cpp` includes (both are
committed; `--check` fails when an array is out of date), so a title carries no
shader files for the kit. The shape and backdrop code is the OpenGL code with
only its declarations changed.

## Checking it on a PC

```bash
tools/host-snapshots.sh build/gl all       # the tour through OpenGL (llvmpipe)
tools/host-snapshots-vk.sh build/vk all    # the same tour through Vulkan (lavapipe)
tools/compare-backends.py build/gl build/vk --diffs build/vk-diffs
```

`HUI_VK_VALIDATION=1` adds the Khronos validation layer and counts its
messages; `HUI_VK_DEVICE=<part of a name>` picks another Vulkan device.

Measured on my PC (Mesa 26.2.4, llvmpipe and lavapipe, 1920 x 1080): the 266
pictures of the whole tour have the same shape and draw-call counts under both
backends, their mean difference is 0.0012 levels in 255 (the worst picture
0.021, a sub-pixel panel edge), and the validation layer reports no message.
