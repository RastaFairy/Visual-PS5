#requires -Version 5.1
<#
.SYNOPSIS
    Writes response files that describe a header-to-C# run for each module in modules.json.
.DESCRIPTION
    Builds the generator and writes one response file per module under
    src/SharpProspero/Interop/Generated. The response files describe the parse for external
    processing; the generator itself makes no external calls. To produce bindings from a supplied
    module instead, use `sharpprospero-bindgen prx --module <file.prx> --names <file>`.
.PARAMETER SdkInclude
    The SDK include tree. Defaults to %PROSPERO_SDK_DIR%/target/include.
#>
param(
    [string]$SdkInclude = ""
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $SdkInclude) {
    if ($env:PROSPERO_SDK_DIR) {
        $SdkInclude = Join-Path $env:PROSPERO_SDK_DIR "target\include"
    } else {
        throw "Set -SdkInclude or the PROSPERO_SDK_DIR environment variable."
    }
}

Write-Host "Building the generator"
& dotnet build (Join-Path $here "SharpProspero.Bindings.Generator.csproj") -c Release -nologo | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Generator build failed." }

Write-Host "Writing response files from $SdkInclude"
& dotnet run --project (Join-Path $here "SharpProspero.Bindings.Generator.csproj") -c Release -- --sdk $SdkInclude
if ($LASTEXITCODE -ne 0) { throw "Generation failed." }
