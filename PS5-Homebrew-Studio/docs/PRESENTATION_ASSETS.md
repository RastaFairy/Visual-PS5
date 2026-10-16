# Recursos de presentación de títulos nativos

Esta guía describe los recursos de presentación que el IDE puede reemplazar en una aplicación nativa ya inicializada. No es una guía para cambiar el tema global de la consola.

## Archivos que consume el paquete

| Archivo | Uso | Formato validado |
|---|---|---|
| `sce_sys/icon0.png` | Icono de la app en la pantalla de inicio | PNG 512×512 |
| `sce_sys/pic0.dds` | Fondo cuando la app está seleccionada | DDS DX10, BC7_UNORM, 3840×2160, una superficie, sin mipmaps |
| `sce_sys/pic1.dds` | Fondo de la transición al lanzar la app | Mismo perfil BC7 que `pic0.dds` |
| `sce_sys/snd0.at9` | Música mientras la app está seleccionada | ATRAC9 en contenedor RIFF/WAVE, 48 kHz, en bucle, máximo 2 MiB |

El perfil está basado en el [PS5 Native App Boilerplate](https://github.com/blackbearreloaded/ps5-native-app-boilerplate) y su `tools/prepare-assets.ps1`, que convierte recursos y valida el conjunto antes de usarlos. El botón **Presentación** invoca ese script upstream: no implementa una conversión DDS o ATRAC9 propia.

## Preparar las herramientas

En Windows instala DirectXTex `texconv`:

```powershell
winget install Microsoft.DirectXTex.Texconv
```

Cierra y vuelve a abrir el servidor si acabas de instalarlo para refrescar `PATH`. La conversión de audio convencional usa FFmpeg y un ejecutable ATRAC9 compatible (`ps4_at9tool.exe`). Debes obtener el codificador de forma legítima; el IDE no lo descarga ni lo redistribuye. También puedes elegir un `.at9` existente si ya pasa la validación upstream, sin necesitar un codificador.

## Uso desde el IDE

1. Abre **Proyectos** y busca una carpeta de título ya inicializada (con `sce_sys/param.json`).
2. Pulsa **Presentación**. La tarjeta muestra qué archivos existen y qué herramientas se detectan.
3. Selecciona un icono, el fondo de selección (`pic0.dds`), el fondo de lanzamiento (`pic1.dds`), audio o cualquier combinación. Si aún no existe el par de fondos, selecciona los dos; cuando ambos existan, puedes sustituir uno de ellos por separado. Los campos vacíos mantienen los archivos existentes.
4. Pulsa **Aplicar cambios**. El servidor prepara todo en una carpeta temporal, llama a `tools/prepare-assets.ps1` y solo copia el conjunto final al proyecto si pasa la validación.
5. Compila el título otra vez y empaqueta el resultado nuevo. El editor actualiza los fuentes del proyecto, no instala directamente el título en la consola.

El icono se convierte a 512×512. Los fondos de selección y lanzamiento pueden ser imágenes distintas y se convierten de forma independiente a `pic0.dds` y `pic1.dds`. Para música normal, el script upstream prepara un fragmento de hasta 15 segundos, lo normaliza y lo codifica como ATRAC9 en bucle. Respeta los límites y requisitos que indique la versión concreta del script instalado.

## Límites de alcance

Estos archivos personalizan la presentación de la aplicación seleccionada: no cambian el fondo global de la pantalla de inicio, los iconos de otras apps ni la música de arranque del sistema. Para temas de sistema en una PS5 modificada existe el proyecto [Blaze414/ps5-theme](https://github.com/Blaze414/ps5-theme), que funciona como plugin/payload con un overlay en memoria y documenta compatibilidad publicada hasta firmware 13.60. Es un proyecto distinto y requiere su propio despliegue y pruebas en consola.

## Fuentes upstream

- [Native App Boilerplate — getting started](https://github.com/blackbearreloaded/ps5-native-app-boilerplate/blob/main/docs/platform/GETTING_STARTED.md)
- [Native App Boilerplate — preparation script](https://github.com/blackbearreloaded/ps5-native-app-boilerplate/blob/main/tools/prepare-assets.ps1)
- [PS5 Themes](https://github.com/Blaze414/ps5-theme) — solo para tema global de consola modificada.
