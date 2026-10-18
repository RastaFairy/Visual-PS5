# PS5 Homebrew Studio: IDE-owned standalone native UI runtime profile.
# Keeps upstream renderer/widgets but removes gallery-shell input and HUD policy.
function WritePS5HSNativeRuntimeTextAtomic([string]$Path, [string]$Content) {
    $temporaryPath = $Path + '.ps5hs-tmp'
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($temporaryPath, $Content, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force | Out-Null
}
function ApplyPS5HSStandaloneNativeUiProfile {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { throw 'La ruta del proyecto está vacía.' }
    $root = [IO.Path]::GetFullPath($ProjectRoot)
    $shellPath = Join-Path $root 'src/app/shell.cpp'
    $renderPath = Join-Path $root 'src/app/shell_render.cpp'
    $manifestPath = Join-Path $root '.ps5hs-native-runtime.json'
    foreach ($requiredPath in @($shellPath, $renderPath)) {
        if (!(Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Falta el punto de integración $requiredPath." }
    }
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try { $existingManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
        catch { throw 'El manifiesto existente no es JSON válido.' }
        if ([string]$existingManifest.schema -ne 'ps5hs-native-runtime' -or [string]$existingManifest.profile -ne 'standalone-native-ui-v1') {
            throw 'El manifiesto existente pertenece a otro perfil de runtime.'
        }
    }
    $originalShell = [IO.File]::ReadAllText($shellPath)
    $originalRender = [IO.File]::ReadAllText($renderPath)
    $shellText = $originalShell
    $renderText = $originalRender
    $actionsMarker = 'PS5HS_STANDALONE_RUNTIME_ACTIONS_V1'
    $updateMarker = 'PS5HS_STANDALONE_RUNTIME_UPDATE_V1'
    $chromeMarker = 'PS5HS_STANDALONE_RUNTIME_CHROME_V1'
    $renderMarker = 'PS5HS_STANDALONE_RUNTIME_RENDER_V1'
    if (!$shellText.Contains($actionsMarker)) {
        $pattern = '(?m)^constexpr std::uint32_t kShellActions =\r?\n    action_bit\(Action::page_prev\) \| action_bit\(Action::page_next\) \| action_bit\(Action::touch\);\r?$'
        if ([regex]::Matches($shellText, $pattern).Count -ne 1) { throw 'Cambió el mapeo de acciones. Runtime autónomo no aplicado.' }
        $shellText = ([regex]::new($pattern)).Replace($shellText, '// ' + $actionsMarker + ': L1/R1/Touchpad are not shell-owned shortcuts.', 1)
    }
    if (!$shellText.Contains($updateMarker)) {
        $pattern = '(?s)    const int count = static_cast<int>\(concepts_\.size\(\)\);\r?\n.*?    concepts_\[current_\]->update\(forwarded, dt, feedback_\);'
        if ([regex]::Matches($shellText, $pattern).Count -ne 1) { throw 'No se reconoce el bloque de enrutamiento del mando. Build detenido por seguridad.' }
        $replacement = @'
    // PS5HS_STANDALONE_RUNTIME_UPDATE_V1: generated screen receives input unchanged.
    concepts_[current_]->update(input, dt, feedback_);
'@
        $shellText = ([regex]::new($pattern)).Replace($shellText, $replacement.TrimEnd(), 1)
    }
    if (!$shellText.Contains($chromeMarker)) {
        $pattern = '(?s)void Shell::draw_chrome\(\)\r?\n\{.*?\r?\n\}'
        if ([regex]::Matches($shellText, $pattern).Count -ne 1) { throw 'No se reconoce Shell::draw_chrome(). Build detenido.' }
        $replacement = @'
void Shell::draw_chrome()
{
    // PS5HS_STANDALONE_RUNTIME_CHROME_V1: no gallery banner or info panel in generated titles.
}
'@
        $shellText = ([regex]::new($pattern)).Replace($shellText, $replacement.TrimEnd(), 1)
    }
    if (!$renderText.Contains($renderMarker)) {
        $pattern = '    chrome_\.clear\(\);\r?\n    draw_chrome\(\);\r?\n    if \(info_show_\.value > 0\.01f\)\r?\n        renderer\.glass\(\); // the info panel frosts whatever the design drew\r?\n    renderer\.draw\(chrome_\);'
        if ([regex]::Matches($renderText, $pattern).Count -ne 1) { throw 'No se reconoce la composición del HUD. Build detenido.' }
        $renderText = ([regex]::new($pattern)).Replace($renderText, '// ' + $renderMarker + ': generated screen is the only UI layer.', 1)
    }
    foreach ($forbidden in @('kShellActions','input.is_pressed(Action::page_prev)','input.is_pressed(Action::page_next)','input.is_pressed(Action::touch)','concepts_[current_]->update(forwarded, dt, feedback_)')) {
        if ($shellText.Contains($forbidden)) { throw "Queda una captura de entrada del shell ($forbidden)." }
    }
    if (!$shellText.Contains($updateMarker) -or !$shellText.Contains('concepts_[current_]->update(input, dt, feedback_);') -or !$shellText.Contains($chromeMarker)) {
        throw 'No se verificó el paso directo de InputFrame y la desactivación del HUD.'
    }
    if (!$renderText.Contains($renderMarker) -or $renderText.Contains('draw_chrome();') -or $renderText.Contains('renderer.draw(chrome_)')) {
        throw 'El compositor aún puede dibujar la galería.'
    }
    $changedFiles = @()
    if ($shellText -cne $originalShell) { WritePS5HSNativeRuntimeTextAtomic $shellPath $shellText; $changedFiles += 'src/app/shell.cpp' }
    if ($renderText -cne $originalRender) { WritePS5HSNativeRuntimeTextAtomic $renderPath $renderText; $changedFiles += 'src/app/shell_render.cpp' }
    $manifest = [ordered]@{
        schema = 'ps5hs-native-runtime'
        profile = 'standalone-native-ui-v1'
        owner = 'PS5 Homebrew Studio'
        sourceFramework = 'blackbearreloaded/ps5-homebrew-ui'
        policy = [ordered]@{gallerySwitcher=$false;touchpadInfoPanel=$false;shellHud=$false;forwardUnmappedControllerActions=$true;defaultL1Action=$false;defaultR1Action=$false;defaultTouchpadAction=$false}
        managedFiles = @('src/app/shell.cpp', 'src/app/shell_render.cpp')
    }
    $manifestText = (ConvertTo-Json -InputObject $manifest -Depth 10) + [Environment]::NewLine
    $manifestNeedsWrite = !(Test-Path -LiteralPath $manifestPath -PathType Leaf)
    if (!$manifestNeedsWrite) { $manifestNeedsWrite = [IO.File]::ReadAllText($manifestPath) -cne $manifestText }
    if ($manifestNeedsWrite) { WritePS5HSNativeRuntimeTextAtomic $manifestPath $manifestText; $changedFiles += '.ps5hs-native-runtime.json' }
    return @{ok=$true;profile='standalone-native-ui-v1';changed=($changedFiles.Count -gt 0);changedFiles=@($changedFiles);manifest='.ps5hs-native-runtime.json';policy='No gallery L1/R1 switcher, no Touchpad info panel, input forwarded unchanged.'}
}
