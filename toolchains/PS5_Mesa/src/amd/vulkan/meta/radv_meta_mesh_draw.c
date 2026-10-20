/*
 * Copyright © 2026 Valve Corporation
 *
 * SPDX-License-Identifier: MIT
 */
#include "nir/radv_meta_nir.h"
#include "radv_cmd_buffer.h"
#include "radv_meta.h"
#include "vk_shader_module.h"

static VkResult
get_pipeline(struct radv_device *device, enum radv_meta_object_key_type key, uint32_t push_constant_bytes,
             nir_shader *(*build)(void), VkPipeline *pipeline_out, VkPipelineLayout *layout_out)
{
   VkResult result;

   const VkPushConstantRange pc_range = {
      .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
      .size = push_constant_bytes,
   };

   result = vk_meta_get_pipeline_layout(&device->vk, &device->meta_state.device, NULL, &pc_range, &key, sizeof(key),
                                        layout_out);
   if (result != VK_SUCCESS)
      return result;

   VkPipeline pipeline_from_cache = vk_meta_lookup_pipeline(&device->meta_state.device, &key, sizeof(key));
   if (pipeline_from_cache != VK_NULL_HANDLE) {
      *pipeline_out = pipeline_from_cache;
      return VK_SUCCESS;
   }

   nir_shader *cs = build();

   const VkPipelineShaderStageCreateInfo stage_info = {
      .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
      .stage = VK_SHADER_STAGE_COMPUTE_BIT,
      .module = vk_shader_module_handle_from_nir(cs),
      .pName = "main",
   };

   const VkComputePipelineCreateInfo pipeline_info = {
      .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = stage_info,
      .layout = *layout_out,
   };

   result = vk_meta_create_compute_pipeline(&device->vk, &device->meta_state.device, &pipeline_info, &key, sizeof(key),
                                            pipeline_out);

   ralloc_free(cs);
   return result;
}

/* The records of an indirect mesh shader draw without DISPATCH_MESH_INDIRECT_MULTI
 * (radv_mesh_draw_records_enabled), written from its commands before the draw reads them.
 * publish_ring is the publish ring's address for a shader that publishes its outputs
 * (radv_ms_publishes), 0 otherwise. An emulated task draw's chunk (radv_task_emulated)
 * names where they go (records_va), its task rings and the task draw; otherwise records_va
 * is 0 and they go to the upload buffer. Returns their address, 0 on failure.
 */
uint64_t
radv_meta_mesh_draw_records(struct radv_cmd_buffer *cmd_buffer, uint64_t indirect_va, uint32_t stride,
                            uint64_t count_va, uint32_t max_count, uint32_t parts, uint64_t publish_ring,
                            uint64_t records_va, uint32_t task_rings, uint32_t task_draw_id)
{
   struct radv_device *device = radv_cmd_buffer_device(cmd_buffer);
   VkPipelineLayout layout;
   VkPipeline pipeline;
   uint32_t offset;

   /* The commands' buffer holds max_count of them, so this is bounded by it. */
   if (!records_va) {
      const uint64_t size = (uint64_t)max_count * sizeof(struct radv_mesh_draw_record);
      if (size > UINT32_MAX || !radv_cmd_buffer_upload_alloc_aligned(cmd_buffer, size, 16, &offset, NULL)) {
         vk_command_buffer_set_error(&cmd_buffer->vk, VK_ERROR_OUT_OF_DEVICE_MEMORY);
         return 0;
      }
      records_va = radv_buffer_get_va(cmd_buffer->upload.upload_bo) + offset;
   }

   VkResult result = get_pipeline(device, RADV_META_OBJECT_KEY_MESH_DRAW_RECORDS, 48,
                                  radv_meta_nir_build_mesh_draw_records_cs, &pipeline, &layout);
   if (result != VK_SUCCESS) {
      vk_command_buffer_set_error(&cmd_buffer->vk, result);
      return 0;
   }

   radv_meta_begin(cmd_buffer);
   radv_meta_save(cmd_buffer, RADV_META_SAVE_COMPUTE_PIPELINE | RADV_META_SAVE_CONSTANTS);

   radv_meta_bind_compute_pipeline(cmd_buffer, pipeline);

   /* The ring is in the 32-bit window. */
   assert(publish_ring >> 32 == 0 || (publish_ring >> 32) == radv_device_physical(device)->info.address32_hi);
   const uint32_t constants[12] = {
      indirect_va,    indirect_va >> 32, records_va, records_va >> 32, count_va,   count_va >> 32,
      stride,         max_count,         parts,      publish_ring,     task_rings, task_draw_id,
   };
   radv_meta_push_constants(cmd_buffer, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(constants), constants);

   /* With a ring, one workgroup goes through the draws in order. */
   radv_unaligned_dispatch(cmd_buffer, publish_ring ? 32 : max_count, 1, 1);

   radv_meta_end(cmd_buffer);

   /* The command processor reads the draws, the mesh shader the grids. */
   cmd_buffer->state.flush_bits |= RADV_CMD_FLAG_CS_PARTIAL_FLUSH | RADV_CMD_FLAG_INV_VCACHE | RADV_CMD_FLAG_INV_SCACHE;

   return records_va;
}

/* An emulated indirect task draw's chunks (radv_task_emulated), for draws
 * draws from first_draw, of chunks chunks of up to entries task workgroups
 * each: at out_va, a radv_task_emu_block a chunk, then the chunks' dispatch
 * workgroups (x, 1, 1, 0), x being the chunk's count of workgroups, 0 past
 * its draw's.
 */
void
radv_meta_task_chunks(struct radv_cmd_buffer *cmd_buffer, uint64_t indirect_va, uint32_t stride, uint64_t count_va,
                      uint32_t first_draw, uint32_t draws, uint32_t chunks, uint32_t entries, uint64_t out_va)
{
   struct radv_device *device = radv_cmd_buffer_device(cmd_buffer);
   VkPipelineLayout layout;
   VkPipeline pipeline;

   VkResult result = get_pipeline(device, RADV_META_OBJECT_KEY_TASK_CHUNKS, 44, radv_meta_nir_build_task_chunks_cs,
                                  &pipeline, &layout);
   if (result != VK_SUCCESS) {
      vk_command_buffer_set_error(&cmd_buffer->vk, result);
      return;
   }

   radv_meta_begin(cmd_buffer);
   radv_meta_save(cmd_buffer, RADV_META_SAVE_COMPUTE_PIPELINE | RADV_META_SAVE_CONSTANTS);

   radv_meta_bind_compute_pipeline(cmd_buffer, pipeline);

   const uint32_t constants[11] = {
      indirect_va, indirect_va >> 32, count_va, count_va >> 32, out_va, out_va >> 32, stride, draws, chunks, entries,
      first_draw,
   };
   radv_meta_push_constants(cmd_buffer, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(constants), constants);

   radv_unaligned_dispatch(cmd_buffer, draws * chunks, 1, 1);

   radv_meta_end(cmd_buffer);

   /* The command processor reads the dispatches, the task shader the blocks. */
   cmd_buffer->state.flush_bits |= RADV_CMD_FLAG_CS_PARTIAL_FLUSH | RADV_CMD_FLAG_INV_VCACHE | RADV_CMD_FLAG_INV_SCACHE;
}
