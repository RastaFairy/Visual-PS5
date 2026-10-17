# Visual-PS5 — PS5 Homebrew Studio 1.1.7

A local visual IDE for Windows for interface design, project management, code inspection, C++20 UI generation and build orchestration through community PS5 toolchains.

## What's new in 1.1.7

- Import a TrueType (`.ttf`) font and select it for a native project. The build bakes project-specific Unicode SDF atlases for OpenGL and Vulkan and fails with a clear missing-codepoint diagnostic when the selected font lacks a required glyph.
- Regression coverage now includes Cyrillic, Greek, Japanese, Simplified/Traditional Chinese and Korean. This concerns game-text rendering, not translation of the Spanish IDE UI; CJK IME input and full right-to-left shaping remain outside scope.
- [Unicode font setup guide](docs/UNICODE-FONTS.en-GB.md)

- Adds the **Structure** view to separate editable visual screens from native C++ menu states. It provides a searchable tree, transition map, detected menu labels and source-line navigation; C++ routes are static inferences and require manual verification.
- Adds an **Structure** view that separates editable visual screens from native C++ menu states, with a searchable tree, transition map, detected menu labels and source-line navigation. C++ routes are inferred statically and may require manual verification.
- Fixes the action buttons in the UltraPack and Presentation dialogs.
- Native OpenGL builds for IDE-generated projects use their own `build.ps1` and local dependencies, avoiding a redundant shared-SDK setup step that can fail on WSL/DrvFS mounts without `metadata`.
- Adds pre-build selection of the app icon, selection/launch backgrounds and music, together with screen management and per-screen layer ordering.
- OpenGL compilation and UltraPack packaging are confirmed by the maintainer in the Windows/WSL test environment. Full Vulkan builds, ATRAC9 conversion and execution on physical PS5 hardware remain unverified. See [known issues and validation status](PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md).

## Languages and documentation

- [User manual — English (UK)](docs/USER-MANUAL.en-GB.md)
- [Manual de usuario — español](docs/MANUAL.es-ES.md)
- [Manuel utilisateur — français](docs/USER-MANUAL.fr-FR.md)
- [Benutzerhandbuch — Deutsch](docs/USER-MANUAL.de-DE.md)
- [用户手册 — 简体中文](docs/USER-MANUAL.zh-CN.md)
- [ユーザーマニュアル — 日本語](docs/USER-MANUAL.ja-JP.md)
- [Руководство пользователя — русский](docs/USER-MANUAL.ru-RU.md)
- [Credits and upstream attribution](docs/CREDITS.md)
- [Architecture and toolchains](docs/ARCHITECTURE-AND-TOOLCHAINS.en-GB.md)
- [Licensing and security](docs/LICENSING-AND-SECURITY.en-GB.md)
- [Upstream SDK/repository matrix](release/UPSTREAM-SDK-MATRIX.md)
- [Changelog](docs/CHANGELOG.md)
- [Known issues and validation status](PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md)

## Quick start

1. Download or build the package for the branch you want to test.
2. Extract it to a writable folder on Windows 10/11.
3. Run `PS5-Homebrew-Studio/start.bat`. If the browser does not open, visit http://127.0.0.1:47813/.

PowerShell 7 is recommended; Windows PowerShell 5.1 is also supported. Native builds require Git, WSL/Linux and the dependencies of the selected template. The service listens only on 127.0.0.1.

The UI remains in Spanish while localisation is prepared. Successful compilation and packaging do not by themselves prove operation on physical PS5 hardware; see the known-issues document for the current validation status.

Visual-PS5 is not an official Sony SDK and includes no proprietary Sony files, firmware, keys, games or BIOS. Each upstream project retains its own licence and notices; see [Credits](docs/CREDITS.md) before redistribution.