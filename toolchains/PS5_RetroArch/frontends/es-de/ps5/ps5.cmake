# PS5 RetroArch - EmulationStation's dependencies on the PS5 (frontends/es-de).
#
# Copyright (C) 2026 Mihawk
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Included by ES-DE's CMakeLists.txt in place of its find_package() calls when
# the PS5 toolchain is used (patches/0001). Every dependency is a static archive
# this project builds (tools/build-*.sh into .deps/native/<name>-ps5), plus SDL2
# and OpenGL from ../PS5_OpenGL; tools/build-esde.sh passes their prefixes.
# Only include paths are given here: the executable is linked by
# tools/build-frontend.sh, which names the archives.

foreach(prefix PS5_PORT_DIR PS5_DEPS PS5_SDL2 PS5_GL_SDK PS5_STB)
    if(NOT ${prefix} OR NOT EXISTS ${${prefix}})
        message(FATAL_ERROR "PS5: ${prefix} must name an existing directory (tools/build-esde.sh sets it)")
    endif()
endforeach()

set(CURL_INCLUDE_DIR ${PS5_DEPS}/curl-ps5/include)
set(PS5_INCLUDE_DIRS
    ${PS5_PORT_DIR}/include
    ${PS5_PORT_DIR}/../../../src
    ${PS5_STB}
    ${PS5_DEPS}/ffmpeg-esde-ps5/include
    ${PS5_DEPS}/freetype-ps5/include/freetype2
    ${PS5_DEPS}/harfbuzz-ps5/include
    ${PS5_DEPS}/harfbuzz-ps5/include/harfbuzz
    ${PS5_DEPS}/icu-ps5/include
    ${PS5_DEPS}/pugixml-ps5/include
    ${PS5_SDL2}/include
    ${PS5_SDL2}/include/SDL2
    ${PS5_GL_SDK}/include)

# The archives are static: ICU's and curl's headers must not ask for imports.
add_compile_definitions(U_STATIC_IMPLEMENTATION CURL_STATICLIB)
