# Publicar una release de Visual-PS5 en GitHub

Este procedimiento explica cómo publicar el ZIP binario v1.0.1 como activo de una release. El repositorio tiene actualmente documentación en dos idiomas; el ZIP corregido se entrega por separado y debe adjuntarse manualmente como activo de GitHub Release para que otras personas puedan descargarlo desde la página del repositorio.

## Antes de publicarla

1. Descarga el archivo adjunto PS5-Homebrew-Studio-v1.0.1.zip y el archivo PS5-Homebrew-Studio-v1.0.1.sha256.
2. Comprueba que el hash del ZIP coincide exactamente con el contenido del archivo SHA-256.
3. No publiques la release como “probada en PS5”: esta versión ha pasado pruebas estáticas del generador, pero no se ha validado con el SDK completo ni en una consola física.
4. Mantén el repositorio privado salvo que se haya decidido expresamente hacerlo público.

## Crear la release

1. Abre el repositorio RastaFairy/Visual-PS5 en GitHub.
2. Entra en **Releases** y elige **Draft a new release**.
3. Crea la etiqueta **v1.0.1** sobre la rama principal y utiliza el título **Visual-PS5 / PS5 Homebrew Studio v1.0.1**.
4. Adjunta los archivos ZIP y SHA-256 en el área de activos de la release. No pegues el ZIP en un archivo Markdown ni lo renombres sin recalcular el hash.
5. Incluye en las notas que v1.0.1 corrige la interpolación PowerShell en SaveProject y que la validación con PowerShell/SDK real y hardware queda pendiente.
6. Revisa la visibilidad del repositorio y pulsa **Publish release**.

## Comprobación posterior

Descarga la release publicada en una carpeta limpia, calcula de nuevo SHA-256 y verifica el ZIP con la herramienta de archivos de tu sistema. Después pruébalo en Windows PowerShell 7.6.7, ejecuta start.bat y conserva el resultado del parser. Solo después de un build upstream correcto y una prueba en hardware se debe añadir una afirmación específica sobre esos entornos.