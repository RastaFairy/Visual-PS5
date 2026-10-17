# Registro de cambios

## 1.1.9 — 2026-10-17

- Unifica las mejoras del modelo de capas de 1.1.8 con la selección opcional de fuente TTF para títulos nativos.
- Conecta la fuente seleccionada con la tarea real de compilación: valida la TTF, recopila los codepoints usados, hornea seis atlas SDF y detiene el proceso si falta un glifo obligatorio.
- Protege los atlas generados frente a una segunda ejecución del script upstream de fuentes, que antes podía sobrescribirlos con la fuente predeterminada.
- Añade `runtime/test-unicode-fonts.js` y `runtime/test-unicode-integration.js` como pruebas de regresión de Unicode y de las conexiones entre interfaz, petición API y backend.
- Validación local: pruebas JavaScript y análisis estático del flujo de integración. Esta versión no se presenta como compilada con PowerShell/WSL ni probada en hardware PS5 desde este entorno.


## 1.1.8 — 2026-10-17

- Migra los `zIndex` sintéticos creados por versiones antiguas (orden secuencial del JSON) a un orden semántico de capas; conserva los órdenes manuales no coincidentes con ese patrón.
- Evita que los títulos de una sola línea se partan y queden cortados cuando el texto es más ancho que su caja: ajusta el tamaño visual al ancho disponible.
- Repara el proyecto de demostración Taller de Colada con el equipo fuera de los paneles, una lista de misiones visible y la descripción de la misión separada del encabezado.
- Añade una prueba de regresión para proyectos guardados con índices de capa automáticos antiguos.

## 1.1.7 — 2026-10-17

- Corrige el orden inicial de capas de modelos antiguos sin `zIndex`: fondos y paneles quedan detrás de tarjetas, imágenes, controles y textos.
- Añade aislamiento temporal de una capa desde la jerarquía o la barra del lienzo, con acción para volver a mostrar todas las capas.
- Ajusta el lienzo 16:9 al espacio disponible cuando cambia el tamaño del panel para evitar recortes del encabezado y del pie.
- Las imágenes importadas usan la transparencia real del recurso en vez del fondo de marcador de posición.
- Aclara el estado inicial de UltraPack y registra el inicio del trabajo en el registro visible.
- Añade pruebas automatizadas para la normalización del orden de capas.

## 1.1.5 — 2026-10-17

- Corrige el botón «Empaquetar» de PS5 UltraPack: el código intentaba iterar el resultado de un selector de elemento único, lanzaba un error antes de iniciar la tarea y dejaba el mensaje «Listo para ejecutar PS5 UltraPack».
- Corrige el mismo patrón en el botón «Aplicar cambios» de Presentación.
- Añade versionado a las URL de los scripts para evitar reutilizar una copia en caché de `app.js` o del generador tras actualizar.
- Validación manual del usuario en Windows/WSL: la compilación nativa vuelve a completarse correctamente y el empaquetado PS5 UltraPack funciona. Las rutas aún no validadas se registran en [Problemas conocidos](KNOWN-ISSUES.es-ES.md).

## 1.1.4 — 2026-10-17

- Corrige la compilación de proyectos UI OpenGL generados por el IDE: ejecuta el `build.ps1` del propio proyecto y reutiliza sus dependencias/SDK locales en vez de bloquearse preparando otra copia compartida del SDK en `toolchains/`.
- Añade a la generación de títulos visuales los campos opcionales para icono, fondo de selección, fondo de lanzamiento y música antes de compilar; usa el preparador de recursos upstream y valida cada archivo.
- Añade selector y gestor de pantallas, con creación, cambio, renombrado y eliminación protegida de pantallas.
- La jerarquía pasa a mostrar las capas por delante/detrás, permite reordenarlas con botones o arrastrando y mantiene el aislamiento por pantalla.

## 1.1.3 — 2026-10-16

