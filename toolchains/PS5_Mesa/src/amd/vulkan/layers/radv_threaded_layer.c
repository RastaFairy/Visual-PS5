/*
 * Copyright © 2026 Mihawk
 *
 * SPDX-License-Identifier: MIT
 */

/* Threaded recording (radv_threaded_layer.h). The application's thread queues
 * commands on the command buffer's vk_cmd_queue (the generated threaded_Cmd*
 * entrypoints, radv_threaded_layer_gen.py); at kick points it moves what is
 * queued into a batch for the device's worker, which records the batch into
 * the command buffer through the layer's own dispatch table (the rest of
 * RADV). A command buffer is only ever recorded by one thread at a time: the
 * worker while it has batches of it, the application's thread otherwise
 * (vkBeginCommandBuffer, vkEndCommandBuffer, resets and frees, and the few
 * commands the layer records directly, all wait for the worker first).
 *
 * What the queue copies is what a command's arguments point to, not the
 * objects they name. The application may destroy one of those while the
 * command buffer records (the command buffer becomes invalid, and only a
 * reset, a begin or a free is left to it), so every destroy and free first
 * waits for the batches handed to the worker before it, and resets, begins
 * and frees drop what is still queued instead of recording it. */

#include "radv_threaded_layer.h"

#include "radv_cmd_buffer.h"
#include "radv_device.h"
#include "radv_entrypoints.h"

#include "util/list.h"
#include "util/os_misc.h"
#include "util/u_atomic.h"
#include "c11/threads.h"
#include "vk_cmd_queue.h"
#include "vk_command_pool.h"

/* Queued commands a kick point hands over; fewer wait for the next one. */
#define RADV_THREADED_KICK_COMMANDS 48
/* Queued commands handed over whatever the command. */
#define RADV_THREADED_MAX_COMMANDS 512
/* How long the worker looks for more work before it sleeps. */
#define RADV_THREADED_SPIN_NS 50000

struct radv_threaded_batch {
   struct list_head link;
   struct list_head cmds;
   struct radv_cmd_buffer *cmd_buffer;
};

struct radv_threaded_recorder {
   mtx_t lock;
   cnd_t work;
   cnd_t done;
   struct list_head batches;
   uint64_t kicked;   /* batches handed over so far */
   uint64_t recorded; /* of those, the ones recorded (in order: one worker) */
   uint32_t barriers; /* threads waiting in radv_threaded_barrier */
   uint32_t queued;   /* batches waiting, read without the lock while spinning */
   bool sleeping;     /* the worker waits on work */
   bool stop;
   thrd_t thread;
};

static thread_local bool radv_threaded_on_worker;

bool
radv_threaded_recording_enabled(void)
{
   return os_get_option("RADV_THREADED_RECORDING") && atoi(os_get_option("RADV_THREADED_RECORDING")) != 0;
}

bool
radv_threaded_replaying(void)
{
   return radv_threaded_on_worker;
}

static uint64_t
radv_threaded_now_ns(void)
{
   struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC, &ts);
   return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static int
radv_threaded_worker(void *opaque)
{
   struct radv_device *device = opaque;
   struct radv_threaded_recorder *rec = device->threaded;
   radv_threaded_on_worker = true;

   mtx_lock(&rec->lock);
   for (;;) {
      if (list_is_empty(&rec->batches)) {
         if (rec->stop)
            break;

         /* Look for more for a while before sleeping: the application's thread
          * hands over batches every few draws and waking a sleeper costs it. */
         mtx_unlock(&rec->lock);
         const uint64_t until = radv_threaded_now_ns() + RADV_THREADED_SPIN_NS;
         while (!p_atomic_read(&rec->queued) && radv_threaded_now_ns() < until)
            __builtin_ia32_pause();
         mtx_lock(&rec->lock);

         if (list_is_empty(&rec->batches) && !rec->stop) {
            rec->sleeping = true;
            cnd_wait(&rec->work, &rec->lock);
            rec->sleeping = false;
         }
         continue;
      }

      struct radv_threaded_batch *batch = list_first_entry(&rec->batches, struct radv_threaded_batch, link);
      list_del(&batch->link);
      p_atomic_dec(&rec->queued);
      mtx_unlock(&rec->lock);

      struct radv_cmd_buffer *cmd_buffer = batch->cmd_buffer;
      struct vk_cmd_queue queue = {0};
      list_replace(&batch->cmds, &queue.cmds);
      vk_cmd_queue_execute(&queue, radv_cmd_buffer_to_handle(cmd_buffer), &device->layer_dispatch.threaded);

      mtx_lock(&rec->lock);
      rec->recorded++;
      if (p_atomic_dec_zero(&cmd_buffer->threaded.pending) || rec->barriers)
         cnd_broadcast(&rec->done);
   }
   mtx_unlock(&rec->lock);
   return 0;
}

