'use strict';
/* PS5HS Flowcode (1.1.60): traduce el programa visual de bloques (project.flowProgram)
 * a C real para el backend payload. Puro y sin DOM para poder testearlo con node.
 *
 * Bloques soportados:
 *   start   — entrada del flujo (una por flujo)
 *   end     — fin del flujo
 *   set     — sentencia C libre (una línea): {code}
 *   if      — decisión: {cond, then, else} con fusión de ramas
 *   while   — bucle: {cond, body, exit} (el cuerpo vuelve al propio while)
 *   delay   — espera en milisegundos: {ms}
 *   read    — obtención de datos: {var, source: time_us|time_ms|rand}
 *   notify  — notificación en pantalla de la PS5: {text}
 *   call    — llamada a otro flujo-función: {fn, args}
 *   return  — retorno explícito: {value?}
 *
 * Los flujos con id distinto de 'main' son funciones (static void nombre(void)).
 */
(() => {
  const VAR_TYPES = { int: 'int', unsigned: 'unsigned int', float: 'float', bool: 'bool', string: 'const char *' };
  const IDENT_RE = /^[A-Za-z_][A-Za-z0-9_]{0,47}$/;
  const READ_SOURCES = {
    time_us: 'sceKernelGetProcessTime()',
    time_ms: '(sceKernelGetProcessTime() / 1000u)',
    rand: '(rand() % 32768)'
  };

  function escC(text) {
    return String(text ?? '').replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\r?\n/g, '\\n');
  }
  function isRecord(v) { return v !== null && typeof v === 'object' && !Array.isArray(v); }
  function validIdent(name) { return IDENT_RE.test(String(name || '')); }

  /* Recorre el grafo y construye el programa. Devuelve {ok, code, diagnostics}. */
  function generate(program) {
    const diagnostics = [];
    const diag = (severity, title, message) => diagnostics.push({ severity, title, message });
    if (!isRecord(program)) return { ok: false, code: '', diagnostics: [{ severity: 'error', title: 'Programa visual ausente', message: 'No hay un programa de bloques que generar.' }] };
    const blocks = Array.isArray(program.blocks) ? program.blocks.filter(isRecord) : [];
    const vars = Array.isArray(program.vars) ? program.vars.filter(isRecord) : [];

    const byId = new Map();
    for (const block of blocks) {
      const id = String(block.id || '');
      if (!id) { diag('error', 'Bloque sin identificador', 'Un bloque del programa no tiene ID y se descartará.'); continue; }
      if (byId.has(id)) diag('error', 'Identificador duplicado', `Dos bloques comparten el ID ${id}; solo se conservará el primero.`);
      else byId.set(id, block);
    }
    /* Flujos: 'main' + cada id de flow distinto que tenga bloque start. */
    const flowIds = new Set(['main']);
    for (const block of byId.values()) {
      if (block.kind === 'start' && typeof block.flow === 'string' && block.flow.trim() && block.flow !== 'main') flowIds.add(block.flow.trim());
    }
    const starts = new Map();
    for (const flowId of flowIds) {
      const start = [...byId.values()].find(b => b.kind === 'start' && String(b.flow || 'main') === flowId);
      if (start) starts.set(flowId, start.id);
    }
    if (!starts.has('main')) {
      return { ok: false, code: '', diagnostics: [...diagnostics, { severity: 'error', title: 'Falta el bloque Inicio', message: 'El programa visual necesita exactamente un bloque Inicio en el flujo principal.' }] };
    }

    const ctx = {
      byId, starts, flowIds, diagnostics, diag,
      uses: { notify: false, delay: false, readTime: false, rand: false, stdio: false }
    };

    /* Variables: nombres seguros; el texto de init se copia tal cual (C del desarrollador). */
    const varLines = [];
    const seenVars = new Set();
    for (const v of vars) {
      const name = String(v.name || '').trim();
      const type = VAR_TYPES[v.type] ? v.type : null;
      if (!validIdent(name)) { diag('error', 'Nombre de variable inválido', `«${name}»: nombre de variable inválido; la variable no se declarará.`); continue; }
      if (seenVars.has(name)) { diag('error', 'Variable duplicada', `${name}: variable duplicada; solo se declarará la primera.`); continue; }
      if (!type) { diag('error', 'Tipo de variable desconocido', `${name}: usa int, unsigned, float, bool o string.`); continue; }
      seenVars.add(name);
      const init = String(v.init ?? '').trim();
      varLines.push(`${VAR_TYPES[type]} ${name}${init ? ' = ' + init : ''};`);
    }

    /* Validación de llamadas y navegación rota (pasada previa). */
    for (const block of byId.values()) {
      if (block.kind === 'call') {
        const fn = String(block.fn || '').trim();
        if (!fn) diag('error', 'Llamada sin función', 'Un bloque Llamar no indica a qué función llama.');
        else if (!flowIds.has(fn)) diag('error', 'Llamada a función inexistente', `El bloque Llamar apunta a «${fn}», que no tiene bloque Inicio propio.`);
        else if (!validIdent(fn)) diag('error', 'Nombre de función inválido', `«${fn}» no es un identificador C válido.`);
      }
      for (const field of ['next', 'then', 'else', 'body', 'exit']) {
        const target = String(block[field] || '');
        if (target && !byId.has(target)) diag('error', 'Conexión rota', `Un bloque ${block.kind} apunta a «${target}», que ya no existe. Reconecta el flujo.`);
      }
    }
    /* Bloques inalcanzables desde algún start: aviso informativo. */
    const reachable = new Set();
    const walk = (id) => { for (const cur of chainFrom(id)) if (!reachable.has(cur)) { reachable.add(cur); const b = byId.get(cur); if (b) for (const f of ['then', 'else', 'body']) if (b[f]) walk(b[f]); } };
    function* chainFrom(startId) { let cur = startId, guard = 0; while (cur && guard++ < 5000) { yield cur; const b = byId.get(cur); cur = b ? String(b.next || '') : ''; } }
    for (const startId of starts.values()) walk(startId);
    for (const block of byId.values()) {
      const id = String(block.id || '');
      if (block.kind !== 'start' && !reachable.has(id)) diag('warning', 'Bloque sin conexión', `El bloque ${block.kind} (${id}) no se alcanza desde ningún Inicio y no formará parte del programa.`);
    }

    /* Emisión estructurada. */
    const bodyLines = [];
    const flowOrder = ['main', ...[...flowIds].filter(f => f !== 'main')];
    const emitted = new Set();
    for (const flowId of flowOrder) {
      if (!validIdent(flowId)) { diag('error', 'Nombre de función inválido', `El flujo «${flowId}» no es un identificador C válido y no se generará.`); continue; }
      const startId = starts.get(flowId);
      if (!startId) continue;
      const out = [];
      emitChain(ctx, startId, null, '    ', out, flowId);
      if (flowId === 'main') {
        bodyLines.push('int main(void) {', ...out, '    return 0;', '}');
      } else {
        bodyLines.push(`static void ${flowId}(void) {`, ...out, '}');
      }
      bodyLines.push('');
    }
    /* Prototipos para permitir llamadas adelantadas entre funciones. */
    const prototypes = [...flowIds].filter(f => f !== 'main' && starts.has(f) && validIdent(f)).map(f => `static void ${f}(void);`);

    const header = [
      '/* Generado por PS5 Homebrew Studio · editor visual de flujos (estilo Flowcode).',
      ' * Puedes editar este C a mano; al regenerar desde el editor visual se reemplazará',
      ' * el contenido entre las marcas FLOWCODE-BEGIN/FLOWCODE-END. */'
    ];
    const includes = ['#include <stdint.h>'];
    if (ctx.uses.stdio) includes.push('#include <stdio.h>');
    if (ctx.uses.notify || ctx.uses.stdio) includes.push('#include <string.h>');
    if (ctx.uses.delay) includes.push('#include <unistd.h>');
    if (ctx.uses.rand) includes.push('#include <stdlib.h>');
    const externs = [];
    if (ctx.uses.notify) externs.push('extern int sceKernelSendNotificationRequest(int, const void *, int, int);');
    if (ctx.uses.readTime) externs.push('extern unsigned int sceKernelGetProcessTime(void);');
    const helper = [];
    if (ctx.uses.notify) {
      helper.push(
        'static void ps5hs_notify(const char *message) {',
        '    char buffer[4160];',
        '    memset(buffer, 0, sizeof(buffer));',
        '    if (message) {',
        '        snprintf(buffer + 0x2C, sizeof(buffer) - 0x2C, "%s", message);',
        '        sceKernelSendNotificationRequest(0, buffer, (int)sizeof(buffer), 1);',
        '    }',
        '}'
      );
    }
    const code = [
      ...header, '',
      ...includes, '',
      ...externs, '',
      ...helper.length ? [...helper, ''] : [],
      '/* === FLOWCODE-BEGIN (zona regenerada por el editor visual) === */',
      ...varLines.length ? [...varLines.map(l => 'static ' + l), ''] : [],
      ...prototypes.length ? [...prototypes, ''] : [],
      ...bodyLines,
      '/* === FLOWCODE-END === */',
      ''
    ].join('\n');
    return { ok: true, code, diagnostics };
  }

  function emitChain(ctx, startId, stopSet, indent, out, flowName) {
    let cur = startId, guard = 0;
    const isMain = flowName === 'main';
    while (cur) {
      if (stopSet && stopSet.has(cur)) return;
      if (++guard > 5000) { out.push(indent + '/* cadena interrumpida: sigue un ciclo que no pasa por un bloque Mientras */'); ctx.diag('error', 'Cadena cíclica sin bucle', 'Hay un ciclo de bloques Siguiente que no pasa por un bloque Mientras; reconéctalo con un Mientras.'); return; }
      const block = ctx.byId.get(cur);
      if (!block) { out.push(indent + '/* conexión rota */'); return; }
      const kind = String(block.kind || '');
      switch (kind) {
        case 'start':
        case 'end':
          if (kind === 'end') { out.push(indent + (isMain ? 'return 0;' : 'return;')); return; }
          cur = String(block.next || ''); continue;
        case 'return':
          out.push(indent + (String(block.value || '').trim() ? 'return ' + block.value + ';' : (isMain ? 'return 0;' : 'return;')));
          return;
        case 'set': {
          const statement = String(block.code || '').trim().replace(/;+\s*$/, '');
          if (!statement) ctx.diag('warning', 'Asignación vacía', 'Un bloque Asignar no tiene sentencia; se omite.');
          else out.push(indent + statement + ';');
          break;
        }
        case 'delay': {
          const ms = String(block.ms ?? '100').trim() || '100';
          if (!/^[0-9]+$/.test(ms)) ctx.diag('error', 'Espera inválida', `«${ms}» no es un número de milisegundos; se usará 100.`);
          ctx.uses.delay = true;
          out.push(indent + `usleep((useconds_t)(${/^[0-9]+$/.test(ms) ? ms : '100'}) * 1000u);`);
          break;
        }
        case 'read': {
          const varName = String(block.var || '').trim();
          const expr = READ_SOURCES[String(block.source || '')];
          if (!varName || !validIdent(varName)) ctx.diag('error', 'Lectura sin variable', 'Un bloque Leer dato no indica una variable de destino válida.');
          else if (!expr) ctx.diag('error', 'Origen de datos desconocido', `El bloque Leer dato usa «${block.source}»; usa time_us, time_ms o rand.`);
          else {
            if (block.source === 'time_us' || block.source === 'time_ms') ctx.uses.readTime = true;
            if (block.source === 'rand') ctx.uses.rand = true;
            out.push(indent + varName + ' = ' + expr + ';');
          }
          break;
        }
        case 'notify': {
          const text = String(block.text || '').trim();
          if (!text) ctx.diag('warning', 'Notificación vacía', 'Un bloque Notificar no tiene texto; se omite.');
          else { ctx.uses.notify = true; ctx.uses.stdio = true; out.push(indent + 'ps5hs_notify("' + escC(text) + '");'); }
          break;
        }
        case 'call': {
          const fn = String(block.fn || '').trim();
          if (!fn || !validIdent(fn)) ctx.diag('error', 'Llamada inválida', 'Un bloque Llamar no indica un nombre de función válido.');
          else out.push(indent + fn + '(' + String(block.args || '').trim() + ');');
          break;
        }
        case 'if': {
          const cond = String(block.cond || '').trim() || '0';
          if (!String(block.cond || '').trim()) ctx.diag('warning', 'Decisión sin condición', 'Un bloque Decisión no tiene condición; se evalúa como falsa.');
          const merge = findMerge(ctx, block);
          const stop = merge ? new Set([merge]) : null;
          out.push(indent + 'if (' + cond + ') {');
          emitChain(ctx, String(block.then || ''), stop, indent + '    ', out, flowName);
          out.push(indent + '}');
          if (block.else) { out.push(indent + 'else {'); emitChain(ctx, String(block.else || ''), stop, indent + '    ', out, flowName); out.push(indent + '}'); }
          if (merge) { cur = merge; continue; }
          return;
        }
        case 'while': {
          const cond = String(block.cond || '').trim() || '0';
          if (!String(block.cond || '').trim()) ctx.diag('warning', 'Bucle sin condición', 'Un bloque Mientras no tiene condición; el cuerpo no se ejecutará.');
          out.push(indent + 'while (' + cond + ') {');
          emitChain(ctx, String(block.body || ''), new Set([cur]), indent + '    ', out, flowName);
          out.push(indent + '}');
          cur = String(block.exit || ''); continue;
        }
        default:
          ctx.diag('error', 'Bloque desconocido', `El bloque ${kind} no se puede traducir; se omite.`);
      }
      cur = String(block.next || '');
    }
  }

  /* Fusión de ramas: primer bloque alcanzable desde «then» y desde «else» sin volver al if. */
  function findMerge(ctx, ifBlock) {
    const collect = (startId) => {
      const seen = new Set(), order = [];
      let queue = [startId], guard = 0;
      while (queue.length && guard++ < 4000) {
        const id = queue.shift();
        if (!id || id === String(ifBlock.id) || seen.has(id)) continue;
        seen.add(id); order.push(id);
        const b = ctx.byId.get(id);
        if (!b || b.kind === 'end' || b.kind === 'return') continue;
        queue.push(String(b.next || ''));
      }
      return order;
    };
    const thenOrder = collect(String(ifBlock.then || ''));
    const elseSeen = new Set(collect(String(ifBlock.else || '')));
    for (const id of thenOrder) if (elseSeen.has(id)) return id;
    return null;
  }

  window.PS5HSFlowCode = { generate, VAR_TYPES, validIdent };
})();
