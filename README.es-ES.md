# Visual-PS5 — PS5 Homebrew Studio

**Versión 1.0.0 · 15 de octubre de 2026**

Visual-PS5 es un IDE visual local para diseñar interfaces, guardar modelos, inspeccionar código generado y coordinar compilaciones mediante toolchains comunitarias de PlayStation 5.

## Para empezar
1. Descarga o reconstruye el ZIP de la distribución y verifica su SHA-256.
2. Extrae el directorio `PS5-Homebrew-Studio` en una ubicación con permisos de escritura.
3. Ejecuta `start.bat` en Windows. Se recomienda PowerShell 7; el lanzador también contempla Windows PowerShell 5.1.
4. Abre `http://127.0.0.1:47813/` si el navegador no se abre automáticamente.
5. Mantén abierta la ventana del servidor mientras utilices el editor.

## Documentación
- [Manual de uso](docs/MANUAL.es-ES.md)
- [Alcance y limitaciones](docs/ALCANCE-Y-LIMITACIONES.es-ES.md)
- [Arquitectura y toolchains](docs/ARQUITECTURA-Y-TOOLCHAINS.es-ES.md)
- [Licencias y seguridad](docs/LICENCIAS-Y-SEGURIDAD.es-ES.md)
- [Manual en inglés británico](docs/USER-MANUAL.en-GB.md)
- [Capacidades y límites (en-GB)](docs/CAPABILITIES-AND-LIMITATIONS.en-GB.md)
- [Arquitectura (en-GB)](docs/ARCHITECTURE-AND-TOOLCHAINS.en-GB.md)
- [Licencias y seguridad (en-GB)](docs/LICENSING-AND-SECURITY.en-GB.md)
- [Catálogo y matriz de SDKs](release/UPSTREAM-SDK-MATRIX.md)
- [Corrección de PowerShell línea 627](docs/patches/FIX-POWERSHELL-627.es-ES.md)

## Alcance
El programa mantiene una interfaz web local, modelo visual, jerarquía, pantallas, flujos, recursos, exportación, diagnóstico y generación de UI C++20 para los backends visuales OpenGL y Vulkan/RADV. También integra flujos de plantillas comunitarias, incluido un flujo C# basado en SharpProspero.

**No es un SDK oficial de Sony.** No incluye archivos propietarios, firmware, claves, juegos, BIOS ni herramientas de Sony. No desbloquea la consola, no elude protecciones, no instala automáticamente títulos en una PS5 y no garantiza compatibilidad con todos los firmwares. Los builds dependen de toolchains upstream compatibles.

## Idiomas
La documentación se mantiene en español de España (`es-ES`) e inglés británico (`en-GB`). Los identificadores de APIs y parte del código generado conservan los nombres originales de los proyectos upstream.

## Estado de validación
Se ejecutaron las comprobaciones de sintaxis de JavaScript y las pruebas del generador. El entorno de preparación no tenía el parser oficial de PowerShell, la toolchain completa de PS5 ni una consola física; por tanto, no se afirma una compilación final de SDK ni una prueba en hardware.
