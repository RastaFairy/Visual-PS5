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
const called = new Set([...app.matchAll(/\bapi\(\s*['"]([^'"]+)['"]/g)].map(match => match[1]));
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
    (apiPath === 'native-projects' && server.includes("$path -eq '/api/native-projects'")),
    `frontend API path must have a server route: ${apiPath}`);
}
assert.match(app, /function openSetup\(/);
assert.match(app, /text:'Configurar dependencias'.*openSetup\(\)/s,
  'environment setup must be reachable from the UI');
assert.match(app, /function openProject(?:\([^)]*\))[\s\S]*const dialogRevision=modalRevision/, 'project browser must capture the dialog context');
assert.match(app, /function saveProject\(\)[\s\S]*snapshotJson=JSON\.stringify\(data\)/, 'save must preserve the serialized snapshot and not mark subsequent edits clean');
assert.match(app, /function openIntegrationSettings\(\)[\s\S]*revisionAtStart=modalRevision/, 'async settings discovery must not replace a newer modal');
console.log(`PASS API contracts: ${called.size} frontend API path families map to server handlers; static assets are resolvable.`);
