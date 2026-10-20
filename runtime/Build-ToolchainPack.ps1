# PS5 Homebrew Studio - Build-ToolchainPack.ps1
# Consolida el material de toolchains local (fuentes ya adoptadas en toolchains\)
# y el SDK binario ps5-opengl en toolchain-pack\, con verificacion SHA-256 del pin.
#
# Uso (desde la carpeta del IDE, en Windows PowerShell 5.1+):
#   powershell -ExecutionPolicy Bypass -File runtime\Build-ToolchainPack.ps1
# Opciones:
#   -SdkTarball <ruta>   Ruta a ps5-opengl-sdk-1.0.2.tar.gz ya descargado
#                        (si se omite, se intenta la cadena de mirrors del pin).
#   -OutputZip <ruta>    Ademas del pack en disco, crea un ZIP de respaldo
#                        completo (toolchains + pack). Puede tardar.
#   -Include <lista>     Carpetas de toolchains a incluir en el inventario y el
#                        ZIP (por defecto las 8 gestionadas por el IDE).
#
# El pack resultante:
#   toolchain-pack\ps5-opengl-sdk\ps5-opengl-sdk-1.0.2.tar.gz  (binario verificado)
#   toolchain-pack\manifest.json                                (inventario + origenes)
# El IDE detecta toolchain-pack\ automaticamente: siembra el tarball en .deps\
# de cada proyecto OpenGL antes de compilar y asi el build no necesita red.
param(
  [string]$SdkTarball = '',
  [string]$OutputZip = '',
  [string[]]$Include = @('ps5-homebrew-ui','ps5-native-app-boilerplate','ps5-opengl','SharpProspero','ps5-payload-sdk','PS5SDK','ps5link-sdk','ps5-ultrapack')
)
$ErrorActionPreference = 'Stop'
$ideRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$toolchainsRoot = Join-Path $ideRoot 'toolchains'
$packRoot = Join-Path $ideRoot 'toolchain-pack'
$pinsPath = Join-Path $PSScriptRoot 'toolchain-pins.json'
if (!(Test-Path -LiteralPath $pinsPath -PathType Leaf)) { throw "No se encontro runtime\toolchain-pins.json." }
$pins = Get-Content -LiteralPath $pinsPath -Raw | ConvertFrom-Json
$artifact = $pins.artifacts.'ps5-opengl-sdk'
if (!$artifact) { throw 'El manifiesto de pins no declara el artefacto ps5-opengl-sdk.' }
$expectedSha = [string]$artifact.archive.sha256
$expectedFile = [string]$artifact.file
$expectedBytes = [int64]$artifact.bytes

