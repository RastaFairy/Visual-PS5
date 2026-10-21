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
const openglSdkFetcher = fs.readFileSync(path.join(root, 'toolchains', 'ps5-homebrew-ui', 'tools', 'fetch-opengl-sdk.sh'), 'utf8');
const openGlNativeDeps = fs.readFileSync(path.join(root, 'toolchains', 'ps5-homebrew-ui', 'tools', 'setup-native-dependencies.sh'), 'utf8');
const nativeCppDeps = fs.readFileSync(path.join(root, 'toolchains', 'ps5-native-app-boilerplate', 'tools', 'setup-native-dependencies.sh'), 'utf8');
const vulkanDeps = fs.readFileSync(path.join(root, 'toolchains', 'PS5_Vulkan', 'tools', 'setup-native-dependencies.sh'), 'utf8');
const pacbrewDeps = fs.readFileSync(path.join(root, 'toolchains', 'ps5-homebrew-ui', 'tools', 'setup-pacbrew-dependencies.sh'), 'utf8');
const testDeps = fs.readFileSync(path.join(root, 'toolchains', 'ps5-homebrew-ui', 'tools', 'setup-test-dependencies.sh'), 'utf8');
const openGlSources = fs.readFileSync(path.join(root, 'toolchains', 'ps5-opengl', 'tools', 'fetch-sources.py'), 'utf8');

