Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-modification-policy.ps1')

function Assert-Condition([bool]$Condition,[string]$Message) {
  if (!$Condition) { throw $Message }
}

$defaults = NormalizePS5HSNativeModificationPolicy $null
Assert-Condition ($defaults.Count -eq 13) 'La política debe declarar todas las operaciones registradas.'
Assert-Condition (@($defaults.Values | Where-Object { $_ -eq $true }).Count -eq 0) 'Todas las modificaciones deben estar denegadas por defecto.'
Assert-Condition (!$defaults.allowExecuteUpstreamAssetTools) 'La conversión de recursos también debe estar denegada por defecto.'
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
Assert-Condition ($normalized.allowOpenGlTemplateIntegration -and !$normalized.allowOpenGlRuntimeProfile) 'Solo deben respetarse permisos booleanos explícitos.'
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
  $treeSnapshot = GetPS5HSNativeTreeHashes -ProjectRoot $root
  Assert-Condition ($treeSnapshot.ContainsKey('.deps/hui/dependency.cpp')) 'El snapshot debe incluir dependencias embebidas, porque también pueden modificarse.'
  Assert-Condition (!$treeSnapshot.ContainsKey('.git/objects/ignored')) 'El snapshot no debe recorrer ni auditar internals Git.'
  Assert-Condition (!$treeSnapshot.ContainsKey('build/compiler-output.bin')) 'El snapshot debe excluir artefactos de build regenerables.'
  Assert-Condition (!$treeSnapshot.ContainsKey('out-123456/title.pkg')) 'El snapshot debe excluir carpetas de salida para no hashear paquetes grandes.'

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

  # Guard local-only del SDK OpenGL: consentimiento, integridad e idempotencia.
  $localRoot = Join-Path $root 'local-project'
  [IO.Directory]::CreateDirectory((Join-Path $localRoot 'tools')) | Out-Null
  $fetchPath = Join-Path $localRoot 'tools/fetch-opengl-sdk.sh'
  $pristineFetch = @'
#!/usr/bin/env bash
set -euo pipefail
version=1.0.2
archive_sha256=30d8e51dd062739b629346102be5932728ba714bc50b1bdcdf08306c8843d9a4
manifest_sha256=0d432edc9d648d6e0cccb4d5eb3db8484f10ba4b075b5ccf23edda3251b66360
url="https://github.com/blackbearreloaded/ps5-opengl/releases/download/v$version/ps5-opengl-sdk-$version.tar.gz"
cache="$root/.deps/ps5-opengl"
archive="$cache/ps5-opengl-sdk-$version.tar.gz"
extracted="$cache/ps5-opengl-sdk-$version"
prefix="$extracted/sdk"
if [[ ! -f $prefix/manifest.sha256 ]]; then
    if [[ ! -f $archive ]] || ! sha256sum --check --status <<<"$archive_sha256  $archive"; then
        printf '==> [opengl] Downloading ps5-opengl SDK %s\n' "$version" >&2
        curl -fL --retry 3 -o "$archive.part" "$url"
        mv -- "$archive.part" "$archive"
    fi
    sha256sum --check --status <<<"$archive_sha256  $archive" || exit 2
fi
'@
  $lf = [string][char]10
  $crlf = ([string][char]13) + ([string][char]10)
  $pristineFetch = $pristineFetch.Replace($crlf,$lf)
  [IO.File]::WriteAllText($fetchPath,$pristineFetch,$utf8)

  $deniedPatch = ApplyPS5HSSdkLocalOnlyPatch -ProjectRoot $localRoot -Policy $null -Backend 'opengl-ui'
  Assert-Condition (!$deniedPatch.ok -and $deniedPatch.skipped -and !$deniedPatch.changed) 'Sin permiso, el parche local-only debe bloquear la operación sin tocar el script.'
  Assert-Condition ([IO.File]::ReadAllText($fetchPath) -ceq $pristineFetch) 'El script del SDK debe quedar intacto sin consentimiento.'

  $localConsent = [pscustomobject]@{allowLocalSdkCachePatch=$true}
  $appliedPatch = ApplyPS5HSSdkLocalOnlyPatch -ProjectRoot $localRoot -Policy $localConsent -Backend 'opengl-ui'
  Assert-Condition ($appliedPatch.ok -and $appliedPatch.changed) 'Con permiso, el parche debe imponer el uso del caché local.'
  $patchedFetch = [IO.File]::ReadAllText($fetchPath)
  Assert-Condition ($patchedFetch.Contains('# PS5HS_LOCAL_ONLY')) 'El script parcheado debe declarar la marca local-only.'
  Assert-Condition ($patchedFetch.Contains('ps5-opengl SDK ausente del caché local')) 'El script debe fallar con un diagnóstico si falta el archivo local.'
  Assert-Condition (!$patchedFetch.Contains('curl ') -and !$patchedFetch.Contains('https://') -and !$patchedFetch.Contains('url="')) 'El script parcheado no puede conservar acceso HTTP.'
  Assert-Condition ($patchedFetch.Contains('archive_sha256=') -and $patchedFetch.Contains('manifest_sha256=')) 'El parche debe conservar ambos pins de integridad.'
  $localManifest = Get-Content -LiteralPath (Join-Path $localRoot '.ps5hs-modifications.json') -Raw | ConvertFrom-Json
  Assert-Condition (@($localManifest.records | Where-Object { $_.operation -eq 'enforce-sdk-local-only' }).Count -ge 1) 'El parche debe registrar su auditoría SHA-256.'

  $idempotentPatch = ApplyPS5HSSdkLocalOnlyPatch -ProjectRoot $localRoot -Policy $localConsent -Backend 'opengl-ui'
  Assert-Condition (!$idempotentPatch.changed -and $idempotentPatch.alreadyPatched) 'El parche debe ser idempotente sobre un script ya parcheado.'
  Assert-Condition ([IO.File]::ReadAllText($fetchPath) -ceq $patchedFetch) 'La reejecución no debe alterar el script parcheado.'

  [IO.File]::WriteAllText($fetchPath,'#!/usr/bin/env bash' + $lf + 'echo unrecognizable' + $lf,$utf8)
  $unrecognized = $false
  try { ApplyPS5HSSdkLocalOnlyPatch -ProjectRoot $localRoot -Policy $localConsent -Backend 'opengl-ui' | Out-Null } catch { $unrecognized = $true }
  Assert-Condition $unrecognized 'Un script de SDK irreconocible debe abortar el parche sin modificaciones parciales.'
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'PASS native modification policy: deny-by-default, fail-closed checks, mutation guards, SHA-256 audit and local-only SDK bootstrap.'
