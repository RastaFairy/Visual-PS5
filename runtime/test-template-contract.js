// Contrato estático entre la plantilla AGC del IDE y el ejemplo upstream probado
// en hardware (toolchains/ps5link-sdk/examples/gpu_cube/main.c). Previene la clase
// de regresión que produjo el arranque sin imagen de 2026-10-24: la plantilla se
// desvió del camino probado (audio antes del primer envío AGC, atributo de búfer
// recortado) y ningún test lo detectó porque solo validaban el texto generado.
'use strict';
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const template = fs.readFileSync(path.join(__dirname, 'templates', 'ps5link-platform-game.c'), 'utf8');
const referencePath = path.join(__dirname, '..', 'toolchains', 'ps5link-sdk', 'examples', 'gpu_cube', 'main.c');
const reference = fs.existsSync(referencePath) ? fs.readFileSync(referencePath, 'utf8') : '';

// 1. El primer envío de comandos AGC nunca puede depender del audio:
// la primera llamada a sceAgcDriverSubmitDcb debe aparecer en el fuente
// antes que la primera apertura de sceAudioOutOpen.
const firstSubmit = template.indexOf('sceAgcDriverSubmitDcb(&submit)');
const firstAudioOpen = template.indexOf('audio_port=sceAudioOutOpen(');
assert.ok(firstSubmit >= 0, 'la plantilla debe enviar el DCB con sceAgcDriverSubmitDcb');
assert.ok(firstAudioOpen < 0 || firstSubmit < firstAudioOpen,
  'el audio no puede inicializarse antes del primer envío AGC: la referencia gpu_cube no lo hace y bloquea el primer flip');

// 2. Sin esperas de driver que bloqueen el hilo fuera del camino probado.
assert.ok(!template.includes('sceAgcDriverWaitUntilSafeForRendering'),
  'la plantilla no debe llamar sceAgcDriverWaitUntilSafeForRendering: la referencia envía y espera vblank');

// 3. El atributo de buffers de VideoOut debe alojar la estructura completa de 80
// bytes; la referencia gpu_cube usa 64 y por eso el IDE la amplió: no retroceder.
const attrMatch = template.match(/unsigned char attr\[(\d+)\]/);
assert.ok(attrMatch, 'la plantilla debe declarar un búfer de atributo con tamaño explícito');
assert.ok(parseInt(attrMatch[1], 10) >= 80,
  `el búfer de SceVideoOutBufferAttribute2 debe ser de 80 bytes o más (es ${attrMatch[1]})`);

// 4. La lista de registros del render target debe coincidir con la referencia.
const offsets = (src, marker) => {
  const start = src.indexOf(marker);
  assert.ok(start >= 0, `no se encontró ${marker}`);
  const body = src.slice(start, src.indexOf('};', start));
  const values = [...body.matchAll(/0x[0-9A-Fa-f]{4}/g)].map(m => m[0].toLowerCase());
  return values;
};
if (reference) {
  const templateOffsets = offsets(template, 'static const unsigned short offsets[16]');
  const referenceOffsets = offsets(reference, 'kRenderTargetOffsets[16]');
  assert.deepStrictEqual(templateOffsets, referenceOffsets,
    'los offsets del bloque de render target deben ser byte a byte los de gpu_cube');

  // 5. La base de registros de usuario del stage GS es un contrato del binario shader.
  assert.ok(template.includes('#define GS_USER_DATA_BASE 0x008C'),
    'GS_USER_DATA_BASE debe seguir siendo 0x008C (contrato AgcShader/SharpProspero)');
  assert.ok(reference.includes('#define GS_USER_DATA_BASE 0x008C'),
    'la referencia cambió: revisar el contrato antes de actualizar la plantilla');

  // 6. El typedef CxRegister y la revisión de defaults son parte del mismo contrato.
  const cxLine = (src) => (src.match(/typedef struct \{ unsigned short offset; unsigned short pad; unsigned int value; \} CxRegister;/) || [])[0];
  assert.ok(cxLine(template) && cxLine(template) === cxLine(reference),
    'el layout de CxRegister debe coincidir con SharpProspero/gpu_cube');
  assert.ok(template.includes('sceAgcInit(&agcState,8)') || template.includes('sceAgcInit(&agcState, 8)'),
    'la revisión de defaults de sceAgcInit debe seguir siendo 8');
}

// 7. Guarda contra envíos vacíos: un DCB sin palabras nunca debe salir por la cola.
assert.ok(/submit\.wordCount==0/.test(template),
  'el envío debe rechazar un DCB vacío en lugar de mandar cero palabras');

// 8. Trazas de diagnóstico solo en Debug; los avisos de error siempre.
assert.ok(template.includes('#ifdef PS5HS_DEBUG') && template.includes('#define PS5HS_TRACE(msg) notify(msg)'),
  'las trazas de hitos deben quedar condicionadas a PS5HS_DEBUG');
assert.ok(template.includes('PS5HS_TRACE(PS5HS_GAME_TITLE ": primer DCB AGC enviado")'),
  'el hito de primer envío debe pasar por PS5HS_TRACE');
assert.ok(template.includes(': renderer detenido por un error AGC') &&
  !template.includes('PS5HS_TRACE(PS5HS_GAME_TITLE ": renderer detenido'),
  'los avisos de error no se silencian en Release');

// 9. Presentación opt-in: el motor no impone explorador, decorado, partículas ni marcos.
for (const macro of ['PS5HS_GAME_EXPLORER_ENABLED', 'PS5HS_GAME_DECOR_ENABLED', 'PS5HS_GAME_PARTICLES_ENABLED', 'PS5HS_GAME_MENU_FRAME_ENABLED']) {
  assert.ok(template.includes(macro), `la decoración debe estar gobernada por ${macro}`);
}
assert.ok(/#if PS5HS_GAME_EXPLORER_ENABLED\s*\n\s*add_nebula_explorer/.test(template),
  'el explorador debe dibujarse solo con el toggle del modelo');
assert.ok(!/#if PS5HS_GAME_MENU_FRAME_ENABLED/.test('') && template.indexOf('#if PS5HS_GAME_MENU_FRAME_ENABLED') < template.indexOf('ui_rect(ui,470,76,980,500'),
  'el marco de menú hardcodeado debe quedar dentro del bloque opt-in');

// 10. Los lotes cuentan lo que descartan: el truncado silencioso está prohibido.
assert.ok(template.includes('unsigned int dropped;') && (template.match(/\{b->dropped\+\+;return;\}/g) || []).length >= 6
  && /if\(w>0&&h>0\)b->dropped\+\+;return;/.test(template),
  'cada guarda de capacidad del lote debe incrementar el contador de descartes');
assert.ok(template.includes(': geometria descartada por lotes llenos: '),
  'los descartes deben notificarse al usuario, nunca callarse');

console.log('PASS template contract: la plantilla AGC mantiene el camino probado por gpu_cube (envío antes de audio, contratos de registros, Debug/Release y presentación opt-in).');
