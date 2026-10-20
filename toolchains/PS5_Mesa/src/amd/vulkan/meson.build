# Copyright © 2017 Intel Corporation
# SPDX-License-Identifier: MIT

radv_tracepoints = custom_target(
  'radv_tracepoints.[ch]',
  input: ['radv_tracepoints.py', vk_api_xml],
  output: ['radv_tracepoints.c', 'radv_entrypoint_tracepoints.c', 'radv_tracepoints_perfetto.h', 'radv_tracepoints.h'],
  command: [
    prog_python, '@INPUT0@',
    '--import-path', mesa_python_path,
    '--src','@OUTPUT0@',
    '--entrypoints-src', '@OUTPUT1@',
    '--perfetto-hdr', '@OUTPUT2@',
    '--hdr', '@OUTPUT3@',
    '--xml', '@INPUT1@',
  ],
  depend_files: u_trace_py,
)

idep_radv_tracepoints = declare_dependency(
  sources: radv_tracepoints,
)

radv_entrypoints_gen_command = [
  prog_python, '@INPUT0@', '--xml', '@INPUT1@', '--proto', '--weak',
  '--out-h', '@OUTPUT0@', '--out-c', '@OUTPUT1@',
  '--beta', with_vulkan_beta.to_string()
]

radv_entrypoints_gen_command += [
  # RADV entrypooints
  '--prefix', 'radv',

  # Tracing layer entrypoints
  '--device-prefix', 'sqtt',
  '--device-prefix', 'rra',
  '--device-prefix', 'rmv',
  '--device-prefix', 'ctx_roll',
  '--device-prefix', 'utrace',

  # Command buffer annotation layer entrypoints
  '--device-prefix', 'annotate',

  # Threaded recording layer entrypoints
  '--device-prefix', 'threaded',
]

radv_entrypoints = custom_target(
  'radv_entrypoints',
  input : [vk_entrypoints_gen, vk_api_xml],
  output : ['radv_entrypoints.h', 'radv_entrypoints.c'],
  command : radv_entrypoints_gen_command,
  depend_files : vk_entrypoints_gen_depend_files,
)

radv_drirc = custom_target(
  'radv_drirc',
  input  : [files('radv_drirc_gen.py'), drirc_gen, '00-radv-defaults.conf'],
  output : ['radv_drirc.c', 'radv_drirc.h'],
  command : [
    prog_python, '@INPUT0@',
    '--import-path', join_paths(dir_source_root, 'src/util'),
    '--drirc-src', '@OUTPUT0@',
    '--drirc-hdr', '@OUTPUT1@',
    '--validate', '@INPUT2@',
  ],
)

