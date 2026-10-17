# Changelog / Registro de cambios

## 1.1.7 — 17 de octubre de 2026

- Añade fuentes TrueType seleccionables por proyecto y horneado de atlas Unicode con codepoints extraídos del contenido visual.
- Genera los atlas para OpenGL y Vulkan; valida cobertura de glifos y falla con un diagnóstico explícito si la fuente seleccionada no contiene un carácter requerido.
- Amplía las pruebas de generación de C++20 a español, francés, alemán, ruso, griego, japonés, chino simplificado/tradicional y coreano.
- La vista previa del IDE usa el fallback tipográfico del navegador. La localización de la interfaz, los IME de CJK y el shaping RTL son funciones distintas y no se declaran resueltos.

## 1.1.6 — 17 de octubre de 2026

- Añade la vista **Estructura**: explora en paralelo las pantallas editables del modelo visual y los estados de interfaz encontrados en código C++ nativo.
- Incluye árbol con búsqueda, mapa de transiciones, etiquetas de menú y enlaces directos a las líneas del renderizador y de declaración.
- Señala que las transiciones del C++ proceden de análisis estático; no presenta los estados dibujados a mano como componentes visuales editables ni garantiza que todas las rutas dinámicas se detecten.
- Añade pruebas de regresión para detección de estados, renderizadores, textos y transiciones.

## 1.1.5 — 17 de octubre de 2026

- Corrige los selectores de botones de UltraPack y Presentación, que lanzaban un error antes de iniciar la acción.
- La compilación OpenGL de proyectos visuales generados por el IDE usa el `build.ps1` del proyecto y su SDK local, evitando la preparación redundante del SDK compartido en rutas WSL/DrvFS sin `metadata`.
- Añade selección previa al build de icono, fondos de selección/lanzamiento y audio; administración de pantallas y capas independientes por pantalla.
- Actualiza los README de portada, los manuales y la documentación de validación.
- Confirmación manual del usuario: compilación OpenGL y empaquetado UltraPack correctos. Vulkan completo, conversión ATRAC9 y ejecución en PS5 física siguen sin verificar; véase `PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md`.

## 1.1.4 — 17 de octubre de 2026

- Añade gestión de pantallas y reordenación de capas, con comprobación de orden de dibujo del generador nativo.
- Permite seleccionar recursos de presentación en el diálogo de compilación de una pantalla nativa.
- Para proyectos OpenGL generados por el IDE, reutiliza el script de build y las dependencias locales del proyecto.

## 1.1.3 — 16 de octubre de 2026

- Añade detección preventiva del problema de permisos Git/DrvFS cuando una unidad WSL carece de `metadata`.
- Incorpora el script de reparación de permisos y documentación de diagnóstico; esto no soluciona automáticamente todos los checkouts del SDK compartido.

## 1.1.1 — 16 de octubre de 2026

- Detección y clasificación del workspace: distingue títulos compilables, plantillas, SDKs/drivers y proyectos de referencia; muestra dependencias pendientes.
- Reconocimiento seguro de clones Git existentes y soporte de inicialización mediante `tools/init-project.sh` o `make init`.
- Preparación explícita de dependencias y SDK para el backend OpenGL UI.
- Limpieza previa con `make clean` solo cuando se detecta un target declarado.
- Cierre del modelo visual sin borrar proyectos nativos ni artefactos.
- UltraPack conserva la invocación CLI probada, sin forzar `--verify`.

## 1.1.0 — 16 de octubre de 2026

- Eliminada la integración activa de lanzamiento mediante Kyty.
- Corregido el flujo de empaquetado UltraPack: trabajo en segundo plano, logs consultables y verificación del contenido mediante `--verify` solo cuando se solicita explícitamente; la interfaz no añade ese argumento de forma implícita.
- Forzada la codificación UTF-8 en la salida Python/CLI y mantenida la compatibilidad con Windows PowerShell 5.1.
- Exigidos `eboot.bin` y `sce_sys/param.json` para habilitar el empaquetado de títulos nativos.
- Retirados stubs vacíos del generador Vulkan y rechazadas referencias de flujo no válidas.
- Actualizados los manuales a 1.1.0 y añadidos documentos en español, inglés, francés, alemán, chino simplificado, japonés y ruso.
- Añadida atribución enlazada a proyectos y cuentas GitHub upstream.

El mantenedor informa de que una imagen `.ffpfsc` generada se probó correctamente en hardware real. Es una prueba concreta, no una garantía de compatibilidad universal.

## Historial anterior

## 1.0.1 — 16 October 2026

- Fixed PowerShell parsing in SaveProject by delimiting the sourceName variable as \${sourceName} before a colon.
- Updated visible application version strings.
- Re-ran JavaScript syntax checks and native-generator tests.
- Archive integrity was checked with unzip; this is not a substitute for the official PowerShell parser, the full PS5 SDK build or a physical-console test.

## 1.0.0 — initial release

- Visual editor, project model, save/open/export, diagnostics and a catalogue of community repositories.
- C++20 UI generation for the native OpenGL and Vulkan/RADV backends.
- Image resource handling, visual flows and build orchestration delegated to upstream toolchains.

## Validation policy

Never describe static generator tests as a successful target build. Record the operating system, PowerShell version, backend, upstream commit IDs, full logs and target firmware when reproducing a build issue.