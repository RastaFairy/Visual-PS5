/*
 * Copyright © 2026 Mihawk
 *
 * SPDX-License-Identifier: MIT
 */

#include "radv_ps5_winsys.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "util/os_time.h"
#include "util/u_atomic.h"
#include "util/u_math.h"
#include "sid.h"

/* Command streams. The console faults a PM4 INDIRECT_BUFFER into title memory
 * (PS5_Vulkan B8), so nothing is chained: a stream's words stay in CPU memory,
 * in chunks that never move, and a submission copies every stream it carries
 * into the queue's ring as AGC submissions, the last of which ends with the
 * packet that writes the submission's sequence number to the marker.
 *
 * Every chunk boundary is a packet boundary, which is where a submission too
 * large for one AGC submission is split. */

#define RADV_PS5_CS_INITIAL_DW (20 * 1024)
#define RADV_PS5_CS_MAX_CHUNK_DW (256u * 1024)

/* The most words one AGC submission carries: the INDIRECT_BUFFER that runs it
 * has a 20-bit size in words, and a larger one never completed on the console
 * (dEQP-VK.api.command_buffers.record_many_draws_primary_2, about 131,000
 * draws in one command buffer). */
#define RADV_PS5_SUBMIT_MAX_DW ((1u << 20) - 64)

/* Each AGC submission starts from reset GPU state: the same 131,000 draws split
 * into two submissions drew only the first part. So a submission is split
 * only where the GPU state is the preamble's -- where a stream starts, and at
 * a split RADV asked for (cs_split), after which it re-emits its state -- and
 * every part after the first starts with the preamble again. A stream asks for
 * a split once it holds this many words past the last one. */
#define RADV_PS5_SPLIT_DUE_DW (512u * 1024)

static bool
radv_ps5_cs_alloc(struct radv_ps5_cs *cs, uint32_t max_dw)
{
   uint32_t *const words = malloc((size_t)max_dw * sizeof(uint32_t));
   if (!words)
      return false;
   cs->base.buf = words;
   cs->base.max_dw = max_dw;
   cs->base.cdw = 0;
   cs->base.reserved_dw = 0;
   return true;
}

static struct ac_cmdbuf *
radv_ps5_cs_create(struct radeon_winsys *rws, enum amd_ip_type ip_type, bool is_secondary)
{
   struct radv_ps5_cs *const cs = calloc(1, sizeof(*cs));
   if (!cs)
      return NULL;
   cs->ws = radv_ps5_winsys(rws);
   cs->ip_type = ip_type;
   cs->is_secondary = is_secondary;
   cs->status = VK_SUCCESS;
   util_dynarray_init(&cs->chunks, NULL);
   if (!radv_ps5_cs_alloc(cs, RADV_PS5_CS_INITIAL_DW)) {
      free(cs);
      return NULL;
   }
   return &cs->base;
}

static void
radv_ps5_cs_free_chunks(struct radv_ps5_cs *cs)
{
   util_dynarray_foreach (&cs->chunks, struct radv_ps5_cs_chunk, chunk)
      free(chunk->words);
   util_dynarray_clear(&cs->chunks);
   cs->words_in_chunks = 0;
}

static void
radv_ps5_cs_destroy(struct ac_cmdbuf *base)
{
   struct radv_ps5_cs *const cs = radv_ps5_cs(base);
   radv_ps5_cs_free_chunks(cs);
   util_dynarray_fini(&cs->chunks);
   free(cs->base.buf);
   free(cs);
}

static enum radeon_bo_domain
radv_ps5_cs_domain(const struct radeon_winsys *rws)
{
   (void)rws;
   return RADEON_DOMAIN_GTT;
}

