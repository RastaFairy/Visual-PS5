# Registro de cambios

## 1.1.56 — 2026-10-24

- Convierte las colisiones de plataformas y objetos 3D en cajas sólidas: aterrizaje superior, bloqueo lateral y respuesta al golpe desde abajo.
- Añade grosor vertical configurable para las plataformas y muestra el volumen completo del colisionador en el lienzo.
- Actualiza la escena AGC generada y conserva un grosor compatible con los proyectos existentes.
- Añade regresiones para la normalización, el inspector visual, la serialización AGC y la respuesta de colisión.

## 1.1.55 — 2026-10-24

- Sustituye el personaje cúbico por una exploradora original construida con mallas AGC procedurales y animación de brazos y piernas al caminar.
- Renderiza los cristales como octaedros facetados y la meta como un arco luminoso con núcleo giratorio.
- Cambia los puntos de luz y el decorado celeste a geometrías 3D coherentes con la escena visual.
- Añade regresiones para evitar que el renderizador vuelva al personaje de cubos y a cristales cúbicos.

## 1.1.54 — 2026-10-24

- Amplía las mallas de escena visual a cubo, cristal facetado, esfera, cilindro, cono y pirámide.
- Genera las nuevas formas con geometría nativa y normales de iluminación en el runtime AGC.
- Añade sus formas al inspector, al árbol de objetos, a la vista de escena y a la validación del proyecto.

## 1.1.53 — 2026-10-24

- Sustituye la vista isométrica fija por una vista 3D orbitable con control de altura, zoom y desplazamiento.
- Mantiene las transformaciones X/Z y la edición visual de colisiones alineadas al mundo al cambiar la cámara.
- Actualiza los controles accesibles, la ayuda y la versión de caché de recursos del IDE.

## 1.1.52 — 2026-10-24

- Corrige la edición de nombre, posición, dimensiones, color y colisión de objetos 3D: cada cambio de teclado actualiza el modelo y se conserva al guardar.
- Conserva el foco del inspector mientras se escribe y refresca la escena sin sustituir el campo en cada pulsación.
- Añade comprobaciones de integración para la ruta de guardado del inspector 3D.

## 1.1.51 — 2026-10-24

- Permite activar en cada cubo o cristal 3D una caja ajustable para aterrizar sobre su cara superior.
- Añade redimensión visual y controles numéricos para las dimensiones X/Y/Z y el desfase de la superficie de aterrizaje.
- Integra estas superficies en la física AGC y en la comprobación de rutas; los lados de los objetos todavía no bloquean al jugador.
- Aclara en la interfaz y la guía que el editor de juego sigue siendo especializado en niveles de plataformas, no un motor 3D general como Unity.
- Actualiza contratos de escena, cabecera nativa y versión de caché del frontend.

## 1.1.50 — 2026-10-24

- Añade cubos y cristales facetados decorativos editables en la escena 3D visual AGC.
- Permite seleccionarlos, moverlos en X/Z y ajustar altura, tamaño, giro y color desde el inspector.
- Genera las primitivas desde los datos del proyecto y las dibuja en el renderer AGC; identifica expresamente que todavía no tienen colisión física.
- Verifica límites, identificadores, formas y valores de la escena antes de generar el título.

## 1.1.49 — 2026-10-24

- Permite cambiar el tamaño de la caja de colisión de una plataforma arrastrando sus cuatro tiradores visibles en la escena isométrica.
- Conserva la edición numérica y muestra una guía de interacción en el propio editor.
- Verifica el cálculo de redimensión entre coordenadas de pantalla y dimensiones del mundo, con límites para evitar colisiones degeneradas o fuera del motor.

## 1.1.48 — 2026-10-24

- Sincroniza la versión del paquete y la caché del IDE con la interfaz publicada como 1.1.48.
- Incluye el editor de escenas AGC con plataformas, marcadores de recorrido, colisiones ajustables, física, cámara, iluminación y flujos de control visuales.
- Añade verificación completa del paquete UltraPack como opción recomendada.

## 1.1.35 — 2026-10-24

