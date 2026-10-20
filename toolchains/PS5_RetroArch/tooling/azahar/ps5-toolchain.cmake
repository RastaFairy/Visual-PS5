# PS5 RetroArch - cross-compile Azahar's libretro core with this repository's SDK;
# never search host headers or libraries.
# Copyright (C) 2026 Mihawk
# SPDX-License-Identifier: GPL-3.0-or-later
#
# tools/build-azahar.sh passes PS5_CORE_LINK_INPUTS (the core-local destructor
# registry) and PS5_EMPTY_LIBS (a directory of empty libm, librt, libpthread and
# libdl archives, whose functions are the console's own).
set(CMAKE_SYSTEM_NAME FreeBSD)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER "$ENV{PS5_PAYLOAD_SDK}/bin/prospero-clang")
set(CMAKE_CXX_COMPILER "$ENV{PS5_PAYLOAD_SDK}/bin/prospero-clang++")
set(CMAKE_AR "$ENV{PS5_PAYLOAD_SDK}/bin/prospero-ar")
set(CMAKE_RANLIB "$ENV{PS5_PAYLOAD_SDK}/bin/prospero-ranlib")
set(CMAKE_FIND_ROOT_PATH "$ENV{PS5_PAYLOAD_SDK}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# Configure-time test programs link like an executable against the console's
# libraries; the core itself is a shared object the title's loader binds.
set(CMAKE_EXE_LINKER_FLAGS_INIT
    "-nostdlib -nostartfiles -nodefaultlibs -Wl,-e,0 -lkernel_web -lSceLibcInternal -lScePosixForWebKit")
set(CMAKE_SHARED_LINKER_FLAGS_INIT
    "-nostdlib -nodefaultlibs -Wl,-z,undefs -Wl,--build-id=sha1 -Wl,-T,${CMAKE_CURRENT_LIST_DIR}/../native/ps5-core.ld ${PS5_CORE_LINK_INPUTS} -L${PS5_EMPTY_LIBS} -lkernel_web -lSceLibcInternal -lScePosixForWebKit")
