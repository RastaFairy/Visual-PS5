/*
 * Copyright © 2026 Mihawk-99
 *
 * SPDX-License-Identifier: MIT
 */

/* Per-vertex fragment inputs in the primitive's own vertex order, on a GPU whose SPI does not give them in it.
 *
 * VK_KHR_fragment_shader_barycentric reads a primitive's vertices in the order the primitive defines. The PS5's parameter
 * cache (GFX10.1's: it has neither SPI_PS_INPUT_CNTL.ROTATE_PC_PTR nor the pixel shader's provoking vertex argument, and
 * the console's reads of both were measured to change nothing, docs/HARDWARE_FINDINGS.md 2026-09-27 and
 * docs/BARYCENTRIC_GFX101.md) hands them over rotated: the first slot holds the vertex furthest left on the screen (then
 * furthest up), whatever the order they were drawn in. Winding is kept: the slots are always a cyclic rotation of the
 * primitive's vertices in its own order. The provoking vertex, on the other hand, is read correctly by an ordinary flat
 * input. So the pre-rasterization stage gives every vertex a tag derived from its position, once flat and once per
 * vertex, and the pixel shader finds the slot whose tag is the flat one: that slot holds the provoking vertex, and the
 * rest follow it in the primitive's order.
 *
 * Each tag is a hash of the vertex's clip-space position, so it tells the three vertices of any primitive that has an area
 * apart (the first hash tried cancelled the sign bit of (-1, -1) and (1, 1): the CTS's own quad found it). Two driver-owned locations carry them, the last two a varying can use; a program using them as well loses them.
 */

#include "nir/nir.h"
#include "nir/nir_builder.h"
#include "nir/nir_deref.h"
#include "radv_nir.h"
#include "radv_pipeline.h"
#include "radv_shader.h"

#include "amdgfxregs.h"

#define PS5_TAG_FLAT_LOCATION   (VARYING_SLOT_VAR0 + 30)
#define PS5_TAG_VERTEX_LOCATION (VARYING_SLOT_VAR0 + 31)

static nir_variable *
find_variable(nir_shader *nir, nir_variable_mode mode, unsigned location)
{
   nir_foreach_variable_with_modes (var, nir, mode) {
      if (var->data.location == location)
         return var;
   }
   return NULL;
}

static bool
is_tag_location(unsigned location)
{
   return location == PS5_TAG_FLAT_LOCATION || location == PS5_TAG_VERTEX_LOCATION;
}

static bool
uses_barycentric_coord(nir_shader *nir)
{
   nir_foreach_function_impl (impl, nir) {
      nir_foreach_block (block, impl) {
         nir_foreach_instr (instr, block) {
            if (instr->type != nir_instr_type_intrinsic)
               continue;
            switch (nir_instr_as_intrinsic(instr)->intrinsic) {
            case nir_intrinsic_load_barycentric_coord_pixel:
            case nir_intrinsic_load_barycentric_coord_centroid:
            case nir_intrinsic_load_barycentric_coord_sample:
            case nir_intrinsic_load_barycentric_coord_at_offset:
            case nir_intrinsic_load_barycentric_coord_at_sample:
               return true;
            default:
               break;
            }
         }
      }
   }
   return false;
}

static bool
has_per_vertex_inputs(nir_shader *nir)
{
   nir_foreach_shader_in_variable (var, nir) {
      if (var->data.per_vertex && !is_tag_location(var->data.location))
         return true;
   }
   return false;
}

/* How many vertices the rasterized primitive has: the pipeline's topology when it is known, the hardware's primitive type
 * otherwise (a dynamic topology, a pipeline library). */
static nir_def *
vertex_count(nir_builder *b, unsigned num_raster_vertices_per_prim)
{
   if (num_raster_vertices_per_prim)
      return nir_imm_int(b, num_raster_vertices_per_prim);

   nir_def *type = nir_load_rasterization_primitive_amd(b);
   return nir_bcsel(b, nir_ieq_imm(b, type, V_028A6C_POINTLIST), nir_imm_int(b, 1),
                    nir_bcsel(b, nir_ieq_imm(b, type, V_028A6C_LINESTRIP), nir_imm_int(b, 2), nir_imm_int(b, 3)));
}

/* The slot holding the primitive's first vertex: its k-th vertex is then slot (k + that) % n. The flat tag is the provoking
 * vertex's, which is the primitive's first when the provoking vertex is first and its last (index n - 1) when it is last;
 * which of the two the pipeline uses travels in the tags' lowest bit, because a pixel shader compiled in a pipeline library
 * (or under a dynamic provoking vertex) does not know it. */
