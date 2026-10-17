# Solución de permisos WSL / DrvFS

## Error identificado

En algunos equipos la compilación OpenGL falla con:

```text
error: chmod on /mnt/d/.../.git/config.lock failed: Operation not permitted
fatal: could not set 'core.filemode' to 'false'
```

El problema no es que el proyecto PS5 necesite ejecutarse como administrador. WSL está accediendo a una unidad NTFS de Windows mediante DrvFS sin la opción `metadata`, por lo que Git no puede establecer los permisos POSIX que necesita al crear la configuración del repositorio. La guía de Microsoft explica cómo se traducen los permisos en DrvFS y cómo `metadata` permite guardar los bits de permisos Linux. [Microsoft — File permissions for WSL](https://learn.microsoft.com/windows/wsl/file-permissions).

## Reparación incluida

1. Guarda el trabajo y termina las compilaciones WSL en curso.
2. Abre la distribución configurada para el IDE. Por ejemplo, desde PowerShell de Windows ejecuta `wsl -d Debian` (usa el nombre que aparezca en Configurar entorno).
3. Desde esa terminal Linux ejecuta el script incluido en la instalación. Si el IDE está en `D:\PS5-Homebrew-Studio`, el comando es:

   ```bash
   sudo bash /mnt/d/PS5-Homebrew-Studio/runtime/fix-wsl-permissions.sh
   ```

   Cambia la ruta por la carpeta real del IDE. El script hace una copia de seguridad de `/etc/wsl.conf`, conserva las demás secciones y añade `metadata` a `[automount] options`. Si ya existe `options`, añade la opción en vez de crear una sección duplicada.
4. Cierra la terminal WSL. Desde PowerShell de Windows ejecuta `wsl --shutdown`. Este comando detiene todas las distribuciones WSL en ejecución; úsalo solo cuando hayas terminado las tareas abiertas.
5. Inicia de nuevo WSL y vuelve a compilar desde el IDE. La comprobación previa de PS5 Homebrew Studio ahora debe permitir `make source-fetch` cuando la unidad montada incluya `metadata`.

El IDE también detecta la configuración antes de construir el SDK OpenGL y muestra instrucciones directas si falta `metadata`. Si ya está activado y persiste un error de permisos, comprueba los permisos NTFS de tu usuario de Windows sobre la carpeta de PS5 Homebrew Studio y `toolchains`; no ejecutes el IDE, Git ni `make` como root o administrador.

## Fuentes

- [Microsoft Learn — File permissions for WSL](https://learn.microsoft.com/windows/wsl/file-permissions)
- [Microsoft Learn — Advanced settings configuration in WSL (`wsl.conf`)](https://learn.microsoft.com/windows/wsl/wsl-config)
- [PS5 OpenGL](https://github.com/blackbearreloaded/ps5-opengl)