VkResult
radv_threaded_device_init(struct radv_device *device)
{
   struct radv_threaded_recorder *rec =
      vk_zalloc(&device->vk.alloc, sizeof(*rec), 8, VK_SYSTEM_ALLOCATION_SCOPE_DEVICE);
   if (!rec)
      return VK_ERROR_OUT_OF_HOST_MEMORY;

   mtx_init(&rec->lock, mtx_plain);
   cnd_init(&rec->work);
   cnd_init(&rec->done);
   list_inithead(&rec->batches);
   device->threaded = rec;

   if (thrd_create(&rec->thread, radv_threaded_worker, device) != thrd_success) {
      device->threaded = NULL;
      mtx_destroy(&rec->lock);
      cnd_destroy(&rec->work);
      cnd_destroy(&rec->done);
      vk_free(&device->vk.alloc, rec);
      return VK_ERROR_INITIALIZATION_FAILED;
   }

   return VK_SUCCESS;
}

void
radv_threaded_device_finish(struct radv_device *device)
{
   struct radv_threaded_recorder *rec = device->threaded;
   if (!rec)
      return;

   mtx_lock(&rec->lock);
   rec->stop = true;
   cnd_signal(&rec->work);
   mtx_unlock(&rec->lock);
   thrd_join(rec->thread, NULL);

   mtx_destroy(&rec->lock);
   cnd_destroy(&rec->work);
   cnd_destroy(&rec->done);
   vk_free(&device->vk.alloc, rec);
   device->threaded = NULL;
}

static void radv_threaded_wait(struct radv_cmd_buffer *cmd_buffer);

/* Hands what is queued on the command buffer to the worker. */
static void
radv_threaded_kick(struct radv_cmd_buffer *cmd_buffer)
{
   struct radv_device *device = radv_cmd_buffer_device(cmd_buffer);
   struct radv_threaded_recorder *rec = device->threaded;
   struct vk_cmd_queue *queue = &cmd_buffer->vk.cmd_queue;

   cmd_buffer->threaded.queued = 0;
   if (!queue->ctx || list_is_empty(&queue->cmds))
      return;

   struct radv_threaded_batch *batch = linear_alloc_child(queue->ctx, sizeof(*batch));
   if (!batch) {
      /* Recorded here instead, once the worker is done with it. */
      radv_threaded_wait(cmd_buffer);
      radv_threaded_on_worker = true;
      vk_cmd_queue_execute(queue, radv_cmd_buffer_to_handle(cmd_buffer), &device->layer_dispatch.threaded);
      radv_threaded_on_worker = false;
      list_inithead(&queue->cmds);
      return;
   }

   batch->cmd_buffer = cmd_buffer;
   list_replace(&queue->cmds, &batch->cmds);
   list_inithead(&queue->cmds);

   p_atomic_inc(&cmd_buffer->threaded.pending);

   mtx_lock(&rec->lock);
   list_addtail(&batch->link, &rec->batches);
   rec->kicked++;
   p_atomic_inc(&rec->queued);
   if (rec->sleeping)
      cnd_signal(&rec->work);
   mtx_unlock(&rec->lock);
}

void
radv_threaded_note(struct radv_cmd_buffer *cmd_buffer, bool kick_point)
{
   const uint32_t queued = ++cmd_buffer->threaded.queued;
   if ((kick_point && queued >= RADV_THREADED_KICK_COMMANDS) || queued >= RADV_THREADED_MAX_COMMANDS)
      radv_threaded_kick(cmd_buffer);
}

/* Waits for the batches of the command buffer the worker has. */
static void
radv_threaded_wait(struct radv_cmd_buffer *cmd_buffer)
{
   struct radv_device *device = radv_cmd_buffer_device(cmd_buffer);
   struct radv_threaded_recorder *rec = device->threaded;

   if (!p_atomic_read(&cmd_buffer->threaded.pending))
      return;

   mtx_lock(&rec->lock);
   while (p_atomic_read(&cmd_buffer->threaded.pending))
      cnd_wait(&rec->done, &rec->lock);
   mtx_unlock(&rec->lock);
}

void
radv_threaded_drain(struct radv_cmd_buffer *cmd_buffer)
{
   radv_threaded_kick(cmd_buffer);
   radv_threaded_wait(cmd_buffer);
}

/* For a reset, a begin or a free: what is still queued is dropped (it may
 * name objects destroyed since, and nothing recorded so far is kept) and
 * what the worker has is waited for. The queue's memory goes with the reset. */
