/* Exercise the shipped extraction/installation transaction with generated fixtures. */
#include "../src/webui_update.h"
#include <cstdio>
#include <string>
#include <unistd.h>
int main(int argc, char **argv)
{
    if (argc < 3)
        return 2;
    std::string root = argv[1], action = argv[2];
    ps5_update::initialize(root);
    bool ok = true;
    if (action != "recover")
    {
        if (argc != 5)
            return 2;
        ok = ps5_update::prepare(root, argv[3], argv[4]);
        if (ok && action != "prepare")
        {
            ok = ps5_update::request_install();
            if (action == "fail")
                unlink((root + "/.update/stage/webui/app.js").c_str());
            ps5_update::stop();
            ok = ps5_update::install() && ok;
        }
    }
    else
        ok = ps5_update::status().state != "error";
    auto s = ps5_update::status();
    std::printf("%s: %s\n", s.state.c_str(), s.message.c_str());
    return ok ? 0 : 1;
}
