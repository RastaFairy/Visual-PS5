/* PS5GL: does the real glGenFramebuffers/glFramebufferTexture2D/
 * glBindFramebuffer wiring (see ps5gl.h's framebuffer comment) work end to
 * end through the actual gl* API, the way a real caller would use it -
 * rather than calling ps5gpu_target_create() directly, as the earlier
 * hardware-confirmed test did?
 *
 * left  - control, magenta via the normal texture path.
 * right - a quad sampling a texture that was:
 *   1. glGenTextures + glTexImage2D(..., NULL) to size it (256x256, no data)
 *   2. attached to a framebuffer's GL_COLOR_ATTACHMENT0
 *   3. glBindFramebuffer'd to, viewport/scissor set to 256x256, a solid
 *      green quad drawn into it via glDrawElements
 *   4. glBindFramebuffer(0) back to the main scene
 *   5. glBindTexture'd and sampled normally on this quad
 * Expect: left magenta, right green, if the whole real-API path works the
 * same way the raw ps5gpu_target_create() call already proved on hardware.
 */
#include <stdio.h>
#include <string.h>
#include <stddef.h>

#include "ps5gl.h"

extern int sceKernelSendNotificationRequest(int device, void *request, int size, int flags);
extern int mkdir(const char *path, unsigned int mode);

#define TOTAL_FRAMES 300
#define LOG_PATH "/app0/data/ps5gl_fbo.txt"

static void notify(const char *msg) {
    static char request[3120];
    int i;
    for (i = 0; i < 3120; i++) request[i] = 0;
    for (i = 0; msg[i] != 0 && i < 3074; i++) request[45 + i] = msg[i];
    sceKernelSendNotificationRequest(0, request, sizeof(request), 0);
}

typedef struct { float pos[3]; float uv[2]; float color[4]; } Vertex;

