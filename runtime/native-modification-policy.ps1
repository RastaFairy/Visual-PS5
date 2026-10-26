# PS5 Homebrew Studio: explicit permission and audit of native source mutations.
# Build-log sink: server.ps1 asigna la ruta del log activo al iniciar un job de build.
# Los hosts que dot-sourcean este archivo sin server.ps1 (p. ej. la suite de tests con
# Set-StrictMode) no la definen; se inicializa de forma defensiva para que quede asignada.
if ($null -eq (Get-Variable -Name ActiveBuildLogPath -Scope Script -ErrorAction SilentlyContinue)) { $script:ActiveBuildLogPath = $null }
$script:PS5HSNativeModificationKeys = @(
  'allowExecuteUpstreamGenerationTools',
  'allowExecuteUpstreamBuildTools',
  'allowPayloadProjectIntegration',
  'allowPs5LinkProjectIntegration',
  'allowExecuteUpstreamAssetTools',
  'allowSharpTemplateIntegration',
  'allowOpenGlTemplateIntegration',
  'allowOpenGlRuntimeProfile',
  'allowOpenGlEuropeanAtlas',
  'allowWindowsBuildEntrypointPatch',
  'allowVulkanTemplateIntegration',
  'allowVulkanComputeShaderBuild',
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

function TestPS5HSNativeProjectDestinationAvailable {
  param([Parameter(Mandatory=$true)][string]$Path)
  try { $fullPath = [IO.Path]::GetFullPath($Path) } catch { return $false }
  $parent = [IO.Path]::GetDirectoryName($fullPath)
  $leaf = [IO.Path]::GetFileName($fullPath)
  if ([string]::IsNullOrWhiteSpace($parent) -or [string]::IsNullOrWhiteSpace($leaf)) { return $false }
  if (!(Test-Path -LiteralPath $parent -PathType Container)) { return $true }
  try {
    $null = AssertPS5HSNativePathNoReparsePoints -Path $parent
    $entry = Get-ChildItem -LiteralPath $parent -Force -ErrorAction Stop |
      Where-Object { $_.Name -ieq $leaf } | Select-Object -First 1
  } catch { return $false }
  if ($null -eq $entry) { return $true }
  if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or !$entry.PSIsContainer) { return $false }
  try {
    $child = Get-ChildItem -LiteralPath $entry.FullName -Force -ErrorAction Stop | Select-Object -First 1
  } catch { return $false }
  return ($null -eq $child)
}

