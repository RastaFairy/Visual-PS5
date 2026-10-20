#requires -Version 5.1
<#
.SYNOPSIS
    Builds this project into a payload (a position-independent .elf a loader maps and runs).
.DESCRIPTION
    Delegates to the SDK's shared build pipeline in payload mode. Set SHARPPROSPERO_ROOT to the SDK
    folder, or pass -SdkRoot. Run the SDK's doctor.ps1 to check the .NET SDK first (the build gathers the
    runtime automatically; on Windows the compile step uses WSL). Send the result to a listening loader
    with the toolchain's `payload --send` command.
#>
param(
    [string]$SdkRoot = "",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $SdkRoot) { $SdkRoot = $env:SHARPPROSPERO_ROOT }
if (-not $SdkRoot -or -not (Test-Path (Join-Path $SdkRoot "build/build-app.ps1"))) {
    throw "Set SHARPPROSPERO_ROOT to the SharpProspero SDK folder, or pass -SdkRoot. See the SDK's doctor.ps1."
}

& (Join-Path $SdkRoot "build/build-app.ps1") `
    -ProjectPath (Join-Path $here "SampleApp.csproj") `
    -Payload `
    -OutputFolder (Join-Path $here "out") `
    -Configuration $Configuration
