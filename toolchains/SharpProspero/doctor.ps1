#requires -Version 5.1
<#
.SYNOPSIS
    Checks that the machine is ready to build SharpProspero applications.
.DESCRIPTION
    Reports the .NET SDK and, on Windows, the WSL host the compile step uses. A plain build and the
    tests need only .NET. Producing a module also needs the ahead-of-time compile to run on Linux: on
    Windows the build does that through WSL automatically, so WSL is the one extra item there. The
    runtime archives are gathered from the .NET SDK's own runtime pack, and the SDK's linker supplies
    its own start object, compat object and stubs, so there is no separate runtime pack or outside tool.
#>

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ok = $true
$wslReady = $true   # non-Windows hosts compile locally; Windows sets this from the WSL check below

function Report([string]$name, [bool]$present, [string]$detail, [string]$fix, [bool]$required) {
    $mark = if ($present) { "[ ok ]" } elseif ($required) { "[fail]" } else { "[warn]" }
    Write-Host "$mark $name"
    if ($detail) { Write-Host "        $detail" }
    if (-not $present) {
        if ($fix) { Write-Host "        -> $fix" }
        if ($required) { $script:ok = $false }
    }
}

Write-Host "SharpProspero environment check"
Write-Host "-------------------------------"

# .NET SDK
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
$dotnetVersion = if ($dotnet) { (& dotnet --version) } else { "" }
$dotnetOk = $dotnet -and ($dotnetVersion -like "10.*")
Report ".NET 10 SDK" $dotnetOk $dotnetVersion "Install the .NET 10 SDK from https://dotnet.microsoft.com/download" $true

# Linux compile host. The ahead-of-time compile runs on Linux; on Windows the build uses WSL for it.
# The name here avoids $IsWindows, which newer PowerShell defines as a read-only variable of its own.
$onWindows = [System.Environment]::OSVersion.Platform -eq "Win32NT"
if ($onWindows) {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    $wslDotnet = $false
    if ($wsl) {
        $v = (& wsl.exe -e bash -lc "dotnet --version 2>/dev/null" | Out-String).Trim()
        $wslDotnet = $v -like "10.*"
    }
    Report "Linux compile host (WSL + .NET 10)" $wslDotnet $(if ($wsl) { "wsl present" } else { "" }) `
        "Install WSL (wsl --install) and the .NET 10 SDK inside it; the build runs the compile step there automatically." $false
    $wslReady = $wslDotnet
}

# SDK root for samples
$root = $env:SHARPPROSPERO_ROOT
$rootOk = $root -and (Test-Path (Join-Path $root "build/build-app.ps1"))
Report "SDK root (SHARPPROSPERO_ROOT)" $rootOk $root "Set SHARPPROSPERO_ROOT to $here so samples and app builds find the SDK." $false

Write-Host "-------------------------------"
if ($ok) {
    if (-not $wslReady) {
        Write-Host "Ready to build and test the SDK. Producing a module also needs the WSL + .NET 10 compile host above; set it up before packaging."
    } else {
        Write-Host "Ready to build and test. Building a module runs the compile step on Linux (via WSL on Windows)."
    }
    exit 0
} else {
    Write-Host "A required item is missing. Fix the [fail] lines above."
    exit 1
}