function Write-Utf8([string]$Path,[string]$Content) {
  $dir = Split-Path -Parent $Path
  if ($dir -and !(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}
function Test-ArchivePin([string]$Path) {
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  return ($hash -eq $expectedSha)
}

# 1. Ubicar o descargar el tarball del SDK con la cadena de mirrors del pin.
$sdkDir = Join-Path $packRoot 'ps5-opengl-sdk'
$sdkTarget = Join-Path $sdkDir $expectedFile
$downloaded = $false
if ($SdkTarball) {
  if (!(Test-Path -LiteralPath $SdkTarball -PathType Leaf)) { throw "No se encontro el tarball indicado en -SdkTarball: $SdkTarball" }
  if (!(Test-ArchivePin $SdkTarball)) { throw "El tarball indicado no coincide con el pin SHA-256 ($expectedSha). No se usara." }
  New-Item -ItemType Directory -Force -Path $sdkDir | Out-Null
  Copy-Item -LiteralPath $SdkTarball -Destination $sdkTarget -Force
} elseif (Test-ArchivePin $sdkTarget) {
  Write-Host "SDK ya presente y verificado: $sdkTarget"
} else {
  New-Item -ItemType Directory -Force -Path $sdkDir | Out-Null
  $tempArchive = Join-Path $env:TEMP ('ps5hs-' + [guid]::NewGuid().ToString('N') + '.tar.gz')
  $ok = $false
  foreach ($url in @($artifact.urls)) {
    Write-Host "Descargando SDK desde: $url"
    try {
      Invoke-WebRequest -Uri ([string]$url) -OutFile $tempArchive -UseBasicParsing -TimeoutSec 1800
      if (Test-ArchivePin $tempArchive) { $ok = $true; break }
      Write-Host '  El archivo descargado no coincide con el pin SHA-256; se descarta.' -ForegroundColor Yellow
    } catch { Write-Host ('  Fallo: ' + $_.Exception.Message) -ForegroundColor Yellow }
    Remove-Item -LiteralPath $tempArchive -Force -ErrorAction SilentlyContinue
  }
  if (!$ok) { throw "No se pudo obtener un tarball del SDK que verifique el pin SHA-256 $expectedSha desde ninguna URL del manifiesto." }
  Copy-Item -LiteralPath $tempArchive -Destination $sdkTarget -Force
  Remove-Item -LiteralPath $tempArchive -Force -ErrorAction SilentlyContinue
  $downloaded = $true
}
if (!(Test-ArchivePin $sdkTarget)) { throw "Verificacion final fallida para $sdkTarget." }
$actualBytes = (Get-Item -LiteralPath $sdkTarget).Length
Write-Host ("SDK verificado: {0} ({1:N0} bytes, SHA-256 {2})" -f $sdkTarget, $actualBytes, $expectedSha)

# 2. Inventario de los toolchains adoptados localmente (origen, commit, licencia).
$inventory = @()
foreach ($folder in $Include) {
  $dir = Join-Path $toolchainsRoot $folder
  if (!(Test-Path -LiteralPath $dir -PathType Container)) {
    Write-Host "Aviso: falta la carpeta de toolchain $dir; se omite del inventario." -ForegroundColor Yellow
    continue
  }
  $originPath = Join-Path $dir '.ps5hs-source.json'
  $origin = $null
  if (Test-Path -LiteralPath $originPath -PathType Leaf) {
    try { $origin = Get-Content -LiteralPath $originPath -Raw | ConvertFrom-Json } catch { $origin = $null }
  }
  $hasGit = (Test-Path -LiteralPath (Join-Path $dir '.git') -PathType Container)
  $hasReadme = (Test-Path -LiteralPath (Join-Path $dir 'README.md') -PathType Leaf)
  $sizeBytes = 0
  try { $sizeBytes = (Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch { $sizeBytes = 0 }
  $inventory += [pscustomobject]@{
    folder = $folder
    present = $true
    gitCheckout = $hasGit
    readable = $hasReadme
    bytes = [int64]$sizeBytes
    repository = if ($origin) { [string]$origin.repository } else { '' }
    branch = if ($origin) { [string]$origin.branch } else { '' }
    commit = if ($origin) { [string]$origin.commit } else { '' }
    installedAt = if ($origin) { [string]$origin.installedAt } else { '' }
  }
}

# 3. Manifiesto del pack.
$manifest = [pscustomobject]@{
  schema = 'ps5hs-toolchain-pack'
  version = 1
  generatedAt = (Get-Date).ToString('o')
  ideRoot = $ideRoot
  sdk = [pscustomobject]@{
    name = 'ps5-opengl-sdk'
    version = [string]$artifact.version
    file = $expectedFile
    bytes = $actualBytes
    sha256 = $expectedSha
    downloadedNow = $downloaded
    mirrors = @($artifact.urls)
  }
  toolchains = $inventory
  notes = 'Las fuentes de los toolchains permanecen en toolchains\; el IDE las adopta sin sobrescribirlas. Este pack anade el binario del SDK que el IDE siembra en .deps\ de cada proyecto OpenGL antes de compilar. Conserva las licencias LICENSE/THIRD_PARTY_NOTICES de cada checkout upstream.'
}
Write-Utf8 (Join-Path $packRoot 'manifest.json') ($manifest | ConvertTo-Json -Depth 6)
Write-Host "Manifiesto escrito: $(Join-Path $packRoot 'manifest.json')"

# 4. ZIP de respaldo completo (opcional).
if ($OutputZip) {
  $OutputZip = [IO.Path]::GetFullPath($OutputZip)
  $staging = Join-Path $env:TEMP ('ps5hs-pack-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $staging | Out-Null
  try {
    foreach ($item in $inventory) {
      $src = Join-Path $toolchainsRoot $item.folder
      Copy-Item -LiteralPath $src -Destination (Join-Path $staging $item.folder) -Recurse -Force
    }
    Copy-Item -LiteralPath $packRoot -Destination $staging -Recurse -Force
    if (Test-Path -LiteralPath $OutputZip) { Remove-Item -LiteralPath $OutputZip -Force }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $OutputZip -CompressionLevel Optimal
    Write-Host ("Respaldo completo creado: {0} ({1:N0} bytes)" -f $OutputZip, (Get-Item -LiteralPath $OutputZip).Length)
  } finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
  }
}
Write-Host 'Listo. El IDE detectara toolchain-pack\ en el proximo arranque o al refrescar el estado.' -ForegroundColor Green
