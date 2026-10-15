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

## Estado del paquete binario

El ZIP corregido **PS5-Homebrew-Studio-v1.0.1.zip** se entrega como artefacto descargable en la conversación de preparación y su SHA-256 se comprobó localmente. El ZIP todavía no está publicado como archivo binario ni como activo de una GitHub Release en este repositorio. El árbol actual de GitHub contiene la documentación y la nota del hotfix. La guía de publicación explica cómo adjuntar los archivos desde la interfaz web de GitHub.

## Validación

Se ejecutaron comprobaciones de sintaxis de JavaScript y pruebas del generador OpenGL/Vulkan. No se dispone en el entorno de preparación del parser oficial de PowerShell, la toolchain completa de PS5 ni una consola física; por tanto, no se afirma una build final del SDK ni una prueba en hardware.
