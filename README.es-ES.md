# Visual-PS5 — PS5 Homebrew Studio 1.1.0

IDE visual local para Windows que permite diseñar interfaces, administrar proyectos, inspeccionar código, generar UI C++20 y coordinar compilaciones mediante toolchains comunitarias de PS5.

## Idiomas y documentación

- [Manual de usuario — español](docs/MANUAL.es-ES.md)
- [User manual — English (UK)](docs/USER-MANUAL.en-GB.md)
- [Manuel utilisateur — français](docs/USER-MANUAL.fr-FR.md)
- [Benutzerhandbuch — Deutsch](docs/USER-MANUAL.de-DE.md)
- [用户手册 — 简体中文](docs/USER-MANUAL.zh-CN.md)
- [ユーザーマニュアル — 日本語](docs/USER-MANUAL.ja-JP.md)
- [Руководство пользователя — русский](docs/USER-MANUAL.ru-RU.md)
- [Créditos y atribuciones upstream](docs/CREDITS.md)
- [Arquitectura y toolchains](docs/ARQUITECTURA-Y-TOOLCHAINS.es-ES.md)
- [Licencias y seguridad](docs/LICENCIAS-Y-SEGURIDAD.es-ES.md)
- [Matriz de SDKs y repositorios upstream](release/UPSTREAM-SDK-MATRIX.md)
- [Registro de cambios](docs/CHANGELOG.md)

## Inicio rápido

1. Descarga o compila el paquete de la rama deseada.
2. Extrae el contenido en una carpeta con permisos de escritura en Windows 10/11.
3. Ejecuta start.bat y abre http://127.0.0.1:47813/ si el navegador no se inicia automáticamente.

Se recomienda PowerShell 7; también se admite Windows PowerShell 5.1. La compilación nativa requiere Git, WSL/Linux y las dependencias de la plantilla seleccionada. El servidor escucha solo en 127.0.0.1.

La interfaz continúa en español mientras se prepara la localización de la UI. El mantenedor ha comunicado que una imagen .ffpfsc se generó y probó con éxito en hardware real; esto no implica compatibilidad universal con todos los títulos o firmwares.

Visual-PS5 no es un SDK oficial de Sony ni incluye archivos propietarios, firmware, claves, juegos o BIOS. Cada proyecto upstream conserva sus licencias y avisos; consulta [Créditos](docs/CREDITS.md) antes de redistribuir.