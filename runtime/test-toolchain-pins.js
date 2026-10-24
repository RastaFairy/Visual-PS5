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
const payloadSdkInstaller = fs.readFileSync(path.join(root, 'toolchains', 'PS5_PayloadSDK', 'platform', 'tools', 'setup-sdk.sh'), 'utf8');
const dusklightSdkSetup = fs.readFileSync(path.join(root, 'toolchains', 'PS5_Dusklight', 'ps5', 'tools', 'setup-sdk.sh'), 'utf8');
const pacbrewDeps = fs.readFileSync(path.join(root, 'toolchains', 'ps5-homebrew-ui', 'tools', 'setup-pacbrew-dependencies.sh'), 'utf8');
const testDeps = fs.readFileSync(path.join(root, 'toolchains', 'ps5-homebrew-ui', 'tools', 'setup-test-dependencies.sh'), 'utf8');
const openGlSources = fs.readFileSync(path.join(root, 'toolchains', 'ps5-opengl', 'tools', 'fetch-sources.py'), 'utf8');
const packageWorkflow = fs.readFileSync(path.join(root, '.github', 'workflows', 'package-self-contained-ide.yml'), 'utf8');
const sdkBuildWorkflow = fs.readFileSync(path.join(root, '.github', 'workflows', 'build-recovered-opengl-sdk.yml'), 'utf8');

const windowsZipSafeFreeBsdHeaders = [
  '_semaphore.h', 'aio.h', 'errno.h', 'fcntl.h', 'float.h',
  'floatingpoint.h', 'linker_set.h', 'ncurses.h', 'poll.h', 'sched.h',
  'stdarg.h', 'stdatomic.h', 'stdint.h', 'syslog.h', 'ucontext.h'
];
const freebsdIncludeDirs = [
  path.join(root, 'toolchains', 'PS5_PayloadSDK-pinned-b83202be', 'include', 'freebsd'),
  path.join(root, 'toolchains', 'PS5_PayloadSDK-pinned-611893fc', 'include', 'freebsd')
];
for (const freebsdIncludeDir of freebsdIncludeDirs) {
  for (const name of windowsZipSafeFreeBsdHeaders) {
    const header = fs.readFileSync(path.join(freebsdIncludeDir, name), 'utf8');
    assert.ok(header.length > 100, `Windows source ZIP must contain the actual ${name} header, not a symbolic-link placeholder`);
  }
}

