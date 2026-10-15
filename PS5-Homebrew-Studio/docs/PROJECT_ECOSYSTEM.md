# Ecosistema de proyectos PS5: motores, plantillas, UI y referencias

Este catálogo separa cuatro cosas que a menudo se confunden: **plantillas para empezar**, **renderers/drivers**, **kits de interfaz** y **aplicaciones completas que sirven como referencia**. El nombre “OpenGL”, “Vulkan”, “SDK” o “AI” no garantiza que un código sea intercambiable o que compile con cualquier otro.

El panel **Proyectos** muestra 34 repositorios catalogados y permite clonarlos de GitHub con Git y submódulos recursivos. Las dependencias con commits históricos fijados (`PS5_PayloadSDK` y `PS5_Mesa`) se clonan con historial completo para que sus scripts upstream puedan resolver revisiones exactas; el resto usa clones superficiales cuando es adecuado. Las fuentes no se incrustan en el ZIP del IDE: se obtienen al usarlas. Los commits y avisos de origen se guardan en `.ps5hs-source.json` junto al checkout.

## Bases que realmente sirven para iniciar un proyecto

| Proyecto | Para qué sirve | Cómo lo utiliza Homebrew Studio | Límites conocidos |
|---|---|---|---|
| [PS5 Native App Boilerplate](https://github.com/blackbearreloaded/ps5-native-app-boilerplate) | Base C++20 de título nativo, herramientas de enlazado/metadata, runtime shim propio y empaquetado de carpeta. | **Crear base C++** copia un checkout real limpio a `Documentos/PS5HomebrewStudio/Projects`, y ejecuta `tools/init-project.sh` upstream a través de WSL para aplicar `TITLE_ID` y nombre. | La base es un skeleton gráfico, no un diseñador visual ni un renderer OpenGL. El build real usa Make, LLVM y dependencias del repositorio. GPL-3.0-or-later. |
| [PS5 Homebrew UI](https://github.com/blackbearreloaded/ps5-homebrew-ui) | Aplicación de muestra y kit C++ de interfaz OpenGL: 21 diseños, 30 temas, 99 componentes reutilizables y audio de interfaz, según el README upstream. | **Crear app UI OpenGL** copia el repositorio real y configura la identidad con el inicializador upstream. | Se apoya en el stack OpenGL compatible. Las licencias de fuentes, audio y piezas de terceros deben revisarse antes de redistribuir. GPL-3.0-or-later. |
| [PS5 Vulkan Template](https://github.com/mihawk-99/PS5_VulkanTemplate) | Base de título Vulkan/RADV, generador `ps5/tools/new-title.py`, muestras, UI opcional y test suite. | **Crear título Vulkan** llama al generador upstream con nombre, `TITLE_ID` y diseño; genera un proyecto C++ independiente del lienzo de SharpProspero. **Compilar** ejecuta el build original y prepara primero la cadena requerida: `PS5_Vulkan`, `PS5_PayloadSDK` en el commit histórico fijado, `PS5_Mesa` en el commit Mesa fijado, host tools, libc runtime y archivo RADV. | El primer build RADV es pesado y requiere WSL/Linux con Clang/LLVM, Meson, Ninja, `rsync` y otras dependencias indicadas upstream. El asistente no declara compilado hasta que el proceso real termina correctamente y deja un artefacto. La base es MIT y el módulo UI opcional tiene GPL-3.0-or-later. |
| [SharpProspero](https://github.com/SvenGDK/SharpProspero) | C# / NativeAOT para aplicaciones, bibliotecas, payloads y utilidades; incluye un toolkit UI propio. | Backend de compilación real del modelo visual de esta versión para aplicaciones nativas. | En Windows exige .NET SDK 10, WSL y .NET 10 dentro de WSL. No debe confundirse un payload ELF con un título interactivo. |

## Gráficos y UI: no son equivalentes

| Repositorio | Modelo gráfico | Qué aporta | Restricción que el IDE muestra |
|---|---|---|---|
| [PS5 OpenGL 4.6 de BlackBearReloaded](https://github.com/blackbearreloaded/ps5-opengl) | OpenGL 4.6 Core / GLSL 4.60 vía Mesa/Gallium y EGL. | SDK estático, shader runtime, bridge SDL2 y ejemplos de integración como Dear ImGui, NanoVG y Sokol. | Es un stack de título nativo, con dependencias y licencia de terceros. No se convierte automáticamente el modelo de canvas de Homebrew Studio a C++. |
| [PS5 OpenGL de mihawk-99](https://github.com/mihawk-99/ps5-opengl) | Otra línea de Mesa/OpenGL. | Renderer y ejemplos del stack alternativo. | No mezclar librerías binarias, versiones ni instrucciones de build entre las dos líneas OpenGL. |
| [PS5GL](https://github.com/Rufidj/ps5gl) | API de estilo OpenGL encima de `ps5link`/`ps5gpu`/AGC. | Compatibilidad para parte de código legacy, buffers, texturas, framebuffer y una capa SDL parcial. | No es OpenGL 4.6: upstream documenta que no hay compilador GLSL completo y algunas funciones existen solo como declaraciones. |
| [PS5 VKHomebrewUI](https://github.com/mihawk-99/PS5_VKHomebrewUI) | UI con backend Vulkan/RADV. | Fork del kit UI compatible con el stack de PS5 Vulkan Template. | Se debe usar la revisión fijada por la plantilla compatible; no se mezclan forks al azar. |
| [Aurora](https://github.com/encounter/aurora) | Capa GX que usa WebGPU/Dawn por debajo, con backends Vulkan, D3D12 y Metal. | Capa de compatibilidad para proyectos de decompilación, SDL3, entrada, audio/disco, Dear ImGui y RmlUi. | Aurora por sí sola es un proyecto cross-platform; los ports de PS5 necesitan una capa PS5/platform y toolchain adicional. MIT. |
| [PS5_Mesa](https://github.com/mihawk-99/PS5_Mesa) y [PS5_Vulkan](https://github.com/mihawk-99/PS5_Vulkan) | RADV/Mesa con winsys y presentación a la plataforma PS5. | Driver real que consumen títulos Vulkan como PS5 Vulkan Template y varios ports. | Son piezas de un stack, no “añade esta DLL y ya funciona Vulkan”. Requieren sus dependencias fijadas y matriz de validación. Licencias Mesa y avisos correspondientes. |
| [ps5-vulkan independiente](https://github.com/mpereiraesaa/ps5-vulkan) | Otro backend Vulkan experimental. | Implementación separada que puede ser útil para experimentación. | No es intercambiable con RADV ni con las versiones de UI que esperan el otro backend. |
| [PS5 FSR4](https://github.com/blackbearreloaded/ps5-fsr4) | Vulkan compute. | SDK experimental de upscaling FSR 4 y aplicación showcase. | Requiere un stack y perfil diagnóstico compatibles. Leer procedencia, licencias y `THIRD_PARTY_NOTICES.md`. |
| [PS5 HelixSR](https://github.com/blackbearreloaded/ps5-helixsr) | Vulkan compute. | Runtime nativo experimental para HelixSR. | El repo declara que hay que aportar localmente `nvngx_dlss.dll`; el IDE no descarga ni redistribuye ese binario. Revisar licencias/avisos. |

## Aplicaciones de referencia y proyectos de porting

Estos repositorios son valiosos por sus estructuras, adaptadores de plataforma, entrada DualSense, persistencia, UI, audio, empaquetado y pipelines. **No son plantillas mínimas ni deben mezclarse copiando ficheros sin auditar las dependencias.**

| Proyecto | Principal valor como referencia | Estado/límite que debe conservarse |
|---|---|---|
| [ProsperoLight](https://github.com/blackbearreloaded/ProsperoLight) | Cliente Moonlight nativo: OpenGL, decodificación de vídeo, audio, input y UI en aplicación grande. | Revisar la licencia exacta de la revisión y cada dependencia. |
| [Unofficial Stremio PS5 Port](https://github.com/Sp9nky/unofficial-stremio-ps5-port) | Aplicación multimedia que combina UI, OpenGL, dependencias y vista previa de PC según su build guide. | Seguir el lock de dependencias y revisar licencia/avisos. |
| [Nativehbl](https://github.com/Rufidj/Nativehbl) | Launcher SDL2, navegación, recursos y servicios de lanzamiento. | Depende de su runtime/toolchain; comprobar la licencia upstream. |
| [PS5 Quake3e](https://github.com/griches/PS5_Quake3e) | Motor de juego real sobre Vulkan/RADV, control DualSense, audio y entrada de ratón/teclado. | Necesita los datos del juego aportados por el usuario; revisar `LICENSING.md`. |
| [PS5 Ghostship](https://github.com/griches/PS5_Ghostship) | Port de Ghostship/libultraship sobre Vulkan/RADV, menús, ajustes, entrada y saves. | No incluye ROM; el README declara generación de su arte de icono/fondo, no necesariamente generación de código. |
| [PS5 SwitchWaker](https://github.com/griches/PS5_SwitchWaker) y [PS5 Dusklight](https://github.com/griches/PS5_Dusklight) | Puertos completos que usan Aurora/Dawn WebGPU sobre RADV. | Requieren sus datos de juego y pila gráfica; compatibilidad parcial verificada en el hardware y revisiones descritos por upstream. |
| [PS5 Sunshine](https://github.com/griches/PS5_Sunshine) | Port que usa OpenGL y una base nativa C++. | Requiere la imagen de juego del usuario; no es un renderer general. |
| [Porpoise / Dolphin](https://github.com/elripalda/Porpoise-Dolphin-Emulator-for-PS5) | Launcher con biblioteca, carátulas, tarjetas de memoria, ajustes por juego y menú in-game. | Proyecto grande; no incluye juegos, BIOS ni firmware. GPL-3.0-or-later. |
| [PS5 RetroArch](https://github.com/mihawk-99/PS5_RetroArch) | Frontend modular, EmulationStation, WebUI y numerosos cores con Vulkan/RADV. | Revisar licencia individual de cada core; no incluye ROM/BIOS/firmware/claves. |
| [PS5X360 de BrinooTk](https://github.com/BrinooTk/PS5X360) | Proyecto Xenia Canary con biblioteca, DualSense, audio y RADV. | Experimental; la compatibilidad cambia por versión de firmware/jailbreak y de upstream. |
| [Syobon Action PS5](https://github.com/kvaps/syobon-action-ps5) | Adaptación SDL2 de un juego existente empaquetada con Native App Boilerplate. | Revisar licencias y dependencias del port original. |

## Build providers: qué se ejecuta realmente

| Plantilla | Comando/build upstream | Criterio de éxito en Homebrew Studio |
|---|---|---|
| Native App Boilerplate | `make` desde el proyecto en WSL/Linux; el propio Makefile prepara las dependencias fijadas y ejecuta `tools/build.sh`. | Código de salida 0 y artefacto de título `eboot.bin` o ZIP bajo `dist/`. |
| Homebrew UI (OpenGL) | `make` desde el repositorio de UI; usa su toolchain y los SDK OpenGL/native que declara el proyecto. | Código de salida 0 y artefacto de título verificable bajo `dist/`. |
| Vulkan Template | `PS5_Vulkan/tools/setup-native-dependencies.sh`, `build-host-tools.sh`, `rebuild-libc.sh` y `build-radv.sh release`; después `PS5_VulkanTemplate/ps5/tools/build.sh` con rutas explícitas al stack clonado. | Código de salida 0 y `eboot.bin` o ZIP verificado bajo el `dist/` del proyecto. |
| Canvas visual SharpProspero | Generación C# específica de SharpProspero y su pipeline NativeAOT. | Proceso de build correcto y artefacto que espera el backend configurado. |

La cadena Vulkan compila RADV desde una revisión fijada de `PS5_Mesa`; no se puede sustituir honestamente por una DLL genérica ni un `vulkan-1.dll` de Windows. En la revisión upstream consultada, `PS5_Vulkan/Makefile` y `tools/build.sh` referencian `tools/ninja-build.sh` y `tools/build-host-tools.sh`, aunque estos dos archivos no estaban presentes en el árbol publicado. Homebrew Studio comprueba esa discrepancia y, solo si faltan, restaura los scripts reales de `blackbearreloaded/ps5-native-app-boilerplate` en el checkout de trabajo. La operación se anota con origen y SHA-256 en `.ps5hs-compatibility.json`; no sustituye los scripts que ya existan ni fabrica código de compilación. El helper es el compartido que construye los archivos de `tooling/native/` y el tool `ps5-native-tool`, así que su validez depende de que esas fuentes coincidan con el ABI que espera el commit de PS5_Vulkan usado.

El primer build puede fallar por herramientas del host ausentes o consumir bastante tiempo/espacio, y el log expone el fallo real para que se pueda corregir. Si `ccache` falta, el IDE pasa `USE_CCACHE=0`, de forma que el cache opcional no sea requisito artificial. Estos proyectos C++ no son una traducción automática del canvas.

## IA declarada: usar evidencias, no suposiciones

Homebrew Studio solo marca **IA declarada** cuando el propio repositorio documenta su uso. Que un proyecto contenga `AGENTS.md`, `CLAUDE.md`, skills, instrucciones para agentes o un prompt no demuestra por sí mismo que la mayor parte de su código haya sido generada por IA. Tampoco el aspecto moderno de un repo es una señal de autoría.

| Proyecto | Declaración upstream relevante | Cómo interpretarla |
|---|---|---|
| [ProsperoEden0](https://github.com/Tiang-88/ProsperoEden0) | Su documentación indica asistencia de herramientas OpenAI y/o Anthropic. | Evidencia de asistencia declarada, no de que cada archivo haya sido generado ni de que todas las funciones estén validadas. Auditar licencia/dependencias. |
| [X360PS5 de polarco](https://github.com/polarco/X360PS5) | README y `docs/DESENVOLVIMENTO_IA.md` documentan el uso activo de Codex para investigación, implementación, automatización y documentación. El propio proyecto advierte que aún no se ha ejecutado en una PS5 ni carga juegos Xbox 360. | Un caso explícito de desarrollo asistido útil para estudiar el flujo y sus evidencias, no una base de producción validada. |
| [PS5 Homebrew UI](https://github.com/blackbearreloaded/ps5-homebrew-ui) y [PS5 Vulkan Template](https://github.com/mihawk-99/PS5_VulkanTemplate) | Incluyen guía para agentes/skills e instrucciones detalladas para asistentes de código. | Es diseño de repositorio para agentes, no prueba de que el código haya sido producido por IA. |
| [PS5 Ghostship](https://github.com/griches/PS5_Ghostship) | El README menciona arte generado mediante un generador de imágenes. | Se refiere al arte; no debe transformarse en una afirmación sobre la autoría del código. |

## Qué hace esta versión del IDE y qué no

- **Clonar**: el panel Proyectos clona la fuente original de GitHub con `git clone --recurse-submodules`. Los backend SDK heredados del panel SDKs pueden descargarse como ZIP cuando no requieren submódulos o disponen de un flujo de dependencias aparte.
- **Crear base C++20**: copia la base real del Native App Boilerplate y ejecuta su `tools/init-project.sh` para configurar el título.
- **Crear app UI OpenGL**: crea un proyecto a partir del kit real ps5-homebrew-ui y aplica la identidad con el inicializador upstream.
- **Crear título Vulkan**: ejecuta `ps5/tools/new-title.py` de PS5 Vulkan Template con parámetros seleccionados en el IDE.
- **Compilar desde el editor visual**: solo se habilita para el backend de SharpProspero que esta versión genera. Las bases C++/OpenGL/Vulkan creadas por sus asistentes son proyectos independientes; no se afirma que el lienzo genérico se traduzca a código C++ o SPIR-V automáticamente.

Cada creación declara si fue sólo generada o si se ha compilado. Un proyecto sólo figura como compilado cuando termina el pipeline real sin error y aparece un artefacto verificable. Ningún proyecto descargado recibe garantía de compatibilidad con todo firmware de PS5.
