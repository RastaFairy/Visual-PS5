# Changelog / Registro de cambios

## 1.1.1 — 16 de octubre de 2026

- Detección y clasificación del workspace: distingue títulos compilables, plantillas, SDKs/drivers y proyectos de referencia; muestra dependencias pendientes.
- Reconocimiento seguro de clones Git existentes y soporte de inicialización mediante `tools/init-project.sh` o `make init`.
- Preparación explícita de dependencias y SDK para el backend OpenGL UI.
- Limpieza previa con `make clean` solo cuando se detecta un target declarado.
- Cierre del modelo visual sin borrar proyectos nativos ni artefactos.
- UltraPack conserva la invocación CLI probada, sin forzar `--verify`.

## 1.1.0 — 16 de octubre de 2026

- Eliminada la integración activa de lanzamiento mediante Kyty.
- Corregido el flujo de empaquetado UltraPack: trabajo en segundo plano, logs consultables y verificación opcional del contenido mediante `--verify` (activada de forma predeterminada).
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