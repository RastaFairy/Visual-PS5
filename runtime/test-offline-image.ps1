#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scriptPath = Join-Path $PSScriptRoot 'offline/prepare-image.sh'
$lockPath = Join-Path $PSScriptRoot 'offline/image-lock.json'
$preparePath = Join-Path $PSScriptRoot 'Prepare-OfflineImage.ps1'

function Assert-Condition([bool]$Condition, [string]$Message) {
  if (!$Condition) { throw $Message }
}

foreach ($path in @($scriptPath, $lockPath, $preparePath)) {
  Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "Falta el archivo previsto: $path"
}

$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
Assert-Condition ($lock.schema -eq 'ps5hs-offline-image-lock') 'El lock de imagen tiene un schema incorrecto.'
Assert-Condition ($lock.ubuntu.versionId -eq '26.04') 'El lock debe fijar la version Ubuntu auditada.'
Assert-Condition ($lock.ubuntu.architecture -eq 'amd64') 'El lock debe fijar la arquitectura de la imagen.'
Assert-Condition ($lock.ubuntu.defaultUser -eq 'visualps5') 'El lock debe definir un usuario WSL generico.'
Assert-Condition (($lock.requiredCommands | Measure-Object).Count -ge 8) 'El lock debe enumerar las herramientas host requeridas.'

$wslCommand = Get-Command 'wsl.exe' -ErrorAction SilentlyContinue
Assert-Condition ($null -ne $wslCommand) 'La prueba de imagen necesita WSL instalado en el equipo de autoría.'

function Convert-ToWslPath([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  if ($full -notmatch '^([A-Za-z]):\\(.*)$') { throw "No se puede convertir a ruta WSL: $full" }
  return ('/mnt/' + $Matches[1].ToLowerInvariant() + '/' + ($Matches[2] -replace '\\','/'))
}
function Quote-Bash([string]$Value) {
  $replacement = [string]::Concat("'", '"', "'", '"', "'")
  return "'" + $Value.Replace("'", $replacement) + "'"
}
function Invoke-TestWsl([string[]]$Arguments, [string]$Label) {
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $result = @(& wsl.exe @Arguments 2>&1)
  $code = $LASTEXITCODE
  $ErrorActionPreference = $previousPreference
  if ($code -ne 0) { throw "$Label fallo con codigo $code. $($result -join ' ')" }
  return ($result | ForEach-Object { $_.ToString() -replace "`0", '' }) -join "`n"
}

$scriptWsl = Convert-ToWslPath $scriptPath
$null = Invoke-TestWsl @('--exec', '/bin/bash', '-n', $scriptWsl) 'Validacion sintactica del limpiador'

$fixture = Join-Path $env:TEMP ('ps5hs-offline-image-test-' + [guid]::NewGuid().ToString('N'))
$fixtureFull = [IO.Path]::GetFullPath($fixture)
$tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
if (!$fixtureFull.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw "La ruta temporal de prueba queda fuera de TEMP: $fixtureFull"
}
$fixtureWsl = Convert-ToWslPath $fixtureFull
$quotedRoot = Quote-Bash $fixtureWsl
$quotedScript = Quote-Bash $scriptWsl
$seedCommand = "set -eu; mkdir -p $quotedRoot/home/rasta/.cache/ps5-native-builds/TALLER/build $quotedRoot/home/rasta/.cache/ps5-native-builds/TALLER/.deps/native $quotedRoot/etc/skel $quotedRoot/opt/ps5-payload-sdk/bin $quotedRoot/var/lib/dpkg; touch $quotedRoot/.ps5hs-offline-image-test-root; printf generated > $quotedRoot/home/rasta/.cache/ps5-native-builds/TALLER/build/eboot.elf; printf cached > $quotedRoot/home/rasta/.cache/ps5-native-builds/TALLER/.deps/native/required.archive; printf '# default shell' > $quotedRoot/etc/skel/.bashrc; printf SDK > $quotedRoot/opt/ps5-payload-sdk/bin/prospero-lld; printf status > $quotedRoot/var/lib/dpkg/status"

try {
  $null = Invoke-TestWsl @('--exec', '/bin/bash', '-c', $seedCommand) 'Creacion de fixture'
  $dryRun = "bash $quotedScript --root $quotedRoot --source-user rasta"
  $null = Invoke-TestWsl @('--exec', '/bin/bash', '-c', $dryRun) 'Limpieza dry-run'
  $checkDryRun = "test -f $quotedRoot/home/rasta/.cache/ps5-native-builds/TALLER/build/eboot.elf"
  $null = Invoke-TestWsl @('--exec', '/bin/bash', '-c', $checkDryRun) 'El dry-run debe conservar archivos'

  $apply = $dryRun + ' --apply'
  $null = Invoke-TestWsl @('--exec', '/bin/bash', '-c', $apply) 'Limpieza de fixture'
  $checkApply = "test ! -e $quotedRoot/home/rasta; test -f $quotedRoot/home/visualps5/.bashrc; test -f $quotedRoot/opt/ps5-payload-sdk/bin/prospero-lld; test -f $quotedRoot/var/lib/dpkg/status"
  $null = Invoke-TestWsl @('--exec', '/bin/bash', '-c', $checkApply) 'Preservacion de SDK y base de paquetes'

  $guardBlocked = $false
  try { $null = Invoke-TestWsl @('--exec', '/bin/bash', $scriptWsl) 'Guardia de la distro fuente' }
  catch { $guardBlocked = $true }
  Assert-Condition $guardBlocked 'El limpiador permitio ejecutarse contra / sin la marca de staging.'
  Write-Host 'PASS: lock, sintaxis, dry-run, limpieza aislada y guardia contra la distro fuente.' -ForegroundColor Green
}
finally {
  if (Test-Path -LiteralPath $fixtureFull) {
    $resolved = [IO.Path]::GetFullPath($fixtureFull)
    if ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $resolved -Recurse -Force
    }
  }
}
