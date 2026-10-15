# Visual-PS5 — PS5 Homebrew Studio

**Versión 1.0.1 · 16 de octubre de 2026**

Visual-PS5 es un IDE visual local para diseñar interfaces, guardar proyectos, inspeccionar código generado y coordinar compilaciones mediante toolchains comunitarias de PlayStation 5.

## Inicio rápido

1. Descarga el ZIP corregido adjunto a la entrega de esta conversación y verifica su SHA-256.
2. Extrae `PS5-Homebrew-Studio` en una ubicación con permisos de escritura.
3. Ejecuta `start.bat` en Windows 10/11. Se recomienda PowerShell 7; el lanzador contempla Windows PowerShell 5.1 como alternativa.
4. Abre `http://127.0.0.1:47813/` si no se abre el navegador automáticamente.

## Documentación

- [Manual de uso](docs/MANUAL.es-ES.md)
- [Alcance y limitaciones](docs/ALCANCE-Y-LIMITACIONES.es-ES.md)
- [Arquitectura y toolchains](docs/ARQUITECTURA-Y-TOOLCHAINS.es-ES.md)
- [Licencias y seguridad](docs/LICENCIAS-Y-SEGURIDAD.es-ES.md)
- [Documentación en inglés británico](README.en-GB.md)
- [Manual en inglés](docs/USER-MANUAL.en-GB.md)
- [Matriz de SDKs y repositorios upstream](release/UPSTREAM-SDK-MATRIX.md)
- [Changelog](docs/CHANGELOG.md)
- [Hotfix de PowerShell, línea 627](docs/patches/FIX-POWERSHELL-627.es-ES.md)

## Qué hace

Proporciona lienzo 1920×1080, inspector, jerarquía, pantallas, flujos visuales, gestión de recursos, diagnósticos, exportación y generación de UI C++20 para OpenGL/Vulkan-RADV. Integra plantillas comunitarias y una ruta C# para SharpProspero. La compilación se delega a los scripts upstream reales.

**No es un SDK oficial de Sony**, no contiene archivos propietarios, firmware, claves, juegos ni BIOS. No hace jailbreak, no instala títulos en consola automáticamente y no garantiza compatibilidad con cada firmware.

## Limitaciones y validación

El editor puede modificar el modelo sin SDK descargado. La compilación necesita WSL/Linux y las dependencias concretas del backend. El éxito del proceso upstream y la presencia de un artefacto no demuestran ejecución correcta en consola.

Se ejecutaron pruebas JavaScript y del generador. En el entorno de preparación no había parser oficial de PowerShell, toolchains completas de PS5 ni consola física, así que no se afirma una validación final con SDK/hardware.

El ZIP v1.0.1 corregido se adjunta como artefacto separado; no está almacenado todavía como activo de GitHub Release.
