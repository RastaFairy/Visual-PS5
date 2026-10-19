'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const contracts = require('./project-contracts.js');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const server = fs.readFileSync(path.join(__dirname, 'server.ps1'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

assert.equal(contracts.isValidTitleId('PPSA12345'), true);
assert.equal(contracts.isValidTitleId('ppsa12345'), true, 'normalization must accept case-insensitive user input');
assert.equal(contracts.isValidTitleId('PPSA00000'), false, 'reserved zero TITLE_ID must be rejected');
assert.equal(contracts.isValidTitleId('PPSA1234'), false);
assert.equal(contracts.isValidTitleId('PPSAX2345'), false);
assert.equal(contracts.isValidProjectName('Taller de Colada'), true);
assert.equal(contracts.isValidProjectName('../outside'), false);
assert.equal(contracts.isValidProjectName(''), false);
assert.equal(contracts.normalizeAssetFilename('captura.PNG'), 'captura.png');
assert.equal(contracts.normalizeAssetFilename('release notes'), 'release-notes', 'extensionless assets must not gain a duplicate trailing character');
assert.equal(contracts.normalizeAssetFilename('../../imagen á.png'), 'imagen-a.png', 'asset names must be reduced to a safe basename');
assert.throws(() => contracts.normalizeAssetFilename('   '), /nombre de archivo válido/);

