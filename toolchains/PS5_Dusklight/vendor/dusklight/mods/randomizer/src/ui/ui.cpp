#include "ui.hpp"

#include <mods/svc/log.hpp>

#include "../session.hpp"

#include "rando_seed_generation.hpp"
#include "rando_config.hpp"

#include <thread>

namespace randomizer::ui {
UiStyleHandle styleHandle{};
static std::atomic uiRunning = false;
static std::thread progressBarUpdateThread;

// Put updating the progress bar on its own thread so it can run more than 30 times a second.
// Otherwise, it looks choppy at higher frame rates
void update_seed_gen_progress_bar() {
    while (uiRunning.load(std::memory_order_relaxed)) {
        UpdateProgressBar();
        std::this_thread::sleep_for(std::chrono::milliseconds(16));
    }
}

ModResult initialize() {
    ModResult res;

    res = session::svc_mng.ui->register_styles_file(
        session::svc_mng.mod_ctx,
        UI_SCOPE_WINDOW,
        "ui.rcss",
        &styleHandle);
    if (res != MOD_OK) {
        mods::log::error("failed to register rcss!");
        return res;
    }

    res = buildMenuTab();
    if (res != MOD_OK) {
        mods::log::error("failed to initialize randomizer menu tab!");
        return res;
    }

    uiRunning = true;
    progressBarUpdateThread = std::thread(update_seed_gen_progress_bar);
    return MOD_OK;
}

void update() {
    UpdateSeedGenerationDialog();
}

ModResult shutdown() {
    uiRunning = false;
    if (progressBarUpdateThread.joinable()) {
        progressBarUpdateThread.join();
    }
    removeMenuTab();
    session::svc_mng.ui->unregister_styles(mod_ctx, styleHandle);
    return MOD_OK;
}

}