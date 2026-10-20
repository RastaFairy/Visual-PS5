/* Link-feasibility test, not a hardware test: does most of libmod_3d's own
 * implementation code (everything except libmod_3d.c itself, the BennuGD2
 * module-registration file that needs bgddl.h - a whole separate interpreter
 * integration, not attempted here) actually LINK against PS5GL, using
 * ps5link's own real linker (link_real)? Compiling clean (already confirmed,
 * 78/80 files) only proves declarations match; link_real is what proves the
 * actual symbols resolve - real ps5gpu_/ps5gl_ functions, real libc
 * NID-catalog entries, and libmod_3d's own cross-file calls all at once.
 *
 * Calls a small, representative handful of real functions so the linker
 * has a reason to pull in and resolve as much of libmod_3d as possible,
 * rather than link succeeding trivially by never referencing any of it.
 * None of these calls need to behave correctly - NULL/zero arguments are
 * fine, since this only tests whether the symbols resolve, not runtime
 * correctness. */
#include <stdio.h>
#include "ps5gl.h"
#include "libmod_3d_math.h"
#include "libmod_3d_mesh.h"
#include "libmod_3d_texture.h"
#include "libmod_3d_scene.h"
#include "libmod_3d_renderer.h"

int main(void) {
    if (ps5gl_init() != 0) {
        printf("ps5gl_init failed: %s\n", ps5gl_last_error());
        return 1;
    }

    Vec3 a = vec3_make(1, 2, 3);
    Mat4 m = mat4_identity();
    (void)a; (void)m;

    G3DMesh *mesh = g3d_mesh_create("test", NULL, 0, NULL, 0);
    (void)mesh;

    G3DTexture *tex = g3d_texture_load_mem("test", NULL, 0);
    (void)tex;

    g3d_scene_impl_create("test_scene");
    g3d_renderer_init(1920, 1080);

    return 0;
}
