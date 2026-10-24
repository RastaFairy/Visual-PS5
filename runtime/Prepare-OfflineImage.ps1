#requires -Version 5.1
[CmdletBinding()]
param(
  [string]$SourceDistro = 'Ubuntu',
  [string]$OutputRoot = '',
  [string]$ResumeStage = '',
  [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$ideRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $ideRoot 'toolchains\WSL2' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$expectedOutputRoot = [IO.Path]::GetFullPath((Join-Path $ideRoot 'toolchains\WSL2'))
$stagingParent = [IO.Path]::GetFullPath((Join-Path $ideRoot '.runtime'))
$lockPath = Join-Path $PSScriptRoot 'offline\image-lock.json'
$cleanerPath = Join-Path $PSScriptRoot 'offline\prepare-image.sh'
$pacbrewInstallerPath = Join-Path $PSScriptRoot 'offline\install-pacbrew-homebrew.py'
$pinsPath = Join-Path $PSScriptRoot 'toolchain-pins.json'
$imageFileName = 'visual-ps5-ubuntu-26.04.1-amd64.tar'
$imagePath = Join-Path $OutputRoot $imageFileName
$outputManifestPath = Join-Path $OutputRoot 'image-manifest.json'
$outputHashPath = Join-Path $OutputRoot ($imageFileName + '.sha256')

function Write-Utf8NoBom([string]$Path, [string]$Content) {
  [IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}
function ConvertTo-WslPath([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  if ($full -notmatch '^([A-Za-z]):\\(.*)$') { throw "No se puede convertir la ruta a WSL: $full" }
  return ('/mnt/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\','/'))
}
function Quote-Bash([string]$Value) {
  $replacement = [string]::Concat("'", '"', "'", '"', "'")
  return "'" + $Value.Replace("'", $replacement) + "'"
}
function Invoke-WslChecked([string[]]$Arguments, [string]$Operation, [switch]$Quiet) {
  $output = @(& wsl.exe @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  $text = (($output | ForEach-Object { $_.ToString() -replace "`0", '' }) -join "`n").Trim()
  if ($exitCode -ne 0) { throw "$Operation fallo (codigo $exitCode). $text" }
  if ($text -and !$Quiet) { Write-Host $text }
  return $text
}
function Get-WslDistros {
  $output = @(& wsl.exe --list --quiet 2>&1)
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) { throw "No se pudo consultar WSL: $($output -join ' ')" }
  return @($output | ForEach-Object { ($_.ToString() -replace "`0", '').Trim() } | Where-Object { $_ })
}
function Assert-PathInside([string]$Child, [string]$Parent, [string]$Description) {
  $childFull = [IO.Path]::GetFullPath($Child).TrimEnd('\') + '\'
  $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
  if (!$childFull.StartsWith($parentFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "$Description debe quedar dentro de $parentFull; recibido: $childFull"
  }
}

if (!(Test-Path -LiteralPath $lockPath -PathType Leaf)) { throw "No existe el lock de imagen: $lockPath" }
if (!(Test-Path -LiteralPath $cleanerPath -PathType Leaf)) { throw "No existe el limpiador de imagen: $cleanerPath" }
if (!(Test-Path -LiteralPath $pacbrewInstallerPath -PathType Leaf)) { throw "No existe el instalador offline PacBrew: $pacbrewInstallerPath" }
if (!(Test-Path -LiteralPath $OutputRoot -PathType Container)) { throw "No existe el destino esperado: $OutputRoot" }
if ($OutputRoot -ne $expectedOutputRoot) { throw "El destino de imagen debe ser exactamente $expectedOutputRoot" }
foreach ($outputPath in @($imagePath, $outputManifestPath, $outputHashPath)) {
  if (Test-Path -LiteralPath $outputPath) { throw "El resultado ya existe; no se sobrescribe: $outputPath" }
}

$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
if ($lock.schema -ne 'ps5hs-offline-image-lock' -or $lock.ubuntu.versionId -ne '26.04' -or $lock.ubuntu.architecture -ne 'amd64') {
  throw 'image-lock.json no identifica la imagen Ubuntu auditada.'
}
if (!(Test-Path -LiteralPath $pinsPath -PathType Leaf)) { throw "No existe el pin de artefactos: $pinsPath" }
$pins = Get-Content -LiteralPath $pinsPath -Raw | ConvertFrom-Json
foreach ($entry in $pins.artifacts.PSObject.Properties) {
  $artifactPath = Join-Path $ideRoot ([string]$entry.Value.localPath)
  if (!(Test-Path -LiteralPath $artifactPath -PathType Leaf)) { throw "Falta el artefacto offline fijado $($entry.Name): $artifactPath" }
  $actualHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualHash -ne [string]$entry.Value.archive.sha256) { throw "El SHA-256 del artefacto $($entry.Name) no coincide con runtime/toolchain-pins.json." }
}
$pacbrewPinProperty = $pins.artifacts.PSObject.Properties['pacbrew']
if (!$pacbrewPinProperty) { throw 'runtime/toolchain-pins.json no fija el artefacto PacBrew.' }
$pacbrewPin = $pacbrewPinProperty.Value
if ($lock.pacbrew.version -ne [string]$pacbrewPin.version -or
    $lock.pacbrew.sha256 -ne [string]$pacbrewPin.archive.sha256 -or
    $lock.pacbrew.artifact -ne [string]$pacbrewPin.localPath -or
    !$lock.pacbrew.targetPrefix -or @($lock.pacbrew.requiredFiles).Count -lt 10) {
  throw 'image-lock.json y runtime/toolchain-pins.json discrepan en PacBrew o en sus dependencias PS5.'
}
$pacbrewArchivePath = Join-Path $ideRoot ([string]$pacbrewPin.localPath -replace '/', '\')
if (!(Test-Path -LiteralPath $pacbrewArchivePath -PathType Leaf)) {
  throw "Falta el archivo PacBrew offline: $pacbrewArchivePath"
}
$driveName = [IO.Path]::GetPathRoot($stagingParent).Substring(0,1)
$drive = Get-PSDrive -Name $driveName -ErrorAction Stop

$wsl = Get-Command 'wsl.exe' -ErrorAction SilentlyContinue
if (!$wsl) { throw 'No se encontro wsl.exe en el PATH.' }
$distros = Get-WslDistros
if ($SourceDistro -notin $distros) { throw "No existe la distro fuente WSL '$SourceDistro'." }
$stagingName = 'PS5HS-ImagePrep-' + [guid]::NewGuid().ToString('N')
if ($stagingName -in $distros) { throw "Ya existe el nombre temporal de distro $stagingName." }

$requiredFreeBytes = 30GB
if ($drive.Free -lt $requiredFreeBytes) {
  throw ("Espacio insuficiente para exportar, importar y volver a exportar la imagen. Libre: {0:N0}; requerido: {1:N0} bytes." -f $drive.Free, $requiredFreeBytes)
}

$signaturePath = Join-Path $ideRoot 'toolchains\WSL2\wsl.2.9.13.0.x64.msi'
if (!(Test-Path -LiteralPath $signaturePath -PathType Leaf)) { throw "Falta el MSI WSL offline: $signaturePath" }
$signature = Get-AuthenticodeSignature -LiteralPath $signaturePath
if ($signature.Status -ne 'Valid' -or !$signature.SignerCertificate.Subject.Contains('Microsoft Corporation')) {
  throw "La firma del MSI WSL no es valida o no pertenece a Microsoft: $($signature.Status)"
}

$stageId = [guid]::NewGuid().ToString('N')
$stagingRoot = Join-Path $stagingParent ('offline-image-' + $stageId)
$sourceExport = Join-Path $stagingRoot 'source-ubuntu.tar'
$distroRoot = Join-Path $stagingRoot 'distro'
$finalStagedImage = Join-Path $stagingRoot $imageFileName
if ($ResumeStage) {
  $stagingRoot = [IO.Path]::GetFullPath($ResumeStage)
  Assert-PathInside $stagingRoot $stagingParent 'El staging reanudado'
  if ([IO.Path]::GetFileName($stagingRoot) -notmatch '^offline-image-[a-f0-9]{32}$') {
    throw "El staging no tiene el nombre esperado offline-image-<guid>: $stagingRoot"
  }
  $stageRecordPath = Join-Path $stagingRoot 'stage.json'
  if (!(Test-Path -LiteralPath $stageRecordPath -PathType Leaf)) { throw "Falta el registro para reanudar: $stageRecordPath" }
  $record = Get-Content -LiteralPath $stageRecordPath -Raw | ConvertFrom-Json
  if ($record.schema -ne 'ps5hs-offline-image-stage' -or $record.sourceDistro -ne $SourceDistro -or
      [IO.Path]::GetFullPath([string]$record.stagingRoot) -ne $stagingRoot -or
      [IO.Path]::GetFullPath([string]$record.outputImage) -ne $imagePath -or
      [string]$record.originalDistroModified -ne 'False') {
    throw 'El registro del staging no coincide con la distro, ruta o estado esperado.'
  }
  $stageId = [string]$record.stageId
  $stagingName = [string]$record.stagingDistro
  if ($stageId -notmatch '^[a-f0-9]{32}$' -or $stagingName -notmatch '^PS5HS-ImagePrep-[a-f0-9]{32}$') {
    throw 'El identificador del staging no es valido.'
  }
  $sourceExport = [string]$record.sourceExport
  $distroRoot = Join-Path $stagingRoot 'distro'
  $finalStagedImage = Join-Path $stagingRoot $imageFileName
  if ($stagingName -notin $distros) { throw "La distro de staging no esta registrada: $stagingName" }
  Assert-PathInside $sourceExport $stagingRoot 'La exportacion de origen'
  Assert-PathInside $distroRoot $stagingRoot 'El disco de staging'
  Assert-PathInside $finalStagedImage $stagingRoot 'La imagen temporal'
}
$lockWsl = ConvertTo-WslPath $lockPath
$cleanerWsl = ConvertTo-WslPath $cleanerPath
$pacbrewInstallerWsl = ConvertTo-WslPath $pacbrewInstallerPath
$pacbrewArchiveWsl = ConvertTo-WslPath $pacbrewArchivePath

Write-Host "Distro fuente: $SourceDistro (se conservara intacta)"
Write-Host "Distro de staging: $stagingName"
Write-Host "Imagen de salida: $imagePath"
Write-Host ("Espacio libre: {0:N1} GB; reserva de staging: {1:N1} GB" -f ($drive.Free / 1GB), ($requiredFreeBytes / 1GB))
if ($ResumeStage) { Write-Host "Reanudando staging existente: $stagingRoot" }
if (!$Apply) {
  Write-Host 'Preflight correcto. La operacion real requiere -Apply y crea una distro de staging separada.' -ForegroundColor Yellow
  exit 0
}

if (!$ResumeStage) {
  if (Test-Path -LiteralPath $stagingRoot) { throw "El staging ya existe y no se reutiliza: $stagingRoot" }
  New-Item -ItemType Directory -Path $stagingRoot | Out-Null
  $record = [pscustomobject]@{
    schema = 'ps5hs-offline-image-stage'
    stageId = $stageId
    sourceDistro = $SourceDistro
    stagingDistro = $stagingName
    sourceExport = $sourceExport
    stagingRoot = $stagingRoot
    outputImage = $imagePath
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    originalDistroModified = $false
  }
  Write-Utf8NoBom (Join-Path $stagingRoot 'stage.json') ($record | ConvertTo-Json -Depth 5)

  Invoke-WslChecked @('--export', $SourceDistro, $sourceExport) 'Exportacion no destructiva de la distro fuente' | Out-Null
  if (!(Test-Path -LiteralPath $sourceExport -PathType Leaf) -or (Get-Item -LiteralPath $sourceExport).Length -lt 1MB) {
    throw "La exportacion de origen esta vacia o truncada: $sourceExport"
  }

  New-Item -ItemType Directory -Path $distroRoot | Out-Null
  Invoke-WslChecked @('--import', $stagingName, $distroRoot, $sourceExport, '--version', '2') 'Importacion de la copia de staging' | Out-Null
  if ($stagingName -notin (Get-WslDistros)) { throw "WSL no registro la distro de staging $stagingName." }

  $sentinelCommand = "printf '%s\n' $(Quote-Bash $stageId) > /etc/ps5hs-offline-image-stage-id"
  Invoke-WslChecked @('-d', $stagingName, '--user', 'root', '--exec', '/bin/bash', '-c', $sentinelCommand) 'Marcado de staging' | Out-Null
}

$identityPresent = $false
try {
  $null = Invoke-WslChecked @('-d', $stagingName, '--user', 'root', '--exec', '/usr/bin/test', '-s', '/etc/ps5hs-image-identity.json') 'Comprobacion de identidad existente' -Quiet
  $identityPresent = $true
} catch { $identityPresent = $false }
if (!$identityPresent) {
  $marker = Invoke-WslChecked @('-d', $stagingName, '--user', 'root', '--exec', '/bin/cat', '/etc/ps5hs-offline-image-stage-id') 'Comprobacion de marca de staging' -Quiet
  if ($marker.Trim() -ne $stageId) { throw 'La marca de staging no coincide; se cancela la limpieza.' }
  Invoke-WslChecked @(
    '-d', $stagingName, '--user', 'root', '--exec', '/usr/bin/python3',
    $pacbrewInstallerWsl,
    '--archive', $pacbrewArchiveWsl,
    '--sha256', [string]$pacbrewPin.archive.sha256,
    '--version', [string]$pacbrewPin.version,
    '--target', [string]$lock.pacbrew.targetPrefix,
    '--stage-id', $stageId
  ) 'Instalacion de dependencias de payload PS5 desde el archivo PacBrew local' | Out-Null
  Invoke-WslChecked @('-d', $stagingName, '--user', 'root', '--exec', '/bin/bash', $cleanerWsl, '--stage-id', $stageId, '--lock-file', $lockWsl, '--apply') 'Saneamiento de la copia de imagen' | Out-Null
}

$identityText = Invoke-WslChecked @('-d', $stagingName, '--user', 'root', '--exec', '/bin/cat', '/etc/ps5hs-image-identity.json') 'Lectura de identidad de imagen' -Quiet
$identity = $identityText | ConvertFrom-Json
if ($identity.schema -ne 'ps5hs-wsl-image' -or $identity.ubuntu.VERSION_ID -ne $lock.ubuntu.versionId -or $identity.architecture -ne $lock.ubuntu.architecture -or $identity.defaultUser -ne $lock.ubuntu.defaultUser) {
  throw 'La identidad generada no coincide con image-lock.json.'
}
$imagePacbrew = $identity.pacbrew
if (!$imagePacbrew -or [string]$imagePacbrew.version -ne [string]$lock.pacbrew.version -or
    [string]$imagePacbrew.archiveSha256 -ne [string]$lock.pacbrew.sha256 -or
    [string]$imagePacbrew.targetPrefix -ne [string]$lock.pacbrew.targetPrefix) {
  throw 'La imagen generada no contiene las dependencias PacBrew fijadas.'
}
foreach ($requiredPacbrewFile in $lock.pacbrew.requiredFiles) {
  $verifiedPacbrewFile = $imagePacbrew.verifiedFiles.PSObject.Properties[[string]$requiredPacbrewFile]
  if (!$verifiedPacbrewFile -or [string]$verifiedPacbrewFile.Value -notmatch '^[0-9a-f]{64}$') {
    throw "La imagen no verifica el archivo PacBrew requerido: $requiredPacbrewFile"
  }
}

Invoke-WslChecked @('--export', $stagingName, $finalStagedImage) 'Exportacion de la imagen saneada' | Out-Null
if (!(Test-Path -LiteralPath $finalStagedImage -PathType Leaf) -or (Get-Item -LiteralPath $finalStagedImage).Length -lt 1MB) {
  throw "La imagen final esta vacia o truncada: $finalStagedImage"
}
$imageHash = (Get-FileHash -LiteralPath $finalStagedImage -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = [pscustomobject]@{
  schema = 'ps5hs-offline-wsl-image'
  version = 1
  file = $imageFileName
  bytes = (Get-Item -LiteralPath $finalStagedImage).Length
  sha256 = $imageHash
  sourceDistro = $SourceDistro
  sourceDistroPreserved = $true
  identity = $identity
}
$manifestStaged = Join-Path $stagingRoot 'image-manifest.json'
$hashStaged = Join-Path $stagingRoot ($imageFileName + '.sha256')
Write-Utf8NoBom $manifestStaged ($manifest | ConvertTo-Json -Depth 12)
Write-Utf8NoBom $hashStaged ($imageHash + '  ' + $imageFileName + "`n")
Move-Item -LiteralPath $finalStagedImage -Destination $imagePath
Move-Item -LiteralPath $manifestStaged -Destination (Join-Path $OutputRoot 'image-manifest.json')
Move-Item -LiteralPath $hashStaged -Destination (Join-Path $OutputRoot ($imageFileName + '.sha256'))

$record | Add-Member -NotePropertyName completedAt -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o')
$record | Add-Member -NotePropertyName imageSha256 -NotePropertyValue $imageHash
$record | Add-Member -NotePropertyName imageBytes -NotePropertyValue $manifest.bytes
Write-Utf8NoBom (Join-Path $stagingRoot 'stage.json') ($record | ConvertTo-Json -Depth 5)
Write-Host "Imagen offline preparada: $imagePath" -ForegroundColor Green
Write-Host ("SHA-256: {0}; bytes: {1:N0}" -f $imageHash, $manifest.bytes)
Write-Host "Distro original intacta: $SourceDistro. Staging registrado: $stagingName ($distroRoot)"
