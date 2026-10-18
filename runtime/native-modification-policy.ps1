# PS5 Homebrew Studio: explicit permission and audit of native source mutations.
$script:PS5HSNativeModificationKeys = @(
  'allowExecuteUpstreamGenerationTools',
  'allowExecuteUpstreamBuildTools',
  'allowOpenGlTemplateIntegration',
  'allowOpenGlRuntimeProfile',
  'allowOpenGlEuropeanAtlas',
  'allowWindowsBuildEntrypointPatch',
  'allowVulkanTemplateIntegration',
  'allowVulkanBuildHelperRestore',
  'normalizeBuildFiles',
  'allowCustomUnicodeFont'
)
function NormalizePS5HSNativeModificationPolicy($Value) {
  $result = @{}
  foreach ($key in $script:PS5HSNativeModificationKeys) { $result[$key] = $false }
  if ($null -eq $Value) { return $result }
  foreach ($key in $script:PS5HSNativeModificationKeys) {
    $property = $Value.PSObject.Properties[$key]
    if ($property -and $property.Value -is [bool] -and $property.Value) { $result[$key] = $true }
    elseif ($Value -is [System.Collections.IDictionary] -and $Value.Contains($key) -and $Value[$key] -is [bool] -and $Value[$key]) { $result[$key] = $true }
  }
  return $result
}
function GetPS5HSNativeModificationConsentGaps {
  param(
    [Parameter(Mandatory=$true)][string]$Backend,
    $Policy,
    [bool]$RequireGeneration = $false,
    [bool]$RequireBuildTools = $false,
    [bool]$RequireVisualIntegration = $false,
    [bool]$HasCustomFont = $false,
    [string[]]$RequirePermissionKeys = @()
  )
  $approved = NormalizePS5HSNativeModificationPolicy $Policy
  $required = [System.Collections.Generic.List[string]]::new()
  if ($RequireGeneration) { $required.Add('allowExecuteUpstreamGenerationTools') }
  if ($RequireBuildTools) { $required.Add('allowExecuteUpstreamBuildTools') }
  if ($RequireVisualIntegration) {
    $integrationKey = if ($Backend -eq 'opengl-ui') { 'allowOpenGlTemplateIntegration' } elseif ($Backend -eq 'vulkan-ui') { 'allowVulkanTemplateIntegration' } else { '' }
    if ($integrationKey) { $required.Add($integrationKey) }
  }
  if ($HasCustomFont) { $required.Add('allowCustomUnicodeFont') }
  foreach ($key in @($RequirePermissionKeys)) {
    if ($key -notin $script:PS5HSNativeModificationKeys) {
      throw ("Se ha solicitado un permiso de modificación no registrado: " + [string]$key)
    }
    $required.Add([string]$key)
  }
  $required = @($required | Select-Object -Unique)
  return @($required | Where-Object { !$approved[$_] })
}
function AssertPS5HSNativeModificationConsent {
  param(
    [Parameter(Mandatory=$true)][string]$Backend,
    $Policy,
    [bool]$RequireGeneration = $false,
    [bool]$RequireBuildTools = $false,
    [bool]$RequireVisualIntegration = $false,
    [bool]$HasCustomFont = $false,
    [string[]]$RequirePermissionKeys = @()
  )
  $approved = NormalizePS5HSNativeModificationPolicy $Policy
  $gaps = @(GetPS5HSNativeModificationConsentGaps -Backend $Backend -Policy $approved -RequireGeneration $RequireGeneration -RequireBuildTools $RequireBuildTools -RequireVisualIntegration $RequireVisualIntegration -HasCustomFont $HasCustomFont -RequirePermissionKeys $RequirePermissionKeys)
  if ($gaps.Count -gt 0) {
    throw ('Operación detenida antes de modificar fuentes o ejecutar herramientas. Falta consentimiento explícito para: ' + ($gaps -join ', ') + '. No se han aplicado esas modificaciones.')
  }
  return $approved
}
function GetPS5HSNativeFileHashes {
  param([Parameter(Mandatory=$true)][string]$ProjectRoot,[Parameter(Mandatory=$true)][string[]]$RelativePaths)
  $result = @{}
  $root = [IO.Path]::GetFullPath($ProjectRoot)
  foreach ($relative in $RelativePaths) {
    $path = Join-Path $root ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      try { $result[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
      catch { $result[$relative] = 'hash-error: ' + $_.Exception.Message }
    } else { $result[$relative] = $null }
  }
  return $result
}
function AddPS5HSNativeModificationRecord {
  param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Backend,
    [Parameter(Mandatory=$true)][string]$Operation,
    [Parameter(Mandatory=$true)][string]$PermissionKey,
    [Parameter(Mandatory=$true)][string[]]$RelativePaths,
    [Parameter(Mandatory=$true)]$BeforeHashes,
    $Policy,
    [string]$SourceRepository = '',
    [string]$SourceCommit = ''
  )
  $approved = NormalizePS5HSNativeModificationPolicy $Policy
  if (!$approved[$PermissionKey]) { throw "Control interno: la modificación '$Operation' no tiene consentimiento registrado." }
  $after = GetPS5HSNativeFileHashes -ProjectRoot $ProjectRoot -RelativePaths $RelativePaths
  $pathRecords = @()
  foreach ($relative in $RelativePaths) {
    $beforeValue = $null
    if ($BeforeHashes -and $BeforeHashes.ContainsKey($relative)) { $beforeValue = $BeforeHashes[$relative] }
    $afterValue = $after[$relative]
    if ($beforeValue -cne $afterValue) {
      $pathRecords += [ordered]@{path=$relative;originalSha256=$beforeValue;resultSha256=$afterValue}
    }
  }
  $manifestPath = Join-Path $ProjectRoot '.ps5hs-modifications.json'
  $manifest = [ordered]@{schema='ps5hs-native-modifications';version=1;project=$ProjectRoot;records=@()}
  if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
      $existing = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
      if ($existing.schema -ne 'ps5hs-native-modifications' -or [int]$existing.version -ne 1) {
        throw 'El esquema o la versión del manifiesto no son compatibles.'
      }
      if ($existing.records) { $manifest.records = @($existing.records) }
    } catch { throw 'El manifiesto de modificaciones existe pero no es válido o compatible; no se sobrescribirá.' }
  }
  $manifest.records = @($manifest.records) + @([ordered]@{
    at=(Get-Date).ToString('o')
    backend=$Backend
    operation=$Operation
    permission=$PermissionKey
    consented=$true
    upstreamRepository=$SourceRepository
    upstreamCommit=$SourceCommit
    changedFiles=@($pathRecords)
    policy=$approved
  })
  $text = (ConvertTo-Json -InputObject $manifest -Depth 20) + [Environment]::NewLine
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($manifestPath))) | Out-Null
  [IO.File]::WriteAllText($manifestPath,$text,[System.Text.UTF8Encoding]::new($false))
  return @{manifest='.ps5hs-modifications.json';operation=$Operation;files=@($pathRecords)}
}


