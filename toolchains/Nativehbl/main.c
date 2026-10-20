#include <SDL.h>
#include <SDL_image.h>
#include <SDL_mixer.h>
#include <SDL_ttf.h>
#include <SDL_test_font.h>
#include <jansson.h>

#include <dirent.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "gpl/hbldr.h"
#include "font_data.h"

#define WINDOW_W 1920
#define WINDOW_H 1080
#define LOGICAL_W WINDOW_W
#define LOGICAL_H WINDOW_H
#define REQUEST_PATH "/data/ps5_homebrew_launcher_request.txt"
#define SKINS_DIR "/data/nativehbl/skins"
#define SKIN_STATE_PATH "/data/nativehbl/skin.txt"
#define MAX_APPS 256
#define MAX_TEXT 256
#define MAX_PATH_LEN 1024
#define MAX_TEXT_CACHE 512
#define SCAN_MAX_DEPTH 8
#define MAX_SKINS 8

typedef struct HomebrewApp {
    char id[MAX_TEXT];
    char title[MAX_TEXT];
    char subtitle[MAX_TEXT];
    char description[MAX_TEXT];
    char version[64];
    char source[MAX_TEXT];
    char folder[MAX_PATH_LEN];
    char elf_path[MAX_PATH_LEN];
    char icon_path[MAX_PATH_LEN];
    SDL_Texture *icon;
} HomebrewApp;

typedef struct Theme Theme;

typedef struct AppState {
    SDL_Window *window;
    SDL_Renderer *renderer;
    SDL_GameController *controller;
    SDL_Joystick *joystick;
    Mix_Music *preview_music;
    HomebrewApp apps[MAX_APPS];
    int app_count;
    int selected;
    int running;
    int audio_ready;
    int preview_index;
    float carousel_pos;
    Uint32 last_ticks;
    char preview_path[MAX_PATH_LEN];
    char status[MAX_TEXT];
} AppState;

struct Theme {
    SDL_Color bg_top;
    SDL_Color bg_bottom;
    SDL_Color bg_grid;
    SDL_Color glow_a;
    SDL_Color glow_b;
    SDL_Color panel;
    SDL_Color panel_soft;
    SDL_Color panel_strong;
    SDL_Color border;
    SDL_Color border_active;
    SDL_Color text;
    SDL_Color text_soft;
    SDL_Color text_muted;
    SDL_Color accent;
    SDL_Color accent_alt;
    SDL_Color accent_soft;
    SDL_Color ps_cross;
    SDL_Color ps_circle;
    SDL_Color ps_square;
    SDL_Color ps_triangle;
    SDL_Color status_bg;
};

typedef struct SkinAssets {
    char id[64];
    char name[128];
    Theme theme;
} SkinAssets;

typedef struct BuiltInSkin {
    const char *id;
    const char *name;
    Theme theme;
} BuiltInSkin;

typedef struct TextCacheEntry {
    char text[MAX_TEXT];
    int scale;
    SDL_Texture *texture;
    int w;
    int h;
} TextCacheEntry;

typedef struct UIFontSet {
    int enabled;
    TTF_Font *scale1;
    TTF_Font *scale2;
    TTF_Font *scale3;
    TTF_Font *scale4;
    TextCacheEntry cache[MAX_TEXT_CACHE];
    int cache_count;
    SDL_Renderer *renderer;
} UIFontSet;

typedef enum ButtonGlyph {
    GLYPH_CROSS,
    GLYPH_CIRCLE,
    GLYPH_SQUARE,
    GLYPH_TRIANGLE,
    GLYPH_ARROW_LEFT,
    GLYPH_ARROW_RIGHT
} ButtonGlyph;

static const Theme g_theme_default = {
    {13, 16, 22, 255},
    {5, 8, 14, 255},
    {32, 40, 52, 255},
    {42, 112, 255, 32},
    {0, 222, 181, 24},
    {17, 22, 30, 226},
    {24, 30, 40, 208},
    {30, 37, 48, 238},
    {58, 72, 93, 255},
    {116, 210, 255, 255},
    {244, 247, 251, 255},
    {184, 196, 212, 255},
    {130, 144, 162, 255},
    {111, 227, 255, 255},
    {255, 186, 92, 255},
    {90, 193, 236, 72},
    {95, 173, 255, 255},
    {255, 106, 134, 255},
    {255, 128, 219, 255},
    {120, 255, 164, 255},
    {8, 12, 18, 210}
};

static const BuiltInSkin g_builtin_skins[] = {
    {
        "default_neon",
        "Default Neon",
        {
            {13, 16, 22, 255}, {5, 8, 14, 255}, {32, 40, 52, 255}, {42, 112, 255, 32}, {0, 222, 181, 24},
            {17, 22, 30, 226}, {24, 30, 40, 208}, {30, 37, 48, 238}, {58, 72, 93, 255}, {116, 210, 255, 255},
            {244, 247, 251, 255}, {184, 196, 212, 255}, {130, 144, 162, 255}, {111, 227, 255, 255}, {255, 186, 92, 255},
            {90, 193, 236, 72}, {95, 173, 255, 255}, {255, 106, 134, 255}, {255, 128, 219, 255}, {120, 255, 164, 255},
            {8, 12, 18, 210}
        }
    },
    {
        "sunset_cassette",
        "Sunset Cassette",
        {
            {40, 16, 26, 255}, {18, 6, 14, 255}, {78, 42, 56, 255}, {255, 120, 94, 36}, {255, 80, 160, 28},
            {36, 18, 28, 232}, {52, 26, 40, 212}, {66, 30, 50, 240}, {132, 74, 96, 255}, {255, 176, 114, 255},
            {255, 245, 238, 255}, {244, 199, 188, 255}, {196, 142, 141, 255}, {255, 125, 94, 255}, {255, 209, 102, 255},
            {255, 110, 168, 78}, {255, 136, 77, 255}, {255, 132, 159, 255}, {255, 182, 93, 255}, {118, 255, 210, 255},
            {18, 8, 16, 214}
        }
    },
    {
        "arctic_glass",
        "Arctic Glass",
        {
            {230, 238, 246, 255}, {188, 208, 224, 255}, {155, 178, 198, 255}, {120, 196, 255, 20}, {72, 244, 222, 24},
            {214, 226, 236, 224}, {196, 214, 226, 216}, {224, 236, 244, 240}, {120, 150, 176, 255}, {0, 143, 214, 255},
            {28, 44, 58, 255}, {52, 79, 98, 255}, {92, 112, 128, 255}, {0, 157, 224, 255}, {0, 204, 170, 255},
            {0, 143, 214, 54}, {43, 93, 255, 255}, {224, 80, 112, 255}, {255, 154, 70, 255}, {0, 196, 138, 255},
            {198, 214, 226, 210}
        }
    },
    {
        "matrix_terminal",
        "Matrix Terminal",
        {
            {6, 16, 8, 255}, {0, 6, 2, 255}, {18, 52, 24, 255}, {0, 255, 102, 22}, {0, 184, 76, 22},
            {8, 24, 12, 232}, {12, 34, 16, 214}, {12, 44, 18, 242}, {36, 128, 58, 255}, {68, 255, 116, 255},
            {203, 255, 212, 255}, {128, 224, 146, 255}, {82, 168, 98, 255}, {70, 255, 126, 255}, {163, 255, 74, 255},
            {40, 255, 104, 60}, {64, 255, 132, 255}, {255, 74, 136, 255}, {255, 208, 72, 255}, {118, 255, 164, 255},
            {0, 10, 2, 220}
        }
    },
    {
        "ember_noir",
        "Ember Noir",
        {
            {24, 20, 22, 255}, {6, 5, 6, 255}, {54, 40, 42, 255}, {255, 108, 42, 22}, {255, 204, 102, 16},
            {22, 18, 20, 232}, {32, 24, 26, 214}, {42, 28, 30, 242}, {110, 84, 72, 255}, {255, 130, 70, 255},
            {250, 236, 224, 255}, {210, 180, 158, 255}, {156, 128, 114, 255}, {255, 140, 88, 255}, {255, 212, 104, 255},
            {255, 134, 58, 66}, {104, 176, 255, 255}, {255, 104, 134, 255}, {255, 182, 78, 255}, {130, 230, 154, 255},
            {10, 8, 9, 220}
        }
    }
};

static UIFontSet g_fonts;
static SkinAssets g_skin;
static int g_skin_index;

static void launcher_log(const char *msg) {
    FILE *fp;

    if(!msg) {
        return;
    }

    fp = fopen("/data/ps5_homebrew_launcher.log", "a");
    if(!fp) {
        return;
    }

    fprintf(fp, "[ui] %s\n", msg);
    fclose(fp);
}

static void launcher_logf(const char *prefix, int value) {
    char buf[128];
    snprintf(buf, sizeof(buf), "%s%d", prefix, value);
    launcher_log(buf);
}

