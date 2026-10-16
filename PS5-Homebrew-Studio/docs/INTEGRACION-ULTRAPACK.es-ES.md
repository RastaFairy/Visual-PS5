# Empaquetado de títulos con PS5 UltraPack

PS5 Homebrew Studio integra la CLI de PS5 UltraPack para convertir un directorio de título nativo en `.ffpfs`, `.ffpfsc` o `.pkg`. El IDE no intenta inferir que un título funciona a partir de la existencia de cualquier ZIP: antes de habilitar el empaquetado exige un `eboot.bin` y `sce_sys/param.json`.

## Configuración

1. Inicia el IDE con `start.bat`.
2. Pulsa **Herramientas**.
3. Configura Python 3.10 o posterior y el archivo `backend\\cli.py` del repositorio local de [PS5 UltraPack](https://github.com/knutwurst/ps5-ultrapack).
4. Usa **Descargar UltraPack (fuente)** para obtener el repositorio y preparar el entorno virtual local, o instala el checkout por separado y configura sus rutas.
5. Pulsa **Guardar configuración**. Las rutas quedan en `.runtime\\integrations.json`, no en el repositorio.

## Generar paquetes

1. Compila una base C++ nativa o un título visual OpenGL/Vulkan.
2. Comprueba que la compilación haya terminado con código cero y que el registro confirme `eboot.bin` y `sce_sys/param.json`.
3. Pulsa **Empaquetar** en la barra superior para el último título compilado o en la tarjeta del proyecto correspondiente.
4. Selecciona el formato y revisa el registro final, el código de salida y la ruta del artefacto.

El resultado se guarda dentro de `packages-ultrapack/<formato>/<fecha-hora>` en el proyecto. Cada ejecución usa un directorio distinto para no mezclar artefactos anteriores. El trabajo de empaquetado se ejecuta en un proceso independiente: el servidor HTTP sigue respondiendo y el IDE consulta el registro del trabajo hasta que termina.

## Estructura del título y formatos

El origen debe contener `eboot.bin` y `sce_sys/param.json`. Si el ejecutable se encuentra en `dist` y los metadatos están en la raíz del proyecto, Homebrew Studio prepara una carpeta temporal para reunir el ejecutable, los metadatos y los recursos habituales encontrados. Revisa el contenido antes de distribuirlo, porque proyectos concretos pueden necesitar archivos adicionales.

- `.ffpfs`: imagen PFS sin compresión.
- `.ffpfsc`: imagen PFS comprimida.
- `.pkg`: fPKG experimental. En Windows exige el helper nativo `backend\\native\\ffpfsc-pkg-tool.exe` y sus dependencias. Si falta, el IDE lo comunica antes de iniciar el empaquetado.

## Diagnóstico y límites

- El registro muestra el comando invocado, el directorio de trabajo, la salida estándar/error, el código de salida y el artefacto encontrado.
- La presencia del CLI o del helper no garantiza que sus dependencias estén completas. Revisa el error concreto que devuelve UltraPack.
- Una compilación no se declara lista solo por producir un ZIP/PKG residual. El IDE necesita un `eboot.bin` y metadatos de título para habilitar las acciones de empaquetado.
- UltraPack y sus dependencias son proyectos externos. Instálalos por separado, revisa las instrucciones y licencias upstream y aporta únicamente recursos que tengas derecho a utilizar.