libradv_files = files(
  'bvh/bvh_defines.h',
  'layers/radv_app_workarounds.c',
  'layers/radv_ctx_roll_layer.c',
  'layers/radv_rmv_layer.c',
  'layers/radv_rra_layer.c',
  'layers/radv_sqtt_layer.c',
  'layers/radv_threaded_layer.c',
  'layers/radv_threaded_layer.h',
  'layers/radv_utrace_layer.c',
  'meta/radv_meta.c',
  'meta/radv_meta.h',
  'meta/radv_meta_astc_decode.c',
  'meta/radv_meta_blit.c',
  'meta/radv_meta_blit2d.c',
  'meta/radv_meta_buffer.c',
  'meta/radv_meta_bufimage.c',
  'meta/radv_meta_clear.c',
  'meta/radv_meta_clear_hiz.c',
  'meta/radv_meta_copy.c',
  'meta/radv_meta_copy_indirect_cs.c',
  'meta/radv_meta_mesh_draw.c',
  'meta/radv_meta_copy_indirect_fs.c',
  'meta/radv_meta_copy_vrs_htile.c',
  'meta/radv_meta_dcc_retile.c',
  'meta/radv_meta_decompress.c',
  'meta/radv_meta_etc_decode.c',
  'meta/radv_meta_fast_clear.c',
  'meta/radv_meta_fmask_copy.c',
  'meta/radv_meta_fmask_expand.c',
  'meta/radv_meta_resolve.c',
  'meta/radv_meta_resolve_cs.c',
  'meta/radv_meta_resolve_fs.c',
  'nir/radv_meta_nir.c',
  'nir/radv_meta_nir.h',
  'nir/radv_nir.h',
  'nir/radv_nir_export_multiview.c',
  'nir/radv_nir_lower_abi.c',
  'nir/radv_nir_lower_call_abi.c',
  'nir/radv_nir_lower_cooperative_matrix.c',
  'nir/radv_nir_lower_descriptors.c',
  'nir/radv_nir_lower_fs_barycentric.c',
  'nir/radv_nir_lower_fs_vertex_order.c',
  'nir/radv_nir_lower_fs_intrinsics.c',
  'nir/radv_nir_lower_hit_attrib_derefs.c',
  'nir/radv_nir_lower_immediate_samplers.c',
  'nir/radv_nir_lower_intrinsics_early.c',
  'nir/radv_nir_lower_io.c',
  'nir/radv_nir_lower_opt_fs_frag_pos.c',
  'nir/radv_nir_lower_primitive_shading_rate.c',
  'nir/radv_nir_lower_printf.c',
  'nir/radv_nir_lower_ray_queries.c',
  'nir/radv_nir_lower_vs_inputs.c',
  'nir/radv_nir_opt_fs_builtins.c',
  'nir/radv_nir_opt_tid_function.c',
  'nir/radv_nir_remap_color_attachment.c',
  'nir/radv_nir_rt_common.c',
  'nir/radv_nir_rt_stage_common.c',
  'nir/radv_nir_rt_stage_cps.c',
  'nir/radv_nir_rt_stage_functions.c',
  'nir/radv_nir_rt_stage_monolithic.c',
  'nir/radv_nir_rt_traversal_shader.c',
  'nir/radv_nir_trim_fs_color_exports.c',
  'tools/radv_debug_hang.c',
  'tools/radv_debug_hang.h',
  'tools/radv_debug_nir.c',
  'tools/radv_debug_nir.h',
  'tools/radv_debug.c',
  'tools/radv_debug.h',
  'tools/radv_rmv.c',
  'tools/radv_rmv.h',
  'tools/radv_rra_gfx10_3.c',
  'tools/radv_rra_gfx12.c',
  'tools/radv_rra.c',
  'tools/radv_rra.h',
  'tools/radv_spm.c',
  'tools/radv_spm.h',
  'tools/radv_sqtt.c',
  'tools/radv_sqtt.h',
  'radv_acceleration_structure.c',
  'radv_android.c',
  'radv_android.h',
  'radv_buffer.c',
  'radv_buffer.h',
  'radv_buffer_view.c',
  'radv_buffer_view.h',
  'radv_cmd_buffer.c',
  'radv_cmd_buffer.h',
  'radv_cp_dma.c',
  'radv_cp_dma.h',
  'radv_cp_reg_shadowing.c',
  'radv_cp_reg_shadowing.h',
  'radv_cs.c',
  'radv_cs.h',
  'radv_device.c',
  'radv_device.h',
  'radv_device_memory.c',
  'radv_device_memory.h',
  'radv_descriptors.c',
  'radv_descriptors.h',
  'radv_descriptor_pool.c',
  'radv_descriptor_pool.h',
  'radv_descriptor_set.c',
  'radv_descriptor_set.h',
  'radv_descriptor_update_template.c',
  'radv_descriptor_update_template.h',
  'radv_dgc.c',
  'radv_dgc.h',
  'radv_event.c',
  'radv_event.h',
  'radv_formats.c',
  'radv_formats.h',
  'radv_host_image_copy.c',
  'radv_image.c',
  'radv_image.h',
  'radv_image_view.c',
  'radv_image_view.h',
  'radv_instance.c',
  'radv_instance.h',
  'radv_perfcounter.c',
  'radv_physical_device.c',
  'radv_pipeline.c',
  'radv_pipeline.h',
  'radv_pipeline_binary.c',
  'radv_pipeline_binary.h',
  'radv_pipeline_cache.c',
  'radv_pipeline_cache.h',
  'radv_pipeline_compute.c',
  'radv_pipeline_compute.h',
  'radv_pipeline_graphics.c',
  'radv_pipeline_layout.c',
  'radv_pipeline_layout.h',
  'radv_pipeline_rt.c',
  'radv_pipeline_rt.h',
  'radv_queue.c',
  'radv_queue.h',
  'radv_radeon_winsys.h',
  'radv_sampler.c',
  'radv_sampler.h',
  'radv_sdma.c',
  'radv_sdma.h',
  'radv_shader.c',
  'radv_shader.h',
  'radv_shader_args.c',
  'radv_shader_args.h',
  'radv_shader_info.c',
  'radv_shader_info.h',
  'radv_shader_object.c',
  'radv_shader_object.h',
  'radv_query.c',
  'radv_query.h',
  'radv_video.c',
  'radv_video.h',
  'radv_video_enc.c',
  'radv_wsi.c',
  'radv_wsi.h',
)

