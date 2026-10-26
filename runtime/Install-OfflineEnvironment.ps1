#requires -Version 5.1
[CmdletBinding()]
param(
  [string]$BundleRoot = '',
  [switch]$Apply
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($BundleRoot)) { $BundleRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')) }
$BundleRoot = [IO.Path]::GetFullPath($BundleRoot)
$scriptPath = [IO.Path]::GetFullPath($MyInvocation.MyCommand.Path)
Import-Module (Join-Path $PSScriptRoot 'offline/OfflineEnvironment.psm1') -Force

try {
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  $quickBeforeElevation = $Apply -and !$isAdmin
  $preflight = Get-PS5HSOfflineHostPreflight -BundleRoot $BundleRoot -HashesFresh:$quickBeforeElevation
  Write-Host 'Visual-PS5: diagnóstico del entorno offline' -ForegroundColor Cyan
  if ($preflight.host) {
    Write-Host ("Windows: {0}, compilación {1}, {2}" -f $preflight.host.productName, $preflight.host.build, $preflight.host.architecture)
    Write-Host ("Virtualización: {0}; WSL: {1}; espacio libre: {2:N1} GB" -f $preflight.host.virtualization, $(if ($preflight.host.wslVersion) { $preflight.host.wslVersion } else { 'no disponible' }), ($preflight.freeBytes / 1GB))
  }
  foreach ($warning in $preflight.warnings) { Write-Host ('AVISO: ' + $warning) -ForegroundColor Yellow }
  foreach ($errorItem in $preflight.errors) { Write-Host ('BLOQUEO: ' + $errorItem) -ForegroundColor Red }
  if (!$preflight.canApply) { exit 2 }
  if (!$Apply) {
    Write-Host 'Diagnóstico completado sin modificar Windows. Ejecuta INSTALL-OFFLINE.bat para instalar.' -ForegroundColor Green
    exit 0
  }

  if ($preflight.requiresElevation -and !$isAdmin) {
    $psExe = Join-Path $PSHOME 'powershell.exe'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -BundleRoot "{1}" -Apply' -f $scriptPath.Replace('"', '""'), $BundleRoot.Replace('"', '""')
    Write-Host 'Windows solicitará autorización para habilitar WSL e instalar su componente local.' -ForegroundColor Yellow
    $process = Start-Process -FilePath $psExe -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
  }

  if ($quickBeforeElevation) {
    $preflight = Get-PS5HSOfflineHostPreflight -BundleRoot $BundleRoot
    foreach ($errorItem in $preflight.errors) { Write-Host ('BLOQUEO: ' + $errorItem) -ForegroundColor Red }
    if (!$preflight.canApply) { exit 2 }
  }
  $result = Install-PS5HSOfflineEnvironment -BundleRoot $BundleRoot -Apply -ValidatedPreflight $preflight
  if ($result.status -eq 'restart-required') {
    Write-Host $result.message -ForegroundColor Yellow
    Write-Host ("Estado guardado en: {0}" -f $result.statePath)
    exit 3010
  }
  Write-Host ("Entorno instalado y verificado: {0}" -f $result.distroName) -ForegroundColor Green
  Write-Host ("Imagen SHA-256: {0}" -f $result.imageSha256)
  Write-Host 'El instalador no descargó componentes ni modificó BIOS/UEFI.' -ForegroundColor Green
  exit 0
} catch {
  Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
  exit 1
}
