Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-modification-policy.ps1')

function Assert-Condition([bool]$Condition,[string]$Message) {
  if (!$Condition) { throw $Message }
}

$defaults = NormalizePS5HSNativeModificationPolicy $null
Assert-Condition ($defaults.Count -eq 10) 'La política debe declarar todas las operaciones registradas.'
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
Assert-Condition (@(GetPS5HSNativeModificationConsentGaps -Backend 'vulkan-ui' -Policy $normalized -RequireVisualIntegration $true -HasCustomFont $true).Count -eq 2) 'Vulkan y la fuente TTF deben exigir sus permisos específicos.'
$unknownDenied = $false
try { AssertPS5HSNativeModificationConsent -Backend 'opengl-ui' -Policy $normalized -RequirePermissionKeys @('unknownPermission') | Out-Null } catch { $unknownDenied = $true }
Assert-Condition $unknownDenied 'Un endpoint no debe poder solicitar un permiso que no figure en el catálogo.'

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
  $treeSnapshot = GetPS5HSNativeTreeHashes -ProjectRoot $root
  Assert-Condition ($treeSnapshot.ContainsKey('.deps/hui/dependency.cpp')) 'El snapshot debe incluir dependencias embebidas, porque también pueden modificarse.'
  Assert-Condition (!$treeSnapshot.ContainsKey('.git/objects/ignored')) 'El snapshot no debe recorrer ni auditar internals Git.'

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
