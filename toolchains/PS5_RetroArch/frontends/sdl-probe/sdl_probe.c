/* PS5 RetroArch - the SDL probe: SDL2 and OpenGL in an executable of its own.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Why this exists. EmulationStation is an SDL2 and OpenGL program, and it is to
 * run as its own executable beside eboot.bin (evidence/loadexec-second-image/),
 * drawing with ../PS5_OpenGL's stack and SDL2 built on it by that project's
 * bridge, never with RetroArch's Vulkan driver. Before EmulationStation, this
 * proves the pieces it needs together on the console: the executable starts from
 * LoadExec with its arguments, SDL opens a window with an OpenGL 3.3 core
 * context, frames reach the screen, the controller arrives as an SDL event, and
 * the program hands the title back to eboot.bin.
 *
 * It shows red, green and blue for two seconds each, reads each colour back
 * from the frame's centre, records what it saw in /app0/es-de/sdl-probe.json,
 * and restarts eboot.bin with the argument it was started with (the relaunch
 * test's, so that test sees its next generation).
 */
#include <SDL.h>
#include <GL/glcorearb.h>
#include <stdio.h>
#include <string.h>

int sceSystemServiceLoadExec(const char *path, const char *const *argv);
int sceSystemServiceHideSplashScreen(void);
int sceKernelUsleep(unsigned int microseconds);

#define RESULT_PATH "/app0/es-de/sdl-probe.json"
#define SECONDS_A_COLOUR 2

static void json_text(FILE *out, const char *text)
{
    fputc('"', out);
    for (const unsigned char *at = (const unsigned char *)(text ? text : ""); *at; at++)
    {
        if (*at == '"' || *at == '\\')
            fprintf(out, "\\%c", *at);
        else if (*at < 0x20)
            fprintf(out, "\\u%04x", *at);
        else
            fputc(*at, out);
    }
    fputc('"', out);
}

int main(int argc, char **argv)
{
    static const float colours[3][3] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}};
    SDL_Window *window = NULL;
    SDL_GLContext context = NULL;
    SDL_Joystick *pad = NULL;
    char pad_name[128] = "";
    int frames[3] = {0, 0, 0}, matched[3] = {0, 0, 0}, width = 0, height = 0, buttons = 0;
    const char *vendor = "", *renderer = "", *version = "";
    const char *failure = NULL;

    const int splash = sceSystemServiceHideSplashScreen();
    SDL_SetMainReady();
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK | SDL_INIT_TIMER) < 0)
    {
        failure = "SDL_Init";
        goto done;
    }
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_DisplayMode mode;
    if (SDL_GetDesktopDisplayMode(0, &mode) < 0)
    {
        failure = "SDL_GetDesktopDisplayMode";
        goto done;
    }
    window = SDL_CreateWindow("PS5 RetroArch SDL probe", SDL_WINDOWPOS_UNDEFINED,
                              SDL_WINDOWPOS_UNDEFINED, mode.w, mode.h,
                              SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN);
    if (!window || !(context = SDL_GL_CreateContext(window)) ||
        SDL_GL_MakeCurrent(window, context) < 0)
    {
        failure = "SDL window or GL context";
        goto done;
    }
    PFNGLGETSTRINGPROC get_string = (PFNGLGETSTRINGPROC)SDL_GL_GetProcAddress("glGetString");
    PFNGLVIEWPORTPROC viewport = (PFNGLVIEWPORTPROC)SDL_GL_GetProcAddress("glViewport");
    PFNGLCLEARCOLORPROC clear_color = (PFNGLCLEARCOLORPROC)SDL_GL_GetProcAddress("glClearColor");
    PFNGLCLEARPROC clear = (PFNGLCLEARPROC)SDL_GL_GetProcAddress("glClear");
    PFNGLREADPIXELSPROC read_pixels = (PFNGLREADPIXELSPROC)SDL_GL_GetProcAddress("glReadPixels");
    PFNGLGETERRORPROC get_error = (PFNGLGETERRORPROC)SDL_GL_GetProcAddress("glGetError");
    if (!get_string || !viewport || !clear_color || !clear || !read_pixels || !get_error)
    {
        failure = "GL entry points";
        goto done;
    }
    vendor = (const char *)get_string(GL_VENDOR);
    renderer = (const char *)get_string(GL_RENDERER);
    version = (const char *)get_string(GL_VERSION);
    SDL_GL_GetDrawableSize(window, &width, &height);
    SDL_GL_SetSwapInterval(1);
    viewport(0, 0, width, height);

    for (int colour = 0; colour < 3; colour++)
    {
        const Uint64 until = SDL_GetTicks64() + SECONDS_A_COLOUR * 1000;
        while (SDL_GetTicks64() < until)
        {
            SDL_Event event;
            while (SDL_PollEvent(&event))
            {
                if (event.type == SDL_JOYDEVICEADDED && !pad)
                {
                    pad = SDL_JoystickOpen(event.jdevice.which);
                    if (pad)
                        snprintf(pad_name, sizeof pad_name, "%s", SDL_JoystickName(pad));
                }
                else if (event.type == SDL_JOYBUTTONDOWN)
                    buttons++;
            }
            clear_color(colours[colour][0], colours[colour][1], colours[colour][2], 1.0f);
            clear(GL_COLOR_BUFFER_BIT);
            unsigned char centre[4] = {0, 0, 0, 0};
            read_pixels(width / 2, height / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, centre);
            if (centre[0] == (unsigned char)(colours[colour][0] * 255) &&
                centre[1] == (unsigned char)(colours[colour][1] * 255) &&
                centre[2] == (unsigned char)(colours[colour][2] * 255))
                matched[colour]++;
            if (get_error() != GL_NO_ERROR)
            {
                failure = "GL error in a frame";
                goto done;
            }
            SDL_GL_SwapWindow(window);
            frames[colour]++;
        }
    }

done:;
    FILE *out = fopen(RESULT_PATH, "wb");
    if (out)
    {
        fprintf(out, "{\"argc\":%d,\"argv\":[", argc);
        for (int i = 0; i < argc; i++)
        {
            if (i)
                fputc(',', out);
            json_text(out, argv[i]);
        }
        fprintf(out, "],\"splash\":%d,\"width\":%d,\"height\":%d,\"gl_vendor\":", splash, width,
                height);
        json_text(out, vendor);
        fputs(",\"gl_renderer\":", out);
        json_text(out, renderer);
        fputs(",\"gl_version\":", out);
        json_text(out, version);
        fprintf(out, ",\"frames\":[%d,%d,%d],\"centre_matched\":[%d,%d,%d],\"pad\":", frames[0],
                frames[1], frames[2], matched[0], matched[1], matched[2]);
        json_text(out, pad_name);
        fprintf(out, ",\"buttons\":%d,\"failure\":", buttons);
        json_text(out, failure ? failure : "");
        if (failure)
        {
            fputs(",\"sdl_error\":", out);
            json_text(out, SDL_GetError());
        }
        fputs("}\n", out);
        fclose(out);
    }
    if (pad)
        SDL_JoystickClose(pad);
    if (context)
    {
        SDL_GL_MakeCurrent(NULL, NULL);
        SDL_GL_DeleteContext(context);
    }
    if (window)
        SDL_DestroyWindow(window);
    SDL_Quit();

    /* Back to the title, with the argument this run was started with. */
    const char *const back[] = {argc > 0 && argv[0] && argv[0][0] ? argv[0] : "", NULL};
    sceSystemServiceLoadExec("/app0/eboot.bin", back);
    for (;;)
        sceKernelUsleep(100000);
}
