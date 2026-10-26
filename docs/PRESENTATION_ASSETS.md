# Recursos de presentación de títulos nativos

Esta guía describe los recursos de presentación que el IDE puede reemplazar en una aplicación nativa ya inicializada. No es una guía para cambiar el tema global de la consola.

## Archivos que consume el paquete

| Archivo | Uso | Formato validado |
|---|---|---|
| `sce_sys/icon0.png` | Icono de la app en la pantalla de inicio | PNG 512×512 |
| `sce_sys/pic0.dds` | Fondo cuando la app está seleccionada | DDS DX10, BC7_UNORM, 3840×2160, una superficie, sin mipmaps |
| `sce_sys/pic1.dds` | Fondo de la transición al lanzar la app | Mismo perfil BC7 que `pic0.dds` |
| `sce_sys/snd0.at9` | Música mientras la app está seleccionada | ATRAC9 en contenedor RIFF/WAVE, 48 kHz, en bucle, máximo 2 MiB |

El perfil de los archivos está basado en el [PS5 Native App Boilerplate](https://github.com/blackbearreloaded/ps5-native-app-boilerplate). El IDE usa su `tools/prepare-assets.ps1` para validar el conjunto final. Antes de esa validación, el IDE codifica localmente WAV, MP3, FLAC y AIFF/AIFC con la toolchain ATRAC9 incluida en `toolchains/ps5-at9-converter/`.

## Preparar las herramientas

Para convertir imágenes, instala DirectXTex `texconv`:

```powershell
winget install Microsoft.DirectXTex.Texconv
```

La conversión de música no requiere FFmpeg ni el codificador propietario `ps4_at9tool.exe`. Homebrew Studio incluye el codificador de código abierto ATRAC9 y sus fuentes, avisos de terceros y licencia en `toolchains/ps5-at9-converter/`; se ejecuta dentro de la distribución WSL incluida y no accede a Internet. El código del encoder está bajo GPL-3.0-or-later; revisa `LICENSE` y `THIRD_PARTY_NOTICES.md` antes de redistribuir. También se puede importar un `.at9` ya codificado para validarlo y copiarlo.

## Uso desde el IDE

1. Abre **Proyectos** y busca una carpeta de título ya inicializada (con `sce_sys/param.json`).
2. Pulsa **Presentación**. La tarjeta muestra qué archivos existen y qué herramientas se detectan.
3. Selecciona un icono, el fondo de selección (`pic0.dds`), el fondo de lanzamiento (`pic1.dds`), música en `.at9`, `.wav`, `.mp3`, `.flac`, `.aiff`, `.aif` o `.aifc`, o cualquier combinación. Si aún no existe el par de fondos, selecciona los dos; cuando ambos existan, puedes sustituir uno de ellos por separado. Los campos vacíos mantienen los archivos existentes.
4. Pulsa **Aplicar cambios**. El servidor prepara todo en una carpeta temporal, convierte la música con la toolchain local cuando hace falta, valida el conjunto con `tools/prepare-assets.ps1` y solo copia los archivos finales si pasan la validación.
5. Compila el título otra vez y empaqueta el resultado nuevo. El editor actualiza los fuentes del proyecto, no instala directamente el título en la consola.

El icono se convierte a 512×512. Los fondos de selección y lanzamiento pueden ser imágenes distintas y se convierten de forma independiente a `pic0.dds` y `pic1.dds`. La herramienta ATRAC9 integrada genera audio estéreo a 48 kHz, a 192 kb/s, con objetivo de -28 LUFS y bucle, y limita la duración para respetar el máximo de 2 MiB. Si una entrada de audio no puede decodificarse o el resultado no cumple el perfil validado, la operación se cancela sin aplicar un archivo parcial.

## Límites de alcance

Estos archivos personalizan la presentación de la aplicación seleccionada: no cambian el fondo global de la pantalla de inicio, los iconos de otras apps ni la música de arranque del sistema. Para temas de sistema en una PS5 modificada existe el proyecto [Blaze414/ps5-theme](https://github.com/Blaze414/ps5-theme), que funciona como plugin/payload con un overlay en memoria y documenta compatibilidad publicada hasta firmware 13.60. Es un proyecto distinto y requiere su propio despliegue y pruebas en consola.

## Fuentes upstream

- [Native App Boilerplate — getting started](https://github.com/blackbearreloaded/ps5-native-app-boilerplate/blob/main/docs/platform/GETTING_STARTED.md)
- [Native App Boilerplate — preparation script](https://github.com/blackbearreloaded/ps5-native-app-boilerplate/blob/main/tools/prepare-assets.ps1)
- [PS5 Themes](https://github.com/Blaze414/ps5-theme) — solo para tema global de consola modificada.
