/*
 * Copyright © 2026 Mihawk
 *
 * SPDX-License-Identifier: MIT
 */

/* Geometry shaders the hardware cannot run, as compute: see radv_gs_compute.h. */

#include "radv_gs_compute.h"

#include "nir/radv_nir.h"
#include "nir_builder.h"
#include "nir_serialize.h"
#include "radv_pipeline.h"
#include "radv_pipeline_cache.h"
#include "radv_device.h"
#include "radv_shader.h"
#include "radv_shader_args.h"
#include "radv_shader_info.h"

#include "ac_nir.h"
#include "libradv_cl.h"
#include "meta/radv_meta.h"
#include "nir/radv_meta_nir.h"
#include "poly/cl/libpoly.h"
#include "poly/geometry.h"
#include "radv_device.h"
#include "util/u_debug.h"
#include "vk_shader_module.h"

bool
radv_gs_compute_wanted(const struct radv_compiler_info *compiler_info, const struct radv_graphics_state_key *gfx_state,
                       const struct radv_shader_stage *stages)
{
   const nir_shader *gs = stages[MESA_SHADER_GEOMETRY].nir;

   if (!compiler_info->key.no_legacy_gs || !gs || !stages[MESA_SHADER_VERTEX].nir)
      return false;

   /* The vertex shader's input may come at the draw
    * (radv_gs_compute_deferred_vs). With tessellation, both of its shaders. */
   const bool tess = stages[MESA_SHADER_TESS_CTRL].nir || stages[MESA_SHADER_TESS_EVAL].nir;
   if (tess && (!stages[MESA_SHADER_TESS_CTRL].nir || !stages[MESA_SHADER_TESS_EVAL].nir))
      return false;

   /* A tessellated geometry shader amplifying past one NGG subgroup: NGG then
    * splits a primitive's invocations across subgroups, which hangs with
    * tessellation on GFX10-class hardware (where RADV takes the legacy GS
    * this GPU does not have, radv_fill_shader_info_ngg). */
   if (tess && gs->info.gs.invocations * gs->info.gs.vertices_out > 256)
      return true;

   /* Transform feedback from a geometry shader, which NGG cannot capture here
    * (radv_gs_compute.h); every geometry shader when forced for testing. */
   return gs->xfb_info || debug_get_bool_option("RADV_PS5_GS_COMPUTE", false);
}

/* The vertex shader's outputs go to memory, indexed by the invocation's place
 * in the unrolled vertex stream (x) and its instance (y), where poly's
 * geometry shader reads its inputs. */
static bool
lower_vs_output_to_memory(nir_builder *b, nir_intrinsic_instr *intr, void *data)
{
   if (intr->intrinsic != nir_intrinsic_store_output)
      return false;

   const uint64_t outputs = *(const uint64_t *)data;
   b->cursor = nir_instr_remove(&intr->instr);

   const nir_io_semantics sem = nir_intrinsic_io_semantics(intr);
   nir_def *location = nir_iadd_imm(b, intr->src[1].ssa, sem.location);
   nir_def *vp = nir_load_vertex_param_buffer_poly(b);
   nir_def *id = nir_load_global_invocation_id(b, 32);
   nir_def *linear = nir_iadd(b, nir_imul(b, nir_channel(b, id, 1), poly_input_vertices(b, vp)), nir_channel(b, id, 0));
   nir_def *addr = poly_vertex_output_address(b, vp, nir_imm_int64(b, outputs), linear, location);

   assert(nir_src_bit_size(intr->src[0]) <= 32);
   addr = nir_iadd_imm(b, addr, nir_intrinsic_component(intr) * 4);
   nir_store_global(b, intr->src[0].ssa, addr, .write_mask = nir_intrinsic_write_mask(intr));
   return true;
}

/* Memory writes of the application's own (buffers, images, device addresses)
 * happen once per invocation, in one copy of the geometry shader: the other
 * copies drop them. poly strips the global and bindless forms; these are
 * RADV's, still derefs and SSBO intrinsics when poly runs. An atomic whose
 * result is used stays. */
static bool
strip_app_memory_writes(nir_builder *b, nir_intrinsic_instr *intr, void *data)
{
   switch (intr->intrinsic) {
   case nir_intrinsic_store_ssbo:
   case nir_intrinsic_image_deref_store:
   case nir_intrinsic_image_store:
   case nir_intrinsic_bindless_image_store:
      nir_instr_remove(&intr->instr);
      return true;

   case nir_intrinsic_store_deref: {
      nir_deref_instr *deref = nir_src_as_deref(intr->src[0]);
      if (!nir_deref_mode_is_one_of(deref, nir_var_mem_ssbo | nir_var_mem_global | nir_var_image))
         return false;
      nir_instr_remove(&intr->instr);
      return true;
   }

   case nir_intrinsic_ssbo_atomic:
   case nir_intrinsic_ssbo_atomic_swap:
   case nir_intrinsic_deref_atomic:
   case nir_intrinsic_deref_atomic_swap:
   case nir_intrinsic_image_deref_atomic:
   case nir_intrinsic_image_deref_atomic_swap:
   case nir_intrinsic_global_atomic:
   case nir_intrinsic_global_atomic_swap:
      if (nir_intrinsic_infos[intr->intrinsic].has_dest && !list_is_empty(&intr->def.uses))
         return false;
      if (intr->intrinsic == nir_intrinsic_deref_atomic || intr->intrinsic == nir_intrinsic_deref_atomic_swap) {
         nir_deref_instr *deref = nir_src_as_deref(intr->src[0]);
         if (!nir_deref_mode_is_one_of(deref, nir_var_mem_ssbo | nir_var_mem_global))
            return false;
      }
      nir_instr_remove(&intr->instr);
      return true;

   default:
      return false;
   }
}

