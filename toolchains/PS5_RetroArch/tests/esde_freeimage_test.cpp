/* The FreeImage functions EmulationStation uses, as frontends/es-de/ps5 provides
 * them over stb_image: FreeImage's layout (bottom-up rows, B, G, R, A), loading,
 * conversion, rescaling, saving, a GIF's frames with their times and a WebP.
 * argv: a scratch directory, a PNG, a two-frame GIF (red then blue, 20 ms) and a
 * lossless 3x2 WebP (red, green, blue; white at half alpha, clear, 10/20/30). */
#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include "../frontends/es-de/ps5/freeimage_stb.cpp"

static unsigned read_proc(void *buffer, unsigned size, unsigned count, fi_handle handle)
{
    return unsigned(std::fread(buffer, size, count, static_cast<std::FILE *>(handle)));
}
static unsigned write_proc(void *, unsigned, unsigned, fi_handle)
{
    return 0;
}
static int seek_proc(fi_handle handle, long offset, int origin)
{
    return std::fseek(static_cast<std::FILE *>(handle), offset, origin);
}
static long tell_proc(fi_handle handle)
{
    return std::ftell(static_cast<std::FILE *>(handle));
}

int main(int argc, char **argv)
{
    assert(argc == 5);
    const std::string dir = argv[1], png = argv[2], gif = argv[3], webp = argv[4];
    FreeImage_Initialise();

    // Detection by content and by name.
    assert(FreeImage_GetFileType(png.c_str()) == FIF_PNG);
    assert(FreeImage_GetFileType(gif.c_str()) == FIF_GIF);
    assert(FreeImage_GetFIFFromFilename("a/b/Cover.JPeg") == FIF_JPEG);
    assert(FreeImage_GetFIFFromFilename("x.webp") == FIF_WEBP);

    // A WebP, through libwebp: FreeImage's layout, the bottom row first.
    assert(FreeImage_GetFileType(webp.c_str()) == FIF_WEBP &&
           FreeImage_FIFSupportsReading(FIF_WEBP));
    FIBITMAP *webp_image = FreeImage_Load(FIF_WEBP, webp.c_str());
    assert(webp_image && FreeImage_GetWidth(webp_image) == 3 &&
           FreeImage_GetHeight(webp_image) == 2 && FreeImage_GetBPP(webp_image) == 32);
    const BYTE *upper = FreeImage_GetScanLine(webp_image, 1),
               *lower = FreeImage_GetScanLine(webp_image, 0);
    assert(upper[FI_RGBA_RED] == 255 && upper[FI_RGBA_GREEN] == 0 && upper[FI_RGBA_ALPHA] == 255);
    assert(upper[4 + FI_RGBA_GREEN] == 255 && upper[8 + FI_RGBA_BLUE] == 255);
    assert(lower[FI_RGBA_RED] == 255 && lower[FI_RGBA_ALPHA] == 128);
    assert(lower[8 + FI_RGBA_RED] == 10 && lower[8 + FI_RGBA_GREEN] == 20 &&
           lower[8 + FI_RGBA_BLUE] == 30);
    FreeImage_Unload(webp_image);

    // A PNG: FreeImage's layout, checked against stb_image's own top-down RGBA.
    FIBITMAP *image = FreeImage_Load(FIF_PNG, png.c_str());
    assert(image && FreeImage_GetBPP(image) == 32);
    const unsigned width = FreeImage_GetWidth(image), height = FreeImage_GetHeight(image);
    int w = 0, h = 0, n = 0;
    unsigned char *rgba = stbi_load(png.c_str(), &w, &h, &n, 4);
    assert(rgba && unsigned(w) == width && unsigned(h) == height);
    const BYTE *bottom = FreeImage_GetScanLine(image, 0);
    const unsigned char *last_row = rgba + size_t(h - 1) * w * 4;
    assert(bottom[FI_RGBA_RED] == last_row[0] && bottom[FI_RGBA_GREEN] == last_row[1] &&
           bottom[FI_RGBA_BLUE] == last_row[2] && bottom[FI_RGBA_ALPHA] == last_row[3]);
    RGBQUAD top_left;
    assert(FreeImage_GetPixelColor(image, 0, height - 1, &top_left));
    assert(top_left.rgbRed == rgba[0] && top_left.rgbGreen == rgba[1] &&
           top_left.rgbBlue == rgba[2]);

    // Raw bits out top-down and back: the same pixels.
    std::vector<BYTE> raw(size_t(width) * height * 4);
    FreeImage_ConvertToRawBits(raw.data(), image, int(width * 4), 32, FI_RGBA_RED, FI_RGBA_GREEN,
                               FI_RGBA_BLUE, 1);
    assert(raw[0] == rgba[2] && raw[1] == rgba[1] && raw[2] == rgba[0]);
    FIBITMAP *back =
        FreeImage_ConvertFromRawBits(raw.data(), int(width), int(height), int(width * 4), 32,
                                     FI_RGBA_RED, FI_RGBA_GREEN, FI_RGBA_BLUE, 1);
    assert(back && std::memcmp(FreeImage_GetScanLine(back, 0), bottom, width * 4) == 0);
    stbi_image_free(rgba);

    // 24 bits, premultiplied alpha, a rescale, and a PNG written and read again.
    FIBITMAP *rgb = FreeImage_ConvertTo24Bits(image);
    assert(rgb && FreeImage_GetBPP(rgb) == 24 && FreeImage_GetPitch(rgb) % 4 == 0);
    assert(FreeImage_PreMultiplyWithAlpha(image));
    FIBITMAP *small = FreeImage_Rescale(image, int(width / 4), int(height / 4), FILTER_LANCZOS3);
    assert(small && FreeImage_GetWidth(small) == width / 4);
    const std::string saved = dir + "/small.png";
    assert(FreeImage_Save(FIF_PNG, small, saved.c_str()));
    FIBITMAP *reloaded = FreeImage_Load(FreeImage_GetFileType(saved.c_str()), saved.c_str());
    assert(reloaded && FreeImage_GetHeight(reloaded) == height / 4);
    assert(!FreeImage_Save(FIF_WEBP, small, (dir + "/small.webp").c_str()));
    for (FIBITMAP *dib : {image, back, rgb, small, reloaded})
        FreeImage_Unload(dib);

    // A GIF as ES-DE plays one: opened from its FILE*, a frame locked, its time read.
    FreeImageIO io{read_proc, write_proc, seek_proc, tell_proc};
    std::FILE *file = std::fopen(gif.c_str(), "rb");
    assert(file);
    FIMULTIBITMAP *animation =
        FreeImage_OpenMultiBitmapFromHandle(FIF_GIF, &io, file, GIF_PLAYBACK);
    assert(animation && FreeImage_GetPageCount(animation) == 2);
    for (int page = 0; page < 2; page++)
    {
        FIBITMAP *frame = FreeImage_LockPage(animation, page);
        assert(frame);
        FITAG *tag = nullptr;
        assert(FreeImage_GetMetadata(FIMD_ANIMATION, frame, "FrameTime", &tag) && tag);
        assert(FreeImage_GetTagCount(tag) == 1 &&
               *static_cast<const uint32_t *>(FreeImage_GetTagValue(tag)) == 200);
        RGBQUAD pixel;
        assert(FreeImage_GetPixelColor(frame, 0, 0, &pixel));
        assert(page == 0 ? (pixel.rgbRed == 255 && pixel.rgbBlue == 0)
                         : (pixel.rgbBlue == 255 && pixel.rgbRed == 0));
        FreeImage_UnlockPage(animation, frame, FALSE);
    }
    FreeImage_CloseMultiBitmap(animation);
    // Opened again for the next frame: decoded once, kept.
    FIMULTIBITMAP *again = FreeImage_OpenMultiBitmapFromHandle(FIF_GIF, &io, file, GIF_PLAYBACK);
    assert(again && gif_cache.size() == 1 && FreeImage_GetPageCount(again) == 2);
    FreeImage_CloseMultiBitmap(again);
    std::fclose(file);
    FreeImage_DeInitialise();
    std::puts("esde_freeimage: layout, conversions, rescale, PNG save, GIF frames with times and "
              "WebP PASS");
    return 0;
}
