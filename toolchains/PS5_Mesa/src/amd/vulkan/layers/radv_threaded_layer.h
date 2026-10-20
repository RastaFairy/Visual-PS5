/*
 * Copyright © 2026 Mihawk
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef RADV_THREADED_LAYER_H
#define RADV_THREADED_LAYER_H

#include <stdbool.h>

#include "vulkan/vulkan_core.h"

struct radv_cmd_buffer;
struct radv_device;

/* Threaded recording (RADV_THREADED_RECORDING=1): an application's vkCmd*
 * calls are queued on the command buffer (the runtime's vk_cmd_queue, the
 * arguments copied) and a worker thread of the device records them, batch by
 * batch, while the application goes on; vkEndCommandBuffer returns once the
 * worker has recorded everything queued. The application's thread spends
 * what copying the arguments costs instead of what recording does. */

bool radv_threaded_recording_enabled(void);
VkResult radv_threaded_device_init(struct radv_device *device);
void radv_threaded_device_finish(struct radv_device *device);

/* True on the worker while it records: a runtime helper that calls back
 * through the device's dispatch table then goes straight down. */
bool radv_threaded_replaying(void);

/* A command was queued; at a kick point with enough queued, the worker gets it. */
void radv_threaded_note(struct radv_cmd_buffer *cmd_buffer, bool kick_point);

/* Everything queued on the command buffer is recorded when this returns. */
void radv_threaded_drain(struct radv_cmd_buffer *cmd_buffer);

/* Every batch handed to the worker so far is recorded when this returns: the
 * layer's destroys and frees call it first, since a queued command may name
 * the object (radv_threaded_layer_gen.py). */
void radv_threaded_barrier(struct radv_device *device);

void radv_threaded_queue_CmdBindDescriptorSets(VkCommandBuffer commandBuffer, VkPipelineBindPoint pipelineBindPoint,
                                               VkPipelineLayout layout, uint32_t firstSet,
                                               uint32_t descriptorSetCount, const VkDescriptorSet *pDescriptorSets,
                                               uint32_t dynamicOffsetCount, const uint32_t *pDynamicOffsets);

void radv_threaded_queue_CmdPushConstants(VkCommandBuffer commandBuffer, VkPipelineLayout layout,
                                          VkShaderStageFlags stageFlags, uint32_t offset, uint32_t size,
                                          const void *pValues);

#endif /* RADV_THREADED_LAYER_H */
