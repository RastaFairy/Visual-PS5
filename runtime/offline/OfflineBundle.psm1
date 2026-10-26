Set-StrictMode -Version 2.0

function Write-PS5HSUtf8NoBom([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-PS5HSBundleFiles([string]$BundleRoot) {
  $root = [IO.Path]::GetFullPath($BundleRoot).TrimEnd('\') + '\'
  $items = New-Object 'System.Collections.Generic.List[object]'
  foreach ($file in Get-ChildItem -LiteralPath $BundleRoot -Recurse -File -Force) {
    $relative = $file.FullName.Substring($root.Length).Replace('\', '/')
    if ($relative -in @('manifest.json', 'SHA256SUMS')) { continue }
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "El bundle no admite archivos enlazados: $relative"
    }
    $items.Add([pscustomobject]@{
      path = $relative
      bytes = [int64]$file.Length
      sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    })
  }
  return @($items.ToArray() | Sort-Object -Property path)
}

function Assert-PS5HSAuthenticode([string]$Path, [string]$SignerNeedle) {
  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Falta el instalador firmado: $Path" }
  $signature = Get-AuthenticodeSignature -LiteralPath $Path
  if ($signature.Status -ne 'Valid' -or !$signature.SignerCertificate -or
      !$signature.SignerCertificate.Subject.Contains($SignerNeedle)) {
    throw "Firma Authenticode ausente, inválida o inesperada: $Path ($($signature.Status))"
  }
  return [pscustomobject]@{ status = [string]$signature.Status; signer = [string]$signature.SignerCertificate.Subject }
}

function New-PS5HSOfflineBundleManifest([string]$BundleRoot) {
  $root = [IO.Path]::GetFullPath($BundleRoot)
  $imagePath = Join-Path $root 'toolchains\WSL2\visual-ps5-ubuntu-26.04.1-amd64.tar'
  $imageManifestPath = Join-Path $root 'toolchains\WSL2\image-manifest.json'
  $imageHashPath = Join-Path $root 'toolchains\WSL2\visual-ps5-ubuntu-26.04.1-amd64.tar.sha256'
  $wslMsiPath = Join-Path $root 'toolchains\WSL2\wsl.2.9.13.0.x64.msi'
  $backendPath = Join-Path $root 'runtime\offline\backend-readiness.json'
  $linksPath = Join-Path $root 'runtime\offline\bundle-links.json'
  $lockPath = Join-Path $root 'runtime\offline\image-lock.json'
  $pinsPath = Join-Path $root 'runtime\toolchain-pins.json'
  $requiredSource = @('app.js', 'index.html', 'start.bat', 'INSTALL-OFFLINE.bat', 'runtime/server.ps1', 'runtime/Install-OfflineEnvironment.ps1', 'runtime/offline/OfflineEnvironment.psm1', 'runtime/offline/install-pacbrew-homebrew.py', 'runtime/offline/install-payload-dependencies.py', 'runtime/payload-dependency-profiles/shadowmountplus.json', 'docs/OFFLINE_INSTALLATION.es-ES.md', 'docs/PAYLOAD_DEPENDENCIES.es-ES.md')
  foreach ($relative in $requiredSource) {
    if (!(Test-Path -LiteralPath (Join-Path $root ($relative -replace '/', '\')) -PathType Leaf)) {
      throw "El bundle no contiene un archivo central de la IDE: $relative"
    }
  }
  foreach ($path in @($imagePath, $imageManifestPath, $imageHashPath, $wslMsiPath, $backendPath, $linksPath, $lockPath, $pinsPath)) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Falta un componente obligatorio del bundle: $path" }
  }

  $imageManifest = Get-Content -LiteralPath $imageManifestPath -Raw | ConvertFrom-Json
  if ($imageManifest.schema -ne 'ps5hs-offline-wsl-image' -or $imageManifest.file -ne 'visual-ps5-ubuntu-26.04.1-amd64.tar') {
    throw 'El manifiesto de imagen no identifica la imagen WSL fijada.'
  }
  $imageFile = Get-Item -LiteralPath $imagePath
  if ($imageFile.Length -ne [int64]$imageManifest.bytes) { throw 'El tamaño de la imagen no coincide con image-manifest.json.' }
  $imageHash = (Get-FileHash -LiteralPath $imagePath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($imageHash -ne [string]$imageManifest.sha256) { throw 'El SHA-256 de la imagen no coincide con image-manifest.json.' }
  if (!(Get-Content -LiteralPath $imageHashPath -Raw).StartsWith($imageHash)) { throw 'El sidecar SHA-256 de la imagen no coincide.' }
  if ($imageManifest.identity.ubuntu.VERSION_ID -ne '26.04' -or $imageManifest.identity.architecture -ne 'amd64' -or
      $imageManifest.identity.defaultUser -ne 'visualps5') { throw 'La identidad de Ubuntu no cumple el perfil offline requerido.' }
  $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
  $wslPin = $lock.installers.wsl
  $wslInstallerFile = Get-Item -LiteralPath $wslMsiPath
  $wslInstallerHash = (Get-FileHash -LiteralPath $wslMsiPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if (!$wslPin -or [string]$wslPin.path -ne 'toolchains/WSL2/wsl.2.9.13.0.x64.msi' -or
      [string]$wslPin.version -ne '2.9.13.0' -or [int64]$wslPin.bytes -ne [int64]$wslInstallerFile.Length -or
      [string]$wslPin.sha256 -ne $wslInstallerHash) {
    throw 'El instalador WSL no coincide con la versión/hash fijados en image-lock.json.'
  }
  foreach ($command in $lock.requiredCommands) {
    $tool = $imageManifest.identity.tools.PSObject.Properties[[string]$command]
    if (!$tool -or !$tool.Value.path) { throw "Falta el comando requerido en la imagen Ubuntu: $command" }
  }
  foreach ($requiredPath in $lock.requiredPaths) {
    if ([string]$requiredPath -notin @($imageManifest.identity.sdkPaths)) { throw "Falta la ruta requerida en la imagen Ubuntu: $requiredPath" }
  }
  $pins = Get-Content -LiteralPath $pinsPath -Raw | ConvertFrom-Json
  if ($pins.schema -ne 'ps5hs-toolchain-pins' -or !$pins.artifacts) { throw 'runtime/toolchain-pins.json no es válido.' }
  $pacbrewPinProperty = $pins.artifacts.PSObject.Properties['pacbrew']
  $pacbrewImage = $imageManifest.identity.pacbrew
  if (!$pacbrewPinProperty -or !$lock.pacbrew -or !$pacbrewImage -or
      [string]$lock.pacbrew.version -ne [string]$pacbrewPinProperty.Value.version -or
      [string]$lock.pacbrew.sha256 -ne [string]$pacbrewPinProperty.Value.archive.sha256 -or
      [string]$lock.pacbrew.artifact -ne [string]$pacbrewPinProperty.Value.localPath -or
      [string]$pacbrewImage.version -ne [string]$lock.pacbrew.version -or
      [string]$pacbrewImage.archiveSha256 -ne [string]$lock.pacbrew.sha256 -or
      [string]$pacbrewImage.targetPrefix -ne [string]$lock.pacbrew.targetPrefix) {
    throw 'PacBrew no coincide entre los pins, image-lock.json y la identidad de la imagen.'
  }
  foreach ($requiredPacbrewFile in $lock.pacbrew.requiredFiles) {
    $verifiedPacbrewFile = $pacbrewImage.verifiedFiles.PSObject.Properties[[string]$requiredPacbrewFile]
    if (!$verifiedPacbrewFile -or [string]$verifiedPacbrewFile.Value -notmatch '^[0-9a-f]{64}$') {
      throw "La imagen no declara verificado el archivo PacBrew requerido: $requiredPacbrewFile"
    }
  }
  $pinnedArtifacts = @()
  foreach ($entry in $pins.artifacts.PSObject.Properties) {
    $relativeArtifact = [string]$entry.Value.localPath
    if (!$relativeArtifact) { throw "El pin $($entry.Name) no declara localPath." }
    $artifactPath = Join-Path $root ($relativeArtifact -replace '/', '\')
    if (!(Test-Path -LiteralPath $artifactPath -PathType Leaf)) { throw "Falta el artefacto local fijado $($entry.Name): $relativeArtifact" }
    $artifactFile = Get-Item -LiteralPath $artifactPath
    $artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($artifactHash -ne [string]$entry.Value.archive.sha256) { throw "Hash incorrecto en el artefacto local fijado $($entry.Name)." }
    $pinnedArtifacts += [pscustomobject]@{ id = [string]$entry.Name; path = $relativeArtifact.Replace('\', '/'); version = [string]$entry.Value.version; bytes = [int64]$artifactFile.Length; sha256 = $artifactHash }
  }

  $wslSignature = Assert-PS5HSAuthenticode $wslMsiPath 'Microsoft Corporation'
  $ps7MsiPath = Join-Path $root 'toolchains\PowerShell7\PowerShell-7.6.1-win-x64.msi'
  $ps7Signature = $null
  if (Test-Path -LiteralPath $ps7MsiPath -PathType Leaf) {
    $ps7Signature = Assert-PS5HSAuthenticode $ps7MsiPath 'Microsoft Corporation'
  }
  $readiness = Get-Content -LiteralPath $backendPath -Raw | ConvertFrom-Json
  if ($readiness.schema -ne 'ps5hs-offline-backend-readiness' -or !$readiness.backends) {
    throw 'backend-readiness.json no tiene un esquema válido.'
  }
  foreach ($backend in $readiness.backends) {
    if ($backend.status -notin @('validated', 'source-only', 'blocked') -or !$backend.id -or !$backend.evidence) {
      throw "Estado o evidencia inválidos para el backend '$($backend.id)'."
    }
  }
  $linkMetadata = Get-Content -LiteralPath $linksPath -Raw | ConvertFrom-Json
  if ($linkMetadata.schema -ne 'ps5hs-offline-bundle-links' -or $null -eq $linkMetadata.links) {
    throw 'runtime/offline/bundle-links.json no es válido.'
  }
  $bundleLinks = @()
  foreach ($link in $linkMetadata.links) {
    foreach ($relativeLinkPath in @([string]$link.path, [string]$link.target)) {
      if (!$relativeLinkPath -or $relativeLinkPath -notmatch '^toolchains/' -or $relativeLinkPath -match '(^|/)\.\.(/|$)') {
        throw "Ruta no permitida en bundle-links.json: $relativeLinkPath"
      }
      if (!(Test-Path -LiteralPath (Join-Path $root ($relativeLinkPath -replace '/', '\')) -PathType Container)) {
        throw "Falta la ruta declarada para enlace empaquetado: $relativeLinkPath"
      }
    }
    $bundleLinks += [pscustomobject]@{ path = [string]$link.path; target = [string]$link.target; type = [string]$link.type; representation = [string]$link.bundleRepresentation }
  }
  $toolchainSources = @()
  $toolchainsRoot = Join-Path $root 'toolchains'
  foreach ($sourceFile in Get-ChildItem -LiteralPath $toolchainsRoot -Recurse -File -Filter '.ps5hs-source.json' -Force) {
    try { $source = Get-Content -LiteralPath $sourceFile.FullName -Raw | ConvertFrom-Json }
    catch { throw "Manifiesto de procedencia inválido: $($sourceFile.FullName)" }
    $relativeSource = $sourceFile.FullName.Substring(([IO.Path]::GetFullPath($root).TrimEnd('\') + '\').Length).Replace('\', '/')
    $repositoryProperty = $source.PSObject.Properties['repository']
    $sourceCommitProperty = $source.PSObject.Properties['sourceCommit']
    $commitProperty = $source.PSObject.Properties['commit']
    $licenseProperty = $source.PSObject.Properties['license']
    $sourceOnlyProperty = $source.PSObject.Properties['sourceOnly']
    $buildVerifiedProperty = $source.PSObject.Properties['buildVerified']
    $toolchainSources += [pscustomobject]@{
      manifest = $relativeSource
      repository = [string]$(if ($repositoryProperty) { $repositoryProperty.Value } else { '' })
      commit = [string]$(if ($sourceCommitProperty -and $sourceCommitProperty.Value) { $sourceCommitProperty.Value } elseif ($commitProperty) { $commitProperty.Value } else { '' })
      license = [string]$(if ($licenseProperty) { $licenseProperty.Value } else { '' })
      sourceOnly = [bool]$(if ($sourceOnlyProperty) { $sourceOnlyProperty.Value } else { $false })
      buildVerified = if ($buildVerifiedProperty) { [bool]$buildVerifiedProperty.Value } else { $null }
    }
  }

  return [pscustomobject]@{
    schema = 'ps5hs-offline-bundle'
    version = 1
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    architecture = 'amd64'
    image = [pscustomobject]@{ path = 'toolchains/WSL2/visual-ps5-ubuntu-26.04.1-amd64.tar'; bytes = $imageFile.Length; sha256 = $imageHash; identity = $imageManifest.identity }
    installers = [pscustomobject]@{
      wsl = [pscustomobject]@{ path = [string]$wslPin.path; version = [string]$wslPin.version; bytes = [int64]$wslPin.bytes; sha256 = $wslInstallerHash; signature = $wslSignature }
      powershell7 = if ($ps7Signature) { [pscustomobject]@{ path = 'toolchains/PowerShell7/PowerShell-7.6.1-win-x64.msi'; optional = $true; signature = $ps7Signature } } else { $null }
    }
    toolchainSources = $toolchainSources
    pinnedArtifacts = $pinnedArtifacts
    bundleLinks = $bundleLinks
    backends = $readiness.backends
    files = (Get-PS5HSBundleFiles $root)
  }
}

function Write-PS5HSSha256Sums([string]$BundleRoot, [object[]]$Files) {
  $lines = @($Files | ForEach-Object { '{0}  {1}' -f $_.sha256, $_.path })
  Write-PS5HSUtf8NoBom (Join-Path $BundleRoot 'SHA256SUMS') (($lines -join "`n") + "`n")
}

function Test-PS5HSOfflineBundle([string]$BundleRoot, [switch]$HashesFresh) {
  $root = [IO.Path]::GetFullPath($BundleRoot)
  $manifestPath = Join-Path $root 'manifest.json'
  $sumsPath = Join-Path $root 'SHA256SUMS'
  if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf) -or !(Test-Path -LiteralPath $sumsPath -PathType Leaf)) {
    throw 'Falta manifest.json o SHA256SUMS en el bundle.'
  }
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  if ($manifest.schema -ne 'ps5hs-offline-bundle' -or $manifest.version -ne 1 -or !$manifest.files) {
    throw 'El manifiesto del bundle no tiene el esquema esperado.'
  }
  foreach ($relative in @('app.js', 'index.html', 'start.bat', 'INSTALL-OFFLINE.bat', 'runtime/server.ps1', 'runtime/Install-OfflineEnvironment.ps1', 'runtime/offline/OfflineEnvironment.psm1', 'runtime/offline/install-pacbrew-homebrew.py', 'runtime/offline/install-payload-dependencies.py', 'runtime/payload-dependency-profiles/shadowmountplus.json', 'docs/OFFLINE_INSTALLATION.es-ES.md', 'docs/PAYLOAD_DEPENDENCIES.es-ES.md')) {
    if ($relative -notin @($manifest.files | ForEach-Object { [string]$_.path })) { throw "Falta un archivo central de la IDE en el bundle: $relative" }
  }
  $declared = @{}
  foreach ($record in $manifest.files) {
    $relative = [string]$record.path
    if (!$relative -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[/\\])\.\.([/\\]|$)') {
      throw "Ruta no válida en manifest.json: $relative"
    }
    if ($declared.ContainsKey($relative)) { throw "Ruta duplicada en manifest.json: $relative" }
    $declared[$relative] = $record
  }
  if ($HashesFresh) {
    $currentFiles = New-Object 'System.Collections.Generic.List[object]'
    $scanRoot = $root.TrimEnd('\') + '\'
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
      $relative = $file.FullName.Substring($scanRoot.Length).Replace('\', '/')
      if ($relative -in @('manifest.json', 'SHA256SUMS')) { continue }
      if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "El bundle contiene un archivo enlazado: $relative" }
      $currentFiles.Add([pscustomobject]@{ path = $relative; bytes = [int64]$file.Length; sha256 = '' })
    }
    $currentFiles = @($currentFiles.ToArray() | Sort-Object -Property path)
  } else {
    $currentFiles = Get-PS5HSBundleFiles $root
  }
  if ($currentFiles.Count -ne $manifest.files.Count) { throw 'El inventario contiene archivos ausentes o no declarados.' }
  foreach ($record in $currentFiles) {
    if (!$declared.ContainsKey([string]$record.path)) { throw "Archivo no declarado: $($record.path)" }
    $expected = $declared[[string]$record.path]
    if ($record.bytes -ne [int64]$expected.bytes) { throw "Tamaño incorrecto: $($record.path)" }
    if (!$HashesFresh -and $record.sha256 -ne [string]$expected.sha256) { throw "Hash incorrecto: $($record.path)" }
  }
  $imageRecord = $declared[[string]$manifest.image.path]
  $imageManifestPath = Join-Path $root 'toolchains\WSL2\image-manifest.json'
  if ($manifest.image.path -ne 'toolchains/WSL2/visual-ps5-ubuntu-26.04.1-amd64.tar' -or !$imageRecord) {
    throw 'El manifiesto no apunta a la imagen WSL esperada.'
  }
  $imageManifest = Get-Content -LiteralPath $imageManifestPath -Raw | ConvertFrom-Json
  if ($imageManifest.schema -ne 'ps5hs-offline-wsl-image' -or $imageManifest.sha256 -ne $manifest.image.sha256 -or
      $imageRecord.sha256 -ne $manifest.image.sha256 -or $imageManifest.identity.ubuntu.VERSION_ID -ne '26.04' -or
      $imageManifest.identity.architecture -ne 'amd64' -or $imageManifest.identity.defaultUser -ne 'visualps5') {
    throw 'El manifiesto de bundle, la imagen o su identidad no coinciden.'
  }
  if ($imageRecord.bytes -ne [int64]$manifest.image.bytes -or $imageManifest.bytes -ne [int64]$manifest.image.bytes) {
    throw 'Los tamaños declarados del tar de Ubuntu no coinciden.'
  }
  $imageHashSidecar = Get-Content -LiteralPath (Join-Path $root 'toolchains\WSL2\visual-ps5-ubuntu-26.04.1-amd64.tar.sha256') -Raw
  if (!$imageHashSidecar.StartsWith([string]$manifest.image.sha256)) { throw 'El sidecar SHA-256 de la imagen no coincide.' }
  $lock = Get-Content -LiteralPath (Join-Path $root 'runtime\offline\image-lock.json') -Raw | ConvertFrom-Json
  $pacbrewImage = $imageManifest.identity.pacbrew
  if (!$lock.pacbrew -or !$pacbrewImage -or
      [string]$pacbrewImage.version -ne [string]$lock.pacbrew.version -or
      [string]$pacbrewImage.archiveSha256 -ne [string]$lock.pacbrew.sha256 -or
      [string]$pacbrewImage.targetPrefix -ne [string]$lock.pacbrew.targetPrefix) {
    throw 'La imagen WSL no contiene la identidad PacBrew fijada en image-lock.json.'
  }
  foreach ($requiredPacbrewFile in $lock.pacbrew.requiredFiles) {
    $verifiedPacbrewFile = $pacbrewImage.verifiedFiles.PSObject.Properties[[string]$requiredPacbrewFile]
    if (!$verifiedPacbrewFile -or [string]$verifiedPacbrewFile.Value -notmatch '^[0-9a-f]{64}$') {
      throw "La identidad de imagen no verifica la dependencia PacBrew: $requiredPacbrewFile"
    }
  }
  $wslPin = $lock.installers.wsl
  $wslRecord = $declared[[string]$manifest.installers.wsl.path]
  if (!$wslPin -or [string]$manifest.installers.wsl.path -ne [string]$wslPin.path -or
      [string]$manifest.installers.wsl.version -ne [string]$wslPin.version -or
      [int64]$manifest.installers.wsl.bytes -ne [int64]$wslPin.bytes -or
      [string]$manifest.installers.wsl.sha256 -ne [string]$wslPin.sha256 -or
      !$wslRecord -or [string]$wslRecord.sha256 -ne [string]$wslPin.sha256 -or [int64]$wslRecord.bytes -ne [int64]$wslPin.bytes) {
    throw 'El instalador WSL, la versión, el hash y el manifiesto no coinciden con el lock offline.'
  }
  foreach ($command in $lock.requiredCommands) {
    $tool = $imageManifest.identity.tools.PSObject.Properties[[string]$command]
    if (!$tool -or !$tool.Value.path) { throw "Falta el comando requerido en la imagen Ubuntu: $command" }
  }
  foreach ($requiredPath in $lock.requiredPaths) {
    if ([string]$requiredPath -notin @($imageManifest.identity.sdkPaths)) { throw "Falta la ruta requerida en la imagen Ubuntu: $requiredPath" }
  }
  $readiness = Get-Content -LiteralPath (Join-Path $root 'runtime\offline\backend-readiness.json') -Raw | ConvertFrom-Json
  if ($readiness.schema -ne 'ps5hs-offline-backend-readiness' -or $readiness.backends.Count -ne $manifest.backends.Count) {
    throw 'El estado de backends del bundle no coincide con su manifiesto.'
  }
  $linkMetadata = Get-Content -LiteralPath (Join-Path $root 'runtime\offline\bundle-links.json') -Raw | ConvertFrom-Json
  $manifestLinkCount = 0
  foreach ($link in $manifest.bundleLinks) {
    $manifestLinkCount++
    if (!(Test-Path -LiteralPath (Join-Path $root ($link.path -replace '/', '\')) -PathType Container) -or
        !(Test-Path -LiteralPath (Join-Path $root ($link.target -replace '/', '\')) -PathType Container)) {
      throw "Falta la ruta materializada de enlace $($link.path) o su destino $($link.target)."
    }
  }
  $sourceLinkCount = 0
  foreach ($link in $linkMetadata.links) { $sourceLinkCount++ }
  if ($linkMetadata.schema -ne 'ps5hs-offline-bundle-links' -or $manifestLinkCount -ne $sourceLinkCount) {
    throw 'El registro de rutas enlazadas no coincide con el bundle.'
  }
  $pins = Get-Content -LiteralPath (Join-Path $root 'runtime\toolchain-pins.json') -Raw | ConvertFrom-Json
  if ($pins.schema -ne 'ps5hs-toolchain-pins') { throw 'runtime/toolchain-pins.json no es válido.' }
  $pacbrewPinProperty = $pins.artifacts.PSObject.Properties['pacbrew']
  if (!$pacbrewPinProperty -or
      [string]$lock.pacbrew.version -ne [string]$pacbrewPinProperty.Value.version -or
      [string]$lock.pacbrew.sha256 -ne [string]$pacbrewPinProperty.Value.archive.sha256 -or
      [string]$lock.pacbrew.artifact -ne [string]$pacbrewPinProperty.Value.localPath) {
    throw 'El lock PacBrew de la imagen no coincide con runtime/toolchain-pins.json.'
  }
  $expectedPinnedCount = 0
  foreach ($entry in $pins.artifacts.PSObject.Properties) {
    $expectedPinnedCount++
    $relative = [string]$entry.Value.localPath
    $pinnedRecord = $declared[$relative.Replace('\', '/')]
    if (!$pinnedRecord -or $pinnedRecord.sha256 -ne [string]$entry.Value.archive.sha256) {
      throw "Falta o no coincide el artefacto local fijado $($entry.Name)."
    }
  }
  $manifestPinnedCount = 0
  foreach ($pinnedItem in $manifest.pinnedArtifacts) { $manifestPinnedCount++ }
  if ($manifestPinnedCount -ne $expectedPinnedCount) { throw 'El listado de artefactos fijados no está completo.' }
  $expectedSums = @{}
  foreach ($record in $manifest.files) {
    $expectedSums[[string]$record.path] = [pscustomobject]@{ path = [string]$record.path; sha256 = [string]$record.sha256 }
  }
  $actualLines = @(Get-Content -LiteralPath $sumsPath)
  if ($actualLines.Count -ne $expectedSums.Count) { throw 'SHA256SUMS no coincide con el manifiesto.' }
  $seenSums = @{}
  foreach ($line in $actualLines) {
    if ($line -notmatch '^([0-9a-fA-F]{64})  (.+)$') { throw 'SHA256SUMS contiene una línea no válida.' }
    $sum = $Matches[1].ToLowerInvariant()
    $relative = $Matches[2]
    if ($seenSums.ContainsKey($relative)) { throw "SHA256SUMS repite la ruta $relative." }
    $expected = $expectedSums[$relative]
    if (!$expected -or $sum -cne $expected.sha256 -or [string]$expected.path -cne $relative) {
      throw "SHA256SUMS no coincide con el manifiesto para $relative."
    }
    $seenSums[$relative] = $true
  }
  $wslSignaturePath = Join-Path $root 'toolchains\WSL2\wsl.2.9.13.0.x64.msi'
  $null = Assert-PS5HSAuthenticode $wslSignaturePath 'Microsoft Corporation'
  $ps7SignaturePath = Join-Path $root 'toolchains\PowerShell7\PowerShell-7.6.1-win-x64.msi'
  if (Test-Path -LiteralPath $ps7SignaturePath -PathType Leaf) { $null = Assert-PS5HSAuthenticode $ps7SignaturePath 'Microsoft Corporation' }
  return [pscustomobject]@{ valid = $true; fileCount = $manifest.files.Count; totalBytes = [int64](($manifest.files | Measure-Object -Property bytes -Sum).Sum); imageBytes = [int64]$manifest.image.bytes; imageSha256 = $manifest.image.sha256; backendCount = $manifest.backends.Count; hashesFresh = [bool]$HashesFresh }
}

Export-ModuleMember -Function New-PS5HSOfflineBundleManifest, Write-PS5HSSha256Sums, Test-PS5HSOfflineBundle
