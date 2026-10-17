# Manual de usuario — PS5 Homebrew Studio 1.1.7

Última actualización: 17 de octubre de 2026. La interfaz de la aplicación continúa en español; estos manuales localizados no significan que la UI ya se haya traducido.

## Novedades y validación de 1.1.7

- Añade la selección de una fuente TrueType (`.ttf`) para compilar texto Unicode en OpenGL y Vulkan. El IDE hornea atlas con los caracteres usados por el proyecto y detiene el build si falta un glifo requerido. Incluye cobertura de prueba para cirílico, griego, japonés, chino y coreano; no añade IME CJK ni shaping RTL completo. [Guía de fuentes Unicode](UNICODE-FUENTES.es-ES.md).

- La pestaña **Estructura** separa las pantallas editables del modelo visual de los estados detectados en C++ nativo. Permite buscar estados, consultar el mapa de transiciones, ver etiquetas detectadas y saltar a las líneas de declaración o renderizado. Las rutas C++ se infieren estáticamente, pueden faltar transiciones complejas y no convierten un menú dibujado a mano en componentes editables.

- Los botones de acción de UltraPack y Presentación ya no fallan por el selector del diálogo.
- La compilación OpenGL de proyectos visuales generados por el IDE ejecuta el `build.ps1` local y reutiliza el SDK/dependencias del propio proyecto.
- El diálogo de compilación nativa permite seleccionar icono, fondos de selección/lanzamiento y música. El gestor de pantallas y la jerarquía permiten organizar menús y capas.
- El mantenedor ha confirmado la compilación OpenGL y el empaquetado UltraPack en Windows/WSL. Vulkan completo, conversión ATRAC9 y ejecución en hardware PS5 no están verificados. Consulta [problemas conocidos](../PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md).

## 1. Requisitos

Para abrir el IDE: Windows 10/11, permisos de lectura y escritura en la carpeta de la aplicación y PowerShell 7 recomendado. El lanzador también admite Windows PowerShell 5.1.

Para compilar: Git, WSL/Linux y las dependencias upstream del backend elegido. SharpProspero/C# requiere la versión de .NET indicada por su revisión. Los títulos C++ necesitan toolchains compatibles con su plantilla. UltraPack requiere Python 3.10 o posterior y un checkout de [PS5 UltraPack](https://github.com/knutwurst/ps5-ultrapack).

## 2. Instalación y arranque

1. Descarga o genera el paquete de la rama que quieras probar.
2. Extrae la carpeta en una ubicación con permisos de escritura; evita directorios protegidos por Windows.
3. Ejecuta start.bat y deja abierta la ventana de PowerShell del servidor.
4. Si el navegador no se abre automáticamente, visita http://127.0.0.1:47813/.
5. Para detener el servicio, cierra su ventana o utiliza STOP.bat.

El servidor escucha únicamente en 127.0.0.1. No lo expongas a la red ni cambies la escucha a 0.0.0.0. Los proyectos del editor se guardan por defecto en Documentos/PS5HomebrewStudio/Projects.

## 3. Interfaz y proyectos visuales

El lienzo representa un área virtual de 1920×1080; no es una captura exacta de la interfaz del sistema PS5. Usa el panel de componentes para añadir controles, el inspector para editar geometría y propiedades, la jerarquía para ordenarlos y el gestor de pantallas para dividir la UI. El editor de flujos conecta eventos con acciones como notify, setText, toggleVisibility, setValue, changeColor y navigate cuando el componente, el evento y el backend admiten esa combinación.

Crea el proyecto, elige el backend antes de preparar dependencias, añade componentes y recursos, usa identificadores únicos y configura las pantallas. Ejecuta los diagnósticos y corrige los destinos que apunten a elementos inexistentes. Guarda con Ctrl+S. Exportar un modelo o ZIP no equivale a compilar un título nativo.

## 4. Backends y compilación

**SharpProspero / C#:** utiliza el pipeline real upstream y .NET/NativeAOT. Comprueba la versión de .NET que necesita el commit instalado.

**OpenGL nativo / C++20:** genera una pantalla compatible con el contrato de ps5-homebrew-ui. Las imágenes seleccionadas se convierten a RGBA8, con límite de 512×512 píxeles y hasta 16 identificadores de textura únicos por pantalla.

**Vulkan/RADV / C++20:** crea un título mediante PS5_VulkanTemplate e integra la UI en el módulo Vulkan compatible. Requiere revisiones compatibles de PS5_Vulkan, PS5_Mesa/RADV, PS5_PayloadSDK y PS5_VKHomebrewUI.

El IDE ejecuta scripts upstream reales y conserva los logs. El código de salida cero no basta: el empaquetado de títulos nativos requiere eboot.bin y sce_sys/param.json. El IDE no distribuye SDK propietarios de Sony ni garantiza compatibilidad con todos los firmwares.

## 5. Empaquetar con UltraPack

1. Abre Herramientas y configura Python 3.10 o posterior y el archivo backend/cli.py de UltraPack.
2. Guarda la configuración. Las rutas quedan localmente en .runtime/integrations.json.
3. Selecciona un proyecto nativo compilado y pulsa Empaquetar.
4. Elige .ffpfs, .ffpfsc o .pkg. En Windows, .pkg depende de un helper nativo y de sus dependencias.
5. Mantén activada la casilla «Verificar el contenido contra el origen» para pasar --verify a UltraPack. La verificación puede aumentar el tiempo de ejecución y el uso de memoria.
6. Revisa el log final, el código de salida, la ruta del archivo y los avisos. Un artefacto antiguo no demuestra que la ejecución actual haya tenido éxito.

Las salidas se guardan bajo packages-ultrapack por formato y fecha/hora. Cada empaquetado se ejecuta en segundo plano para mantener operativo el editor. El mantenedor ha informado de una imagen .ffpfsc generada y probada correctamente en hardware real; esto no garantiza cualquier título, firmware o backend.

## 6. Pruebas y diagnóstico

Con Node.js instalado, ejecuta desde la carpeta PS5-Homebrew-Studio: node --check app.js, node --check runtime/native-generator.js y node runtime/test-native-generator.js. Estas pruebas revisan sintaxis JavaScript y casos del generador; no sustituyen la compilación con la toolchain completa de PS5 ni una prueba en consola.

Si el servidor no arranca, conserva el error completo y comprueba PowerShell y los permisos. Si falla el build, registra backend, versiones y commits upstream, salida íntegra y código de salida. Si falla UltraPack, revisa las rutas de Python y cli.py, la presencia de eboot.bin y sce_sys/param.json y los permisos del destino. No compartas tokens, claves, ficheros protegidos ni logs con secretos.

## 7. Licencias y alcance

Los SDK, drivers, plantillas y kits conservan sus licencias propias. Revisa LICENSE, COPYING, NOTICE y las condiciones de redistribución antes de publicar un binario. Visual-PS5 no es un SDK oficial de Sony, no incluye firmware, claves, juegos ni BIOS y no instala automáticamente títulos en la consola. La vista previa no es un emulador de PS5 ni valida runtime, audio, entrada o persistencia.
