/* The PS5 WebUI, generated from the current console address; no remote QR service. */
#pragma once
#include "GuiComponent.h"
#include "components/TextComponent.h"
#include "ps5_webui_qr.h"
#include "renderers/Renderer.h"
#include <algorithm>
#include <cmath>

class GuiWebUI : public GuiComponent
{
public:
    GuiWebUI()
        : heading("WebUI", Font::get(FONT_SIZE_LARGE), 0xffffffff, ALIGN_CENTER),
          address("", Font::get(FONT_SIZE_MEDIUM), 0xffffffff, ALIGN_CENTER),
          hint("Scan with a phone on the same network", Font::get(FONT_SIZE_SMALL),
               0xffffffff, ALIGN_CENTER)
    {
        ps5_webui_qr_refresh(&qr, true);
    }
    bool input(InputConfig* config, Input input) override
    {
        if (input.value && (config->isMappedTo("b", input) || config->isMappedTo("back", input))) {
            delete this;
            return true;
        }
        return true; // A modal: do not pass input to the menu beneath it.
    }
    std::vector<HelpPrompt> getHelpPrompts() override { return {{"b", "close"}}; }
    void render(const glm::mat4& parentTrans) override
    {
        ps5_webui_qr_refresh(&qr, false);
        auto* renderer = Renderer::getInstance();
        const float w = renderer->getScreenWidth(), h = renderer->getScreenHeight();
        renderer->setMatrix(parentTrans);
        renderer->drawRect(0, 0, w, h, 0x12101fff, 0x12101fff);
        if (qr.size) {
            const float scale = std::max(1.0f, std::floor(h * 0.48f / qr.size));
            const float side = scale * qr.size, left = std::floor((w - side) / 2), top = std::floor(h * 0.23f);
            renderer->drawRect(left, top, side, side, 0xffffffff, 0xffffffff);
            for (unsigned y = 0; y < qr.size; y++)
                for (unsigned x = 0; x < qr.size; x++)
                    if (qr.modules[y * qr.size + x])
                        renderer->drawRect(left + x * scale, top + y * scale, scale, scale,
                                           0x000000ff, 0x000000ff);
        }
        heading.setSize(w, h * 0.10f);
        heading.setPosition(0, h * 0.08f);
        heading.render(parentTrans);
        address.setText(qr.size ? qr.url : PS5_WEBUI_QR_OFFLINE);
        address.setSize(w, h * 0.09f);
        address.setPosition(0, h * 0.75f);
        address.render(parentTrans);
        hint.setSize(w, h * 0.08f);
        hint.setPosition(0, h * 0.86f);
        hint.render(parentTrans);
    }
private:
    ps5_webui_qr qr{};
    TextComponent heading, address, hint;
};
