/* PS5 RetroArch - the FreeImage functions EmulationStation uses, over stb_image.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * See include/FreeImage.h for why. A bitmap is kept as FreeImage keeps one: rows
 * bottom-up, 32-bit pixels B, G, R, A and 24-bit ones B, G, R, each row padded
 * to four bytes, because ES-DE copies rows out and flips them itself. stb_image
 * decodes top-down R, G, B, A, so loading and saving convert. WebP, which ES-DE's
 * default theme draws its system art from, is libwebp's decoder (still images).
 *
 * ES-DE plays a GIF by opening it again for every frame it shows
 * (GIFAnimComponent::update), so the decoded frames of the last few GIFs are
 * kept, keyed on the stream's handle, length and a hash of its start: reopening
 * one costs a read of its first bytes, not a decode.
 */
#include "FreeImage.h"

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_STATIC
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_ONLY_GIF
#define STBI_ONLY_BMP
#define STBI_ONLY_TGA
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_WRITE_STATIC
#include "stb_image_write.h"
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#define STB_IMAGE_RESIZE_STATIC
#include "stb_image_resize2.h"

#include <webp/decode.h>

struct FITAG
{
    uint32_t value = 0;
};

struct FIBITMAP
{
    unsigned width = 0, height = 0, bpp = 32, pitch = 0;
    std::vector<BYTE> bits;
    bool has_frame_time = false;
    FITAG frame_time;
};

struct FIMEMORY
{
    const BYTE *data = nullptr;
    size_t size = 0;
};

namespace ps5_freeimage
{
struct Gif
{
    fi_handle handle = nullptr;
    long length = 0;
    uint64_t start_hash = 0;
    int width = 0, height = 0, frames = 0;
    std::vector<BYTE> rgba; /* frames * width * height * 4, top-down */
    std::vector<int> delays;
};
std::vector<std::shared_ptr<Gif>> gif_cache;
constexpr size_t gif_cache_size = 4;
} // namespace ps5_freeimage
using namespace ps5_freeimage;

struct FIMULTIBITMAP
{
    std::shared_ptr<Gif> gif;
};

