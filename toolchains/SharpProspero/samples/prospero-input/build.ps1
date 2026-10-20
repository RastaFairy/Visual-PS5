#requires -Version 5.1
<#
.SYNOPSIS
    Builds this application into an installable package.
.DESCRIPTION
    Delegates to the SDK's shared build pipeline. Set SHARPPROSPERO_ROOT to the SDK folder, or pass
    -SdkRoot. Run the SDK's doctor.ps1 to check the .NET SDK first (the build gathers the runtime automatically; on Windows the compile step uses WSL).
#>
param(
    [string]$SdkRoot = "",
    [string]$Configuration = "Release",
    [ValidateSet("Package", "Folder")][string]$Output = "Package"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $SdkRoot) { $SdkRoot = $env:SHARPPROSPERO_ROOT }
if (-not $SdkRoot -or -not (Test-Path (Join-Path $SdkRoot "build/build-app.ps1"))) {
    throw "Set SHARPPROSPERO_ROOT to the SharpProspero SDK folder, or pass -SdkRoot. See the SDK's doctor.ps1."
}

& (Join-Path $SdkRoot "build/build-app.ps1") `
    -ProjectPath (Join-Path $here "SampleApp.csproj") `
    -Output $Output `
    -OutputFolder (Join-Path $here "out") `
    -Configuration $Configuration `
    -SdkRoot $SdkRoot
