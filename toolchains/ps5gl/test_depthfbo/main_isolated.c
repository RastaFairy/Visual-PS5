/* Pure isolation build: no depth texture, no FBO at all - just magenta and
 * white on the plain scene, identical structure otherwise to
 * test_depthfbo/main.c. If this ALSO shows nothing, the bug in that build is
 * not about the depth-only FBO at all - something else in this specific
 * source tree/build is broken. If this WORKS, the FBO setup itself (even
 * before any draw into it) is what corrupts rendering. */
#include <stdio.h>
#include <string.h>
#include <stddef.h>

#include "ps5gl.h"

extern int sceKernelSendNotificationRequest(int device, void *request, int size, int flags);
extern int mkdir(const char *path, unsigned int mode);

#define TOTAL_FRAMES 300
#define LOG_PATH "/app0/data/ps5gl_isolated.txt"

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
    GLuint magenta_tex, white_tex;
    GLuint vao, vbo, ebo;
    static uint8_t magenta_rgba[4 * 4 * 4], white_rgba[4 * 4 * 4];
    int frame;

    mkdir("/app0/data", 0777);
    log = fopen(LOG_PATH, "wb");
    if (!log) return 1;
    fprintf(log, "PS5GL: pure isolation test, no FBO at all.\n\n");
    fflush(log);

    if (ps5gl_init() != 0) {
        fprintf(log, "ps5gl_init failed: %s\n", ps5gl_last_error());
        fclose(log);
        notify("PS5GL isolated test: init failed");
        return 1;
    }
    fprintf(log, "ps5gl_init OK\n");
    fflush(log);

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

        Vertex left[4] = {
            { {-1,-1,0}, {0.5f,0.5f}, {1,1,1,1} }, { {0,-1,0}, {0.5f,0.5f}, {1,1,1,1} },
            { {0, 1,0}, {0.5f,0.5f}, {1,1,1,1} }, { {-1, 1,0}, {0.5f,0.5f}, {1,1,1,1} },
        };
        glBindTexture(GL_TEXTURE_2D, magenta_tex);
        draw_quad_verts(vbo, ebo, left);

        Vertex right[4] = {
            { {0,-1,0}, {0.5f,0.5f}, {1,1,1,1} }, { {1,-1,0}, {0.5f,0.5f}, {1,1,1,1} },
            { {1, 1,0}, {0.5f,0.5f}, {1,1,1,1} }, { {0, 1,0}, {0.5f,0.5f}, {1,1,1,1} },
        };
        glBindTexture(GL_TEXTURE_2D, white_tex);
        draw_quad_verts(vbo, ebo, right);

        ps5gl_end_frame();
    }

    fprintf(log, "done: %d frames. expected: left magenta, right white.\n", TOTAL_FRAMES);
    fclose(log);
    notify("PS5GL isolated test done - left magenta, right white expected");
    return 0;
}
