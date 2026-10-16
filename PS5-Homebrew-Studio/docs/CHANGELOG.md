# Registro de cambios

## 1.0.3 — 16 de octubre de 2026

- Corrige el empaquetado de imágenes del generador visual: los IDs se gestionan coherentemente como `Map`, sin llamar a `.add()`.
- Normaliza los finales de línea de archivos de texto críticos para el build nativo al crear el proyecto y justo antes de compilar en WSL; cubre scripts `.sh`, Makefiles, fuentes C/C++, `CMakeLists.txt` y manifiestos `.sha256`.
- Declara `*.sha256 text eol=lf` en `.gitattributes` del proyecto generado y fija `core.autocrlf=false` para nuevos clones.
- Mantiene intacta la comprobación SHA-256 del runtime; corrige el formato del manifiesto en vez de desactivar la protección.


## 1.0.0 — Generación visual nativa C++20

- Convierte el lienzo y los flujos visuales en pantallas C++20 compatibles con el contrato `hui::app::Concept` del kit `ps5-homebrew-ui` y su fork Vulkan.
- Añade un flujo de interfaz para generar y compilar diseños nativos: selección de nombre/TITLE_ID, creación en un directorio separado, log en vivo y validación del artefacto real de salida.
- Backend OpenGL: carga RGBA8 desde `assets/ps5hs`, después de decodificar las imágenes en el navegador y reducirlas a un máximo de 512×512. Limita a 16 recursos únicos y registra hash/procedencia de los ficheros en el manifiesto.
- Backend Vulkan: inyecta la pantalla generada en el título creado por `PS5_VulkanTemplate` y usa CMake/Ninja/RADV. Las imágenes RGBA8 se registran en `ps5/assets.json`, se empaquetan en `/app0/assets/ps5hs/` y se suben con `VkRenderer::create_texture`; añade además un aviso de licencia para recursos aportados por el usuario.
- Expone `visualBackend` y `generatedFromStudio` en el registro de proyectos nativos, incluye tests Node.js de los generadores y actualiza avisos de uso/licencias.
- Añade teclado nativo en pantalla para `input` en ambos generadores C++: navegación con cruceta, letras ASCII, dígitos, puntuación básica, espacio, borrar, limpiar, aceptar/cancelar y disparo del evento `change`. No se presenta como IME multilingüe del sistema.

### Validación

`node --check app.js`, `node --check runtime/native-generator.js` y `node runtime/test-native-generator.js` pasan. Clang también ha comprobado el código C++ generado para ambas rutas contra interfaces de prueba locales; esto no sustituye la compilación con los headers/SDK completos ni una prueba en PS5. El entorno no dispone de PowerShell ni del toolchain PS5 completo, por lo que el parser oficial de PowerShell y el build final deben ejecutarse en Windows/WSL, donde `start.bat` analiza `runtime/server.ps1` antes de arrancar.

## 0.2.0 — Ecosistema de proyectos nativos

- Amplía el panel Proyectos a 34 repositorios: boilerplates C++20, OpenGL 4.6, kits UI, Vulkan/RADV, Mesa/winsys, Aurora/WebGPU, upscaling experimental y aplicaciones completas de referencia.
- Distingue bases de proyecto, renderers, drivers, dependencias y aplicaciones de referencia. Los repositorios grandes no se presentan como boilerplates universales.
- Añade inicializadores reales upstream para Native App Boilerplate, ps5-homebrew-ui y PS5 Vulkan Template; crea proyectos independientes fuera del canvas C#.
- Añade un listado de proyectos nativos creados, entradas Compilar, logs del proceso upstream y criterio de éxito basado en el código de salida y un artefacto real.
- Añade preparación del stack Vulkan con los scripts upstream de PS5_Vulkan, su SDK compañero y PS5_Mesa, conservando historial Git completo donde se necesitan commits fijados.
- En la revisión del stack Vulkan consultada se detectó que dos helpers referenciados por el build no estaban presentes. Si faltan, el IDE restaura los archivos reales de `blackbearreloaded/ps5-native-app-boilerplate` y registra hashes/procedencia en `.ps5hs-compatibility.json`.
- Identifica como IA declarada únicamente proyectos que documentan el uso explícito de estas herramientas; AGENTS.md/CLAUDE.md no se tratan como prueba de generación de código.
- Conserva el parser PowerShell de arranque y el límite de servicio `127.0.0.1`.

### Validación

`app.js` ha pasado `node --check`. La comprobación estática de PowerShell encontró delimitadores equilibrados y 18 bloques `try` asociados a `catch`/`finally`. En el entorno de preparación no está instalado PowerShell, por lo que no se ejecutó el parser real ni se realizó una compilación de PS5. El paquete usa `runtime/check-syntax.ps1` para hacer la validación sintáctica real en Windows antes de iniciar el servicio.


## 1.0.1 — 16 de octubre de 2026

- Corregida la interpolación PowerShell de `$sourceName:` en `runtime/server.ps1` para evitar que el parser interprete el colon como una referencia cualificada inválida.
- Actualizados los identificadores de versión visibles en la UI.
- Esta corrección no implica que se haya ejecutado el parser oficial en el entorno de preparación ni una build real de SDK/hardware.


## 1.0.2 — 16 de octubre de 2026

- Añadidas rutas de configuración locales para KytyPS5, Python y PS5 UltraPack.
- Añadida la acción «Probar en Kyty» para lanzar un título compilado desde su carpeta.
- Añadido el empaquetado UltraPack a `.ffpfs`, `.ffpfsc` o `.pkg`, con registro y verificación del archivo de salida.
- Añadida guía en `docs/INTEGRACIONES-KYTY-ULTRAPACK.es-ES.md`.
- La integración no distribuye binarios ni garantiza compatibilidad de emulación o soporte de fPKG en Windows.
