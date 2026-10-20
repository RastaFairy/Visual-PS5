// ps5-homebrew-ui - OpenGL backend for the frame composition.
// Copyright (C) 2026 BlackBearReloaded
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "gfx/backdrop.hpp"
#include "gfx/canvas.hpp"
#include "gfx/gl_batch.hpp"
#include "gfx/renderer.hpp"

#include <GL/glcorearb.h>

#include <cstddef>
#include <cstdint>

namespace hui::gfx
{

// Plays a Renderer's queue with OpenGL: one GlBatch for the draw lists, one
// Backdrop program, and two small canvases that hold the glass copy.
class GlRenderer final : public Renderer
{
  public:
    GlRenderer() = default;
    ~GlRenderer() override;

    // Needs the GL context. release() deletes everything init() made.
    bool init();
    void release();

    GlBatch &batch()
    {
        return batch_;
    }
    Backdrop &backdrops()
    {
        return backdrop_;
    }

    std::uint32_t create_font_texture(const Font &font) override;
    std::uint32_t create_texture(int width, int height, const std::uint8_t *rgba) override;
    std::uint32_t render_to_texture(int width, int height, float virtual_width,
                                    float virtual_height) override;
    void destroy_texture(std::uint32_t texture) override;
    std::uint32_t glass_texture() const override
    {
        return glass_a_.texture();
    }

    // Draws the queued layers into framebuffer (0 is the display). The
    // virtual size is the coordinate space of the lists.
    void present(GLuint framebuffer, int width, int height, float virtual_width = kVirtualWidth,
                 float virtual_height = kVirtualHeight);

  private:
    void play(const Layer &layer, int width, int height, float virtual_width, float virtual_height);
    void capture_glass(std::size_t layers, float virtual_width, float virtual_height);

    GlBatch batch_;
    Backdrop backdrop_;
    Canvas glass_a_;
    Canvas glass_b_;
    GLuint blur_program_ = 0;
    GLuint blur_vao_ = 0;
};

} // namespace hui::gfx
