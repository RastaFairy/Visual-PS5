# PS5 Homebrew Studio - Build-ToolchainPack.ps1
# Consolida el material de toolchains local (fuentes ya adoptadas en toolchains\)
# y el SDK binario ps5-opengl en toolchains\ps5-opengl-sdk\, con verificacion SHA-256 del pin.
#
# Uso (desde la carpeta del IDE, en Windows PowerShell 5.1+):
#   powershell -ExecutionPolicy Bypass -File runtime\Build-ToolchainPack.ps1
# Opciones:
#   -SdkTarball <ruta>   Ruta a ps5-opengl-sdk-1.0.2.tar.gz ya descargado
#                        (si se omite, sólo se buscan copias locales verificables en toolchains/).
#   -OutputZip <ruta>    Ademas del pack en disco, crea un ZIP de respaldo
#                        completo (toolchains + pack). Puede tardar.
#   -Include <lista>     Carpetas de toolchains a incluir en el inventario y el
#                        ZIP (por defecto las 8 gestionadas por el IDE).
#
# El pack resultante:
#   toolchains\ps5-opengl-sdk\ps5-opengl-sdk-1.0.2.tar.gz  (binario verificado)
#   toolchains\ps5-opengl-sdk\manifest.json                                (inventario + origenes)
# El IDE sólo usa toolchains\ps5-opengl-sdk\ y siembra el tarball local en .deps\
# de cada proyecto OpenGL antes de compilar y asi el build no necesita red.
param(
  [string]$SdkTarball = '',
  [string]$OutputZip = '',
  [string[]]$Include = @('ps5-homebrew-ui','ps5-native-app-boilerplate','ps5-opengl','SharpProspero','ps5-payload-sdk','PS5SDK','ps5link-sdk','ps5-ultrapack','ps5-opengl-sdk')
)
$ErrorActionPreference = 'Stop'
$ideRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$toolchainsRoot = Join-Path $ideRoot 'toolchains'
$packRoot = Join-Path $toolchainsRoot 'ps5-opengl-sdk'
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

# 1. Ubicar el tarball solo en toolchains/ o en la ruta local especificada.
$sdkDir = $packRoot
$sdkTarget = Join-Path $sdkDir $expectedFile
New-Item -ItemType Directory -Force -Path $sdkDir | Out-Null
$copiedFromLocalPath = ''
if ($SdkTarball) {
  if (!(Test-Path -LiteralPath $SdkTarball -PathType Leaf)) { throw "No se encontro el tarball local indicado en -SdkTarball: $SdkTarball" }
  if (!(Test-ArchivePin $SdkTarball)) { throw "El tarball indicado no coincide con el pin SHA-256 ($expectedSha). No se usara." }
  $providedPath = [IO.Path]::GetFullPath($SdkTarball)
  if ($providedPath -ne [IO.Path]::GetFullPath($sdkTarget)) {
    Copy-Item -LiteralPath $providedPath -Destination $sdkTarget -Force
  }
  $copiedFromLocalPath = $providedPath
} elseif (Test-ArchivePin $sdkTarget) {
  Write-Host "SDK local ya presente y verificado: $sdkTarget"
  $copiedFromLocalPath = $sdkTarget
} else {
  $localCandidates = @(
    (Join-Path $toolchainsRoot ('ps5-homebrew-ui\.deps\ps5-opengl\' + $expectedFile)),
    (Join-Path $toolchainsRoot ('ps5-opengl\.deps\ps5-opengl\' + $expectedFile))
  )
  $sourcePath = ''
  foreach ($candidate in $localCandidates) {
    if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and (Test-ArchivePin $candidate)) {
      $sourcePath = $candidate
      break
    }
  }
  if (!$sourcePath) {
    throw "No se encontro el SDK OpenGL en toolchains/. El IDE no descarga binarios. Coloca localmente el archivo $expectedFile en toolchains\ps5-opengl-sdk\ o pásalo con -SdkTarball después de verificar su procedencia."
  }
  Copy-Item -LiteralPath $sourcePath -Destination $sdkTarget -Force
  $copiedFromLocalPath = [IO.Path]::GetFullPath($sourcePath)
}
if (!(Test-ArchivePin $sdkTarget)) { throw "Verificacion final fallida para $sdkTarget." }
$actualBytes = (Get-Item -LiteralPath $sdkTarget).Length
Write-Host ("SDK local verificado: {0} ({1:N0} bytes, SHA-256 {2})" -f $sdkTarget, $actualBytes, $expectedSha)

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
  schema = 'ps5hs-local-sdk-pack'
  version = 1
  generatedAt = (Get-Date).ToString('o')
  ideRoot = $ideRoot
  sdk = [pscustomobject]@{
    name = 'ps5-opengl-sdk'
    version = [string]$artifact.version
    file = $expectedFile
    bytes = $actualBytes
    sha256 = $expectedSha
    copiedFromLocalPath = $copiedFromLocalPath
    networkAccess = $false
  }
  toolchains = $inventory
  notes = 'Fuentes y artefacto SDK proceden únicamente de toolchains\. No se descargan ni instalan dependencias en red. El tarball debe coincidir con el pin SHA-256. Se conservan licencias y avisos incluidos en las fuentes.'
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
    if (Test-Path -LiteralPath $OutputZip) { Remove-Item -LiteralPath $OutputZip -Force }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $OutputZip -CompressionLevel Optimal
    Write-Host ("Respaldo completo creado: {0} ({1:N0} bytes)" -f $OutputZip, (Get-Item -LiteralPath $OutputZip).Length)
  } finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
  }
}
Write-Host 'Listo. El IDE detectara el SDK local en toolchains\ps5-opengl-sdk\ al refrescar el estado.' -ForegroundColor Green