- Integra una toolchain ATRAC9 de código abierto dentro de `toolchains/`; el IDE convierte WAV, MP3, FLAC y AIFF/AIFC offline sin FFmpeg ni `ps4_at9tool.exe`.
- Conserva el audio importado y su vínculo en el proyecto exportable; al compilar juegos AGC genera y valida `dist/<TITLE_ID>/sce_sys/snd0.at9`.
- Aplica el mismo codificador a la edición de presentación de títulos nativos existentes y actualiza los manuales/licencias visibles.

## 1.1.34 — 2026-10-24

- El build AGC registra acciones de juego visuales con su nombre correcto y distingue los proyectos que usan C manual.
- Elimina una función auxiliar sin uso de la fuente generada, que había provocado una advertencia del compilador.
- La vista Código explica en cada backend si el fuente es editable o se regenera desde el modelo visual.
- Añade contratos de regresión para preservar el modo visual y los diagnósticos del build.

## 1.1.33 — 2026-10-24

- Mantiene los proyectos AGC en modo visual al compilar: envía el modelo de bloques, escena y Flujos para que el IDE genere `src/main.c` desde su motor reutilizable.
- Ya no exige contenido en el editor Código para compilar un juego visual; la edición manual sigue disponible como modo separado.
- Muestra en el diálogo y en Salida los bloques, plataformas y acciones que alimentarán la generación visual.
- Añade contratos de regresión para impedir que la compilación convierta accidentalmente un proyecto visual a código manual.

## 1.1.32 — 2026-10-24

- Crea la interfaz del minijuego con bloques, pantallas, propiedades y Flujos; las instrucciones del menú, pausa y partida se leen desde el lienzo visual.
- Añade etiquetas dinámicas para componentes visuales mediante `{current}`, `{total}`, `{percent}` y `{state}`; el contador, el progreso y el sonido responden al estado del juego.
- Mantiene el editor de escena, las colisiones por plataforma, el mando DualSense y las cinco acciones de juego en el modelo visual; el motor AGC se genera y queda en solo lectura.
- Corrige la composición de nombres y avisos del motor para que dependan del título del proyecto, y oculta el botón de pausa al completar el nivel.
## 1.1.31 — 2026-10-24

- Genera el motor AGC de plataformas desde una plantilla reutilizable del IDE; en modo visual ya no exige editar el código C a mano.
- Enlaza acciones de Flujos con inicio, pausa, continuación, reinicio y sonido, y deriva los botones y pantallas efectivos de los componentes configurados.
- Genera desde Juego 3D las colisiones, físicas, cámara, colores, regla de victoria y HUD; el código generado se muestra en solo lectura para inspección.
- Conserva una copia de seguridad del `src/main.c` anterior cuando el proyecto pasa de código manual al motor visual generado.

## 1.1.30 — 2026-10-24

- Evita que los nombres largos de plataforma se superpongan en el mapa isométrico: la vista muestra números legibles y conserva los nombres completos en la lista e inspector.
- Guarda y valida desde la interfaz la ruta de Nebula Steps con seis cristales, cuatro checkpoints, una meta y cajas ajustables por plataforma.
- El backend AGC toma las plataformas, los cristales, la meta, el inicio, la física y sus hitboxes directamente del encabezado generado desde la escena visual.

## 1.1.29 — 2026-10-24

- Añade colisión ajustable por plataforma: activación, medio ancho X, medio fondo Z y desfase vertical; el contorno se dibuja en la vista isométrica.
- El motor AGC usa la caja de colisión editada para detectar aterrizajes y ajustar el punto de apoyo y de reaparición.
- El editor y el build comprueban que inicio, checkpoints, cristales y meta tengan colisión activa y que los objetivos sean alcanzables con la física configurada.
- Sincroniza el código AGC del proyecto Nebula Steps con el editor y deriva los contadores, el progreso y la meta desde la escena guardada.
## 1.1.28 — 2026-10-24

- Añade el editor visual de escena 3D: plataformas arrastrables, propiedades geométricas, marcadores de inicio, cristal, checkpoint y meta, junto con parámetros editables de movimiento y salto.
- Convierte la escena guardada en `src/ps5hs_game_scene.h` durante la integración AGC; el servidor bloquea el build si el programa no incluye y consume los datos visuales.
- Corrige el guardado de propiedades de plataforma y física con eventos delegados; los cambios ya no dependen de un `onchange` asignado a un contenedor sin soporte.
- Documenta el flujo visual de creación de niveles y el enlace con el motor ps5link/AGC.

