# Registro de actividad y trazabilidad del IDE

**Estado:** propuesta para revisión del usuario  
**Fecha:** 2026-10-22  
**Proyecto canónico:** `C:\Visual-PS5`  
**Orden:** Fase 0; debe completarse antes de implementar la UI nativa portable OpenGL/Vulkan.

## Objetivo

Permitir que el desarrollador reconstruya de forma local qué hizo el IDE, cómo procesó cada operación, a qué vista, archivo, ruta, servicio, proceso o backend fue dirigida y cuál fue su respuesta. El registro debe incluir cambios del proyecto, pasos de operaciones, resultados, avisos, errores y diagnósticos, incluso si la ventana principal no terminó de iniciar.

La cobertura comprende las acciones significativas de usuario y las operaciones que el IDE inicia o recibe. No pretende grabar movimientos del puntero, hover ni cada repetición de tecla. Una interacción continua, como arrastrar una capa o editar texto, se registra como una operación consolidada al confirmarse.

## Estado actual observado

- `app.js` guarda un máximo de 500 entradas de texto en `localStorage`, presenta el panel Salida y exporta el log como texto. Las entradas no tienen un esquema de evento ni identificadores de correlación generales (`app.js`).
- `index.html` registra errores de arranque, cargas fallidas de recursos y promesas rechazadas sin capturar; también detecta el intento de compilar antes de que el IDE termine de inicializar (`index.html`).
- `toast()` presenta mensajes, pero no registra de forma central los avisos y errores. `changed()` marca el proyecto como modificado sin identificar por sí mismo la acción o el destino (`app.js`).
- El wrapper `api()` ejecuta `fetch()` y devuelve la respuesta, pero no registra centralmente método, ruta, resultado HTTP ni duración (`app.js`).
- El servicio local enruta las API y escribe excepciones en la consola, pero no deja una entrada persistente por cada ruta, handler y respuesta (`runtime/server.ps1`).
- Los trabajos nativos tienen `build.log` y `result.json` bajo `.runtime/build-jobs/<jobId>/`, con salida de toolchain. `StartNativeBuildJob` también guarda el cuerpo completo de la solicitud en `request.json`, que utiliza el proceso trabajador como comunicación entre procesos (`runtime/server.ps1`).
- La política de modificaciones nativas conserva una auditoría distinta con manifiestos y SHA-256 de los archivos tocados. Esta auditoría de modificaciones debe seguir separada y enlazarse al evento de operación que la originó (`runtime/native-modification-policy.ps1`).

## Enfoque elegido

Se añadirá un diario estructurado de eventos, escrito localmente por el servicio de Windows y conectado al IDE mediante un identificador de sesión y un identificador de seguimiento por operación. El mismo seguimiento unirá el evento de usuario, los pasos internos, la solicitud y respuesta API, el trabajo asíncrono, el proceso externo y el artefacto resultante.

La fuente durable del registro será un archivo JSON Lines por fecha, bajo:

`%LOCALAPPDATA%\PS5HomebrewStudio\logs\activity-YYYY-MM-DD.jsonl`

El servicio creará la ruta al iniciar. El registro no se enviará a servicios externos. Los archivos detallados existentes de compilación permanecerán en `.runtime/build-jobs/<jobId>/build.log`; el diario guardará la relación, el resumen, el resultado y la ruta al log detallado, sin duplicar toda la salida del compilador.

La fuente durable no tendrá un límite de 500 eventos ni borrará registros automáticamente en esta etapa. La UI permitirá exportar un seguimiento o un rango de eventos y borrar registros de forma explícita, con confirmación. Los registros de trabajo que contengan la salida de toolchain se incluirán al exportar el seguimiento asociado.

El servicio local será el único escritor del diario durable y serializará las escrituras para evitar líneas JSONL intercaladas cuando coincidan solicitudes y trabajadores. El navegador enviará lotes al endpoint local de ingestión; cada evento conservará su `eventId`, que el servicio usará para reconocer reintentos y evitar duplicados. La respuesta de ingestión distinguirá eventos aceptados y persistidos.

## Modelo de evento

