# Licences

The repository as a whole, and any title built from it, is offered under the GNU
General Public License, version 3 ([`LICENSE`](LICENSE)). Its files come from
projects under several licences, each compatible with that; every source file
names its own in its header, and may also be used under that licence alone.

| Path | Licence | Text |
| --- | --- | --- |
| `ps5/tools/png-to-title-dds.py` (encoder from PS5 RetroArch, by Mihawk) | GPL-3.0-or-later | [`licenses/GPL-3.0.txt`](licenses/GPL-3.0.txt) |
| `ps5/src/platform.c`, `ps5/src/platform.h` and the tools taken from the PS5 Vulkan Template (by Mihawk) | MIT | [`licenses/MIT.txt`](licenses/MIT.txt) |
| The rest of `ps5/src/`, `ps5/tools/`, `ps5/cmake/` and `ps5/art/*.sh` (written for this port and the ports before it) | MIT | [`licenses/MIT.txt`](licenses/MIT.txt) |
| `ps5/sdl/` (SDL2 drivers for the console) and `ps5/patches/sdl.patch` | Zlib, as SDL | [`licenses/Zlib.txt`](licenses/Zlib.txt) |
| `ps5/third_party/volk/` | MIT | `ps5/third_party/volk/LICENSE.md` |
| `ps5/patches/ghostship.patch`, `libultraship.patch`, `torch.patch` | MIT, as the projects they change | in each project's source |
| The icon and the background | made for this port | |

## What is built from elsewhere

Nothing below is stored in this repository; the build takes each from its own
project, under that project's licence.

| Part | Project | Licence |
| --- | --- | --- |
| The game's code | [Ghostship](https://github.com/HarbourMasters/Ghostship), which compiles the [Super Mario 64 decompilation](https://github.com/n64decomp/sm64) | MIT; CC0-1.0 |
| The N64 layer and renderer | [libultraship](https://github.com/Kenix3/libultraship) | MIT |
| The ROM's conversion | [Torch](https://github.com/HarbourMasters/Torch) | MIT |
| Windowing, input and sound output | [SDL2](https://github.com/libsdl-org/SDL) | Zlib |
| Shader compilation | [shaderc](https://github.com/google/shaderc), glslang, SPIRV-Tools | Apache-2.0; BSD-3-Clause and others (glslang) |
| The menu | Dear ImGui | MIT |
| Smaller libraries | libzip, spdlog, nlohmann/json, tinyxml2, yaml-cpp, dr_libs, stb, Monocypher, prism | BSD-3-Clause, MIT, public domain and similar |
| The Vulkan driver | RADV from [PS5_Mesa](https://github.com/mihawk-99/PS5_Mesa), linked by [PS5_Vulkan](https://github.com/mihawk-99/PS5_Vulkan) | MIT (Mesa); GPL-3.0 (PS5_Vulkan's tools) |
| The platform layer and SDK | [PS5_PayloadSDK](https://github.com/mihawk-99/PS5_PayloadSDK) | GPL-3.0 |

## A built title

A built `eboot.bin` links the GPL-3.0 platform layer with everything above, so
a title as distributed is under **GPL-3.0**. It holds no game data: the player
supplies their own ROM. This is my reading of the licences, not a review; no
release has been made.
