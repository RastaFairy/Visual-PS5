/* Included by the patched XMB driver, after its drawing helpers. */
#include "ps5_webui_qr.h"
static void ps5_webui_qr_draw_xmb(xmb_handle_t *xmb, video_frame_info_t *video_info)
{
    const struct ps5_webui_qr *qr = ps5_webui_qr_current();
    gfx_display_t *disp = disp_get_ptr();
    settings_t *settings = config_get_ptr();
    unsigned w = video_info->width, h = video_info->height;
    unsigned scale = qr->size ? (unsigned)(h * 0.48f) / qr->size : 1;
    unsigned side = qr->size * scale, left = (w - side) / 2, top = (unsigned)(h * 0.23f);
    float dark[16] = {0, 0, 0, 0.95f, 0, 0, 0, 0.95f, 0, 0, 0, 0.95f, 0, 0, 0, 0.95f};
    float white[16] = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1};
    float black[16] = {0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1};
    gfx_display_draw_quad(disp, video_info->userdata, w, h, 0, 0, w, h, w, h, dark, NULL);
    xmb_draw_text(false, xmb, settings, "WebUI", w / 2, h * 0.13f, 1, 1, TEXT_ALIGN_CENTER, w, h,
                  xmb->font);
    if (qr->size)
    {
        gfx_display_draw_quad(disp, video_info->userdata, w, h, left, top, side, side, w, h, white,
                              NULL);
        for (unsigned y = 0; y < qr->size; y++)
            for (unsigned x = 0; x < qr->size;)
            {
                if (!qr->modules[y * qr->size + x])
                {
                    x++;
                    continue;
                }
                unsigned start = x++;
                while (x < qr->size && qr->modules[y * qr->size + x])
                    x++;
                gfx_display_draw_quad(disp, video_info->userdata, w, h, left + start * scale,
                                      top + y * scale, (x - start) * scale, scale, w, h, black,
                                      NULL);
            }
    }
    xmb_draw_text(false, xmb, settings, qr->size ? qr->url : PS5_WEBUI_QR_OFFLINE, w / 2, h * 0.79f,
                  1, 1, TEXT_ALIGN_CENTER, w, h, xmb->font);
    xmb_draw_text(false, xmb, settings, "Scan with a phone on the same network", w / 2, h * 0.87f,
                  1, 1, TEXT_ALIGN_CENTER, w, h, xmb->font);
    xmb_draw_text(false, xmb, settings, "Circle: Close", w / 2, h * 0.94f, 1, 1, TEXT_ALIGN_CENTER,
                  w, h, xmb->font);
}
