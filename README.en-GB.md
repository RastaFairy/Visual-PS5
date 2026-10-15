# Visual-PS5 — PS5 Homebrew Studio

**Version 1.0.1 · 16 October 2026**

Visual-PS5 is a local visual IDE for designing interfaces, saving projects, inspecting generated code and coordinating builds through community PlayStation 5 toolchains.

## Quick start

1. Clone or download this repository.
2. To reconstruct the complete project copy, run `.\scripts\Restore-SourceArchive.ps1` from the repository root. The script decodes the segments, verifies SHA-256 and extracts `PS5-Homebrew-Studio`.
3. Enter the extracted directory and run `start.bat` on Windows 10/11. PowerShell 7 is recommended; the launcher also supports Windows PowerShell 5.1 as a fallback.
4. Open `http://127.0.0.1:47813/` if the browser does not open automatically.

On Linux/WSL, use `sh scripts/restore-source-archive.sh`.

## Documentation

- [User manual](docs/USER-MANUAL.en-GB.md)
- [Capabilities and limitations](docs/CAPABILITIES-AND-LIMITATIONS.en-GB.md)
- [Architecture and toolchains](docs/ARCHITECTURE-AND-TOOLCHAINS.en-GB.md)
- [Licensing and security](docs/LICENSING-AND-SECURITY.en-GB.md)
- [Documentation en español de España](README.es-ES.md)
- [Manual de uso en español](docs/MANUAL.es-ES.md)
- [Upstream SDK/repository matrix](release/UPSTREAM-SDK-MATRIX.md)
- [Changelog](docs/CHANGELOG.md)
- [Release publication instructions](docs/RELEASING.en-GB.md)
- [PowerShell line 627 hotfix](docs/patches/FIX-POWERSHELL-627.en-GB.md)

## What it does

The editor provides a 1920×1080 canvas, property inspector, hierarchy, screens, visual flows, asset management, diagnostics, export and C++20 UI generation for OpenGL/Vulkan-RADV. It integrates community templates and a SharpProspero C# workflow. Builds are delegated to the actual upstream scripts.

**It is not an official Sony SDK**, includes no proprietary files, firmware, keys, games or BIOS, does not jailbreak a console, and does not install titles on hardware automatically or guarantee compatibility across firmware versions.

## Integrity and validation

The reconstructed source archive must have this SHA-256: `f6aa6aae6d5d58a1e5e2e3582d168f0e97f67e1d105938ed6039ba963b329d13`. Reconstruction from the twenty segments committed to GitHub has been verified and matches that hash exactly.

JavaScript and generator tests were run. The preparation environment did not have the official PowerShell parser, the complete PS5 toolchains or a physical console, so no final SDK/hardware validation is claimed.

The binary ZIP is not yet attached as a GitHub Release asset; the linked instructions explain how to attach it through GitHub.
