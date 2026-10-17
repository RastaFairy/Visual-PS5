# Unicode fonts in PS5 Homebrew Studio 1.1.7

## Use a multilingual font

1. Open **Resources** and choose **Import resource**.
2. Import a TrueType font with a `.ttf` extension (maximum 20 MiB). OTF/CFF files are not supported by the bundled atlas baker.
3. Select it in **Unicode font for native build (TTF)**.
4. Build with **Native UI · OpenGL 4.6 / C++20** or **Vulkan / RADV**.

Before native compilation, the IDE collects codepoints used by project text and the generated screen's built-in messages. The upstream font baker creates project-specific SDF atlases for OpenGL and Vulkan. If the font lacks a required glyph, compilation stops with the missing codepoint rather than silently rendering a blank glyph.

This supports Latin and extended Latin, Cyrillic, Greek, Japanese, Simplified/Traditional Chinese, Korean and other scripts **when the selected font contains the needed glyphs**.

## Limits

- This setting affects native game text; it does not translate the IDE UI, which remains Spanish.
- Only codepoints detected at build time are baked. Characters generated dynamically at runtime must already be represented in the project's model or require a rebuild.
- The generated virtual keyboard remains ASCII-only. A CJK input method editor (IME) and composition are not included.
- Full complex-text shaping, ligatures and right-to-left layout for Arabic, Persian, Hebrew and other RTL scripts are not claimed. Correct rendering of those scripts requires a shaping engine.
- Custom fonts may change the appearance of the six original font styles: the selected TTF is baked for all six native styles to provide consistent glyph coverage.
- The original TTF and `codepoints.txt` are retained in `.ps5hs-font-source/` in the generated native project for local rebuilds. The title package contains baked atlases rather than a separate copy of the source font.
- Check the font licence before distributing a title. The IDE does not grant redistribution rights.

Without a custom font, the project retains the default assets and glyph coverage supplied by the upstream template. The browser preview may use operating-system fallback fonts and cannot guarantee that every glyph is present in the PS5 executable.