- Detecta de forma preventiva unidades WSL/DrvFS sin `metadata` antes del `make source-fetch` de PS5 OpenGL.
- Si el error de permisos de Git persiste, muestra el procedimiento de reparación en el mensaje y el log de compilación.
- Añade `runtime/fix-wsl-permissions.sh`, con backup de `/etc/wsl.conf` y edición preservando las demás opciones.
- El IDE ya no oculta la excepción final de la compilación detrás del registro de dependencias.


## 1.1.2 — 2026-10-16

- Añade la acción «Presentación» a los proyectos nativos inicializados con `sce_sys/param.json`.
- Permite sustituir el icono `icon0.png`, los fondos independientes de selección/lanzamiento `pic0.dds` y `pic1.dds`, y la música `snd0.at9`.
- Utiliza `tools/prepare-assets.ps1` de Native App Boilerplate para convertir y validar formatos en staging temporal antes de aplicar los archivos.
- Añade límites de tamaño y restringe las escrituras al workspace; restaura los archivos si falla la aplicación de recursos.
- Distingue los recursos de una app de los temas globales de ShellUI.

## 1.1.1 — 2026-10-16

- Detecta proyectos nativos y repositorios upstream en el workspace, distingue títulos, plantillas, SDKs, drivers y referencias y muestra las dependencias pendientes.
- Reconoce checkouts Git válidos que no tienen manifiesto de procedencia del IDE y los registra sin sobrescribir archivos.
- Permite inicializar plantillas compatibles mediante `tools/init-project.sh` o `make init`.
- Prepara las dependencias Native App Boilerplate / PS5 OpenGL y compila el SDK OpenGL antes de construir UI cuando falta.
- Añade `make clean` opcional y protegido: solo se ejecuta cuando el Makefile declara el target.
- Añade «Cerrar proyecto» para descargar el modelo visual sin borrar fuentes, compilaciones ni paquetes nativos.
- Conserva la invocación CLI de UltraPack validada por el usuario, sin añadir `--verify` desde la interfaz.

## 1.1.0 — 2026-10-16

- Se retiró Kyty de las acciones, la configuración y las rutas activas del IDE.
- El empaquetado UltraPack se ejecuta como tarea independiente y muestra su salida, código de salida y artefacto.
- Se corrigió el uso de colecciones de botones en el frontend y la compatibilidad de ProcessStartInfo con Windows PowerShell 5.1.
- La compilación nativa ya no considera un ZIP/PKG residual como prueba de título; se exige `eboot.bin` y `sce_sys/param.json`.
- El generador Vulkan ya no emite un cargador de texturas vacío y rechaza flujos con destinos o pantallas inexistentes.
- La reparación de la instalación de UltraPack conserva el checkout y los helpers locales.

## 1.0.9 — 2026-10-16

- Kyty recibe la ruta completa de `eboot.bin` mediante `--game`, con resolución 1920×1080 y registro del comando utilizado.
- La instalación de UltraPack crea un entorno Python aislado en `toolchains/ps5-ultrapack/.venv` e instala dependencias CLI; Herramientas guarda las rutas exactas de `backend/cli.py` y de ese Python.
- La ejecución de empaquetado valida la ruta configurada y registra CLI, Python, origen y destino. Si falta el helper nativo de Windows para `.pkg`, devuelve un error explícito antes de ejecutar.
- Se aclara que los imports sin resolver y los guest faults son fallos de compatibilidad de Kyty, no errores que el IDE pueda solucionar únicamente cambiando argumentos.

## 1.0.8 — 2026-10-16

- La llamada a PS5 UltraPack usa argumentos estructurados de proceso, el directorio de trabajo del CLI y un directorio temporal explícito; registra el comando real y separa STDOUT/STDERR para diagnosticar fallos en Windows.

## 1.0.7 — 2026-10-16

- Las acciones «Probar en Kyty» y «Empaquetar» permanecen en la barra común del IDE y recuerdan la última compilación nativa correcta.
- La consulta de `build.log` usa lectura compartida con reintentos para evitar que una escritura concurrente interrumpa el seguimiento de una compilación.
- La compilación visual permite cambiar el nombre/destino y sobrescribir explícitamente solo carpetas con manifiesto de Homebrew Studio y plantilla coincidente.
- Los fallos de UltraPack muestran diagnóstico, salida del proceso, código de salida y si se verificó un artefacto.

