/* PS5 RetroArch - the display modes test: every size the Vulkan driver's
 * display offers, presented in turn.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Why this exists. The driver (RADV's VideoOut WSI, PS5_Mesa) offered one
 * 3840x2160 mode, so this title drew 4K whatever the screen took. Its display
 * now offers a mode for each size VideoOut takes buffers of, and each size a
 * swapchain uses is registered with VideoOut as its own set of buffers. Whether
 * VideoOut takes every size, several sets at once and flips between them is
 * measured here, before RetroArch is pointed at a size.
 *
 * /app0/display-modes-test.txt ("<frames per mode>", tools/run-title.sh
 * --display-modes-test) arms it. Before RetroArch starts, it makes a Vulkan
 * device on the title's driver and, for every mode the display reports and
 * then the first again (its set already registered), a surface and a swapchain
 * of that size, through oldSwapchain, and presents a pattern for the frames
 * asked: the left and right halves in two shades of one colour a size (red
 * 3840x2160, green 2560x1440, blue 1920x1080, yellow 1280x720) and a white
 * border on every edge, so a person at the screen sees whether each size fills
 * it. Each mode's result is one JSON line in /app0/display-modes-test.jsonl;
 * the driver's own lines (the sets it registers) go to the trace. The test is
 * disarmed and RetroArch starts as usual.
 */
#include "display_modes_ps5.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#define VK_NO_PROTOTYPES
#include "gfx/include/vulkan/vulkan.h"

#include "trace.hpp"

extern "C" VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(VkInstance instance,
                                                                          const char *name);

