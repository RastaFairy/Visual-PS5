Fuentes y toolchains comunitarios de PS5

Las carpetas versionadas bajo toolchains/ son la única fuente de código que usa el IDE en tiempo de ejecución. El panel SDKs/Proyectos comprueba esas copias locales y no clona upstreams, no descarga ZIP y no intenta mirrors. Si falta una carpeta o una dependencia, el IDE informa de la ruta local que falta y conserva los archivos existentes.

Los repositorios y snapshots se versionan como archivos ordinarios; no exigen un .git anidado. Los archivos .ps5hs-source.json registran procedencia y revisión. La sincronización mediante GitHub Actions es una tarea de mantenimiento separada y no la invoca el IDE durante su uso normal.

El SDK OpenGL precompilado debe existir localmente bajo toolchains/toolchain-pack/ps5-opengl-sdk/ y verificarse por SHA-256. El script de build no lo descargará. Si falta, el build se detiene con un diagnóstico explícito. UltraPack solo puede resolver módulos Python desde wheels locales bajo toolchains/ps5-ultrapack/wheels, con pip --no-index.

El modo local-only para fuentes y artefactos de toolchains no instala requisitos del sistema. WSL, compiladores, .NET y paquetes de Linux siguen siendo requisitos del entorno que deben instalarse por separado. La acción explícita de configuración del sistema es independiente del gestor de fuentes locales.

No se incluyen firmware, claves, binarios propietarios de Sony, ROMs, BIOS ni recursos de juegos. Revisa licencias, THIRD_PARTY_NOTICES, requisitos del build y compatibilidad de firmware antes de reutilizar fuentes.

Inventario de procedencia y estado: REPOSITORIOS.es-ES.md.
Las dependencias genéricas indicadas por los Makefile/scripts pueden requerir herramientas del entorno que no son código fuente del IDE. La detección local no debe presentar una fuente source-only ni una carpeta ausente como compilable.

Estado de compilación: buildVerified: false significa que no consta una compilación verificada en el entorno de destino. Materializar un submódulo como archivos locales elimina la necesidad de recuperar esa carpeta desde upstream, pero no demuestra que el backend compile o funcione en hardware.
