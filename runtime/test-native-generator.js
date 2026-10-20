'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const codegen = require('./native-generator.js');

const makeComponent = (id, overrides = {}) => ({
  id, screenId: 'home', type: 'text', label: id,
  x: 10, y: 10, w: 120, h: 50, font: 20, opacity: 100,
  value: 0, min: 0, max: 100, step: 1,
  bg: '#202a40', fg: '#ffffff', visible: true, checked: false,
  action: 'none', actionMessage: `${id} activado`,
  items: [], assetId: null, custom: {}, zIndex: 1,
  ...overrides,
});
const makeAsset = (id, overrides = {}) => ({
  id, name: `Recurso ${id}`, fileName: `${id}.png`, mime: 'image/png',
  dataUrl: 'data:image/png;base64,AA==', size: 1,
  ...overrides,
});
const makeProject = (overrides = {}) => ({
  name: 'Studio "Prueba"', backend: 'opengl-ui', currentScreen: 'home',
  theme: { background: '#101827', accent: '#7865f6', text: '#f0f3ff' },
  assets: [makeAsset('asset-avatar', { fileName: 'avatar.png', name: 'Avatar' })],
  screens: [{ id: 'home', name: 'Inicio' }, { id: 'settings', name: 'Ajustes' }],
  components: [
    makeComponent('heading', { type: 'title', label: 'Hola "PS5" · áéíóú ÁÉÍÓÚ ñ Ñ ü Ü ¿Qué tal? ¡Funciona! €', x: 80, y: 45, w: 800, h: 100, font: 52, bg: 'transparent', zIndex: 1 }),
    makeComponent('start', { type: 'button', label: 'Abrir ajustes', x: 100, y: 190, w: 300, h: 70, font: 24, bg: '#7865f6', screenId: 'home', action: 'notify', actionMessage: 'Activado', zIndex: 2 }),
    makeComponent('enabled', { type: 'toggle', label: 'Audio', screenId: 'settings', x: 50, y: 80, w: 300, h: 60, checked: true, zIndex: 3 }),
    makeComponent('volume', { type: 'slider', label: 'Volumen', screenId: 'settings', x: 50, y: 160, w: 350, h: 70, value: 75, step: 5, zIndex: 4 }),
    makeComponent('quality', { type: 'select', label: 'Calidad', screenId: 'settings', x: 50, y: 250, w: 350, h: 70, value: 1, min: 0, max: 2, step: 1, items: ['Baja', 'Media', 'Alta'], custom: { selected: 1 }, zIndex: 5 }),
    makeComponent('avatar', { type: 'image', label: 'Avatar', assetId: 'asset-avatar', x: 500, y: 200, w: 150, h: 150, font: 14, zIndex: 6 }),
    makeComponent('username', { type: 'input', label: 'Usuario', x: 100, y: 300, w: 280, h: 64, font: 18, custom: { text: '' }, zIndex: 7 }),
    makeComponent('meter', { type: 'gauge', label: 'Carga', x: 700, y: 180, w: 140, h: 140, value: 62, zIndex: 8 }),
  ],
  flows: [
    { id: 'f1', componentId: 'start', event: 'activate', action: 'navigate', targetScreen: 'settings', enabled: true, targetId: '', message: '', value: '' },
    { id: 'f2', componentId: 'enabled', event: 'change', action: 'setText', targetId: 'heading', value: 'Estado cambiado', enabled: true, targetScreen: '', message: '' },
    { id: 'f3', componentId: 'volume', event: 'change', action: 'setValue', targetId: 'meter', value: '55', enabled: true, targetScreen: '', message: '' },
    { id: 'f4', componentId: '', event: 'start', action: 'notify', message: 'Bienvenido', value: '', targetId: '', targetScreen: '', enabled: true },
  ],
  ...overrides,
});
const project = makeProject();