static void
radv_ps5_cs_grow(struct ac_cmdbuf *base, size_t min_size)
{
   struct radv_ps5_cs *const cs = radv_ps5_cs(base);
   if (cs->status != VK_SUCCESS) {
      cs->base.cdw = 0;
      return;
   }
   /* The current chunk is finished as it stands: every packet RADV writes
    * checks for its space first, so none straddles two chunks. */
   const struct radv_ps5_cs_chunk done = {
      .words = cs->base.buf,
      .cdw = cs->base.cdw,
      .max_dw = cs->base.max_dw,
      .starts_submission = cs->buf_starts_submission,
   };
   const uint64_t wanted = MAX2((uint64_t)min_size + 16, (uint64_t)cs->base.max_dw * 2);
   const uint32_t max_dw = (uint32_t)MAX2(MIN2(wanted, RADV_PS5_CS_MAX_CHUNK_DW), (uint64_t)min_size + 16);
   struct radv_ps5_cs_chunk *const slot = util_dynarray_grow(&cs->chunks, struct radv_ps5_cs_chunk, 1);
   if (slot)
      *slot = done;
   if (!slot || !radv_ps5_cs_alloc(cs, max_dw)) {
      if (slot)
         (void)util_dynarray_pop(&cs->chunks, struct radv_ps5_cs_chunk);
      cs->base.buf = done.words;
      cs->base.max_dw = done.max_dw;
      cs->base.cdw = 0;
      cs->status = VK_ERROR_OUT_OF_HOST_MEMORY;
      return;
   }
   cs->words_in_chunks += done.cdw;
   cs->buf_starts_submission = false;
}

static void
radv_ps5_cs_emit_nops(struct radv_ps5_cs *cs, unsigned count)
{
   if (count == 0)
      return;
   if (count == 1) {
      cs->base.buf[cs->base.cdw++] = PKT3_NOP_PAD;
      return;
   }
   /* One NOP packet whose body fills the rest. */
   cs->base.buf[cs->base.cdw] = PKT3(PKT3_NOP, count - 2, 0);
   cs->base.cdw += count;
}

static void
radv_ps5_cs_pad(struct ac_cmdbuf *base, unsigned leave_dw_space)
{
   struct radv_ps5_cs *const cs = radv_ps5_cs(base);
   const uint32_t mask = cs->ws->info.ip[cs->ip_type].ib_pad_dw_mask;
   const uint32_t unaligned = (cs->base.cdw + leave_dw_space) & mask;
   if (unaligned)
      radv_ps5_cs_emit_nops(cs, mask + 1 - unaligned);
}

static VkResult
radv_ps5_cs_finalize(struct ac_cmdbuf *base)
{
   struct radv_ps5_cs *const cs = radv_ps5_cs(base);
   assert(cs->base.cdw <= cs->base.reserved_dw || cs->status != VK_SUCCESS);
   return cs->status;
}

static void
radv_ps5_cs_reset(struct ac_cmdbuf *base)
{
   struct radv_ps5_cs *const cs = radv_ps5_cs(base);
   radv_ps5_cs_free_chunks(cs);
   cs->base.cdw = 0;
   cs->base.reserved_dw = 0;
   cs->buf_starts_submission = false;
   cs->split_at = 0;
   cs->status = VK_SUCCESS;
}

static bool
radv_ps5_cs_chain(struct ac_cmdbuf *cs, struct ac_cmdbuf *next_cs, bool pre_ena)
{
   (void)cs;
   (void)next_cs;
   (void)pre_ena;
   return false;
}

static void
radv_ps5_cs_unchain(struct ac_cmdbuf *cs)
{
   (void)cs;
}

static void
radv_ps5_cs_add_buffer(struct ac_cmdbuf *cs, struct radeon_winsys_bo *bo)
{
   /* Every buffer is resident for as long as it lives. */
   (void)cs;
   (void)bo;
}

static uint32_t
radv_ps5_cs_words(const struct radv_ps5_cs *cs)
{
   return cs->words_in_chunks + cs->base.cdw;
}

/* Appends count words to a stream, growing it as needed. */
static void
radv_ps5_cs_append(struct radv_ps5_cs *cs, const uint32_t *words, uint32_t count)
{
   while (count && cs->status == VK_SUCCESS) {
      if (cs->base.cdw == cs->base.max_dw)
         radv_ps5_cs_grow(&cs->base, MIN2(count, RADV_PS5_CS_MAX_CHUNK_DW - 16));
      const uint32_t room = cs->base.max_dw - cs->base.cdw;
      const uint32_t n = MIN2(room, count);
      memcpy(cs->base.buf + cs->base.cdw, words, (size_t)n * sizeof(uint32_t));
      cs->base.cdw += n;
      cs->base.reserved_dw = MAX2(cs->base.reserved_dw, cs->base.cdw);
      words += n;
      count -= n;
   }
}

