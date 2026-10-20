/*
 * PS5 RetroArch - the frontend picker: RetroArch or EmulationStation, in Gloss.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The title's pre-screen (docs/FRONTENDS.md). It is a program of PS5_VulkanTemplate's
 * UI module (BlackBearReloaded's kit, drawn with Vulkan), built into its own
 * executable, /app0/picker/picker.bin, by tools/build-picker.sh; eboot.bin starts it
 * through LoadExec when the title is launched from the home screen. It always wears
 * the kit's "gloss" theme (Gloss, Skeuomorphic), whatever theme the kit would pick.
 *
 * Two cards, each with a picture of the frontend it starts: RetroArch's XMB menu,
 * and EmulationStation's Alekfull NX system view, both captured on the console
 * (/app0/picker/previews/*.rgba, written by the build from assets/picker/). LEFT and
 * RIGHT move, CROSS starts the frontend, CIRCLE closes the title. Both frontends
 * play every game through RetroArch, with its cores, saves, shaders and settings.
 *
 * SQUARE switches Remember: with it on, the frontend started is written to
 * /app0/config/frontend.cfg (src/ps5_frontend_choice.h, copied beside this file by
 * the build), and the title starts it straight away from then on; holding L1 while
 * the title starts comes back here, which shows the switch on and that frontend
 * chosen. With it off, the file says "ask" and this screen opens every time.
 *
 * Choosing ends the program, so its device and display are released, and then
 * ps5_title_next (called by the title's main once the program is gone) restarts
 * the title as the frontend: eboot.bin with --ps5-mode=retroarch, or
 * /app0/es-de/es-de.bin.
 *
 * Armed by /app0/picker/picker-test.txt ("<frames> <retroarch|es-de|none>
 * [remember|forget]", tools/run-title.sh --picker-test), the picker draws that many
 * frames without the pad, sets Remember when the third word asks, moves to the card
 * named, saves its last frame as
 * /app0/picker/screenshots/picker.ppm, chooses it, and records what it chose in
 * /app0/picker/picker-test.jsonl. The file is removed when read: it arms one launch.
 */

#include "kit.hpp"
#include "ps5_frontend_choice.h"
#include "webui_link.h"
#include "ps5_webui_qr.h"
#include <atomic>
#include <ps5platform/libc.h>
#include <sys/stat.h>

extern "C" int sceSystemServiceLoadExec(const char *path, const char *const *argv);
extern "C" int sceKernelUsleep(uint32_t microseconds);

