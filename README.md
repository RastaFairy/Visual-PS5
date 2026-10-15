# Visual-PS5 — PS5 Homebrew Studio

**Version 1.0.0 · Release date: 15 October 2026**

A visual, local-first IDE for creating and managing PlayStation 5 homebrew projects. The interface is designed around a drag-and-drop canvas, property inspector, component hierarchy, visual flows, project assets, code inspection and build diagnostics.

**Languages / Idiomas**
- [Español (España)](README.es-ES.md)
- [English (United Kingdom)](README.en-GB.md)

## Start here / Para empezar

The complete v1.0.0 Windows distribution is stored in the `release/` directory as a text-safe, split Base64 archive. Restore the original ZIP, verify its SHA-256, then follow the relevant manual:

- [Manual de uso (es-ES)](docs/MANUAL.es-ES.md)
- [User manual (en-GB)](docs/USER-MANUAL.en-GB.md)
- [Alcance y limitaciones](docs/ALCANCE-Y-LIMITACIONES.es-ES.md)
- [Capabilities and limitations](docs/CAPABILITIES-AND-LIMITATIONS.en-GB.md)

PowerShell 7 is preferred; Windows PowerShell 5.1 is the fallback supported by the launcher. The editor UI runs locally at `http://127.0.0.1:47813/`.

## What the project is / Qué es este proyecto

Visual-PS5 (application name: **PS5 Homebrew Studio**) is an editor and orchestration layer. It is not a Sony-authorised SDK, does not contain proprietary PlayStation files, and cannot make an arbitrary application compatible with every PS5 firmware. Native builds are delegated to upstream community toolchains and their own build scripts.

The application catalogue differentiates UI kits, project templates, native toolchains, graphics drivers and reference applications. They are related but not interchangeable.

## Documentation / Documentación

| Subject | Español de España | British English |
|---|---|---|
| Installation and daily use | [Manual](docs/MANUAL.es-ES.md) | [User manual](docs/USER-MANUAL.en-GB.md) |
| Features and non-features | [Alcance y límites](docs/ALCANCE-Y-LIMITACIONES.es-ES.md) | [Capabilities and limitations](docs/CAPABILITIES-AND-LIMITATIONS.en-GB.md) |
| Architecture and toolchains | [Arquitectura](docs/ARQUITECTURA-Y-TOOLCHAINS.es-ES.md) | [Architecture](docs/ARCHITECTURE-AND-TOOLCHAINS.en-GB.md) |
| Security and licensing | [Licencias y seguridad](docs/LICENCIAS-Y-SEGURIDAD.es-ES.md) | [Licensing and security](docs/LICENSING-AND-SECURITY.en-GB.md) |
| Upstream ecosystem research | [SDK matrix](release/UPSTREAM-SDK-MATRIX.md) | [SDK matrix](release/UPSTREAM-SDK-MATRIX.md) |
| Reconstruct the release ZIP | [PowerShell script](scripts/Restore-ReleaseArchive.ps1) | [Shell script](scripts/restore-release-archive.sh) |

## Repository delivery format

The original release ZIP is split into numbered Base64 text segments under `release/` so it can be committed using the repository's text-file interface. The restore scripts concatenate the segments and decode them to the original ZIP. This is a packaging choice only; the decoded ZIP contains the Windows project tree.

**SHA-256 (release ZIP):** see `release/PS5-Homebrew-Studio-v1.0.0.zip.sha256`.

## Validation status

Static JavaScript and generator tests were run during preparation. The preparation environment could not run the Windows PowerShell parser, the full PS5 cross-compilation toolchains or a physical-console test. A successful local app launch or upstream build must therefore be confirmed on the target Windows/WSL installation; the documentation does not claim unperformed hardware validation.
