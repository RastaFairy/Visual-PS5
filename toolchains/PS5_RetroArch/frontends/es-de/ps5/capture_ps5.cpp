/* PS5 RetroArch - pictures of what EmulationStation draws, for evidence and previews.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Armed by /app0/es-de/capture-test.txt (tools/run-title.sh --frontend-capture):
 *
 *     <seconds>[,<seconds>...] <run id> [scroll][,profile][,quit][,launch][,menu]
 *
 * ES-DE presents each frame with SDL_GL_SwapWindow, which the link wraps
 * (frontends/es-de/link.sh). When a frame is presented that many seconds after
 * the first, its back buffer is read and written as
 * /app0/es-de/capture-<run id>-<pid>-<seconds>.ppm (binary RGB, top row first), and a
 * line is added to /app0/es-de/capture-test.jsonl with the frame's number, size,
 * the sound driver SDL chose and how many of its devices are playing, the OpenGL
 * error state and the frame times since the line before: how far
 * apart the swaps were and how long the swap itself took (it waits for the GPU
 * to finish the frame and for the flip). With "scroll", a Right key is pressed
 * every 400 ms from the fifth second on, as a person browsing the systems would,
 * so the times are those of ES-DE animating and loading. With "profile", the
 * process is sampled every millisecond of CPU time (an ITIMER_PROF timer): each
 * sample is the interrupted instruction and up to eight return addresses from its
 * frame-pointer chain, written to /app0/es-de/profile-<run id>.txt at the last
 * capture, one sample a line, in hex, for symbolizing against the linked ELF. With
 * "quit", ES-DE is sent SDL_QUIT after the last capture, as its Quit entry does,
 * so it returns to eboot.bin (main_ps5.cpp). With "launch", Return is pressed at 6 s
 * and at 8 s, which opens the system ES-DE starts on and starts its first game in
 * RetroArch (game mode, game_ps5.cpp); an ES-DE back from that game presses nothing.
 * The process id in each file name and line tells the ES-DE before a game from the
 * one after it.
 * Unarmed, this costs one failed open, once.
 */
#include <SDL.h>

#include <unistd.h>

#include <signal.h>
#include <sys/time.h>
#include <ucontext.h>

#define GL_GLEXT_PROTOTYPES 1
#include <GL/gl.h>
#include <GL/glext.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

extern "C" void __real_SDL_GL_SwapWindow(SDL_Window *window);
extern "C" int ps5_esde_started_from_game(void);

namespace
{
constexpr const char *arm_file = "/app0/es-de/capture-test.txt";
constexpr const char *record_file = "/app0/es-de/capture-test.jsonl";

struct Capture
{
    bool read = false;
    std::vector<unsigned> seconds;
    std::string run;
    size_t next = 0;
    bool scroll = false;
    bool profile = false;
    bool quit = false;
    bool launch = false;
    bool menu = false;
    unsigned menu_presses = 0;
    unsigned launch_presses = 0;
    unsigned long long frames = 0;
    std::chrono::steady_clock::time_point first, last_swap, last_press;
    std::vector<float> intervals_ms, swaps_ms; // since the last record
    unsigned presses = 0, presses_total = 0;
    std::string slow; // frames over 100 ms since the last record: "seconds:ms@presses"
};

Capture state;

bool valid_run(const std::string &run)
{
    if (run.empty() || run.size() > 64)
        return false;
    for (char c : run)
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
              c == '-' || c == '_'))
            return false;
    return true;
}

void read_arm()
{
    state.read = true;
    std::FILE *arm = std::fopen(arm_file, "r");
    if (!arm)
        return;
    char list[128] = {}, run[80] = {}, mode[16] = {};
    const int fields = std::fscanf(arm, "%127s %79s %15s", list, run, mode);
    std::fclose(arm);
    if (fields < 2 || !valid_run(run))
        return;
    state.scroll = fields == 3 && std::strstr(mode, "scroll") != nullptr;
    state.profile = fields == 3 && std::strstr(mode, "profile") != nullptr;
    state.quit = fields == 3 && std::strstr(mode, "quit") != nullptr;
    state.menu = fields == 3 && std::strstr(mode, "menu") != nullptr;
    state.launch =
        fields == 3 && std::strstr(mode, "launch") != nullptr && !ps5_esde_started_from_game();
    unsigned last = 0;
    for (char *token = std::strtok(list, ","); token; token = std::strtok(nullptr, ","))
    {
        char *end = nullptr;
        const unsigned long value = std::strtoul(token, &end, 10);
        if (!end || *end || value == 0 || value > 3600 || value <= last)
            return;
        state.seconds.push_back(static_cast<unsigned>(value));
        last = static_cast<unsigned>(value);
    }
    state.run = run;
}

constexpr unsigned sample_depth = 9; // the instruction and eight return addresses
constexpr unsigned sample_capacity = 120000;
uintptr_t samples[sample_capacity][sample_depth];
volatile unsigned sample_count = 0;
volatile bool sampling = false;