static void
strip_side_effects(nir_shader *nir)
{
   bool progress;
   do {
      progress = false;
      NIR_PASS(progress, nir, nir_shader_intrinsics_pass, strip_app_memory_writes, nir_metadata_control_flow, NULL);
      NIR_PASS(progress, nir, nir_opt_dce);
      NIR_PASS(progress, nir, nir_opt_dead_cf);
   } while (progress);
}

/* The vertex shader's half: its outputs go to memory, where the geometry
 * shader reads them; returns the mask that fixes their layout. */
uint64_t
radv_gs_compute_lower_vs(nir_shader *vs, const struct radv_shader_stage_key *key)
{
   radv_nir_lower_io(vs);
   NIR_PASS(_, vs, nir_lower_vars_to_ssa);
   radv_optimize_nir(vs, key->optimisations_disabled);
   nir_shader_gather_info(vs, nir_shader_get_entrypoint(vs));

   uint64_t outputs = vs->info.outputs_written;
   NIR_PASS(_, vs, nir_shader_intrinsics_pass, lower_vs_output_to_memory, nir_metadata_control_flow, &outputs);
   return outputs;
}

/* After tessellation the primitive ID restarts with each instance
 * (radv_gs_compute_tess_primitive_id); without tessellation parameters in
 * the draw block, poly's own ID stands. */
static void
lower_tess_primitive_id(nir_shader *gs)
{
   nir_function_impl *impl = nir_shader_get_entrypoint(gs);
   struct util_dynarray loads;
   util_dynarray_init(&loads, NULL);
   nir_foreach_block (block, impl) {
      nir_foreach_instr (instr, block) {
         if (instr->type == nir_instr_type_intrinsic &&
             nir_instr_as_intrinsic(instr)->intrinsic == nir_intrinsic_load_primitive_id)
            util_dynarray_append(&loads, nir_instr_as_intrinsic(instr));
      }
   }

   nir_builder b = nir_builder_create(impl);
   const unsigned vertices_per_prim = mesa_vertices_per_prim(gs->info.gs.input_primitive);
   util_dynarray_foreach (&loads, nir_intrinsic_instr *, load) {
      b.cursor = nir_before_instr(&(*load)->instr);
      nir_def *raw = nir_load_primitive_id(&b);
      nir_def *params = nir_load_tess_param_buffer_poly(&b);
      nir_def *adjusted;
      nir_push_if(&b, nir_ine_imm(&b, params, 0));
      {
         adjusted = radv_gs_compute_tess_primitive_id(&b, params, raw, nir_imm_int(&b, vertices_per_prim));
      }
      nir_pop_if(&b, NULL);
      nir_def_replace(&(*load)->def, nir_if_phi(&b, adjusted, raw));
   }
   util_dynarray_fini(&loads);
   nir_progress(true, impl, nir_metadata_none);
}

/* The geometry shader's half: poly's count pass, pre-GS setup, the GS proper
 * (out->nir) and the rasterization copy (returned). The GS reads the vertex
 * outputs through the mask the draw passes (poly's vertex parameters), so this
 * half does not depend on the vertex shader. */
nir_shader *
radv_gs_compute_split_gs(nir_shader *gs, const struct radv_shader_stage_key *key, struct radv_gs_compute_nir *out)
{
   radv_nir_lower_io(gs);
   NIR_PASS(_, gs, nir_lower_vars_to_ssa);
   radv_optimize_nir(gs, key->optimisations_disabled);
   /* poly keeps the memory writes in a count pass only when the shader's
    * information says it writes memory: gather it again after lowering. */
   nir_shader_gather_info(gs, nir_shader_get_entrypoint(gs));

   lower_tess_primitive_id(gs);

   nir_shader *count = NULL, *rast = NULL, *pre_gs = NULL;
   NIR_PASS(_, gs, poly_nir_lower_gs, &count, &rast, &pre_gs, &out->info);

   /* The application's memory writes happen once per invocation: in the count
    * pass when poly made one, in the GS proper otherwise (static counts). The
    * rasterization copy runs the shader again per output vertex and never
    * keeps them. */
   if (count)
      strip_side_effects(gs);
   strip_side_effects(rast);

   /* poly's bookkeeping lives in shader temporaries: make them SSA as the
    * rest of RADV expects. */
   nir_shader *const lowered[] = {count, pre_gs, gs, rast};
   for (unsigned i = 0; i < ARRAY_SIZE(lowered); i++) {
      if (!lowered[i])
         continue;
      NIR_PASS(_, lowered[i], nir_lower_global_vars_to_local);
      NIR_PASS(_, lowered[i], nir_lower_vars_to_ssa);

      /* poly wrote the transform feedback: none of these captures any in
       * hardware. */
      lowered[i]->xfb_info = NULL;
      lowered[i]->info.has_transform_feedback_varyings = false;
   }

   /* The rasterization copy reads the vertex ID RADV lowers right after
    * SPIR-V: poly made it after that. */
   NIR_PASS(_, rast, nir_lower_system_values);

   out->nir[radv_gs_compute_index(RADV_GS_COMPUTE_COUNT)] = count;
   out->nir[radv_gs_compute_index(RADV_GS_COMPUTE_PRE_GS)] = pre_gs;
   out->nir[radv_gs_compute_index(RADV_GS_COMPUTE_MAIN)] = gs;
   return rast;
}