static bool
radv_ps5_cs_split_due(struct ac_cmdbuf *base)
{
   struct radv_ps5_cs *const cs = radv_ps5_cs(base);
   return cs->status == VK_SUCCESS && radv_ps5_cs_words(cs) - cs->split_at > RADV_PS5_SPLIT_DUE_DW;
}

/* The words from here on may start an AGC submission: the current chunk ends
 * and the next starts at the split. */
static void
radv_ps5_cs_split(struct ac_cmdbuf *base)
{
   struct radv_ps5_cs *const cs = radv_ps5_cs(base);
   if (cs->base.cdw)
      radv_ps5_cs_grow(&cs->base, 0);
   if (cs->status != VK_SUCCESS)
      return;
   cs->buf_starts_submission = true;
   cs->split_at = radv_ps5_cs_words(cs);
}

static void
radv_ps5_cs_execute_secondary(struct ac_cmdbuf *parent_base, struct ac_cmdbuf *child_base, bool allow_ib2)
{
   (void)allow_ib2;
   struct radv_ps5_cs *const parent = radv_ps5_cs(parent_base);
   struct radv_ps5_cs *const child = radv_ps5_cs(child_base);
   if (parent->status != VK_SUCCESS || child->status != VK_SUCCESS)
      return;
   /* Each of the child's chunks lands whole in one chunk of the parent, so
    * the parent's chunk boundaries stay packet boundaries, and the child's
    * splits become the parent's. */
   util_dynarray_foreach (&child->chunks, struct radv_ps5_cs_chunk, chunk) {
      if (chunk->starts_submission)
         radv_ps5_cs_split(&parent->base);
      if (parent->base.max_dw - parent->base.cdw < chunk->cdw)
         radv_ps5_cs_grow(&parent->base, chunk->cdw);
      radv_ps5_cs_append(parent, chunk->words, chunk->cdw);
   }
   if (child->buf_starts_submission)
      radv_ps5_cs_split(&parent->base);
   if (parent->base.max_dw - parent->base.cdw < child->base.cdw)
      radv_ps5_cs_grow(&parent->base, child->base.cdw);
   radv_ps5_cs_append(parent, child->base.buf, child->base.cdw);
}

static void
radv_ps5_cs_execute_ib(struct ac_cmdbuf *cs, struct radeon_winsys_bo *bo, const uint64_t va, const uint32_t cdw,
                       const bool predicate)
{
   (void)bo;
   (void)va;
   (void)cdw;
   (void)predicate;
   /* A GPU-generated command buffer runs as an INDIRECT_BUFFER, which the
    * console faults; the physical device does not report device-generated
    * commands (radeon_info.has_gpu_written_ibs). */
   fprintf(stderr, "radv/ps5: an indirect buffer was recorded; the console cannot run one\n");
   radv_ps5_cs(cs)->status = VK_ERROR_FEATURE_NOT_PRESENT;
}

static void
radv_ps5_cs_chain_dgc_ib(struct ac_cmdbuf *cs, uint64_t va, uint32_t cdw, uint64_t trailer_va, const bool predicate)
{
   (void)va;
   (void)trailer_va;
   radv_ps5_cs_execute_ib(cs, NULL, 0, cdw, predicate);
}

static void
radv_ps5_cs_dump(struct ac_cmdbuf *cs, FILE *file, const int *trace_ids, int trace_id_count,
                 enum radv_cs_dump_type type)
{
   (void)cs;
   (void)file;
   (void)trace_ids;
   (void)trace_id_count;
   (void)type;
}

static void
radv_ps5_cs_annotate(struct ac_cmdbuf *cs, const char *marker)
{
   (void)cs;
   (void)marker;
}

/* ------------------------------------------------------------- submission */

/* The completion packet: one RELEASE_MEM of CACHE_FLUSH_AND_INV_TS_EVENT
 * (event 20, index 5) that flushes the colour and depth caches, writes back and
 * invalidates L2 and the vector caches (the GCR actions 0x30c), and only then
 * writes the sequence number's low 32 bits -- the packet ps5vk ends every
 * submission with (PS5_Vulkan R90), and the one the amdgpu kernel's fences are. */
