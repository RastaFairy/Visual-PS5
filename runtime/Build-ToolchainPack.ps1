# PS5 Homebrew Studio - Build-ToolchainPack.ps1
# Valida y empaqueta exclusivamente fuentes/artefactos que ya existen en toolchains/.
# No descarga archivos ni prueba mirrors.
param(
  [string]$SdkTarball = '',
  [string]$OutputZip = '',
  [string[]]$Include = @('ps5-homebrew-ui','ps5-native-app-boilerplate','ps5-opengl','ps5-at9-converter','SharpProspero','ps5-payload-sdk','PS5SDK','ps5link-sdk','ps5-ultrapack')
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
$sdkDir = Join-Path $toolchainsRoot 'ps5-opengl-sdk'
$sdkTarget = Join-Path $sdkDir $expectedFile

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

if ($SdkTarball) {
  $provided = [IO.Path]::GetFullPath($SdkTarball)
  $required = [IO.Path]::GetFullPath($sdkTarget)
  if ($provided -ne $required) {
    throw "Modo local-only: -SdkTarball solo acepta el archivo versionado en $required."
  }
}
if (!(Test-Path -LiteralPath $sdkTarget -PathType Leaf)) {
  throw "Falta el SDK OpenGL local fijado: $sdkTarget. No se descargara; incorpora el archivo verificado a toolchains/ps5-opengl-sdk/."
}
if (!(Test-ArchivePin $sdkTarget)) {
  throw "El SDK OpenGL local no coincide con el SHA-256 fijado ($expectedSha): $sdkTarget."
}
$actualBytes = (Get-Item -LiteralPath $sdkTarget).Length
Write-Host ("SDK local verificado: {0} ({1:N0} bytes, SHA-256 {2})" -f $sdkTarget, $actualBytes, $expectedSha)

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

New-Item -ItemType Directory -Force -Path $packRoot | Out-Null
$manifest = [pscustomobject]@{
  schema = 'ps5hs-toolchain-pack'
  version = 1
  generatedAt = (Get-Date).ToString('o')
  ideRoot = $ideRoot
  networkAccess = $false
  localOnly = $true
  sdk = [pscustomobject]@{
    name = 'ps5-opengl-sdk'
    version = [string]$artifact.version
    file = $expectedFile
    localPath = 'toolchains/ps5-opengl-sdk/' + $expectedFile
    bytes = $actualBytes
    sha256 = $expectedSha
    downloadedNow = $false
  }
  toolchains = $inventory
  notes = 'El packer solo inspecciona el árbol versionado toolchains/. No descarga fuentes, releases, mirrors ni paquetes. Los artefactos deben estar presentes localmente y superar los checksums fijados.'
}
Write-Utf8 (Join-Path $packRoot 'manifest.json') ($manifest | ConvertTo-Json -Depth 6)
Write-Host "Manifiesto local escrito: $(Join-Path $packRoot 'manifest.json')"

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
    Write-Host ("Respaldo local creado: {0} ({1:N0} bytes)" -f $OutputZip, (Get-Item -LiteralPath $OutputZip).Length)
  } finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
  }
}
Write-Host 'Listo. No se consultaron servicios externos.' -ForegroundColor Green