/* Either tessellation shader may declare the mode, spacing, winding, point
 * mode and output patch size; they agree where both do (as merge_tess_info
 * merges them for the hardware path). */
static void
merge_tess_info(nir_shader *tcs, nir_shader *tes)
{
   tes->info.tess.tcs_vertices_out |= tcs->info.tess.tcs_vertices_out;
   tes->info.tess.spacing |= tcs->info.tess.spacing;
   tes->info.tess._primitive_mode |= tcs->info.tess._primitive_mode;
   tes->info.tess.ccw |= tcs->info.tess.ccw;
   tes->info.tess.point_mode |= tcs->info.tess.point_mode;
   tcs->info.tess.tcs_vertices_out = tes->info.tess.tcs_vertices_out;
   tcs->info.tess._primitive_mode = tes->info.tess._primitive_mode;
}

static void
lower_io_for_poly(nir_shader *nir, const struct radv_shader_stage_key *key)
{
   radv_nir_lower_io(nir);
   NIR_PASS(_, nir, nir_lower_vars_to_ssa);
   radv_optimize_nir(nir, key->optimisations_disabled);
   nir_shader_gather_info(nir, nir_shader_get_entrypoint(nir));
}

/* The tessellation control shader reads the vertex shader's outputs from
 * memory and writes its own there, one workgroup per patch (poly's layout). */
void
radv_gs_compute_lower_tcs(nir_shader *tcs, const struct radv_shader_stage_key *key,
                          struct radv_gs_compute_tess_info *tess)
{
   lower_io_for_poly(tcs, key);
   tess->output_patch_size = tcs->info.tess.tcs_vertices_out;
   tess->per_vertex_outputs = poly_tcs_per_vertex_outputs(tcs);
   tess->patch_outputs = util_last_bit(tcs->info.patch_outputs_written);
   tess->tcs_stride_B = poly_tcs_output_stride(tcs);
   NIR_PASS(_, tcs, poly_nir_lower_tcs, false);
}

/* The tessellation evaluation shader runs over the tessellator's output as
 * the geometry shader's vertex stage: its domain point, patch and inputs come
 * from memory, and its outputs go there as a vertex shader's do. */
void
radv_gs_compute_lower_tes(nir_shader *tes, const struct radv_shader_stage_key *key,
                          struct radv_gs_compute_tess_info *tess)
{
   lower_io_for_poly(tes, key);
   tess->prim = tes->info.tess._primitive_mode;
   tess->spacing = tes->info.tess.spacing;
   tess->ccw = tes->info.tess.ccw;
   tess->points = tes->info.tess.point_mode;
   NIR_PASS(_, tes, poly_nir_lower_tes, false);

   uint64_t outputs = tes->info.outputs_written;
   NIR_PASS(_, tes, nir_shader_intrinsics_pass, lower_vs_output_to_memory, nir_metadata_control_flow, &outputs);
   tess->tes_outputs = outputs;
}

void
radv_gs_compute_split(const struct radv_compiler_info *compiler_info, struct radv_shader_stage *stages,
                      struct radv_gs_compute_nir *out)
{
   (void)compiler_info;
   struct radv_shader_stage *vs_stage = &stages[MESA_SHADER_VERTEX];
   struct radv_shader_stage *tcs_stage = &stages[MESA_SHADER_TESS_CTRL];
   struct radv_shader_stage *tes_stage = &stages[MESA_SHADER_TESS_EVAL];
   struct radv_shader_stage *gs_stage = &stages[MESA_SHADER_GEOMETRY];

