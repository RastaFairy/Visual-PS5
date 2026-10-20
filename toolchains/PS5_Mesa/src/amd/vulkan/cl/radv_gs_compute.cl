/*
 * Copyright © 2026 Mihawk
 *
 * SPDX-License-Identifier: MIT
 */

/* RADV's OpenCL helpers for geometry shaders run as compute, turned into NIR
 * builder functions by vtn_bindgen2 as poly's are (radv_gs_compute_abi.h). */

/* poly's allocations that do not fit go to the guard past the heap's end
 * (RADV_GS_COMPUTE_HEAP_GUARD) instead of aborting, which RADV's shaders
 * cannot. */
#define POLY_HEAP_GUARD 1

#include "compiler/libcl/libcl.h"
#include "poly/cl/tessellator.h"
#include "poly/geometry.h"
#include "poly/prim.h"
#include "radv_gs_compute_abi.h"

/* A bump allocation from the command buffer's heap, or false when it does
 * not fit: the draw then draws nothing rather than write out of bounds. A
 * failed allocation leaves heap->bottom past heap->size, as poly's do. */
static bool
heap_alloc(global struct poly_heap *heap, uint64_t size_B, uint *offs_B)
{
   if (size_B > heap->size) {
      atomic_fetch_max((volatile atomic_uint *)(&heap->bottom), heap->size + 16);
      return false;
   }

   uint offs = poly_heap_alloc_offs(heap, (uint)size_B);
   if (offs == heap->size)
      return false;

   *offs_B = offs;
   return true;
}

/* Whether an allocation of this draw's or an earlier one's did not fit. */
static bool
heap_overflowed(global struct poly_heap *heap)
{
   return heap->bottom > heap->size;
}

void
radv_gs_compute_setup(global struct radv_gs_compute_setup *s)
{
   global uint32_t *draw = s->draw;
   global struct radv_gs_compute_draw *block = s->block;
   global struct poly_vertex_params *vp = block->vertex_params;
   global struct poly_geometry_params *p = block->geometry_params;
   global struct poly_heap *heap = s->heap;
   const bool indexed = s->index_size_B != 0;
   const enum poly_gs_shape shape = s->shape;

   uint vertex_count = draw[0];
   uint instance_count = draw[1];
   if (s->byte_count) {
      uint counter = *s->byte_count;
      vertex_count = counter > s->byte_offset ? (counter - s->byte_offset) / s->byte_stride : 0;
   }
   if (s->draw_count && s->draw_index >= *s->draw_count)
      vertex_count = 0;

   block->first_vertex = indexed ? draw[3] : draw[2];
   block->base_instance = indexed ? draw[4] : draw[3];

   /* Every size in 64 bits: a draw too large for 32-bit counts or for the
    * heap draws nothing. */
   uint64_t prims =
      vertex_count <= INT32_MAX ? u_decomposed_prims_for_vertices(s->prim, vertex_count) : 0;
   uint64_t input_prims = prims * instance_count;
   uint64_t vs_B = (uint64_t)vertex_count * instance_count * util_bitcount64(s->vs_outputs) * 16;
   uint64_t count_B = input_prims * p->count_buffer_stride;
   uint64_t index_B = shape == POLY_GS_SHAPE_DYNAMIC_INDEXED ? input_prims * s->max_indices * 4 : 0;

   /* After tessellation, the domain points went to the guard if the heap
    * overflowed: nothing reads them. */
   uint vs_offs = 0, count_offs = 0, index_offs = 0;
   bool ok = !heap_overflowed(heap) && vertex_count && instance_count && vertex_count <= INT32_MAX &&
             input_prims * max(s->max_indices, 1u) <= UINT32_MAX && heap_alloc(heap, vs_B, &vs_offs) &&
             (!count_B || heap_alloc(heap, count_B, &count_offs)) &&
             (!index_B || heap_alloc(heap, index_B, &index_offs));
   if (!ok) {
      vertex_count = 0;
      instance_count = 0;
   }

   poly_vertex_params_set_draw(vp, vertex_count, instance_count);
   poly_geometry_params_set_draw(p, s->prim, shape, s->max_indices, vertex_count, instance_count);

   if (ok) {
      vp->output_buffer = (uintptr_t)(heap->base + vs_offs);
      if (indexed) {
         vp->index_size_B = s->index_size_B;
         vp->index_buffer = draw[2] < s->index_buffer_range_el
                               ? s->index_buffer + (uint64_t)draw[2] * s->index_size_B
                               : block->ro_sink;
         vp->index_buffer_range_el = poly_index_buffer_range_el(s->index_buffer_range_el, draw[2]);
      }
      if (count_B)
         p->count_buffer = (global uint *)(heap->base + count_offs);
      if (index_B) {
         p->output_index_buffer = (global uint *)(heap->base + index_offs);
         p->draw.first_index = index_offs / 4;
      }
   }

   s->vs_groups[0] = (vertex_count + RADV_GS_COMPUTE_WAVE - 1) / RADV_GS_COMPUTE_WAVE;
   s->vs_groups[1] = instance_count;
   s->vs_groups[2] = 1;
   s->gs_groups[0] = (p->grid[0] + RADV_GS_COMPUTE_WAVE - 1) / RADV_GS_COMPUTE_WAVE;
   s->gs_groups[1] = p->grid[1];
   s->gs_groups[2] = 1;
}

