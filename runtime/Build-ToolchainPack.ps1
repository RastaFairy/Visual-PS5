# PS5 Homebrew Studio - Build-ToolchainPack.ps1
# Consolida material de toolchains y el SDK OpenGL previamente incorporado a toolchains\toolchain-pack\.
# Nunca descarga fuentes ni binarios.
#
# Uso (desde la carpeta del IDE, en Windows PowerShell 5.1+):
#   powershell -ExecutionPolicy Bypass -File runtime\Build-ToolchainPack.ps1
# Opciones:
#   -SdkTarball <ruta>   Archivo existente bajo toolchains\ que ya verifique el pin SHA-256.
#                        (si se omite, el archivo debe estar en el pack local).
#   -OutputZip <ruta>    Ademas del pack en disco, crea un ZIP de respaldo
#                        completo (toolchains + pack). Puede tardar.
#   -Include <lista>     Carpetas de toolchains a incluir en el inventario y el
#                        ZIP (por defecto las 8 gestionadas por el IDE).
#
# El pack resultante:
#   toolchains\toolchain-pack\ps5-opengl-sdk\ps5-opengl-sdk-1.0.2.tar.gz  (binario verificado)
#   toolchains\toolchain-pack\manifest.json                                   (inventario + origenes)
# El IDE detecta toolchains\toolchain-pack\ automaticamente: siembra el tarball en .deps\
# de cada proyecto OpenGL antes de compilar y asi el build no necesita red.
param(
  [string]$SdkTarball = '',
  [string]$OutputZip = '',
  [string[]]$Include = @('ps5-homebrew-ui','ps5-native-app-boilerplate','ps5-opengl','SharpProspero','ps5-payload-sdk','PS5SDK','ps5link-sdk','ps5-ultrapack')
)
$ErrorActionPreference = 'Stop'
$ideRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$toolchainsRoot = Join-Path $ideRoot 'toolchains'
$packRoot = Join-Path $toolchainsRoot 'toolchain-pack'
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

# 1. Validar únicamente un archivo local dentro de toolchains/.
$sdkDir = Join-Path $packRoot 'ps5-opengl-sdk'
$sdkTarget = Join-Path $sdkDir $expectedFile
$downloaded = $false
$toolchainsPrefix = [IO.Path]::GetFullPath($toolchainsRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($SdkTarball) {
  $sourceArchive = [IO.Path]::GetFullPath($SdkTarball)
  if (!$sourceArchive.StartsWith($toolchainsPrefix,[StringComparison]::OrdinalIgnoreCase)) {
    throw "Por política local-only, -SdkTarball debe apuntar a un archivo bajo '$toolchainsRoot'."
  }
  if (!(Test-Path -LiteralPath $sourceArchive -PathType Leaf)) { throw "No se encontro el archivo local indicado en -SdkTarball: $sourceArchive" }
  if (!(Test-ArchivePin $sourceArchive)) { throw "El tarball local no coincide con el pin SHA-256 ($expectedSha). No se usara." }
  New-Item -ItemType Directory -Force -Path $sdkDir | Out-Null
  if ($sourceArchive -ne [IO.Path]::GetFullPath($sdkTarget)) {
    Copy-Item -LiteralPath $sourceArchive -Destination $sdkTarget -Force
  }
} elseif (Test-ArchivePin $sdkTarget) {
  Write-Host "SDK local ya presente y verificado: $sdkTarget"
} else {
  throw "Falta el tarball del SDK OpenGL bajo '$sdkDir'. Añade manualmente el archivo fijado por SHA-256; no se realiza ninguna descarga."
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
  }
  toolchains = $inventory
  notes = 'El pack solo acepta artefactos locales bajo toolchains\; el IDE los verifica por SHA-256 y los siembra en .deps\ antes de compilar. No descarga fuentes ni binarios.'
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
      $stagingToolchains = Join-Path $staging 'toolchains'
      New-Item -ItemType Directory -Force -Path $stagingToolchains | Out-Null
      Copy-Item -LiteralPath $src -Destination (Join-Path $stagingToolchains $item.folder) -Recurse -Force
    }
    $stagingToolchains = Join-Path $staging 'toolchains'
    New-Item -ItemType Directory -Force -Path $stagingToolchains | Out-Null
    Copy-Item -LiteralPath $packRoot -Destination (Join-Path $stagingToolchains 'toolchain-pack') -Recurse -Force
    if (Test-Path -LiteralPath $OutputZip) { Remove-Item -LiteralPath $OutputZip -Force }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $OutputZip -CompressionLevel Optimal
    Write-Host ("Respaldo completo creado: {0} ({1:N0} bytes)" -f $OutputZip, (Get-Item -LiteralPath $OutputZip).Length)
  } finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
  }
}
Write-Host 'Listo. El IDE detectara toolchains\toolchain-pack\ en el proximo arranque o al refrescar el estado.' -ForegroundColor Green