const windowsZipSafeFreeBsdHeaders = [
  '_semaphore.h', 'aio.h', 'errno.h', 'fcntl.h', 'float.h',
  'floatingpoint.h', 'linker_set.h', 'ncurses.h', 'poll.h', 'sched.h',
  'stdarg.h', 'stdatomic.h', 'stdint.h', 'syslog.h', 'ucontext.h'
];
const freebsdIncludeDir = path.join(root, 'toolchains', 'PS5_PayloadSDK-pinned-b83202be', 'include', 'freebsd');
for (const name of windowsZipSafeFreeBsdHeaders) {
  const header = fs.readFileSync(path.join(freebsdIncludeDir, name), 'utf8');
  assert.ok(header.length > 100, `Windows source ZIP must contain the actual ${name} header, not a symbolic-link placeholder`);
}

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
assert.match(server, /No se ha consultado GitHub, probado mirrors ni descargado/, 'si falta una copia, se debe explicar que no hay fallback de red');
assert.doesNotMatch(server, /winget install|--install -d Debian/, 'el asistente solo puede diagnosticar; no instala requisitos por Internet');
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
assert.doesNotMatch(server, /A Homebrew Studio OpenGL project has its own supported Windows entry point/, 'el build visual no debe saltarse la preparación compartida de dependencias solo por existir build.ps1');
assert.match(server, /Resolviendo SDK OpenGL 1\.0\.2/, 'el pipeline debe resolver el SDK precompilado fijado antes de compilar el título');
assert.doesNotMatch(server, /\$sdkCmd\s*=.*make sdk-gl46/, 'el IDE no debe intentar reconstruir Mesa/PSBC desde una instantánea sin third_party/');
assert.match(server, /PS5HS_ALLOW_PINNED_SDK_DOWNLOAD=1/, 'solo la recuperación del SDK fijado tiene una excepción explícita de red');
assert.match(server, /PS5_OPENGL_PREFIX=' \+ \(BashQuote \$openglPrefix\)/, 'el pipeline debe inyectar explícitamente el prefijo SDK al Makefile del título');
assert.ok(server.includes('$legacyRequiredFiles') && server.includes('$legacyParam.titleId') && server.includes('Proyecto antiguo sin manifiesto') && server.includes('Move-Item -LiteralPath $targetCandidate -Destination $replacementBackupPath'), 'legacy visual projects must be identity-checked and backed up before regeneration');
assert.match(openglSdkFetcher, /toolchains_root/, 'el SDK OpenGL debe resolver toolchains/ de forma explícita');
assert.match(openglSdkFetcher, /direct_url="https:\/\/github\.com\/blackbearreloaded\/ps5-opengl\/releases\/download\/v\$version\/ps5-opengl-sdk-\$version\.tar\.gz"/, 'el SDK debe probar primero la URL directa del asset fijado para no depender de la API');
assert.ok(openglSdkFetcher.indexOf('direct_url=') < openglSdkFetcher.indexOf('release_api='), 'la descarga debe intentar el asset fijado antes de consultar la API que puede devolver 404');
assert.match(openglSdkFetcher, /El asset de URL fija no respondió correctamente/, 'si el asset directo no existe debe registrarse el fallo y probar la alternativa');
assert.match(openglSdkFetcher, /api\.github\.com\/repos\/blackbearreloaded\/ps5-opengl\/releases\/tags\/v\$version/, 'el SDK debe descubrir sus assets en la API del release oficial fijado');
assert.match(openglSdkFetcher, /name\.startswith\("ps5-opengl-sdk-"\) and name\.endswith\("\.tar\.gz"\)/, 'el resolver debe inspeccionar los nombres reales de los assets, no asumir uno');
assert.match(openglSdkFetcher, /browser_download_url/, 'cada candidato debe venir de la metadata oficial del release');
assert.match(openglSdkFetcher, /archive_sha256=30d8e51dd062739b629346102be5932728ba714bc50b1bdcdf08306c8843d9a4/, 'el archivo descargado debe usar la huella SHA-256 fijada');
assert.match(openglSdkFetcher, /PS5HS_ALLOW_PINNED_SDK_DOWNLOAD:-0/, 'la descarga se activa mediante un permiso explícito');
assert.match(openglSdkFetcher, /sha256sum --check --strict --status/, 'el archivo se debe verificar antes de extraerlo o promoverlo');
assert.match(openglSdkFetcher, /local_prefixes=\(/, 'el SDK debe buscar una copia ya extraída dentro de toolchains/');
assert.match(openglSdkFetcher, /verify_prefix\(\) \{/, 'el SDK extraído debe verificarse contra la identidad fijada');
assert.match(openglSdkFetcher, /manifest_sha256=0d432edc9d648d6e0cccb4d5eb3db8484f10ba4b075b5ccf23edda3251b66360/, 'el manifiesto del SDK debe coincidir con el pin exacto');
assert.match(openglSdkFetcher, /falta el tarball fijado o un SDK/, 'si no hay tarball ni copia extraída válida, el error debe explicitar el bloqueo offline');
assert.match(openglSdkFetcher, /archive="\$toolchains_root\/ps5-opengl-sdk\/ps5-opengl-sdk-\$version\.tar\.gz"/, 'el tarball del SDK se guarda una sola vez bajo la raíz local toolchains configurada');
for (const [name, script] of [['OpenGL native', openGlNativeDeps], ['Native C++', nativeCppDeps], ['Vulkan', vulkanDeps]]) {
  assert.match(script, /PS5HS_LOCAL_TOOLCHAINS_ONLY:-0/, name + ' debe respetar el modo local-only');
  assert.match(script, /toolchains\/artifacts\/zlib-\$zlib_version\.tar\.gz/, name + ' debe pedir zlib local si falta la caché');
}
assert.match(openGlNativeDeps, /toolchains\/artifacts\/ps5-payload-sdk\.zip/, 'OpenGL debe pedir el SDK fijado en toolchains/artifacts');
assert.match(nativeCppDeps, /toolchains\/artifacts\/ps5-payload-sdk\.zip/, 'Native C++ debe pedir el SDK fijado localmente');
assert.match(pacbrewDeps, /PS5HS_LOCAL_TOOLCHAINS_ONLY:-0/, 'PacBrew debe detenerse si falta su artefacto local');
assert.match(pacbrewDeps, /toolchains\/artifacts\/ps5-payload-dev-\$version\.tar\.gz/, 'PacBrew debe buscar su archivo solo en toolchains/artifacts');
assert.match(testDeps, /PS5HS_LOCAL_TOOLCHAINS_ONLY:-0/, 'GoogleTest debe respetar el modo local-only');
assert.match(testDeps, /toolchains\/artifacts\/googletest-\$version\.tar\.gz/, 'GoogleTest debe buscar su archivo solo en toolchains/artifacts');
assert.match(openGlSources, /PS5HS_LOCAL_TOOLCHAINS_ONLY/, 'el sincronizador de fuentes OpenGL debe bloquear recuperación de red en modo local');


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
assert.match(packer, /networkAccess = \$false/, 'the packer must declare that it does not access the network');
assert.ok(packer.includes("$sdkDir = Join-Path $toolchainsRoot 'ps5-opengl-sdk'"), 'the SDK must be read from toolchains/');
assert.equal(packer.includes('Invoke-WebRequest'), false, 'the packer must not download archives');
assert.equal(packer.includes('https://'), false, 'the packer must not contain remote URLs');
assert.equal(packer.includes('.urls'), false, 'the packer must not iterate remote URL lists');
assert.doesNotMatch(packer, /Remove-Item.*toolchains/, 'the packer must never delete toolchains');

console.log('PASS toolchain pins: local-only source resolution, vendor manifests, integrity pins, policy and packer contracts.');
