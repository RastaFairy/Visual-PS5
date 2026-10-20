/* PS5GL: does ps5gpu_target_create() - a caller-sized render target, the
 * generalization of the fixed scene/reflection/shadow targets - actually
 * work on hardware? See its UNTESTED note in ps5gpu.h; this is that test.
 *
 * left  - a control quad, sampling a known-good magenta texture the normal
 *         way. Expect: pure magenta.
 * right - a quad sampling the user render target's texture id. That target
 *         was selected once with ps5gpu_set_target(), had a solid GREEN
 *         quad drawn into it filling its whole area, then the scene target
 *         was reselected before drawing this on-screen quad. If the new
 *         target geometry (width/height/colour address/depth address in
 *         emit_frame_state) is right, this reads back pure green. Anything
 *         else - black, garbage, the wrong size/scale - means the
 *         generalization has a bug, the same way milestone 1's multi-texture
 *         container did on its first few tries.
 */
#include <stdio.h>
#include <string.h>

#include "ps5gpu.h"

extern int sceKernelSendNotificationRequest(int device, void *request, int size, int flags);
extern int mkdir(const char *path, unsigned int mode);

#define TOTAL_FRAMES 300
#define LOG_PATH "/app0/data/ps5gl_rendertarget.txt"

static void notify(const char *msg) {
    static char request[3120];
    int i;
    for (i = 0; i < 3120; i++) request[i] = 0;
    for (i = 0; msg[i] != 0 && i < 3074; i++) request[45 + i] = msg[i];
    sceKernelSendNotificationRequest(0, request, sizeof(request), 0);
}

static void draw_quad(float x0, float y0, float x1, float y1, uint32_t color) {
    Ps5GpuVertex quad[6];
    float corners[6][2] = {
        { x0, y1 }, { x1, y1 }, { x0, y0 },
        { x1, y1 }, { x1, y0 }, { x0, y0 },
    };
    int i;
    for (i = 0; i < 6; i++) {
        quad[i].x = corners[i][0]; quad[i].y = corners[i][1]; quad[i].z = 0.0f;
        quad[i].u = 0.5f; quad[i].v = 0.5f; quad[i].n_pad = 0.0f;
        quad[i].uv_unused[0] = 0.0f; quad[i].uv_unused[1] = 0.0f;
        quad[i].color = color;
    }
    ps5gpu_draw(quad, 6);
}

int main(void) {
    FILE *log;
    uint32_t magenta_tex, white_tex;
    static uint8_t magenta_rgba[4 * 4 * 4];
    static uint8_t white_rgba[4 * 4 * 4];
    int rt_index, rt_tex;
    int frame;

    mkdir("/app0/data", 0777);
    log = fopen(LOG_PATH, "wb");
    if (!log) return 1;
    fprintf(log, "PS5GL: ps5gpu_target_create() hardware test.\n\n");
    fflush(log);

    if (ps5gpu_init() != 0) {
        fprintf(log, "ps5gpu_init failed: %s\n", ps5gpu_last_error());
        fclose(log);
        notify("PS5GL rendertarget test: ps5gpu_init failed, see log");
        return 1;
    }
    fprintf(log, "ps5gpu_init OK\n");

    for (frame = 0; frame < 16 * 4; frame += 4) {
        magenta_rgba[frame + 0] = 255; magenta_rgba[frame + 1] = 0;
        magenta_rgba[frame + 2] = 255; magenta_rgba[frame + 3] = 255;
    }
    magenta_tex = ps5gpu_texture_new();
    ps5gpu_texture_upload(magenta_tex, magenta_rgba, 4, 4);
    memset(white_rgba, 0xFF, sizeof(white_rgba));
    white_tex = ps5gpu_texture_new();
    ps5gpu_texture_upload(white_tex, white_rgba, 4, 4);

    rt_index = ps5gpu_target_create(256, 256);
    rt_tex = rt_index >= 0 ? ps5gpu_target_texture(rt_index) : -1;
    fprintf(log, "ps5gpu_target_create(256,256) = %d, texture id = %d\n", rt_index, rt_tex);
    fflush(log);

    static const float identity[16] = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 };
    ps5gpu_set_mvp(identity);
    ps5gpu_set_program(0);

    for (frame = 0; frame < TOTAL_FRAMES; frame++) {
        ps5gpu_begin_frame();

        if (rt_index >= 0) {
            /* Render a solid green quad into the user target, filling it.
             * The viewport/scissor must match the target's own size - they
             * are NOT reset by ps5gpu_set_target(), same as for the
             * reflection target (whose caller sets them explicitly too;
             * it just happens to equal the screen's own size so is easy to
             * miss). Restored to the screen's own size afterward. */
            ps5gpu_set_target(PS5GPU_TARGET_USER0 + rt_index);
            ps5gpu_set_viewport(0, 0, 256, 256);
            ps5gpu_set_scissor(0, 0, 256, 256);
            /* White, not magenta: the built-in program is texel*colour, and
             * multiplying by magenta's zero G channel would zero out the
             * green vertex colour below regardless of what it says - this
             * bug, not the render target code, is what produced black on
             * the first few tries at this test. */
            ps5gpu_texture_select(white_tex);
            draw_quad(-1.0f, -1.0f, 1.0f, 1.0f, 0xFF00FF00u);   /* A=FF R=00 G=FF B=00 -> green, full alpha */
            /* Back to the normal scene for everything else this frame. */
            ps5gpu_set_target(PS5GPU_TARGET_SCENE);
            ps5gpu_set_viewport(0, 0, 1920, 1080);
            ps5gpu_set_scissor(0, 0, 1920, 1080);
        }

        /* Left: control, magenta. */
        ps5gpu_texture_select(magenta_tex);
        draw_quad(-1.0f, -1.0f, 0.0f, 1.0f, 0xFFFFFFFFu);

        /* Right: the user target's own texture, sampled back. */
        if (rt_tex >= 0) {
            ps5gpu_texture_select((uint32_t)rt_tex);
            draw_quad(0.0f, -1.0f, 1.0f, 1.0f, 0xFFFFFFFFu);
        }

        ps5gpu_end_frame();

        if (frame == 250 && rt_index >= 0) {
            unsigned char px[4];
            ps5gpu_debug_read_target_pixel(rt_index, 128, 128, px);
            /* Raw memory byte order, not necessarily R,G,B,A - expect
             * something matching the green vertex colour written
             * (0xFF00FF00 = A=FF R=00 G=FF B=00) in SOME byte order if the
             * write side worked; all zero if nothing was ever written. */
            fprintf(log, "frame 250: raw CPU-side pixel (128,128) of the target = bytes %u %u %u %u\n",
                    px[0], px[1], px[2], px[3]);
            fflush(log);
        }
    }

    fprintf(log, "\ndone: %d frames. expected: left magenta, right green.\n", TOTAL_FRAMES);
    fclose(log);
    notify(rt_index >= 0
        ? "PS5GL rendertarget test: left magenta, right should be green - see screen + log"
        : "PS5GL rendertarget test: ps5gpu_target_create FAILED, see log");
    return 0;
}
