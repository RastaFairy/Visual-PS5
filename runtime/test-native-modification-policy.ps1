Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-modification-policy.ps1')

function Assert-Condition([bool]$Condition,[string]$Message) {
  if (!$Condition) { throw $Message }
}

$defaults = NormalizePS5HSNativeModificationPolicy $null
Assert-Condition ($defaults.Count -eq 15) 'La política debe declarar todas las operaciones registradas.'
Assert-Condition (@($defaults.Values | Where-Object { $_ -eq $true }).Count -eq 0) 'Todas las modificaciones deben estar denegadas por defecto.'
Assert-Condition (!$defaults.allowExecuteUpstreamAssetTools) 'La conversión de recursos también debe estar denegada por defecto.'
Assert-Condition (!$defaults.allowPayloadProjectIntegration) 'La integración de código C/C++ y Makefile payload también debe estar denegada por defecto.'
$gaps = @(GetPS5HSNativeModificationConsentGaps -Backend 'opengl-ui' -Policy $null -RequireGeneration $true -RequireBuildTools $true -RequireVisualIntegration $true)
Assert-Condition ($gaps.Count -eq 3) 'OpenGL debe exigir generador, herramientas upstream e integración visual.'
$approved = [pscustomobject]@{
  allowExecuteUpstreamGenerationTools=$true
  allowExecuteUpstreamBuildTools=$true
  allowExecuteUpstreamAssetTools=$false
  allowSharpTemplateIntegration=$false
  allowOpenGlTemplateIntegration=$true
  allowOpenGlRuntimeProfile=$false
  allowOpenGlEuropeanAtlas=$false
  allowWindowsBuildEntrypointPatch=$false
  allowVulkanTemplateIntegration=$false
  allowVulkanComputeShaderBuild=$true
  allowVulkanBuildHelperRestore=$false
  normalizeBuildFiles=$false
  allowCustomUnicodeFont=$false
  unexpectedPermission=$true
}
$normalized = NormalizePS5HSNativeModificationPolicy $approved
$visualGaps = @(GetPS5HSNativeModificationConsentGaps -Backend 'opengl-ui' -Policy $normalized -RequirePermissionKeys @('allowExecuteUpstreamAssetTools','allowCustomUnicodeFont'))
Assert-Condition ($visualGaps.Count -eq 2) 'El preflight visual debe detectar conversión de recursos y TTF sin autorización antes de empezar.'
$visualApproved = NormalizePS5HSNativeModificationPolicy ([pscustomobject]@{allowExecuteUpstreamAssetTools=$true;allowCustomUnicodeFont=$true})
Assert-Condition (@(GetPS5HSNativeModificationConsentGaps -Backend 'opengl-ui' -Policy $visualApproved -RequirePermissionKeys @('allowExecuteUpstreamAssetTools','allowCustomUnicodeFont')).Count -eq 0) 'Las autorizaciones específicas deben desbloquear solo las operaciones señaladas.'
Assert-Condition ($normalized.allowOpenGlTemplateIntegration -and !$normalized.allowOpenGlRuntimeProfile -and $normalized.allowVulkanComputeShaderBuild) 'Solo deben respetarse permisos booleanos explícitos.'
Assert-Condition (!$normalized.ContainsKey('unexpectedPermission')) 'No deben admitirse permisos desconocidos.'
Assert-Condition (@(GetPS5HSNativeModificationConsentGaps -Backend 'vulkan-ui' -Policy $normalized -RequireVisualIntegration $true -HasCustomFont $true).Count -eq 2) 'Vulkan y la fuente TTF deben exigir sus permisos específicos.'
$unknownDenied = $false
try { AssertPS5HSNativeModificationConsent -Backend 'opengl-ui' -Policy $normalized -RequirePermissionKeys @('unknownPermission') | Out-Null } catch { $unknownDenied = $true }
Assert-Condition $unknownDenied 'Un endpoint no debe poder solicitar un permiso que no figure en el catálogo.'
$sharpGaps = @(GetPS5HSNativeModificationConsentGaps -Backend 'sharp' -Policy $null -RequirePermissionKeys @('allowSharpTemplateIntegration','allowExecuteUpstreamBuildTools'))
Assert-Condition ($sharpGaps.Count -eq 2) 'SharpProspero debe exigir consentimiento separado para integrar la plantilla y ejecutar el build.'
$sharpDenied = $false
try {
  AssertPS5HSNativeModificationConsent -Backend 'sharp' -Policy $null -RequirePermissionKeys @('allowSharpTemplateIntegration','allowExecuteUpstreamBuildTools') | Out-Null
} catch { $sharpDenied = $true }
Assert-Condition $sharpDenied 'Una invocación directa de SharpProspero debe fallar cerrada si no recibe permiso de integración y de build.'
$payloadGaps = @(GetPS5HSNativeModificationConsentGaps -Backend 'payload' -Policy $null -RequirePermissionKeys @('allowPayloadProjectIntegration','allowExecuteUpstreamBuildTools'))
Assert-Condition ($payloadGaps.Count -eq 2) 'Un payload debe exigir permiso independiente para escribir el proyecto y ejecutar el SDK.'
$assetGaps = @(GetPS5HSNativeModificationConsentGaps -Backend 'hui-gl' -Policy $null -RequirePermissionKeys @('allowExecuteUpstreamAssetTools'))
Assert-Condition ($assetGaps.Count -eq 1 -and $assetGaps[0] -eq 'allowExecuteUpstreamAssetTools') 'Los cambios de presentación deben exigir el permiso de conversión independiente del build.';
$assetDenied = $false
try {
  AssertPS5HSNativeModificationConsent -Backend 'hui-gl' -Policy $null -RequirePermissionKeys @('allowExecuteUpstreamAssetTools') | Out-Null
} catch { $assetDenied = $true }
Assert-Condition $assetDenied 'La conversión de presentación debe fallar cerrada sin autorización propia.'

