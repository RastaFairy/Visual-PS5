// ps5-homebrew-ui - Host preview through the Vulkan backend: the tour's pictures.
// Copyright (C) 2026 BlackBearReloaded
// Copyright (C) 2026 Mihawk
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Vulkan twin of snapshot_main.cpp's tour: the same shell, tour, fixed
// 60 Hz clock and stand-in telemetry, drawn by gfx::VkRenderer into an
// off-screen image on the PC's Vulkan driver. It prefers a CPU device
// (lavapipe), which pairs with the OpenGL tool's llvmpipe, so
// tools/compare-backends.py can set every picture beside the OpenGL one.
// HUI_VK_DEVICE=<part of a device name> picks another device, and
// HUI_VK_VALIDATION=1 turns on the Khronos validation layer.

#include "app/shell.hpp"
#include "app/tour.hpp"
#include "core/save_file.hpp"
#include "demo/catalog.hpp"
#include "gfx/vk/vk_renderer.hpp"
#include "ui/fonts.hpp"

#include <vulkan/vulkan.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../third_party/stb/stb_image_write.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace
{

std::size_t g_validation_messages = 0;

VKAPI_ATTR VkBool32 VKAPI_CALL report(VkDebugUtilsMessageSeverityFlagBitsEXT severity,
                                      VkDebugUtilsMessageTypeFlagsEXT,
                                      const VkDebugUtilsMessengerCallbackDataEXT *data, void *)
{
    if (severity >= VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT)
    {
        ++g_validation_messages;
        std::fprintf(stderr, "validation: %s\n", data->pMessage);
    }
    return VK_FALSE;
}

struct Context
{
    VkInstance instance = VK_NULL_HANDLE;
    VkDebugUtilsMessengerEXT messenger = VK_NULL_HANDLE;
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    std::uint32_t family = 0;
    VkPhysicalDeviceMemoryProperties memory{};
    std::string name;
};

bool open_context(Context &context)
{
    const bool validation = std::getenv("HUI_VK_VALIDATION") != nullptr;
    const char *layers[] = {"VK_LAYER_KHRONOS_validation"};
    const char *extensions[] = {VK_EXT_DEBUG_UTILS_EXTENSION_NAME};
    VkApplicationInfo application{};
    application.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    application.pApplicationName = "hui_vk_snapshots";
    application.apiVersion = VK_API_VERSION_1_1;
    VkInstanceCreateInfo instance{};
    instance.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    instance.pApplicationInfo = &application;
    if (validation)
    {
        instance.enabledLayerCount = 1;
        instance.ppEnabledLayerNames = layers;
        instance.enabledExtensionCount = 1;
        instance.ppEnabledExtensionNames = extensions;
    }
    if (vkCreateInstance(&instance, nullptr, &context.instance) != VK_SUCCESS)
        return false;
    if (validation)
    {
        auto create = reinterpret_cast<PFN_vkCreateDebugUtilsMessengerEXT>(
            vkGetInstanceProcAddr(context.instance, "vkCreateDebugUtilsMessengerEXT"));
        VkDebugUtilsMessengerCreateInfoEXT messenger{};
        messenger.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
        messenger.messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                                    VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
        messenger.messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                                VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                                VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
        messenger.pfnUserCallback = report;
        if (create != nullptr)
            create(context.instance, &messenger, nullptr, &context.messenger);
    }

    std::uint32_t count = 0;
    vkEnumeratePhysicalDevices(context.instance, &count, nullptr);
    std::vector<VkPhysicalDevice> devices(count);
    vkEnumeratePhysicalDevices(context.instance, &count, devices.data());
    const char *wanted = std::getenv("HUI_VK_DEVICE");
    for (int pass = 0; pass < 2 && context.physical == VK_NULL_HANDLE; ++pass)
        for (VkPhysicalDevice device : devices)
        {
            VkPhysicalDeviceProperties properties{};
            vkGetPhysicalDeviceProperties(device, &properties);
            const bool match = wanted != nullptr
                                   ? std::strstr(properties.deviceName, wanted) != nullptr
                                   : properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU;
            if (match || (pass == 1 && wanted == nullptr))
            {
                context.physical = device;
                context.name = properties.deviceName;
                break;
            }
        }
    if (context.physical == VK_NULL_HANDLE)
        return false;
    vkGetPhysicalDeviceMemoryProperties(context.physical, &context.memory);

    vkGetPhysicalDeviceQueueFamilyProperties(context.physical, &count, nullptr);
    std::vector<VkQueueFamilyProperties> families(count);
    vkGetPhysicalDeviceQueueFamilyProperties(context.physical, &count, families.data());
    context.family = UINT32_MAX;
    for (std::uint32_t i = 0; i < count; ++i)
        if ((families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0)
        {
            context.family = i;
            break;
        }
    if (context.family == UINT32_MAX)
        return false;
    const float priority = 1.0f;
    VkDeviceQueueCreateInfo queue{};
    queue.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue.queueFamilyIndex = context.family;
    queue.queueCount = 1;
    queue.pQueuePriorities = &priority;
    VkDeviceCreateInfo device{};
    device.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    device.queueCreateInfoCount = 1;
    device.pQueueCreateInfos = &queue;
    if (vkCreateDevice(context.physical, &device, nullptr, &context.device) != VK_SUCCESS)
        return false;
    vkGetDeviceQueue(context.device, context.family, 0, &context.queue);
    return true;
}

std::uint32_t memory_type(const Context &context, std::uint32_t bits, VkMemoryPropertyFlags flags)
{
    for (std::uint32_t i = 0; i < context.memory.memoryTypeCount; ++i)
        if ((bits & (1u << i)) != 0 &&
            (context.memory.memoryTypes[i].propertyFlags & flags) == flags)
            return i;
    return UINT32_MAX;
}

// The picture: an RGBA8 image as the OpenGL tool's renderbuffer, cleared to
// opaque black, and a buffer it is copied into for the PNG.
struct Target
{
    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory image_memory = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    VkRenderPass pass = VK_NULL_HANDLE;
    VkFramebuffer framebuffer = VK_NULL_HANDLE;
    VkBuffer readback = VK_NULL_HANDLE;
    VkDeviceMemory readback_memory = VK_NULL_HANDLE;
    void *pixels = nullptr;
    VkCommandPool pool = VK_NULL_HANDLE;
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    int width = 0;
    int height = 0;
};

bool create_target(const Context &context, Target &target, int width, int height)
{
    const VkDevice device = context.device;
    target.width = width;
    target.height = height;
    VkImageCreateInfo image{};
    image.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    image.imageType = VK_IMAGE_TYPE_2D;
    image.format = VK_FORMAT_R8G8B8A8_UNORM;
    image.extent = {static_cast<std::uint32_t>(width), static_cast<std::uint32_t>(height), 1};
    image.mipLevels = 1;
    image.arrayLayers = 1;
    image.samples = VK_SAMPLE_COUNT_1_BIT;
    image.tiling = VK_IMAGE_TILING_OPTIMAL;
    image.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    if (vkCreateImage(device, &image, nullptr, &target.image) != VK_SUCCESS)
        return false;
    VkMemoryRequirements requirements{};
    vkGetImageMemoryRequirements(device, target.image, &requirements);
    VkMemoryAllocateInfo allocate{};
    allocate.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocate.allocationSize = requirements.size;
    allocate.memoryTypeIndex =
        memory_type(context, requirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (vkAllocateMemory(device, &allocate, nullptr, &target.image_memory) != VK_SUCCESS ||
        vkBindImageMemory(device, target.image, target.image_memory, 0) != VK_SUCCESS)
        return false;
    VkImageViewCreateInfo view{};
    view.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    view.image = target.image;
    view.viewType = VK_IMAGE_VIEW_TYPE_2D;
    view.format = image.format;
    view.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    if (vkCreateImageView(device, &view, nullptr, &target.view) != VK_SUCCESS)
        return false;

    VkAttachmentDescription attachment{};
    attachment.format = image.format;
    attachment.samples = VK_SAMPLE_COUNT_1_BIT;
    attachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    attachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    attachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    attachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    attachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    attachment.finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    const VkAttachmentReference color{0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkSubpassDescription subpass{};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &color;
    VkSubpassDependency dependencies[2]{};
    dependencies[0].srcSubpass = VK_SUBPASS_EXTERNAL;
    dependencies[0].srcStageMask =
        VK_PIPELINE_STAGE_TRANSFER_BIT | VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependencies[0].dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependencies[0].dstAccessMask =
        VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    dependencies[1].srcSubpass = 0;
    dependencies[1].dstSubpass = VK_SUBPASS_EXTERNAL;
    dependencies[1].srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependencies[1].srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    dependencies[1].dstStageMask = VK_PIPELINE_STAGE_TRANSFER_BIT;
    dependencies[1].dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    VkRenderPassCreateInfo pass{};
    pass.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    pass.attachmentCount = 1;
    pass.pAttachments = &attachment;
    pass.subpassCount = 1;
    pass.pSubpasses = &subpass;
    pass.dependencyCount = 2;
    pass.pDependencies = dependencies;
    if (vkCreateRenderPass(device, &pass, nullptr, &target.pass) != VK_SUCCESS)
        return false;
    VkFramebufferCreateInfo framebuffer{};
    framebuffer.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
    framebuffer.renderPass = target.pass;
    framebuffer.attachmentCount = 1;
    framebuffer.pAttachments = &target.view;
    framebuffer.width = static_cast<std::uint32_t>(width);
    framebuffer.height = static_cast<std::uint32_t>(height);
    framebuffer.layers = 1;
    if (vkCreateFramebuffer(device, &framebuffer, nullptr, &target.framebuffer) != VK_SUCCESS)
        return false;

    VkBufferCreateInfo buffer{};
    buffer.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buffer.size = static_cast<VkDeviceSize>(width) * height * 4;
    buffer.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    if (vkCreateBuffer(device, &buffer, nullptr, &target.readback) != VK_SUCCESS)
        return false;
    vkGetBufferMemoryRequirements(device, target.readback, &requirements);
    allocate.allocationSize = requirements.size;
    allocate.memoryTypeIndex =
        memory_type(context, requirements.memoryTypeBits,
                    VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (vkAllocateMemory(device, &allocate, nullptr, &target.readback_memory) != VK_SUCCESS ||
        vkBindBufferMemory(device, target.readback, target.readback_memory, 0) != VK_SUCCESS ||
        vkMapMemory(device, target.readback_memory, 0, VK_WHOLE_SIZE, 0, &target.pixels) !=
            VK_SUCCESS)
        return false;

    VkCommandPoolCreateInfo pool{};
    pool.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pool.queueFamilyIndex = context.family;
    if (vkCreateCommandPool(device, &pool, nullptr, &target.pool) != VK_SUCCESS)
        return false;
    VkCommandBufferAllocateInfo cmd{};
    cmd.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cmd.commandPool = target.pool;
    cmd.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cmd.commandBufferCount = 1;
    return vkAllocateCommandBuffers(device, &cmd, &target.cmd) == VK_SUCCESS;
}

void destroy_target(const Context &context, Target &target)
{
    const VkDevice device = context.device;
    vkDestroyCommandPool(device, target.pool, nullptr);
    vkDestroyBuffer(device, target.readback, nullptr);
    vkFreeMemory(device, target.readback_memory, nullptr);
    vkDestroyFramebuffer(device, target.framebuffer, nullptr);
    vkDestroyRenderPass(device, target.pass, nullptr);
    vkDestroyImageView(device, target.view, nullptr);
    vkDestroyImage(device, target.image, nullptr);
    vkFreeMemory(device, target.image_memory, nullptr);
}

// Plays the queued frame into the target and copies it out. Every frame
// waits, so slot 0 is always free.
bool present(const Context &context, Target &target, hui::gfx::VkRenderer &renderer)
{
    VkCommandBufferBeginInfo begin{};
    begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (vkBeginCommandBuffer(target.cmd, &begin) != VK_SUCCESS)
        return false;
    renderer.prepare(target.cmd, 0);
    VkClearValue clear{};
    clear.color.float32[3] = 1.0f;
    VkRenderPassBeginInfo pass{};
    pass.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    pass.renderPass = target.pass;
    pass.framebuffer = target.framebuffer;
    pass.renderArea = {
        {0, 0},
        {static_cast<std::uint32_t>(target.width), static_cast<std::uint32_t>(target.height)}};
    pass.clearValueCount = 1;
    pass.pClearValues = &clear;
    vkCmdBeginRenderPass(target.cmd, &pass, VK_SUBPASS_CONTENTS_INLINE);
    renderer.draw(target.cmd, target.width, target.height);
    vkCmdEndRenderPass(target.cmd);
    VkBufferImageCopy copy{};
    copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    copy.imageExtent = {static_cast<std::uint32_t>(target.width),
                        static_cast<std::uint32_t>(target.height), 1};
    vkCmdCopyImageToBuffer(target.cmd, target.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                           target.readback, 1, &copy);
    if (vkEndCommandBuffer(target.cmd) != VK_SUCCESS)
        return false;
    VkSubmitInfo submit{};
    submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &target.cmd;
    return vkQueueSubmit(context.queue, 1, &submit, VK_NULL_HANDLE) == VK_SUCCESS &&
           vkQueueWaitIdle(context.queue) == VK_SUCCESS;
}

bool load_font(hui::gfx::Renderer &renderer, const std::string &path, hui::gfx::Font *font,
               hui::ui::FontRef *ref)
{
    std::string data;
    if (!hui::save::read_file(path, &data) || !font->load(data))
    {
        std::fprintf(stderr, "cannot load font %s\n", path.c_str());
        return false;
    }
    ref->font = font;
    ref->texture = renderer.create_font_texture(*font);
    return ref->texture != 0;
}

} // namespace

int main(int argc, char **argv)
{
    if (argc < 3)
    {
        std::fprintf(stderr, "usage: %s <assets dir> <output dir> [design id|all] [width height]\n",
                     argv[0]);
        return 2;
    }
    const std::string assets = argv[1];
    const std::string output = argv[2];
    const std::string only = argc > 3 && std::string(argv[3]) != "all" ? argv[3] : "";
    const int width = argc > 5 ? std::atoi(argv[4]) : 1920;
    const int height = argc > 5 ? std::atoi(argv[5]) : 1080;

    Context context;
    if (!open_context(context))
    {
        std::fprintf(stderr, "no Vulkan device with a graphics queue\n");
        return 1;
    }
    std::fprintf(stderr, "Vulkan device: %s\n", context.name.c_str());
    Target target;
    if (!create_target(context, target, width, height))
    {
        std::fprintf(stderr, "cannot create the %dx%d target\n", width, height);
        return 1;
    }

    int status = 0;
    {
        hui::gfx::VkRenderer renderer;
        hui::gfx::VkRendererConfig config;
        config.physical_device = context.physical;
        config.device = context.device;
        config.queue = context.queue;
        config.queue_family = context.family;
        config.frames_in_flight = 1;
        config.render_pass = target.pass;
        hui::gfx::Font regular;
        hui::gfx::Font semibold;
        hui::gfx::Font display;
        hui::gfx::Font mono;
        hui::gfx::Font pixel;
        hui::gfx::Font hand;
        hui::ui::Fonts fonts;
        if (!renderer.init(config) ||
            !load_font(renderer, assets + "/fonts/inter-regular.huifont", &regular,
                       &fonts.regular) ||
            !load_font(renderer, assets + "/fonts/inter-semibold.huifont", &semibold,
                       &fonts.semibold) ||
            !load_font(renderer, assets + "/fonts/montserrat-medium.huifont", &display,
                       &fonts.display) ||
            !load_font(renderer, assets + "/fonts/dejavu-sans-mono.huifont", &mono, &fonts.mono) ||
            !load_font(renderer, assets + "/fonts/press-start-2p.huifont", &pixel, &fonts.pixel) ||
            !load_font(renderer, assets + "/fonts/patrick-hand.huifont", &hand, &fonts.hand))
        {
            std::fprintf(stderr, "renderer init failed: VkResult %d\n",
                         static_cast<int>(renderer.last_error()));
            return 1;
        }
        hui::demo::Catalog catalog;
        if (!catalog.build_covers(renderer, fonts))
        {
            std::fprintf(stderr, "cover art failed: VkResult %d\n",
                         static_cast<int>(renderer.last_error()));
            return 1;
        }

        // Settings are not read from (or written to) a real save: a scratch folder.
        const std::string data_root = output + "/.data";
        hui::save::ensure_directory(output);
        hui::save::ensure_directory(data_root);
        std::remove((data_root + "/settings.bin").c_str());
        hui::app::Shell shell(fonts, catalog, data_root, renderer.glass_texture());
        shell.set_version("host");

        constexpr float kDt = 1.0f / 60.0f;
        bool ok = true;
        const auto render = [&](const std::string &name)
        {
            shell.compose(renderer);
            const bool drawn = present(context, target, renderer);
            std::vector<unsigned char> pixels(static_cast<std::size_t>(width) * height * 4);
            std::memcpy(pixels.data(), target.pixels, pixels.size());
            // The PNG is opaque whatever the blending left in the alpha channel.
            for (std::size_t i = 3; i < pixels.size(); i += 4)
                pixels[i] = 255;
            const std::string path = output + "/" + name + ".png";
            ok = drawn &&
                 stbi_write_png(path.c_str(), width, height, 4, pixels.data(), width * 4) != 0 &&
                 ok;
            std::fprintf(stderr, "wrote %s: %zu shapes, %zu draw calls, VkResult %d\n",
                         path.c_str(), renderer.last_instances(), renderer.last_draw_calls(),
                         static_cast<int>(renderer.last_error()));
        };

        hui::app::Tour tour(shell, only);
        if (tour.finished())
        {
            std::fprintf(stderr, "no design named '%s'\n", only.c_str());
            return 2;
        }
        long frames = 0;
        while (!tour.finished() && frames < 60 * 60 * 60)
        {
            const hui::InputFrame input = tour.step(kDt);
            // The same stand-in numbers as the OpenGL tool, so pictures that
            // show them match.
            hui::app::Telemetry &telemetry = shell.telemetry();
            const float jitter = static_cast<float>((frames * 7919) % 97) / 97.0f;
            telemetry.push(16.3f + jitter * 0.8f + (frames % 211 == 0 ? 5.5f : 0.0f));
            telemetry.fps = 59.9f;
            telemetry.average_ms = 16.7f;
            telemetry.voices = static_cast<int>(frames / 40 % 4);
            telemetry.draw_calls = renderer.last_draw_calls();
            telemetry.instances = renderer.last_instances();
            shell.update(input, kDt);
            ++frames;
            if (!tour.capture().empty())
            {
                render(tour.capture());
                tour.capture_done();
            }
            else
            {
                shell.rehearse(); // as on the console, every frame is drawn
            }
        }
        std::fprintf(stderr, "tour: %ld frames simulated\n", frames);
        status = ok ? 0 : 1;
        renderer.release();
    }
    destroy_target(context, target);
    vkDestroyDevice(context.device, nullptr);
    if (context.messenger != VK_NULL_HANDLE)
    {
        auto destroy = reinterpret_cast<PFN_vkDestroyDebugUtilsMessengerEXT>(
            vkGetInstanceProcAddr(context.instance, "vkDestroyDebugUtilsMessengerEXT"));
        if (destroy != nullptr)
            destroy(context.instance, context.messenger, nullptr);
    }
    vkDestroyInstance(context.instance, nullptr);
    if (std::getenv("HUI_VK_VALIDATION") != nullptr)
        std::fprintf(stderr, "validation: %zu messages\n", g_validation_messages);
    return status;
}
