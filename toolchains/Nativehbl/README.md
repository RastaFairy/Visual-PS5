
# PS5 Native Homebrew Launcher

Native PS5 homebrew launcher built with SDL2 and `ps5-payload-sdk`.

## Credits

This launcher reuses and adapts core homebrew launching components derived from `ps5-payload-dev/websrv`.

Original `websrv` launcher backend credit:
- John Törnblom

Project reference:
- `https://github.com/ps5-payload-dev/websrv`

This project provides:
- a native SDL2 launcher UI
- direct homebrew launching without the browser workflow
- a bootstrap ELF for autoloader / elfldr entry
- software-rendered theme support
- per-homebrew music preview with `sndgame.ogg` or `snd0.ogg`

## Media

[launcher-demo.webm](https://github.com/user-attachments/assets/18ab063d-26f0-4309-aefe-6cdf168b3ecf)

<img width="3840" height="2160" alt="20120220_061943_00651743" src="https://github.com/user-attachments/assets/72868e6b-de16-46cd-8260-3e2ff998b39c" />
<img width="3840" height="2160" alt="20120220_061935_00295190" src="https://github.com/user-attachments/assets/650a1908-2688-49c1-b7aa-c5e873b4ec21" />
<img width="3840" height="2160" alt="20120220_061928_00153653" src="https://github.com/user-attachments/assets/a88430bb-cd8d-48cf-a9a9-f8597f6b6a98" />


## Project Layout

- `build/ps5_homebrew_launcher_bootstrap.elf`
  Bootstrap entrypoint. This is the ELF you should load first.
- `build/ps5_homebrew_launcher_ui_swonly.elf`
  Native launcher UI loaded by the bootstrap.
- `main.c`
  Launcher UI, scanning, themes and music preview.
- `bootstrap.c`
  Bigapp launch bridge and launch request supervisor.
- `gpl/`
  Adapted launch backend components derived from `ps5-payload-dev/websrv`.
- `assets/`
  Fonts, screenshots and README media.
- `skins/`
  Example software theme manifests.

## Runtime Files On PS5

Expected launcher files:

- `/data/ps5_homebrew_launcher_bootstrap.elf`
- `/data/ps5_homebrew_launcher_ui_swonly.elf`

Required installed package:

- the PS5 Homebrew Launcher PKG / fake app used by the hbldr flow

This launcher still relies on the same bigapp-style homebrew launch path as `websrv`.
So, just like `websrv`, you must have the Homebrew Launcher PKG installed on the console.
Without that installed base app, the launcher may fail to open the UI or fail to launch selected homebrew correctly.

Autoloader compatibility:

- this launcher is compatible with autoloader flows
- load `ps5_homebrew_launcher_bootstrap.elf`, not the UI ELF directly
- in practice, it is recommended to configure an autoloader delay of about 5 seconds so the rest of the environment can finish initializing first

Optional theme config files:

- `/data/nativehbl/skin.txt`
- `/data/nativehbl/skins/<skin_id>/manifest.json`

Runtime logs:

- `/data/ps5_homebrew_launcher.log`
- `/data/ps5_homebrew_last_run.txt`

## Launch Flow

1. Load `ps5_homebrew_launcher_bootstrap.elf` from your autoloader or elfldr flow.
2. The bootstrap launches the UI as a bigapp.
3. The UI scans homebrew folders, displays entries and writes launch requests.
4. The bootstrap consumes the request and launches the selected homebrew.

Important:

- the Homebrew Launcher PKG must already be installed
- this project replaces the browser-based frontend, not the underlying installed app requirement
- if using autoloader, launch the bootstrap ELF and consider a ~5 second wait before execution

## Homebrew Locations

The launcher scans:

- `/data/homebrew`
- `/mnt/usb0/homebrew`
- `/mnt/usb1/homebrew`
- `/mnt/ext0/homebrew`
- `/mnt/ext1/homebrew`

## Supported Homebrew Layout

See [HOMEBREW_FORMAT.md](./HOMEBREW_FORMAT.md).

## Themes

Themes are software-rendered. They do not use external PNG panels anymore.

You can customize a built-in theme by creating:

- `/data/nativehbl/skins/<skin_id>/manifest.json`

Built-in skin ids:

- `default_neon`
- `sunset_cassette`
- `arctic_glass`
- `matrix_terminal`
- `ember_noir`

Theme format is documented in [SKIN_FORMAT.md](./SKIN_FORMAT.md).

## Music Preview

When a homebrew entry is selected, the launcher looks for:

- `sce_sys/sndgame.ogg`
- `sce_sys/snd0.ogg`
- `sndgame.ogg`
- `snd0.ogg`

If found, it plays the track in loop until you change selection, launch the app, or leave the launcher.

## Controls

- `Left/Right`: change selection
- `Cross`: launch selected homebrew
- `Square`: refresh scan
- `Triangle`: cycle theme
- `Circle`: exit launcher

## Build

From this directory:

```sh
make -C ps5_homebrew_launcher clean all
```

Outputs:

- `build/ps5_homebrew_launcher_bootstrap.elf`
- `build/ps5_homebrew_launcher_ui_swonly.elf`

## License

This subproject includes GPL-derived launcher backend code.

- Main license text: [COPYING](./COPYING)
- Third-party attribution: [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)

If you distribute binaries, distribute the corresponding source for the exact build as well.
