/* PS5 Homebrew Studio native UI code generator.
 * Generates a C++20 concept for the published ps5-homebrew-ui DrawList/Concept API.
 * Both backends use bounded, predecoded RGBA assets; Vulkan textures are resolved through the title's VkRenderer registry.
 */
(function (root) {
  'use strict';

  const clamp = (n, min, max) => Math.min(max, Math.max(min, Number.isFinite(Number(n)) ? Number(n) : 0));
  const cppString = value => '"' + String(value ?? '').replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\r/g, '\\r').replace(/\n/g, '\\n').replace(/\t/g, '\\t').replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, ch => `\\x${ch.charCodeAt(0).toString(16).padStart(2, '0')}`) + '"';
  const floatLiteral = value => {
    let n = Number(value);
    if (!Number.isFinite(n)) n = 0;
    let s = String(Math.round(n * 1000) / 1000);
    if (!/[.eE]/.test(s)) s += '.0';
    return s + 'f';
  };
  const intLiteral = value => String(Math.trunc(clamp(value, 0, 0xffffffff)));
  const colorHex = (value, fallback) => /^#[0-9a-f]{6}$/i.test(String(value || '')) ? parseInt(String(value).slice(1), 16) : fallback;
  const colorLiteral = value => `gfx::Color::rgb(0x${colorHex(value, 0x101827).toString(16).padStart(6, '0')})`;
  const interactiveTypes = new Set(['button', 'toggle', 'slider', 'stepper', 'select', 'carousel', 'list', 'input']);

  function generate(project, backend) {
    const p = project || {};
    const targetBackend = backend || p.backend || 'opengl-ui';
    const isVulkan = targetBackend === 'vulkan-ui';
    const safeAssetId = value => String(value || '').replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 80);
    const components = (Array.isArray(p.components) ? p.components : []).map((c, i) => ({
      id: String(c.id || `widget-${i + 1}`), screenId: String(c.screenId || 'screen-main'),
      type: String(c.type || 'text'), label: String(c.label || c.type || 'Elemento'),
      x: clamp(c.x, 0, 1919), y: clamp(c.y, 0, 1079), w: clamp(c.w || 1, 1, 1920), h: clamp(c.h || 1, 1, 1080),
      font: clamp(c.font || 20, 8, 144), opacity: clamp(c.opacity ?? 100, 0, 100),
      value: Number.isFinite(Number(c.custom?.selected)) && ['select', 'carousel', 'list'].includes(c.type) ? Number(c.custom.selected) : Number(c.value || 0),
      min: Number.isFinite(Number(c.min)) ? Number(c.min) : 0, max: Number.isFinite(Number(c.max)) ? Number(c.max) : 100,
      step: Math.max(0.1, Number(c.step) || 1), bg: colorHex(c.bg, 0x202a40), fg: colorHex(c.fg, 0xe8edff),
      visible: c.visible !== false, checked: Boolean(c.checked), transparentBg: c.bg === 'transparent',
      action: String(c.action || ''), actionMessage: String(c.actionMessage || ''),
      text: String(c.custom?.text || ''), assetPath: (c.assetId && (Array.isArray(p.assets) ? p.assets : []).some(a => a && a.id === c.assetId && String(a.dataUrl || '').startsWith('data:image/')) ? `ps5hs/${safeAssetId(c.assetId)}.rgba` : ''), items: Array.isArray(c.items) ? c.items.map(String) : []
    }));
    const indexById = new Map(components.map((c, i) => [c.id, i]));
    const flows = (Array.isArray(p.flows) ? p.flows : []).filter(f => f && f.enabled !== false).map(f => ({
      componentId: String(f.componentId || ''), targetId: String(f.targetId || ''), event: String(f.event || 'activate'),
      action: String(f.action || 'notify'), message: String(f.message || ''), value: String(f.value ?? ''),
      targetScreen: String(f.targetScreen || 'screen-main')
    }));
    if (new Set(components.map(c => c.id)).size !== components.length) throw new Error('El modelo contiene identificadores de componente duplicados.');
    const screenIds = new Set((Array.isArray(p.screens) ? p.screens : []).map(screen => String(screen?.id || '')).filter(Boolean));
    const validEvents = new Set(['activate', 'change', 'start', 'any']);
    const validActions = new Set(['notify', 'setText', 'toggleVisibility', 'setValue', 'changeColor', 'navigate']);
    const requiredTargetActions = new Set(['setText', 'toggleVisibility', 'setValue']);
    const numericTypes = new Set(['slider', 'stepper', 'select', 'carousel', 'list', 'progress', 'gauge']);
    for (const flow of flows) {
      if (!validEvents.has(flow.event)) throw new Error(`Flujo con evento no admitido: ${flow.event}`);
      if (!validActions.has(flow.action)) throw new Error(`Flujo con acción no admitida: ${flow.action}`);
      if (flow.event !== 'start' && !indexById.has(flow.componentId)) throw new Error(`El flujo no tiene un componente de origen válido: ${flow.componentId || '(vacío)'}`);
      if (requiredTargetActions.has(flow.action) && !indexById.has(flow.targetId)) throw new Error(`La acción ${flow.action} requiere un componente de destino válido: ${flow.targetId || '(vacío)'}`);
      if (flow.action === 'setValue') {
        const target = components[indexById.get(flow.targetId)];
        if (target.type !== 'toggle' && !numericTypes.has(target.type)) throw new Error(`No se puede asignar un valor a un componente de tipo ${target.type}: ${target.id}`);
        if (target.type !== 'toggle' && !Number.isFinite(Number(flow.value))) throw new Error(`El valor de setValue no es numérico para ${target.id}: ${flow.value}`);
      }
      if (flow.action === 'navigate' && !screenIds.has(flow.targetScreen)) throw new Error(`La navegación apunta a una pantalla inexistente: ${flow.targetScreen}`);
      if (flow.action === 'changeColor' && !/^#[0-9a-f]{6}$/i.test(flow.value)) throw new Error(`changeColor requiere un color hexadecimal #RRGGBB; recibido: ${flow.value}`);
    }
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
      const items = c.items.length ? c.items : (['select', 'carousel', 'list'].includes(c.type) ? ['Opción 1', 'Opción 2', 'Opción 3'] : []);
      const fields = [cppString(c.id), cppString(c.screenId), cppString(c.type), cppString(c.label),
        floatLiteral(c.x), floatLiteral(c.y), floatLiteral(c.w), floatLiteral(c.h), floatLiteral(c.font), floatLiteral(c.opacity),
        floatLiteral(c.value), floatLiteral(c.min), floatLiteral(c.max), floatLiteral(c.step), `0x${c.bg.toString(16).padStart(6, '0')}`, `0x${c.fg.toString(16).padStart(6, '0')}`,
        String(c.visible), String(c.checked), String(c.transparentBg), cppString(c.action), cppString(c.actionMessage), cppString(c.text), cppString(c.assetPath), '0',
        `std::vector<std::string>{${items.map(cppString).join(', ')}}`];
      push('            Widget{' + fields.join(', ') + '}' + (i < components.length - 1 ? ',' : ''));
    });
    push('        };', `        screen_ = ${cppString(String(p.currentScreen || 'screen-main'))};`, '        background_ = ' + colorLiteral(p.theme?.background) + ';', '        accent_ = ' + colorLiteral(p.theme?.accent || '#7865f6') + ';', '        selected_ = next_interactive(-1, 1);', '    }', '',
      '    const hui::app::ConceptInfo &info() const override', '    {',
      '        static constexpr const char *kTechniques[] = {"Generated from a 1920x1080 visual canvas", "Absolute-position layout preserved", "DualSense navigation and value editing", "Visual event flows compiled into native C++", "All screens are embedded in one concept"};',
      `        static const hui::app::ConceptInfo kInfo{"ps5hs-generated", ${cppString(String(p.name || 'Homebrew Screen'))}, "Screen generated from PS5 Homebrew Studio", "generated/ps5hs-screen.cpp", hui::audio::SoundSet::glass, ${colorLiteral(p.theme?.accent || '#7865f6')}, kTechniques};`,
      '        return kInfo;', '    }', '', ...(isVulkan ? ['    void enter() override { started_ = false; selected_ = next_interactive(-1, 1); keyboard_open_ = false; }'] : ['    void enter() override { started_ = false; selected_ = next_interactive(-1, 1); keyboard_open_ = false; load_textures(); }']), '',
      '    void update(const hui::InputFrame &input, float /*dt*/, hui::app::Feedback & /*feedback*/) override', '    {',
      '        if (!started_) { started_ = true; run_flows(-1, "start"); }',
      '        if (keyboard_open_) { update_keyboard(input); return; }',
      '        if (input.nav == hui::Direction::down || input.nav == hui::Direction::up)', '        {', '            selected_ = next_interactive(selected_, input.nav == hui::Direction::down ? 1 : -1);', '            if (selected_ >= 0) status_ = widgets_[static_cast<std::size_t>(selected_)].label;', '        }',
      '        if (selected_ >= 0 && (input.nav == hui::Direction::left || input.nav == hui::Direction::right))', '        {', '            Widget &w = widgets_[static_cast<std::size_t>(selected_)];', '            const float delta = input.nav == hui::Direction::right ? w.step : -w.step;',
      '            if (w.type == "slider" || w.type == "stepper") { w.value = clamp_value(w.value + delta, w.min, w.max); run_flows(selected_, "change"); }',
      '            else if (w.type == "select" || w.type == "carousel" || w.type == "list") { const int count = static_cast<int>(w.items.size()); if (count > 0) { w.value = static_cast<float>((static_cast<int>(w.value) + (delta > 0 ? 1 : count - 1)) % count); run_flows(selected_, "change"); } }',
      '        }',
      '        if (input.is_pressed(hui::Action::confirm) && selected_ >= 0) activate(selected_);',
      '        if (input.is_pressed(hui::Action::back)) status_ = "Atrás · usa OPTIONS para salir de la aplicación";',
      '    }', '', '    void draw(hui::app::Frame &frame) const override', '    {', '        DrawList &draw = frame.scene;', '        draw.clear();', '        draw.gradient_rect(Rect{0, 0, 1920, 1080}, 0, background_, Color::rgb(0x0b1020));',
      '        for (std::size_t i = 0; i < widgets_.size(); ++i)', '        {', '            const Widget &w = widgets_[i];', '            if (!w.visible || w.screen != screen_) continue;', '            draw_widget(draw, w, static_cast<int>(i) == selected_);', '        }',
      '        if (!status_.empty() && !keyboard_open_) { draw.rounded_rect(Rect{42, 1018, 1836, 40}, 9, Color::rgb(0x0b1020, 0.82f)); hui::ui::text(draw, context_.fonts.regular, status_, 64, 1043, 17, Color::rgb(0xaeb9d3)); }',
      '        if (keyboard_open_) draw_keyboard(draw);',
      '    }', '', 'private:', '    hui::app::Context &context_;', '    std::vector<Widget> widgets_;', '    std::string screen_ = "screen-main";', '    std::string status_ = "Listo · cruceta para navegar · X para activar";', '    Color background_ = Color::rgb(0x101827);', '    Color accent_ = Color::rgb(0x7865f6);', '    int selected_ = -1;', '    bool started_ = false;', '    bool keyboard_open_ = false;', '    int keyboard_widget_ = -1;', '    int keyboard_index_ = 0;', '    std::string keyboard_draft_;',
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
        '            if (!hui::save::read_file("/app0/assets/" + w.asset_path, &bytes, 1048584) || bytes.size() < 8) continue;',
        '            const auto *raw = reinterpret_cast<const unsigned char *>(bytes.data());',
        '            const std::uint32_t width = static_cast<std::uint32_t>(raw[0]) | (static_cast<std::uint32_t>(raw[1]) << 8) | (static_cast<std::uint32_t>(raw[2]) << 16) | (static_cast<std::uint32_t>(raw[3]) << 24);',
        '            const std::uint32_t height = static_cast<std::uint32_t>(raw[4]) | (static_cast<std::uint32_t>(raw[5]) << 8) | (static_cast<std::uint32_t>(raw[6]) << 16) | (static_cast<std::uint32_t>(raw[7]) << 24);',
        '            if (width == 0 || height == 0 || width > 512 || height > 512 || bytes.size() != 8u + static_cast<std::size_t>(width) * height * 4u) continue;',
        '            GLint previousTexture = 0; GLint previousAlignment = 4;',
        '            glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture);',
        '            glGetIntegerv(GL_UNPACK_ALIGNMENT, &previousAlignment);',
        '            glGenTextures(1, &w.texture);',
        '            if (w.texture == 0) continue;',
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
      '        else { if (w.action == "notify") status_ = w.action_message.empty() ? (w.label + " activado") : w.action_message; run_flows(index, "activate"); }',
      '    }', '', '    void run_flows(int source, std::string_view event)', '    {');
    flows.forEach(f => {
      const sourceIndex = indexById.has(f.componentId) ? indexById.get(f.componentId) : -1;
      if (f.event === 'start') {
        if (f.action === 'notify') push(`        if (event == "start") status_ = ${cppString(f.message || 'Acción ejecutada')};`);
        else push(`        if (event == "start") { ${flowAction(f, indexById, components, isVulkan)} }`);
      } else {
        if (sourceIndex < 0) return;
        const eventExpr = f.event === 'any' ? 'true' : `(event == ${cppString(f.event)})`;
        push(`        if (source == ${sourceIndex} && ${eventExpr}) { ${flowAction(f, indexById, components, isVulkan)} }`);
      }
    });
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
      '        else if (w.type == "select" || w.type == "carousel") { const std::string selected = w.items.empty() ? w.label : w.items[static_cast<std::size_t>(std::max(0, std::min(static_cast<int>(w.items.size()) - 1, static_cast<int>(w.value))))]; hui::ui::text(draw, strong, "‹  " + selected + "  ›", w.x + w.w * 0.5f, w.y + w.h * 0.65f, w.font, fg, hui::gfx::Align::center); if (w.type == "select") hui::ui::text(draw, body, w.label, w.x + 8, w.y + 16, std::max(12.0f, w.font * 0.65f), fg); }',
      '        else if (w.type == "list") { hui::ui::text(draw, strong, w.label, w.x + 12, w.y + 26, w.font, fg); const float rowH = std::max(24.0f, (w.h - 38) / std::max<std::size_t>(1, w.items.size())); for (std::size_t n = 0; n < w.items.size() && n < 8; ++n) { const float y = w.y + 36 + static_cast<float>(n) * rowH; if (static_cast<int>(n) == static_cast<int>(w.value)) draw.rounded_rect(Rect{w.x + 6, y, w.w - 12, rowH - 2}, 5, Color::rgb(0x7865f6, 0.25f)); hui::ui::text(draw, body, w.items[n], w.x + 16, y + rowH * 0.65f, std::min(22.0f, w.font), fg); } }',
      '        else if (w.type == "progress") { const float ratio = w.max > w.min ? clamp_value((w.value - w.min) / (w.max - w.min), 0, 1) : 0; draw.rounded_rect(Rect{w.x, w.y + w.h * 0.38f, w.w, std::max(6.0f, w.h * 0.24f)}, 6, Color::rgb(0x374159)); draw.rounded_rect(Rect{w.x, w.y + w.h * 0.38f, w.w * ratio, std::max(6.0f, w.h * 0.24f)}, 6, accent_); }',
      '        else if (w.type == "badge") { hui::ui::text(draw, strong, w.label, w.x + w.w * 0.5f, w.y + w.h * 0.66f, w.font, fg, hui::gfx::Align::center); }',
      ...(isVulkan ? [
        '        else if (w.type == "image") { const std::uint32_t texture = w.asset_path.empty() ? 0u : ps5ui::ps5hs_texture_for(w.asset_path); if (texture != 0) draw.image(texture, r, Rect{0, 0, 1, 1}, Color::rgb(0xffffff), 8.0f); else { draw.bordered_rect(r, 8, Color::rgb(0x172033), 1, Color::rgb(0x596985)); hui::ui::text(draw, strong, "▧  " + w.label, w.x + w.w * 0.5f, w.y + w.h * 0.5f, std::min(w.font, 24.0f), fg, hui::gfx::Align::center); hui::ui::text(draw, body, "Imagen no disponible", w.x + w.w * 0.5f, w.y + w.h * 0.68f, 13, Color::rgb(0x9aa8c1), hui::gfx::Align::center); } }'
      ] : [
        '        else if (w.type == "image") { if (w.texture != 0) draw.image(w.texture, r, Rect{0, 0, 1, 1}, Color::rgb(0xffffff), 8.0f); else { draw.bordered_rect(r, 8, Color::rgb(0x172033), 1, Color::rgb(0x596985)); hui::ui::text(draw, strong, "▧  " + w.label, w.x + w.w * 0.5f, w.y + w.h * 0.5f, std::min(w.font, 24.0f), fg, hui::gfx::Align::center); hui::ui::text(draw, body, "Imagen no disponible", w.x + w.w * 0.5f, w.y + w.h * 0.68f, 13, Color::rgb(0x9aa8c1), hui::gfx::Align::center); } }'
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
    const v = cppString(flow.value || flow.message || '');
    switch (flow.action) {
      case 'notify': return `status_ = ${cppString(flow.message || 'Acción ejecutada')};`;
      case 'setText': {
        if (i < 0) throw new Error(`setText tiene un destino inexistente: ${flow.targetId}`);
        return components[i].type === 'input' ? `widgets_[${i}].text = ${v};` : `widgets_[${i}].label = ${v};`;
      }
      case 'toggleVisibility': {
        if (i < 0) throw new Error(`toggleVisibility tiene un destino inexistente: ${flow.targetId}`);
        return `widgets_[${i}].visible = !widgets_[${i}].visible;`;
      }
      case 'setValue': {
        if (i < 0) throw new Error(`setValue tiene un destino inexistente: ${flow.targetId}`);
        const target = components[i];
        if (target.type === 'toggle') return `widgets_[${i}].checked = ${/^(true|1|sí|si|on)$/i.test(String(flow.value)) ? 'true' : 'false'};`;
        if (['select', 'carousel', 'list'].includes(target.type)) return `widgets_[${i}].value = static_cast<float>(std::max(0, std::min(static_cast<int>(widgets_[${i}].items.size()) - 1, ${Math.max(0, Math.trunc(Number(flow.value) || 0))})));`;
        return `widgets_[${i}].value = clamp_value(${floatLiteral(Number(flow.value) || 0)}, widgets_[${i}].min, widgets_[${i}].max);`;
      }
      case 'changeColor': return `background_ = Color::rgb(0x${colorHex(flow.value, 0x7865f6).toString(16).padStart(6, '0')});`;
      case 'navigate': return `screen_ = ${cppString(flow.targetScreen || 'screen-main')}; selected_ = next_interactive(-1, 1); status_ = "Pantalla: " + screen_;`;
      default: throw new Error(`Acción de flujo sin implementación: ${flow.action}`);
    }
  }

  const api = { generate, cppString };
  root.PS5HSNativeCodegen = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