namespace ps5::display_modes
{
namespace
{
#define INSTANCE_COMMANDS(X)                                                                       \
    X(vkEnumeratePhysicalDevices)                                                                  \
    X(vkGetPhysicalDeviceDisplayPropertiesKHR)                                                     \
    X(vkGetDisplayModePropertiesKHR)                                                               \
    X(vkCreateDisplayPlaneSurfaceKHR)                                                              \
    X(vkGetPhysicalDeviceSurfaceCapabilitiesKHR)                                                   \
    X(vkDestroySurfaceKHR)                                                                         \
    X(vkGetPhysicalDeviceMemoryProperties)                                                         \
    X(vkCreateDevice)                                                                              \
    X(vkGetDeviceProcAddr)                                                                         \
    X(vkDestroyInstance)
#define DEVICE_COMMANDS(X)                                                                         \
    X(vkGetDeviceQueue)                                                                            \
    X(vkCreateSwapchainKHR)                                                                        \
    X(vkDestroySwapchainKHR)                                                                       \
    X(vkGetSwapchainImagesKHR)                                                                     \
    X(vkAcquireNextImageKHR)                                                                       \
    X(vkQueuePresentKHR)                                                                           \
    X(vkCreateCommandPool)                                                                         \
    X(vkDestroyCommandPool)                                                                        \
    X(vkAllocateCommandBuffers)                                                                    \
    X(vkBeginCommandBuffer)                                                                        \
    X(vkEndCommandBuffer)                                                                          \
    X(vkResetCommandBuffer)                                                                        \
    X(vkCmdPipelineBarrier)                                                                        \
    X(vkCmdCopyBufferToImage)                                                                      \
    X(vkQueueSubmit)                                                                               \
    X(vkCreateSemaphore)                                                                           \
    X(vkDestroySemaphore)                                                                          \
    X(vkCreateFence)                                                                               \
    X(vkDestroyFence)                                                                              \
    X(vkWaitForFences)                                                                             \
    X(vkResetFences)                                                                               \
    X(vkCreateBuffer)                                                                              \
    X(vkDestroyBuffer)                                                                             \
    X(vkGetBufferMemoryRequirements)                                                               \
    X(vkAllocateMemory)                                                                            \
    X(vkFreeMemory)                                                                                \
    X(vkBindBufferMemory)                                                                          \
    X(vkMapMemory)                                                                                 \
    X(vkDeviceWaitIdle)                                                                            \
    X(vkDestroyDevice)

#define DECLARE(name) PFN_##name name;
struct Vk
{
    PFN_vkCreateInstance vkCreateInstance;
    INSTANCE_COMMANDS(DECLARE)
    DEVICE_COMMANDS(DECLARE)
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice gpu = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    VkCommandPool pool = VK_NULL_HANDLE;
};
#undef DECLARE

/* A failed call, what it was and what it returned, for the record: the title is
 * built without exceptions, so a step returns false with *error set. */
bool fail(std::string &error, const std::string &call, VkResult result)
{
    error = call + " = " + std::to_string(int(result));
    return false;
}

#define CHECK(call)                                                                                \
    do                                                                                             \
    {                                                                                              \
        const VkResult result_ = (call);                                                           \
        if (result_ != VK_SUCCESS)                                                                 \
            return fail(error, #call, result_);                                                    \
    } while (0)

/* The two shades of a size's colour, as B8G8R8A8 words. */
void colours(const VkExtent2D &extent, uint32_t &left, uint32_t &right)
{
    switch (extent.height)
    {
    case 2160:
        left = 0xffff0000u, right = 0xff800000u;
        break; /* red */
    case 1440:
        left = 0xff00ff00u, right = 0xff008000u;
        break; /* green */
    case 1080:
        left = 0xff0000ffu, right = 0xff000080u;
        break; /* blue */
    default:
        left = 0xffffff00u, right = 0xff808000u;
        break; /* yellow */
    }
}
} // namespace

void fill_pattern(uint32_t *pixels, VkExtent2D extent)
{
    uint32_t left, right;
    colours(extent, left, right);
    const uint32_t border = extent.height / 54; /* 40 pixels at 2160, 13 at 720 */
    for (uint32_t y = 0; y < extent.height; y++)
        for (uint32_t x = 0; x < extent.width; x++)
        {
            const bool edge = x < border || y < border || x >= extent.width - border ||
                              y >= extent.height - border;
            pixels[size_t(y) * extent.width + x] =
                edge ? 0xffffffffu : (x < extent.width / 2 ? left : right);
        }
}

std::string mode_line(const VkDisplayModeParametersKHR &mode, unsigned frames, unsigned images,
                      double seconds, const std::string &error)
{
    char line[512];
    std::snprintf(line, sizeof line,
                  "{\"width\":%u,\"height\":%u,\"refresh_millihertz\":%u,\"frames\":%u,"
                  "\"images\":%u,\"seconds\":%.3f,\"result\":\"%s\"}",
                  mode.visibleRegion.width, mode.visibleRegion.height, mode.refreshRate, frames,
                  images, seconds, error.empty() ? "ok" : error.c_str());
    return line;
}

namespace
{
/* A host-visible, coherent memory type of bits, UINT32_MAX when there is none. */
uint32_t host_memory_type(const Vk &vk, uint32_t bits)
{
    VkPhysicalDeviceMemoryProperties properties;
    vk.vkGetPhysicalDeviceMemoryProperties(vk.gpu, &properties);
    const VkMemoryPropertyFlags wanted =
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    for (uint32_t i = 0; i < properties.memoryTypeCount; i++)
        if ((bits & (1u << i)) && (properties.memoryTypes[i].propertyFlags & wanted) == wanted)
            return i;
    return UINT32_MAX;
}

/* One mode: a surface, a swapchain replacing chain, and frames of its pattern;
 * *images is the swapchain's image count. */
bool present_mode(Vk &vk, const VkDisplayModePropertiesKHR &mode, unsigned frames,
                  VkSwapchainKHR &chain, VkSurfaceKHR &surface, double &seconds,
                  unsigned &images_made, std::string &error)
{
    const VkExtent2D extent = mode.parameters.visibleRegion;
    VkDisplaySurfaceCreateInfoKHR surface_info{};
    surface_info.sType = VK_STRUCTURE_TYPE_DISPLAY_SURFACE_CREATE_INFO_KHR;
    surface_info.displayMode = mode.displayMode;
    surface_info.transform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
    surface_info.alphaMode = VK_DISPLAY_PLANE_ALPHA_OPAQUE_BIT_KHR;
    surface_info.imageExtent = extent;
    VkSurfaceKHR new_surface;
    CHECK(vk.vkCreateDisplayPlaneSurfaceKHR(vk.instance, &surface_info, nullptr, &new_surface));
    VkSurfaceCapabilitiesKHR caps;
    CHECK(vk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vk.gpu, new_surface, &caps));
    if (caps.currentExtent.width != extent.width || caps.currentExtent.height != extent.height)
        return fail(error,
                    "surface extent " + std::to_string(caps.currentExtent.width) + "x" +
                        std::to_string(caps.currentExtent.height),
                    VK_ERROR_INITIALIZATION_FAILED);