## 1.1.26 — 2026-10-23

- Permite redimensionar el lienzo desde el IDE, con preajustes y tamaño personalizado entre 640×360 y 7680×4320; al aplicarlo, escala posiciones, tamaños y fuentes de los componentes.
- Separa ese lienzo lógico del perfil de render de referencia: permite previsualizar 720p, 900p, 1080p, 1440p, 4K o medidas personalizadas y muestra en el inspector el rectángulo equivalente en píxeles de salida.
- Guarda el perfil de render con el proyecto sin cambiar el lienzo, el código generado ni el modo de VideoOut que se elija al ejecutar.
- Hace que la paleta, el arrastre, el redimensionado, el inspector, las flechas, los diagnósticos y el contrato de proyectos usen la resolución lógica activa.
- Mapea la geometría de proyecto al lienzo lógico de cada backend. En OpenGL y Vulkan, el renderer escala ese espacio virtual a la superficie activa de VideoOut/swapchain (incluida la salida 4K cuando el modo está disponible); 1920×1080 no fija la resolución física de salida.

## 1.1.25 — 2026-10-23

- Hace seguros todos los IDs de revisión Vulkan Compute y migra grafos antiguos con revisiones inválidas sin asociar mediciones antiguas a una revisión nueva.
- Muestra los diagnósticos del grafo Vulkan Compute en la vista general y los mantiene fuera del bloqueo de compilación de backends distintos.
- Genera el namespace C# a partir del nombre del proyecto para evitar el marcador genérico `SampleApp`.
- Reconoce `libNidResolver` como fuente local offline: snapshot upstream `3f7ce7086c38ef35eb7869aafb247ed544ae3ee1`, licencia GPL-2.0 y documentación de procedencia.

## 1.1.24 — 2026-10-23

- Integra el artefacto PacBrew v0.40.2 fijado localmente en la imagen WSL: bibliotecas estáticas, cabeceras y metadatos pkg-config para ShadowMountPlus. La identidad de imagen y el bundle verifican versión, hash y cada archivo requerido.
- ShadowMountPlus puede usar una caché local en `.runtime/` desde el mismo archivo versionado cuando la distro WSL actual no tiene esas dependencias. PacBrew se mantiene fijado por versión y SHA-256 y se pasa al Makefile upstream sin modificarlo.
- El backend payload respeta `toolchain.llvmMajor` si el proyecto lo fija; si no, selecciona la pareja Clang/LLD/LLVM compatible más reciente de WSL/Ubuntu. Refresca los índices apt como máximo una vez al día, registra la selección y, sin conexión, conserva la versión compatible ya instalada.
- Añade `hostPackages` para herramientas Ubuntu por proyecto y respaldo HTTPS con SHA-256 para dependencias empaquetadas. La resolución busca primero en WSL, proyecto, caché y `toolchains/`; solo intenta instalar o descargar lo declarado cuando falta.
- Corrige la conversión de ruta WSL del archivo PacBrew en el generador de imágenes y añade comprobaciones de dependencias al instalar/verificar la imagen.
- No se afirma compilación de ShadowMountPlus; queda pendiente confirmar el ELF en el entorno local del usuario.

## 1.1.21 — 2026-10-23

- Añade un backend Vulkan Compute separado de los renderizadores de UI: editor de grafo, pases GLSL 450, imágenes `storage-image`, bindings, despacho y resolución de destino ajustable.
- Valida en el cliente y el servidor el orden de lectura/escritura, límites Vulkan, correspondencia de bindings, formato/acceso de imagen y declaraciones GLSL huérfanas.
- Compila offline a SPIR-V Vulkan 1.2 con `glslangValidator` local en WSL, verifica la cabecera y SHA-256 y conserva los archivos parciales ante errores. La operación requiere consentimiento y no ejecuta los shaders en GPU.
- Añade importación de informes GPU ligada a la revisión del grafo y a SHA-256 por shader, con métricas por pase y comparación de rendimiento.
- Los proyectos compute guardan `compute-graph.json`; dejan de presentar o exportar código C# ficticio. Documentación: `docs/VULKAN_COMPUTE.md`.
- No se ejecutó una compilación SPIR-V ni una prueba de GPU en esta intervención.

