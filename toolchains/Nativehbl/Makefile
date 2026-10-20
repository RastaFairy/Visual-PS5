PS5_HOST ?= ps5
PS5_PORT ?= 9021

SDK := $(if $(wildcard /home/ruben/ps5-payload-sdk-pacbrew/bin/prospero-clang),/home/ruben/ps5-payload-sdk-pacbrew,/tmp/opt/ps5-payload-sdk)

CC := $(SDK)/bin/prospero-clang
PKG_CONFIG := $(SDK)/bin/prospero-pkg-config

OUTDIR := build
UI_BIN := $(OUTDIR)/ps5_homebrew_launcher_ui_swonly.elf
BOOTSTRAP_BIN := $(OUTDIR)/ps5_homebrew_launcher_bootstrap.elf

COMMON_GPL_SRCS := gpl/pt.c gpl/elfldr.c gpl/hbldr.c gpl/fs_readfile.c

CFLAGS := -g -O1 -Wall -Wextra -Wno-unused-parameter \
	-D__PS5__ \
	-I$(SDK)/target/user/homebrew/include \
	-I$(SDK)/target/user/homebrew/include/freetype2 \
	-I$(SDK)/target/user/homebrew/include/SDL2 \
	-I.

BOOTSTRAP_CFLAGS := $(CFLAGS) -DLAUNCHER_UI_PATH=\"/data/ps5_homebrew_launcher_ui_swonly.elf\"

LDADD := \
	$(SDK)/target/user/homebrew/lib/libSDL2main.a \
	$(SDK)/target/user/homebrew/lib/libSDL2.a \
	$(SDK)/target/user/homebrew/lib/libSDL2_image.a \
	$(SDK)/target/user/homebrew/lib/libSDL2_mixer.a \
	$(SDK)/target/user/homebrew/lib/libSDL2_ttf.a \
	$(SDK)/target/user/homebrew/lib/libSDL2_test.a \
	$(SDK)/target/user/homebrew/lib/libjansson.a \
	$(SDK)/target/user/homebrew/lib/libfreetype.a \
	$(SDK)/target/user/homebrew/lib/libvorbisfile.a \
	$(SDK)/target/user/homebrew/lib/libvorbis.a \
	$(SDK)/target/user/homebrew/lib/libogg.a \
	$(SDK)/target/user/homebrew/lib/libpng.a \
	$(SDK)/target/user/homebrew/lib/libjpeg.a \
	$(SDK)/target/user/homebrew/lib/libwebp.a \
	$(SDK)/target/user/homebrew/lib/libwebpdemux.a \
	$(SDK)/target/user/homebrew/lib/libsharpyuv.a \
	-lSceSystemService -lSceUserService \
	-lSceVideoOut -lSceAudioOut -lScePad \
	-lSceKeyboard -lSceImeDialog \
	-lkernel_sys -lm -lz -lbz2 -liconv

UI_SRCS := main.c font_data.c $(COMMON_GPL_SRCS)
BOOTSTRAP_SRCS := bootstrap.c $(COMMON_GPL_SRCS)

all: $(UI_BIN) $(BOOTSTRAP_BIN)

$(OUTDIR):
	mkdir -p $(OUTDIR)

$(UI_BIN): $(UI_SRCS) | $(OUTDIR)
	$(CC) $(CFLAGS) -o $@ $(UI_SRCS) $(LDADD)

$(BOOTSTRAP_BIN): $(BOOTSTRAP_SRCS) | $(OUTDIR)
	$(CC) $(BOOTSTRAP_CFLAGS) -o $@ $(BOOTSTRAP_SRCS) \
		-lSceSystemService -lSceUserService \
		-lkernel_sys -lm -lz -lbz2 -liconv

clean:
	rm -rf $(OUTDIR)

.PHONY: all clean
