'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const codegen = require('./native-generator.js');
const unicodeFonts = require('./unicode-fonts.js');

const project = {
  name: 'Studio "Prueba"', backend: 'opengl-ui', currentScreen: 'home',
  theme: { background: '#101827', accent: '#7865f6' },
  assets: [{ id: 'asset-avatar', fileName: 'avatar.png', mime: 'image/png', dataUrl: 'data:image/png;base64,AA==' }],
  screens: [{ id: 'home', name: 'Inicio' }, { id: 'settings', name: 'Ajustes' }],
  components: [
    { id: 'heading', screenId: 'home', type: 'title', label: 'Hola "PS5" · áéíóú ÁÉÍÓÚ ñ Ñ ü Ü ¿Qué tal? ¡Funciona! € · Русский язык · Ελληνικά · 日本語かな漢字 · 简体中文繁體中文 · 한국어 · français Grüße', x: 80, y: 45, w: 800, h: 100, font: 52, bg: 'transparent', fg: '#ffffff', visible: true },
    { id: 'start', screenId: 'home', type: 'button', label: 'Abrir ajustes', x: 100, y: 190, w: 300, h: 70, font: 24, bg: '#7865f6', fg: '#ffffff', action: 'notify', actionMessage: 'Activado', visible: true },
    { id: 'enabled', screenId: 'settings', type: 'toggle', label: 'Audio', x: 50, y: 80, w: 300, h: 60, font: 20, bg: '#202a40', fg: '#ffffff', checked: true, visible: true },
    { id: 'volume', screenId: 'settings', type: 'slider', label: 'Volumen', x: 50, y: 160, w: 350, h: 70, font: 20, bg: '#202a40', fg: '#ffffff', value: 75, min: 0, max: 100, step: 5, visible: true },
    { id: 'quality', screenId: 'settings', type: 'select', label: 'Calidad', x: 50, y: 250, w: 350, h: 70, font: 20, bg: '#202a40', fg: '#ffffff', value: 1, min: 0, max: 2, step: 1, items: ['Baja', 'Media', 'Alta'], visible: true },
    { id: 'avatar', assetId: 'asset-avatar', screenId: 'home', type: 'image', label: 'Avatar', x: 500, y: 200, w: 150, h: 150, font: 14, bg: '#202a40', fg: '#ffffff', visible: true },
    { id: 'username', screenId: 'home', type: 'input', label: 'Usuario', x: 100, y: 300, w: 280, h: 64, font: 18, bg: '#141b29', fg: '#ffffff', visible: true },
    { id: 'meter', screenId: 'home', type: 'gauge', label: 'Carga', x: 700, y: 180, w: 140, h: 140, font: 18, bg: '#263047', fg: '#ffffff', value: 62, min: 0, max: 100, visible: true },
  ],
  flows: [
    { id: 'f1', componentId: 'start', event: 'activate', action: 'navigate', targetScreen: 'settings', enabled: true },
    { id: 'f2', componentId: 'enabled', event: 'change', action: 'setText', targetId: 'heading', value: 'Estado cambiado', enabled: true },
    { id: 'f3', componentId: 'volume', event: 'change', action: 'setValue', targetId: 'meter', value: '55', enabled: true },
    { id: 'f4', componentId: '', event: 'start', action: 'notify', message: 'Bienvenido', enabled: true },
  ]
};

for (const backend of ['opengl-ui', 'vulkan-ui']) {
  const source = codegen.generate(project, backend);
  if (process.env.PS5HS_EMIT_TEST_CPP) { fs.mkdirSync(process.env.PS5HS_EMIT_TEST_CPP, { recursive: true }); fs.writeFileSync(path.join(process.env.PS5HS_EMIT_TEST_CPP, `${backend}.cpp`), source); }
  assert.ok(source.length > 5000, `${backend}: source unexpectedly short`);
  assert.ok(source.includes('class GeneratedScreen final : public hui::app::Concept'));
  assert.ok(source.includes('Hola \\"PS5\\"'));
  assert.ok(source.includes('áéíóú ÁÉÍÓÚ ñ Ñ ü Ü ¿Qué tal? ¡Funciona! €'), `${backend}: UTF-8 European characters must survive C++ generation`);
  assert.ok(source.includes('Estado cambiado'));
  assert.ok(source.includes('widgets_[0].label'));
  assert.ok(source.includes('widgets_[7].value'));
  assert.ok(source.includes('screen_ = "settings"'));
  assert.ok(source.includes('update_keyboard(input)'));
  assert.ok(source.includes('kKeyboardKeys'));
  assert.ok(source.includes('Teclado de pantalla'));
  assert.ok(source.includes('w.max > w.min ? clamp_value((w.value - w.min) / (w.max - w.min)'));
  if (backend === 'opengl-ui') { assert.ok(source.includes('glTexImage2D')); assert.ok(source.includes('ps5hs/asset-avatar.rgba')); assert.ok(source.includes('draw.image(w.texture')); }
  else { assert.ok(!source.includes('void load_textures() {}'), `${backend}: Vulkan must not emit an empty texture stub`); assert.ok(source.includes('ps5ui::ps5hs_texture_for(w.asset_path)')); assert.ok(source.includes('ps5hs/asset-avatar.rgba')); assert.ok(source.includes('Imagen no disponible')); }
  assert.ok(!source.includes('target component was not resolved'), `${backend}: generated flows must not contain unresolved-target placeholders`);
  assert.ok(!source.includes('unsupported visual action'), `${backend}: generated flows must not contain unsupported-action placeholders`);
  assert.ok(source.includes('Audio'));
  assert.ok(source.includes('Русский язык · Ελληνικά · 日本語かな漢字 · 简体中文繁體中文 · 한국어 · français Grüße'), `${backend}: Unicode scripts must survive C++ source generation`);
  if (backend === 'opengl-ui') assert.ok(source.includes('make_ps5hs_generated'));
  else assert.ok(source.includes('namespace ps5ui') && source.includes('make_screen'));
  console.log(`PASS ${backend}: ${source.length} bytes, screens/components/flows encoded`);
}

