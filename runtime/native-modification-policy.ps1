# PS5 Homebrew Studio: explicit permission and audit of native source mutations.
# Build-log sink: server.ps1 asigna la ruta del log activo al iniciar un job de build.
# Los hosts que dot-sourcean este archivo sin server.ps1 (p. ej. la suite de tests con
# Set-StrictMode) no la definen; se inicializa de forma defensiva para que quede asignada.
if ($null -eq (Get-Variable -Name ActiveBuildLogPath -Scope Script -ErrorAction SilentlyContinue)) { $script:ActiveBuildLogPath = $null }
$script:PS5HSNativeModificationKeys = @(
  'allowExecuteUpstreamGenerationTools',
  'allowExecuteUpstreamBuildTools',
  'allowExecuteUpstreamAssetTools',
  'allowSharpTemplateIntegration',
  'allowOpenGlTemplateIntegration',
  'allowOpenGlRuntimeProfile',
  'allowOpenGlEuropeanAtlas',
  'allowWindowsBuildEntrypointPatch',
  'allowUpstreamSdkMirrorPatch',
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
function AssertPS5HSNativePathNoReparsePoints {
  param([Parameter(Mandatory=$true)][string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Ruta vacía en la comprobación de enlaces.' }
  try { $fullPath = [IO.Path]::GetFullPath($Path) } catch { throw ('Ruta no válida en la comprobación de enlaces: ' + $Path) }
  $volumeRoot = [IO.Path]::GetPathRoot($fullPath)
  if ([string]::IsNullOrWhiteSpace($volumeRoot)) { throw ('No se pudo resolver la raíz de la ruta: ' + $fullPath) }
  $current = $volumeRoot
  $segments = @($fullPath.Substring($volumeRoot.Length) -split '[\\/]' | Where-Object { $_ })
  foreach ($segment in $segments) {
    $current = Join-Path $current $segment
    if (!(Test-Path -LiteralPath $current)) { break }
    $item = Get-Item -LiteralPath $current -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw ("No se seguirá una ruta que atraviesa un enlace o punto de reanálisis: " + $current)
    }
  }
  return $fullPath
}

function GetPS5HSNativeFileHashes {
  param([Parameter(Mandatory=$true)][string]$ProjectRoot,[Parameter(Mandatory=$true)][string[]]$RelativePaths)
  $result = @{}
  $root = AssertPS5HSNativePathNoReparsePoints -Path $ProjectRoot
  if (Test-Path -LiteralPath $root -PathType Container) {
    $rootItem = Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "No se auditará un proyecto situado en una carpeta enlazada: $root"
    }
  }
  foreach ($relative in $RelativePaths) {
    if ([IO.Path]::IsPathRooted([string]$relative) -or @(([string]$relative -split '[\\/]') | Where-Object { $_ -eq '..' }).Count -gt 0) {
      throw "Ruta relativa de auditoría no segura: $relative"
    }
    $path = Join-Path $root ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
    $current = $root
    $segments = @(([string]$relative -split '[\\/]') | Where-Object { $_ -and $_ -ne '.' })
    foreach ($segment in $segments) {
      $current = Join-Path $current $segment
      if (Test-Path -LiteralPath $current) {
        $currentItem = Get-Item -LiteralPath $current -Force
        if (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          throw "No se modificará ni auditará una ruta a través de un enlace: $relative"
        }
      } else { break }
    }
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $item = Get-Item -LiteralPath $path -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "No se modificará ni auditará un archivo enlazado: $relative"
      }
      $result[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
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
  $root = AssertPS5HSNativePathNoReparsePoints -Path $ProjectRoot
  $manifestPath = Join-Path $root '.ps5hs-modifications.json'
  $null = AssertPS5HSNativePathNoReparsePoints -Path $manifestPath
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
  $root = AssertPS5HSNativePathNoReparsePoints -Path $ProjectRoot
  $hashes = @{}
  if (!(Test-Path -LiteralPath $root -PathType Container)) { return $hashes }
  $pending = [System.Collections.Generic.Stack[string]]::new()
  $pending.Push($root)
  $excludedDirectoryNames = @('.git','.cache','.runtime','build','dist','out','bin','obj','node_modules','__pycache__','.venv')
  while ($pending.Count -gt 0) {
    $directory = $pending.Pop()
    foreach ($subdirectory in [IO.Directory]::EnumerateDirectories($directory)) {
      $directoryName = [IO.Path]::GetFileName($subdirectory)
      $directoryItem = Get-Item -LiteralPath $subdirectory -Force
      if (($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw ("Se ha encontrado una carpeta enlazada dentro del árbol nativo; se cancela para evitar escrituras fuera del proyecto: " + $subdirectory)
      }
      if ($directoryName -in $excludedDirectoryNames -or $directoryName -match '^out-[A-Za-z0-9-]+$') { continue }
      $pending.Push($subdirectory)
    }
    foreach ($filePath in [IO.Directory]::EnumerateFiles($directory)) {
      $item = Get-Item -LiteralPath $filePath -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw ("Se ha encontrado un archivo enlazado dentro del árbol nativo; se cancela la operación: " + $filePath)
      }
      if ($item.Name -ieq '.ps5hs-modifications.json') { continue }
      $relative = $item.FullName.Substring($root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
      $relative = $relative.Replace([IO.Path]::DirectorySeparatorChar,'/').Replace([IO.Path]::AltDirectorySeparatorChar,'/')
      $hashes[$relative] = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
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
  $path = Join-Path $ProjectRoot 'build.ps1'
  if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
    if ($script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath 'Parche opcional de build.ps1 omitido: la plantilla no contiene ese archivo; no se ha modificado ningún archivo.' }
    return @{ok=$true;changed=$false;skipped=$true;reason='build.ps1 no existe';files=@()}
  }
  $null = AssertPS5HSNativeModificationManifestWritable -ProjectRoot $ProjectRoot
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

function ApplyPS5HSSdkMirrorChainPatch {
  param(
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    $Policy,
    [string]$Backend='opengl-ui',
    [string]$SourceRepository='',
    [string[]]$MirrorUrls=@()
  )
  $approved = NormalizePS5HSNativeModificationPolicy $Policy
  if (!$approved.allowUpstreamSdkMirrorPatch) {
    if ($script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath 'Cadena de mirrors del SDK OpenGL omitida por política: si el upstream sigue caído, tools/fetch-opengl-sdk.sh devolvera 404 y el build se detendra sin modificar fuentes.' }
    return @{ok=$true;changed=$false;skipped=$true;files=@()}
  }
  $path = Join-Path $ProjectRoot 'tools/fetch-opengl-sdk.sh'
  if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
    if ($script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath 'Parche de mirrors del SDK omitido: el proyecto no contiene tools/fetch-opengl-sdk.sh.' }
    return @{ok=$true;changed=$false;skipped=$true;reason='fetch-opengl-sdk.sh no existe';files=@()}
  }
  $urls = @($MirrorUrls | Where-Object { ![string]::IsNullOrWhiteSpace($_) })
  if ($urls.Count -lt 2) {
    $urls = @(
      'https://github.com/blackbearreloaded/ps5-opengl/releases/download/v1.0.2/ps5-opengl-sdk-1.0.2.tar.gz',
      'https://github.com/LedyBacer/ps5-opengl/releases/download/v1.0.2/ps5-opengl-sdk-1.0.2.tar.gz',
      'https://github.com/darkxex/ps5-opengl/releases/download/v1.0.2/ps5-opengl-sdk-1.0.2.tar.gz'
    )
  }
  $null = AssertPS5HSNativeModificationManifestWritable -ProjectRoot $ProjectRoot
  $original = [IO.File]::ReadAllText($path)
  if ($original.Contains('# PS5HS_MIRROR_CHAIN')) {
    return @{ok=$true;changed=$false;alreadyPatched=$true;files=@()}
  }
  $updated = $original
  $nl = "`n"
  if ($original -match "`r`n") { $nl = "`r`n" }
  $urlPattern = '(?m)^url="https://github\.com/[^/"]+/ps5-opengl/releases/download/v\$version/ps5-opengl-sdk-\$version\.tar\.gz"\s*$'
  $chainLines = @('# PS5HS_MIRROR_CHAIN: upstream primero, mirrors verificados despues. Los pins de integridad no cambian.')
  foreach ($u in $urls) { $chainLines += ('  "' + $u + '"') }
  $chainBlock = 'urls=(' + $nl + (($chainLines) -join $nl) + $nl + ')'
  if ([regex]::IsMatch($updated,$urlPattern)) {
    $urlRegex = [regex]::new($urlPattern)
    $updated = $urlRegex.Replace($updated,{ param($m) $chainBlock },1)
  } elseif ($updated -notmatch '(?m)^urls=\(') {
    throw 'No se reconoce la linea url= del pin del SDK en tools/fetch-opengl-sdk.sh. Se detiene sin modificar la plantilla.'
  }
  $curlPattern = '(?m)^([ \t]*)curl -fL --retry 3 -o "\$archive\.part" "\$url"[ \t]*$'
  $curlTemplate = @(
    '@@I@@ok=0',
    '@@I@@for url in "${urls[@]}"; do',
    '@@I@@    rm -f -- "$archive.part"',
    '@@I@@    if curl -fL --retry 3 -o "$archive.part" "$url"; then ok=1; break; fi',
    '@@I@@    printf ''==> [opengl] Mirror no disponible, probando el siguiente: %s\n'' "$url" >&2',
    '@@I@@    rm -f -- "$archive.part"',
    '@@I@@done',
    '@@I@@if [[ $ok -ne 1 ]]; then',
    '@@I@@    echo ''ps5-opengl SDK: todos los mirrors fijados fallaron'' >&2',
    '@@I@@    exit 2',
    '@@I@@fi'
  )
  $curlMatches = [regex]::Matches($updated,$curlPattern)
  if ($curlMatches.Count -eq 1) {
    $indent = $curlMatches[0].Groups[1].Value
    $replacement = (($curlTemplate | ForEach-Object { $_.Replace('@@I@@',$indent) }) -join $nl)
    $curlRegex = [regex]::new($curlPattern)
    $updated = $curlRegex.Replace($updated,{ param($m) $replacement },1)
  } elseif ($updated -notmatch '(?m)^[ \t]*for url in "\$\{urls\[@\]\}"') {
    throw 'No se reconoce la invocacion curl de descarga del SDK en tools/fetch-opengl-sdk.sh. Se detiene sin modificar la plantilla.'
  }
  if ($updated -notmatch 'archive_sha256=' -or $updated -notmatch 'manifest_sha256=') {
    throw 'El script del SDK ya no declara sus pins de integridad; no se aplica la cadena de mirrors sin poder verificar el archivo.'
  }
  if ($updated -cne $original) {
    $relative = 'tools/fetch-opengl-sdk.sh'
    $before = GetPS5HSNativeFileHashes -ProjectRoot $ProjectRoot -RelativePaths @($relative)
    [IO.File]::WriteAllText($path,$updated,(New-Object System.Text.UTF8Encoding($false)))
    $record = AddPS5HSNativeModificationRecord -ProjectRoot $ProjectRoot -Backend $Backend -Operation 'apply-sdk-mirror-chain' -PermissionKey 'allowUpstreamSdkMirrorPatch' -RelativePaths @($relative) -BeforeHashes $before -Policy $approved -SourceRepository $SourceRepository
    if ($script:ActiveBuildLogPath) { WriteBuildJobLog $script:ActiveBuildLogPath ('Modificacion autorizada y auditada: tools/fetch-opengl-sdk.sh usa la cadena de mirrors verificada (' + $urls.Count + ' URLs; pins SHA-256 intactos).') }
    return @{ok=$true;changed=$true;files=@($relative);audit=$record}
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
