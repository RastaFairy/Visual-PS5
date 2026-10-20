/* PS5GL milestone 2 test: draw real geometry entirely through the GL-shaped
 * API (buffers, VAO, glDrawElements, glUniformMatrix4fv, glBlendFunc) instead
 * of calling ps5gpu_* directly, to prove the wrapper's plumbing - attribute
 * gathering, index buffers, the mvp uniform's transpose handling, and the
 * blend-mode mapping milestone 1 found - actually works end to end.
 *
 * Draws two overlapping triangles forming a quad on the left (magenta,
 * single pass - same control as before) and on the right, the same quad
 * drawn twice: once magenta, once cyan with glBlendFunc(GL_DST_COLOR,
 * GL_ZERO) - PS5GL's spelling of the multiply pass. Expect left magenta,
 * right blue, the same result already confirmed via raw ps5gpu_* calls, now
 * through the actual library a real caller would use.
 */
#include <stdio.h>
#include <string.h>
#include <stddef.h>

#include "ps5gl.h"

extern int sceKernelSendNotificationRequest(int device, void *request, int size, int flags);
extern int mkdir(const char *path, unsigned int mode);

#define TOTAL_FRAMES 300
#define LOG_PATH "/app0/data/ps5gl_test.txt"

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
    GLuint textures[2];
    GLuint vao, vbo_left, vbo_right, ebo;
    static uint8_t magenta_rgba[4 * 4 * 4], cyan_rgba[4 * 4 * 4];
    int frame;

    mkdir("/app0/data", 0777);
    log = fopen(LOG_PATH, "wb");
    if (!log) return 1;
    fprintf(log, "PS5GL milestone 2: drawing through the real glGen/glBind/glDraw* API.\n\n");
    fflush(log);

    if (ps5gl_init() != 0) {
        fprintf(log, "ps5gl_init failed: %s\n", ps5gl_last_error());
        fclose(log);
        notify("PS5GL test: init failed, see log");
        return 1;
    }
    fprintf(log, "ps5gl_init OK - %s / %s / %s\n",
            glGetString(GL_VENDOR), glGetString(GL_RENDERER), glGetString(GL_VERSION));

    for (int i = 0; i < 16 * 4; i += 4) {
        magenta_rgba[i+0]=255; magenta_rgba[i+1]=0;   magenta_rgba[i+2]=255; magenta_rgba[i+3]=255;
        cyan_rgba[i+0]=0;      cyan_rgba[i+1]=255;     cyan_rgba[i+2]=255;    cyan_rgba[i+3]=255;
    }
    glGenTextures(2, textures);
    glBindTexture(GL_TEXTURE_2D, textures[0]);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 4, 4, 0, GL_RGBA, GL_UNSIGNED_BYTE, magenta_rgba);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glBindTexture(GL_TEXTURE_2D, textures[1]);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 4, 4, 0, GL_RGBA, GL_UNSIGNED_BYTE, cyan_rgba);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    fprintf(log, "textures: magenta=%u cyan=%u (err=%u)\n", textures[0], textures[1], glGetError());

    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    glGenBuffers(1, &vbo_left);
    glGenBuffers(1, &vbo_right);
    glGenBuffers(1, &ebo);

    /* One quad shape, reused for both sides at different positions. */
    Vertex left[4] = {
        { { -1.0f, -1.0f, 0.0f }, { 0.5f, 0.5f }, { 1,1,1,1 } },
        { {  0.0f, -1.0f, 0.0f }, { 0.5f, 0.5f }, { 1,1,1,1 } },
        { {  0.0f,  1.0f, 0.0f }, { 0.5f, 0.5f }, { 1,1,1,1 } },
        { { -1.0f,  1.0f, 0.0f }, { 0.5f, 0.5f }, { 1,1,1,1 } },
    };
    Vertex right[4] = {
        { {  0.0f, -1.0f, 0.0f }, { 0.5f, 0.5f }, { 1,1,1,1 } },
        { {  1.0f, -1.0f, 0.0f }, { 0.5f, 0.5f }, { 1,1,1,1 } },
        { {  1.0f,  1.0f, 0.0f }, { 0.5f, 0.5f }, { 1,1,1,1 } },
        { {  0.0f,  1.0f, 0.0f }, { 0.5f, 0.5f }, { 1,1,1,1 } },
    };
    static const unsigned short quad_indices[6] = { 0, 1, 2, 2, 3, 0 };

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(quad_indices), quad_indices, GL_STATIC_DRAW);

    static const float identity[16] = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 };
    GLint mvp_loc = glGetUniformLocation(0, "mvp");
    glUniformMatrix4fv(mvp_loc, 1, GL_FALSE, identity);
    fprintf(log, "mvp uniform location = %d (err=%u)\n\n", mvp_loc, glGetError());
    fflush(log);

    for (frame = 0; frame < TOTAL_FRAMES; frame++) {
        ps5gl_begin_frame();

        /* Left quad: single pass, magenta, no blend. */
        glDisable(GL_BLEND);
        glBindBuffer(GL_ARRAY_BUFFER, vbo_left);
        glBufferData(GL_ARRAY_BUFFER, sizeof(left), left, GL_DYNAMIC_DRAW);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, pos));
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, uv));
        glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, color));
        glEnableVertexAttribArray(0); glEnableVertexAttribArray(1); glEnableVertexAttribArray(2);
        glBindTexture(GL_TEXTURE_2D, textures[0]);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
        glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, (void *)0);

        /* Right quad, pass 1: magenta, normal. */
        glBindBuffer(GL_ARRAY_BUFFER, vbo_right);
        glBufferData(GL_ARRAY_BUFFER, sizeof(right), right, GL_DYNAMIC_DRAW);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, pos));
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, uv));
        glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void *)offsetof(Vertex, color));
        glBindTexture(GL_TEXTURE_2D, textures[0]);
        glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, (void *)0);

        /* Right quad, pass 2: cyan, multiply blend - PS5GL's spelling of
         * milestone 1's proven multi-pass approach. */
        glEnable(GL_BLEND);
        glBlendFunc(GL_DST_COLOR, GL_ZERO);
        glBindTexture(GL_TEXTURE_2D, textures[1]);
        glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, (void *)0);
        glDisable(GL_BLEND);

        ps5gl_end_frame();
    }

    fprintf(log, "done: %d frames. expected: left magenta, right blue.\n", TOTAL_FRAMES);
    fclose(log);
    notify("PS5GL test: drawn via real gl* API - left magenta, right should be blue");
    return 0;
}
