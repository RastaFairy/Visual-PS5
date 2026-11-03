# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
# HelixSR 3.0 setup for Windows, the only thing to run:
#   1. the first time (or with -Rebuild): builds HelixSR's upscaling network (from NVIDIA's DLSS 310.7.0 DLL, downloaded
#      from NVIDIA after you agree) and HLX FSR 4's shaders (from AMD's FSR 4 driver file amdxcffx64.dll 2.4.0.4370: an
#      installed AMD driver's copy, else read out of AMD's driver package downloaded after you agree) on this PC, into
#      the folders next to this script;
#   2. lists your games and installs HelixSR into the ones you pick (HelixSR Scaler, or the FSR drop-in HLX FSR 4 for
#      games with FSR 3.1 and games with anti-cheat), updates or removes it.
#   helixsr-setup.bat [GAME_FOLDER].. [-Dlss nvngx_dlss.dll] [-Rebuild] [-Yes]
# A GAME_FOLDER (or a folder dropped onto helixsr-setup.bat) adds a game the setup does not find by itself. -Yes answers
# every question with its default. One-time downloads into %LOCALAPPDATA%\HelixSR: Python (python.org embeddable
# package) + numpy (PyPI) and the DirectX Shader Compiler (Microsoft's GitHub, two releases). No admin rights are needed.
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Dlss = "",
    [string[]]$Dlssg = @(),
    [switch]$NoFg,
    [switch]$Yes,
    [switch]$Rebuild,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Folders = @()
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is much faster without the progress bar

$Here = $PSScriptRoot
$Out = Join-Path $Here 'HelixSR'
$Data = Join-Path $env:LOCALAPPDATA 'HelixSR'
$Downloads = @{
    python = @{ url = 'https://www.python.org/ftp/python/3.14.8/python-3.14.8-embed-amd64.zip'
                sha = 'a93abe456ab01bd96d7a085b3cdb6566b3063f4241360d114142fbdb07f0a310' }
    numpy  = @{ url = 'https://files.pythonhosted.org/packages/a4/73/d2c08231e4fde7e415501fd02c715d96e98599b2d8384445933944152984/numpy-2.5.3-cp314-cp314-win_amd64.whl'
                sha = '2c25dfa72943e4336ddb6b0ee4277b47a0c85bede0807530ec68103bf58e2c10' }
    dxc    = @{ url = 'https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.9.2607/dxc_2026_07_29.zip'
                sha = 'a1dfb116ba3eeae6a1582291b53a8e7bf65ad760676bd3194685c8f7367cd241' }
    # HLX FSR 4's kernels were built with both releases (some with v1.9.2609): the setup rebuilds them with each
    dxc2609 = @{ url = 'https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.9.2609/dxc_2026_09_29.zip'
                 sha = 'ad31b1fc8443175d204f77a611fdb3ef2ec42759bdc2f1167368de24a4a7e7f1' }
}

function Say($m) { Write-Host "[helixsr-setup] $m" }
function Fetch($name, $file) {
    $d = $Downloads[$name]
    Say "downloading $(Split-Path $file -Leaf)"
    Invoke-WebRequest -Uri $d.url -OutFile $file -UseBasicParsing
    if ((Get-FileHash -Algorithm SHA256 $file).Hash.ToLower() -ne $d.sha) {
        Remove-Item $file -Force
        throw "$(Split-Path $file -Leaf): checksum mismatch"
    }
}