const defaults = { format: 'ps5vproj', formatVersion: 2, name: 'Prueba', backend: 'sharp', resolution: {width:1920,height:1080}, theme: {background:'#101827',accent:'#7865f6',text:'#f0f3ff'}, components: [], flows: [], assets: [], fontAssetId: '', screens: [{id:'screen-main',name:'Pantalla principal'}], currentScreen:'screen-main', settings: {titleId:'',firmware:'12.00',moduleKind:'app'}, customCode:'', manualCode:false };
const normalize = (value, sourceName) => contracts.normalizeProjectModel(value, defaults, ['panel','title','text','button','toggle','slider','stepper','select','carousel','list','progress','badge','image','input','gauge','separator','card'], ['sharp','opengl-ui','vulkan-ui','sharp-payload','ps5sdk','payload','ps5link','etahen'], sourceName);
const component = (overrides = {}) => ({id:'component-1',type:'text',label:'Componente de prueba',screenId:'screen-main',x:12,y:24,w:120,h:40,bg:'transparent',fg:'#ffffff',font:20,opacity:100,value:0,min:0,max:100,step:1,visible:true,checked:false,items:[],custom:{},action:'none',...overrides});
assert.equal(normalize({name:'Proyecto normalizado',components:[component({x:'12'})]}).components[0].x, 12);
assert.deepEqual(normalize({name:'Custom omitido',components:[component({custom:undefined})]}).components[0].custom, {}, 'an omitted custom bag is normalized to an empty object, never left undefined');
assert.throws(() => normalize({name:'Geometria incompleta',components:[{id:'c1',type:'text',label:'Texto',screenId:'screen-main',x:12,y:24,bg:'transparent',fg:'#ffffff'}]}), /valor geométrico explícito.*w/);
assert.throws(() => normalize({name:'Pantalla implicita',components:[component({screenId:undefined})]}), /identificador de pantalla explícito/);
assert.throws(() => normalize({name:'Etiqueta invalida',components:[component({label:7})]}), /etiqueta textual explícita/);
assert.throws(() => normalize({name:'Resolucion parcial',resolution:{width:1920}}), /declarar explícitamente ancho y alto/);
assert.throws(() => normalize({name:'Formato desconocido',formatVersion:3}), /Versión de formato no compatible/);
assert.throws(() => normalize({format:'ps5vproj',formatVersion:2,name:'Proyecto v2 incompleto'}), /campos requeridos: .*backend/);
assert.throws(() => normalize({name:'Bandera manual ambigua',manualCode:'true'}), /manualCode debe ser una bandera booleana explícita/);
const migratedLegacy = normalize({format:'ps5vproj',formatVersion:1,name:'Proyecto legado',backend:'sharp',resolution:{width:1920,height:1080},theme:{background:'#101827',accent:'#7865f6',text:'#f0f3ff'},components:[component({screenId:undefined})],flows:[],assets:[],screens:[],currentScreen:''});
assert.equal(migratedLegacy.formatVersion, 2, 'legacy imports must be upgraded to the current schema after validation');
assert.equal(migratedLegacy.currentScreen, 'screen-main');
assert.equal(migratedLegacy.components[0].screenId, 'screen-main', 'legacy single-screen components must be migrated as real context, not left detached');
const legacyFilename = normalize({format:'ps5vproj',formatVersion:1,name:'Taller de Colada – edición antigua con caracteres no ASCII y un nombre excesivamente largo que antes se podía abrir',backend:'sharp',resolution:{width:1920,height:1080},theme:{background:'#101827',accent:'#7865f6',text:'#f0f3ff'},components:[component()],flows:[],assets:[],screens:[],currentScreen:''}, 'C:\\Proyectos\\TallerColadaPrincipal.ps5vproj');
assert.equal(legacyFilename.name, 'TallerColadaPrincipal', 'when a legacy name exceeds the supported limit, use the actual compatible source filename rather than arbitrarily truncating it');
const legacyNameWithExtension = normalize({format:'ps5vproj',formatVersion:1,name:'TallerColadaPrincipal.ps5vproj',backend:'sharp',resolution:{width:1920,height:1080},theme:{background:'#101827',accent:'#7865f6',text:'#f0f3ff'},components:[component()],flows:[],assets:[],screens:[],currentScreen:''}, 'TallerColadaPrincipal.ps5vproj');
assert.equal(legacyNameWithExtension.name, 'TallerColadaPrincipal.ps5vproj', 'a valid legacy name matching the displayed file name must be accepted');
const legacyUnicodeName = normalize({format:'ps5vproj',formatVersion:1,name:'Taller de Colada á',backend:'sharp',resolution:{width:1920,height:1080},theme:{background:'#101827',accent:'#7865f6',text:'#f0f3ff'},components:[component()],flows:[],assets:[],screens:[],currentScreen:''});
assert.equal(legacyUnicodeName.name, 'Taller de Colada a', 'legacy Unicode names are converted deterministically without dropping the project');
const legacySourceNameFallback = normalize({format:'ps5vproj',formatVersion:1,name:'\u0000\u0001\u200b',backend:'sharp',resolution:{width:1920,height:1080},theme:{background:'#101827',accent:'#7865f6',text:'#f0f3ff'},components:[component()],flows:[],assets:[],screens:[],currentScreen:''}, 'C:\\Proyectos\\TallerColadaPrincipal.ps5vproj');
assert.equal(legacySourceNameFallback.name, 'TallerColadaPrincipal', 'if an old internal name cannot be recovered, use the actual compatible source filename rather than a generic placeholder');
const legacyMissingName = normalize({format:'ps5vproj',formatVersion:1,backend:'sharp',resolution:{width:1920,height:1080},theme:{background:'#101827',accent:'#7865f6',text:'#f0f3ff'},components:[component()],flows:[],assets:[],screens:[],currentScreen:''}, 'TallerColadaPrincipal.ps5vproj');
assert.equal(legacyMissingName.name, 'TallerColadaPrincipal', 'legacy projects without an internal name must derive it from the supplied source filename, not a default placeholder');
assert.throws(() => normalize({format:'ps5vproj',formatVersion:2,name:'Á'.repeat(41),backend:'sharp',resolution:{width:1920,height:1080},theme:{background:'#101827',accent:'#7865f6',text:'#f0f3ff'},components:[],flows:[],assets:[],fontAssetId:'',screens:[{id:'screen-main',name:'Pantalla principal'}],currentScreen:'screen-main',settings:{titleId:''},customCode:'',manualCode:false}), /nombre del proyecto.*40 caracteres ASCII seguros/, 'current schema projects must remain strictly validated instead of silently renamed');
assert.throws(() => normalize({format:'ps5vproj',formatVersion:1,name:'Legado ambiguo',backend:'sharp',resolution:{width:1920,height:1080},theme:{background:'#101827',accent:'#7865f6',text:'#f0f3ff'},components:[component({screenId:undefined})],flows:[],assets:[],screens:[{id:'home',name:'Inicio'},{id:'settings',name:'Ajustes'}],currentScreen:''}), /varias pantallas pero no declara currentScreen/);
assert.throws(() => normalize({format:'ps5vproj',formatVersion:1,name:'Legado con pantalla falsa',backend:'sharp',resolution:{width:1920,height:1080},theme:{background:'#101827',accent:'#7865f6',text:'#f0f3ff'},components:[component({screenId:'home'})],flows:[],assets:[],screens:[],currentScreen:'missing'}), /pantalla activa que no existe/);
assert.throws(() => normalize({name:'Color ficticio',components:[component({fg:''})]}), /color de texto hexadecimal explícito/);
assert.throws(() => normalize({name:'Geometria imposible',components:[component({x:1900,w:80})]}), /fuera del lienzo/);
assert.throws(() => normalize({name:'ID inseguro',components:[component({id:'../selector'})]}), /identificador técnico seguro/);
assert.throws(() => normalize({name:'Falta propiedad',components:[component({font:undefined})]}), /valor explícito en font/);
assert.throws(() => normalize({name:'Bandera ambigua',components:[component({visible:'false'})]}), /declarar visible como booleano/);
assert.throws(() => normalize({name:'Bandera ausente',components:[component({checked:undefined})]}), /declarar checked como booleano explícito/);
assert.throws(() => normalize({name:'Stepper decimal',components:[component({type:'stepper',value:2.5,step:1})]}), /valor, mínimo, máximo y paso enteros/);
assert.throws(() => normalize({name:'Seleccion inexistente',components:[component({type:'select',items:['A','B'],custom:{selected:3}})]}), /opción existente/);
assert.throws(() => normalize({name:'Pantallas duplicadas',screens:[{id:'screen-main',name:'Inicio'},{id:'settings',name:'inicio'}]}), /nombre de pantalla.*duplicado/i);
assert.equal(normalize({name:'ID normalizado',settings:{titleId:'ppsa12345'}}).settings.titleId, 'PPSA12345');
assert.throws(() => normalize({name:'Tema invalido',theme:{background:'#101827',accent:'sin-color',text:'#f0f3ff'}}), /color accent con formato/);
assert.throws(() => normalize({name:'Tema parcial',theme:{accent:'#7865f6'}}), /declarar explícitamente el color background/);
const fontAsset = {id:'font-file',name:'Fuente.ttf',fileName:'Fuente.ttf',mime:'font/ttf',size:4,dataUrl:'data:font/ttf;base64,AAAA'};
assert.equal(normalize({name:'Fuente valida',assets:[fontAsset],fontAssetId:'font-file'}).fontAssetId, 'font-file');
assert.throws(() => normalize({name:'Recurso sin datos',assets:[{id:'image-file',name:'imagen.png',fileName:'imagen.png',mime:'image/png',size:4,dataUrl:''}]}), /data URL válido/);
assert.throws(() => normalize({name:'Ruta en archivo',assets:[{id:'image-file',name:'imagen.png',fileName:'..\\outside.png',mime:'image/png',size:4,dataUrl:'data:image/png;base64,AAAA'}]}), /nombre de archivo no seguro/);
assert.throws(() => normalize({name:'Fuente no TTF',assets:[{id:'font-file',name:'Fuente.otf',fileName:'Fuente.otf',mime:'font/otf',size:4,dataUrl:'data:font/otf;base64,AAAA'}],fontAssetId:'font-file'}), /recurso TTF real/);
assert.throws(() => normalize({name:'Fuente desconocida',fontAssetId:'missing-font'}), /recurso inexistente/);
assert.throws(() => normalize({name:'Proyecto roto',components:{}}), /components debe ser una lista/);
assert.throws(() => normalize({name:'Proyecto roto',components:[{id:'c1',type:'unimplemented'}]}), /tipo no compatible/);
assert.throws(() => normalize({name:'Proyecto roto',components:[component({id:'c1'}),component({id:'c1'})]}), /duplicado/);
assert.throws(() => normalize({name:'Proyecto roto',backend:'backend-fantasma'}), /Backend de proyecto desconocido/);
assert.throws(() => normalize({name:'Proyecto roto',settings:{titleId:'PPSA00000'}}), /TITLE_ID guardado/);
assert.throws(() => normalize({name:'Pantalla sin nombre', screens:[{id:'screen-main',name:'   '}]}), /necesita un nombre explícito/);
assert.throws(() => normalize({name:'Toggle invalido',components:[component({id:'flag',type:'toggle',label:'Flag'})],flows:[{id:'f-toggle',componentId:'flag',event:'change',action:'setValue',targetId:'flag',value:'maybe'}]}), /valor booleano explícito/);
assert.throws(() => normalize({name:'Navegacion circular',components:[component({id:'button-home',type:'button',label:'Inicio'})],flows:[{id:'f-home',componentId:'button-home',event:'activate',action:'navigate',targetScreen:'screen-main'}]}), /misma pantalla/);