    VkSwapchainCreateInfoKHR info{};
    info.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    info.surface = new_surface;
    info.minImageCount = 3;
    info.imageFormat = VK_FORMAT_B8G8R8A8_UNORM;
    info.imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
    info.imageExtent = extent;
    info.imageArrayLayers = 1;
    info.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    info.preTransform = VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
    info.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    info.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    info.clipped = VK_TRUE;
    info.oldSwapchain = chain;
    VkSwapchainKHR new_chain;
    CHECK(vk.vkCreateSwapchainKHR(vk.device, &info, nullptr, &new_chain));
    if (chain != VK_NULL_HANDLE)
        vk.vkDestroySwapchainKHR(vk.device, chain, nullptr);
    if (surface != VK_NULL_HANDLE)
        vk.vkDestroySurfaceKHR(vk.instance, surface, nullptr);
    chain = new_chain;
    surface = new_surface;

    uint32_t count = 0;
    CHECK(vk.vkGetSwapchainImagesKHR(vk.device, chain, &count, nullptr));
    std::vector<VkImage> images(count);
    CHECK(vk.vkGetSwapchainImagesKHR(vk.device, chain, &count, images.data()));
    images_made = count;

    /* The pattern, once, in a host buffer each frame copies from. */
    const VkDeviceSize bytes = VkDeviceSize(extent.width) * extent.height * 4;
    VkBufferCreateInfo buffer_info{};
    buffer_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buffer_info.size = bytes;
    buffer_info.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    VkBuffer buffer;
    CHECK(vk.vkCreateBuffer(vk.device, &buffer_info, nullptr, &buffer));
    VkMemoryRequirements reqs;
    vk.vkGetBufferMemoryRequirements(vk.device, buffer, &reqs);
    VkMemoryAllocateInfo allocate{};
    allocate.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocate.allocationSize = reqs.size;
    allocate.memoryTypeIndex = host_memory_type(vk, reqs.memoryTypeBits);
    if (allocate.memoryTypeIndex == UINT32_MAX)
        return fail(error, "a host-visible memory type", VK_ERROR_FEATURE_NOT_PRESENT);
    VkDeviceMemory memory;
    CHECK(vk.vkAllocateMemory(vk.device, &allocate, nullptr, &memory));
    CHECK(vk.vkBindBufferMemory(vk.device, buffer, memory, 0));
    void *mapped = nullptr;
    CHECK(vk.vkMapMemory(vk.device, memory, 0, bytes, 0, &mapped));
    fill_pattern(static_cast<uint32_t *>(mapped), extent);

    VkSemaphoreCreateInfo semaphore_info{};
    semaphore_info.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    VkFenceCreateInfo fence_info{};
    fence_info.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    VkSemaphore acquired, copied;
    VkFence done;
    CHECK(vk.vkCreateSemaphore(vk.device, &semaphore_info, nullptr, &acquired));
    CHECK(vk.vkCreateSemaphore(vk.device, &semaphore_info, nullptr, &copied));
    CHECK(vk.vkCreateFence(vk.device, &fence_info, nullptr, &done));
    VkCommandBufferAllocateInfo command_info{};
    command_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    command_info.commandPool = vk.pool;
    command_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    command_info.commandBufferCount = 1;
    VkCommandBuffer cmd;
    CHECK(vk.vkAllocateCommandBuffers(vk.device, &command_info, &cmd));