nir_def *
radv_nir_ps5_vertex_order_slot(nir_builder *b, unsigned num_raster_vertices_per_prim)
{
   nir_variable *flat = find_variable(b->shader, nir_var_shader_in, PS5_TAG_FLAT_LOCATION);
   nir_variable *vertex = find_variable(b->shader, nir_var_shader_in, PS5_TAG_VERTEX_LOCATION);
   assert(flat && vertex);

   nir_def *provoking = nir_load_var(b, flat);
   nir_def *slot0 = nir_load_deref(b, nir_build_deref_array_imm(b, nir_build_deref_var(b, vertex), 0));
   nir_def *slot1 = nir_load_deref(b, nir_build_deref_array_imm(b, nir_build_deref_var(b, vertex), 1));
   nir_def *provoking_slot = nir_bcsel(b, nir_ieq(b, slot0, provoking), nir_imm_int(b, 0),
                                       nir_bcsel(b, nir_ieq(b, slot1, provoking), nir_imm_int(b, 1), nir_imm_int(b, 2)));
   nir_def *count = vertex_count(b, num_raster_vertices_per_prim);
   nir_def *provoking_last = nir_i2b(b, nir_iand_imm(b, provoking, 1));
   return nir_umod(b, nir_bcsel(b, provoking_last, nir_iadd_imm(b, provoking_slot, 1), provoking_slot), count);
}

static void
create_tag_variables(nir_shader *nir)
{
   if (find_variable(nir, nir_var_shader_in, PS5_TAG_FLAT_LOCATION))
      return;

   nir_variable *flat = nir_variable_create(nir, nir_var_shader_in, glsl_uint_type(), "ps5_vertex_tag_flat");
   flat->data.location = PS5_TAG_FLAT_LOCATION;
   flat->data.interpolation = INTERP_MODE_FLAT;

   nir_variable *vertex = nir_variable_create(nir, nir_var_shader_in, glsl_array_type(glsl_uint_type(), 3, 0),
                                              "ps5_vertex_tag_vertex");
   vertex->data.location = PS5_TAG_VERTEX_LOCATION;
   vertex->data.per_vertex = true;
}

static nir_deref_instr *
rebuild_deref_with_vertex(nir_builder *b, nir_deref_path *path, unsigned vertex)
{
   nir_deref_instr *deref = nir_build_deref_array_imm(b, nir_build_deref_var(b, path->path[0]->var), vertex);

   for (unsigned i = 2; path->path[i]; i++) {
      switch (path->path[i]->deref_type) {
      case nir_deref_type_struct:
         deref = nir_build_deref_struct(b, deref, path->path[i]->strct.index);
         break;
      case nir_deref_type_array:
         deref = nir_build_deref_array(b, deref, path->path[i]->arr.index.ssa);
         break;
      default:
         return NULL;
      }
   }
   return deref;
}

static bool
lower_per_vertex_load(nir_builder *b, nir_intrinsic_instr *intrin, unsigned num_raster_vertices_per_prim)
{
   if (intrin->intrinsic != nir_intrinsic_load_deref)
      return false;

   nir_deref_instr *deref = nir_src_as_deref(intrin->src[0]);
   if (!nir_deref_mode_is(deref, nir_var_shader_in))
      return false;

   nir_deref_path path;
   nir_deref_path_init(&path, deref, NULL);

   bool progress = false;
   nir_variable *var = path.path[0]->var;
   if (var->data.per_vertex && !is_tag_location(var->data.location) && path.path[1] &&
       path.path[1]->deref_type == nir_deref_type_array) {
      b->cursor = nir_before_instr(&intrin->instr);

      nir_def *loads[3];
      bool ok = true;
      for (unsigned slot = 0; slot < 3 && ok; slot++) {
         nir_deref_instr *slot_deref = rebuild_deref_with_vertex(b, &path, slot);
         ok = slot_deref != NULL;
         if (ok)
            loads[slot] = nir_build_load_deref(b, intrin->def.num_components, intrin->def.bit_size, &slot_deref->def,
                                               nir_intrinsic_access(intrin));
      }

      if (ok) {
         nir_def *first = radv_nir_ps5_vertex_order_slot(b, num_raster_vertices_per_prim);
         /* A line has two vertices and a point one: the vertex indices past the last repeat it (the CTS's {2p, 2p+1,
          * 2p+1}, and a point's {p, p, p}). */
         nir_def *count = vertex_count(b, num_raster_vertices_per_prim);
         nir_def *index = nir_umin(b, path.path[1]->arr.index.ssa, nir_iadd_imm(b, count, -1));
         nir_def *slot = nir_umod(b, nir_iadd(b, index, first), count);
         nir_def *value = nir_bcsel(b, nir_ieq_imm(b, slot, 0), loads[0],
                                    nir_bcsel(b, nir_ieq_imm(b, slot, 1), loads[1], loads[2]));
         nir_def_replace(&intrin->def, value);
         progress = true;
      }
   }

   nir_deref_path_finish(&path);
   return progress;
}