/* The first invocation of the workgroup where cond holds, or the workgroup
 * size: the workgroup is one wave, so one ballot sees all of it. */
static uint
first_true(bool cond)
{
   uint4 ballot = sub_group_ballot(cond);
   if (ballot.x)
      return ctz(ballot.x);
   if (ballot.y)
      return 32 + ctz(ballot.y);
   return RADV_GS_COMPUTE_WAVE;
}

/* poly_unroll_geometry (poly/cl/restart.h) for one wave, allocating from the
 * heap without aborting. */
void
radv_gs_compute_unroll(global struct radv_gs_compute_unroll *u)
{
   global uint32_t *in_draw = u->draw;
   global uint32_t *out_draw = u->out_draw;
   global struct poly_heap *heap = u->heap;
   const uint tid = cl_local_id.x;
   const enum mesa_prim mode = u->prim;
   const uint per_prim = mesa_vertices_per_prim(mode);
   const uint size_B = u->index_size_B;

   uint count = in_draw[0];
   if (u->draw_count && u->draw_index >= *u->draw_count)
      count = 0;

   /* Restarts only shorten the output: its bound is the input without any. */
   uint64_t max_prims = count <= INT32_MAX ? u_decomposed_prims_for_vertices(mode, count) : 0;
   uint offs = 0;
   uint ok = 0;
   if (tid == 0)
      ok = count && heap_alloc(heap, max_prims * per_prim * size_B, &offs);
   ok = sub_group_broadcast(ok, 0);
   offs = sub_group_broadcast(offs, 0);

   if (tid == 0) {
      out_draw[0] = 0;
      out_draw[1] = in_draw[1];
      out_draw[2] = offs / size_B;
      out_draw[3] = in_draw[3];
      out_draw[4] = in_draw[4];
   }
   if (!ok)
      return;

   uint64_t in_ptr = in_draw[2] < u->index_buffer_range_el
                        ? u->index_buffer + (uint64_t)in_draw[2] * size_B
                        : u->ro_sink;
   uint in_range_el = poly_index_buffer_range_el(u->index_buffer_range_el, in_draw[2]);
   uint64_t out_ptr = (uintptr_t)(heap->base + offs);

   uint out_prims = 0;
   uint needle = 0;
   while (needle < count) {
      /* The next restart or the end; lanes load in parallel. */
      uint next_restart = needle;
      for (;;) {
         uint idx = next_restart + tid;
         bool restart = idx >= count || poly_load_index(in_ptr, in_range_el, idx, size_B) == u->restart_index;

         uint next_offs = first_true(restart);
         next_restart += next_offs;
         if (next_offs < RADV_GS_COMPUTE_WAVE)
            break;
      }

      /* Up to it, decomposed; lanes store in parallel. */
      uint subcount = next_restart - needle;
      uint subprims = u_decomposed_prims_for_vertices(mode, subcount);
      for (uint i = tid; i < subprims; i += RADV_GS_COMPUTE_WAVE) {
         for (uint vtx = 0; vtx < per_prim; ++vtx) {
            uint id = poly_vertex_id_for_topology(mode, u->flatshade_first, i, vtx, subprims);
            uint x = ((out_prims + i) * per_prim) + vtx;
            uint y = poly_load_index(in_ptr, in_range_el, needle + id, size_B);

            poly_store_index(out_ptr, size_B, x, y);
         }
      }

      out_prims += subprims;
      needle = next_restart + 1;
   }

   if (tid == 0)
      out_draw[0] = out_prims * per_prim;
}

