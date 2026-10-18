# Static unit tests for the IDE-owned OpenGL runtime profile. No title build is run.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-runtime.ps1')
function Assert-Condition([bool]$Condition, [string]$Message) { if (!$Condition) { throw $Message } }
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$root = Join-Path ([IO.Path]::GetTempPath()) ('ps5hs-native-runtime-' + [guid]::NewGuid().ToString('N'))
$badRoot = Join-Path ([IO.Path]::GetTempPath()) ('ps5hs-native-runtime-bad-' + [guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $root 'src/app')
    $shellFixture = @'
constexpr std::uint32_t kShellActions =
    action_bit(Action::page_prev) | action_bit(Action::page_next) | action_bit(Action::touch);
void Shell::update(const InputFrame &input, float dt)
{
    const int count = static_cast<int>(concepts_.size());
    if (input.is_pressed(Action::page_next) || input.is_pressed(Action::page_prev))
    {
        direction_ = input.is_pressed(Action::page_next) ? 1 : -1;
        show(static_cast<std::size_t>((static_cast<int>(current_) + direction_ + count) % count), true);
    }
    if (input.is_pressed(Action::touch)) { info_open_ = !info_open_; }
    else if (info_open_ && input.is_pressed(Action::back)) { info_open_ = false; }
    InputFrame forwarded = input;
    forwarded.pressed &= ~kShellActions;
    forwarded.released &= ~kShellActions;
    forwarded.held &= ~kShellActions;
    concepts_[current_]->update(forwarded, dt, feedback_);
}
void Shell::draw_chrome()
{
    draw_gallery_banner();
    draw_touchpad_info_panel();
}
'@
    $renderFixture = @'
void Shell::compose(gfx::Renderer &renderer)
{
    chrome_.clear();
    draw_chrome();
    if (info_show_.value > 0.01f)
        renderer.glass(); // the info panel frosts whatever the design drew
    renderer.draw(chrome_);
}
'@
    [IO.File]::WriteAllText((Join-Path $root 'src/app/shell.cpp'), $shellFixture, $utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $root 'src/app/shell_render.cpp'), $renderFixture, $utf8NoBom)
    $result = ApplyPS5HSStandaloneNativeUiProfile $root
    Assert-Condition ([bool]$result.ok) 'El runtime no devolvió éxito.'
    Assert-Condition ([bool]$result.changed) 'La primera aplicación debe cambiar archivos y crear el manifiesto.'
    $patchedShell = [IO.File]::ReadAllText((Join-Path $root 'src/app/shell.cpp'))
    $patchedRender = [IO.File]::ReadAllText((Join-Path $root 'src/app/shell_render.cpp'))
    Assert-Condition ($patchedShell.Contains('PS5HS_STANDALONE_RUNTIME_ACTIONS_V1')) 'Falta marcador de acciones.'
    Assert-Condition ($patchedShell.Contains('PS5HS_STANDALONE_RUNTIME_UPDATE_V1')) 'Falta marcador de enrutamiento.'
    Assert-Condition ($patchedShell.Contains('concepts_[current_]->update(input, dt, feedback_);')) 'InputFrame no se pasa sin filtrar.'
    Assert-Condition (!$patchedShell.Contains('kShellActions')) 'El shell aún filtra la máscara de acciones.'
    Assert-Condition (!$patchedShell.Contains('input.is_pressed(Action::page_next)')) 'L1/R1 aún cambian el diseño.'
    Assert-Condition (!$patchedShell.Contains('input.is_pressed(Action::touch)')) 'Touchpad aún abre el panel.'
    Assert-Condition (!$patchedShell.Contains('update(forwarded')) 'Queda una ruta de entrada filtrada.'
    Assert-Condition ($patchedShell.Contains('PS5HS_STANDALONE_RUNTIME_CHROME_V1')) 'No se neutralizó el HUD.'
    Assert-Condition ($patchedRender.Contains('PS5HS_STANDALONE_RUNTIME_RENDER_V1')) 'No se neutralizó el compositor.'
    Assert-Condition (!$patchedRender.Contains('draw_chrome();')) 'El compositor aún llama al HUD.'
    Assert-Condition (!$patchedRender.Contains('renderer.draw(chrome_)')) 'El compositor aún dibuja la galería.'
    Assert-Condition (Test-Path -LiteralPath (Join-Path $root '.ps5hs-native-runtime.json') -PathType Leaf) 'Falta manifiesto.'
    $again = ApplyPS5HSStandaloneNativeUiProfile $root
    Assert-Condition (-not [bool]$again.changed) 'La aplicación repetida debe ser idempotente.'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $badRoot 'src/app')
    $badShell = '// incompatible upstream shell'
    $badRender = '// incompatible upstream renderer'
    [IO.File]::WriteAllText((Join-Path $badRoot 'src/app/shell.cpp'), $badShell, $utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $badRoot 'src/app/shell_render.cpp'), $badRender, $utf8NoBom)
    $failedClosed = $false
    try { $null = ApplyPS5HSStandaloneNativeUiProfile $badRoot } catch { $failedClosed = $true }
    Assert-Condition $failedClosed 'El perfil debe rechazar estructuras upstream desconocidas.'
    Assert-Condition (([IO.File]::ReadAllText((Join-Path $badRoot 'src/app/shell.cpp'))) -ceq $badShell) 'El fallo seguro modificó shell.cpp.'
    Assert-Condition (([IO.File]::ReadAllText((Join-Path $badRoot 'src/app/shell_render.cpp'))) -ceq $badRender) 'El fallo seguro modificó shell_render.cpp.'
    Assert-Condition (!(Test-Path -LiteralPath (Join-Path $badRoot '.ps5hs-native-runtime.json'))) 'El fallo seguro no debe crear manifiesto.'
    Write-Output 'PASS standalone native UI runtime: pass-through, gallery removal, idempotency and fail-closed.'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    if (Test-Path -LiteralPath $badRoot) { Remove-Item -LiteralPath $badRoot -Recurse -Force }
}
