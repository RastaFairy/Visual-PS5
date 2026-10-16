# PS5 Homebrew Studio

**Versión 1.1.0 · IDE visual local para Windows.** Diseña interfaces, gestiona proyectos y genera UI C++20 para OpenGL/Vulkan, además de coordinar compilaciones reales mediante toolchains upstream.

## Inicio en Windows

1. Extrae el ZIP en una carpeta con permisos de escritura.
2. Ejecuta start.bat. Se recomienda PowerShell 7; Windows PowerShell 5.1 se admite como alternativa.
3. El lanzador analiza la sintaxis del servidor antes de iniciarlo.
4. El IDE se abre en http://127.0.0.1:47813/. Mantén abierta la ventana del servidor.

El servicio escucha solo en 127.0.0.1. Los proyectos se guardan por defecto en Documentos/PS5HomebrewStudio/Projects.

## Documentación incluida

- Manuales en siete idiomas: archivos MANUAL.es-ES.md y USER-MANUAL.* en docs/.
- [Integración UltraPack](docs/INTEGRACION-ULTRAPACK.es-ES.md)
- [Ecosistema de proyectos upstream](docs/PROJECT_ECOSYSTEM.md)
- [Matriz de SDK](docs/SDK_MATRIX.md)
- [Créditos y atribuciones](docs/CREDITS.md)
- [Registro de cambios](docs/CHANGELOG.md)

## Cambios de 1.1.0

- Se retiró la integración activa con Kyty.
- UltraPack se ejecuta en segundo plano y puede comprobar el contenido respecto al origen mediante --verify.
- Se fuerza UTF-8 para las salidas Python/CLI.
- Se valida Python 3.10+ y se exige eboot.bin más sce_sys/param.json para preparar el empaquetado.
- El generador rechaza flujos con referencias inválidas y no emite stubs vacíos de texturas.
- El mantenedor ha informado de un .ffpfsc probado correctamente en hardware real; esto no implica compatibilidad universal.

La interfaz continúa en español; las traducciones del manual no son una traducción de la UI. Visual-PS5 no es un SDK oficial de Sony ni incluye firmware, claves, juegos o BIOS. Revisa licencias y atribuciones antes de redistribuir.