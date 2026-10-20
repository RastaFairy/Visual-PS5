Fuentes y toolchains comunitarios de PS5

Esta carpeta se rellena desde los paneles SDKs y Proyectos. El panel Proyectos clona los repositorios originales de GitHub con Git, historial shallow y submódulos recursivos cuando los hay; se guarda un manifiesto local de repositorio/commit. El panel SDKs mantiene el flujo específico de cada backend, incluidos ZIP de fuentes cuando es apropiado y dependencias separadas cuando el ZIP upstream no contiene submódulos.

Las plantillas creadas por el IDE se copian a Documentos\PS5HomebrewStudio\Projects y ejecutan inicializadores/generadores upstream. La carpeta original toolchains no se modifica a propósito. No se incluyen firmware, claves, binarios propietarios de Sony, ROMs, BIOS ni recursos de juegos.

Antes de reutilizar/redistribuir, revisa la licencia, THIRD_PARTY_NOTICES, dependencias, requisitos del build y compatibilidad de firmware de la revisión exacta. El editor visual genera código para SharpProspero; las plantillas C++/OpenGL/Vulkan se generan como proyectos independientes y no son transpiladores automáticos del lienzo.

Inventario de procedencia y estado: REPOSITORIOS.es-ES.md.
Cada carpeta incluida en el árbol principal se trata como snapshot vendorizado; no exige un .git anidado ni se clona su upstream si existe un manifiesto .ps5hs-source.json coincidente. El resultado de la sincronización se registra en REPOSITORY-VENDOR-REPORT.json.

Los repositorios de referencia que no forman parte del backend principal se mantienen separados para no mezclar forks de OpenGL/Vulkan. Se conservan licencias, notices y metadatos de origen. No se deben incorporar firmware, claves, ROMs, BIOS ni recursos de juegos.

Esta copia local elimina la dependencia de que la cuenta upstream siga disponible para las fuentes que se hayan versionado. Las descargas de dependencias de compilación genéricas siguen siendo independientes y deben verificarse mediante versión y hash.
