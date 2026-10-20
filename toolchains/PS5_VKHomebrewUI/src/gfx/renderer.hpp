// ps5-homebrew-ui - Frame composition: backdrops, draw lists and frosted glass.
// Copyright (C) 2026 BlackBearReloaded
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "gfx/backdrop_spec.hpp"
#include "gfx/draw_list.hpp"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace hui::gfx
{

class Font;

// Composes one frame from a short list of layers, drawn back to front:
//
//   backdrop(spec)   a procedural full-screen shader (or a post overlay)
//   draw(list)       a DrawList of shapes, text and images
//   glass()          blurs everything queued so far into glass_texture(), so
//                    that later lists can draw frosted panels over it
//
// The glass copy is made by replaying the earlier layers into a small
// off-screen canvas and blurring that, so it costs nothing on frames that do
// not ask for it and never reads the display surface back.
//
// PS5_VKHomebrewUI: the queue and the texture calls are the same for every
// graphics API, so the shell, the designs and the sample content see only
// this class. A backend plays the queue and owns the textures: GlRenderer
// (gfx/gl_renderer.hpp) with OpenGL, VkRenderer (gfx/vk/) with Vulkan.
class Renderer
{
  public:
    Renderer() = default;
    Renderer(const Renderer &) = delete;
    Renderer &operator=(const Renderer &) = delete;
    virtual ~Renderer() = default;

    // ---- textures ----
    // Uploads a font atlas as a single-channel texture and gives it one of
    // the font slots; returns the handle DrawList::text takes. With every
    // slot taken it returns a plain texture handle, which also works but
    // starts a new draw call wherever that font is used.
    virtual std::uint32_t create_font_texture(const Font &font) = 0;
    // Uploads RGBA8 pixels, top row first, as a single-level texture; draw
    // it with kFullUv. Returns its handle.
    virtual std::uint32_t create_texture(int width, int height, const std::uint8_t *rgba) = 0;
    // Plays the queued layers into a new width x height texture laid out in
    // a virtual_width x virtual_height space, and returns its handle (0 on
    // failure). Like every target the renderer draws into, it is stored
    // bottom row first: draw it with kCanvasUv.
    virtual std::uint32_t render_to_texture(int width, int height, float virtual_width,
                                            float virtual_height) = 0;
    // Frees a texture made by create_texture or render_to_texture.
    virtual void destroy_texture(std::uint32_t texture) = 0;
    // The texture later lists pass to DrawList::glass(). The handle is
    // stable from initialisation on; a list that draws it sees the glass()
    // queued last before that list.
    virtual std::uint32_t glass_texture() const = 0;

    // ---- queue a frame ----
    void begin();
    void backdrop(const BackdropSpec &spec, float opacity = 1.0f);
    void draw(const DrawList &list);
    void glass();

    std::size_t last_draw_calls() const
    {
        return draw_calls_;
    }
    std::size_t last_instances() const
    {
        return instances_;
    }

  protected:
    enum class Kind : std::uint8_t
    {
        backdrop,
        list,
        glass,
    };
    struct Layer
    {
        Kind kind = Kind::list;
        BackdropSpec spec;
        float opacity = 1.0f;
        const DrawList *list = nullptr;
    };

    std::vector<Layer> layers_;
    std::size_t draw_calls_ = 0;
    std::size_t instances_ = 0;
};

} // namespace hui::gfx