const empty = codegen.generate({ name: 'Vacío', components: [], flows: [], screens: [{ id: 'screen-main' }] }, 'opengl-ui');
assert.ok(empty.includes('widgets_ = {\n        };'));
console.log('PASS empty model: compiles to a valid empty component list');

const orphanFlow = JSON.parse(JSON.stringify(project));
orphanFlow.flows.push({ id: 'orphan', componentId: 'start', event: 'activate', action: 'setText', targetId: 'missing-target', value: 'bad', enabled: true });
assert.throws(() => codegen.generate(orphanFlow, 'opengl-ui'), /destino válido/);
const invalidNavigation = JSON.parse(JSON.stringify(project));
invalidNavigation.flows[0].targetScreen = 'does-not-exist';
assert.throws(() => codegen.generate(invalidNavigation, 'vulkan-ui'), /pantalla inexistente/);
console.log('PASS invalid flows: unresolved component targets and navigation screens are rejected before C++ generation');

const layered = {
  name: 'Capas', theme: { background: '#101827', accent: '#7865f6' },
  screens: [{ id: 'home', name: 'Inicio' }], currentScreen: 'home', assets: [], flows: [],
  components: [
    { id: 'layer-front', screenId: 'home', type: 'panel', label: 'CAPA DELANTE', x: 50, y: 50, w: 400, h: 200, bg: '#222222', fg: '#ffffff', zIndex: 9 },
    { id: 'layer-back', screenId: 'home', type: 'panel', label: 'CAPA DETRÁS', x: 40, y: 40, w: 400, h: 200, bg: '#111111', fg: '#ffffff', zIndex: 1 },
  ],
};
for (const backend of ['opengl-ui', 'vulkan-ui']) {
  const source = codegen.generate(layered, backend);
  assert.ok(source.indexOf('Widget{"layer-back"') < source.indexOf('Widget{"layer-front"'), `${backend}: back-to-front z-order must be preserved in the draw list`);
}
console.log('PASS layers: native OpenGL/Vulkan output orders back layers before front layers');

const multilingualModel = {
  name: 'Unicode',
  components: [{ label: 'Español áéíóú ñ · Русский язык · Ελληνικά · 日本語かな漢字 · 简体中文繁體中文 · 한국어 · français Grüße' }],
  screens: [{ name: '日本語 設定' }],
  flows: [{ message: '中文提示', value: 'Тест' }]
};
const codepoints = unicodeFonts.collectCodepoints(multilingualModel);
for (const character of 'Русский язык Ελληνικά 日本語かな漢字 简体中文繁體中文 한국어 áéíóú ñ') {
  assert.ok(codepoints.includes(character.codePointAt(0)), 'Unicode codepoint missing for ' + character);
}
assert.deepEqual(codepoints, [...new Set(codepoints)].sort((a, b) => a - b), 'codepoint list must be unique and sorted');
assert.throws(() => unicodeFonts.prepareFontAsset({ name: 'font.otf', dataUrl: 'data:font/otf;base64,AA==', size: 2 }), /\.ttf/);
assert.throws(() => unicodeFonts.prepareFontAsset({ name: 'font.ttf', dataUrl: 'data:font/ttf;base64,AA==', size: 25 * 1024 * 1024 }), /20 MiB/);
console.log('PASS Unicode fonts: multilingual codepoints collected; TTF type and size validated');
