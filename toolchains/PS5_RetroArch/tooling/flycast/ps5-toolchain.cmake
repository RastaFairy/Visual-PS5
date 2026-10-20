# PS5 RetroArch - cross-compile Flycast's libretro core with this repository's SDK;
# never search host headers or libraries.
# Copyright (C) 2026 Mihawk
# SPDX-License-Identifier: GPL-3.0-or-later
#
# tools/build-flycast.sh passes PS5_CORE_LINK_INPUTS (the core-local destructor
# registry and any objects the core needs beside it) and PS5_EMPTY_LIBS (empty
# libm, librt, libpthread, libdl and libutil archives, whose functions are the
# console's own).
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
# The fork's PS5 changes are under PROSPERO (its CMakeLists.txt) and __PROSPERO__.
set(PROSPERO ON CACHE BOOL "" FORCE)
# Configure-time test programs link like an executable against the console's
# libraries; the core itself is a shared object the title's loader binds.
set(CMAKE_EXE_LINKER_FLAGS_INIT
    "-nostdlib -nostartfiles -nodefaultlibs -Wl,-e,0 -lkernel_web -lSceLibcInternal -lScePosixForWebKit")
set(CMAKE_SHARED_LINKER_FLAGS_INIT
    "-nostdlib -nodefaultlibs -Wl,-z,undefs -Wl,--build-id=sha1 -Wl,-T,${CMAKE_CURRENT_LIST_DIR}/../native/ps5-core.ld ${PS5_CORE_LINK_INPUTS} -L${PS5_EMPTY_LIBS} -lkernel_web -lSceLibcInternal -lScePosixForWebKit")
# Flycast's bundled libzip probes for Annex K and Windows functions; against the
# SDK's archives those probes link, but the title binds none of them at load
# time. libzip's own compat.h covers each one, so the probes are answered no.
foreach(_check
        HAVE_MEMCPY_S HAVE_STRNCPY_S HAVE_STRERROR_S HAVE_STRERRORLEN_S
        HAVE_SNPRINTF_S HAVE_LOCALTIME_S HAVE_CLONEFILE HAVE_EXPLICIT_BZERO
        HAVE_EXPLICIT_MEMSET HAVE_FTS_OPEN HAVE_SETMODE HAVE_STRICMP
        HAVE__CLOSE HAVE__DUP HAVE__FDOPEN HAVE__FILENO HAVE__SETMODE
        HAVE__SNPRINTF HAVE__SNPRINTF_S HAVE__SNWPRINTF_S HAVE__STRDUP
        HAVE__STRICMP HAVE__STRTOI64 HAVE__STRTOUI64 HAVE__UNLINK)
    set(${_check} FALSE CACHE BOOL "" FORCE)
endforeach()
