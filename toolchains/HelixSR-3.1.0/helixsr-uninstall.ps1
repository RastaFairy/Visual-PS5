# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
# HelixSR uninstaller for Windows: removes HelixSR (HelixSR Scaler or the FSR drop-in, also installs of earlier
# versions) from the games you pick and puts back every file it replaced; then it can delete what the setup built here
# and the setup's downloads (%LOCALAPPDATA%\HelixSR).
#   helixsr-uninstall.bat [GAME_FOLDER]..
# A GAME_FOLDER (or a folder dropped onto helixsr-uninstall.bat) adds a game the uninstaller does not find by itself.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Folders = @())
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
$Data = Join-Path $env:LOCALAPPDATA 'HelixSR'
try {
    $Py = Join-Path $Data 'python\python.exe'
    if (-not (Test-Path $Py)) {
        $Py = $null
        foreach ($c in @('py', 'python')) {
            $cmd = Get-Command $c -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source -notlike '*WindowsApps*') { $Py = $cmd.Source; break }
        }
        if (-not $Py) { throw "no Python found (the setup's Python in $Data is gone): run helixsr-setup.bat once, then the uninstaller again" }
    }
    $inst = @($Here, 'remove', '--data', $Data)
    foreach ($f in $Folders) {
        if (-not (Test-Path -LiteralPath $f -PathType Container)) { throw "not a folder: $f" }
        $inst += @('--folder', (Resolve-Path -LiteralPath $f).Path)
    }
    & $Py (Join-Path $Here 'setup\helixsr_install.py') @inst
    $rc = $LASTEXITCODE
    if ($rc -eq 3) {
        Remove-Item -LiteralPath $Data -Recurse -Force
        Write-Host "[helixsr-uninstall] deleted $Data"
    } elseif ($rc -ne 0) { throw "uninstall failed (exit $rc)" }
}
catch {
    Write-Host "[helixsr-uninstall] error: $_" -ForegroundColor Red
    exit 1
}
