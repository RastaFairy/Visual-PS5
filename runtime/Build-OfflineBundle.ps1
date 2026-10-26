#requires -Version 5.1
[CmdletBinding()]
param(
  [string]$InputRoot = '',
  [Parameter(Mandatory = $true)][string]$OutputRoot,
  [string]$WslDistro = 'Ubuntu',
  [string]$ResumeStageRoot = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'offline/OfflineBundle.psm1') -Force
$ideRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($InputRoot)) { $InputRoot = $ideRoot }
$InputRoot = [IO.Path]::GetFullPath($InputRoot)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (!(Test-Path -LiteralPath $InputRoot -PathType Container)) { throw "No existe la entrada: $InputRoot" }
$inputPrefix = $InputRoot.TrimEnd('\') + '\'
$outputPrefix = $OutputRoot.TrimEnd('\') + '\'
if ($OutputRoot.StartsWith($inputPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    $InputRoot.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'La carpeta de salida debe estar fuera del árbol de entrada.'
}
if (Test-Path -LiteralPath $OutputRoot) {
  if ((Get-ChildItem -LiteralPath $OutputRoot -Force | Measure-Object).Count -gt 0) { throw "La salida debe estar vacía: $OutputRoot" }
} else {
  $outputParent = Split-Path -Parent $OutputRoot
  if (!(Test-Path -LiteralPath $outputParent -PathType Container)) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
  }
}

function ConvertTo-OfflineWslPath([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  if ($full -notmatch '^([A-Za-z]):\\(.*)$') { throw "No se puede convertir la ruta del enlace a WSL: $full" }
  return ('/mnt/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\', '/'))
}

$stageParent = [IO.Path]::GetFullPath((Split-Path -Parent $OutputRoot)).TrimEnd('\') + '\'
$stageHasManifest = $false
if ($ResumeStageRoot) {
  $stage = [IO.Path]::GetFullPath($ResumeStageRoot)
  if (!$stage.StartsWith($stageParent, [StringComparison]::OrdinalIgnoreCase) -or
      [IO.Path]::GetFileName($stage) -notmatch '^\.ps5hs-offline-bundle-[a-f0-9]{32}$') {
    throw "El staging de reanudación debe estar en $stageParent y tener nombre .ps5hs-offline-bundle-<guid>."
  }
  if (!(Test-Path -LiteralPath $stage -PathType Container)) { throw "No existe el staging para reanudar: $stage" }
  $stageHasManifest = Test-Path -LiteralPath (Join-Path $stage 'manifest.json') -PathType Leaf
  if ($stageHasManifest -and !(Test-Path -LiteralPath (Join-Path $stage 'SHA256SUMS') -PathType Leaf)) {
    throw 'El staging tiene manifiesto, pero no SHA256SUMS; no se modifica.'
  }
  Write-Output "Reanudando staging: $stage"
} else {
  $stage = Join-Path (Split-Path -Parent $OutputRoot) ('.ps5hs-offline-bundle-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $stage | Out-Null
}
if ($stageHasManifest) {
  $check = Test-PS5HSOfflineBundle $stage -HashesFresh
  if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Force }
  Move-Item -LiteralPath $stage -Destination $OutputRoot
  Write-Output ("Bundle validado: {0} archivos, {1:N0} bytes" -f $check.fileCount, $check.totalBytes)
  Write-Output "Salida: $OutputRoot"
  Write-Output "Imagen SHA-256: $($check.imageSha256)"
  exit 0
}
try {
  $linksPath = Join-Path $InputRoot 'runtime\offline\bundle-links.json'
  $linksManifest = Get-Content -LiteralPath $linksPath -Raw | ConvertFrom-Json
  if ($linksManifest.schema -ne 'ps5hs-offline-bundle-links' -or $null -eq $linksManifest.links) { throw 'runtime/offline/bundle-links.json no es válido.' }
  $expectedLinkPaths = @()
  foreach ($link in $linksManifest.links) {
    $expectedLinkPaths += [IO.Path]::GetFullPath((Join-Path $InputRoot ($link.path -replace '/', '\')))
  }
  $sourceReparse = @(Get-ChildItem -LiteralPath $InputRoot -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike ((Join-Path $InputRoot '.runtime') + '\*') -and $_.FullName -notlike ((Join-Path $InputRoot '.git') + '\*') })
  if ($sourceReparse.Count -ne $expectedLinkPaths.Count) {
    throw "Hay $($sourceReparse.Count) enlaces en la fuente y $($expectedLinkPaths.Count) documentados; se cancela para no omitir rutas."
  }
  foreach ($sourceLink in $sourceReparse) {
    $sourceLinkPath = [IO.Path]::GetFullPath($sourceLink.FullName)
    if ($sourceLinkPath -notin $expectedLinkPaths) { throw "Enlace no declarado en bundle-links.json: $sourceLinkPath" }
    $linkWsl = ConvertTo-OfflineWslPath $sourceLinkPath
    $resolvedLines = @(& wsl.exe -d $WslDistro --exec /bin/readlink -f -- $linkWsl 2>&1)
    $resolvedCode = $LASTEXITCODE
    if ($resolvedCode -ne 0 -or !$resolvedLines.Count) { throw "No se pudo resolver el enlace local $sourceLinkPath con WSL '$WslDistro'." }
    $resolvedWsl = (($resolvedLines | ForEach-Object { $_.ToString() -replace "`0", '' }) -join "`n").Trim()
    $windowsLines = @(& wsl.exe -d $WslDistro --exec /usr/bin/wslpath -w $resolvedWsl 2>&1)
    if ($LASTEXITCODE -ne 0 -or !$windowsLines.Count) { throw "No se pudo convertir el destino del enlace a Windows: $resolvedWsl" }
    $resolvedWindows = [IO.Path]::GetFullPath((($windowsLines | ForEach-Object { $_.ToString() -replace "`0", '' }) -join '').Trim())
    $expectedTarget = [IO.Path]::GetFullPath((Join-Path $InputRoot ([string]$link.target -replace '/', '\')))
    if ($resolvedWindows -ne $expectedTarget -or !$resolvedWindows.StartsWith($inputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "El enlace $sourceLinkPath apunta fuera del destino declarado: $resolvedWindows"
    }
  }

  $exclude = @((Join-Path $InputRoot '.runtime'), (Join-Path $InputRoot '.git'))
  & robocopy.exe $InputRoot $stage /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /NP /NFL /NDL /NJH /NJS /XD $exclude
  $copyCode = $LASTEXITCODE
  if ($copyCode -ge 8) { throw "No se pudo copiar el contenido offline (robocopy $copyCode)." }

  foreach ($link in $linksManifest.links) {
    $sourceTarget = Join-Path $InputRoot ([string]$link.target -replace '/', '\')
    $destinationLink = Join-Path $stage ([string]$link.path -replace '/', '\')
    if (!(Test-Path -LiteralPath $sourceTarget -PathType Container)) { throw "Falta el destino enlazado en la fuente: $sourceTarget" }
    if (Test-Path -LiteralPath $destinationLink) {
      $destinationInfo = Get-Item -LiteralPath $destinationLink -Force
      if (($destinationInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "El destino del bundle conserva un enlace sin materializar: $destinationLink" }
    }
    & robocopy.exe $sourceTarget $destinationLink /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NP /NFL /NDL /NJH /NJS
    if ($LASTEXITCODE -ge 8) { throw "No se pudo materializar la ruta enlazada $($link.path)." }
    if (!(Test-Path -LiteralPath $destinationLink -PathType Container)) { throw "No se creó la ruta materializada: $destinationLink" }
  }
  if (Test-Path -LiteralPath (Join-Path $stage '.runtime')) { throw 'El bundle no puede contener estado temporal de .runtime.' }

  $manifest = New-PS5HSOfflineBundleManifest $stage
  $manifestPath = Join-Path $stage 'manifest.json'
  [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding($false)))
  Write-PS5HSSha256Sums $stage $manifest.files
  $check = Test-PS5HSOfflineBundle $stage -HashesFresh
  Write-Output ("Bundle validado: {0} archivos, {1:N0} bytes" -f $check.fileCount, $check.totalBytes)
  if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Force
  }
  Move-Item -LiteralPath $stage -Destination $OutputRoot
  Write-Output "Salida: $OutputRoot"
  Write-Output "Imagen SHA-256: $($check.imageSha256)"
} catch {
  if (Test-Path -LiteralPath $stage) {
    $stageFull = [IO.Path]::GetFullPath($stage)
    $parentFull = [IO.Path]::GetFullPath((Split-Path -Parent $OutputRoot)).TrimEnd('\') + '\'
    if ($stageFull.StartsWith($parentFull, [StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $stageFull -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  throw
}