   memset(out, 0, sizeof(*out));
   out->vs_outputs = radv_gs_compute_lower_vs(vs_stage->nir, &vs_stage->key);
   out->nir[radv_gs_compute_index(RADV_GS_COMPUTE_VS)] = vs_stage->nir;
   if (tcs_stage->nir) {
      merge_tess_info(tcs_stage->nir, tes_stage->nir);
      radv_gs_compute_lower_tcs(tcs_stage->nir, &tcs_stage->key, &out->tess);
      radv_gs_compute_lower_tes(tes_stage->nir, &tes_stage->key, &out->tess);
      out->tess.used = true;
      out->nir[radv_gs_compute_index(RADV_GS_COMPUTE_TCS)] = tcs_stage->nir;
      out->nir[radv_gs_compute_index(RADV_GS_COMPUTE_TES)] = tes_stage->nir;
      tcs_stage->nir = NULL;
      tcs_stage->stage = MESA_SHADER_NONE;
      tes_stage->nir = NULL;
      tes_stage->stage = MESA_SHADER_NONE;
   }
   nir_shader *const rast = radv_gs_compute_split_gs(gs_stage->nir, &gs_stage->key, out);

   /* The pipeline's hardware vertex shader is the rasterization copy; there is
    * no hardware geometry shader, and no hardware tessellation. The copy runs
    * the geometry shader again, with its dynamic buffers. */
   vs_stage->nir = rast;
   vs_stage->layout.use_dynamic_descriptors |= gs_stage->layout.use_dynamic_descriptors;
   vs_stage->next_stage = MESA_SHADER_FRAGMENT;
   gs_stage->nir = NULL;
   gs_stage->stage = MESA_SHADER_NONE;
}

static nir_def *
load_draw(nir_builder *b, const struct radv_compiler_info *compiler_info, const struct radv_shader_args *args,
          unsigned offset, unsigned num_components)
{
   nir_def *base = nir_pack_64_2x32_split(b, ac_nir_load_arg(b, &args->ac, args->gs_compute_draw),
                                         nir_imm_int(b, compiler_info->hw.address32_hi));
   return ac_nir_load_smem(b, num_components, base, nir_imm_int(b, offset), 4, ACCESS_CAN_SPECULATE);
}

static nir_def *
load_draw64(nir_builder *b, const struct radv_compiler_info *compiler_info, const struct radv_shader_args *args,
            unsigned offset)
{
   return nir_pack_64_2x32(b, load_draw(b, compiler_info, args, offset, 2));
}

struct lower_sysvals_state {
   const struct radv_compiler_info *compiler_info;
   const struct radv_shader_stage *stage;
};

/* The vertex shader run as compute: its vertex is the index-buffer entry at its
 * place in the stream, or that place itself without an index buffer. */
static nir_def *
sw_vs_vertex(nir_builder *b)
{
   nir_def *place = nir_channel(b, nir_load_global_invocation_id(b, 32), 0);
   nir_def *index_size = nir_load_index_size_poly(b);
   nir_def *indexed;
   nir_push_if(b, nir_ine_imm(b, index_size, 0));
   {
      indexed = poly_load_index_buffer(b, nir_load_vertex_param_buffer_poly(b), place, index_size);
   }
   nir_pop_if(b, NULL);
   return nir_if_phi(b, indexed, place);
}

static bool
lower_sw_vs_sysval(nir_builder *b, nir_intrinsic_instr *intr, void *data)
{
   b->cursor = nir_before_instr(&intr->instr);

   switch (intr->intrinsic) {
   case nir_intrinsic_load_vertex_id_zero_base:
      nir_def_replace(&intr->def, sw_vs_vertex(b));
      return true;
   case nir_intrinsic_load_vertex_id:
      nir_def_replace(&intr->def, nir_iadd(b, sw_vs_vertex(b), nir_load_first_vertex(b)));
      return true;
   case nir_intrinsic_load_instance_id:
      nir_def_replace(&intr->def, nir_channel(b, nir_load_global_invocation_id(b, 32), 1));
      return true;
   case nir_intrinsic_load_is_indexed_draw:
      nir_def_replace(&intr->def, nir_b2i32(b, nir_ine_imm(b, nir_load_index_size_poly(b), 0)));
      return true;
   case nir_intrinsic_load_base_vertex:
      nir_def_replace(&intr->def, nir_bcsel(b, nir_ine_imm(b, nir_load_index_size_poly(b), 0),
                                            nir_load_first_vertex(b), nir_imm_int(b, 0)));
      return true;
   default:
      return false;
   }
}

