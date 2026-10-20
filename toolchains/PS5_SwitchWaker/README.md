# Wind Waker (GameCube) for PlayStation 5

[![stars](https://img.shields.io/github/stars/griches/PS5_SwitchWaker?style=flat)](https://github.com/griches/PS5_SwitchWaker/stargazers)
[![release](https://img.shields.io/github/v/release/griches/PS5_SwitchWaker)](https://github.com/griches/PS5_SwitchWaker/releases/latest)
[![licence](https://img.shields.io/badge/licence-GPL--3.0%20as%20built-blue)](LICENSING.md)

A PS5 homebrew port of [SwitchWaker](https://github.com/centollOS/SwitchWaker), the
native port of the 2002 GameCube game (USA disc `GZLE01`, revision 0) compiled
from its decompilation and drawn with [Aurora](https://github.com/encounter/aurora).
It is laid out like [PS5_Dusklight](https://github.com/griches/PS5_Dusklight) and
uses the same console layer: Aurora on Dawn's WebGPU on RADV, from the
[PS5 Vulkan](https://github.com/mihawk-99/PS5_Vulkan) stack.

The build reads no disc and holds no game data: SwitchWaker's runtime-assets
mode compiles against stub headers and fills them from the player's own disc
image when the title starts.

## Status

**Runs on the console.** First run on 2026-10-12 on a PS5 at 3840x2160: the
title screen, name entry, the prologue and Outset, at 60 images a second
(frame interpolation; the game's logic stays at 30), with the DualSense's
symbols on the HUD. Played on the console as far as the forest on Outset, the
scenes that follow it, and the boss room of Dragon Roost Cavern; nothing else
has been seen there.

**[Version 1.0.3](https://github.com/griches/PS5_SwitchWaker/releases/tag/v1.0.3)** fixes a crash in Dragon Roost Cavern, in the rooms with
the hanging platforms. [Version 1.0.2](https://github.com/griches/PS5_SwitchWaker/releases/tag/v1.0.2) fixed a crash when the boss of Dragon
Roost Cavern appears, and stopped the whole class of fault behind it (an
integer division by zero) from ending the game anywhere else. [Version 1.0.1](https://github.com/griches/PS5_SwitchWaker/releases/tag/v1.0.1)
fixed a stop on a black screen at the end of the forest scene. See
[Development](#development) for what
they were. Copy the [new release](https://github.com/griches/PS5_SwitchWaker/releases/latest) over the old folder; saves carry on.

A release is the title's folder with no game in it: the player copies their own `GZLE01` disc image (`.iso`, `.gcm` or `.ciso`) into
`/data/homebrew/PPSA99309/` beside `eboot.bin`, and the title finds it (the
first one in its folder, then on a USB drive).

| Area | State |
| --- | --- |
| Disc | Found in the title's folder; a `.iso` and a `.ciso` have both been run on the console; `.gcm` has not. A missing or wrong disc closes the title with a console notification (the close is seen working; the notification's text has not been read on a television yet) |
| Picture | 16:9. The output is 3840x2160 unless the options menu's "Output resolution" says 2560x1440 or 1920x1080 (applied at the next start); the console scales it to the television. "Internal resolution" follows it ("Window size") or is fixed, which dynamic resolution needs |
| 60 fps | Held at 3840x2160 in the scenes above, by the frame counter on screen. Not measured over a long session |
| Shaders | A first start with no cache compiled 3,056 render pipelines in about 12 minutes. The title now ships the caches a console produced (`ps5/shader-cache`) and copies them into place when the console has none: the same start then compiles nothing. They must be taken from a console again after a change to Dawn, the driver or the shaders |
| Button prompts | The HUD shows Cross (A), Square (B), Circle (X), Triangle (Y), R1 for Z, R2 for R and a right stick for the C stick (`ps5/art/make-glyphs.py`, [Kenney's CC0 Input Prompts](https://kenney.nl/assets/input-prompts)). The options menu's hints name the DualSense's buttons. Not done: the button pictures inside message text (they are in the game's font). With an HD texture pack the pack's buttons are drawn instead: see [Button symbols with a pack](#hd-textures-optional) |
| Options menu | The touch pad's click opens it |
| Saves, settings | `/data/homebrew/PPSA99309/user/`; the first start asks to create a save file, as the game does on an empty memory card |
| HD textures | A Dolphin texture pack the player supplies replaces the game's textures (on when a pack is in `user/hd_textures`, off otherwise; see [HD textures](#hd-textures-optional)). Seen working on the console with Hypatia's pack on Outset and in its forest. The pack has an optional PlayStation button set for the HUD |
| Sound | Not checked by ear in this log |
| DevLoop | `devloop-shot` and `devloop-quit` in the title's folder (registered as `windwaker-gc`); the shot answers once the game's loop runs |
| Art | The icon and background are the port's own, cel-shaded, made with an image generator (`ps5/art/`) |

Controls: left stick to move, right stick for the camera (the C stick), Cross A,
Square B, Circle X, Triangle Y, R1 Z, L2 L, R2 R, Options START. The buttons are
mapped by position, where the GameCube pad has them around A, so the HUD's
symbols sit where the buttons do on the DualSense: the sword is on Square.
The symbol of an empty item slot sits in the middle of its bubble.

## Install

Download `WindWaker-PS5-vX.Y.Z.zip` from the
[latest release](https://github.com/griches/PS5_SwitchWaker/releases/latest) and
unpack it: it holds one folder, `PPSA99309`. (Or build that folder yourself, see
[Build](#build).) It contains no game data.

**What the console needs**

- A PS5 that runs homebrew, with etaHEN (or an equivalent) loaded.
- ShadowMountPlus, which shows the folders in `/data/homebrew` as titles on the
  home screen.
- An FTP server on the console to copy files with (port 2121 here).

**Steps**

1. Unpack the release (or build: the result is the folder `dist/PPSA99309/`).
2. Copy that whole folder to the console as `/data/homebrew/PPSA99309/`, so that
   you have:

   ```text
   /data/homebrew/PPSA99309/eboot.bin
   /data/homebrew/PPSA99309/initial_pipeline_cache.db
   /data/homebrew/PPSA99309/sce_sys/      (param.json, icon0.png, pic0.dds, pic1.dds)
   /data/homebrew/PPSA99309/sce_module/libc.prx
   /data/homebrew/PPSA99309/res/          (button symbols and shader caches)
   /data/homebrew/PPSA99309/licenses/
   ```

   Copy `sce_sys/icon0.png` with the first upload: ShadowMountPlus will not
   register a title without its icon.
3. Copy your disc image into the same folder, under any name ending in `.iso`,
   `.gcm` or `.ciso`:

   ```text
   /data/homebrew/PPSA99309/your-disc.iso
   ```

   It has to be there or on a USB drive, not elsewhere in `/data`: a title can
   only see its own folder. The game takes the first image it finds.
4. Wait a few seconds for "Wind Waker" to appear on the home screen, and start
   it. The first start asks to create a save file.

With no disc image, or one that is not the supported disc, the title closes and
the console shows a notification that says why.

Saves and settings are written to `/data/homebrew/PPSA99309/user/`. Copying a new
build over the folder leaves them, and the disc image, alone.

**The disc image.** Dump your own copy of the game
([how](https://wiki.dolphin-emu.org/index.php?title=Ripping_Games)). Only the USA
disc, `GZLE01` revision 0, is supported. If your dump is RVZ or another compressed
format, convert it to `.iso` with [Dolphin](https://dolphin-emu.org/) first.

## HD textures (optional)

The game's textures are the GameCube's, made for a 480-line picture. A texture
pack replaces them with redrawn, larger ones as the game draws them; nothing in
the game itself changes, and the option can be turned on and off while playing.
The port reads packs made for the [Dolphin](https://dolphin-emu.org/) emulator
for the USA disc (`GZLE01`). No pack comes with the title: each is its author's
own work, and you download it yourself.

The pack tried here is **Hypatia's "WWHD Mod" v2.0001a**, about 5,700 textures
covering most of the game. Its downloads are in the first post of
[its thread on the Dolphin forum](https://forums.dolphin-emu.org/thread-55004.html).
Take **"PC DDS Half Size"** (a `.7z` of 850 MB, 2.5 GB unpacked), which is the
one used here:
[direct download from the author's Google Drive mirror](https://drive.google.com/file/d/1qBK8YOeSAwLpNP3NUkwcXgvUnQPKlgj7/view?usp=sharing)
(`Hypatia WWHD Mod v2.0001a (DDS-Half).7z`). The port reads it as it is. The full-size one is four times larger for a picture that is hard
to tell apart, and the PNG one is not suitable.

1. Unpack the `.7z` on a computer. Inside is a folder `GZL`.
2. Copy what is **inside** `GZL` (the folders `Characters`, `Environments`,
   `HUD` and so on) to the console, into
   `/data/homebrew/PPSA99309/user/hd_textures/`. Create that folder if it is
   not there. Over FTP the 5,700 files take about ten minutes.
3. Start the game. A pack found in that folder is used from the start; the
   options menu (the touch pad's click) has Graphics > "HD textures" to turn it
   off and on, and remembers what you chose.

With no pack in that folder the option does nothing.

Seen on the console on 2026-10-12 with that pack: Outset at 3840x2160 and 60
images a second with the textures replaced, and its forest. Not played further
than that.

**Button symbols with a pack.** The pack replaces the HUD's buttons as well, with
its own GameCube ones, so the DualSense's symbols this port draws are lost while
it is on. To have PlayStation buttons with the pack, also copy the `HUD` folder
from its `-[Optional Textures]-/[HUD] Controller Buttons - Playstation` over
the `HUD` folder in `hd_textures`, replacing files: those label the buttons by
position, as this port maps them (Cross where A is, Square for B, Circle for X,
Triangle for Y). The button pictures inside message text stay the GameCube's
either way.

## Development

To try a change without the console:

```sh
cmake -S vendor/switchwaker/native -B build/native-mac -G Ninja \
    -DFETCHCONTENT_SOURCE_DIR_AURORA=$PWD/.deps/aurora -DCOS_AURORA_PREPATCHED=ON \
    -DCOS_RECOMPCORE_DIR=$PWD/.deps/recompcore \
    -DCOS_RUNTIME_ASSETS=ON -DCOS_ASSETS_DIR=$PWD/.deps/assets/GZLE01
ninja -C build/native-mac switchwaker
COS_BUILD_DIR=$PWD/build/native-mac COS_DISC=/path/to/GZLE01.iso COS_FPS60=1 \
    COS_BUTTON_GLYPHS=$PWD/ps5/art/glyphs vendor/switchwaker/native/tools/run.sh run \
    --preset sailing --aspect 16:9 --frames 700 --shot 690
```

**Finding a fault on the console.** The game's own `[cos]` lines go to the
console's log (klog, port 3232) with the driver's. A `[dev]` section at the end
of `user/settings.ini` sets developer variables at the next start, for example
`COS_TRACE=scene,res` for every scene created and every file opened. A scene
change that stays in one step logs `scene-req-watch` lines every 300 calls: the
step, and the processes still waiting to be deleted.

The stop that 1.0.1 fixes was found that way. Some actors declare their methods
as returning `bool` and the game's process framework calls them as returning
`int` and compares with `TRUE`. On x86-64 the rest of the register is undefined,
so a delete could be refused for ever and the next scene never came; on ARM (the
Mac, the Switch) it does not show. The framework now reads only the low byte
([`f_pc_method.cpp` in the patch](ps5/patches/switchwaker.patch)). On the Mac, `COS_EVENT_SWEEP_FOLLOW=1` lets
`run.sh event-sweep` go on through a stage change an event asks for.

The crash that 1.0.3 fixes is a third one. A hanging platform of Dragon Roost
Cavern whose ropes were cut on an earlier visit is created with them cut, and
the rope points are simulated from values nothing has set. A NaN among them
reaches the arctangent table as an index: the conversion to an integer gives
0x80000000, which the GameCube's 32 bit address wraps back to the first entry
and x86-64 turns into a read 4 GB below the table. The lookup now gives the
first entry for a NaN or a ratio outside the table ([`c_math.cpp` in the patch](ps5/patches/switchwaker.patch)).
It was found from a player's photograph of the console's error message: the
two addresses in it, less the load address 0x400000, name `cM_atan2s` and
`himo_move` in the release's ELF.

The crash that 1.0.2 fixes is the same kind of difference. The boss of Dragon
Roost Cavern turns towards the player with a step count that is still zero the
first time, an integer division by zero: the GameCube and ARM give a quotient
and go on, x86-64 raises SIGFPE. The three helpers involved now give 0
([`c_lib.cpp` in the patch](ps5/patches/switchwaker.patch)), and so that the next one elsewhere is not a crash,
the title handles SIGFPE itself: it finishes the division as ARM does (quotient
0, remainder the dividend), logs `integer division fault` with the address, and
goes on. The console's code cannot be read at run time, so the build lists
every division instruction of the linked title in `res/div-table.bin`
([`make-div-table.py`](ps5/tools/make-div-table.py)) and the handler looks the address up; a fault
that is not in the list is still a crash with the console's record.
`COS_DIV_TEST=1` in `[dev]` divides by zero once at the start to check it. On
the Mac, `COS_SAVE_LOAD_WALK=<frames>` makes `run.sh save-load` walk forward
from a loaded save (`COS_CARD_DIR` names a card folder holding a player's
`.gci`).

`COS_TEXTURE_DUMPS=1` writes every texture drawn into the cache folder's
`texture_dumps`, named as a replacement for it must be named.

## Build

As PS5_Dusklight: on Linux (on a Mac, in the Lima VM) with PS5_Vulkan, PS5_Mesa
and PS5_PayloadSDK beside this folder.

```sh
ps5/tools/vm.sh build     # from macOS; ps5/tools/build.sh inside the VM
ps5/tools/vm.sh deploy
ps5/tools/vm.sh run
```

`build.sh` runs `setup-source.sh` first, which patches `vendor/switchwaker`
(`ps5/patches/switchwaker.patch`, every hunk behind `__PROSPERO__`) and fetches
into `.deps/` Aurora at SwitchWaker's pin with its patches, Dolphin's DSP HLE
sources and the stub asset headers. While changing `vendor/switchwaker`, run
`git -C vendor/switchwaker diff > ps5/patches/switchwaker.patch` before a build.

## Licence

GPL-3.0 for the repository as a whole and for a built title: see
[`LICENSING.md`](LICENSING.md). No game data is stored here or built in.