int main(void) {
    FILE *log;
    GLuint magenta_tex, rt_tex, fbo;
    GLuint vao, vbo, ebo;
    static uint8_t magenta_rgba[4 * 4 * 4];
    int frame;

    mkdir("/app0/data", 0777);
    log = fopen(LOG_PATH, "wb");
    if (!log) return 1;
    fprintf(log, "PS5GL: real glGenFramebuffers/glFramebufferTexture2D/glBindFramebuffer test.\n\n");
    fflush(log);

    if (ps5gl_init() != 0) {
        fprintf(log, "ps5gl_init failed: %s\n", ps5gl_last_error());
        fclose(log);
        notify("PS5GL FBO test: init failed, see log");
        return 1;
    }
    fprintf(log, "ps5gl_init OK\n");

    for (int i = 0; i < 16 * 4; i += 4) {
        magenta_rgba[i+0] = 255; magenta_rgba[i+1] = 0; magenta_rgba[i+2] = 255; magenta_rgba[i+3] = 255;
    }
    glGenTextures(1, &magenta_tex);
    glBindTexture(GL_TEXTURE_2D, magenta_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 4, 4, 0, GL_RGBA, GL_UNSIGNED_BYTE, magenta_rgba);

    /* The render-target texture: sized, not uploaded. */
    glGenTextures(1, &rt_tex);
    glBindTexture(GL_TEXTURE_2D, rt_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 256, 256, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    fprintf(log, "rt_tex=%u glGetError after sizing NULL-data texture = %u\n", rt_tex, glGetError());

    /* glBindFramebuffer only records which FBO is bound now (see its own
     * comment in ps5gl.c) - the real ps5gpu_set_target() call it used to
     * make immediately is deferred to the next draw, precisely so this
     * ordinary GL sequence (bind, attach, check, unbind, all before any
     * frame has begun) is safe. The first version of this test called
     * ps5gpu_set_target() eagerly here and crashed hard on hardware
     * (SIGSEGV jumping to address 0 - the per-frame command buffer
     * ps5gpu_begin_frame() sets up did not exist yet). */
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, rt_tex, 0);
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    fprintf(log, "glCheckFramebufferStatus = 0x%X (COMPLETE=0x%X, UNSUPPORTED=0x%X)\n",
            status, GL_FRAMEBUFFER_COMPLETE, GL_FRAMEBUFFER_UNSUPPORTED);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    fflush(log);

    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    glGenBuffers(1, &vbo);
    glGenBuffers(1, &ebo);

    static const unsigned short quad_indices[6] = { 0, 1, 2, 2, 3, 0 };
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(quad_indices), quad_indices, GL_STATIC_DRAW);

    static const float identity[16] = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 };
    GLint mvp_loc = glGetUniformLocation(0, "mvp");
    glUniformMatrix4fv(mvp_loc, 1, GL_FALSE, identity);
    glUseProgram(0);

    for (frame = 0; frame < TOTAL_FRAMES; frame++) {
        ps5gl_begin_frame();

        if (status == GL_FRAMEBUFFER_COMPLETE) {
            /* Render solid green into the FBO's texture. */
            glBindFramebuffer(GL_FRAMEBUFFER, fbo);
            glViewport(0, 0, 256, 256);
            glScissor(0, 0, 256, 256);
            Vertex fill[4] = {
                { { -1,-1,0 }, {0.5f,0.5f}, {0,1,0,1} }, { { 1,-1,0 }, {0.5f,0.5f}, {0,1,0,1} },
                { { 1, 1,0 }, {0.5f,0.5f}, {0,1,0,1} }, { { -1, 1,0 }, {0.5f,0.5f}, {0,1,0,1} },
            };
            glBindBuffer(GL_ARRAY_BUFFER, vbo);
            glBufferData(GL_ARRAY_BUFFER, sizeof(fill), fill, GL_DYNAMIC_DRAW);
            glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, pos));
            glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, uv));
            glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, color));
            glEnableVertexAttribArray(0); glEnableVertexAttribArray(1); glEnableVertexAttribArray(2);
            glBindTexture(GL_TEXTURE_2D, magenta_tex);   /* wrong choice zeroes channels via texel*colour - use white instead below */
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
            /* White, not magenta: texel*colour would zero the green channel
             * otherwise - the exact bug the raw ps5gpu_target_create() test
             * hit on its first try. Reuse magenta_tex's RGBA slot as white
             * by uploading over it once, before the loop, would be cleaner,
             * but simplest here is a dedicated white texture. */
            static GLuint white_tex; static int white_made;
            if (!white_made) {
                static uint8_t white_rgba[4*4*4];
                memset(white_rgba, 0xFF, sizeof(white_rgba));
                glGenTextures(1, &white_tex);
                glBindTexture(GL_TEXTURE_2D, white_tex);
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 4, 4, 0, GL_RGBA, GL_UNSIGNED_BYTE, white_rgba);
                white_made = 1;
            }
            glBindTexture(GL_TEXTURE_2D, white_tex);
            glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, (void *)0);

            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glViewport(0, 0, 1920, 1080);
            glScissor(0, 0, 1920, 1080);
        }

        /* Left: control, magenta. */
        Vertex left[4] = {
            { { -1,-1,0 }, {0.5f,0.5f}, {1,1,1,1} }, { { 0,-1,0 }, {0.5f,0.5f}, {1,1,1,1} },
            { { 0, 1,0 }, {0.5f,0.5f}, {1,1,1,1} }, { { -1, 1,0 }, {0.5f,0.5f}, {1,1,1,1} },
        };
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, sizeof(left), left, GL_DYNAMIC_DRAW);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, pos));
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, uv));
        glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, color));
        glBindTexture(GL_TEXTURE_2D, magenta_tex);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
        glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, (void *)0);

        /* Right: the FBO's own texture, sampled back normally. */
        if (status == GL_FRAMEBUFFER_COMPLETE) {
            Vertex right[4] = {
                { { 0,-1,0 }, {0.5f,0.5f}, {1,1,1,1} }, { { 1,-1,0 }, {0.5f,0.5f}, {1,1,1,1} },
                { { 1, 1,0 }, {0.5f,0.5f}, {1,1,1,1} }, { { 0, 1,0 }, {0.5f,0.5f}, {1,1,1,1} },
            };
            glBufferData(GL_ARRAY_BUFFER, sizeof(right), right, GL_DYNAMIC_DRAW);
            glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, pos));
            glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, uv));
            glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, color));
            glBindTexture(GL_TEXTURE_2D, rt_tex);
            glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, (void *)0);
        }

        ps5gl_end_frame();
    }

    fprintf(log, "\ndone: %d frames. expected: left magenta, right green.\n", TOTAL_FRAMES);
    fclose(log);
    notify(status == GL_FRAMEBUFFER_COMPLETE
        ? "PS5GL FBO test: left magenta, right should be green - see screen + log"
        : "PS5GL FBO test: framebuffer incomplete, see log");
    return 0;
}
