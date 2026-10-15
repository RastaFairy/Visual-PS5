Fuentes y toolchains comunitarios de PS5

Esta carpeta se rellena desde los paneles SDKs y Proyectos. El panel Proyectos clona los repositorios originales de GitHub con Git, historial shallow y submódulos recursivos cuando los hay; se guarda un manifiesto local de repositorio/commit. El panel SDKs mantiene el flujo específico de cada backend, incluidos ZIP de fuentes cuando es apropiado y dependencias separadas cuando el ZIP upstream no contiene submódulos.

Las plantillas creadas por el IDE se copian a Documentos\PS5HomebrewStudio\Projects y ejecutan inicializadores/generadores upstream. La carpeta original toolchains no se modifica a propósito. No se incluyen firmware, claves, binarios propietarios de Sony, ROMs, BIOS ni recursos de juegos.

Antes de reutilizar/redistribuir, revisa la licencia, THIRD_PARTY_NOTICES, dependencias, requisitos del build y compatibilidad de firmware de la revisión exacta. El editor visual genera código para SharpProspero; las plantillas C++/OpenGL/Vulkan se generan como proyectos independientes y no son transpiladores automáticos del lienzo.
