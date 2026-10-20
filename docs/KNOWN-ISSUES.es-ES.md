# Validación y problemas conocidos — PS5 Homebrew Studio 1.1.18

Última actualización: 2026-10-19.

## Validación técnica de 1.1.18 en el entorno de preparación

- Corregida la regresión de 1.1.17 que abortaba la compilación nativa tras confirmar el diálogo: `TypeError: buttons.forEach is not a function` en `app.js:1364`. Los flujos OpenGL/Vulkan y SharpProspero usaban `$` (elemento único) donde el resto del código ya usaba `$$` (lista). El detalle del parche está en `docs/patches/FIX-MODAL-BUTTONS-1364.es-ES.md`.
- `node --check` sobre `app.js` y los módulos del runtime: correctos. Las diez suites JavaScript pasan, incluida la nueva regresión estática de selectores de `test-build-flow.js` y el pin de versión actualizado de `test-project-contracts.js`.
- Prueba de navegador del flujo completo: en la 1.1.17 se reproduce el TypeError exacto tras «Confirmación recibida para generación/compilación opengl-ui»; en la 1.1.18 los botones del diálogo se desactivan durante el build, la fuente C++20 se genera (19.776 caracteres en la prueba) y el fallo del backend se captura y registra sin promesas rechazadas, con reactivación de los controles en el `finally`.
- El análisis sintáctico de PowerShell, una compilación C++20 real y un empaquetado UltraPack siguen pendientes de Windows/WSL; esta corrección no altera `runtime/server.ps1` ni los proveedores de build.

## Validación técnica de 1.1.17 en el entorno de preparación

- Corregida la regresión que impedía abrir algunos `.ps5vproj` antiguos por el nombre guardado: la migración v1 admite nombres heredados incompatibles y usa el nombre de archivo como recuperación determinista cuando hace falta; v2 sigue rechazando nombres inválidos.

- `node --check app.js`, `runtime/native-generator.js`, `runtime/layer-model.js`, `runtime/unicode-fonts.js`, `runtime/native-modification-policy.js` y `runtime/project-contracts.js`: correctos.
- `node runtime/test-layer-model.js`: correcto (normalización de capas antiguas, prioridad explícita, alta de componentes y comprobaciones CSS).
- `node runtime/test-native-generator.js`: correctos los casos OpenGL/Vulkan y las validaciones negativas.
- `node runtime/test-structure-explorer.js` y `node runtime/test-unicode-fonts.js`: correctos.
- `node runtime/test-unicode-integration.js`, `node runtime/test-native-modification-policy.js`, `node runtime/test-project-contracts.js`, `node runtime/test-api-contracts.js` y `node runtime/test-static-assets.js`: correctos los contratos UI/API/backend, el preflight, el modelo de proyecto y los recursos locales.
- La v1.1.17 mantiene la validación del modelo y de las respuestas asíncronas, y ahora rechaza al importar geometría incompleta o fuera de lienzo, colores inválidos, IDs técnicos inseguros, datos numéricos ausentes o contradictorios y estados con tipos ambiguos. La prueba de importación también cubre `custom` omitido, opciones fuera de rango y nombres de pantalla duplicados.
- El esquema de proyecto queda versionado como `formatVersion: 2`. La migración desde v1 admite un contexto de pantalla único o IDs de pantalla ya declarados; cuando no se puede determinar con certeza la pantalla activa, el archivo se rechaza y no se sobrescribe el autosalvado.
- Los recursos deben llevar nombre seguro, MIME válido, `dataUrl` real y tamaño de 1 byte a 20 MiB. La selección de fuente se modifica únicamente por una acción explícita del usuario, no como efecto lateral del renderizado.
- El ZIP local de esta auditoría se verifica con `unzip -t` y se calcula su SHA-256 al terminar el empaquetado. Esto solo confirma la integridad del contenedor; no sustituye una compilación Windows/WSL ni una prueba de consola.

**Control de modificaciones nativas:** la suite PowerShell comprueba denegación por defecto, permisos explícitos, manifiestos, enlaces y hashes SHA-256. La ejecución de GitHub Actions para la rama de auditoría confirmó el análisis sintáctico PowerShell y las pruebas aisladas de esa revisión; los cambios nuevos deben superar de nuevo la CI.