assert.throws(() => normalize({name:'Backend vacio',backend:''}), /backend explícito no puede estar vacío/);
assert.throws(() => normalize({name:'Seleccion tipo texto',components:[component({type:'select',items:['A','B'],custom:{selected:'1'}})]}), /índice entero/);
assert.throws(() => normalize({name:'Seleccion nula',components:[component({type:'select',items:['A','B'],custom:{selected:null}})]}), /índice entero/);
assert.throws(() => contracts.normalizeAssetFilename('💫.png'), /no contiene caracteres de archivo compatibles/);
assert.throws(() => normalize({name:'Flujo valor fuera de rango',components:[component({id:'source'}),component({id:'meter',type:'gauge',min:10,max:50,value:20})],flows:[{id:'f-outside',componentId:'source',event:'activate',action:'setValue',targetId:'meter',value:'75'}]}), /fuera del intervalo/);
assert.throws(() => normalize({name:'Flujo indice sin opcion',components:[component({id:'component-1'}),component({id:'picker',type:'select',items:['A','B']})],flows:[{id:'f-index',componentId:'component-1',event:'activate',action:'setValue',targetId:'picker',value:'2'}]}), /índice entero que apunte a una opción real/);


assert.match(html, /runtime\/project-contracts\.js\?v=1\.1\.16/);
assert.match(server, /function TestPS5HSTitleId\(/);
assert.match(server, /TestPS5HSTitleId \$titleId/);
assert.match(server, /TestPS5HSTitleId \$TitleId/);
assert.doesNotMatch(app, /Math\.floor\(Math\.random\(\)\*90000\)\+10000/,
  'new projects must not silently invent a TITLE_ID');
assert.match(app, /if\(!project\.manualCode&&!project\.components\.length/,
  'manual source builds must not be rejected solely for an empty visual canvas');
assert.match(app, /function normalizeProjectModel\(value,sourceName\)/, 'all imported and restored projects use schema normalization and import filenames for legacy recovery');
assert.match(app, /No se generará código C# bajo un backend OpenGL\/Vulkan/, 'a missing native generator must fail closed, never fall through into the Sharp C# generator');

assert.match(app, /!value\.format&&Array\.isArray\(value\.components\)\?\{\.\.\.value,format:'ps5vproj',formatVersion:1\}/, 'legacy raw component JSON must enter the explicit schema migration path');
assert.doesNotMatch(app, /c\.actionMessage\|\|'Acción completada'/, 'empty notify actions must not be replaced with a generic success message');
assert.doesNotMatch(app, /const lab=q\(c\.label\|\|TYPES/, 'generated labels must not silently substitute a widget type name');
assert.match(app, /valor booleano explícito para el interruptor/, 'invalid toggle values must be rejected in preview and generation');

assert.match(app, /índice entero que corresponda a una opción real/, 'preview flow execution must reject invalid option indices rather than round/clamp them');
assert.match(app, /csharpFloat\(\(c\.value-c\.min\)\/\(c\.max-c\.min\)\)/, 'C# progress values must be normalized to the component min/max interval');
assert.ok(app.includes("const selectedIndex=c=>{const items=requireItems(c);const raw=Object.hasOwn(c.custom||{},'selected')?c.custom.selected:c.value;"), 'the Sharp selector must respect the model value when no explicit custom selection overrides it');
assert.match(app, /El valor debe respetar el rango del control/, 'static analysis must report values outside a flow target range');

assert.match(app, /El botón \$\{c\.id\} no tiene una acción ejecutable/, 'Sharp generation must reject interactive buttons with no callback instead of generating an inert button');
assert.doesNotMatch(app, /return action\?`new Button\(\$\{lab\}, \(\) => \{ \$\{action\} \}\)`:`new Button\(\$\{lab\}\)`/, 'Sharp codegen must not emit a button without a callback as a fallback');


assert.doesNotMatch(app, /c\[key\]=Number\(val\)\|\|0/, 'blank or invalid inspector values must not mutate the model to zero');
assert.match(app, /La geometría debe permanecer dentro del lienzo/, 'inspector edits must reject out-of-bounds geometry instead of silently clamping it');


assert.match(app, /operationRevision!==modalRevision/, 'async generation callbacks must not alter a newer modal');
assert.match(app, /nativeProjectsRequestRevision/, 'late workspace responses must not overwrite a newer project list');
assert.match(app, /root!==\$\('#nativeProjectList'\)/, 'workspace callbacks must still own the active DOM root before rendering');
assert.match(app, /No se generará una tarjeta sustitutiva/, 'missing images must block native build rather than create a placeholder');
assert.match(app, /contracts\.normalizeAssetFilename\(file\.name\)/, 'asset import must use the shared, tested filename contract');
assert.match(app, /normalizeProjectModel\(data,file\.name\)/, 'legacy project import must supply the actual filename for safe deterministic name recovery');
assert.match(app, /const maxBytes=20\*1024\*1024/, 'asset import must enforce a bounded resource size');
assert.doesNotMatch(app, /const id='asset-'\+Date\.now\(\)\.toString\(36\)/, 'asset IDs must not collide when imported in the same millisecond');
assert.doesNotMatch(app, /if\(project\.fontAssetId&&!fontAssets\.some\(a=>a\.id===project\.fontAssetId\)\)project\.fontAssetId=''/, 'renderers must not silently mutate project state');
assert.match(app, /El archivo de recuperación local se conserva sin modificar/, 'invalid autosaves must be preserved instead of being deleted automatically');
assert.match(app, /function undo\(/);

assert.ok(app.includes("if(!/^[a-zA-Z_][a-zA-Z0-9_-]{0,63}$/.test(v))"), 'renaming a component must use the same minimum ID length as the model contract');
assert.match(app, /data-prop="x" min="0" max="1920" step="any" value="\$\{c\.x\}"/, 'the inspector must preserve coordinate precision when it renders numeric fields');
assert.match(app, /function redo\(/);
assert.match(app, /e\.key\.toLowerCase\(\)==='z'\).*undo\(\)/s);
assert.match(app, /e\.key\.toLowerCase\(\)==='y'\).*redo\(\)/s);

assert.match(app, /const ratio=Number\.isFinite\(c\.min\)&&Number\.isFinite\(c\.max\)&&c\.max>c\.min\?\(c\.value-c\.min\)\/\(c\.max-c\.min\):0/, 'progress and gauge previews must normalize against the component range');
assert.doesNotMatch(app, /clamp\(c\.value,0,100\).*progress-fill/, 'progress preview must not assume a 0–100 value range');
assert.doesNotMatch(app, /esc\(c\.value\)\}%<\/span>.*slider-track/, 'slider preview must not label arbitrary range values as percentages');

console.log('PASS project contracts: explicit TITLE_ID, shared name validation, manual source and connected history.');
