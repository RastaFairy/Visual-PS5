// Input decoding for the snd0.at9 maker: MP3 (minimp3), WAV/RF64/AIFF
// (dr_wav) and FLAC (dr_flac). Format detection mirrors ps5at9/audio_io.py.
// Copyright (C) 2026 BlackBearReloaded (original Python implementation)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "at9.h"

#include <cstdlib>
#include <cstring>

#define MINIMP3_IMPLEMENTATION
#define MINIMP3_FLOAT_OUTPUT
#define MINIMP3_NO_STDIO
#include "minimp3_ex.h"

#define DR_WAV_IMPLEMENTATION
#define DR_WAV_NO_STDIO
#define DR_WAV_NO_WCHAR
#include "dr_wav.h"

#define DR_FLAC_IMPLEMENTATION
#define DR_FLAC_NO_STDIO
#define DR_FLAC_NO_WCHAR
#define DR_FLAC_NO_OGG
#include "dr_flac.h"

namespace at9 {
namespace {

bool starts(const std::vector<uint8_t> &b, size_t off, const char *s) {
    size_t n = std::strlen(s);
    return b.size() >= off + n && std::memcmp(b.data() + off, s, n) == 0;
}

// Integer samples are scaled by 1 / 2^31 after left-justification, exactly as
// the Python reader does (16- and 24-bit input is represented exactly).
constexpr double INT_SCALE = 1.0 / 2147483648.0;

bool decode_wav(const std::vector<uint8_t> &bytes, Audio &out, std::string &err) {
    drwav wav;
    if (!drwav_init_memory(&wav, bytes.data(), bytes.size(), nullptr)) {
        err = "could not read WAV/AIFF file";
        return false;
    }
    bool ok = true;
    if (wav.channels < 1 || wav.sampleRate < 1) {
        err = "unsupported WAVE format";
        ok = false;
    } else {
        const size_t ch = wav.channels;
        const drwav_uint64 frames = wav.totalPCMFrameCount;
        out.rate = (int)wav.sampleRate;
        out.channels = (int)ch;
        out.pcm.clear();
        if (wav.translatedFormatTag == DR_WAVE_FORMAT_IEEE_FLOAT) {
            out.pcm.resize((size_t)frames * ch);
            drwav_uint64 got = drwav_read_pcm_frames_f32(&wav, frames, out.pcm.data());
            out.pcm.resize((size_t)got * ch);
        } else {
            std::vector<drwav_int32> tmp((size_t)frames * ch);
            drwav_uint64 got = drwav_read_pcm_frames_s32(&wav, frames, tmp.data());
            out.pcm.resize((size_t)got * ch);
            for (size_t i = 0; i < out.pcm.size(); i++) out.pcm[i] = (float)(tmp[i] * INT_SCALE);
        }
        if (out.pcm.empty()) {
            err = "the WAV/AIFF file contains no audio";
            ok = false;
        }
    }
    drwav_uninit(&wav);
    return ok;
}

bool decode_flac(const std::vector<uint8_t> &bytes, Audio &out, std::string &err) {
    drflac *f = drflac_open_memory(bytes.data(), bytes.size(), nullptr);
    if (!f) {
        err = "could not decode FLAC";
        return false;
    }
    const size_t ch = f->channels;
    out.rate = (int)f->sampleRate;
    out.channels = (int)ch;
    out.pcm.clear();
    std::vector<drflac_int32> buf(4096 * ch);
    for (;;) {
        drflac_uint64 got = drflac_read_pcm_frames_s32(f, 4096, buf.data());
        if (!got) break;
        for (size_t i = 0; i < (size_t)got * ch; i++) out.pcm.push_back((float)(buf[i] * INT_SCALE));
    }
    drflac_close(f);
    if (out.pcm.empty() || out.rate <= 0) {
        err = "could not decode FLAC (no audio)";
        return false;
    }
    return true;
}

bool decode_mp3(const std::vector<uint8_t> &bytes, Audio &out, std::string &err) {
    mp3dec_t dec;
    mp3dec_file_info_t info;
    std::memset(&info, 0, sizeof info);
    if (mp3dec_load_buf(&dec, bytes.data(), bytes.size(), &info, nullptr, nullptr) || !info.buffer ||
        !info.samples || info.channels <= 0 || info.hz <= 0) {
        std::free(info.buffer);
        err = "could not decode MP3: no MPEG audio frames found";
        return false;
    }
    out.rate = info.hz;
    out.channels = info.channels;
    out.pcm.assign(info.buffer, info.buffer + info.samples - info.samples % info.channels);
    std::free(info.buffer);
    return true;
}

} // namespace

bool decode_file(const std::vector<uint8_t> &bytes, Audio &out, std::string &err) {
    out = Audio();
    err.clear();
    if (bytes.size() < 12) {
        err = "the file is too small to be audio";
        return false;
    }
    if ((starts(bytes, 0, "RIFF") || starts(bytes, 0, "RF64")) && starts(bytes, 8, "WAVE"))
        return decode_wav(bytes, out, err);
    if (starts(bytes, 0, "FORM") && (starts(bytes, 8, "AIFF") || starts(bytes, 8, "AIFC")))
        return decode_wav(bytes, out, err);
    if (starts(bytes, 0, "fLaC")) return decode_flac(bytes, out, err);
    if (starts(bytes, 0, "OggS")) {
        err = "unsupported input format (OGG); use MP3, WAV, AIFF or FLAC";
        return false;
    }
    if (starts(bytes, 4, "ftyp")) {
        err = "unsupported input format (MP4); use MP3, WAV, AIFF or FLAC";
        return false;
    }
    // ID3, an MPEG frame sync, or junk before the first frame: try MP3.
    return decode_mp3(bytes, out, err);
}

} // namespace at9
