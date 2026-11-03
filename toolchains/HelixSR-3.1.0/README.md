# HelixSR 3.1.0

HelixSR runs DLSS and FSR 4 upscaling networks with Direct3D 12 compute shaders on GPUs that do not have them:

- **HLX DLSS**: the DLSS Model E upscaling network, as HelixSR Scaler's DLSS upscaler (`HelixSR\helixsr.dll`).
  Through HelixSR Scaler it also upscales DirectX 11 and Vulkan games.
- **HLX FSR 4**: HelixSR's own FSR 4-class upscaler, AMD's FSR 4 network on its own fast pipeline
  (`HLX-FSR4\amd_fidelityfx_upscaler_dx12.dll`): the FSR drop-in for games with FSR 3.1, and an upscaler of its own in
  HelixSR Scaler's list.

AMD FSR 3 / FSR 4 (with its FSR 4 presets and models on GPUs that have them) and Intel XeSS stay selectable in HelixSR
Scaler's menu, and so does their frame generation. This release has no HelixSR frame generation.

## New in 3.1.0

- HLX FSR 4 is an upscaler of its own in HelixSR Scaler's list, next to AMD's FSR; AMD's FSR 4 is listed again on GPUs
  that have it, with its FSR 4 preset and model choices.
- HLX FSR 4 is faster on AMD GPUs (a new prepass and post pass, same picture) and picks its INT8 path first on GTX 16.
- HLX DLSS in Vulkan games (through HelixSR Scaler), as in DirectX 11 games.
- GTX 10 (Pascal) on Windows: HLX DLSS's faster conversions are back (they were missing in 3.0.0).
- The setup lists only games: programs from Windows' installed apps and Steam shortcuts that are not games (editors,
  tools) are no longer offered. Enter now skips a game; type **s** or **f** for the games you want.
- Games with anti-cheat are treated like any other game (no warning, no extra question).

## Install

1. Download `HelixSR-3.1.0.zip` and extract it into a folder you keep (for example `C:\HelixSR` or your home folder).
2. Close your games and run the setup in that folder:
   - **Windows:** double-click `helixsr-setup.bat`
   - **Linux / Steam Deck:** `./helixsr-setup.sh` (in a terminal, or double-click and choose *Run in terminal*)
3. The first time, it asks before each download (press Enter) and builds HelixSR on your PC:
   - the upscaling network, from NVIDIA's DLSS 310.7.0 DLL (downloaded from NVIDIA);
   - HLX FSR 4's shaders, from AMD's FSR 4 driver file `amdxcffx64.dll` 2.4.0.4370 (AMD Software 26.10.1). On Windows
     with that AMD driver installed it uses the installed copy; otherwise it downloads AMD's driver package once and
     reads only that file out of it (about 420 MB downloaded, nothing is installed). Every shader is checked against
     the tested one.

   This takes a few minutes.
4. It lists your games (Steam, Epic, GOG, Xbox, Heroic, Lutris), numbered, with what they have (DLSS, FSR 3.1,
   XeSS) and what is installed. Type a game's number (or drag a game's folder into the window), then **Enter** to
   install it the recommended way, or **s** = HelixSR Scaler: pick **DLSS** in the game, **f** = FSR drop-in (HLX FSR 4),
   for games with FSR 3.1: pick **AMD FSR** in the game, **r** = remove. Pick as many games as you like; **Enter** on its
   own when done.
5. Start the game and pick what the setup told you at the end (**DLSS** or **AMD FSR**). Press **Insert** in the game
   for HelixSR Scaler's menu.

No launch options and no settings files are needed (on Linux, the setup tells you when a game needs a launch
option). A game that is not listed: run the setup with its folder (`./helixsr-setup.sh /path/to/game`, or drop the
folder onto `helixsr-setup.bat`).

**Update:** run the setup of the new version and pick the games that have HelixSR (marked in the list): Enter updates
it, **s** / **f** switches the way, **r** removes it.