## 1.1.20 — 2026-10-22

- Añade un bootstrap local para diagnosticar e instalar WSL2 y la imagen Ubuntu del bundle offline, con validación de integridad, comprobación de virtualización/espacio, detección de colisiones, elevación puntual y reanudación después de reiniciar.
- El estado del IDE muestra si está ejecutándose desde un bundle offline, si la distro Visual-PS5 está verificada y qué backends siguen bloqueados para compilación sin red.
- El bundle impide iniciar builds de backends que su matriz de preparación aún no declara validados; no se anuncia compatibilidad offline a partir de la mera presencia de fuentes.
- La instalación Windows y la importación WSL siguen pendientes de validación en un equipo limpio. OpenGL, Vulkan y SharpProspero permanecen bloqueados en la matriz offline hasta cerrar sus dependencias y builds representativos.

## 1.1.19 — 2026-10-20

- El upstream comunitario `blackbearreloaded` desapareció de GitHub (ps5-opengl, ps5-native-app-boilerplate, ps5-homebrew-ui, ProsperoLight, ps5-fsr4, ps5-helixsr) y los builds OpenGL morían con `curl: (22) 404` al descargar el SDK ps5-opengl 1.0.2. Esta versión integra toolchains, pins y mirrors para que una copia local baste y la red sea opcional.
- Nuevo manifiesto `runtime/toolchain-pins.json`: declara los upstreams caídos con sus mirrors verificados (LedyBacer y darkxex publican el tarball del SDK idéntico byte a byte, comprobado contra el SHA-256 original `30d8e51d…`) y fija versión, tamaño y SHA-256 del artefacto binario `ps5-opengl-sdk` 1.0.2.
- `InstallRepo` clona con cadena de candidatos (upstream primero, mirrors después) y registra la fuente usada en `.ps5hs-source.json` (`mirrorRepository`); las copias locales adoptadas siguen intocables y con prioridad.
- Nuevo permiso auditable `allowUpstreamSdkMirrorPatch`: con consentimiento, el IDE reescribe `tools/fetch-opengl-sdk.sh` del proyecto con la cadena de mirrors (marca `# PS5HS_MIRROR_CHAIN`, idempotente, pins de integridad intactos, registro SHA-256 antes/después en `.ps5hs-modifications.json`). Sin consentimiento, el script upstream queda intacto y el fallo es el 404 original. El parche se aplica tanto al crear el proyecto como antes de compilar uno existente.
- Siembra offline del SDK: si `toolchain-pack/ps5-opengl-sdk/ps5-opengl-sdk-1.0.2.tar.gz` existe y verifica el pin, el IDE lo copia a `.deps/ps5-opengl/` del proyecto antes de compilar y el build del SDK no necesita red. Nuevo `runtime/Build-ToolchainPack.ps1` para construir el pack (y un respaldo ZIP opcional) desde las toolchains locales.
- Panel SDKs y dock con salud de toolchains: estado por entrada (`LOCAL · UPSTREAM CAÍDO`, `MIRROR DISPONIBLE`, `SOLO COPIA LOCAL`) y estado del pack (`PACK SDK OK/AUSENTE/SHA MAL`); `GetStatus` expone `toolchainHealth`.
- Documentación: nuevo `docs/TOOLCHAIN-VENDORING.md` con la arquitectura de capas, el manifiesto de pins, el parche, el pack y la postura de licencias (vendoring íntegro, MIT del IDE + GPL de los toolchains, sin binarios de Sony).
- Verificación: parser real de PowerShell OK para `server.ps1`, `native-modification-policy.ps1`, `Build-ToolchainPack.ps1` y tests; `test-native-modification-policy.ps1` ampliado (13 claves + bloque del parche: denegado, autorizado, idempotente, irreconocible) y pasa en pwsh 7.4; nueva suite `test-toolchain-pins.js` registrada en CI; las 11 suites JS pasan; la cadena de mirrors y la siembra offline se probaron de extremo a extremo con el script real (upstream 404 → mirror LedyBacer → verificación y extracción correctas; con tarball sembrado, 3,8 s y cero red).


## 1.1.18 — 2026-10-19