#define RADV_PS5_COMPLETION_WORDS 8
#define RADV_PS5_COMPLETION_EVENT 20u
#define RADV_PS5_COMPLETION_GCR 0x30cu

static void
radv_ps5_completion_words(uint32_t *words, uint64_t marker_address, uint32_t value)
{
   words[0] = PKT3(PKT3_RELEASE_MEM, 6, 0);
   words[1] = (RADV_PS5_COMPLETION_GCR << 12) | (5u << 8) | RADV_PS5_COMPLETION_EVENT;
   words[2] = 0x20000000u; /* DATA_SEL(1): the 32-bit value; DST_SEL(0): memory */
   words[3] = (uint32_t)marker_address;
   words[4] = (uint32_t)(marker_address >> 32);
   words[5] = value;
   words[6] = 0;
   words[7] = 0;
}

/* The GPU clock, as a timestamp query reads it: a RELEASE_MEM that writes the
 * 64-bit 100 MHz counter at the bottom of the pipe (HARDWARE_FINDINGS.md in
 * PS5_Vulkan, "A readable GPU clock"), submitted alone and waited for. It
 * lands after whatever the queue still runs, which the caller's CPU clock
 * readings around it (vkGetCalibratedTimestampsKHR's deviation) include. The
 * packet and its value live in the marker's page, past the marker. */
#define RADV_PS5_CLOCK_WORDS_OFFSET 1024
#define RADV_PS5_CLOCK_VALUE_OFFSET 2048

uint64_t
radv_ps5_read_gpu_clock(void)
{
   /* The model runs no GPU: its clock is the host's, at the same rate. */
   if (!radv_ps5_platform_runs_gpu())
      return (uint64_t)os_time_get_nano() / 10;
   struct radv_ps5_queue *const queue = radv_ps5_queue_get();
   if (!queue)
      return 0;
   uint8_t *const page = (uint8_t *)queue->marker_memory.cpu;
   uint32_t *const words = (uint32_t *)(page + RADV_PS5_CLOCK_WORDS_OFFSET);
   volatile uint64_t *const value = (volatile uint64_t *)(page + RADV_PS5_CLOCK_VALUE_OFFSET);
   const uint64_t va = (uint64_t)(uintptr_t)value;

   simple_mtx_lock(&queue->submit_lock);
   *value = UINT64_MAX;
   radv_ps5_cpu_flush((const void *)value, sizeof(*value));
   words[0] = PKT3(PKT3_RELEASE_MEM, 6, 0);
   words[1] = EVENT_TYPE(V_028A90_BOTTOM_OF_PIPE_TS) | EVENT_INDEX(5);
   words[2] = EOP_DATA_SEL(EOP_DATA_SEL_TIMESTAMP);
   words[3] = (uint32_t)va;
   words[4] = (uint32_t)(va >> 32);
   words[5] = 0;
   words[6] = 0;
   words[7] = 0;
   uint64_t clock = 0;
   if (radv_ps5_submit(words, 8, NULL, 0) == 0) {
      const int64_t deadline = os_time_get_nano() + INT64_C(1000000000);
      do {
         radv_ps5_cpu_flush((const void *)value, sizeof(*value));
         clock = *value;
      } while (clock == UINT64_MAX && os_time_get_nano() < deadline);
      if (clock == UINT64_MAX)
         clock = 0;
   }
   simple_mtx_unlock(&queue->submit_lock);
   return clock;
}

/* Forgets the ring records the GPU has finished with. Called with the submit
 * lock held. */
static void
radv_ps5_queue_retire(struct radv_ps5_queue *queue)
{
   const uint64_t completed = radv_ps5_queue_poll(queue);
   while (queue->in_flight_count) {
      struct radv_ps5_in_flight *const oldest = &queue->in_flight[queue->in_flight_first];
      if (oldest->seq > completed)
         break;
      radv_ps5_memory_free(&oldest->dedicated);
      queue->in_flight_first = (queue->in_flight_first + 1) % RADV_PS5_MAX_IN_FLIGHT;
      queue->in_flight_count--;
   }
}

