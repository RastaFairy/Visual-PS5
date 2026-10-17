'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { normalizeScreenLayers, nextZIndexForNewComponent } = require('./layer-model.js');

const legacy = [
  { id: 'image-machine', type: 'image' },
  { id: 'title', type: 'title' },
  { id: 'panel', type: 'panel' },
  { id: 'button', type: 'button' },
  { id: 'card', type: 'card' },
  { id: 'detail', type: 'text' }
];
normalizeScreenLayers(legacy);
assert.deepEqual(legacy.slice().sort((a, b) => a.zIndex - b.zIndex).map(c => c.id), [
  'panel', 'card', 'image-machine', 'button', 'detail', 'title'
]);
assert.equal(new Set(legacy.map(c => c.zIndex)).size, legacy.length, 'default layer values must be unique');

const legacyNumbered = [
  { id: 'image-machine', type: 'image', zIndex: 10 },
  { id: 'title', type: 'title', zIndex: 20 },
  { id: 'panel', type: 'panel', zIndex: 30 },
  { id: 'button', type: 'button', zIndex: 40 },
  { id: 'card', type: 'card', zIndex: 50 },
  { id: 'detail', type: 'text', zIndex: 60 }
];
normalizeScreenLayers(legacyNumbered);
assert.deepEqual(legacyNumbered.slice().sort((a, b) => a.zIndex - b.zIndex).map(c => c.id), [
  'panel', 'card', 'image-machine', 'button', 'detail', 'title'
], 'legacy array-index zIndex values must migrate to semantic order');
assert.equal(new Set(legacyNumbered.map(c => c.zIndex)).size, legacyNumbered.length);

const explicit = [
  { id: 'front', type: 'text', zIndex: 20 },
  { id: 'back', type: 'panel', zIndex: 10 }
];
normalizeScreenLayers(explicit);
assert.deepEqual(explicit.slice().sort((a, b) => a.zIndex - b.zIndex).map(c => c.id), ['back', 'front']);

const mixed = [
  { id: 'known', type: 'button', zIndex: 20 },
  { id: 'missing', type: 'panel' }
];
normalizeScreenLayers(mixed);
assert.ok(mixed.every(c => Number.isFinite(c.zIndex)), 'missing layer values must be completed');
assert.equal(new Set(mixed.map(c => c.zIndex)).size, mixed.length, 'mixed order must remain unique');
const defaults = [{ id: 'panel', type: 'panel', zIndex: 10 }, { id: 'image', type: 'image', zIndex: 20 }, { id: 'title', type: 'title', zIndex: 30 }];
const newPanelIndex = nextZIndexForNewComponent(defaults, 'panel');
assert.equal(newPanelIndex, 20, 'new background panels should be inserted behind existing content but after background panels');
assert.ok(newPanelIndex < defaults.find(c => c.id === 'image').zIndex, 'new panel must remain behind images');
assert.deepEqual(defaults.slice().sort((a, b) => a.zIndex - b.zIndex).map(c => c.id), ['panel', 'image', 'title']);
const styles = fs.readFileSync(path.join(__dirname, '..', 'styles.css'), 'utf8');
assert.doesNotMatch(styles.match(/\.canvas-item\.selected\{[^}]*\}/)?.[0] || '', /z-index\s*:/, 'selecting a component must not raise it above its real layer');
assert.match(styles, /\.canvas-item\.image\.asset-image\{background:transparent!important;border:0!important;?\}/, 'linked images should preserve alpha transparency');
console.log('Layer model normalization and visual stacking: OK');