namespace {

using hui::gfx::Color;
using hui::gfx::Rect;

constexpr int cardCount = 2;
constexpr const char *testPath = PS5_APP_ROOT "/picker-test.txt";
constexpr const char *testRecord = PS5_APP_ROOT "/picker-test.jsonl";
constexpr const char *screenshotPath = PS5_APP_ROOT "/screenshots/picker.ppm";

struct Frontend {
	const char *id;
	const char *title;
	const char *subtitle;
	const char *preview;
	const char *next;     // the executable that runs it
	const char *argument; // its one argument
	Color accent;
};

const Frontend frontends[cardCount] = {
	{ "retroarch", "RetroArch", "The XMB menu: every core, setting and shader", PS5_APP_ROOT "/previews/retroarch.rgba",
		"/app0/eboot.bin", "--ps5-mode=retroarch", Color::rgb(0x7c4dff) },
	{ "es-de", "EmulationStation", "ES-DE in the Alekfull NX theme; games start in RetroArch",
		PS5_APP_ROOT "/previews/es-de.rgba", "/app0/es-de/es-de.bin", "", Color::rgb(0x00b4d8) },
};

// What runs once the program has ended: -1 for nothing (the title closes)
int nextFrontend = -1;
// Remember's state when the program ended: the frontend chosen is written, or "ask"
bool rememberChoice = false;
std::string testLine;
// The WebUI's daemon asked for the title to close, to install an update (src/webui_link.h)
std::atomic<bool> closeForUpdate{ false };

const hui::ui::Theme &glossTheme()
{
	for (const hui::ui::Theme &theme : hui::ui::themes()) {
		if (std::strcmp(theme.id, "gloss") == 0) {
			return theme;
		}
	}
	return hui::ui::default_theme();
}

// A preview: "PS5RGBA1", the width and height (little-endian 32-bit), then the pixels
std::vector<std::uint8_t> readPreview(const char *path, int &width, int &height)
{
	std::vector<std::uint8_t> pixels;
	FILE *file = std::fopen(path, "rb");
	if (!file) {
		return pixels;
	}
	char magic[8];
	std::uint32_t size[2];
	if (std::fread(magic, 1, 8, file) == 8 && std::memcmp(magic, "PS5RGBA1", 8) == 0 &&
		std::fread(size, sizeof(size[0]), 2, file) == 2 && size[0] > 0 && size[1] > 0 && size[0] <= 4096 &&
		size[1] <= 4096) {
		pixels.resize((size_t)size[0] * size[1] * 4);
		if (std::fread(pixels.data(), 1, pixels.size(), file) == pixels.size()) {
			width = (int)size[0];
			height = (int)size[1];
		} else {
			pixels.clear();
		}
	}
	std::fclose(file);
	return pixels;
}

void openForFtp(const char *path, int depth); // below

class VulkanExample : public ps5ui::KitExample
{
	unsigned framesSinceStart = 0; // for opening the shader cache to FTP
public:
	int focus{ 0 };
	int chosen{ -2 }; // -2: still choosing, -1: close, else the frontend
	hui::tween::Spring shown[cardCount];
	std::uint32_t previews[cardCount]{};
	float previewAspect[cardCount]{ 16.0f / 9.0f, 16.0f / 9.0f };
	const hui::ui::Theme &theme = glossTheme();
	hui::gfx::DrawList scene;
	hui::ui::Feedback feedback;
	float clock{ 0.0f };
	int testChoice{ -2 }; // armed: the frontend to choose, or -1 for none
	int testRemember{ -1 }; // armed: 1 remember, 0 forget, -1 leave the switch
	bool remember{ false };
	bool showWebUI{ false };
	ps5_webui_qr webuiQR{};

	VulkanExample() : KitExample()
	{
		title = "Frontend picker";
		name = "picker";
		settings.overlay = false;
		ps5.ownOverlay = true;
		defaultClearColor = { { 0.0f, 0.0f, 0.0f, 1.0f } };
		// The WebUI is the daemon's while the picker shows: it stays up as a frontend starts
		ps5_webui_link_start("picker", [] { closeForUpdate = true; }, [](const char *line) { say("%s", line); });
	}

	void readTest()
	{
		FILE *file = std::fopen(testPath, "r");
		if (!file) {
			return;
		}
		unsigned frames = 0;
		char choice[16] = {}, switchWord[16] = {};
		const int fields = std::fscanf(file, "%u %15s %15s", &frames, choice, switchWord);
		std::fclose(file);
		std::remove(testPath);
		if (fields < 2 || frames < 10 || frames > 36000) {
			return;
		}
		if (fields == 3) {
			testRemember = std::strcmp(switchWord, "remember") == 0 ? 1 : std::strcmp(switchWord, "forget") == 0 ? 0 : -1;
		}
		testChoice = -1;
		for (int i = 0; i < cardCount; i++) {
			if (std::strcmp(choice, frontends[i].id) == 0) {
				testChoice = i;
			}
		}
		benchmark.active = true;
		ps5.frameBudget = frames;
		mkdir(PS5_APP_ROOT "/screenshots", 0777);
		ps5.screenshotPath = screenshotPath;
		char line[96];
		std::snprintf(line, sizeof(line), "\"frames\":%u,\"choice\":\"%s\",\"remember\":%d", frames, choice,
			testRemember);
		testLine = line;
	}

