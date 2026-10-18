'use strict';
(function attachNativeModificationPolicy(root) {
  const ENTRIES = [
    {key:'allowExecuteUpstreamGenerationTools', label:'Autorizar el generador/inicializador upstream', description:'Ejecuta las herramientas oficiales de la plantilla para generar o inicializar la carpeta del proyecto. Se registra la procedencia; el desarrollador acepta ejecutar ese código externo.', backends:['opengl-ui','vulkan-ui','nativecpp','hui-gl','sharp'], required:true, files:['upstream generator/initializer']},
    {key:'allowExecuteUpstreamBuildTools', label:'Autorizar la ejecución de herramientas de build upstream', description:'Ejecuta Make/CMake/Ninja y los scripts de build de la plantilla o driver. No se ejecuta sin esta autorización.', backends:['opengl-ui','vulkan-ui','nativecpp','hui-gl','sharp'], required:true, files:['Makefile/build.ps1/ps5/tools/build.sh and dependency build scripts']},
    {key:'allowOpenGlTemplateIntegration', label:'OpenGL: integrar la pantalla visual en la plantilla', description:'Modifica concepts.hpp y reemplaza registry.cpp para que la pantalla generada sea la UI activa.', backends:['opengl-ui'], required:true, files:['src/concepts/concepts.hpp','src/concepts/registry.cpp']},
    {key:'allowWindowsBuildEntrypointPatch', label:'Adaptar build.ps1 al target Makefile app', description:'Modifica el punto de entrada build.ps1 y añade variables del SDK. Si no se autoriza, el IDE conserva intacto ese script.', backends:['nativecpp','hui-gl','opengl-ui'], required:false, files:['build.ps1']},
    {key:'allowOpenGlRuntimeProfile', label:'OpenGL: desactivar el HUD y las capturas de mando heredadas', description:'Modifica src/app/shell.cpp y src/app/shell_render.cpp. Si no se autoriza, se conserva la política original de la plantilla.', backends:['opengl-ui'], required:false, files:['src/app/shell.cpp','src/app/shell_render.cpp']},
    {key:'allowOpenGlEuropeanAtlas', label:'OpenGL: activar atlas tipográfico europeo', description:'Modifica tools/bake-fonts.sh para solicitar un atlas mayor con caracteres europeos. Desactivado por defecto.', backends:['opengl-ui'], required:false, files:['tools/bake-fonts.sh']},
    {key:'allowVulkanTemplateIntegration', label:'Vulkan: integrar la pantalla visual en el programa de la plantilla', description:'Reemplaza el screen.cpp de la muestra seleccionada y, cuando hay imágenes, añade el cargador de texturas a la fuente del programa.', backends:['vulkan-ui'], required:true, files:['examples/<id>/kit/screen.cpp','examples/<id>/<id>.cpp']},
    {key:'allowVulkanBuildHelperRestore', label:'Vulkan: restaurar scripts auxiliares ausentes', description:'Autoriza copiar tools/ninja-build.sh y tools/build-host-tools.sh desde PS5 Native App Boilerplate a toolchains/PS5_Vulkan si realmente faltan.', backends:['vulkan-ui'], required:false, files:['toolchains/PS5_Vulkan/tools/ninja-build.sh','toolchains/PS5_Vulkan/tools/build-host-tools.sh']},
    {key:'normalizeBuildFiles', label:'Normalizar finales de línea para el build', description:'Convierte finales CRLF a LF en scripts, manifiestos, Makefiles y fuentes C/C++ del proyecto. No altera el contenido lógico y registra los hashes antes/después.', backends:['opengl-ui','vulkan-ui','nativecpp','hui-gl'], required:false, files:['Makefile, scripts, fuentes C/C++, cabeceras y manifiestos de build']},
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
  function missingForBackend(backend, value, hasCustomFont) {
    const policy = normalize(value);
    const missing = missingForPermissions(policy, requiredForBackend(backend));
    if (hasCustomFont && policy.allowCustomUnicodeFont !== true) missing.push('allowCustomUnicodeFont');
    return missing;
  }
  const api = {version:1, entries:ENTRIES.slice(), defaults, normalize, entriesForBackend, getEntry, requiredForBackend, missingForPermissions, missingForBackend};
  if (root) root.PS5HSNativeModificationPolicy = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis === 'object' ? globalThis : null);
