#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$targets = @(
    (Join-Path $PSScriptRoot 'server.ps1'),
    (Join-Path $PSScriptRoot 'native-runtime.ps1'),
    (Join-Path $PSScriptRoot 'Prepare-OfflineImage.ps1'),
    (Join-Path $PSScriptRoot 'Build-OfflineBundle.ps1'),
    (Join-Path $PSScriptRoot 'Install-OfflineEnvironment.ps1'),
    (Join-Path $PSScriptRoot 'offline/OfflineBundle.psm1'),
    (Join-Path $PSScriptRoot 'offline/OfflineEnvironment.psm1')
)
foreach ($target in $targets) {
    if (!(Test-Path -LiteralPath $target -PathType Leaf)) { continue }
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) {
        Write-Host "Errores de sintaxis en $target" -ForegroundColor Red
        foreach ($parseError in $parseErrors) {
            Write-Host ("Línea {0}, columna {1}: {2}" -f $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message) -ForegroundColor Red
            if ($parseError.Extent.Text) { Write-Host ("  > " + $parseError.Extent.Text) -ForegroundColor DarkRed }
        }
        exit 1
    }
    Write-Host ("Sintaxis correcta: " + [IO.Path]::GetFileName($target)) -ForegroundColor Green
}
Write-Host 'Todos los scripts PowerShell requeridos por el IDE han pasado el parser.' -ForegroundColor Green
exit 0
