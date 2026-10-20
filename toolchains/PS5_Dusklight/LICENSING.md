# Licences

The repository as a whole, and any title built from it, is offered under the GNU
General Public License, version 3 ([`LICENSE`](LICENSE)). Its files come from
projects under several licences, each compatible with that; every source file
names its own in its header, and may also be used under that licence alone. This
is the summary.

| Path | Licence | Text |
| --- | --- | --- |
| `ps5/tools/png-to-title-dds.py` (encoder from PS5 RetroArch, by Mihawk) | GPL-3.0-or-later | [`licenses/GPL-3.0.txt`](licenses/GPL-3.0.txt) |
| `ps5/src/platform.c`, `ps5/src/platform.h` and the tools taken from the PS5 Vulkan Template (by Mihawk, after Sascha Willems' Vulkan examples) | MIT | [`licenses/MIT.txt`](licenses/MIT.txt) |
| The rest of `ps5/src/`, `ps5/tools/`, `ps5/cmake/`, `ps5/stage1/`, `ps5/art/make-title-art.py` and `ps5/nod/nod.cpp` (written for this port) | MIT | [`licenses/MIT.txt`](licenses/MIT.txt) |
| `ps5/nod/include/nod.h` (the C header of [nod](https://github.com/encounter/nod), unchanged) | MIT or Apache-2.0, at your choice; used here under MIT | [`licenses/MIT.txt`](licenses/MIT.txt) |
| `ps5/sdl/` (SDL3 drivers for the console) and `ps5/patches/sdl.patch` | Zlib, as SDL | [`licenses/Zlib.txt`](licenses/Zlib.txt) |
| `ps5/patches/dawn.patch` | BSD-3-Clause, as Dawn | in Dawn's source |
| `ps5/patches/dawn-abseil.patch` | Apache-2.0, as Abseil | in Abseil's source |
| `ps5/patches/aurora.patch`, `ps5/patches/borealis.patch` | MIT, as Aurora and Borealis | in their sources |
| `ps5/patches/dusklight.patch` | CC0-1.0, as Dusklight | in Dusklight's source |

## What is built from elsewhere

Nothing below is stored in this repository; the build takes each from its own
project, under that project's licence.

| Part | Project | Licence |
| --- | --- | --- |
| The game's code | [Dusklight](https://github.com/TwilitRealm/dusklight), a reimplementation based on the [Twilight Princess decompilation](https://github.com/zeldaret/tp) | CC0-1.0 |
| The GameCube layer | [Aurora](https://github.com/encounter/aurora) | MIT |
| Support code | [Borealis](https://github.com/encounter/borealis) | MIT |
| WebGPU | [Dawn](https://github.com/encounter/dawn) (Google's, at the revision Aurora pins) | BSD-3-Clause |
| Windowing, input and sound | [SDL3](https://github.com/libsdl-org/SDL) | Zlib |
| The Vulkan driver | RADV from [PS5_Mesa](https://github.com/mihawk-99/PS5_Mesa), linked by [PS5_Vulkan](https://github.com/mihawk-99/PS5_Vulkan) | MIT (Mesa); GPL-3.0 (PS5_Vulkan's tools) |
| The platform layer and SDK | [PS5_PayloadSDK](https://github.com/mihawk-99/PS5_PayloadSDK), a fork of ps5-payload-dev/sdk | GPL-3.0 |
| Smaller libraries Aurora and Dusklight fetch | fmt, zstd, libpng, FreeType, Dear ImGui, RmlUi, SQLite, xxHash, Tracy, Abseil, miniz, PicoSHA2, cxxopts and others | each its own, all permissive or public domain |

## A built title

A built `eboot.bin` links the GPL-3.0 platform layer with everything above, so a
title as distributed is under **GPL-3.0**. Anyone who distributes a build must
make the source of every part available at the revisions it was built from.

## What is not covered

- **The game.** The Legend of Zelda: Twilight Princess, its disc image and
  everything on it belong to Nintendo. None of it is in this repository or in
  any build of it, and no licence above covers it. A title built from here does
  nothing without a disc image you provide.
- **Decompiled code.** Dusklight's contributors release their work as CC0, which
  can only give away what is theirs. The code is a reimplementation derived from
  a decompilation of Nintendo's game; whether and where that is lawful to use or
  share is not something these licences settle.
- **Artwork.** `ps5/sce_sys/icon0.png`, `pic0.dds` and `pic1.dds` come from
  `ps5/art/icon0-source.png` and `ps5/art/pic-source.jpg`, the port's own
  pictures (a young swordsman and a black wolf split by a seam of twilight, over
  carved stone, made for it by Gary Riches with an image generator): nothing in
  them is from the game. The menu pictures
  in `ps5/art/res/` (which a built title carries in place of Dusklight's own
  logo, icon, emblem and pre-launch background) are drawn by
  `ps5/art/make-title-art.py`: a generated landscape and the lettering of
  Dusklight's logo (CC0, without its mascot). Nothing in them is Nintendo's.
- **Button symbols.** `ps5/art/glyphs/` (shipped as `res/ps5-glyphs/`) is made
  from Kenney's Input Prompts (www.kenney.nl), Creative Commons Zero:
  `ps5/art/kenney/License.txt`. The cross, circle, square and triangle are
  Sony's marks whoever draws them.
- **Trademarks.** "The Legend of Zelda", "Twilight Princess", "GameCube" and
  "Nintendo" are trademarks of Nintendo. "PlayStation" and "PS5" are trademarks
  of Sony Interactive Entertainment Inc. This project is not affiliated with or
  endorsed by either, or by the Dusklight project.
