Fuentes y toolchains comunitarios de PS5

Esta carpeta contiene los snapshots versionados de las fuentes y toolchains que utiliza PS5 Homebrew Studio. Los paneles SDKs y Proyectos verifican únicamente subcarpetas de este árbol y su manifiesto `.ps5hs-source.json`; no clonan repositorios, recuperan submódulos, descargan ZIP/releases ni prueban mirrors. Si una fuente no está incluida o su manifiesto no coincide, el IDE informa del problema sin obtener archivos externos.

Las plantillas creadas por el IDE se copian a Documentos\PS5HomebrewStudio\Projects y ejecutan inicializadores/generadores upstream. La carpeta original toolchains no se modifica a propósito. No se incluyen firmware, claves, binarios propietarios de Sony, ROMs, BIOS ni recursos de juegos.

Antes de reutilizar/redistribuir, revisa la licencia, THIRD_PARTY_NOTICES, dependencias, requisitos del build y compatibilidad de firmware de la revisión exacta. El editor visual genera código para SharpProspero; las plantillas C++/OpenGL/Vulkan se generan como proyectos independientes y no son transpiladores automáticos del lienzo.

Inventario de procedencia y estado: REPOSITORIOS.es-ES.md.
Las carpetas fuente se guardan como snapshots ordinarios versionados en el repositorio principal; no exigen un .git anidado. El sincronizador registra cada resultado en REPOSITORY-VENDOR-REPORT.json y no sobrescribe carpetas con procedencia no coincidente.

La resolución de fuentes del IDE permanece local-only. Esto no convierte automáticamente en offline todos los builds: herramientas del sistema, paquetes de WSL/Linux, zlib, bibliotecas de host y SDKs precompilados que no estén en `toolchains/` deben aportarse/instalarse por separado. No se descargan automáticamente; si faltan, el build debe detenerse indicando el requisito. Todo `sourceOnly` queda marcado y nunca se presenta como backend compilable.

Los snapshots exactos recuperados de Web Archive se conservan en toolchains/archive/, separados de las entradas actuales del catálogo. Los módulos external/ps5-vulkan de FSR4 y HelixSR se incluyen como archivos normales y sus manifiestos registran el SHA y el SHA del árbol verificado. Esto no incluye DLL propietarias ni sustituye los requisitos genéricos de compilación.


Estado de compilación: `buildableWithoutExternalRepo: true` en un manifiesto solo indica que el Gitlink de código fuente correspondiente está materializado como archivos locales y que no hace falta recuperar esa carpeta desde el upstream desaparecido. **No significa que se haya demostrado una compilación correcta.** Los manifiestos de FSR4 y HelixSR registran `buildVerified: false` mientras no se hayan ejecutado builds reales en el entorno de destino. Las dependencias genéricas, SDKs precompilados y la DLL legítima aportada por el usuario que HelixSR necesita siguen siendo requisitos separados.
