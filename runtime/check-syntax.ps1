#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$target = Join-Path $PSScriptRoot 'server.ps1'
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
Write-Host 'Sintaxis de runtime/server.ps1 correcta.' -ForegroundColor Green
exit 0
