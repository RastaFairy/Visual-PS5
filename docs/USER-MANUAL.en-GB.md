# User Manual — PS5 Homebrew Studio 1.1.5

Last updated: 16 October 2026. The application interface is still in Spanish. Localised manuals do not mean that the UI itself has been translated.

## 1. Requirements

To launch the IDE: Windows 10/11, read/write access to the application folder, and PowerShell 7 recommended. The launcher also supports Windows PowerShell 5.1.

To build: Git, WSL/Linux and the upstream dependencies for the selected backend. SharpProspero/C# requires the .NET version specified by the installed revision. Native C++ templates need compatible toolchains. UltraPack requires Python 3.10 or later and a checkout of [PS5 UltraPack](https://github.com/knutwurst/ps5-ultrapack).

## 2. Install and launch

1. Download or build the package for the branch you intend to test.
2. Extract it to a writable folder; avoid Windows-protected directories.
3. Run start.bat and keep the PowerShell server window open.
4. If the browser does not open automatically, visit http://127.0.0.1:47813/.
5. Close the server window or use STOP.bat to stop the service.

The service binds only to 127.0.0.1. Do not expose it to a network or change the bind address to 0.0.0.0. Projects are saved by default under Documents/PS5HomebrewStudio/Projects.

## 3. Interface and visual projects

The canvas starts at 1920×1080 and can be resized. It is a virtual work area, not an exact screenshot of the PS5 system interface. Use the components panel to add controls, the inspector to edit geometry and properties, the hierarchy to organise elements, and the screens manager to structure the UI. The flow editor connects events to actions such as notify, setText, toggleVisibility, setValue, changeColor and navigate when the selected component, event and backend support that combination.

Create a project, choose its backend before preparing dependencies, add components and assets, keep IDs unique, and configure screens. Run diagnostics and fix references to missing elements. Save with Ctrl+S. Exporting a model or ZIP is not the same as compiling a native title.

## 4. Backends and builds

**SharpProspero / C#:** uses the real upstream build pipeline and .NET/NativeAOT. Check the .NET version required by your installed commit.

**Native OpenGL / C++20:** generates a screen compatible with the ps5-homebrew-ui contract. Selected images are converted to RGBA8, limited to 512×512 pixels and up to 16 unique texture IDs per screen.

**Vulkan/RADV / C++20:** creates a title through PS5_VulkanTemplate and integrates UI into a compatible Vulkan module. Compatible revisions of PS5_Vulkan, PS5_Mesa/RADV, PS5_PayloadSDK and PS5_VKHomebrewUI are required.

The IDE runs real upstream scripts and preserves build logs. Exit code zero alone is not sufficient: native-title packaging requires eboot.bin and sce_sys/param.json. The IDE does not distribute Sony proprietary SDKs and does not guarantee universal firmware compatibility.

## 5. Native app presentation assets

In **Projects**, choose an initialized title and select **Presentación**. Only selected fields are replaced; blank fields remain unchanged. The operation updates the project source `sce_sys` files for the next build.

- **Icon:** converted to `sce_sys/icon0.png`, 512×512 PNG.
- **Selection and launch backgrounds:** the selection image produces `pic0.dds` and the launch image `pic1.dds`, each 3840×2160 BC7/DX10. They may differ; if neither exists, select both. DirectXTex `texconv` is required (`winget install Microsoft.DirectXTex.Texconv`); renaming a PNG to `.dds` is not valid conversion.
- **Selection music:** produces `sce_sys/snd0.at9`, looped 48 kHz ATRAC9 no larger than 2 MiB. Supply a compatible AT9 directly or import WAV/MP3/FLAC/AIFF/AIFC; the included open-source encoder converts offline without FFmpeg or `ps4_at9tool.exe`. Review its GPL-3.0-or-later license and notices in `toolchains/ps5-at9-converter/`.

The upstream `tools/prepare-assets.ps1` script validates dimensions and formats. If conversion fails, inspect the output and install the missing tools; incomplete files are not applied. These assets affect the selected app only, not the system-wide home background or console startup sound. The separate [ps5-theme project](https://github.com/Blaze414/ps5-theme) is a plugin/payload for jailbroken PS5 systems and documents firmware support up to 13.60; it is not part of this asset editor.

## 6. Packaging with UltraPack

1. Open Tools and configure Python 3.10+ and the UltraPack backend/cli.py file.
2. Save settings. Paths are stored locally in .runtime/integrations.json.
3. Select a built native project and choose Package.
4. Select .ffpfs, .ffpfsc or .pkg. On Windows, .pkg requires a native helper and its dependencies.
5. Leave “Verify content against source” checked to pass --verify to UltraPack. Verification can increase runtime and memory use.
6. Review the final log, exit code, output path and warnings. An old artefact does not prove that the current run succeeded.

Outputs are stored under packages-ultrapack, grouped by format and timestamp. Packaging runs in the background so the editor remains responsive. The maintainer has reported a generated .ffpfsc image successfully tested on real hardware; that does not guarantee every title, firmware or backend.

## 7. Tests and troubleshooting

With Node.js installed, run node --check app.js, node --check runtime/native-generator.js and node runtime/test-native-generator.js from the PS5-Homebrew-Studio folder. These tests check JavaScript syntax and generator cases; they do not replace a complete PS5 toolchain build or a console test.

If the server fails to start, keep the full error and check PowerShell and permissions. For build failures, record the backend, upstream versions and commits, full output and exit code. If UltraPack fails, check Python and cli.py paths, eboot.bin, sce_sys/param.json and output permissions. Never share tokens, keys, protected files or logs containing secrets.


### WSL error: chmod on .git/config.lock

If the log contains `chmod on /mnt/d/.../.git/config.lock failed: Operation not permitted` or `could not set 'core.filemode' to 'false'`, WSL has mounted a Windows drive without the `metadata` option. The IDE detects this before the SDK build and shows the repair steps.

Open the WSL distribution and run the helper shipped with the IDE (adjust the path to the actual installation):

```bash
sudo bash /mnt/d/PS5-Homebrew-Studio/runtime/fix-wsl-permissions.sh
```

The script backs up `/etc/wsl.conf` and updates `[automount] options` without discarding other settings. Close WSL, run `wsl --shutdown` from Windows PowerShell, start the distribution again, and retry the build. This stops all running WSL distributions, so save work first. Do not run Git or the IDE as administrator. See the [detailed WSL permissions guide](WSL_PERMISSIONS.md) and [Microsoft's documentation](https://learn.microsoft.com/windows/wsl/file-permissions).
## 8. Licensing and scope

SDKs, drivers, templates and UI kits retain their own licences. Review LICENSE, COPYING, NOTICE and redistribution requirements before publishing a binary. Visual-PS5 is not an official Sony SDK, includes no firmware, keys, games or BIOS, and does not automatically install titles on a console. The editor preview is not a PS5 emulator and does not validate runtime, audio, input or persistence.