// Manifiesto de integridad: se conserva para verificar artefactos colocados localmente.
assert.equal(pins.schema, 'ps5hs-toolchain-pins', 'toolchain-pins.json debe declarar su esquema');
assert.equal(pins.version, 1, 'la version del manifiesto debe ser 1');
assert.ok(pins.artifacts && pins.artifacts['ps5-opengl-sdk'], 'el manifiesto debe fijar el artefacto ps5-opengl-sdk');
assert.match(String(pins.artifacts['ps5-opengl-sdk'].version), /^1\.\d+\.\d+$/, 'la version del SDK debe ser semver');
assert.match(pins.artifacts['ps5-opengl-sdk'].archive.sha256, /^[0-9a-f]{64}$/, 'el archivo debe tener un SHA-256 fijado');
assert.match(pins.artifacts['ps5-opengl-sdk'].sdkManifest.sha256, /^[0-9a-f]{64}$/, 'el manifest interno debe tener SHA-256');
const bundledRuntimeArtifacts = [
  ['ps5-payload-sdk', 'toolchains/artifacts/ps5-payload-sdk.zip', '8cfbc7cd5811e719eb4f0c47eea668d3dc7b40bc8ab11c4a5031d40c23ec02da'],
  ['zlib', 'toolchains/artifacts/zlib-1.3.2.tar.gz', 'bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16'],
  ['pacbrew', 'toolchains/artifacts/ps5-payload-dev-v0.40.2.tar.gz', 'a85f65de418a8e6a898c6c3e3c870d50fff7618a200e4dd59ea9692af6ecec4d'],
  ['googletest', 'toolchains/artifacts/googletest-1.17.0.tar.gz', '65fab701d9829d38cb77c14acdc431d2108bfdbf8979e40eb8ae567edf10b27c']
];
const payloadSdkSourcePins = pins.sourcePins.ps5PayloadSdk.revisions;
const vulkanSdkSource = JSON.parse(fs.readFileSync(path.join(root, payloadSdkSourcePins.vulkan.localPath, '.ps5hs-source.json'), 'utf8'));
const dusklightSdkSource = JSON.parse(fs.readFileSync(path.join(root, payloadSdkSourcePins.dusklight.localPath, '.ps5hs-source.json'), 'utf8'));
assert.equal(vulkanSdkSource.sourceCommit, payloadSdkSourcePins.vulkan.commit, 'el snapshot Vulkan debe estar en el commit exacto del manifiesto');
assert.equal(dusklightSdkSource.sourceCommit, payloadSdkSourcePins.dusklight.commit, 'el snapshot Dusklight debe estar en el commit exacto del manifiesto');
assert.equal(dusklightSdkSource.materializedSymlinkCount, windowsZipSafeFreeBsdHeaders.length, 'el snapshot Dusklight debe materializar las cabeceras enlazadas de Windows a WSL');
assert.match(vulkanDeps, new RegExp(`sdk_revision=${payloadSdkSourcePins.vulkan.commit}`), 'Vulkan debe conservar su pin de SDK propio');
assert.match(dusklightSdkSetup, new RegExp(`sdk_revision=${payloadSdkSourcePins.dusklight.commit}`), 'Dusklight debe conservar su pin de SDK propio');
assert.ok(dusklightSdkSetup.includes('PS5_PayloadSDK-pinned-611893fc'), 'Dusklight debe resolver el snapshot fijado aunque la copia no tenga historial Git');
assert.ok(vulkanDeps.includes('install -m 0644 "$sdk_fork/platform/tools/setup-sdk.sh"'), 'Vulkan debe usar el instalador local con soporte offline para el snapshot exportado');
assert.ok(payloadSdkInstaller.includes('PS5HS_LOCAL_TOOLCHAINS_ONLY:-0'), 'el instalador Payload SDK debe respetar modo local-only');
assert.ok(payloadSdkInstaller.includes('toolchains_root/artifacts/ps5-payload-sdk.zip'), 'el instalador Payload SDK debe usar el ZIP verificado empaquetado');
assert.ok(payloadSdkInstaller.includes('sha256sum --check --strict'), 'el instalador Payload SDK debe validar el ZIP local antes de extraerlo');
for (const [name, localPath, expectedSha256] of bundledRuntimeArtifacts) {
  const pin = pins.artifacts[name];
  assert.ok(pin, `el manifiesto debe fijar la dependencia local ${name}`);
  assert.equal(pin.localPath, localPath, `${name} debe usar su ruta local de distribución`);
  assert.equal(pin.file, path.basename(localPath), `${name} debe usar el nombre de archivo esperado`);
  assert.equal(pin.archive.sha256, expectedSha256, `${name} debe mantener el SHA-256 del bootstrapper`);
  assert.match(pin.sourceUrl, /^https:\/\//, `${name} debe documentar la fuente usada solo para empaquetado`);
}
assert.ok(openGlNativeDeps.includes(`sdk_hash="${pins.artifacts['ps5-payload-sdk'].archive.sha256}"`), 'OpenGL debe usar el pin payload declarado');
assert.ok(nativeCppDeps.includes(`sdk_hash="${pins.artifacts['ps5-payload-sdk'].archive.sha256}"`), 'Native C++ debe usar el pin payload declarado');
for (const [name, script] of [['OpenGL native', openGlNativeDeps], ['Native C++', nativeCppDeps], ['Vulkan', vulkanDeps]]) {
  assert.ok(script.includes(`zlib_hash="${pins.artifacts.zlib.archive.sha256}"`), `${name} debe usar el pin zlib declarado`);
}
assert.ok(pacbrewDeps.includes(`hash=${pins.artifacts.pacbrew.archive.sha256}`), 'PacBrew debe usar el hash del manifiesto');
assert.ok(testDeps.includes(`hash="${pins.artifacts.googletest.archive.sha256}"`), 'GoogleTest debe usar el hash del manifiesto');
assert.ok(packageWorkflow.includes('run-id: ${{ steps.sdk-run.outputs.run_id }}'), 'el empaquetado debe elegir dinámicamente el artefacto SDK y no fijar un run ID efímero');
assert.ok(packageWorkflow.includes('runtime-artifact-pins.tsv'), 'el empaquetado debe leer los pins de artefactos desde el manifiesto');
assert.ok(packageWorkflow.includes('toolchains/artifacts'), 'el ZIP debe incluir los artefactos runtime bajo toolchains/artifacts');
for (const [name] of bundledRuntimeArtifacts) {
  assert.ok(packageWorkflow.includes(name), `el empaquetado debe incluir la dependencia fijada ${name}`);
}
assert.ok(packageWorkflow.includes('sha256sum --check --strict'), 'cada archivo runtime descargado en CI debe verificarse contra su hash');
assert.ok(packageWorkflow.includes('Visual-PS5-offline-build-recovery-20261021-with-runtime-deps.zip'), 'el paquete generado debe identificarse como la edición con dependencias runtime');
assert.doesNotMatch(packageWorkflow, /run-id:\s*\d+/, 'el empaquetado no debe depender de un ID fijo de ejecución que pueda caducar');
assert.ok(packageWorkflow.includes('select(.status != "completed")'), 'el empaquetado debe esperar si hay una reconstrucción del SDK en curso y evitar seleccionar un artefacto antiguo');
assert.ok(packageWorkflow.includes('sleep 15'), 'la selección del SDK debe reconsultar las ejecuciones activas, no adelantarse a su resultado');
assert.ok(packageWorkflow.includes('select(.status == "completed" and .conclusion == "success")'), 'el empaquetado no debe elegir artefactos de ejecuciones fallidas del SDK');
assert.ok(sdkBuildWorkflow.includes('tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf -'), 'el archivo SDK debe normalizar orden, fecha y propiedad para obtener un SHA-256 reproducible');
assert.ok(sdkBuildWorkflow.includes('gzip -n -9'), 'el empaquetado SDK debe quitar fecha/nombre variables de la cabecera gzip');
assert.ok(sdkBuildWorkflow.includes('cmp --silent "$RUNNER_TEMP/$name.tar.gz" "$RUNNER_TEMP/$name.repeat.tar.gz"'), 'el workflow debe verificar que dos empaquetados consecutivos sean idénticos');
assert.ok(sdkBuildWorkflow.includes('test "$manifest_sha" = "$expected_manifest_sha"'), 'el workflow debe fallar si el manifiesto interno no coincide con el pin');



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
assert.doesNotMatch(server, /PS5HS_ALLOW_PINNED_SDK_DOWNLOAD=1/, 'la compilación de títulos debe permanecer local-only incluso para el SDK OpenGL');
assert.match(server, /PS5_OPENGL_PREFIX=' \+ \(BashQuote \$openglPrefix\)/, 'el pipeline debe inyectar explícitamente el prefijo SDK al Makefile del título');
assert.ok(server.includes('$legacyRequiredFiles') && server.includes('$legacyParam.titleId') && server.includes('Proyecto antiguo sin manifiesto') && server.includes('Move-Item -LiteralPath $targetCandidate -Destination $replacementBackupPath'), 'legacy visual projects must be identity-checked and backed up before regeneration');
assert.match(openglSdkFetcher, /toolchains_root/, 'el SDK OpenGL debe resolver toolchains/ de forma explícita');
assert.doesNotMatch(openglSdkFetcher, /blackbearreloaded\/ps5-opengl\/releases|api\.github\.com\/repos\/blackbearreloaded\/ps5-opengl/, 'el SDK no debe llamar los endpoints upstream que devuelven 404');
assert.match(openglSdkFetcher, /No se consulta Internet/, 'la resolución del SDK debe ser local-only y no depender de la release upstream caída');
assert.match(openglSdkFetcher, /Usa el paquete del IDE que incluye el SDK OpenGL 1\.0\.2/, 'si falta el artefacto local debe explicar que debe incluirse en el paquete');
assert.doesNotMatch(openglSdkFetcher, /release_api=|browser_download_url/, 'el resolver no debe enumerar assets remotos');
assert.match(openglSdkFetcher, /local_prefixes=\(/, 'el resolvedor verifica candidatos de SDK que ya están extraídos localmente');
assert.match(openglSdkFetcher, /archive="\$sdk_root\/ps5-opengl-sdk-\$version\.tar\.gz"/, 'el SDK local debe leerse desde la ruta empaquetada del IDE');
assert.ok(openglSdkFetcher.includes(`archive_sha256=${pins.artifacts['ps5-opengl-sdk'].archive.sha256}`), 'el resolvedor OpenGL debe compartir el SHA-256 del tarball definido en el manifiesto');
assert.doesNotMatch(openglSdkFetcher, /PS5HS_ALLOW_PINNED_SDK_DOWNLOAD|direct_url=|curl --fail|wget --quiet/, 'el resolver no debe intentar descargas externas');
assert.equal(openglSdkFetcher.includes('curl'), false, 'el SDK OpenGL no debe contener un cliente HTTP');
assert.equal(openglSdkFetcher.includes('wget'), false, 'el SDK OpenGL no debe usar wget');
assert.match(openglSdkFetcher, /"\$root\/\.deps\/ps5-opengl\/ps5-opengl-sdk-\$version\/sdk"/, 'se puede reutilizar la caché local anterior solo si verify_prefix confirma el manifiesto exacto');
assert.match(openglSdkFetcher, /sha256sum --check --strict --status/, 'el archivo se debe verificar antes de extraerlo o promoverlo');
assert.match(openglSdkFetcher, /local_prefixes=\(/, 'el SDK debe buscar una copia ya extraída dentro de toolchains/');
assert.match(openglSdkFetcher, /verify_prefix\(\) \{/, 'el SDK extraído debe verificarse contra la identidad fijada');
assert.ok(openglSdkFetcher.includes(`manifest_sha256=${pins.artifacts['ps5-opengl-sdk'].sdkManifest.sha256}`), 'el resolvedor OpenGL debe compartir el SHA-256 del manifiesto interno fijado');
assert.match(openglSdkFetcher, /local-only: falta \$archive/, 'si no hay tarball local ni copia extraída válida, el error debe explicitar el bloqueo offline');
assert.match(openglSdkFetcher, /sdk_root="\$toolchains_root\/ps5-opengl-sdk"/, 'el tarball del SDK se guarda bajo la raíz local toolchains configurada');
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



// ZIP -> checkout helper: only pinned files, SHA-256 verification, no network, no clobbering.
const artifactImporter = fs.readFileSync(path.join(__dirname, 'Import-PackagedToolchainArtifacts.ps1'), 'utf8');
assert.ok(artifactImporter.includes("@('ps5-opengl-sdk', 'ps5-payload-sdk', 'zlib', 'pacbrew', 'googletest')"), 'the importer must cover all five locally pinned runtime archives');
assert.match(artifactImporter, /toolchain-pins\.json/, 'the importer must read the same pin manifest used by the build');
assert.match(artifactImporter, /OpenRead/, 'the importer must read directly from the provided distribution ZIP');
assert.match(artifactImporter, /GetEntry\(\$entryName\)/, 'the importer must address only exact pinned ZIP entries');
assert.match(artifactImporter, /Get-FileHash -LiteralPath \$stagedPath -Algorithm SHA256/, 'the importer must verify each staged archive');
assert.match(artifactImporter, /No se sobrescribe el archivo existente/, 'the importer must refuse to replace mismatched local files');
assert.match(artifactImporter, /\[IO\.File\]::Move/, 'the importer must promote verified copies atomically');
assert.doesNotMatch(artifactImporter, /Invoke-WebRequest|Invoke-RestMethod|\bcurl\b|\bwget\b|git clone/i, 'the importer must be strictly local-only');

console.log('PASS toolchain pins: local-only source resolution, vendor manifests, integrity pins, policy and packer contracts.');
