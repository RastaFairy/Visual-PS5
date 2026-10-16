# Visual-PS5 — PS5 Homebrew Studio 1.1.0

A local visual IDE for Windows for interface design, project management, code inspection, C++20 UI generation and build orchestration through community PS5 toolchains.

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

## Quick start

1. Download or build the package for the branch you want to test.
2. Extract it to a writable folder on Windows 10/11.
3. Run start.bat. If the browser does not open, visit http://127.0.0.1:47813/.

PowerShell 7 is recommended; Windows PowerShell 5.1 is also supported. Native builds require Git, WSL/Linux and the dependencies of the selected template. The service listens only on 127.0.0.1.

The UI remains in Spanish while localisation is prepared. The maintainer reports that a generated .ffpfsc image was tested successfully on real hardware; this does not guarantee compatibility across all titles or firmware versions.

Visual-PS5 is not an official Sony SDK and includes no proprietary Sony files, firmware, keys, games or BIOS. Each upstream project retains its own licence and notices; see [Credits](docs/CREDITS.md) before redistribution.