if with_radv_ps5
  libradv_files += files(
    'winsys/ps5/radv_ps5_bo.c',
    'winsys/ps5/radv_ps5_cs.c',
    'winsys/ps5/radv_ps5_platform.c',
    'winsys/ps5/radv_ps5_platform.h',
    'winsys/ps5/radv_ps5_sync.c',
    'winsys/ps5/radv_ps5_winsys.c',
    'winsys/ps5/radv_ps5_winsys.h',
    'winsys/ps5/radv_ps5_winsys_public.h',
  )
elif not with_platform_windows
  libradv_files += files(
    'winsys/amdgpu/radv_amdgpu_bo.c',
    'winsys/amdgpu/radv_amdgpu_bo.h',
    'winsys/amdgpu/radv_amdgpu_cs.c',
    'winsys/amdgpu/radv_amdgpu_cs.h',
    'winsys/amdgpu/radv_amdgpu_winsys.c',
    'winsys/amdgpu/radv_amdgpu_winsys.h',
    'winsys/amdgpu/radv_amdgpu_winsys_public.h',
  )
endif

if amd_with_llvm
  libradv_files += files(
    'radv_llvm_helper.cpp',
    'radv_llvm_helper.h',
    'radv_nir_to_llvm.c',
    'radv_nir_to_llvm.h',
  )
endif

subdir('bvh')

subdir('layers')

radv_deps = []
radv_flags = cc.get_supported_arguments(['-Wimplicit-fallthrough', '-Wshadow'])

if with_amdgpu_virtio
  radv_flags += '-DHAVE_AMDGPU_VIRTIO'
endif

if with_platform_x11
  radv_deps += dep_xcb_dri3
endif

if with_platform_wayland
  radv_deps += dep_wayland_client
endif

if with_xlib_lease
  radv_deps += [dep_xlib_xrandr]
endif

if with_platform_android
  radv_deps += dep_android
endif

radv_build_id = get_option('radv-build-id')
if radv_build_id != ''
  radv_flags += '-DRADV_BUILD_ID_OVERRIDE="' + radv_build_id + '"'
endif

# The PS5 RADV runs the geometry shaders NGG cannot as compute, with poly
# (docs/RADV_GS_COMPUTE.md in PS5_Vulkan).
radv_link_with = []
if with_radv_ps5
  # poly's bindings are compiled into libpoly_nir: RADV needs only their header.
  radv_deps += declare_dependency(sources : [libpoly_shaders[1]])
  radv_link_with += libpoly_nir
  radv_flags += '-DRADV_GS_COMPUTE=1'
  libradv_files += files('radv_gs_compute.c', 'radv_gs_compute.h', 'radv_gs_compute_abi.h')

  # RADV's own OpenCL helpers for them, NIR builder functions as poly's are.
  # Without shader asserts: RADV gives these no printf buffer.
  libradv_cl_spv = custom_target(
    input : files('cl/radv_gs_compute.cl'),
    output : 'libradv_cl.spv',
    command : [
      prog_mesa_clc, '-o', '@OUTPUT@', '--depfile', '@DEPFILE@', '@INPUT@', '--',
      '-I' + join_paths(meson.project_source_root(), 'include'),
      '-I' + join_paths(meson.project_source_root(), 'src/compiler/libcl'),
      '-I' + join_paths(meson.project_source_root(), 'src'),
      '-I' + meson.current_source_dir(),
      cl_args, '-DNDEBUG',
    ],
    depfile : 'libradv_cl.spv.d',
  )
  libradv_cl = custom_target(
    input : libradv_cl_spv,
    output : ['libradv_cl.cpp', 'libradv_cl.h'],
    command : [prog_vtn_bindgen2, '@INPUT@', '@OUTPUT0@', '@OUTPUT1@'],
  )
  libradv_files += libradv_cl
endif

radv_u_trace = get_option('radv-u_trace')
if radv_u_trace
  radv_flags += '-DRADV_U_TRACE=1'
endif

_radv_target = {
  'include_directories' : [
    inc_include, inc_src, inc_amd, inc_amd_common, inc_amd_common_llvm,
    inc_util, inc_virtio_gpu
  ],
  'link_with' : [
    libamd_common, libamd_common_llvm, libamdgpu_addrlib, radv_link_with,
  ],
  'dependencies' : [
    dep_llvm, dep_libdrm_amdgpu, dep_thread, dep_elf, dep_dl, dep_m,
    dep_valgrind, radv_deps, idep_aco,
    idep_mesautil, idep_nir, idep_vulkan_util, idep_vulkan_wsi,
    idep_vulkan_runtime, idep_amd_generated_headers, idep_xmlconfig,
    idep_radv_tracepoints,
  ],
  'c_args' : [no_override_init_args, radv_flags, c_msvc_compat_args],
  'cpp_args' : [radv_flags, cpp_msvc_compat_args],
  'gnu_symbol_visibility' : 'hidden',
  'install' : true,
}
_radv_sources = [libradv_files, radv_entrypoints, radv_drirc, sha1_h, radix_sort_spv, bvh_spv, radv_annotate_layer, radv_threaded_layer]

