/* PS5GL: the standard depth-only FBO idiom (shadow mapping's usual shape) -
 * a framebuffer with ONLY a GL_DEPTH_ATTACHMENT, no colour attachment at
 * all, glDrawBuffer(GL_NONE)/glReadBuffer(GL_NONE). See
 * glFramebufferTexture2D's own comment in ps5gl.h for what "depth" means
 * here: there is no real Z-buffer-as-texture path, so this is backed by an
 * ordinary render target and the shader that draws into it must write depth
 * as a colour value itself - exactly like ps5gpu.c's own built-in shadow
 * target already does.
 *
 * left  - control, magenta.
 * right - a quad sampling the "depth" texture, into which a shader wrote a
 *         solid colour (standing in for "depth", since there is no real
 *         depth shader here - the built-in program always does
 *         texel*vertex-colour) via the depth-only FBO. Expect green, the
 *         same result already proven for a colour-attached FBO - this test
 *         is about whether the ATTACHMENT KIND (depth, not colour) still
 *         gets a real ps5gpu_target_create() behind it.
 */
#include <stdio.h>
#include <string.h>
#include <stddef.h>

#include "ps5gl.h"
#include "ps5gpu.h"

extern int sceKernelSendNotificationRequest(int device, void *request, int size, int flags);
extern int mkdir(const char *path, unsigned int mode);

#define TOTAL_FRAMES 300
#define LOG_PATH "/app0/data/ps5gl_depthfbo.txt"

static void notify(const char *msg) {
    static char request[3120];
    int i;
    for (i = 0; i < 3120; i++) request[i] = 0;
    for (i = 0; msg[i] != 0 && i < 3074; i++) request[45 + i] = msg[i];
    sceKernelSendNotificationRequest(0, request, sizeof(request), 0);
}

typedef struct { float pos[3]; float uv[2]; float color[4]; } Vertex;

static void draw_quad_verts(GLuint vbo, GLuint ebo, Vertex quad[4]) {
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, 4 * sizeof(Vertex), quad, GL_DYNAMIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, pos));
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, uv));
    glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, color));
    /* Found the hard way (a whole debugging saga's worth): forgetting these
     * leaves every attribute disabled, so gather_vertex() in ps5gl.c falls
     * back to the constant default for position - (0,0,0) for every vertex,
     * a zero-area triangle that draws nothing. test_fbo/main.c's working
     * quads only happened to work because it called this once, on its very
     * first draw, and the enabled flags persist on the VAO afterward. */
    glEnableVertexAttribArray(0); glEnableVertexAttribArray(1); glEnableVertexAttribArray(2);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, (void *)0);
}