	void prepare() override
	{
		VulkanExampleBase::prepare();
		// A frontend remembered (this screen came back because L1 was held): the switch
		// is on and that frontend's card is the one chosen
		const char *remembered = ps5_frontend_choice_read(PS5_FRONTEND_CHOICE_PATH);
		for (int i = 0; i < cardCount; i++) {
			if (std::strcmp(remembered, frontends[i].id) == 0) {
				remember = true;
				focus = i;
			}
		}
		readTest();
		prepareKit({ .music = false, .covers = false });
		for (int i = 0; i < cardCount; i++) {
			int width = 0, height = 0;
			const std::vector<std::uint8_t> pixels = readPreview(frontends[i].preview, width, height);
			if (!pixels.empty()) {
				previews[i] = kit.renderer.create_texture(width, height, pixels.data());
				previewAspect[i] = (float)width / (float)height;
			}
			shown[i].snap(i == focus ? 1.0f : 0.0f);
		}
		prepared = true;
	}

	void move(int to)
	{
		if (to == focus) {
			return;
		}
		feedback.play(hui::audio::Cue::focus, 1.0f, to == 0 ? -0.35f : 0.35f);
		focus = to;
	}

	void update(float dt)
	{
		feedback.clear();
		hui::InputFrame input = kit.input();
		if (ps5.frameBudget) {
			// A test run is the same whoever holds the pad: it moves to its card a third
			// of the way in, and chooses it on its last frame
			input = hui::InputFrame{};
			input.connected = true;
			if (testChoice >= 0 && ps5.framesDrawn == ps5.frameBudget / 3) {
				move(testChoice);
			}
			if (testRemember >= 0 && ps5.framesDrawn == ps5.frameBudget / 2) {
				remember = testRemember == 1;
			}
			if (ps5.framesDrawn + 1 == ps5.frameBudget) {
				chosen = testChoice;
			}
		}
		clock += dt;
		// Consume the overlay's buttons so Circle never closes the title underneath it.
		if (input.is_pressed(hui::Action::north)) {
			showWebUI = !showWebUI;
			if (showWebUI) ps5_webui_qr_refresh(&webuiQR, true);
			input = hui::InputFrame{};
		} else if (showWebUI) {
			if (input.is_pressed(hui::Action::back)) showWebUI = false;
			input = hui::InputFrame{};
		}
		if (showWebUI) ps5_webui_qr_refresh(&webuiQR, false);
		if (input.nav == hui::Direction::left && focus > 0) {
			move(focus - 1);
		} else if (input.nav == hui::Direction::right && focus < cardCount - 1) {
			move(focus + 1);
		} else if (input.nav != hui::Direction::none && !input.nav_repeat) {
			feedback.play(hui::audio::Cue::error, 1.0f, 0.0f, 0.5f);
		}
		if (input.is_pressed(hui::Action::confirm)) {
			feedback.play(hui::audio::Cue::select);
			chosen = focus;
		} else if (input.is_pressed(hui::Action::back)) {
			chosen = -1;
		} else if (input.is_pressed(hui::Action::west)) {
			remember = !remember;
			feedback.play(hui::audio::Cue::toggle);
		}
		for (int i = 0; i < cardCount; i++) {
			shown[i].target = i == focus ? 1.0f : 0.0f;
			shown[i].update(dt, theme.omega);
		}
		kit.play(feedback, theme.sounds);
		kit.tick(dt);
	}

