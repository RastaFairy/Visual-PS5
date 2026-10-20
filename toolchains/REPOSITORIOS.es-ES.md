# Inventario de repositorios para PS5 Homebrew Studio

Fecha de auditoría: 2026-10-20  
Repositorio que conservará las copias: [RastaFairy/Visual-PS5](https://github.com/RastaFairy/Visual-PS5/tree/main/toolchains)

## Regla de mantenimiento

Los repositorios de esta lista se guardan como **copias de código versionadas dentro de este repositorio**, no como submódulos Git. Los archivos `.ps5hs-source.json` registran procedencia y revisión; el IDE debe utilizar primero la copia local y no exigir una carpeta `.git` anidada ni volver a clonar el upstream.

Las nuevas copias se preparan con `.github/workflows/vendor-toolchains.yml` y `.github/scripts/vendor-toolchains.sh`. El resultado de cada ejecución se registra en `REPOSITORY-VENDOR-REPORT.json`. La automatización no debe sustituir una carpeta de destino que ya exista pero no tenga un manifiesto válido.

Esta estrategia elimina la dependencia de que la cuenta original siga publicada **para las fuentes que ya se hayan incorporado**. No convierte por sí sola en offline las dependencias genéricas de build (por ejemplo, zlib, herramientas de compilación, paquetes Linux, fuentes de Mesa descargadas por scripts upstream ni dependencias de Python). Esas dependencias se deben fijar, verificar por hash y auditar por separado.

## A. Toolchains y plantillas principales

| Directorio en `toolchains/` | Repositorio de procedencia | Uso en el IDE | Estado antes de la sincronización |
|---|---|---|---|
| `SharpProspero` | `SvenGDK/SharpProspero` | Backend C# / NativeAOT y aplicaciones nativas | Ya versionado |
| `PS5SDK` | `PS5Dev/PS5SDK` | SDK alternativo para payloads ELF C/C++ | Ya versionado |
| `ps5-payload-sdk` | `ps5-payload-dev/sdk` | SDK de payloads C/C++ | Ya versionado |
| `ps5link-sdk` | `Rufidj/ps5link-sdk` | Enlace de títulos nativos / eboot.bin | Ya versionado |
| `etaHEN-Plugins` | `etaHEN/etaHEN-Plugins` | Plugins y daemons de etaHEN | Ya versionado |
| `libNidResolver` | `astrelsky/libNidResolver` | Dependencia de etaHEN-Plugins | Ya versionado |
| `ps5-native-app-boilerplate` | `blackbearreloaded/ps5-native-app-boilerplate` | Base C/C++20, runtime, metadatos, empaquetado y pruebas | Ya versionado |
| `ps5-opengl` | `blackbearreloaded/ps5-opengl` | Mesa/Gallium, EGL, compilación de shaders y SDK OpenGL | Ya versionado |
| `ps5-homebrew-ui` | `blackbearreloaded/ps5-homebrew-ui` | Kit de UI y componentes OpenGL | Ya versionado |
| `PS5_VulkanTemplate` | `mihawk-99/PS5_VulkanTemplate` | Generador de títulos Vulkan | Ya versionado |
| `PS5_Vulkan` | `mihawk-99/PS5_Vulkan` | Driver Vulkan/RADV y herramientas del backend | Ya versionado |
| `PS5_PayloadSDK` | `mihawk-99/PS5_PayloadSDK` | Fork del SDK requerido por el stack Vulkan | Ya versionado; el historial Git no se incluye |
| `PS5_Mesa` | `mihawk-99/PS5_Mesa` | Fork Mesa/RADV con la capa de plataforma PS5 | Ya versionado; el historial Git no se incluye |
| `ps5-ultrapack` | `knutwurst/ps5-ultrapack` | Empaquetado ffpfs/ffpfsc/PKG | Ya versionado |
| `PS5_PayloadSDK-pinned-b83202be` | `mihawk-99/PS5_PayloadSDK`, commit `b83202be73e930050e00de0f1b4d9ec46c0391bf` | Snapshot exacto requerido por el build Vulkan cuando no existe historial Git local | Añadido por la sincronización |

**Importante:** las carpetas ya versionadas con historial vacío en su manifiesto se conservan como snapshots; no se inventa su commit original. La revisión exacta se considera desconocida cuando el manifiesto antiguo no la registró.

## B. Backends alternativos, utilidades y ejemplos de referencia

Estos repositorios son útiles porque aparecen en el catálogo SDK/Proyectos, pero no todos son requisitos para compilar la IDE ni para los backends principales. Se mantienen separados para no mezclar forks gráficos incompatibles ni convertir aplicaciones completas en dependencias del compilador.

| Directorio en `toolchains/` | Repositorio declarado por el catálogo | Fuente a copiar | Propósito |
|---|---|---|---|
| `ps5-vulkan-alt` | `mpereiraesaa/ps5-vulkan` | Mismo repositorio | Driver Vulkan experimental alternativo |
| `PS5_VKHomebrewUI` | `mihawk-99/PS5_VKHomebrewUI` | Mismo repositorio | Kit UI alternativo para experiencias PS5 |
| `ProsperoLight` | `blackbearreloaded/ProsperoLight` | `LedyBacer/ProsperoLight` (repositorio movido/mirror) | Aplicación de referencia Moonlight |
| `ProsperoEden0` | `Tiang-88/ProsperoEden0` | Mismo repositorio | Aplicación experimental de referencia |
| `unofficial-stremio-ps5-port` | `Sp9nky/unofficial-stremio-ps5-port` | Mismo repositorio | Aplicación multimedia de referencia |
| `Nativehbl` | `Rufidj/Nativehbl` | Mismo repositorio | Launcher nativo SDL2 |
| `ps5gl` | `Rufidj/ps5gl` | Mismo repositorio | API gráfica con forma OpenGL sobre AGC; API parcial |
| `ps5-opengl-mihawk` | `mihawk-99/ps5-opengl` | Mismo repositorio | Fork OpenGL alternativo, separado del backend principal |
| `ps5-fsr4` | `blackbearreloaded/ps5-fsr4` | `manoma080/ps5-fsr4` (mirror) | **Snapshot source-only**: el submódulo `external/ps5-vulkan` referencia el commit `4bb0c8b1423698a7369efc22b829bf16a99e7128` del upstream ausente; no es un backend compilable completo |
| `ps5-helixsr` | `blackbearreloaded/ps5-helixsr` | `manoma080/ps5-helixsr` (mirror) | **Snapshot source-only**: el submódulo `external/ps5-vulkan` referencia el commit `6875f21438b7e51a1377a30f2d7f77b3e0154cd6` del upstream ausente; no es un backend compilable completo. Además, requiere DLL legítima del usuario |
| `PS5_Sunshine` | `griches/PS5_Sunshine` | Mismo repositorio | Port y ejemplo OpenGL |
| `PS5_SwitchWaker` | `griches/PS5_SwitchWaker` | Mismo repositorio | Port de referencia WebGPU/RADV; datos propios del juego |
| `PS5_Dusklight` | `griches/PS5_Dusklight` | Mismo repositorio | Port de referencia WebGPU/RADV; datos propios del juego |
| `PS5_Ghostship` | `griches/PS5_Ghostship` | Mismo repositorio | Port nativo de referencia Vulkan |
| `Porpoise-Dolphin-Emulator-for-PS5` | `elripalda/Porpoise-Dolphin-Emulator-for-PS5` | Mismo repositorio | Emulador de referencia Vulkan |
| `PS5X360` | `BrinooTk/PS5X360` | Mismo repositorio | Prototipo de Xenia/DirectX sobre PS5 |
| `syobon-action-ps5` | `kvaps/syobon-action-ps5` | Mismo repositorio | Ejemplo de port SDL2 |
| `aurora` | `encounter/aurora` | Mismo repositorio | Capa GX/WebGPU para proyectos GameCube/Wii |
| `PS5_Quake3e` | `griches/PS5_Quake3e` | Mismo repositorio | Motor/port de referencia Vulkan-RADV |
| `PS5_RetroArch` | `mihawk-99/PS5_RetroArch` | Mismo repositorio | Frontend modular de emulación; no contiene ROMs/BIOS |
| `X360PS5-AI-Prototype` | `polarco/X360PS5` | Mismo repositorio | Prototipo experimental Xenia/Vulkan |

La copia automatizada deja constancia de los submódulos ausentes o de archivos grandes. FSR4 y HelixSR se conservan como snapshots de código fuente con un estado `vendored-source-only`, porque su Gitlink `external/ps5-vulkan` apunta a commits que no existen en los forks accesibles. El manifiesto registra esos SHAs y `buildableWithoutExternalRepo=false`: no se oculta ni se sustituye el driver por otro commit incompatible. Cualquier otro submódulo ausente o archivo individual de más de 95 MiB bloquea la incorporación para evitar copias engañosas.

## C. Dependencias indirectas detectadas dentro de las plantillas

- `PS5_VulkanTemplate/.gitmodules` declara GLM y Vulkan-Assets. Sus archivos se encuentran dentro del árbol versionado bajo `PS5_VulkanTemplate/external/glm` y `PS5_VulkanTemplate/assets`; se deben conservar como archivos ordinarios, no como submódulos externos.
- El build Vulkan usa el commit exacto `b83202be73e930050e00de0f1b4d9ec46c0391bf` de `PS5_PayloadSDK`. El snapshot dedicado evita requerir el historial Git de la carpeta ordinaria.
- El build OpenGL usa el código local de `ps5-opengl`, pero su SDK precompilado y varias dependencias de compilación se descargan/generan aparte. El error HTTP 404 observado en la versión 1.1.19 demuestra que una release no se debe considerar disponible solo porque el repositorio fuente exista.
- Los archivos de licencia y avisos de terceros de cada repositorio deben permanecer al lado de su código. No se deben agregar firmware, claves privadas, juegos, ROMs, BIOS ni DLL propietarias.

## D. Criterios de aceptación de la sincronización

1. Cada directorio integrado tiene `.ps5hs-source.json` con repositorio declarado, fuente efectiva (si es espejo), revisión exacta cuando se conoce y marca `vendoredSnapshot`. Los snapshots source-only declaran submódulos sin resolver y no figuran como compilables.
2. Cada carpeta de código se guarda bajo `toolchains/<folder>` en el árbol principal de Git; no depende de un `.git` anidado.
3. `InstallRepo` reconoce el manifiesto local compatible y no vuelve a clonar una fuente ya integrada.
4. Los repositorios ausentes, las copias parciales y los límites de tamaño quedan señalados en `REPOSITORY-VENDOR-REPORT.json`.
5. Los backends OpenGL y Vulkan se deben probar en Windows/WSL real tras la incorporación; el inventario de fuentes por sí solo no equivale a una compilación comprobada.
