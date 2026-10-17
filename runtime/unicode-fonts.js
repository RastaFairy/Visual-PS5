/* Unicode coverage helpers for PS5 Homebrew Studio's native UI build. */
(function (root) {
  'use strict';
  const MAX_FONT_BYTES = 20 * 1024 * 1024;
  const MAX_CODEPOINTS = 2500;
  const SKIP_KEYS = new Set(['dataUrl', 'base64', 'fileName', 'mime', 'id', 'assetId', 'assetPath', 'path', 'titleId', 'backend', 'format', 'formatVersion']);
  const BUILTIN_TEXT = 'Listo cruceta para navegar X para activar Teclado de pantalla Escribe con la cruceta y confirma las teclas Espacio Borrar Limpiar Aceptar Cancelar Confirmar seleccionar Atrás para guardar Edición cancelada valor actualizado Opción · ¿¡áéíóúÁÉÍÓÚñÑüÜ€…‹›';

  function collectCodepoints(project) {
    const points = new Set();
    for (let cp = 0x20; cp <= 0x7e; cp++) points.add(cp);
    for (const char of BUILTIN_TEXT) points.add(char.codePointAt(0));
    const visit = (value, key) => {
      if (typeof value === 'string') {
        if (!SKIP_KEYS.has(key)) for (const char of value) points.add(char.codePointAt(0));
      } else if (Array.isArray(value)) {
        value.forEach(item => visit(item, ''));
      } else if (value && typeof value === 'object') {
        for (const [childKey, childValue] of Object.entries(value)) {
          if (SKIP_KEYS.has(childKey)) continue;
          visit(childValue, childKey);
        }
      }
    };
    visit(project, '');
    const sorted = [...points].filter(cp => Number.isInteger(cp) && cp >= 0x20 && cp <= 0x10ffff && !(cp >= 0xd800 && cp <= 0xdfff)).sort((a, b) => a - b);
    if (sorted.length > MAX_CODEPOINTS) {
      throw new Error('El proyecto usa ' + sorted.length + ' caracteres Unicode distintos; el límite es ' + MAX_CODEPOINTS + '. Reduce los caracteres únicos o usa fuentes por pantalla.');
    }
    return sorted;
  }

  function prepareFontAsset(asset) {
    const name = String(asset && (asset.fileName || asset.name) || '');
    if (!/\.ttf$/i.test(name)) throw new Error('La fuente debe ser TrueType .ttf. Los archivos OTF/CFF no son compatibles con el generador de atlas.');
    const size = Number(asset && asset.size || 0);
    if (size > MAX_FONT_BYTES) throw new Error('La fuente TTF supera el límite de 20 MiB.');
    const dataUrl = String(asset && asset.dataUrl || '');
    const comma = dataUrl.indexOf(',');
    if (!dataUrl.startsWith('data:') || comma < 0) throw new Error('No se pudieron leer los datos de la fuente TTF seleccionada.');
    const base64 = dataUrl.slice(comma + 1);
    if (!base64 || base64.length > Math.ceil(MAX_FONT_BYTES * 4 / 3) + 16) throw new Error('El archivo TTF está vacío o supera el límite de 20 MiB.');
    return { fileName: name, size, base64 };
  }

  const api = { collectCodepoints, prepareFontAsset, MAX_FONT_BYTES, MAX_CODEPOINTS };
  root.PS5HSUnicodeFonts = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
