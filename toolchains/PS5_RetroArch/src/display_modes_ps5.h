/* PS5 RetroArch - the display modes test (src/display_modes_ps5.cpp says why).
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#ifndef PS5_RETROARCH_DISPLAY_MODES_PS5_H
#define PS5_RETROARCH_DISPLAY_MODES_PS5_H

#ifdef __cplusplus
#include <string>

namespace ps5::display_modes
{
/* Runs the test when its arm file is there, disarming it; true when every mode
 * presented. */
bool run_test(const std::string &arm, const std::string &results);
} // namespace ps5::display_modes

extern "C"
{
#endif

    void ps5_display_modes_test_if_requested(void);

#ifdef __cplusplus
}
#endif

#endif
