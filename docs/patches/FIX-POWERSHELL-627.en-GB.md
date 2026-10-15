# Startup fix: PowerShell line 627

## Symptom
PowerShell reports an invalid variable reference, pointing at $sourceName: in runtime/server.ps1, inside SaveProject.

## Cause
In an expandable PowerShell string, a colon immediately after a variable name can be interpreted as part of a qualified reference (for example, $env:PATH). Here the intended output was the source filename followed by a colon.

## Applied fix
Replace:

\`\`\`powershell
- $sourceName: $description
\`\`\`

with:

\`\`\`powershell
- \${sourceName}: $description
\`\`\`

The braces delimit the variable name without changing the generated text.

## Manual application
1. Stop the editor.
2. Open runtime/server.ps1 in a UTF-8 text editor.
3. Find $sourceName: $description and replace it with \${sourceName}: $description.
4. Save and run start.bat again.

Do not change valid scoped variables such as $script:Root or $script:Url.

## Validation
The fix is included in the corrected local package. JavaScript syntax checks and generator tests pass. The official PowerShell parser must be run on Windows/PowerShell; it was not available in the preparation environment.