/* Words for a submission of count words: a ring range the GPU no longer reads,
 * or a buffer of its own for one too large for the ring. Called with the submit
 * lock held; records the claim for seq. */
static uint32_t *
radv_ps5_queue_claim(struct radv_ps5_queue *queue, uint32_t count, uint64_t seq)
{
   radv_ps5_queue_retire(queue);
   while (queue->in_flight_count == RADV_PS5_MAX_IN_FLIGHT) {
      const uint64_t oldest = queue->in_flight[queue->in_flight_first].seq;
      if (!radv_ps5_queue_wait_seq(queue, oldest, OS_TIMEOUT_INFINITE))
         return NULL;
      radv_ps5_queue_retire(queue);
   }
   struct radv_ps5_in_flight *const claim =
      &queue->in_flight[(queue->in_flight_first + queue->in_flight_count) % RADV_PS5_MAX_IN_FLIGHT];
   *claim = (struct radv_ps5_in_flight){.seq = seq, .dedicated = {.physical = -1}};

   if (count > RADV_PS5_RING_WORDS / 2) {
      if (!radv_ps5_memory_alloc((uint64_t)count * 4, RADV_PS5_LARGE_BYTES, true, &claim->dedicated))
         return NULL;
      queue->in_flight_count++;
      return (uint32_t *)claim->dedicated.cpu;
   }

   /* Streams start on a 64-byte line and follow one another round the ring. */
   uint32_t start = align(queue->ring_head, 16);
   if (start + count > RADV_PS5_RING_WORDS)
      start = 0;
   const uint32_t end = start + count;
   /* Wait for every earlier stream still in the range to be run. */
   for (uint32_t i = 0; i < queue->in_flight_count; i++) {
      const struct radv_ps5_in_flight *const record =
         &queue->in_flight[(queue->in_flight_first + i) % RADV_PS5_MAX_IN_FLIGHT];
      if (record->dedicated.cpu || record->end <= start || end <= record->start)
         continue;
      if (!radv_ps5_queue_wait_seq(queue, record->seq, OS_TIMEOUT_INFINITE))
         return NULL;
   }
   radv_ps5_queue_retire(queue);
   claim->start = start;
   claim->end = end;
   /* The claim is recorded after the retire, which may have moved the first
    * record; rebuild it in place at the end of the list. */
   struct radv_ps5_in_flight *const slot =
      &queue->in_flight[(queue->in_flight_first + queue->in_flight_count) % RADV_PS5_MAX_IN_FLIGHT];
   *slot = (struct radv_ps5_in_flight){.seq = seq, .start = start, .end = end, .dedicated = {.physical = -1}};
   queue->in_flight_count++;
   queue->ring_head = end;
   return (uint32_t *)queue->ring.cpu + start;
}

/* A run of a submission's words that must go to the GPU in one AGC submission:
 * from a place the GPU state is the preamble's (a stream's start or a split)
 * to the next such place. */
struct radv_ps5_unit {
   unsigned first_piece;
   uint32_t words;
   /* The unit starts an AGC submission after the first. */
   bool starts_part;
};

/* The words of a stream in submission order, as chunks (the current one last). */
static void
radv_ps5_stream_pieces(const struct radv_ps5_cs *cs, struct util_dynarray *pieces)
{
   util_dynarray_foreach (&cs->chunks, struct radv_ps5_cs_chunk, chunk) {
      if (chunk->cdw)
         util_dynarray_append(pieces, *chunk);
      else if (chunk->starts_submission)
         util_dynarray_append(pieces, ((struct radv_ps5_cs_chunk){.starts_submission = true}));
   }
   util_dynarray_append(pieces, ((struct radv_ps5_cs_chunk){
                                   .words = cs->base.buf,
                                   .cdw = cs->base.cdw,
                                   .max_dw = cs->base.max_dw,
                                   .starts_submission = cs->buf_starts_submission,
                                }));
}

static uint32_t
radv_ps5_count_streams(struct ac_cmdbuf **streams, unsigned count)
{
   uint32_t words = 0;
   for (unsigned i = 0; i < count; i++)
      words += radv_ps5_cs_words(radv_ps5_cs(streams[i]));
   return words;
}

