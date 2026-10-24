Fuentes y toolchains comunitarios de PS5

Esta carpeta contiene los snapshots versionados de las fuentes y toolchains que utiliza PS5 Homebrew Studio. Los paneles SDKs y Proyectos verifican únicamente subcarpetas de este árbol y su manifiesto `.ps5hs-source.json`; no clonan repositorios, recuperan submódulos, descargan ZIP/releases ni prueban mirrors. Si una fuente no está incluida o su manifiesto no coincide, el IDE informa del problema sin obtener archivos externos.

Las plantillas creadas por el IDE se copian a Documentos\PS5HomebrewStudio\Projects y ejecutan inicializadores/generadores upstream. La carpeta original toolchains no se modifica a propósito. No se incluyen firmware, claves, binarios propietarios de Sony, ROMs, BIOS ni recursos de juegos.

Antes de reutilizar/redistribuir, revisa la licencia, THIRD_PARTY_NOTICES, dependencias, requisitos del build y compatibilidad de firmware de la revisión exacta. El editor visual genera código para SharpProspero; las plantillas C++/OpenGL/Vulkan se generan como proyectos independientes y no son transpiladores automáticos del lienzo.

Inventario de procedencia y estado: REPOSITORIOS.es-ES.md.
Las carpetas fuente se guardan como snapshots ordinarios versionados en el repositorio principal; no exigen un .git anidado. El sincronizador registra cada resultado en REPOSITORY-VENDOR-REPORT.json y no sobrescribe carpetas con procedencia no coincidente.

En modo local-only, los bootstrapers aceptan cachés existentes verificadas; si falta un artefacto, solo buscan el archivo fijado en toolchains/artifacts/ (SDK de PS5 ps5-payload-sdk.zip, zlib zlib-1.3.2.tar.gz, PacBrew ps5-payload-dev-v0.40.2.tar.gz, GoogleTest googletest-1.17.0.tar.gz) o el SDK OpenGL en toolchains/ps5-opengl-sdk/ps5-opengl-sdk-1.0.2.tar.gz. No los descargan. La imagen WSL offline instala las bibliotecas y cabeceras PacBrew fijadas dentro del SDK PS5. Para una distro WSL ya existente, la compilación de ShadowMountPlus extrae solo esos archivos a una caché local de .runtime/; no instala paquetes ni modifica la distro. Si el artefacto local no existe o su hash no coincide, el log identifica el fallo antes de modificar el proyecto. La resolución de fuentes del IDE permanece local-only. Las herramientas del sistema, bibliotecas de host y otros SDKs precompilados siguen siendo requisitos separados cuando una plantilla los necesite. Todo sourceOnly queda marcado y nunca se presenta como backend compilable.

Los snapshots exactos recuperados de Web Archive se conservan en toolchains/archive/, separados de las entradas actuales del catálogo. Los módulos external/ps5-vulkan de FSR4 y HelixSR se incluyen como archivos normales y sus manifiestos registran el SHA y el SHA del árbol verificado. Esto no incluye DLL propietarias ni sustituye los requisitos genéricos de compilación.


Estado de compilación: `buildableWithoutExternalRepo: true` en un manifiesto solo indica que el Gitlink de código fuente correspondiente está materializado como archivos locales y que no hace falta recuperar esa carpeta desde el upstream desaparecido. **No significa que se haya demostrado una compilación correcta.** Los manifiestos de FSR4 y HelixSR registran `buildVerified: false` mientras no se hayan ejecutado builds reales en el entorno de destino. Las dependencias genéricas, SDKs precompilados y la DLL legítima aportada por el usuario que HelixSR necesita siguen siendo requisitos separados.


Empaquetado de artefactos fijados y CI

Los SHA-256 definidos en `runtime/toolchain-pins.json` se verifican durante el empaquetado. La CI puede acceder a las URL de origen al preparar paquetes; las instalaciones del IDE deben resolver estas dependencias desde los archivos locales de `toolchains/`. Los requisitos del compilador WSL/Linux y los paquetes de sistema siguen instalándose en el host.