	void compose()
	{
		const std::uint32_t glass = kit.renderer.glass_texture();
		scene.clear();
		hui::ui::Canvas canvas{ scene, kit.fonts, glass, clock };
		hui::ui::Painter painter(scene, kit.fonts, theme, glass);
		const hui::ui::ComponentStyle style{ theme };

		// The entrance: the heading fades in, then the cards rise one after the other
		const auto arrive = [this](float delay, float length) {
			return hui::tween::smoothstep(std::clamp((clock - delay) / length, 0.0f, 1.0f));
		};
		const float heading = arrive(0.0f, 0.5f);
		scene.push_opacity(heading);
		scene.push_transform(1.0f, 0.0f, 0.0f, 0.0f, (1.0f - heading) * 24.0f);
		painter.label("PS5 RETROARCH", 200.0f, 140.0f, 22.0f, painter.page_text_muted());
		painter.heading("Choose a frontend", 196.0f, 236.0f, 84.0f, painter.page_text());
		painter.body("Both play every game through RetroArch, with the same cores, saves, shaders and settings",
			200.0f, 292.0f, 26.0f, painter.page_text_muted());
		if (remember) {
			painter.body("Remember is on: the title starts this frontend straight away. Hold L1 while it starts to come back here.",
				200.0f, 940.0f, 24.0f, painter.page_text_muted());
		}
		scene.pop_transform();
		scene.pop_opacity();

		hui::ui::CardLook look;
		look.art_aspect = 16.0f / 9.0f;
		look.title_size = 44.0f;
		look.subtitle_size = 24.0f;
		look.text_gap = 20.0f;
		look.glow = true;
		const float cardWidth = 700.0f;
		const float gap = 120.0f;
		for (int i = 0; i < cardCount; i++) {
			hui::ui::CardItem item;
			item.title = frontends[i].title;
			item.subtitle = frontends[i].subtitle;
			item.texture = previews[i];
			item.uv = hui::gfx::kFullUv;
			item.image_aspect = previewAspect[i];
			item.accent = frontends[i].accent;
			hui::ui::CardState state;
			state.focus = shown[i].value;
			const Rect card{ 200.0f + (cardWidth + gap) * (float)i, 360.0f, cardWidth,
				hui::ui::card_height(look, cardWidth) };
			const float rise = arrive(0.25f + 0.12f * (float)i, 0.55f);
			scene.push_opacity(rise);
			scene.push_transform(1.0f, 0.0f, 0.0f, 0.0f, (1.0f - rise) * 120.0f);
			hui::ui::draw_card(canvas, style, look, card, item, state);
			scene.pop_transform();
			scene.pop_opacity();
		}

		const float foot = arrive(0.75f, 0.4f);
		scene.push_opacity(foot);
		ps5ui::draw_hints(scene, kit.fonts, theme,
			{ { hui::ui::Button::dpad, "Move" }, { hui::ui::Button::cross, "Start" },
				{ hui::ui::Button::square, remember ? "Remember: on" : "Remember: off" },
				{ hui::ui::Button::triangle, "WebUI" }, { hui::ui::Button::circle, "Close" } },
			960.0f, 1010.0f, 0);
		scene.pop_opacity();

		if (showWebUI) {
			scene.rounded_rect({ 0, 0, 1920, 1080 }, 0, Color{ 0, 0, 0, 0.96f });
			painter.heading("WebUI", 820, 150, 64, Color::rgb(0xffffff));
			if (webuiQR.size) {
				const unsigned scale = 14, side = webuiQR.size * scale;
				const float left = (1920.0f - side) / 2, top = 210;
				scene.rounded_rect({ left, top, (float)side, (float)side }, 0, Color::rgb(0xffffff));
				for (unsigned y = 0; y < webuiQR.size; y++)
					for (unsigned x = 0; x < webuiQR.size; x++)
						if (webuiQR.modules[y * webuiQR.size + x])
							scene.rounded_rect({ left + x * scale, top + y * scale, (float)scale, (float)scale }, 0, Color::rgb(0x000000));
			}
			painter.body(webuiQR.size ? webuiQR.url : PS5_WEBUI_QR_OFFLINE, 560, 810, 36, Color::rgb(0xffffff));
			painter.body("Scan with a phone on the same network", 560, 880, 30, Color::rgb(0xffffff));
			ps5ui::draw_hints(scene, kit.fonts, theme,
				{ { hui::ui::Button::triangle, "Close WebUI" }, { hui::ui::Button::circle, "Close WebUI" } }, 960, 1010, 0);
		}

		hui::gfx::BackdropSpec backdrop = theme.backdrop;
		backdrop.time = clock;
		kit.renderer.begin();
		kit.renderer.backdrop(backdrop);
		kit.renderer.glass();
		kit.renderer.draw(scene);
	}

