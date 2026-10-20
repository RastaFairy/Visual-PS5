/* The display modes test on the host, through the Khronos loader: argv[1] is a
 * scratch directory. Unarmed, it must do nothing. The pattern must have its
 * border and its halves. With a driver to run on (argv[2] = "armed", and
 * VK_DRIVER_FILES naming a build of RADV with the VideoOut WSI, whose host
 * model presents at once), every mode must present. */
#include <cassert>
#include <cstdio>
#include <string>
#include <vector>
#include "../src/display_modes_ps5.cpp"

void ps5::debug::mark(const char *step) noexcept
{
    std::printf("trace: %s\n", step);
}
void ps5::debug::mark_value(const char *step, long long value) noexcept
{
    std::printf("trace: %s %lld\n", step, value);
}

int main(int argc, char **argv)
{
    assert(argc >= 2);
    const std::string dir = argv[1];
    const std::string arm = dir + "/display-modes-test.txt",
                      results = dir + "/display-modes-test.jsonl";

    // Unarmed: no device, no record.
    assert(!ps5::display_modes::run_test(arm, results));
    assert(std::fopen(results.c_str(), "rb") == nullptr);

    // The pattern: a white border, then the size's two shades either side of the middle.
    const VkExtent2D extent{1280, 720};
    std::vector<uint32_t> pixels(size_t(extent.width) * extent.height);
    ps5::display_modes::fill_pattern(pixels.data(), extent);
    assert(pixels[0] == 0xffffffffu && pixels.back() == 0xffffffffu);
    assert(pixels[size_t(360) * 1280 + 12] == 0xffffffffu);
    assert(pixels[size_t(360) * 1280 + 13] == 0xffffff00u);
    assert(pixels[size_t(360) * 1280 + 639] == 0xffffff00u);
    assert(pixels[size_t(360) * 1280 + 640] == 0xff808000u);
    const std::string line = ps5::display_modes::mode_line({{1920, 1080}, 59940}, 3, 3, 0.05, "");
    assert(line == "{\"width\":1920,\"height\":1080,\"refresh_millihertz\":59940,\"frames\":3,"
                   "\"images\":3,\"seconds\":0.050,\"result\":\"ok\"}");

    if (argc > 2 && std::string(argv[2]) == "armed")
    {
        std::FILE *file = std::fopen(arm.c_str(), "wb");
        std::fputs("3\n", file);
        std::fclose(file);
        const bool passed = ps5::display_modes::run_test(arm, results);
        std::printf("display_modes_ps5 armed run: %s\n", passed ? "PASS" : "FAIL");
        return passed ? 0 : 1;
    }
    std::puts("display_modes_ps5: unarmed, pattern and record PASS");
    return 0;
}
