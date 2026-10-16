# Visual-PS5 — PS5 Homebrew Studio 1.1.0

Local visual IDE for Windows to design interfaces, manage projects, generate native UI code and orchestrate PS5 homebrew builds with community toolchains.

## Choose your language

- [Español](README.es-ES.md) · [English (UK)](README.en-GB.md) · [Français](README.fr-FR.md) · [Deutsch](README.de-DE.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja-JP.md) · [Русский](README.ru-RU.md)

## Start here

- [User manuals in seven languages](docs/)
- [Credits and upstream attribution](docs/CREDITS.md)
- [Distribution README](PS5-Homebrew-Studio/README_ES.md)
- [UltraPack integration guide](PS5-Homebrew-Studio/docs/INTEGRACION-ULTRAPACK.es-ES.md)
- [Upstream SDK and project matrix](release/UPSTREAM-SDK-MATRIX.md)
- [Changelog](docs/CHANGELOG.md)

## Quick start

1. Download or build the package for the intended branch.
2. Extract it to a writable folder on Windows 10/11.
3. Run start.bat. If the browser does not open automatically, visit http://127.0.0.1:47813/.

PowerShell 7 is recommended; Windows PowerShell 5.1 is supported. Native builds require Git, WSL/Linux and the dependencies specified by the selected upstream template. The service binds only to 127.0.0.1.

## Project status

The maintained source tree is under PS5-Homebrew-Studio/. The segments under release/source-archive/ are a historical backup of version 1.0.1, not the canonical source for 1.1.0; do not use them to restore the current source.

The interface is still in Spanish while UI localisation is prepared. The maintainer reports that a generated .ffpfsc image was tested successfully on real hardware. This specific result does not guarantee compatibility for every title or firmware.

Visual-PS5 is not an official Sony SDK and includes no proprietary Sony files, firmware, keys, games or BIOS. Upstream projects retain their licences and notices; see [Credits](docs/CREDITS.md).