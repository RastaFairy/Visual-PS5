# Registro de cambios — Visual-PS5 / PS5 Homebrew Studio

## 1.1.0 — 16 de octubre de 2026

- Retirada la integración activa de lanzamiento mediante Kyty; el flujo se centra en títulos compilados y pruebas en hardware.
- Corregidos los selectores de interfaz que impedían activar acciones de UltraPack.
- Empaquetado como tarea en segundo plano con registro consultable, código de salida y ruta del artefacto.
- Añadida verificación opcional del contenido contra el origen mediante --verify; la casilla está activada por defecto.
- Aplicada codificación UTF-8 a las salidas Python/CLI para conservar caracteres no ASCII en los registros.
- Conservada la compatibilidad con Windows PowerShell 5.1, validación de Python 3.10+ y reparación de UltraPack sin reemplazar el checkout ni el helper local.
- La preparación de empaquetado exige eboot.bin y sce_sys/param.json; los ZIP/PKG residuales no se consideran prueba de título válido.
- Eliminados stubs vacíos del generador Vulkan y rechazados flujos con destinos inexistentes.
- Añadidos manuales completos en español, inglés, francés, alemán, chino simplificado, japonés y ruso, junto con créditos de upstream.

### Validación

La CI cubre sintaxis JavaScript, pruebas del generador, parsers PowerShell 7 y Windows PowerShell 5.1, contratos de integración, versión y creación del ZIP. El mantenedor comunicó una prueba satisfactoria de empaquetado .ffpfsc en hardware real; no implica compatibilidad universal.

## Historial

Los cambios de las versiones 1.0.x permanecen en el historial Git.