Cada línea contendrá un objeto JSON con `schemaVersion`, `eventId`, `timestampUtc`, `sessionId`, `traceId`, `parentEventId`, `actor`, `eventType`, `action`, `phase`, `severity`, `outcome`, `target`, `destination`, `summary`, `durationMs` y `relatedIds`. Los campos `request`, `response` y `diagnostic` se incluirán cuando correspondan.

- `actor`: usuario, IDE, servicio local, trabajador o proceso externo.
- `action`: verbo estable, como `project.save`, `component.move`, `api.request`, `build.compile` o `asset.import`.
- `phase`: recepción, validación, despacho, ejecución, respuesta o verificación.
- `target`: proyecto, componente, pantalla, ajuste, archivo o recurso afectado.
- `destination`: panel/acción local, ruta API, backend, comando/proceso y directorio de trabajo, según corresponda.
- `outcome`: iniciado, completado, rechazado, cancelado, fallido o parcial.
- `request`/`response`: método y ruta, estado HTTP, resumen seguro y código/resultado. Nunca incluirán automáticamente el cuerpo completo.
- `relatedIds`: IDs de trabajo, manifiesto de auditoría, artefacto o diagnóstico enlazado.

Los niveles serán `DEBUG`, `INFO`, `WARN`, `ERROR` y `FATAL`. Los eventos de usuario y fallos permanecerán disponibles en el navegador mediante la vista Actividad, filtros por seguimiento, acción, severidad y destino, y exportación legible y JSONL.

## Cobertura de registro

### Acciones de usuario y cambios del proyecto

Registrar el inicio y resultado de acciones como nuevo/abrir/cerrar/guardar/importar/exportar proyecto; cambios de backend y ajustes; selección de pantallas y destinos; alta, edición, movimiento, redimensionamiento, orden, ocultación y eliminación de componentes; edición de flujos; importación y retirada de recursos; deshacer/rehacer; vista previa; análisis; permisos concedidos/rechazados; creación de proyectos; compilación y empaquetado.

Los eventos de cambios indicarán el tipo de operación, el ID del elemento y los campos modificados. Para valores escalares seguros del modelo se podrá registrar el valor anterior y el nuevo. Para texto arbitrario, fuente C++, binarios e imágenes se registrarán longitud, tipo y SHA-256, no el contenido. Una operación de arrastre se escribirá una vez al soltar; la edición de texto se agrupará por confirmación/cambio consolidado, no por tecla.

La navegación por paneles y vistas principales podrá registrarse como `INFO`, pero no se registrarán hover, foco transitorio ni movimiento del puntero.

### Solicitudes y respuestas

El wrapper de API generará o heredará un `traceId` y anotará el método, la ruta, el instante de envío, duración, resultado HTTP y resumen de respuesta. El identificador viajará en una cabecera local de correlación y se devolverá en la respuesta cuando sea posible. El servicio anotará la ruta recibida, el handler elegido, resultado HTTP y duración, incluidos 4xx/5xx y excepciones.

Los resúmenes de cuerpos se generarán con una lista permitida de metadatos por ruta (por ejemplo, backend, nombre/ID de proyecto, número de componentes, tamaño de solicitud y cantidad/tamaño de recursos). No se registrarán cuerpos JSON completos, fuentes, tokens, credenciales, cabeceras de autorización ni datos binarios. Los valores de URL que puedan contener secretos se eliminarán o redactarán.

### Procesos y trabajos asíncronos

Cada operación que invoque un proceso externo registrará ejecutable/herramienta, backend, directorio de trabajo, argumentos seguros, política de permiso, hora de inicio/fin, código de salida y artefactos verificados. Los argumentos sensibles se redactarán. La salida completa continuará en el log del trabajo y se asociará mediante `traceId`/`jobId`.

`request.json` seguirá siendo un contenedor IPC temporal necesario para entregar una operación al trabajador, no una copia del diario. El trabajador eliminará ese archivo una vez leído el cuerpo y persistido el resultado, también en la ruta de error. El diario conservará metadatos suficientes para identificar qué operación se ejecutó sin conservar fuente o recursos completos.

### Avisos, errores y diagnósticos

Los avisos y errores mostrados mediante `toast()` se registrarán centralmente. También se registrarán errores JavaScript no capturados, rechazos de promesa, fallos de carga al inicio, excepciones del servidor, errores de API, fallos inesperados de trabajadores, errores de compilación, diagnósticos del analizador y problemas al escribir/exportar el propio registro.

