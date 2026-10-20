# Dusklight Cosmetics

The official cosmetics mod for [Dusklight](https://github.com/TwilitRealm/dusklight).

## Building

```sh
git clone https://github.com/TwilitRealm/dusklight-cosmetics/
cmake -B build
cmake --build build --parallel 
```

The compiled mod is `build/mods/cosmetics.dusk`. Copy it into the game's mods folder to try it:

- Windows: `%APPDATA%\TwilitRealm\Dusklight\mods`
- Linux: `~/.local/share/TwilitRealm/Dusklight/mods`
- macOS: `~/Library/Application Support/TwilitRealm/Dusklight/mods`

## For Dusklight developers

Point the build at an existing checkout instead of fetching one:

```sh
cmake -B build -DDUSKLIGHT_DIR=~/path/to/dusklight
```