- Corrige el fallo `TypeError: buttons.forEach is not a function` que interrumpía la compilación justo después de confirmar el diálogo «Generar y compilar»: los flujos OpenGL/Vulkan (`buildNativeVisualProject`) y SharpProspero (`buildSharpWithConsent`) consultaban los botones del diálogo con `$` (un solo elemento) en lugar de `$$` (lista), por lo que `forEach` no existía y la promesa del control quedaba rechazada sin capturar antes de desactivar los botones.
- Ambos flujos quedan alineados con el resto del código, que ya usaba `$$` para ese selector: los botones del diálogo se desactivan al iniciar el build y se reactivan en el `finally` como estaba previsto.
- Añade a `test-build-flow.js` una regresión estática que rechaza consultar botones del diálogo con `$` (elemento único) y usar el resultado con `forEach`; esta clase de error ya se había visto en 1.1.5 con el selector del diálogo UltraPack.
- Invalida la caché del frontend con `?v=1.1.18` y alinea `VERSION.txt`, la meta `application-version`, el número visible de la marca, el registro de arranque, los pins de versión de los tests y el nombre del ZIP de CI.
- Verificación: `node --check` sobre `app.js` y los módulos del runtime, las diez suites JavaScript, y una prueba de navegador real del flujo completo (Compilar → diálogo nativo → confirmar) que reproduce el error en la 1.1.17 y comprueba en la 1.1.18 que los botones se desactivan durante el build, que el fallo del backend se registra sin promesas rechazadas y que el `finally` reactiva los controles. El parser de PowerShell y una compilación real de PS5 siguen requiriendo Windows/WSL; esta revisión no cambia `runtime/server.ps1`.

## 1.1.17 — 2026-10-19

- Restaura la compilación de proyectos que contienen botones explícitamente configurados como «Sin acción»: se mantienen como widgets reales sin callback vacío y dejan de bloquear el build completo. Los flujos y las notificaciones configurados siguen usando sus ejecutores reales.
- Registra cada clic de compilación antes de cualquier prevalidación y anota el backend, el contexto del proyecto, los errores de análisis, las etapas del build, la salida del SDK y las excepciones.
- Persiste hasta 500 entradas de diagnóstico en el navegador y añade «Exportar log» para guardar un fichero `.log` que se puede adjuntar al informar de fallos.
- Añade pruebas de regresión para el orden de trazado, la persistencia/exportación del log y la compatibilidad con botones sin acción, sin introducir callbacks vacíos ni código placeholder.

## 1.1.16 — 2026-10-19

- Repara una regresión de compatibilidad al abrir proyectos antiguos: el contrato v2 estricto no se aplica retroactivamente a los nombres de proyectos v1.
- Si el nombre interno de un proyecto legado es incompatible con el formato actual, se normaliza de forma determinista; cuando no puede recuperarse, se deriva del nombre real del archivo `.ps5vproj`, sin crear un nombre genérico ficticio.
- Los proyectos v2 actuales siguen sujetos a la validación estricta; no se rebajan los controles de nombres ni los de seguridad de rutas.
- Añade pruebas de regresión para nombres legados largos, caracteres Unicode, nombres ausentes y rechazo de nombres inválidos en proyectos v2.

## 1.1.15 — 2026-10-19

- Corrige una desincronización de backend: si el generador C++20 OpenGL/Vulkan no está cargado, el IDE falla con un diagnóstico y no cae por accidente en la generación C# de SharpProspero.
- Rechaza botones interactivos sin notificación ni flujo de activación; los generadores ya no emiten botones clicables sin callback ni un método `run_flows` vacío cuando un proyecto no tiene flujos.
- Valida los rangos de `setValue` antes de la generación y durante la vista previa; los índices de selector deben ser enteros que correspondan a opciones existentes y los steppers requieren enteros.
- Corrige la normalización de `progress`/`gauge` para usar el mínimo y máximo reales del modelo, conserva precisión numérica en literales de C++/C# y elimina el recorte silencioso de valores de flujo.
- Hace transaccional la edición del inspector para que números inválidos no se conviertan en cero ni la geometría salga del lienzo por un clamp oculto. La selección inicial de SharpProspero respeta `custom.selected` o el valor explícito del modelo.
- Escapa controles en cadenas C++ con escapes octales fijos para evitar que caracteres hexadecimales contiguos se incorporen al escape. Detecta IDs que colisionan tras transformarse en nombres de campos C#.
- Rechaza banderas `visible`/`checked` ausentes o ambiguas, un backend explícitamente vacío, selecciones no numéricas, nombres de recurso que no se puedan normalizar y flujos numéricos fuera de rango.
- Se ejecutaron las nueve suites JavaScript y `node --check` sobre `app.js` y todos los módulos JavaScript del runtime. No se declara validada una compilación PowerShell, Windows/WSL, toolchain PS5 o consola física desde este entorno.

