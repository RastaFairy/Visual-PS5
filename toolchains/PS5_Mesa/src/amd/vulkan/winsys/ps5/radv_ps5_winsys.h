/*
 * Copyright © 2026 Mihawk
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef RADV_PS5_WINSYS_H
#define RADV_PS5_WINSYS_H

#include "radv_ps5_platform.h"
#include "radv_ps5_winsys_public.h"

#include "c11/threads.h"
#include "util/simple_mtx.h"
#include "util/u_dynarray.h"

/* The console exposes one graphics queue to a title, and submissions to it run
 * in order. Every context and every RADV queue shares it: a submission gets
 * the next sequence number, the words it carries end with a packet that writes
 * that number's low 32 bits to the marker once they have run, and the GPU has
 * run everything up to the number the marker names (PS5_Vulkan R69). */

/* The ring the submissions' words are copied into (a PM4 INDIRECT_BUFFER into
 * title memory faulted the GPU, PS5_Vulkan B8). A submission's words go to the
 * GPU as one AGC submission, or several in order when they are too many for
 * one (radv_ps5_cs.c). The ring is large enough for most; a larger one gets a
 * buffer of its own. */
#define RADV_PS5_RING_BYTES (UINT64_C(16) << 20)
#define RADV_PS5_RING_WORDS ((uint32_t)(RADV_PS5_RING_BYTES / 4))
#define RADV_PS5_MAX_IN_FLIGHT 4096

struct radv_ps5_in_flight {
   uint64_t seq;
   /* Words [start, end) of the ring, or a buffer of its own. */
   uint32_t start;
   uint32_t end;
   struct radv_ps5_memory dedicated;
};

/* The GPU queue, shared by every winsys in the process: each VkDevice gets a
 * winsys of its own, but they all submit to the one queue, so the sequence
 * numbers, the marker and the ring are the process's. */
struct radv_ps5_queue {
   /* Held while a submission claims ring space, writes its words and submits,
    * so sequence numbers reach the GPU in order. */
   simple_mtx_t submit_lock;
   struct radv_ps5_memory ring;
   uint32_t ring_head;
   struct radv_ps5_in_flight in_flight[RADV_PS5_MAX_IN_FLIGHT];
   uint32_t in_flight_first;
   uint32_t in_flight_count;

   /* The marker the completion packets write, in its own buffer. */
   struct radv_ps5_memory marker_memory;
   volatile uint32_t *marker;
   /* Written under submit_lock (submitted) or atomically (completed). */
   uint64_t submitted_seq;
   uint64_t completed_seq;

   /* The tessellation factor ring AGC holds, and whether it holds RADV's
    * off-chip parameter (submit_lock). */
   uint64_t tess_factor_ring_va;
   uint32_t tess_factor_ring_size;
   bool hs_offchip_param_set;

   /* Waiters for a sync object to be submitted for signalling. */
   mtx_t sync_lock;
   cnd_t sync_cond;
};

/* The process's queue, created by the first winsys; NULL if it cannot be. */
struct radv_ps5_queue *radv_ps5_queue_get(void);

/* The GPU's timestamp clock, read through the queue; 0 if it cannot be. */
uint64_t radv_ps5_read_gpu_clock(void);

struct radv_ps5_winsys {
   struct radeon_winsys base;
   struct radeon_info info;
   uint64_t debug_flags;
   uint64_t perftest_flags;
   struct radv_ps5_queue *queue;

   uint64_t allocated_vram;
   uint64_t allocated_gtt;
};

static inline struct radv_ps5_winsys *
radv_ps5_winsys(struct radeon_winsys *base)
{
   return (struct radv_ps5_winsys *)base;
}

