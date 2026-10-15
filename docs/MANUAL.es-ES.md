# Manual de uso — PS5 Homebrew Studio

Este manual corresponde a la distribución 1.0.0. Los nombres de botones y APIs pueden aparecer en inglés porque son los identificadores originales de la aplicación o de sus dependencias.

## 1. Requisitos

**Para abrir el editor:** Windows 10/11, permisos de lectura y escritura en la carpeta de la aplicación, y PowerShell 7 recomendado (Windows PowerShell 5.1 como alternativa).

**Para compilar:** se necesitan además Git, WSL/Linux y las dependencias específicas de la plantilla seleccionada. Los requisitos exactos dependen de SharpProspero/.NET, OpenGL o Vulkan/RADV. La primera compilación Vulkan puede compilar RADV desde fuentes y consumir bastante tiempo y espacio en disco.

## 2. Instalación y arranque

1. Descarga el ZIP desde la entrega o reconstruye el paquete indicado por el README.
2. Verifica el SHA-256 publicado para ese archivo.
3. Extrae el ZIP en una carpeta con permisos de escritura. Evita ubicaciones protegidas por Windows.
4. Ejecuta \`start.bat\`.
5. Si el navegador no se abre, visita \`http://127.0.0.1:47813/\`.
6. Mantén abierta la ventana PowerShell que ejecuta el servicio.

El lanzador ejecuta \`runtime/check-syntax.ps1\` antes de iniciar el servidor. Este script pide al parser de PowerShell que compruebe \`runtime/server.ps1\`. Si la validación falla, se aborta el arranque. Para detener el servicio, cierra su ventana o usa el mecanismo \`STOP.bat\` disponible en la distribución. No publiques el puerto en la red ni cambies la escucha a \`0.0.0.0\`.

## 3. Partes de la interfaz

- **Lienzo:** superficie virtual de 1920×1080 para colocar y dimensionar elementos. No es una captura exacta del sistema PS5.
- **Panel de componentes:** inserta los controles que conoce el modelo del editor.
- **Inspector de propiedades:** ajusta posición, tamaño, texto, color, valor y visibilidad.
- **Jerarquía y pantallas:** organiza componentes en pantallas. La navegación tiene que enlazarse a través de flujos/acciones.
- **Editor de flujos:** conecta eventos con acciones, por ejemplo mostrar una notificación, cambiar texto o valor, alternar visibilidad, cambiar color o navegar.
- **Vista previa:** muestra una aproximación del modelo en el editor. No emula la PS5 ni valida el código que ejecutará el dispositivo.
- **Panel de código y diagnósticos:** enseña código generado y advertencias. El análisis estático no sustituye al compilador ni las pruebas en tiempo de ejecución.

## 4. Crear una interfaz

1. Selecciona **Nuevo proyecto** y asigna un nombre descriptivo.
2. Elige el backend apropiado antes de configurar dependencias.
3. Añade controles al lienzo. Arrástralos para cambiar su posición y utiliza el inspector para ajustar dimensiones y apariencia.
4. Crea las pantallas necesarias. Mantén IDs/nombres únicos y estables.
5. Establece valores iniciales y revisa las propiedades del componente.
6. Define flujos. Comprueba que cada destino referencia un ID válido y que la acción es compatible con el backend.
7. Importa imágenes desde el área de recursos y asígnalas a componentes. Importar un archivo no significa que el código nativo sepa decodificarlo: esa integración depende del backend.
8. Ejecuta el análisis estático. Corrige errores y examina especialmente IDs, textos escapados, valores máximos/mínimos y pantallas de destino.
9. Guarda con **Ctrl+S** o el botón Guardar.

La ubicación de trabajo por defecto en Windows es \`Documentos\\PS5HomebrewStudio\\Projects\`. Si el servidor no responde, el navegador puede mantener una copia del modelo en \`localStorage\`; esta copia solo pertenece a ese navegador y no reemplaza una exportación de seguridad.

## 5. Guardar, abrir y exportar

- **Guardar:** guarda el modelo y los fuentes asociados en el workspace local si el servicio está activo.
- **Abrir:** carga proyectos del workspace o modelos compatibles \`.ps5vproj\`/JSON.
- **Exportar ZIP:** crea un archivo de proyecto. Si no se puede exportar con el servicio, puede descargarse un modelo \`.ps5vproj\`.
- **Exportar no es compilar:** el ZIP de proyecto no debe suponerse que contenga \`eboot.bin\`. El binario se obtiene mediante el proceso de compilación de la plantilla.

Haz una copia de seguridad antes de cambiar de backend o ejecutar herramientas upstream que modifiquen fuentes.

## 6. Elegir el backend

### SharpProspero / C#
Utiliza el pipeline C# upstream y NativeAOT. Requiere la versión compatible de .NET y del SDK según la revisión instalada. Los payloads, plugins y aplicaciones gráficas son tipos de proyecto diferentes: no los trates como intercambiables.

### OpenGL nativo / C++20
Genera la pantalla de UI usando el contrato \`hui::app::Concept\` del kit OpenGL upstream y la integra en una plantilla nativa. Las imágenes se convierten a RGBA8, con tamaño máximo de 512×512 píxeles y un máximo de 16 IDs únicos de textura por pantalla. El build llama a los scripts reales del upstream; no es una compilación simulada.

### Vulkan/RADV nativo / C++20
Integra la pantalla en PS5 Vulkan Template con el módulo UI Vulkan esperado. Las imágenes RGBA8 se registran como recursos del título y se cargan mediante el contrato \`VkRenderer::create_texture\` del kit correspondiente. Las revisiones de plantilla, Mesa/RADV y PS5_PayloadSDK deben ser compatibles.

Las acciones visuales documentadas incluyen \`notify\`, \`setText\`, \`toggleVisibility\`, \`setValue\`, \`changeColor\` y \`navigate\`. La disponibilidad depende del componente/evento y backend. El teclado nativo para controles de entrada es un teclado ASCII básico (A–Z, números, puntuación básica, espacio, borrar, limpiar, aceptar y cancelar); no es un teclado multilingüe ni un IME del sistema.

## 7. Compilación

1. Inicializa o selecciona una plantilla upstream y revisa su documentación y licencia.
2. Comprueba Git/submódulos, WSL/Linux, rutas, herramientas del host, versiones de SDK y dependencias.
3. Corrige los errores estáticos relevantes antes de pulsar **Compilar**.
4. Lee el log completo. Conserva código de salida, ruta y versiones de dependencias si falla.
5. El IDE solo informa de éxito si el proceso upstream termina con código cero y se encuentra un artefacto verificable, como \`eboot.bin\` o un ZIP.
6. Prueba el resultado por separado en un entorno y equipo autorizado.

El éxito del build no prueba la ejecución en consola, compatibilidad con todos los firmwares, rendimiento, entrada, audio, persistencia o comportamiento de todos los recursos.

## 8. Ejecutar las pruebas del generador

Con Node.js instalado, desde la carpeta extraída:

\`\`\`powershell
node --check app.js
node --check runtime/native-generator.js
node runtime/test-native-generator.js
\`\`\`

Las pruebas comprueban casos del generador OpenGL, Vulkan y modelo vacío. No ejecutan una PS5 ni sustituyen una compilación upstream.

## 9. Solución de problemas

- **El servidor no arranca:** conserva todo el error de \`start.bat\`; comprueba PowerShell, permisos y sintaxis. Si se informa de una variable de PowerShell mal formada, consulta [la corrección de la línea 627](patches/FIX-POWERSHELL-627.es-ES.md).
- **El navegador no conecta:** confirma que la ventana del servidor sigue activa y usa exactamente la URL local.
- **No guarda:** revisa permisos del directorio Documentos, espacio en disco y estado del servicio.
- **El build falla:** revisa el log íntegro, Git, submódulos, WSL y las versiones de las toolchains. No sustituyas scripts upstream por ficheros vacíos.
- **No aparece una textura:** comprueba el vínculo del recurso, dimensiones, límite de 16 IDs y soporte del backend.
- **Falla en consola:** registra firmware, revisiones de dependencias, artefacto, pasos y log. El editor no garantiza compatibilidad universal.

## 10. Informar de un fallo

Incluye versión del IDE, Windows/PowerShell, backend, pasos mínimos, salida completa sin secretos y commit de las dependencias. Indica si falla al arrancar, editar, generar, compilar o ejecutar. No adjuntes claves, tokens, datos privados ni archivos de juegos protegidos.