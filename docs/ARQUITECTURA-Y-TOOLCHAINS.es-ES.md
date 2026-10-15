# Arquitectura y toolchains

## 1. Arquitectura general

La aplicación tiene una interfaz web local y un servicio de automatización en PowerShell. No constituye una toolchain de bajo nivel autónoma: mantiene el modelo visual, genera código de UI y delega la inicialización y compilación en proyectos comunitarios upstream.

\`\`\`text
Navegador: index.html + styles.css + app.js
  | solicitudes HTTP locales / JSON
  v
runtime/server.ps1
  |-- guardar, cargar y exportar modelos
  |-- catálogo e inicialización de plantillas
  |-- integrar fuente y recursos nativos
  '-- ejecutar build upstream y comprobar artefactos

runtime/native-generator.js
  '-- modelo visual -> C++20 / contrato hui::app::Concept

runtime/test-native-generator.js
  '-- pruebas del generador; no es una prueba en PS5
\`\`\`

## 2. Archivos principales

- \`index.html\`: estructura y puntos de entrada del editor web.
- \`styles.css\`: diseño, lienzo, paneles, inspector y diálogos.
- \`app.js\`: modelo, interacciones, render del editor, estado del proyecto, flujos, recursos, diagnóstico, presentación de código y llamadas a la API local.
- \`runtime/server.ps1\`: servicio HTTP local, catálogo de repositorios, guardado/carga/exportación, inicializadores de proyectos, generación/integración y ejecución de builds.
- \`runtime/native-generator.js\`: transforma pantallas, componentes, propiedades, recursos y flujos a C++20 para los backends visuales OpenGL/Vulkan.
- \`runtime/test-native-generator.js\`: pruebas de casos OpenGL, Vulkan y modelo vacío.
- \`runtime/check-syntax.ps1\`: valida la sintaxis del servidor con el parser oficial de PowerShell antes del inicio.
- \`start.bat\`, \`STOP.bat\`: arranque y parada del servicio.
- \`toolchains/\`: fuentes de terceros descargadas durante la preparación; el ZIP base no incluye necesariamente todas las toolchains.

El workspace predeterminado es \`Documentos\\PS5HomebrewStudio\\Projects\`. Los datos de runtime y exportaciones se almacenan bajo \`.runtime\`.

## 3. Servicio HTTP local

El servicio escucha en \`127.0.0.1:47813\`. La interfaz intercambia JSON con el servicio. Las rutas internas incluyen operaciones de estado, catálogo, proyectos, guardar/cargar/exportar, instalación de SDK, creación de plantilla y build visual/nativo. Son detalles de implementación, no una API pública con garantía de estabilidad. No expongas el servicio a redes no confiables.

Si el servicio deja de estar disponible, la interfaz puede recurrir a \`localStorage\` para retener el modelo del navegador; el fallback no sustituye todas las operaciones del servidor ni una copia de seguridad.

## 4. Modelo y generación

El modelo contiene backend, pantallas, componentes, tema, recursos y flujos. Cada componente tiene identificador, tipo, pantalla, geometría y propiedades. El código generado debe escapar literales, respetar límites de valores y resolver identificadores existentes. El generador produce la capa UI/Concept: no crea por sí solo un runtime de título completo, metadatos de título o empaquetado.

### OpenGL
El generador integra una pantalla C++20 contra \`hui::app::Concept\` del kit \`ps5-homebrew-ui\`, ligado al stack OpenGL upstream. Los recursos de imagen se convierten a RGBA8 en \`assets/ps5hs/<id>.rgba\`, con máximo 512×512 píxeles y 16 IDs únicos por pantalla. La carga utiliza el contrato OpenGL del proyecto base y restaura el estado GL que altera. El servidor ejecuta el build real de la plantilla.

### Vulkan/RADV
El flujo crea un título con \`PS5_VulkanTemplate\`, localiza la muestra/ID de programa reales e integra el C++20 generado en el módulo UI Vulkan correspondiente. Las imágenes se registran en \`ps5/assets.json\` y se cargan como texturas RGBA8 mediante el contrato \`VkRenderer::create_texture\` del kit seleccionado. Este backend depende de un conjunto compatible de PS5_VulkanTemplate, PS5_Vulkan, PS5_Mesa/RADV, PS5_PayloadSDK y PS5_VKHomebrewUI. No mezcles ramas/commits sin validar el conjunto; algunas instalaciones necesitan historial Git completo.

### SharpProspero y C++ base
SharpProspero usa el pipeline C#/.NET/NativeAOT de su upstream. El boilerplate C++ inicializa un título nativo y usa scripts de compilación upstream. Ninguno transforma automáticamente cualquier código C# o aplicación arbitraria en una UI portable.

## 5. Recursos

La interfaz puede recibir y organizar imágenes; el backend visual transforma texturas seleccionadas a RGBA8. Para el flujo nativo se valida el encabezado, longitud y dimensiones y se rechazan IDs duplicados. El máximo descrito es 512×512 y 16 IDs únicos. Otros ficheros pueden permanecer en el proyecto, pero no se conectan automáticamente a una API nativa universal.

## 6. Compilación y artefactos

Los builds no se simulan: el servidor ejecuta scripts upstream reales y recoge su log. El IDE solo marca éxito cuando el proceso termina con código cero y encuentra un artefacto verificable como \`eboot.bin\` o ZIP. Scripts auxiliares restaurados desde el boilerplate upstream se registran con procedencia/hash cuando se usa ese mecanismo; no se deben sustituir por stubs vacíos.

## 7. Pruebas reproducibles

\`\`\`powershell
node --check app.js
node --check runtime/native-generator.js
node runtime/test-native-generator.js
\`\`\`

Estos comandos comprueban JavaScript y el generador. En Windows, \`start.bat\` ejecuta la comprobación del parser PowerShell. Para validar un build real es preciso preparar WSL/Linux y todos los requisitos upstream, fijar los commits de dependencias y conservar los logs. La prueba final en hardware debe documentarse por separado.