Los diagnósticos incluirán severidad, código estable cuando exista, mensaje, ubicación, origen y `traceId`. Las re-ejecuciones del mismo análisis no crearán ruido: se registrará una nueva incidencia cuando aparezca/cambie el diagnóstico y una finalización de análisis con el resumen de resultados.

Si el servicio todavía no está disponible durante el arranque, el logger temprano conservará los eventos pendientes en una cola local persistente y los reenviará al conectar. Los `eventId` harán idempotente la repetición tras una interrupción. Si falla el almacenamiento durable o se agota la cuota del respaldo local, se mostrará un aviso explícito, se conservarán los eventos mientras haya espacio y no se afirmará que quedaron persistidos. El diario no registrará su propia confirmación de escritura como un nuevo evento de actividad, para evitar recursión.

## Interfaz de consulta y exportación

La interfaz incluirá una vista Actividad accesible desde el IDE, además de conservar la salida detallada de compilación. Permitirá filtrar por nivel, acción, destino y `traceId`; abrir un evento y seguir sus pasos relacionados; navegar desde un evento a su diagnóstico, log de trabajo o artefacto; exportar eventos legibles o JSONL; y borrar registros mediante una acción explícita.

La vista no presentará una respuesta como exitosa solo por haber recibido HTTP 200: mostrará por separado estado HTTP, resultado funcional (`ok`), etapa y verificación del artefacto cuando aplique.

## Protección y límites

- El diario es local y de diagnóstico; no es un registro legal inmutable ni evidencia de hardware.
- No duplicará el contenido de código, imágenes, binarios ni cuerpos de solicitudes. Los proyectos y recursos siguen almacenándose donde corresponde; el registro guarda metadatos y hashes.
- Las rutas y nombres de proyecto pueden revelar información personal. Permanecerán en el perfil local y se incluirán en exportaciones solo cuando describan el destino necesario para entender la operación.
- La exportación advertirá que incluye rutas locales y salida de herramientas antes de crear el archivo.
- La auditoría SHA-256 de modificaciones de toolchains/proyectos seguirá siendo la fuente detallada de archivos tocados; el diario la enlazará por ID.

## Criterios de aceptación

1. Una acción significativa de usuario genera un evento con tiempo UTC, actor, acción, objetivo/destino y resultado.
2. Las ediciones de proyecto identifican entidad y campos afectados, agrupando arrastres y ediciones continuas sin perder el cambio confirmado.
3. Cada solicitud API muestra destino, handler, estado funcional/HTTP y duración con un `traceId` común.
4. Cada trabajo asíncrono enlaza los eventos de interfaz, servidor, trabajador, salida de toolchain y verificación del artefacto.
5. Avisos y errores visibles, diagnósticos y excepciones no capturadas quedan registrados sin exigir que el usuario los copie manualmente.
6. Los registros sobreviven al reinicio del IDE; el historial durable no se limita a las últimas 500 líneas y solo se borra bajo acción explícita del usuario.
7. Si no se puede persistir, la UI avisa, conserva el buffer de respaldo cuando sea posible y señala el posible hueco del registro.
8. Los registros no contienen cuerpos completos de proyectos, código fuente, recursos binarios, tokens ni credenciales; `request.json` temporal se elimina después de entregar el trabajo.
9. El usuario puede seguir un `traceId`, consultar el evento y exportar el diario junto a los logs de trabajo relacionados.
10. El diario no afirma compilación satisfactoria sin el resultado funcional y la verificación de artefacto que exige el pipeline.
11. Esta fase cubre la aplicación y su servicio local; se completa antes de empezar el modo C++ portable OpenGL/Vulkan.

## Validación prevista

La revisión deberá cubrir acciones locales de proyecto, una solicitud API correcta y fallida, permisos rechazados, un aviso y un error visibles, un error de arranque, una operación asíncrona completada/fallida, correlación del artefacto, persistencia tras reinicio, exportación y fallo simulado de escritura. También comprobará que el diario no contenga fuente/cuerpos completos y que el archivo IPC desaparezca al finalizar el trabajador.

Esta validación comprueba trazabilidad del IDE. No equivale a validar un título en consola ni sustituye la evidencia de compilación de cada backend.
