/* The relaunch test's chain, run on the host against a LoadExec that either
 * replaces the process (a thrown Replaced), refuses, or is accepted and ignored.
 * The processes get argv as the console gives it: LoadExec's arguments are the
 * whole argv, with no program name in front, and a launch from the home screen
 * gets one empty argument. argv[1] is a scratch directory; the results file is
 * left there for tests/test_relaunch_ps5.py to parse as JSON. */
#include <cassert>
#include <cstdio>
#include <string>
#include <vector>
#include "../src/relaunch_ps5.cpp"

namespace
{
struct Replaced
{
};
enum class Exec
{
    replace,
    refuse,
    ignore
};
Exec exec_mode = Exec::replace;
int exec_calls = 0;
std::string exec_path, exec_argument;
std::vector<std::string> exec_arguments;
std::vector<std::string> marks;

std::string slurp(const std::string &path)
{
    std::string out;
    ps5::relaunch::read_file(path, out);
    return out;
}
bool exists(const std::string &path)
{
    std::FILE *file = std::fopen(path.c_str(), "rb");
    if (file)
        std::fclose(file);
    return file != nullptr;
}
void arm(const ps5::relaunch::Paths &paths, const char *text)
{
    std::FILE *file = std::fopen(paths.arm.c_str(), "wb");
    assert(file);
    std::fputs(text, file);
    std::fclose(file);
}
unsigned lines(const std::string &text)
{
    unsigned count = 0;
    for (char c : text)
        count += c == '\n';
    return count;
}
/* One process of the chain: true when LoadExec replaced it. */
bool launch(const ps5::relaunch::Paths &paths, std::vector<const char *> argv, bool &continued)
{
    argv.push_back(nullptr);
    try
    {
        continued = ps5::relaunch::run_test(paths, static_cast<int>(argv.size() - 1),
                                            const_cast<char **>(argv.data()), 0);
        return false;
    }
    catch (const Replaced &)
    {
        return true;
    }
}
} // namespace

/* src/permissions_ps5.cpp: the repair is the title's; here it has nothing to wait for. */
extern "C" void ps5_permissions_settle()
{
}
extern "C" int sceSystemServiceLoadExec(const char *path, const char *const *argv)
{
    exec_calls++;
    exec_path = path;
    exec_argument = argv && argv[0] ? argv[0] : "";
    assert(argv && argv[0]);
    exec_arguments.assign(argv, argv + 1);
    for (const char *const *at = argv + 1; *at; at++)
        exec_arguments.emplace_back(*at);
    if (exec_mode == Exec::replace)
        throw Replaced{};
    return exec_mode == Exec::refuse ? static_cast<int>(0x80020002u) : 0;
}
extern "C" int sceKernelAvailableFlexibleMemorySize(std::size_t *size)
{
    *size = 403u << 20;
    return 0;
}
void ps5::debug::mark(const char *step) noexcept
{
    marks.emplace_back(step);
}
void ps5::debug::mark_value(const char *step, long long value) noexcept
{
    marks.emplace_back(std::string(step) + " " + std::to_string(value));
}

