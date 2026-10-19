'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const server = fs.readFileSync(path.join(__dirname, 'server.ps1'), 'utf8');
const allowedMatch = server.match(/\$allowed\s*=\s*@\(([^)]*)\)/i);
assert.ok(allowedMatch, 'ServeStatic allowlist must be declared in runtime/server.ps1');
const allowed = new Set([...allowedMatch[1].matchAll(/'([^']+)'/g)].map(match => match[1]));
const localScripts = [...html.matchAll(/<script\b[^>]*\bsrc=["']([^"']+)["'][^>]*>/gi)]
  .map(match => match[1].split('?')[0])
  .filter(src => !/^(?:[a-z]+:)?\/\//i.test(src) && !src.startsWith('/'));
assert.ok(localScripts.length, 'index.html must declare local script assets');
for (const src of localScripts) {
  assert.ok(fs.existsSync(path.join(root, src)), `Script file must exist: ${src}`);
  assert.ok(allowed.has(src), `ServeStatic must allow script requested by index.html: ${src}`);
}
console.log(`PASS static assets: all ${localScripts.length} local scripts exist and are served by the allowlist.`);
