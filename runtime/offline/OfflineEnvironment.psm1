#requires -Version 5.1
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'OfflineBundle.psm1') -Force

$script:PS5HSOfflineDistroName = 'VisualPS5-Ubuntu-26.04'
$script:PS5HSOfflineWslMsiVersion = [version]'2.9.13.0'

function Get-PS5HSOfflineHostSnapshot {
  $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
  $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
  $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue)
  $virtualization = 'Unknown'
  if ($system -and $system.HypervisorPresent) {
    $virtualization = 'Ready'
  } elseif ($processors.Count -and @($processors | Where-Object { $_.VirtualizationFirmwareEnabled -eq $true }).Count) {
    $virtualization = 'Ready'
  } elseif ($processors.Count -and @($processors | Where-Object { $_.VirtualizationFirmwareEnabled -eq $false }).Count -eq $processors.Count) {
    $virtualization = 'Disabled'
  }

  $featureStates = @{}
  foreach ($feature in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    try {
      $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction Stop
      $featureStates[$feature] = [string]$state.State
    } catch {
      $featureStates[$feature] = 'Unknown'
    }
  }

  $wslCommand = Get-Command 'wsl.exe' -ErrorAction SilentlyContinue
  $wslVersion = $null
  $distroNames = @()
  if ($wslCommand) {
    $versionOutput = @(& $wslCommand.Source --version 2>&1)
    if ($LASTEXITCODE -eq 0) {
      $versionText = ($versionOutput | ForEach-Object { $_.ToString() -replace "`0", '' }) -join "`n"
      if ($versionText -match '(?im)^WSL\s*version:\s*([0-9]+(?:\.[0-9]+){1,3})') { $wslVersion = $Matches[1] }
    }
    $distroOutput = @(& $wslCommand.Source --list --quiet 2>&1)
    if ($LASTEXITCODE -eq 0) {
      $distroNames = @($distroOutput | ForEach-Object { ($_.ToString() -replace "`0", '').Trim() } | Where-Object { $_ })
    }
  }

  $distroRegistry = @()
  $registryRoot = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
  if (Test-Path -LiteralPath $registryRoot) {
    foreach ($key in Get-ChildItem -LiteralPath $registryRoot -ErrorAction SilentlyContinue) {
      $entry = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
      if ($entry.DistributionName) {
        $distroRegistry += [pscustomobject]@{ name = [string]$entry.DistributionName; basePath = [string]$entry.BasePath }
      }
    }
  }
  foreach ($name in $distroNames) {
    if (@($distroRegistry | Where-Object { $_.name -ieq $name }).Count -eq 0) {
      $distroRegistry += [pscustomobject]@{ name = $name; basePath = '' }
    }
  }

  $pendingRestart = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
  try {
    $rename = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
    if ($rename.PendingFileRenameOperations) { $pendingRestart = $true }
  } catch {}

  $driveRoot = [IO.Path]::GetPathRoot($env:LOCALAPPDATA)
  $drive = New-Object -TypeName IO.DriveInfo -ArgumentList $driveRoot
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  [pscustomobject]@{
    productName = [string]$os.Caption
    version = [string]$os.Version
    build = [int]$os.BuildNumber
    architecture = [string]$os.OSArchitecture
    isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    virtualization = $virtualization
    windowsFeatures = $featureStates
    wslAvailable = [bool]$wslCommand
    wslVersion = $wslVersion
    distros = @($distroRegistry)
    pendingRestart = [bool]$pendingRestart
    installDriveFreeBytes = [int64]$drive.AvailableFreeSpace
  }
}