int main(int argc, char **argv)
{
    assert(argc == 2);
    const std::string dir = argv[1];
    ps5::relaunch::Paths paths{dir + "/relaunch-test.txt", dir + "/relaunch-test.jsonl",
                               "/app0/eboot.bin"};
    bool continued = true;

    // Unarmed: nothing is read, written or started.
    assert(!launch(paths, {""}, continued) && !continued);
    assert(!exists(paths.results) && exec_calls == 0);

    // Arm files that must not start anything; each is removed.
    for (const char *bad : {"0 run", "21 run", "3", "3 bad/run", "3 \"quote\"", "x run"})
    {
        arm(paths, bad);
        assert(!launch(paths, {""}, continued) && !continued);
        assert(!exists(paths.arm) && !exists(paths.results) && exec_calls == 0);
    }

    // A full chain: generation 0 from the home screen, three restarts, then RetroArch.
    // Another run's line already in the file does not count toward this one.
    {
        std::FILE *old = std::fopen(paths.results.c_str(), "wb");
        std::fputs("{\"run\":\"older\",\"generation\":0,\"action\":\"restart\"}\n", old);
        std::fclose(old);
    }
    arm(paths, "3 chain-1\n");
    assert(launch(paths, {""}, continued));
    assert(exec_calls == 1 && exec_path == "/app0/eboot.bin" &&
           exec_argument == "--ps5-relaunch=1" && exec_arguments.size() == 1);
    assert(launch(paths, {"--ps5-relaunch=1"}, continued) && exec_argument == "--ps5-relaunch=2");
    // A restart whose arguments were lost still counts from the file; the last
    // one finds its token after another argument.
    assert(launch(paths, {""}, continued) && exec_argument == "--ps5-relaunch=3");
    assert(!launch(paths, {"other", "--ps5-relaunch=3"}, continued) && !continued);
    assert(exec_calls == 3 && !exists(paths.arm));
    const std::string chain = slurp(paths.results);
    assert(lines(chain) == 5);
    assert(ps5::relaunch::generation(chain, "chain-1") == 4);
    assert(ps5::relaunch::generation(chain, "older") == 1);
    assert(chain.find("\"generation\":0,\"count\":3,\"argument_generation\":-1") !=
           std::string::npos);
    assert(chain.find("\"generation\":1,\"count\":3,\"argument_generation\":1") !=
           std::string::npos);
    assert(chain.find("\"generation\":2,\"count\":3,\"argument_generation\":-1") !=
           std::string::npos);
    assert(chain.find("\"generation\":3,\"count\":3,\"argument_generation\":3") !=
           std::string::npos);
    assert(chain.find("\"flexible_free\":422576128") != std::string::npos);
    assert(chain.rfind("\"action\":\"continue\"}") != std::string::npos);

    // Refused: the result is recorded and the launch continues into RetroArch.
    exec_mode = Exec::refuse;
    arm(paths, "2 refused\n");
    assert(!launch(paths, {""}, continued) && continued && !exists(paths.arm));
    std::string text = slurp(paths.results);
    assert(text.find("{\"run\":\"refused\",\"generation\":0,\"event\":\"loadexec\",\"result\":-"
                     "2147352574}") != std::string::npos);
    assert(ps5::relaunch::generation(text, "refused") == 1);

    // Accepted, yet this process is still running after the wait: said, and disarmed.
    exec_mode = Exec::ignore;
    arm(paths, "2 ignored\n");
    assert(!launch(paths, {""}, continued) && continued && !exists(paths.arm));
    text = slurp(paths.results);
    assert(text.find("\"run\":\"ignored\",\"generation\":0,\"event\":\"loadexec\",\"result\":0,"
                     "\"still_running_after_s\":0}") != std::string::npos);

    // Another image in /app0: LoadExec is asked for it, and it is in the record.
    exec_mode = Exec::replace;
    arm(paths, "1 other-image /app0/probe/eboot-copy.bin\n");
    assert(launch(paths, {""}, continued) && exec_path == "/app0/probe/eboot-copy.bin");
    assert(!launch(paths, {"--ps5-relaunch=1"}, continued) && !continued);
    text = slurp(paths.results);
    assert(text.find("\"run\":\"other-image\",\"generation\":0,\"count\":1,"
                     "\"image\":\"/app0/probe/eboot-copy.bin\"") != std::string::npos);
    // Images outside /app0, or climbing out of it, are refused and start nothing.
    const int before_bad_images = exec_calls;
    for (const char *bad : {"1 r /data/x.bin", "1 r /app0/../x.bin", "1 r app0/x.bin"})
    {
        arm(paths, bad);
        assert(!launch(paths, {""}, continued) && !continued && !exists(paths.arm));
    }
    assert(exec_calls == before_bad_images);

    // Arguments are escaped: the file stays JSON whatever the shell passes.
    exec_mode = Exec::replace;
    arm(paths, "1 escaped\n");
    assert(launch(paths, {"eboot", "quote\"back\\slash", "tab\there"}, continued));
    text = slurp(paths.results);
    assert(text.find("\"argv\":[\"eboot\",\"quote\\\"back\\\\slash\",\"tab\\u0009here\"]") !=
           std::string::npos);
    assert(!launch(paths, {"--ps5-relaunch=1"}, continued) && !continued);

    // Arguments for the restarts, one a line after the first: each restart carries them
    // after its generation (a home screen forwarder's here). A bad line arms nothing.
    arm(paths, "1 forward\n--rom\r\nsnes/Game (USA).zip\n\n--core\nsnes9x\n");
    assert(launch(paths, {""}, continued));
    assert((exec_arguments == std::vector<std::string>{"--ps5-relaunch=1", "--rom",
                                                       "snes/Game (USA).zip", "--core", "snes9x"}));
    assert(!launch(paths, {"--ps5-relaunch=1", "--rom", "snes/Game (USA).zip", "--core", "snes9x"},
                   continued) &&
           !continued && !exists(paths.arm));
    const int before_bad_arguments = exec_calls;
    for (const char *bad : {"1 r\nok\nbad\ttab", "1 r\n1\n2\n3\n4\n5\n6\n7\n8\n9"})
    {
        arm(paths, bad);
        assert(!launch(paths, {""}, continued) && !continued && !exists(paths.arm));
    }
    assert(exec_calls == before_bad_arguments);

    // A record that cannot be written never restarts.
    const int calls = exec_calls;
    ps5::relaunch::Paths unwritable = paths;
    unwritable.results = dir + "/missing-directory/relaunch-test.jsonl";
    arm(unwritable, "2 unwritable\n");
    assert(!launch(unwritable, {""}, continued) && !continued);
    assert(exec_calls == calls && !exists(unwritable.arm));

    std::puts("relaunch_ps5: arming, chain counting, lost arguments, refused and ignored LoadExec, "
              "escaping and unwritable records PASS");
    return 0;
}
