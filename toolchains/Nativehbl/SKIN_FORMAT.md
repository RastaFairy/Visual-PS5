Las skins del launcher vuelven a estar activas, pero ahora son `software-only`.

Eso significa:
- no usan PNGs externos
- no dependen de texturas de fondo
- solo cambian colores y nombre del tema
- se editan con un `manifest.json`

Ruta esperada en PS5:
- `/data/nativehbl/skins/<skin_id>/manifest.json`

Seleccion:
- `Triangle` cambia a la siguiente skin
- la skin elegida se guarda en `/data/nativehbl/skin.txt`

Formato:

```json
{
  "name": "Matrix Terminal",
  "colors": {
    "bg_top": "#061008FF",
    "bg_bottom": "#000602FF",
    "bg_grid": "#123418FF",
    "panel": "#08180CFF",
    "panel_soft": "#0C2210FF",
    "panel_strong": "#0C2C12FF",
    "border": "#24803AFF",
    "border_active": "#44FF74FF",
    "text": "#CBFFD4FF",
    "text_soft": "#80E092FF",
    "text_muted": "#52A862FF",
    "accent": "#46FF7EFF",
    "accent_alt": "#40FF84FF",
    "accent_soft": "#28FF683C",
    "ps_cross": "#40FF84FF",
    "ps_circle": "#FF4A88FF",
    "ps_square": "#FFD048FF",
    "ps_triangle": "#76FFA4FF",
    "status_bg": "#000A02DC"
  }
}
```

Notas:
- los colores aceptan `#RRGGBB` o `#RRGGBBAA`
- si falta una clave, se conserva el color base de esa skin
- el launcher trae varias skins integradas y estos `manifest.json` sirven para sobrescribirlas

Skins incluidas:
- `default_neon`
- `sunset_cassette`
- `arctic_glass`
- `matrix_terminal`
- `ember_noir`
