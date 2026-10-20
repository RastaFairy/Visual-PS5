# Auditoría de estabilidad · v1.1.17

## Alcance de 1.1.18

La 1.1.18 es una corrección puntual de la 1.1.17: sustituye dos selectores de `app.js` (líneas 1364 y 1448, `$` → `$$`), invalida la caché del frontend con `?v=1.1.18` y añade las regresiones asociadas. No cambia el modelo de datos, los contratos de importación ni `runtime/server.ps1`; las conclusiones de la auditoría de 1.1.17 que siguen se mantienen para esta revisión.

La versión 1.1.17 incorpora una corrección de compatibilidad: los nombres de proyectos heredados se normalizan durante la migración, y los nombres v2 mantienen la validación estricta.

## Correcciones del modelo y los contextos

- El runtime C++ inicia en el `currentScreen` del modelo; ya no comienza en un identificador constante que podía dejar vacía la pantalla inicial.
- La generación nativa rechaza un backend omitido, nombre vacío, tema o colores incompletos, geometría ausente/cero, opciones vacías y acciones predeterminadas sin mensaje.
- Los recursos mantienen su ID original a través de la normalización. Se detectan IDs de recurso duplicados y colisiones tras normalizar los nombres de archivo. Se rechazan más de 16 rutas de textura únicas antes de generar código.
- Los flujos exigen valores explícitos compatibles con sus destinos y con sus rangos. Los índices de selector no se redondean ni recortan, los steppers requieren enteros y los valores de progreso/medidor se normalizan según `min/max`. Un interruptor no convierte un texto arbitrario en `false`; la navegación hacia la misma pantalla no se presenta como transición válida.
- Se eliminaron las etiquetas y opciones de sustitución del generador visual. Los componentes con recursos o acciones sin implementación se rechazan con un error legible. Un botón configurado como «Sin acción» se conserva como widget pasivo y no bloquea el build; si debe reaccionar, se requiere un flujo real. Los proyectos sin flujos generan el comportamiento runtime explícito y no una función vacía.
- La importación valida el modelo antes de sustituir el estado activo; geometría, colores, IDs, valores numéricos, banderas booleanas y referencias deben ser coherentes. No se inventan valores cuando faltan campos críticos.
- `custom` ausente se normaliza como objeto vacío (su estructura opcional válida); tipos incorrectos, texto personalizado no textual y opciones seleccionadas inexistentes se rechazan. Las banderas `visible` y `checked` deben ser booleanos reales.
- Los callbacks tardíos y los guardados asíncronos no deben marcar como guardada una versión distinta de la enviada. El inspector rechaza números y geometría inválidos sin convertirlos a cero ni recortarlos automáticamente.
- Se eliminó la selección automática de colores fallback en el generador C#; el tema debe ser válido antes de producir código. Si el generador C++20 no está cargado, el IDE detiene la generación en lugar de emitir C# bajo un backend OpenGL/Vulkan.
- El esquema de proyecto `formatVersion: 2` requiere todos los campos de contexto. Los proyectos v1 se migran en una etapa identificable; la migración usa IDs de pantalla existentes o la pantalla única antigua y se detiene si la correlación multipantalla es ambigua.
- Los archivos de recurso tienen validación común para nombre, MIME, data URL, tamaño y rutas, con límite de 20 MiB. Se usan IDs UUID y el renderizado del selector de fuente no cambia el estado.
- Si un autosalvado no puede validarse, no se elimina automáticamente: queda preservado para recuperación.

## Validación realizada

Se ejecuta `node --check` en `app.js` y todos los módulos JavaScript de `runtime/`, además de diez suites JavaScript: modelo de capas, generación nativa, explorador de estructura, fuentes Unicode, integración Unicode, política de modificaciones, contratos de proyecto, contratos API, recursos estáticos y trazabilidad del build. El generador se prueba con modelos OpenGL/Vulkan válidos y negativos, incluida la pantalla activa, los flujos inválidos, la colisión de rutas de imagen y el límite de texturas.

PowerShell 7.6.6 está disponible en este entorno: los seis scripts revisados pasan el parser y las suites `test-native-runtime.ps1` y `test-native-modification-policy.ps1` pasan. No hay toolchain PS5; por ello, no se afirma una compilación real C++20, una operación UltraPack completa ni una prueba en hardware. El intento de compilación ahora abre el panel Salida antes del preflight, conserva 500 entradas de log en localStorage y permite exportarlas como .log, incluidos errores que antes retornaban sin diagnóstico. La prueba de arranque en Debian usa una ruta de Documentos temporal; falta repetir el flujo en Windows/WSL antes de considerar el IDE completamente verificado.
