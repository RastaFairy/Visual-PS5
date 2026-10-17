'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const appPath = path.join(__dirname, '..', 'app.js');
const app = fs.readFileSync(appPath, 'utf8');
const startToken = '  // Explores visual screens separately from native code states.';
const endToken = '  function selectScreen(id){';
const start = app.indexOf(startToken);
const end = app.indexOf(endToken, start);
assert.notEqual(start, -1, 'Structure scanner must exist in app.js');
assert.notEqual(end, -1, 'Structure scanner must end before selectScreen');
assert.ok(end > start, 'Structure scanner boundaries must be in order');

const sandbox = {};
vm.runInNewContext(
  app.slice(start, end) + '\nglobalThis.__scanNativeStructure = scanNativeStructure;',
  sandbox,
  { timeout: 1500 }
);

const source = [
  'enum class Screen { title, missions, settings, confirm };',
  'enum class UiText { welcome, choose, preferences, yes, no, count };',
  'static constexpr const char *kUiStrings[1][static_cast<int>(UiText::count)] = {',
  '  { "Inicio", "Misiones", "Ajustes", "Sí", "No" }',
  '};',
  'class App {',
  '  Screen screen_ = Screen::title;',
  '  void draw() {',
  '    switch (screen_) {',
  '      case Screen::title:',
  '        draw_title();',
  '        if (pressed) { screen_ = Screen::missions; }',
  '        break;',
  '      case Screen::missions:',
  '        draw_menu();',
  '        if (open_settings) { screen_ = Screen::settings; }',
  '        break;',
  '      case Screen::settings:',
  '        draw_settings();',
  '        if (confirm_action) { open_confirmation(); }',
  '        break;',
  '      case Screen::confirm:',
  '        draw_confirmation();',
  '        if (cancelled) { screen_ = Screen::title; }',
  '        break;',
  '    }',
  '  }',
  '  void draw_title() const {',
  '    label(ui_text(UiText::welcome));',
  '    label(ui_text(UiText::choose));',
  '  }',
  '  void draw_menu() const { label(ui_text(UiText::choose)); }',
  '  void draw_settings() const { label(ui_text(UiText::preferences)); }',
  '  void draw_confirmation() const { label(ui_text(UiText::yes)); }',
  '  void open_confirmation() { screen_ = Screen::confirm; }',
  '};'
].join('\n');

const parsed = sandbox.__scanNativeStructure(source);
assert.equal(parsed.available, true, 'An enum class Screen should be detected');
assert.deepEqual(
  Array.from(parsed.states, state => state.id),
  ['title', 'missions', 'settings', 'confirm'],
  'All four screen states should appear in the explorer'
);

const byId = Object.fromEntries(Array.from(parsed.states, state => [state.id, state]));
assert.equal(byId.title.renderer, 'draw_title', 'Renderer function should be associated with the title screen');
assert.ok(byId.title.rendererLine > 0, 'Renderer source line should be available');
assert.ok(byId.title.items.includes('Inicio'), 'UiText labels should be resolved from kUiStrings');
assert.ok(byId.title.items.includes('Misiones'), 'Multiple labels should be extracted from a renderer');

const edges = new Set(Array.from(parsed.transitions, edge => edge.from + '>' + edge.to));
for (const expected of ['title>missions', 'missions>settings', 'settings>confirm', 'confirm>title']) {
  assert.ok(edges.has(expected), 'Expected screen transition was not detected: ' + expected);
}
console.log('Structure explorer scanner: OK (' + parsed.states.length + ' states, ' + parsed.transitions.length + ' transitions)');