## 1.1.14 — 2026-10-19

- Endurece el contrato de importación: los componentes deben contener geometría explícita dentro del lienzo, colores válidos y propiedades numéricas requeridas; se rechazan dimensiones faltantes, intervalos invertidos, valores fuera de rango y colores inválidos.
- Valida IDs de componentes, pantallas, recursos y flujos para que puedan usarse de forma segura y consistente en el DOM y en el código generado.
- Normaliza `custom` ausente a un objeto vacío y rechaza estructuras de tipo incorrecto, selecciones que no apuntan a opciones existentes, indicadores booleanos ambiguos y nombres de pantalla duplicados.
- El generador C# deja de sustituir silenciosamente un tema inválido por colores fallback; el tema debe pasar la validación antes de escribir código.
- Añade regresiones para geometría ausente/fuera de lienzo, color inválido, IDs inseguros y normalización de campos opcionales.
- Actualiza el esquema de proyecto a `formatVersion: 2`; la migración explícita de proyectos v1 conserva las pantallas que pueden inferirse de IDs reales y rechaza los casos multipantalla ambiguos en vez de escoger contexto arbitrario.
- Valida nombres de recurso, MIME, data URL y tamaño (1 byte–20 MiB), normaliza nombres de archivo mediante un contrato compartido y genera IDs únicos; importar un recurso vacío o fuera de límite se rechaza antes de alterar el modelo.
- El selector de fuentes deja de mutar el proyecto al renderizar; quitar la fuente seleccionada actualiza el modelo y su historial de forma explícita. Una recuperación local inválida se conserva para evitar borrar automáticamente el único respaldo del usuario.
- Se ejecutaron las suites JavaScript localmente. PowerShell, build real de PS5 y empaquetado UltraPack deben verificarse en Windows/WSL.

## 1.1.13 — 2026-10-19

- Unifica la validación de nombre/TITLE_ID en el cliente; los proyectos nuevos no inventan un TITLE_ID y el servidor rechaza el valor reservado `PPSA00000` antes de descargar o modificar una plantilla.
- Permite compilar código manual sin exigir componentes visuales ni bloquearlo por diagnósticos exclusivos del lienzo; el backend sigue validando el código y su compilación real.
- Bloquea operaciones de proyecto mientras hay una compilación en curso para mantener sincronizados modelo, backend, identificador y resultado.
- Protege los callbacks que terminan después de cerrar un diálogo y evita que el resultado de Configurar entorno se inserte en un modal ajeno.
- Completa el historial con deshacer/rehacer de memoria acotada; elimina funciones y parámetros sin uso y conecta Configurar entorno desde Herramientas.
- Corrige un fallo de contexto del runtime nativo: la pantalla de inicio procede del modelo activo, no del ID fijo `screen-main`.
- Rechaza nombres de pantalla vacíos, temas/colores incompletos, acciones predeterminadas sin implementación o mensaje, valores booleanos ambiguos, navegación sin cambio de pantalla y colisiones de rutas de recursos.
- Valida el límite de 16 texturas antes de generar C++ y evita omitirlas silenciosamente; no inventa backend, etiqueta, opción, acción ni recurso para que la generación parezca correcta.
- Añade pruebas de regresión para los contextos de pantalla, la integridad de acciones/flujos, las colisiones de recursos, la capacidad de texturas y la coherencia API/servidor.
- Pruebas JavaScript ejecutadas localmente; la compilación real de PS5, la sintaxis de PowerShell y UltraPack permanecen pendientes de Windows/WSL.


## 1.1.12 — 2026-10-19

