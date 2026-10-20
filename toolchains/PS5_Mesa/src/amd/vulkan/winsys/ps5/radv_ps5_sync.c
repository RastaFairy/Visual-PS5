/*
 * Copyright © 2026 Mihawk
 *
 * SPDX-License-Identifier: MIT
 */

#include "radv_ps5_winsys.h"

#include "util/os_time.h"
#include "vk_sync.h"

/* A binary sync object on the console's one queue. It is signalled by the
 * submission that carries it -- the GPU has run it once the queue's marker
 * passes that submission's sequence number -- or by the host at once. Every
 * submission runs after the ones before it, so a submission that waits on a
 * sync signalled by an earlier one needs only that signal to have been
 * submitted, never a GPU wait (PS5_Vulkan R69). The state is guarded by the
 * queue's sync lock, whose condition wakes waiters when a signal is submitted.
 */
struct radv_ps5_sync {
   struct vk_sync base;
   /* A signal has been submitted, or made by the host. */
   bool pending;
   /* Signalled once the GPU has run this sequence (0: already). */
   uint64_t seq;
};

static inline struct radv_ps5_sync *
radv_ps5_sync(struct vk_sync *sync)
{
   return container_of(sync, struct radv_ps5_sync, base);
}

static struct radv_ps5_queue *
radv_ps5_sync_queue(void)
{
   return radv_ps5_queue_get();
}

static VkResult
radv_ps5_sync_init(struct vk_device *device, struct vk_sync *vk_sync, uint64_t initial_value)
{
   (void)device;
   struct radv_ps5_sync *const sync = radv_ps5_sync(vk_sync);
   sync->pending = initial_value != 0;
   sync->seq = 0;
   return VK_SUCCESS;
}

static void
radv_ps5_sync_finish(struct vk_device *device, struct vk_sync *vk_sync)
{
   (void)device;
   (void)vk_sync;
}

static void
radv_ps5_sync_set(struct radv_ps5_sync *sync, bool pending, uint64_t seq)
{
   struct radv_ps5_queue *const queue = radv_ps5_sync_queue();
   mtx_lock(&queue->sync_lock);
   sync->pending = pending;
   sync->seq = seq;
   if (pending)
      cnd_broadcast(&queue->sync_cond);
   mtx_unlock(&queue->sync_lock);
}

static VkResult
radv_ps5_sync_signal(struct vk_device *device, struct vk_sync *vk_sync, uint64_t value)
{
   (void)device;
   (void)value;
   radv_ps5_sync_set(radv_ps5_sync(vk_sync), true, 0);
   return VK_SUCCESS;
}

static VkResult
radv_ps5_sync_reset(struct vk_device *device, struct vk_sync *vk_sync)
{
   (void)device;
   radv_ps5_sync_set(radv_ps5_sync(vk_sync), false, 0);
   return VK_SUCCESS;
}

static VkResult
radv_ps5_sync_move(struct vk_device *device, struct vk_sync *dst, struct vk_sync *src)
{
   (void)device;
   struct radv_ps5_queue *const queue = radv_ps5_sync_queue();
   mtx_lock(&queue->sync_lock);
   struct radv_ps5_sync *const d = radv_ps5_sync(dst), *const s = radv_ps5_sync(src);
   d->pending = s->pending;
   d->seq = s->seq;
   s->pending = false;
   s->seq = 0;
   if (d->pending)
      cnd_broadcast(&queue->sync_cond);
   mtx_unlock(&queue->sync_lock);
   return VK_SUCCESS;
}

/* Whether one wait is satisfied: the signal submitted, and for a complete wait
 * the GPU past its sequence. Called with the sync lock held. */
static bool
radv_ps5_sync_ready(struct radv_ps5_queue *queue, const struct radv_ps5_sync *sync, enum vk_sync_wait_flags flags)
{
   if (!sync->pending)
      return false;
   if (flags & VK_SYNC_WAIT_PENDING)
      return true;
   return sync->seq == 0 || radv_ps5_queue_poll(queue) >= sync->seq;
}

static VkResult
radv_ps5_sync_wait_many(struct vk_device *device, uint32_t wait_count, const struct vk_sync_wait *waits,
                        enum vk_sync_wait_flags flags, uint64_t abs_timeout_ns)
{
   (void)device;
   struct radv_ps5_queue *const queue = radv_ps5_sync_queue();
   const bool any = flags & VK_SYNC_WAIT_ANY;

