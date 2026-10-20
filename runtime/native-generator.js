/* PS5 Homebrew Studio native UI code generator.
 * Generates a C++20 concept for the published ps5-homebrew-ui DrawList/Concept API.
 * Both backends use bounded, predecoded RGBA assets; Vulkan textures are resolved through the title's VkRenderer registry.
 */
(function (root) {
  'use strict';

  const cppString = value => '"' + String(value ?? '').replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\r/g, '\\r').replace(/\n/g, '\\n').replace(/\t/g, '\\t').replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, ch => `\\${ch.charCodeAt(0).toString(8).padStart(3, '0')}`) + '"';
  const floatLiteral = value => {
    const n = Number(value);
    if (!Number.isFinite(n) || !Number.isFinite(Math.fround(n))) throw new Error(`No se puede emitir un literal float C++ representable para el valor: ${String(value)}`);
    let s = String(n);
    if (!/[.eE]/.test(s)) s += '.0';
    return s + 'f';
  };
  const colorHex = value => { if (!/^#[0-9a-f]{6}$/i.test(String(value || ''))) throw new Error(`Color hexadecimal inválido: ${String(value ?? '(vacío)')}`); return parseInt(String(value).slice(1), 16); };
  const colorLiteral = value => `gfx::Color::rgb(0x${colorHex(value).toString(16).padStart(6, '0')})`;

  function generate(project, backend) {
    if (!project || typeof project !== 'object' || Array.isArray(project)) throw new Error('No se recibió un modelo de proyecto válido para generar C++20.');
    const p = project;
    if (typeof p.name !== 'string' || !p.name.trim()) throw new Error('El proyecto no tiene un nombre explícito. Asigna un nombre antes de generar C++20.');
    const targetBackend = backend === undefined || backend === null ? p.backend : backend;
    if (typeof targetBackend !== 'string' || !targetBackend.trim()) throw new Error('No se especificó un backend C++20. Selecciona OpenGL o Vulkan antes de generar.');
    if (!['opengl-ui', 'vulkan-ui'].includes(targetBackend)) throw new Error(`Backend de generación C++20 no compatible: ${targetBackend}`);
    if (!Array.isArray(p.components)) throw new Error('El modelo visual contiene una lista de componentes inválida.');
    if (p.components.length === 0) throw new Error('El lienzo está vacío. Añade al menos un componente real antes de generar código C++20.');
    if (!Array.isArray(p.flows)) throw new Error('El modelo visual debe declarar una lista de flujos, aunque esté vacía.');
    if (!Array.isArray(p.assets)) throw new Error('El modelo visual debe declarar una lista de recursos, aunque esté vacía.');
    if (!Array.isArray(p.screens) || p.screens.length === 0) throw new Error('El modelo visual debe definir al menos una pantalla real.');
    const isVulkan = targetBackend === 'vulkan-ui';
    const safeId = (value, pattern, label) => {
      if (typeof value !== 'string' || !pattern.test(value)) throw new Error(`${label} necesita un identificador técnico explícito y seguro.`);
      return value;
    };
    const requireNumber = (owner, field, label) => {
      const value = owner[field];
      if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`${label} necesita un valor numérico explícito y finito en ${field}.`);
      return value;
    };
    const isColor = value => typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value);
    if (!p.theme || typeof p.theme !== 'object' || Array.isArray(p.theme)) throw new Error('El proyecto no contiene un tema visual válido.');
    for (const key of ['background','accent','text']) if (!isColor(p.theme[key])) throw new Error(`El tema necesita un color ${key} explícito con formato #RRGGBB.`);

    const screenIds = new Set();
    const screenNames = new Set();
    for (const [index, screen] of p.screens.entries()) {
      if (!screen || typeof screen !== 'object' || Array.isArray(screen)) throw new Error(`La pantalla ${index + 1} no es un objeto válido.`);
      safeId(screen.id, /^[A-Za-z_][A-Za-z0-9_-]{0,63}$/, `La pantalla ${index + 1}`);
      if (screenIds.has(screen.id)) throw new Error(`Identificador de pantalla duplicado: ${screen.id}`);
      if (typeof screen.name !== 'string' || !screen.name.trim()) throw new Error(`La pantalla ${screen.id} necesita un nombre explícito.`);
      const normalizedName = screen.name.trim().toLocaleLowerCase();
      if (screenNames.has(normalizedName)) throw new Error(`El nombre de pantalla «${screen.name}» está duplicado.`);
      screenIds.add(screen.id);
      screenNames.add(normalizedName);
    }
    if (typeof p.currentScreen !== 'string' || !screenIds.has(p.currentScreen)) throw new Error(`La pantalla activa no existe: ${String(p.currentScreen || '(vacía)')}`);

    const allowedTypes = new Set(['panel','title','text','button','toggle','slider','stepper','select','carousel','list','progress','badge','image','input','gauge','separator','card']);
    const selectableTypes = new Set(['select','carousel','list']);
    const inputComponents = p.components;
    const sourceIds = new Set();
    for (let i = 0; i < inputComponents.length; i++) {
      const component = inputComponents[i];
      if (!component || typeof component !== 'object' || Array.isArray(component)) throw new Error(`El componente ${i + 1} no es un objeto válido.`);
      safeId(component.id, /^[A-Za-z_][A-Za-z0-9_-]{0,63}$/, `El componente ${i + 1}`);
      if (!allowedTypes.has(component.type)) throw new Error(`El componente ${component.id} usa un tipo no implementado: ${String(component.type || '(vacío)')}.`);
      if (sourceIds.has(component.id)) throw new Error(`Identificador de componente duplicado: ${component.id}`);
      sourceIds.add(component.id);
      if (typeof component.label !== 'string' || (!component.label.trim() && component.type !== 'separator')) throw new Error(`El componente ${component.id} necesita una etiqueta explícita${component.type === 'separator' ? '' : ' y no vacía'}.`);
      if (typeof component.screenId !== 'string' || !screenIds.has(component.screenId)) throw new Error(`El componente ${component.id} apunta a una pantalla inexistente o no especificada: ${String(component.screenId || '(vacía)')}`);
      for (const field of ['x','y','w','h','font','opacity','value','min','max','step']) requireNumber(component, field, `El componente ${component.id}`);
      if (component.x < 0 || component.y < 0 || component.w <= 0 || component.h <= 0 || component.x + component.w > 1920 || component.y + component.h > 1080) throw new Error(`La geometría del componente ${component.id} queda fuera del lienzo 1920×1080 o tiene dimensiones no positivas; no se recortará silenciosamente.`);
      if (component.font < 8 || component.font > 144) throw new Error(`El tamaño de fuente del componente ${component.id} debe estar entre 8 y 144; no se cambiará automáticamente.`);
      if (component.opacity < 0 || component.opacity > 100) throw new Error(`La opacidad del componente ${component.id} debe estar entre 0 y 100.`);
      if (component.min > component.max) throw new Error(`El intervalo min/max del componente ${component.id} está invertido.`);
      if (component.step <= 0) throw new Error(`El paso del componente ${component.id} debe ser mayor que cero.`);
      if (component.value < component.min || component.value > component.max) throw new Error(`El valor inicial del componente ${component.id} queda fuera de su intervalo.`);
      if (typeof component.visible !== 'boolean' || typeof component.checked !== 'boolean') throw new Error(`El componente ${component.id} debe declarar visible y checked como booleanos explícitos.`);
      if (component.bg !== 'transparent' && !isColor(component.bg)) throw new Error(`El componente ${component.id} necesita un fondo hexadecimal #RRGGBB o «transparent».`);
      if (!isColor(component.fg)) throw new Error(`El componente ${component.id} necesita un color de texto hexadecimal #RRGGBB.`);
      if (typeof component.action !== 'string' || !['none','notify'].includes(component.action)) throw new Error(`La acción predeterminada del componente ${component.id} debe declarar none o notify; no se sustituirá una acción desconocida.`);
      if (component.actionMessage !== undefined && typeof component.actionMessage !== 'string') throw new Error(`La acción del componente ${component.id} tiene un mensaje de tipo no válido.`);
      if (component.action === 'notify' && (typeof component.actionMessage !== 'string' || !component.actionMessage.trim())) throw new Error(`El componente ${component.id} necesita un mensaje explícito para su acción de notificación.`);
      if (!Array.isArray(component.items) || component.items.some(item => typeof item !== 'string' || !item.trim())) throw new Error(`El componente ${component.id} debe declarar una lista items válida.`);
      if (component.custom !== undefined && component.custom !== null && (typeof component.custom !== 'object' || Array.isArray(component.custom))) throw new Error(`El campo custom del componente ${component.id} debe ser un objeto.`);
      const custom = component.custom || {};
      if (Object.hasOwn(custom, 'text') && typeof custom.text !== 'string') throw new Error(`El texto personalizado del componente ${component.id} debe ser una cadena explícita.`);
      if (Object.hasOwn(custom, 'selected')) {
        if (!selectableTypes.has(component.type)) throw new Error(`El componente ${component.id} define custom.selected pero no es un selector.`);
        if (!Number.isInteger(custom.selected) || custom.selected < 0 || custom.selected >= component.items.length) throw new Error(`La selección del componente ${component.id} no apunta a una opción real.`);
      }
      if (selectableTypes.has(component.type)) {
        if (component.items.length === 0) throw new Error(`El control «${component.label || component.id}» necesita opciones reales; no se crearán opciones ficticias.`);
        const selected = Object.hasOwn(custom, 'selected') ? custom.selected : component.value;
        if (!Number.isInteger(selected) || selected < 0 || selected >= component.items.length) throw new Error(`El control «${component.label || component.id}» tiene una selección inicial que no corresponde a sus opciones reales.`);
      }
    }

    const assets = p.assets;
    const assetIds = new Set();
    const assetById = new Map();
    for (const [index, asset] of assets.entries()) {
      if (!asset || typeof asset !== 'object' || Array.isArray(asset)) throw new Error(`El recurso ${index + 1} no es un objeto válido.`);
      safeId(asset.id, /^[A-Za-z_][A-Za-z0-9_-]{0,79}$/, `El recurso ${index + 1}`);
      if (assetIds.has(asset.id)) throw new Error(`Identificador de recurso duplicado: ${asset.id}`);
      if (typeof asset.name !== 'string' || !asset.name.trim() || asset.name.length > 255) throw new Error(`El recurso ${asset.id} necesita un nombre explícito y válido.`);
      if (typeof asset.fileName !== 'string' || !asset.fileName.trim() || asset.fileName.length > 128 || asset.fileName === '.' || asset.fileName === '..' || asset.fileName.includes('..') || /[\\/]/.test(asset.fileName) || !/^[A-Za-z0-9_-][A-Za-z0-9_. -]*$/.test(asset.fileName)) throw new Error(`El recurso ${asset.id} tiene un nombre de archivo no seguro o no explícito.`);
      if (typeof asset.mime !== 'string' || !/^[A-Za-z0-9!#$&^_.+-]+\/[A-Za-z0-9!#$&^_.+-]+$/.test(asset.mime)) throw new Error(`El recurso ${asset.id} necesita un tipo MIME explícito y válido.`);
      if (typeof asset.dataUrl !== 'string') throw new Error(`El recurso ${asset.id} necesita sus datos reales; no se aceptan recursos vacíos.`);
      const dataUrl = /^data:([^;,]+);base64,([A-Za-z0-9+/]+={0,2})$/.exec(asset.dataUrl);
      if (!dataUrl || dataUrl[1].toLowerCase() !== asset.mime.toLowerCase() || dataUrl[2].length % 4 !== 0) throw new Error(`Los datos del recurso ${asset.id} deben ser un data URL Base64 válido cuyo MIME coincida con el recurso.`);
      if (typeof asset.size !== 'number' || !Number.isSafeInteger(asset.size) || asset.size <= 0 || asset.size > 20 * 1024 * 1024) throw new Error(`El tamaño del recurso ${asset.id} debe ser un entero entre 1 byte y 20 MiB.`);
      const padding = dataUrl[2].endsWith('==') ? 2 : dataUrl[2].endsWith('=') ? 1 : 0;
      const decodedSize = dataUrl[2].length * 3 / 4 - padding;
      if (decodedSize !== asset.size) throw new Error(`El tamaño declarado del recurso ${asset.id} (${asset.size} bytes) no coincide con sus datos (${decodedSize} bytes).`);
      assetIds.add(asset.id);
      assetById.set(asset.id, asset);
    }

    for (const component of inputComponents) {
      if (component.assetId !== undefined && component.assetId !== null && component.assetId !== '' && !assetById.has(component.assetId)) throw new Error(`El componente ${component.id} apunta a un recurso inexistente: ${component.assetId}`);
      if (component.type === 'image') {
        const asset = assetById.get(component.assetId);
        if (!asset || !asset.mime.toLowerCase().startsWith('image/') || !asset.dataUrl.startsWith('data:image/')) throw new Error(`La imagen «${component.label}» no tiene un recurso gráfico válido. Importa el archivo y asígnalo antes de generar C++20.`);
      }
    }

    const components = inputComponents.map((component, index) => ({ component, index })).sort((a, b) => {
      const za = Object.hasOwn(a.component, 'zIndex') ? requireNumber(a.component, 'zIndex', `El componente ${a.component.id}`) : a.index;
      const zb = Object.hasOwn(b.component, 'zIndex') ? requireNumber(b.component, 'zIndex', `El componente ${b.component.id}`) : b.index;
      return za - zb || a.index - b.index;
    }).map(({ component: c }) => {
      const custom = c.custom || {};
      const asset = c.assetId ? assetById.get(c.assetId) : null;
      return {
        id: c.id, screenId: c.screenId, assetId: c.assetId || '',
        type: c.type, label: c.label,
        x: c.x, y: c.y, w: c.w, h: c.h,
        font: c.font, opacity: c.opacity,
        value: Object.hasOwn(custom, 'selected') ? custom.selected : c.value,
        min: c.min, max: c.max, step: c.step,
        bg: c.bg === 'transparent' ? 0 : colorHex(c.bg), fg: colorHex(c.fg),
        visible: c.visible, checked: c.checked, transparentBg: c.bg === 'transparent',
        action: c.action, actionMessage: c.actionMessage || '',
        text: custom.text || '', assetPath: c.type === 'image' && asset ? `ps5hs/${asset.id}.rgba` : '',
        items: c.items
      };
    });
    const imageComponents = components.filter(item => item.type === 'image');
    const uniqueImagePaths = new Set(imageComponents.map(component => component.assetPath));
    if (uniqueImagePaths.size > 16) throw new Error(`El runtime nativo admite hasta 16 imágenes únicas por título; el proyecto requiere ${uniqueImagePaths.size}. No se omitirán texturas automáticamente.`);
    const indexById = new Map(components.map((c, i) => [c.id, i]));
    const flowIds = new Set();
    const validEvents = new Set(['activate', 'change', 'start', 'any']);
    const validActions = new Set(['notify', 'setText', 'toggleVisibility', 'setValue', 'changeColor', 'navigate']);
    const requiredTargetActions = new Set(['setText', 'toggleVisibility', 'setValue']);
    const numericTypes = new Set(['slider', 'stepper', 'select', 'carousel', 'list', 'progress', 'gauge']);
    const flows = p.flows.map((f, index) => {
      if (!f || typeof f !== 'object' || Array.isArray(f)) throw new Error(`El flujo ${index + 1} no es un objeto válido.`);
      safeId(f.id, /^[A-Za-z_][A-Za-z0-9_-]{0,79}$/, `El flujo ${index + 1}`);
      if (flowIds.has(f.id)) throw new Error(`Identificador de flujo duplicado: ${f.id}`);
      flowIds.add(f.id);
      if (typeof f.enabled !== 'boolean') throw new Error(`El flujo ${f.id} debe declarar enabled como booleano explícito.`);
      if (typeof f.componentId !== 'string') throw new Error(`El flujo ${f.id} debe declarar su componentId como texto explícito (cadena vacía solo para evento start).`);
      if (typeof f.event !== 'string' || !validEvents.has(f.event)) throw new Error(`Flujo con evento no admitido: ${String(f.event || '(vacío)')}`);
      if (typeof f.action !== 'string' || !validActions.has(f.action)) throw new Error(`Flujo con acción no admitida: ${String(f.action || '(vacía)')}`);
      if (f.targetId !== undefined && typeof f.targetId !== 'string') throw new Error(`El destino del flujo ${f.id} debe ser texto.`);
      if (f.targetScreen !== undefined && typeof f.targetScreen !== 'string') throw new Error(`La pantalla de destino del flujo ${f.id} debe ser texto.`);
      if (f.message !== undefined && typeof f.message !== 'string') throw new Error(`El mensaje del flujo ${f.id} debe ser texto.`);
      if (f.action === 'setText' && typeof f.value !== 'string') throw new Error(`El flujo ${f.id} necesita un valor de texto explícito.`);
      if (['setValue','changeColor'].includes(f.action) && !(typeof f.value === 'string' || typeof f.value === 'number')) throw new Error(`El flujo ${f.id} necesita un valor explícito para ${f.action}.`);
      if (f.action === 'navigate' && typeof f.targetScreen !== 'string') throw new Error(`El flujo ${f.id} necesita una pantalla de destino explícita.`);
      if (f.action === 'notify' && (typeof f.message !== 'string' || !f.message.trim())) throw new Error(`El flujo ${f.id} necesita un mensaje explícito.`);
      return {
        id: f.id, componentId: f.componentId, targetId: f.targetId || '', event: f.event, action: f.action,
        message: f.message || '', value: f.value === undefined ? '' : String(f.value), targetScreen: f.targetScreen || '', enabled: f.enabled
      };
    });
    const activeFlows = flows.filter(flow => flow.enabled);
    for (const flow of activeFlows) {
      if (flow.event !== 'start' && !indexById.has(flow.componentId)) throw new Error(`El flujo no tiene un componente de origen válido: ${flow.componentId || '(vacío)'}`);
      if (flow.componentId && !indexById.has(flow.componentId)) throw new Error(`El flujo ${flow.id} apunta a un componente de origen inexistente: ${flow.componentId}`);
      if (requiredTargetActions.has(flow.action) && !indexById.has(flow.targetId)) throw new Error(`La acción ${flow.action} requiere un componente de destino válido: ${flow.targetId || '(vacío)'}`);
      if (flow.action === 'setText' && !['title','text','button','toggle','slider','stepper','select','badge','panel','card','input'].includes(components[indexById.get(flow.targetId)]?.type)) throw new Error(`El destino ${flow.targetId} no admite cambio de texto.`);
      if (flow.action === 'setValue') {
        const target = components[indexById.get(flow.targetId)];
        if (target.type !== 'toggle' && !numericTypes.has(target.type)) throw new Error(`No se puede asignar un valor a un componente de tipo ${target.type}: ${target.id}`);
        if (target.type === 'toggle' && !/^(true|false|1|0|sí|si|no|on|off)$/i.test(flow.value.trim())) throw new Error(`El valor de setValue para el interruptor ${target.id} debe ser explícitamente true/false, sí/no, on/off o 1/0.`);
        if (target.type !== 'toggle' && (flow.value.trim() === '' || !Number.isFinite(Number(flow.value)))) throw new Error(`El valor de setValue no es numérico para ${target.id}: ${flow.value}`);
        if (selectableTypes.has(target.type) && (!Number.isInteger(Number(flow.value)) || Number(flow.value) < 0 || Number(flow.value) >= target.items.length)) throw new Error(`El valor de setValue para ${target.id} debe ser un índice entero de una opción real.`);
        if (!selectableTypes.has(target.type) && target.type !== 'toggle' && (Number(flow.value) < target.min || Number(flow.value) > target.max)) throw new Error(`El valor de setValue para ${target.id} está fuera del intervalo ${target.min}–${target.max}.`);
        if (target.type === 'stepper' && !Number.isInteger(Number(flow.value))) throw new Error(`El valor de setValue para el stepper ${target.id} debe ser entero.`);
      }
      if (flow.action === 'navigate' && !screenIds.has(flow.targetScreen)) throw new Error(`La navegación apunta a una pantalla inexistente: ${flow.targetScreen}`);
      const sourceScreen = flow.componentId && indexById.has(flow.componentId) ? components[indexById.get(flow.componentId)].screenId : (flow.event === 'start' ? p.currentScreen : '');
      if (flow.action === 'navigate' && sourceScreen && sourceScreen === flow.targetScreen) throw new Error(`La navegación del flujo ${flow.id} apunta a la misma pantalla; selecciona una pantalla diferente.`);
      if (flow.action === 'changeColor' && !isColor(flow.value)) throw new Error(`changeColor requiere un color hexadecimal #RRGGBB explícito; recibido: ${flow.value}`);
      if (flow.action === 'notify' && !flow.message.trim()) throw new Error(`El flujo ${flow.id} necesita un mensaje explícito.`);
    }
    // action='none' is an explicit visual-only setting. The runtime still generates
    // the actual widget and input handling; it simply has no default action callback.
    const ns = isVulkan ? 'hui::screen' : 'hui::concepts';
    const out = [];
    const push = (...lines) => out.push(...lines);
    push('// Generated by PS5 Homebrew Studio from the visual project model.',
      '// Backend: ' + (isVulkan ? 'PS5 Vulkan Template + PS5_VKHomebrewUI' : 'PS5 Homebrew UI + PS5 OpenGL'),
      '// Controller input uses hui::InputFrame. Images use bounded predecoded RGBA assets in both OpenGL and Vulkan UI runtimes.',
      '#include "app/concept.hpp"', '#include "core/input.hpp"', '#include "gfx/draw_list.hpp"', '#include "ui/fonts.hpp"',
      '#include <algorithm>', '#include <cmath>', '#include <cstddef>', '#include <cstdint>', '#include <memory>', '#include <string>', '#include <string_view>', '#include <utility>', '#include <vector>',
      ...(isVulkan ? [] : ['#include <GL/gl.h>', '#include "core/save_file.hpp"']), ...(isVulkan ? ['', 'namespace ps5ui { std::uint32_t ps5hs_texture_for(std::string_view asset_path); }', ''] : []), '', `namespace ${ns}`, '{', 'namespace', '{',
      'using hui::gfx::Color;', 'using hui::gfx::Rect;', 'using hui::gfx::DrawList;', '',
      'struct Widget', '{',
      '    std::string id, screen, type, label;',
      '    float x = 0, y = 0, w = 1, h = 1, font = 20, opacity = 100, value = 0, min = 0, max = 100, step = 1;',
      '    std::uint32_t bg = 0x202a40, fg = 0xe8edff;',
      '    bool visible = true, checked = false, transparent_bg = false;',
      '    std::string action, action_message, text, asset_path;',
      '    std::uint32_t texture = 0;',
      '    std::vector<std::string> items;',
      '};', '', 'class GeneratedScreen final : public hui::app::Concept', '{', 'public:',
      '    explicit GeneratedScreen(hui::app::Context &context) : context_(context)', '    {', '        widgets_ = {');
    components.forEach((c, i) => {
      const items = c.items;
      const fields = [cppString(c.id), cppString(c.screenId), cppString(c.type), cppString(c.label),
        floatLiteral(c.x), floatLiteral(c.y), floatLiteral(c.w), floatLiteral(c.h), floatLiteral(c.font), floatLiteral(c.opacity),
        floatLiteral(c.value), floatLiteral(c.min), floatLiteral(c.max), floatLiteral(c.step), `0x${c.bg.toString(16).padStart(6, '0')}`, `0x${c.fg.toString(16).padStart(6, '0')}`,
        String(c.visible), String(c.checked), String(c.transparentBg), cppString(c.action), cppString(c.actionMessage), cppString(c.text), cppString(c.assetPath), '0',
        `std::vector<std::string>{${items.map(cppString).join(', ')}}`];
      push('            Widget{' + fields.join(', ') + '}' + (i < components.length - 1 ? ',' : ''));
    });
    push('        };', `        screen_ = ${cppString(p.currentScreen)};`, `        background_ = ${colorLiteral(p.theme.background)};`, `        accent_ = ${colorLiteral(p.theme.accent)};`, `        text_color_ = ${colorLiteral(p.theme.text)};`, '        selected_ = next_interactive(-1, 1);', '    }', '',
      '    const hui::app::ConceptInfo &info() const override', '    {',
      '        static constexpr const char *kTechniques[] = {"Generated from a 1920x1080 visual canvas", "Absolute-position layout preserved", "DualSense navigation and value editing", "Visual event flows compiled into native C++", "All screens are embedded in one concept"};',
      `        static const hui::app::ConceptInfo kInfo{"ps5hs-generated", ${cppString(p.name)}, "Screen generated from PS5 Homebrew Studio", "generated/ps5hs-screen.cpp", hui::audio::SoundSet::glass, ${colorLiteral(p.theme.accent)}, kTechniques};`,
      '        return kInfo;', '    }', '', ...(isVulkan ? ['    void enter() override { started_ = false; selected_ = next_interactive(-1, 1); keyboard_open_ = false; }'] : ['    void enter() override { started_ = false; selected_ = next_interactive(-1, 1); keyboard_open_ = false; load_textures(); }']), '',
      '    void update(const hui::InputFrame &input, float /*dt*/, hui::app::Feedback & /*feedback*/) override', '    {',
      '        if (!started_) { started_ = true; run_flows(-1, "start"); }',
      ...(isVulkan ? ['        if (!asset_error_reported_) { for (const Widget &w : widgets_) { if (w.type == "image" && ps5ui::ps5hs_texture_for(w.asset_path) == 0) { status_ = "Error: no se pudo cargar el recurso gráfico " + w.asset_path; asset_error_reported_ = true; break; } } }'] : []),
      '        if (keyboard_open_) { update_keyboard(input); return; }',
      '        if (input.nav == hui::Direction::down || input.nav == hui::Direction::up)', '        {', '            selected_ = next_interactive(selected_, input.nav == hui::Direction::down ? 1 : -1);', '            if (selected_ >= 0) status_ = widgets_[static_cast<std::size_t>(selected_)].label;', '        }',
      '        if (selected_ >= 0 && (input.nav == hui::Direction::left || input.nav == hui::Direction::right))', '        {', '            Widget &w = widgets_[static_cast<std::size_t>(selected_)];', '            const float delta = input.nav == hui::Direction::right ? w.step : -w.step;',
      '            if (w.type == "slider" || w.type == "stepper") { w.value = clamp_value(w.value + delta, w.min, w.max); run_flows(selected_, "change"); }',
      '            else if (w.type == "select" || w.type == "carousel" || w.type == "list") { const int count = static_cast<int>(w.items.size()); if (count > 0) { w.value = static_cast<float>((static_cast<int>(w.value) + (delta > 0 ? 1 : count - 1)) % count); run_flows(selected_, "change"); } }',
      '        }',
      '        if (input.is_pressed(hui::Action::confirm) && selected_ >= 0) activate(selected_);',
      '        if (input.is_pressed(hui::Action::back)) status_ = "Atrás · usa OPTIONS para salir de la aplicación";',
      '    }', '', '    void draw(hui::app::Frame &frame) const override', '    {', '        DrawList &draw = frame.scene;', '        draw.clear();', '        draw.gradient_rect(Rect{0, 0, 1920, 1080}, 0, background_, background_);',
      '        for (std::size_t i = 0; i < widgets_.size(); ++i)', '        {', '            const Widget &w = widgets_[i];', '            if (!w.visible || w.screen != screen_) continue;', '            draw_widget(draw, w, static_cast<int>(i) == selected_);', '        }',
      '        if (!status_.empty() && !keyboard_open_) { draw.rounded_rect(Rect{42, 1018, 1836, 40}, 9, background_); hui::ui::text(draw, context_.fonts.regular, status_, 64, 1043, 17, text_color_); }',
      '        if (keyboard_open_) draw_keyboard(draw);',
      '    }', '', 'private:', '    hui::app::Context &context_;', '    std::vector<Widget> widgets_;', `    std::string screen_ = ${cppString(p.currentScreen)};`, '    std::string status_ = "Listo · cruceta para navegar · X para activar";', '    Color background_ = Color::rgb(0x101827);', '    Color accent_ = Color::rgb(0x7865f6);', '    Color text_color_ = Color::rgb(0xf0f3ff);', '    int selected_ = -1;', '    bool started_ = false;', '    bool keyboard_open_ = false;', ...(isVulkan ? ['    bool asset_error_reported_ = false;'] : []), '    int keyboard_widget_ = -1;', '    int keyboard_index_ = 0;', '    std::string keyboard_draft_;',
      '    static constexpr const char *kKeyboardKeys[] = {"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z","0","1","2","3","4","5","6","7","8","9",".",",","-","_","Espacio","Borrar","Limpiar","Aceptar","Cancelar"};',
      '    static constexpr int kKeyboardKeyCount = 45;', '',
      ...(isVulkan ? [] : [
        '    void load_textures()',
        '    {',
        '        std::size_t loaded = 0;',
        '        for (Widget &w : widgets_)',
        '        {',
        '            if (w.type != "image" || w.asset_path.empty() || w.texture != 0) continue;',
        '            for (const Widget &previous : widgets_) { if (&previous == &w) break; if (previous.texture != 0 && previous.asset_path == w.asset_path) { w.texture = previous.texture; break; } }',
        '            if (w.texture != 0) continue;',
        '            if (loaded >= 16) break;',
        '            std::string bytes;',
        '            if (!hui::save::read_file("/app0/assets/" + w.asset_path, &bytes, 1048584) || bytes.size() < 8) { status_ = "Error: no se pudo leer el recurso gráfico " + w.asset_path; continue; }',
        '            const auto *raw = reinterpret_cast<const unsigned char *>(bytes.data());',
        '            const std::uint32_t width = static_cast<std::uint32_t>(raw[0]) | (static_cast<std::uint32_t>(raw[1]) << 8) | (static_cast<std::uint32_t>(raw[2]) << 16) | (static_cast<std::uint32_t>(raw[3]) << 24);',
        '            const std::uint32_t height = static_cast<std::uint32_t>(raw[4]) | (static_cast<std::uint32_t>(raw[5]) << 8) | (static_cast<std::uint32_t>(raw[6]) << 16) | (static_cast<std::uint32_t>(raw[7]) << 24);',
        '            if (width == 0 || height == 0 || width > 512 || height > 512 || bytes.size() != 8u + static_cast<std::size_t>(width) * height * 4u) { status_ = "Error: el recurso gráfico tiene dimensiones o datos inválidos: " + w.asset_path; continue; }',
        '            GLint previousTexture = 0; GLint previousAlignment = 4;',
        '            glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture);',
        '            glGetIntegerv(GL_UNPACK_ALIGNMENT, &previousAlignment);',
        '            glGenTextures(1, &w.texture);',
        '            if (w.texture == 0) { status_ = "Error: no se pudo reservar textura para " + w.asset_path; continue; }',
        '            glBindTexture(GL_TEXTURE_2D, w.texture);',
        '            glPixelStorei(GL_UNPACK_ALIGNMENT, 1);',
        '            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);',
        '            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);',
        '            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);',
        '            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);',
        '            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, static_cast<GLsizei>(width), static_cast<GLsizei>(height), 0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.data() + 8);',
        '            glBindTexture(GL_TEXTURE_2D, static_cast<GLuint>(previousTexture));',
        '            glPixelStorei(GL_UNPACK_ALIGNMENT, previousAlignment);',
        '            ++loaded;',
        '        }',
        '    }',
      ]),
      '    void update_keyboard(const hui::InputFrame &input)', '    {',
      '        if (input.is_pressed(hui::Action::back)) { keyboard_open_ = false; keyboard_widget_ = -1; status_ = "Edición cancelada"; return; }',
      '        const int row = keyboard_index_ / 8, col = keyboard_index_ % 8;',
      '        if (input.nav == hui::Direction::left) keyboard_index_ = col > 0 ? keyboard_index_ - 1 : (row == 5 ? 44 : row * 8 + 7);',
      '        else if (input.nav == hui::Direction::right) keyboard_index_ = row == 5 ? (col >= 4 ? 40 : keyboard_index_ + 1) : (col == 7 ? row * 8 : keyboard_index_ + 1);',
      '        else if (input.nav == hui::Direction::up) keyboard_index_ = row == 0 ? 40 + std::min(col, 4) : (row == 5 ? 32 + col : keyboard_index_ - 8);',
      '        else if (input.nav == hui::Direction::down) keyboard_index_ = row == 5 ? keyboard_index_ : (row == 4 ? 40 + std::min(col, 4) : keyboard_index_ + 8);',
      '        if (!input.is_pressed(hui::Action::confirm) || keyboard_widget_ < 0 || keyboard_widget_ >= static_cast<int>(widgets_.size())) return;',
      '        const std::string_view key = kKeyboardKeys[keyboard_index_];',
      '        if (key == "Espacio") { if (keyboard_draft_.size() < 256) keyboard_draft_ += " "; }',
      '        else if (key == "Borrar") { if (!keyboard_draft_.empty()) keyboard_draft_.pop_back(); }',
      '        else if (key == "Limpiar") keyboard_draft_.clear();',
      '        else if (key == "Cancelar") { keyboard_open_ = false; keyboard_widget_ = -1; status_ = "Edición cancelada"; }',
      '        else if (key == "Aceptar") { Widget &w = widgets_[static_cast<std::size_t>(keyboard_widget_)]; w.text = keyboard_draft_; status_ = w.label + ": valor actualizado"; const int edited = keyboard_widget_; keyboard_open_ = false; keyboard_widget_ = -1; run_flows(edited, "change"); }',
      '        else if (keyboard_draft_.size() + key.size() <= 256) keyboard_draft_.append(key);',
      '    }',
      '    void draw_keyboard(DrawList &draw) const', '    {',
      '        draw.rounded_rect(Rect{0, 0, 1920, 1080}, 0, Color::rgb(0x000000, 0.62f));',
      '        draw.rounded_rect(Rect{330, 255, 1260, 600}, 24, Color::rgb(0x141d30));',
      '        draw.bordered_rect(Rect{330, 255, 1260, 600}, 24, Color::rgb(0x141d30), 2, accent_);',
      '        hui::ui::text(draw, context_.fonts.display, "Teclado de pantalla", 960, 305, 34, Color::rgb(0xffffff), hui::gfx::Align::center);',
      '        hui::ui::text(draw, context_.fonts.regular, keyboard_draft_.empty() ? "Escribe con la cruceta y confirma las teclas" : keyboard_draft_, 960, 354, 23, Color::rgb(0xcbd5e1), hui::gfx::Align::center);',
      '        for (int k = 0; k < kKeyboardKeyCount; ++k) { const int row = k / 8, col = k % 8; const Rect r{406.0f + col * 140.0f, 385.0f + row * 70.0f, 128.0f, 60.0f}; const bool focused = k == keyboard_index_; draw.rounded_rect(r, 10, focused ? accent_ : Color::rgb(0x252f45)); if (focused) draw.bordered_rect(r, 10, accent_, 2, Color::rgb(0xffffff)); hui::ui::text(draw, context_.fonts.semibold, kKeyboardKeys[k], r.x + r.w * 0.5f, r.y + 38, k >= 40 ? 17.0f : 21.0f, Color::rgb(0xffffff), hui::gfx::Align::center); }',
      '        hui::ui::text(draw, context_.fonts.regular, "Confirmar: seleccionar  ·  Atrás: cancelar  ·  Aceptar para guardar", 960, 830, 17, Color::rgb(0xaeb9d3), hui::gfx::Align::center);',
      '    }',
      '    static float clamp_value(float value, float low, float high) { if (high < low) std::swap(high, low); return std::max(low, std::min(high, value)); }',
      '    static bool interactive(std::string_view type) { return type == "button" || type == "toggle" || type == "slider" || type == "stepper" || type == "select" || type == "carousel" || type == "list" || type == "input"; }',
      '    int next_interactive(int from, int direction) const', '    {',
      '        if (widgets_.empty()) return -1;',
      '        const int n = static_cast<int>(widgets_.size());',
      '        for (int step = 1; step <= n; ++step) { const int i = (from + direction * step + n * 2) % n; const Widget &w = widgets_[static_cast<std::size_t>(i)]; if (w.visible && w.screen == screen_ && interactive(w.type)) return i; }',
      '        return -1;', '    }', '',
      '    void activate(int index)', '    {', '        if (index < 0 || index >= static_cast<int>(widgets_.size())) return;', '        Widget &w = widgets_[static_cast<std::size_t>(index)];',
      '        if (w.type == "toggle") { w.checked = !w.checked; run_flows(index, "change"); }',
      '        else if (w.type == "slider" || w.type == "stepper") { w.value = clamp_value(w.value + w.step, w.min, w.max); run_flows(index, "change"); }',
      '        else if (w.type == "select" || w.type == "carousel" || w.type == "list") { if (!w.items.empty()) w.value = static_cast<float>((static_cast<int>(w.value) + 1) % static_cast<int>(w.items.size())); run_flows(index, "change"); run_flows(index, "activate"); }',
      '        else if (w.type == "input") { keyboard_widget_ = index; keyboard_draft_ = w.text; keyboard_index_ = 0; keyboard_open_ = true; status_ = "Editor de texto abierto"; }',
      '        else { if (w.action == "notify") { if (w.action_message.empty()) status_ = "Error: la acción no tiene un mensaje configurado"; else status_ = w.action_message; } run_flows(index, "activate"); }',
      '    }', '', '    void run_flows(int source, std::string_view event)', '    {');
    if (activeFlows.length === 0) {
      push('        (void)source;', '        (void)event; // No se han configurado acciones visuales para este proyecto.');
    } else {
      activeFlows.forEach(f => {
        const sourceIndex = indexById.has(f.componentId) ? indexById.get(f.componentId) : -1;
        if (f.event === 'start') {
          if (f.action === 'notify') push(`        if (event == "start") status_ = ${cppString(f.message)};`);
          else push(`        if (event == "start") { ${flowAction(f, indexById, components)} }`);
        } else {
          if (sourceIndex < 0) return;
          const eventExpr = f.event === 'any' ? 'true' : `(event == ${cppString(f.event)})`;
          push(`        if (source == ${sourceIndex} && ${eventExpr}) { ${flowAction(f, indexById, components)} }`);
        }
      });
    }
    push('    }', '', '    void draw_widget(DrawList &draw, const Widget &w, bool focused) const', '    {',
      '        const Rect r{w.x, w.y, w.w, w.h};', '        const Color fg = Color::rgb(w.fg);', '        const Color bg = Color::rgb(w.bg, w.transparent_bg ? 0.0f : 1.0f);',
      '        draw.push_opacity(clamp_value(w.opacity / 100.0f, 0.0f, 1.0f));',
      '        if (!w.transparent_bg && w.type != "separator") draw.rounded_rect(r, (w.type == "badge" ? 18.0f : 10.0f), bg);',
      '        if (focused) draw.bordered_rect(r, 10.0f, Color::rgb(w.bg, w.transparent_bg ? 0.0f : 1.0f), 3.0f, accent_);',
      '        const auto &body = context_.fonts.regular;', '        const auto &strong = context_.fonts.semibold;', '        const auto &display = context_.fonts.display;',
      '        if (w.type == "separator") { draw.line(w.x, w.y + w.h * 0.5f, w.x + w.w, w.y + w.h * 0.5f, std::max(1.0f, w.h), bg); }',
      '        else if (w.type == "title") { hui::ui::text(draw, display, w.label, w.x + w.w * 0.5f, w.y + w.h * 0.68f, w.font, fg, hui::gfx::Align::center); }',
      '        else if (w.type == "text") { hui::ui::text(draw, body, w.label, w.x + w.w * 0.5f, w.y + w.h * 0.66f, w.font, fg, hui::gfx::Align::center); }',
      '        else if (w.type == "panel" || w.type == "card") { hui::ui::text(draw, strong, w.label, w.x + 18.0f, w.y + std::min(w.h - 8.0f, std::max(w.font + 10.0f, 36.0f)), w.font, fg); }',
      '        else if (w.type == "toggle") { draw.rounded_rect(Rect{w.x + 12, w.y + (w.h - 30) * 0.5f, 54, 30}, 15, w.checked ? accent_ : Color::rgb(0x48536b)); draw.circle(w.x + (w.checked ? 51 : 27), w.y + w.h * 0.5f, 11, Color::rgb(0xffffff)); hui::ui::text(draw, strong, w.label, w.x + 78, w.y + w.h * 0.66f, w.font, fg); }',
      '        else if (w.type == "slider") { const float ratio = w.max > w.min ? clamp_value((w.value - w.min) / (w.max - w.min), 0, 1) : 0; draw.rounded_rect(Rect{w.x + 12, w.y + w.h * 0.66f, std::max(0.0f, w.w - 24), 8}, 4, Color::rgb(0x424c63)); draw.rounded_rect(Rect{w.x + 12, w.y + w.h * 0.66f, std::max(0.0f, (w.w - 24) * ratio), 8}, 4, accent_); const std::string label = w.label + "  " + std::to_string(static_cast<int>(w.value)); hui::ui::text(draw, strong, label, w.x + 12, w.y + w.h * 0.38f, w.font, fg); }',
      '        else if (w.type == "stepper") { const std::string label = w.label + "   ‹  " + std::to_string(static_cast<int>(w.value)) + "  ›"; hui::ui::text(draw, strong, label, w.x + w.w * 0.5f, w.y + w.h * 0.65f, w.font, fg, hui::gfx::Align::center); }',
      '        else if (w.type == "select" || w.type == "carousel") { const std::string selected = w.items[static_cast<std::size_t>(std::max(0, std::min(static_cast<int>(w.items.size()) - 1, static_cast<int>(w.value))))]; hui::ui::text(draw, strong, "‹  " + selected + "  ›", w.x + w.w * 0.5f, w.y + w.h * 0.65f, w.font, fg, hui::gfx::Align::center); if (w.type == "select") hui::ui::text(draw, body, w.label, w.x + 8, w.y + 16, std::max(12.0f, w.font * 0.65f), fg); }',
      '        else if (w.type == "list") { hui::ui::text(draw, strong, w.label, w.x + 12, w.y + 26, w.font, fg); const float rowH = std::max(24.0f, (w.h - 38) / std::max<std::size_t>(1, w.items.size())); for (std::size_t n = 0; n < w.items.size() && n < 8; ++n) { const float y = w.y + 36 + static_cast<float>(n) * rowH; if (static_cast<int>(n) == static_cast<int>(w.value)) draw.rounded_rect(Rect{w.x + 6, y, w.w - 12, rowH - 2}, 5, Color::rgb(0x7865f6, 0.25f)); hui::ui::text(draw, body, w.items[n], w.x + 16, y + rowH * 0.65f, std::min(22.0f, w.font), fg); } }',
      '        else if (w.type == "progress") { const float ratio = w.max > w.min ? clamp_value((w.value - w.min) / (w.max - w.min), 0, 1) : 0; draw.rounded_rect(Rect{w.x, w.y + w.h * 0.38f, w.w, std::max(6.0f, w.h * 0.24f)}, 6, Color::rgb(0x374159)); draw.rounded_rect(Rect{w.x, w.y + w.h * 0.38f, w.w * ratio, std::max(6.0f, w.h * 0.24f)}, 6, accent_); }',
      '        else if (w.type == "badge") { hui::ui::text(draw, strong, w.label, w.x + w.w * 0.5f, w.y + w.h * 0.66f, w.font, fg, hui::gfx::Align::center); }',
      ...(isVulkan ? [
        '        else if (w.type == "image") { const std::uint32_t texture = ps5ui::ps5hs_texture_for(w.asset_path); if (texture != 0) draw.image(texture, r, Rect{0, 0, 1, 1}, Color::rgb(0xffffff), 8.0f); }'
      ] : [
        '        else if (w.type == "image") { if (w.texture != 0) draw.image(w.texture, r, Rect{0, 0, 1, 1}, Color::rgb(0xffffff), 8.0f); }'
      ]),
      '        else if (w.type == "input") { draw.bordered_rect(r, 8, Color::rgb(0x111827), 1, focused ? accent_ : Color::rgb(0x48536b)); const std::string value = w.text.empty() ? ("▤  " + w.label + "  ·  X para abrir el teclado") : w.text; hui::ui::text(draw, body, value, w.x + 12, w.y + w.h * 0.65f, std::min(20.0f, w.font), fg); }',
      '        else if (w.type == "gauge") { const float radius = std::max(8.0f, std::min(w.w, w.h) * 0.34f); const float ratio = w.max > w.min ? clamp_value((w.value - w.min) / (w.max - w.min), 0, 1) : 0; draw.ring(w.x + w.w * 0.5f, w.y + w.h * 0.48f, radius, 8, Color::rgb(0x374159)); draw.arc(w.x + w.w * 0.5f, w.y + w.h * 0.48f, radius, 8, 0, 6.2831853f * ratio, accent_); hui::ui::text(draw, strong, std::to_string(static_cast<int>(w.value)) + "%", w.x + w.w * 0.5f, w.y + w.h * 0.55f, w.font, fg, hui::gfx::Align::center); }',
      '        else { hui::ui::text(draw, strong, w.label, w.x + w.w * 0.5f, w.y + w.h * 0.65f, w.font, fg, hui::gfx::Align::center); }',
      '        draw.pop_opacity();', '    }', '};', '', `} // namespace`, `} // namespace ${ns}`, '');

    if (isVulkan) {
      push('namespace ps5ui', '{', 'std::unique_ptr<hui::app::Concept> make_screen(hui::app::Context &context)', '{', `    return std::make_unique<${ns}::GeneratedScreen>(context);`, '}', '} // namespace ps5ui', '');
    } else {
      push('namespace hui::concepts', '{', 'std::unique_ptr<hui::app::Concept> make_ps5hs_generated(hui::app::Context &context)', '{', `    return std::make_unique<${ns}::GeneratedScreen>(context);`, '}', '} // namespace hui::concepts', '');
    }
    return out.join('\n');
  }

  function flowAction(flow, indexById, components) {
    const i = indexById.has(flow.targetId) ? indexById.get(flow.targetId) : -1;
    switch (flow.action) {
      case 'notify': if (!flow.message.trim()) throw new Error(`El flujo ${flow.id} necesita un mensaje de notificación explícito.`); return `status_ = ${cppString(flow.message)};`;
      case 'setText': {
        if (i < 0) throw new Error(`setText tiene un destino inexistente: ${flow.targetId}`);
        if (!['title','text','button','toggle','slider','stepper','select','badge','panel','card','input'].includes(components[i].type)) throw new Error(`setText no admite el tipo ${components[i].type}: ${flow.targetId}`);
        return components[i].type === 'input' ? `widgets_[${i}].text = ${cppString(flow.value)};` : `widgets_[${i}].label = ${cppString(flow.value)};`;
      }
      case 'toggleVisibility': {
        if (i < 0) throw new Error(`toggleVisibility tiene un destino inexistente: ${flow.targetId}`);
        return `widgets_[${i}].visible = !widgets_[${i}].visible;`;
      }
      case 'setValue': {
        if (i < 0) throw new Error(`setValue tiene un destino inexistente: ${flow.targetId}`);
        const target = components[i];
        if (target.type === 'toggle') return `widgets_[${i}].checked = ${/^(true|1|sí|si|on)$/i.test(String(flow.value)) ? 'true' : 'false'};`;
        if (['select', 'carousel', 'list'].includes(target.type)) return `widgets_[${i}].value = static_cast<float>(${Number(flow.value)});`;
        return `widgets_[${i}].value = ${floatLiteral(Number(flow.value))};`;
      }
      case 'changeColor': if (!/^#[0-9a-f]{6}$/i.test(flow.value)) throw new Error(`changeColor necesita un color hexadecimal #RRGGBB explícito: ${flow.value}`); return `background_ = Color::rgb(0x${parseInt(flow.value.slice(1), 16).toString(16).padStart(6, '0')});`;
      case 'navigate': return `screen_ = ${cppString(flow.targetScreen)}; selected_ = next_interactive(-1, 1); status_ = "Pantalla: " + screen_;`;
      default: throw new Error(`Acción de flujo sin implementación: ${flow.action}`);
    }
  }

  const api = { generate, cppString };
  root.PS5HSNativeCodegen = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
