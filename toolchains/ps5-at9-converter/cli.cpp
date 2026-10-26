// PS5 Homebrew Studio command-line adapter for the open ATRAC9 encoder.
// This file is GPL-3.0-or-later because it links the GPL-3.0-or-later at9 library.
#include "src/lib/at9/at9.h"
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
void usage() {
    std::cout << "Usage: ps5-at9-converter --input FILE --output FILE [--start SEC] [--duration SEC] [--bitrate KBPS] [--no-loop]\n"
                 "Supports WAV, MP3, FLAC, AIFF/AIFC input. Default output: 48 kHz stereo, 192 kb/s, -28 LUFS, whole-track loop.\n";
}
double number(const std::string &value, const char *name) {
    std::size_t used = 0;
    const double parsed = std::stod(value, &used);
    if (used != value.size() || !std::isfinite(parsed)) throw std::runtime_error(std::string("Invalid ") + name + ": " + value);
    return parsed;
}
std::vector<std::uint8_t> read_file(const std::string &path) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) throw std::runtime_error("Cannot open input audio: " + path);
    stream.seekg(0, std::ios::end);
    const auto size = stream.tellg();
    if (size <= 0) throw std::runtime_error("Input audio is empty: " + path);
    if (static_cast<unsigned long long>(size) > 512ull * 1024ull * 1024ull) throw std::runtime_error("Input audio exceeds 512 MiB.");
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(size));
    stream.seekg(0, std::ios::beg);
    if (!stream.read(reinterpret_cast<char *>(bytes.data()), static_cast<std::streamsize>(bytes.size()))) throw std::runtime_error("Cannot read complete input audio: " + path);
    return bytes;
}
}

int main(int argc, char **argv) {
    try {
        std::string input, output;
        at9::Options options;
        for (int i = 1; i < argc; ++i) {
            const std::string arg = argv[i];
            if (arg == "--help" || arg == "-h") { usage(); return 0; }
            if (arg == "--no-loop") { options.loop = false; continue; }
            if (i + 1 >= argc) throw std::runtime_error("Missing value after " + arg);
            const std::string value = argv[++i];
            if (arg == "--input") input = value;
            else if (arg == "--output") output = value;
            else if (arg == "--start") options.start_sec = number(value, "start time");
            else if (arg == "--duration") options.duration_sec = number(value, "duration");
            else if (arg == "--bitrate") options.bitrate_kbps = static_cast<int>(number(value, "bitrate"));
            else if (arg == "--lufs") options.lufs = number(value, "LUFS target");
            else if (arg == "--true-peak") options.true_peak_db = number(value, "true-peak ceiling");
            else throw std::runtime_error("Unknown option: " + arg);
        }
        if (input.empty() || output.empty()) { usage(); throw std::runtime_error("Both --input and --output are required."); }
        at9::Audio audio;
        std::string error;
        const auto encodedInput = read_file(input);
        if (!at9::decode_file(encodedInput, audio, error)) throw std::runtime_error("Audio decoding failed: " + error);
        const auto result = at9::make_snd0(audio, options);
        std::ofstream stream(output, std::ios::binary | std::ios::trunc);
        if (!stream || !stream.write(reinterpret_cast<const char *>(result.at9.data()), static_cast<std::streamsize>(result.at9.size()))) {
            throw std::runtime_error("Cannot write output file: " + output);
        }
        stream.close();
        if (!stream) throw std::runtime_error("Failed to flush output file: " + output);
        std::cout << "ATRAC9 snd0.at9: 48000 Hz stereo, " << options.bitrate_kbps << " kb/s, "
                  << result.seconds << " s, " << result.at9.size() << " bytes, loudness "
                  << result.loudness_param << " LUFS, loop " << (options.loop ? "enabled" : "disabled") << ".\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "ATRAC9 conversion failed: " << error.what() << '\n';
        return 2;
    }
}