void on_profile_tick(int, siginfo_t *, void *context)
{
    if (!sampling)
        return;
    const unsigned index = __atomic_fetch_add(&sample_count, 1u, __ATOMIC_RELAXED);
    if (index >= sample_capacity)
        return;
    const mcontext_t &machine = static_cast<ucontext_t *>(context)->uc_mcontext;
    uintptr_t *sample = samples[index];
    sample[0] = uintptr_t(machine.mc_rip);
    uintptr_t frame = uintptr_t(machine.mc_rbp);
    const uintptr_t stack = uintptr_t(machine.mc_rsp);
    for (unsigned depth = 1; depth < sample_depth; depth++)
    {
        // A frame pointer above the interrupted stack pointer and within 8 MiB of it.
        if (frame < stack || frame - stack > (8u << 20) || (frame & 7))
        {
            sample[depth] = 0;
            continue;
        }
        const uintptr_t *link = reinterpret_cast<const uintptr_t *>(frame);
        sample[depth] = link[1];
        frame = link[0];
    }
}

void start_profile()
{
    struct sigaction action{};
    action.sa_sigaction = on_profile_tick;
    action.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGPROF, &action, nullptr) != 0)
        return;
    sampling = true;
    struct itimerval every{};
    every.it_interval.tv_usec = 1000;
    every.it_value.tv_usec = 1000;
    if (setitimer(ITIMER_PROF, &every, nullptr) != 0)
        sampling = false;
}

void write_profile()
{
    sampling = false;
    struct itimerval off{};
    setitimer(ITIMER_PROF, &off, nullptr);
    const unsigned count = std::min(unsigned(sample_count), sample_capacity);
    const std::string file = "/app0/es-de/profile-" + state.run + ".txt";
    if (std::FILE *out = std::fopen(file.c_str(), "w"))
    {
        for (unsigned index = 0; index < count; index++)
        {
            for (unsigned depth = 0; depth < sample_depth; depth++)
                std::fprintf(out, depth ? " %lx" : "%lx",
                             static_cast<unsigned long>(samples[index][depth]));
            std::fputc('\n', out);
        }
        std::fclose(out);
    }
}

float percentile(std::vector<float> values, float fraction)
{
    if (values.empty())
        return 0.0f;
    const size_t index = std::min(values.size() - 1, size_t(fraction * float(values.size())));
    std::nth_element(values.begin(), values.begin() + long(index), values.end());
    return values[index];
}

float mean(const std::vector<float> &values)
{
    float sum = 0.0f;
    for (float value : values)
        sum += value;
    return values.empty() ? 0.0f : sum / float(values.size());
}

void record(unsigned seconds, int width, int height, const std::string &file, unsigned error,
            bool written)
{
    const auto &gaps = state.intervals_ms;
    const long slow =
        std::count_if(gaps.begin(), gaps.end(), [](float gap) { return gap > 25.0f; });
    /* Sound: the driver SDL chose and the devices playing now (ES-DE opens one). */
    const char *audio_driver = SDL_GetCurrentAudioDriver();
    int audio_playing = 0;
    for (SDL_AudioDeviceID device = 1; device <= 8; device++)
        audio_playing += SDL_GetAudioDeviceStatus(device) == SDL_AUDIO_PLAYING;
    if (std::FILE *out = std::fopen(record_file, "a"))
    {
        std::fprintf(
            out,
            "{\"run\":\"%s\",\"pid\":%d,\"seconds\":%u,\"frame\":%llu,\"width\":%d,\"height\":%d,"
            "\"audio_driver\":\"%s\",\"audio_playing\":%d,"
            "\"file\":\"%s\",\"gl_error\":%u,\"written\":%s,\"interval_frames\":%zu,"
            "\"interval_ms\":{\"mean\":%.2f,\"p50\":%.2f,\"p95\":%.2f,\"max\":%.2f,\"over_25\":%ld}"
            ","
            "\"swap_ms\":{\"mean\":%.2f,\"p95\":%.2f,\"max\":%.2f},\"presses\":%u,\"slow\":[%s]}\n",
            state.run.c_str(), static_cast<int>(getpid()), seconds, state.frames, width, height,
            audio_driver ? audio_driver : "", audio_playing, file.c_str(), error,
            written ? "true" : "false", gaps.size(), mean(gaps), percentile(gaps, 0.5f),
            percentile(gaps, 0.95f), percentile(gaps, 1.0f), slow, mean(state.swaps_ms),
            percentile(state.swaps_ms, 0.95f), percentile(state.swaps_ms, 1.0f), state.presses,
            state.slow.c_str());
        std::fclose(out);
    }
    state.slow.clear();
    state.intervals_ms.clear();
    state.swaps_ms.clear();
    state.presses = 0;
}

