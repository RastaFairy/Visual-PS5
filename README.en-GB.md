# Visual-PS5 — PS5 Homebrew Studio

**Version 1.0.1 · 16 October 2026**

Visual-PS5 is a local visual IDE for designing interfaces, saving projects, inspecting generated code and coordinating builds through community PlayStation 5 toolchains.

## Quick start

1. Download the corrected ZIP attached to this conversation's delivery and verify its SHA-256.
2. Extract `PS5-Homebrew-Studio` to a writable directory.
3. Run `start.bat` on Windows 10/11. PowerShell 7 is recommended; the launcher also supports Windows PowerShell 5.1 as a fallback.
4. Open `http://127.0.0.1:47813/` if the browser does not open automatically.

## Documentation

- [User manual](docs/USER-MANUAL.en-GB.md)
- [Capabilities and limitations](docs/CAPABILITIES-AND-LIMITATIONS.en-GB.md)
- [Architecture and toolchains](docs/ARCHITECTURE-AND-TOOLCHAINS.en-GB.md)
- [Licensing and security](docs/LICENSING-AND-SECURITY.en-GB.md)
- [Documentation en español de España](README.es-ES.md)
- [Manual de uso en español](docs/MANUAL.es-ES.md)
- [Upstream SDK/repository matrix](release/UPSTREAM-SDK-MATRIX.md)
- [Changelog](docs/CHANGELOG.md)
- [PowerShell line 627 hotfix](docs/patches/FIX-POWERSHELL-627.en-GB.md)

## What it does

The editor provides a 1920×1080 canvas, property inspector, hierarchy, screens, visual flows, asset management, diagnostics, export and C++20 UI generation for OpenGL/Vulkan-RADV. It integrates community templates and a SharpProspero C# workflow. Builds are delegated to the actual upstream scripts.

**It is not an official Sony SDK**, includes no proprietary files, firmware, keys, games or BIOS, does not jailbreak a console, and does not install titles on hardware automatically or guarantee compatibility across firmware versions.

## Limitations and validation

The editor can modify models without an SDK downloaded. Builds require WSL/Linux and the selected backend's dependencies. A successful upstream process plus an artefact does not prove that the application works correctly on a console.

JavaScript and generator tests were run. The preparation environment did not include the official PowerShell parser, complete PS5 toolchains or a physical console, so no final SDK/hardware validation is claimed.

The corrected v1.0.1 ZIP is supplied as a separate attachment; it is not yet stored as a GitHub Release asset.
