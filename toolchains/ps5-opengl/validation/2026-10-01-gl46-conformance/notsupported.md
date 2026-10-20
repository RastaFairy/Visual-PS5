# NotSupported results of run `official3`

Every NotSupported result is covered by one of the rules below.

| Session | Pass | NotSupported | Other |
|---|---:|---:|---:|
| `config-gl30-khr-main-cfg-1-run-0-width-64-height-64-seed-1-egl` | 0 | 1 | 0 |
| `config-gl40-khr-main-cfg-1-run-1-width-64-height-64-seed-1-egl` | 1 | 0 | 0 |
| `config-gl43-khr-main-cfg-1-run-2-width-64-height-64-seed-1-egl` | 0 | 12 | 0 |
| `config-gl45-es3-main-cfg-1-run-0-width-256-height-256-egl` | 1,325 | 0 | 0 |
| `config-gl45-es31-main-cfg-1-run-1-width-256-height-256-egl` | 30,866 | 382 | 0 |
| `config-gl45-khr-main-cfg-1-run-3-width-64-height-64-seed-1-egl` | 2 | 6 | 0 |
| `config-gl46-khr-single-cfg-1-run-3-width-64-height-64-seed-1-egl` | 5,056 | 6,292 | 0 |
| `config-gl46-main-cfg-2-run-0-width-64-height-64-seed-1-egl` | 15,335 | 4,378 | 1 |
| `config-gl46-main-cfg-2-run-1-width-113-height-47-seed-2-egl` | 15,335 | 4,378 | 1 |
| `config-gl46-main-cfg-2-run-2-width-64-height--1-seed-3-egl` | 15,335 | 4,378 | 1 |
| `config-gl46-main-cfg-2-run-3-width--1-height-64-seed-3-egl` | 15,335 | 4,378 | 1 |
| `configs` | 15 | 0 | 0 |

