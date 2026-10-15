# Visual-PS5 — PS5 Homebrew Studio

**Versión 1.0.1 · 16 de octubre de 2026**

Visual-PS5 es un IDE visual local para diseñar interfaces, guardar proyectos, inspeccionar código generado y coordinar compilaciones mediante toolchains comunitarias de PlayStation 5.

## Inicio rápido

1. Clona o descarga este repositorio.
2. El árbol completo del proyecto ya está publicado en `PS5-Homebrew-Studio/`. Si necesitas reconstruir la copia desde el archivo de respaldo, ejecuta `.\scripts\Restore-SourceArchive.ps1` desde la raíz del repositorio. El script decodifica los segmentos, verifica SHA-256 y extrae `PS5-Homebrew-Studio`.
3. Entra en la carpeta extraída y ejecuta `start.bat` en Windows 10/11. Se recomienda PowerShell 7; el lanzador contempla Windows PowerShell 5.1 como alternativa.
4. Abre `http://127.0.0.1:47813/` si el navegador no se abre automáticamente.

En Linux/WSL también está disponible `sh scripts/restore-source-archive.sh`.

## Documentación

- [Manual de uso](docs/MANUAL.es-ES.md)
- [Alcance y limitaciones](docs/ALCANCE-Y-LIMITACIONES.es-ES.md)
- [Arquitectura y toolchains](docs/ARQUITECTURA-Y-TOOLCHAINS.es-ES.md)
- [Licencias y seguridad](docs/LICENCIAS-Y-SEGURIDAD.es-ES.md)
- [Documentación en inglés británico](README.en-GB.md)
- [Manual en inglés](docs/USER-MANUAL.en-GB.md)
- [Matriz de SDKs y repositorios upstream](release/UPSTREAM-SDK-MATRIX.md)
- [Changelog](docs/CHANGELOG.md)
- [Publicar la release en GitHub](docs/PUBLICACION-DE-RELEASE.es-ES.md)
- [Hotfix de PowerShell, línea 627](docs/patches/FIX-POWERSHELL-627.es-ES.md)

## Qué hace

Proporciona lienzo 1920×1080, inspector, jerarquía, pantallas, flujos visuales, gestión de recursos, diagnósticos, exportación y generación de UI C++20 para OpenGL/Vulkan-RADV. Integra plantillas comunitarias y una ruta C# para SharpProspero. La compilación se delega a los scripts upstream reales.

**No es un SDK oficial de Sony**, no contiene archivos propietarios, firmware, claves, juegos ni BIOS. No hace jailbreak, no instala títulos en consola automáticamente y no garantiza compatibilidad con cada firmware.

## Integridad y validación

El código fuente reconstruido debe tener este SHA-256: `f6aa6aae6d5d58a1e5e2e3582d168f0e97f67e1d105938ed6039ba963b329d13`. La reconstrucción desde los veinte segmentos almacenados en GitHub se ha verificado y coincide exactamente con ese hash.

Se ejecutaron pruebas JavaScript y del generador. El entorno de preparación no disponía del parser oficial de PowerShell, todas las toolchains PS5 ni una consola física; no se afirma una compilación final con SDK/hardware.

El archivo ZIP binario aún no está publicado como activo de GitHub Release; la guía enlazada explica cómo adjuntarlo desde GitHub.
