# Mario 64 for PlayStation 5

[![stars](https://img.shields.io/github/stars/griches/PS5_Ghostship?style=flat)](https://github.com/griches/PS5_Ghostship/stargazers)
[![release](https://img.shields.io/github/v/release/griches/PS5_Ghostship)](https://github.com/griches/PS5_Ghostship/releases/latest)
[![licence](https://img.shields.io/badge/licence-GPL--3.0%20as%20built-blue)](LICENSING.md)

A PS5 homebrew port of [Ghostship](https://github.com/HarbourMasters/Ghostship)
(v3.0.0), HarbourMasters' native port of the 1996 Nintendo 64 game, compiled
from its decompilation on [libultraship](https://github.com/Kenix3/libultraship).
On the console it draws through libultraship's Vulkan renderer on RADV, from the
[PS5 Vulkan](https://github.com/mihawk-99/PS5_Vulkan) stack.

The build reads no ROM and holds no game data. The player copies their own ROM
beside the title, and the title converts it once, on the console.

## Status

**Runs on the console.** First run on 2026-10-12 on a PS5 at 3840x2160: the title
screen, the file select, a new game and the castle grounds, at a measured 60
images a second (frame interpolation; the game's logic stays at 30).

| Area | State |
| --- | --- |
| Game data | A US or JP `.z64` in the title's folder is found on the first start and converted to `sm64.o2r` in a few seconds. With neither file the title says what to copy where and closes |
| Picture | 3840x2160 on a 4K output, 16:9 |
| 60 fps | Measured at 3840x2160 on the title screen and the castle grounds |
| Menu | The touch pad's click opens Ghostship's settings menu. L1/R1 change tab, L2/R2 change section, the d-pad and Cross work the settings, Options asks to quit. The controls are listed along the bottom of the screen |
| HD textures | [SM64 Reloaded](#hd-textures-optional) seen working on the console |
| Saves, settings | `/data/homebrew/PPSA99310/userdata/` |
| DevLoop | `devloop-shot` in the title's folder (registered as `ghostship`) |
| Art | The icon and background are the port's own, made with an image generator (`ps5/art/`) |

Controls are Ghostship's defaults for a pad: left stick to move, Cross A,
Circle B, L2 Z, R2 R, L1 L, Options START, the right stick for the C buttons.
They can be changed in the menu under Settings, Controls.

## Install

Download `Mario64-PS5-vX.Y.zip` from the
[latest release](https://github.com/griches/PS5_Ghostship/releases/latest) and
unpack it: it holds one folder, `PPSA99310`. (Or build that folder yourself, see
Build.) It contains no game data.

**What the console needs**

- A PS5 that runs homebrew, with etaHEN (or an equivalent) loaded.
- ShadowMountPlus, which shows the folders in `/data/homebrew` as titles on the
  home screen.
- An FTP server on the console to copy files with (port 2121 here).

**Steps**

1. Copy the whole folder `PPSA99310` to the console as
   `/data/homebrew/PPSA99310/`, so that you have:

   ```text
   /data/homebrew/PPSA99310/eboot.bin
   /data/homebrew/PPSA99310/ghostship.o2r
   /data/homebrew/PPSA99310/config.yml
   /data/homebrew/PPSA99310/assets/       (what the ROM's conversion reads)
   /data/homebrew/PPSA99310/sce_sys/      (param.json, icon0.png, pic0.dds, pic1.dds)
   /data/homebrew/PPSA99310/sce_module/libc.prx
   /data/homebrew/PPSA99310/licenses/
   ```

   Copy `sce_sys/icon0.png` with the first upload: ShadowMountPlus will not
   register a title without its icon.
2. Copy your own Super Mario 64 ROM into the same folder, beside `eboot.bin`.
   It must be the Nintendo 64 game's US or JP release, in `.z64` format (big
   endian; convert a `.n64` or `.v64` dump first), under any name ending in
   `.z64`. The title checks the ROM against these hashes and takes no other:

   ```text
   /data/homebrew/PPSA99310/baserom.us.z64
   ```

   | Release | SHA-1 |
   | --- | --- |
   | US | `9bef1128717f958171a4afac3ed78ee2bb4e86ce` |
   | JP | `8a20a5c83d6ceb0f0506cfc9fa20d8f438cafe51` |

3. Wait a few seconds for "Mario 64" to appear on the home screen, and start it.
4. The first start says "ROM found" and asks whether to generate the game files:
   press **Cross**. It takes a few seconds, and the game starts. The ROM is not
   needed again and can be deleted from the console.

If you already have an `sm64.o2r` made by Ghostship 3.0.0 on a PC, copy that
into the folder in place of the ROM.

If "Mario 64" does not appear on the home screen, look in
`/data/shadowmount/debug.log`. "AppInstallAll hook is no longer installed" means
ShadowMountPlus has to be restarted before it will register a new title.

## HD textures (optional)

The port takes Ghostship texture packs unchanged. The one tried on the console is
**SM64 Reloaded** by GhostlyDark:

- Project: <https://github.com/GhostlyDark/SM64-Reloaded>
- Downloads: <https://github.com/GhostlyDark/SM64-Reloaded/releases/latest>

**1. Download the Ghostship version of the pack.** On the releases page, take the
file whose name contains `gs-o2r`:

| File | Size | |
| --- | --- | --- |
| `sm64-reloaded-v2.6.0-gs-o2r-hd.7z` | 99 MB | HD; the one used on the console |
| `sm64-reloaded-v2.6.0-gs-o2r-4k.7z` | 618 MB | 4K |

The other files on that page are for emulators and other ports and will not work.

**2. Unpack it.** It holds one `.o2r` file, for example
`SM64_Reloaded_v2.6.0_HD.o2r` (547 MB).

**3. Copy the `.o2r` to the console's `mods` folder:**

```text
/data/homebrew/PPSA99310/userdata/mods/SM64_Reloaded_v2.6.0_HD.o2r
```

The folder exists once the game has been started once.

**4. Switch the pack on in the menu.** Start the game, then:

1. Press the **touch pad** to open the menu.
2. Press **R1** once, to the **Enhancements** tab.
3. The **Graphics** section is the first one and is already selected (if another
   is, press **L2** until Graphics is).
4. Move down with the **d-pad** to **Use Alternate Assets**, under "Mods", and
   press **Cross** to tick it.
5. Press the **touch pad** to close the menu.

The setting is remembered. Untick the same box to go back to the original
textures. If the textures do not change when you tick the box, quit and start
the game again.

## Build

On Linux (on a Mac, in the Lima VM) with PS5_Vulkan, PS5_Mesa and PS5_PayloadSDK
beside this folder.

```sh
ps5/tools/vm.sh build            # from macOS; ps5/tools/build.sh inside the VM
ps5/tools/vm.sh assets           # ghostship.o2r, Ghostship's own assets, into dist/
ps5/tools/vm.sh deploy
ps5/tools/vm.sh run
```

`build.sh` runs `setup-source.sh` first, which applies the console's changes to
`vendor/ghostship` and its two submodules from `ps5/patches/` (every hunk behind
`__PROSPERO__` or `PS5`). While changing anything under `vendor/`, run
`ps5/tools/setup-source.sh --save` before a build.

`ps5/tools/vm.sh assets ROM.z64` also makes `sm64.o2r` on this machine, into the
ignored `game/` folder, and `ps5/tools/vm.sh console-files` uploads it: the
quicker loop while developing.

What the console needed:

- **SDL2.** libultraship is written for SDL2; `ps5/sdl/` holds SDL2 video, audio
  and pad drivers for the console (`ps5/patches/sdl.patch` registers them).
- **Vulkan with no loader.** RADV is linked into the title, so libultraship's
  Vulkan renderer and Dear ImGui's reach it through volk. OpenGL is compiled out.
- **shaderc**, built from source: the renderer writes its shaders as GLSL at run
  time.
- **No working directory.** A title cannot `chdir`, `getcwd` or `realpath`;
  `ps5/src/shims.c` answers the last two for `std::filesystem`.
- **The log.** A flush for every line made the ROM's conversion take twenty
  minutes; errors are flushed at once, the rest every two seconds.
- **The menu with a pad alone**: see Status.

`GHOSTSHIP_PS5_FPS=1` in `/data/homebrew/PPSA99310/env.txt` writes the frame
rate to the console's log every ten seconds.

## Licence

GPL-3.0 for the repository as a whole and for a built title: see
[`LICENSING.md`](LICENSING.md). No game data is stored here or built in.
"Mario" and "Super Mario 64" are Nintendo's; this project is not affiliated with
Nintendo, HarbourMasters or Sony Interactive Entertainment.
