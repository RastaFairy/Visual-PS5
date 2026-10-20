# Licences

The repository as a whole, and any title built from it, is offered under the GNU
General Public License, version 3 ([`LICENSE`](LICENSE)). Its files come from
projects under several licences, each compatible with that; every source file
names its own in its header, and may also be used under that licence alone.

| Path | Licence | Text |
| --- | --- | --- |
| `ps5/tools/png-to-title-dds.py` (encoder from PS5 RetroArch, by Mihawk) | GPL-3.0-or-later | [`licenses/GPL-3.0.txt`](licenses/GPL-3.0.txt) |
| `ps5/src/platform.c`, `ps5/src/platform.h` and the tools taken from the PS5 Vulkan Template (by Mihawk) | MIT | [`licenses/MIT.txt`](licenses/MIT.txt) |
| The rest of `ps5/src/`, `ps5/tools/`, `ps5/cmake/`, `ps5/art/*.py`, `ps5/art/*.sh` and `ps5/nod/` (written for this port and for PS5_Dusklight) | MIT | [`licenses/MIT.txt`](licenses/MIT.txt) |
| `ps5/sdl/` (SDL3 drivers for the console) and `ps5/patches/sdl.patch` | Zlib, as SDL | [`licenses/Zlib.txt`](licenses/Zlib.txt) |
| `ps5/patches/dawn.patch` | BSD-3-Clause, as Dawn | in Dawn's source |
| `ps5/patches/dawn-abseil.patch` | Apache-2.0, as Abseil | in Abseil's source |
| `ps5/patches/aurora.patch` | MIT, as Aurora | in Aurora's source |
| `ps5/patches/switchwaker.patch` | MIT, as SwitchWaker | in SwitchWaker's source |
| `ps5/art/kenney/` (Kenney's Input Prompts) | CC0-1.0 | `ps5/art/kenney/License.txt` |
| `ps5/art/glyphs/`, the icon and the background | made for this port | |
| `ps5/shader-cache/` | compiled output of this build's shader generator and driver, recorded on a console; no game data | |

## What is built from elsewhere

Nothing below is stored in this repository; the build takes each from its own
project, under that project's licence.

| Part | Project | Licence |
| --- | --- | --- |
| The game's code | [SwitchWaker](https://github.com/centollOS/SwitchWaker) (MIT), which compiles the [Wind Waker decompilation](https://github.com/zeldaret/tww); part of it comes from an AI-assisted fork (see SwitchWaker's README) | MIT; CC0-1.0 |
| Sound | Dolphin's DSP HLE, as SwitchWaker uses it | GPL-2.0-or-later |
| The GameCube layer | [Aurora](https://github.com/encounter/aurora) | MIT |
| WebGPU | Dawn, at the revision Aurora pins | BSD-3-Clause |
| Windowing, input and sound output | [SDL3](https://github.com/libsdl-org/SDL) | Zlib |
| The Vulkan driver | RADV from [PS5_Mesa](https://github.com/mihawk-99/PS5_Mesa), linked by [PS5_Vulkan](https://github.com/mihawk-99/PS5_Vulkan) | MIT (Mesa); GPL-3.0 (PS5_Vulkan's tools) |
| The platform layer and SDK | [PS5_PayloadSDK](https://github.com/mihawk-99/PS5_PayloadSDK) | GPL-3.0 |

## A built title

A built `eboot.bin` links the GPL-3.0 platform layer and Dolphin's
GPL-2.0-or-later DSP HLE with everything above, so a title as distributed is
under **GPL-3.0**. It holds no game data: the player supplies their own disc
image. This has not been reviewed for a release; no release has been made.