bool
radv_nir_lower_fs_vertex_order(nir_shader *fs, unsigned num_raster_vertices_per_prim)
{
   assert(fs->info.stage == MESA_SHADER_FRAGMENT);

   const bool per_vertex = has_per_vertex_inputs(fs);
   if (!per_vertex && !uses_barycentric_coord(fs))
      return false;

   create_tag_variables(fs);

   bool progress = false;
   if (per_vertex) {
      nir_foreach_function_impl (impl, fs) {
         nir_builder b = nir_builder_create(impl);
         nir_foreach_block (block, impl) {
            nir_foreach_instr_safe (instr, block) {
               if (instr->type == nir_instr_type_intrinsic)
                  progress |= lower_per_vertex_load(&b, nir_instr_as_intrinsic(instr), num_raster_vertices_per_prim);
            }
         }
         nir_progress(progress, impl, nir_metadata_none);
      }
   }

   nir_shader_gather_info(fs, nir_shader_get_entrypoint(fs));
   return true;
}

bool
radv_nir_ps5_vertex_order_enabled(nir_shader *fs)
{
   return find_variable(fs, nir_var_shader_in, PS5_TAG_FLAT_LOCATION) != NULL;
}

/* The pre-rasterization stage's half: both tags are the same hash of the vertex's clip-space position, written at the end
 * of the shader where every write to the position is seen. */
bool
radv_nir_export_vertex_tags(nir_shader *nir, bool provoking_last)
{
   if (nir->info.stage != MESA_SHADER_VERTEX && nir->info.stage != MESA_SHADER_TESS_EVAL)
      return false;

   nir_variable *position = find_variable(nir, nir_var_shader_out, VARYING_SLOT_POS);
   if (!position || find_variable(nir, nir_var_shader_out, PS5_TAG_FLAT_LOCATION))
      return false;

   nir_function_impl *impl = nir_shader_get_entrypoint(nir);
   nir_builder b = nir_builder_at(nir_after_impl(impl));

   /* The shader's outputs are already temporaries (radv_shader.c) written out at the end of the last block: the position
    * is the value of that last write, a whole vec4, or the temporary a copy takes it from. */
   nir_def *pos = NULL;
   nir_block *last = nir_impl_last_block(impl);
   nir_foreach_instr (instr, last) {
      if (instr->type != nir_instr_type_intrinsic)
         continue;
      nir_intrinsic_instr *write = nir_instr_as_intrinsic(instr);
      if (write->intrinsic == nir_intrinsic_store_deref) {
         nir_deref_instr *deref = nir_src_as_deref(write->src[0]);
         if (deref->deref_type == nir_deref_type_var && deref->var == position &&
             nir_intrinsic_write_mask(write) == 0xf && write->src[1].ssa->num_components == 4)
            pos = write->src[1].ssa;
      } else if (write->intrinsic == nir_intrinsic_copy_deref) {
         nir_deref_instr *dst = nir_src_as_deref(write->src[0]);
         nir_deref_instr *src = nir_src_as_deref(write->src[1]);
         if (dst->deref_type == nir_deref_type_var && dst->var == position && src->deref_type == nir_deref_type_var &&
             src->var->data.mode == nir_var_function_temp) {
            b.cursor = nir_before_instr(instr);
            pos = nir_load_var(&b, src->var);
            b.cursor = nir_after_impl(impl);
         }
      }
   }
   if (!pos)
      return false;

   nir_variable *flat = nir_variable_create(nir, nir_var_shader_out, glsl_uint_type(), "ps5_vertex_tag_flat");
   flat->data.location = PS5_TAG_FLAT_LOCATION;
   flat->data.interpolation = INTERP_MODE_FLAT;
   nir_variable *vertex = nir_variable_create(nir, nir_var_shader_out, glsl_uint_type(), "ps5_vertex_tag_vertex");
   vertex->data.location = PS5_TAG_VERTEX_LOCATION;
   /* Each component is folded in with a multiply and shifts: a plain xor of products loses the sign bit when two
    * components flip it together, and (-1, -1) and (1, 1) are corners of the most common primitive there is. */
   nir_def *hash = nir_imm_int(&b, 0x9e3779b9u);
   for (unsigned i = 0; i < 4; i++) {
      hash = nir_imul_imm(&b, nir_ixor(&b, hash, nir_channel(&b, pos, i)), 0x85ebca6bu);
      hash = nir_ixor(&b, hash, nir_ushr_imm(&b, hash, 13));
      hash = nir_imul_imm(&b, hash, 0xc2b2ae35u);
      hash = nir_ixor(&b, hash, nir_ushr_imm(&b, hash, 16));
   }

   /* The lowest bit says whether the provoking vertex is the last. */
   nir_def *provoking_is_last = nir->info.stage == MESA_SHADER_VERTEX ?
                      nir_b2i32(&b, nir_ine_imm(&b, nir_load_provoking_vtx_in_prim_amd(&b), 0)) :
                      nir_imm_int(&b, provoking_last);
   hash = nir_ior(&b, nir_iand_imm(&b, hash, 0xfffffffeu), provoking_is_last);

   nir_store_var(&b, flat, hash, 0x1);
   nir_store_var(&b, vertex, hash, 0x1);

   nir_progress(true, impl, nir_metadata_none);
   nir_shader_gather_info(nir, impl);
   return true;
}
