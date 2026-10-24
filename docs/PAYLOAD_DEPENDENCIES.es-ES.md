# Dependencias de proyectos payload

Los payloads no comparten necesariamente las mismas bibliotecas ni herramientas. El SDK base de la imagen WSL ofrece herramientas comunes; las dependencias particulares se declaran por proyecto. El IDE busca primero en WSL, en el proyecto y en `toolchains/`. Solo si falta una herramienta o un archivo que el manifiesto permite obtener, intenta usar los repositorios Ubuntu de WSL o una URL HTTPS declarada. Las descargas se comprueban con SHA-256 antes de extraerlas o usarlas. La imagen WSL incluida sigue siendo la ruta offline habitual.

## Manifiesto del proyecto

Añade .ps5hs-payload-dependencies.json a la raíz del proyecto payload. El archivo usa el esquema ps5hs-payload-dependencies, versión 1:

{
  "schema": "ps5hs-payload-dependencies",
  "version": 1,
  "requiredCommands": ["xxd"],
  "toolchain": { "llvmMajor": 18 },
  "hostPackages": [
    { "id": "cmake", "package": "cmake" },
    { "id": "ninja", "package": "ninja-build" }
  ],
  "requiredPaths": [
    { "scope": "project", "path": "vendor/mylib/include/mylib.h" }
  ],
  "packages": [
    {
      "id": "mylib",
      "version": "1.2.0",
      "source": {
        "kind": "directory",
        "scope": "project",
        "path": "vendor/mylib"
      },
      "includeDirs": ["include"],
      "libraryDirs": ["lib"],
      "binDirs": [],
      "executableFiles": [],
      "libraries": ["mylib"],
      "linkFiles": [],
      "requiredFiles": ["include/mylib.h", "lib/libmylib.a"]
    }
  ],
  "compiler": {
    "cFlags": ["-DMYLIB_STATIC"],
    "cxxFlags": [],
    "linkFlags": [],
    "libraries": [],
    "linkFiles": []
  },
  "build": {
    "makefile": "Makefile",
    "target": "payload.elf",
    "artifact": "payload.elf",
    "compiler": "ps5",
    "variables": {}
  }
}

scope puede ser project o ide. Las rutas son relativas a la raíz declarada y no pueden salir de ella. Las dependencias directory pueden estar en vendor/ dentro del proyecto o en una carpeta local de toolchains/.

## Paquetes comprimidos

Para archivos .tar, .tar.gz, .tgz o .zip, usa source.kind archive y declara SHA-256, además de `scope` y `path` locales, una URL HTTPS, o ambos. Una copia local válida siempre tiene prioridad. Si falta, el IDE puede descargar la URL indicada a su caché y verifica el SHA-256 antes de extraerla. El manifiesto sigue fijando versión y hash: para actualizar una dependencia, el desarrollador cambia conscientemente la versión, la URL y el hash. `files` es una lista explícita de rutas o patrones POSIX que se copiarán al caché local. Los enlaces simbólicos, rutas ascendentes, dispositivos y miembros que excedan los límites se rechazan. Si el archivo contiene alias simbólicos a cabeceras, declara las rutas de los archivos reales y añade sus carpetas a includeDirs; así el compilador conserva los nombres de inclusión sin extraer enlaces.

Ejemplo de source:
{
  "kind": "archive",
  "scope": "project",
  "path": "vendor/archives/mylib-1.2.0.tar.gz",
  "url": "https://example.org/releases/mylib-1.2.0.tar.gz",
  "sha256": "64-caracteres-hexadecimales",
  "prefix": "mylib-1.2.0"
}
Ejemplo de files:
["include/**", "lib/**"]

Añade requiredFiles para evitar que un paquete incompleto pase a compilación. Declara en executableFiles las herramientas que deben conservar permiso de ejecución; el IDE aplica ese permiso al extraer ZIP/TAR y lo comprueba antes de compilar. El caché se guarda en .runtime/payload-dependencies y se verifica contra sus hashes e inventario al reutilizarlo. binDirs se añade al PATH del proceso de build; includeDirs, libraryDirs, libraries y linkFiles se convierten en opciones del compilador/linker.

## Makefiles upstream

