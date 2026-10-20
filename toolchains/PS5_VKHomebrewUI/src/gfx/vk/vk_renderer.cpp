// ps5-homebrew-ui - Vulkan backend for the frame composition.
// Copyright (C) 2026 BlackBearReloaded
// Copyright (C) 2026 Mihawk
// SPDX-License-Identifier: GPL-3.0-or-later

#include "gfx/vk/vk_renderer.hpp"

#include "gfx/font.hpp"

#include <stdint.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <iterator>

namespace hui::gfx
{

namespace
{

// SPIR-V of src/gfx/vk/shaders/*, made by tools/compile-vk-shaders.sh.
#include "gfx/vk/shaders/backdrop.frag.inc"
#include "gfx/vk/shaders/batch.frag.inc"
#include "gfx/vk/shaders/batch.vert.inc"
#include "gfx/vk/shaders/blur.frag.inc"
#include "gfx/vk/shaders/fullscreen.vert.inc"
#include "gfx/vk/shaders/mesh.frag.inc"
#include "gfx/vk/shaders/mesh.vert.inc"

// The glass copy is small on purpose: the blur hides the resolution, and a
// 480x270 target keeps both the replay and the blur passes cheap at 4K.
constexpr int kGlassWidth = 480;
constexpr int kGlassHeight = 270;
// Targets the renderer draws into, as OpenGL's GL_RGBA8 canvases.
constexpr VkFormat kTargetFormat = VK_FORMAT_R8G8B8A8_UNORM;
// Descriptor sets: one per texture, plus the font sets.
constexpr std::uint32_t kMaxSets = 4096;
constexpr std::uint32_t kMaxFontSets = 16;

// Push constants, laid out as the shaders declare them.
struct BatchPush
{
    float viewport[4]; // scale, offset x, offset y, unused
    float surface[2];
    float flip;
    float unused;
};
static_assert(sizeof(BatchPush) == 32);

struct BackdropPush
{
    float resolution[2];
    float time;
    std::int32_t mode;
    float colors[16];
    float params[4];
    float opacity;
    float flip;
};
static_assert(sizeof(BackdropPush) == 104);

struct BlurPush
{
    float step[2];
};

template <std::size_t N> VkShaderModule make_module(VkDevice device, const std::uint32_t (&code)[N])
{
    VkShaderModuleCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    info.codeSize = sizeof(code);
    info.pCode = code;
    VkShaderModule module = VK_NULL_HANDLE;
    if (vkCreateShaderModule(device, &info, nullptr, &module) != VK_SUCCESS)
        return VK_NULL_HANDLE;
    return module;
}

void set_viewport(VkCommandBuffer cmd, int width, int height)
{
    const VkViewport viewport{0.0f, 0.0f, static_cast<float>(width), static_cast<float>(height),
                              0.0f, 1.0f};
    const VkRect2D scissor{{0, 0},
                           {static_cast<std::uint32_t>(width), static_cast<std::uint32_t>(height)}};
    vkCmdSetViewport(cmd, 0, 1, &viewport);
    vkCmdSetScissor(cmd, 0, 1, &scissor);
}

} // namespace

VkRenderer::~VkRenderer()
{
    release();
}

bool VkRenderer::check(VkResult result)
{
    if (result == VK_SUCCESS)
        return true;
    error_ = result;
    return false;
}

std::uint32_t VkRenderer::memory_type(std::uint32_t bits, VkMemoryPropertyFlags flags) const
{
    for (std::uint32_t i = 0; i < memory_properties_.memoryTypeCount; ++i)
        if ((bits & (1u << i)) != 0 &&
            (memory_properties_.memoryTypes[i].propertyFlags & flags) == flags)
            return i;
    return UINT32_MAX;
}

bool VkRenderer::init(const VkRendererConfig &config)
{
    release();
    config_ = config;
    config_.frames_in_flight = std::max(1u, config_.frames_in_flight);
    const VkDevice device = config_.device;
    vkGetPhysicalDeviceMemoryProperties(config_.physical_device, &memory_properties_);

    VkCommandPoolCreateInfo pool_info{};
    pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool_info.flags =
        VK_COMMAND_POOL_CREATE_TRANSIENT_BIT | VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pool_info.queueFamilyIndex = config_.queue_family;
    if (!check(vkCreateCommandPool(device, &pool_info, nullptr, &command_pool_)))
        return false;

    // Linear, clamped, one level: OpenGL's textures here are the same.
    VkSamplerCreateInfo sampler{};
    sampler.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    sampler.magFilter = VK_FILTER_LINEAR;
    sampler.minFilter = VK_FILTER_LINEAR;
    sampler.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
    sampler.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sampler.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sampler.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sampler.maxLod = 0.0f;
    sampler.borderColor = VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK;
    if (!check(vkCreateSampler(device, &sampler, nullptr, &sampler_)))
        return false;

    VkDescriptorSetLayoutBinding binding{};
    binding.binding = 0;
    binding.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    binding.descriptorCount = kFontSlots;
    binding.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
    VkDescriptorSetLayoutCreateInfo set_layout{};
    set_layout.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    set_layout.bindingCount = 1;
    set_layout.pBindings = &binding;
    if (!check(vkCreateDescriptorSetLayout(device, &set_layout, nullptr, &font_layout_)))
        return false;
    binding.descriptorCount = 1;
    if (!check(vkCreateDescriptorSetLayout(device, &set_layout, nullptr, &texture_layout_)))
        return false;

    const VkDescriptorPoolSize pool_size{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                                         kMaxSets + kMaxFontSets * kFontSlots};
    VkDescriptorPoolCreateInfo descriptor_pool{};
    descriptor_pool.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    descriptor_pool.flags = VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT;
    descriptor_pool.maxSets = kMaxSets + kMaxFontSets;
    descriptor_pool.poolSizeCount = 1;
    descriptor_pool.pPoolSizes = &pool_size;
    if (!check(vkCreateDescriptorPool(device, &descriptor_pool, nullptr, &descriptor_pool_)))
        return false;

    const VkDescriptorSetLayout batch_sets[2] = {font_layout_, texture_layout_};
    const VkPushConstantRange batch_push{VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                                         0, sizeof(BatchPush)};
    const VkPushConstantRange backdrop_push{VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(BackdropPush)};
    const VkPushConstantRange blur_push{VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(BlurPush)};
    VkPipelineLayoutCreateInfo layout{};
    layout.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    layout.setLayoutCount = 2;
    layout.pSetLayouts = batch_sets;
    layout.pushConstantRangeCount = 1;
    layout.pPushConstantRanges = &batch_push;
    if (!check(vkCreatePipelineLayout(device, &layout, nullptr, &batch_layout_)))
        return false;
    layout.setLayoutCount = 0;
    layout.pPushConstantRanges = &backdrop_push;
    if (!check(vkCreatePipelineLayout(device, &layout, nullptr, &backdrop_layout_)))
        return false;
    layout.setLayoutCount = 1;
    layout.pSetLayouts = &texture_layout_;
    layout.pPushConstantRanges = &blur_push;
    if (!check(vkCreatePipelineLayout(device, &layout, nullptr, &blur_layout_)))
        return false;

    // The off-screen passes leave their target ready to be sampled. Their
    // dependencies order them after earlier reads and writes of the same
    // target (the frame before may still be sampling a glass copy) and make
    // the result visible to the fragment shaders and copies that follow.
    for (VkRenderPass *pass : {&clear_pass_, &overwrite_pass_})
    {
        VkAttachmentDescription attachment{};
        attachment.format = kTargetFormat;
        attachment.samples = VK_SAMPLE_COUNT_1_BIT;
        attachment.loadOp =
            pass == &clear_pass_ ? VK_ATTACHMENT_LOAD_OP_CLEAR : VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        attachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
        attachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        attachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        attachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        attachment.finalLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        const VkAttachmentReference color{0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
        VkSubpassDescription subpass{};
        subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
        subpass.colorAttachmentCount = 1;
        subpass.pColorAttachments = &color;
        VkSubpassDependency dependencies[2]{};
        dependencies[0].srcSubpass = VK_SUBPASS_EXTERNAL;
        dependencies[0].dstSubpass = 0;
        dependencies[0].srcStageMask = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT |
                                       VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                                       VK_PIPELINE_STAGE_TRANSFER_BIT;
        dependencies[0].srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        dependencies[0].dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dependencies[0].dstAccessMask =
            VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        dependencies[1].srcSubpass = 0;
        dependencies[1].dstSubpass = VK_SUBPASS_EXTERNAL;
        dependencies[1].srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dependencies[1].srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        dependencies[1].dstStageMask =
            VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT | VK_PIPELINE_STAGE_TRANSFER_BIT;
        dependencies[1].dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_TRANSFER_READ_BIT;
        VkRenderPassCreateInfo info{};
        info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
        info.attachmentCount = 1;
        info.pAttachments = &attachment;
        info.subpassCount = 1;
        info.pSubpasses = &subpass;
        info.dependencyCount = 2;
        info.pDependencies = dependencies;
        if (!check(vkCreateRenderPass(device, &info, nullptr, pass)))
            return false;
    }

    if (!make_pipelines(offscreen_, false) || !make_pipelines(target_, true))
        return false;

    instance_buffers_.resize(config_.frames_in_flight + 1);
    mesh_buffers_.resize(config_.frames_in_flight + 1);

    const std::uint8_t transparent[4] = {0, 0, 0, 0};
    if (!create_image(dummy_, 1, 1, VK_FORMAT_R8G8B8A8_UNORM, false) ||
        !upload(dummy_, transparent, sizeof(transparent)) || !write_font_set())
        return false;
    // The first copy of each bank exists from the start, cleared, because a
    // frame may read the other bank's copy before any frame has written one.
    const Image *first = glass_target(0, 0);
    const Image *second = glass_target(1, 0);
    return first != nullptr && second != nullptr && clear_target(glass_[0][0]) &&
           clear_target(glass_[1][0]) &&
           create_image(glass_scratch_, kGlassWidth, kGlassHeight, kTargetFormat, true);
}

VkPipeline VkRenderer::make_pipeline(VkShaderModule vertex, VkShaderModule fragment,
                                     const VkPipelineVertexInputStateCreateInfo &input, bool blend,
                                     VkPipelineLayout layout, bool target)
{
    VkPipelineShaderStageCreateInfo stages[2]{};
    stages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = vertex;
    stages[0].pName = "main";
    stages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = fragment;
    stages[1].pName = "main";
    VkPipelineInputAssemblyStateCreateInfo assembly{};
    assembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkPipelineViewportStateCreateInfo viewport{};
    viewport.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewport.viewportCount = 1;
    viewport.scissorCount = 1;
    VkPipelineRasterizationStateCreateInfo raster{};
    raster.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    raster.polygonMode = VK_POLYGON_MODE_FILL;
    raster.cullMode = VK_CULL_MODE_NONE;
    raster.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    raster.lineWidth = 1.0f;
    VkPipelineMultisampleStateCreateInfo multisample{};
    multisample.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisample.rasterizationSamples = target ? config_.samples : VK_SAMPLE_COUNT_1_BIT;
    VkPipelineDepthStencilStateCreateInfo depth{};
    depth.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    depth.depthCompareOp = VK_COMPARE_OP_ALWAYS;
    // Straight alpha in, premultiplied coverage kept in the target's alpha:
    // glBlendFuncSeparate(SRC_ALPHA, ONE_MINUS_SRC_ALPHA, ONE, ONE_MINUS_SRC_ALPHA).
    VkPipelineColorBlendAttachmentState attachment{};
    attachment.blendEnable = blend ? VK_TRUE : VK_FALSE;
    attachment.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
    attachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    attachment.colorBlendOp = VK_BLEND_OP_ADD;
    attachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
    attachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    attachment.alphaBlendOp = VK_BLEND_OP_ADD;
    attachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                                VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    VkPipelineColorBlendStateCreateInfo color{};
    color.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    color.attachmentCount = 1;
    color.pAttachments = &attachment;
    const VkDynamicState states[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dynamic{};
    dynamic.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamic.dynamicStateCount = static_cast<std::uint32_t>(std::size(states));
    dynamic.pDynamicStates = states;
    VkPipelineRenderingCreateInfo rendering{};
    rendering.sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO;
    rendering.colorAttachmentCount = 1;
    rendering.pColorAttachmentFormats = &config_.color_format;
    rendering.depthAttachmentFormat = config_.depth_format;
    rendering.stencilAttachmentFormat = config_.stencil_format;

    VkGraphicsPipelineCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    info.stageCount = 2;
    info.pStages = stages;
    info.pVertexInputState = &input;
    info.pInputAssemblyState = &assembly;
    info.pViewportState = &viewport;
    info.pRasterizationState = &raster;
    info.pMultisampleState = &multisample;
    info.pDepthStencilState = &depth;
    info.pColorBlendState = &color;
    info.pDynamicState = &dynamic;
    info.layout = layout;
    if (target)
    {
        info.renderPass = config_.render_pass;
        info.subpass = config_.subpass;
        if (config_.render_pass == VK_NULL_HANDLE)
            info.pNext = &rendering;
    }
    else
    {
        info.renderPass = clear_pass_; // compatible with overwrite_pass_
    }
    VkPipeline pipeline = VK_NULL_HANDLE;
    if (!check(vkCreateGraphicsPipelines(config_.device, config_.pipeline_cache, 1, &info, nullptr,
                                         &pipeline)))
        return VK_NULL_HANDLE;
    return pipeline;
}

bool VkRenderer::make_pipelines(Pipelines &pipelines, bool target)
{
    const VkDevice device = config_.device;
    const VkShaderModule batch_vertex = make_module(device, kBatchVert);
    const VkShaderModule batch_fragment = make_module(device, kBatchFrag);
    const VkShaderModule mesh_vertex = make_module(device, kMeshVert);
    const VkShaderModule mesh_fragment = make_module(device, kMeshFrag);
    const VkShaderModule fullscreen = make_module(device, kFullscreenVert);
    const VkShaderModule backdrop = make_module(device, kBackdropFrag);
    const VkShaderModule blur = make_module(device, kBlurFrag);

    // One quad per instance: six vec4 attributes, read once per instance.
    const VkVertexInputBindingDescription batch_binding{0, sizeof(Instance),
                                                        VK_VERTEX_INPUT_RATE_INSTANCE};
    VkVertexInputAttributeDescription batch_attributes[6]{};
    for (std::uint32_t i = 0; i < 6; ++i)
        batch_attributes[i] = {i, 0, VK_FORMAT_R32G32B32A32_SFLOAT, i * 16};
    VkPipelineVertexInputStateCreateInfo batch_input{};
    batch_input.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    batch_input.vertexBindingDescriptionCount = 1;
    batch_input.pVertexBindingDescriptions = &batch_binding;
    batch_input.vertexAttributeDescriptionCount = 6;
    batch_input.pVertexAttributeDescriptions = batch_attributes;

    const VkVertexInputBindingDescription mesh_binding{0, sizeof(MeshVertex),
                                                       VK_VERTEX_INPUT_RATE_VERTEX};
    const VkVertexInputAttributeDescription mesh_attributes[2] = {
        {0, 0, VK_FORMAT_R32G32_SFLOAT, 0},
        {1, 0, VK_FORMAT_R32G32B32A32_SFLOAT, 8},
    };
    VkPipelineVertexInputStateCreateInfo mesh_input = batch_input;
    mesh_input.pVertexBindingDescriptions = &mesh_binding;
    mesh_input.vertexAttributeDescriptionCount = 2;
    mesh_input.pVertexAttributeDescriptions = mesh_attributes;

    VkPipelineVertexInputStateCreateInfo no_input{};
    no_input.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;

    bool ok = batch_vertex != VK_NULL_HANDLE && batch_fragment != VK_NULL_HANDLE &&
              mesh_vertex != VK_NULL_HANDLE && mesh_fragment != VK_NULL_HANDLE &&
              fullscreen != VK_NULL_HANDLE && backdrop != VK_NULL_HANDLE && blur != VK_NULL_HANDLE;
    if (ok)
    {
        pipelines.batch =
            make_pipeline(batch_vertex, batch_fragment, batch_input, true, batch_layout_, target);
        pipelines.mesh =
            make_pipeline(mesh_vertex, mesh_fragment, mesh_input, true, batch_layout_, target);
        pipelines.backdrop_opaque =
            make_pipeline(fullscreen, backdrop, no_input, false, backdrop_layout_, target);
        pipelines.backdrop_blend =
            make_pipeline(fullscreen, backdrop, no_input, true, backdrop_layout_, target);
        if (!target)
            blur_ = make_pipeline(fullscreen, blur, no_input, false, blur_layout_, false);
        ok = pipelines.batch != VK_NULL_HANDLE && pipelines.mesh != VK_NULL_HANDLE &&
             pipelines.backdrop_opaque != VK_NULL_HANDLE &&
             pipelines.backdrop_blend != VK_NULL_HANDLE && (target || blur_ != VK_NULL_HANDLE);
    }
    for (VkShaderModule module :
         {batch_vertex, batch_fragment, mesh_vertex, mesh_fragment, fullscreen, backdrop, blur})
        if (module != VK_NULL_HANDLE)
            vkDestroyShaderModule(device, module, nullptr);
    return ok;
}

void VkRenderer::release()
{
    if (config_.device == VK_NULL_HANDLE)
        return;
    const VkDevice device = config_.device;
    vkDeviceWaitIdle(device);
    collect(true);
    for (auto &entry : textures_)
        destroy_image(entry.second);
    textures_.clear();
    for (Image &font : fonts_)
        destroy_image(font);
    font_count_ = 0;
    font_set_ = VK_NULL_HANDLE; // freed with the pool
    destroy_image(dummy_);
    for (auto &bank : glass_)
        for (Image &image : bank)
            destroy_image(image);
    destroy_image(glass_scratch_);
    glass_count_[0] = glass_count_[1] = 0;
    for (Buffer &buffer : instance_buffers_)
        destroy_buffer(buffer);
    for (Buffer &buffer : mesh_buffers_)
        destroy_buffer(buffer);
    instance_buffers_.clear();
    mesh_buffers_.clear();
    layer_data_.clear();
    for (Pipelines *pipelines : {&target_, &offscreen_})
    {
        for (VkPipeline pipeline : {pipelines->batch, pipelines->mesh, pipelines->backdrop_opaque,
                                    pipelines->backdrop_blend})
            if (pipeline != VK_NULL_HANDLE)
                vkDestroyPipeline(device, pipeline, nullptr);
        *pipelines = {};
    }
    if (blur_ != VK_NULL_HANDLE)
        vkDestroyPipeline(device, blur_, nullptr);
    for (VkPipelineLayout layout : {batch_layout_, backdrop_layout_, blur_layout_})
        if (layout != VK_NULL_HANDLE)
            vkDestroyPipelineLayout(device, layout, nullptr);
    for (VkRenderPass pass : {clear_pass_, overwrite_pass_})
        if (pass != VK_NULL_HANDLE)
            vkDestroyRenderPass(device, pass, nullptr);
    if (descriptor_pool_ != VK_NULL_HANDLE)
        vkDestroyDescriptorPool(device, descriptor_pool_, nullptr);
    for (VkDescriptorSetLayout layout : {font_layout_, texture_layout_})
        if (layout != VK_NULL_HANDLE)
            vkDestroyDescriptorSetLayout(device, layout, nullptr);
    if (sampler_ != VK_NULL_HANDLE)
        vkDestroySampler(device, sampler_, nullptr);
    if (command_pool_ != VK_NULL_HANDLE)
        vkDestroyCommandPool(device, command_pool_, nullptr);
    blur_ = VK_NULL_HANDLE;
    batch_layout_ = backdrop_layout_ = blur_layout_ = VK_NULL_HANDLE;
    clear_pass_ = overwrite_pass_ = VK_NULL_HANDLE;
    descriptor_pool_ = VK_NULL_HANDLE;
    font_layout_ = texture_layout_ = VK_NULL_HANDLE;
    sampler_ = VK_NULL_HANDLE;
    command_pool_ = VK_NULL_HANDLE;
    config_ = {};
    next_texture_ = 1;
    serial_ = 0;
}

bool VkRenderer::create_buffer(Buffer &buffer, VkDeviceSize size, VkBufferUsageFlags usage)
{
    const VkDevice device = config_.device;
    VkBufferCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    info.size = size;
    info.usage = usage;
    info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if (!check(vkCreateBuffer(device, &info, nullptr, &buffer.buffer)))
        return false;
    VkMemoryRequirements requirements{};
    vkGetBufferMemoryRequirements(device, buffer.buffer, &requirements);
    VkMemoryAllocateInfo allocate{};
    allocate.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocate.allocationSize = requirements.size;
    allocate.memoryTypeIndex =
        memory_type(requirements.memoryTypeBits,
                    VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (allocate.memoryTypeIndex == UINT32_MAX ||
        !check(vkAllocateMemory(device, &allocate, nullptr, &buffer.memory)) ||
        !check(vkBindBufferMemory(device, buffer.buffer, buffer.memory, 0)) ||
        !check(vkMapMemory(device, buffer.memory, 0, VK_WHOLE_SIZE, 0, &buffer.mapped)))
    {
        destroy_buffer(buffer);
        return false;
    }
    buffer.size = size;
    return true;
}

void VkRenderer::destroy_buffer(Buffer &buffer)
{
    const VkDevice device = config_.device;
    if (buffer.buffer != VK_NULL_HANDLE)
        vkDestroyBuffer(device, buffer.buffer, nullptr);
    if (buffer.memory != VK_NULL_HANDLE)
        vkFreeMemory(device, buffer.memory, nullptr); // unmaps it
    buffer = {};
}

bool VkRenderer::reserve(Buffer &buffer, VkDeviceSize size, VkBufferUsageFlags usage)
{
    if (buffer.buffer != VK_NULL_HANDLE && buffer.size >= size)
        return true;
    // The slot's previous submission has finished, so its buffer can go now.
    const VkDeviceSize grown = std::max<VkDeviceSize>({size, buffer.size * 3 / 2, 64 * 1024});
    destroy_buffer(buffer);
    return create_buffer(buffer, grown, usage);
}

bool VkRenderer::create_image(Image &image, int width, int height, VkFormat format, bool target)
{
    const VkDevice device = config_.device;
    image.width = width;
    image.height = height;
    VkImageCreateInfo info{};
    info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    info.imageType = VK_IMAGE_TYPE_2D;
    info.format = format;
    info.extent = {static_cast<std::uint32_t>(width), static_cast<std::uint32_t>(height), 1};
    info.mipLevels = 1;
    info.arrayLayers = 1;
    info.samples = VK_SAMPLE_COUNT_1_BIT;
    info.tiling = VK_IMAGE_TILING_OPTIMAL;
    info.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    if (target)
        info.usage |= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    bool ok = check(vkCreateImage(device, &info, nullptr, &image.image));
    if (ok)
    {
        VkMemoryRequirements requirements{};
        vkGetImageMemoryRequirements(device, image.image, &requirements);
        VkMemoryAllocateInfo allocate{};
        allocate.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        allocate.allocationSize = requirements.size;
        allocate.memoryTypeIndex =
            memory_type(requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
        ok = allocate.memoryTypeIndex != UINT32_MAX &&
             check(vkAllocateMemory(device, &allocate, nullptr, &image.memory)) &&
             check(vkBindImageMemory(device, image.image, image.memory, 0));
    }
    if (ok)
    {
        VkImageViewCreateInfo view{};
        view.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        view.image = image.image;
        view.viewType = VK_IMAGE_VIEW_TYPE_2D;
        view.format = format;
        view.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        ok = check(vkCreateImageView(device, &view, nullptr, &image.view));
    }
    if (ok && target)
    {
        VkFramebufferCreateInfo framebuffer{};
        framebuffer.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        framebuffer.renderPass = clear_pass_;
        framebuffer.attachmentCount = 1;
        framebuffer.pAttachments = &image.view;
        framebuffer.width = static_cast<std::uint32_t>(width);
        framebuffer.height = static_cast<std::uint32_t>(height);
        framebuffer.layers = 1;
        ok = check(vkCreateFramebuffer(device, &framebuffer, nullptr, &image.framebuffer));
    }
    if (ok)
    {
        VkDescriptorSetAllocateInfo allocate{};
        allocate.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocate.descriptorPool = descriptor_pool_;
        allocate.descriptorSetCount = 1;
        allocate.pSetLayouts = &texture_layout_;
        ok = check(vkAllocateDescriptorSets(device, &allocate, &image.set));
    }
    if (!ok)
    {
        destroy_image(image);
        return false;
    }
    const VkDescriptorImageInfo descriptor{sampler_, image.view,
                                           VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
    VkWriteDescriptorSet write{};
    write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write.dstSet = image.set;
    write.descriptorCount = 1;
    write.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    write.pImageInfo = &descriptor;
    vkUpdateDescriptorSets(device, 1, &write, 0, nullptr);
    return true;
}

void VkRenderer::destroy_image(Image &image)
{
    const VkDevice device = config_.device;
    if (image.set != VK_NULL_HANDLE)
        vkFreeDescriptorSets(device, descriptor_pool_, 1, &image.set);
    if (image.framebuffer != VK_NULL_HANDLE)
        vkDestroyFramebuffer(device, image.framebuffer, nullptr);
    if (image.owned)
    {
        if (image.view != VK_NULL_HANDLE)
            vkDestroyImageView(device, image.view, nullptr);
        if (image.image != VK_NULL_HANDLE)
            vkDestroyImage(device, image.image, nullptr);
        if (image.memory != VK_NULL_HANDLE)
            vkFreeMemory(device, image.memory, nullptr);
    }
    image = {};
}

VkCommandBuffer VkRenderer::begin_one_shot()
{
    VkCommandBufferAllocateInfo allocate{};
    allocate.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocate.commandPool = command_pool_;
    allocate.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocate.commandBufferCount = 1;
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    if (!check(vkAllocateCommandBuffers(config_.device, &allocate, &cmd)))
        return VK_NULL_HANDLE;
    VkCommandBufferBeginInfo begin{};
    begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (!check(vkBeginCommandBuffer(cmd, &begin)))
    {
        vkFreeCommandBuffers(config_.device, command_pool_, 1, &cmd);
        return VK_NULL_HANDLE;
    }
    return cmd;
}

bool VkRenderer::end_one_shot(VkCommandBuffer cmd)
{
    bool ok = check(vkEndCommandBuffer(cmd));
    if (ok)
    {
        VkSubmitInfo submit{};
        submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submit.commandBufferCount = 1;
        submit.pCommandBuffers = &cmd;
        // Uploads are rare (start-up, new art), so they simply wait. With the
        // queue idle, everything retired so far is unused and can go too.
        ok = check(vkQueueSubmit(config_.queue, 1, &submit, VK_NULL_HANDLE)) &&
             check(vkQueueWaitIdle(config_.queue));
    }
    vkFreeCommandBuffers(config_.device, command_pool_, 1, &cmd);
    if (ok)
        collect(true);
    return ok;
}

bool VkRenderer::upload(Image &image, const void *pixels, VkDeviceSize bytes)
{
    Buffer staging;
    if (!create_buffer(staging, bytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT))
        return false;
    std::memcpy(staging.mapped, pixels, static_cast<std::size_t>(bytes));
    const VkCommandBuffer cmd = begin_one_shot();
    if (cmd == VK_NULL_HANDLE)
    {
        destroy_buffer(staging);
        return false;
    }
    VkImageMemoryBarrier barrier{};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = image.image;
    barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
                         0, nullptr, 0, nullptr, 1, &barrier);
    VkBufferImageCopy copy{};
    copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    copy.imageExtent = {static_cast<std::uint32_t>(image.width),
                        static_cast<std::uint32_t>(image.height), 1};
    vkCmdCopyBufferToImage(cmd, staging.buffer, image.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                           1, &copy);
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
                         0, 0, nullptr, 0, nullptr, 1, &barrier);
    const bool ok = end_one_shot(cmd);
    destroy_buffer(staging);
    return ok;
}

bool VkRenderer::clear_target(Image &image)
{
    const VkCommandBuffer cmd = begin_one_shot();
    if (cmd == VK_NULL_HANDLE)
        return false;
    const float black[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    begin_offscreen(cmd, clear_pass_, image, black);
    vkCmdEndRenderPass(cmd);
    return end_one_shot(cmd);
}

bool VkRenderer::write_font_set()
{
    VkDescriptorSetAllocateInfo allocate{};
    allocate.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    allocate.descriptorPool = descriptor_pool_;
    allocate.descriptorSetCount = 1;
    allocate.pSetLayouts = &font_layout_;
    VkDescriptorSet set = VK_NULL_HANDLE;
    if (!check(vkAllocateDescriptorSets(config_.device, &allocate, &set)))
        return false;
    VkDescriptorImageInfo images[kFontSlots]{};
    for (std::uint32_t slot = 0; slot < kFontSlots; ++slot)
        images[slot] = {sampler_, slot < font_count_ ? fonts_[slot].view : dummy_.view,
                        VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
    VkWriteDescriptorSet write{};
    write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write.dstSet = set;
    write.descriptorCount = kFontSlots;
    write.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    write.pImageInfo = images;
    vkUpdateDescriptorSets(config_.device, 1, &write, 0, nullptr);
    // A set bound by a frame still in flight cannot change: each new font
    // gets a new set, and the old one goes when no frame can use it.
    if (font_set_ != VK_NULL_HANDLE)
    {
        Retired retired;
        retired.set = font_set_;
        retired.serial = serial_;
        retired_.push_back(retired);
    }
    font_set_ = set;
    return true;
}

void VkRenderer::retire(const Image &image)
{
    Retired retired;
    retired.image = image;
    retired.serial = serial_;
    retired_.push_back(retired);
}

void VkRenderer::collect(bool all)
{
    // Frame serial s reuses the slot of serial s - frames_in_flight, which
    // the caller has waited for: whatever was retired by then is unused.
    auto unused = [&](const Retired &retired)
    { return all || serial_ >= retired.serial + config_.frames_in_flight; };
    for (Retired &retired : retired_)
    {
        if (!unused(retired))
            continue;
        destroy_image(retired.image);
        if (retired.set != VK_NULL_HANDLE)
            vkFreeDescriptorSets(config_.device, descriptor_pool_, 1, &retired.set);
        retired.set = VK_NULL_HANDLE;
    }
    retired_.erase(std::remove_if(retired_.begin(), retired_.end(), unused), retired_.end());
}

std::uint32_t VkRenderer::create_font_texture(const Font &font)
{
    Image image;
    const int width = font.atlas_width();
    const int height = font.atlas_height();
    if (!create_image(image, width, height, VK_FORMAT_R8_UNORM, false))
        return 0;
    if (!upload(image, font.atlas().data(), static_cast<VkDeviceSize>(width) * height))
    {
        destroy_image(image);
        return 0;
    }
    if (font_count_ < kFontSlots)
    {
        fonts_[font_count_] = image;
        ++font_count_;
        if (!write_font_set())
            return 0;
        return kFontHandleBase | font_count_;
    }
    const std::uint32_t handle = next_texture_++;
    textures_.emplace(handle, image);
    return handle;
}

std::uint32_t VkRenderer::create_texture(int width, int height, const std::uint8_t *rgba)
{
    Image image;
    if (!create_image(image, width, height, VK_FORMAT_R8G8B8A8_UNORM, false))
        return 0;
    if (!upload(image, rgba, static_cast<VkDeviceSize>(width) * height * 4))
    {
        destroy_image(image);
        return 0;
    }
    const std::uint32_t handle = next_texture_++;
    textures_.emplace(handle, image);
    return handle;
}

std::uint32_t VkRenderer::render_to_texture(int width, int height, float virtual_width,
                                            float virtual_height)
{
    Image image;
    if (!create_image(image, width, height, kTargetFormat, true))
        return 0;
    const VkCommandBuffer cmd = begin_one_shot();
    if (cmd == VK_NULL_HANDLE)
    {
        destroy_image(image);
        return 0;
    }
    ++serial_;
    record(cmd, config_.frames_in_flight, virtual_width, virtual_height);
    if (layer_data_.size() == layers_.size())
    {
        const float transparent[4] = {0.0f, 0.0f, 0.0f, 0.0f};
        begin_offscreen(cmd, clear_pass_, image, transparent);
        for (std::size_t i = 0; i < layers_.size(); ++i)
        {
            if (layers_[i].kind == Kind::glass)
                continue;
            if (layers_[i].kind == Kind::list)
                instances_ += layers_[i].list->instances().size();
            play(cmd, i, offscreen_, width, height, -1.0f);
        }
        vkCmdEndRenderPass(cmd);
    }
    if (!end_one_shot(cmd))
    {
        destroy_image(image);
        return 0;
    }
    const std::uint32_t handle = next_texture_++;
    textures_.emplace(handle, image);
    return handle;
}

std::uint32_t VkRenderer::import_texture(VkImageView view)
{
    Image image;
    image.view = view;
    image.owned = false;
    VkDescriptorSetAllocateInfo allocate{};
    allocate.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    allocate.descriptorPool = descriptor_pool_;
    allocate.descriptorSetCount = 1;
    allocate.pSetLayouts = &texture_layout_;
    if (view == VK_NULL_HANDLE ||
        !check(vkAllocateDescriptorSets(config_.device, &allocate, &image.set)))
        return 0;
    const VkDescriptorImageInfo descriptor{sampler_, view,
                                           VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
    VkWriteDescriptorSet write{};
    write.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write.dstSet = image.set;
    write.descriptorCount = 1;
    write.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    write.pImageInfo = &descriptor;
    vkUpdateDescriptorSets(config_.device, 1, &write, 0, nullptr);
    const std::uint32_t handle = next_texture_++;
    textures_.emplace(handle, image);
    return handle;
}

void VkRenderer::destroy_texture(std::uint32_t texture)
{
    const auto found = textures_.find(texture);
    if (found == textures_.end())
        return; // 0, a font slot, the glass handle, or already gone
    retire(found->second);
    textures_.erase(found);
}

const VkRenderer::Image *VkRenderer::glass_target(int bank, int index)
{
    Image &image = glass_[bank][index];
    if (image.image == VK_NULL_HANDLE &&
        !create_image(image, kGlassWidth, kGlassHeight, kTargetFormat, true))
        return nullptr;
    return &image;
}

void VkRenderer::prepare(VkCommandBuffer cmd, std::uint32_t frame, float virtual_width,
                         float virtual_height)
{
    ++serial_;
    collect(false);
    record(cmd, frame % config_.frames_in_flight, virtual_width, virtual_height);
}

void VkRenderer::record(VkCommandBuffer cmd, std::uint32_t slot, float virtual_width,
                        float virtual_height)
{
    slot_ = slot;
    virtual_width_ = virtual_width;
    virtual_height_ = virtual_height;
    draw_calls_ = 0;
    instances_ = 0;
    layer_data_.clear();

    // Every list's instances go up once, in one buffer per frame slot; the
    // glass replays and the final pass draw the same data.
    std::vector<LayerData> data(layers_.size());
    std::size_t instances = 0;
    std::size_t vertices = 0;
    for (std::size_t i = 0; i < layers_.size(); ++i)
    {
        if (layers_[i].kind != Kind::list)
            continue;
        data[i].instance_base = static_cast<std::uint32_t>(instances);
        data[i].mesh_base = static_cast<std::uint32_t>(vertices);
        instances += layers_[i].list->instances().size();
        vertices += layers_[i].list->mesh_vertices().size();
    }
    Buffer &instance_buffer = instance_buffers_[slot];
    Buffer &mesh_buffer = mesh_buffers_[slot];
    if (!reserve(instance_buffer, std::max<std::size_t>(instances, 1) * sizeof(Instance),
                 VK_BUFFER_USAGE_VERTEX_BUFFER_BIT) ||
        !reserve(mesh_buffer, std::max<std::size_t>(vertices, 1) * sizeof(MeshVertex),
                 VK_BUFFER_USAGE_VERTEX_BUFFER_BIT))
        return; // draw() finds no layer data and draws nothing
    for (std::size_t i = 0; i < layers_.size(); ++i)
    {
        if (layers_[i].kind != Kind::list)
            continue;
        const DrawList &list = *layers_[i].list;
        if (!list.instances().empty())
            std::memcpy(static_cast<Instance *>(instance_buffer.mapped) + data[i].instance_base,
                        list.instances().data(), list.instances().size() * sizeof(Instance));
        if (!list.mesh_vertices().empty())
            std::memcpy(static_cast<MeshVertex *>(mesh_buffer.mapped) + data[i].mesh_base,
                        list.mesh_vertices().data(),
                        list.mesh_vertices().size() * sizeof(MeshVertex));
    }
    layer_data_ = std::move(data);

    // The glass copies, in queue order, each into a target of its own.
    const int other = bank_;
    bank_ ^= 1;
    const Image *current = &glass_[other][std::max(0, glass_count_[other] - 1)];
    int count = 0;
    for (std::size_t i = 0; i < layers_.size(); ++i)
    {
        if (layers_[i].kind != Kind::glass)
        {
            layer_data_[i].glass = current;
            continue;
        }
        const Image *target = glass_target(bank_, std::min(count, kMaxGlass - 1));
        if (target != nullptr)
        {
            capture_glass(cmd, i, *target);
            current = target;
        }
        ++count;
    }
    glass_count_[bank_] = std::min(count, kMaxGlass);
}

void VkRenderer::begin_offscreen(VkCommandBuffer cmd, VkRenderPass pass, const Image &target,
                                 const float clear[4])
{
    VkClearValue value{};
    if (clear != nullptr)
        std::memcpy(value.color.float32, clear, sizeof(value.color.float32));
    VkRenderPassBeginInfo begin{};
    begin.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    begin.renderPass = pass;
    begin.framebuffer = target.framebuffer;
    begin.renderArea = {
        {0, 0},
        {static_cast<std::uint32_t>(target.width), static_cast<std::uint32_t>(target.height)}};
    begin.clearValueCount = clear != nullptr ? 1 : 0;
    begin.pClearValues = &value;
    vkCmdBeginRenderPass(cmd, &begin, VK_SUBPASS_CONTENTS_INLINE);
    set_viewport(cmd, target.width, target.height);
}

void VkRenderer::capture_glass(VkCommandBuffer cmd, std::size_t layers, const Image &target)
{
    const float black[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    begin_offscreen(cmd, clear_pass_, target, black);
    for (std::size_t i = 0; i < layers; ++i)
        play(cmd, i, offscreen_, kGlassWidth, kGlassHeight, -1.0f);
    vkCmdEndRenderPass(cmd);

    // Two rounds of horizontal then vertical blur, the second one wider.
    for (float step : {1.0f, 2.2f})
    {
        blur_pass(cmd, target, glass_scratch_, step / static_cast<float>(kGlassWidth), 0.0f);
        blur_pass(cmd, glass_scratch_, target, 0.0f, step / static_cast<float>(kGlassHeight));
        draw_calls_ += 2;
    }
}

void VkRenderer::blur_pass(VkCommandBuffer cmd, const Image &source, const Image &target,
                           float step_x, float step_y)
{
    begin_offscreen(cmd, overwrite_pass_, target, nullptr);
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, blur_);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, blur_layout_, 0, 1, &source.set,
                            0, nullptr);
    const BlurPush push{{step_x, step_y}};
    vkCmdPushConstants(cmd, blur_layout_, VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(push), &push);
    vkCmdDraw(cmd, 3, 1, 0, 0);
    vkCmdEndRenderPass(cmd);
}

void VkRenderer::draw(VkCommandBuffer cmd, int width, int height)
{
    if (layer_data_.size() != layers_.size())
        return;
    for (std::size_t i = 0; i < layers_.size(); ++i)
    {
        if (layers_[i].kind == Kind::glass)
            continue;
        if (layers_[i].kind == Kind::list)
            instances_ += layers_[i].list->instances().size();
        play(cmd, i, target_, width, height, 1.0f);
    }
}

void VkRenderer::play(VkCommandBuffer cmd, std::size_t layer, const Pipelines &pipelines, int width,
                      int height, float flip)
{
    const Layer &item = layers_[layer];
    if (item.kind == Kind::list)
    {
        draw_list(cmd, layer, pipelines, width, height, flip);
        return;
    }
    if (item.kind != Kind::backdrop)
        return;
    // Post overlays and cross-fades blend over what is there.
    const bool post = static_cast<int>(item.spec.mode) >= 20;
    vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
                      post || item.opacity < 1.0f ? pipelines.backdrop_blend
                                                  : pipelines.backdrop_opaque);
    set_viewport(cmd, width, height);
    BackdropPush push{};
    push.resolution[0] = static_cast<float>(width);
    push.resolution[1] = static_cast<float>(height);
    push.time = item.spec.time;
    push.mode = static_cast<std::int32_t>(item.spec.mode);
    for (int i = 0; i < 4; ++i)
    {
        push.colors[i * 4 + 0] = item.spec.colors[i].r;
        push.colors[i * 4 + 1] = item.spec.colors[i].g;
        push.colors[i * 4 + 2] = item.spec.colors[i].b;
        push.colors[i * 4 + 3] = item.spec.colors[i].a;
    }
    std::memcpy(push.params, item.spec.params, sizeof(push.params));
    push.opacity = item.opacity;
    push.flip = flip;
    vkCmdPushConstants(cmd, backdrop_layout_, VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(push), &push);
    vkCmdDraw(cmd, 3, 1, 0, 0);
    ++draw_calls_;
}

void VkRenderer::draw_list(VkCommandBuffer cmd, std::size_t layer, const Pipelines &pipelines,
                           int width, int height, float flip)
{
    const DrawList &list = *layers_[layer].list;
    const LayerData &data = layer_data_[layer];
    const Viewport viewport = fit_viewport(width, height, virtual_width_, virtual_height_);
    set_viewport(cmd, width, height);
    const BatchPush push{{viewport.scale, viewport.offset_x, viewport.offset_y, 0.0f},
                         {static_cast<float>(width), static_cast<float>(height)},
                         flip,
                         0.0f};
    const VkDescriptorSet sets[2] = {font_set_, dummy_.set};
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, batch_layout_, 0, 2, sets, 0,
                            nullptr);
    vkCmdPushConstants(cmd, batch_layout_,
                       VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(push),
                       &push);
    const VkDeviceSize instance_offset = VkDeviceSize{data.instance_base} * sizeof(Instance);
    const VkDeviceSize mesh_offset = VkDeviceSize{data.mesh_base} * sizeof(MeshVertex);

    int bound = -1; // 0: the batch pipeline, 1: the mesh pipeline
    std::uint32_t bound_texture = 0;
    for (const Run &run : list.runs())
    {
        if (run.count == 0)
            continue;
        const int wanted = run.mesh ? 1 : 0;
        if (wanted != bound)
        {
            bound = wanted;
            vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS,
                              run.mesh ? pipelines.mesh : pipelines.batch);
            const VkBuffer buffer =
                run.mesh ? mesh_buffers_[slot_].buffer : instance_buffers_[slot_].buffer;
            const VkDeviceSize offset = run.mesh ? mesh_offset : instance_offset;
            vkCmdBindVertexBuffers(cmd, 0, 1, &buffer, &offset);
        }
        // Font atlases are in set 0 for the whole list; any other texture is
        // set 1, bound when the run's texture changes.
        if (run.texture != 0 && run.texture != bound_texture && !is_font_handle(run.texture))
        {
            VkDescriptorSet set = dummy_.set;
            if (run.texture == kGlassHandle)
            {
                if (data.glass != nullptr)
                    set = data.glass->set;
            }
            else if (const auto found = textures_.find(run.texture); found != textures_.end())
            {
                set = found->second.set;
            }
            vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, batch_layout_, 1, 1, &set,
                                    0, nullptr);
            bound_texture = run.texture;
        }
        VkRect2D scissor{{0, 0},
                         {static_cast<std::uint32_t>(width), static_cast<std::uint32_t>(height)}};
        if (run.clipped)
        {
            const float x0 = std::floor(run.clip.x * viewport.scale + viewport.offset_x);
            const float y0 = std::floor(run.clip.y * viewport.scale + viewport.offset_y);
            const float x1 =
                std::ceil((run.clip.x + run.clip.w) * viewport.scale + viewport.offset_x);
            const float y1 =
                std::ceil((run.clip.y + run.clip.h) * viewport.scale + viewport.offset_y);
            // OpenGL's scissor counts rows up from the bottom: a target stored
            // bottom row first is the same, the display is not. Vulkan wants
            // the rectangle inside the target, so it is clamped.
            const float top = flip < 0.0f ? static_cast<float>(height) - y1 : y0;
            const float left = std::max(0.0f, x0);
            const float right = std::min(static_cast<float>(width), x1);
            const float upper = std::max(0.0f, top);
            const float lower = std::min(static_cast<float>(height), top + (y1 - y0));
            scissor.offset = {static_cast<std::int32_t>(left), static_cast<std::int32_t>(upper)};
            scissor.extent = {static_cast<std::uint32_t>(std::max(0.0f, right - left)),
                              static_cast<std::uint32_t>(std::max(0.0f, lower - upper))};
        }
        vkCmdSetScissor(cmd, 0, 1, &scissor);
        if (run.mesh)
            vkCmdDraw(cmd, run.count, 1, run.first, 0);
        else
            vkCmdDraw(cmd, 6, run.count, 0, run.first);
        ++draw_calls_;
    }
}

} // namespace hui::gfx
