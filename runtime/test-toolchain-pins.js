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

// Local integrity pins remain mandatory; runtime URLs are not a dependency source.
assert.equal(pins.schema, 'ps5hs-toolchain-pins');
assert.equal(pins.version, 1);
assert.ok(pins.artifacts && pins.artifacts['ps5-opengl-sdk']);
const sdkPin = pins.artifacts['ps5-opengl-sdk'];
assert.match(String(sdkPin.version), /^1\.\d+\.\d+$/);
assert.match(sdkPin.archive.sha256, /^[0-9a-f]{64}$/);
assert.match(sdkPin.sdkManifest.sha256, /^[0-9a-f]{64}$/);
assert.ok(Number.isInteger(sdkPin.bytes) && sdkPin.bytes > 0);
assert.equal(sdkPin.urls, undefined, 'runtime pins must not advertise SDK download URLs');

// InstallRepo adopts local files and does not fetch source from a network.
const installStart = server.indexOf('function InstallRepo($Entry) {');
const installEnd = server.indexOf('\nfunction ', installStart + 1);
assert.ok(installStart >= 0 && installEnd > installStart, 'InstallRepo must exist as a standalone function');
const installRepo = server.slice(installStart, installEnd);
assert.match(installRepo, /toolchains\/ de este repositorio/);
assert.doesNotMatch(installRepo, /git clone|Invoke-WebRequest|codeload\.github\.com|https:\/\/github\.com/);
assert.match(installRepo, /--no-index/, 'UltraPack Python packages must resolve from local wheels');
assert.match(installRepo, /Dependencia local ausente/, 'missing local sources must fail with a diagnostic');
assert.match(server, /function GetPS5HSToolchainPackRoot \{ return \(Join-Path \$script:Toolchains 'toolchain-pack'\) \}/);
assert.match(server, /sourcePolicy='local-only'/);
assert.match(server, /localOnly=\$true/);
assert.doesNotMatch(server, /GetPS5HSMirrorAlternatives|GetPS5HSSdkMirrorUrls|ApplyPS5HSSdkMirrorChainPatch|Invoke-WebRequest -Uri \('https:\/\/codeload/);
assert.match(server, /ApplyPS5HSSdkLocalOnlyPatch/);

// Legacy project patch is explicit, audited and tied to the normal build permission.
assert.match(policy, /function ApplyPS5HSSdkLocalOnlyPatch\b/);
assert.match(policy, /enforce-local-only-sdk-source/);
assert.doesNotMatch(policy, /allowUpstreamSdkMirrorPatch|ApplyPS5HSSdkMirrorChainPatch|PS5HS_MIRROR_CHAIN/);
assert.doesNotMatch(policyJs, /allowUpstreamSdkMirrorPatch/);

// The vendored SDK bootstrap can only consume a locally seeded archive.
assert.match(sdkFetch, /PS5HS_LOCAL_ONLY/);
assert.match(sdkFetch, /archive_sha256=/);
assert.match(sdkFetch, /manifest_sha256=/);
assert.doesNotMatch(sdkFetch, /curl\s|wget\s|https:\/\/github\.com|url="https?/);

// UI reports local availability instead of online mirrors and downloads.
assert.match(app, /No se ejecuta git clone, no se descargan ZIP/);
assert.match(app, /NO INCLUIDO EN TOOLCHAINS/);
assert.doesNotMatch(app, /MIRROR DISPONIBLE|allowUpstreamSdkMirrorPatch|upstreamUnavailable|mirrorAlternatives/);
assert.doesNotMatch(app, /Descarga los repositorios oficiales desde GitHub|Se descargan fuentes de GitHub/);

// Offline packer verifies only the local pinned archive, never downloading it.
assert.match(packer, /Join-Path \$toolchainsRoot 'toolchain-pack'/);
assert.match(packer, /Get-FileHash -LiteralPath \$Path -Algorithm SHA256/);
assert.match(packer, /no se realiza ninguna descarga/);
assert.doesNotMatch(packer, /Invoke-WebRequest|artifact\.urls|Descargando SDK desde/);
assert.match(packer, /Compress-Archive/);
assert.doesNotMatch(packer, /Remove-Item.*toolchains/);

console.log('PASS local-only toolchain resolution: local source folders, pinned SDK cache, offline Python wheels, audit and packer contracts.');
