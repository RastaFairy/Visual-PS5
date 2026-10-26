'use strict';
(function attachNativeModificationPolicy(root) {
  const ENTRIES = [
    {key:'allowExecuteUpstreamGenerationTools', label:'Autorizar el generador/inicializador upstream', description:'Ejecuta las herramientas oficiales de la plantilla para generar o inicializar la carpeta del proyecto. Se registra la procedencia; el desarrollador acepta ejecutar ese código externo.', backends:['opengl-ui','vulkan-ui','vulkan-template','nativecpp','hui-gl'], required:true, files:['upstream generator/initializer']},
    {key:'allowExecuteUpstreamBuildTools', label:'Autorizar la ejecución de herramientas de build upstream', description:'Ejecuta Make/CMake/Ninja y scripts de build. En payload, el IDE también puede actualizar índices apt, instalar los paquetes Ubuntu declarados y descargar por HTTPS archivos declarados con SHA-256. Se registra cada acción; no se añade ningún repositorio.', backends:['opengl-ui','vulkan-ui','vulkan-template','nativecpp','hui-gl','sharp','payload','ps5link'], required:true, files:['Makefile/build.ps1/ps5/tools/build.sh and dependency build scripts']},
    {key:'allowPayloadProjectIntegration', label:'Payload: escribir el código C/C++ y la configuración de compilación', description:'Guarda src/main.c o src/main.cpp, el Makefile administrado por el IDE, project.json y las salidas ELF del proyecto payload. Requiere también autorizar explícitamente las herramientas de compilación.', backends:['payload'], required:true, files:['project.json','src/main.c|src/main.cpp','.ps5hs-payload.mk','build/*.elf']},
    {key:'allowPs5LinkProjectIntegration', label:'ps5link: integrar el código C, los bloques visuales y el título AGC', description:'Guarda src/main.c, genera el puente C a partir de componentes, flujos y la escena de juego, y prepara un título local con eboot.bin, portada, metadatos y la libc.prx local seleccionada. No sube ni instala el título en la consola.', backends:['ps5link'], required:true, files:['project.json','src/main.c','src/ps5hs_visual.c','src/ps5hs_visual.h','src/ps5hs_game_scene.h','dist/<TITLE_ID>/']},
    {key:'allowSharpTemplateIntegration', label:'SharpProspero: integrar código y metadatos generados por el IDE', description:'Autoriza copiar la plantilla UI administrada por Homebrew Studio, escribir Program.cs, actualizar SampleApp.csproj, adaptar sce_sys/param.json e integrar los recursos del proyecto. Es independiente de ejecutar build-app.ps1.', backends:['sharp'], required:true, files:['SampleApp.csproj','Program.cs','sce_sys/param.json','assets/']},
    {key:'allowExecuteUpstreamAssetTools', label:'Autorizar conversión offline de recursos de presentación', description:'Ejecuta el conversor local de ATRAC9 y tools/prepare-assets.ps1 para validar la pista importada y actualizar solo los archivos de presentación elegidos. No descarga ni usa FFmpeg o ps4_at9tool.', backends:['opengl-ui','vulkan-ui','nativecpp','hui-gl','vulkan-template','ps5link'], required:false, files:['sce_sys/icon0.png','sce_sys/pic0.dds','sce_sys/pic1.dds','sce_sys/snd0.at9','sce_sys/param.json']},
    {key:'allowOpenGlTemplateIntegration', label:'OpenGL: integrar la pantalla visual en la plantilla', description:'Modifica concepts.hpp y reemplaza registry.cpp para que la pantalla generada sea la UI activa.', backends:['opengl-ui'], required:true, files:['src/concepts/concepts.hpp','src/concepts/registry.cpp']},
    {key:'allowWindowsBuildEntrypointPatch', label:'Adaptar build.ps1 al target Makefile app', description:'Modifica el punto de entrada build.ps1 y añade variables del SDK. Si no se autoriza, el IDE conserva intacto ese script.', backends:['nativecpp','hui-gl','opengl-ui'], required:false, files:['build.ps1']},

    {key:'allowOpenGlRuntimeProfile', label:'OpenGL: desactivar el HUD y las capturas de mando heredadas', description:'Modifica src/app/shell.cpp y src/app/shell_render.cpp. Si no se autoriza, se conserva la política original de la plantilla.', backends:['opengl-ui'], required:false, files:['src/app/shell.cpp','src/app/shell_render.cpp']},
    {key:'allowOpenGlEuropeanAtlas', label:'OpenGL: activar atlas tipográfico europeo', description:'Modifica tools/bake-fonts.sh para solicitar un atlas mayor con caracteres europeos. Desactivado por defecto.', backends:['opengl-ui'], required:false, files:['tools/bake-fonts.sh']},
    {key:'allowVulkanTemplateIntegration', label:'Vulkan: integrar la pantalla visual en el programa de la plantilla', description:'Reemplaza el screen.cpp de la muestra seleccionada y, cuando hay imágenes, añade el cargador de texturas a la fuente del programa.', backends:['vulkan-ui'], required:true, files:['examples/<id>/kit/screen.cpp','examples/<id>/<id>.cpp']},
    {key:'allowVulkanComputeShaderBuild', label:'Vulkan Compute: generar archivos del proyecto y ejecutar glslangValidator local', description:'Escribe los shaders y el manifiesto en una carpeta nueva de Proyectos y ejecuta el compilador GLSL ya instalado en WSL. No descarga dependencias ni ejecuta el shader en la GPU.', backends:['vulkan-compute'], required:true, files:['shaders/*.comp','compute-graph.json','build/spirv/*.spv']},
    {key:'allowVulkanBuildHelperRestore', label:'Vulkan: restaurar scripts auxiliares ausentes', description:'Autoriza copiar tools/ninja-build.sh y tools/build-host-tools.sh desde PS5 Native App Boilerplate a toolchains/PS5_Vulkan si realmente faltan.', backends:['vulkan-ui','vulkan-template'], required:false, files:['toolchains/PS5_Vulkan/tools/ninja-build.sh','toolchains/PS5_Vulkan/tools/build-host-tools.sh']},
    {key:'normalizeBuildFiles', label:'Normalizar finales de línea para el build', description:'Convierte finales CRLF a LF en scripts, manifiestos, Makefiles y fuentes C/C++ del proyecto. No altera el contenido lógico y registra los hashes antes/después.', backends:['opengl-ui','vulkan-ui','vulkan-template','nativecpp','hui-gl'], required:false, files:['Makefile, scripts, fuentes C/C++, cabeceras y manifiestos de build']},
    {key:'allowCustomUnicodeFont', label:'Modificar herramientas upstream para hornear una fuente TTF personalizada', description:'Solo se aplica si has seleccionado una TTF: modifica font-baker, bake-fonts.sh y, en Vulkan, setup-kit.sh para incluir los glifos solicitados.', backends:['opengl-ui','vulkan-ui'], required:false, files:['tools/font-baker/bake_font.cpp','tools/bake-fonts.sh','ps5/ui/setup-kit.sh']}
  ];
  const KEYS = ENTRIES.map(entry => entry.key);
  function defaults() {
    const result = {};
    KEYS.forEach(key => { result[key] = false; });
    return result;
  }
  function normalize(value) {
    const result = defaults();
    if (value && typeof value === 'object') KEYS.forEach(key => { result[key] = value[key] === true; });
    return result;
  }
  function entriesForBackend(backend) {
    return ENTRIES.filter(entry => entry.backends.includes(backend));
  }
  function getEntry(key) {
    return ENTRIES.find(entry => entry.key === key) || null;
  }
  function requiredForBackend(backend) {
    return entriesForBackend(backend).filter(entry => entry.required).map(entry => entry.key);
  }
  function missingForPermissions(value, requiredKeys) {
    const policy = normalize(value);
    const missing = [];
    for (const key of [...new Set(requiredKeys || [])]) {
      if (!KEYS.includes(key) || policy[key] !== true) missing.push(key);
    }
    return missing;
  }
  function requiredForNativeVisualBuild(backend, options = {}) {
    const required = requiredForBackend(backend);
    if (options.hasPresentationAssets) required.push('allowExecuteUpstreamAssetTools');
    if (options.hasCustomFont) required.push('allowCustomUnicodeFont');
    return [...new Set(required)];
  }
  function missingForNativeVisualBuild(backend, value, options = {}) {
    return missingForPermissions(value, requiredForNativeVisualBuild(backend, options));
  }
  function missingForBackend(backend, value, hasCustomFont) {
    return missingForPermissions(value, [...requiredForBackend(backend), ...(hasCustomFont ? ['allowCustomUnicodeFont'] : [])]);
  }
  const api = {version:1, entries:ENTRIES.slice(), defaults, normalize, entriesForBackend, getEntry, requiredForBackend, requiredForNativeVisualBuild, missingForPermissions, missingForBackend, missingForNativeVisualBuild};
  if (root) root.PS5HSNativeModificationPolicy = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis === 'object' ? globalThis : null);
