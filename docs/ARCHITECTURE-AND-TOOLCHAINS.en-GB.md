# Architecture and build toolchains

## 1. System overview

The application consists of a local web UI and a PowerShell orchestration service. It is not a self-contained low-level toolchain: it manages the visual model, generates UI code and delegates initialisation/build work to community upstream projects.

\`\`\`text
Browser: index.html + styles.css + app.js
  | local HTTP requests / JSON
  v
runtime/server.ps1
  |-- save, load and export models
  |-- catalogue and template initialisation
  |-- integrate native source and assets
  '-- run upstream build and verify artefacts

runtime/native-generator.js
  '-- visual model -> C++20 / hui::app::Concept contract

runtime/test-native-generator.js
  '-- generator tests; not a PS5 test
\`\`\`

## 2. Principal files

- \`index.html\`: web editor structure and UI entry points.
- \`styles.css\`: layout, canvas, panels, inspector and dialogs.
- \`app.js\`: model, interactions, editor rendering, project state, flows, assets, diagnostics, code display and local API calls.
- \`runtime/server.ps1\`: local HTTP service, repository catalogue, save/load/export, project initialisers, code/asset integration and build execution.
- \`runtime/native-generator.js\`: converts screens, components, properties, assets and flows to C++20 for the OpenGL/Vulkan visual backends.
- \`runtime/test-native-generator.js\`: OpenGL, Vulkan and empty-model test cases.
- \`runtime/check-syntax.ps1\`: validates server syntax with PowerShell's official parser before startup.
- \`start.bat\`, \`STOP.bat\`: service start/stop.
- \`toolchains/\`: third-party sources fetched during setup; the base ZIP does not necessarily include every toolchain.

The default workspace is \`Documents\\PS5HomebrewStudio\\Projects\`. Runtime data and exports live under \`.runtime\`.

## 3. Local HTTP service

The service listens on \`127.0.0.1:47813\`. The UI exchanges JSON with it. Internal routes cover status, catalogue, projects, save/load/export, SDK setup, template creation and native/visual builds. These are implementation details rather than a stable public API. Do not expose the service to untrusted networks.

If the service becomes unavailable, the UI may fall back to browser \`localStorage\` to retain the model. That fallback cannot replace every server operation or a separate backup.

## 4. Model and code generation

The model contains a backend, screens, components, theme, assets and flows. Components carry an ID, type, screen, geometry and properties. Generated code must escape literals, respect value bounds and resolve existing identifiers. The generator creates the UI/Concept layer; it does not on its own produce a complete title runtime, title metadata or package.

### OpenGL
The generator integrates a C++20 screen against \`hui::app::Concept\` from \`ps5-homebrew-ui\`, coupled to the upstream OpenGL stack. Image assets become RGBA8 files in \`assets/ps5hs/<id>.rgba\`, limited to 512×512 pixels and 16 unique IDs per screen. The loader uses the base project's OpenGL contract and restores GL state it changes. The server runs the real template build.

### Vulkan/RADV
The workflow creates a title with \`PS5_VulkanTemplate\`, locates the actual sample/program ID and integrates generated C++20 into the corresponding Vulkan UI module. Images are registered in \`ps5/assets.json\` and loaded as RGBA8 textures through the selected kit's \`VkRenderer::create_texture\` contract. This backend depends on compatible revisions of PS5_VulkanTemplate, PS5_Vulkan, PS5_Mesa/RADV, PS5_PayloadSDK and PS5_VKHomebrewUI. Do not mix branches/commits without validating the full stack; some setups require full Git history.

### SharpProspero and the C++ base
SharpProspero uses its upstream C#/.NET/NativeAOT pipeline. The C++ boilerplate initialises a native title using upstream build scripts. Neither automatically translates arbitrary C# or arbitrary applications into a portable UI.

## 5. Assets

The UI can receive and organise images; visual backends convert selected textures to RGBA8. The native path validates headers, length and dimensions and rejects duplicate IDs. The documented maximum is 512×512 and 16 unique IDs. Other files can remain in the project but are not automatically connected to a universal native API.

## 6. Builds and artefacts

Builds are not simulated: the server runs actual upstream scripts and captures their logs. The IDE reports success only when the process exits with code zero and a verifiable artefact such as \`eboot.bin\` or a ZIP is found. Where helper scripts are restored from the companion upstream boilerplate, that mechanism records provenance/hash; never replace upstream build scripts with empty stubs.

## 7. Reproducible checks

\`\`\`powershell
node --check app.js
node --check runtime/native-generator.js
node runtime/test-native-generator.js
\`\`\`

These commands check JavaScript and the generator. On Windows, \`start.bat\` runs the PowerShell parser check. To validate a real build, prepare WSL/Linux and all upstream prerequisites, pin dependency commits and keep the logs. A final hardware test must be recorded separately.