function AssertPS5HSNativeModificationManifestWritable {
  param([Parameter(Mandatory=$true)][string]$ProjectRoot)
  $root = [IO.Path]::GetFullPath($ProjectRoot)
  $manifestPath = Join-Path $root '.ps5hs-modifications.json'
  if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
      $existing = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
      if ($existing.schema -ne 'ps5hs-native-modifications' -or [int]$existing.version -ne 1) {
        throw 'Esquema/versión incompatibles.'
      }
    } catch { throw 'El manifiesto .ps5hs-modifications.json existe pero no es válido; la operación se detiene antes de tocar las fuentes.' }
    $stream = $null
    try {
      $stream = [IO.File]::Open($manifestPath,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
    } catch {
      throw 'El manifiesto de auditoría existe, pero no se puede escribir. No se modificará ningún archivo fuente.'
    } finally {
      if ($stream) { $stream.Dispose() }
    }
  } else {
    $probeRoot = $root
    if (!(Test-Path -LiteralPath $probeRoot -PathType Container)) {
      $probeRoot = [IO.Path]::GetDirectoryName($root)
    }
    if ([string]::IsNullOrWhiteSpace($probeRoot) -or !(Test-Path -LiteralPath $probeRoot -PathType Container)) {
      throw 'No existe una carpeta accesible donde preparar el registro de auditoría.'
    }
    $probePath = Join-Path $probeRoot ('.ps5hs-audit-probe-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
      [IO.File]::WriteAllText($probePath,'PS5 Homebrew Studio audit preflight',[System.Text.UTF8Encoding]::new($false))
    } catch {
      throw 'La carpeta del proyecto no permite crear el registro de auditoría. No se modificará ningún archivo fuente.'
    } finally {
      if (Test-Path -LiteralPath $probePath -PathType Leaf) {
        Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
      }
    }
  }
  return $true
}