function Get-PS5HSOfflineHostPreflight {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$BundleRoot,
    [pscustomobject]$HostSnapshot,
    [switch]$HashesFresh
  )
  $root = [IO.Path]::GetFullPath($BundleRoot)
  $errors = New-Object 'System.Collections.Generic.List[string]'
  $warnings = New-Object 'System.Collections.Generic.List[string]'
  $bundleCheck = $null
  try { $bundleCheck = Test-PS5HSOfflineBundle -BundleRoot $root -HashesFresh:$HashesFresh }
  catch { $errors.Add($_.Exception.Message) }
  if (!$HostSnapshot) {
    try { $HostSnapshot = Get-PS5HSOfflineHostSnapshot }
    catch { $errors.Add("No se pudo leer el estado de Windows: $($_.Exception.Message)") }
  }
  if (!$HostSnapshot) {
    return [pscustomobject]@{ compatible = $false; ready = $false; canApply = $false; requiresElevation = $true; errors = @($errors.ToArray()); warnings = @(); bundle = $bundleCheck }
  }

  if ([int]$HostSnapshot.build -lt 22000 -or [string]$HostSnapshot.productName -notmatch 'Windows 11') {
    $errors.Add("Se requiere Windows 11 (compilación 22000 o posterior); detectado: $($HostSnapshot.productName), compilación $($HostSnapshot.build).")
  }
  if ([string]$HostSnapshot.architecture -notmatch '^(?i:x64|amd64|64-bit)$') {
    $errors.Add("La arquitectura de Windows no es compatible con este bundle: $($HostSnapshot.architecture).")
  }
  if ([string]$HostSnapshot.virtualization -eq 'Disabled') {
    $errors.Add('La virtualización de firmware parece deshabilitada. Actívala en BIOS/UEFI y vuelve a ejecutar el preflight; el instalador no cambia ajustes de firmware.')
  } elseif ([string]$HostSnapshot.virtualization -ne 'Ready') {
    $errors.Add('No se pudo confirmar que la virtualización esté disponible. Comprueba BIOS/UEFI y las capacidades de virtualización de Windows antes de instalar.')
  }
  if ([bool]$HostSnapshot.pendingRestart) { $warnings.Add('Windows informa de un reinicio pendiente. Reinicia antes de instalar componentes WSL.') }

  $featureNames = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')
  $featuresReady = $true
  foreach ($feature in $featureNames) {
    $state = [string]$HostSnapshot.windowsFeatures[$feature]
    if ($state -ne 'Enabled') {
      $featuresReady = $false
      if ($state -eq 'Unknown' -and $HostSnapshot.isElevated -eq $true) { $errors.Add("No se pudo consultar el estado de la característica local $feature incluso con elevación.") }
      elseif ($state -eq 'Unknown') { $warnings.Add("No se pudo consultar $feature sin elevación; se volverá a comprobar después de UAC.") }
      elseif ($state -notin @('Disabled', 'DisabledWithPayloadRemoved')) { $warnings.Add("La característica $feature indica el estado $state; puede requerir reinicio.") }
    }
  }
  if ($HostSnapshot.pendingRestart) { $errors.Add('Hay un reinicio de Windows pendiente; completa el reinicio antes de aplicar cambios.') }

  $minimumBytes = [int64]10GB
  if ($bundleCheck) { $minimumBytes = [Math]::Max($minimumBytes, [int64]($bundleCheck.imageBytes * 2 + 8GB)) }
  $freeBytes = [int64]$HostSnapshot.installDriveFreeBytes
  if ($freeBytes -lt $minimumBytes) {
    $errors.Add(('Espacio insuficiente en la unidad de instalación: {0:N0} bytes libres; se recomiendan {1:N0} bytes.' -f $freeBytes, $minimumBytes))
  }

  $installRoot = Join-Path $env:LOCALAPPDATA 'Visual-PS5\WSL\Ubuntu-26.04'
  $existingDistro = @($HostSnapshot.distros | Where-Object { $_.name -ieq $script:PS5HSOfflineDistroName } | Select-Object -First 1)
  if ($existingDistro.Count -and $existingDistro[0].basePath -and
      [IO.Path]::GetFullPath([string]$existingDistro[0].basePath).TrimEnd('\') -ine [IO.Path]::GetFullPath($installRoot).TrimEnd('\')) {
    $errors.Add("Ya existe la distribución $($script:PS5HSOfflineDistroName) en otra ruta; no se sobrescribirá.")
  }
  if (!$existingDistro.Count -and (Test-Path -LiteralPath $installRoot)) {
    $hasFiles = @(Get-ChildItem -LiteralPath $installRoot -Force -ErrorAction SilentlyContinue).Count -gt 0
    if ($hasFiles) { $errors.Add("La ruta de instalación ya contiene datos y no pertenece a una distribución registrada: $installRoot") }
  }
  $wslVersion = $null
  try { if ($HostSnapshot.wslVersion) { $wslVersion = [version][string]$HostSnapshot.wslVersion } } catch {}
  $needsWslMsi = !$HostSnapshot.wslAvailable -or !$wslVersion -or $wslVersion -lt $script:PS5HSOfflineWslMsiVersion
  $needsFeatures = !$featuresReady
  $compatible = $errors.Count -eq 0
  [pscustomobject]@{
    compatible = $compatible
    ready = $compatible -and $featuresReady -and !$needsWslMsi -and $existingDistro.Count -gt 0
    canApply = $compatible
    requiresElevation = $needsFeatures -or $needsWslMsi
    requiresRestart = [bool]$HostSnapshot.pendingRestart
    distroName = $script:PS5HSOfflineDistroName
    installRoot = $installRoot
    existingDistro = if ($existingDistro.Count) { $existingDistro[0] } else { $null }
    needsWslMsi = $needsWslMsi
    needsFeatures = $needsFeatures
    minimumFreeBytes = $minimumBytes
    freeBytes = $freeBytes
    bundleRoot = $root
    errors = @($errors.ToArray())
    warnings = @($warnings.ToArray())
    bundle = $bundleCheck
    host = $HostSnapshot
  }
}