static uint32_t *
radv_ps5_copy_streams(uint32_t *at, struct ac_cmdbuf **streams, unsigned count)
{
   for (unsigned i = 0; i < count; i++) {
      const struct radv_ps5_cs *const cs = radv_ps5_cs(streams[i]);
      util_dynarray_foreach (&cs->chunks, struct radv_ps5_cs_chunk, chunk) {
         memcpy(at, chunk->words, (size_t)chunk->cdw * sizeof(uint32_t));
         at += chunk->cdw;
      }
      memcpy(at, cs->base.buf, (size_t)cs->base.cdw * sizeof(uint32_t));
      at += cs->base.cdw;
   }
   return at;
}

/* Where the submissions' time goes: a line on stderr every 10 s of a queue
 * that submits (held with the submit lock). */
static struct {
   uint64_t window_start, count, words, claim_ns, copy_ns;
} radv_ps5_submit_window;

static void
radv_ps5_note_submission(uint32_t words, uint64_t claim_ns, uint64_t copy_ns)
{
   const uint64_t now = os_time_get_nano();
   if (!radv_ps5_submit_window.window_start)
      radv_ps5_submit_window.window_start = now;
   radv_ps5_submit_window.count++;
   radv_ps5_submit_window.words += words;
   radv_ps5_submit_window.claim_ns += claim_ns;
   radv_ps5_submit_window.copy_ns += copy_ns;
   if (now - radv_ps5_submit_window.window_start < 10ull * 1000 * 1000 * 1000)
      return;
   uint64_t times[3];
   radv_ps5_submit_times(times);
   fprintf(stderr,
           "radv/ps5 submissions: window count=%" PRIu64 " kwords=%" PRIu64 " claim_ms=%.1f copy_ms=%.1f flush_ms=%.1f"
           " agc_ms=%.1f suspend_ms=%.1f\n",
           radv_ps5_submit_window.count, radv_ps5_submit_window.words / 1024, radv_ps5_submit_window.claim_ns / 1e6,
           radv_ps5_submit_window.copy_ns / 1e6, times[0] / 1e6, times[1] / 1e6, times[2] / 1e6);
   memset(&radv_ps5_submit_window, 0, sizeof(radv_ps5_submit_window));
   radv_ps5_submit_window.window_start = now;
}