function GetPS5HSNativeTreeHashes {
  param([Parameter(Mandatory=$true)][string]$ProjectRoot)
  $root = [IO.Path]::GetFullPath($ProjectRoot)
  $hashes = @{}
  if (!(Test-Path -LiteralPath $root -PathType Container)) { return $hashes }
  foreach ($item in (Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction Stop)) {
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
    $relative = $item.FullName.Substring($root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    # For an upstream generator audit, every project file is relevant. Ignore only Git internals and the audit manifest itself.
    if ($relative -match '(^|[\\/])\.git([\\/]|$)' -or $relative -ieq '.ps5hs-modifications.json') { continue }
    $relative = $relative.Replace([IO.Path]::DirectorySeparatorChar,'/').Replace([IO.Path]::AltDirectorySeparatorChar,'/')
    $hashes[$relative] = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  return $hashes
}

function InvokePS5HSNativeTreeModificationWithAudit {
  param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Backend,
    [Parameter(Mandatory=$true)][string]$Operation,
    [Parameter(Mandatory=$true)][string]$PermissionKey,
    [Parameter(Mandatory=$true)]$Policy,
    [Parameter(Mandatory=$true)][scriptblock]$Action,
    [string]$SourceRepository = ''
  )
  $approved = AssertPS5HSNativeModificationConsent -Backend $Backend -Policy $Policy -RequirePermissionKeys @($PermissionKey)
  $null = AssertPS5HSNativeModificationManifestWritable -ProjectRoot $ProjectRoot
  $before = GetPS5HSNativeTreeHashes -ProjectRoot $ProjectRoot
  $result = $null
  try {
    $result = & $Action
  } finally {
    if (Test-Path -LiteralPath $ProjectRoot -PathType Container) {
      $after = GetPS5HSNativeTreeHashes -ProjectRoot $ProjectRoot
      $allPaths = @(@($before.Keys) + @($after.Keys) | Select-Object -Unique)
      $changed = @($allPaths | Where-Object { $before[$_] -cne $after[$_] })
      if ($changed.Count -gt 0) {
        $null = AddPS5HSNativeModificationRecord -ProjectRoot $ProjectRoot -Backend $Backend -Operation $Operation -PermissionKey $PermissionKey -RelativePaths $changed -BeforeHashes $before -Policy $approved -SourceRepository $SourceRepository
      }
    }
  }
  return $result
}

function InvokePS5HSNativeModificationWithAudit {
  param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Backend,
    [Parameter(Mandatory=$true)][string]$Operation,
    [Parameter(Mandatory=$true)][string]$PermissionKey,
    [Parameter(Mandatory=$true)][string[]]$RelativePaths,
    [Parameter(Mandatory=$true)]$Policy,
    [Parameter(Mandatory=$true)][scriptblock]$Action,
    [string]$SourceRepository = ''
  )
  $approved = AssertPS5HSNativeModificationConsent -Backend $Backend -Policy $Policy -RequirePermissionKeys @($PermissionKey)
  $null = AssertPS5HSNativeModificationManifestWritable -ProjectRoot $ProjectRoot
  $before = GetPS5HSNativeFileHashes -ProjectRoot $ProjectRoot -RelativePaths $RelativePaths
  $result = $null
  try {
    $result = & $Action
  } finally {
    $after = GetPS5HSNativeFileHashes -ProjectRoot $ProjectRoot -RelativePaths $RelativePaths
    $changed = @($RelativePaths | Where-Object { $before[$_] -cne $after[$_] })
    if ($changed.Count -gt 0) {
      $null = AddPS5HSNativeModificationRecord -ProjectRoot $ProjectRoot -Backend $Backend -Operation $Operation -PermissionKey $PermissionKey -RelativePaths $changed -BeforeHashes $before -Policy $approved -SourceRepository $SourceRepository
    }
  }
  return $result
}