function Invoke-PS5HSOfflineOperation {
  param([string]$Name, [object]$Arguments, [scriptblock]$ActionRunner)
  if ($ActionRunner) { return (& $ActionRunner $Name $Arguments) }
  switch ($Name) {
    'EnableWindowsFeatures' {
      foreach ($feature in $Arguments.features) {
        & dism.exe /Online /Enable-Feature /FeatureName:$feature /All /NoRestart /LimitAccess | Out-Null
        if ($LASTEXITCODE -notin @(0, 3010)) { throw "DISM no pudo habilitar $feature (código $LASTEXITCODE). No se intentó acceder a Windows Update." }
        if ($LASTEXITCODE -eq 3010) { return [pscustomobject]@{ exitCode = 3010; requiresRestart = $true } }
      }
      return [pscustomobject]@{ exitCode = 0 }
    }
    'InstallWslMsi' {
      $argumentLine = '/i "{0}" /qn /norestart' -f [string]$Arguments.path
      $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $argumentLine -Wait -PassThru
      if ($process.ExitCode -notin @(0, 3010)) { throw "El MSI local de WSL falló con código $($process.ExitCode)." }
      return [pscustomobject]@{ exitCode = [int]$process.ExitCode; requiresRestart = ($process.ExitCode -eq 3010) }
    }
    'ImportDistro' {
      $output = @(& wsl.exe --import $Arguments.name $Arguments.installRoot $Arguments.imagePath --version 2 2>&1)
      if ($LASTEXITCODE -ne 0) { throw "WSL no pudo importar la imagen local (código $LASTEXITCODE): $($output -join ' ')" }
      return [pscustomobject]@{ exitCode = 0; output = ($output -join "`n") }
    }
    'VerifyDistro' {
      $script = 'set -eu; test "$(id -un)" = visualps5; test -x /opt/ps5-payload-sdk/bin/prospero-lld; test -x "$(command -v cmake)"; test -x "$(command -v git)"; test "$(. /etc/os-release; printf %s "$VERSION_ID")" = 26.04; homebrew=/opt/ps5-payload-sdk/target/user/homebrew; for f in include/json-c/json.h include/microhttpd.h include/png.h include/sqlite3.h include/zlib.h lib/libjson-c.a lib/libmicrohttpd.a lib/libpng16.a lib/libsqlite3.a lib/libz.a .ps5hs-pacbrew-install.json; do test -s "$homebrew/$f" || { echo "Missing pinned PacBrew dependency: $homebrew/$f" >&2; exit 1; }; done'
      $output = @(& wsl.exe -d $Arguments.name --exec /bin/bash -lc $script 2>&1)
      if ($LASTEXITCODE -ne 0) { throw "La distro importada no pasó la comprobación de identidad/herramientas: $($output -join ' ')" }
      return [pscustomobject]@{ exitCode = 0; output = ($output -join "`n") }
    }
    default { throw "Operación offline desconocida: $Name" }
  }
}