/* The inclusive prefix sum of one word of the count buffer across the draw's
 * input primitives, for their places in the transform feedback buffers: one
 * workgroup of one wave per word. */
void
radv_gs_compute_prefix_sum(global struct poly_geometry_params *p)
{
   const uint word = cl_group_id.x;
   const uint words = p->count_buffer_stride / 4;
   const uint len = p->input_primitives;
   global uint *counts = p->count_buffer;

   uint carry = 0;
   for (uint base = 0; base < len; base += RADV_GS_COMPUTE_WAVE) {
      const uint i = base + cl_local_id.x;
      const uint x = i < len ? counts[i * words + word] : 0;
      const uint sum = sub_group_scan_inclusive_add(x) + carry;
      if (i < len)
         counts[i * words + word] = sum;
      carry = sub_group_broadcast(sum, RADV_GS_COMPUTE_WAVE - 1);
   }
}

/* Tessellation: the vertex shader, the tessellation control shader and
 * poly's tessellator run as compute, and the tessellation evaluation shader
 * runs as the vertex stage of the geometry shader's passes over the
 * tessellator's output (radv_gs_compute.h). */
void
radv_gs_compute_tess_setup(global struct radv_gs_compute_tess_setup *s)
{
   global uint32_t *draw = s->draw;
   global struct radv_gs_compute_draw *block = s->block;
   global struct poly_vertex_params *vp = block->vertex_params;
   global struct poly_tess_params *p = block->tess_params;
   global struct poly_heap *heap = s->heap;
   const bool indexed = s->index_size_B != 0;

   uint count = draw[0];
   uint instance_count = draw[1];
   if (s->byte_count) {
      uint counter = *s->byte_count;
      count = counter > s->byte_offset ? (counter - s->byte_offset) / s->byte_stride : 0;
   }
   if (s->draw_count && s->draw_index >= *s->draw_count)
      count = 0;

   block->first_vertex = indexed ? draw[3] : draw[2];
   block->base_instance = indexed ? draw[4] : draw[3];

   /* Only whole patches are drawn, and only their vertices shaded. */
   uint in_patches = count / p->input_patch_size;
   uint vertices = in_patches * p->input_patch_size;
   uint64_t patches = (uint64_t)in_patches * instance_count;
   uint64_t vs_B = (uint64_t)vertices * instance_count * util_bitcount64(vp->outputs) * 16;
   uint64_t tcs_B = patches * p->tcs_stride_el * 4;

   uint vs_offs = 0, tcs_offs = 0, coord_offs = 0, count_offs = 0;
   bool ok = in_patches && instance_count && patches <= UINT32_MAX / 4 && heap_alloc(heap, vs_B, &vs_offs) &&
             heap_alloc(heap, tcs_B, &tcs_offs) && heap_alloc(heap, patches * 4, &coord_offs) &&
             heap_alloc(heap, patches * 4, &count_offs);
   if (!ok) {
      in_patches = 0;
      vertices = 0;
      instance_count = 0;
      patches = 0;
   }

   poly_vertex_params_set_draw(vp, vertices, instance_count);
   p->patches_per_instance = in_patches;
   p->nr_patches = patches;
   if (ok) {
      vp->output_buffer = (uintptr_t)(heap->base + vs_offs);
      if (indexed) {
         vp->index_size_B = s->index_size_B;
         vp->index_buffer = draw[2] < s->index_buffer_range_el
                               ? s->index_buffer + (uint64_t)draw[2] * s->index_size_B
                               : block->ro_sink;
         vp->index_buffer_range_el = poly_index_buffer_range_el(s->index_buffer_range_el, draw[2]);
      }
      p->tcs_buffer = (global float *)(heap->base + tcs_offs);
      p->coord_allocs = (global uint *)(heap->base + coord_offs);
      p->counts = (global uint *)(heap->base + count_offs);
   }

   s->vs_groups[0] = (vertices + RADV_GS_COMPUTE_WAVE - 1) / RADV_GS_COMPUTE_WAVE;
   s->vs_groups[1] = instance_count;
   s->vs_groups[2] = 1;
   s->tcs_groups[0] = in_patches;
   s->tcs_groups[1] = instance_count;
   s->tcs_groups[2] = 1;
   s->tess_groups[0] = ((uint)patches + RADV_GS_COMPUTE_WAVE - 1) / RADV_GS_COMPUTE_WAVE;
   s->tess_groups[1] = 1;
   s->tess_groups[2] = 1;
}

