# Integraciones externas: KytyPS5 y PS5 UltraPack

## Qué se integra

PS5 Homebrew Studio añade dos acciones por proyecto nativo compilado:

- **Probar en Kyty**: inicia `kyty_emulator.exe --game "<carpeta-del-título>"` con el directorio del título que contiene `eboot.bin`.
- **UltraPack**: ejecuta la CLI local de PS5 UltraPack para generar `.ffpfs`, `.ffpfsc` o `.pkg`. La salida se guarda en `packages-ultrapack/<formato>/<fecha-hora>` dentro del proyecto.

Las integraciones se ejecutan únicamente en el equipo local. No se descargan binarios del emulador ni se redistribuyen herramientas de terceros con Homebrew Studio.

## Configuración

1. Inicia Homebrew Studio con `start.bat`.
2. Pulsa **Herramientas** en la barra superior.
3. Introduce la ruta absoluta a `kyty_emulator.exe`, si ya has instalado o compilado Kyty.
4. Introduce el ejecutable de Python 3.10 o posterior.
5. Introduce la ruta a `backend\cli.py` dentro de tu checkout de PS5 UltraPack. El botón **Descargar UltraPack (fuente)** puede clonar el repositorio en `toolchains\ps5-ultrapack`.
6. Pulsa **Guardar configuración**. Las rutas quedan almacenadas en `.runtime\integrations.json`, no en el repositorio.

Kyty está disponible en [KytyPS5](https://github.com/KytyPS5/KytyPS5). Si lo compilas desde fuentes, la ubicación del ejecutable puede variar; configúrala manualmente.

UltraPack está publicado en [knutwurst/ps5-ultrapack](https://github.com/knutwurst/ps5-ultrapack). Homebrew Studio ejecuta el archivo `backend/cli.py` con `--to ffpfs`, `--to ffpfsc` o `--to pkg`. Las dependencias requeridas por ese repositorio deben instalarse según sus propias instrucciones.

## Cómo usarlo

1. Crea una base C++, una app UI OpenGL o un título Vulkan con Homebrew Studio.
2. Compila desde el IDE y comprueba que se haya generado un `eboot.bin`.
3. En la tarjeta del proyecto, pulsa **Probar en Kyty** para iniciar el emulador.
4. Pulsa **UltraPack**, selecciona el formato y ejecuta el empaquetado. El registro indica el resultado real y la ruta del artefacto.

Para crear imágenes de juego con UltraPack, el directorio de origen debe incluir `eboot.bin` y `sce_sys/param.json`. Si los metadatos están en la raíz del proyecto pero el ejecutable se encuentra en `dist`, Homebrew Studio prepara una carpeta temporal con el ejecutable y los metadatos conocidos. Revisa los recursos de la salida antes de distribuirla; un proyecto puede requerir otros archivos específicos.

## Limitaciones

- Kyty es un emulador experimental; iniciar el proceso no significa que el título sea compatible ni que haya arrancado correctamente.
- Un `eboot.bin` aislado puede no bastar: algunos proyectos necesitan bibliotecas, recursos u otra estructura de título.
- El soporte de UltraPack fuera de macOS varía según las dependencias instaladas. El formato `.pkg` requiere el helper de fPKG y no se garantiza que esté listo en Windows.
- La integración comunica el código de salida y busca el archivo generado; no sustituye una comprobación en consola o dispositivo compatible.
- Instala los proyectos upstream por separado y respeta las licencias de cada repositorio y dependencia. Homebrew Studio no incluye, solicita ni redistribuye claves, firmware ni bibliotecas propietarias.
