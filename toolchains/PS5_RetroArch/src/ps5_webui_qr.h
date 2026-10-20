/* Runtime WebUI address and QR modules shared by every frontend. */
#ifndef PS5_WEBUI_QR_H
#define PS5_WEBUI_QR_H
#include <stdbool.h>
#include <stdint.h>
#include <time.h>

#define PS5_WEBUI_QR_MAX_SIZE 37 /* Version 3 plus a four-module quiet zone. */
#define PS5_WEBUI_QR_OFFLINE "Connect your PS5 to the network, then try again."
#ifdef __cplusplus
extern "C"
{
#endif
    struct ps5_webui_qr
    {
        char url[64];
        unsigned size;
        uint8_t modules[PS5_WEBUI_QR_MAX_SIZE * PS5_WEBUI_QR_MAX_SIZE];
        time_t checked;
    };
    /* Build from an IPv4 address; invalid/offline addresses clear the previous QR. */
    bool ps5_webui_qr_encode(struct ps5_webui_qr *qr, const char *address);
    /* Read the console's active interfaces, at most once per second unless forced. */
    void ps5_webui_qr_refresh(struct ps5_webui_qr *qr, bool force);
    /* RetroArch's modal state. Other frontends own their own ps5_webui_qr. */
    void ps5_webui_qr_open(void);
    void ps5_webui_qr_close(void);
    bool ps5_webui_qr_visible(void);
    const struct ps5_webui_qr *ps5_webui_qr_current(void);
#ifdef __cplusplus
}
#endif
#endif
