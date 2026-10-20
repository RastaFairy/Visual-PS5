// ps5-homebrew-ui - Vulkan backend for the frame composition.
// Copyright (C) 2026 BlackBearReloaded
// Copyright (C) 2026 Mihawk
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "gfx/renderer.hpp"

#include <vulkan/vulkan.h>

#include <cstddef>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace hui::gfx
{

// What the renderer draws with, and the pass it draws into. The caller
// begins that pass: a render pass (render_pass, subpass), or, with
// render_pass left null, dynamic rendering into attachments of the formats
// given here. Only Vulkan 1.0 features are used, except dynamic rendering
// when the caller draws that way.
struct VkRendererConfig
{
    VkPhysicalDevice physical_device = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    // A graphics queue: uploads and render_to_texture submit to it and wait.
    VkQueue queue = VK_NULL_HANDLE;
    std::uint32_t queue_family = 0;
    VkPipelineCache pipeline_cache = VK_NULL_HANDLE;
    std::uint32_t frames_in_flight = 2;
    VkRenderPass render_pass = VK_NULL_HANDLE;
    std::uint32_t subpass = 0;
    VkFormat color_format = VK_FORMAT_UNDEFINED; // dynamic rendering only
    VkFormat depth_format = VK_FORMAT_UNDEFINED;
    VkFormat stencil_format = VK_FORMAT_UNDEFINED;
    VkSampleCountFlagBits samples = VK_SAMPLE_COUNT_1_BIT;
};

// Plays a Renderer's queue with Vulkan. A frame:
//
//   renderer.begin(); ... backdrop / draw / glass ...   queue the layers
//   renderer.prepare(cmd, frame);   outside any pass: uploads the frame's
//                                   instances, records the glass copies
//   (the caller begins its pass)
//   renderer.draw(cmd, width, height);   records the layers into that pass
//
// frame is the frame-in-flight slot (0 .. frames_in_flight - 1); the caller
// has waited for that slot's previous submission, so its buffers are free.
//
// OpenGL plays the glass copies in the middle of the frame; Vulkan records
// them ahead of the caller's pass, so each glass() of a frame gets a target
// of its own and every list samples the copy queued last before it, as it
// would under OpenGL. A list queued before any glass() of the frame sees the
// last copy of the frame before.
//
// Targets the renderer draws into (render_to_texture, the glass copies) are
// stored bottom row first, as OpenGL stores them, so kCanvasUv and the glass
// coordinates stay as they are; the caller's pass is drawn top row first.
class VkRenderer final : public Renderer
{
  public:
    VkRenderer() = default;
    ~VkRenderer() override;

    bool init(const VkRendererConfig &config);
    // Waits for the device to be idle, then destroys everything init() made.
    void release();

    std::uint32_t create_font_texture(const Font &font) override;
    std::uint32_t create_texture(int width, int height, const std::uint8_t *rgba) override;
    std::uint32_t render_to_texture(int width, int height, float virtual_width,
                                    float virtual_height) override;
    void destroy_texture(std::uint32_t texture) override;
    std::uint32_t glass_texture() const override
    {
        return kGlassHandle;
    }

    // A sampled image the program owns (a 3D scene it renders off-screen, a
    // video frame), drawn like any texture: DrawList::image(handle, ...), and
    // replayed into the glass copies, so frosted panels blur it. The view
    // stays the program's: it is in SHADER_READ_ONLY_OPTIMAL whenever a frame
    // that draws it runs, and outlives those frames. destroy_texture forgets
    // the handle without touching the image. An image the program renders
    // top row first is drawn with kFullUv.
    std::uint32_t import_texture(VkImageView view);

    void prepare(VkCommandBuffer cmd, std::uint32_t frame, float virtual_width = kVirtualWidth,
                 float virtual_height = kVirtualHeight);
    // Queuing a list stays Renderer::draw(list); this overload records the frame.
    using Renderer::draw;
    void draw(VkCommandBuffer cmd, int width, int height);

    // The last call that failed, for the log (VK_SUCCESS when none has).
    VkResult last_error() const
    {
        return error_;
    }

    // The handle glass_texture() returns: the batch binds the frame's glass
    // copy wherever a run uses it.
    static constexpr std::uint32_t kGlassHandle = 0xf0000100u;

  private:
    static constexpr int kMaxGlass = 4; // glass() calls per frame with a target of their own

    struct Buffer
    {
        VkBuffer buffer = VK_NULL_HANDLE;
        VkDeviceMemory memory = VK_NULL_HANDLE;
        void *mapped = nullptr;
        VkDeviceSize size = 0;
    };
    struct Image
    {
        VkImage image = VK_NULL_HANDLE;
        VkDeviceMemory memory = VK_NULL_HANDLE;
        VkImageView view = VK_NULL_HANDLE;
        VkFramebuffer framebuffer = VK_NULL_HANDLE; // targets only
        VkDescriptorSet set = VK_NULL_HANDLE;       // samples the image
        int width = 0;
        int height = 0;
        bool owned = true; // false: an imported view, the program's to destroy
    };
    struct Pipelines
    {
        VkPipeline batch = VK_NULL_HANDLE;
        VkPipeline mesh = VK_NULL_HANDLE;
        VkPipeline backdrop_opaque = VK_NULL_HANDLE;
        VkPipeline backdrop_blend = VK_NULL_HANDLE;
    };
    struct LayerData
    {
        std::uint32_t instance_base = 0; // into the frame's instance buffer
        std::uint32_t mesh_base = 0;     // into its mesh buffer
        const Image *glass = nullptr;    // the copy kGlassHandle means for this layer
    };
    struct Retired
    {
        Image image;
        VkDescriptorSet set = VK_NULL_HANDLE;
        std::uint64_t serial = 0;
    };

    bool check(VkResult result);
    std::uint32_t memory_type(std::uint32_t bits, VkMemoryPropertyFlags flags) const;
    bool create_buffer(Buffer &buffer, VkDeviceSize size, VkBufferUsageFlags usage);
    void destroy_buffer(Buffer &buffer);
    bool reserve(Buffer &buffer, VkDeviceSize size, VkBufferUsageFlags usage);
    bool create_image(Image &image, int width, int height, VkFormat format, bool target);
    void destroy_image(Image &image);
    VkCommandBuffer begin_one_shot();
    bool end_one_shot(VkCommandBuffer cmd);
    bool upload(Image &image, const void *pixels, VkDeviceSize bytes);
    bool clear_target(Image &image);
    bool write_font_set();
    void retire(const Image &image);
    void collect(bool all);
    VkPipeline make_pipeline(VkShaderModule vertex, VkShaderModule fragment,
                             const VkPipelineVertexInputStateCreateInfo &input, bool blend,
                             VkPipelineLayout layout, bool target);
    bool make_pipelines(Pipelines &pipelines, bool target);
    const Image *glass_target(int bank, int index);

    void record(VkCommandBuffer cmd, std::uint32_t slot, float virtual_width, float virtual_height);
    void capture_glass(VkCommandBuffer cmd, std::size_t layers, const Image &target);
    void blur_pass(VkCommandBuffer cmd, const Image &source, const Image &target, float step_x,
                   float step_y);
    void play(VkCommandBuffer cmd, std::size_t layer, const Pipelines &pipelines, int width,
              int height, float flip);
    void draw_list(VkCommandBuffer cmd, std::size_t layer, const Pipelines &pipelines, int width,
                   int height, float flip);
    void begin_offscreen(VkCommandBuffer cmd, VkRenderPass pass, const Image &target,
                         const float clear[4]);

    VkRendererConfig config_{};
    VkPhysicalDeviceMemoryProperties memory_properties_{};
    VkResult error_ = VK_SUCCESS;

    VkCommandPool command_pool_ = VK_NULL_HANDLE;
    VkSampler sampler_ = VK_NULL_HANDLE;
    VkDescriptorSetLayout font_layout_ = VK_NULL_HANDLE;
    VkDescriptorSetLayout texture_layout_ = VK_NULL_HANDLE;
    VkDescriptorPool descriptor_pool_ = VK_NULL_HANDLE;
    VkPipelineLayout batch_layout_ = VK_NULL_HANDLE;
    VkPipelineLayout backdrop_layout_ = VK_NULL_HANDLE;
    VkPipelineLayout blur_layout_ = VK_NULL_HANDLE;
    // Off-screen passes into RGBA8 targets: one clears, one overwrites.
    VkRenderPass clear_pass_ = VK_NULL_HANDLE;
    VkRenderPass overwrite_pass_ = VK_NULL_HANDLE;
    Pipelines target_{};
    Pipelines offscreen_{};
    VkPipeline blur_ = VK_NULL_HANDLE;

    Image dummy_; // bound where a run has no texture of its own
    Image fonts_[kFontSlots];
    std::uint32_t font_count_ = 0;
    VkDescriptorSet font_set_ = VK_NULL_HANDLE;
    std::unordered_map<std::uint32_t, Image> textures_;
    std::uint32_t next_texture_ = 1;
    std::vector<Retired> retired_;

    // Two banks, used by alternate frames, so a frame can still read the
    // last copy of the frame before while it writes its own.
    Image glass_[2][kMaxGlass];
    int glass_count_[2] = {0, 0};
    int bank_ = 0;
    Image glass_scratch_;

    // One instance and one mesh buffer per frame in flight, and one more for
    // render_to_texture.
    std::vector<Buffer> instance_buffers_;
    std::vector<Buffer> mesh_buffers_;
    std::vector<LayerData> layer_data_;
    std::uint32_t slot_ = 0;
    std::uint64_t serial_ = 0;
    float virtual_width_ = kVirtualWidth;
    float virtual_height_ = kVirtualHeight;
};

} // namespace hui::gfx
