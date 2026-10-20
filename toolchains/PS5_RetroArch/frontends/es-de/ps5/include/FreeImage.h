/* PS5 RetroArch - the FreeImage API EmulationStation uses, over stb_image.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ES-DE 3.5.0 loads, converts, rescales and saves images through FreeImage: 36
 * functions in seven files (es-core's ImageIO and GIFAnimComponent, es-app's
 * MiximageGenerator, Scraper and main). FreeImage itself is a large tree of
 * bundled codecs that does not build with this compiler unpatched, so the port
 * provides those functions over stb_image, stb_image_write and stb_image_resize2
 * (frontends/es-de/ps5/freeimage_stb.cpp), with FreeImage's own memory layout,
 * which ES-DE relies on: rows bottom-up, 32-bit pixels as B, G, R, A bytes and
 * 24-bit ones as B, G, R, rows padded to four bytes. Reading covers PNG, JPEG,
 * GIF (with its frames and their times), BMP and TGA; WebP is reported as not
 * readable, as it is to a FreeImage built without it.
 */
#ifndef PS5_RETROARCH_ESDE_FREEIMAGE_H
#define PS5_RETROARCH_ESDE_FREEIMAGE_H

#include <stdint.h>

#ifdef __cplusplus
#define FI_DEFAULT(x) = x
extern "C" {
#else
#define FI_DEFAULT(x)
#endif

#define DLL_CALLCONV
#define DLL_API

typedef int32_t BOOL;
typedef uint8_t BYTE;
typedef uint16_t WORD;
typedef uint32_t DWORD;
#ifndef TRUE
#define TRUE 1
#define FALSE 0
#endif

typedef struct tagRGBQUAD
{
    BYTE rgbBlue;
    BYTE rgbGreen;
    BYTE rgbRed;
    BYTE rgbReserved;
} RGBQUAD;

typedef struct FIBITMAP FIBITMAP;
typedef struct FIMULTIBITMAP FIMULTIBITMAP;
typedef struct FIMEMORY FIMEMORY;
typedef struct FITAG FITAG;

typedef void *fi_handle;
typedef unsigned (*FI_ReadProc)(void *buffer, unsigned size, unsigned count, fi_handle handle);
typedef unsigned (*FI_WriteProc)(void *buffer, unsigned size, unsigned count, fi_handle handle);
typedef int (*FI_SeekProc)(fi_handle handle, long offset, int origin);
typedef long (*FI_TellProc)(fi_handle handle);

typedef struct FreeImageIO
{
    FI_ReadProc read_proc;
    FI_WriteProc write_proc;
    FI_SeekProc seek_proc;
    FI_TellProc tell_proc;
} FreeImageIO;

/* FreeImage's own values, so a value written down elsewhere means the same. */
typedef enum FREE_IMAGE_FORMAT
{
    FIF_UNKNOWN = -1,
    FIF_BMP = 0,
    FIF_JPEG = 2,
    FIF_PNG = 13,
    FIF_TARGA = 17,
    FIF_TIFF = 18,
    FIF_GIF = 25,
    FIF_WEBP = 35
} FREE_IMAGE_FORMAT;

typedef enum FREE_IMAGE_MDMODEL
{
    FIMD_NODATA = -1,
    FIMD_COMMENTS = 0,
    FIMD_ANIMATION = 9
} FREE_IMAGE_MDMODEL;

typedef enum FREE_IMAGE_FILTER
{
    FILTER_BOX = 0,
    FILTER_BICUBIC = 1,
    FILTER_BILINEAR = 2,
    FILTER_BSPLINE = 3,
    FILTER_CATMULLROM = 4,
    FILTER_LANCZOS3 = 5
} FREE_IMAGE_FILTER;

/* Little-endian FreeImage: the bytes of a pixel are blue, green, red, alpha. */
#define FI_RGBA_RED 2
#define FI_RGBA_GREEN 1
#define FI_RGBA_BLUE 0
#define FI_RGBA_ALPHA 3
#define FI_RGBA_RED_MASK 0x00FF0000
#define FI_RGBA_GREEN_MASK 0x0000FF00
#define FI_RGBA_BLUE_MASK 0x000000FF
#define FI_RGBA_ALPHA_MASK 0xFF000000

/* Load flags: a GIF opened with GIF_PLAYBACK gives each page as the full,
 * composited frame. */
#define GIF_DEFAULT 0
#define GIF_PLAYBACK 2
#define PNG_DEFAULT 0
#define JPEG_DEFAULT 0

void FreeImage_Initialise(BOOL load_local_plugins_only FI_DEFAULT(FALSE));
void FreeImage_DeInitialise(void);

FIMEMORY *FreeImage_OpenMemory(BYTE *data FI_DEFAULT(0), DWORD size_in_bytes FI_DEFAULT(0));
void FreeImage_CloseMemory(FIMEMORY *stream);

FREE_IMAGE_FORMAT FreeImage_GetFileType(const char *filename, int size FI_DEFAULT(0));
FREE_IMAGE_FORMAT FreeImage_GetFileTypeFromMemory(FIMEMORY *stream, int size FI_DEFAULT(0));
FREE_IMAGE_FORMAT FreeImage_GetFIFFromFilename(const char *filename);
BOOL FreeImage_FIFSupportsReading(FREE_IMAGE_FORMAT fif);

FIBITMAP *FreeImage_Load(FREE_IMAGE_FORMAT fif, const char *filename, int flags FI_DEFAULT(0));
FIBITMAP *FreeImage_LoadFromMemory(FREE_IMAGE_FORMAT fif, FIMEMORY *stream, int flags FI_DEFAULT(0));
BOOL FreeImage_Save(FREE_IMAGE_FORMAT fif, FIBITMAP *dib, const char *filename, int flags FI_DEFAULT(0));
void FreeImage_Unload(FIBITMAP *dib);

unsigned FreeImage_GetWidth(FIBITMAP *dib);
unsigned FreeImage_GetHeight(FIBITMAP *dib);
unsigned FreeImage_GetPitch(FIBITMAP *dib);
unsigned FreeImage_GetBPP(FIBITMAP *dib);
BYTE *FreeImage_GetScanLine(FIBITMAP *dib, int scanline);
BOOL FreeImage_GetPixelColor(FIBITMAP *dib, unsigned x, unsigned y, RGBQUAD *value);

FIBITMAP *FreeImage_ConvertTo24Bits(FIBITMAP *dib);
FIBITMAP *FreeImage_ConvertTo32Bits(FIBITMAP *dib);
BOOL FreeImage_PreMultiplyWithAlpha(FIBITMAP *dib);
void FreeImage_ConvertToRawBits(BYTE *bits, FIBITMAP *dib, int pitch, unsigned bpp, unsigned red_mask,
                                unsigned green_mask, unsigned blue_mask, BOOL topdown FI_DEFAULT(FALSE));
FIBITMAP *FreeImage_ConvertFromRawBits(BYTE *bits, int width, int height, int pitch, unsigned bpp,
                                       unsigned red_mask, unsigned green_mask, unsigned blue_mask,
                                       BOOL topdown FI_DEFAULT(FALSE));
FIBITMAP *FreeImage_Rescale(FIBITMAP *dib, int dst_width, int dst_height,
                            FREE_IMAGE_FILTER filter FI_DEFAULT(FILTER_CATMULLROM));

FIMULTIBITMAP *FreeImage_OpenMultiBitmapFromHandle(FREE_IMAGE_FORMAT fif, FreeImageIO *io, fi_handle handle,
                                                   int flags FI_DEFAULT(0));
BOOL FreeImage_CloseMultiBitmap(FIMULTIBITMAP *bitmap, int flags FI_DEFAULT(0));
int FreeImage_GetPageCount(FIMULTIBITMAP *bitmap);
FIBITMAP *FreeImage_LockPage(FIMULTIBITMAP *bitmap, int page);
void FreeImage_UnlockPage(FIMULTIBITMAP *bitmap, FIBITMAP *data, BOOL changed);

BOOL FreeImage_GetMetadata(FREE_IMAGE_MDMODEL model, FIBITMAP *dib, const char *key, FITAG **tag);
DWORD FreeImage_GetTagCount(FITAG *tag);
const void *FreeImage_GetTagValue(FITAG *tag);

#ifdef __cplusplus
}
#endif

#endif
