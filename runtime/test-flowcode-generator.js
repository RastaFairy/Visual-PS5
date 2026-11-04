'use strict';
/* Regresiones del generador Flowcode: bloques → C para el backend payload. */
const assert = require('node:assert/strict');
global.window = {};
require('./flowcode-generator.js');
const gen = global.window.PS5HSFlowCode;
assert.ok(gen && typeof gen.generate === 'function', 'el módulo Flowcode debe exponer generate()');

function build(blocks, vars) {
  return { schemaVersion: 1, enabled: true, vars: vars || [], blocks };
}
let startSeq = 0;
const start = (id, next, flow) => ({ id, kind: 'start', flow: flow || 'main', next });
const end = () => ({ id: 'e1', kind: 'end', flow: 'main' });

/* 1. Programa lineal completo: set → delay → read → notify → end */
{
  const r = gen.generate(build([
    start('s1', 'b2'),
    { id: 'b2', kind: 'set', code: 'contador = contador + 1;', next: 'b3' },
    { id: 'b3', kind: 'delay', ms: '250', next: 'b4' },
    { id: 'b4', kind: 'read', var: 'contador', source: 'time_ms', next: 'b5' },
    { id: 'b5', kind: 'notify', text: 'Hola PS5', next: 'e1' },
    end()
  ], [{ name: 'contador', type: 'int', init: '0' }]));
  assert.equal(r.ok, true, 'el programa lineal debe generar');
  assert.match(r.code, /int contador = 0;/, 'declara la variable con su valor inicial');
  assert.match(r.code, /contador = contador \+ 1;/, 'emite la asignación');
  assert.match(r.code, /usleep\(\(useconds_t\)\(250\) \* 1000u\);/, 'emite la espera en ms');
  assert.match(r.code, /contador = \(sceKernelGetProcessTime\(\) \/ 1000u\);/, 'emite la lectura de tiempo');
  assert.match(r.code, /ps5hs_notify\("Hola PS5"\);/, 'emite la notificación');
  assert.match(r.code, /sceKernelSendNotificationRequest/, 'declara el externo de notificaciones');
  assert.match(r.code, /int main\(void\)/, 'el flujo main es main()');
  assert.match(r.code, /FLOWCODE-BEGIN/, 'marca la zona regenerada');
}

/* 2. Decisión con fusión de ramas: el bloque de fusión se emite UNA vez */
{
  const r = gen.generate(build([
    start('s1','i1'),
    { id: 'i1', kind: 'if', cond: 'contador > 3', then: 'a1', else: 'b1' },
    { id: 'a1', kind: 'set', code: 'contador = 10;', next: 'm1' },
    { id: 'b1', kind: 'set', code: 'contador = 20;', next: 'm1' },
    { id: 'm1', kind: 'notify', text: 'fin', next: 'e1' },
    end()
  ]));
  assert.equal(r.ok, true);
  assert.match(r.code, /if \(contador > 3\) \{/, 'emite la condición');
  assert.match(r.code, /else \{/, 'emite la rama else');
  assert.equal((r.code.match(/ps5hs_notify\("fin"\);/g) || []).length, 1, 'la rama se fusiona: el bloque común se emite una sola vez');
}

/* 3. Bucle Mientras: el cuerpo vuelve al while y se emite una vez */
{
  const r = gen.generate(build([
    start('s1','w1'),
    { id: 'w1', kind: 'while', cond: 'quedan > 0', body: 'c1', exit: 'e1' },
    { id: 'c1', kind: 'set', code: 'quedan = quedan - 1;', next: 'w1' },
    end()
  ], [{ name: 'quedan', type: 'int', init: '5' }]));
  assert.equal(r.ok, true);
  assert.match(r.code, /while \(quedan > 0\) \{/, 'emite el bucle');
  assert.equal((r.code.match(/quedan = quedan - 1;/g) || []).length, 1, 'el cuerpo se emite una sola vez');
}

/* 4. Funciones: prototipo + definición + llamada */
{
  const r = gen.generate(build([
    start('s2','n1','parpadear'),
    { id: 'n1', kind: 'notify', text: 'parpadeo', next: 'e2' },
    { id: 'e2', kind: 'end', flow: 'parpadear' },
    start('m1','m2b'),
    { id: 'm2b', kind: 'call', fn: 'parpadear', next: 'e1' },
    end()
  ]));
  assert.equal(r.ok, true);
  assert.match(r.code, /static void parpadear\(void\);/, 'prototipo adelantado');
  assert.match(r.code, /static void parpadear\(void\) \{/, 'definición de la función');
  assert.match(r.code, /parpadear\(\);/, 'la llamada se emite');
}

/* 5. Programa sin Inicio: error fatal controlado */
{
  const r = gen.generate(build([{ id: 'x', kind: 'set', code: 'a = 1;' }]));
  assert.equal(r.ok, false, 'sin bloque Inicio no se genera');
  assert.ok(r.diagnostics.some(d => /Inicio/.test(d.title)), 'el diagnóstico lo explica');
}

/* 6. Variables inválidas o duplicadas: diagnóstico sin romper la generación */
{
  const r = gen.generate(build([
    start('s1','b2'), { id: 'b2', kind: 'notify', text: 'x', next: 'e1' }, end()
  ], [{ name: '2mala', type: 'int', init: '0' }, { name: 'contador', type: 'int', init: '1' }, { name: 'contador', type: 'int', init: '2' }]));
  assert.equal(r.ok, true);
  assert.ok(r.diagnostics.some(d => /inválido/.test(d.message) && /2mala/.test(d.message)), 'identificador inválido diagnosticado');
  assert.ok(r.diagnostics.some(d => /duplicada/.test(d.message)), 'duplicado diagnosticado');
  assert.match(r.code, /int contador = 1;/, 'solo la primera declaración se emite');
  assert.doesNotMatch(r.code, /int contador = 2;/, 'la segunda no se emite');
}

/* 7. Conexión rota: aviso y término limpio */
{
  const r = gen.generate(build([
    start('s1','b2'), { id: 'b2', kind: 'set', code: 'a = 1;', next: 'fantasma' }, end()
  ]));
  assert.equal(r.ok, true);
  assert.ok(r.diagnostics.some(d => /Conexión rota/.test(d.title)), 'la conexión rota se diagnostica');
  assert.match(r.code, /a = 1;/, 'el bloque previo se mantiene');
}

/* 8. Determinismo: dos ejecuciones idénticas */
{
  const program = build([start('s1','b2'), { id: 'b2', kind: 'notify', text: 'd', next: 'e1' }, end()]);
  assert.equal(gen.generate(program).code, gen.generate(program).code, 'misma entrada, mismo C');
}

/* 9. Lectura aleatoria y tiempo en microsegundos */
{
  const r = gen.generate(build([
    start('s1','b2'),
    { id: 'b2', kind: 'read', var: 'azar', source: 'rand', next: 'b3' },
    { id: 'b3', kind: 'read', var: 't0', source: 'time_us', next: 'e1' },
    end()
  ], [{ name: 'azar', type: 'unsigned', init: '0' }, { name: 't0', type: 'unsigned', init: '0' }]));
  assert.match(r.code, /azar = \(rand\(\) % 32768\);/, 'fuente rand');
  assert.match(r.code, /t0 = sceKernelGetProcessTime\(\);/, 'fuente time_us');
  assert.match(r.code, /#include <stdlib\.h>/, 'incluye stdlib para rand');
}

console.log('PASS flowcode generator: lineal, fusión de ramas, bucles, funciones, lecturas de datos y diagnósticos de flujo roto.');
