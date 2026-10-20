/*
 * ps5-native-app-boilerplate - Native PS5 dynamic-module writer interface.
 * Copyright (C) 2026 BlackBearReloaded
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Declares conversion of an ordinary LLVM-linked PIE into the PS5 application
 * ELF layout consumed by the FSELF wrapper.
 */

#pragma once

#include "elf_object.hpp"

#include <cstdint>
#include <limits>
#include <span>
#include <string>
#include <vector>

namespace ps5::module
{

struct Options
{
    std::string entry = "_start";
    std::string file_name = "eboot.elf";
    std::uint32_t module_sdk = 0x02000009;
    std::uint32_t companion_sdk = 0x08050001;
    /* The libc heap the process parameters reserve: the most there is, unless a
     * program that keeps its memory elsewhere (an OpenGL frontend) asks for less. */
    std::uint64_t libc_heap_size = std::numeric_limits<std::uint64_t>::max();
    /* The modules the system preloads for the process (its process parameters'
     * pointer at 0x50): 0 leaves the pointer out and the system's full default list,
     * VideoOut included. A headless helper asks for less (0x8000000000000002: libc
     * only), as ../PS5_Proton measured for Sony's local processes. */
    std::uint64_t preload_prx_flags = 0;
    std::vector<std::string> version_components;
};

[[nodiscard]] elf::Bytes write_executable(const elf::Image &image, std::span<const elf::Stub> stubs,
                                          const Options &options = {});

} // namespace ps5::module