struct radv_ps5_bo {
   struct radeon_winsys_bo base;
   struct radv_ps5_winsys *ws;
   struct radv_ps5_memory memory;
   enum radeon_bo_flag flags;
   struct radeon_bo_metadata metadata;
   /* A second CPU mapping at an address the application chose
    * (VK_EXT_map_memory_placed), or NULL. */
   void *placed;
   /* A sparse resource's range (RADEON_FLAG_VIRTUAL): memory is the reserved
    * range, and buffers are bound into it. */
   bool sparse;
   /* Host memory the application owns (buffer_from_ptr), which the buffer
    * does not free. */
   bool imported;
};

static inline struct radv_ps5_bo *
radv_ps5_bo(struct radeon_winsys_bo *base)
{
   return (struct radv_ps5_bo *)base;
}

/* A command stream: its words live in CPU memory in chunks, since a submission
 * copies them into the ring anyway, and a chunk never moves once written so
 * nothing RADV keeps an index or a pointer to changes. */
struct radv_ps5_cs_chunk {
   uint32_t *words;
   uint32_t cdw;
   uint32_t max_dw;
   /* The chunk starts at a split (cs_split): an AGC submission may begin with
    * it, after the preamble. */
   bool starts_submission;
};

struct radv_ps5_cs {
   struct ac_cmdbuf base;
   struct radv_ps5_winsys *ws;
   enum amd_ip_type ip_type;
   bool is_secondary;
   VkResult status;
   /* Finished chunks, oldest first; the current one is base.buf. */
   struct util_dynarray chunks;
   uint32_t words_in_chunks;
   /* The current chunk starts at a split, and where in the stream the last
    * split (or the start) is. */
   bool buf_starts_submission;
   uint32_t split_at;
};

static inline struct radv_ps5_cs *
radv_ps5_cs(struct ac_cmdbuf *base)
{
   return (struct radv_ps5_cs *)base;
}

/* RADV's queues per IP type, as the amdgpu winsys counts them. */
enum { MAX_RINGS_PER_TYPE = 8 };

struct radv_ps5_ctx {
   struct radv_ps5_winsys *ws;
   enum radeon_ctx_priority priority;
   /* Whether a submission on this context carried its initial preamble. */
   bool queue_used[AMD_NUM_IP_TYPES][MAX_RINGS_PER_TYPE];
   /* The tessellation factor ring this context's submissions use, if any. */
   uint64_t tess_factor_ring_va;
   uint32_t tess_factor_ring_size;
};

/* Completion: the sequence the GPU has run up to, read from the marker. */
uint64_t radv_ps5_queue_poll(struct radv_ps5_queue *queue);
/* Waits until the GPU has run seq, or until abs_timeout_ns (os_time_get_nano's
 * clock); false on timeout. */
bool radv_ps5_queue_wait_seq(struct radv_ps5_queue *queue, uint64_t seq, uint64_t abs_timeout_ns);

/* The sync object type: binary, signalled by a submission's sequence number or
 * by the host. The physical device builds timelines over it
 * (vk_sync_timeline). */
extern const struct vk_sync_type radv_ps5_sync_type;
/* Waits until every sync in waits has been submitted for signalling (or
 * signalled by the host), then returns the latest sequence they depend on. */
VkResult radv_ps5_sync_wait_submitted(uint32_t wait_count, const struct vk_sync_wait *waits, uint64_t *seq);
/* Marks signals as signalled once the GPU has run seq. */
void radv_ps5_sync_signal_seq(uint32_t signal_count, const struct vk_sync_signal *signals, uint64_t seq);
VkResult radv_ps5_sync_copy_payloads(struct vk_device *device, uint32_t wait_count, const struct vk_sync_wait *waits,
                                     uint32_t signal_count, const struct vk_sync_signal *signals);

/* Direct memory held by every winsys in the process. */
extern uint64_t radv_ps5_allocated_bytes;

void radv_ps5_bo_init_functions(struct radv_ps5_winsys *ws);
void radv_ps5_cs_init_functions(struct radv_ps5_winsys *ws);

#endif /* RADV_PS5_WINSYS_H */