Para conservar un Makefile upstream, guarda el proyecto como buildMode upstream-makefile en .ps5hs-payload-project.json e incluye el bloque build en el manifiesto. makefile, target y artifact son rutas relativas al proyecto. variables asigna variables de Make a una ruta local (scope/path) o a la raíz de una dependencia (dependency). No se infiere ni se sustituye una receta a partir del nombre del repositorio.

El compilador PS5 se entrega mediante CC y CXX; los directorios de cabeceras y bibliotecas de los paquetes se exponen mediante CPPFLAGS, LDFLAGS y las variables PS5HS_DEP_<ID>_*. Las bibliotecas declaradas se añaden por defecto a LDLIBS; indica build.linkVariable = "LIBS" si el Makefile upstream usa esa variable. El Makefile sigue siendo responsable de enlazar sus bibliotecas de la forma que requiera el proyecto.

## Selección de compilador, enlazador y herramientas host

El PS5 Payload SDK usa LLVM como pareja compatible de compilador y enlazador. Si se declara `toolchain.llvmMajor`, esa versión se conserva exactamente; el IDE puede instalarla desde los repositorios Ubuntu de WSL si falta, pero nunca la sustituye por otra. `build.llvmMajor` sigue aceptado por compatibilidad con perfiles existentes. Si no se declara una versión, el IDE busca la pareja compatible más reciente instalada y ofrecida por los repositorios configurados. Actualiza los índices de apt como máximo una vez al día y puede instalar una versión más reciente. Si no hay Internet, usa la pareja más reciente instalada y lo registra; si no hay ninguna, explica que hace falta instalarla. `LLVM_CONFIG`, Clang y LLD efectivos quedan registrados en el log. El build sigue ejecutándose como el usuario normal de WSL; solo el resolver de paquetes utiliza WSL como `root` para instalar paquetes Ubuntu declarados.

`hostPackages` permite declarar herramientas de Ubuntu necesarias por proyecto. Si no se indica `version`, el IDE conserva la instalada cuando es la más reciente conocida; si apt ofrece una posterior, intenta actualizarla. Si falta el paquete, instala la versión candidata de los repositorios configurados. Si se fija una `version`, debe estar instalada o disponible exactamente en esos repositorios. Sin conexión, las herramientas que ya estén instaladas se conservan; una dependencia ausente detiene el build con el error de apt y conserva el proyecto. No añade PPAs ni repositorios externos.

## Disponibilidad

`requiredCommands` se comprueba dentro de WSL antes de modificar el proyecto. Los paquetes host se pueden declarar en `hostPackages`; el IDE solo intenta instalarlos cuando faltan o cuando el proyecto fija una versión no instalada. Las dependencias de destino PS5 se declaran en `packages`, con archivos locales y/o una URL HTTPS y SHA-256. Si falta una dependencia sin origen remoto fijado, el IDE cancela el build y explica qué debe aportar el desarrollador. No se usa pip ni cargo automáticamente.

El resolver extrae archivos TAR/ZIP seleccionados y verifica cada archivo. Para incluir una herramienta no disponible en Ubuntu, aporta un paquete portable con su ejecutable y bibliotecas de ejecución necesarias, decláralo en binDirs y executableFiles, y añade su nombre a requiredCommands. La comprobación previa confirma que cada comando se puede ejecutar en WSL.

El perfil integrado de ShadowMountPlus conserva PacBrew v0.40.2 y LLVM 18 como elecciones explícitas del perfil. Los proyectos nuevos no heredan esas versiones: declaran las suyas o dejan LLVM sin fijar para que se resuelva la versión compatible más reciente disponible.

El perfil de ShadowMountPlus también fija LLVM 18, comprueba su versión real en WSL, registra las versiones efectivas de Clang/LLD y ejecuta el objetivo `clean` antes del ELF. Para comparar con la release 1.7beta7, aplica su etiqueta y hora de compilación solo cuando el `HEAD` coincide con el commit de referencia y el contenido rastreado es equivalente (ignorando finales de línea). Después calcula el SHA-256 del ELF y lo contrasta con el publicado. Una diferencia restante indica que hay que alinear también los paquetes PacBrew, los stubs del SDK y las demás entradas del build; la receta pública obtiene algunas de esas entradas desde ramas no fijadas.