function ApplyPS5HSWindowsBuildEntrypointPatch {
  param([Parameter(Mandatory=$true)][string]$ProjectRoot,$Policy,[string]$Backend='nativecpp',[string]$SourceRepository='',[string]$SourceCommit='')
  $approved = NormalizePS5HSNativeModificationPolicy $Policy
  if (!$approved.allowWindowsBuildEntrypointPatch) { return @{ok=$true;changed=$false;skipped=$true;files=@()} }
  $null = AssertPS5HSNativeModificationManifestWritable -ProjectRoot $ProjectRoot
  $path = Join-Path $ProjectRoot 'build.ps1'
  if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Se autorizó el parche de build.ps1, pero el proyecto no contiene ese archivo.' }
  $original = [IO.File]::ReadAllText($path)
  $updated = $original
  $envPattern = '(?m)^(\s*)"APP_STATIC_ARCHIVES",\r?\n\s*"APP_RUNTIME_MODULES",\s*$'
  $envReplacement = '$1"APP_STATIC_ARCHIVES",' + [Environment]::NewLine + '        "APP_IMPORT_STUBS",' + [Environment]::NewLine + '        "APP_RUNTIME_MODULES",' + [Environment]::NewLine + '        "PS5_OPENGL_PREFIX",' + [Environment]::NewLine + '        "BUILD_JOBS",' + [Environment]::NewLine + '        "USE_CCACHE",'
  if ([regex]::IsMatch($updated,$envPattern)) {
    $updated = [regex]::Replace($updated,$envPattern,$envReplacement,1)
  } elseif ($updated -notmatch '(?s)"APP_IMPORT_STUBS".*"PS5_OPENGL_PREFIX".*"BUILD_JOBS".*"USE_CCACHE"') {
    throw 'No se reconoce el bloque de variables de build.ps1. Se detiene sin modificar la plantilla.'
  }
  $legacyBuildCall = '$arguments += @("bash", (Convert-ToWslPath $build))'
  $makeBuildCall = '$arguments += @("make", "-C", (Convert-ToWslPath (Split-Path -Parent $MyInvocation.MyCommand.Path)), "app")'
  if ($updated.Contains($legacyBuildCall)) {
    $updated = $updated.Replace($legacyBuildCall,$makeBuildCall)
  } elseif (!$updated.Contains($makeBuildCall)) {
    throw 'No se reconoce el punto de invocación del build de build.ps1. Se detiene sin modificar la plantilla.'
  }
  if ($updated -cne $original) {
    $before = GetPS5HSNativeFileHashes -ProjectRoot $ProjectRoot -RelativePaths @('build.ps1')
    WriteUtf8 $path $updated
    $record = AddPS5HSNativeModificationRecord -ProjectRoot $ProjectRoot -Backend $Backend -Operation 'adapt-build-ps1-to-make-app' -PermissionKey 'allowWindowsBuildEntrypointPatch' -RelativePaths @('build.ps1') -BeforeHashes $before -Policy $approved -SourceRepository $SourceRepository -SourceCommit $SourceCommit
    if ($script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath 'Modificación autorizada y auditada: build.ps1 ahora invoca el target Makefile app.' }
    return @{ok=$true;changed=$true;files=@('build.ps1');audit=$record}
  }
  return @{ok=$true;changed=$false;files=@()}
}

function NormalizeNativeBuildFilesWithAudit {
  param([Parameter(Mandatory=$true)][string]$ProjectRoot,$Policy,[string]$Backend,[string]$SourceRepository='', [string]$SourceCommit='')
  $approved = NormalizePS5HSNativeModificationPolicy $Policy
  if (!$approved.normalizeBuildFiles) {
    if ($script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath 'Normalización omitida por política: no se han cambiado finales de línea de archivos fuente.' }
    return @{count=0;changedFiles=@();skipped=$true}
  }
  $null = AssertPS5HSNativeModificationManifestWritable -ProjectRoot $ProjectRoot
  $root = [IO.Path]::GetFullPath($ProjectRoot)
  $allowedExtensions = @('.sh','.sha256','.c','.cc','.cpp','.h','.hpp','.ld','.mk','.s','.cmake','.yml','.yaml')
  $allowedNames = @('Makefile','GNUmakefile','CMakeLists.txt','.gitattributes')
  $relativePaths = @()
  foreach ($item in (Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction Stop)) {
    $relative = $item.FullName.Substring($root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if ($relative -match '(^|[\\/])(\.git|\.deps|\.cache|build|dist|out|obj|node_modules|\.runtime)([\\/]|$)') { continue }
    if ($item.Name -notin $allowedNames -and $item.Extension.ToLowerInvariant() -notin $allowedExtensions) { continue }
    $relativePaths += $relative.Replace([IO.Path]::DirectorySeparatorChar,'/').Replace([IO.Path]::AltDirectorySeparatorChar,'/')
  }
  $relativePaths = @($relativePaths | Select-Object -Unique)
  if ($relativePaths.Count -eq 0) { return @{count=0;changedFiles=@();skipped=$false} }
  $before = GetPS5HSNativeFileHashes -ProjectRoot $root -RelativePaths $relativePaths
  $count = 0
  $normalizationError = ''
  try { $count = NormalizeNativeBuildFiles $root }
  catch { $normalizationError = $_.Exception.Message }
  # The normalizer writes files one by one. Always compare and log partial changes
  # even when a later file fails, then surface the original failure.
  $after = GetPS5HSNativeFileHashes -ProjectRoot $root -RelativePaths $relativePaths
  $changed = @($relativePaths | Where-Object { $before[$_] -cne $after[$_] })
  if ($changed.Count -gt 0) {
    $record = AddPS5HSNativeModificationRecord -ProjectRoot $root -Backend $Backend -Operation 'normalize-build-file-line-endings' -PermissionKey 'normalizeBuildFiles' -RelativePaths $changed -BeforeHashes $before -Policy $approved -SourceRepository $SourceRepository -SourceCommit $SourceCommit
    if ($script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath ("Normalización consentida y auditada: $count archivos; registro $($record.manifest).") }
  }
  if ($normalizationError) {
    throw ("La normalización no se completó. Los cambios parciales se han comparado y auditado cuando fue posible. Error original: " + $normalizationError)
  }
  return @{count=$count;changedFiles=@($changed);skipped=$false}
}

