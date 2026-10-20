# Corrección de compilación nativa: selector de botones del diálogo, app.js línea 1364

## Síntoma

Tras confirmar «Generar y compilar» en el diálogo nativo, el registro de Salida muestra:

```text
[BUILD …] Confirmación recibida para generación/compilación opengl-ui.
ERROR
BOOT: promesa rechazada sin capturar: TypeError: buttons.forEach is not a function
    at HTMLButtonElement.action (http://127.0.0.1:47813/app.js?v=1.1.17:1364:96)
```

La compilación se detiene justo después de la confirmación: los botones del diálogo nunca se desactivan y el flujo no llega a generar código.

## Causa

`app.js` define dos selectores: `$` devuelve un único elemento (`querySelector`) y `$$` devuelve una lista (`[...querySelectorAll]`), que es la que dispone de `forEach`. En la versión 1.1.17, `buildNativeVisualProject` (OpenGL/Vulkan) y `buildSharpWithConsent` (SharpProspero) consultaban los botones del diálogo con `$`:

```js
const buttons=$('#modalActions button');buttons.forEach(b=>b.disabled=true);
```

`querySelector` devuelve el primer botón (o `null`), no una lista, por lo que `buttons.forEach` no existe y la función async del botón queda rechazada sin capturar. El resto del código ya usaba `$$` para ese mismo selector; esta clase de error ya se había visto en 1.1.5 con el diálogo UltraPack.

## Solución aplicada

Cambiar, en `buildNativeVisualProject` (línea 1364):

```js
const buttons=$('#modalActions button');
```

por:

```js
const buttons=$$('#modalActions button');
```

Y lo mismo en `buildSharpWithConsent` (línea 1448). El `finally` de ambos flujos reactiva los botones con la misma variable, así que la reactivación queda cubierta sin más cambios.

## Aplicación manual

1. Cierra la instancia del editor (cierra la ventana de PowerShell o ejecuta `STOP.bat`).
2. Abre `app.js` con un editor de texto UTF-8.
3. Busca las dos apariciones de `const buttons=$('#modalActions button')` y sustitúyelas por `const buttons=$$('#modalActions button')`. No toques las que ya usan `$$`.
4. Guarda y ejecuta de nuevo `start.bat`. Con el paquete 1.1.18 no hace falta recarga forzada: la consulta de versión pasa a `?v=1.1.18` y el navegador descarga los archivos nuevos. Si parcheas a mano sobre la 1.1.17, haz un Ctrl+F5 la primera vez.

## Verificación

Se aplicó al paquete 1.1.18 y se comprobó en un navegador real con el flujo completo (Compilar → diálogo nativo → permisos → confirmar): la 1.1.17 reproduce el TypeError exacto tras «Confirmación recibida»; la 1.1.18 desactiva los dos botones del diálogo durante el build, genera la fuente C++20 (19.776 caracteres en la prueba), registra el fallo del backend sin promesas rechazadas y reactiva los controles en el `finally`. `node --check` y las diez suites JavaScript pasan, incluida la nueva regresión estática que impide reutilizar `$` (elemento único) con `forEach`. El build real de PS5 depende del toolchain de Windows/WSL y no se afirma aquí.
