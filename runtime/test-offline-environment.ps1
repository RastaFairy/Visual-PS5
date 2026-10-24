#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $PSScriptRoot 'offline/OfflineBundle.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'offline/OfflineEnvironment.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'offline/OfflineBundle.psm1') -Force
$wslInstaller = Join-Path $repoRoot 'toolchains\WSL2\wsl.2.9.13.0.x64.msi'
if (!(Test-Path -LiteralPath $wslInstaller -PathType Leaf)) { throw "No existe el MSI WSL firmado de prueba: $wslInstaller" }
$tempRoot = [IO.Path]::GetFullPath((Join-Path $env:TEMP ('ps5hs-offline-environment-test-' + [guid]::NewGuid().ToString('N'))))
$localAppDataBefore = $env:LOCALAPPDATA
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$bundleFixtureRoot = Join-Path $tempRoot 'bundle'
$localFixtureRoot = Join-Path $tempRoot 'local'
$env:LOCALAPPDATA = $localFixtureRoot
$env:LOCALAPPDATA = Join-Path $tempRoot 'local'

function Assert-OfflineEnvironmentCondition([bool]$Condition, [string]$Message) {
  if (!$Condition) { throw $Message }
}

try {
  $bundleRoot = $bundleFixtureRoot
  New-Item -ItemType Directory -Path $bundleRoot -Force | Out-Null
  $appFixturePath = Join-Path $bundleRoot 'app.js'
  $wslMsi = Join-Path $bundleRoot 'toolchains\WSL2\wsl.2.9.13.0.x64.msi'
  $imagePath = Join-Path $bundleRoot 'toolchains\WSL2\visual-ps5-ubuntu-26.04.1-amd64.tar'
  $offlineRoot = Join-Path $bundleRoot 'runtime\offline'
  $imageManifestPath = Join-Path $bundleRoot 'toolchains\WSL2\image-manifest.json'
  New-Item -ItemType Directory -Path (Split-Path -Parent $wslMsi) -Force | Out-Null
  New-Item -ItemType Directory -Path $offlineRoot -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $bundleRoot 'toolchains\fixture') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $bundleRoot 'toolchains\PS5_Vulkan\.deps\native\ps5-payload-sdk\target\include_common') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $bundleRoot 'toolchains\PS5_Vulkan\.deps\native\ps5-payload-sdk\target\user\homebrew\include') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $bundleRoot 'docs') -Force | Out-Null
  Copy-Item -LiteralPath $wslInstaller -Destination $wslMsi
  foreach ($relative in @('image-lock.json', 'backend-readiness.json', 'bundle-links.json')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('offline\' + $relative)) -Destination (Join-Path $offlineRoot $relative)
  }
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'toolchain-pins.json') -Destination (Join-Path $bundleRoot 'runtime\toolchain-pins.json')
  foreach ($relative in @('app.js', 'index.html', 'start.bat', 'INSTALL-OFFLINE.bat', 'runtime/server.ps1', 'runtime/Install-OfflineEnvironment.ps1', 'runtime/offline/OfflineEnvironment.psm1', 'runtime/offline/install-pacbrew-homebrew.py', 'runtime/offline/install-payload-dependencies.py', 'runtime/payload-dependency-profiles/shadowmountplus.json', 'docs/OFFLINE_INSTALLATION.es-ES.md', 'docs/PAYLOAD_DEPENDENCIES.es-ES.md')) {
    $path = Join-Path $bundleRoot ($relative -replace '/', '\')
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, 'offline test fixture', (New-Object System.Text.UTF8Encoding($false)))
  }
  $pinPath = Join-Path $bundleRoot 'toolchains\fixture\archive.bin'
  [IO.File]::WriteAllBytes($pinPath, [Text.Encoding]::UTF8.GetBytes('fixture pinned archive'))
  $pinHash = (Get-FileHash -LiteralPath $pinPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $pins = [pscustomobject]@{ schema = 'ps5hs-toolchain-pins'; version = 1; artifacts = @{ pacbrew = @{ usedBy = 'offline environment fixture'; localPath = 'toolchains/fixture/archive.bin'; version = 'v0.40.2'; file = 'fixture.tar.gz'; archive = @{ sha256 = $pinHash }; sourceUrl = 'https://example.invalid/fixture.tar.gz' } } }
  [IO.File]::WriteAllText((Join-Path $bundleRoot 'runtime\toolchain-pins.json'), ($pins | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
  [IO.File]::WriteAllBytes($imagePath, [Text.Encoding]::UTF8.GetBytes('ubuntu image fixture'))
  $imageHash = (Get-FileHash -LiteralPath $imagePath -Algorithm SHA256).Hash.ToLowerInvariant()
  $lock = Get-Content -LiteralPath (Join-Path $offlineRoot 'image-lock.json') -Raw | ConvertFrom-Json
  $lock.pacbrew.artifact = 'toolchains/fixture/archive.bin'
  $lock.pacbrew.sha256 = $pinHash
  [IO.File]::WriteAllText((Join-Path $offlineRoot 'image-lock.json'), ($lock | ConvertTo-Json -Depth 16), (New-Object System.Text.UTF8Encoding($false)))
  $tools = @{}
  foreach ($command in $lock.requiredCommands) { $tools[[string]$command] = @{ path = '/usr/bin/' + $command; version = 'fixture' } }
  $pacbrewVerifiedFiles = @{}
  foreach ($requiredFile in $lock.pacbrew.requiredFiles) { $pacbrewVerifiedFiles[[string]$requiredFile] = 'a' * 64 }
  $identity = [pscustomobject]@{ schema = 'ps5hs-wsl-image'; schemaVersion = 1; architecture = 'amd64'; defaultUser = 'visualps5'; ubuntu = @{ ID = 'ubuntu'; VERSION_ID = '26.04'; PRETTY_NAME = 'Ubuntu 26.04.1 LTS' }; tools = $tools; sdkPaths = @($lock.requiredPaths); packages = @{}; pacbrew = @{ version = $lock.pacbrew.version; archiveSha256 = $lock.pacbrew.sha256; targetPrefix = $lock.pacbrew.targetPrefix; verifiedFiles = $pacbrewVerifiedFiles } }
  $imageManifest = [pscustomobject]@{ schema = 'ps5hs-offline-wsl-image'; version = 1; file = 'visual-ps5-ubuntu-26.04.1-amd64.tar'; bytes = (Get-Item -LiteralPath $imagePath).Length; sha256 = $imageHash; identity = $identity }
  [IO.File]::WriteAllText($imageManifestPath, ($imageManifest | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText($imagePath + '.sha256', ($imageHash + '  visual-ps5-ubuntu-26.04.1-amd64.tar' + "`n"), (New-Object System.Text.UTF8Encoding($false)))
  $manifest = New-PS5HSOfflineBundleManifest $bundleRoot
  [IO.File]::WriteAllText((Join-Path $bundleRoot 'manifest.json'), ($manifest | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding($false)))
  Write-PS5HSSha256Sums $bundleRoot $manifest.files
  $null = Test-PS5HSOfflineBundle $bundleRoot

  $snapshot = [pscustomobject]@{
    productName = 'Microsoft Windows 11 Pro'; build = 26100; architecture = '64-bit'; isElevated = $true
    virtualization = 'Ready'; windowsFeatures = @{ 'Microsoft-Windows-Subsystem-Linux' = 'Enabled'; VirtualMachinePlatform = 'Enabled' }
    wslAvailable = $true; wslVersion = '2.9.13.0'; distros = @(); pendingRestart = $false; installDriveFreeBytes = [int64](100GB)
  }
  $preflight = Get-PS5HSOfflineHostPreflight -BundleRoot $bundleRoot -HostSnapshot $snapshot
  Assert-OfflineEnvironmentCondition ($preflight.canApply -and !$preflight.ready -and !$preflight.needsWslMsi) 'El preflight compatible debe permitir la importación, pero indicar que la distro falta.'
  $quickPreflight = Get-PS5HSOfflineHostPreflight -BundleRoot $bundleRoot -HostSnapshot $snapshot -HashesFresh
  Assert-OfflineEnvironmentCondition ($quickPreflight.canApply -and $quickPreflight.bundle.hashesFresh) 'La comprobación rápida anterior a UAC debe validar estructura y tamaños e indicar que no calculó hashes completos.'
  $operations = New-Object 'System.Collections.Generic.List[string]'
  $runner = {
    param($name, $arguments)
    $operations.Add([string]$name)
    return [pscustomobject]@{ exitCode = 0 }
  }.GetNewClosure()
  $fastReceiptRejected = $false
  try { Install-PS5HSOfflineEnvironment -BundleRoot $bundleRoot -Apply -ValidatedPreflight $quickPreflight -ActionRunner $runner } catch { $fastReceiptRejected = $true }
  Assert-OfflineEnvironmentCondition $fastReceiptRejected 'La instalación no debe aceptar como íntegro un preflight rápido anterior a UAC.'
  $dry = Install-PS5HSOfflineEnvironment -BundleRoot $bundleRoot -HostSnapshot $snapshot -ActionRunner $runner
  Assert-OfflineEnvironmentCondition ($dry.canApply -and $operations.Count -eq 0) 'Sin -Apply el instalador debe ser de solo lectura.'
  $installed = Install-PS5HSOfflineEnvironment -BundleRoot $bundleRoot -Apply -HostSnapshot $snapshot -ValidatedPreflight $preflight -ActionRunner $runner
  Assert-OfflineEnvironmentCondition ($installed.status -eq 'installed' -and $operations -contains 'ImportDistro' -and $operations -contains 'VerifyDistro') 'La instalación simulada debe importar y verificar la distro.'

  $resumeSnapshot = $snapshot.PSObject.Copy()
  $resumeSnapshot.distros = @([pscustomobject]@{ name = $installed.distroName; basePath = $installed.installRoot })
  $operations.Clear()
  $resumePreflight = Get-PS5HSOfflineHostPreflight -BundleRoot $bundleRoot -HostSnapshot $resumeSnapshot
  $resumed = Install-PS5HSOfflineEnvironment -BundleRoot $bundleRoot -Apply -HostSnapshot $resumeSnapshot -ValidatedPreflight $resumePreflight -ActionRunner $runner
  Assert-OfflineEnvironmentCondition ($resumed.status -eq 'installed' -and $operations -notcontains 'ImportDistro' -and $operations -contains 'VerifyDistro') 'La reanudación no debe volver a importar una distro ya registrada en su ruta.'

  $blockedSnapshot = $snapshot.PSObject.Copy()
  $blockedSnapshot.virtualization = 'Disabled'
  $operations.Clear()
  $blocked = Get-PS5HSOfflineHostPreflight -BundleRoot $bundleRoot -HostSnapshot $blockedSnapshot
  Assert-OfflineEnvironmentCondition (!$blocked.canApply -and ($blocked.errors -join ' ') -match 'BIOS/UEFI') 'El preflight debe bloquear virtualización deshabilitada.'

  $collisionSnapshot = $snapshot.PSObject.Copy()
  $collisionSnapshot.distros = @([pscustomobject]@{ name = 'VisualPS5-Ubuntu-26.04'; basePath = (Join-Path $tempRoot 'other-distro') })
  $collision = Get-PS5HSOfflineHostPreflight -BundleRoot $bundleRoot -HostSnapshot $collisionSnapshot
  Assert-OfflineEnvironmentCondition (!$collision.canApply -and ($collision.errors -join ' ') -match 'otra ruta') 'El preflight debe bloquear una colisión de nombre con otra ubicación.'

  $spaceSnapshot = $snapshot.PSObject.Copy()
  $spaceSnapshot.installDriveFreeBytes = [int64](1GB)
  $space = Get-PS5HSOfflineHostPreflight -BundleRoot $bundleRoot -HostSnapshot $spaceSnapshot
  Assert-OfflineEnvironmentCondition (!$space.canApply -and ($space.errors -join ' ') -match 'Espacio insuficiente') 'El preflight debe bloquear espacio insuficiente.'

  $unknownFeatureSnapshot = $snapshot.PSObject.Copy()
  $unknownFeatureSnapshot.isElevated = $false
  $unknownFeatureSnapshot.windowsFeatures = @{ 'Microsoft-Windows-Subsystem-Linux' = 'Unknown'; VirtualMachinePlatform = 'Unknown' }
  $unknownFeatures = Get-PS5HSOfflineHostPreflight -BundleRoot $bundleRoot -HostSnapshot $unknownFeatureSnapshot
  Assert-OfflineEnvironmentCondition ($unknownFeatures.canApply -and $unknownFeatures.requiresElevation -and $unknownFeatures.needsFeatures) 'Si la consulta de características requiere privilegios, el instalador debe pedir UAC y volver a comprobar, no bloquearse antes de elevar.'

  $featureSnapshot = $snapshot.PSObject.Copy()
  $featureSnapshot.windowsFeatures = @{ 'Microsoft-Windows-Subsystem-Linux' = 'Disabled'; VirtualMachinePlatform = 'Enabled' }
  $operations.Clear()
  $restartRunner = {
    param($name, $arguments)
    $operations.Add([string]$name)
    return [pscustomobject]@{ exitCode = 3010; requiresRestart = $true }
  }.GetNewClosure()
  $restart = Install-PS5HSOfflineEnvironment -BundleRoot $bundleRoot -Apply -HostSnapshot $featureSnapshot -ActionRunner $restartRunner
  Assert-OfflineEnvironmentCondition ($restart.status -eq 'restart-required' -and $operations.Count -eq 1 -and $operations[0] -eq 'EnableWindowsFeatures') 'La activación de características debe detenerse y pedir reinicio antes de importar Ubuntu.'

  $tamperBytes = [IO.File]::ReadAllBytes($appFixturePath)
  $tamperBytes[0] = [byte]($tamperBytes[0] -bxor 1)
  [IO.File]::WriteAllBytes($appFixturePath, $tamperBytes)
  $quickTampered = Get-PS5HSOfflineHostPreflight -BundleRoot $bundleRoot -HostSnapshot $snapshot -HashesFresh
  Assert-OfflineEnvironmentCondition ($quickTampered.canApply -and $quickTampered.bundle.hashesFresh) 'La comprobación rápida no debe confundirse con la verificación completa antes de modificar Windows.'
  $tampered = Get-PS5HSOfflineHostPreflight -BundleRoot $bundleRoot -HostSnapshot $snapshot
  Assert-OfflineEnvironmentCondition (!$tampered.canApply -and $tampered.errors.Count -gt 0) ('El preflight debe detener un bundle alterado antes de modificar Windows. Diagnóstico: ' + ($tampered.errors -join ' '))

  Write-Host 'PASS: preflight, solo lectura, elevación/reinicio, colisión, espacio, reanudación e importación idempotente.' -ForegroundColor Green
} finally {
  $env:LOCALAPPDATA = $localAppDataBefore
  $full = [IO.Path]::GetFullPath($tempRoot)
  $parent = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
  if ($full.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full)) {
    Remove-Item -LiteralPath $full -Recurse -Force
  }
}