static void launcher_log_path(const char *prefix, const char *path) {
    char buf[1200];
    snprintf(buf, sizeof(buf), "%s%s", prefix ? prefix : "", path ? path : "(null)");
    launcher_log(buf);
}

#ifdef __PS5__
extern int sceSystemServiceHideSplashScreen(void);
#endif

static const char *g_scan_roots[] = {
    "/data/homebrew",
    "/mnt/usb0/homebrew",
    "/mnt/usb1/homebrew",
    "/mnt/ext0/homebrew",
    "/mnt/ext1/homebrew"
};

static const Theme *active_theme(void) {
    return g_skin.theme.text.a ? &g_skin.theme : &g_theme_default;
}

static void draw_text_scaled(SDL_Renderer *r, int x, int y, const char *text, SDL_Color color, int scale);
static int file_exists(const char *path);
static void copy_text(char *dst, size_t dst_size, const char *src);
static void measure_text(const char *text, int scale, int *w, int *h);
static void clear_text_cache(void);
static void update_preview_music(AppState *app, int force_reload);
static void stop_preview_music(AppState *app);
static void set_status(AppState *app, const char *text);
static const char *json_string_or(const json_t *obj, const char *key, const char *fallback);
static void cycle_skin(AppState *app, int direction);
static int path_is_dir(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static int path_is_regular(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static const char *path_basename_const(const char *path) {
    const char *slash;
    if(!path) {
        return "";
    }
    slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

static int file_has_elf_magic(const char *path) {
    unsigned char magic[4];
    FILE *fp;

    fp = fopen(path, "rb");
    if(!fp) {
        return 0;
    }
    if(fread(magic, 1, sizeof(magic), fp) != sizeof(magic)) {
        fclose(fp);
        return 0;
    }
    fclose(fp);
    return magic[0] == 0x7f && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F';
}

static int resolve_candidate(char *out, size_t out_size, const char *folder, const char **rels, int count) {
    int i;
    char path[MAX_PATH_LEN];

    for(i = 0; i < count; i++) {
        snprintf(path, sizeof(path), "%s/%s", folder, rels[i]);
        if(file_exists(path)) {
            copy_text(out, out_size, path);
            return 1;
        }
    }

    return 0;
}

static int resolve_folder_named_exec(char *out, size_t out_size, const char *folder) {
    char path[MAX_PATH_LEN];
    const char *base = path_basename_const(folder);

    if(!base[0]) {
        return 0;
    }

    snprintf(path, sizeof(path), "%s/%s", folder, base);
    if(path_is_regular(path) && file_has_elf_magic(path)) {
        copy_text(out, out_size, path);
        return 1;
    }

    return 0;
}

static int resolve_any_elf_in_folder(char *out, size_t out_size, const char *folder) {
    DIR *dir;
    struct dirent *ent;
    char path[MAX_PATH_LEN];

    dir = opendir(folder);
    if(!dir) {
        return 0;
    }

    while((ent = readdir(dir))) {
        if(ent->d_name[0] == '.') {
            continue;
        }
        if(strcmp(ent->d_name, "sce_sys") == 0) {
            continue;
        }
        snprintf(path, sizeof(path), "%s/%s", folder, ent->d_name);
        if(!path_is_regular(path)) {
            continue;
        }
        if(file_has_elf_magic(path)) {
            copy_text(out, out_size, path);
            closedir(dir);
            return 1;
        }
    }

    closedir(dir);
    return 0;
}

static int find_preview_music_path(const HomebrewApp *item, char *out, size_t out_size) {
    char path[MAX_PATH_LEN];
    static const char *candidates[] = {
        "sce_sys/sndgame.ogg",
        "sce_sys/snd0.ogg",
        "sndgame.ogg",
        "snd0.ogg"
    };
    int i;

    if(!item || !out || out_size == 0) {
        return 0;
    }

    out[0] = 0;
    for(i = 0; i < (int)(sizeof(candidates) / sizeof(candidates[0])); i++) {
        snprintf(path, sizeof(path), "%s/%s", item->folder, candidates[i]);
        if(file_exists(path)) {
            copy_text(out, out_size, path);
            return 1;
        }
    }
    return 0;
}

static void stop_preview_music(AppState *app) {
    if(!app) {
        return;
    }
    if(app->preview_music) {
        Mix_HaltMusic();
        Mix_FreeMusic(app->preview_music);
        app->preview_music = 0;
    }
    app->preview_path[0] = 0;
    app->preview_index = -1;
}

static void update_preview_music(AppState *app, int force_reload) {
    char path[MAX_PATH_LEN];

    if(!app || !app->audio_ready || app->app_count <= 0 || app->selected < 0 || app->selected >= app->app_count) {
        return;
    }

    if(!find_preview_music_path(&app->apps[app->selected], path, sizeof(path))) {
        stop_preview_music(app);
        return;
    }

    if(!force_reload &&
       app->preview_music &&
       app->preview_index == app->selected &&
       strcmp(app->preview_path, path) == 0) {
        return;
    }

    stop_preview_music(app);
    app->preview_music = Mix_LoadMUS(path);
    if(!app->preview_music) {
        launcher_log_path("preview music load failed: ", path);
        launcher_log(Mix_GetError());
        return;
    }
    if(Mix_PlayMusic(app->preview_music, -1) != 0) {
        launcher_log_path("preview music play failed: ", path);
        launcher_log(Mix_GetError());
        Mix_FreeMusic(app->preview_music);
        app->preview_music = 0;
        return;
    }
    Mix_VolumeMusic(MIX_MAX_VOLUME / 2);
    copy_text(app->preview_path, sizeof(app->preview_path), path);
    app->preview_index = app->selected;
    launcher_log_path("preview music playing: ", path);
}

static void destroy_skin_assets(void) {
    memset(&g_skin, 0, sizeof(g_skin));
}

static int parse_hex_color(const char *text, SDL_Color *out) {
    unsigned int value;
    size_t len;

    if(!text || !out) {
        return 0;
    }
    if(text[0] == '#') {
        text++;
    }
    len = strlen(text);
    if(len != 6 && len != 8) {
        return 0;
    }
    if(sscanf(text, "%x", &value) != 1) {
        return 0;
    }
    if(len == 6) {
        out->r = (value >> 16) & 0xff;
        out->g = (value >> 8) & 0xff;
        out->b = value & 0xff;
        out->a = 255;
    } else {
        out->r = (value >> 24) & 0xff;
        out->g = (value >> 16) & 0xff;
        out->b = (value >> 8) & 0xff;
        out->a = value & 0xff;
    }
    return 1;
}

static void skin_set_color(json_t *colors, const char *key, SDL_Color *dst) {
    json_t *value = json_object_get(colors, key);
    SDL_Color parsed;
    if(json_is_string(value) && parse_hex_color(json_string_value(value), &parsed)) {
        *dst = parsed;
    }
}

static void apply_skin_manifest_override(const char *id) {
    char manifest_path[MAX_PATH_LEN];
    json_error_t err;
    json_t *root;
    json_t *colors;

    snprintf(manifest_path, sizeof(manifest_path), "%s/%s/manifest.json", SKINS_DIR, id);
    if(!file_exists(manifest_path)) {
        return;
    }

    root = json_load_file(manifest_path, 0, &err);
    if(!root) {
        launcher_log_path("skin manifest invalid: ", manifest_path);
        return;
    }

    copy_text(g_skin.name, sizeof(g_skin.name), json_string_or(root, "name", g_skin.name));
    colors = json_object_get(root, "colors");
    if(json_is_object(colors)) {
        skin_set_color(colors, "bg_top", &g_skin.theme.bg_top);
        skin_set_color(colors, "bg_bottom", &g_skin.theme.bg_bottom);
        skin_set_color(colors, "bg_grid", &g_skin.theme.bg_grid);
        skin_set_color(colors, "glow_a", &g_skin.theme.glow_a);
        skin_set_color(colors, "glow_b", &g_skin.theme.glow_b);
        skin_set_color(colors, "panel", &g_skin.theme.panel);
        skin_set_color(colors, "panel_soft", &g_skin.theme.panel_soft);
        skin_set_color(colors, "panel_strong", &g_skin.theme.panel_strong);
        skin_set_color(colors, "border", &g_skin.theme.border);
        skin_set_color(colors, "border_active", &g_skin.theme.border_active);
        skin_set_color(colors, "text", &g_skin.theme.text);
        skin_set_color(colors, "text_soft", &g_skin.theme.text_soft);
        skin_set_color(colors, "text_muted", &g_skin.theme.text_muted);
        skin_set_color(colors, "accent", &g_skin.theme.accent);
        skin_set_color(colors, "accent_alt", &g_skin.theme.accent_alt);
        skin_set_color(colors, "accent_soft", &g_skin.theme.accent_soft);
        skin_set_color(colors, "ps_cross", &g_skin.theme.ps_cross);
        skin_set_color(colors, "ps_circle", &g_skin.theme.ps_circle);
        skin_set_color(colors, "ps_square", &g_skin.theme.ps_square);
        skin_set_color(colors, "ps_triangle", &g_skin.theme.ps_triangle);
        skin_set_color(colors, "status_bg", &g_skin.theme.status_bg);
    }
    json_decref(root);
    launcher_log_path("skin manifest loaded: ", manifest_path);
}

static void save_skin_selection(void) {
    FILE *fp = fopen(SKIN_STATE_PATH, "w");
    if(!fp) {
        return;
    }
    fprintf(fp, "%s\n", g_skin.id);
    fclose(fp);
}

static void apply_skin_index(int index) {
    const BuiltInSkin *skin;

    if(index < 0 || index >= (int)(sizeof(g_builtin_skins) / sizeof(g_builtin_skins[0]))) {
        index = 0;
    }
    g_skin_index = index;
    skin = &g_builtin_skins[g_skin_index];
    destroy_skin_assets();
    copy_text(g_skin.id, sizeof(g_skin.id), skin->id);
    copy_text(g_skin.name, sizeof(g_skin.name), skin->name);
    g_skin.theme = skin->theme;
    apply_skin_manifest_override(g_skin.id);
    launcher_log_path("theme applied: ", g_skin.name);
}

static void load_skin_selection(void) {
    FILE *fp;
    char line[128];
    int i;

    fp = fopen(SKIN_STATE_PATH, "r");
    if(!fp) {
        apply_skin_index(0);
        return;
    }
    if(!fgets(line, sizeof(line), fp)) {
        fclose(fp);
        apply_skin_index(0);
        return;
    }
    fclose(fp);
    line[strcspn(line, "\r\n")] = 0;
    for(i = 0; i < (int)(sizeof(g_builtin_skins) / sizeof(g_builtin_skins[0])); i++) {
        if(strcmp(g_builtin_skins[i].id, line) == 0) {
            apply_skin_index(i);
            return;
        }
    }
    apply_skin_index(0);
}

static void cycle_skin(AppState *app, int direction) {
    int skin_count = (int)(sizeof(g_builtin_skins) / sizeof(g_builtin_skins[0]));
    char status[160];

    g_skin_index += direction;
    if(g_skin_index < 0) {
        g_skin_index = skin_count - 1;
    } else if(g_skin_index >= skin_count) {
        g_skin_index = 0;
    }
    apply_skin_index(g_skin_index);
    clear_text_cache();
    save_skin_selection();
    snprintf(status, sizeof(status), "Skin: %s", g_skin.name);
    set_status(app, status);
}

static TTF_Font *font_for_scale(int scale) {
    switch(scale) {
        case 4: return g_fonts.scale4;
        case 3: return g_fonts.scale3;
        case 2: return g_fonts.scale2;
        default: return g_fonts.scale1;
    }
}

static void clear_text_cache(void) {
    int i;
    for(i = 0; i < g_fonts.cache_count; i++) {
        if(g_fonts.cache[i].texture) {
            SDL_DestroyTexture(g_fonts.cache[i].texture);
        }
    }
    memset(g_fonts.cache, 0, sizeof(g_fonts.cache));
    g_fonts.cache_count = 0;
}

static void shutdown_fonts(void) {
    clear_text_cache();
    if(g_fonts.scale1) TTF_CloseFont(g_fonts.scale1);
    if(g_fonts.scale2) TTF_CloseFont(g_fonts.scale2);
    if(g_fonts.scale3) TTF_CloseFont(g_fonts.scale3);
    if(g_fonts.scale4) TTF_CloseFont(g_fonts.scale4);
    memset(&g_fonts, 0, sizeof(g_fonts));
    if(TTF_WasInit()) {
        TTF_Quit();
    }
}

static int init_fonts(SDL_Renderer *renderer) {
    SDL_RWops *rw;
    if(TTF_Init() != 0) {
        launcher_log("TTF_Init failed, using SDL_test_font fallback");
        return 0;
    }

    rw = SDL_RWFromConstMem(
        ps5_homebrew_launcher_assets_fonts_NotoSansDisplay_Regular_ttf,
        (int)ps5_homebrew_launcher_assets_fonts_NotoSansDisplay_Regular_ttf_len
    );
    if(!rw) {
        launcher_log("SDL_RWFromConstMem font failed");
        return 0;
    }

    g_fonts.scale1 = TTF_OpenFontRW(rw, 0, 20);
    if(!g_fonts.scale1) {
        SDL_RWclose(rw);
        launcher_log("TTF_OpenFontRW scale1 failed");
        return 0;
    }
    g_fonts.scale2 = TTF_OpenFontRW(SDL_RWFromConstMem(ps5_homebrew_launcher_assets_fonts_NotoSansDisplay_Regular_ttf,
                                                       (int)ps5_homebrew_launcher_assets_fonts_NotoSansDisplay_Regular_ttf_len), 1, 32);
    g_fonts.scale3 = TTF_OpenFontRW(SDL_RWFromConstMem(ps5_homebrew_launcher_assets_fonts_NotoSansDisplay_Regular_ttf,
                                                       (int)ps5_homebrew_launcher_assets_fonts_NotoSansDisplay_Regular_ttf_len), 1, 48);
    g_fonts.scale4 = TTF_OpenFontRW(SDL_RWFromConstMem(ps5_homebrew_launcher_assets_fonts_NotoSansDisplay_Regular_ttf,
                                                       (int)ps5_homebrew_launcher_assets_fonts_NotoSansDisplay_Regular_ttf_len), 1, 68);
    if(!g_fonts.scale2 || !g_fonts.scale3 || !g_fonts.scale4) {
        launcher_log("TTF_OpenFontRW additional scales failed");
        shutdown_fonts();
        return 0;
    }

    TTF_SetFontHinting(g_fonts.scale1, TTF_HINTING_LIGHT);
    TTF_SetFontHinting(g_fonts.scale2, TTF_HINTING_LIGHT);
    TTF_SetFontHinting(g_fonts.scale3, TTF_HINTING_LIGHT);
    TTF_SetFontHinting(g_fonts.scale4, TTF_HINTING_LIGHT);
    g_fonts.enabled = 1;
    g_fonts.renderer = renderer;
    launcher_log("TTF font initialized");
    return 1;
}

static TextCacheEntry *find_cached_text(const char *text, int scale) {
    int i;
    for(i = 0; i < g_fonts.cache_count; i++) {
        if(g_fonts.cache[i].scale == scale && strcmp(g_fonts.cache[i].text, text) == 0) {
            return &g_fonts.cache[i];
        }
    }
    return 0;
}

static TextCacheEntry *create_cached_text(const char *text, int scale) {
    TextCacheEntry *entry;
    SDL_Surface *surface;
    TTF_Font *font;
    if(!g_fonts.enabled || !text || !text[0] || g_fonts.cache_count >= MAX_TEXT_CACHE) {
        return 0;
    }

    font = font_for_scale(scale);
    if(!font) {
        return 0;
    }

    surface = TTF_RenderUTF8_Blended(font, text, (SDL_Color){255, 255, 255, 255});
    if(!surface) {
        return 0;
    }

    entry = &g_fonts.cache[g_fonts.cache_count++];
    memset(entry, 0, sizeof(*entry));
    copy_text(entry->text, sizeof(entry->text), text);
    entry->scale = scale;
    entry->texture = SDL_CreateTextureFromSurface(g_fonts.renderer, surface);
    entry->w = surface->w;
    entry->h = surface->h;
    SDL_FreeSurface(surface);
    if(!entry->texture) {
        memset(entry, 0, sizeof(*entry));
        g_fonts.cache_count--;
        return 0;
    }

    SDL_SetTextureBlendMode(entry->texture, SDL_BLENDMODE_BLEND);
    return entry;
}

static void measure_text(const char *text, int scale, int *w, int *h) {
    TTF_Font *font;
    int mw = 0;
    int mh = 0;

    if(!text || !text[0]) {
        if(w) *w = 0;
        if(h) *h = 0;
        return;
    }

    if(g_fonts.enabled) {
        TextCacheEntry *entry = find_cached_text(text, scale);
        if(!entry) {
            entry = create_cached_text(text, scale);
        }
        if(entry) {
            mw = entry->w;
            mh = entry->h;
        } else {
            font = font_for_scale(scale);
            if(font) {
                TTF_SizeUTF8(font, text, &mw, &mh);
            }
        }
    }

    if(mw <= 0) {
        mw = (int)strlen(text) * 8 * scale;
        mh = 10 * scale;
    }

    if(w) *w = mw;
    if(h) *h = mh;
}

static void text_copy_clamped_px(char *dst, size_t dst_size, const char *src, int scale, int max_width) {
    int len;
    int w = 0;
    int h = 0;

    if(!dst || dst_size == 0) {
        return;
    }
    if(!src) {
        dst[0] = 0;
        return;
    }

    copy_text(dst, dst_size, src);
    measure_text(dst, scale, &w, &h);
    if(w <= max_width) {
        return;
    }

    len = (int)strlen(src);
    while(len > 1) {
        snprintf(dst, dst_size, "%.*s...", len, src);
        measure_text(dst, scale, &w, &h);
        if(w <= max_width) {
            return;
        }
        len--;
    }

    copy_text(dst, dst_size, "...");
}

static float clampf(float v, float lo, float hi) {
    if(v < lo) return lo;
    if(v > hi) return hi;
    return v;
}

static float lerpf(float a, float b, float t) {
    return a + (b - a) * t;
}

static int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

static void set_status(AppState *app, const char *text) {
    snprintf(app->status, sizeof(app->status), "%s", text ? text : "");
}

static const char *json_string_or(const json_t *obj, const char *key, const char *fallback) {
    json_t *val = json_object_get((json_t *)obj, key);
    if(json_is_string(val)) {
        return json_string_value(val);
    }
    return fallback;
}

static void copy_text(char *dst, size_t dst_size, const char *src) {
    snprintf(dst, dst_size, "%s", src ? src : "");
}

static int app_already_added(const AppState *app, const char *folder) {
    int i;
    for(i = 0; i < app->app_count; i++) {
        if(strcmp(app->apps[i].folder, folder) == 0) {
            return 1;
        }
    }
    return 0;
}

static int resolve_homebrew_paths(const char *folder, char *exec_path, size_t exec_size, char *icon_path, size_t icon_size, char *param_path, size_t param_size) {
    static const char *exec_candidates[] = {
        "eboot.elf",
        "eboot",
        "eboot.bin",
        "homebrew.elf",
        "homebrew.bin",
        "homebrew"
    };
    static const char *icon_candidates[] = {
        "sce_sys/icon0.png",
        "sce_sys/icon0.PNG",
        "icon0.png",
        "ICON0.PNG"
    };
    static const char *param_candidates[] = {
        "sce_sys/param.json",
        "sce_sys/param.JSON"
    };

    exec_path[0] = 0;
    icon_path[0] = 0;
    param_path[0] = 0;

    if(!resolve_candidate(exec_path, exec_size, folder, exec_candidates, (int)(sizeof(exec_candidates) / sizeof(exec_candidates[0])))
       && !resolve_folder_named_exec(exec_path, exec_size, folder)
       && !resolve_any_elf_in_folder(exec_path, exec_size, folder)) {
        return 0;
    }

    resolve_candidate(icon_path, icon_size, folder, icon_candidates, (int)(sizeof(icon_candidates) / sizeof(icon_candidates[0])));
    resolve_candidate(param_path, param_size, folder, param_candidates, (int)(sizeof(param_candidates) / sizeof(param_candidates[0])));
    return 1;
}

static void add_app(AppState *app, const char *folder, const char *source_name) {
    json_error_t err;
    char param_path[MAX_PATH_LEN];
    char icon_path[MAX_PATH_LEN];
    char elf_path[MAX_PATH_LEN];
    json_t *root;
    json_t *localized;
    const char *lang;
    const char *title = 0;
    const char *subtitle = 0;
    const char *version = 0;
    const char *title_id = 0;
    HomebrewApp *item;

    if(app->app_count >= MAX_APPS) {
        launcher_log("add_app skipped: MAX_APPS reached");
        return;
    }

    if(app_already_added(app, folder)) {
        launcher_log_path("add_app skipped duplicate: ", folder);
        return;
    }

    if(!resolve_homebrew_paths(folder, elf_path, sizeof(elf_path), icon_path, sizeof(icon_path), param_path, sizeof(param_path))) {
        launcher_log_path("add_app skipped no executable: ", folder);
        return;
    }

    root = param_path[0] ? json_load_file(param_path, 0, &err) : 0;
    item = &app->apps[app->app_count];
    memset(item, 0, sizeof(*item));

    copy_text(item->folder, sizeof(item->folder), folder);
    copy_text(item->elf_path, sizeof(item->elf_path), elf_path);
    copy_text(item->icon_path, sizeof(item->icon_path), icon_path);
    copy_text(item->source, sizeof(item->source), source_name);
    launcher_log_path("add_app accepted: ", folder);
    launcher_log_path("  exec: ", elf_path);
    if(param_path[0]) {
        launcher_log_path("  param: ", param_path);
    } else {
        launcher_log("  param: (missing)");
    }
    if(icon_path[0]) {
        launcher_log_path("  icon: ", icon_path);
    } else {
        launcher_log("  icon: (missing)");
    }

    if(root) {
        localized = json_object_get(root, "localizedParameters");
        lang = json_string_or(localized, "defaultLanguage", "en-US");
        if(json_is_object(localized)) {
            json_t *entry = json_object_get(localized, lang);
            if(json_is_object(entry)) {
                title = json_string_or(entry, "titleName", 0);
                subtitle = json_string_or(entry, "subTitle", 0);
            }
        }

        version = json_string_or(root, "contentVersion", "");
        title_id = json_string_or(root, "titleId", "");

        copy_text(item->id, sizeof(item->id), title_id && title_id[0] ? title_id : "HOMEBREW");
        copy_text(item->title, sizeof(item->title), title && title[0] ? title : strrchr(folder, '/') ? strrchr(folder, '/') + 1 : folder);
        copy_text(item->subtitle, sizeof(item->subtitle), subtitle && subtitle[0] ? subtitle : "Native PS5 homebrew");
        copy_text(item->version, sizeof(item->version), version);
        copy_text(item->description, sizeof(item->description), json_string_or(root, "contentId", "Ready to launch from the native SDL2 frontend."));
        json_decref(root);
    } else {
        copy_text(item->id, sizeof(item->id), "HOMEBREW");
        copy_text(item->title, sizeof(item->title), strrchr(folder, '/') ? strrchr(folder, '/') + 1 : folder);
        copy_text(item->subtitle, sizeof(item->subtitle), "Missing param.json");
        copy_text(item->description, sizeof(item->description), "This title has no sce_sys/param.json yet, but the ELF exists and can be indexed.");
    }

    app->app_count++;
}

static void scan_root_recursive(AppState *app, const char *root, const char *source_name, int depth) {
    DIR *dir = opendir(root);
    struct dirent *ent;
    char folder[MAX_PATH_LEN];
    char exec_path[MAX_PATH_LEN];
    char icon_path[MAX_PATH_LEN];
    char param_path[MAX_PATH_LEN];

    if(!dir || depth < 0) {
        if(depth < 0) {
            launcher_log_path("scan depth limit reached at: ", root);
        } else {
            launcher_log_path("scan opendir failed: ", root);
        }
        return;
    }

    launcher_log_path("scan enter: ", root);

    while((ent = readdir(dir))) {
        if(ent->d_name[0] == '.') {
            continue;
        }
        snprintf(folder, sizeof(folder), "%s/%s", root, ent->d_name);
        if(!path_is_dir(folder)) {
            continue;
        }
        launcher_log_path("scan dir: ", folder);
        if(resolve_homebrew_paths(folder, exec_path, sizeof(exec_path), icon_path, sizeof(icon_path), param_path, sizeof(param_path))) {
            launcher_log_path("scan candidate hit: ", folder);
            add_app(app, folder, source_name);
            continue;
        }
        launcher_log_path("scan recurse: ", folder);
        if(depth > 0) {
            scan_root_recursive(app, folder, source_name, depth - 1);
        }
    }

    closedir(dir);
    launcher_log_path("scan leave: ", root);
}

static SDL_Texture *load_icon(SDL_Renderer *renderer, const char *path) {
    if(!file_exists(path)) {
        return 0;
    }
    return IMG_LoadTexture(renderer, path);
}

static SDL_Rect fit_rect(SDL_Texture *tex, int x, int y, int w, int h) {
    SDL_Rect dst = {x, y, w, h};
    int tw = 0;
    int th = 0;

    if(tex && SDL_QueryTexture(tex, 0, 0, &tw, &th) == 0 && tw > 0 && th > 0) {
        float scale_x = (float)w / (float)tw;
        float scale_y = (float)h / (float)th;
        float scale = scale_x < scale_y ? scale_x : scale_y;
        int rw = (int)(tw * scale);
        int rh = (int)(th * scale);
        dst.w = rw;
        dst.h = rh;
        dst.x = x + (w - rw) / 2;
        dst.y = y + (h - rh) / 2;
    }

    return dst;
}

static int init_app(AppState *app) {
    int i;
    memset(app, 0, sizeof(*app));
    app->running = 1;
    app->selected = 0;
    app->preview_index = -1;
    app->carousel_pos = 0.0f;
    launcher_log("init_app start");

    putenv("SDL_VIDEODRIVER=ps5");
    SDL_SetHint("SDL_VIDEODRIVER", "ps5");
    launcher_log("SDL_VIDEODRIVER=ps5");

    if(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER | SDL_INIT_JOYSTICK | SDL_INIT_EVENTS) != 0) {
        launcher_log("SDL_Init failed");
        return -1;
    }
    launcher_log("SDL_Init ok");
    SDL_JoystickEventState(SDL_ENABLE);
    launcher_logf("SDL_NumJoysticks=", SDL_NumJoysticks());
    if((IMG_Init(IMG_INIT_PNG) & IMG_INIT_PNG) == 0) {
        launcher_log("IMG_Init failed");
        return -1;
    }
    launcher_log("IMG_Init ok");

    app->window = SDL_CreateWindow(
        "PS5 Homebrew Launcher",
        SDL_WINDOWPOS_UNDEFINED,
        SDL_WINDOWPOS_UNDEFINED,
        WINDOW_W,
        WINDOW_H,
        SDL_WINDOW_FULLSCREEN
    );
    if(!app->window) {
        launcher_log("SDL_CreateWindow failed");
        return -1;
    }
    launcher_log("SDL_CreateWindow ok");

#ifdef __PS5__
    sceSystemServiceHideSplashScreen();
    launcher_log("sceSystemServiceHideSplashScreen called");
#endif

    app->renderer = SDL_CreateRenderer(app->window, -1, SDL_RENDERER_SOFTWARE | SDL_RENDERER_TARGETTEXTURE);
    if(app->renderer) {
        launcher_log("SDL_CreateRenderer ok software+targettexture");
    } else {
        launcher_log("SDL_CreateRenderer failed software+targettexture");
        app->renderer = SDL_CreateRenderer(app->window, -1, SDL_RENDERER_SOFTWARE | SDL_RENDERER_PRESENTVSYNC);
        if(app->renderer) {
            launcher_log("SDL_CreateRenderer ok software+vsync");
        } else {
            launcher_log("SDL_CreateRenderer failed software+vsync");
            app->renderer = SDL_CreateRenderer(app->window, -1, SDL_RENDERER_SOFTWARE);
            if(app->renderer) {
                launcher_log("SDL_CreateRenderer ok software");
            } else {
                launcher_log("SDL_CreateRenderer failed software");
                return -1;
            }
        }
    }

    SDL_SetRenderDrawBlendMode(app->renderer, SDL_BLENDMODE_BLEND);
    load_skin_selection();
    init_fonts(app->renderer);
    if((Mix_Init(MIX_INIT_OGG) & MIX_INIT_OGG) != 0 &&
       Mix_OpenAudio(48000, MIX_DEFAULT_FORMAT, 2, 4096) == 0) {
        app->audio_ready = 1;
        launcher_log("Mix_OpenAudio ok");
    } else {
        launcher_log("Mix audio init failed");
        launcher_log(Mix_GetError());
    }
    for(i = 0; i < SDL_NumJoysticks(); i++) {
        if(SDL_IsGameController(i)) {
            app->controller = SDL_GameControllerOpen(i);
            if(app->controller) {
                launcher_log("SDL_GameControllerOpen ok");
                break;
            }
        }
    }
    if(!app->controller) {
        launcher_log("SDL_GameControllerOpen not found");
    }
    if(SDL_NumJoysticks() > 0) {
        app->joystick = SDL_JoystickOpen(0);
        if(app->joystick) {
            launcher_log("SDL_JoystickOpen ok");
        } else {
            launcher_log("SDL_JoystickOpen failed");
        }
    }
    set_status(app, "Scanning homebrew locations...");
    launcher_log("init_app done");

    return 0;
}

static void load_homebrew(AppState *app) {
    int i;
    char buf[128];

    clear_text_cache();
    app->app_count = 0;
    for(i = 0; i < (int)(sizeof(g_scan_roots) / sizeof(g_scan_roots[0])); i++) {
        scan_root_recursive(app, g_scan_roots[i], g_scan_roots[i], SCAN_MAX_DEPTH);
    }

    for(i = 0; i < app->app_count; i++) {
        app->apps[i].icon = load_icon(app->renderer, app->apps[i].icon_path);
    }

    if(app->app_count > 0) {
        set_status(app, "Cross launch, Square refresh, Triangle skin");
        if(app->selected >= app->app_count) {
            app->selected = app->app_count - 1;
        }
        if(app->selected < 0) {
            app->selected = 0;
        }
        update_preview_music(app, 1);
    } else {
        set_status(app, "No homebrew found in /data/homebrew or mounted devices");
        stop_preview_music(app);
    }
    snprintf(buf, sizeof(buf), "load_homebrew count=%d", app->app_count);
    launcher_log(buf);
}

static void draw_rect(SDL_Renderer *r, int x, int y, int w, int h, SDL_Color c) {
    SDL_Rect rect = {x, y, w, h};
    SDL_SetRenderDrawColor(r, c.r, c.g, c.b, c.a);
    SDL_RenderFillRect(r, &rect);
}

static SDL_Rect rect_hero_panel(void) {
    SDL_Rect rect = {80, 188, 1180, 560};
    return rect;
}

static SDL_Rect rect_hero_art(void) {
    SDL_Rect rect = {112, 222, 430, 430};
    return rect;
}

static SDL_Rect rect_sidebar_panel(void) {
    SDL_Rect rect = {1290, 188, 550, 560};
    return rect;
}

static SDL_Rect rect_rail_panel(void) {
    SDL_Rect rect = {80, 786, 1760, 220};
    return rect;
}

static SDL_Rect rect_rail_cards_clip(void) {
    SDL_Rect rect = {98, 834, 1588, 154};
    return rect;
}

static void draw_rect_alpha(SDL_Renderer *r, SDL_Rect rect, SDL_Color c) {
    SDL_SetRenderDrawColor(r, c.r, c.g, c.b, c.a);
    SDL_RenderFillRect(r, &rect);
}

static void draw_outline(SDL_Renderer *r, int x, int y, int w, int h, SDL_Color c) {
    SDL_Rect rect = {x, y, w, h};
    SDL_SetRenderDrawColor(r, c.r, c.g, c.b, c.a);
    SDL_RenderDrawRect(r, &rect);
}

static void draw_frame(SDL_Renderer *r, SDL_Rect rect, SDL_Color fill, SDL_Color border) {
    draw_rect_alpha(r, rect, fill);
    SDL_SetRenderDrawColor(r, border.r, border.g, border.b, border.a);
    SDL_RenderDrawRect(r, &rect);
}

static void draw_shadow(SDL_Renderer *r, SDL_Rect rect, SDL_Color color, int spread, int layers) {
    int i;
    for(i = layers; i >= 1; i--) {
        SDL_Rect layer = {
            rect.x - spread * i,
            rect.y - spread * i,
            rect.w + spread * i * 2,
            rect.h + spread * i * 2
        };
        SDL_Color c = color;
        c.a = (Uint8)(color.a / (i + 1));
        draw_rect_alpha(r, layer, c);
    }
}

static void draw_chip(SDL_Renderer *r, int x, int y, int w, const char *text, SDL_Color bg, SDL_Color fg) {
    SDL_Rect rect = {x, y, w, 34};
    char clipped[128];
    draw_frame(r, rect, bg, (SDL_Color){bg.r, bg.g, bg.b, 255});
    text_copy_clamped_px(clipped, sizeof(clipped), text, 1, w - 24);
    draw_text_scaled(r, x + 12, y + 10, clipped, fg, 1);
}

static int chip_width_for_text(const char *text, int min_w) {
    int tw = 0;
    int th = 0;
    measure_text(text, 1, &tw, &th);
    tw += 24;
    return tw > min_w ? tw : min_w;
}

static SDL_Color glyph_color(ButtonGlyph glyph) {
    const Theme *theme = active_theme();
    switch(glyph) {
        case GLYPH_CROSS: return theme->ps_cross;
        case GLYPH_CIRCLE: return theme->ps_circle;
        case GLYPH_SQUARE: return theme->ps_square;
        case GLYPH_TRIANGLE: return theme->ps_triangle;
        case GLYPH_ARROW_LEFT:
        case GLYPH_ARROW_RIGHT:
        default: return theme->accent;
    }
}

static void draw_circle_outline(SDL_Renderer *r, int cx, int cy, int radius, SDL_Color color) {
    int x = radius;
    int y = 0;
    int err = 0;

    SDL_SetRenderDrawColor(r, color.r, color.g, color.b, color.a);
    while(x >= y) {
        SDL_RenderDrawPoint(r, cx + x, cy + y);
        SDL_RenderDrawPoint(r, cx + y, cy + x);
        SDL_RenderDrawPoint(r, cx - y, cy + x);
        SDL_RenderDrawPoint(r, cx - x, cy + y);
        SDL_RenderDrawPoint(r, cx - x, cy - y);
        SDL_RenderDrawPoint(r, cx - y, cy - x);
        SDL_RenderDrawPoint(r, cx + y, cy - x);
        SDL_RenderDrawPoint(r, cx + x, cy - y);

        y++;
        if(err <= 0) {
            err += 2 * y + 1;
        }
        if(err > 0) {
            x--;
            err -= 2 * x + 1;
        }
    }
}

static void draw_line_thick(SDL_Renderer *r, int x1, int y1, int x2, int y2, SDL_Color color, int thickness) {
    int i;
    SDL_SetRenderDrawColor(r, color.r, color.g, color.b, color.a);
    for(i = -thickness / 2; i <= thickness / 2; i++) {
        SDL_RenderDrawLine(r, x1 + i, y1, x2 + i, y2);
        SDL_RenderDrawLine(r, x1, y1 + i, x2, y2 + i);
    }
}

static void draw_button_glyph(SDL_Renderer *r, SDL_Rect rect, ButtonGlyph glyph, SDL_Color color) {
    int cx = rect.x + rect.w / 2;
    int cy = rect.y + rect.h / 2;
    int pad = rect.w < rect.h ? rect.w / 4 : rect.h / 4;
    int left = rect.x + pad;
    int right = rect.x + rect.w - pad;
    int top = rect.y + pad;
    int bottom = rect.y + rect.h - pad;

    switch(glyph) {
        case GLYPH_CROSS:
            draw_line_thick(r, left, top, right, bottom, color, 2);
            draw_line_thick(r, right, top, left, bottom, color, 2);
            break;
        case GLYPH_CIRCLE:
            draw_circle_outline(r, cx, cy, (rect.w < rect.h ? rect.w : rect.h) / 2 - pad / 2, color);
            draw_circle_outline(r, cx, cy, (rect.w < rect.h ? rect.w : rect.h) / 2 - pad / 2 - 1, color);
            break;
        case GLYPH_SQUARE: {
            SDL_Rect sq = {left, top, right - left, bottom - top};
            SDL_SetRenderDrawColor(r, color.r, color.g, color.b, color.a);
            SDL_RenderDrawRect(r, &sq);
            sq.x += 1;
            sq.y += 1;
            sq.w -= 2;
            sq.h -= 2;
            SDL_RenderDrawRect(r, &sq);
            break;
        }
        case GLYPH_TRIANGLE:
            draw_line_thick(r, cx, top, left, bottom, color, 2);
            draw_line_thick(r, cx, top, right, bottom, color, 2);
            draw_line_thick(r, left, bottom, right, bottom, color, 2);
            break;
        case GLYPH_ARROW_LEFT:
            draw_line_thick(r, right, top, left, cy, color, 2);
            draw_line_thick(r, left, cy, right, bottom, color, 2);
            break;
        case GLYPH_ARROW_RIGHT:
            draw_line_thick(r, left, top, right, cy, color, 2);
            draw_line_thick(r, right, cy, left, bottom, color, 2);
            break;
    }
}

static void draw_control_chip(SDL_Renderer *r, int x, int y, int w, ButtonGlyph glyph, const char *action) {
    const Theme *theme = active_theme();
    SDL_Color icon = glyph_color(glyph);
    SDL_Rect rect = {x, y, w, 40};
    SDL_Rect button_rect = {x + 8, y + 5, 30, 30};
    SDL_Rect glow_rect = {button_rect.x - 4, button_rect.y - 4, button_rect.w + 8, button_rect.h + 8};
    char clipped[96];
    draw_frame(r, rect, theme->panel_soft, theme->border);
    draw_rect_alpha(r, glow_rect, (SDL_Color){icon.r, icon.g, icon.b, 28});
    draw_frame(r, button_rect, (SDL_Color){18, 24, 34, 255}, (SDL_Color){icon.r, icon.g, icon.b, 190});
    draw_button_glyph(r, button_rect, glyph, icon);
    if(action && action[0]) {
        text_copy_clamped_px(clipped, sizeof(clipped), action, 1, w - 60);
        draw_text_scaled(r, x + 52, y + 13, clipped, theme->text_soft, 1);
    }
}

static int control_chip_width(const char *action) {
    int tw = 0;
    int th = 0;
    if(action && action[0]) {
        measure_text(action, 1, &tw, &th);
        return 52 + tw + 16;
    }
    return 46;
}

static void draw_text_right(SDL_Renderer *r, int right_x, int y, const char *text, SDL_Color color, int scale) {
    int tw = 0;
    int th = 0;
    if(!text || !text[0]) {
        return;
    }
    measure_text(text, scale, &tw, &th);
    draw_text_scaled(r, right_x - tw, y, text, color, scale);
}

static void draw_divider(SDL_Renderer *r, int x, int y, int w, SDL_Color c) {
    SDL_SetRenderDrawColor(r, c.r, c.g, c.b, c.a);
    SDL_RenderDrawLine(r, x, y, x + w, y);
}

static void draw_progress_bar(SDL_Renderer *r, int x, int y, int w, int h, float progress, SDL_Color track, SDL_Color fill) {
    int fw;
    progress = clampf(progress, 0.0f, 1.0f);
    draw_rect(r, x, y, w, h, track);
    fw = (int)((float)w * progress);
    if(fw > 0) {
        draw_rect(r, x, y, fw, h, fill);
    }
}

static void draw_gradient_bg(SDL_Renderer *r, Uint32 ticks) {
    const Theme *theme = active_theme();
    int y;
    for(y = 0; y < LOGICAL_H; y++) {
        float t = (float)y / (float)LOGICAL_H;
        Uint8 rr = (Uint8)lerpf((float)theme->bg_top.r, (float)theme->bg_bottom.r, t);
        Uint8 gg = (Uint8)lerpf((float)theme->bg_top.g, (float)theme->bg_bottom.g, t);
        Uint8 bb = (Uint8)lerpf((float)theme->bg_top.b, (float)theme->bg_bottom.b, t);
        SDL_SetRenderDrawColor(r, rr, gg, bb, 255);
        SDL_RenderDrawLine(r, 0, y, LOGICAL_W, y);
    }

    draw_rect(r, 104 + (int)(sinf(ticks * 0.0011f) * 18.0f), 98, 420, 420, theme->glow_a);
    draw_rect(r, 1330 + (int)(cosf(ticks * 0.0010f) * 14.0f), 120, 320, 320, theme->glow_b);
    draw_rect(r, 1460, 730 + (int)(sinf(ticks * 0.0016f) * 10.0f), 220, 160, theme->glow_a);

    for(y = 100; y < LOGICAL_H - 80; y += 88) {
        SDL_SetRenderDrawColor(r, theme->bg_grid.r, theme->bg_grid.g, theme->bg_grid.b, 20);
        SDL_RenderDrawLine(r, 64, y, LOGICAL_W - 64, y);
    }
    for(y = 64; y < LOGICAL_W - 64; y += 96) {
        SDL_SetRenderDrawColor(r, theme->bg_grid.r, theme->bg_grid.g, theme->bg_grid.b, 12);
        SDL_RenderDrawLine(r, y, 64, y, LOGICAL_H - 64);
    }
}

static void draw_text_scaled(SDL_Renderer *r, int x, int y, const char *text, SDL_Color color, int scale) {
    TextCacheEntry *entry;
    const float render_scale = (float)scale;
    if(!text || !text[0]) {
        return;
    }
    if(g_fonts.enabled) {
        SDL_Rect dst;
        entry = find_cached_text(text, scale);
        if(!entry) {
            entry = create_cached_text(text, scale);
        }
        if(entry && entry->texture) {
            dst.x = x;
            dst.y = y;
            dst.w = entry->w;
            dst.h = entry->h;
            SDL_SetTextureColorMod(entry->texture, color.r, color.g, color.b);
            SDL_SetTextureAlphaMod(entry->texture, color.a);
            SDL_RenderCopy(r, entry->texture, 0, &dst);
            return;
        }
    }
    SDL_SetRenderDrawColor(r, color.r, color.g, color.b, color.a);
    SDL_RenderSetScale(r, render_scale, render_scale);
    SDLTest_DrawString(r, x / (int)render_scale, y / (int)render_scale, text);
    SDL_RenderSetScale(r, 1.0f, 1.0f);
}

static void draw_wrapped_text(SDL_Renderer *r, int x, int y, int width, const char *text, SDL_Color color, int scale, int max_lines) {
    char line[128];
    int len = 0;
    int lines = 0;
    const int max_chars = width / (8 * scale);
    const char *p = text;

    while(*p && lines < max_lines) {
        const char *word_start = p;
        int word_len = 0;

        while(*p && *p != ' ' && *p != '\n') {
            p++;
            word_len++;
        }

        if(*p == '\n') {
            if(len > 0) {
                line[len] = 0;
                draw_text_scaled(r, x, y + lines * (12 * scale + 10), line, color, scale);
                lines++;
                len = 0;
            }
            p++;
            continue;
        }

        if(len && len + 1 + word_len > max_chars) {
            line[len] = 0;
            draw_text_scaled(r, x, y + lines * (12 * scale + 10), line, color, scale);
            lines++;
            len = 0;
            if(lines >= max_lines) {
                break;
            }
        }

        if(word_len > max_chars) {
            word_len = max_chars;
        }

        if(len > 0 && len < (int)sizeof(line) - 1) {
            line[len++] = ' ';
        }
        if(len + word_len >= (int)sizeof(line)) {
            word_len = (int)sizeof(line) - len - 1;
        }
        memcpy(line + len, word_start, (size_t)word_len);
        len += word_len;

        while(*p == ' ') {
            p++;
        }
    }

    if(len > 0 && lines < max_lines) {
        line[len] = 0;
        draw_text_scaled(r, x, y + lines * (12 * scale + 10), line, color, scale);
    }
}

static void draw_icon_or_placeholder(SDL_Renderer *r, HomebrewApp *item, int x, int y, int w, int h, int selected) {
    const Theme *theme = active_theme();
    SDL_Rect dst = {x, y, w, h};
    if(item->icon) {
        dst = fit_rect(item->icon, x, y, w, h);
        SDL_RenderCopy(r, item->icon, 0, &dst);
    } else {
        draw_rect(r, x, y, w, h, theme->panel_soft);
        draw_outline(r, x, y, w, h, theme->border);
        draw_text_scaled(r, x + 24, y + h / 2 - 10, "NO ICON", theme->text_soft, 2);
    }

    if(selected) {
        draw_outline(r, x - 2, y - 2, w + 4, h + 4, theme->border_active);
    }
}

static void draw_card(SDL_Renderer *r, HomebrewApp *item, int x, int y, int w, int h, int selected) {
    const Theme *theme = active_theme();
    SDL_Rect card = {x, y, w, h};
    SDL_Rect icon_rect = {x + 14, y + 14, 112, 112};
    SDL_Color border = selected ? theme->border_active : theme->border;
    SDL_Color panel = selected ? theme->panel_strong : theme->panel;
    SDL_Color shadow = selected ? (SDL_Color){theme->accent.r, theme->accent.g, theme->accent.b, 14} : (SDL_Color){0, 0, 0, 16};
    char title[72];
    char subtitle[96];
    char id[48];
    char source[64];
    int text_scale = selected ? 2 : 1;

    draw_shadow(r, card, shadow, 2, selected ? 4 : 2);
    draw_frame(r, card, panel, border);
    draw_rect(r, x + 14, y + 14, 112, 112, theme->panel_soft);
    draw_icon_or_placeholder(r, item, icon_rect.x, icon_rect.y, icon_rect.w, icon_rect.h, 0);
    if(selected) {
        draw_rect(r, x, y, 6, h, theme->accent);
    }

    text_copy_clamped_px(title, sizeof(title), item->title, text_scale, w - 164);
    text_copy_clamped_px(subtitle, sizeof(subtitle), item->subtitle, 1, w - 164);
    text_copy_clamped_px(id, sizeof(id), item->id, 1, w - 164);
    text_copy_clamped_px(source, sizeof(source), item->source, 1, 110);

    draw_text_scaled(r, x + 146, y + 20, title, theme->text, text_scale);
    draw_text_scaled(r, x + 146, y + 58, subtitle, theme->text_soft, 1);
    draw_text_scaled(r, x + 146, y + 88, id, selected ? theme->accent_alt : theme->accent, 1);
    draw_text_right(r, x + w - 16, y + h - 20, source, theme->text_muted, 1);
}

static void draw_header(SDL_Renderer *r, AppState *app) {
    const Theme *theme = active_theme();
    char count_label[48];
    char skin_label[96];
    int count_w;
    int skin_w;
    int launch_w;
    int refresh_w;
    int right = 1840;
    SDL_Rect mast = {80, 44, 1760, 108};
    draw_frame(r, mast, (SDL_Color){14, 18, 25, 168}, theme->border);
    draw_text_scaled(r, 80, 54, "PS5 HOME HUB", theme->accent, 1);
    draw_text_scaled(r, 80, 84, "Native Homebrew Launcher", theme->text, 3);
    draw_text_scaled(r, 80, 132, "Fast local browsing, direct launch flow, software skins from manifest.", theme->text_soft, 1);
    snprintf(count_label, sizeof(count_label), "%d APPS", app->app_count);
    snprintf(skin_label, sizeof(skin_label), "%s", g_skin.name[0] ? g_skin.name : "Skin");
    count_w = chip_width_for_text(count_label, 92);
    skin_w = control_chip_width(skin_label);
    launch_w = control_chip_width("Launch");
    refresh_w = control_chip_width("Refresh");
    draw_control_chip(r, right - skin_w, 69, skin_w, GLYPH_TRIANGLE, skin_label);
    right -= skin_w + 12;
    draw_control_chip(r, right - refresh_w, 69, refresh_w, GLYPH_SQUARE, "Refresh");
    right -= refresh_w + 12;
    draw_control_chip(r, right - launch_w, 69, launch_w, GLYPH_CROSS, "Launch");
    right -= launch_w + 12;
    draw_chip(r, right - count_w, 72, count_w, count_label, theme->accent_soft, theme->accent);
}

static void draw_hero(SDL_Renderer *r, HomebrewApp *item) {
    const Theme *theme = active_theme();
    SDL_Rect hero = rect_hero_panel();
    SDL_Rect art_bg = rect_hero_art();
    SDL_Rect side = rect_sidebar_panel();
    char title[96];
    char subtitle[96];
    char version_line[96];
    char source_line[128];
    char source_value[96];
    char badge_line[96];
    char folder_line[128];
    char elf_line[128];
    int refresh_w;
    int back_w;
    int cross_w;

    draw_shadow(r, hero, (SDL_Color){0, 0, 0, 18}, 3, 4);
    draw_frame(r, hero, theme->panel, theme->border);
    draw_rect(r, hero.x, hero.y, hero.w, 140, theme->panel_soft);
    draw_rect(r, art_bg.x, art_bg.y, art_bg.w, art_bg.h, theme->panel_soft);
    draw_rect(r, art_bg.x - 18, art_bg.y - 18, art_bg.w + 36, art_bg.h + 36, theme->accent_soft);

    text_copy_clamped_px(title, sizeof(title), item->title, 4, 600);
    text_copy_clamped_px(subtitle, sizeof(subtitle), item->subtitle, 2, 600);
    snprintf(version_line, sizeof(version_line), "VERSION %s", item->version[0] ? item->version : "UNSPECIFIED");
    text_copy_clamped_px(source_value, sizeof(source_value), item->source[0] ? item->source : "UNKNOWN", 1, 220);
    snprintf(source_line, sizeof(source_line), "SOURCE %s", source_value);
    snprintf(badge_line, sizeof(badge_line), "%s READY", item->id);
    text_copy_clamped_px(folder_line, sizeof(folder_line), item->folder, 1, 470);
    text_copy_clamped_px(elf_line, sizeof(elf_line), item->elf_path, 1, 470);
    refresh_w = control_chip_width("Refresh");
    back_w = control_chip_width("Back");
    cross_w = control_chip_width("");

    draw_icon_or_placeholder(r, item, art_bg.x, art_bg.y, art_bg.w, art_bg.h, 0);
    draw_chip(r, 590, 214, chip_width_for_text(badge_line, 132), badge_line, theme->accent_soft, theme->accent);
    draw_text_scaled(r, 590, 254, title, theme->text, 4);
    draw_text_scaled(r, 592, 314, subtitle, theme->accent, 2);
    draw_wrapped_text(r, 592, 366, 610, item->description[0] ? item->description : "Ready to launch from the native SDL2 frontend.", theme->text_soft, 2, 5);
    draw_divider(r, 590, 552, 590, theme->border);
    draw_text_scaled(r, 592, 582, item->id, theme->text, 2);
    draw_text_scaled(r, 592, 620, version_line, theme->text_muted, 1);
    draw_text_scaled(r, 592, 648, source_line, theme->text_muted, 1);

    draw_shadow(r, side, (SDL_Color){0, 0, 0, 16}, 3, 3);
    draw_frame(r, side, theme->panel, theme->border);
    draw_text_scaled(r, 1324, 226, "NOW SELECTED", theme->accent, 1);
    draw_text_scaled(r, 1324, 256, "Launch Details", theme->text, 3);
    draw_divider(r, 1324, 310, 482, theme->border);
    draw_text_scaled(r, 1324, 344, "Title ID", theme->text_muted, 1);
    draw_text_scaled(r, 1324, 370, item->id, theme->text, 2);
    draw_progress_bar(r, 1324, 404, 470, 6, item->version[0] ? 1.0f : 0.64f, theme->panel_soft, theme->accent);
    draw_text_scaled(r, 1324, 430, "Folder", theme->text_muted, 1);
    draw_text_scaled(r, 1324, 456, folder_line, theme->text_soft, 1);
    draw_text_scaled(r, 1324, 544, "ELF", theme->text_muted, 1);
    draw_text_scaled(r, 1324, 570, elf_line, theme->text_soft, 1);
    draw_chip(r, 1324, 674, 138, item->version[0] ? item->version : "NO VERSION", theme->accent_soft, theme->accent);
    draw_control_chip(r, 1468, 670, refresh_w, GLYPH_SQUARE, "Refresh");
    draw_control_chip(r, 1468 + refresh_w + 10, 670, back_w, GLYPH_CIRCLE, "Back");
    draw_control_chip(r, 1468 + refresh_w + back_w + 20, 670, cross_w, GLYPH_CROSS, "");
}

static void draw_empty_state(SDL_Renderer *r) {
    const Theme *theme = active_theme();
    SDL_Rect panel = {178, 248, 1564, 492};

    draw_shadow(r, panel, (SDL_Color){0, 0, 0, 18}, 3, 4);
    draw_frame(r, panel, theme->panel, theme->border);
    draw_text_scaled(r, 258, 318, "NO HOMEBREW FOUND", theme->text, 4);
    draw_text_scaled(r, 258, 380, "Drop apps into a scanned folder and they will appear here automatically.", theme->accent, 2);
    draw_wrapped_text(r, 258, 446, 1220,
                      "Create folders under /data/homebrew, /mnt/usb0/homebrew or mounted storage with eboot.elf plus sce_sys/param.json and icon0.png. Themes are software-rendered and can be customized by editing manifest.json files.",
                      theme->text_soft, 2, 6);
}

static void draw_bottom_rail(SDL_Renderer *r, AppState *app) {
    const Theme *theme = active_theme();
    SDL_Rect rail = rect_rail_panel();
    SDL_Rect cards_clip = rect_rail_cards_clip();
    int i;
    int card_w = 332;
    int card_h = 146;
    int gap = 20;
    int center_x = rail.x + rail.w / 2 - card_w / 2;
    float offset = app->carousel_pos;

    draw_frame(r, rail, theme->status_bg, theme->border);
    draw_text_scaled(r, rail.x + 28, rail.y + 20, "Library", theme->text, 2);
    draw_text_scaled(r, rail.x + 28, rail.y + 52, g_skin.name[0] ? g_skin.name : "Browse installed homebrew", theme->text_muted, 1);
    {
        int next_w = control_chip_width("Next");
        int prev_w = control_chip_width("Prev");
        int right = rail.x + rail.w - 26;
        draw_control_chip(r, right - next_w, rail.y + 10, next_w, GLYPH_ARROW_RIGHT, "Next");
        right -= next_w + 10;
        draw_control_chip(r, right - prev_w, rail.y + 10, prev_w, GLYPH_ARROW_LEFT, "Prev");
    }

    SDL_RenderSetClipRect(r, &cards_clip);
    for(i = 0; i < app->app_count; i++) {
        int x = center_x + (int)((i - offset) * (float)(card_w + gap));
        int y = rail.y + 54 + (i == app->selected ? -10 : 0);
        if(x + card_w < cards_clip.x || x > cards_clip.x + cards_clip.w) {
            continue;
        }
        draw_card(r, &app->apps[i], x, y, card_w, card_h, i == app->selected);
    }
    SDL_RenderSetClipRect(r, 0);
}

static void render(AppState *app) {
    const Theme *theme = active_theme();
    Uint32 ticks = SDL_GetTicks();
    float dt = clampf((ticks - app->last_ticks) / 1000.0f, 0.0f, 0.05f);
    float app_progress = app->app_count > 1 ? (float)app->selected / (float)(app->app_count - 1) : 1.0f;

    app->last_ticks = ticks;
    app->carousel_pos = lerpf(app->carousel_pos, (float)app->selected, clampf(dt * 8.0f, 0.0f, 1.0f));

    SDL_RenderSetClipRect(app->renderer, 0);
    SDL_RenderSetScale(app->renderer, 1.0f, 1.0f);
    SDL_SetRenderDrawColor(app->renderer, 0, 0, 0, 255);
    SDL_RenderClear(app->renderer);
    draw_gradient_bg(app->renderer, ticks);
    draw_header(app->renderer, app);

    if(app->app_count > 0) {
        HomebrewApp *selected = &app->apps[app->selected];
        draw_hero(app->renderer, selected);
        draw_bottom_rail(app->renderer, app);
        draw_progress_bar(app->renderer, 80, 1024, 1760, 5, app_progress, theme->panel_soft, theme->accent);
    } else {
        draw_empty_state(app->renderer);
    }
    draw_rect(app->renderer, 0, LOGICAL_H - 40, LOGICAL_W, 40, theme->status_bg);
    draw_text_scaled(app->renderer, 20, LOGICAL_H - 24, app->status, theme->text_soft, 1);
    SDL_RenderPresent(app->renderer);
}

static void attempt_launch(AppState *app) {
    HomebrewApp *item;
    FILE *fp;
    if(app->app_count <= 0) {
        return;
    }
    item = &app->apps[app->selected];
    stop_preview_music(app);
    fp = fopen(REQUEST_PATH, "w");
    if(!fp) {
        snprintf(app->status, sizeof(app->status), "Cannot write launch request");
        return;
    }
    fprintf(fp, "%s\n%s\n", item->elf_path, item->folder);
    fclose(fp);
    snprintf(app->status, sizeof(app->status), "Launching %s...", item->title);
    SDL_Delay(250);
    app->running = 0;
}

static void handle_input(AppState *app, const SDL_Event *event) {
    int prev_selected = app->selected;

    if(event->type == SDL_QUIT) {
        app->running = 0;
        return;
    }

    if(event->type == SDL_KEYDOWN) {
        switch(event->key.keysym.sym) {
            case SDLK_ESCAPE:
                app->running = 0;
                break;
            case SDLK_LEFT:
                if(app->selected > 0) app->selected--;
                break;
            case SDLK_RIGHT:
                if(app->selected + 1 < app->app_count) app->selected++;
                break;
            case SDLK_RETURN:
            case SDLK_SPACE:
                attempt_launch(app);
                break;
            case SDLK_t:
                cycle_skin(app, 1);
                break;
            case SDLK_r:
                load_homebrew(app);
                break;
        }
    }

    if(event->type == SDL_CONTROLLERBUTTONDOWN) {
        launcher_logf("controller button=", event->cbutton.button);
        switch(event->cbutton.button) {
            case SDL_CONTROLLER_BUTTON_DPAD_LEFT:
                if(app->selected > 0) app->selected--;
                break;
            case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:
                if(app->selected + 1 < app->app_count) app->selected++;
                break;
            case SDL_CONTROLLER_BUTTON_A:
                attempt_launch(app);
                break;
            case SDL_CONTROLLER_BUTTON_X:
                load_homebrew(app);
                break;
            case SDL_CONTROLLER_BUTTON_Y:
                cycle_skin(app, 1);
                break;
            case SDL_CONTROLLER_BUTTON_B:
                app->running = 0;
                break;
        }
    }

    if(event->type == SDL_JOYBUTTONDOWN) {
        launcher_logf("joy button=", event->jbutton.button);
        switch(event->jbutton.button) {
            case 0:
                attempt_launch(app);
                break;
            case 1:
                app->running = 0;
                break;
            case 2:
                load_homebrew(app);
                break;
            case 3:
                cycle_skin(app, 1);
                break;
            case 13:
                if(app->selected > 0) app->selected--;
                break;
            case 14:
                if(app->selected + 1 < app->app_count) app->selected++;
                break;
        }
    }

    if(event->type == SDL_JOYHATMOTION) {
        launcher_logf("joy hat=", event->jhat.value);
        if(event->jhat.value & SDL_HAT_LEFT) {
            if(app->selected > 0) app->selected--;
        } else if(event->jhat.value & SDL_HAT_RIGHT) {
            if(app->selected + 1 < app->app_count) app->selected++;
        }
    }

    if(app->selected != prev_selected) {
        update_preview_music(app, 1);
    }
}

static void shutdown_app(AppState *app) {
    int i;
    for(i = 0; i < app->app_count; i++) {
        if(app->apps[i].icon) {
            SDL_DestroyTexture(app->apps[i].icon);
        }
    }
    if(app->controller) {
        SDL_GameControllerClose(app->controller);
    }
    if(app->joystick) {
        SDL_JoystickClose(app->joystick);
    }
    stop_preview_music(app);
    if(app->audio_ready) {
        Mix_CloseAudio();
    }
    Mix_Quit();
    destroy_skin_assets();
    if(app->renderer) SDL_DestroyRenderer(app->renderer);
    if(app->window) SDL_DestroyWindow(app->window);
    shutdown_fonts();
    IMG_Quit();
    SDL_Quit();
}

int main(int argc, char **argv) {
    AppState app;
    SDL_Event event;
    (void)argc;
    (void)argv;
    launcher_log("main start");

    if(init_app(&app) != 0) {
        launcher_log("init_app returned error");
        fprintf(stderr, "Launcher init failed: %s\n", SDL_GetError());
        return 1;
    }

    load_homebrew(&app);
    app.last_ticks = SDL_GetTicks();
    launcher_log("entering main loop");

    while(app.running) {
        while(SDL_PollEvent(&event)) {
            handle_input(&app, &event);
        }
        render(&app);
        SDL_Delay(16);
    }

    launcher_log("shutdown");
    shutdown_app(&app);
    return 0;
}