	void render() override
	{
		if (!prepared) {
			return;
		}
		prepareFrame();
		update(std::min(frameTimer, 0.05f));
		compose();
		buildKitCommandBuffer();
		submitFrame();
		// Once the first frames are drawn RADV has written its shader cache: open it
		// to FTP now, as the title may be closed from here without a choice.
		if (++framesSinceStart == 30) {
			openForFtp("/app0/radv-shader-cache", 6);
		}
		if (closeForUpdate && chosen == -2) {
			say("picker: closing the title for the WebUI's update");
			chosen = -1;
		}
		if (chosen != -2) {
			nextFrontend = chosen;
			rememberChoice = remember;
			quit = true;
		}
	}

	~VulkanExample() override
	{
		if (device) {
			vkDeviceWaitIdle(device);
		}
	}
};

// What the picker wrote below a folder is given 0777, as eboot.bin gives everything
// under /app0 (src/permissions_ps5.cpp): this executable has none of the title's
// wrappers, and RADV writes its shader cache 0666. Without it FTP met those files
// as the picker left them until eboot.bin's next start.
void openForFtp(const char *path, int depth)
{
	chmod(path, 0777);
	DIR *directory = depth > 0 ? ps5_opendir(path) : nullptr;
	if (!directory) {
		return;
	}
	while (const struct dirent *entry = ps5_readdir(directory)) {
		if (std::strcmp(entry->d_name, ".") == 0 || std::strcmp(entry->d_name, "..") == 0) {
			continue;
		}
		char child[1024];
		const int length = std::snprintf(child, sizeof(child), "%s/%s", path, entry->d_name);
		if (length > 0 && static_cast<size_t>(length) < sizeof(child)) {
			openForFtp(child, depth - 1);
		}
	}
	ps5_closedir(directory);
}

} // namespace

// Called by the title's main once the program has ended and released its device
// (tools/build-picker.sh adds the call): the title restarts as the frontend chosen.
extern "C" void ps5_title_next(void)
{
	const Frontend *next = nextFrontend >= 0 && nextFrontend < cardCount ? &frontends[nextFrontend] : nullptr;
	openForFtp("/app0/radv-shader-cache", 6); // the device is released: the cache is final
	// Starting a frontend records Remember: that frontend, or "ask"; closing leaves it
	if (next) {
		const int written = ps5_frontend_choice_write(PS5_FRONTEND_CHOICE_PATH, rememberChoice ? next->id : "ask");
		say("picker: remember %s (write %d)", rememberChoice ? next->id : "ask", written);
	}
	if (!testLine.empty()) {
		if (FILE *record = std::fopen(testRecord, "a")) {
			std::fprintf(record, "{%s,\"next\":\"%s\"}\n", testLine.c_str(), next ? next->next : "");
			std::fclose(record);
			chmod(testRecord, 0777);
		}
	}
	if (!next) {
		return; // the title closes
	}
	ps5_webui_link_settle(); // a daemon being sent to the loader goes whole
	say("picker: %s -> LoadExec(%s, \"%s\")", next->id, next->next, next->argument);
	const char *const argv[] = { next->argument, nullptr };
	const int result = sceSystemServiceLoadExec(next->next, argv);
	say("picker: LoadExec returned %d", result);
	for (;;) {
		sceKernelUsleep(100000);
	}
}

VULKAN_EXAMPLE_MAIN()

// The link to the WebUI's daemon, compiled into this program (tools/build-picker.sh
// copies it beside this file; the template builds one source per program).
#include "webui_link.cpp"