for (const backend of ['opengl-ui', 'vulkan-ui']) {
  const source = codegen.generate(project, backend);
  if (process.env.PS5HS_EMIT_TEST_CPP) {
    fs.mkdirSync(process.env.PS5HS_EMIT_TEST_CPP, { recursive: true });
    fs.writeFileSync(path.join(process.env.PS5HS_EMIT_TEST_CPP, `${backend}.cpp`), source);
  }
  assert.ok(source.length > 5000, `${backend}: source unexpectedly short`);
  assert.ok(source.includes('class GeneratedScreen final : public hui::app::Concept'));
  assert.ok(source.includes('Hola \\"PS5\\"'));
  assert.ok(source.includes('áéíóú ÁÉÍÓÚ ñ Ñ ü Ü ¿Qué tal? ¡Funciona! €'), `${backend}: UTF-8 European characters must survive C++ generation`);
  assert.ok(source.includes('Estado cambiado'));
  assert.ok(source.includes('widgets_[0].label'));
  assert.ok(source.includes('widgets_[7].value'));
  assert.ok(source.includes('screen_ = "settings"'));
  assert.ok(source.includes('std::string screen_ = "home";'), `${backend}: initial runtime screen must match the selected model screen`);
  assert.ok(source.includes('text_color_ = Color::rgb(0xf0f3ff)'), `${backend}: theme text color must be honored`);
  assert.ok(source.includes('update_keyboard(input)'));
  assert.ok(source.includes('kKeyboardKeys'));
  assert.ok(source.includes('Teclado de pantalla'));
  assert.ok(source.includes('w.max > w.min ? clamp_value((w.value - w.min) / (w.max - w.min)'));
  if (backend === 'opengl-ui') { assert.ok(source.includes('glTexImage2D')); assert.ok(source.includes('ps5hs/asset-avatar.rgba')); assert.ok(source.includes('draw.image(w.texture')); }
  else { assert.ok(!source.includes('void load_textures() {}'), `${backend}: Vulkan must not emit an empty texture stub`); assert.ok(source.includes('ps5ui::ps5hs_texture_for(w.asset_path)')); assert.ok(source.includes('ps5hs/asset-avatar.rgba')); }
  assert.ok(!source.includes('Imagen no disponible'), `${backend}: missing resources must never be represented by a placeholder widget`);
  assert.ok(!source.includes('target component was not resolved'), `${backend}: generated flows must not contain unresolved-target placeholders`);
  assert.ok(!source.includes('unsupported visual action'), `${backend}: generated flows must not contain unsupported-action placeholders`);
  assert.ok(source.includes('Audio'));
  if (backend === 'opengl-ui') assert.ok(source.includes('make_ps5hs_generated'));
  else assert.ok(source.includes('namespace ps5ui') && source.includes('make_screen'));
  console.log(`PASS ${backend}: ${source.length} bytes, screens/components/flows encoded`);
}

const empty = makeProject({ components: [] });
assert.throws(() => codegen.generate(empty, 'opengl-ui'), /lienzo está vacío/);
assert.throws(() => codegen.generate(null, 'opengl-ui'), /modelo de proyecto válido/);
console.log('PASS empty model: generator refuses to emit an empty visual screen or replace a null project with a stub.');

