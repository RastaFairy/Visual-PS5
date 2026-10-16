# Empaquetado con PS5 UltraPack

PS5 Homebrew Studio integra la CLI de [PS5 UltraPack](https://github.com/knutwurst/ps5-ultrapack) para crear imágenes .ffpfs y .ffpfsc y, si el entorno dispone del helper, paquetes .pkg. UltraPack es un proyecto externo y conserva sus propios requisitos y licencias.

## Configuración

1. Inicia el IDE con start.bat.
2. Abre Herramientas.
3. Configura Python 3.10 o posterior y la ruta del archivo backend/cli.py del checkout de UltraPack.
4. Utiliza la instalación integrada o configura un checkout existente. La reparación del entorno Python no debe borrar las fuentes existentes ni sobrescribir el helper nativo local.
5. Guarda la configuración. Las rutas quedan en .runtime/integrations.json y no deben añadirse al repositorio.

## Crear una imagen

1. Compila un proyecto nativo.
2. Comprueba que el origen contenga eboot.bin y sce_sys/param.json. Un ZIP/PKG antiguo no sirve como prueba.
3. Pulsa Empaquetar y selecciona .ffpfs, .ffpfsc o .pkg.
4. Mantén activa la casilla «Verificar el contenido contra el origen» para pasar --verify a la CLI. La comprobación puede consumir más tiempo y memoria.
5. Revisa el registro final, el código de salida, la ruta del resultado y los mensajes del verificador.

El resultado se guarda en packages-ultrapack/<formato>/<fecha-hora>. Cada ejecución usa una carpeta distinta para evitar confundir los resultados nuevos con artefactos previos. La tarea se ejecuta en segundo plano para que la interfaz continúe respondiendo.

## Interpretación del resultado

Un código de salida cero, un archivo presente y una estructura válida son señales distintas. Cuando se activa --verify, UltraPack compara el contenido con el origen según las capacidades de la CLI utilizada. Si el log indica que se omitió la verificación o que se comprobaron cero hashes, no describas ese resultado como una verificación íntegra de contenido.

El mantenedor ha informado de que una imagen .ffpfsc generada funciona en hardware real. Es una validación específica y no garantiza todos los títulos, firmwares ni formatos. En Windows, .pkg requiere un helper nativo y dependencias compatibles.

## Diagnóstico

- Comprueba que Python sea 3.10+ y que las rutas de Python y cli.py sean correctas.
- Conserva el log, el código de salida y la ruta del artefacto.
- Revisa los permisos y que el archivo no esté bloqueado.
- Empaqueta únicamente contenido que tengas derecho a utilizar; no redistribuyas recursos protegidos.
- No incluyas tokens, claves o credenciales en logs públicos.