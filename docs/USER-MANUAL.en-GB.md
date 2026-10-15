# User Manual — PS5 Homebrew Studio

This manual applies to distribution 1.0.0. Button labels and API names may remain in English because they are the application's or upstream dependencies' original identifiers.

## 1. Requirements

**To open the editor:** Windows 10/11, read/write access to the application directory, and PowerShell 7 recommended (Windows PowerShell 5.1 is the fallback).

**To build:** Git, WSL/Linux and the dependencies required by the chosen template are also needed. Exact requirements vary between SharpProspero/.NET, OpenGL and Vulkan/RADV. The first Vulkan build may compile RADV from source and consume considerable time and disk space.

## 2. Installation and launch

1. Download the ZIP from the release or reconstruct the package referenced by the README.
2. Verify the SHA-256 published for that file.
3. Extract it to a writable directory. Avoid Windows-protected locations.
4. Run \`start.bat\`.
5. If the browser does not open, visit \`http://127.0.0.1:47813/\`.
6. Keep the PowerShell server window open while using the editor.

The launcher runs \`runtime/check-syntax.ps1\` before starting the service. That script asks PowerShell's parser to validate \`runtime/server.ps1\`; startup aborts if validation fails. Close the server window or use the supplied \`STOP.bat\` mechanism to stop the service. Do not expose the port to a network or bind the service to \`0.0.0.0\`.

## 3. Interface areas

- **Canvas:** a 1920×1080 virtual surface for positioning and sizing elements. It is not an exact screenshot of the PS5 system interface.
- **Components panel:** inserts controls supported by the editor model.
- **Property inspector:** edits position, size, text, colour, value and visibility.
- **Hierarchy and screens:** organises components across screens. Navigation must be connected through flows/actions.
- **Flow editor:** connects events to actions, such as displaying a notification, changing text or value, toggling visibility, changing colour or navigating.
- **Preview:** approximates the model inside the editor. It is not a PS5 emulator and does not validate code running on the device.
- **Code and diagnostics panel:** shows generated source and warnings. Static analysis is not a substitute for a compiler or runtime testing.

## 4. Create an interface

1. Choose **New project** and provide a meaningful name.
2. Select the appropriate backend before configuring dependencies.
3. Add controls to the canvas. Drag to reposition them and use the inspector to refine size and appearance.
4. Create the required screens. Keep IDs/names unique and stable.
5. Set initial values and review component properties.
6. Define flows. Confirm that each target points to a valid ID and each action is supported by the backend.
7. Import images in the assets area and assign them to components. Importing a file does not guarantee native code can decode it; integration depends on the backend.
8. Run static analysis. Fix errors and inspect IDs, escaped strings, value bounds and destination screens.
9. Save with **Ctrl+S** or the Save button.

The default Windows workspace is \`Documents\\PS5HomebrewStudio\\Projects\`. If the service does not respond, the browser may retain the model in \`localStorage\`; that copy belongs only to that browser and is not a replacement for an exported backup.

## 5. Save, open and export

- **Save:** stores the model and associated source in the local workspace when the service is running.
- **Open:** loads projects from the workspace or compatible \`.ps5vproj\`/JSON models.
- **Export ZIP:** creates a project archive. If server-side export is unavailable, a \`.ps5vproj\` model may be downloaded.
- **Export is not a build:** do not assume a project ZIP contains \`eboot.bin\`. The binary artefact comes from the template's build process.

Back up your project before switching backend or running upstream tools that modify generated files.

## 6. Choosing a backend

### SharpProspero / C#
Uses the upstream C# and NativeAOT pipeline. It requires the .NET and SDK versions compatible with the installed revision. Payloads, plugins and graphical applications are different project types and must not be treated as interchangeable.

### Native OpenGL / C++20
Generates a UI screen using the upstream OpenGL kit's \`hui::app::Concept\` contract and integrates it into a native template. Images are converted to RGBA8, up to 512×512 pixels, with no more than 16 unique texture IDs per screen. The build invokes the real upstream scripts; it is not a simulated compilation.

### Native Vulkan/RADV / C++20
Integrates the generated screen into PS5 Vulkan Template and the expected Vulkan UI module. RGBA8 images are registered as title assets and loaded through the matching kit's \`VkRenderer::create_texture\` contract. Template, Mesa/RADV and PS5_PayloadSDK revisions must be compatible.

Documented visual actions include \`notify\`, \`setText\`, \`toggleVisibility\`, \`setValue\`, \`changeColor\` and \`navigate\`. Availability depends on component/event and backend. The native input keyboard is basic ASCII (A–Z, digits, basic punctuation, space, backspace, clear, accept and cancel); it is not a multilingual keyboard or system IME.

## 7. Building

1. Initialise/select an upstream template and review its documentation and licence.
2. Check Git/submodules, WSL/Linux, paths, host tools, SDK versions and dependencies.
3. Resolve relevant static-analysis errors before pressing **Build**.
4. Read the full log. Record exit code, project path and dependency versions on failure.
5. The IDE reports success only when the upstream process exits with code zero and a verifiable artefact, such as \`eboot.bin\` or a ZIP, is found.
6. Test the result separately in an environment and on equipment you are authorised to use.

Build success does not prove console execution, all-firmware compatibility, performance, input, audio, persistence or correct behaviour for every asset.

## 8. Run generator tests

With Node.js installed, run from the extracted directory:

\`\`\`powershell
node --check app.js
node --check runtime/native-generator.js
node runtime/test-native-generator.js
\`\`\`

These tests cover OpenGL, Vulkan and empty-model generator cases. They do not run on a PS5 and do not replace an upstream build.

## 9. Troubleshooting

- **Server does not start:** retain the complete \`start.bat\` error output; check PowerShell, permissions and syntax. For malformed PowerShell variable errors, see [the line 627 fix](patches/FIX-POWERSHELL-627.es-ES.md).
- **Browser cannot connect:** confirm the server window remains open and use the exact local URL.
- **Saving fails:** check Documents folder permissions, free disk space and service status.
- **Build fails:** inspect the complete log, Git, submodules, WSL and toolchain versions. Do not replace upstream scripts with empty files.
- **Texture missing:** check the asset link, dimensions, 16-ID limit and backend support.
- **Fails on console:** record firmware, dependency revisions, artefact, steps and logs. The editor does not guarantee universal compatibility.

## 10. Reporting a fault

Include IDE version, Windows/PowerShell, backend, minimal reproduction steps, complete output with secrets removed and dependency commits. State whether it failed during launch, editing, generation, building or execution. Do not attach keys, tokens, private data or protected game files.