| Class | Cases | Why | Example |
|---|---:|---|---|
| minimum-limit | 18 | needs more than the required minimum MAX_SHADER_STORAGE_BLOCK_SIZE (2^27) | `dEQP-GL45-ES31.functional.draw_indirect.compute_interop.large.drawarrays_combined_grid_1000x1000_drawcount_1` |
| minimum-limit | 12 | the case needs a larger surface than this session's | `KHR-GL46.texture_query_lod.sampler1D_test` |
| minimum-limit | 4 | both limits are at their required minimums (128 and 64) | `KHR-GL46.tessellation_shader.tessellation_shader_tessellation.max_in_out_attributes` |
| minimum-limit | 1 | needs more than the required minimum MAX_GEOMETRY_TOTAL_OUTPUT_COMPONENTS (1024) | `dEQP-GL45-ES31.functional.geometry_shading.basic.output_256` |
| not-applicable | 568 | the case fetches with texelFetch, which GLSL does not define for rectangle (lod) and cube map targets | `KHR-GL46.texture_swizzle.functional_format_idx_0_target_idx_5` |
| not-applicable | 104 | the test excludes depth formats on 3D and multisample targets and RGB9_E5 on multisample targets | `KHR-GL46.texture_swizzle.functional_format_idx_38_target_idx_7` |
| not-applicable | 96 | GLSL defines no textureProj* function for the 2D array target of the smoke test | `KHR-GL46.texture_swizzle.smoke_access_idx_12_channel_idx_0` |
| not-applicable | 64 | the test fetches cull distances only when drawing points | `KHR-GL46.cull_distance.functional_test_item_8_primitive_mode_lines_max_culldist_0` |
| not-applicable | 18 | the sRGB ETC2 formats are supported but, like every Mesa driver, not listed in COMPRESSED_TEXTURE_FORMATS, which the test consults | `dEQP-GL45-ES31.functional.texture.border_clamp.formats.compressed_srgb8_alpha8_etc2_eac.gather_size_not_tile_multiple` |
| not-applicable | 13 | the case applies to OpenGL ES contexts only | `dEQP-GL45-ES31.functional.draw_indirect.negative.client_vertex_attrib_array` |
| not-applicable | 4 | the case applies to OpenGL ES contexts only | `KHR-GL46.draw_elements_base_vertex_tests.valid_active_tf` |
| not-applicable | 4 | RGB9_E5 is not a required color-renderable format | `KHR-GL46.internalformat.renderbuffer.rgb9_e5` |
| optional-extension | 11,800 | ARB_sparse_texture, ARB_sparse_texture2, ARB_sparse_texture_clamp and ARB_sparse_buffer are not part of OpenGL 4.6 | `KHR-GL46.sparse_buffer_tests.BufferStorageTest_case_b1_tf_type_0_draw_call_indexed` |
| optional-extension | 6,053 | KHR_shader_subgroup is not part of OpenGL 4.6 | `KHR-Single-GL46.subgroups.arithmetic.compute.subgroupadd_double` |
| optional-extension | 4,268 | EXT_fragment_shading_rate is not part of OpenGL 4.6 | `KHR-GL46.fragment_shading_rate.api.basic` |
| optional-extension | 239 | EXT_mesh_shader is not part of OpenGL 4.6 | `KHR-Single-GL46.meshShader.apiTests.draw.draw_count_0.no_indirect_args.no_count_limit.no_count_offset.no_task_shader` |
| optional-extension | 120 | tests of ARB_sparse_texture2 and EXT_texture_shadow_lod built-ins | `KHR-GL46.negative_texture_lookup_functions_with_bias_tests.sparseTextureARB_isampler2DArray_bias` |
| optional-extension | 60 | EXT_texture_shadow_lod is not part of OpenGL 4.6 | `KHR-GL46.ext_texture_shadow_lod.texture.sampler2darrayshadow_bias_fragment` |
| optional-extension | 48 | the cases require the ARB_depth_texture extension string, which a core profile does not list | `KHR-GL46.internalformat.copy_tex_image.depth_component16` |
| optional-extension | 47 | EXT_shader_framebuffer_fetch is not part of OpenGL 4.6 | `dEQP-GL45-ES31.functional.debug.negative_coverage.callbacks.framebuffer_fetch.invalid_inout_version` |
| optional-extension | 39 | KHR_blend_equation_advanced(_coherent) is not part of OpenGL 4.6 | `dEQP-GL45-ES31.functional.blend_equation_advanced.coherent.colorburn` |
| optional-extension | 30 | EXT_texture_sRGB_R8 and EXT_texture_sRGB_RG8 are not part of OpenGL 4.6 | `dEQP-GL45-ES31.functional.srgb_texture_decode.skip_decode.sr8.conversion_gpu` |
| optional-extension | 20 | ARB_texture_filter_minmax is not part of OpenGL 4.6 | `KHR-GL46.texture_filter_minmax_tests.TextureFilterMinmaxMagnificationFiltering` |
| optional-extension | 12 | ARB_shader_viewport_layer_array is not part of OpenGL 4.6 | `KHR-GL46.shader_viewport_layer_array.ShaderLayerFramebufferLayeredTestCase` |
| optional-extension | 8 | ARB_post_depth_coverage is not part of OpenGL 4.6 | `KHR-GL46.post_depth_coverage_tests.PostDepthSampleMask` |
| optional-extension | 4 | the case tests the EXT_shader_integer_mix extension string; the functionality itself is GLSL 4.50 and tested by the other cases | `KHR-GL46.shaders.shader_integer_mix.prototypes` |
| sample-count | 522 | the case needs more samples than the implementation's maximum of 4 (OpenGL 4.6 requires MAX_SAMPLES >= 4, integer formats >= 1) | `dEQP-GL45-ES31.functional.sample_shading.min_sample_shading.multisample_renderbuffer_samples_16_color` |
| sample-count | 10 | the session's default framebuffer config is single-sampled | `dEQP-GL45-ES31.functional.multisample.default_framebuffer.constancy_alpha_to_coverage_sample_coverage_sample_mask` |
| surface-type | 19 | the case creates its own window-surface context; the conformant EGL config renders to pbuffers | `KHR-NoContext.gl30.no_error.create_context` |
