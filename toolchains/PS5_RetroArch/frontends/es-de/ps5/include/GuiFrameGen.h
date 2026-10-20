/* PS5 frame generation options in ES-DE's menu (patches/series, 0120). The choices are written to
 * /app0/config/framegen.cfg, which the title appends when it starts RetroArch; RetroArch's own menus
 * edit the same file (src/ps5_framegen_config.h). */
#pragma once
#include "components/OptionListComponent.h"
#include "guis/GuiSettings.h"
#include "ps5_framegen_config.h"

class GuiFrameGen : public GuiSettings
{
public:
    GuiFrameGen() : GuiSettings("FRAME GENERATION")
    {
        auto options = std::make_shared<ps5_fg_options>();
        ps5_fg_defaults(options.get());
        ps5_fg_load(options.get());

        for (unsigned item = 0; item < PS5_FG_RESET; item++) {
            auto list = std::make_shared<OptionListComponent<unsigned>>(ps5_fg_item_name(item), false);
            for (unsigned value = 0; value < ps5_fg_choice_count(item); value++)
                list->add(ps5_fg_choice_name(item, value), value, value == ps5_fg_get(options.get(), item));
            addWithLabel(std::string(ps5_fg_item_name(item)), list);
            addSaveFunc([options, list, item] { ps5_fg_set(options.get(), item, list->getSelected()); });
        }
        addSaveFunc([options] { ps5_fg_save(options.get()); });
    }
};
