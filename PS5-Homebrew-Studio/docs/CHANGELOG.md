# Changelog — PS5 Homebrew Studio

## 1.1.0 — 2026-10-16

- Removed the Kyty launch integration from active UI, configuration and routes; the workflow focuses on built titles and hardware testing.
- Fixed the UltraPack UI selector bug and moved packaging into a pollable background job.
- Added a source-content verification option that passes --verify to UltraPack; enabled by default.
- Forced UTF-8 for Python/CLI output to preserve non-ASCII characters in logs.
- Preserved Windows PowerShell 5.1 compatibility and added Python 3.10+ validation.
- UltraPack repair preserves the existing checkout and local native helper.
- Native-title readiness requires eboot.bin and sce_sys/param.json.
- Removed empty Vulkan texture-loader stubs and reject invalid flow targets before C++ generation.
- Added user manuals in Spanish, English, French, German, Simplified Chinese, Japanese and Russian, plus upstream credits.

### Validation notes

Automated checks cover JavaScript syntax, generator tests, PowerShell 7 and Windows PowerShell 5.1 parsing, integration hooks, version metadata and ZIP packaging. The maintainer reports successful .ffpfsc packaging tested on real hardware. This is a specific test, not a universal compatibility guarantee.

Earlier 1.0.x release notes remain in Git history.