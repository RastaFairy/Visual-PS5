'use strict';
const assert = require('node:assert/strict');
const unicode = require('./unicode-fonts.js');

const project = {
  name: 'Prueba Unicode',
  components: [{ label: 'Español áéíóú ñ · Русский язык · Ελληνικά · 日本語かな漢字 · 简体中文繁體中文 · 한국어 · français Grüße 😀' }],
  screens: [{ name: 'Ajustes 日本語' }],
  flows: [{ message: '中文提示', value: 'Тест' }],
  assets: [{ fileName: 'fuente-privada.ttf', dataUrl: 'data:font/ttf;base64,SHOULD_NOT_BE_COLLECTED', mime: 'font/🧬' }]
};
const points = unicode.collectCodepoints(project);
for (const char of 'ñРусскийΕλληνικά日本語简体中文繁體中文한국어Grüße😀') {
  assert.ok(points.includes(char.codePointAt(0)), `missing codepoint U+${char.codePointAt(0).toString(16)}`);
}
assert.deepEqual(points, [...new Set(points)].sort((a, b) => a - b), 'codepoints must be unique and ascending');
assert.ok(!points.includes('🧬'.codePointAt(0)), 'asset MIME metadata should not be scanned');

const base64 = Buffer.alloc(256, 1).toString('base64');
const asset = unicode.prepareFontAsset({ fileName: 'font.ttf', size: 256, dataUrl: `data:font/ttf;base64,${base64}` });
assert.equal(asset.fileName, 'font.ttf');
assert.equal(asset.size, 256);
assert.equal(asset.base64, base64);
assert.throws(() => unicode.prepareFontAsset({ fileName: 'font.otf', size: 256, dataUrl: `data:font/otf;base64,${base64}` }), /\.ttf/);
assert.throws(() => unicode.prepareFontAsset({ fileName: 'font.ttf', size: unicode.MAX_FONT_BYTES + 1, dataUrl: `data:font/ttf;base64,${base64}` }), /20 MiB/);
assert.throws(() => unicode.prepareFontAsset({ fileName: 'font.ttf', size: 256, dataUrl: 'data:font/ttf;base64,' }), /vacío|supera/);
assert.throws(() => unicode.collectCodepoints({ text: Array.from({length: 2501}, (_, i) => String.fromCodePoint(0x4000 + i)).join('') }), /2500/);
console.log('PASS Unicode fonts: multilingual codepoints, sorting/deduplication, TTF validation, size limits and maximum repertoire');
