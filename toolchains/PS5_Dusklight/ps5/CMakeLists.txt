# Dusklight for the PlayStation 5 - the renderer test's build (ps5/tools/build-triangle.sh
# drives it). The game's own build is vendor/dusklight's, with ps5/cmake/ps5-game.cmake.
#
# Configured with the payload SDK's toolchain (toolchain/prospero.cmake).
#
# Stage 1 (PS5_STAGE=triangle): Dawn, Aurora's WebGPU implementation, built for
# the console from .deps/dawn (tools/setup-dawn.sh: the revision Aurora pins,
# with patches/dawn.patch), and a title that draws one triangle through it on
# RADV. tools/link-title.sh links the objects with RADV and packages the title
# folder.
#
# SPDX-License-Identifier: MIT

cmake_minimum_required(VERSION 3.25)
project(ps5_dusklight C CXX)

set(ROOT ${CMAKE_CURRENT_SOURCE_DIR}/..)
# The title's name, from its identity: klog's prefix
file(READ ${CMAKE_CURRENT_SOURCE_DIR}/sce_sys/param.json param_json)
string(JSON PS5_TITLE_NAME GET "${param_json}" localizedParameters en-US titleName)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS sce_sys/param.json)
set(PS5_VULKAN_DIR "${ROOT}/../PS5_Vulkan" CACHE PATH "the PS5_Vulkan checkout (RADV archive, link recipe, packaging)")
set(DAWN_DIR "${ROOT}/.deps/dawn" CACHE PATH "the Dawn checkout (tools/setup-dawn.sh)")
set(PS5_STAGE "triangle" CACHE STRING "what the title is: triangle (Dawn's bring-up)")
if(NOT EXISTS ${DAWN_DIR}/src/dawn/native/CMakeLists.txt)
	message(FATAL_ERROR "no Dawn sources at ${DAWN_DIR}: run ps5/tools/setup-dawn.sh")
endif()

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# -fno-omit-frame-pointer: the console's crash backtraces are frame-pointer walks.
add_compile_options(-O2 -g1 -ffunction-sections -fdata-sections -fno-omit-frame-pointer)

# Dawn: the Vulkan backend alone, on the RADV linked into the title, as one
# static library. No window system: the surface is VK_KHR_display.
set(DAWN_PLATFORM_PS5 ON CACHE INTERNAL "")
set(DAWN_FETCH_DEPENDENCIES OFF CACHE INTERNAL "")
set(DAWN_BUILD_MONOLITHIC_LIBRARY STATIC CACHE INTERNAL "")
set(DAWN_ENABLE_VULKAN ON CACHE INTERNAL "")
foreach(off DAWN_ENABLE_D3D11 DAWN_ENABLE_D3D12 DAWN_ENABLE_METAL DAWN_ENABLE_NULL
		DAWN_ENABLE_DESKTOP_GL DAWN_ENABLE_OPENGLES DAWN_ENABLE_WEBGPU_ON_WEBGPU
		DAWN_USE_X11 DAWN_USE_WAYLAND DAWN_USE_GLFW DAWN_BUILD_SAMPLES DAWN_BUILD_TESTS
		DAWN_BUILD_BENCHMARKS DAWN_BUILD_PROTOBUF DAWN_ENABLE_INSTALL DAWN_WERROR
		DAWN_ENABLE_SPIRV_VALIDATION
		TINT_BUILD_CMD_TOOLS TINT_BUILD_TESTS TINT_BUILD_BENCHMARKS TINT_BUILD_IR_BINARY
		TINT_BUILD_GLSL_WRITER TINT_BUILD_GLSL_VALIDATOR TINT_BUILD_HLSL_WRITER
		TINT_BUILD_MSL_WRITER TINT_BUILD_NULL_WRITER TINT_BUILD_SPV_READER TINT_BUILD_TINTD)
	set(${off} OFF CACHE INTERNAL "")
endforeach()
add_subdirectory(${DAWN_DIR} dawn EXCLUDE_FROM_ALL)

add_library(title OBJECT
	stage1/triangle.cpp
	src/platform.c
	src/shims.c)
target_compile_definitions(title PRIVATE "PS5_TITLE_NAME=\"${PS5_TITLE_NAME}\"")
target_include_directories(title PRIVATE src)
target_link_libraries(title PRIVATE dawn::webgpu_dawn)

# Link, sign and package: the title folder in dist/<TITLE_ID>/
add_custom_command(
	OUTPUT ${CMAKE_BINARY_DIR}/eboot.elf
	COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tools/link-title.sh ${CMAKE_BINARY_DIR} ${PS5_VULKAN_DIR} ${PS5_PAYLOAD_SDK}
		"$<TARGET_OBJECTS:title>" $<TARGET_FILE:webgpu_dawn>
	DEPENDS title "$<TARGET_OBJECTS:title>" webgpu_dawn ${CMAKE_CURRENT_SOURCE_DIR}/tools/link-title.sh
	COMMAND_EXPAND_LISTS
	VERBATIM)
add_custom_target(eboot ALL DEPENDS ${CMAKE_BINARY_DIR}/eboot.elf)