**Uninstall:** run `helixsr-uninstall.bat` (Windows) or `./helixsr-uninstall.sh` (Linux). It removes HelixSR from the
games you pick and puts back every file as it was; at the end it can also delete what the setup built and its
downloads. A game you added by hand: drop its folder onto the uninstaller, or pass it
(`./helixsr-uninstall.sh /path/to/game`).

**Install by hand (without the game list):** run the setup once first (steps 1 to 3; at the game list press Enter
on its own). HelixSR Scaler's own `setup_windows.bat` / `setup_linux.sh` (in the HelixSR Scaler download) can also
put it into one game at a time. The ZIP's DLLs only hold HelixSR's code: the setup builds the network into `HelixSR\helixsr.dll` and HLX
FSR 4's shaders into `helixsr-scaler\OptiScaler\amd_fidelityfx_upscaler_dx12.dll` and
`HLX-FSR4\amd_fidelityfx_upscaler_dx12.dll`. Copied straight from the ZIP they have nothing to run (HLX FSR 4 is then
not offered at all). Then copy into the game's folder with its .exe (Unreal Engine games: `Binaries\Win64`):

1. from `helixsr-scaler`: `OptiScaler.dll`, renamed to `dxgi.dll` (if the game has its own `dxgi.dll`, name it
   `winmm.dll` or `version.dll` instead), `OptiScaler.ini` and the whole `OptiScaler` folder (it already holds HLX FSR 4
   as `amd_fidelityfx_upscaler_dx12.dll`, next to AMD's original as `amd_fidelityfx_upscaler_dx12.amd.dll`: keep both);
2. the whole `HelixSR` folder (`helixsr.dll`, `helixsr.ini`), next to `dxgi.dll`, not inside the `OptiScaler` folder.

The game folder then has `dxgi.dll`, `OptiScaler.ini`, `OptiScaler\` and `HelixSR\`. Pick **DLSS** in the game for
HLX DLSS; for HLX FSR 4 pick it in HelixSR Scaler's menu (Insert). On Linux, `dxgi.dll` needs no launch option; with
`winmm.dll` or `version.dll` add `WINEDLLOVERRIDES="winmm=n,b" %command%` (or `version=n,b`). HLX FSR 4 alone, without
HelixSR Scaler (games with FSR 3.1): see `fsr3-drop-in\README.txt`. Frame generation needs more files: install it with
the setup or HelixSR Desktop. Remove by hand: delete these files and folders again.

The setup needs Python with numpy and Microsoft's DirectX Shader Compiler (releases v1.9.2607 and v1.9.2609); it
downloads them when needed (Linux runs the shader compiler through Proton or Wine). What it builds contains data made
from NVIDIA's and AMD's software: it is for your own PC, do not share or upload it. Running the setup again only
redoes what is missing (`--rebuild` / `-Rebuild` builds everything again). It also makes `fsr3-drop-in`, for putting
HelixSR into an FSR 3.1 game by hand (see its README.txt).

HelixSR Scaler 2.1.0 comes with this download (folder `helixsr-scaler`, GPL-3.0, see `SOURCE.md`).

## Settings

HelixSR's settings (Int8, WaveSize) are under `[HelixSR]` in the game's `OptiScaler.ini`; HelixSR Scaler writes them
to `helixsr.ini` next to HelixSR's DLL in the game's `HelixSR` folder when the game starts. Restart the game after
changing them. The upscaler (HLX DLSS, HLX FSR 4, AMD FSR, XeSS) is picked in the menu (Insert). `helixsr.log` next to the DLL says what HelixSR
does; HLX FSR 4 writes to `OptiScaler.log` with HelixSR Scaler, else to `HLX_FSR.log` next to its DLL. Include the log
when reporting a problem: https://github.com/lonewolf0622/HelixSR/issues

HelixSR is independent and is not affiliated with NVIDIA or AMD. See `LICENSE`, `SOURCE.md` and
`THIRD_PARTY_NOTICES.md` for licensing and source information.