   mtx_lock(&queue->sync_lock);
   for (;;) {
      uint32_t ready = 0;
      /* The sequence the slowest ready-but-running wait still needs. */
      uint64_t need = 0;
      bool all_pending = true;
      for (uint32_t i = 0; i < wait_count; i++) {
         const struct radv_ps5_sync *const sync = radv_ps5_sync(waits[i].sync);
         if (radv_ps5_sync_ready(queue, sync, flags)) {
            ready++;
         } else if (sync->pending) {
            need = MAX2(need, sync->seq);
         } else {
            all_pending = false;
         }
      }
      if (any ? ready > 0 || wait_count == 0 : ready == wait_count) {
         mtx_unlock(&queue->sync_lock);
         return VK_SUCCESS;
      }
      const uint64_t now = os_time_get_nano();
      if (now >= abs_timeout_ns) {
         mtx_unlock(&queue->sync_lock);
         return VK_TIMEOUT;
      }
      if (all_pending && need != 0) {
         /* Everything waited for is submitted: the rest is the GPU's. */
         mtx_unlock(&queue->sync_lock);
         if (any) {
            radv_ps5_sleep_us(100);
         } else if (!radv_ps5_queue_wait_seq(queue, need, abs_timeout_ns)) {
            return os_time_get_nano() >= abs_timeout_ns ? VK_TIMEOUT : VK_ERROR_DEVICE_LOST;
         }
         mtx_lock(&queue->sync_lock);
         continue;
      }
      /* A signal still has to be submitted: sleep until one is, or a
       * millisecond passes so running work is polled too. */
      struct timespec until;
      const uint64_t wake = MIN2(abs_timeout_ns, now + 1000000);
      until.tv_sec = wake / 1000000000;
      until.tv_nsec = wake % 1000000000;
      cnd_timedwait(&queue->sync_cond, &queue->sync_lock, &until);
   }
}

const struct vk_sync_type radv_ps5_sync_type = {
   .size = sizeof(struct radv_ps5_sync),
   .features = VK_SYNC_FEATURE_BINARY | VK_SYNC_FEATURE_GPU_WAIT | VK_SYNC_FEATURE_GPU_MULTI_WAIT |
               VK_SYNC_FEATURE_CPU_WAIT | VK_SYNC_FEATURE_CPU_RESET | VK_SYNC_FEATURE_CPU_SIGNAL |
               VK_SYNC_FEATURE_WAIT_ANY | VK_SYNC_FEATURE_WAIT_PENDING,
   .init = radv_ps5_sync_init,
   .finish = radv_ps5_sync_finish,
   .signal = radv_ps5_sync_signal,
   .reset = radv_ps5_sync_reset,
   .move = radv_ps5_sync_move,
   .wait_many = radv_ps5_sync_wait_many,
};

VkResult
radv_ps5_sync_wait_submitted(uint32_t wait_count, const struct vk_sync_wait *waits, uint64_t *seq)
{
   *seq = 0;
   if (wait_count == 0)
      return VK_SUCCESS;
   const VkResult result = radv_ps5_sync_wait_many(NULL, wait_count, waits, VK_SYNC_WAIT_PENDING, OS_TIMEOUT_INFINITE);
   if (result != VK_SUCCESS)
      return result;
   struct radv_ps5_queue *const queue = radv_ps5_sync_queue();
   mtx_lock(&queue->sync_lock);
   for (uint32_t i = 0; i < wait_count; i++)
      *seq = MAX2(*seq, radv_ps5_sync(waits[i].sync)->seq);
   mtx_unlock(&queue->sync_lock);
   return VK_SUCCESS;
}

void
radv_ps5_sync_signal_seq(uint32_t signal_count, const struct vk_sync_signal *signals, uint64_t seq)
{
   if (signal_count == 0)
      return;
   struct radv_ps5_queue *const queue = radv_ps5_sync_queue();
   mtx_lock(&queue->sync_lock);
   for (uint32_t i = 0; i < signal_count; i++) {
      struct radv_ps5_sync *const sync = radv_ps5_sync(signals[i].sync);
      sync->pending = true;
      sync->seq = seq;
   }
   cnd_broadcast(&queue->sync_cond);
   mtx_unlock(&queue->sync_lock);
}

VkResult
radv_ps5_sync_copy_payloads(struct vk_device *device, uint32_t wait_count, const struct vk_sync_wait *waits,
                            uint32_t signal_count, const struct vk_sync_signal *signals)
{
   (void)device;
   uint64_t seq = 0;
   const VkResult result = radv_ps5_sync_wait_submitted(wait_count, waits, &seq);
   if (result != VK_SUCCESS)
      return result;
   radv_ps5_sync_signal_seq(signal_count, signals, seq);
   return VK_SUCCESS;
}
