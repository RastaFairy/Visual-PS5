# Visual-PS5 — PS5 Homebrew Studio

**Version 1.0.1 · Hotfix date: 16 October 2026**

A local visual IDE for designing interfaces, saving projects, inspecting generated code and coordinating builds through community PlayStation 5 toolchains.

**Languages / Idiomas**
- [Español (España)](README.es-ES.md)
- [English (United Kingdom)](README.en-GB.md)

## Start here / Para empezar

- [Manual de uso (es-ES)](docs/MANUAL.es-ES.md)
- [User manual (en-GB)](docs/USER-MANUAL.en-GB.md)
- [Alcance y limitaciones](docs/ALCANCE-Y-LIMITACIONES.es-ES.md)
- [Capabilities and limitations](docs/CAPABILITIES-AND-LIMITATIONS.en-GB.md)
- [Arquitectura y toolchains](docs/ARQUITECTURA-Y-TOOLCHAINS.es-ES.md)
- [Architecture and toolchains](docs/ARCHITECTURE-AND-TOOLCHAINS.en-GB.md)
- [Licencias y seguridad](docs/LICENCIAS-Y-SEGURIDAD.es-ES.md)
- [Licensing and security](docs/LICENSING-AND-SECURITY.en-GB.md)
- [Catálogo de SDKs y proyectos upstream](release/UPSTREAM-SDK-MATRIX.md)
- [Changelog](docs/CHANGELOG.md)
- [Publicar la release](docs/PUBLICACION-DE-RELEASE.es-ES.md)
- [Publish a GitHub release](docs/RELEASING.en-GB.md)
- [Hotfix de PowerShell, español](docs/patches/FIX-POWERSHELL-627.es-ES.md)
- [PowerShell hotfix, British English](docs/patches/FIX-POWERSHELL-627.en-GB.md)

## Qué es el proyecto

Visual-PS5 (nombre de aplicación: **PS5 Homebrew Studio**) es una capa de edición y orquestación. Incluye un lienzo virtual 1920×1080, inspector de propiedades, jerarquía, pantallas, flujos visuales, gestión de recursos, diagnósticos y generación de UI C++20 para los backends visuales OpenGL y Vulkan/RADV. También coordina plantillas comunitarias y un flujo C# para SharpProspero.

**No es un SDK oficial de Sony.** No incluye archivos propietarios, firmware, claves, juegos o BIOS de Sony; tampoco desbloquea la consola, elude protecciones ni garantiza compatibilidad con todos los firmwares. La compilación real depende de toolchains y dependencias upstream compatibles.

## Instalación

En Windows 10/11, extrae la distribución en una carpeta con permisos de escritura y ejecuta `start.bat`. Se recomienda PowerShell 7. El servicio local escucha en `http://127.0.0.1:47813/`. Para compilar también necesitas WSL/Linux y las herramientas requeridas por la plantilla elegida.

## Código fuente corregido en este repositorio

El código completo de la versión 1.0.1 está incluido en este repositorio como un archivo TAR comprimido con XZ, codificado en veinte segmentos Base64 en [`release/source-archive/`](release/source-archive/README.md). Tras clonar el repositorio, ejecuta desde su raíz:

```powershell
.\scripts\Restore-SourceArchive.ps1
```

El script reúne los segmentos, comprueba el SHA-256 y extrae el árbol del proyecto. En Linux/WSL puedes usar `sh scripts/restore-source-archive.sh`.

SHA-256 del archivo reconstruido: `f6aa6aae6d5d58a1e5e2e3582d168f0e97f67e1d105938ed6039ba963b329d13`. El contenido remoto de los veinte segmentos se ha descargado y reconstruido durante la verificación; el hash coincide con el del archivo fuente preparado.

El ZIP binario todavía no está adjunto como activo de GitHub Release. Para publicar también el ZIP descargable desde la página Releases, sigue la [guía de publicación](docs/PUBLICACION-DE-RELEASE.es-ES.md).

## Validación

Se ejecutaron comprobaciones de sintaxis de JavaScript y pruebas del generador OpenGL/Vulkan. El entorno de preparación no disponía del parser oficial de PowerShell, de todas las toolchains PS5 ni de una consola física; no se afirma una compilación final con el SDK ni una prueba en hardware.