namespace
{
FIBITMAP *allocate(unsigned width, unsigned height, unsigned bpp)
{
    if (width == 0 || height == 0 || (bpp != 24 && bpp != 32))
        return nullptr;
    auto *dib = new FIBITMAP;
    dib->width = width;
    dib->height = height;
    dib->bpp = bpp;
    dib->pitch = (width * (bpp / 8) + 3) & ~3u;
    dib->bits.assign(size_t(dib->pitch) * height, 0);
    return dib;
}

/* Top-down R, G, B, A pixels to a 32-bit bitmap. */
FIBITMAP *from_rgba(const unsigned char *rgba, int width, int height)
{
    FIBITMAP *dib = allocate(unsigned(width), unsigned(height), 32);
    if (!dib)
        return nullptr;
    for (int y = 0; y < height; y++)
    {
        const unsigned char *in = rgba + size_t(y) * width * 4;
        BYTE *out = dib->bits.data() + size_t(height - 1 - y) * dib->pitch;
        for (int x = 0; x < width; x++, in += 4, out += 4)
        {
            out[FI_RGBA_RED] = in[0];
            out[FI_RGBA_GREEN] = in[1];
            out[FI_RGBA_BLUE] = in[2];
            out[FI_RGBA_ALPHA] = in[3];
        }
    }
    return dib;
}

FREE_IMAGE_FORMAT format_of(const BYTE *data, size_t size)
{
    if (size >= 8 && std::memcmp(data, "\x89PNG\r\n\x1a\n", 8) == 0)
        return FIF_PNG;
    if (size >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF)
        return FIF_JPEG;
    if (size >= 6 && (std::memcmp(data, "GIF87a", 6) == 0 || std::memcmp(data, "GIF89a", 6) == 0))
        return FIF_GIF;
    if (size >= 2 && data[0] == 'B' && data[1] == 'M')
        return FIF_BMP;
    if (size >= 12 && std::memcmp(data, "RIFF", 4) == 0 && std::memcmp(data + 8, "WEBP", 4) == 0)
        return FIF_WEBP;
    return FIF_UNKNOWN;
}

bool read_file(const char *filename, std::vector<BYTE> &out)
{
    std::FILE *file = std::fopen(filename, "rb");
    if (!file)
        return false;
    std::fseek(file, 0, SEEK_END);
    const long length = std::ftell(file);
    std::fseek(file, 0, SEEK_SET);
    if (length <= 0)
    {
        std::fclose(file);
        return false;
    }
    out.resize(size_t(length));
    const bool ok = std::fread(out.data(), 1, out.size(), file) == out.size();
    std::fclose(file);
    return ok;
}

FIBITMAP *decode(const BYTE *data, size_t size)
{
    if (format_of(data, size) == FIF_WEBP)
    {
        int width = 0, height = 0;
        uint8_t *rgba = WebPDecodeRGBA(data, size, &width, &height);
        if (!rgba)
            return nullptr;
        FIBITMAP *dib = from_rgba(rgba, width, height);
        WebPFree(rgba);
        return dib;
    }
    int width = 0, height = 0, channels = 0;
    unsigned char *rgba = stbi_load_from_memory(data, int(size), &width, &height, &channels, 4);
    if (!rgba)
        return nullptr;
    FIBITMAP *dib = from_rgba(rgba, width, height);
    stbi_image_free(rgba);
    return dib;
}

/* A bitmap's pixels as top-down R, G, B(, A), for the encoders. */
std::vector<unsigned char> to_top_down(FIBITMAP *dib, int channels)
{
    std::vector<unsigned char> out(size_t(dib->width) * dib->height * channels);
    const unsigned step = dib->bpp / 8;
    for (unsigned y = 0; y < dib->height; y++)
    {
        const BYTE *in = dib->bits.data() + size_t(dib->height - 1 - y) * dib->pitch;
        unsigned char *row = out.data() + size_t(y) * dib->width * channels;
        for (unsigned x = 0; x < dib->width; x++, in += step, row += channels)
        {
            row[0] = in[FI_RGBA_RED];
            row[1] = in[FI_RGBA_GREEN];
            row[2] = in[FI_RGBA_BLUE];
            if (channels == 4)
                row[3] = step == 4 ? in[FI_RGBA_ALPHA] : 0xFF;
        }
    }
    return out;
}

FIBITMAP *convert(FIBITMAP *dib, unsigned bpp)
{
    if (!dib)
        return nullptr;
    FIBITMAP *out = allocate(dib->width, dib->height, bpp);
    if (!out)
        return nullptr;
    const unsigned in_step = dib->bpp / 8, out_step = bpp / 8;
    for (unsigned y = 0; y < dib->height; y++)
    {
        const BYTE *in = dib->bits.data() + size_t(y) * dib->pitch;
        BYTE *row = out->bits.data() + size_t(y) * out->pitch;
        for (unsigned x = 0; x < dib->width; x++, in += in_step, row += out_step)
        {
            row[0] = in[0];
            row[1] = in[1];
            row[2] = in[2];
            if (out_step == 4)
                row[3] = in_step == 4 ? in[3] : 0xFF;
        }
    }
    return out;
}

uint64_t fnv1a(const BYTE *data, size_t size)
{
    uint64_t hash = 0xcbf29ce484222325ull;
    for (size_t i = 0; i < size; i++)
        hash = (hash ^ data[i]) * 0x100000001b3ull;
    return hash;
}
} // namespace