try {
    if (-not (Test-Path (Join-Path $Out 'helixsr.dll'))) {
        throw "$Out\helixsr.dll is missing: extract the whole ZIP and run the setup there"
    }
    New-Item -ItemType Directory -Force -Path $Data | Out-Null

    # --- Python + numpy (embeddable package: no installer, no PATH changes) ---
    $Py = Join-Path $Data 'python\python.exe'
    if (-not (Test-Path (Join-Path $Data 'python\numpy'))) {
        $zip = Join-Path $Data 'python.zip'
        Fetch 'python' $zip
        Expand-Archive -Path $zip -DestinationPath (Join-Path $Data 'python') -Force
        Remove-Item $zip -Force
        $whl = Join-Path $Data 'numpy.zip'   # a wheel is a zip
        Fetch 'numpy' $whl
        Expand-Archive -Path $whl -DestinationPath (Join-Path $Data 'python') -Force
        Remove-Item $whl -Force
    }
    $Setup = Join-Path $Here 'setup\helixsr_setup.py'
    # a package without frame generation (no setup\fg) builds the network only
    $hasFg = Test-Path (Join-Path $Here 'setup\fg\fg_setup.py')
    if (-not $hasFg) { $NoFg = $true }

    # --- what is built already: the network inside HelixSR's DLL, frame generation in helixsr-fg ---
    $status = & $Py $Setup $Out --status
    $net = "$status" -match 'network=1'
    $fg = ("$status" -match 'fg=1') -or $NoFg
    $hlx = "$status" -match 'hlx=1'
    if ($net -and $fg -and $hlx -and -not $Rebuild) {
        Say "already built (-Rebuild builds it again): $Out"
    } else {
        # --- DirectX Shader Compiler ---
        $Dxc = Join-Path $Data 'dxc\dxc.exe'
        if (-not (Test-Path $Dxc)) {
            $zip = Join-Path $Data 'dxc.zip'
            Fetch 'dxc' $zip
            $tmp = Join-Path $Data 'dxc-unpack'
            Expand-Archive -Path $zip -DestinationPath $tmp -Force
            New-Item -ItemType Directory -Force -Path (Join-Path $Data 'dxc') | Out-Null
            Copy-Item (Join-Path $tmp 'bin\x64\*') (Join-Path $Data 'dxc') -Force
            Remove-Item $zip, $tmp -Recurse -Force
        }
        $Dxc9 = Join-Path $Data 'dxc2609\dxc.exe'
        if ((Test-Path (Join-Path $Here 'setup\hlxfsr4')) -and -not (Test-Path $Dxc9)) {
            $zip = Join-Path $Data 'dxc2609.zip'
            Fetch 'dxc2609' $zip
            $tmp = Join-Path $Data 'dxc2609-unpack'
            Expand-Archive -Path $zip -DestinationPath $tmp -Force
            New-Item -ItemType Directory -Force -Path (Join-Path $Data 'dxc2609') | Out-Null
            Copy-Item (Join-Path $tmp 'bin\x64\*') (Join-Path $Data 'dxc2609') -Force
            Remove-Item $zip, $tmp -Recurse -Force
        }

        # --- build (only frame generation when the network is there already) ---
        $pass = @($Out, '--dxc', $Dxc, '--dxc-dir', (Join-Path $Data 'dxc'), '--dxc2609-dir', (Join-Path $Data 'dxc2609'))
        if ($Dlss) { $pass += @('--dlss', (Resolve-Path $Dlss).Path) }
        foreach ($g in $Dlssg) { $pass += @('--dlssg', (Resolve-Path $g).Path) }
        if ($NoFg) { $pass += '--no-fg' }
        $fgOnly = $net -and -not $Rebuild
        if ($fgOnly) { $pass += '--fg-only' }
        if ($Yes) { $pass += '--yes' }
        & $Py $Setup @pass
        $rc = $LASTEXITCODE
        if ($rc -ne 0 -and $rc -ne 3 -and $rc -ne 4 -and -not ($fgOnly -and $rc -eq 1)) { throw "setup failed (exit $rc)" }
    }

    $status = & $Py $Setup $Out --status
    if (-not ("$status" -match 'network=1')) { throw "the network is not built" }
    Say "done: $Out"
    if (-not $hasFg) { Say "  upscaling is ready" }
    elseif ("$status" -match 'fg=1') { Say "  upscaling and DLSS frame generation are ready" }
    else { Say "  upscaling is ready; DLSS frame generation is not (run the setup again to retry)" }
    if (Test-Path (Join-Path $Here 'setup\hlxfsr4')) {
        if ("$status" -match 'hlx=1') { Say "  HLX FSR 4 is ready (HLX-FSR4\ and helixsr-scaler\OptiScaler\)" }
        else { Say "  HLX FSR 4 is not built (the reason is above; run the setup again to retry)" }
    }
    Say "The HelixSR folder contains files built from NVIDIA's software: it is for this PC only, do not share or upload it."
    if (Test-Path (Join-Path $Here 'setup\hlxfsr4')) { Say "HLX FSR 4's DLLs contain data built from AMD's software: they are for this PC only too." }

    # --- games ---
    Write-Host ""
    $inst = @($Here)
    foreach ($f in $Folders) {
        if (-not (Test-Path -LiteralPath $f -PathType Container)) { throw "not a folder: $f" }
        $inst += @('--folder', (Resolve-Path -LiteralPath $f).Path)
    }
    if ($Yes) { $inst += '--yes' }
    & $Py (Join-Path $Here 'setup\helixsr_install.py') @inst
    if ($LASTEXITCODE -ne 0) { throw "game setup failed (exit $LASTEXITCODE)" }
}
catch {
    Write-Host "[helixsr-setup] error: $_" -ForegroundColor Red
    exit 1
}