static bool
lower_sysval(nir_builder *b, nir_intrinsic_instr *intr, void *data)
{
   const struct lower_sysvals_state *state = data;
   const struct radv_compiler_info *compiler_info = state->compiler_info;
   const struct radv_shader_args *args = &state->stage->args;
   const bool compute = state->stage->stage == MESA_SHADER_COMPUTE;

   b->cursor = nir_before_instr(&intr->instr);

   nir_def *value;
   switch (intr->intrinsic) {
   case nir_intrinsic_load_vertex_param_buffer_poly:
      value = load_draw64(b, compiler_info, args, RADV_GS_COMPUTE_DRAW_OFFSET(vertex_params));
      break;
   case nir_intrinsic_load_geometry_param_buffer_poly:
      value = load_draw64(b, compiler_info, args, RADV_GS_COMPUTE_DRAW_OFFSET(geometry_params));
      break;
   case nir_intrinsic_load_tess_param_buffer_poly:
      value = load_draw64(b, compiler_info, args, RADV_GS_COMPUTE_DRAW_OFFSET(tess_params));
      break;
   case nir_intrinsic_load_ro_sink_address_poly:
   case nir_intrinsic_load_stat_query_address_poly:
      /* Statistics come with queries (not yet): into the sink meanwhile. */
      value = load_draw64(b, compiler_info, args, RADV_GS_COMPUTE_DRAW_OFFSET(ro_sink));
      break;
   case nir_intrinsic_load_flat_mask:
      value = load_draw64(b, compiler_info, args, RADV_GS_COMPUTE_DRAW_OFFSET(flat_mask));
      break;
   case nir_intrinsic_load_input_topology_poly:
      value = load_draw(b, compiler_info, args, RADV_GS_COMPUTE_DRAW_OFFSET(input_topology), 1);
      break;
   case nir_intrinsic_load_rasterization_stream:
      value = load_draw(b, compiler_info, args, RADV_GS_COMPUTE_DRAW_OFFSET(rasterization_stream), 1);
      break;
   case nir_intrinsic_load_provoking_last:
      value = nir_b2b32(b, nir_ine_imm(b, load_draw(b, compiler_info, args,
                                                     RADV_GS_COMPUTE_DRAW_OFFSET(provoking_last), 1), 0));
      break;
   case nir_intrinsic_ro_to_rw_poly:
      value = intr->src[0].ssa;
      break;
   case nir_intrinsic_load_first_vertex:
      if (!compute)
         return false;
      value = load_draw(b, compiler_info, args, RADV_GS_COMPUTE_DRAW_OFFSET(first_vertex), 1);
      break;
   case nir_intrinsic_load_base_instance:
      if (!compute)
         return false;
      value = load_draw(b, compiler_info, args, RADV_GS_COMPUTE_DRAW_OFFSET(base_instance), 1);
      break;
   case nir_intrinsic_load_draw_id:
      if (!compute)
         return false;
      value = load_draw(b, compiler_info, args, RADV_GS_COMPUTE_DRAW_OFFSET(draw_id), 1);
      break;
   case nir_intrinsic_load_view_index:
      /* The rasterization copy has the hardware's; the passes, the draw's. */
      if (!compute)
         return false;
      value = load_draw(b, compiler_info, args, RADV_GS_COMPUTE_DRAW_OFFSET(view_index), 1);
      break;
   default:
      return false;
   }

   nir_def_replace(&intr->def, value);
   return true;
}

bool
radv_gs_compute_lower_sysvals(nir_shader *nir, const struct radv_compiler_info *compiler_info,
                              const struct radv_shader_stage *stage)
{
   bool progress = false;
   NIR_PASS(progress, nir, poly_nir_lower_sysvals);
   const struct lower_sysvals_state state = {.compiler_info = compiler_info, .stage = stage};
   NIR_PASS(progress, nir, nir_shader_intrinsics_pass, lower_sysval, nir_metadata_control_flow, (void *)&state);
   return progress;
}

/* Only invocations inside poly's grid run: (vertices, instances) for the
 * vertex shader or the tessellation evaluation shader in its place,
 * (primitives, instances) for the geometry shader's passes, from the
 * parameter blocks. A dispatch covers whole workgroups; the rest of the last
 * one must write nothing. */
static void
guard_grid(nir_shader *nir, enum radv_gs_compute_kind kind)
{
   nir_function_impl *impl = nir_shader_get_entrypoint(nir);
   nir_cf_list body;
   nir_cf_extract(&body, nir_before_impl(impl), nir_after_impl(impl));

   nir_builder b = nir_builder_at(nir_before_impl(impl));
   nir_def *params;
   unsigned grid_offset;
   if (kind == RADV_GS_COMPUTE_VS || kind == RADV_GS_COMPUTE_TES) {
      params = nir_load_vertex_param_buffer_poly(&b);
      grid_offset = offsetof(struct poly_vertex_params, grid);
   } else {
      params = nir_load_geometry_param_buffer_poly(&b);
      grid_offset = offsetof(struct poly_geometry_params, grid);
   }
   nir_def *grid = nir_load_global_constant(&b, 2, 32, nir_iadd_imm(&b, params, grid_offset), .align_mul = 4);
   nir_def *id = nir_load_global_invocation_id(&b, 32);
   nir_def *inside = nir_iand(&b, nir_ult(&b, nir_channel(&b, id, 0), nir_channel(&b, grid, 0)),
                              nir_ult(&b, nir_channel(&b, id, 1), nir_channel(&b, grid, 1)));
   nir_push_if(&b, inside);
   nir_cf_reinsert(&body, b.cursor);
   nir_pop_if(&b, NULL);
   nir_progress(true, impl, nir_metadata_none);
}

/* As RADV's compute shaders, and poly's OpenCL helpers' global IDs without a
 * base (a dispatch here starts at 0). */
static const nir_lower_compute_system_values_options compute_sysval_options = {
   .lower_local_invocation_index = true,
   .has_base_global_invocation_id = false,
   .has_base_workgroup_id = false,
};