function Install-PS5HSOfflineEnvironment {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$BundleRoot,
    [switch]$Apply,
    [pscustomobject]$ValidatedPreflight,
    [pscustomobject]$HostSnapshot,
    [scriptblock]$ActionRunner
  )
  $root = [IO.Path]::GetFullPath($BundleRoot)
  if ($ValidatedPreflight) {
    if ([IO.Path]::GetFullPath([string]$ValidatedPreflight.bundleRoot) -ine $root -or !$ValidatedPreflight.bundle -or !$ValidatedPreflight.bundle.valid -or $ValidatedPreflight.bundle.hashesFresh) {
      throw 'El preflight suministrado no valida este bundle; vuelve a ejecutar el diagnóstico.'
    }
    $preflight = $ValidatedPreflight
  } else {
    $preflight = Get-PS5HSOfflineHostPreflight -BundleRoot $root -HostSnapshot $HostSnapshot
  }
  if (!$Apply) { return $preflight }
  if (!$preflight.canApply) { throw ('Preflight bloqueó la instalación: ' + ($preflight.errors -join ' ')) }
  if (!$HostSnapshot) { $HostSnapshot = Get-PS5HSOfflineHostSnapshot }
  if ($HostSnapshot.isElevated -ne $true -and $preflight.requiresElevation -and !$ActionRunner) {
    throw 'La instalación necesita elevación para habilitar WSL o instalar el MSI. Vuelve a ejecutar INSTALL-OFFLINE.bat con privilegios de administrador.'
  }

  $imagePath = Join-Path $root 'toolchains\WSL2\visual-ps5-ubuntu-26.04.1-amd64.tar'
  $msiPath = Join-Path $root 'toolchains\WSL2\wsl.2.9.13.0.x64.msi'
  $stateRoot = Join-Path $env:LOCALAPPDATA 'Visual-PS5'
  if (!(Test-Path -LiteralPath $stateRoot)) { New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null }
  $statePath = Join-Path $stateRoot 'offline-install.json'
  $state = [ordered]@{ schema = 'ps5hs-offline-install-state'; version = 1; distroName = $preflight.distroName; installRoot = $preflight.installRoot; stage = 'preflight'; updatedUtc = [DateTime]::UtcNow.ToString('o') }

  if ($preflight.needsFeatures) {
    $disabled = @(@('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform') | Where-Object { [string]$HostSnapshot.windowsFeatures[$_] -ne 'Enabled' })
    $featureResult = Invoke-PS5HSOfflineOperation -Name 'EnableWindowsFeatures' -Arguments ([pscustomobject]@{ features = $disabled; sourceMode = 'local-only' }) -ActionRunner $ActionRunner
    $featureRestartNeeded = $featureResult -and ($featureResult.requiresRestart -or [int]$featureResult.exitCode -eq 3010)
    $featureStatesAfterApply = $null
    if (!$ActionRunner -and !$featureRestartNeeded) {
      $afterFeatureSnapshot = Get-PS5HSOfflineHostSnapshot
      $featureStatesAfterApply = $afterFeatureSnapshot.windowsFeatures
      $featureRestartNeeded = [bool]$afterFeatureSnapshot.pendingRestart -or
        @($disabled | Where-Object { [string]$featureStatesAfterApply[$_] -match 'Pending' }).Count -gt 0
      $failedFeatures = @($disabled | Where-Object { [string]$featureStatesAfterApply[$_] -ne 'Enabled' -and [string]$featureStatesAfterApply[$_] -notmatch 'Pending' })
      if ($failedFeatures.Count) { throw ('Windows no activó las características locales: ' + (($failedFeatures | ForEach-Object { $_ + ' (' + [string]$featureStatesAfterApply[$_] + ')' }) -join ', ')) }
    }
    if ($featureRestartNeeded) {
      $state.stage = 'restart-required'; $state.updatedUtc = [DateTime]::UtcNow.ToString('o')
      [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
      return [pscustomobject]@{ status = 'restart-required'; statePath = $statePath; message = 'Reinicia Windows y vuelve a ejecutar INSTALL-OFFLINE.bat para continuar.' }
    }
  }
  if ($preflight.needsWslMsi) {
    $msiResult = Invoke-PS5HSOfflineOperation -Name 'InstallWslMsi' -Arguments ([pscustomobject]@{ path = $msiPath; version = [string]$script:PS5HSOfflineWslMsiVersion }) -ActionRunner $ActionRunner
    $wslRestartNeeded = $msiResult -and ($msiResult.requiresRestart -or [int]$msiResult.exitCode -eq 3010)
    if (!$ActionRunner -and !$wslRestartNeeded -and (Get-PS5HSOfflineHostSnapshot).pendingRestart) { $wslRestartNeeded = $true }
    if ($wslRestartNeeded) {
      $state.stage = 'restart-required'; $state.updatedUtc = [DateTime]::UtcNow.ToString('o')
      [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
      return [pscustomobject]@{ status = 'restart-required'; statePath = $statePath; message = 'Reinicia Windows y vuelve a ejecutar INSTALL-OFFLINE.bat para continuar.' }
    }
  }

  if (!$preflight.existingDistro) {
    if (!(Test-Path -LiteralPath $preflight.installRoot)) { New-Item -ItemType Directory -Path $preflight.installRoot -Force | Out-Null }
    Invoke-PS5HSOfflineOperation -Name 'ImportDistro' -Arguments ([pscustomobject]@{ name = $preflight.distroName; installRoot = $preflight.installRoot; imagePath = $imagePath }) -ActionRunner $ActionRunner | Out-Null
  }
  Invoke-PS5HSOfflineOperation -Name 'VerifyDistro' -Arguments ([pscustomobject]@{ name = $preflight.distroName }) -ActionRunner $ActionRunner | Out-Null
  $state.stage = 'complete'; $state.updatedUtc = [DateTime]::UtcNow.ToString('o'); $state.imageSha256 = $preflight.bundle.imageSha256
  [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
  return [pscustomobject]@{ status = 'installed'; distroName = $preflight.distroName; installRoot = $preflight.installRoot; statePath = $statePath; imageSha256 = $preflight.bundle.imageSha256 }
}

Export-ModuleMember -Function Get-PS5HSOfflineHostPreflight, Install-PS5HSOfflineEnvironment
