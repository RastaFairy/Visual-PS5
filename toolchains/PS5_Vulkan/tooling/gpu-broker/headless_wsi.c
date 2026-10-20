/* Copyright (C) 2026 Mihawk-99 */
/* SPDX-License-Identifier: LGPL-2.1-or-later */
/* The offscreen client has no display targets and no native VideoOut import. */
#include <vulkan/vulkan.h>
struct wsi_device;
struct wsi_swapchain;
struct wsi_image_info;
VkResult wsi_display_init_wsi(struct wsi_device *w,const VkAllocationCallbacks *a,int fd)
{ (void)w;(void)a;(void)fd;return VK_SUCCESS; }
void wsi_display_finish_wsi(struct wsi_device *w,const VkAllocationCallbacks *a) { (void)w;(void)a; }
void wsi_display_setup_syncobj_fd(struct wsi_device *w,int fd) { (void)w;(void)fd; }
int wsi_videoout_set_flip_rate(int rate) { (void)rate;return -1; }
#define EMPTY(name,type) VkResult name(VkPhysicalDevice p,uint32_t *count,type *values) \
{ (void)p;(void)values;*count=0;return VK_SUCCESS; }
EMPTY(wsi_GetPhysicalDeviceDisplayPropertiesKHR,VkDisplayPropertiesKHR)
EMPTY(wsi_GetPhysicalDeviceDisplayProperties2KHR,VkDisplayProperties2KHR)
EMPTY(wsi_GetPhysicalDeviceDisplayPlanePropertiesKHR,VkDisplayPlanePropertiesKHR)
EMPTY(wsi_GetPhysicalDeviceDisplayPlaneProperties2KHR,VkDisplayPlaneProperties2KHR)
VkResult wsi_GetDisplayPlaneSupportedDisplaysKHR(VkPhysicalDevice p,uint32_t plane,uint32_t *count,VkDisplayKHR *values)
{ (void)p;(void)plane;(void)values;*count=0;return VK_SUCCESS; }
#define MODES(name,type) VkResult name(VkPhysicalDevice p,VkDisplayKHR d,uint32_t *count,type *values) \
{ (void)p;(void)d;(void)values;*count=0;return VK_SUCCESS; }
MODES(wsi_GetDisplayModePropertiesKHR,VkDisplayModePropertiesKHR)
MODES(wsi_GetDisplayModeProperties2KHR,VkDisplayModeProperties2KHR)
VkResult wsi_CreateDisplayModeKHR(VkPhysicalDevice p,VkDisplayKHR d,const VkDisplayModeCreateInfoKHR *info,
                                const VkAllocationCallbacks *a,VkDisplayModeKHR *mode)
{ (void)p;(void)d;(void)info;(void)a;(void)mode;return VK_ERROR_INITIALIZATION_FAILED; }
VkResult wsi_GetDisplayPlaneCapabilitiesKHR(VkPhysicalDevice p,VkDisplayModeKHR mode,uint32_t plane,VkDisplayPlaneCapabilitiesKHR *caps)
{ (void)p;(void)mode;(void)plane;(void)caps;return VK_ERROR_INITIALIZATION_FAILED; }
VkResult wsi_GetDisplayPlaneCapabilities2KHR(VkPhysicalDevice p,const VkDisplayPlaneInfo2KHR *info,VkDisplayPlaneCapabilities2KHR *caps)
{ (void)p;(void)info;(void)caps;return VK_ERROR_INITIALIZATION_FAILED; }
VkResult wsi_CreateDisplayPlaneSurfaceKHR(VkInstance i,const VkDisplaySurfaceCreateInfoKHR *info,const VkAllocationCallbacks *a,VkSurfaceKHR *surface)
{ (void)i;(void)info;(void)a;(void)surface;return VK_ERROR_INITIALIZATION_FAILED; }
VkResult wsi_videoout_configure_image(const struct wsi_swapchain *c,const VkSwapchainCreateInfoKHR *info,struct wsi_image_info *image)
{ (void)c;(void)info;(void)image;return VK_ERROR_FEATURE_NOT_PRESENT; }