const noFlows = codegen.generate(makeProject({ flows: [] }), 'opengl-ui');
assert.match(noFlows, /void run_flows\(int source, std::string_view event\)\s*\{\s*\(void\)source;\s*\(void\)event;/,
  'a project with no configured flows must emit an explicit no-op rationale, not an empty function stub');
const precisionProject = makeProject({ flows: [], components: [makeComponent('precise', { x: 10.1234567, y: 10.0000001, w: 120.9876543, h: 50, font: 20.25 })] });
const preciseSource = codegen.generate(precisionProject, 'opengl-ui');
assert.match(preciseSource, /10\.1234567f/, 'float literals must retain model precision instead of rounding to three decimals');
assert.match(preciseSource, /10\.0000001f/, 'small representable float differences must not be rounded away');

const controlEscapeProject = makeProject({ flows: [], components: [makeComponent('control-text', { label: 'X\u0001F' })] });
const controlEscapeSource = codegen.generate(controlEscapeProject, 'opengl-ui');
assert.ok(controlEscapeSource.includes('X\\001F'), 'C++ control escapes must be fixed-width octal so the next hex-like character cannot be absorbed into the escape.');
console.log('PASS generated source integrity: no empty flow stub and precise numeric literals are retained.');


const orphanFlow = makeProject();
orphanFlow.flows.push({ id: 'orphan', componentId: 'start', event: 'activate', action: 'setText', targetId: 'missing-target', value: 'bad', enabled: true, targetScreen: '', message: '' });
assert.throws(() => codegen.generate(orphanFlow, 'opengl-ui'), /destino válido/);
const invalidNavigation = makeProject();
invalidNavigation.flows[0].targetScreen = 'does-not-exist';
assert.throws(() => codegen.generate(invalidNavigation, 'vulkan-ui'), /pantalla inexistente/);

const outOfRangeFlow = makeProject();
outOfRangeFlow.flows.push({ id: 'out-range', componentId: 'start', event: 'activate', action: 'setValue', targetId: 'volume', value: '1000', enabled: true, targetScreen: '', message: '' });
assert.throws(() => codegen.generate(outOfRangeFlow, 'opengl-ui'), /está fuera del intervalo/);
const inertButton = makeProject({
  screens: [{ id: 'home', name: 'Inicio' }], currentScreen: 'home', assets: [], flows: [],
  components: [makeComponent('inert', { type: 'button', screenId: 'home', label: 'Botón sin acción', action: 'none' })]
});
for (const backend of ['opengl-ui', 'vulkan-ui']) {
  const passiveButtonSource = codegen.generate(inertButton, backend);
  assert.ok(passiveButtonSource.includes('inert') && passiveButtonSource.includes('Botón sin acción'), `${backend}: explicit action=none must preserve the actual button widget`);
  assert.ok(!passiveButtonSource.includes('unsupported visual action'), `${backend}: passive button must not be replaced by an unsupported-action placeholder`);
}
console.log('PASS button semantics: explicit action=none generates a real passive widget without an empty callback and does not block compilation');
console.log('PASS invalid flows: unresolved component targets and navigation screens are rejected before C++ generation');

const missingNativeImage = makeProject({ assets: [], components: [makeComponent('image-orphan', { type: 'image', label: 'Carátula', bg: 'transparent', assetId: null })], flows: [] });
assert.throws(() => codegen.generate(missingNativeImage, 'opengl-ui'), /no tiene un recurso gráfico válido/);
assert.throws(() => codegen.generate(missingNativeImage, 'vulkan-ui'), /no tiene un recurso gráfico válido/);
console.log('PASS image validation: missing resources fail before code generation and no placeholder widget is emitted.');

const missingId = makeProject({ components: [makeComponent('', { label: 'Texto' })] });
assert.throws(() => codegen.generate(missingId, 'opengl-ui'), /identificador técnico explícito y seguro/);
const unknownType = makeProject({ components: [makeComponent('x', { type: 'unknown' })] });
assert.throws(() => codegen.generate(unknownType, 'opengl-ui'), /tipo no implementado/);
const noOptions = makeProject({ components: [makeComponent('x', { type: 'select', label: 'Selección', items: [] })] });
assert.throws(() => codegen.generate(noOptions, 'opengl-ui'), /no se crearán opciones ficticias/);
assert.throws(() => codegen.generate(makeProject({ components: {} }), 'opengl-ui'), /lista de componentes inválida/);
console.log('PASS native model contracts: no invented IDs, types, options or implicit empty model fallbacks.');

assert.throws(() => codegen.generate(makeProject({ currentScreen: 'does-not-exist' }), 'opengl-ui'), /pantalla activa no existe/);
assert.throws(() => codegen.generate(makeProject({ theme: { background: '', accent: '#7865f6', text: '#ffffff' } }), 'opengl-ui'), /color background explícito/);
assert.throws(() => codegen.generate(makeProject({ theme: { background: '#101827', accent: '#7865f6', text: '' } }), 'opengl-ui'), /color text explícito/);
assert.throws(() => codegen.generate(makeProject({ backend: undefined }), undefined), /No se especificó un backend/);
assert.throws(() => codegen.generate(project, ''), /No se especificó un backend/);
const emptyDefaultAction = makeProject();
emptyDefaultAction.components[1].action = 'notify';
emptyDefaultAction.components[1].actionMessage = '';
assert.throws(() => codegen.generate(emptyDefaultAction, 'opengl-ui'), /necesita un mensaje explícito/);
const sameScreenNavigation = makeProject();
sameScreenNavigation.flows[0].targetScreen = 'home';
assert.throws(() => codegen.generate(sameScreenNavigation, 'opengl-ui'), /pantalla diferente/);
const invalidToggleFlow = makeProject();
invalidToggleFlow.flows.push({ id: 'bad-toggle', componentId: 'enabled', event: 'change', action: 'setValue', targetId: 'enabled', value: '', enabled: true, targetScreen: '', message: '' });
assert.throws(() => codegen.generate(invalidToggleFlow, 'opengl-ui'), /explícitamente true\/false/);
const invalidSelectionFlow = makeProject();
invalidSelectionFlow.flows.push({ id: 'bad-selection', componentId: 'volume', event: 'change', action: 'setValue', targetId: 'quality', value: '9', enabled: true, targetScreen: '', message: '' });
assert.throws(() => codegen.generate(invalidSelectionFlow, 'opengl-ui'), /índice entero de una opción real/);
console.log('PASS context validation: startup screen, explicit backend/theme, flow semantics and selection bounds.');

assert.throws(() => codegen.generate(makeProject({ components: [makeComponent('outside', { x: 1910, w: 100 })] }), 'opengl-ui'), /no se recortará silenciosamente/);
assert.throws(() => codegen.generate(makeProject({ components: [makeComponent('font-outside', { font: 200 })] }), 'opengl-ui'), /no se cambiará automáticamente/);
assert.throws(() => codegen.generate(makeProject({ components: [makeComponent('implicit-visible', { visible: undefined })] }), 'opengl-ui'), /visible y checked como booleanos explícitos/);
assert.throws(() => codegen.generate(makeProject({ flows: undefined }), 'opengl-ui'), /lista de flujos/);
assert.throws(() => codegen.generate(makeProject({ assets: undefined }), 'opengl-ui'), /lista de recursos/);
assert.throws(() => codegen.generate(makeProject({ screens: [{ id: 'home' }]}), 'opengl-ui'), /nombre explícito/);
assert.throws(() => codegen.generate(makeProject({ assets: [makeAsset('bad', { size: 3 })] }), 'opengl-ui'), /no coincide con sus datos/);
assert.throws(() => codegen.generate(makeProject({ assets: [makeAsset('bad', { dataUrl: '' })] }), 'opengl-ui'), /data URL Base64 válido/);
console.log('PASS fail-closed generator contracts: no clamping, hidden booleans or incomplete resources.');

const layered = makeProject({
  name: 'Capas', assets: [], flows: [], screens: [{ id: 'home', name: 'Inicio' }], currentScreen: 'home',
  components: [
    makeComponent('layer-front', { label: 'CAPA DELANTE', x: 50, y: 50, w: 400, h: 200, bg: '#222222', zIndex: 9 }),
    makeComponent('layer-back', { label: 'CAPA DETRÁS', x: 40, y: 40, w: 400, h: 200, bg: '#111111', zIndex: 1 }),
  ],
});
for (const backend of ['opengl-ui', 'vulkan-ui']) {
  const source = codegen.generate(layered, backend);
  assert.ok(source.indexOf('Widget{"layer-back"') < source.indexOf('Widget{"layer-front"'), `${backend}: back-to-front z-order must be preserved in the draw list`);
}
console.log('PASS layers: native OpenGL/Vulkan output orders back layers before front layers');

const safeAssetPathProject = makeProject({ assets: [makeAsset('asset?unsafe')] });
assert.throws(() => codegen.generate(safeAssetPathProject, 'opengl-ui'), /identificador técnico explícito y seguro/);
console.log('PASS assets: native resource IDs reject unsafe path names before packaging.');
