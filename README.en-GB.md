# Visual-PS5 — PS5 Homebrew Studio

**Version 1.0.0 · 15 October 2026**

Visual-PS5 is a local visual IDE for designing interfaces, saving models, inspecting generated source and coordinating builds through community PlayStation 5 toolchains.

## Getting started
1. Download or reconstruct the distribution ZIP and verify its SHA-256.
2. Extract the `PS5-Homebrew-Studio` directory to a writable location.
3. Run `start.bat` on Windows. PowerShell 7 is recommended; the launcher also accommodates Windows PowerShell 5.1.
4. Open `http://127.0.0.1:47813/` if the browser does not start automatically.
5. Keep the server window open while using the editor.

## Documentation
- [User manual](docs/USER-MANUAL.en-GB.md)
- [Capabilities and limitations](docs/CAPABILITIES-AND-LIMITATIONS.en-GB.md)
- [Architecture and toolchains](docs/ARCHITECTURE-AND-TOOLCHAINS.en-GB.md)
- [Licensing and security](docs/LICENSING-AND-SECURITY.en-GB.md)
- [Manual en español de España](docs/MANUAL.es-ES.md)
- [Alcance y limitaciones (es-ES)](docs/ALCANCE-Y-LIMITACIONES.es-ES.md)
- [Arquitectura y toolchains (es-ES)](docs/ARQUITECTURA-Y-TOOLCHAINS.es-ES.md)
- [Licencias y seguridad (es-ES)](docs/LICENCIAS-Y-SEGURIDAD.es-ES.md)
- [Upstream SDK catalogue](release/UPSTREAM-SDK-MATRIX.md)
- [PowerShell line 627 fix](docs/patches/FIX-POWERSHELL-627.es-ES.md)

## Scope
The application provides a local web UI, visual model, hierarchy, screens, flows, assets, export, diagnostics and C++20 UI generation for native OpenGL and Vulkan/RADV visual backends. It also integrates community template workflows, including a SharpProspero-based C# workflow.

**It is not an official Sony SDK.** No proprietary Sony files, firmware, keys, games, BIOS or Sony toolchain are included. It does not jailbreak a console, bypass platform protections, automatically install titles on a PS5 or guarantee compatibility across firmware versions. Builds depend on compatible upstream toolchains.

## Language policy
Documentation is maintained in Spanish (Spain, `es-ES`) and British English (`en-GB`). API identifiers and some generated source retain the upstream projects' original names.

## Validation status
JavaScript syntax checks and generator tests were run. The preparation environment did not have the official PowerShell parser, the complete PS5 toolchain or a physical console; therefore, no final SDK build or hardware test is claimed.
