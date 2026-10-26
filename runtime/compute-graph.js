'use strict';
(function attachPS5HSComputeGraph(root) {
  const clone = value => JSON.parse(JSON.stringify(value));
  const safeId = value => /^[A-Za-z_][A-Za-z0-9_-]{0,63}$/.test(String(value || ''));
  const safeRevisionId = value => safeId(String(value || '').replace(/-/g, '_'));
  const newRevisionId = () => { try { return `rev_${crypto.randomUUID()}`; } catch { return `rev_${Date.now().toString(36)}_${Math.random().toString(36).slice(2)}`; } };
  const DEFAULT_SOURCE = `#version 450\nlayout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;\nlayout(set = 0, binding = 0, rgba8) writeonly uniform image2D outputImage;\nvoid main()\n{\n    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);\n    ivec2 size = imageSize(outputImage);\n    if (any(greaterThanEqual(pixel, size))) return;\n    vec2 uv = vec2(pixel) / max(vec2(size - 1), vec2(1.0));\n    imageStore(outputImage, pixel, vec4(uv, 0.25 + 0.75 * uv.x, 1.0));\n}\n`;
  function createDefaultGraph() {
    return {
      schema: 'ps5hs-vulkan-compute-graph', version: 1, revisionId: newRevisionId(),
      target: { api: 'Vulkan', shaderTarget: 'vulkan1.2', width: 1920, height: 1080 },
      resources: [{ id: 'outputImage', name: 'Imagen de salida', kind: 'storage-image', format: 'rgba8', width: 1920, height: 1080, externalInput: false }],
      passes: [{ id: 'gradient', name: 'Gradiente de prueba', localSize: { x: 8, y: 8, z: 1 }, dispatch: { x: 1920, y: 1080, z: 1 }, bindings: [{ resourceId: 'outputImage', binding: 0, access: 'write' }], source: DEFAULT_SOURCE }],
      reports: []
    };
  }
  function normalizeGraph(value) {
    const fallback = createDefaultGraph();
    if (!value || typeof value !== 'object' || Array.isArray(value)) return fallback;
    const graph = { ...fallback, ...value };
    graph.target = { ...fallback.target, ...(value.target || {}) };
    graph.resources = Array.isArray(value.resources) ? value.resources : fallback.resources;
    graph.passes = Array.isArray(value.passes) ? value.passes : fallback.passes;
    graph.reports = Array.isArray(value.reports) ? value.reports : [];
    // Older snapshots may contain UUIDs that begin with a digit. Keep their
    // measurements, but move the graph to a safe revision so they cannot be
    // mistaken for measurements of the updated graph.
    if (!safeRevisionId(graph.revisionId)) graph.revisionId = newRevisionId();
    return graph;
  }
  function validateGraph(value) {
    const graph = normalizeGraph(value), diagnostics = [], resourceById = new Map(), passById = new Map();
    const add = (severity, title, message, location, fix = '') => diagnostics.push({ severity, title, message, location, fix });
    if (graph.schema !== 'ps5hs-vulkan-compute-graph' || graph.version !== 1) add('error', 'Formato de grafo no compatible', 'El grafo debe usar ps5hs-vulkan-compute-graph versión 1.', 'Compute Graph');
    if (graph.target?.api !== 'Vulkan') add('error', 'API de cómputo no compatible', 'Esta primera integración compila shaders Vulkan/SPIR-V.', 'Destino');
    if (graph.target?.shaderTarget !== 'vulkan1.2') add('error', 'Destino de shader no compatible', 'La primera integración compila SPIR-V para Vulkan 1.2.', 'Destino');
    if (!safeRevisionId(graph.revisionId)) add('error', 'Revisión del grafo inválida', 'El grafo necesita un revisionId seguro para asociar las mediciones GPU.', 'Compute Graph');
    if (!Number.isInteger(graph.target?.width) || !Number.isInteger(graph.target?.height) || graph.target.width < 1 || graph.target.height < 1 || graph.target.width > 16384 || graph.target.height > 16384) add('error', 'Tamaño de destino inválido', 'El destino debe medir entre 1 y 16384 píxeles por eje.', 'Destino');
    if (!graph.passes.length) add('error', 'Grafo sin pases', 'Añade al menos un pase de cómputo con un shader GLSL.', 'Compute Graph');
    if (graph.passes.length > 64) add('error', 'Demasiados pases', 'El límite de esta versión es 64 pases por grafo.', 'Compute Graph');
    if (graph.resources.length > 128) add('error', 'Demasiados recursos', 'El límite de esta versión es 128 imágenes de almacenamiento.', 'Recursos');
    graph.resources.forEach((resource, index) => {
      const where = `Recurso ${resource?.name || index + 1}`;
      if (!resource || !safeId(resource.id)) add('error', 'Identificador de recurso inválido', 'Usa letras, números, guion y guion bajo; el primer carácter debe ser una letra o guion bajo.', where);
      else if (resourceById.has(resource.id)) add('error', 'Identificador de recurso duplicado', `El identificador ${resource.id} ya existe.`, where);
      else resourceById.set(resource.id, resource);
      if (resource?.kind !== 'storage-image') add('error', 'Tipo de recurso no compatible', 'Solo se admiten imágenes Vulkan de almacenamiento en esta versión.', where);
      if (!['rgba8', 'rgba16f', 'r32f', 'rg16f'].includes(resource?.format)) add('error', 'Formato de imagen no compatible', 'Usa rgba8, rgba16f, r32f o rg16f.', where);
      if (!Number.isInteger(resource?.width) || !Number.isInteger(resource?.height) || resource.width < 1 || resource.height < 1 || resource.width > 16384 || resource.height > 16384) add('error', 'Dimensiones de recurso inválidas', 'Cada imagen debe medir entre 1 y 16384 píxeles por eje.', where);
      if (typeof resource?.externalInput !== 'boolean') add('error', 'Uso externo no declarado', 'Indica si los datos los aporta la aplicación antes del grafo.', where);
    });
    graph.passes.forEach((pass, index) => {
      const where = `Pase ${pass?.name || index + 1}`;
      const source = String(pass?.source || '');
      if (!pass || !safeId(pass.id)) add('error', 'Identificador de pase inválido', 'Usa un identificador técnico seguro (letras, números, guion o guion bajo).', where);
      else if (passById.has(pass.id)) add('error', 'Identificador de pase duplicado', `El identificador ${pass.id} ya existe.`, where);
      else passById.set(pass.id, pass);
      for (const axis of ['x', 'y', 'z']) {
        const local = Number(pass?.localSize?.[axis]), dispatch = Number(pass?.dispatch?.[axis]);
        if (!Number.isInteger(local) || local < 1 || local > 1024) add('error', `Tamaño local ${axis.toUpperCase()} inválido`, 'Cada dimensión local debe ser un entero entre 1 y 1024.', where);
        if (!Number.isInteger(dispatch) || dispatch < 1 || dispatch > 4194240) add('error', `Tamaño de despacho ${axis.toUpperCase()} inválido`, 'Cada dimensión lógica debe ser un entero positivo; los grupos no pueden superar 65535.', where);
        else if (Number.isInteger(local) && Math.ceil(dispatch / local) > 65535) add('error', `Despacho ${axis.toUpperCase()} excede Vulkan`, 'El número de grupos de trabajo por eje supera el límite garantizado 65535.', where, 'Reduce la dimensión o aumenta el tamaño local.');
      }
      if (Number(pass?.localSize?.x) * Number(pass?.localSize?.y) * Number(pass?.localSize?.z) > 1024) add('error', 'Grupo local demasiado grande', 'El producto de las dimensiones locales supera 1024 invocaciones.', where);
      if (!Array.isArray(pass?.bindings)) add('error', 'Enlaces de recursos inválidos', 'Cada pase debe declarar sus recursos y bindings Vulkan.', where);
      const usedBindings = new Set();
      for (const binding of Array.isArray(pass?.bindings) ? pass.bindings : []) {
        if (!resourceById.has(binding?.resourceId)) add('error', 'Recurso enlazado inexistente', `No existe el recurso ${String(binding?.resourceId || '(vacío)')}.`, where);
        if (!Number.isInteger(binding?.binding) || binding.binding < 0 || binding.binding > 31) add('error', 'Binding Vulkan inválido', 'El binding debe ser un entero entre 0 y 31.', where);
        else if (usedBindings.has(binding.binding)) add('error', 'Binding repetido', `El binding ${binding.binding} aparece más de una vez en el pase.`, where);
        else usedBindings.add(binding.binding);
        if (!['read', 'write', 'readwrite'].includes(binding?.access)) add('error', 'Acceso de recurso inválido', 'Selecciona lectura, escritura o lectura y escritura.', where);
        if (Number.isInteger(binding?.binding)) {
          const layoutPattern = new RegExp(`layout\\s*\\(([^)]*\\bbinding\\s*=\\s*${binding.binding}\\b[^)]*)\\)\\s*([^;]*\\buniform\\s+[^;]*)`, 's');
          const declaration = layoutPattern.exec(source);
          if (!declaration || !/\bimage2D\b/.test(declaration[2])) add('error', 'Imagen GLSL no declarada', `El binding ${binding.binding} debe declarar una imagen image2D en GLSL.`, where);
          else {
            const set = /\bset\s*=\s*(\d+)\b/.exec(declaration[1]);
            if (set && Number(set[1]) !== 0) add('error', 'Descriptor set no compatible', `El binding ${binding.binding} debe usar set = 0.`, where);
            const resource = resourceById.get(binding.resourceId);
            const imageFormat = /\b(rgba8|rgba16f|rg16f|r32f)\b/.exec(declaration[1])?.[1];
            if (resource && imageFormat !== resource.format) add('error', 'Formato GLSL y recurso distintos', `El binding ${binding.binding} debe declarar layout(${resource.format}) para ${resource.name || resource.id}.`, where);
            if (binding.access === 'read' && !/\breadonly\b/.test(declaration[2])) add('error', 'Acceso GLSL demasiado amplio', `El binding ${binding.binding} se declara de solo lectura en el grafo y debe usar readonly en GLSL.`, where);
            if (binding.access === 'write' && !/\bwriteonly\b/.test(declaration[2])) add('error', 'Acceso GLSL demasiado amplio', `El binding ${binding.binding} se declara de solo escritura en el grafo y debe usar writeonly en GLSL.`, where);
            if (binding.access === 'readwrite' && /\b(?:readonly|writeonly)\b/.test(declaration[2])) add('error', 'Acceso GLSL insuficiente', `El binding ${binding.binding} permite lectura y escritura en el grafo; GLSL no puede restringirlo a un solo sentido.`, where);
          }
        }
      }
      if (!source.trim()) add('error', 'Shader vacío', 'El pase necesita código GLSL de cómputo.', where);
      if (source.length > 512 * 1024) add('error', 'Shader demasiado grande', 'El máximo por shader es 512 KiB.', where);
      if (!/^\s*#version\s+450\b/m.test(source)) add('error', 'Versión GLSL no declarada', 'Los shaders deben declarar #version 450.', where);
      if (!/\bvoid\s+main\s*\(/.test(source)) add('error', 'Función main ausente', 'El shader debe declarar void main().', where);
      if (!/\blayout\s*\([^)]*\blocal_size_x\s*=\s*\d+[^)]*\)\s*in\s*;/s.test(source)) add('error', 'Tamaño local GLSL ausente', 'Declara local_size_x, local_size_y y local_size_z con layout(... ) in;.', where);
      for (const axis of ['x','y','z']) {
        const expected = Number(pass?.localSize?.[axis]);
        if (Number.isInteger(expected) && expected > 0 && !new RegExp(`\\blocal_size_${axis}\\s*=\\s*${expected}\\b`).test(source)) add('error', `local_size_${axis} no coincide`, `La fuente GLSL debe usar local_size_${axis} = ${expected}, como declara el pase.`, where);
      }
      const declaredImageBindings = new Set();
      for (const descriptor of source.matchAll(/layout\s*\(([^)]*)\)\s*([^;]*\buniform\s+[^;]*\bimage2D\b[^;]*);/gs)) {
        const declared = /\bbinding\s*=\s*(\d+)\b/.exec(descriptor[1]);
        if (!declared) { add('error', 'Imagen GLSL sin binding', 'Cada imagen image2D debe declarar un binding que exista en el grafo.', where); continue; }
        const bindingIndex = Number(declared[1]);
        if (declaredImageBindings.has(bindingIndex)) add('error', 'Binding GLSL duplicado', `La imagen image2D declara binding=${bindingIndex} más de una vez.`, where);
        declaredImageBindings.add(bindingIndex);
        if (!usedBindings.has(bindingIndex)) add('error', 'Binding GLSL huérfano', `El shader declara binding=${bindingIndex}, pero el pase no lo enlaza con ningún recurso.`, where);
      }
      const lastWriter = new Map();
      for (const prior of graph.passes.slice(0, index)) for (const output of (Array.isArray(prior?.bindings) ? prior.bindings : []).filter(item => ['write', 'readwrite'].includes(item?.access))) lastWriter.set(output.resourceId, prior.id);
      for (const input of (Array.isArray(pass?.bindings) ? pass.bindings : []).filter(item => ['read', 'readwrite'].includes(item?.access))) {
        const resource = resourceById.get(input.resourceId);
        if (resource && !resource.externalInput && !lastWriter.has(input.resourceId)) add('error', 'Lectura sin productor', `El recurso ${resource.name || resource.id} se lee antes de que un pase lo escriba y no está marcado como entrada externa.`, where, 'Añade un pase productor anterior o marca el recurso como entrada externa.');
      }
    });
    if (graph.passes.every(pass => Array.isArray(pass?.bindings) && !pass.bindings.some(binding => ['write', 'readwrite'].includes(binding?.access)))) add('warning', 'Grafo sin salida escrita', 'Ningún pase declara una escritura de imagen; no se generará una salida verificable.', 'Compute Graph');
    return diagnostics;
  }
  function workgroups(pass) {
    return ['x','y','z'].map(axis => Math.ceil(Number(pass.dispatch[axis]) / Number(pass.localSize[axis])));
  }
  function buildManifest(graph, projectName) {
    const normalized = normalizeGraph(graph);
    return {
      schema: normalized.schema, version: normalized.version, revisionId: normalized.revisionId, projectName: String(projectName || 'VulkanCompute'),
      target: clone(normalized.target), resources: clone(normalized.resources),
      passes: normalized.passes.map(pass => ({ id: pass.id, name: pass.name, shader: `shaders/${pass.id}.comp`, spirv: `build/spirv/${pass.id}.spv`, localSize: clone(pass.localSize), dispatch: clone(pass.dispatch), workgroups: workgroups(pass), bindings: clone(pass.bindings) })),
      hardwareValidation: { status: 'not-run', reportSchema: 'ps5hs-vulkan-compute-report', note: 'La compilación SPIR-V no ejecuta el shader en GPU. Importa un informe real del runtime para registrar métricas de hardware.' }
    };
  }
  function validateReport(value, expectedPasses, expectedRevisionId) {
    const issues = [];
    if (!value || typeof value !== 'object' || Array.isArray(value)) return ['El informe debe ser un objeto JSON.'];
    const allowedFields = new Set(['schema','version','graphRevisionId','capturedAt','runId','device','driver','runtime','target','results']);
    for (const key of Object.keys(value)) if (!allowedFields.has(key)) issues.push(`El informe contiene un campo no reconocido: ${key}.`);
    if (value.schema !== 'ps5hs-vulkan-compute-report' || value.version !== 1) issues.push('El informe debe declarar schema ps5hs-vulkan-compute-report y version 1.');
    if (!safeId(String(value.graphRevisionId || '').replace(/-/g, '_'))) issues.push('Falta graphRevisionId para asociar la medición con una versión del grafo.');
    if (expectedRevisionId && value.graphRevisionId !== expectedRevisionId) issues.push('La medición corresponde a otra revisión del grafo; vuelve a ejecutarla con los shaders actuales.');
    if (typeof value.capturedAt !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value.capturedAt) || !Number.isFinite(Date.parse(value.capturedAt))) issues.push('capturedAt debe incluir una fecha y hora ISO 8601 con zona horaria.');
    if (value.runId !== undefined && (typeof value.runId !== 'string' || value.runId.length > 128)) issues.push('runId debe ser texto de hasta 128 caracteres.');
    if (!value.device || typeof value.device !== 'object' || Array.isArray(value.device)) issues.push('device debe ser un objeto con el nombre del dispositivo GPU.');
    else if (typeof value.device.name !== 'string' || !value.device.name.trim()) issues.push('Falta el nombre del dispositivo GPU.');
    if (value.device && typeof value.device === 'object' && !Array.isArray(value.device)) {
      for (const key of Object.keys(value.device)) if (!['name','vendor','deviceId'].includes(key)) issues.push(`device contiene un campo no reconocido: ${key}.`);
      if (typeof value.device.name === 'string' && value.device.name.length > 256) issues.push('device.name supera los 256 caracteres.');
      for (const key of ['vendor','deviceId']) if (value.device[key] !== undefined && (typeof value.device[key] !== 'string' || value.device[key].length > 128)) issues.push(`device.${key} debe ser texto de hasta 128 caracteres.`);
    }
    if (typeof value.driver !== 'string' || !value.driver.trim()) issues.push('Falta la versión del driver.');
    if (typeof value.runtime !== 'string' || !value.runtime.trim()) issues.push('Falta el runtime que ejecutó el grafo.');
    for (const key of ['driver','runtime']) if (typeof value[key] === 'string' && value[key].length > 256) issues.push(`${key} supera los 256 caracteres.`);
    if (value.target !== undefined) {
      if (!value.target || typeof value.target !== 'object' || Array.isArray(value.target)) issues.push('target debe ser un objeto.');
      else {
        for (const key of Object.keys(value.target)) if (!['api','width','height','format'].includes(key)) issues.push(`target contiene un campo no reconocido: ${key}.`);
        if (value.target.api !== undefined && value.target.api !== 'Vulkan') issues.push('target.api debe ser Vulkan.');
        for (const key of ['width','height']) if (value.target[key] !== undefined && (!Number.isInteger(value.target[key]) || value.target[key] < 1 || value.target[key] > 16384)) issues.push(`target.${key} debe estar entre 1 y 16384.`);
        if (value.target.format !== undefined && (typeof value.target.format !== 'string' || value.target.format.length > 32)) issues.push('target.format debe ser texto de hasta 32 caracteres.');
      }
    }
    if (!Array.isArray(value.results) || value.results.length === 0) issues.push('El informe necesita al menos una medición por pase.');
    const seen = new Set();
    for (const row of Array.isArray(value.results) ? value.results : []) {
      if (!row || typeof row !== 'object' || Array.isArray(row)) { issues.push('Cada resultado debe ser un objeto.'); continue; }
      for (const key of Object.keys(row)) if (!['passId','shaderSha256','gpuMs','psnrDb','ssim','memoryBytes','outputSha256','referenceSha256'].includes(key)) issues.push(`Una medición contiene un campo no reconocido: ${key}.`);
      if (!safeId(row?.passId)) { issues.push('Una medición tiene passId inválido.'); continue; }
      if (seen.has(row.passId)) issues.push(`El pase ${row.passId} aparece más de una vez.`);
      seen.add(row.passId);
      if (!/^[a-f0-9]{64}$/i.test(String(row.shaderSha256 || ''))) issues.push(`${row.passId}: falta shaderSha256 para identificar la fuente ejecutada.`);
      if (!Number.isFinite(row.gpuMs) || row.gpuMs < 0) issues.push(`La medición ${row.passId} necesita gpuMs >= 0.`);
      if (row.psnrDb !== undefined && !Number.isFinite(row.psnrDb)) issues.push(`${row.passId}: psnrDb debe ser numérico.`);
      if (row.ssim !== undefined && (!Number.isFinite(row.ssim) || row.ssim < -1 || row.ssim > 1)) issues.push(`${row.passId}: ssim debe estar entre -1 y 1.`);
      if (row.memoryBytes !== undefined && (!Number.isInteger(row.memoryBytes) || row.memoryBytes < 0)) issues.push(`${row.passId}: memoryBytes debe ser un entero no negativo.`);
      for (const key of ['outputSha256','referenceSha256']) if (row[key] !== undefined && !/^[a-f0-9]{64}$/i.test(String(row[key]))) issues.push(`${row.passId}: ${key} debe ser un SHA-256 hexadecimal de 64 caracteres.`);
    }
    const results = Array.isArray(value.results) ? value.results : [];
    const expectedList = (expectedPasses || []).map(pass => typeof pass === 'string' ? { id: pass } : pass);
    const expected = new Set(expectedList.map(pass => pass.id));
    if (expected.size && [...expected].some(id => !seen.has(id))) issues.push('Faltan mediciones de uno o más pases del grafo actual.');
    if (expected.size && [...seen].some(id => !expected.has(id))) issues.push('El informe contiene pases que no pertenecen al grafo actual.');
    for (const pass of expectedList) {
      const row = results.find(item => item?.passId === pass.id);
      if (row && pass.shaderSha256 && String(row.shaderSha256).toLowerCase() !== String(pass.shaderSha256).toLowerCase()) issues.push(`La medición del pase ${pass.id} usa otro shader.`);
    }
    return issues;
  }
  function summary(report) {
    const times = (report.results || []).map(row => Number(row.gpuMs)).filter(Number.isFinite).sort((a, b) => a - b);
    if (!times.length) return null;
    const median = times.length % 2 ? times[(times.length - 1) / 2] : (times[times.length / 2 - 1] + times[times.length / 2]) / 2;
    const p95 = times[Math.max(0, Math.ceil(times.length * 0.95) - 1)];
    return { runs: times.length, medianGpuMs: median, p95GpuMs: p95, meanGpuMs: times.reduce((sum, time) => sum + time, 0) / times.length };
  }
  const api = { version: 1, defaultSource: DEFAULT_SOURCE, newRevisionId, createDefaultGraph, normalizeGraph, validateGraph, workgroups, buildManifest, validateReport, summary, safeId };
  if (root) root.PS5HSComputeGraph = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis === 'object' ? globalThis : null);
