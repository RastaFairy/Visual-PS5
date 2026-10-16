# Validación y problemas conocidos — PS5 Homebrew Studio 1.1.5

Última actualización: 2026-10-17.

## Verificado por el usuario

- **Compilación nativa OpenGL desde el IDE:** el usuario confirma que compila correctamente en su entorno Windows/WSL.
- **Empaquetado PS5 UltraPack:** el usuario confirma que la acción vuelve a funcionar después de corregir el selector de botones del diálogo.
- **Pruebas automatizadas locales:** pasan `node --check app.js`, `node --check runtime/native-generator.js` y `node runtime/test-native-generator.js`, incluida la comprobación de orden de capas para las salidas OpenGL y Vulkan.

La confirmación de compilación y UltraPack corresponde al entorno del usuario; no implica que se hayan validado todas las combinaciones de SDK, backend o hardware.

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
