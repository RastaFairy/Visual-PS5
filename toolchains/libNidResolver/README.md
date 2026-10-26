# libNidResolver — copia offline

Biblioteca C para resolver NIDs de Prospero desde otro proceso. Este código se distribuye como dependencia fuente; no es un SDK autónomo ni un backend de interfaz gráfica.

## Procedencia

- Upstream: https://github.com/astrelsky/libNidResolver
- Rama: `master`
- Commit incluido: `3f7ce7086c38ef35eb7869aafb247ed544ae3ee1`
- Licencia: GPL-2.0; conservar el aviso completo de `LICENSE` al redistribuir.
- La fuente versionada en este directorio coincide con los 12 archivos del árbol upstream de ese commit. No se requiere Git ni conexión a Internet para consultarla o copiarla.

## Integración

Está pensada para incorporarse a un proyecto consumidor compatible, como dependencia CMake. El `CMakeLists.txt` upstream declara C17 y CMake 3.20, y espera que el proyecto consumidor configure su toolchain PS5 y las variables SDK que utiliza (`D_PS5SDK`, `C_DEFS`, `C_FLAGS` y `V_FW`). Comprueba también las rutas de cabeceras del consumidor antes de añadir el subdirectorio. Esta carpeta por sí sola no produce una aplicación o payload instalable.

La entrada del gestor de toolchains verifica esta copia local mediante `.ps5hs-source.json`; no descarga ni actualiza archivos automáticamente.