extern "C" {

void FreeImage_Initialise(BOOL)
{
}

void FreeImage_DeInitialise(void)
{
    gif_cache.clear();
}

FIMEMORY *FreeImage_OpenMemory(BYTE *data, DWORD size_in_bytes)
{
    auto *stream = new FIMEMORY;
    stream->data = data;
    stream->size = size_in_bytes;
    return stream;
}

void FreeImage_CloseMemory(FIMEMORY *stream)
{
    delete stream;
}

FREE_IMAGE_FORMAT FreeImage_GetFileType(const char *filename, int)
{
    BYTE head[16] = {};
    std::FILE *file = filename ? std::fopen(filename, "rb") : nullptr;
    if (!file)
        return FIF_UNKNOWN;
    const size_t read = std::fread(head, 1, sizeof head, file);
    std::fclose(file);
    return format_of(head, read);
}

FREE_IMAGE_FORMAT FreeImage_GetFileTypeFromMemory(FIMEMORY *stream, int)
{
    return stream && stream->data ? format_of(stream->data, stream->size) : FIF_UNKNOWN;
}

FREE_IMAGE_FORMAT FreeImage_GetFIFFromFilename(const char *filename)
{
    if (!filename)
        return FIF_UNKNOWN;
    const char *dot = std::strrchr(filename, '.');
    if (!dot)
        return FIF_UNKNOWN;
    std::string extension;
    for (const char *at = dot + 1; *at; at++)
        extension += char(std::tolower(static_cast<unsigned char>(*at)));
    if (extension == "png")
        return FIF_PNG;
    if (extension == "jpg" || extension == "jpeg" || extension == "jpe" || extension == "jif")
        return FIF_JPEG;
    if (extension == "gif")
        return FIF_GIF;
    if (extension == "bmp")
        return FIF_BMP;
    if (extension == "tga" || extension == "targa")
        return FIF_TARGA;
    if (extension == "webp")
        return FIF_WEBP;
    if (extension == "tif" || extension == "tiff")
        return FIF_TIFF;
    return FIF_UNKNOWN;
}

BOOL FreeImage_FIFSupportsReading(FREE_IMAGE_FORMAT fif)
{
    return fif == FIF_PNG || fif == FIF_JPEG || fif == FIF_GIF || fif == FIF_BMP || fif == FIF_TARGA ||
           fif == FIF_WEBP;
}

FIBITMAP *FreeImage_Load(FREE_IMAGE_FORMAT fif, const char *filename, int)
{
    std::vector<BYTE> data;
    if (!FreeImage_FIFSupportsReading(fif) || !read_file(filename, data))
        return nullptr;
    return decode(data.data(), data.size());
}

FIBITMAP *FreeImage_LoadFromMemory(FREE_IMAGE_FORMAT fif, FIMEMORY *stream, int)
{
    if (!stream || !stream->data || !FreeImage_FIFSupportsReading(fif))
        return nullptr;
    return decode(stream->data, stream->size);
}

BOOL FreeImage_Save(FREE_IMAGE_FORMAT fif, FIBITMAP *dib, const char *filename, int)
{
    if (!dib || !filename)
        return FALSE;
    const int width = int(dib->width), height = int(dib->height);
    switch (fif)
    {
    case FIF_PNG:
    {
        const int channels = dib->bpp == 32 ? 4 : 3;
        const auto pixels = to_top_down(dib, channels);
        return stbi_write_png(filename, width, height, channels, pixels.data(), width * channels) != 0;
    }
    case FIF_JPEG:
    {
        const auto pixels = to_top_down(dib, 3);
        return stbi_write_jpg(filename, width, height, 3, pixels.data(), 90) != 0;
    }
    case FIF_BMP:
    {
        const auto pixels = to_top_down(dib, 3);
        return stbi_write_bmp(filename, width, height, 3, pixels.data()) != 0;
    }
    case FIF_TARGA:
    {
        const auto pixels = to_top_down(dib, 4);
        return stbi_write_tga(filename, width, height, 4, pixels.data()) != 0;
    }
    default:
        return FALSE;
    }
}

void FreeImage_Unload(FIBITMAP *dib)
{
    delete dib;
}

unsigned FreeImage_GetWidth(FIBITMAP *dib)
{
    return dib ? dib->width : 0;
}

unsigned FreeImage_GetHeight(FIBITMAP *dib)
{
    return dib ? dib->height : 0;
}

unsigned FreeImage_GetPitch(FIBITMAP *dib)
{
    return dib ? dib->pitch : 0;
}

unsigned FreeImage_GetBPP(FIBITMAP *dib)
{
    return dib ? dib->bpp : 0;
}

BYTE *FreeImage_GetScanLine(FIBITMAP *dib, int scanline)
{
    if (!dib || scanline < 0 || unsigned(scanline) >= dib->height)
        return nullptr;
    return dib->bits.data() + size_t(scanline) * dib->pitch;
}

BOOL FreeImage_GetPixelColor(FIBITMAP *dib, unsigned x, unsigned y, RGBQUAD *value)
{
    if (!dib || !value || x >= dib->width || y >= dib->height)
        return FALSE;
    const BYTE *pixel = dib->bits.data() + size_t(y) * dib->pitch + size_t(x) * (dib->bpp / 8);
    value->rgbBlue = pixel[FI_RGBA_BLUE];
    value->rgbGreen = pixel[FI_RGBA_GREEN];
    value->rgbRed = pixel[FI_RGBA_RED];
    value->rgbReserved = dib->bpp == 32 ? pixel[FI_RGBA_ALPHA] : 0;
    return TRUE;
}

FIBITMAP *FreeImage_ConvertTo24Bits(FIBITMAP *dib)
{
    return convert(dib, 24);
}

FIBITMAP *FreeImage_ConvertTo32Bits(FIBITMAP *dib)
{
    return convert(dib, 32);
}

BOOL FreeImage_PreMultiplyWithAlpha(FIBITMAP *dib)
{
    if (!dib || dib->bpp != 32)
        return FALSE;
    for (unsigned y = 0; y < dib->height; y++)
    {
        BYTE *pixel = dib->bits.data() + size_t(y) * dib->pitch;
        for (unsigned x = 0; x < dib->width; x++, pixel += 4)
        {
            const unsigned alpha = pixel[FI_RGBA_ALPHA];
            if (alpha == 0xFF)
                continue;
            for (int c = 0; c < 3; c++)
                pixel[c] = BYTE((pixel[c] * alpha + 127) / 255);
        }
    }
    return TRUE;
}

void FreeImage_ConvertToRawBits(BYTE *bits, FIBITMAP *dib, int pitch, unsigned bpp, unsigned, unsigned, unsigned,
                                BOOL topdown)
{
    /* As FreeImage does for 24 and 32 bits: the rows as they are, the masks unused. */
    if (!bits || !dib || bpp != dib->bpp)
        return;
    const size_t row_bytes = size_t(dib->width) * (bpp / 8);
    for (unsigned y = 0; y < dib->height; y++)
    {
        const unsigned source = topdown ? dib->height - 1 - y : y;
        std::memcpy(bits + size_t(y) * pitch, dib->bits.data() + size_t(source) * dib->pitch, row_bytes);
    }
}

FIBITMAP *FreeImage_ConvertFromRawBits(BYTE *bits, int width, int height, int pitch, unsigned bpp, unsigned,
                                       unsigned, unsigned, BOOL topdown)
{
    if (!bits || width <= 0 || height <= 0)
        return nullptr;
    FIBITMAP *dib = allocate(unsigned(width), unsigned(height), bpp);
    if (!dib)
        return nullptr;
    const size_t row_bytes = size_t(width) * (bpp / 8);
    for (int y = 0; y < height; y++)
    {
        const int destination = topdown ? height - 1 - y : y;
        std::memcpy(dib->bits.data() + size_t(destination) * dib->pitch, bits + size_t(y) * pitch, row_bytes);
    }
    return dib;
}

FIBITMAP *FreeImage_Rescale(FIBITMAP *dib, int dst_width, int dst_height, FREE_IMAGE_FILTER filter)
{
    if (!dib || dst_width <= 0 || dst_height <= 0)
        return nullptr;
    FIBITMAP *out = allocate(unsigned(dst_width), unsigned(dst_height), dib->bpp);
    if (!out)
        return nullptr;
    const stbir_pixel_layout layout = dib->bpp == 32 ? STBIR_BGRA : STBIR_BGR;
    /* Rows stay bottom-up on both sides, so the image is not flipped. */
    STBIR_RESIZE resize;
    stbir_resize_init(&resize, dib->bits.data(), int(dib->width), int(dib->height), int(dib->pitch),
                      out->bits.data(), dst_width, dst_height, int(out->pitch), layout, STBIR_TYPE_UINT8_SRGB);
    const stbir_filter stb_filter = filter == FILTER_BOX        ? STBIR_FILTER_BOX
                                    : filter == FILTER_BILINEAR ? STBIR_FILTER_TRIANGLE
                                    : filter == FILTER_BSPLINE  ? STBIR_FILTER_CUBICBSPLINE
                                    : filter == FILTER_BICUBIC  ? STBIR_FILTER_MITCHELL
                                                                : STBIR_FILTER_CATMULLROM;
    stbir_set_filters(&resize, stb_filter, stb_filter);
    if (!stbir_resize_extended(&resize))
    {
        delete out;
        return nullptr;
    }
    return out;
}

FIMULTIBITMAP *FreeImage_OpenMultiBitmapFromHandle(FREE_IMAGE_FORMAT fif, FreeImageIO *io, fi_handle handle, int)
{
    if (fif != FIF_GIF || !io || !io->read_proc || !io->seek_proc || !io->tell_proc)
        return nullptr;
    io->seek_proc(handle, 0, SEEK_END);
    const long length = io->tell_proc(handle);
    io->seek_proc(handle, 0, SEEK_SET);
    if (length <= 0)
        return nullptr;
    BYTE head[256];
    const unsigned head_size = unsigned(length < long(sizeof head) ? length : long(sizeof head));
    if (io->read_proc(head, 1, head_size, handle) != head_size)
        return nullptr;
    const uint64_t start_hash = fnv1a(head, head_size);
    for (auto &gif : gif_cache)
        if (gif->handle == handle && gif->length == length && gif->start_hash == start_hash)
            return new FIMULTIBITMAP{gif};

    std::vector<BYTE> data(static_cast<size_t>(length));
    io->seek_proc(handle, 0, SEEK_SET);
    if (io->read_proc(data.data(), 1, unsigned(length), handle) != unsigned(length))
        return nullptr;
    auto gif = std::make_shared<Gif>();
    int *delays = nullptr, channels = 0;
    unsigned char *frames = stbi_load_gif_from_memory(data.data(), int(data.size()), &delays, &gif->width,
                                                      &gif->height, &gif->frames, &channels, 4);
    if (!frames)
        return nullptr;
    gif->handle = handle;
    gif->length = length;
    gif->start_hash = start_hash;
    gif->rgba.assign(frames, frames + size_t(gif->frames) * gif->width * gif->height * 4);
    gif->delays.assign(delays, delays + gif->frames);
    stbi_image_free(frames);
    STBI_FREE(delays);
    if (gif_cache.size() == gif_cache_size)
        gif_cache.erase(gif_cache.begin());
    gif_cache.push_back(gif);
    return new FIMULTIBITMAP{gif};
}

BOOL FreeImage_CloseMultiBitmap(FIMULTIBITMAP *bitmap, int)
{
    delete bitmap;
    return TRUE;
}

int FreeImage_GetPageCount(FIMULTIBITMAP *bitmap)
{
    return bitmap && bitmap->gif ? bitmap->gif->frames : 0;
}

FIBITMAP *FreeImage_LockPage(FIMULTIBITMAP *bitmap, int page)
{
    if (!bitmap || !bitmap->gif || page < 0 || page >= bitmap->gif->frames)
        return nullptr;
    const Gif &gif = *bitmap->gif;
    FIBITMAP *dib =
        from_rgba(gif.rgba.data() + size_t(page) * gif.width * gif.height * 4, gif.width, gif.height);
    if (dib)
    {
        dib->has_frame_time = true;
        dib->frame_time.value = uint32_t(gif.delays[size_t(page)]);
    }
    return dib;
}

void FreeImage_UnlockPage(FIMULTIBITMAP *, FIBITMAP *data, BOOL)
{
    delete data;
}

BOOL FreeImage_GetMetadata(FREE_IMAGE_MDMODEL model, FIBITMAP *dib, const char *key, FITAG **tag)
{
    if (!tag)
        return FALSE;
    *tag = nullptr;
    if (model != FIMD_ANIMATION || !dib || !key || std::strcmp(key, "FrameTime") != 0 || !dib->has_frame_time)
        return FALSE;
    *tag = &dib->frame_time;
    return TRUE;
}

DWORD FreeImage_GetTagCount(FITAG *tag)
{
    return tag ? 1 : 0;
}

const void *FreeImage_GetTagValue(FITAG *tag)
{
    return tag ? &tag->value : nullptr;
}

} // extern "C"
