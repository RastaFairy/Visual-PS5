# Catálogo upstream — matriz de orientación (versión 1.0.0)

Este documento resume el catálogo integrado en la versión 1.0.0. Es una guía de navegación, no una auditoría actual de cada repositorio ni una garantía de compilación. Las ramas, commits, licencias y dependencias externas pueden cambiar. Antes de ejecutar o redistribuir software, inspecciona el repositorio y registra el commit utilizado.

## Claves de lectura

- **SDK/payload:** librerías y herramientas de runtime o payload; no implica que produzca una aplicación completa.
- **Plantilla/título nativo:** una base para compilar un título; necesita el SDK y pipeline concretos.
- **Renderer/driver/UI:** componentes gráficos o de interfaz; no son plantillas autónomas.
- **Referencia/port:** código real que estudiar o portar; no suele ser una plantilla mínima.
- **Licencia:** los resúmenes son orientativos. Verifica LICENSE, NOTICE y las licencias transitivas en el commit utilizado.

## Repositorios del catálogo

| Nombre | Repositorio | Función principal | Nota de uso |
|---|---|---|---|
| SharpProspero | [SvenGDK/SharpProspero](https://github.com/SvenGDK/SharpProspero) | SDK C# y toolchain de aplicaciones/payloads | Comprobar .NET/NativeAOT |
| PS5SDK | [PS5Dev/PS5SDK](https://github.com/PS5Dev/PS5SDK) | SDK de payloads ELF C/C++ | No construye títulos completos por defecto |
| ps5-payload-dev/sdk | [ps5-payload-dev/sdk](https://github.com/ps5-payload-dev/sdk) | SDK para payloads C/C++ | Revisar toolchain y muestras |
| ps5link-sdk | [Rufidj/ps5link-sdk](https://github.com/Rufidj/ps5link-sdk) | Enlace/paquetizado de títulos nativos | Runtime compatible requerido |
| etaHEN-Plugins | [etaHEN/etaHEN-Plugins](https://github.com/etaHEN/etaHEN-Plugins) | Plugins/daemons etaHEN | No es una GUI independiente |
| libNidResolver | [astrelsky/libNidResolver](https://github.com/astrelsky/libNidResolver) | Dependencia de plugins | Revisar submódulos |
| PS5 Native App Boilerplate | [blackbearreloaded/ps5-native-app-boilerplate](https://github.com/blackbearreloaded/ps5-native-app-boilerplate) | Plantilla C/C++ para títulos nativos | Clonar con Git y submódulos |
| PS5 OpenGL 4.6 | [blackbearreloaded/ps5-opengl](https://github.com/blackbearreloaded/ps5-opengl) | Stack OpenGL 4.6/GLSL | Dependencias específicas |
| PS5 Homebrew UI (OpenGL) | [blackbearreloaded/ps5-homebrew-ui](https://github.com/blackbearreloaded/ps5-homebrew-ui) | Kit visual OpenGL | Revisar GPL upstream |
| PS5 Vulkan Template | [mihawk-99/PS5_VulkanTemplate](https://github.com/mihawk-99/PS5_VulkanTemplate) | Plantilla Vulkan/RADV con generador | Necesita stack Vulkan compatible |
| PS5_Vulkan / RADV | [mihawk-99/PS5_Vulkan](https://github.com/mihawk-99/PS5_Vulkan) | Driver/plataforma Vulkan | Dependencia central del backend |
| PS5_PayloadSDK (fork RADV) | [mihawk-99/PS5_PayloadSDK](https://github.com/mihawk-99/PS5_PayloadSDK) | SDK compañero Vulkan | Puede necesitar historial Git completo |
| ps5-vulkan (alternativo) | [mpereiraesaa/ps5-vulkan](https://github.com/mpereiraesaa/ps5-vulkan) | Driver alternativo experimental | No mezclar APIs sin validar |
| PS5 VKHomebrewUI | [mihawk-99/PS5_VKHomebrewUI](https://github.com/mihawk-99/PS5_VKHomebrewUI) | Kit UI Vulkan | Usar revisión compatible |
| ProsperoLight | [blackbearreloaded/ProsperoLight](https://github.com/blackbearreloaded/ProsperoLight) | Aplicación de referencia Moonlight | Proyecto grande, no plantilla mínima |
| ProsperoEden0 | [Tiang-88/ProsperoEden0](https://github.com/Tiang-88/ProsperoEden0) | Port experimental de referencia | Auditar todas las dependencias |
| Unofficial Stremio PS5 Port | [Sp9nky/unofficial-stremio-ps5-port](https://github.com/Sp9nky/unofficial-stremio-ps5-port) | Aplicación multimedia | Revisar fuentes/licencias de multimedia |
| Nativehbl | [Rufidj/Nativehbl](https://github.com/Rufidj/Nativehbl) | Launcher homebrew/SDL2 | No intercambiar con runtime de UI |
| PS5GL | [Rufidj/ps5gl](https://github.com/Rufidj/ps5gl) | API OpenGL-shaped sobre AGC | API parcial; verificar funciones |
| PS5 OpenGL (fork alternativo) | [mihawk-99/ps5-opengl](https://github.com/mihawk-99/ps5-opengl) | Fork alternativo del renderer | No mezclar SDK de revisiones distintas |
| PS5 FSR4 | [blackbearreloaded/ps5-fsr4](https://github.com/blackbearreloaded/ps5-fsr4) | Upscaling compute experimental | Revisar licencias y dependencias |
| PS5 HelixSR | [blackbearreloaded/ps5-helixsr](https://github.com/blackbearreloaded/ps5-helixsr) | Runtime experimental de upscaling | Revisar requisitos externos upstream |
| PS5 Sunshine | [griches/PS5_Sunshine](https://github.com/griches/PS5_Sunshine) | Port/referencia OpenGL | Datos de juego no incluidos |
| PS5 SwitchWaker | [griches/PS5_SwitchWaker](https://github.com/griches/PS5_SwitchWaker) | Port WebGPU/RADV | Recursos de juego no incluidos |
| PS5 Dusklight | [griches/PS5_Dusklight](https://github.com/griches/PS5_Dusklight) | Port WebGPU/RADV experimental | No asumir que sea plantilla genérica |
| PS5 Ghostship | [griches/PS5_Ghostship](https://github.com/griches/PS5_Ghostship) | Port/referencia Vulkan | Revisar dependencias/assets |
| Porpoise Dolphin Emulator | [elripalda/Porpoise-Dolphin-Emulator-for-PS5](https://github.com/elripalda/Porpoise-Dolphin-Emulator-for-PS5) | Emulador de referencia Vulkan | No incluye ROMs/BIOS |
| PS5X360 (Xenia Canary) | [BrinooTk/PS5X360](https://github.com/BrinooTk/PS5X360) | Emulador experimental Vulkan/RADV | Revisar estado, licencia y assets |
| Syobon Action PS5 | [kvaps/syobon-action-ps5](https://github.com/kvaps/syobon-action-ps5) | Juego SDL2/port de referencia | Referencia de porting |
| PS5_Mesa / RADV | [mihawk-99/PS5_Mesa](https://github.com/mihawk-99/PS5_Mesa) | Mesa/RADV y winsys PS5 | Puede requerir commit exacto |
| Aurora | [encounter/aurora](https://github.com/encounter/aurora) | Capa de compatibilidad GX/WebGPU | Dependencias y licencia propias |
| PS5 Quake3e | [griches/PS5_Quake3e](https://github.com/griches/PS5_Quake3e) | Motor/port Vulkan-RADV | Requiere datos del juego |
| PS5 RetroArch | [mihawk-99/PS5_RetroArch](https://github.com/mihawk-99/PS5_RetroArch) | Frontend de emulación | Licencias por core; sin ROMs/BIOS |
| X360PS5 (asistencia IA declarada) | [polarco/X360PS5](https://github.com/polarco/X360PS5) | Prototipo Xenia/Vulkan experimental | No asumir que esté probado en consola |

El catálogo es heterogéneo. Sus 34 elementos no son SDKs equivalentes ni se compilan desde una interfaz única. Categoría, rama, submódulos, commits y dependencias importan.

## Política de instalación

1. Usa Git cuando haya submódulos o commits fijados; un ZIP no conserva historial ni inicializa submódulos.
2. Lee el README de la rama exacta y ejecuta primero cualquier modo de comprobación.
3. Registra el SHA del commit y versión de compiladores.
4. No ejecutes scripts privilegiados sin revisarlos.
5. Antes de distribuir un binario, revisa la licencia de cada dependencia y los assets empaquetados.

## Referencias externas

La matriz procede del catálogo de la aplicación en versión 1.0.0. Debe verificarse antes de cada release. Consulta [ps5-homebrew-ui](https://github.com/blackbearreloaded/ps5-homebrew-ui), [native-app-boilerplate](https://github.com/blackbearreloaded/ps5-native-app-boilerplate) y [PS5_VulkanTemplate](https://github.com/mihawk-99/PS5_VulkanTemplate) para la documentación y licencias upstream.
