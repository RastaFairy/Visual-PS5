/* PS5 RetroArch - L1 held as the title starts, which opens the picker even when a
 * frontend is remembered (src/frontend_mode_ps5.cpp, src/ps5_frontend_choice.h).
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Read on the first user's pad before RetroArch or a frontend opens it, with the calls
 * and sample layout src/input_ps5.cpp uses. The shell can hold the pad while it shows
 * the title starting (a sample's top bit), so the samples are read for up to a second,
 * and the first one that is the title's decides. The pad is closed again: whatever
 * starts next opens its own. One trace line says what was read.
 */
#include <cstddef>
#include <cstdint>
#include <cstdio>

#include "frontend_mode_ps5.h"
#include "trace.hpp"

extern "C"
{
    std::int32_t sceUserServiceInitialize(const void *params);
    std::int32_t sceUserServiceGetInitialUser(std::int32_t *user_id);
    std::int32_t sceUserServiceTerminate();
    std::int32_t scePadInit();
    std::int32_t scePadOpen(std::int32_t user_id, std::int32_t port_type, std::int32_t index,
                            const void *params);
    std::int32_t scePadRead(std::int32_t handle, void *samples, std::int32_t capacity);
    std::int32_t scePadClose(std::int32_t handle);
    std::int32_t sceKernelUsleep(std::uint32_t microseconds);
}

namespace
{
struct Sample
{
    std::uint32_t buttons;
    std::uint8_t sticks_and_triggers[72];
    std::int32_t connected;
    std::uint8_t rest[40];
};
static_assert(sizeof(Sample) == 120, "the console's pad samples are 120 bytes");
static_assert(offsetof(Sample, connected) == 0x4c, "connection state sits at 0x4c");

constexpr std::uint32_t button_l1 = 0x000400u;
constexpr std::uint32_t system_has_pad = 0x80000000u;
constexpr int reads = 20; /* every 50 ms: a second */
constexpr std::uint32_t read_interval = 50000;
} // namespace

extern "C" bool ps5_frontend_reopen_held(void)
{
    const bool owns_users = sceUserServiceInitialize(nullptr) == 0;
    std::int32_t user = -1;
    std::int32_t handle = -1;
    if (sceUserServiceGetInitialUser(&user) >= 0 && scePadInit() >= 0)
        for (int attempt = 0; attempt < 10 && handle < 0; attempt++)
        {
            handle = scePadOpen(user, 0, 0, nullptr);
            if (handle < 0)
                sceKernelUsleep(100000);
        }
    bool decided = false, held = false;
    int waited_ms = 0, system_samples = 0;
    static Sample samples[64];
    for (int read = 0; handle >= 0 && read < reads && !decided; read++)
    {
        const std::int32_t count = scePadRead(handle, samples, 64);
        for (std::int32_t i = 0; i < count && i < 64 && !decided; i++)
        {
            if (!samples[i].connected)
                continue;
            if (samples[i].buttons & system_has_pad)
            {
                system_samples++;
                continue;
            }
            decided = true;
            held = (samples[i].buttons & button_l1) != 0;
        }
        if (!decided)
        {
            sceKernelUsleep(read_interval);
            waited_ms += read_interval / 1000;
        }
    }
    if (handle >= 0)
        scePadClose(handle);
    if (owns_users)
        sceUserServiceTerminate();
    char line[160];
    std::snprintf(line, sizeof line,
                  "frontend: L1 at launch: pad %d, %s after %d ms (%d samples the system's)",
                  static_cast<int>(handle), decided ? (held ? "held" : "not held") : "no sample",
                  waited_ms, system_samples);
    ps5::debug::mark(line);
    return held;
}