static void
radv_threaded_discard(struct radv_cmd_buffer *cmd_buffer)
{
   struct vk_cmd_queue *queue = &cmd_buffer->vk.cmd_queue;

   cmd_buffer->threaded.queued = 0;
   if (queue->ctx)
      list_inithead(&queue->cmds);
   radv_threaded_wait(cmd_buffer);
}

void
radv_threaded_barrier(struct radv_device *device)
{
   struct radv_threaded_recorder *rec = device->threaded;

   /* The worker itself (a runtime helper destroying its own objects) has
    * recorded everything before what it records now. */
   if (!rec || radv_threaded_on_worker)
      return;

   mtx_lock(&rec->lock);
   const uint64_t target = rec->kicked;
   if (rec->recorded < target) {
      rec->barriers++;
      while (rec->recorded < target)
         cnd_wait(&rec->done, &rec->lock);
      rec->barriers--;
   }
   mtx_unlock(&rec->lock);
}

/* Every command buffer of the pool discarded (resets and frees of the pool)
 * or only waited for (trims, which leave recording command buffers be). */
static void
radv_threaded_pool(VkCommandPool commandPool, bool discard)
{
   VK_FROM_HANDLE(vk_command_pool, pool, commandPool);
   if (!pool)
      return;

   list_for_each_entry (struct vk_command_buffer, vk_cmd_buffer, &pool->command_buffers, pool_link) {
      struct radv_cmd_buffer *cmd_buffer = container_of(vk_cmd_buffer, struct radv_cmd_buffer, vk);
      if (discard)
         radv_threaded_discard(cmd_buffer);
      else
         radv_threaded_wait(cmd_buffer);
   }
}

void
radv_threaded_queue_CmdBindDescriptorSets(VkCommandBuffer commandBuffer, VkPipelineBindPoint pipelineBindPoint,
                                          VkPipelineLayout layout, uint32_t firstSet, uint32_t descriptorSetCount,
                                          const VkDescriptorSet *pDescriptorSets, uint32_t dynamicOffsetCount,
                                          const uint32_t *pDynamicOffsets)
{
   VK_FROM_HANDLE(radv_cmd_buffer, cmd_buffer, commandBuffer);
   struct vk_cmd_queue *queue = &cmd_buffer->vk.cmd_queue;

   if (vk_command_buffer_has_error(&cmd_buffer->vk))
      return;

   struct vk_cmd_queue_entry *cmd = linear_alloc_child(queue->ctx, vk_cmd_queue_type_sizes[VK_CMD_BIND_DESCRIPTOR_SETS]);
   VkDescriptorSet *sets = descriptorSetCount ? linear_alloc_child(queue->ctx, sizeof(*sets) * descriptorSetCount) : NULL;
   uint32_t *offsets = dynamicOffsetCount ? linear_alloc_child(queue->ctx, sizeof(*offsets) * dynamicOffsetCount) : NULL;
   if (!cmd || (descriptorSetCount && !sets) || (dynamicOffsetCount && !offsets)) {
      vk_command_buffer_set_error(&cmd_buffer->vk, VK_ERROR_OUT_OF_HOST_MEMORY);
      return;
   }

   if (descriptorSetCount)
      memcpy(sets, pDescriptorSets, sizeof(*sets) * descriptorSetCount);
   if (dynamicOffsetCount)
      memcpy(offsets, pDynamicOffsets, sizeof(*offsets) * dynamicOffsetCount);

   cmd->type = VK_CMD_BIND_DESCRIPTOR_SETS;
   cmd->u.bind_descriptor_sets.pipeline_bind_point = pipelineBindPoint;
   cmd->u.bind_descriptor_sets.layout = layout;
   cmd->u.bind_descriptor_sets.first_set = firstSet;
   cmd->u.bind_descriptor_sets.descriptor_set_count = descriptorSetCount;
   cmd->u.bind_descriptor_sets.descriptor_sets = sets;
   cmd->u.bind_descriptor_sets.dynamic_offset_count = dynamicOffsetCount;
   cmd->u.bind_descriptor_sets.dynamic_offsets = offsets;
   list_addtail(&cmd->cmd_link, &queue->cmds);
}