## 1.0.6 — 2026-10-16

- Las compilaciones visuales y los proyectos nativos C++ se ejecutan en un trabajador de fondo y el IDE consulta su estado sin bloquear el servicio local.
- El registro muestra la salida real de WSL/Make/CMake/Ninja conforme se produce; se elimina el contador ficticio de progreso.
- El botón termina en un estado explícito: «Completado» o «Error · Reintentar».
- Tras una compilación visual correcta, se ofrecen acciones directas para probar el título en KytyPS5 o empaquetarlo con UltraPack, con selector `.ffpfs`, `.ffpfsc` y `.pkg`.
- OpenGL regenera el atlas tipográfico europeo (2048 px) antes de compilar para conservar los acentos españoles.
- Las pruebas del generador C++ verifican que las cadenas UTF-8 con vocales acentuadas, ñ, ü, signos españoles y euro sobreviven en los backends OpenGL y Vulkan.
- Se conserva el mensaje de resultado, los diagnósticos, la ruta del proyecto y el artefacto verificable.

# Registro de cambios

## 1.0.4 — 16 de octubre de 2026

- Corrige el punto de entrada Windows para proyectos C++ nativos generados: `build.ps1` llama al destino `app` del Makefile dentro de WSL en vez de ejecutar `tools/build.sh` directamente.
- El Makefile vuelve a definir los includes obligatorios `src/` y OpenGL, los archivos estáticos y los import stubs que faltaban en el registro de compilación mostrado por el wrapper.
- El generador parchea la plantilla al copiarla, para que los proyectos nuevos reciban la corrección incluso si el upstream todavía conserva el wrapper antiguo.


## 1.0.3 — 16 de octubre de 2026

- Corrige el empaquetado de imágenes del generador visual: los IDs se gestionan coherentemente como `Map`, sin llamar a `.add()`.
- Normaliza los finales de línea de archivos de texto críticos para el build nativo al crear el proyecto y justo antes de compilar en WSL; cubre scripts `.sh`, Makefiles, fuentes C/C++, `CMakeLists.txt` y manifiestos `.sha256`.
- Declara `*.sha256 text eol=lf` en `.gitattributes` del proyecto generado y fija `core.autocrlf=false` para nuevos clones.
- Mantiene intacta la comprobación SHA-256 del runtime; corrige el formato del manifiesto en vez de desactivar la protección.


## 1.0.0 — Generación visual nativa C++20

- Convierte el lienzo y los flujos visuales en pantallas C++20 compatibles con el contrato `hui::app::Concept` del kit `ps5-homebrew-ui` y su fork Vulkan.
- Añade un flujo de interfaz para generar y compilar diseños nativos: selección de nombre/TITLE_ID, creación en un directorio separado, log en vivo y validación del artefacto real de salida.
- Backend OpenGL: carga RGBA8 desde `assets/ps5hs`, después de decodificar las imágenes en el navegador y reducirlas a un máximo de 512×512. Limita a 16 recursos únicos y registra hash/procedencia de los ficheros en el manifiesto.
- Backend Vulkan: inyecta la pantalla generada en el título creado por `PS5_VulkanTemplate` y usa CMake/Ninja/RADV. Las imágenes RGBA8 se registran en `ps5/assets.json`, se empaquetan en `/app0/assets/ps5hs/` y se suben con `VkRenderer::create_texture`; añade además un aviso de licencia para recursos aportados por el usuario.
- Expone `visualBackend` y `generatedFromStudio` en el registro de proyectos nativos, incluye tests Node.js de los generadores y actualiza avisos de uso/licencias.
- Añade teclado nativo en pantalla para `input` en ambos generadores C++: navegación con cruceta, letras ASCII, dígitos, puntuación básica, espacio, borrar, limpiar, aceptar/cancelar y disparo del evento `change`. No se presenta como IME multilingüe del sistema.