    const auto start = std::chrono::steady_clock::now();
    for (unsigned frame = 0; frame < frames; frame++)
    {
        uint32_t index;
        CHECK(vk.vkAcquireNextImageKHR(vk.device, chain, UINT64_MAX, acquired, VK_NULL_HANDLE,
                                       &index));
        VkCommandBufferBeginInfo begin{};
        begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        CHECK(vk.vkResetCommandBuffer(cmd, 0));
        CHECK(vk.vkBeginCommandBuffer(cmd, &begin));
        VkImageMemoryBarrier barrier{};
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.srcQueueFamilyIndex = barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.image = images[index];
        barrier.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        vk.vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                                VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1,
                                &barrier);
        VkBufferImageCopy region{};
        region.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        region.imageExtent = {extent.width, extent.height, 1};
        vk.vkCmdCopyBufferToImage(cmd, buffer, images[index], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                  1, &region);
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = 0;
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        vk.vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT,
                                VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, nullptr, 0, nullptr, 1,
                                &barrier);
        CHECK(vk.vkEndCommandBuffer(cmd));
        const VkPipelineStageFlags stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
        VkSubmitInfo submit{};
        submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submit.waitSemaphoreCount = 1;
        submit.pWaitSemaphores = &acquired;
        submit.pWaitDstStageMask = &stage;
        submit.commandBufferCount = 1;
        submit.pCommandBuffers = &cmd;
        submit.signalSemaphoreCount = 1;
        submit.pSignalSemaphores = &copied;
        CHECK(vk.vkQueueSubmit(vk.queue, 1, &submit, done));
        VkPresentInfoKHR present{};
        present.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        present.waitSemaphoreCount = 1;
        present.pWaitSemaphores = &copied;
        present.swapchainCount = 1;
        present.pSwapchains = &chain;
        present.pImageIndices = &index;
        CHECK(vk.vkQueuePresentKHR(vk.queue, &present));
        CHECK(vk.vkWaitForFences(vk.device, 1, &done, VK_TRUE, UINT64_MAX));
        CHECK(vk.vkResetFences(vk.device, 1, &done));
    }
    seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    CHECK(vk.vkDeviceWaitIdle(vk.device));
    vk.vkDestroyFence(vk.device, done, nullptr);
    vk.vkDestroySemaphore(vk.device, copied, nullptr);
    vk.vkDestroySemaphore(vk.device, acquired, nullptr);
    vk.vkDestroyBuffer(vk.device, buffer, nullptr);
    vk.vkFreeMemory(vk.device, memory, nullptr);
    return true;
}

/* The instance, the display's modes, the device, its queue and a command pool. */
bool set_up(Vk &vk, std::vector<VkDisplayModePropertiesKHR> &modes, std::string &error)
{
    vk.vkCreateInstance =
        (PFN_vkCreateInstance)vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance");
    const char *const instance_extensions[] = {VK_KHR_SURFACE_EXTENSION_NAME,
                                               VK_KHR_DISPLAY_EXTENSION_NAME};
    VkApplicationInfo app{};
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.pApplicationName = "PS5 RetroArch display modes test";
    app.apiVersion = VK_API_VERSION_1_1;
    VkInstanceCreateInfo instance_info{};
    instance_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    instance_info.pApplicationInfo = &app;
    instance_info.enabledExtensionCount = 2;
    instance_info.ppEnabledExtensionNames = instance_extensions;
    CHECK(vk.vkCreateInstance(&instance_info, nullptr, &vk.instance));
#define LOAD_INSTANCE(name) vk.name = (PFN_##name)vkGetInstanceProcAddr(vk.instance, #name);
    INSTANCE_COMMANDS(LOAD_INSTANCE)
#undef LOAD_INSTANCE
    uint32_t count = 1;
    vk.vkEnumeratePhysicalDevices(vk.instance, &count, &vk.gpu);
    if (count == 0)
        return fail(error, "vkEnumeratePhysicalDevices: none", VK_ERROR_INITIALIZATION_FAILED);
    VkDisplayPropertiesKHR display{};
    count = 1;
    vk.vkGetPhysicalDeviceDisplayPropertiesKHR(vk.gpu, &count, &display);
    if (count == 0)
        return fail(error, "vkGetPhysicalDeviceDisplayPropertiesKHR: none",
                    VK_ERROR_INITIALIZATION_FAILED);
    uint32_t mode_count = 0;
    CHECK(vk.vkGetDisplayModePropertiesKHR(vk.gpu, display.display, &mode_count, nullptr));
    modes.resize(mode_count);
    CHECK(vk.vkGetDisplayModePropertiesKHR(vk.gpu, display.display, &mode_count, modes.data()));
    std::string list = "display modes test: " + std::to_string(mode_count) + " modes:";
    for (const auto &mode : modes)
        list += " " + std::to_string(mode.parameters.visibleRegion.width) + "x" +
                std::to_string(mode.parameters.visibleRegion.height) + "@" +
                std::to_string(mode.parameters.refreshRate);
    ps5::debug::mark(list.c_str());

    float priority = 1.0f;
    VkDeviceQueueCreateInfo queue_info{};
    queue_info.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &priority;
    const char *const device_extensions[] = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    VkDeviceCreateInfo device_info{};
    device_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    device_info.queueCreateInfoCount = 1;
    device_info.pQueueCreateInfos = &queue_info;
    device_info.enabledExtensionCount = 1;
    device_info.ppEnabledExtensionNames = device_extensions;
    CHECK(vk.vkCreateDevice(vk.gpu, &device_info, nullptr, &vk.device));
#define LOAD_DEVICE(name) vk.name = (PFN_##name)vk.vkGetDeviceProcAddr(vk.device, #name);
    DEVICE_COMMANDS(LOAD_DEVICE)
#undef LOAD_DEVICE
    vk.vkGetDeviceQueue(vk.device, 0, 0, &vk.queue);
    VkCommandPoolCreateInfo pool_info{};
    pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    CHECK(vk.vkCreateCommandPool(vk.device, &pool_info, nullptr, &vk.pool));
    return true;
}

