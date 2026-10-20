/* Included by the patched RGUI driver, after its framebuffer and font helpers. */
#include "ps5_webui_qr.h"
static void ps5_webui_qr_draw_rgui(rgui_t *rgui, unsigned w, unsigned h)
{
    const struct ps5_webui_qr *qr = ps5_webui_qr_current();
    unsigned line = rgui->font_height_stride;
    unsigned scale = qr->size && h > 7 * line ? (h - 7 * line) / qr->size : 1;
    unsigned side = qr->size * scale, left = (w - side) / 2, top = 2 * line;
    const char *url = qr->size ? qr->url : "No network address";
    if (!rgui->frame_buf.data)
        return;
    rgui_color_rect(rgui->frame_buf.data, w, h, 0, 0, w, h, 0x000f);
    rgui_blit_line(rgui, w, (w - 5 * rgui->font_width_stride) / 2, line / 2, "WebUI", 0xffff,
                   0x000f);
    if (qr->size)
    {
        rgui_color_rect(rgui->frame_buf.data, w, h, left, top, side, side, 0xffff);
        for (unsigned y = 0; y < qr->size; y++)
            for (unsigned x = 0; x < qr->size; x++)
                if (qr->modules[y * qr->size + x])
                    rgui_color_rect(rgui->frame_buf.data, w, h, left + x * scale, top + y * scale,
                                    scale, scale, 0x000f);
    }
    rgui_blit_line(rgui, w, (w - strlen(url) * rgui->font_width_stride) / 2, h - 4 * line, url,
                   0xffff, 0x000f);
    rgui_blit_line(rgui, w, (w - 24 * rgui->font_width_stride) / 2, h - 3 * line,
                   "Scan on the same network", 0xffff, 0x000f);
    rgui_blit_line(rgui, w, (w - 13 * rgui->font_width_stride) / 2, h - 2 * line, "Circle: Close",
                   0xffff, 0x000f);
    /* Redraw once more after closing, so no QR pixels remain on the menu. */
    rgui->flags |= RGUI_FLAG_FORCE_REDRAW;
}
