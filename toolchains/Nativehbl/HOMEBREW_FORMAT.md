# Homebrew Format

This launcher expects each homebrew to live in its own folder.

## Important Requirement

Before using this launcher, you must have the Homebrew Launcher PKG / fake app installed on the PS5, just like with `websrv`.

This project removes the browser step, but it still uses the same underlying homebrew launch path based on that installed app context.

If you use an autoloader:

- load `ps5_homebrew_launcher_bootstrap.elf`
- do not load the UI ELF directly
- a delay of around 5 seconds is recommended before launch so the rest of the environment can finish loading

## Recommended Layout

```text
<homebrew-folder>/
├── eboot.elf
└── sce_sys/
    ├── icon0.png
    ├── param.json
    ├── sndgame.ogg   (optional)
    └── snd0.ogg      (optional fallback)
```

Example:

```text
/data/homebrew/BennuGD2/
├── eboot.elf
└── sce_sys/
    ├── icon0.png
    ├── param.json
    └── sndgame.ogg
```

## What The Launcher Uses

### Required for launch

- an ELF executable in the homebrew folder

The launcher can detect:

- `eboot.elf`
- `eboot`
- `eboot.bin`
- `homebrew.elf`
- `homebrew.bin`
- `homebrew`
- an ELF with the same name as the folder
- any ELF file found in the homebrew root

### Recommended for good presentation

- `sce_sys/icon0.png`
- `sce_sys/param.json`

If `param.json` is missing, the launcher still indexes the homebrew, but title/subtitle/description fall back to generic values.

## Music Preview

Optional music files:

- `sce_sys/sndgame.ogg`
- `sce_sys/snd0.ogg`
- `sndgame.ogg`
- `snd0.ogg`

Use OGG Vorbis for compatibility with the current launcher build.

Recommended behavior:

- short loopable preview
- moderate volume
- avoid excessively long intros

## Shared Runtime Libraries

Some ports may also require shared runtime libraries under:

- `/user/homebrew/lib`

If a homebrew works in another loader but not here, check whether it depends on shared `.so` files in that runtime location.

## Naming Advice

For best compatibility:

- rename the main executable to `eboot.elf`
- include `sce_sys/param.json`
- include `sce_sys/icon0.png`

That gives the cleanest scan and the best UI presentation.
