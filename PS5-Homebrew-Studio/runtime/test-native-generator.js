'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const codegen = require('./native-generator.js');

const project = {
  name: 'Studio "Prueba"', backend: 'opengl-ui', currentScreen: 'home',
  theme: { background: '#101827', accent: '#7865f6' },
  assets: [{ id: 'asset-avatar', fileName: 'avatar.png', mime: 'image/png', dataUrl: 'data:image/png;base64,AA==' }],
  screens: [{ id: 'home', name: 'Inicio' }, { id: 'settings', name: 'Ajustes' }],
  components: [
    { id: 'heading', screenId: 'home', type: 'title', label: 'Hola "PS5"', x: 80, y: 45, w: 800, h: 100, font: 52, bg: 'transparent', fg: '#ffffff', visible: true },
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
  assert.ok(source.includes('Estado cambiado'));
  assert.ok(source.includes('widgets_[0].label'));
  assert.ok(source.includes('widgets_[7].value'));
  assert.ok(source.includes('screen_ = "settings"'));
  assert.ok(source.includes('update_keyboard(input)'));
  assert.ok(source.includes('kKeyboardKeys'));
  assert.ok(source.includes('Teclado de pantalla'));
  assert.ok(source.includes('w.max > w.min ? clamp_value((w.value - w.min) / (w.max - w.min)'));
  if (backend === 'opengl-ui') { assert.ok(source.includes('glTexImage2D')); assert.ok(source.includes('ps5hs/asset-avatar.rgba')); assert.ok(source.includes('draw.image(w.texture')); }
  else { assert.ok(source.includes('void load_textures() {}')); assert.ok(source.includes('ps5ui::ps5hs_texture_for(w.asset_path)')); assert.ok(source.includes('ps5hs/asset-avatar.rgba')); assert.ok(source.includes('Imagen no disponible')); }
  assert.ok(source.includes('Audio'));
  if (backend === 'opengl-ui') assert.ok(source.includes('make_ps5hs_generated'));
  else assert.ok(source.includes('namespace ps5ui') && source.includes('make_screen'));
  console.log(`PASS ${backend}: ${source.length} bytes, screens/components/flows encoded`);
}

const empty = codegen.generate({ name: 'Vacío', components: [], flows: [], screens: [{ id: 'screen-main' }] }, 'opengl-ui');
assert.ok(empty.includes('widgets_ = {\n        };'));
console.log('PASS empty model: compiles to a valid empty component list');
