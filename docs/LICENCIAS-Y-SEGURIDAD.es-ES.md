# Licencias y seguridad

## Licencias

El propio IDE se distribuye conforme al fichero \`LICENSE\` de su árbol. Las plantillas, librerías, SDK y drivers descargados desde GitHub conservan sus propias licencias, avisos de copyright, condiciones de redistribución y obligaciones de publicar modificaciones. La licencia de este editor **no** sustituye ni hereda automáticamente las licencias upstream.

Antes de distribuir un proyecto generado:
1. Anota el repositorio y commit exactos de cada dependencia.
2. Lee \`LICENSE\`, \`COPYING\`, \`NOTICE\`, \`THIRD_PARTY_NOTICES\` y documentación relevante dentro de cada repositorio.
3. Comprueba dependencias transitivas, assets, shaders, fuentes y recursos empaquetados.
4. Conserva avisos y ofertas de código fuente cuando las licencias lo exijan.
5. No confundas una licencia GPL de una UI opcional con la licencia de la plantilla base, ni supongas que todo el stack usa la misma licencia.
6. Para redistribuir binarios, consulta las condiciones concretas del proyecto y pide asesoramiento jurídico cuando sea necesario.

Las licencias que aparecen en el catálogo son etiquetas informativas recogidas al preparar la versión, no una conclusión legal definitiva. “Revisar upstream” significa exactamente que el usuario debe examinar la licencia real del commit que descargue.

## Archivos y marcas de Sony

Visual-PS5 no es un producto oficial ni avalado por Sony. No incluye firmware, claves, archivos propietarios de Sony, juegos, ROMs, BIOS ni payloads que eludan protecciones. El usuario es responsable de disponer legalmente de cualquier entorno, recurso de juego o dispositivo que utilice.

## Seguridad local

- El servidor escucha en \`127.0.0.1:47813\`; no cambies el bind a una interfaz de red pública.
- Descarga toolchains solo desde los repositorios upstream declarados y revisa los commits antes de ejecutar scripts.
- Una compilación puede ejecutar Make, Python, shell y otras herramientas de terceros. Comprueba los scripts y permisos; no ejecutes builds privilegiados sin entenderlos.
- El workspace contiene código y recursos locales. No abras proyectos de origen desconocido sin revisarlos.
- No guardes credenciales, tokens, claves ni secretos en el modelo, logs, issue reports o repositorio.
- Conserva logs con secretos eliminados y no adjuntes dumps privados ni contenidos de juegos protegidos.
- El fallback \`localStorage\` se encuentra dentro del navegador; no lo consideres copia de seguridad cifrada.
- Las comprobaciones estáticas y el hash del ZIP no son una auditoría de seguridad ni una firma criptográfica de confianza.

## Informe de problemas

Incluye versión, sistema operativo, versión de PowerShell, backend, commit de cada dependencia, pasos reproducibles y logs depurados. No afirmes compatibilidad con firmware o hardware que no hayas probado.

## Validación conocida

Durante la preparación se ejecutaron comprobaciones de sintaxis JS y pruebas del generador; se validó la sintaxis C++ generada contra interfaces de prueba. No se dispuso del parser oficial de PowerShell, de toda la toolchain PS5 ni de hardware físico. Por ello no se declara completada una compilación real con el SDK final.

## Validación posterior comunicada por el mantenedor

El mantenedor informó de que una imagen .ffpfsc funcionó en hardware real. Esta prueba específica no sustituye una auditoría de seguridad ni garantiza la compatibilidad de todos los títulos y firmwares.
