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

// Manifiesto de integridad: se conserva para verificar artefactos colocados localmente.
assert.equal(pins.schema, 'ps5hs-toolchain-pins', 'toolchain-pins.json debe declarar su esquema');
assert.equal(pins.version, 1, 'la version del manifiesto debe ser 1');
assert.ok(pins.artifacts && pins.artifacts['ps5-opengl-sdk'], 'el manifiesto debe fijar el artefacto ps5-opengl-sdk');
assert.match(String(pins.artifacts['ps5-opengl-sdk'].version), /^1\.\d+\.\d+$/, 'la version del SDK debe ser semver');
assert.match(pins.artifacts['ps5-opengl-sdk'].archive.sha256, /^[0-9a-f]{64}$/, 'el archivo debe tener un SHA-256 fijado');
assert.match(pins.artifacts['ps5-opengl-sdk'].sdkManifest.sha256, /^[0-9a-f]{64}$/, 'el manifest interno debe tener SHA-256');

const vendoredManifest = JSON.parse(fs.readFileSync(path.join(root, 'toolchains', 'SharpProspero', '.ps5hs-source.json'), 'utf8'));
assert.equal(vendoredManifest.vendoredSnapshot, true, 'el snapshot de muestra debe estar versionado');
assert.equal(vendoredManifest.vendorRepository, 'RastaFairy/Visual-PS5', 'el manifiesto debe identificar el repositorio que contiene la copia');

// Resolver local: una fuente solo se acepta si está dentro de toolchains/ y su manifiesto coincide.
assert.match(server, /function GetPS5HSBundledToolchainInfo\(/, 'el servidor debe tener un validador de fuentes locales');
assert.match(server, /\$sourceInfo\.vendoredSnapshot/, 'la copia debe declarar vendoredSnapshot');
assert.match(server, /\$sourceInfo\.vendorRepository/, 'el manifiesto debe identificar al repositorio que versiona la copia');
assert.match(server, /function InstallRepo\(\$Entry\)/, 'el instalador debe usar la resolución local');
assert.match(server, /No se ha consultado GitHub, probado mirrors ni descargado nada/, 'si falta una copia, se debe explicar que no hay fallback de red');
const installerStart = server.indexOf('function InstallRepo($Entry) {');
const installerEnd = server.indexOf('function BashQuote([string]$Text) {', installerStart);
assert.ok(installerStart >= 0 && installerEnd > installerStart, 'el instalador local debe estar delimitado');
const installer = server.slice(installerStart, installerEnd);
assert.doesNotMatch(installer, /git clone|Invoke-WebRequest|Invoke-RestMethod|pip install|Expand-Archive|https:\/\/github\.com/i, 'la resolución no debe clonar, descargar, extraer ZIP ni instalar paquetes de Internet');
assert.doesNotMatch(server, /function GetPS5HSUpstreamUnavailable\(|function GetPS5HSMirrorAlternatives\(|function GetPS5HSSdkMirrorUrls\(|ApplyPS5HSSdkMirrorChainPatch/, 'el runtime ya no debe consultar ni parchear cadenas de mirrors');
assert.match(server, /Join-Path \$script:Toolchains 'ps5-opengl-sdk'/, 'el SDK OpenGL local debe buscarse bajo toolchains/');
assert.match(server, /localOnly=\$true/, 'el diagnóstico debe exponer el modo de dependencias local-only');
assert.match(server, /function GetMissingProjectDependencies[\s\S]*?GetPS5HSBundledToolchainInfo/, 'las dependencias del proyecto deben validarse con el manifiesto local');
assert.doesNotMatch(server, /make source-fetch\s*&&/, 'el IDE no debe ejecutar source-fetch durante la preparación OpenGL');
assert.doesNotMatch(server, /&& make deps &&/, 'el IDE no debe ejecutar un target deps que recupere paquetes externos');
assert.match(server, /PS5HS_LOCAL_TOOLCHAINS_ONLY=1/, 'el flag local-only debe propagarse al build');

// The obsolete permission to rewrite an upstream downloader must disappear from both policies.
assert.doesNotMatch(policy, /ApplyPS5HSSdkMirrorChainPatch|allowUpstreamSdkMirrorPatch/, 'PowerShell policy must not offer mirror patching');
assert.doesNotMatch(policyJs, /allowUpstreamSdkMirrorPatch/, 'client policy must not offer mirror patching');
assert.match(policyJs, /function entriesForBackend/, 'the remaining permissions must continue to be available');
assert.match(app, /Verificar toolchains locales/, 'the IDE must expose local toolchain verification');
assert.match(app, /NO INCLUIDA/, 'the UI must say when a local source is missing');
assert.match(app, /SOLO REFERENCIA/, 'source-only snapshots must remain clearly non-buildable');
assert.doesNotMatch(app, /Clonar desde GitHub|Descarga de repositorios finalizada|MIRROR DISPONIBLE/, 'the SDK panel must not advertise network cloning or mirrors');

// Packer: integrity remains required and packaging never deletes sources.
assert.match(packer, /Get-FileHash -LiteralPath \$Path -Algorithm SHA256/, 'the packer must verify SHA-256');
assert.match(packer, /toolchain-pins\.json/, 'the packer must read the pin manifest');
assert.match(packer, /manifest\.json/, 'the packer must emit a pack manifest');
assert.match(packer, /Compress-Archive/, 'the packer must support its optional ZIP backup');
assert.doesNotMatch(packer, /Remove-Item.*toolchains/, 'the packer must never delete toolchains');

console.log('PASS toolchain pins: local-only source resolution, vendor manifests, integrity pins, policy and packer contracts.');
