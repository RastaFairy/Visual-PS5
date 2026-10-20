#requires -Version 5.1
<#
.SYNOPSIS
    Builds this library into a relocatable module (.prx).
.DESCRIPTION
    Delegates to the SDK's shared build pipeline, which compiles and links the module. A library is not
    packaged as an application, so the output is the folder holding the built <name>.prx; copy it into an
    application's sce_module folder. Set SHARPPROSPERO_ROOT to the SDK folder, or pass -SdkRoot. Run the
    SDK's doctor.ps1 to check the .NET SDK first (the build gathers the runtime automatically; on Windows the compile step uses WSL).
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
    -Output Folder `
    -OutputFolder (Join-Path $here "out") `
    -Configuration $Configuration `
    -SdkRoot $SdkRoot
