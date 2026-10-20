/*
 * Copyright © 2016 Red Hat.
 * Copyright © 2016 Bas Nieuwenhuizen
 *
 * based in part on anv driver which is:
 * Copyright © 2015 Intel Corporation
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef RADV_SHADER_OBJECT_H
#define RADV_SHADER_OBJECT_H

#include "radv_gs_compute.h"
#include "radv_shader.h"

struct radv_shader_object {
   struct vk_object_base base;

   mesa_shader_stage stage;

   VkShaderCodeTypeEXT code_type;

   /* Main shader */
   struct radv_shader *shader;
   struct radv_shader_binary *binary;

   /* Shader variants */
   /* VS before TCS */
   struct {
      struct radv_shader *shader;
      struct radv_shader_binary *binary;
   } as_ls;

   /* VS/TES before GS */
   struct {
      struct radv_shader *shader;
      struct radv_shader_binary *binary;
   } as_es;

   /* GS copy shader */
   struct {
      struct radv_shader *copy_shader;
      struct radv_shader_binary *copy_binary;
   } gs;

   uint32_t dynamic_offset_count;

   /* Geometry shaders run as compute (radv_gs_compute.h) where the GPU has no
    * legacy GS. A vertex object that may feed a geometry shader keeps its
    * vertex pass, compiled at the draw for the vertex input, and the mask of
    * the outputs it stores; a geometry object whose shader NGG cannot run
    * here (transform feedback) keeps its passes and its rasterization copy,
    * which a draw binds as the vertex stage. */
   struct {
      struct radv_gs_compute_deferred_vs *vs;
      uint64_t vs_outputs;
      struct radv_gs_compute_pipeline *gs;
      struct radv_shader_binary *binaries[RADV_GS_COMPUTE_SHADERS];
      struct radv_shader *rast;
      struct radv_shader_binary *rast_binary;
      /* A geometry object amplifying past one NGG subgroup, which runs as
       * compute when tessellation feeds it. */
      bool amplifies;
      /* A tessellation control or evaluation object's pass, and the part of
       * the tessellation state its stage fixes. */
      struct radv_shader *tess_pass;
      struct radv_shader_binary *tess_binary;
      struct radv_gs_compute_tess_info tess;
   } gs_compute;
};

VK_DEFINE_NONDISP_HANDLE_CASTS(radv_shader_object, base, VkShaderEXT, VK_OBJECT_TYPE_SHADER_EXT);

#endif /* RADV_SHADER_OBJECT_H */