struct radv_shader_binary *
radv_gs_compute_compile(const struct radv_compiler_info *compiler_info, const struct radv_graphics_state_key *gfx_state,
                        const struct radv_shader_stage *vs_stage, enum radv_gs_compute_kind kind, nir_shader *nir,
                        struct radv_shader_debug_info *debug)
{
   struct radv_shader_stage stage;
   memset(&stage, 0, sizeof(stage));
   stage.stage = MESA_SHADER_COMPUTE;
   stage.next_stage = MESA_SHADER_NONE;
   stage.entrypoint = "main";
   stage.layout = vs_stage->layout;
   stage.key = vs_stage->key;
   stage.nir = nir;

   /* The vertex shader's attribute fetch needs its vertex input information,
    * gathered while it is still a vertex shader. */
   struct radv_shader_info vs_info;
   if (kind == RADV_GS_COMPUTE_VS) {
      radv_nir_shader_info_init(MESA_SHADER_VERTEX, MESA_SHADER_NONE, &vs_info);
      radv_nir_shader_info_pass(compiler_info, nir, &stage.layout, &stage.key, gfx_state, RADV_PIPELINE_GRAPHICS,
                                false, &vs_info);
   }

   /* The pre-GS setup is one invocation, and the tessellation control shader
    * one workgroup per patch, as many as there are; the others cover poly's
    * grid. */
   if (kind != RADV_GS_COMPUTE_PRE_GS && kind != RADV_GS_COMPUTE_TCS)
      guard_grid(nir, kind);

   /* Everything runs as compute, 64 invocations a workgroup along x but the
    * tessellation control shader, a patch's output vertices. */
   const unsigned workgroup_size = kind == RADV_GS_COMPUTE_TCS ? nir->info.tess.tcs_vertices_out : 64;
   nir->info.stage = MESA_SHADER_COMPUTE;
   memset(&nir->info.cs, 0, sizeof(nir->info.cs));
   nir->info.workgroup_size[0] = workgroup_size;
   nir->info.workgroup_size[1] = 1;
   nir->info.workgroup_size[2] = 1;
   nir->info.workgroup_size_variable = false;
   /* The vertex and geometry shaders keep the wave size of their own stages. */
   nir->info.min_subgroup_size = 64;
   nir->info.max_subgroup_size = 64;
   NIR_PASS(_, nir, nir_lower_compute_system_values, &compute_sysval_options);
   NIR_PASS(_, nir, nir_lower_global_vars_to_local);
   NIR_PASS(_, nir, ac_nir_lower_indirect_derefs);
   NIR_PASS(_, nir, nir_lower_vars_to_ssa);
   radv_optimize_nir(nir, stage.key.optimisations_disabled);
   nir_shader_gather_info(nir, nir_shader_get_entrypoint(nir));

   radv_nir_shader_info_init(MESA_SHADER_COMPUTE, MESA_SHADER_NONE, &stage.info);
   radv_nir_shader_info_pass(compiler_info, nir, &stage.layout, &stage.key, NULL, RADV_PIPELINE_COMPUTE, false,
                             &stage.info);
   stage.info.gs_compute = kind;
   /* A graphics stage still, whose dynamic buffers' offsets come as a
    * graphics stage's do with independent sets (radv_nir_lower_descriptors),
    * which the pass above only gives graphics stages. */
   if (stage.info.loads_dynamic_offsets && stage.layout.independent_sets)
      stage.info.loads_dynamic_descriptors_offset_addr = true;
   if (kind == RADV_GS_COMPUTE_VS)
      stage.info.vs = vs_info.vs;

   radv_declare_shader_args(compiler_info, NULL, &stage, MESA_SHADER_NONE, debug);
   stage.info.user_sgprs_locs = stage.args.user_sgprs_locs;
   stage.info.inline_push_constant_mask = stage.args.ac.inline_push_const_mask;

   if (kind == RADV_GS_COMPUTE_VS) {
      NIR_PASS(_, nir, radv_nir_lower_vs_inputs, compiler_info, &stage, gfx_state);
      NIR_PASS(_, nir, nir_shader_intrinsics_pass, lower_sw_vs_sysval, nir_metadata_none, NULL);
   }
   radv_gs_compute_lower_sysvals(nir, compiler_info, &stage);
   NIR_PASS(_, nir, nir_lower_compute_system_values, &compute_sysval_options);
   radv_optimize_nir(nir, stage.key.optimisations_disabled);

   radv_postprocess_nir(compiler_info, NULL, &stage);

   struct radv_shader_binary *binary = radv_shader_nir_to_asm(compiler_info, &stage, &nir, 1, NULL);
   radv_shader_dump_asm(compiler_info, debug, binary, &stage.info);
   return binary;
}