- Se añade verificación del contenido de UltraPack contra el origen mediante `--verify`, activada por defecto en la interfaz.
- Se fijan las salidas Python/CLI en UTF-8 para preservar caracteres no ASCII.
- Se publican manuales actualizados en siete idiomas y créditos con enlaces a los repositorios y cuentas upstream. La UI permanece en español hasta una fase de localización independiente.

### Validación

`node --check app.js`, `node --check runtime/native-generator.js` y `node runtime/test-native-generator.js` pasan. Clang también ha comprobado el código C++ generado para ambas rutas contra interfaces de prueba locales; esto no sustituye la compilación con los headers/SDK completos ni una prueba en PS5. El entorno no dispone de PowerShell ni del toolchain PS5 completo, por lo que el parser oficial de PowerShell y el build final deben ejecutarse en Windows/WSL, donde `start.bat` analiza `runtime/server.ps1` antes de arrancar.

## 0.2.0 — Ecosistema de proyectos nativos

- Amplía el panel Proyectos a 34 repositorios: boilerplates C++20, OpenGL 4.6, kits UI, Vulkan/RADV, Mesa/winsys, Aurora/WebGPU, upscaling experimental y aplicaciones completas de referencia.
- Distingue bases de proyecto, renderers, drivers, dependencias y aplicaciones de referencia. Los repositorios grandes no se presentan como boilerplates universales.
- Añade inicializadores reales upstream para Native App Boilerplate, ps5-homebrew-ui y PS5 Vulkan Template; crea proyectos independientes fuera del canvas C#.
- Añade un listado de proyectos nativos creados, entradas Compilar, logs del proceso upstream y criterio de éxito basado en el código de salida y un artefacto real.
- Añade preparación del stack Vulkan con los scripts upstream de PS5_Vulkan, su SDK compañero y PS5_Mesa, conservando historial Git completo donde se necesitan commits fijados.
- En la revisión del stack Vulkan consultada se detectó que dos helpers referenciados por el build no estaban presentes. Si faltan, el IDE restaura los archivos reales de `blackbearreloaded/ps5-native-app-boilerplate` y registra hashes/procedencia en `.ps5hs-compatibility.json`.
- Identifica como IA declarada únicamente proyectos que documentan el uso explícito de estas herramientas; AGENTS.md/CLAUDE.md no se tratan como prueba de generación de código.
- Conserva el parser PowerShell de arranque y el límite de servicio `127.0.0.1`.

### Validación

`app.js` ha pasado `node --check`. La comprobación estática de PowerShell encontró delimitadores equilibrados y 18 bloques `try` asociados a `catch`/`finally`. En el entorno de preparación no está instalado PowerShell, por lo que no se ejecutó el parser real ni se realizó una compilación de PS5. El paquete usa `runtime/check-syntax.ps1` para hacer la validación sintáctica real en Windows antes de iniciar el servicio.


## 1.0.1 — 16 de octubre de 2026

- Corregida la interpolación PowerShell de `$sourceName:` en `runtime/server.ps1` para evitar que el parser interprete el colon como una referencia cualificada inválida.
- Actualizados los identificadores de versión visibles en la UI.
- Esta corrección no implica que se haya ejecutado el parser oficial en el entorno de preparación ni una build real de SDK/hardware.


## 1.0.2 — 16 de octubre de 2026

- Añadidas rutas de configuración locales para KytyPS5, Python y PS5 UltraPack.
- Añadida la acción «Probar en Kyty» para lanzar un título compilado desde su carpeta.
- Añadido el empaquetado UltraPack a `.ffpfs`, `.ffpfsc` o `.pkg`, con registro y verificación del archivo de salida.
- Añadida guía en `docs/INTEGRACIONES-KYTY-ULTRAPACK.es-ES.md`.
- La integración no distribuye binarios ni garantiza compatibilidad de emulación o soporte de fPKG en Windows.