static VkResult
radv_ps5_cs_submit(struct radeon_winsys_ctx *rctx, const struct radv_winsys_submit_info *submit, uint32_t wait_count,
                   const struct vk_sync_wait *waits, uint32_t signal_count, const struct vk_sync_signal *signals)
{
   struct radv_ps5_ctx *const ctx = (struct radv_ps5_ctx *)rctx;
   struct radv_ps5_queue *const queue = ctx->ws->queue;

   if (submit->ip_type != AMD_IP_GFX)
      return VK_ERROR_FEATURE_NOT_PRESENT;
   for (unsigned i = 0; i < submit->cs_count; i++) {
      if (radv_ps5_cs(submit->cs_array[i])->status != VK_SUCCESS)
         return radv_ps5_cs(submit->cs_array[i])->status;
   }

   /* Waits need only their signals submitted: this queue runs in order. */
   uint64_t depends = 0;
   VkResult result = radv_ps5_sync_wait_submitted(wait_count, waits, &depends);
   if (result != VK_SUCCESS)
      return result;

   simple_mtx_lock(&queue->submit_lock);
   /* AGC owns the tessellation factor ring's registers: the ring is handed to
    * it, after the GPU has finished with the one it held. */
   if (ctx->tess_factor_ring_va && (ctx->tess_factor_ring_va != queue->tess_factor_ring_va ||
                                    ctx->tess_factor_ring_size != queue->tess_factor_ring_size)) {
      radv_ps5_queue_wait_seq(queue, queue->submitted_seq, OS_TIMEOUT_INFINITE);
      const int set = radv_ps5_set_tess_factor_ring(ctx->tess_factor_ring_va, ctx->tess_factor_ring_size);
      if (set != 0)
         fprintf(stderr, "radv/ps5: sceAgcDriverSetTFRing(0x%llx, %u) failed: 0x%08x\n",
                 (unsigned long long)ctx->tess_factor_ring_va, ctx->tess_factor_ring_size, (unsigned)set);
      queue->tess_factor_ring_va = ctx->tess_factor_ring_va;
      queue->tess_factor_ring_size = ctx->tess_factor_ring_size;
   }
   /* The off-chip ring RADV allocated holds as many workgroups as its
    * OFFCHIP_BUFFERING names; AGC starts with its own. */
   if (ctx->tess_factor_ring_va && !queue->hs_offchip_param_set) {
      const uint32_t param = ctx->ws->info.hs_offchip_param;
      const int set = radv_ps5_set_hs_offchip_param(G_03093C_OFFCHIP_GRANULARITY_GFX103(param),
                                                    G_03093C_OFFCHIP_BUFFERING_GFX103(param));
      if (set != 0)
         fprintf(stderr, "radv/ps5: sceAgcDriverSetHsOffchipParam failed: 0x%08x\n", (unsigned)set);
      queue->hs_offchip_param_set = true;
   }
   if (submit->cs_count == 0) {
      /* Nothing for the GPU: the signals follow what was submitted before. */
      const uint64_t last = queue->submitted_seq;
      simple_mtx_unlock(&queue->submit_lock);
      radv_ps5_sync_signal_seq(signal_count, signals, MAX2(last, depends));
      return VK_SUCCESS;
   }

   /* The initial preambles (every submission starts from the state they set,
    * as each amdgpu submission does), the streams, the postambles, then the
    * completion. The streams and postambles are cut into units; units go
    * into one AGC submission as long as they fit, and each further AGC
    * submission starts with the preambles again. */
   const uint32_t preamble_words = radv_ps5_count_streams(submit->initial_preamble_cs, submit->initial_preamble_count);
   struct util_dynarray pieces, units;
   util_dynarray_init(&pieces, NULL);
   util_dynarray_init(&units, NULL);
   for (unsigned i = 0; i < submit->cs_count + submit->postamble_count; i++) {
      struct ac_cmdbuf *const stream =
         i < submit->cs_count ? submit->cs_array[i] : submit->postamble_cs[i - submit->cs_count];
      const unsigned first = util_dynarray_num_elements(&pieces, struct radv_ps5_cs_chunk);
      radv_ps5_stream_pieces(radv_ps5_cs(stream), &pieces);
      const unsigned end = util_dynarray_num_elements(&pieces, struct radv_ps5_cs_chunk);
      for (unsigned p = first; p < end; p++) {
         struct radv_ps5_cs_chunk *const piece = util_dynarray_element(&pieces, struct radv_ps5_cs_chunk, p);
         if (p == first || piece->starts_submission)
            util_dynarray_append(&units, ((struct radv_ps5_unit){.first_piece = p}));
         util_dynarray_last_ptr(&units, struct radv_ps5_unit)->words += piece->cdw;
      }
   }

   /* Plan: which unit starts each AGC submission, and the words in all. */
   const unsigned unit_count = util_dynarray_num_elements(&units, struct radv_ps5_unit);
   const uint32_t room = RADV_PS5_SUBMIT_MAX_DW - RADV_PS5_COMPLETION_WORDS;
   uint32_t count = preamble_words + RADV_PS5_COMPLETION_WORDS;
   uint32_t fill = preamble_words;
   bool too_large = false;
   for (unsigned u = 0; u < unit_count; u++) {
      struct radv_ps5_unit *const unit = util_dynarray_element(&units, struct radv_ps5_unit, u);
      if (preamble_words + unit->words > room)
         too_large = true;
      if (fill > preamble_words && fill + unit->words > room) {
         unit->starts_part = true;
         count += preamble_words;
         fill = preamble_words;
      }
      fill += unit->words;
      count += unit->words;
   }

   const uint64_t seq = queue->submitted_seq + 1;
   const uint64_t claim_start = os_time_get_nano();
   uint32_t *const words = too_large ? NULL : radv_ps5_queue_claim(queue, count, seq);
   const uint64_t copy_start = os_time_get_nano();
   if (!words) {
      simple_mtx_unlock(&queue->submit_lock);
      util_dynarray_fini(&pieces);
      util_dynarray_fini(&units);
      if (too_large)
         fprintf(stderr, "radv/ps5: a submission holds more words between two splits than one AGC submission can\n");
      return VK_ERROR_DEVICE_LOST;
   }

   struct util_dynarray starts;
   util_dynarray_init(&starts, NULL);
   util_dynarray_append(&starts, 0u);
   uint32_t *at = radv_ps5_copy_streams(words, submit->initial_preamble_cs, submit->initial_preamble_count);
   for (unsigned u = 0; u < unit_count; u++) {
      const struct radv_ps5_unit *const unit = util_dynarray_element(&units, struct radv_ps5_unit, u);
      if (unit->starts_part) {
         util_dynarray_append(&starts, (uint32_t)(at - words));
         at = radv_ps5_copy_streams(at, submit->initial_preamble_cs, submit->initial_preamble_count);
      }
      const unsigned end = u + 1 < unit_count ? util_dynarray_element(&units, struct radv_ps5_unit, u + 1)->first_piece
                                              : util_dynarray_num_elements(&pieces, struct radv_ps5_cs_chunk);
      for (unsigned p = unit->first_piece; p < end; p++) {
         const struct radv_ps5_cs_chunk *const piece = util_dynarray_element(&pieces, struct radv_ps5_cs_chunk, p);
         memcpy(at, piece->words, (size_t)piece->cdw * sizeof(uint32_t));
         at += piece->cdw;
      }
   }
   radv_ps5_completion_words(at, (uint64_t)(uintptr_t)queue->marker, (uint32_t)seq);
   at += RADV_PS5_COMPLETION_WORDS;
   assert((uint32_t)(at - words) == count);
   util_dynarray_fini(&pieces);
   util_dynarray_fini(&units);

   const uint64_t copy_end = os_time_get_nano();
   p_atomic_set(&queue->submitted_seq, seq);
   int submitted = 0;
   const unsigned parts = util_dynarray_num_elements(&starts, uint32_t);
   for (unsigned i = 0; i < parts && submitted == 0; i++) {
      const uint32_t start = *util_dynarray_element(&starts, uint32_t, i);
      const uint32_t end = i + 1 < parts ? *util_dynarray_element(&starts, uint32_t, i + 1) : count;
      submitted = radv_ps5_submit(words + start, end - start, queue->marker, (uint32_t)seq);
   }
   util_dynarray_fini(&starts);
   radv_ps5_note_submission(count, copy_start - claim_start, copy_end - copy_start);
   simple_mtx_unlock(&queue->submit_lock);
   if (submitted != 0) {
      fprintf(stderr, "radv/ps5: sceAgcDriverSubmitDcb failed: 0x%08x\n", (unsigned)submitted);
      return VK_ERROR_DEVICE_LOST;
   }
   ctx->queue_used[submit->ip_type][submit->queue_index] = true;
   radv_ps5_sync_signal_seq(signal_count, signals, seq);
   return VK_SUCCESS;
}