struct radv_gs_compute_deferred_vs *
radv_gs_compute_deferred_vs_create(struct radv_device *device, const struct radv_gs_compute_binaries *binaries,
                                   const struct radv_pipeline_layout *layout,
                                   const struct radv_graphics_state_key *gfx_state)
{
   struct radv_gs_compute_deferred_vs *deferred = calloc(1, sizeof(*deferred));
   if (!deferred)
      return NULL;
   deferred->nir = malloc(binaries->vs_nir_size);
   if (!deferred->nir) {
      free(deferred);
      return NULL;
   }
   memcpy(deferred->nir, binaries->vs_nir, binaries->vs_nir_size);
   deferred->nir_size = binaries->vs_nir_size;
   deferred->key = binaries->vs_key;
   deferred->gfx_state = *gfx_state;
   radv_pipeline_layout_init(device, &deferred->layout, layout->independent_sets);
   for (uint32_t s = 0; s < layout->num_sets; s++) {
      if (layout->set[s].layout)
         radv_pipeline_layout_add_set(&deferred->layout, s, layout->set[s].layout);
   }
   simple_mtx_init(&deferred->lock, mtx_plain);
   util_dynarray_init(&deferred->variants, NULL);
   return deferred;
}

void
radv_gs_compute_deferred_vs_destroy(struct radv_device *device, struct radv_gs_compute_deferred_vs *deferred)
{
   if (!deferred)
      return;
   util_dynarray_foreach (&deferred->variants, struct radv_gs_compute_vs_variant, variant)
      radv_shader_unref(device, variant->shader);
   util_dynarray_fini(&deferred->variants);
   simple_mtx_destroy(&deferred->lock);
   radv_pipeline_layout_finish(device, &deferred->layout);
   free(deferred->nir);
   free(deferred);
}

struct radv_shader *
radv_gs_compute_deferred_vs_get(struct radv_device *device, struct radv_gs_compute_deferred_vs *deferred,
                                const struct radv_graphics_state_key *vi_key)
{
   struct radv_shader *shader = NULL;

   simple_mtx_lock(&deferred->lock);
   util_dynarray_foreach (&deferred->variants, struct radv_gs_compute_vs_variant, variant) {
      if (!memcmp(&variant->vi_key.vi, &vi_key->vi, sizeof(vi_key->vi))) {
         shader = variant->shader;
         break;
      }
   }

   if (!shader) {
      const struct radv_compiler_info *compiler_info = &device->compiler_info;
      struct blob_reader reader;
      blob_reader_init(&reader, deferred->nir, deferred->nir_size);
      nir_shader *nir = nir_deserialize(NULL, &compiler_info->nir_options[MESA_SHADER_VERTEX], &reader);

      struct radv_shader_stage stage;
      memset(&stage, 0, sizeof(stage));
      stage.stage = MESA_SHADER_VERTEX;
      stage.next_stage = MESA_SHADER_GEOMETRY;
      stage.entrypoint = "main";
      stage.key = deferred->key;
      radv_shader_layout_init(&deferred->layout, MESA_SHADER_VERTEX, &stage.layout);

      struct radv_graphics_state_key gfx_state = deferred->gfx_state;
      memcpy(&gfx_state.vi, &vi_key->vi, sizeof(gfx_state.vi));
      gfx_state.vs.has_prolog = false;

      struct radv_shader_debug_info debug = {0};
      struct radv_shader_binary *binary =
         radv_gs_compute_compile(compiler_info, &gfx_state, &stage, RADV_GS_COMPUTE_VS, nir, &debug);
      ralloc_free(nir);
      if (binary) {
         shader = radv_shader_create(device, NULL, binary, true, &debug);
         free(binary);
      }
      if (shader) {
         const struct radv_gs_compute_vs_variant variant = {.vi_key = *vi_key, .shader = shader};
         util_dynarray_append(&deferred->variants, variant);
      }
   }
   simple_mtx_unlock(&deferred->lock);
   return shader;
}

