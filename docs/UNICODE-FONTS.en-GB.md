# Unicode fonts in PS5 Homebrew Studio 1.1.7

## Use a multilingual font

1. Open **Resources** and choose **Import resource**.
2. Import a TrueType font with a `.ttf` extension (maximum 20 MiB). OTF/CFF files are not supported by the bundled atlas baker.
3. Select it in **Unicode font for native build (TTF)**.
4. Build with **Native UI · OpenGL 4.6 / C++20** or **Vulkan / RADV**.

Before native compilation, the IDE collects codepoints used by the project text and the generated screen's built-in messages. The upstream font baker produces project-specific SDF atlases, and the six native font styles are baked from the selected face. Glyph coverage is validated. If the face is missing a required character, the build stops with the missing codepoint instead of silently producing a blank glyph.

This supports Latin and extended Latin, Cyrillic, Greek, Japanese, Simplified/Traditional Chinese, Korean and other writing systems **when the chosen font contains the required glyphs**. A universal atlas containing every Unicode character is not required.

## Limits and behaviour

- The setting affects native game text. It does not translate the IDE itself, whose UI remains Spanish.
- Only characters detected at build time are baked. Characters generated dynamically at runtime must already be present in the model or the project must be rebuilt with those characters included.
- The generated virtual keyboard remains ASCII-only. No Japanese/Chinese/Korean input method editor (IME) or composition is included.
- Full complex-text shaping, ligatures and right-to-left layout for Arabic, Persian, Hebrew and other RTL scripts are not claimed. Unicode strings can be stored, but correct rendering of those scripts requires a shaping engine.
- Custom fonts may change the visual appearance of the original six font styles: the chosen TTF is baked for all six native styles to provide consistent glyph coverage.
- The original font and `codepoints.txt` are retained under `.ps5hs-font-source/` in the generated native project for local rebuilds. The title package contains baked atlases, not a separate copy of the original TTF.
- The IDE does not grant rights to a font. Check its licence before distributing a game.

Without a custom font, the project keeps the default font assets and glyph coverage supplied by the upstream template. The browser preview may use operating-system fallback fonts and does not by itself guarantee that every glyph is present in the PS5 executable.
