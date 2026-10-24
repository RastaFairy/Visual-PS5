#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $PSScriptRoot 'offline/OfflineBundle.psm1') -Force
$wslInstaller = Join-Path $repoRoot 'toolchains\WSL2\wsl.2.9.13.0.x64.msi'
if (!(Test-Path -LiteralPath $wslInstaller -PathType Leaf)) { throw "No existe el MSI firmado de prueba: $wslInstaller" }
$tempRoot = [IO.Path]::GetFullPath((Join-Path $env:TEMP ('ps5hs-offline-bundle-test-' + [guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$wslMsi = Join-Path $tempRoot 'toolchains\WSL2\wsl.2.9.13.0.x64.msi'
$runtimeRoot = Join-Path $tempRoot 'runtime'
$offlineRoot = Join-Path $tempRoot 'runtime\offline'
$imagePath = Join-Path $tempRoot 'toolchains\WSL2\visual-ps5-ubuntu-26.04.1-amd64.tar'
$imageManifestPath = Join-Path $tempRoot 'toolchains\WSL2\image-manifest.json'
$hashPath = $imagePath + '.sha256'
$sourcePath = Join-Path $tempRoot 'toolchains\fixture\README.md'
$pinnedPath = Join-Path $tempRoot 'toolchains\fixture\archive.bin'

function Assert-OfflineBundleCondition([bool]$Condition, [string]$Message) {
  if (!$Condition) { throw $Message }
}
function Assert-OfflineBundleRejects([scriptblock]$Action, [string]$Message) {
  $rejected = $false
  try { & $Action } catch { $rejected = $true }
  Assert-OfflineBundleCondition $rejected $Message
}

try {
  New-Item -ItemType Directory -Path (Split-Path -Parent $wslMsi) -Force | Out-Null
  New-Item -ItemType Directory -Path $offlineRoot -Force | Out-Null
  New-Item -ItemType Directory -Path (Split-Path -Parent $sourcePath) -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $tempRoot 'toolchains\fixture\link') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $tempRoot 'toolchains\fixture\target') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $tempRoot 'docs') -Force | Out-Null
  Copy-Item -LiteralPath $wslInstaller -Destination $wslMsi
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'offline/image-lock.json') -Destination (Join-Path $offlineRoot 'image-lock.json')
  $lock = Get-Content -LiteralPath (Join-Path $offlineRoot 'image-lock.json') -Raw | ConvertFrom-Json
  $lock.pacbrew.artifact = 'toolchains/fixture/archive.bin'
  [IO.File]::WriteAllText((Join-Path $offlineRoot 'image-lock.json'), ($lock | ConvertTo-Json -Depth 16), (New-Object System.Text.UTF8Encoding($false)))
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'offline/backend-readiness.json') -Destination (Join-Path $offlineRoot 'backend-readiness.json')
  $linkInfo = [pscustomobject]@{ schema = 'ps5hs-offline-bundle-links'; version = 1; links = @([pscustomobject]@{ path = 'toolchains/fixture/link'; target = 'toolchains/fixture/target'; type = 'directory-symbolic-link'; bundleRepresentation = 'materialized-copy' }) }
  [IO.File]::WriteAllText((Join-Path $offlineRoot 'bundle-links.json'), ($linkInfo | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText($sourcePath, 'toolchains are preserved in the bundle', (New-Object System.Text.UTF8Encoding($false)))
  [IO.File]::WriteAllBytes($pinnedPath, [Text.Encoding]::UTF8.GetBytes('pinned fixture archive'))
  foreach ($relative in @('app.js', 'index.html', 'start.bat', 'INSTALL-OFFLINE.bat', 'runtime/server.ps1', 'runtime/Install-OfflineEnvironment.ps1', 'runtime/offline/OfflineEnvironment.psm1', 'runtime/offline/install-pacbrew-homebrew.py', 'runtime/offline/install-payload-dependencies.py', 'runtime/payload-dependency-profiles/shadowmountplus.json', 'docs/OFFLINE_INSTALLATION.es-ES.md', 'docs/PAYLOAD_DEPENDENCIES.es-ES.md')) {
    $path = Join-Path $tempRoot ($relative -replace '/', '\')
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, 'fixture', (New-Object System.Text.UTF8Encoding($false)))
  }
  [IO.File]::WriteAllBytes($imagePath, [Text.Encoding]::UTF8.GetBytes('offline-image-fixture'))

  $imageHash = (Get-FileHash -LiteralPath $imagePath -Algorithm SHA256).Hash.ToLowerInvariant()
  $tools = @{}
  foreach ($command in $lock.requiredCommands) { $tools[[string]$command] = @{ path = '/usr/bin/' + $command; version = 'fixture' } }
  $pacbrewVerifiedFiles = @{}
  foreach ($requiredFile in $lock.pacbrew.requiredFiles) { $pacbrewVerifiedFiles[[string]$requiredFile] = 'a' * 64 }
  $identity = [pscustomobject]@{
    schema = 'ps5hs-wsl-image'; schemaVersion = 1; architecture = 'amd64'; defaultUser = 'visualps5'
    ubuntu = @{ ID = 'ubuntu'; VERSION_ID = '26.04'; PRETTY_NAME = 'Ubuntu 26.04.1 LTS' }
    tools = $tools; sdkPaths = @($lock.requiredPaths); packages = @{}
    pacbrew = @{ version = $lock.pacbrew.version; archiveSha256 = $lock.pacbrew.sha256; targetPrefix = $lock.pacbrew.targetPrefix; verifiedFiles = $pacbrewVerifiedFiles }
  }
  $imageManifest = [pscustomobject]@{
    schema = 'ps5hs-offline-wsl-image'; version = 1; file = 'visual-ps5-ubuntu-26.04.1-amd64.tar'
    bytes = (Get-Item -LiteralPath $imagePath).Length; sha256 = $imageHash; identity = $identity
  }
  $pinnedHash = (Get-FileHash -LiteralPath $pinnedPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $lock.pacbrew.sha256 = $pinnedHash
  [IO.File]::WriteAllText((Join-Path $offlineRoot 'image-lock.json'), ($lock | ConvertTo-Json -Depth 16), (New-Object System.Text.UTF8Encoding($false)))
  $identity.pacbrew.archiveSha256 = $pinnedHash
  [IO.File]::WriteAllText($imageManifestPath, ($imageManifest | ConvertTo-Json -Depth 16), (New-Object System.Text.UTF8Encoding($false)))
  $pins = [pscustomobject]@{ schema = 'ps5hs-toolchain-pins'; version = 1; artifacts = @{ pacbrew = @{ usedBy = 'offline bundle fixture'; localPath = $lock.pacbrew.artifact; version = $lock.pacbrew.version; file = 'fixture.tar.gz'; archive = @{ sha256 = $pinnedHash }; sourceUrl = 'https://example.invalid/fixture.tar.gz' } } }
  [IO.File]::WriteAllText((Join-Path $runtimeRoot 'toolchain-pins.json'), ($pins | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText($imageManifestPath, ($imageManifest | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText($hashPath, ($imageHash + '  visual-ps5-ubuntu-26.04.1-amd64.tar' + "`n"), (New-Object System.Text.UTF8Encoding($false)))

  $manifest = New-PS5HSOfflineBundleManifest $tempRoot
  [IO.File]::WriteAllText((Join-Path $tempRoot 'manifest.json'), ($manifest | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding($false)))
  Write-PS5HSSha256Sums $tempRoot $manifest.files
  $valid = Test-PS5HSOfflineBundle $tempRoot
  Assert-OfflineBundleCondition $valid.valid 'Un bundle completo y firmado debe superar la validación.'
  $sumLines = @(Get-Content -LiteralPath (Join-Path $tempRoot 'SHA256SUMS'))
  [array]::Reverse($sumLines)
  [IO.File]::WriteAllText((Join-Path $tempRoot 'SHA256SUMS'), (($sumLines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
  $reorderedValid = Test-PS5HSOfflineBundle $tempRoot
  Assert-OfflineBundleCondition $reorderedValid.valid 'La validación de SHA256SUMS no debe depender del orden de las rutas.'
  Write-PS5HSSha256Sums $tempRoot $manifest.files
  $sumPath = Join-Path $tempRoot 'SHA256SUMS'
  $sumLines = @(Get-Content -LiteralPath $sumPath)
  $savedSumLine = $sumLines[0]
  $sumLines[0] = ('0' * 64) + $savedSumLine.Substring(64)
  [IO.File]::WriteAllText($sumPath, (($sumLines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
  Assert-OfflineBundleRejects { Test-PS5HSOfflineBundle $tempRoot } 'El bundle debe rechazar una lista SHA256SUMS alterada.'
  Write-PS5HSSha256Sums $tempRoot $manifest.files
  $savedManifestText = [IO.File]::ReadAllText((Join-Path $tempRoot 'manifest.json'))
  $manifest.installers.wsl.version = '0.0.0.0'
  [IO.File]::WriteAllText((Join-Path $tempRoot 'manifest.json'), ($manifest | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding($false)))
  Assert-OfflineBundleRejects { Test-PS5HSOfflineBundle $tempRoot } 'El bundle debe rechazar una versión MSI distinta del lock.'
  [IO.File]::WriteAllText((Join-Path $tempRoot 'manifest.json'), $savedManifestText, (New-Object System.Text.UTF8Encoding($false)))
  $freshValid = Test-PS5HSOfflineBundle $tempRoot -HashesFresh
  Assert-OfflineBundleCondition ($freshValid.valid -and $freshValid.hashesFresh) 'El manifiesto recién generado debe superar la comprobación estructural rápida.'
  Assert-OfflineBundleCondition (Test-Path -LiteralPath $sourcePath -PathType Leaf) 'El empaquetado debe conservar las rutas toolchains/.'

  [IO.File]::AppendAllText($sourcePath, 'tamper', (New-Object System.Text.UTF8Encoding($false)))
  Assert-OfflineBundleRejects { Test-PS5HSOfflineBundle $tempRoot } 'El bundle debe rechazar un fichero con hash alterado.'
  [IO.File]::WriteAllText($sourcePath, 'toolchains are preserved in the bundle', (New-Object System.Text.UTF8Encoding($false)))
  Assert-OfflineBundleRejects { New-PS5HSOfflineBundleManifest (Join-Path $tempRoot 'missing-image') } 'El empaquetador debe rechazar una imagen ausente.'
  $heldMsi = $wslMsi + '.hold'
  Move-Item -LiteralPath $wslMsi -Destination $heldMsi
  Assert-OfflineBundleRejects { New-PS5HSOfflineBundleManifest $tempRoot } 'El empaquetador debe rechazar un MSI WSL ausente.'
  Move-Item -LiteralPath $heldMsi -Destination $wslMsi
  [IO.File]::AppendAllText($pinnedPath, 'tamper', (New-Object System.Text.UTF8Encoding($false)))
  Assert-OfflineBundleRejects { New-PS5HSOfflineBundleManifest $tempRoot } 'El empaquetador debe rechazar un artefacto local con pin incorrecto.'
  [IO.File]::WriteAllBytes($pinnedPath, [Text.Encoding]::UTF8.GetBytes('pinned fixture archive'))

  $savedIdentity = $imageManifest.identity
  $imageManifest.identity.tools.git.path = $null
  [IO.File]::WriteAllText($imageManifestPath, ($imageManifest | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
  Assert-OfflineBundleRejects { New-PS5HSOfflineBundleManifest $tempRoot } 'El empaquetador debe bloquear un comando obligatorio ausente.'
  $imageManifest.identity = $savedIdentity
  [IO.File]::WriteAllText($imageManifestPath, ($imageManifest | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))

  $savedHash = $imageManifest.sha256
  $imageManifest.sha256 = ('0' * 64)
  [IO.File]::WriteAllText($imageManifestPath, ($imageManifest | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
  Assert-OfflineBundleRejects { New-PS5HSOfflineBundleManifest $tempRoot } 'El empaquetador debe rechazar un hash de imagen incorrecto.'
  Write-Host 'PASS: MSI firmado, inventario con hashes, integridad, rutas toolchains y rechazo de imagen/dependencia ausente.' -ForegroundColor Green
} finally {
  $full = [IO.Path]::GetFullPath($tempRoot)
  $parent = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
  if ($full.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full)) {
    Remove-Item -LiteralPath $full -Recurse -Force
  }
}