void press(SDL_Scancode scancode, SDL_Keycode key)
{
    SDL_Event event{};
    event.type = SDL_KEYDOWN;
    event.key.state = SDL_PRESSED;
    event.key.keysym.scancode = scancode;
    event.key.keysym.sym = key;
    SDL_PushEvent(&event);
    event.type = SDL_KEYUP;
    event.key.state = SDL_RELEASED;
    SDL_PushEvent(&event);
    state.presses++;
    state.presses_total++;
}

void press_right()
{
    press(SDL_SCANCODE_RIGHT, SDLK_RIGHT);
}

void capture(SDL_Window *window, unsigned seconds)
{
    int width = 0, height = 0;
    SDL_GL_GetDrawableSize(window, &width, &height);
    const std::string file = "/app0/es-de/capture-" + state.run + "-" + std::to_string(getpid()) +
                             "-" + std::to_string(seconds) + ".ppm";
    if (width <= 0 || height <= 0 || width > 8192 || height > 8192)
    {
        record(seconds, width, height, file, 0, false);
        return;
    }
    while (glGetError() != GL_NO_ERROR)
    {
    }
    GLint read_framebuffer = 0, pack_alignment = 4;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read_framebuffer);
    glGetIntegerv(GL_PACK_ALIGNMENT, &pack_alignment);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    glReadBuffer(GL_BACK);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    const size_t row = static_cast<size_t>(width) * 3;
    std::vector<unsigned char> pixels(row * static_cast<size_t>(height));
    glReadPixels(0, 0, width, height, GL_RGB, GL_UNSIGNED_BYTE, pixels.data());
    const unsigned error = glGetError();
    glPixelStorei(GL_PACK_ALIGNMENT, pack_alignment);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, static_cast<GLuint>(read_framebuffer));

    bool written = false;
    if (std::FILE *out = std::fopen(file.c_str(), "wb"))
    {
        std::fprintf(out, "P6\n%d %d\n255\n", width, height);
        written = true;
        for (int y = height - 1; y >= 0 && written; y--)
            written = std::fwrite(pixels.data() + row * static_cast<size_t>(y), 1, row, out) == row;
        written = std::fclose(out) == 0 && written;
    }
    record(seconds, width, height, file, error, written);
}
} // namespace

extern "C" void __wrap_SDL_GL_SwapWindow(SDL_Window *window)
{
    const auto now = std::chrono::steady_clock::now();
    if (!state.read)
    {
        read_arm();
        state.first = state.last_swap = state.last_press = now;
        if (state.profile && !state.seconds.empty())
            start_profile();
    }
    else if (!state.seconds.empty())
    {
        const float gap = std::chrono::duration<float, std::milli>(now - state.last_swap).count();
        state.intervals_ms.push_back(gap);
        if (gap > 100.0f && state.slow.size() < 400)
        {
            char entry[64];
            std::snprintf(entry, sizeof(entry), "%s\"%.2f:%.0f@%u\"", state.slow.empty() ? "" : ",",
                          std::chrono::duration<float>(now - state.first).count(), gap,
                          state.presses_total);
            state.slow += entry;
        }
    }
    state.last_swap = now;
    state.frames++;
    if (state.launch && state.launch_presses < 2 &&
        now - state.first >= std::chrono::seconds(6 + 2 * state.launch_presses))
    {
        press(SDL_SCANCODE_RETURN, SDLK_RETURN);
        state.launch_presses++;
    }
    // "menu": Escape at 6 s opens ES-DE's menu, Return at 10 s opens its first entry
    // (Frame Generation on the PS5), so captures at 8 and 12 s show both.
    if (state.menu && state.menu_presses < 2 &&
        now - state.first >= std::chrono::seconds(6 + 4 * state.menu_presses))
    {
        if (state.menu_presses == 0)
            press(SDL_SCANCODE_ESCAPE, SDLK_ESCAPE);
        else
            press(SDL_SCANCODE_RETURN, SDLK_RETURN);
        state.menu_presses++;
    }
    if (state.scroll && state.next < state.seconds.size() &&
        now - state.first >= std::chrono::seconds(5) &&
        now - state.last_press >= std::chrono::milliseconds(400))
    {
        press_right();
        state.last_press = now;
    }
    if (state.next < state.seconds.size())
    {
        const auto elapsed = std::chrono::steady_clock::now() - state.first;
        const unsigned seconds = state.seconds[state.next];
        if (elapsed >= std::chrono::seconds(seconds))
        {
            capture(window, seconds);
            state.next++;
            if (state.profile && state.next == state.seconds.size())
                write_profile();
            if (state.quit && state.next == state.seconds.size())
            {
                SDL_Event event{};
                event.type = SDL_QUIT;
                SDL_PushEvent(&event);
            }
        }
    }
    const auto before = std::chrono::steady_clock::now();
    __real_SDL_GL_SwapWindow(window);
    if (!state.seconds.empty())
        state.swaps_ms.push_back(
            std::chrono::duration<float, std::milli>(std::chrono::steady_clock::now() - before)
                .count());
}