void
radv_threaded_queue_CmdPushConstants(VkCommandBuffer commandBuffer, VkPipelineLayout layout,
                                     VkShaderStageFlags stageFlags, uint32_t offset, uint32_t size, const void *pValues)
{
   VK_FROM_HANDLE(radv_cmd_buffer, cmd_buffer, commandBuffer);
   struct vk_cmd_queue *queue = &cmd_buffer->vk.cmd_queue;

   if (vk_command_buffer_has_error(&cmd_buffer->vk))
      return;

   struct vk_cmd_queue_entry *cmd = linear_alloc_child(queue->ctx, vk_cmd_queue_type_sizes[VK_CMD_PUSH_CONSTANTS]);
   void *values = size ? linear_alloc_child(queue->ctx, size) : NULL;
   if (!cmd || (size && !values)) {
      vk_command_buffer_set_error(&cmd_buffer->vk, VK_ERROR_OUT_OF_HOST_MEMORY);
      return;
   }

   if (size)
      memcpy(values, pValues, size);

   cmd->type = VK_CMD_PUSH_CONSTANTS;
   cmd->u.push_constants.layout = layout;
   cmd->u.push_constants.stage_flags = stageFlags;
   cmd->u.push_constants.offset = offset;
   cmd->u.push_constants.size = size;
   cmd->u.push_constants.values = values;
   list_addtail(&cmd->cmd_link, &queue->cmds);
}

/* The command buffer lifecycle: an end records what is queued first; a
 * begin, a reset or a free drops it (radv_threaded_discard). */

VKAPI_ATTR VkResult VKAPI_CALL
threaded_BeginCommandBuffer(VkCommandBuffer commandBuffer, const VkCommandBufferBeginInfo *pBeginInfo)
{
   VK_FROM_HANDLE(radv_cmd_buffer, cmd_buffer, commandBuffer);
   struct radv_device *device = radv_cmd_buffer_device(cmd_buffer);

   radv_threaded_discard(cmd_buffer);

   /* RADV makes its command buffers without the runtime's queue. */
   if (!cmd_buffer->vk.cmd_queue.ctx)
      vk_cmd_queue_init(&cmd_buffer->vk.cmd_queue);
   cmd_buffer->threaded.queued = 0;

   return device->layer_dispatch.threaded.BeginCommandBuffer(commandBuffer, pBeginInfo);
}

VKAPI_ATTR VkResult VKAPI_CALL
threaded_EndCommandBuffer(VkCommandBuffer commandBuffer)
{
   VK_FROM_HANDLE(radv_cmd_buffer, cmd_buffer, commandBuffer);
   struct radv_device *device = radv_cmd_buffer_device(cmd_buffer);

   radv_threaded_drain(cmd_buffer);
   return device->layer_dispatch.threaded.EndCommandBuffer(commandBuffer);
}

VKAPI_ATTR VkResult VKAPI_CALL
threaded_ResetCommandBuffer(VkCommandBuffer commandBuffer, VkCommandBufferResetFlags flags)
{
   VK_FROM_HANDLE(radv_cmd_buffer, cmd_buffer, commandBuffer);
   struct radv_device *device = radv_cmd_buffer_device(cmd_buffer);

   radv_threaded_discard(cmd_buffer);
   return device->layer_dispatch.threaded.ResetCommandBuffer(commandBuffer, flags);
}

VKAPI_ATTR void VKAPI_CALL
threaded_FreeCommandBuffers(VkDevice _device, VkCommandPool commandPool, uint32_t commandBufferCount,
                            const VkCommandBuffer *pCommandBuffers)
{
   VK_FROM_HANDLE(radv_device, device, _device);

   for (uint32_t i = 0; i < commandBufferCount; i++) {
      if (pCommandBuffers[i])
         radv_threaded_discard(radv_cmd_buffer_from_handle(pCommandBuffers[i]));
   }

   device->layer_dispatch.threaded.FreeCommandBuffers(_device, commandPool, commandBufferCount, pCommandBuffers);
}

VKAPI_ATTR VkResult VKAPI_CALL
threaded_ResetCommandPool(VkDevice _device, VkCommandPool commandPool, VkCommandPoolResetFlags flags)
{
   VK_FROM_HANDLE(radv_device, device, _device);

   radv_threaded_pool(commandPool, true);
   return device->layer_dispatch.threaded.ResetCommandPool(_device, commandPool, flags);
}

VKAPI_ATTR void VKAPI_CALL
threaded_TrimCommandPool(VkDevice _device, VkCommandPool commandPool, VkCommandPoolTrimFlags flags)
{
   VK_FROM_HANDLE(radv_device, device, _device);

   radv_threaded_pool(commandPool, false);
   device->layer_dispatch.threaded.TrimCommandPool(_device, commandPool, flags);
}

VKAPI_ATTR void VKAPI_CALL
threaded_DestroyCommandPool(VkDevice _device, VkCommandPool commandPool, const VkAllocationCallbacks *pAllocator)
{
   VK_FROM_HANDLE(radv_device, device, _device);

   radv_threaded_pool(commandPool, true);
   device->layer_dispatch.threaded.DestroyCommandPool(_device, commandPool, pAllocator);
}
