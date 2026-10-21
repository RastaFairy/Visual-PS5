'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const server = fs.readFileSync(path.join(__dirname, 'server.ps1'), 'utf8');
const policy = fs.readFileSync(path.join(__dirname, 'native-modification-policy.ps1'), 'utf8');
const policyJs = fs.readFileSync(path.join(__dirname, 'native-modification-policy.js'), 'utf8');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const packer = fs.readFileSync(path.join(__dirname, 'Build-ToolchainPack.ps1'), 'utf8');
const pins = JSON.parse(fs.readFileSync(path.join(__dirname, 'toolchain-pins.json'), 'utf8'));
const sdkFetch = fs.readFileSync(path.join(root, 'toolchains/ps5-homebrew-ui/tools/fetch-opengl-sdk.sh'), 'utf8');

// Pins: source and SDK artifacts are all local-only.
assert.equal(pins.schema, 'ps5hs-toolchain-pins');
assert.equal(pins.version, 1);
assert.ok(!pins.mirrors, 'the pin manifest must not advertise external fallbacks');
assert.ok(!JSON.stringify(pins).includes('https://'), 'the pin manifest must not contain download URLs');
const sdkPin = pins.artifacts && pins.artifacts['ps5-opengl-sdk'];
assert.ok(sdkPin, 'the OpenGL SDK pin must remain available');
assert.match(String(sdkPin.version), /^1\.\d+\.\d+$/);
assert.match(sdkPin.archive.sha256, /^[0-9a-f]{64}$/);
assert.match(sdkPin.sdkManifest.sha256, /^[0-9a-f]{64}$/);
assert.equal(sdkPin.localPath, 'toolchains/ps5-opengl-sdk/ps5-opengl-sdk-1.0.2.tar.gz');
assert.ok(!sdkPin.urls, 'the SDK pin must not contain remote URLs');

// Local source resolver: no remote clone, archive download, or online pip fallback.
const installStart = server.indexOf('function InstallRepo($Entry) {');
const installEnd = server.indexOf('function BashQuote([string]$Text)', installStart);
assert.ok(installStart >= 0 && installEnd > installStart, 'InstallRepo must exist');
const installBlock = server.slice(installStart, installEnd);
assert.match(installBlock, /Dependencia local no disponible/);
assert.match(installBlock, /GetPS5HSBundledToolchainInfo/);
assert.match(installBlock, /No se descargará ni sobrescribirá/);
assert.doesNotMatch(installBlock, /\bgit clone\b|Invoke-WebRequest|Invoke-RestMethod|codeload\.github|pip install|winget install|https?:\/\//i);
assert.match(server, /function GetPS5HSLocalSdkRoot/);
assert.match(server, /Join-Path \$script:Toolchains 'ps5-opengl-sdk'/);
assert.match(server, /function SeedProjectOpenGlSdkCache/);
assert.doesNotMatch(server, /function GetPS5HSMirrorAlternatives|function GetPS5HSUpstreamUnavailable|function GetPS5HSSdkMirrorUrls/);

// Setup is diagnosis-only; Windows tools must not be fetched by the IDE.
const setupStart = server.indexOf('function InvokeSetup([string]$Action) {');
const setupEnd = server.indexOf('function ServeStatic(', setupStart);
assert.ok(setupStart >= 0 && setupEnd > setupStart);
const setupBlock = server.slice(setupStart, setupEnd);
assert.match(setupBlock, /Diagnóstico local completado/);
assert.doesNotMatch(setupBlock, /winget install|wsl\.exe --install|Invoke-WebRequest|Start-BitsTransfer/i);

// OpenGL's source fetcher is offline-only and keeps both archive and internal manifest checksums.
assert.match(sdkFetch, /PS5HS_LOCAL_ONLY/);
assert.match(sdkFetch, /caché local/);
assert.match(sdkFetch, /archive_sha256/);
assert.match(sdkFetch, /manifest_sha256/);
assert.doesNotMatch(sdkFetch, /\bcurl\b|\bwget\b|https?:\/\//i);

// The project-specific guard is mandatory, auditable, and does not add network fallbacks.
assert.match(policy, /function ApplyPS5HSSdkLocalOnlyPatch/);
assert.match(policy, /allowLocalSdkCachePatch/);
assert.match(policy, /enforce-sdk-local-only/);
assert.match(policy, /PS5HS_LOCAL_ONLY/);
assert.doesNotMatch(policy, /function ApplyPS5HSSdkMirrorChainPatch/);
assert.match(policyJs, /key:'allowLocalSdkCachePatch'[^}]+required:true/);
assert.doesNotMatch(policyJs, /allowUpstreamSdkMirrorPatch/);

// The SDK panel and installer describe a local verification, not cloning/downloading.
assert.match(app, /verifica fuentes locales versionadas en toolchains\//);
assert.match(app, /Verificar toolchains locales/);
assert.match(app, /Buscar en toolchains\//);
assert.match(app, /FALTA EN toolchains\//);
assert.match(app, /allowLocalSdkCachePatch/);
assert.doesNotMatch(app, /MIRROR DISPONIBLE|Clonar desde GitHub|Descargar todos los SDK|allowUpstreamSdkMirrorPatch/);
assert.match(app, /No se instalarán herramientas por Internet/);

// The SDK packer validates local files and emits a manifest, with no download path.
assert.match(packer, /Get-FileHash -LiteralPath \$Path -Algorithm SHA256/);
assert.match(packer, /networkAccess = \$false/);
assert.match(packer, /toolchains\\ps5-opengl-sdk/);
assert.match(packer, /Compress-Archive/);
assert.doesNotMatch(packer, /Invoke-WebRequest|https?:\/\/|\.urls\b|toolchain-pack/i);

console.log('PASS local-only toolchains: resolver, setup, SDK script, UI, policy and packer contracts.');