bool append(const std::string &path, const std::string &line)
{
    std::FILE *file = std::fopen(path.c_str(), "ab");
    if (!file)
        return false;
    const bool ok = std::fprintf(file, "%s\n", line.c_str()) > 0;
    return std::fclose(file) == 0 && ok;
}
} // namespace

bool run_test(const std::string &arm, const std::string &results)
{
    std::FILE *file = std::fopen(arm.c_str(), "rb");
    if (!file)
        return false;
    unsigned frames = 0;
    if (std::fscanf(file, "%u", &frames) != 1 || frames == 0 || frames > 1200)
        frames = 180;
    std::fclose(file);
    std::remove(arm.c_str());
    std::remove(results.c_str());
    ps5::debug::mark_value("display modes test: frames a mode", frames);

    Vk vk{};
    bool passed = false;
    VkSwapchainKHR chain = VK_NULL_HANDLE;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    std::vector<VkDisplayModePropertiesKHR> modes;
    std::string error;
    if (!set_up(vk, modes, error))
    {
        const std::string line = "{\"setup\":\"" + error + "\"}";
        ps5::debug::mark(("display modes test: " + line).c_str());
        append(results, line);
    }
    else
    {
        /* Every mode, then the first again: its set is registered already. */
        std::vector<VkDisplayModePropertiesKHR> order = modes;
        if (!modes.empty())
            order.push_back(modes.front());
        passed = !order.empty();
        for (const auto &mode : order)
        {
            double seconds = 0;
            unsigned images = 0;
            error.clear();
            if (!present_mode(vk, mode, frames, chain, surface, seconds, images, error))
                passed = false;
            const std::string line = mode_line(mode.parameters, frames, images, seconds, error);
            ps5::debug::mark(("display modes test: " + line).c_str());
            append(results, line);
            if (!error.empty())
                break;
        }
    }
    if (vk.device != VK_NULL_HANDLE)
    {
        vk.vkDeviceWaitIdle(vk.device);
        if (chain != VK_NULL_HANDLE)
            vk.vkDestroySwapchainKHR(vk.device, chain, nullptr);
        if (vk.pool != VK_NULL_HANDLE)
            vk.vkDestroyCommandPool(vk.device, vk.pool, nullptr);
        vk.vkDestroyDevice(vk.device, nullptr);
    }
    if (vk.instance != VK_NULL_HANDLE)
    {
        if (surface != VK_NULL_HANDLE)
            vk.vkDestroySurfaceKHR(vk.instance, surface, nullptr);
        vk.vkDestroyInstance(vk.instance, nullptr);
    }
    append(results, std::string("{\"result\":\"") + (passed ? "PASS" : "FAIL") + "\"}");
    ps5::debug::mark(passed ? "display modes test: PASS" : "display modes test: FAIL");
    return passed;
}
} // namespace ps5::display_modes

extern "C" void ps5_display_modes_test_if_requested()
{
    ps5::display_modes::run_test("/app0/display-modes-test.txt", "/app0/display-modes-test.jsonl");
}
