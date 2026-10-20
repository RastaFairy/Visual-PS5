/* The WebUI link (src/webui_link.cpp) on the host, against the loader and daemon
 * tests/test_webui_link.py plays: PS5_WEBUI_APP0 and the two ports are the test's.
 * It links as eboot.bin does ("title"), says it runs RetroArch once linked, and
 * reports whether a daemon serves and whether it was asked to close for an update. */
#include "../src/webui_link.cpp"

#include <atomic>
#include <cstdio>

namespace
{
std::atomic<int> installs{0};
}

int main()
{
    std::setvbuf(stdout, nullptr, _IOLBF, 0);
    ps5_webui_link_start(
        "title", [] { ++installs; }, [](const char *line) { std::printf("log %s\n", line); });
    const int linked = ps5_webui_link_wait(15000);
    std::printf("wait=%d\n", linked);
    ps5_webui_link_frontend("retroarch");
    for (int i = 0; linked && i < 500 && !ps5_webui_link_install_requested(); ++i)
        usleep(10000);
    std::printf("install=%d callbacks=%d\n", ps5_webui_link_install_requested(), installs.load());
    return 0;
}
