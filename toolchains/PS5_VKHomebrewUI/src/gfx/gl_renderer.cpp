// ps5-homebrew-ui - OpenGL backend for the frame composition.
// Copyright (C) 2026 BlackBearReloaded
// SPDX-License-Identifier: GPL-3.0-or-later

#include "gfx/gl_renderer.hpp"

#include "gfx/gl_program.hpp"

namespace hui::gfx
{

namespace
{

// The glass copy is small on purpose: the blur hides the resolution, and a
// 480x270 target keeps both the replay and the blur passes cheap at 4K.
constexpr int kGlassWidth = 480;
constexpr int kGlassHeight = 270;

constexpr const char *kBlurVertex = R"(
out vec2 v_uv;
void main()
{
    vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
    v_uv = p;
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
)";

// Nine-tap Gaussian from five bilinear fetches (weights after Rakos).
constexpr const char *kBlurFragment = R"(
layout(location = 0) uniform sampler2D u_texture;
layout(location = 1) uniform vec2 u_step;
in vec2 v_uv;
out vec4 frag_color;
void main()
{
    vec4 c = texture(u_texture, v_uv) * 0.227027;
    c += (texture(u_texture, v_uv + u_step * 1.384615) +
          texture(u_texture, v_uv - u_step * 1.384615)) * 0.316216;
    c += (texture(u_texture, v_uv + u_step * 3.230769) +
          texture(u_texture, v_uv - u_step * 3.230769)) * 0.070270;
    frag_color = vec4(c.rgb, 1.0);
}
)";

} // namespace

GlRenderer::~GlRenderer()
{
    release();
}

bool GlRenderer::init()
{
    if (!batch_.init() || !backdrop_.init())
        return false;
    blur_program_ = build_program("blur", kBlurVertex, kBlurFragment);
    if (blur_program_ == 0)
        return false;
    glGenVertexArrays(1, &blur_vao_);
    return glass_a_.create(kGlassWidth, kGlassHeight, 1) &&
           glass_b_.create(kGlassWidth, kGlassHeight, 1);
}

void GlRenderer::release()
{
    if (blur_vao_ != 0)
        glDeleteVertexArrays(1, &blur_vao_);
    if (blur_program_ != 0)
        glDeleteProgram(blur_program_);
    blur_vao_ = blur_program_ = 0;
    glass_a_.destroy();
    glass_b_.destroy();
    backdrop_.release();
    batch_.release();
}

std::uint32_t GlRenderer::create_font_texture(const Font &font)
{
    return batch_.create_font_texture(font);
}

std::uint32_t GlRenderer::create_texture(int width, int height, const std::uint8_t *rgba)
{
    return batch_.create_texture(width, height, rgba);
}

std::uint32_t GlRenderer::render_to_texture(int width, int height, float virtual_width,
                                            float virtual_height)
{
    GLuint texture = 0;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    // One level only: mip chains leave ps5-opengl's batched fast path.
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, 0);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    GLuint framebuffer = 0;
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    const bool complete = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
    if (complete)
    {
        glViewport(0, 0, width, height);
        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        present(framebuffer, width, height, virtual_width, virtual_height);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDeleteFramebuffers(1, &framebuffer);
    if (complete)
        return texture;
    glDeleteTextures(1, &texture);
    return 0;
}

void GlRenderer::destroy_texture(std::uint32_t texture)
{
    if (texture != 0 && !is_font_handle(texture))
        glDeleteTextures(1, &texture);
}

void GlRenderer::play(const Layer &layer, int width, int height, float virtual_width,
                      float virtual_height)
{
    if (layer.kind == Kind::backdrop)
    {
        backdrop_.draw(layer.spec, width, height, layer.opacity);
        ++draw_calls_;
    }
    else if (layer.kind == Kind::list)
    {
        batch_.draw(*layer.list, fit_viewport(width, height, virtual_width, virtual_height), width,
                    height);
        draw_calls_ += batch_.last_draw_calls();
    }
}

void GlRenderer::capture_glass(std::size_t layers, float virtual_width, float virtual_height)
{
    glass_a_.bind();
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    for (std::size_t i = 0; i < layers; ++i)
        play(layers_[i], kGlassWidth, kGlassHeight, virtual_width, virtual_height);

    // Two rounds of horizontal then vertical blur, the second one wider.
    glDisable(GL_BLEND);
    glDisable(GL_SCISSOR_TEST);
    glUseProgram(blur_program_);
    glUniform1i(0, 0);
    glActiveTexture(GL_TEXTURE0);
    glBindVertexArray(blur_vao_);
    for (float step : {1.0f, 2.2f})
    {
        glass_b_.bind();
        glBindTexture(GL_TEXTURE_2D, glass_a_.texture());
        glUniform2f(1, step / static_cast<float>(kGlassWidth), 0.0f);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        glass_a_.bind();
        glBindTexture(GL_TEXTURE_2D, glass_b_.texture());
        glUniform2f(1, 0.0f, step / static_cast<float>(kGlassHeight));
        glDrawArrays(GL_TRIANGLES, 0, 3);
        draw_calls_ += 2;
    }
    glBindVertexArray(0);
}

void GlRenderer::present(GLuint framebuffer, int width, int height, float virtual_width,
                         float virtual_height)
{
    draw_calls_ = 0;
    instances_ = 0;
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glViewport(0, 0, width, height);
    for (std::size_t i = 0; i < layers_.size(); ++i)
    {
        const Layer &layer = layers_[i];
        if (layer.kind == Kind::glass)
        {
            capture_glass(i, virtual_width, virtual_height);
            glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
            glViewport(0, 0, width, height);
            continue;
        }
        if (layer.kind == Kind::list)
            instances_ += layer.list->instances().size();
        play(layer, width, height, virtual_width, virtual_height);
    }
}

} // namespace hui::gfx
