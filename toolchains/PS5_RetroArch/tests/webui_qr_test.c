/* Host network/clock seam and RGUI framebuffer for the real shared QR code. */
#include "ps5_webui_qr.h"
#include <arpa/inet.h>
#include <assert.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>

static struct ifaddrs interfaces[2];
static struct sockaddr_in addresses[2];
static time_t now = 100;
static int failed;
int frees;
void qr_test_network(const char *ip, unsigned flags, int fail, long seconds)
{
    memset(interfaces, 0, sizeof(interfaces));
    memset(addresses, 0, sizeof(addresses));
    now = seconds;
    failed = fail;
    addresses[0].sin_family = addresses[1].sin_family = AF_INET;
    inet_pton(AF_INET, "127.0.0.1", &addresses[0].sin_addr);
    inet_pton(AF_INET, ip, &addresses[1].sin_addr);
    interfaces[0].ifa_addr = (struct sockaddr *)&addresses[0];
    interfaces[0].ifa_flags = IFF_UP | IFF_LOOPBACK;
    interfaces[0].ifa_next = &interfaces[1];
    interfaces[1].ifa_addr = (struct sockaddr *)&addresses[1];
    interfaces[1].ifa_flags = flags;
}
int __wrap_getifaddrs(struct ifaddrs **out)
{
    *out = failed ? NULL : interfaces;
    return failed ? -1 : 0;
}
void __wrap_freeifaddrs(struct ifaddrs *list)
{
    assert(list == interfaces);
    frees++;
}
time_t __wrap_time(time_t *out)
{
    if (out)
        *out = now;
    return now;
}

typedef struct
{
    struct
    {
        uint16_t *data;
    } frame_buf;
    unsigned font_height_stride, font_width_stride, flags;
} rgui_t;
#define RGUI_FLAG_FORCE_REDRAW 1
static void rgui_color_rect(uint16_t *out, unsigned w, unsigned h, unsigned x, unsigned y,
                            unsigned width, unsigned height, uint16_t color)
{
    assert(x + width <= w && y + height <= h);
    for (unsigned row = y; row < y + height; row++)
        for (unsigned col = x; col < x + width; col++)
            out[row * w + col] = color;
}
static void rgui_blit_line(rgui_t *rgui, unsigned w, unsigned x, unsigned y, const char *text,
                           uint16_t color, uint16_t shadow)
{
    (void)y;
    (void)color;
    (void)shadow;
    assert(x + strlen(text) * rgui->font_width_stride <= w);
}
#include "ps5_webui_qr_rgui.h"
void qr_test_rgui(uint16_t *pixels, unsigned width, unsigned height)
{
    rgui_t rgui = {{pixels}, 10, 6, 0};
    ps5_webui_qr_draw_rgui(&rgui, width, height);
    assert(rgui.flags & RGUI_FLAG_FORCE_REDRAW);
}

typedef struct
{
    int unused;
} gfx_display_t;
typedef struct
{
    int unused;
} settings_t;
typedef struct
{
    void *font;
} xmb_handle_t;
typedef struct
{
    unsigned width, height;
    void *userdata;
} video_frame_info_t;
#define TEXT_ALIGN_CENTER 1
static gfx_display_t *disp_get_ptr(void)
{
    return NULL;
}
static settings_t *config_get_ptr(void)
{
    return NULL;
}
static void gfx_display_draw_quad(gfx_display_t *disp, void *out, unsigned w, unsigned h,
                                  unsigned x, unsigned y, unsigned width, unsigned height,
                                  unsigned vw, unsigned vh, const float *color, void *matrix)
{
    (void)disp;
    (void)vw;
    (void)vh;
    (void)matrix;
    rgui_color_rect(out, w, h, x, y, width, height, color[0] == 1 ? 0xffff : 0x000f);
}
static void xmb_draw_text(bool shadow, xmb_handle_t *xmb, settings_t *settings, const char *text,
                          float x, float y, float a, float b, int align, unsigned w, unsigned h,
                          void *font)
{
    (void)shadow;
    (void)xmb;
    (void)settings;
    (void)text;
    (void)x;
    (void)y;
    (void)a;
    (void)b;
    (void)align;
    (void)w;
    (void)h;
    (void)font;
}
#include "ps5_webui_qr_xmb.h"
void qr_test_xmb(uint16_t *pixels, unsigned width, unsigned height)
{
    xmb_handle_t xmb = {0};
    video_frame_info_t video = {width, height, pixels};
    ps5_webui_qr_draw_xmb(&xmb, &video);
}