/* One tessellator pass over the draw's patches, one invocation each, in the
 * mode enum poly_tess_mode names. */
void
radv_gs_compute_tess_isolines(constant struct poly_tess_params *p, uint mode)
{
   uint patch = cl_global_id.x;
   if (patch < p->nr_patches)
      poly_tess_isoline_process(p, patch, mode);
}

void
radv_gs_compute_tess_triangles(constant struct poly_tess_params *p, uint mode)
{
   uint patch = cl_global_id.x;
   if (patch < p->nr_patches)
      poly_tess_tri_process(p, patch, mode);
}

void
radv_gs_compute_tess_quads(constant struct poly_tess_params *p, uint mode)
{
   uint patch = cl_global_id.x;
   if (patch < p->nr_patches)
      poly_tess_quad_process(p, patch, mode);
}

/* The inclusive prefix sum of the patches' index counts (one workgroup of one
 * wave), then the index buffer they take and the draw of the tessellator's
 * output: a VkDrawIndirectCommand of that many vertices, which the
 * evaluation shader reads through the index buffer (poly_load_tes_index).
 * When the index buffer does not fit, no patch is tessellated and nothing is
 * drawn. */
void
radv_gs_compute_tess_prefix_sum(global struct poly_tess_params *p)
{
   const uint len = p->nr_patches;
   global uint *counts = p->counts;

   uint carry = 0;
   for (uint base = 0; base < len; base += RADV_GS_COMPUTE_WAVE) {
      const uint i = base + cl_local_id.x;
      const uint x = i < len ? counts[i] : 0;
      const uint sum = sub_group_scan_inclusive_add(x) + carry;
      if (i < len)
         counts[i] = sum;
      carry = sub_group_broadcast(sum, RADV_GS_COMPUTE_WAVE - 1);
   }

   if (cl_local_id.x != 0)
      return;

   uint total = carry;
   uint offs = 0;
   if (len && heap_alloc(p->heap, (uint64_t)total * 4, &offs)) {
      p->index_buffer = (global uint32_t *)(p->heap->base + offs);
   } else {
      total = 0;
      p->nr_patches = 0;
   }

   global uint32_t *draw = p->out_draws;
   draw[0] = total;
   draw[1] = 1;
   draw[2] = 0;
   draw[3] = 0;
}

/* After tessellation, a geometry shader's primitive ID counts the primitives
 * presented to it since its instance started, as Vulkan resets it per
 * instance, where the draw of the tessellator's output holds every
 * instance's primitives in one: the instance's first primitive comes off.
 * Instances' patches are consecutive and counts[] holds the inclusive prefix
 * sum of their indices. */
uint
radv_gs_compute_tess_primitive_id(constant struct poly_tess_params *p, uint raw, uint vertices_per_prim)
{
   const uint per_instance = p->patches_per_instance;
   if (per_instance == 0 || p->nr_patches <= per_instance)
      return raw;

   /* The last instance whose first index is at most this primitive's. */
   const uint index = raw * vertices_per_prim;
   uint lo = 0, hi = p->nr_patches / per_instance - 1;
   while (lo < hi) {
      const uint mid = (lo + hi + 1) / 2;
      if (p->counts[mid * per_instance - 1] <= index)
         lo = mid;
      else
         hi = mid - 1;
   }
   const uint first = lo ? p->counts[lo * per_instance - 1] : 0;
   return raw - first / vertices_per_prim;
}
