# Visual-PS5 — PS5 Homebrew Studio 1.1.6

Local visual IDE for Windows to design interfaces, manage projects, generate native UI code and orchestrate PS5 homebrew builds with community toolchains.

## Release 1.1.6

- Adds an **Structure** view to inspect editable visual screens separately from native C++ menu states, with a searchable tree, transition map, detected menu labels and source-line navigation. C++ routes are inferred statically and may need manual verification.
- Fixes the action-button selector that prevented the PS5 UltraPack and Presentation dialogs from running.
- Native OpenGL builds for IDE-generated projects use the project's own `build.ps1` and local SDK/dependencies, avoiding the redundant shared-SDK preparation step that can fail on WSL/DrvFS mounts without `metadata`.
- Adds pre-build selectors for application icon, selection background, launch background and music, plus screen management and per-screen layer ordering.
- The maintainer has confirmed that OpenGL compilation and PS5 UltraPack packaging now work in the Windows/WSL test environment. Vulkan end-to-end, ATRAC9 conversion and execution on physical PS5 hardware remain unverified; see the known-issues document.

## Choose your language

- [Español](README.es-ES.md) · [English (UK)](README.en-GB.md) · [Français](README.fr-FR.md) · [Deutsch](README.de-DE.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja-JP.md) · [Русский](README.ru-RU.md)

## Start here

- [User manuals in seven languages](docs/)
- [Credits and upstream attribution](docs/CREDITS.md)
- [Distribution README](PS5-Homebrew-Studio/README_ES.md)
- [UltraPack integration guide](PS5-Homebrew-Studio/docs/INTEGRACION-ULTRAPACK.es-ES.md)
- [Upstream SDK and project matrix](release/UPSTREAM-SDK-MATRIX.md)
- [Changelog](docs/CHANGELOG.md)
- [Current release known issues and validation status](PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md)

## Quick start

1. Download or build the package for the intended branch.
2. Extract it to a writable folder on Windows 10/11.
3. Run `PS5-Homebrew-Studio/start.bat`. If the browser does not open automatically, visit http://127.0.0.1:47813/.

PowerShell 7 is recommended; Windows PowerShell 5.1 is supported. Native builds require Git, WSL/Linux and the dependencies specified by the selected upstream template. The service binds only to 127.0.0.1.

## Project status

The maintained source tree is under PS5-Homebrew-Studio/. The segments under release/source-archive/ are a historical backup of version 1.0.1, not the canonical source for 1.1.5; do not use them to restore the current source.

The interface is still in Spanish while UI localisation is prepared. Compilation and successful packaging do not by themselves validate execution on a physical PS5. Current hardware-runtime validation status is recorded in [known issues](PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md).

Visual-PS5 is not an official Sony SDK and includes no proprietary Sony files, firmware, keys, games or BIOS. Upstream projects retain their licences and notices; see [Credits](docs/CREDITS.md).