function GetPS5HSNativeReparsePointData {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (!('PS5HS.NativeReparsePointReader' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace PS5HS {
  public static class NativeReparsePointReader {
    private const uint FILE_READ_ATTRIBUTES = 0x00000080;
    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_WRITE = 0x00000002;
    private const uint FILE_SHARE_DELETE = 0x00000004;
    private const uint OPEN_EXISTING = 3;
    private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
    private const uint FSCTL_GET_REPARSE_POINT = 0x000900A8;

    [DllImport("kernel32.dll", EntryPoint="CreateFileW", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security,
      uint creation, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool DeviceIoControl(SafeFileHandle handle, uint controlCode, IntPtr input,
      uint inputSize, [Out] byte[] output, uint outputSize, out uint bytesReturned, IntPtr overlapped);

    public static byte[] Read(string path) {
      using (SafeFileHandle handle = CreateFile(path, FILE_READ_ATTRIBUTES,
          FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, IntPtr.Zero, OPEN_EXISTING,
          FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, IntPtr.Zero)) {
        if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFile failed for reparse point metadata.");
        byte[] buffer = new byte[16 * 1024];
        uint returned;
        if (!DeviceIoControl(handle, FSCTL_GET_REPARSE_POINT, IntPtr.Zero, 0, buffer,
            (uint)buffer.Length, out returned, IntPtr.Zero)) {
          throw new Win32Exception(Marshal.GetLastWin32Error(), "FSCTL_GET_REPARSE_POINT failed.");
        }
        if (returned < 8 || returned > buffer.Length) throw new InvalidDataException("Invalid reparse point metadata length.");
        byte[] result = new byte[(int)returned];
        Buffer.BlockCopy(buffer, 0, result, 0, (int)returned);
        return result;
      }
    }
  }
}
'@
  }
  return [PS5HS.NativeReparsePointReader]::Read($Path)
}

function GetPS5HSNativeReparsePointFingerprint {
  param([Parameter(Mandatory=$true)][byte[]]$ReparseData)
  if ($ReparseData.Length -lt 8) { throw 'Los metadatos del enlace están incompletos.' }
  $tag = [BitConverter]::ToUInt32($ReparseData,0)
  $dataLength = [BitConverter]::ToUInt16($ReparseData,4)
  if ($ReparseData.Length -ne (8 + [int]$dataLength)) { throw 'La longitud de los metadatos del enlace no es válida.' }
  $symlinkTag = [Convert]::ToUInt32('A000000C',16)
  $lxSymlinkTag = [Convert]::ToUInt32('A000001D',16)
  if ($tag -ne $symlinkTag -and $tag -ne $lxSymlinkTag) {
    throw ('Tipo de punto de reanálisis no permitido para un enlace simbólico: 0x' + $tag.ToString('X8'))
  }
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha.ComputeHash($ReparseData))).Replace('-','').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function GetPS5HSNativeGeneratedDependencyLinkFingerprint {
  param(
    [Parameter(Mandatory=$true)]$LinkItem,
    [byte[]]$ReparseData
  )
  if (($LinkItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
    throw 'El enlace generado esperado no es un punto de reanálisis.'
  }
  if ($null -eq $ReparseData) {
    if ([string]::IsNullOrWhiteSpace([string]$LinkItem.FullName)) {
      throw 'No se pudo identificar la ruta del enlace generado.'
    }
    $ReparseData = GetPS5HSNativeReparsePointData -Path $LinkItem.FullName
  }
  return GetPS5HSNativeReparsePointFingerprint -ReparseData $ReparseData
}

function GetPS5HSPayloadSdkIncludeLinkFingerprint {
  param(
    [Parameter(Mandatory=$true)]$LinkItem,
    [byte[]]$ReparseData
  )
  if (($LinkItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
    throw 'target/include_common no es el enlace simbólico esperado del SDK.'
  }
  if ($null -eq $ReparseData) {
    $ReparseData = GetPS5HSNativeReparsePointData -Path $LinkItem.FullName
  }
  $fingerprint = GetPS5HSNativeReparsePointFingerprint -ReparseData $ReparseData
  $lxSymlinkTag = [Convert]::ToUInt32('A000001D',16)
  if ([BitConverter]::ToUInt32($ReparseData,0) -ne $lxSymlinkTag -or $ReparseData.Length -lt 12) {
    throw 'target/include_common no usa un enlace simbólico WSL válido.'
  }
  $isRelative = [BitConverter]::ToUInt32($ReparseData,8) -eq 2
  $target = [Text.Encoding]::UTF8.GetString($ReparseData,12,$ReparseData.Length - 12)
  if (!$isRelative -or $target -cne 'user/homebrew/include') {
    throw 'target/include_common no apunta al include interno esperado del SDK.'
  }
  return $fingerprint
}

function GetPS5HSNativeTreeReparsePointHash {
  param(
    [Parameter(Mandatory=$true)][string]$RelativePath,
    [Parameter(Mandatory=$true)]$LinkItem,
    [Parameter(Mandatory=$true)][ValidateSet('file','directory')][string]$EntryKind,
    [byte[]]$ReparseData
  )
  if ($RelativePath -ieq '.deps/ps5-opengl/current') {
    return GetPS5HSNativeGeneratedDependencyLinkFingerprint -LinkItem $LinkItem -ReparseData $ReparseData
  }
  if ($RelativePath -ieq '.deps/native/ps5-payload-sdk/target/include_common') {
    # WSL creates this SDK include alias. Hash only its reparse metadata; never traverse its target.
    return GetPS5HSPayloadSdkIncludeLinkFingerprint -LinkItem $LinkItem -ReparseData $ReparseData
  }
  if ($EntryKind -eq 'directory') {
    throw ('Se ha encontrado una carpeta enlazada dentro del árbol nativo; se cancela para evitar escrituras fuera del proyecto: ' + $LinkItem.FullName)
  }
  throw ('Se ha encontrado un archivo enlazado dentro del árbol nativo; se cancela la operación: ' + $LinkItem.FullName)
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
    $linkFingerprint = $null
    foreach ($segment in $segments) {
      $current = Join-Path $current $segment
      if (Test-Path -LiteralPath $current) {
        $currentItem = Get-Item -LiteralPath $current -Force
        if (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          if ($relative -ieq '.deps/ps5-opengl/current' -and $current -ieq $path) {
            $linkFingerprint = GetPS5HSNativeGeneratedDependencyLinkFingerprint -LinkItem $currentItem
            break
          }
          if ($relative -ieq '.deps/native/ps5-payload-sdk/target/include_common' -and $current -ieq $path) {
            $linkFingerprint = GetPS5HSPayloadSdkIncludeLinkFingerprint -LinkItem $currentItem
            break
          }
          throw "No se modificará ni auditará una ruta a través de un enlace: $relative"
        }
      } else { break }
    }
    if ($null -ne $linkFingerprint) {
      $result[$relative] = $linkFingerprint
      continue
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
    # A new project path may not exist yet. Probe the nearest existing ancestor,
    # not only its immediate parent; the generator creates the project tree afterwards.
    $probeRoot = $root
    while (![string]::IsNullOrWhiteSpace($probeRoot) -and !(Test-Path -LiteralPath $probeRoot -PathType Container)) {
      $parent = [IO.Directory]::GetParent($probeRoot)
      if ($null -eq $parent) { $probeRoot = ''; break }
      $probeRoot = $parent.FullName
    }
    if ([string]::IsNullOrWhiteSpace($probeRoot) -or !(Test-Path -LiteralPath $probeRoot -PathType Container)) {
      throw ('No existe una carpeta accesible donde preparar el registro de auditoría. Ruta solicitada: ' + $root)
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
      $relativeDirectory = $subdirectory.Substring($root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
      $relativeDirectory = $relativeDirectory.Replace([IO.Path]::DirectorySeparatorChar,'/').Replace([IO.Path]::AltDirectorySeparatorChar,'/')
      if (($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        # The generated SDK alias may be returned as a directory or file entry
        # depending on the reparse tag. Hash its metadata, never its target.
        $hashes[$relativeDirectory] = GetPS5HSNativeTreeReparsePointHash -RelativePath $relativeDirectory -LinkItem $directoryItem -EntryKind 'directory'
        continue
      }
      if ($directoryName -in $excludedDirectoryNames -or $directoryName -match '^out-[A-Za-z0-9-]+$') { continue }
      $pending.Push($subdirectory)
    }
    foreach ($filePath in [IO.Directory]::EnumerateFiles($directory)) {
      $item = Get-Item -LiteralPath $filePath -Force
      $relative = $item.FullName.Substring($root.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar).Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
      $relative = $relative.Replace([IO.Path]::DirectorySeparatorChar,'/').Replace([IO.Path]::AltDirectorySeparatorChar,'/')
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $hashes[$relative] = GetPS5HSNativeTreeReparsePointHash -RelativePath $relative -LinkItem $item -EntryKind 'file'
        continue
      }
      if ($item.Name -ieq '.ps5hs-modifications.json') { continue }
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