# A PS5 title cannot load a shared library, so the console build is an archive
# the title links; the host build of the PS5 winsys stays a loadable ICD.
if with_radv_ps5 and get_option('default_library') == 'static'
  # zlib, which the shader cache compresses with, comes from its subproject
  # for the console and installs as an archive of its own: the title links one.
  _radv_whole = []
  if dep_zlib.found() and dep_zlib.type_name() == 'internal'
    _radv_whole += subproject('zlib').get_variable('zlib')
  endif
  libvulkan_radeon = static_library('vulkan_radeon', _radv_sources, kwargs : _radv_target,
                                    link_whole : _radv_whole)
else
  libvulkan_radeon = shared_library(
    'vulkan_radeon',
    _radv_sources,
    vs_module_defs : vulkan_api_def,
    link_args : [
      ld_args_build_id, ld_args_bsymbolic, ld_args_gc_sections, vulkan_icd_link_args,
    ],
    link_depends : vulkan_icd_link_depends,
    name_prefix : host_machine.system() == 'windows' ? '' : [],
    kwargs : _radv_target,
  )
endif

if with_symbols_check
  test(
    'radv symbols check',
    symbols_check,
    args : [
      '--lib', libvulkan_radeon,
      '--symbols-file', vulkan_icd_symbols,
      '--ignore-symbol', 'ac_init_shared_llvm_once',
      symbols_check_args,
    ],
    suite : ['amd'],
  )
endif

icd_file_name = libname_prefix + 'vulkan_radeon.' + libname_suffix

icd_command = [
  prog_python, '@INPUT0@',
  '--api-version', '1.4', '--xml', '@INPUT1@',
  '--sizeof-pointer', sizeof_pointer,
  '--icd-lib-path', vulkan_icd_lib_path,
  '--icd-filename', icd_file_name,
  '--out', '@OUTPUT@',
]
if with_platform_windows
  icd_command += '--use-backslash'
endif

radeon_icd = custom_target(
  'radeon_icd',
  input : [vk_icd_gen, vk_api_xml],
  output : 'radeon_icd.' + vulkan_manifest_suffix,
  command : icd_command,
  build_by_default : true,
  install_dir : with_vulkan_icd_dir,
  install_tag : 'runtime',
  install : true,
)

_dev_icdname = 'radeon_devenv_icd.@0@.json'.format(host_machine.cpu())
_dev_icd = custom_target(
  'radeon_devenv_icd',
  input : [vk_icd_gen, vk_api_xml],
  output : _dev_icdname,
  command : [
    prog_python, '@INPUT0@',
    '--api-version', '1.4', '--xml', '@INPUT1@',
    '--sizeof-pointer', sizeof_pointer,
    '--icd-lib-path', meson.current_build_dir(),
    '--icd-filename', icd_file_name,
    '--out', '@OUTPUT@',
  ],
  build_by_default : true,
)

devenv.append('VK_DRIVER_FILES', _dev_icd.full_path())

if with_radv_tests
  test(
    'radv_tests',
    executable(
      'radv_tests',
      files(
        'nir/radv_nir_lower_hit_attrib_derefs.c',
        'tests/radv_nir_lower_hit_attrib_derefs_tests.cpp',
        'tests/helpers.cpp',
        'tests/helpers.h',
        'tests/drirc.cpp',
        'tests/misc.cpp',
      ),
      cpp_args : [cpp_msvc_compat_args],
      gnu_symbol_visibility : 'hidden',
      include_directories : [
        inc_include,
        inc_src,
        inc_amd,
        inc_amd_common,
        inc_compiler,
        inc_util,
        include_directories('.'),
      ],
      link_with  : [ libamd_common, libvulkan_radeon, libamdgpu_noop_drm_shim ],
      dependencies : [dep_llvm, dep_thread, idep_gtest, idep_nir, idep_mesautil, idep_vulkan_util_headers],
    ),
    suite : ['compiler', 'nir'],
    protocol : 'gtest',
    env : [
      'LD_PRELOAD=@0@'.format(libamdgpu_noop_drm_shim.full_path()),
      'AMDGPU_GPU_ID=navi21',
    ],
  )
endif