int main(void) {
    FILE *log;
    GLuint magenta_tex, white_tex, depth_tex, fbo;
    GLuint vao, vbo, ebo;
    static uint8_t magenta_rgba[4 * 4 * 4], white_rgba[4 * 4 * 4];
    int frame;

    mkdir("/app0/data", 0777);
    log = fopen(LOG_PATH, "wb");
    if (!log) return 1;
    fprintf(log, "PS5GL: depth-only FBO (shadow-map pattern) test.\n\n");
    fflush(log);

    if (ps5gl_init() != 0) {
        fprintf(log, "ps5gl_init failed: %s\n", ps5gl_last_error());
        fclose(log);
        notify("PS5GL depth-FBO test: init failed, see log");
        return 1;
    }
    fprintf(log, "ps5gl_init OK\n");

    for (int i = 0; i < 16 * 4; i += 4) {
        magenta_rgba[i+0]=255; magenta_rgba[i+1]=0; magenta_rgba[i+2]=255; magenta_rgba[i+3]=255;
    }
    memset(white_rgba, 0xFF, sizeof(white_rgba));
    glGenTextures(1, &magenta_tex);
    glBindTexture(GL_TEXTURE_2D, magenta_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 4, 4, 0, GL_RGBA, GL_UNSIGNED_BYTE, magenta_rgba);
    glGenTextures(1, &white_tex);
    glBindTexture(GL_TEXTURE_2D, white_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 4, 4, 0, GL_RGBA, GL_UNSIGNED_BYTE, white_rgba);

    /* The "depth" texture - real GL apps use GL_DEPTH_COMPONENT, but this
     * backend only ever stores RGBA8 regardless (see glTexImage2D's own
     * comment) - the format argument doesn't change what actually gets
     * allocated. */
    glGenTextures(1, &depth_tex);
    glBindTexture(GL_TEXTURE_2D, depth_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, 256, 256, 0, GL_DEPTH_COMPONENT, GL_UNSIGNED_BYTE, NULL);
    fprintf(log, "depth_tex=%u glGetError after sizing = %u\n", depth_tex, glGetError());

    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, depth_tex, 0);
    glDrawBuffer(GL_NONE);
    glReadBuffer(GL_NONE);
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    fprintf(log, "glCheckFramebufferStatus (depth-only) = 0x%X (COMPLETE=0x%X)\n", status, GL_FRAMEBUFFER_COMPLETE);
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
    glUniformMatrix4fv(glGetUniformLocation(0, "mvp"), 1, GL_FALSE, identity);
    glUseProgram(0);

    for (frame = 0; frame < TOTAL_FRAMES; frame++) {
        ps5gl_begin_frame();

        /* Reordered from the previous build: magenta and white now draw
         * FIRST, before the depth-target fill touches anything - isolating
         * whether the fill command corrupts/stalls the GPU's execution of
         * everything queued after it in the same frame's command buffer
         * (the leading hypothesis after literally nothing, not even the
         * always-reliable magenta control, showed up last time). If these
         * two now appear, that hypothesis is confirmed; if they still don't,
         * something else - broken regardless of draw order - is at fault. */
        Vertex left[4] = {
            { {-1,-1,0}, {0.5f,0.5f}, {1,1,1,1} }, { {-0.34f,-1,0}, {0.5f,0.5f}, {1,1,1,1} },
            { {-0.34f, 1,0}, {0.5f,0.5f}, {1,1,1,1} }, { {-1, 1,0}, {0.5f,0.5f}, {1,1,1,1} },
        };
        glBindTexture(GL_TEXTURE_2D, magenta_tex);
        draw_quad_verts(vbo, ebo, left);

        Vertex middle[4] = {
            { {-0.33f,-1,0}, {0.5f,0.5f}, {1,1,1,1} }, { {0.33f,-1,0}, {0.5f,0.5f}, {1,1,1,1} },
            { {0.33f, 1,0}, {0.5f,0.5f}, {1,1,1,1} }, { {-0.33f, 1,0}, {0.5f,0.5f}, {1,1,1,1} },
        };
        glBindTexture(GL_TEXTURE_2D, white_tex);
        draw_quad_verts(vbo, ebo, middle);

        if (status == GL_FRAMEBUFFER_COMPLETE) {
            glBindFramebuffer(GL_FRAMEBUFFER, fbo);
            glViewport(0, 0, 256, 256);
            glScissor(0, 0, 256, 256);
            Vertex fill[4] = {
                { {-1,-1,0}, {0.5f,0.5f}, {0,1,0,1} }, { {1,-1,0}, {0.5f,0.5f}, {0,1,0,1} },
                { {1, 1,0}, {0.5f,0.5f}, {0,1,0,1} }, { {-1, 1,0}, {0.5f,0.5f}, {0,1,0,1} },
            };
            glBindTexture(GL_TEXTURE_2D, white_tex);
            draw_quad_verts(vbo, ebo, fill);

            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glViewport(0, 0, 1920, 1080);
            glScissor(0, 0, 1920, 1080);
        }

        if (status == GL_FRAMEBUFFER_COMPLETE) {
            Vertex right[4] = {
                { {0.34f,-1,0}, {0.5f,0.5f}, {1,1,1,1} }, { {1,-1,0}, {0.5f,0.5f}, {1,1,1,1} },
                { {1, 1,0}, {0.5f,0.5f}, {1,1,1,1} }, { {0.34f, 1,0}, {0.5f,0.5f}, {1,1,1,1} },
            };
            glBindTexture(GL_TEXTURE_2D, depth_tex);
            draw_quad_verts(vbo, ebo, right);
        }

        ps5gl_end_frame();

        if (frame == 250 && status == GL_FRAMEBUFFER_COMPLETE) {
            int rt_index = ps5gl_debug_texture_rt_index(depth_tex);
            unsigned char px[4] = { 9, 9, 9, 9 };
            int ok = ps5gpu_debug_read_target_pixel(rt_index, 128, 128, px);
            fprintf(log, "frame 250: depth_tex rt_index=%d, raw pixel(128,128) read ok=%d, bytes %u %u %u %u\n",
                    rt_index, ok, px[0], px[1], px[2], px[3]);
            fflush(log);
        }
    }

    fprintf(log, "\ndone: %d frames. expected: left magenta, middle white, right green (or at least not black, per the isolation this build adds).\n", TOTAL_FRAMES);
    fclose(log);
    notify(status == GL_FRAMEBUFFER_COMPLETE
        ? "PS5GL depth-FBO test: left magenta, right should be green"
        : "PS5GL depth-FBO test: framebuffer incomplete, see log");
    return 0;
}
