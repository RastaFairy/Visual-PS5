# Capabilities and limitations — version 1.1.0

This document distinguishes what the IDE provides, what depends on external tooling, and what must not be assumed.

## Available capabilities

| Area | What it provides | Conditions/limits |
|---|---|---|
| Visual editor | 1920×1080 canvas, positioning, dimensions, properties, hierarchy, screens and preview | Preview is not a PS5 emulator |
| Project model | Create, edit, save, open, analyse and export the model | Main save path requires the local service; browser backup is limited |
| Flows | Visual events and actions | Not a general-purpose programming language; IDs and actions must exist |
| Assets | Import and reference images | Import does not guarantee native-code decoding |
| Catalogue | 34 community repositories across different categories | A reference project is not always a build template |
| OpenGL C++20 | Generates \`hui::app::Concept\` screens, flows and textures | Up to 512×512 px per texture and 16 unique IDs per screen |
| Vulkan/RADV C++20 | Integrates screen and assets into a specific Vulkan template | Requires compatible renderer, Mesa/RADV and PS5_PayloadSDK revisions |
| SharpProspero/C# | Uses the upstream C# pipeline | Requires suitable SDK/.NET; payloads/plugins are not interchangeable with GUIs |
| Build | Runs the actual upstream pipeline and verifies artefacts | Requires its toolchain and host dependencies |

Documented visual actions include \`notify\`, \`setText\`, \`toggleVisibility\`, \`setValue\`, \`changeColor\` and \`navigate\`. Availability depends on component, event and backend. The input control keyboard is basic ASCII: A–Z, digits, basic punctuation, space, backspace, clear, accept and cancel.

## What it does not do

- It is not an official or Sony-endorsed SDK/product.
- It does not jailbreak a console, modify firmware, bypass authentication or install applications on a PS5 automatically.
- It includes no firmware, keys, games, BIOS or proprietary Sony files.
- It cannot build without the toolchains and dependencies required by each template.
- It does not turn arbitrary games, C# programs or applications into portable native code.
- It does not generate a complete game from a drawing: the generator covers the UI layer implemented by the selected kit.
- It does not provide exact emulation, real-hardware profiling or guaranteed compatibility across firmware versions.
- It does not include a system multilingual keyboard or IME; the native keyboard is basic ASCII.
- It does not guarantee that imported audio, video, JSON or binary assets can automatically be consumed by native code.
- It does not guarantee that third-party repositories remain available, compatible or buildable in future.
- It does not provide formal security audits, automated licence clearance or legal advice.
- CI validation and physical-console testing are separate. The maintainer later confirmed a specific .ffpfsc packaging test on a real PS5; this does not validate every title, firmware, backend or IDE feature.

## Meaning of “build succeeded”

The IDE requires the upstream process to exit with code zero and a verifiable artefact (for example, \`eboot.bin\` or a ZIP). This only shows that the pipeline produced an artefact under those criteria. It does not prove that it boots on hardware, that every screen works or that every firmware is compatible.

## Practical states

- **No SDK:** edit, save and analyse the model and run generator tests with Node.js.
- **Sources present, incomplete toolchain:** source can be generated, but the real build will fail until prerequisites are met.
- **Successful build:** a verifiable artefact exists; separate tests are still needed.
- **Console test:** document firmware, environment, revisions, steps and reproducible evidence.

The catalogue links to third parties whose branches, dependencies and licences can change. Record their commits, check upstream licences/notices and verify compatibility before distributing software.

## Hardware test reported by the maintainer — 16 October 2026

The maintainer reported that a title packaged as .ffpfsc worked on real hardware. This is a specific test of the artefact and environment used, not a universal compatibility claim or validation of every backend and firmware.
