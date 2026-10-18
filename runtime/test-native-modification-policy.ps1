Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-modification-policy.ps1')
function Assert-Condition([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
$defaults = NormalizePS5HSNativeModificationPolicy $null
Assert-Condition ($defaults.Count -eq 10) 'La política debe normalizar todas las operaciones registradas.'
Assert-Condition (@($defaults.Values | Where-Object { $_ -eq $true }).Count -eq 0) 'Todas las modificaciones deben estar denegadas por defecto.'
$gaps = @(GetPS5HSNativeModificationConsentGaps -Backend 'opengl-ui' -Policy $null -RequireGeneration $true -RequireBuildTools $true -RequireVisualIntegration $true)
Assert-Condition ($gaps.Count -eq 3) 'OpenGL debe exigir generador, herramientas upstream e integración visual.'
$approved = [pscustomobject]@{
  allowExecuteUpstreamGenerationTools=$true
  allowExecuteUpstreamBuildTools=$true
  allowOpenGlTemplateIntegration=$true
  allowOpenGlRuntimeProfile=$false
  allowOpenGlEuropeanAtlas=$false
  allowWindowsBuildEntrypointPatch=$false
  allowVulkanTemplateIntegration=$false
  allowVulkanBuildHelperRestore=$false
  normalizeBuildFiles=$false
  allowCustomUnicodeFont=$false
  unexpectedPermission=$true
}
$normalized = NormalizePS5HSNativeModificationPolicy $approved
Assert-Condition ($normalized.allowOpenGlTemplateIntegration -and !$normalized.allowOpenGlRuntimeProfile) 'Solo deben respetarse permisos booleanos explícitos.'
Assert-Condition (!$normalized.ContainsKey('unexpectedPermission')) 'No deben admitirse permisos desconocidos.'
Assert-Condition (@(GetPS5HSNativeModificationConsentGaps -Backend 'vulkan-ui' -Policy $normalized -HasCustomFont $true).Count -eq 2) 'El backend Vulkan y la fuente TTF deben requerir sus autorizaciones propias.'
$root = Join-Path ([IO.Path]::GetTempPath()) ('ps5hs-policy-' + [guid]::NewGuid().ToString('N'))
try {
  [IO.Directory]::CreateDirectory((Join-Path $root 'src')) | Out-Null
  $path=Join-Path $root 'src/sample.cpp'
  [IO.File]::WriteAllText($path,'before',[Text.UTF8Encoding]::new($false))
  $before = GetPS5HSNativeFileHashes -ProjectRoot $root -RelativePaths @('src/sample.cpp')
  [IO.File]::WriteAllText($path,'after',[Text.UTF8Encoding]::new($false))
  $record=AddPS5HSNativeModificationRecord -ProjectRoot $root -Backend 'opengl-ui' -Operation 'test-patch' -PermissionKey 'allowOpenGlRuntimeProfile' -RelativePaths @('src/sample.cpp') -BeforeHashes $before -Policy ([pscustomobject]@{allowOpenGlRuntimeProfile=$true})
  $manifest=Get-Content -LiteralPath (Join-Path $root '.ps5hs-modifications.json') -Raw | ConvertFrom-Json
  Assert-Condition ($manifest.records.Count -eq 1) 'Debe crearse un registro de auditoría.'
  Assert-Condition ($manifest.records[0].changedFiles[0].originalSha256 -ne $manifest.records[0].changedFiles[0].resultSha256) 'El manifiesto debe registrar hashes previos/finales.'
  $blocked=$false
  try { AddPS5HSNativeModificationRecord -ProjectRoot $root -Backend 'opengl-ui' -Operation 'blocked' -PermissionKey 'allowOpenGlRuntimeProfile' -RelativePaths @('src/sample.cpp') -BeforeHashes $before -Policy $null | Out-Null } catch { $blocked=$true }
  Assert-Condition $blocked 'No debe registrarse una modificación sin permiso.'
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output 'PASS native modification policy: fail-closed consent, strict normalization and SHA-256 audit.'
