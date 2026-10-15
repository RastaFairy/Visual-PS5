# Changelog

## 1.0.1 — 16 October 2026

- Fixed PowerShell parsing in SaveProject by delimiting the sourceName variable as \${sourceName} before a colon.
- Updated visible application version strings.
- Re-ran JavaScript syntax checks and native-generator tests.
- Archive integrity was checked with unzip; this is not a substitute for the official PowerShell parser, the full PS5 SDK build or a physical-console test.

## 1.0.0 — initial release

- Visual editor, project model, save/open/export, diagnostics and a catalogue of community repositories.
- C++20 UI generation for the native OpenGL and Vulkan/RADV backends.
- Image resource handling, visual flows and build orchestration delegated to upstream toolchains.

## Validation policy

Never describe static generator tests as a successful target build. Record the operating system, PowerShell version, backend, upstream commit IDs, full logs and target firmware when reproducing a build issue.