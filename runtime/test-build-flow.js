'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const sharpStart = app.indexOf('const defaultHandler=c=>');
const sharpEnd = app.indexOf('case\'toggle\':', sharpStart);
assert.ok(sharpStart >= 0 && sharpEnd > sharpStart, 'Sharp button generator must remain connected to the component generator');
const sharpButtonBranch = app.slice(app.indexOf("case'button':", sharpStart), sharpEnd);
assert.match(sharpButtonBranch, /return action\?`new Button\(\$\{lab\}, \(\) => \{ \$\{action\} \}\)`:`new Button\(\$\{lab\}\)`;/,
  'Sharp generator must preserve a real no-action button as a widget and must not create an empty callback');
assert.match(app, /BUILD_LOG_STORAGE_KEY = 'ps5hs:diagnostic-log:v1'/, 'diagnostic log storage key must exist');
assert.match(app, /localStorage\.setItem\(BUILD_LOG_STORAGE_KEY,JSON\.stringify\(outputLines\)\)/, 'diagnostic log must persist across reloads');
assert.match(app, /function exportDiagnosticLog\(\)/, 'diagnostic log must be exportable');
assert.match(html, /id="exportBuildLogBtn"/, 'UI must expose an export-log control');
assert.match(html, /PS5HS early diagnostics/, 'a pre-app boot logger must exist so missing scripts and early startup failures remain diagnosable');
assert.match(html, /addEventListener\('unhandledrejection'/, 'uncaught async initialization errors must be logged');
assert.match(app, /window\.__PS5HS_BOOT_READY=true/, 'the app must declare startup complete only after event handlers and initial rendering are wired');
const bootScript = html.match(/<!-- PS5HS early diagnostics: runs before external scripts so failed startup is still observable\. -->\s*<script>([\s\S]*?)<\/script>/);
assert.ok(bootScript, 'the pre-app diagnostics script must be embedded before external resources');
const vm = require('node:vm');
new vm.Script(bootScript[1]);
const persisted = new Map();
const windowListeners = new Map();
const documentListeners = new Map();
class FakeElement {
  constructor(tag='div') { this.tagName=tag.toUpperCase(); this.children=[]; this.className=''; this.textContent=''; this.scrollTop=0; this.scrollHeight=0; this.id=''; }
  append(...items) { this.children.push(...items); this.scrollHeight=this.children.length; }
  remove() { this.removed=true; }
  get firstElementChild() { return this.children[0] || null; }
  closest(selector) { return selector==='#buildBtn'&&this.id==='buildBtn'||selector==='#exportBuildLogBtn'&&this.id==='exportBuildLogBtn' ? this : null; }
}
const bootWindow = {addEventListener:(name,handler)=>{const list=windowListeners.get(name)||[];list.push(handler);windowListeners.set(name,list);}};
const dockContent = new FakeElement();
const bootDocument = {
  addEventListener:(name,handler)=>{const list=documentListeners.get(name)||[];list.push(handler);documentListeners.set(name,list);},
  getElementById:id=>id==='dockContent'?dockContent:null,
  createElement:tag=>new FakeElement(tag)
};
const bootStorage = {getItem:key=>persisted.get(key)||null,setItem:(key,value)=>persisted.set(key,value)};
vm.runInNewContext(bootScript[1], {window:bootWindow,document:bootDocument,localStorage:bootStorage,Element:FakeElement,Date,JSON,String,Array,Math,URL,Blob});
windowListeners.get('error')[0]({target:bootWindow,filename:'app.js',lineno:17,colno:3,message:'Unexpected token'});
const compileClick = new FakeElement('button'); compileClick.id='buildBtn';
for (const handler of documentListeners.get('click')) handler({target:compileClick});
const bootEntries = JSON.parse(persisted.get('ps5hs:diagnostic-log:v1')||'[]');
assert.ok(bootEntries.some(entry=>entry.level==='ERROR'&&entry.text.includes('Unexpected token')), 'startup JavaScript errors must persist before app.js initializes');
assert.ok(bootEntries.some(entry=>entry.level==='ERROR'&&entry.text.includes('clic en Compilar')), 'a compile click must still leave a log if the main app never reaches event wiring');
assert.ok(dockContent.children.length>=2, 'startup errors must also be visible in the output dock before normal rendering exists');
assert.match(html, /application-version" content="1\.1\.19"/, 'visible app version must match the patched sources');
assert.doesNotMatch(html, /(?:app\.js|styles\.css|runtime\/[^" ]+)\?v=1\.1\.17/, 'the browser cache must not be pinned to stale 1.1.17 assets');
assert.doesNotMatch(app, /(?<!\$)\$\('#modalActions button'\)/, 'modal action buttons must be enumerated with the $$ array helper; a single-element $ lookup has no forEach (v1.1.17 regression)');
assert.doesNotMatch(app, /(?<!\$)\$\('[^']+'\);[A-Za-z_$][\w$]*\.forEach\(/, 'a querySelector result is a single element or null and must never be used with forEach');
assert.ok((app.match(/buttons=\$\$\('#modalActions button'\);buttons\.forEach\(\w+=>\w+\.disabled=true\)/g) || []).length >= 3, 'build confirmations must keep disabling modal action buttons through the $$ array helper');
const buildStart = app.indexOf('async function buildProject(){');
const preflight = app.indexOf('if(!isProjectOpen)', buildStart);
const clickLog = app.indexOf("buildLog(traceId,'Evento de compilación recibido por buildProject().');", buildStart);
assert.ok(buildStart >= 0 && clickLog > buildStart && preflight > clickLog, 'build request must be logged before early-return preflight checks');
assert.match(app, /Prevalidación \$\{index\+1\}\/\$\{errors\.length\}/, 'every static-analysis blocker must be written to the output log');
assert.doesNotMatch(app, /add\('error','Botón sin acción ejecutable'/, 'the explicit no-action setting must not block the entire build');
const nativeGenerator = fs.readFileSync(path.join(root, 'runtime/native-generator.js'), 'utf8');
assert.doesNotMatch(nativeGenerator, /El botón \$\{component\.id\} no tiene una acción ejecutable/, 'native C++ generation must not reject explicitly passive buttons');
console.log('PASS build flow: click-first persistent diagnostics, exportable log, preflight trace and passive button compatibility.');