VkResult
radv_gs_compute_get_meta_pipeline(struct radv_device *device, enum radv_gs_compute_meta meta,
                                  VkPipeline *pipeline_out, VkPipelineLayout *layout_out)
{
   static const enum radv_meta_object_key_type keys[] = {
      [RADV_GS_COMPUTE_META_SETUP] = RADV_META_OBJECT_KEY_GS_COMPUTE_SETUP,
      [RADV_GS_COMPUTE_META_UNROLL] = RADV_META_OBJECT_KEY_GS_COMPUTE_UNROLL,
      [RADV_GS_COMPUTE_META_PREFIX_SUM] = RADV_META_OBJECT_KEY_GS_COMPUTE_PREFIX_SUM,
      [RADV_GS_COMPUTE_META_TESS_SETUP] = RADV_META_OBJECT_KEY_GS_COMPUTE_TESS_SETUP,
      [RADV_GS_COMPUTE_META_TESS_ISOLINES] = RADV_META_OBJECT_KEY_GS_COMPUTE_TESS_ISOLINES,
      [RADV_GS_COMPUTE_META_TESS_TRIANGLES] = RADV_META_OBJECT_KEY_GS_COMPUTE_TESS_TRIANGLES,
      [RADV_GS_COMPUTE_META_TESS_QUADS] = RADV_META_OBJECT_KEY_GS_COMPUTE_TESS_QUADS,
      [RADV_GS_COMPUTE_META_TESS_PREFIX_SUM] = RADV_META_OBJECT_KEY_GS_COMPUTE_TESS_PREFIX_SUM,
   };
   static const char *const names[] = {
      [RADV_GS_COMPUTE_META_SETUP] = "meta_gs_compute_setup",
      [RADV_GS_COMPUTE_META_UNROLL] = "meta_gs_compute_unroll",
      [RADV_GS_COMPUTE_META_PREFIX_SUM] = "meta_gs_compute_prefix_sum",
      [RADV_GS_COMPUTE_META_TESS_SETUP] = "meta_gs_compute_tess_setup",
      [RADV_GS_COMPUTE_META_TESS_ISOLINES] = "meta_gs_compute_tess_isolines",
      [RADV_GS_COMPUTE_META_TESS_TRIANGLES] = "meta_gs_compute_tess_triangles",
      [RADV_GS_COMPUTE_META_TESS_QUADS] = "meta_gs_compute_tess_quads",
      [RADV_GS_COMPUTE_META_TESS_PREFIX_SUM] = "meta_gs_compute_tess_prefix_sum",
   };
   const enum radv_meta_object_key_type key = keys[meta];
   const VkPushConstantRange pc_range = {
      .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
      .size = sizeof(uint64_t),
   };

   VkResult result = vk_meta_get_pipeline_layout(&device->vk, &device->meta_state.device, NULL, &pc_range, &key,
                                                 sizeof(key), layout_out);
   if (result != VK_SUCCESS)
      return result;

   VkPipeline pipeline_from_cache = vk_meta_lookup_pipeline(&device->meta_state.device, &key, sizeof(key));
   if (pipeline_from_cache != VK_NULL_HANDLE) {
      *pipeline_out = pipeline_from_cache;
      return VK_SUCCESS;
   }

   /* One invocation sets a draw up; the unroll and each prefix sum are one
    * wave (their ballots and scans see the whole workgroup); the tessellator
    * runs one invocation per patch. The push constant is the address of the
    * argument block, of the geometry parameters for the geometry shader's
    * prefix sum, or of the tessellation parameters for the tessellator's. */
   nir_builder b = radv_meta_nir_init_shader(MESA_SHADER_COMPUTE, "%s", names[meta]);
   b.shader->info.workgroup_size[0] =
      meta == RADV_GS_COMPUTE_META_SETUP || meta == RADV_GS_COMPUTE_META_TESS_SETUP ? 1 : RADV_GS_COMPUTE_WAVE;
   nir_def *args = nir_pack_64_2x32(&b, nir_load_push_constant(&b, 2, 32, nir_imm_int(&b, 0), .range = 8));
   switch (meta) {
   case RADV_GS_COMPUTE_META_SETUP:
      radv_gs_compute_setup(&b, args);
      break;
   case RADV_GS_COMPUTE_META_UNROLL:
      radv_gs_compute_unroll(&b, args);
      break;
   case RADV_GS_COMPUTE_META_PREFIX_SUM:
      radv_gs_compute_prefix_sum(&b, args);
      break;
   case RADV_GS_COMPUTE_META_TESS_SETUP:
      radv_gs_compute_tess_setup(&b, args);
      break;
   case RADV_GS_COMPUTE_META_TESS_ISOLINES:
   case RADV_GS_COMPUTE_META_TESS_TRIANGLES:
   case RADV_GS_COMPUTE_META_TESS_QUADS: {
      /* struct radv_gs_compute_tessellate */
      nir_def *params = nir_load_global(&b, 1, 64, args, .align_mul = 8);
      nir_def *mode = nir_load_global(&b, 1, 32, nir_iadd_imm(&b, args, 8), .align_mul = 4);
      if (meta == RADV_GS_COMPUTE_META_TESS_ISOLINES)
         radv_gs_compute_tess_isolines(&b, params, mode);
      else if (meta == RADV_GS_COMPUTE_META_TESS_TRIANGLES)
         radv_gs_compute_tess_triangles(&b, params, mode);
      else
         radv_gs_compute_tess_quads(&b, params, mode);
      break;
   }
   case RADV_GS_COMPUTE_META_TESS_PREFIX_SUM:
      radv_gs_compute_tess_prefix_sum(&b, args);
      break;
   }

   const VkPipelineShaderStageRequiredSubgroupSizeCreateInfo subgroup_size = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_REQUIRED_SUBGROUP_SIZE_CREATE_INFO,
      .requiredSubgroupSize = RADV_GS_COMPUTE_WAVE,
   };
   const VkComputePipelineCreateInfo pipeline_info = {
      .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage =
         {
            .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = &subgroup_size,
            .stage = VK_SHADER_STAGE_COMPUTE_BIT,
            .module = vk_shader_module_handle_from_nir(b.shader),
            .pName = "main",
         },
      .layout = *layout_out,
   };

   result = vk_meta_create_compute_pipeline(&device->vk, &device->meta_state.device, &pipeline_info, &key, sizeof(key),
                                            pipeline_out);
   ralloc_free(b.shader);
   return result;
}
