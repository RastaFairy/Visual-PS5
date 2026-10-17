# Matriz de SDKs y toolchains comunitarios

Para proyectos, renderers, UI y referencias consulte también [PROJECT_ECOSYSTEM.md](PROJECT_ECOSYSTEM.md). La funcionalidad se delimita según la documentación del repositorio upstream; no se infiere equivalencia por el nombre “SDK”. Las ramas y requisitos cambian, por lo que cada copia descargada debe leerse junto a su README, licencia, submódulos y build guide.

## Toolchains / formatos

| Toolchain | Producto/formato principal | Áreas | Requisitos destacados en Windows | Integración actual |
|---|---|---|---|---|
| [SharpProspero](https://github.com/SvenGDK/SharpProspero) | Aplicación `eboot.bin` y `pkg`/carpeta; biblioteca `.prx`; payload ELF | UI propia, gráficos 2D/3D, entrada, audio, multimedia, archivos, red y servicios | .NET SDK 10 en Windows; WSL y .NET 10 dentro de WSL para NativeAOT | **Backend real de compilación para la app visual C#**. Se informa éxito sólo si produce un artefacto. |
| [PS5SDK](https://github.com/PS5Dev/PS5SDK) | ELF payload / homebrew sencillo | CRT, headers y funciones documentadas de payload | CMake ≥ 3.20, Ninja, Clang/LLD, variables de firmware en ejemplos sensibles | Descarga; la UI visual de C# no se transpila a C. Upstream dice que aún no genera títulos completos. |
| [ps5-payload-dev/sdk](https://github.com/ps5-payload-dev/sdk) | Payload ELF con enlace dinámico | SDK C/C++, `prospero-clang`, samples y despliegue | Toolchain del checkout; WSL/Linux suele ser la vía práctica | Descarga; requiere proyecto C/C++ payload separado. |
| [ps5link-sdk](https://github.com/Rufidj/ps5link-sdk) | Título nativo enlazado como `eboot.bin` | Linker, imports dinámicos/NID, ejemplos GPU/input | `ps5-payload-dev/sdk`, `prospero-clang` y tooling de empaquetado compatible | Descarga; no se confunde con un payload ni con una aplicación SharpProspero. |
| [etaHEN-Plugins](https://github.com/etaHEN/etaHEN-Plugins) | Plugins/daemons de etaHEN | API de plugins y ejemplos | Requiere `ps5-payload-dev/sdk` y el submódulo `libNidResolver` | Descarga fuente; no es un backend de aplicación GUI independiente. |
| [libNidResolver](https://github.com/astrelsky/libNidResolver) | Biblioteca auxiliar para resolver NID | Dependencia del stack de plugins | Necesita el consumidor y su toolchain | Descarga separada donde los ZIP upstream no traen submódulos. |

## Renderers y stacks gráficos

| Stack | Diferencia principal | No confundir con |
|---|---|---|
| [PS5 OpenGL 4.6 (BlackBearReloaded)](https://github.com/blackbearreloaded/ps5-opengl) | Mesa/Gallium, OpenGL 4.6 / GLSL 4.60, EGL y SDL2; el repo de UI acompaña esta línea. | No es un backend Vulkan ni equivale a `ps5gl`. |
| [PS5 OpenGL (mihawk-99)](https://github.com/mihawk-99/ps5-opengl) | Línea independiente OpenGL/Mesa. | No mezclar binarios de SDK ni asumir compatibilidad directa entre forks. |
| [PS5GL](https://github.com/Rufidj/ps5gl) | API de estilo OpenGL sobre `ps5link`/AGC, con subconjunto de funciones implementadas. | No es OpenGL 4.6: su README avisa de ausencia de un compilador GLSL general. |
| [PS5 Vulkan Template](https://github.com/mihawk-99/PS5_VulkanTemplate) + [PS5_Vulkan](https://github.com/mihawk-99/PS5_Vulkan) + [PS5_Mesa](https://github.com/mihawk-99/PS5_Mesa) | Stack integrado de título, RADV/Mesa, winsys de PS5, UI Vulkan opcional y generador C++. | No es una sola biblioteca universal; las revisiones y dependencias deben coincidir. |
| [ps5-vulkan alternativo](https://github.com/mpereiraesaa/ps5-vulkan) | Backend Vulkan experimental independiente. | No intercambiable con RADV ni con un kit de UI construido para RADV. |
| [Aurora](https://github.com/encounter/aurora) | Capa GX/WebGPU de fuentes comunes, con SDL3, Dear ImGui, RmlUi y backends multiplataforma. | No es por sí sola un port PS5 completo. |
| [PS5 Homebrew UI / OpenGL](https://github.com/blackbearreloaded/ps5-homebrew-ui) y [PS5 VKHomebrewUI](https://github.com/mihawk-99/PS5_VKHomebrewUI) | Kits visuales que comparten ideas y componentes, pero tienen diferentes backends de render. | No asumir que las implementaciones OpenGL y Vulkan son intercambiables. |

## Builds integrados y dependencias históricas

La ruta Native App Boilerplate y la app Homebrew UI se compilan con `make` dentro de WSL/Linux, usando los scripts de build upstream. La ruta Vulkan necesita tres checkouts con papeles distintos: `PS5_Vulkan` (scripts de linking/tools), `PS5_PayloadSDK` (fork de SDK de plataforma) y `PS5_Mesa` (fuente de RADV). El IDE clona los dos forks con historial completo porque los scripts consultan commits exactos, ejecuta los scripts upstream de preparación y solo marca éxito tras comprobar el proceso y el artefacto. El primer build RADV necesita herramientas de desarrollo Linux y puede ser pesado; no se descarga un driver genérico ni se inventa un binario.

## Reglas del IDE

1. El modelo de proyecto y el panel de diagnósticos son comunes; el generador y el build provider dependen del backend.
2. La versión actual genera código de UI para SharpProspero. Los asistentes de C++/OpenGL/Vulkan llaman a generadores o inicializadores upstream para crear proyectos independientes; no traducen automáticamente el lienzo a cualquier API gráfica.
3. La instalación de un checkout no equivale a instalar todas sus dependencias. La salida del generador no equivale a compilación; la compilación no equivale a prueba en consola.
4. No se descargan firmware, llaves, binarios de Sony, `libc.prx` propietario, ROMs, BIOS ni datos de juegos.
5. La etiqueta **IA declarada** sólo se muestra cuando el repo lo declara. `AGENTS.md`, `CLAUDE.md` o instrucciones para agentes indican que el repositorio está preparado para asistentes, no la autoría total por IA.

### Compatibilidad del build RADV

La cadena Vulkan necesita que `PS5_Vulkan/tools/build.sh` pueda construir `build/host/ps5-native-tool`. En el árbol consultado, `Makefile`/`tools/build.sh` referencian `tools/ninja-build.sh` y `tools/build-host-tools.sh`, pero no están en la raíz `tools/`. Homebrew Studio restaura estos helpers desde la base pública `blackbearreloaded/ps5-native-app-boilerplate` solo cuando faltan y registra origen/SHA-256 en `.ps5hs-compatibility.json`. Se preserva cualquier archivo preexistente; después, la compilación debe validar las fuentes compartidas del checkout real.