void
radv_ps5_cs_init_functions(struct radv_ps5_winsys *ws)
{
   ws->base.cs_domain = radv_ps5_cs_domain;
   ws->base.cs_create = radv_ps5_cs_create;
   ws->base.cs_destroy = radv_ps5_cs_destroy;
   ws->base.cs_grow = radv_ps5_cs_grow;
   ws->base.cs_finalize = radv_ps5_cs_finalize;
   ws->base.cs_reset = radv_ps5_cs_reset;
   ws->base.cs_chain = radv_ps5_cs_chain;
   ws->base.cs_unchain = radv_ps5_cs_unchain;
   ws->base.cs_add_buffer = radv_ps5_cs_add_buffer;
   ws->base.cs_execute_secondary = radv_ps5_cs_execute_secondary;
   ws->base.cs_execute_ib = radv_ps5_cs_execute_ib;
   ws->base.cs_chain_dgc_ib = radv_ps5_cs_chain_dgc_ib;
   ws->base.cs_submit = radv_ps5_cs_submit;
   ws->base.cs_dump = radv_ps5_cs_dump;
   ws->base.cs_annotate = radv_ps5_cs_annotate;
   ws->base.cs_pad = radv_ps5_cs_pad;
   ws->base.cs_split_due = radv_ps5_cs_split_due;
   ws->base.cs_split = radv_ps5_cs_split;
}