$utf8 = [Text.UTF8Encoding]::new($false)
$root = Join-Path ([IO.Path]::GetTempPath()) ('ps5hs-policy-' + [guid]::NewGuid().ToString('N'))
try {
  [IO.Directory]::CreateDirectory((Join-Path $root 'src')) | Out-Null
  $path = Join-Path $root 'src/sample.cpp'
  [IO.File]::WriteAllText($path,'before',$utf8)

  # Consent is validated before invoking any mutation delegate.
  $denied = $false
  try {
    InvokePS5HSNativeModificationWithAudit -ProjectRoot $root -Backend 'opengl-ui' -Operation 'denied-test' -PermissionKey 'allowOpenGlRuntimeProfile' -RelativePaths @('src/sample.cpp') -Policy $null -Action {
      [IO.File]::WriteAllText($path,'must-not-run',$utf8)
    } | Out-Null
  } catch { $denied = $true }
  Assert-Condition $denied 'Una operación sin consentimiento debe rechazarse.'
  Assert-Condition ([IO.File]::ReadAllText($path) -ceq 'before') 'La operación denegada no debe modificar el archivo.'

  # A permitted mutation must record stable before/after SHA-256 hashes.
  $runtimeConsent = [pscustomobject]@{allowOpenGlRuntimeProfile=$true}
  $actionResult = InvokePS5HSNativeModificationWithAudit -ProjectRoot $root -Backend 'opengl-ui' -Operation 'allowed-test' -PermissionKey 'allowOpenGlRuntimeProfile' -RelativePaths @('src/sample.cpp') -Policy $runtimeConsent -Action {
    [IO.File]::WriteAllText($path,'after',$utf8)
    return 'action-result'
  }
  Assert-Condition ($actionResult -eq 'action-result') 'El envoltorio debe devolver el resultado de la operación.'
  $manifestPath = Join-Path $root '.ps5hs-modifications.json'
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  Assert-Condition ($manifest.records.Count -eq 1) 'La mutación autorizada debe quedar registrada.'
  $changedFile = $manifest.records[0].changedFiles | Where-Object { $_.path -eq 'src/sample.cpp' } | Select-Object -First 1
  Assert-Condition ($null -ne $changedFile) 'El registro debe identificar el archivo cambiado.'
  Assert-Condition ($changedFile.originalSha256 -ne $changedFile.resultSha256) 'El registro debe contener hashes diferentes antes y después.'

  # A corrupt log must block the action before source files are touched.
  [IO.File]::WriteAllText($manifestPath,'not-json',$utf8)
  $corruptManifestDenied = $false
  try {
    InvokePS5HSNativeModificationWithAudit -ProjectRoot $root -Backend 'opengl-ui' -Operation 'corrupt-log-test' -PermissionKey 'allowOpenGlRuntimeProfile' -RelativePaths @('src/sample.cpp') -Policy $runtimeConsent -Action {
      [IO.File]::WriteAllText($path,'must-not-run-corrupt-log',$utf8)
    } | Out-Null
  } catch { $corruptManifestDenied = $true }
  Assert-Condition $corruptManifestDenied 'Un manifiesto corrupto debe bloquear la operación.'
  Assert-Condition ([IO.File]::ReadAllText($path) -ceq 'after') 'Un manifiesto corrupto no debe permitir modificar fuentes.'

  # Source snapshots include embedded dependencies but never .git internals.
  [IO.Directory]::CreateDirectory((Join-Path $root '.deps/hui')) | Out-Null
  [IO.Directory]::CreateDirectory((Join-Path $root '.git/objects')) | Out-Null
  [IO.File]::WriteAllText((Join-Path $root '.deps/hui/dependency.cpp'),'dependency',$utf8)
  [IO.File]::WriteAllText((Join-Path $root '.git/objects/ignored'),'git',[Text.UTF8Encoding]::new($false))
  [IO.Directory]::CreateDirectory((Join-Path $root 'build')) | Out-Null
  [IO.Directory]::CreateDirectory((Join-Path $root 'out-123456')) | Out-Null
  [IO.File]::WriteAllText((Join-Path $root 'build/compiler-output.bin'),'binary output',$utf8)
  [IO.File]::WriteAllText((Join-Path $root 'out-123456/title.pkg'),'binary output',$utf8)
  $openGlDepsRoot = Join-Path $root '.deps/ps5-opengl'
  $openGlSdkTarget = Join-Path $openGlDepsRoot 'sdk-1.0.2'
  [IO.Directory]::CreateDirectory($openGlSdkTarget) | Out-Null
  [IO.File]::WriteAllText((Join-Path $openGlSdkTarget 'sdk-cache.txt'),'verified-sdk-cache',$utf8)
  $openGlCurrentLink = Join-Path $openGlDepsRoot 'current'
  New-Item -ItemType SymbolicLink -Path $openGlCurrentLink -Target $openGlSdkTarget | Out-Null

  # WSL stores LX symlinks as file-like reparse points, and PowerShell does not
  # expose their target through Target/LinkTarget. Exercise that metadata shape
  # without following the destination.
  $lxTargetBytes = [Text.Encoding]::UTF8.GetBytes('/mnt/c/Visual-PS5/toolchains/ps5-opengl-sdk/.cache/sdk')
  $lxPayload = [byte[]]::new(4 + $lxTargetBytes.Length)
  [BitConverter]::GetBytes([int]2).CopyTo($lxPayload,0)
  [Array]::Copy($lxTargetBytes,0,$lxPayload,4,$lxTargetBytes.Length)
  $lxReparseData = [byte[]]::new(8 + $lxPayload.Length)
  [BitConverter]::GetBytes([Convert]::ToUInt32('A000001D',16)).CopyTo($lxReparseData,0)
  [BitConverter]::GetBytes([uint16]$lxPayload.Length).CopyTo($lxReparseData,4)
  [Array]::Copy($lxPayload,0,$lxReparseData,8,$lxPayload.Length)
  $lxLinkItem = [pscustomobject]@{
    FullName = $openGlCurrentLink
    Attributes = [IO.FileAttributes]::Archive -bor [IO.FileAttributes]::ReparsePoint
    Target = $null
    LinkTarget = $null
  }
  $lxFingerprint = GetPS5HSNativeGeneratedDependencyLinkFingerprint -LinkItem $lxLinkItem -ReparseData $lxReparseData
  Assert-Condition ($lxFingerprint -match '^[0-9a-f]{64}$') 'El enlace WSL debe producir una huella SHA-256 del metadato sin depender de Target/LinkTarget.'
  $lxTreeFingerprint = GetPS5HSNativeTreeReparsePointHash -RelativePath '.deps/ps5-opengl/current' -LinkItem $lxLinkItem -ReparseData $lxReparseData -EntryKind 'file'
  Assert-Condition ($lxTreeFingerprint -ceq $lxFingerprint) 'El alias OpenGL enumerado como archivo debe pasar por la huella de metadatos permitida.'
  $wrongLxPathDenied = $false
  try { $null = GetPS5HSNativeTreeReparsePointHash -RelativePath 'src/untrusted-link' -LinkItem $lxLinkItem -ReparseData $lxReparseData -EntryKind 'file' } catch { $wrongLxPathDenied = $true }
  Assert-Condition $wrongLxPathDenied 'El auditor debe seguir rechazando los enlaces WSL fuera del alias OpenGL exacto.'
  $unknownReparseData = [byte[]]$lxReparseData.Clone()
  [BitConverter]::GetBytes([Convert]::ToUInt32('A0000003',16)).CopyTo($unknownReparseData,0)
  $unknownTagDenied = $false
  try { $null = GetPS5HSNativeGeneratedDependencyLinkFingerprint -LinkItem $lxLinkItem -ReparseData $unknownReparseData } catch { $unknownTagDenied = $true }
  Assert-Condition $unknownTagDenied 'El alias OpenGL debe rechazar tipos de reanálisis distintos de symlink y LX symlink.'

  $treeSnapshot = GetPS5HSNativeTreeHashes -ProjectRoot $root
  Assert-Condition ($treeSnapshot.ContainsKey('.deps/hui/dependency.cpp')) 'El snapshot debe incluir dependencias embebidas, porque también pueden modificarse.'
  Assert-Condition ($treeSnapshot.ContainsKey('.deps/ps5-opengl/current')) 'El alias generado current debe quedar representado en el hash de auditoría.'
  Assert-Condition (!$treeSnapshot.ContainsKey('.deps/ps5-opengl/current/sdk-cache.txt')) 'El auditor debe registrar el alias como metadatos y nunca seguir el enlace.'
  $linkOnlyHash = GetPS5HSNativeFileHashes -ProjectRoot $root -RelativePaths @('.deps/ps5-opengl/current')
  Assert-Condition ($linkOnlyHash['.deps/ps5-opengl/current'] -ceq $treeSnapshot['.deps/ps5-opengl/current']) 'El snapshot completo y el registro de cambios deben hashear el mismo metadato del enlace.'
  Assert-Condition (!$treeSnapshot.ContainsKey('.git/objects/ignored')) 'El snapshot no debe recorrer ni auditar internals Git.'

  # Only the exact upstream-generated OpenGL alias is accepted; arbitrary links stay denied.
  $unexpectedLink = Join-Path $root 'src/untrusted-link'
  New-Item -ItemType SymbolicLink -Path $unexpectedLink -Target $openGlSdkTarget | Out-Null
  $unexpectedLinkDenied = $false
  try { $null = GetPS5HSNativeTreeHashes -ProjectRoot $root } catch { $unexpectedLinkDenied = $true }
  Assert-Condition $unexpectedLinkDenied 'El auditor debe seguir rechazando enlaces distintos del alias current del SDK OpenGL.'
  Remove-Item -LiteralPath $unexpectedLink -Force
  Assert-Condition (!$treeSnapshot.ContainsKey('build/compiler-output.bin')) 'El snapshot debe excluir artefactos de build regenerables.'
  Assert-Condition (!$treeSnapshot.ContainsKey('out-123456/title.pkg')) 'El snapshot debe excluir carpetas de salida para no hashear paquetes grandes.'

  # Project paths may be nested and not exist before generation starts. The audit
  # preflight must walk to an existing ancestor instead of requiring the immediate parent.
  $nestedRoot = Join-Path $root 'not-created-yet/nested/generated-project'
  $nestedGenerationConsent = [pscustomobject]@{allowExecuteUpstreamGenerationTools=$true}
  $null = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $nestedRoot -Backend 'nativecpp' -Operation 'test-nested-tree-generator' -PermissionKey 'allowExecuteUpstreamGenerationTools' -Policy $nestedGenerationConsent -Action {
    [IO.Directory]::CreateDirectory((Join-Path $nestedRoot 'src')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $nestedRoot 'src/generated.cpp'),'generated',$utf8)
  }
  $nestedManifest = Get-Content -LiteralPath (Join-Path $nestedRoot '.ps5hs-modifications.json') -Raw | ConvertFrom-Json
  Assert-Condition ($nestedManifest.records.Count -eq 1) 'El preflight de auditoría debe aceptar nuevas rutas con más de un directorio padre inexistente.'

  # A newly generated project must record files created by the upstream generator.
  $treeRoot = Join-Path $root 'generated-project'
  $generationConsent = [pscustomobject]@{allowExecuteUpstreamGenerationTools=$true}
  $null = InvokePS5HSNativeTreeModificationWithAudit -ProjectRoot $treeRoot -Backend 'nativecpp' -Operation 'test-tree-generator' -PermissionKey 'allowExecuteUpstreamGenerationTools' -Policy $generationConsent -SourceRepository 'test-fixture' -Action {
    [IO.Directory]::CreateDirectory((Join-Path $treeRoot 'src')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $treeRoot 'src/generated.cpp'),'generated',$utf8)
  }
  $treeManifest = Get-Content -LiteralPath (Join-Path $treeRoot '.ps5hs-modifications.json') -Raw | ConvertFrom-Json
  Assert-Condition ($treeManifest.records.Count -eq 1) 'El generador debe producir un único registro de auditoría.'
  Assert-Condition ($treeManifest.records[0].permission -eq 'allowExecuteUpstreamGenerationTools') 'El registro debe identificar el consentimiento utilizado.'
  Assert-Condition (@($treeManifest.records[0].changedFiles | Where-Object { $_.path -eq 'src/generated.cpp' -and $null -eq $_.originalSha256 -and $_.resultSha256 }).Count -eq 1) 'El registro debe identificar los archivos creados por el generador.'

} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'PASS native modification policy: deny-by-default, fail-closed checks, mutation guards and SHA-256 audit.'
