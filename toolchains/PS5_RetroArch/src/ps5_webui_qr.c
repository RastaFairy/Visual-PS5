/* The encoder is compiled here once per executable, with no heap or service calls. */
#include "ps5_webui_qr.h"
#include "qrcodegen/qrcodegen.c"
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <sys/time.h>
#include <net/if.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>

static bool usable_address(const struct in_addr *address)
{
    const uint32_t ip = ntohl(address->s_addr);
    return ip != 0 && (ip >> 24) != 127 && (ip >> 24) != 0 && (ip >> 24) < 224;
}

bool ps5_webui_qr_encode(struct ps5_webui_qr *qr, const char *address)
{
    struct in_addr ip;
    uint8_t scratch[qrcodegen_BUFFER_LEN_FOR_VERSION(3)];
    uint8_t code[qrcodegen_BUFFER_LEN_FOR_VERSION(3)];
    qr->url[0] = '\0';
    qr->size = 0;
    memset(qr->modules, 0, sizeof(qr->modules));
    if (!address || inet_pton(AF_INET, address, &ip) != 1 || !usable_address(&ip))
        return false;
    snprintf(qr->url, sizeof(qr->url), "http://%s:6769/", address);
    if (!qrcodegen_encodeText(qr->url, scratch, code, qrcodegen_Ecc_MEDIUM, 1, 3,
                              qrcodegen_Mask_AUTO, true))
    {
        qr->url[0] = '\0';
        return false;
    }
    const unsigned size = (unsigned)qrcodegen_getSize(code);
    qr->size = size + 8;
    for (unsigned y = 0; y < size; y++)
        for (unsigned x = 0; x < size; x++)
            qr->modules[(y + 4) * qr->size + x + 4] = qrcodegen_getModule(code, x, y);
    return true;
}

void ps5_webui_qr_refresh(struct ps5_webui_qr *qr, bool force)
{
    const time_t now = time(NULL);
    if (!force && qr->checked == now)
        return;
    qr->checked = now;
    struct ifaddrs *interfaces = NULL;
    char address[INET_ADDRSTRLEN] = "";
    if (getifaddrs(&interfaces) == 0)
    {
        for (const struct ifaddrs *it = interfaces; it; it = it->ifa_next)
        {
            if (!it->ifa_addr || it->ifa_addr->sa_family != AF_INET || !(it->ifa_flags & IFF_UP) ||
                (it->ifa_flags & IFF_LOOPBACK))
                continue;
            const struct sockaddr_in *in = (const struct sockaddr_in *)it->ifa_addr;
            if (usable_address(&in->sin_addr) &&
                inet_ntop(AF_INET, &in->sin_addr, address, sizeof(address)))
                break;
        }
        freeifaddrs(interfaces);
    }
    char url[64] = "";
    if (*address)
        snprintf(url, sizeof(url), "http://%s:6769/", address);
    if (strcmp(url, qr->url) != 0 || force)
        ps5_webui_qr_encode(qr, address);
}

static struct ps5_webui_qr current;
static bool visible;
void ps5_webui_qr_open(void)
{
    ps5_webui_qr_refresh(&current, true);
    visible = true;
}
void ps5_webui_qr_close(void)
{
    visible = false;
}
bool ps5_webui_qr_visible(void)
{
    return visible;
}
const struct ps5_webui_qr *ps5_webui_qr_current(void)
{
    ps5_webui_qr_refresh(&current, false);
    return &current;
}