**Validación PowerShell realizada con PowerShell 7.6.6:** los seis scripts revisados pasan el parser; `test-native-runtime.ps1` y `test-native-modification-policy.ps1` pasan. Este entorno no dispone de la toolchain PS5 del equipo de destino; por ello no se ejecutaron una compilación C++20 real de PPSA19918 ni una operación UltraPack de extremo a extremo. La prueba de arranque del servidor en Debian necesita un directorio temporal para suplir la ruta Documentos de Windows y no sustituye una prueba en Windows.

## Verificado por el usuario en versiones anteriores (1.1.5)

- **Compilación nativa OpenGL desde el IDE:** el usuario confirma que compila correctamente en su entorno Windows/WSL.
- **Empaquetado PS5 UltraPack:** el usuario confirma que la acción vuelve a funcionar después de corregir el selector de botones del diálogo.
- **Pruebas automatizadas locales:** pasan `node --check app.js`, `node --check runtime/native-generator.js` y `node runtime/test-native-generator.js`, incluida la comprobación de orden de capas para las salidas OpenGL y Vulkan.

Las confirmaciones siguientes se refieren a la versión 1.1.5 y al entorno del usuario, no a una prueba de extremo a extremo de la 1.1.9. Tampoco implican que se hayan validado todas las combinaciones de SDK, backend o hardware.

## Runtime OpenGL autónomo de 1.1.12

- El perfil controlado por el IDE elimina la captura de L1/R1/Touchpad y el HUD de galería en títulos visuales generados.
- Las pruebas de unidad del perfil verifican el paso directo de InputFrame, la idempotencia y el fallo seguro ante una estructura upstream inesperada.
- La validación PowerShell y la compilación de título real deben confirmarse en Windows/WSL mediante GitHub Actions y el entorno de destino. Las pruebas estáticas no sustituyen una compilación de PS5 ni una prueba en consola.
- El renderer y los componentes gráficos siguen dependiendo de fuentes upstream; el IDE controla el shell y la política de entrada.

## Problemas y validaciones pendientes

### 1. Preparación directa del SDK OpenGL compartido en una unidad DrvFS sin `metadata`

**Estado: pendiente; existe una vía alternativa para proyectos visuales generados por el IDE.**

El intento de preparar la copia compartida de `toolchains/ps5-opengl` bajo una unidad Windows montada en WSL (por ejemplo, `/mnt/d/PS5-Homebrew-Studio/toolchains/ps5-opengl`) todavía puede fallar cuando DrvFS no tiene habilitada la opción `metadata` y Git necesita aplicar permisos POSIX. La versión 1.1.4/1.1.5 evita ese paso redundante para proyectos OpenGL generados por Homebrew Studio: ejecuta el `build.ps1` del proyecto y utiliza su SDK/dependencias locales. Esto es una mitigación acotada al flujo indicado, no una reparación general del SDK compartido ni de todas las instalaciones WSL.

**Alternativas actuales:** seguir compilando desde el proyecto generado con su `build.ps1`; o revisar `docs/WSL_PERMISSIONS.md` y configurar DrvFS/WSL siguiendo el procedimiento documentado antes de construir directamente la copia compartida.

### 2. Backend Vulkan de extremo a extremo

**Estado: validación parcial.** El generador tiene pruebas automatizadas del orden de capas para la salida Vulkan, pero no se dispone de confirmación de una compilación Vulkan completa en el entorno Windows/WSL del usuario. No debe darse por validado únicamente a partir de las pruebas JavaScript.

### 3. Conversión y empaquetado de audio ATRAC9

**Estado: no confirmado en el entorno del usuario.** La preparación de `snd0.at9` depende de las herramientas/codificador externo que requiere la plantilla upstream. No se ha confirmado aquí el ciclo completo de conversión, validación e inclusión del audio en una compilación real. Si falla, registrar las herramientas disponibles y la salida exacta del conversor.

### 4. Ejecución en consola PS5 física

**Estado: no verificado.** Que el IDE compile y que UltraPack genere un paquete no confirma que el título arranque y funcione en hardware PS5. Hace falta una prueba real del paquete en consola para cerrar esta validación.

## Criterio para cerrar pendientes

Registrar backend, versión de SDK/plantilla, entorno Windows/WSL, herramienta/codificador usados y salida completa de cada etapa. No cambiar estos elementos a «resuelto» sin una prueba reproducible en el entorno afectado.