- Corrige el preflight de compilación nativa para validar antes de iniciar el trabajador los permisos requeridos por herramientas de conversión de recursos de presentación y fuentes TTF personalizadas.
- Añade al servidor local los módulos JavaScript de capas y fuentes que `index.html` ya carga; antes, la lista permitida de `ServeStatic` respondía 404 para esos dos recursos.
- Añade una prueba de regresión que comprueba que todos los scripts locales referenciados por `index.html` existen y están permitidos por el servidor.
- Invalida la caché de los scripts del frontend y alinea el número de versión mostrado al iniciar.
- Las suites JavaScript se ejecutaron en el entorno de preparación. No se afirma una compilación real de PS5 ni una prueba en consola.

## 1.1.11 — 2026-10-19

- Añade permisos explícitos, independientes y denegados por defecto para inicializadores/generadores upstream, integración de pantallas OpenGL/Vulkan/SharpProspero, herramientas de compilación, conversión de recursos y fuentes Unicode personalizadas.
- El backend vuelve a validar permisos antes de modificar proyectos o ejecutar herramientas; las operaciones denegadas se detienen antes de escribir archivos.
- Registra los archivos cambiados y sus hashes SHA-256 en `.ps5hs-modifications.json`; rechaza manifiestos de auditoría corruptos y evita seguir enlaces/reparse points.
- Extiende las pruebas JavaScript y PowerShell y la validación automática de Windows para el control de consentimiento y la auditoría.
- La validación cubre sintaxis y regresiones automatizadas; no afirma una compilación de título PS5 ni una prueba en consola física.

## 1.1.10 — 2026-10-18

- Añade un perfil de runtime nativo controlado por PS5 Homebrew Studio para los títulos visuales OpenGL.
- Retira la reserva de L1/R1/Touchpad en el shell de galería, pasa el InputFrame sin filtrar y desactiva el HUD y el panel informativo heredados.
- El perfil se aplica al generar títulos nuevos y al compilar proyectos visuales anteriores identificados por su fuente generada; los proyectos de galería genéricos no se alteran.
- El runtime es idempotente, deja un manifiesto para auditoría y detiene la compilación si las anclas de código upstream no se reconocen.
- Añade pruebas de unidad del parche y validación automática de JavaScript/PowerShell en GitHub Actions; el flujo publica un ZIP versionado como artefacto.
- Renderer y componentes gráficos siguen procediendo de sus fuentes upstream; esta integración controla el shell y la política de entrada, no afirma haber absorbido Mesa o el SDK.
- No se afirma una compilación de título PS5 ni una prueba en consola en esta revisión.

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

## 1.1.15 — 2026-10-19

- Corrige una desincronización de backend: si el generador C++20 OpenGL/Vulkan no está cargado, el IDE falla con un diagnóstico y no cae por accidente en la generación C# de SharpProspero.
- Rechaza botones interactivos sin notificación ni flujo de activación; los generadores ya no emiten botones clicables sin callback ni un método `run_flows` vacío cuando un proyecto no tiene flujos.
- Valida los rangos de `setValue` antes de la generación y durante la vista previa; los índices de selector deben ser enteros que correspondan a opciones existentes y los steppers requieren enteros.
- Corrige la normalización de `progress`/`gauge` para usar el mínimo y máximo reales del modelo, conserva precisión numérica en literales de C++/C# y elimina el recorte silencioso de valores de flujo.
- Hace transaccional la edición del inspector para que números inválidos no se conviertan en cero ni la geometría salga del lienzo por un clamp oculto. La selección inicial de SharpProspero respeta `custom.selected` o el valor explícito del modelo.
- Escapa controles en cadenas C++ con escapes octales fijos para evitar que caracteres hexadecimales contiguos se incorporen al escape. Detecta IDs que colisionan tras transformarse en nombres de campos C#.
- Rechaza banderas `visible`/`checked` ausentes o ambiguas, un backend explícitamente vacío, selecciones no numéricas, nombres de recurso que no se puedan normalizar y flujos numéricos fuera de rango.
- Se ejecutaron las nueve suites JavaScript y `node --check` sobre `app.js` y todos los módulos JavaScript del runtime. No se declara validada una compilación PowerShell, Windows/WSL, toolchain PS5 o consola física desde este entorno.

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
