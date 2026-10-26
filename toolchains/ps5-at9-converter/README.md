# Offline ATRAC9 converter for PS5 Homebrew Studio

This folder vendors only the ATRAC9 conversion library and its decoding dependencies from PSGFX commit `5ee7aa9e7d91c9f518322847d13a6bda5ba97837`, plus a small command-line adapter written for Homebrew Studio.

The encoder implementation is a C++ port of BlackBearReloaded's `ps5-at9-converter` v0.1.0 (original revision `65be0a1`), as recorded in `src/lib/at9/NOTICES.md`. It emits the PS5 selection-music `RIFF/WAVE ATRAC9` profile. The table data is derived from LibAtrac9 (MIT); MP3, WAV and FLAC readers are minimp3 (CC0) and dr_libs (public domain/MIT-0). The notice file and individual source headers retain the exact attribution and license terms.

The encoder library and CLI adapter are GPL-3.0-or-later, distributed as a separate executable/toolchain from the IDE application. See `LICENSE` and `src/lib/at9/NOTICES.md`. No Sony encoder or proprietary SDK binary is included.

## Offline runtime

Homebrew Studio invokes the prebuilt `bin/ps5-at9-converter` under the bundled WSL Ubuntu image. It needs no FFmpeg, internet connection, Sony tools, pip packages, or network downloads. If rebuilding the tool, run `bash build.sh` inside WSL with the image's `g++`.

Input formats supported by this bundled build: WAV, MP3, FLAC and AIFF/AIFC. Already encoded `.at9` is validated and copied without re-encoding. The default output profile is 48 kHz stereo, 192 kb/s, -28 LUFS, -2 dBTP, 15 seconds, whole-track loop, and it rejects output over the PS5 2 MiB file limit.