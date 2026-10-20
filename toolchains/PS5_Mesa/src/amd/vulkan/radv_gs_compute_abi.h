/*
 * Copyright © 2026 Mihawk
 *
 * SPDX-License-Identifier: MIT
 */

/* What the driver and its OpenCL functions for geometry shaders run as
 * compute share (radv_gs_compute.h, cl/radv_gs_compute.cl). */

#pragma once

#include "compiler/libcl/libcl.h"
#include "poly/geometry.h"
#include "poly/tessellator.h"

/* The per-draw block every such shader reads through a user SGPR. With
 * tessellation a draw has two: the vertex shader's and the tessellation
 * control shader's, whose vertex parameters describe the vertex shader's
 * outputs, and the tessellation evaluation shader's and the geometry
 * shader's, whose vertex parameters describe the evaluation shader's. */
struct radv_gs_compute_draw {
   DEVICE(struct poly_vertex_params) vertex_params;
   DEVICE(struct poly_geometry_params) geometry_params;
   DEVICE(struct poly_tess_params) tess_params;
   uint64_t ro_sink;        /* where writes that must go nowhere go */
   uint64_t flat_mask;      /* the fragment shader's flat inputs */
   uint32_t input_topology; /* enum mesa_prim of the draw */
   uint32_t provoking_last;
   uint32_t first_vertex;
   uint32_t base_instance;
   uint32_t draw_id;
   uint32_t rasterization_stream;
   uint32_t view_index; /* with multiview, the view this draw's passes run for */
} PACKED;
static_assert(sizeof(struct radv_gs_compute_draw) == 17 * 4, "struct radv_gs_compute_draw must be 17 words");

/* A draw whose counts live in memory (indirect, byte count, or unrolled for
 * primitive restart) is set up by one invocation of radv_gs_compute_setup:
 * it sizes the passes, allocates their buffers from the command buffer's
 * heap and writes the workgroup counts of the dispatches that follow. When
 * the heap is full the draw draws nothing. */
struct radv_gs_compute_setup {
   DEVICE(uint32_t) draw;       /* VkDraw[Indexed]IndirectCommand */
   DEVICE(uint32_t) draw_count; /* the count of an indirect count draw, or 0 */
   DEVICE(uint32_t) byte_count; /* the counter of a byte count draw, or 0 */
   DEVICE(struct radv_gs_compute_draw) block;
   DEVICE(struct poly_heap) heap;
   uint64_t index_buffer;
   uint64_t vs_outputs;
   uint32_t index_buffer_range_el;
   uint32_t index_size_B; /* 0 when not indexed */
   uint32_t draw_index;
   uint32_t byte_offset;
   uint32_t byte_stride;
   uint32_t prim; /* enum mesa_prim */
   uint32_t shape;
   uint32_t max_indices;

   /* Written: workgroup counts of the vertex and geometry passes. */
   uint32_t vs_groups[3];
   uint32_t gs_groups[3];
} PACKED;
static_assert(sizeof(struct radv_gs_compute_setup) == 28 * 4, "struct radv_gs_compute_setup must be 28 words");

/* An indexed draw with primitive restart becomes an indexed draw of the
 * decomposed list topology without restarts, in the heap
 * (radv_gs_compute_unroll, one workgroup of one wave). */
struct radv_gs_compute_unroll {
   DEVICE(uint32_t) draw;       /* VkDrawIndexedIndirectCommand */
   DEVICE(uint32_t) draw_count; /* the count of an indirect count draw, or 0 */
   DEVICE(uint32_t) out_draw;   /* the unrolled VkDrawIndexedIndirectCommand */
   DEVICE(struct poly_heap) heap;
   uint64_t index_buffer;
   uint64_t ro_sink;
   uint32_t index_buffer_range_el;
   uint32_t index_size_B;
   uint32_t restart_index;
   uint32_t flatshade_first;
   uint32_t prim; /* enum mesa_prim, before decomposition */
   uint32_t draw_index;
} PACKED;
static_assert(sizeof(struct radv_gs_compute_unroll) == 18 * 4, "struct radv_gs_compute_unroll must be 18 words");

/* A tessellated draw is set up by one invocation of
 * radv_gs_compute_tess_setup: it sizes the vertex and tessellation control
 * passes and the tessellator's per-patch buffers, allocates them from the
 * heap and writes the workgroup counts of the dispatches that follow. The
 * vertex shader shades only the vertices of whole patches. */
struct radv_gs_compute_tess_setup {
   DEVICE(uint32_t) draw;       /* VkDraw[Indexed]IndirectCommand */
   DEVICE(uint32_t) draw_count; /* the count of an indirect count draw, or 0 */
   DEVICE(uint32_t) byte_count; /* the counter of a byte count draw, or 0 */
   DEVICE(struct radv_gs_compute_draw) block; /* the vertex shader's block */
   DEVICE(struct poly_heap) heap;
   uint64_t index_buffer;
   uint32_t index_buffer_range_el;
   uint32_t index_size_B; /* 0 when not indexed */
   uint32_t draw_index;
   uint32_t byte_offset;
   uint32_t byte_stride;

   /* Written: workgroup counts of the vertex and tessellation control passes
    * (one workgroup per patch) and of the tessellator (one invocation per
    * patch). */
   uint32_t vs_groups[3];
   uint32_t tcs_groups[3];
   uint32_t tess_groups[3];
} PACKED;
static_assert(sizeof(struct radv_gs_compute_tess_setup) == 26 * 4,
              "struct radv_gs_compute_tess_setup must be 26 words");

/* One tessellator pass: counting each patch's indices, or writing them and
 * the domain points once the counts are summed (enum poly_tess_mode). */
struct radv_gs_compute_tessellate {
   DEVICE(struct poly_tess_params) params;
   uint32_t mode; /* enum poly_tess_mode */
   uint32_t pad;
} PACKED;
static_assert(sizeof(struct radv_gs_compute_tessellate) == 4 * 4,
              "struct radv_gs_compute_tessellate must be 4 words");

/* The heap's size leaves a guard behind it for poly's allocations that do
 * not fit (POLY_HEAP_GUARD): the largest is one patch's domain points, at
 * most 65 by 65 of them. */
#define RADV_GS_COMPUTE_HEAP_GUARD (64u << 10)

#define RADV_GS_COMPUTE_WAVE 64
