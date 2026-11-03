'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const server = fs.readFileSync(path.join(__dirname, 'server.ps1'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const allowedMatch = server.match(/\$allowed\s*=\s*@\(([^)]*)\)/i);
assert.ok(allowedMatch, 'static-serving allowlist must exist');
const allowed = new Set([...allowedMatch[1].matchAll(/'([^']+)'/g)].map(match => match[1]));
for (const match of html.matchAll(/<script\b[^>]*\bsrc=["']([^"']+)["'][^>]*>/gi)) {
  const src = match[1].split('?')[0];
  if (/^(?:[a-z]+:)?\/\//i.test(src) || src.startsWith('/')) continue;
  assert.ok(fs.existsSync(path.join(root, src)), `script exists: ${src}`);
  assert.ok(allowed.has(src), `server serves script: ${src}`);
}
const called = new Set();
for (const match of app.matchAll(/\bapi\(\s*(['"`])([^'"`]+?)\1/g)) {
  const route = match[2].split('?')[0].split('${')[0];
  if (route) called.add(route);
}
for (const apiPath of called) {
  if (apiPath === 'build-jobs/') {
    assert.match(server, /-and \$path -match '\^\/api\/build-jobs\/\[a-f0-9\]\{32\}\$'/,
      'dynamic build-job poll must be routed as a GET endpoint');
    continue;
  }
  const exactSwitch = `'/api/${apiPath}'`;
  assert.ok(server.includes(exactSwitch) || server.includes(`'/api/${apiPath}/start'`) ||
    server.includes(`'/api/${apiPath}'`) || (apiPath === 'status' && server.includes("$path -eq '/api/status'")) ||
    (apiPath === 'integrations' && server.includes("$path -eq '/api/integrations'")) ||
    (apiPath === 'projects' && server.includes("$path -eq '/api/projects'")) ||
    (apiPath === 'native-projects' && server.includes("$path -eq '/api/native-projects'")) ||
    (apiPath === 'files' && server.includes("'/api/files'")),
    `frontend API path must have a server route: ${apiPath}`);
}
assert.match(app, /function openSetup\(/);
assert.match(app, /text:'Configurar dependencias'.*openSetup\(\)/s,
  'environment setup must be reachable from the UI');
assert.match(server, /offlineEnvironment=\$offlineEnvironment/, 'status must expose the offline installation and Ubuntu verification state');
assert.match(server, /GetPS5HSOfflineBackendReadiness/, 'the server must read the declared offline backend readiness matrix');
assert.match(server, /buildStoppedBeforeMutation=\$true;offlineStatus=\$offlineBackend\.status/, 'a bundled build must stop before project mutation when its backend is not validated offline');
assert.match(app, /Instalación offline disponible/, 'the setup dialog must direct clean hosts to the bundled offline installer');
assert.match(app, /Preparación offline por backend/, 'the setup dialog must show backend readiness rather than generic download instructions');
assert.match(app, /function openProject(?:\([^)]*\))[\s\S]*const dialogRevision=modalRevision/, 'project browser must capture the dialog context');
assert.match(app, /function saveProject\(\)[\s\S]*snapshotJson=JSON\.stringify\(data\)/, 'save must preserve the serialized snapshot and not mark subsequent edits clean');
assert.match(app, /function openIntegrationSettings\(\)[\s\S]*revisionAtStart=modalRevision/, 'async settings discovery must not replace a newer modal');
assert.match(app, /api\('console\/deploy',\{host,localFolder:folder,remoteFolder:remote/, 'FTP deploy must send localFolder/remoteFolder as the server contract expects');
assert.match(server, /'\/api\/console\/deploy' \{[\s\S]{0,400}\$body\.localFolder[\s\S]{0,200}\$body\.remoteFolder/, 'server deploy route must read localFolder/remoteFolder');
assert.match(app, /api\('console\/klog-stop'/, 'stopping the klog poll must release the server-side socket');
assert.ok(server.includes("'/api/console/klog-stop'"), 'server must expose /api/console/klog-stop');
assert.match(html, /id="consoleStopBtn"/, 'console view must offer a stop control');
assert.match(app, /\$\('#consoleStopBtn'\)\.addEventListener/, 'stop control must be wired');
assert.match(app, /\$\('#consoleDownloadBtn'\)\.addEventListener/, 'klog download button must be wired');
assert.match(app, /NON_UI_BACKEND_NOTICE/, 'non-canvas backends must warn immediately on selection');
assert.ok(server.includes("'/api/files'"), 'server must expose the project file explorer endpoint');
assert.ok(server.includes("'/api/files/search'"), 'server must expose project-wide search');
assert.match(app, /api\('files/, 'file explorer must call the files API');
assert.ok(!server.includes("'/api/build-native' {"), 'dead synchronous /api/build-native route must stay removed');
assert.ok(!server.includes("'/api/build-visual-native' {"), 'dead synchronous /api/build-visual-native route must stay removed');
const version = (fs.readFileSync(path.join(root, 'VERSION.txt'), 'utf8').match(/Version:\s*(\S+)/) || [])[1];
assert.ok(version, 'VERSION.txt must declare a version');
assert.ok(html.includes(`?v=${version}`), 'index.html cache-busting must match VERSION.txt');
assert.ok(app.includes(`v${version}`), 'app.js footer version must match VERSION.txt');
assert.match(fs.readFileSync(path.join(root, 'docs/CHANGELOG.md'), 'utf8'),
  new RegExp(`^## ${version.replace(/\./g, '\\.')}`, 'm'), 'CHANGELOG.md must have an entry for the current version');
assert.match(html, /id="themeToggle"/, 'theme toggle must exist in the topbar');
assert.match(app, /I18N_STRINGS/, 'i18n dictionary must be present');
assert.match(html, /data-i18n=/, 'static UI must carry i18n keys');
assert.match(html, /id="uiLangSelect"/, 'language selector must exist');
assert.match(app, /SHAPE_VERTS/, 'AGC vertex budget estimator must run in Diagnostics');
assert.match(server, /function Test-PS5HSProjectModel/, 'server must validate the project model');
assert.match(server, /Test-PS5HSProjectModel \$body\.project/, 'the save route must validate the model');
assert.match(app, /payloadBuildProfile/, 'payload build dialog must expose the build profile');
assert.match(html, /ps5hs-i18n\.js/, 'the i18n engine must load before app.js');
assert.match(html, /ps5hs-ui-theme\.js/, 'the theme engine must load before app.js');
assert.ok(!app.includes('I18N_STRINGS'), 'i18n dictionary must live in runtime/ps5hs-i18n.js, not inline in app.js');
const template = fs.readFileSync(path.join(__dirname, 'templates/ps5link-platform-game.c'), 'utf8');
assert.match(template, /scePthreadCreate/, 'the AGC template must run audio in its own thread');
assert.match(template, /audio_request_sfx/, 'SFX must be handed to the audio thread through the mutex-protected queue');
for (const moduleFile of ['server-console.ps1', 'server-status.ps1', 'server-model.ps1', 'server-project-files.ps1', 'server-build-config.ps1']) {
  assert.ok(fs.existsSync(path.join(__dirname, moduleFile)), `server module must exist: ${moduleFile}`);
  assert.match(server, new RegExp(moduleFile.replace(/\./g, '\\.')), `server.ps1 must dot-source ${moduleFile}`);
}
console.log(`PASS API contracts: ${called.size} frontend API path families map to server handlers; static assets and version strings are consistent.`);
