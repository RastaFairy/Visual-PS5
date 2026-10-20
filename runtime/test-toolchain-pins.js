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

// Manifiesto de pins.
assert.equal(pins.schema, 'ps5hs-toolchain-pins', 'toolchain-pins.json debe declarar su esquema');
assert.equal(pins.version, 1, 'la version del manifiesto de pins debe ser 1');
assert.ok(pins.mirrors, 'el manifiesto debe declarar mirrors');
assert.ok(pins.artifacts && pins.artifacts['ps5-opengl-sdk'], 'el manifiesto debe fijar el artefacto ps5-opengl-sdk');

const sha256Hex = /^[0-9a-f]{64}$/;
const sdkPin = pins.artifacts['ps5-opengl-sdk'];
assert.match(String(sdkPin.version), /^1\.\d+\.\d+$/, 'la version del SDK debe ser semver');
assert.match(sdkPin.archive.sha256, sha256Hex, 'el pin del tarball debe ser un SHA-256 en minusculas');
assert.match(sdkPin.sdkManifest.sha256, sha256Hex, 'el pin del manifest interno debe ser un SHA-256');
assert.ok(Number.isInteger(sdkPin.bytes) && sdkPin.bytes > 0, 'el pin debe declarar el tamano en bytes');
assert.ok(Array.isArray(sdkPin.urls) && sdkPin.urls.length >= 3, 'la cadena de descarga debe incluir upstream y al menos dos mirrors');
assert.ok(sdkPin.urls[0].includes('blackbearreloaded/ps5-opengl'), 'el upstream original debe ser la primera URL de la cadena');
assert.ok(sdkPin.urls.some(u => u.includes('LedyBacer/ps5-opengl')), 'la cadena debe incluir el mirror verificado LedyBacer');
assert.ok(new Set(sdkPin.urls).size === sdkPin.urls.length, 'las URLs de la cadena no deben repetirse');
for (const url of sdkPin.urls) {
  assert.match(url, /^https:\/\/github\.com\/[\w.-]+\/ps5-opengl\/releases\/download\/v1\.0\.2\/ps5-opengl-sdk-1\.0\.2\.tar\.gz$/, 'cada URL debe apuntar al mismo asset v1.0.2 del SDK');
}

// Mirrors declarados: repos conocidos y sin auto-referencia.
for (const [repo, info] of Object.entries(pins.mirrors)) {
  assert.match(repo, /^[\w.-]+\/[\w.-]+$/, 'cada mirror key debe ser un repo GitHub');
  assert.equal(info.status, 'unavailable', 'solo se declaran upstreams no disponibles');
  assert.ok(Array.isArray(info.alternatives), 'las alternativas deben ser una lista');
  assert.ok(!info.alternatives.includes(repo), 'un upstream caido no puede ser su propio mirror');
  for (const alt of info.alternatives) {
    assert.match(alt, /^[\w.-]+\/[\w.-]+$/, 'cada alternativa debe ser un repo GitHub');
    assert.ok(repo !== alt, 'la alternativa debe differir del original');
    assert.ok(!Object.keys(pins.mirrors).includes(alt), 'la alternativa no debe ser a su vez un upstream declarado caido');
  }
}
assert.ok(pins.mirrors['blackbearreloaded/ps5-opengl'].alternatives.length >= 2, 'ps5-opengl necesita al menos dos mirrors porque el SDK binario solo existe en releases');
assert.ok(pins.mirrors['blackbearreloaded/ps5-homebrew-ui'].alternatives.includes('LedyBacer/ps5-homebrew-ui'), 'la plantilla hui-gl debe tener mirror');

// server.ps1: helpers, fallback y hooks.
assert.match(server, /function GetPS5HSMirrorAlternatives\(/, 'server.ps1 debe resolver mirrors del pin');
assert.match(server, /function SeedProjectOpenGlSdkCache\(/, 'server.ps1 debe sembrar el cache offline del SDK');
assert.match(server, /function GetPS5HSToolchainPackSdkArchive\b/, 'server.ps1 debe inspeccionar el pack local');
assert.match(server, /\$candidateRepos=@\(\[string\]\$Entry\.repo\)\+\(GetPS5HSMirrorAlternatives/, 'el clon git debe intentar el upstream y luego los mirrors');
assert.match(server, /mirrorRepository=\$usedRepo/, 'el clon con mirror debe registrar la fuente usada');
assert.match(server, /toolchainHealth/, 'GetStatus debe exponer la salud de toolchains');
assert.match(server, /upstreamUnavailable=\(GetPS5HSUpstreamUnavailable/, 'el estado de cada SDK debe indicar si su upstream cayo');
assert.ok(
  server.includes("ApplyPS5HSSdkMirrorChainPatch -ProjectRoot $projectRoot -Policy $policy -Backend $backend") &&
  server.includes("ApplyPS5HSSdkMirrorChainPatch -ProjectRoot $projectRoot -Policy $policy -Backend 'opengl-ui'"),
  'el parche de mirrors debe engancharse tanto en la creacion como en el build de un proyecto existente');
assert.match(server, /SeedProjectOpenGlSdkCache \$projectRoot/, 'la siembra offline debe ejecutarse antes de compilar');

// Politica de modificaciones: nueva clave y funcion, con registro de auditoria.
assert.match(policy, /'allowUpstreamSdkMirrorPatch',/, 'la politica PowerShell debe registrar la clave del parche de mirrors');
assert.match(policy, /function ApplyPS5HSSdkMirrorChainPatch\b/, 'la politica debe implementar el parche');
assert.match(policy, /'apply-sdk-mirror-chain'/, 'el parche debe grabar su operacion en la auditoria');
assert.match(policy, /PS5HS_MIRROR_CHAIN/, 'el parche debe marcar el script modificado para idempotencia');
assert.match(policyJs, /key:'allowUpstreamSdkMirrorPatch'/, 'el catalogo cliente debe exponer la nueva clave');
assert.match(policyJs, /backends:\['opengl-ui','hui-gl'\]/, 'la clave aplica a los flujos OpenGL');
assert.ok(!/required:\s*true/.test(policyJs.match(/key:'allowUpstreamSdkMirrorPatch'[^}]+/)[0]), 'el parche de mirrors es opcional, no un requisito del pipeline');

// app.js: UI de salud y consentimiento.
assert.match(app, /MIRROR DISPONIBLE/, 'el panel SDK debe mostrar mirrors disponibles');
assert.match(app, /PACK SDK/, 'el dock debe mostrar el estado del pack local');
assert.match(app, /allowUpstreamSdkMirrorPatch/, 'el flujo de build hui-gl debe ofrecer el nuevo permiso');
assert.match(app, /toolchain-pins\.json/, 'la UI debe documentar el manifiesto de pins');

// Packer: debe verificar el pin y respetar el manifiesto.
assert.match(packer, /Get-FileHash -LiteralPath \$Path -Algorithm SHA256/, 'el packer debe verificar SHA-256');
assert.match(packer, /toolchain-pins\.json/, 'el packer debe leer el manifiesto de pins');
assert.match(packer, /manifest\.json/, 'el packer debe emitir un manifiesto del pack');
assert.match(packer, /Compress-Archive/, 'el packer debe poder crear el respaldo ZIP opcional');
assert.doesNotMatch(packer, /Remove-Item.*toolchains/, 'el packer jamas debe borrar toolchains');

console.log('PASS toolchain pins: manifest, mirrors, server hooks, policy key, UI and packer contracts.');
