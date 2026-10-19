'use strict';

(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const clone = o => JSON.parse(JSON.stringify(o));
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const slug = s => String(s || 'MiHomebrew').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-zA-Z0-9_-]+/g,'-').replace(/^-+|-+$/g,'').slice(0,48) || 'MiHomebrew';
  const now = () => new Date().toLocaleTimeString('es-ES',{hour12:false});
  const px = n => Math.round(Number(n)||0);
  const clamp = (n,min,max) => Math.min(max,Math.max(min,Number(n)||0));
  const TYPES = {
    panel:{name:'Panel',icon:'▱',group:'Estructura',w:780,h:590,bg:'#182236',fg:'#e8edff',font:28,desc:'Contenedor visual para agrupar elementos.'},
    title:{name:'Título',icon:'T',group:'Texto',w:850,h:95,bg:'transparent',fg:'#f2f5ff',font:58,desc:'Texto destacado de cabecera.'},
    text:{name:'Texto',icon:'≡',group:'Texto',w:600,h:75,bg:'transparent',fg:'#aab6d0',font:29,desc:'Etiqueta informativa.'},
    button:{name:'Botón',icon:'▣',group:'Controles',w:370,h:86,bg:'#7562f7',fg:'#ffffff',font:30,desc:'Control activable con X / Intro.'},
    toggle:{name:'Interruptor',icon:'◉',group:'Controles',w:330,h:60,bg:'#222b40',fg:'#e5eaff',font:22,desc:'Valor booleano activable.'},
    slider:{name:'Deslizador',icon:'╍',group:'Controles',w:380,h:75,bg:'#202a3e',fg:'#e8edff',font:22,desc:'Valor ajustable en un intervalo.'},
    stepper:{name:'Incrementador',icon:'±',group:'Controles',w:350,h:65,bg:'#222b40',fg:'#e8edff',font:22,desc:'Entero modificable.'},
    select:{name:'Selector',icon:'⌄',group:'Controles',w:380,h:70,bg:'#222b40',fg:'#e8edff',font:22,desc:'Selector de opciones.'},
    carousel:{name:'Carrusel',icon:'◫',group:'Controles',w:500,h:110,bg:'#202a3e',fg:'#e8edff',font:24,desc:'Selección horizontal de elementos.'},
    list:{name:'Lista',icon:'☷',group:'Controles',w:440,h:250,bg:'#182236',fg:'#d9e0f4',font:20,desc:'Lista de filas seleccionables.'},
    progress:{name:'Progreso',icon:'▬',group:'Datos',w:380,h:45,bg:'#30394e',fg:'#9c8cff',font:18,desc:'Indicador de avance.'},
    badge:{name:'Insignia',icon:'●',group:'Datos',w:200,h:46,bg:'#2f3b5b',fg:'#b8adff',font:19,desc:'Etiqueta corta de estado.'},
    image:{name:'Imagen',icon:'▧',group:'Recursos',w:310,h:190,bg:'#20283a',fg:'#abb7d1',font:18,desc:'Imagen PNG/JPEG del proyecto.'},
    input:{name:'Campo de texto',icon:'▤',group:'Controles',w:370,h:64,bg:'#141b29',fg:'#d8deef',font:20,desc:'Campo para texto / teclado en pantalla.'},
    gauge:{name:'Medidor',icon:'◉',group:'Datos',w:150,h:150,bg:'#263047',fg:'#9b8bff',font:22,desc:'Medidor circular de valor.'},
    separator:{name:'Separador',icon:'━',group:'Estructura',w:620,h:3,bg:'#59627a',fg:'#59627a',font:12,desc:'Línea divisoria.'},
    card:{name:'Tarjeta',icon:'▤',group:'Estructura',w:360,h:190,bg:'#202a40',fg:'#e8edff',font:24,desc:'Tarjeta para agrupar contenido.'}
  };
  const REPO_CATALOG = [
    {id:'sharp',name:'SharpProspero',repo:'SvenGDK/SharpProspero',branch:'main',folder:'SharpProspero',role:'Backend principal',kind:'app',license:'GPL-3.0-or-later',description:'SDK C# y toolchain integral para aplicaciones nativas, interfaz de usuario, juegos, audio, red, módulos y payloads. En Windows necesita .NET 10 y WSL para el paso NativeAOT.',href:'https://github.com/SvenGDK/SharpProspero',status:'Primario'},
    {id:'ps5sdk',name:'PS5SDK',repo:'PS5Dev/PS5SDK',branch:'main',folder:'PS5SDK',role:'Payloads ELF',kind:'payload',license:'GPL-2.0',description:'Headers, CRT y toolchain C/C++ para payloads ELF y homebrew sencillo. El propio proyecto documenta que no crea aplicaciones completas de título.',href:'https://github.com/PS5Dev/PS5SDK',status:'En desarrollo'},
    {id:'payload',name:'ps5-payload-dev/sdk',repo:'ps5-payload-dev/sdk',branch:'master',folder:'ps5-payload-sdk',role:'SDK de payloads',kind:'payload',license:'GPL-3.0-or-later',description:'SDK C/C++ con enlace dinámico y herramientas prospero-clang, ejemplos y soporte para distintos cargadores ELF. En Windows la vía práctica es WSL/MSYS2 según toolchain.',href:'https://github.com/ps5-payload-dev/sdk',status:'Payload'},
    {id:'ps5link',name:'ps5link-sdk',repo:'Rufidj/ps5link-sdk',branch:'master',folder:'ps5link-sdk',role:'Títulos nativos',kind:'title',license:'GPL-3.0',description:'Enlazador C y headers para construir títulos nativos con eboot.bin, importación dinámica por NID y ejemplos de GPU/entrada. El empaquetado requiere dependencias adicionales y un libc.prx propio compatible.',href:'https://github.com/Rufidj/ps5link-sdk',status:'Nativo'},
    {id:'etahen',name:'etaHEN-Plugins',repo:'etaHEN/etaHEN-Plugins',branch:'main',folder:'etaHEN-Plugins',role:'Plugins etaHEN',kind:'plugin',license:'GPL-3.0',description:'SDK para plugins/daemons del Toolbox de etaHEN. Requiere el SDK de John Törnblom y trae ejemplos orientados a plugins; no equivale a una app de interfaz ordinaria.',href:'https://github.com/etaHEN/etaHEN-Plugins',status:'Plugin'},
    {id:'nid',name:'libNidResolver',repo:'astrelsky/libNidResolver',branch:'main',folder:'libNidResolver',role:'Dependencia etaHEN',kind:'dependency',license:'Consultar upstream',description:'Dependencia declarada como submódulo por etaHEN-Plugins; el Gestor de SDK la descarga por separado porque los ZIP de GitHub no incluyen el contenido de submódulos.',href:'https://github.com/astrelsky/libNidResolver',status:'Dependencia'}
  ];
  // Curated, source-backed PS5 projects. These are not interchangeable SDKs:
  // each entry states whether it is a foundation, a renderer, a UI kit, a driver or a reference app.
  const SOURCE_CATALOG = [
    {id:'nativecpp',name:'PS5 Native App Boilerplate',repo:'blackbearreloaded/ps5-native-app-boilerplate',role:'Fundación C/C++20 para títulos nativos',kind:'base',license:'GPL-3.0-or-later',description:'Esqueleto nativo, runtime propio reproducible, conversor ELF/FSELF, metadatos y empaquetado en carpeta. Base recomendada para proyectos C/C++ que no sean payloads.',requires:'Git; Windows, WSL o Linux; toolchain LLVM que el repo prepara bajo demanda.',ai:'Guías de agentes y contribución; no se atribuye generación por IA.',href:'https://github.com/blackbearreloaded/ps5-native-app-boilerplate'},
    {id:'opengl',name:'PS5 OpenGL 4.6',repo:'blackbearreloaded/ps5-opengl',role:'Renderer OpenGL 4.6 / GLSL 4.60',kind:'renderer',license:'GPL-3.0-or-later',description:'Pila gráfica experimental basada en Mesa/Gallium, EGL nativo, SDK estático, shader compiler, puente SDL2 y muestras (Dear ImGui, NanoVG, Sokol y otras). Se empaqueta como título nativo, no como ELF de elfldr.',requires:'Native App Boilerplate, Git, Make, WSL/Linux, Clang/LLD, CMake, Python/Meson/Ninja y más dependencias indicadas upstream.',ai:'Incluye documentación para agentes; no equivale a declaración de autoría con IA.',href:'https://github.com/blackbearreloaded/ps5-opengl'},
    {id:'hui-gl',name:'PS5 Homebrew UI (OpenGL)',repo:'blackbearreloaded/ps5-homebrew-ui',role:'Kit de interfaz nativa',kind:'ui',license:'GPL-3.0-or-later',description:'Kit de renderizado, movimiento y sonido; 99 componentes reutilizables, 21 diseños y 30 temas. Diseñado para usar con ps5-opengl y la base nativa.',requires:'Git, PS5 OpenGL y Native App Boilerplate; consulta THIRD_PARTY_NOTICES.md antes de redistribuir.',ai:'Incluye AGENTS.md, CLAUDE.md y documentación pensada para agentes de código; el repo no se etiqueta aquí como generado por IA.',href:'https://github.com/blackbearreloaded/ps5-homebrew-ui'},
    {id:'vulkan-template',name:'PS5 Vulkan Template',repo:'mihawk-99/PS5_VulkanTemplate',role:'Plantilla nativa Vulkan/RADV + generador',kind:'template',license:'MIT en la base; el módulo UI opcional es GPL-3.0-or-later',description:'La base más integrada para la vía Vulkan: generador new-title.py, capa PS5, muestras gráficas, tests y UI kit con diseños/temas. La declaración upstream informa de 16 muestras validadas en hardware; es evidencia del mantenedor, no una garantía universal.',requires:'Git con submódulos, WSL/Linux y las herramientas nativas enumeradas en BUILD.md. El propio repo obtiene dependencias con revisiones fijadas.',ai:'Incluye AGENTS.md y skills para agentes de código; no se infiere que todo el código sea generado por IA.',href:'https://github.com/mihawk-99/PS5_VulkanTemplate',generator:true},
    {id:'vulkan-radv',name:'PS5_Vulkan / RADV',repo:'mihawk-99/PS5_Vulkan',role:'Driver Vulkan basado en Mesa/RADV',kind:'driver',license:'GPL-3.0-or-later',description:'Implementación Vulkan/RADV enlazada con la capa de plataforma y el winsys para PS5. Es parte de un stack; no es una librería Vulkan universal de descarga y uso directo.',requires:'Git, SDK de payload del fork del proyecto, PS5_Mesa y resto de fuentes/herramientas fijadas por el repositorio.',ai:'Documentación de trabajo para agentes; revisar evidencia y matriz de validación upstream.',href:'https://github.com/mihawk-99/PS5_Vulkan'},
    {id:'vulkan-sdk',name:'PS5_PayloadSDK (fork RADV)',repo:'mihawk-99/PS5_PayloadSDK',role:'Dependencia de la plantilla Vulkan',kind:'dependency',license:'Consultar upstream',description:'Fork del payload SDK con la capa de plataforma que espera PS5_VulkanTemplate. El generador/build necesita una revisión fijada que exige conservar el historial Git; no es intercambiable con cualquier ps5-payload-sdk.',requires:'El IDE lo clona con historial completo al preparar un proyecto Vulkan, porque el script upstream valida un commit fijo con git cat-file. Git, WSL/Linux y resto de dependencias de Vulkan Template.',ai:'Dependencia de toolchain, no un proyecto visual independiente.',href:'https://github.com/mihawk-99/PS5_PayloadSDK'},
    {id:'vulkan-alt',name:'ps5-vulkan (implementación alternativa)',repo:'mpereiraesaa/ps5-vulkan',role:'Driver Vulkan 1.3 experimental alternativo',kind:'driver',license:'GPL-3.0-or-later',description:'Implementación experimental independiente para PS5 gfx1013 con API/formatos documentados, compilación SPIR-V y pruebas específicas. No es intercambiable con RADV; no declara un loader/ICD Vulkan general.',requires:'Git, Python, Make, compilador C y SDK/capa gráfica compañera de acuerdo con BUILDING.md.',ai:'No se infiere autoría por IA sin declaración explícita.',href:'https://github.com/mpereiraesaa/ps5-vulkan'},
    {id:'hui-vk',name:'PS5 VKHomebrewUI',repo:'mihawk-99/PS5_VKHomebrewUI',role:'Kit UI con backend Vulkan',kind:'ui',license:'GPL-3.0-or-later',description:'Fork de ps5-homebrew-ui adaptado para que el kit dibuje mediante Vulkan/RADV. PS5 Vulkan Template fija una revisión; usarlo suelto requiere respetar esa compatibilidad.',requires:'Se recomienda instalar mediante el flujo fijado de PS5 Vulkan Template, no mezclar revisiones al azar.',ai:'Incluye documentación para agentes; no se infiere generación por IA.',href:'https://github.com/mihawk-99/PS5_VKHomebrewUI'},
    {id:'prosperolight',name:'ProsperoLight',repo:'blackbearreloaded/ProsperoLight',role:'Aplicación completa de referencia',kind:'reference',license:'Consulta la licencia y THIRD_PARTY_NOTICES upstream',description:'Cliente nativo Moonlight/Sunshine con OpenGL, decodificación de vídeo, audio, entrada y una interfaz de launcher. Muy útil como referencia de arquitectura de aplicación grande.',requires:'No se trata como plantilla mínima; seguir los requisitos exactos de la revisión descargada.',ai:'Revisar AGENTS.md/CLAUDE.md si la revisión los incluye; no se etiqueta como generado por IA.',href:'https://github.com/blackbearreloaded/ProsperoLight'},
    {id:'eden',name:'ProsperoEden0',repo:'Tiang-88/ProsperoEden0',role:'Aplicación/emulador de referencia',kind:'reference',license:'Consultar licencia y avisos upstream antes de reutilizar archivos',description:'Port experimental con frontend nativo. README documenta la composición con Native App Boilerplate, OpenGL, PS5_Mesa/PS5_Vulkan y ps5-vulkan.',requires:'Proyecto voluminoso con dependencias fijadas; usar su build guide, no copiarlo como boilerplate minimalista.',ai:'El repositorio declara asistencia de herramientas de IA (OpenAI y/o Anthropic). La asistencia declarada no sustituye pruebas, revisión de licencias ni auditoría.',href:'https://github.com/Tiang-88/ProsperoEden0',aiDeclared:true},
    {id:'stremio',name:'Unofficial Stremio PS5 Port',repo:'Sp9nky/unofficial-stremio-ps5-port',role:'Aplicación multimedia de referencia',kind:'reference',license:'Revisar licencia y notices upstream',description:'Cliente Stremio con UI basada en ps5-homebrew-ui, OpenGL y el boilerplate nativo; el build script documenta la preparación de herramientas y una vista previa en PC.',requires:'Linux/WSL, Clang, ps5-payload-sdk, boilerplate y SDK OpenGL fijado.',ai:'No se etiqueta como IA generada sin declaración verificable.',href:'https://github.com/Sp9nky/unofficial-stremio-ps5-port'},
    {id:'nativehbl',name:'Nativehbl',repo:'Rufidj/Nativehbl',role:'Launcher nativo SDL2',kind:'reference',license:'Consultar licencia upstream y dependencias heredadas',description:'Launcher nativo con UI SDL2, backend de lanzamiento y recursos de tema. Referencia para input, navegación, audio y modularización; no es un SDK universal.',requires:'ps5-payload-sdk y dependencias/binaries indicados por la versión.',ai:'No se etiqueta como IA generada sin declaración verificable.',href:'https://github.com/Rufidj/Nativehbl'},
    {id:'ps5gl',name:'PS5GL · API OpenGL-shaped',repo:'Rufidj/ps5gl',role:'API de compatibilidad sobre AGC',kind:'renderer',license:'Consultar upstream',description:'API de estilo OpenGL construida sobre ps5link/ps5gpu y AGC. Tiene un subconjunto real de buffers, texturas y framebuffer, pero no compila GLSL; varias funciones están declaradas y no implementadas.',requires:'ps5link-sdk, toolchain nativo y firmware de prueba compatible. No equivale a OpenGL 4.6.',ai:'No hay declaración verificable de que sea IA generada.',href:'https://github.com/Rufidj/ps5gl'},
    {id:'opengl-mihawk',name:'PS5 OpenGL · línea alternativa',repo:'mihawk-99/ps5-opengl',role:'Renderer OpenGL 4.6 / GLSL 4.60',kind:'renderer',license:'GPL-3.0-or-later',description:'Línea alternativa de OpenGL/Mesa con ejemplos y pruebas de conformidad declaradas por upstream. Compárala con blackbearreloaded/ps5-opengl; no mezcles SDK binarios entre revisiones.',requires:'Git con submódulos y dependencias de build de su README; normalmente WSL/Linux.',ai:'Documentación preparada para agentes no demuestra que el código haya sido generado por IA.',href:'https://github.com/mihawk-99/ps5-opengl'},
    {id:'fsr4',name:'PS5 FSR4',repo:'blackbearreloaded/ps5-fsr4',role:'SDK de upscaling Vulkan compute',kind:'graphics-addon',license:'Revisar LICENSE y THIRD_PARTY_NOTICES',description:'Integración experimental de FSR 4.1.1 para homebrew nativo, con SDK, showcase, Makefiles y submódulos fijados. Requiere un perfil diagnóstico de Vulkan y respetar procedencia/licencia de componentes.',requires:'Stack Vulkan compatible, git con submódulos, toolchain nativo y fuentes upstream fijadas.',ai:'No se atribuye generación por IA sin declaración explícita.',href:'https://github.com/blackbearreloaded/ps5-fsr4'},
    {id:'helixsr',name:'PS5 HelixSR',repo:'blackbearreloaded/ps5-helixsr',role:'SDK de upscaling Vulkan compute',kind:'graphics-addon',license:'Revisar LICENSE y THIRD_PARTY_NOTICES',description:'Runtime nativo experimental para HelixSR sobre Vulkan compute. El repositorio es source-only y exige aportar localmente nvngx_dlss.dll; el IDE no descargará ese binario ni pesos propietarios.',requires:'Stack Vulkan compatible, perfil diagnóstico del driver, Git con submódulos y fichero de origen que exige upstream.',ai:'No se atribuye generación por IA sin declaración explícita.',href:'https://github.com/blackbearreloaded/ps5-helixsr'},
    {id:'sunshine',name:'PS5 Sunshine',repo:'griches/PS5_Sunshine',role:'Port nativo / referencia OpenGL',kind:'reference',license:'GPL-3.0 según el README; revisar LICENSING.md',description:'Port de Super Mario Sunshine sobre el PS5 OpenGL SDK. Es una referencia de una aplicación completa, no un boilerplate genérico; requiere que el usuario aporte su propia imagen de juego.',requires:'Native App Boilerplate, OpenGL, componentes upstream fijados y su propio dump legítimo del juego.',ai:'El README indica generación de arte gráfico en el proyecto, no que el código fuente sea generado por IA.',href:'https://github.com/griches/PS5_Sunshine'},
    {id:'switchwaker',name:'PS5 SwitchWaker',repo:'griches/PS5_SwitchWaker',role:'Port nativo / referencia WebGPU-RADV',kind:'reference',license:'GPL-3.0 según el README; revisar LICENSING.md',description:'Port de Wind Waker que usa Aurora/Dawn WebGPU y RADV en PS5. Referencia avanzada de integración gráfica, input y recursos de juego; no es un motor universal.',requires:'Stack PS5 Vulkan, toolchain nativo, dependencias fijadas y datos de juego aportados por el usuario.',ai:'No se atribuye generación por IA sin declaración verificable.',href:'https://github.com/griches/PS5_SwitchWaker'},
    {id:'dusklight',name:'PS5 Dusklight',repo:'griches/PS5_Dusklight',role:'Port de juego / referencia WebGPU-RADV',kind:'reference',license:'GPL-3.0 según el README; revisar LICENSING.md',description:'Port experimental de Dusklight sobre Aurora/Dawn WebGPU y RADV. Útil para estudiar un frontend nativo con persistencia, UI y renderer WebGPU en PS5.',requires:'Stack PS5 Vulkan, repositorios compañeros, toolchain y recursos propios del juego.',ai:'No se atribuye generación por IA sin declaración verificable.',href:'https://github.com/griches/PS5_Dusklight'},
    {id:'ghostship',name:'PS5 Ghostship · Mario 64',repo:'griches/PS5_Ghostship',role:'Port nativo / referencia Vulkan',kind:'reference',license:'GPL-3.0 según el README; revisar LICENSING.md',description:'Port de Ghostship/libultraship sobre Vulkan/RADV, con menú de ajustes, entrada DualSense, saves y recursos. Es una buena referencia de proyecto nativo grande.',requires:'Stack PS5 Vulkan y bibliotecas fijadas; el usuario debe aportar su ROM propia. No se distribuye ROM.',ai:'El README menciona arte de icono/fondo hecho con un generador de imágenes, no código generado por IA.',href:'https://github.com/griches/PS5_Ghostship'},
    {id:'porpoise',name:'Porpoise · Dolphin Emulator',repo:'elripalda/Porpoise-Dolphin-Emulator-for-PS5',role:'Emulador de referencia Vulkan',kind:'reference',license:'GPL-3.0-or-later',description:'Aplicación Dolphin para PS5 con biblioteca, carátulas, memory cards, ajustes por juego y menú in-game. Proyecto de gran tamaño, no una plantilla base.',requires:'Construcción nativa y dependencias Dolphin/libretro según BUILDING.md. No incluye juegos, BIOS ni firmware.',ai:'No se infiere generación de código por IA sin declaración explícita.',href:'https://github.com/elripalda/Porpoise-Dolphin-Emulator-for-PS5'},
    {id:'ps5x360',name:'PS5X360 · Xenia Canary',repo:'BrinooTk/PS5X360',role:'Emulador de referencia Vulkan/RADV',kind:'reference',license:'Revisar licencia/avisos upstream',description:'Integración experimental de Xenia Canary con DualSense, audio, biblioteca de juegos y RADV. Es una referencia de aplicación compleja, no un boilerplate.',requires:'Stack gráfico Vulkan de PS5, dependencias Xenia y recursos de juego propios; verificar compatibilidad de firmware en upstream.',ai:'No se infiere generación de código por IA sin declaración explícita.',href:'https://github.com/BrinooTk/PS5X360'},
    {id:'syobon',name:'Syobon Action PS5',repo:'kvaps/syobon-action-ps5',role:'Port SDL2 / referencia de adaptación',kind:'reference',license:'Revisar licencia y avisos upstream',description:'Port de Syobon Action a SDL2 empaquetado con Native App Boilerplate. Ejemplo concreto de adaptar un juego existente, entrada, sonido, recursos y pantalla al runtime nativo.',requires:'Linux/WSL, Make y el stack de Native App Boilerplate; la compilación obtiene dependencias públicas según Makefile.',ai:'No se infiere generación por IA sin declaración explícita.',href:'https://github.com/kvaps/syobon-action-ps5'},
    {id:'ps5-mesa',name:'PS5_Mesa · fuente crítica de RADV',repo:'mihawk-99/PS5_Mesa',role:'Dependencia Mesa/RADV con winsys PS5',kind:'dependency',license:'Licencias Mesa y avisos de terceros; revisar upstream',description:'Fork grande de Mesa con winsys/VideoOut y RADV adaptado a PS5. PS5_Vulkan fija una revisión de esta fuente y la compila para producir el archive enlazado por la plantilla; no es un binario precompilado.',requires:'El gestor clona el historial completo para resolver el commit exacto de tools/build-radv.sh. El build requiere WSL/Linux, Clang/LLVM, Meson, Ninja, rsync y más dependencias indicadas upstream.',ai:'AGENTS.md y skills indican soporte para agentes; no se infiere que el driver esté generado por IA.',href:'https://github.com/mihawk-99/PS5_Mesa'},
    {id:'aurora',name:'Aurora · capa de compatibilidad GameCube/Wii',repo:'encounter/aurora',role:'Motor/capa GX con backend WebGPU',kind:'renderer',license:'MIT',description:'Capa de compatibilidad de código fuente para proyectos de decompilación: SDL3, GX, Vulkan/D3D12/Metal, input, vídeo de discos, Dear ImGui y RmlUi. Los puertos PS5 que la usan añaden además una capa de plataforma.',requires:'CMake y dependencias definidas por upstream. El proyecto no es por sí mismo una distribución PS5 lista para instalar.',ai:'No se atribuye código generado por IA sin una declaración explícita.',href:'https://github.com/encounter/aurora'},
    {id:'quake3e',name:'PS5 Quake3e',repo:'griches/PS5_Quake3e',role:'Motor/port de juego Vulkan-RADV',kind:'reference',license:'GPL-3.0 según LICENSING.md; revisar componentes heredados',description:'Port del motor Quake3e con Vulkan/RADV, DualSense, audio, salida a 4K y soporte de teclado/ratón USB. Buena referencia de motor real; exige datos del juego aportados por el usuario.',requires:'PS5 Vulkan Template/RADV, toolchain nativo y datos legítimos de Quake III Arena. No es boilerplate de aplicación vacía.',ai:'No se atribuye generación de código por IA sin declaración upstream.',href:'https://github.com/griches/PS5_Quake3e'},
    {id:'retroarch',name:'PS5 RetroArch',repo:'mihawk-99/PS5_RetroArch',role:'Frontend y aplicación de emulación Vulkan',kind:'reference',license:'GPL y licencias individuales de cores; revisar notices',description:'Aplicación nativa con RetroArch, EmulationStation, WebUI y decenas de cores, sobre Vulkan/RADV. Referencia útil para arquitectura modular e interfaz compleja, no una plantilla mínima.',requires:'Stack Vulkan PS5, toolchain nativo y dependencias/core-specific; no incluye ROMs, BIOS, firmware ni claves.',ai:'No se infiere generación por IA a partir de documentación para agentes.',href:'https://github.com/mihawk-99/PS5_RetroArch'},
    {id:'x360-ai',name:'X360PS5 · prototipo asistido por IA',repo:'polarco/X360PS5',role:'Investigación experimental Xenia/Vulkan',kind:'reference',license:'GPL-3.0-or-later para código propio según README; auditar dependencias',description:'Prototipo para investigar la adaptación de Xenia a PS5, con pruebas de CPU/JIT preliminar, memoria, threading, menú y compute Vulkan en host. Su README declara que todavía no ha sido probado en PS5 ni carga juegos Xbox 360.',requires:'Entorno nativo y dependencias Xenia. Debe tratarse como investigación experimental hasta aportar evidencia en hardware.',ai:'IA declarada de forma explícita: README y docs/DESENVOLVIMENTO_IA.md documentan el uso activo de Codex en investigación, implementación y automatización. No constituye validación de los resultados.',href:'https://github.com/polarco/X360PS5',aiDeclared:true}

  ];
  const STORAGE_KEY = 'ps5-homebrew-studio-state-v1';
  const freshProject = () => ({format:'ps5vproj',formatVersion:1,name:'MiHomebrew',backend:'sharp',resolution:{width:1920,height:1080},theme:{background:'#101827',accent:'#7865f6',text:'#f0f3ff'},components:[],flows:[],assets:[],fontAssetId:'',screens:[{id:'screen-main',name:'Pantalla principal'}],currentScreen:'screen-main',settings:{titleId:'PPSA'+String(Math.floor(Math.random()*90000)+10000),firmware:'12.00',moduleKind:'app'},customCode:'',manualCode:false,updatedAt:new Date().toISOString()});
  let project = freshProject();
  let isProjectOpen = true;
  let selectedId = null, activePanel = 'components', activeView='design', activeRight='inspector', activeDock='output';
  let sdkStatus = null, isDirty = false, isPreview = false, previewSnapshot=null, showGrid=true, zoom=100, dragInfo=null, buildBusy=false;
  let undoStack=[], redoStack=[], outputLines=[], allDiagnostics=[], activeAssetId=null;
  let structureSelection=null, structureScope='auto', structureAnalysis=null;
  let isolatedLayerId=null;

  function log(text, level='INFO') {
    const line={time:now(),text:String(text),level}; outputLines.push(line); if(outputLines.length>180)outputLines=outputLines.slice(-180); renderDock();
  }
  function toast(message, kind='ok') {
    const node=document.createElement('div');node.className='toast';node.innerHTML=`<i>${kind==='error'?'!':kind==='warn'?'!':'✓'}</i><span>${esc(message)}</span>`;$('#toastHost').append(node);setTimeout(()=>node.remove(),4200);
  }
  async function api(path, body) {
    const options=body===undefined?{method:'GET'}:{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)};
    const res=await fetch(path.startsWith('/')?path:`/api/${path}`,options);
    const type=res.headers.get('content-type')||'';
    const data=type.includes('json')?await res.json():await res.text();
    if(!res.ok)throw new Error(data?.error||data?.message||String(data));
    return data;
  }
  function snapshot() { undoStack.push(JSON.stringify(project)); if(undoStack.length>50)undoStack.shift(); redoStack=[]; }
  function changed(message='Cambios pendientes') { isDirty=true; project.updatedAt=new Date().toISOString();$('#dirtyPill').textContent='SIN GUARDAR';$('#dirtyPill').classList.remove('saved');$('#canvasState').textContent=message; refreshCodeIfGenerated(); scheduleAnalysis(); }
  function savedState(){isDirty=false;$('#dirtyPill').textContent=isProjectOpen?'GUARDADO':'SIN PROYECTO';$('#dirtyPill').classList.add('saved');}
  function setProjectOpenState(open){
    isProjectOpen=!!open;
    ['saveProjectBtn','exportProjectBtn','buildBtn'].forEach(id=>{const button=$('#'+id);if(button)button.disabled=!isProjectOpen;});
    const closeButton=$('#closeProjectBtn');if(closeButton)closeButton.disabled=!isProjectOpen;
    const pill=$('#dirtyPill');if(pill&&!isProjectOpen){pill.textContent='SIN PROYECTO';pill.classList.add('saved');}
  }
  function refreshCodeIfGenerated(){if(!project.manualCode&&activeView==='code')renderCode();}
  function selectComponent(id){selectedId=id;renderCanvas();renderInspector();renderHierarchy();$('#selectionPosition').textContent=id?(component(id)?.label||component(id)?.id||'Elemento')+' · '+(component(id)?.x||0)+', '+(component(id)?.y||0):'Sin selección';}
  function component(id){return project.components.find(c=>c.id===id);}
  function screenComponents(){return project.components.filter(c=>c.screenId===(project.currentScreen||'screen-main'));}
  function makeComponent(type,x,y){
    const spec=TYPES[type]||TYPES.button, list=screenComponents();
    const ww=spec.w,hh=spec.h;let cx=x??Math.round((1920-ww)/2),cy=y??Math.round(120+list.length*100);
    cx=clamp(cx,0,1920-ww);cy=clamp(cy,0,1080-hh);
    const nextZ=window.PS5HSLayers&&typeof window.PS5HSLayers.nextZIndexForNewComponent==='function'?window.PS5HSLayers.nextZIndexForNewComponent(list,type):list.reduce((max,item)=>Math.max(max,Number(item.zIndex)||0),0)+10;
    const c={id:`${type}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2,5)}`,screenId:project.currentScreen||'screen-main',type,zIndex:nextZ,label:({title:'Título de pantalla',text:'Texto informativo',button:'Botón nuevo',toggle:'Activar opción',slider:'Volumen',stepper:'Cantidad',select:'Dificultad',carousel:'Selecciona una opción',list:'Elementos',progress:'Progreso',badge:'Estado',image:'Imagen',input:'Introduce texto',gauge:'75%',separator:'',panel:'Panel principal',card:'Tarjeta'})[type]||spec.name,x:cx,y:cy,w:ww,h:hh,bg:spec.bg,fg:spec.fg,font:spec.font,visible:true,opacity:100,value:type==='slider'?70:type==='progress'?65:type==='gauge'?75:type==='stepper'?3:0,min:0,max:100,step:5,checked:type==='toggle',items:['Opción 1','Opción 2','Opción 3'],assetId:null,action:'none',actionMessage:'Acción completada',targetId:'',custom:{}};
    snapshot();project.components.push(c);changed('Componente añadido');selectComponent(c.id);return c;
  }
  function setActiveView(view){activeView=view;$$('.editor-tab').forEach(el=>el.classList.toggle('active',el.dataset.view===view));['design','structure','logic','code','diagnostics'].forEach(v=>$('#'+v+'View').classList.toggle('hidden',v!==view));if(view==='structure')renderStructure();if(view==='logic')renderFlows();if(view==='code')renderCode();if(view==='diagnostics')renderDiagnostics();}
  function setActivePanel(panel){activePanel=panel;$$('.rail-item').forEach(el=>el.classList.toggle('active',el.dataset.panel===panel));renderSidePanel();}
  function setRightPane(pane){activeRight=pane;$$('.right-tab').forEach(el=>el.classList.toggle('active',el.dataset.right===pane));$('#inspectorPane').classList.toggle('hidden',pane!=='inspector');$('#hierarchyPane').classList.toggle('hidden',pane!=='hierarchy');if(pane==='hierarchy')renderHierarchy();else renderInspector();}
  function setDock(dock){activeDock=dock;$$('.dock-tab').forEach(el=>el.classList.toggle('active',el.dataset.dock===dock));renderDock();}

  function renderSidePanel(){
    const titles={components:['Componentes','Arrastra elementos al lienzo','UI'],logic:['Lógica visual','Eventos y comportamientos','FLOW'],systems:['Subsistemas','Capacidades del entorno','API'],assets:['Recursos','Archivos del proyecto','ASSET'],sdk:['SDK y toolchains','Backends comunitarios','SDK'],templates:['Proyectos y motores','Repositorios reales de PS5','SRC'],docs:['Documentación técnica','Capacidades y límites','REF']};
    const t=titles[activePanel];$('#panelTitle').textContent=t[0];$('#panelSubtitle').textContent=t[1];$('#panelKicker').textContent=t[2];
    const root=$('#panelContent');root.innerHTML='';
    if(activePanel==='components'){
      const search=document.createElement('div');search.className='search-wrap';search.innerHTML='<input id="componentSearch" placeholder="Buscar componentes…" autocomplete="off">';root.append(search);
      const grid=document.createElement('div');grid.id='componentPalette';root.append(grid);drawComponentPalette('');
      $('#componentSearch').addEventListener('input',e=>drawComponentPalette(e.target.value));
      const note=document.createElement('div');note.className='panel-info';note.innerHTML='<strong>Atajos</strong><br>• Arrastrar o pulsar para añadir<br>• <span class="mini-kbd">Supr</span> borrar selección<br>• <span class="mini-kbd">Ctrl + S</span> guardar proyecto<br>• Flechas mover elemento 1 px';root.append(note);
    }else if(activePanel==='logic'){
      root.innerHTML=`<div class="system-tile"><strong>Flujos del proyecto</strong><p>Define qué ocurre al activar un control o cambiar un valor. Los flujos se guardan en el modelo y se convierten en acciones del runtime cuando el backend admite la operación.</p><button id="sideAddFlow" class="btn primary small" style="margin-top:10px">＋ Crear flujo</button></div><div class="system-tile"><strong>Eventos disponibles</strong><p>Activar · Valor cambiado · Inicio de pantalla · Acción completada</p></div><div class="system-tile"><strong>Acciones comunes</strong><p>Mostrar notificación · Cambiar texto · Mostrar/ocultar · Cambiar valor · Navegar pantalla</p></div>`;
      $('#sideAddFlow').onclick=()=>{setActiveView('logic');addFlow();};
    }else if(activePanel==='systems'){
      root.innerHTML=`<div class="system-tile"><strong>Gráficos y renderizado</strong><p>Surface 2D, UI toolkit, GPU/AGC y shaders cuando estén soportados por el backend.</p><div class="state">SHARPPROSPERO · PS5LINK · PS5SDK (SEGÚN API)</div></div><div class="system-tile"><strong>Entrada y DualSense</strong><p>Navegación por D-pad, X/O, sticks, sensores y háptica según bindings del SDK.</p><div class="state">SHARPPROSPERO UI / INPUT</div></div><div class="system-tile"><strong>Audio y multimedia</strong><p>Reproducción, mezcla/síntesis y decodificación disponibles según backend y runtime.</p><div class="state">SHARPPROSPERO</div></div><div class="system-tile"><strong>Datos y almacenamiento</strong><p>Archivos, JSON, configuración, save data y ficheros empaquetados sujetos a permisos del entorno.</p><div class="state">DEPENDIENTE DEL SDK</div></div><div class="system-tile"><strong>Red y servicios</strong><p>Sockets, HTTP/servidores y servicios de sistema. Algunas API son específicas de firmware.</p><div class="state">API Y FIRMWARE</div></div><div class="panel-info">Los nombres de subsistemas representan capacidades documentadas de los backends, no garantías de compatibilidad universal de firmware.</div>`;
    }else if(activePanel==='assets'){
      root.innerHTML=`<button id="addAssetBtn" class="btn secondary" style="width:100%">＋ Importar recurso</button><div class="section-note">PNG/JPEG, audio, JSON y archivos binarios. Las imágenes se previsualizan en el lienzo y se conservan al exportar el proyecto.</div><div id="assetList" class="asset-list" style="margin-top:13px"></div><div class="panel-info">En un backend nativo, cada recurso necesita estar copiado en el paquete y cargarse mediante la API correspondiente.</div>`;
      $('#addAssetBtn').onclick=()=>$('#assetFileInput').click();renderAssetList();
    }else if(activePanel==='sdk'){
      root.innerHTML=`<div class="panel-info" style="margin-top:0;margin-bottom:12px">Descarga los repositorios oficiales desde GitHub y conserva cada toolchain por separado. No se fusionan ABI ni sistemas de empaquetado incompatibles.</div><button id="installAllSdks" class="btn primary" style="width:100%;margin-bottom:10px">⬇ Descargar todos los SDK</button><button id="refreshSdkState" class="btn secondary" style="width:100%">⟳ Verificar entorno</button><div id="sdkSideStatus" style="margin-top:13px"></div>`;
      $('#installAllSdks').onclick=()=>installSdks(REPO_CATALOG.map(x=>x.id));$('#refreshSdkState').onclick=refreshStatus;renderSdkSideStatus();
    }else if(activePanel==='templates'){
      root.innerHTML=`<div class="panel-info" style="margin-top:0"><strong>Fuentes reales, no mockups.</strong><br>Clona repositorios originales conservando el árbol Git y los submódulos. Distingue las bases para crear títulos, los drivers y los programas de referencia. Los asistentes upstream crean proyectos nativos independientes; el destino Native UI también transpila el modelo visual a C++20 para los kits OpenGL y Vulkan.</div><div class="search-wrap"><input id="sourceSearch" placeholder="Buscar OpenGL, Vulkan, boilerplate…" autocomplete="off"></div><div class="source-filters"><button class="source-filter active" data-source-filter="all">Todos</button><button class="source-filter" data-source-filter="base">Bases</button><button class="source-filter" data-source-filter="renderer">Gráficos</button><button class="source-filter" data-source-filter="ui">UI</button><button class="source-filter" data-source-filter="driver">Drivers</button><button class="source-filter" data-source-filter="dependency">Dependencias</button><button class="source-filter" data-source-filter="template">Generadores</button><button class="source-filter" data-source-filter="graphics-addon">Gráficos extra</button><button class="source-filter" data-source-filter="reference">Referencias</button><button class="source-filter" data-source-filter="ai">IA declarada</button></div><div id="sourceCatalog" class="source-catalog"></div><div class="panel-info">Instalar significa clonar la fuente original; los repositorios con submódulos se clonan recursivamente. La etiqueta IA se limita a declaraciones explícitas del proyecto, no a AGENTS.md/CLAUDE.md. No instala automáticamente todos los toolchains de Linux/WSL ni redistribuye archivos de Sony. Revisa licencias, dependencias fijadas, compatibilidad de firmware y tests antes de reutilizar código.</div>`;
      renderSourceCatalog('');
      $('#sourceSearch').addEventListener('input',e=>renderSourceCatalog(e.target.value));
      $$('.source-filter').forEach(b=>b.onclick=()=>{$$('.source-filter').forEach(x=>x.classList.toggle('active',x===b));renderSourceCatalog($('#sourceSearch').value,b.dataset.sourceFilter);});
      $('#sourceCatalog').addEventListener('click',async e=>{const nativeBuild=e.target.closest('[data-native-build]');if(nativeBuild){let savedMods={};try{savedMods=JSON.parse(nativeBuild.dataset.nativeModifications||'{}');}catch{}buildNativeProject(nativeBuild.dataset.nativeBuild,nativeBuild.dataset.nativeTitleId||'',nativeBuild.dataset.nativeName||'',nativeBuild.dataset.nativeNeedsInit==='true',nativeBuild.dataset.nativeSupportsClean==='true',nativeBuild.dataset.nativeTemplate||'',nativeBuild.dataset.nativeGeneratedFromStudio==='true',savedMods);return;}if(e.target.closest('[data-refresh-native-projects]')){renderNativeProjects();return;}const install=e.target.closest('[data-source-install]');if(install){installSdks([install.dataset.sourceInstall]);return;}const create=e.target.closest('[data-source-create]');if(create){if(create.dataset.sourceCreate==='vulkan-template')openVulkanTemplateCreate();else openNativeBoilerplateCreate(create.dataset.sourceCreate);return;}const open=e.target.closest('[data-source-open]');if(open){window.open(open.dataset.sourceOpen,'_blank','noopener,noreferrer');}});
    }else if(activePanel==='docs'){
      root.innerHTML=`<div class="system-tile"><strong>SharpProspero</strong><p>Aplicaciones nativas, payloads, bibliotecas y toolkit visual C#. Requiere .NET 10 y WSL en Windows.</p><a class="repo-link" href="https://github.com/SvenGDK/SharpProspero" target="_blank" rel="noreferrer">Repositorio y documentación ↗</a></div><div class="system-tile"><strong>PS5SDK</strong><p>Headers/CRT y payloads ELF; upstream indica que no construye títulos completos.</p><a class="repo-link" href="https://github.com/PS5Dev/PS5SDK" target="_blank" rel="noreferrer">Repositorio ↗</a></div><div class="system-tile"><strong>ps5link-sdk</strong><p>Enlazador nativo de títulos y examples de gráficos/entrada, necesita prospero-clang.</p><a class="repo-link" href="https://github.com/Rufidj/ps5link-sdk" target="_blank" rel="noreferrer">Repositorio ↗</a></div><div class="system-tile"><strong>etaHEN-Plugins</strong><p>SDK para plugins y daemons cargados por etaHEN; requiere Johns SDK.</p><a class="repo-link" href="https://github.com/etaHEN/etaHEN-Plugins" target="_blank" rel="noreferrer">Repositorio ↗</a></div><div class="panel-info">Consulta <a class="repo-link" href="/docs/SDK_MATRIX.md" target="_blank" rel="noreferrer">Matriz de SDKs ↗</a> y <a class="repo-link" href="/docs/PROJECT_ECOSYSTEM.md" target="_blank" rel="noreferrer">Estudio de proyectos, UI, OpenGL, Vulkan e IA ↗</a>.</div>`;
    }
  }
  function renderSourceCatalog(filter='',category='all'){
    const root=$('#sourceCatalog');if(!root)return;
    const q=String(filter||'').toLowerCase();
    const status=(id)=>sdkStatus?.sdks?.find(x=>x.id===id);
    const items=SOURCE_CATALOG.filter(x=>(category==='all'||(category==='ai'?!!x.aiDeclared:x.kind===category))&&(x.name+' '+x.repo+' '+x.role+' '+x.description+' '+x.kind+' '+x.license+' '+(x.ai||'')).toLowerCase().includes(q));
    const cards=items.map(x=>{
      const st=status(x.id);const installed=!!st?.installed;
      const kindLabel=({base:'BASE',renderer:'RENDERER',ui:'UI KIT',template:'GENERADOR',driver:'DRIVER',dependency:'DEPENDENCIA',reference:'REFERENCIA','graphics-addon':'GRÁFICOS EXTRA'})[x.kind]||x.kind.toUpperCase();
      const canCreate=!!x.generator||x.id==='nativecpp'||x.id==='hui-gl';const action=canCreate?`<button class="btn primary small" data-source-create="${esc(x.id)}">${x.id==='vulkan-template'?'Crear título Vulkan':x.id==='hui-gl'?'Crear app UI OpenGL':'Crear base C++'}</button>`:'';
      const state=installed?'<span class="source-state installed">CLONADO</span>':'<span class="source-state">NO CLONADO</span>';
      const ai=x.aiDeclared?'<span class="source-ai declared">IA declarada</span>':x.ai&&/documentación para agentes|documentación de trabajo para agentes|AGENTS\.md|CLAUDE\.md/i.test(x.ai)?'<span class="source-ai">Guías para agentes</span>':'';
      const buildNote=({nativecpp:'Perfil de título nativo C/C++: Makefile + inicializador upstream.',opengl:'SDK/renderer; debe compilarse como dependencia antes de usar una UI OpenGL.', 'hui-gl':'Aplicación UI OpenGL: necesita Native App Boilerplate y el SDK OpenGL compilado.', 'vulkan-template':'Plantilla generadora: primero crea un título y prepara PS5_Vulkan, PS5_PayloadSDK y PS5_Mesa.', 'vulkan-radv':'Dependencia del stack Vulkan/RADV; no es un título independiente.', 'vulkan-sdk':'Dependencia de SDK; requiere la revisión fijada por la plantilla Vulkan.', 'ps5-mesa':'Dependencia Mesa/RADV compilada desde una revisión upstream compatible.', 'hui-vk':'Kit UI Vulkan; requiere la plantilla y la revisión RADV compatibles.'})[x.id]||(['renderer','driver','dependency','graphics-addon'].includes(x.kind)?'Componente de toolchain o renderer; no se compila como título genérico.':'Proyecto de referencia: consulta su build guide y dependencias upstream; el IDE no supone que un make genérico produzca un título PS5.');
      return '<article class="source-card"><div class="source-card-top"><span class="source-kind">'+esc(kindLabel)+'</span>'+state+'</div><h3>'+esc(x.name)+'</h3><div class="source-repo">'+esc(x.repo)+'</div><p>'+esc(x.description)+'</p><p class="source-profile-note">'+esc(buildNote)+'</p><div class="source-tags"><span>'+esc(x.license)+'</span>'+ai+'</div><details><summary>Requisitos y uso</summary><p>'+esc(x.requires)+'</p><p><strong>Nota de procedencia:</strong> '+esc(x.ai)+'</p></details><div class="source-card-actions"><button class="btn '+(installed?'secondary':'primary')+' small" data-source-install="'+esc(x.id)+'">'+(installed?'Ver fuente instalada':'Clonar desde GitHub')+'</button>'+action+'<button class="btn ghost small" data-source-open="'+esc(x.href)+'">GitHub ↗</button></div></article>';
    }).join('');
    root.innerHTML=(cards||'<div class="empty-screen">No hay repositorios que coincidan con esa búsqueda.</div>')+
      `<section class="native-projects-panel"><div class="native-projects-head"><div><strong>PROYECTOS NATIVOS Y UPSTREAM DETECTADOS</strong><p>Proyectos y checkouts detectados en el workspace. El perfil identifica el tipo, las dependencias y si hay una receta de título compatible; los repositorios de referencia no se compilan con un make genérico.</p></div><button class="btn secondary small" data-refresh-native-projects>Actualizar</button></div><div id="nativeProjectList"><div class="empty-screen">Consultando el espacio de trabajo de Windows…</div></div></section>`;
    renderNativeProjects();
  }

  async function renderNativeProjects(){
    const root=$('#nativeProjectList');if(!root)return;
    try{
      const result=await api('native-projects'),projects=result.projects||[];
      if(!projects.length){root.innerHTML='<div class="empty-screen">No se han detectado proyectos nativos o repositorios upstream en el workspace. Clona una fuente desde el catálogo o crea una base C++, una app UI OpenGL o un título Vulkan.</div>';return;}
      root.innerHTML=projects.map(p=>{
        const template=String(p.templateId||'');
        const upstream=template==='vulkan-template'?'https://github.com/mihawk-99/PS5_VulkanTemplate':template==='hui-gl'?'https://github.com/blackbearreloaded/ps5-homebrew-ui':template==='nativecpp'?'https://github.com/blackbearreloaded/ps5-native-app-boilerplate':p.repository?'https://github.com/'+p.repository:'https://github.com';
        const missing=Array.isArray(p.missingDependencies)?p.missingDependencies:[];
        const missingBlock=missing.length?'<span class="native-dependency-warning">Dependencias pendientes: '+esc(missing.join(', '))+'</span>':'';
        const reason=p.buildReason?'<p class="native-project-reason">'+esc(p.buildReason)+'</p>':'';
        const buildLabel=p.needsInit?'Inicializar y compilar':'Compilar';
        const disabled=p.buildable?'':' disabled title="'+esc(p.buildReason||'No hay un perfil de título compatible')+'"';
        return '<article class="native-project-card"><div class="native-project-main"><strong>'+esc(p.name||p.titleId||'Proyecto upstream')+'</strong><span class="native-project-meta">'+esc(p.typeLabel||p.visualBackend||template||'Proyecto detectado')+' · '+esc(p.buildSystem||'Build upstream')+' · '+esc(p.titleId||'sin TITLE_ID')+(p.design?' · diseño '+esc(p.design):'')+(p.generatedFromStudio?' · canvas → C++20':'')+'</span><code title="Ruta del proyecto">'+esc(p.path||'')+'</code>'+missingBlock+reason+(p.built?'<span class="native-build-state success">Título detectado: '+esc(p.artifact)+'</span>':'<span class="native-build-state pending">Título todavía sin artefacto validado</span>')+'</div><div class="native-project-actions"><button class="btn primary small" data-native-build="'+esc(p.path||'')+'" data-native-title-id="'+esc(p.titleId||'')+'" data-native-name="'+esc(p.name||'')+'" data-native-needs-init="'+String(!!p.needsInit)+'" data-native-supports-clean="'+String(!!p.supportsClean)+'" data-native-template="'+esc(template)+'" data-native-generated-from-studio="'+String(!!p.generatedFromStudio)+'" data-native-modifications="'+esc(JSON.stringify(p.nativeModifications||{}))+'"'+disabled+'>'+buildLabel+'</button><button class="btn ghost small" data-source-open="'+esc(upstream)+'">Upstream ↗</button></div></article>';
      }).join('');
      root.querySelectorAll('.native-project-card').forEach((card,index)=>{
        const p=projects[index]||{},actions=card.querySelector('.native-project-actions');if(!actions)return;
        const pack=document.createElement('button');pack.className='btn secondary small';pack.textContent='Empaquetar';pack.disabled=!p.built;pack.dataset.nativePackage=p.path||'';pack.title=p.built?'Crear ffpfs, ffpfsc o pkg con PS5 UltraPack':'Compila y verifica el título antes de empaquetarlo';
        const presentation=document.createElement('button');presentation.className='btn ghost small';presentation.textContent='Presentación';presentation.disabled=!p.presentation?.editable;presentation.title=presentation.disabled?'Inicializa primero el título y genera sce_sys/param.json':'Cambiar icono, fondo y música de presentación';presentation.onclick=()=>openNativePresentationEditor(p);actions.insertBefore(presentation,actions.children[1]||null);
        actions.insertBefore(pack,actions.children[1]||null);pack.onclick=()=>packageNativeWithUltraPack(pack.dataset.nativePackage);
      });
    }catch(e){root.innerHTML='<div class="empty-screen">No se pudo consultar el workspace de Windows: '+esc(e.message)+'. El servicio local debe estar ejecutándose.</div>';}
  }


  function presentationStatusRows(state){
    const entries=[['Icono de inicio','icon'],['Fondo al seleccionar','selectionBackground'],['Fondo de lanzamiento','launchBackground'],['Música al seleccionar','music']];
    return entries.map(([label,key])=>'<div class="presentation-file-status '+(state?.[key]?'present':'missing')+'"><span>'+esc(label)+'</span><b>'+(state?.[key]?'Detectado':'No instalado')+'</b></div>').join('');
  }
  function presentationToolRows(state){
    const entries=[['Conversor de recursos upstream','conversionScript'],['DirectXTex texconv','texconv'],['FFmpeg (solo si conviertes audio)','ffmpeg'],['ATRAC9 ps4_at9tool (solo audio comprimido)','at9Encoder']];
    return entries.map(([label,key])=>'<div class="presentation-tool-status '+(state?.[key]?'present':'missing')+'"><span>'+esc(label)+'</span><b>'+(state?.[key]?'Detectado':'Pendiente')+'</b></div>').join('');
  }
  function encodePresentationFile(file){
    return new Promise((resolve,reject)=>{const reader=new FileReader();reader.onerror=()=>reject(new Error('No se pudo leer '+file.name));reader.onload=()=>{const value=String(reader.result||''),comma=value.indexOf(',');if(comma<0){reject(new Error('Formato de lectura inesperado para '+file.name));return;}resolve({name:file.name,type:file.type||'',data:value.slice(comma+1)});};reader.readAsDataURL(file);});
  }
  async function openNativePresentationEditor(nativeProject){
    const state=nativeProject.presentation||{};
    const body='<p>Modifica los recursos <code>sce_sys</code> que aparecen en la tarjeta de esta aplicación en PS5. Puedes cambiar una o varias cosas; los campos vacíos se conservan.</p>'+
      '<div class="presentation-status-grid">'+presentationStatusRows(state)+'</div>'+
      '<div class="form-field"><label>Icono de la aplicación · PNG/JPEG/BMP/TIFF</label><input id="presentationIconFile" type="file" accept=".png,.jpg,.jpeg,.bmp,.tif,.tiff,.dds"><small>Se convierte a <code>icon0.png</code> de 512×512.</small></div>'+
      '<div class="form-field"><label>Fondo al seleccionar la app · imagen</label><input id="presentationSelectionFile" type="file" accept=".png,.jpg,.jpeg,.bmp,.tif,.tiff,.dds"><small>Genera <code>pic0.dds</code>, 3840×2160 BC7. Si aún no existe el par de fondos, selecciona también el de lanzamiento.</small></div>'+
      '<div class="form-field"><label>Fondo durante el lanzamiento · imagen</label><input id="presentationLaunchFile" type="file" accept=".png,.jpg,.jpeg,.bmp,.tif,.tiff,.dds"><small>Genera <code>pic1.dds</code>, 3840×2160 BC7. Puede ser diferente del fondo de selección.</small></div>'+
      '<div class="form-field"><label>Música al seleccionar la app · AT9/MP3/WAV/OGG/M4A/AAC/FLAC</label><input id="presentationAudioFile" type="file" accept=".at9,.mp3,.wav,.ogg,.m4a,.aac,.flac,audio/*"><small>El resultado es <code>snd0.at9</code> (ATRAC9, 48 kHz, en bucle y máximo 2 MiB). La conversión de audio convencional necesita FFmpeg y un codificador ATRAC9 compatible.</small></div>'+
      '<div class="presentation-section-title">Herramientas detectadas</div><div class="presentation-tool-grid">'+presentationToolRows(state)+'</div>'+
      '<p class="section-note">La conversión de imágenes necesita DirectXTex texconv. Se acepta un archivo AT9 ya codificado sin instalar el codificador. Los fondos y la música de aquí son específicos de esta app; no cambian el tema global ni el sonido de encendido de la consola.</p>'+
      '<section class="native-modification-policy"><h3>Permiso para esta operación</h3><p>El cambio ejecuta la herramienta local/upstream <code>tools/prepare-assets.ps1</code> y sustituye exclusivamente los archivos de presentación elegidos. El servidor verificará el permiso y registrará hashes SHA-256 antes/después.</p><label class="native-change-row" for="presentationAllowUpstreamTools"><input id="presentationAllowUpstreamTools" type="checkbox"><span><strong>Autorizar herramientas upstream de conversión · requerido</strong><small>Sin este permiso no se ejecutará el conversor ni se escribirá en sce_sys/.</small></span></label></section>'+
      '<pre id="presentationAssetOutput" class="presentation-output">Esperando archivos. No se ha modificado ningún recurso.</pre>';
    openModal('Presentación · '+(nativeProject.name||nativeProject.titleId||'Título nativo'),body,[
      {text:'Cerrar',class:'ghost',action:closeModal},
      {text:'Aplicar cambios',class:'primary',action:async()=>{
        const iconFile=$('#presentationIconFile')?.files?.[0]||null,selectionFile=$('#presentationSelectionFile')?.files?.[0]||null,launchFile=$('#presentationLaunchFile')?.files?.[0]||null,audioFile=$('#presentationAudioFile')?.files?.[0]||null;
        if(!iconFile&&!selectionFile&&!launchFile&&!audioFile){toast('Selecciona al menos un recurso.','warn');return;}
        if(!$('#presentationAllowUpstreamTools')?.checked){toast('Autoriza expresamente las herramientas upstream para convertir los recursos. No se ha modificado nada.','warn');return;}
        if(!state.icon&&!iconFile){toast('Este título aún no tiene icono. Selecciona uno antes de cambiar los fondos o la música.','warn');return;}
        if((!state.selectionBackground||!state.launchBackground)&&((selectionFile&&!launchFile)||(!selectionFile&&launchFile))){toast('Este título aún no tiene ambos fondos. Selecciona los dos para crear pic0.dds y pic1.dds.','warn');return;}
        const max={icon:10*1024*1024,selection:24*1024*1024,launch:24*1024*1024,audio:24*1024*1024};
        for(const [file,label,limit] of [[iconFile,'Icono',max.icon],[selectionFile,'Fondo de selección',max.selection],[launchFile,'Fondo de lanzamiento',max.launch],[audioFile,'Audio',max.audio]]){if(file&&file.size>limit){toast(label+' supera el máximo de '+Math.round(limit/1024/1024)+' MiB.','error');return;}}
        const buttons=$$('#modalActions button');buttons.forEach(button=>button.disabled=true);
        const output=$('#presentationAssetOutput');if(output)output.textContent='Preparando recursos en una carpeta temporal y validando formatos…';
        try{
          const payload={path:nativeProject.path,nativeModifications:window.PS5HSNativeModificationPolicy.normalize({allowExecuteUpstreamAssetTools:$('#presentationAllowUpstreamTools')?.checked===true})};
          if(iconFile)payload.icon=await encodePresentationFile(iconFile);
          if(selectionFile)payload.selectionBackground=await encodePresentationFile(selectionFile);
          if(launchFile)payload.launchBackground=await encodePresentationFile(launchFile);
          if(audioFile)payload.audio=await encodePresentationFile(audioFile);
          const result=await api('native-presentation-assets',payload);
          if(output)output.textContent=(result.message||'Recursos actualizados.')+(result.output?'\n\n'+result.output:'');
          log(result.message||'Presentación actualizada.','INFO');toast('Presentación de la app actualizada');
          closeModal();await renderNativeProjects();
        }catch(error){if(output)output.textContent='No se aplicaron los cambios.\n'+error.message;toast('No se pudo cambiar la presentación: '+error.message,'error');buttons.forEach(button=>button.disabled=false);}
      }}
    ]);
  }

  async function openIntegrationSettings(){
    let config={};try{config=await api('integrations');}catch(e){toast('No se pudo leer la configuración: '+e.message,'error');return;}
    const ready=flag=>flag?'<span style="color:var(--green)">Detectado</span>':'<span style="color:var(--yellow)">Pendiente</span>';
    const body='<p>Configura las herramientas locales de empaquetado. Las rutas se guardan en <code>.runtime/integrations.json</code>.</p>'+
      '<div class="form-field"><label>Ejecutable de Python 3.10 o posterior</label><input id="integrationPythonPath" spellcheck="false" value="'+esc(config.pythonExe||'')+'" placeholder="python.exe o C:\\\\Python311\\\\python.exe"></div>'+
      '<div class="form-field"><label>PS5 UltraPack · archivo backend\\\\cli.py</label><input id="integrationUltraPackPath" spellcheck="false" value="'+esc(config.ultraPackCli||'')+'" placeholder="D:\\\\ps5-ultrapack\\\\backend\\\\cli.py"></div>'+
      '<div class="system-tile"><strong>Estado detectado</strong><p>Python: '+ready(config.pythonReady)+' · UltraPack CLI: '+ready(config.ultraPackReady)+'</p><p><a class="repo-link" href="https://github.com/knutwurst/ps5-ultrapack" target="_blank" rel="noreferrer">Repositorio PS5 UltraPack ↗</a></p></div>'+
      '<p>El empaquetado .ffpfs/.ffpfsc depende de las bibliotecas Python upstream. La creación de .pkg en Windows requiere el helper nativo de fPKG y sus dependencias.</p>';
    openModal('Herramientas de empaquetado · PS5 UltraPack',body,[
      {text:'Cerrar',class:'ghost',action:closeModal},
      {text:'Descargar UltraPack (fuente)',class:'secondary',action:async()=>{
        const button=$$('#modalActions button').find(x=>x.textContent==='Descargar UltraPack (fuente)');if(button)button.disabled=true;
        try{const result=await api('sdk-install',{ids:['ps5-ultrapack']});const item=(result.results||[]).find(x=>x.name==='PS5 UltraPack'||x.path);
          if(!item||!item.ok||!item.path)throw new Error(item?.message||result.message||'La descarga no terminó correctamente.');
          const cli=item.cli||item.path+'\\\\backend\\\\cli.py',python=item.pythonExe||$('#integrationPythonPath').value.trim();
          const saved=await api('integration-config',{pythonExe:python,ultraPackCli:cli});
          log('UltraPack descargado como código fuente: '+item.path,'INFO');toast(saved.message||'UltraPack preparado');closeModal();await openIntegrationSettings();
        }catch(e){toast('No se pudo preparar UltraPack: '+e.message,'error');if(button)button.disabled=false;}
      }},
      {text:'Guardar configuración',class:'primary',action:async()=>{
        const data={pythonExe:$('#integrationPythonPath').value.trim(),ultraPackCli:$('#integrationUltraPackPath').value.trim()};
        try{const result=await api('integration-config',data);closeModal();log(result.message||'Configuración guardada.','INFO');toast('Configuración de empaquetado guardada');await renderNativeProjects();}
        catch(e){toast('No se pudo guardar la configuración: '+e.message,'error');}
      }}
    ]);
  }

  async function packageNativeWithUltraPack(path){
    if(!path){toast('La ruta del proyecto está vacía.','error');return;}
    const body='<p>Se validará que el título incluya <code>eboot.bin</code> y <code>sce_sys/param.json</code>. El resultado se guardará dentro de <code>packages-ultrapack</code> en la carpeta del proyecto.</p>'+
      '<div class="form-field"><label>Formato de salida</label><select id="ultraPackFormat" class="compact-select" style="width:100%"><option value="ffpfsc">.ffpfsc · PFS comprimido</option><option value="ffpfs">.ffpfs · PFS sin comprimir</option><option value="pkg">.pkg · fPKG (requiere helper Windows)</option></select></div>'+
      '<pre id="ultraPackOutput" style="font:10px/1.55 Consolas,monospace;white-space:pre-wrap;word-break:break-word;max-height:40vh;overflow:auto">Preparado. Selecciona el formato y pulsa «Empaquetar» para iniciar la tarea. Si falta Python o backend\\cli.py, se mostrará el requisito pendiente.</pre>';
    openModal('Empaquetar con PS5 UltraPack',body,[
      {text:'Cerrar',class:'ghost',action:closeModal},
      {text:'Empaquetar',class:'primary',action:async()=>{
        const format=$('#ultraPackFormat').value,buttons=$$('#modalActions button');buttons.forEach(b=>b.disabled=true);log(`Solicitud UltraPack: ${format} · ${path}`,'INFO');
        const box=$('#ultraPackOutput');if(box)box.textContent='Preparando el empaquetado '+format+'…';
        try{
          const startedJob=await api('package-ultrapack/start',{path,format});
          if(!startedJob.ok||!startedJob.jobId)throw new Error(startedJob.message||'No se pudo iniciar el trabajo de empaquetado.');if(box)box.textContent=`Tarea iniciada (${startedJob.jobId}). Recibiendo salida del backend…`;log('Tarea UltraPack iniciada: '+startedJob.jobId,'INFO');
          let status=null,lastLog='';
          while(true){status=await api('build-jobs/'+startedJob.jobId);const currentLog=String(status.log||'');
            if(currentLog!==lastLog){const out=$('#ultraPackOutput');if(out){out.textContent=currentLog||'Preparando el proceso…';out.scrollTop=out.scrollHeight;}lastLog=currentLog;}
            if(status.done)break;await new Promise(resolve=>setTimeout(resolve,450));
          }
          const result=status.result||{ok:false,message:'El empaquetador terminó sin entregar un resultado.',output:lastLog,exitCode:1};
          const output=(result.message?'Resultado: '+result.message+'\n\n':'')+(result.output||lastLog||'El proceso no proporcionó salida.')+'\n\nCódigo de salida: '+(result.exitCode??'no disponible')+(result.artifact?'\n\nArchivo generado: '+result.artifact:'\n\nNo se ha verificado ningún archivo de salida.')+(result.note?'\n\n'+result.note:'');
          if(box)box.textContent=output;
          if(result.ok){log(result.message||'Empaquetado completado.','INFO');log('Artefacto UltraPack: '+result.artifact,'INFO');toast('Paquete creado con UltraPack');}
          else{log(result.message||'UltraPack no generó el archivo esperado.','ERROR');toast('UltraPack terminó con errores','error');}
        }catch(e){if(box)box.textContent='No se pudo ejecutar UltraPack.\n'+e.message;log('Error de UltraPack: '+e.message,'ERROR');toast('UltraPack terminó con errores','error');}
        finally{buttons.forEach(b=>b.disabled=false);await renderNativeProjects();}
      }}
    ]);
  }

  async function buildNativeProject(path,titleId='',name='',needsInit=false,supportsClean=true,templateId='',generatedFromStudio=false,storedModifications={}){
    if(!path){toast('La ruta del proyecto está vacía.','error');return;}
    const safeTitle=/^PPSA\d{5}$/.test(String(titleId||''))?String(titleId):'';
    const safeName=String(name||'').trim();
    const form='<p>El IDE detecta el tipo y ejecuta la receta upstream validada para ese perfil. Si la plantilla no tiene un perfil compatible, la compilación se deshabilita en la lista. Los archivos del proyecto no se eliminan por conjetura.</p>'+nativeBuildModificationOptionsMarkup(templateId,storedModifications,needsInit)+
      '<div class="form-field"><label>Nombre de título (solo necesario al inicializar)</label><input id="nativeBuildName" maxlength="40" value="'+esc(safeName)+'" '+(needsInit?'':'disabled')+'></div>'+
      '<div class="form-field"><label>TITLE_ID (solo necesario al inicializar)</label><input id="nativeBuildTitleId" maxlength="9" value="'+esc(safeTitle)+'" pattern="PPSA[0-9]{5}" '+(needsInit?'':'disabled')+'></div>'+
      '<label class="check-row"><input id="nativeCleanBeforeBuild" type="checkbox"> Limpiar antes de compilar: ejecutar make clean solo si el Makefile declara ese target</label>'+
      '<p class="section-note">'+(supportsClean?'El proyecto declara un target clean.':'La detección no encontró un target clean; el IDE lo volverá a comprobar y no borrará artefactos si no existe.')+' Para las plantillas cuyo pipeline no usa Make en la raíz, se conserva el build upstream sin limpieza automática.</p>'+
      '<pre id="nativeBuildOutput" style="font:10px/1.55 Consolas,monospace;color:#aeb8cf;white-space:pre-wrap;word-break:break-word;max-height:42vh;overflow:auto">Listo para iniciar la compilación…</pre>';
    openModal('Compilación nativa · perfil detectado',form,[
      {text:'Cancelar',class:'ghost',action:closeModal},
      {text:'Compilar',class:'primary',action:async()=>{
        const requestedName=String($('#nativeBuildName')?.value||'').trim();
        const requestedTitleId=String($('#nativeBuildTitleId')?.value||'').trim().toUpperCase();
        const cleanBeforeBuild=!!$('#nativeCleanBeforeBuild')?.checked;
        const nativeModifications=nativeBuildModificationPolicyFromUi(templateId,storedModifications,needsInit);
        const requiredPermissionKeys=['allowExecuteUpstreamBuildTools'];
        if(needsInit)requiredPermissionKeys.unshift('allowExecuteUpstreamGenerationTools');
        const missingPermissionKeys=window.PS5HSNativeModificationPolicy.missingForPermissions(nativeModifications,requiredPermissionKeys);
        if(missingPermissionKeys.length){toast('Autoriza expresamente antes de ejecutar el pipeline: '+missingPermissionKeys.map(key=>window.PS5HSNativeModificationPolicy.getEntry(key)?.label||key).join(', ')+'. No se ha iniciado ningún proceso.','warn');return;}
        if(needsInit&&(!/^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$/.test(requestedName)||!/^PPSA\d{5}$/.test(requestedTitleId)||requestedTitleId==='PPSA00000')){toast('Para inicializar la plantilla introduce un nombre ASCII válido y un TITLE_ID PPSA12345.','error');return;}
        const output=$('#nativeBuildOutput');if(output)output.textContent='Preparando perfil, dependencias y compilación…';
        const actions=$$('#modalActions button');actions.forEach(b=>{if(b.textContent.trim()==='Compilar')b.disabled=true;});
        log('Inicio de compilación: '+path+(cleanBeforeBuild?' (clean solicitado)':''));
        let outcome='error';
        try{
          const startedJob=await api('build-native/start',{path,cleanBeforeBuild,titleId:requestedTitleId||safeTitle,name:requestedName||safeName,nativeModifications});
          if(!startedJob.ok||!startedJob.jobId)throw new Error(startedJob.message||'No se pudo iniciar el trabajador de compilación.');
          let status=null,lastLog='';
          while(true){
            status=await api('build-jobs/'+startedJob.jobId);
            const currentLog=String(status.log||'');
            if(currentLog!==lastLog){const out=$('#nativeBuildOutput');if(out){out.textContent=currentLog||'Esperando salida del proceso…';out.scrollTop=out.scrollHeight;}lastLog=currentLog;}
            if(status.done)break;
            await new Promise(resolve=>setTimeout(resolve,450));
          }
          const result=status.result||{ok:false,message:'El trabajador terminó sin resultado legible.',output:lastLog};
          const out=$('#nativeBuildOutput');if(out){out.textContent=(result.output||result.message||lastLog||'Proceso finalizado.')+(result.artifact?'\n\nArtefacto verificado: '+result.artifact:'');out.scrollTop=out.scrollHeight;}
          if(result.ok){
            outcome='success';setLastPostBuildPath(result.path||path);log(result.message||'Build upstream completado.');if(result.artifact)log('Artefacto nativo: '+result.artifact);toast('Compilación nativa completada');
            const modalActions=$('#modalActions');
            if(modalActions&&!modalActions.querySelector('[data-post-build="ultrapack"]')){
              const packButton=document.createElement('button');packButton.className='btn secondary';packButton.dataset.postBuild='ultrapack';packButton.textContent='Empaquetar con UltraPack';packButton.onclick=()=>packageNativeWithUltraPack(result.path||path);modalActions.append(packButton);
            }
          }else{outcome='error';log(result.message||'El build nativo ha fallado.','ERROR');toast('La compilación nativa ha fallado. Revisa el log.','error');}
          if(result.diagnostics){result.diagnostics.forEach(d=>allDiagnostics.push(d));renderDiagnostics();}
        }catch(e){const out=$('#nativeBuildOutput');if(out)out.textContent=e.message;log('Invocación del build nativo: '+e.message,'ERROR');toast('No se pudo ejecutar el build nativo.','error');}
        finally{const title=$('#modalTitle');if(title)title.textContent=outcome==='success'?'Compilación completada':'Error de compilación';$$('#modalActions button').forEach(b=>b.disabled=false);await refreshStatus();await renderNativeProjects();}
      }}
    ]);
  }

  function openNativeBoilerplateCreate(templateId='nativecpp'){
    const isUi=templateId==='hui-gl';
    const defaults=project.name&&project.name!=='MiHomebrew'?project.name:'MiHomebrew';
    const tid='PPSA'+String(Math.floor(Math.random()*90000)+10000);
    openModal(isUi?'Crear proyecto UI OpenGL':'Crear base nativa C++20',`<p>Se creará un proyecto independiente desde el checkout real de <code>${isUi?'blackbearreloaded/ps5-homebrew-ui':'blackbearreloaded/ps5-native-app-boilerplate'}</code>. El asistente configura el <code>TITLE_ID</code> y el nombre con el inicializador upstream. ${isUi?'Incluye el kit OpenGL y los diseños/componente de upstream; necesita sus dependencias de OpenGL.':'No combina automáticamente el kit OpenGL/UI ni afirma que compile hasta ejecutar Make.'}</p><div class="form-field"><label>Nombre del título</label><input id="nativeTitleName" maxlength="40" value="${esc(defaults)}" /></div><div class="form-field"><label>TITLE_ID</label><input id="nativeTitleId" maxlength="9" value="${tid}" pattern="PPSA[0-9]{5}" /></div><div class="form-field"><label>Tipo</label><select id="nativeTitleCategory"><option value="game">Juego / app interactiva</option><option value="media">Aplicación multimedia</option></select>${nativeModificationOptionsMarkup(isUi?'hui-gl':'nativecpp',['allowExecuteUpstreamGenerationTools'],['allowExecuteUpstreamGenerationTools','allowWindowsBuildEntrypointPatch','normalizeBuildFiles'])}<div id="nativeCreateProgress" class="section-note">El asistente descarga la plantilla si hace falta. Requiere WSL con Git y Python 3; el resultado es la plantilla C++ upstream ${isUi?'con UI OpenGL':'nativa básica'}, no un proyecto SharpProspero.</div>`,[{text:'Cancelar',class:'ghost',action:closeModal},{text:isUi?'Crear app UI OpenGL':'Crear base C++',class:'primary',action:async()=>{const name=$('#nativeTitleName').value.trim();const titleId=$('#nativeTitleId').value.trim().toUpperCase();const category=$('#nativeTitleCategory').value;if(!name||! /^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$/.test(name)){toast('Nombre no válido.','error');return;}if(!/^PPSA[0-9]{5}$/.test(titleId)){toast('TITLE_ID debe tener el formato PPSA12345.','error');return;}const panel=$('#nativeCreateProgress');panel.textContent=isUi?'Copiando el kit UI OpenGL y aplicando la identidad upstream…':'Copiando el boilerplate y aplicando la identidad con el script upstream…';try{const policyApi=window.PS5HSNativeModificationPolicy;const createPermissionKeys=['allowExecuteUpstreamGenerationTools','allowWindowsBuildEntrypointPatch','normalizeBuildFiles'];const nativeModifications=policyApi.normalize(Object.fromEntries(createPermissionKeys.map(key=>[key,$('#nativeMod-'+key)?.checked===true])));const missing=policyApi.missingForPermissions(nativeModifications,['allowExecuteUpstreamGenerationTools']);if(missing.length){toast('Autoriza expresamente antes de crear el proyecto: '+missing.map(key=>policyApi.getEntry(key)?.label||key).join(', ')+'.','warn');return;}const result=await api('template-create',{templateId,name,titleId,category,nativeModifications});panel.textContent=(result.output||result.message||'').slice(-7000);if(result.ok){log(result.message+' Ruta: '+result.path);toast(isUi?'App UI OpenGL creada':'Base C++ creada');setTimeout(()=>{closeModal();openModal(isUi?'Proyecto UI OpenGL creado':'Base nativa creada',`<p>${esc(result.message)}</p><div class="system-tile"><strong>Ubicación</strong><p><code>${esc(result.path)}</code></p><p>${isUi?'La app contiene el kit OpenGL UI de upstream. Revisa su guía, licencia, dependencias y build antes de compilar.':'Es la base real C++20 de upstream. Para menús complejos añade el kit OpenGL compatible o usa un proyecto Vulkan; el lienzo genérico no se traduce automáticamente a C++.'}</p></div>`,[{text:'Cerrar',class:'ghost',action:closeModal},{text:'Compilar ahora',class:'primary',action:()=>{closeModal();buildNativeProject(result.path,titleId,name,false,true,isUi?'hui-gl':'nativecpp',false,nativeModifications);}}]);},120);}else{log(result.message||'No se pudo crear la base.','ERROR');}}catch(err){panel.textContent=err.message;log('Generación C++: '+err.message,'ERROR');}}}]);
  }

  function openVulkanTemplateCreate(){
    const defaults=project.name&&project.name!=='MiHomebrew'?project.name:'MiHomebrew';
    const tid='PPSA'+String(Math.floor(Math.random()*90000)+10000);
    openModal('Crear título desde PS5 Vulkan Template',`<p>Este asistente llamará al <code>ps5/tools/new-title.py</code> del repositorio descargado. Generará una carpeta C++ nativa independiente en el espacio de trabajo de Windows. No compila por sí solo ni traduce automáticamente los bloques del lienzo.</p><div class="form-field"><label>Nombre del título</label><input id="vulkanTitleName" maxlength="40" value="${esc(defaults)}" /></div><div class="form-field"><label>TITLE_ID</label><input id="vulkanTitleId" maxlength="9" value="${tid}" pattern="PPSA[0-9]{5}" /></div><div class="form-field"><label>Plantilla upstream</label><select id="vulkanTitleDesign"><option value="starter">Starter 3D (MIT, sin UI GPL opcional)</option><option value="aurora">UI: Aurora Shelf</option><option value="settings">UI: Settings</option><option value="store">UI: Store</option><option value="hud">UI: HUD</option></select>${nativeGenerationConsentMarkup()}<div id="vulkanCreateProgress" class="section-note">El asistente descarga el generador si falta. Para compilar, la preparación de RADV/Mesa es pesada y exige las herramientas nativas documentadas por upstream en WSL/Linux.</div>`,[{text:'Cancelar',class:'ghost',action:closeModal},{text:'Generar proyecto',class:'primary',action:async()=>{const name=$('#vulkanTitleName').value.trim();const titleId=$('#vulkanTitleId').value.trim().toUpperCase();const design=$('#vulkanTitleDesign').value;if(!name||! /^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$/.test(name)){toast('Nombre no válido para el generador upstream.','error');return;}if(!/^PPSA[0-9]{5}$/.test(titleId)){toast('TITLE_ID debe tener el formato PPSA12345.','error');return;}const p=$('#vulkanCreateProgress');p.textContent='Invocando el generador real del repositorio. No cierres el IDE.';try{if(!$('#native-create-upstream')?.checked){toast('Autoriza expresamente la ejecución del generador upstream para continuar.','warn');return;}const nativeModifications=window.PS5HSNativeModificationPolicy.normalize({allowExecuteUpstreamGenerationTools:true});const result=await api('template-create',{templateId:'vulkan-template',name,titleId,design,nativeModifications});p.textContent=(result.output||result.message||'').slice(-7000);if(result.ok){log(result.message+' Ruta: '+result.path);toast('Proyecto Vulkan generado');setTimeout(()=>{closeModal();openModal('Proyecto creado',`<p>${esc(result.message)}</p><div class="system-tile"><strong>Ubicación</strong><p><code>${esc(result.path)}</code></p><p>El README y el generador upstream indican cómo compilarlo. No se ha afirmado que esté compilado hasta ejecutar su pipeline.</p></div>`,[{text:'Cerrar',class:'ghost',action:closeModal},{text:'Compilar ahora',class:'primary',action:()=>{closeModal();buildNativeProject(result.path,titleId,name,false,false,'vulkan-template',false,nativeModifications);}}]);},120);}else{log(result.message||'No se pudo generar el título.','ERROR');}}catch(err){p.textContent=err.message;log('Generador Vulkan: '+err.message,'ERROR');}}}]);
  }

  function drawComponentPalette(filter){
    const root=$('#componentPalette');if(!root)return;root.innerHTML='';const q=(filter||'').toLowerCase();const entries=Object.entries(TYPES).filter(([id,t])=>(t.name+' '+t.group+' '+t.desc+' '+id).toLowerCase().includes(q));
    const groups=[...new Set(entries.map(([,t])=>t.group))];for(const group of groups){const label=document.createElement('div');label.className='category-label';label.textContent=group.toUpperCase();root.append(label);const grid=document.createElement('div');grid.className='component-grid';entries.filter(([,t])=>t.group===group).forEach(([id,t])=>{const el=document.createElement('button');el.className='component-tile';el.draggable=true;el.dataset.component=id;el.innerHTML=`<span class="tile-icon">${t.icon}</span><span class="tile-name">${esc(t.name)}</span>`;el.title=t.desc;el.addEventListener('click',()=>{if(isPreview)return;makeComponent(id);setActiveView('design');});el.addEventListener('dragstart',ev=>{ev.dataTransfer.setData('application/x-ps5-component',id);ev.dataTransfer.effectAllowed='copy';});grid.append(el);});root.append(grid);}
  }

  function ensureProjectScreens(){
    if(!Array.isArray(project.components))project.components=[];if(!Array.isArray(project.flows))project.flows=[];if(!Array.isArray(project.screens))project.screens=[];
    if(!project.screens.length)project.screens.push({id:'screen-main',name:'Pantalla principal'});
    const ids=new Set();
    project.screens=project.screens.filter((screen,index)=>{if(!screen||typeof screen!=='object')return false;let id=String(screen.id||'').trim();if(!id)id='screen-'+(index+1);while(ids.has(id))id+='-'+(index+1);screen.id=id;screen.name=String(screen.name||('Pantalla '+(index+1))).slice(0,48);ids.add(id);return true;});
    let screenIds=new Set(project.screens.map(screen=>screen.id));
    (Array.isArray(project.components)?project.components:[]).forEach((component,index)=>{if(!component.screenId)component.screenId='screen-main';if(!screenIds.has(component.screenId)){project.screens.push({id:String(component.screenId),name:'Pantalla '+(project.screens.length+1)});screenIds.add(String(component.screenId));}});
    if(!project.screens.some(screen=>screen.id===project.currentScreen))project.currentScreen=project.screens[0].id;
    for(const screen of project.screens){
      const rows=project.components.filter(component=>component.screenId===screen.id);
      if(window.PS5HSLayers&&typeof window.PS5HSLayers.normalizeScreenLayers==='function')window.PS5HSLayers.normalizeScreenLayers(rows);
      else {const ordered=rows.slice().sort((a,b)=>(Number(a.zIndex)||Infinity)-(Number(b.zIndex)||Infinity));ordered.forEach((component,index)=>{component.zIndex=(index+1)*10;});}
    }
  }

  // Explores visual screens separately from native code states.
  function structureLineAt(source,index){return String(source||'').slice(0,Math.max(0,index)).split('\n').length;}
  function structureHumanize(value){
    const key=String(value||'').trim(),names={title:'Inicio',main:'Inicio',main_menu:'Menú principal',mainmenu:'Menú principal',missions:'Misiones',mission_select:'Selección de misiones',play:'Juego',gameplay:'Juego',result:'Resultados',results:'Resultados',manual:'Manual',settings:'Ajustes',options:'Opciones',saves:'Partidas guardadas',save_data:'Partidas guardadas',confirm_delete:'Confirmar eliminación',confirm_new_game:'Confirmar nueva partida',pause:'Pausa',paused:'Pausa',loading:'Carga',game_over:'Fin de partida',credits:'Créditos',inventory:'Inventario',controls:'Controles',audio:'Audio',video:'Vídeo'};
    if(names[key.toLowerCase()])return names[key.toLowerCase()];
    return key.replace(/([a-z0-9])([A-Z])/g,'$1 $2').replace(/[_-]+/g,' ').replace(/\b[a-z]/g,ch=>ch.toUpperCase());
  }
  function structureEnumMembers(raw){
    return String(raw||'').replace(/\/\*[\s\S]*?\*\//g,'').split(',').map(part=>part.replace(/\/\/.*$/,'').trim().match(/^[A-Za-z_]\w*/)).filter(Boolean).map(match=>match[0]).filter(name=>!['count','Count','COUNT','size','SIZE','total','TOTAL'].includes(name));
  }
  function structureMatchingBrace(source,start){
    let depth=0,quote='',escaped=false,lineComment=false,blockComment=false;
    for(let i=start;i<source.length;i++){
      const ch=source[i],next=source[i+1];
      if(lineComment){if(ch==='\n')lineComment=false;continue;}
      if(blockComment){if(ch==='*'&&next==='/'){blockComment=false;i++;}continue;}
      if(quote){if(escaped){escaped=false;continue;}if(ch==='\\'){escaped=true;continue;}if(ch===quote)quote='';continue;}
      if(ch==='/'&&next==='/'){lineComment=true;i++;continue;}
      if(ch==='/'&&next==='*'){blockComment=true;i++;continue;}
      if(ch==='"'||ch==="'"){quote=ch;continue;}
      if(ch==='{')depth++;else if(ch==='}'&&--depth===0)return i;
    }
    return -1;
  }
  function structureDecodeLiteral(value){try{return JSON.parse(value);}catch{return String(value||'').slice(1,-1).replace(/\\(["'\\])/g,'$1').replace(/\\n/g,'\n').replace(/\\t/g,'\t');}}
  function structureUiTextLabels(source){
    const out={},em=source.match(/\benum\s+(?:class\s+)?UiText\s*(?::\s*[^{}]+)?\s*\{([^{}]*)\}/);
    if(!em)return out;
    const keys=structureEnumMembers(em[1]),ix=source.indexOf('kUiStrings');
    if(ix<0)return out;
    const eq=source.indexOf('=',ix),open=source.indexOf('{',eq),end=open<0?-1:structureMatchingBrace(source,open);
    if(open<0||end<0)return out;
    const rowOpen=source.indexOf('{',open+1);
    if(rowOpen<0||rowOpen>=end)return out;
    const rowEnd=structureMatchingBrace(source,rowOpen);
    if(rowEnd<0)return out;
    const literals=source.slice(rowOpen+1,rowEnd).match(/"(?:\\.|[^"\\])*"/g)||[];
    keys.forEach((key,i)=>{if(literals[i])out[key]=structureDecodeLiteral(literals[i]);});
    return out;
  }
  function structureFunction(source,name){
    if(!name)return null;
    const match=new RegExp('\\b'+name+'\\s*\\([^;{}]*\\)\\s*(?:(?:const|noexcept|override)\\s*)*\\{','m').exec(source);
    if(!match)return null;
    const open=source.indexOf('{',match.index+match[0].length-1),end=structureMatchingBrace(source,open);
    if(open<0||end<0)return null;
    return {name:name,line:structureLineAt(source,match.index),body:source.slice(open+1,end),bodyIndex:open+1};
  }
  function structureAssignments(block,states,offset,fullSource){
    if(!states.length)return [];
    const ids=states.map(state=>state.id).join('|');
    const re=new RegExp('\\b(?:screen_|screen|current_screen_|currentScreen)\\s*=\\s*(?:[A-Za-z_]\\w*::)?('+ids+')\\b','g'),found=[];
    let m;
    while((m=re.exec(block))!==null)found.push({to:m[1],index:offset+m.index,line:structureLineAt(fullSource,offset+m.index)});
    return found;
  }
  function scanNativeStructure(source){
    source=String(source||'');
    const states=[],seen=new Set(),enumRx=/\benum\s+(?:class\s+)?([A-Za-z_]\w*)\s*(?::\s*[\w:<>]+)?\s*\{([^{}]*)\}/g;
    let em;
    while((em=enumRx.exec(source))!==null){
      if(!/(screen|view|page|scene|menu|state)/i.test(em[1]))continue;
      const members=structureEnumMembers(em[2]);
      members.forEach(id=>{
        if(seen.has(id))return;seen.add(id);
        states.push({id:id,label:structureHumanize(id),enumName:em[1],enumLine:structureLineAt(source,em.index+em[0].indexOf(em[2])+em[2].indexOf(id)),caseLine:0,renderer:'',rendererLine:0,items:[]});
      });
    }
    const result={source:source,enumName:states.length?states[0].enumName:'',states:states,transitions:[],available:states.length>0};
    if(!states.length)return result;
    const stateIds=new Set(states.map(state=>state.id)),labelMap=structureUiTextLabels(source),routes=new Map(),helperCalls=[];
    function addRoute(from,target,index,via){
      if(!stateIds.has(from)||!stateIds.has(target)||from===target)return;
      const key=from+'>'+target;
      if(routes.has(key)){const old=routes.get(key);if(!old.line&&index>=0){old.line=structureLineAt(source,index);old.via=via;}return;}
      routes.set(key,{from:from,to:target,line:index>=0?structureLineAt(source,index):0,via:via||'asignación de estado'});
    }
    function scanBody(body,offset,from,via){
      structureAssignments(body,states,offset,source).forEach(item=>addRoute(from,item.to,item.index,via));
      for(const call of body.matchAll(/\b([A-Za-z_]\w*)\s*\(/g)){
        const name=call[1];
        if(/^(if|switch|while|for|sizeof|static_cast|reinterpret_cast|ui_text|printf|strlen|strcmp|to_string|push_back|emplace_back|begin|end|size|empty|clear|front|back|abs|round|sqrt|sin|cos|clamp|assert)$/i.test(name))continue;
        if(/(screen|menu|mission|save|new_game|continue|confirm|delete|setting|manual|title|play|back|cancel|start|return|open|close|select|navigat|quit|resume|pause|restart|accept|reject|load|begin|enter|leave|switch|route|activate|handle|input|next|previous|prev|launch|finish|game)/i.test(name))helperCalls.push({from:from,name:name});
      }
    }
    const conditionRx=/\bif\s*\(\s*(?:this->)?(?:screen_|screen|current_screen_|currentScreen)\s*==\s*(?:[A-Za-z_]\w*::)?([A-Za-z_]\w*)\s*\)\s*\{/g;
    let condition;
    while((condition=conditionRx.exec(source))!==null){
      if(!stateIds.has(condition[1]))continue;
      const open=source.indexOf('{',condition.index+condition[0].length-1),end=structureMatchingBrace(source,open);
      if(open>=0&&end>=0)scanBody(source.slice(open+1,end),open+1,condition[1],'condición de estado');
    }
    const switchRx=/\bswitch\s*\(\s*(?:this->)?(screen_|screen|current_screen_|currentScreen)\s*\)\s*\{/g;
    let sw;
    while((sw=switchRx.exec(source))!==null){
      const open=source.indexOf('{',sw.index+sw[0].length-1),end=structureMatchingBrace(source,open);
      if(open<0||end<0)continue;
      const body=source.slice(open+1,end),caseRx=/\bcase\s+(?:[A-Za-z_]\w*::)?([A-Za-z_]\w*)\s*:/g,cases=[];
      let cm;
      while((cm=caseRx.exec(body))!==null)if(stateIds.has(cm[1]))cases.push({id:cm[1],start:cm.index,bodyStart:caseRx.lastIndex});
      cases.forEach((entry,i)=>{
        const stop=i+1<cases.length?cases[i+1].start:body.length,sub=body.slice(entry.bodyStart,stop),absolute=open+1+entry.bodyStart,state=states.find(s=>s.id===entry.id);
        if(state&&!state.caseLine)state.caseLine=structureLineAt(source,open+1+entry.start);
        const draws=Array.from(sub.matchAll(/\b(?:draw|render|show|paint)_[A-Za-z_]\w*\s*\(/g)).map(x=>x[0].replace(/\s*\($/,''));
        if(state&&draws.length)state.renderer=draws.find(n=>n==='draw_'+entry.id||n==='render_'+entry.id||n==='show_'+entry.id||n==='paint_'+entry.id)||draws[draws.length-1];
        scanBody(sub,absolute,entry.id,'caso '+entry.id);
      });
    }
    const origins=new Map();
    helperCalls.forEach(call=>{if(!origins.has(call.name))origins.set(call.name,new Set());origins.get(call.name).add(call.from);});
    origins.forEach((fromStates,name)=>{
      const fn=structureFunction(source,name);if(!fn)return;
      structureAssignments(fn.body,states,fn.bodyIndex,source).forEach(target=>fromStates.forEach(from=>addRoute(from,target.to,target.index,'llamada a '+name)));
    });
    states.forEach(state=>{
      if(!state.renderer){
        const fn=['draw_'+state.id,'render_'+state.id,'show_'+state.id,'paint_'+state.id].map(name=>structureFunction(source,name)).find(Boolean);
        if(fn)state.renderer=fn.name;
      }
      const fn=structureFunction(source,state.renderer);if(!fn)return;
      state.rendererLine=fn.line;
      Array.from(fn.body.matchAll(/\bUiText::([A-Za-z_]\w*)/g)).forEach(match=>{
        const label=labelMap[match[1]]||structureHumanize(match[1]);
        if(label&&state.items.indexOf(label)<0&&state.items.length<14)state.items.push(String(label).slice(0,100));
      });
      const arrays=Array.from(fn.body.matchAll(/(?:const\s+)?char\s*\*+\s*(?:labels|items|options|names|entries)\s*\[[^\]]*\]\s*=\s*\{([\s\S]*?)\}\s*;/ig));
      arrays.forEach(array=>(array[1].match(/"(?:\\.|[^"\\])*"/g)||[]).forEach(literal=>{
        const label=structureDecodeLiteral(literal).trim();
        if(label.length>1&&label.length<90&&state.items.indexOf(label)<0&&state.items.length<14)state.items.push(label);
      }));
      if(!state.items.length&&/\bkMissionTitles\b|\bkMissions\b/.test(fn.body)){
        const count=source.match(/\bkMissionCount\s*=\s*(\d+)/);state.items.push('Catálogo dinámico de '+(count?count[1]:'varias')+' misiones');
      }
    });
    result.transitions=Array.from(routes.values()).sort((a,b)=>(a.line||0)-(b.line||0)).slice(0,140);
    return result;
  }
  function structureSourceCode(){
    if(project.manualCode)return String(project.customCode||$('#codeEditor')?.value||'');
    if(['opengl-ui','vulkan-ui'].includes(project.backend))return String(generateCode()||'');
    return String(project.customCode||generateCode()||'');
  }
  function structureVisualEdges(){
    const edges=[];
    project.flows.filter(flow=>flow.enabled!==false&&flow.action==='navigate').forEach(flow=>{
      const from=component(flow.componentId)?.screenId||project.currentScreen,to=flow.targetScreen;
      if(from&&to&&project.screens.some(s=>s.id===from)&&project.screens.some(s=>s.id===to))edges.push({from:from,to:to,line:0});
    });
    return edges;
  }
  function renderStructureTree(){
    const root=$('#structureTree');if(!root)return;
    const q=String($('#structureSearch')?.value||'').trim().toLocaleLowerCase();
    const visual=project.screens.filter(s=>(s.name+' '+s.id).toLocaleLowerCase().includes(q));
    const native=(structureAnalysis?.states||[]).filter(s=>(s.label+' '+s.id+' '+s.renderer).toLocaleLowerCase().includes(q));
    const visualRows=visual.map(s=>{
      const key='visual:'+s.id,count=project.components.filter(c=>c.screenId===s.id).length;
      return '<button type="button" class="structure-tree-row '+(structureSelection===key?'active':'')+'" data-structure-select="'+esc(key)+'"><span class="structure-tree-icon">▣</span><span class="structure-tree-copy"><strong>'+esc(s.name)+'</strong><small>'+count+' componentes · '+esc(s.id)+'</small></span></button>';
    }).join('')||(q?'<div class="structure-tree-empty">No hay pantallas que coincidan.</div>':'<div class="structure-tree-empty">No hay pantallas definidas.</div>');
    const nativeRows=native.map(s=>{
      const key='native:'+s.id;
      return '<button type="button" class="structure-tree-row '+(structureSelection===key?'active':'')+'" data-structure-select="'+esc(key)+'"><span class="structure-tree-icon">⌘</span><span class="structure-tree-copy"><strong>'+esc(s.label)+'</strong><small>'+esc(s.id)+(s.renderer?' · '+esc(s.renderer):' · renderizador no identificado')+'</small></span></button>';
    }).join('')||(q?'<div class="structure-tree-empty">No hay estados que coincidan.</div>':'<div class="structure-tree-empty">No se detectaron estados en el código.</div>');
    root.innerHTML='<div class="structure-tree-group">Modelo visual · '+project.screens.length+'</div>'+visualRows+'<div class="structure-tree-group">Estados de código · '+(structureAnalysis?.states.length||0)+'</div>'+nativeRows;
    $('#structureTreeCount').textContent=String(visual.length+native.length);
    root.querySelectorAll('[data-structure-select]').forEach(btn=>btn.addEventListener('click',()=>{
      structureSelection=btn.dataset.structureSelect;structureScope=structureSelection.startsWith('native:')?'native':'visual';renderStructure();
    }));
  }
  function renderStructureMap(){
    const root=$('#structureMapCanvas');if(!root)return;
    const nativeScope=structureScope==='native',nativeStates=structureAnalysis?.states||[];
    const nodes=nativeScope?nativeStates.map(s=>({key:'native:'+s.id,id:s.id,label:s.label,kind:s.items.length?'Menú / estado':'Estado C++',subtitle:s.renderer||'Renderizador no identificado',footer:s.items.length+' opciones detectadas'})):project.screens.map(s=>({key:'visual:'+s.id,id:s.id,label:s.name,kind:'Pantalla visual',subtitle:s.id,footer:project.components.filter(c=>c.screenId===s.id).length+' componentes'}));
    const valid=new Set(nodes.map(n=>n.id)),allEdges=nativeScope?(structureAnalysis?.transitions||[]):structureVisualEdges(),edges=allEdges.filter(e=>valid.has(e.from)&&valid.has(e.to));
    const wNode=198,hNode=92,gx=66,gy=34,positions=new Map();
    if(!edges.length)nodes.forEach((n,i)=>positions.set(n.id,{x:24+(i%3)*(wNode+gx),y:26+Math.floor(i/3)*(hNode+gy)}));
    else{
      const indegree=new Map(nodes.map(n=>[n.id,0]));edges.forEach(e=>indegree.set(e.to,(indegree.get(e.to)||0)+1));
      const roots=nodes.filter(n=>!indegree.get(n.id)).map(n=>n.id);if(!roots.length&&nodes.length)roots.push(nodes[0].id);
      const depth=new Map(),queue=[];roots.forEach(id=>{depth.set(id,0);queue.push(id);});
      for(let i=0;i<queue.length;i++)edges.filter(e=>e.from===queue[i]).forEach(e=>{if(!depth.has(e.to)){depth.set(e.to,depth.get(queue[i])+1);queue.push(e.to);}});
      let max=Math.max(0,...Array.from(depth.values()));nodes.forEach(n=>{if(!depth.has(n.id)){max++;depth.set(n.id,max);}});
      const groups=new Map();nodes.forEach(n=>{const d=depth.get(n.id)||0;if(!groups.has(d))groups.set(d,[]);groups.get(d).push(n);});
      Array.from(groups.entries()).sort((a,b)=>a[0]-b[0]).forEach(([d,group])=>group.forEach((n,row)=>positions.set(n.id,{x:24+d*(wNode+gx),y:26+row*(hNode+gy)})));
    }
    let width=760,height=440;positions.forEach(p=>{width=Math.max(width,p.x+wNode+24);height=Math.max(height,p.y+hNode+26);});
    root.style.width=width+'px';root.style.height=height+'px';
    const edgeMarkup=edges.map(e=>{
      const a=positions.get(e.from),b=positions.get(e.to);if(!a||!b)return '';
      const sx=a.x+wNode,sy=a.y+hNode/2,tx=b.x,ty=b.y+hNode/2,mid=(sx+tx)/2;
      const path=tx>sx+8?'M '+sx+' '+sy+' C '+mid+' '+sy+', '+mid+' '+ty+', '+tx+' '+ty:'M '+sx+' '+sy+' C '+(sx+55)+' '+Math.max(8,Math.min(sy,ty)-28)+', '+(tx-55)+' '+Math.max(8,Math.min(sy,ty)-28)+', '+tx+' '+ty;
      return '<path class="'+(nativeScope?'derived':'')+'" d="'+path+'" marker-end="url(#structureArrow)"><title>'+esc(e.from+' → '+e.to+(e.line?' · línea '+e.line:''))+'</title></path>';
    }).join('');
    const cards=nodes.map(n=>{
      const p=positions.get(n.id),out=edges.filter(e=>e.from===n.id).length,inc=edges.filter(e=>e.to===n.id).length;
      return '<button type="button" class="structure-node '+(structureSelection===n.key?'active':'')+'" data-structure-select="'+esc(n.key)+'" style="left:'+p.x+'px;top:'+p.y+'px"><span class="structure-node-top"><span class="structure-node-kind">'+esc(n.kind)+'</span><span class="structure-node-count">'+inc+' entr. · '+out+' sal.</span></span><strong>'+esc(n.label)+'</strong><small>'+esc(n.subtitle)+'</small><span class="structure-node-footer">'+esc(n.footer)+'</span></button>';
    }).join('');
    root.innerHTML='<svg class="structure-map-edges" width="'+width+'" height="'+height+'" viewBox="0 0 '+width+' '+height+'" aria-hidden="true"><defs><marker id="structureArrow" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto"><path d="M0,0 L0,6 L6,3 z" fill="#8290b2"></path></marker></defs>'+edgeMarkup+'</svg>'+cards+(nodes.length?'':'<div class="structure-empty"><strong>No hay nodos que representar</strong>No se han encontrado estados nativos ni pantallas visuales.</div>');
    $('#structureMapHint').textContent=nativeScope?nativeStates.length+' estados · '+edges.length+' transiciones detectadas':project.screens.length+' pantallas · '+edges.length+' navegaciones explícitas';
    root.querySelectorAll('[data-structure-select]').forEach(btn=>btn.addEventListener('click',()=>{structureSelection=btn.dataset.structureSelect;renderStructure();}));
  }
  function renderStructureDetails(){
    const root=$('#structureDetails');if(!root)return;
    if(structureScope==='native'){
      const s=(structureAnalysis?.states||[]).find(x=>'native:'+x.id===structureSelection);
      if(!s){root.innerHTML='<div class="structure-empty"><strong>Sin estados nativos detectados</strong>No se reconocieron estados en el código actual.</div>';return;}
      const routes=(title,list)=>'<div class="structure-detail-section"><strong>'+title+' · '+list.length+'</strong><div class="structure-detail-list">'+(list.map(e=>{
        const id=title==='Salidas'?e.to:e.from,t=(structureAnalysis.states||[]).find(x=>x.id===id);
        return '<button type="button" class="structure-detail-item" data-structure-select="native:'+esc(id)+'"><span class="structure-detail-bullet">↗</span><span>'+esc(t?.label||id)+(e.line?' · línea '+e.line:'')+'</span></button>';
      }).join('')||'<div class="structure-detail-note">No se detectaron transiciones explícitas.</div>')+'</div></div>';
      const items=s.items.length?'<div class="structure-detail-section"><strong>Opciones / elementos detectados</strong><div class="structure-menu-items">'+s.items.map(x=>'<span class="structure-menu-item">'+esc(x)+'</span>').join('')+'</div></div>':'<p class="structure-detail-note">No se encontró una lista estática de opciones. El estado podría dibujar sus controles directamente en C++.</p>';
      const out=(structureAnalysis.transitions||[]).filter(e=>e.from===s.id),incoming=(structureAnalysis.transitions||[]).filter(e=>e.to===s.id);
      root.innerHTML='<div class="structure-detail-kicker">'+(s.items.length?'Menú / estado nativo':'Estado nativo C++')+'</div><h3>'+esc(s.label)+'</h3><p class="structure-detail-id">'+esc(s.enumName+'::'+s.id)+'</p><p class="structure-detail-note">Estado encontrado en el código. Este análisis estático no reconstruye el dibujo final en tiempo de ejecución.</p><div class="structure-detail-section"><strong>Implementación</strong><div class="structure-detail-list"><div class="structure-detail-item"><span class="structure-detail-bullet">ƒ</span><span>'+esc(s.renderer||'Renderizador no identificado')+(s.rendererLine?' · línea '+s.rendererLine:'')+'</span></div><div class="structure-detail-item"><span class="structure-detail-bullet">#</span><span>Declaración · línea '+s.enumLine+(s.caseLine?' · caso en línea '+s.caseLine:'')+'</span></div></div></div>'+items+routes('Salidas',out)+routes('Entradas',incoming)+'<div class="structure-detail-actions">'+(s.rendererLine?'<button type="button" class="btn primary small" data-structure-open-code="'+s.rendererLine+'">Ver renderizador</button>':'')+'<button type="button" class="btn secondary small" data-structure-open-code="'+s.enumLine+'">Ir a declaración</button></div><div class="structure-explain">Los enlaces se infieren de condiciones, casos y asignaciones detectadas. Revisa el origen para confirmar rutas complejas.</div>';
    }else{
      const s=project.screens.find(x=>'visual:'+x.id===structureSelection)||project.screens.find(x=>x.id===project.currentScreen);
      if(!s){root.innerHTML='<div class="structure-empty"><strong>Sin pantalla seleccionada</strong>Añade una pantalla desde Diseño.</div>';return;}
      const comps=project.components.filter(c=>c.screenId===s.id),flows=project.flows.filter(f=>component(f.componentId)?.screenId===s.id||(f.action==='navigate'&&f.targetScreen===s.id));
      const outgoing=structureVisualEdges().filter(e=>e.from===s.id),incoming=structureVisualEdges().filter(e=>e.to===s.id);
      const routes=(title,list)=>'<div class="structure-detail-section"><strong>'+title+' · '+list.length+'</strong><div class="structure-detail-list">'+(list.map(e=>{
        const id=title==='Salidas'?e.to:e.from,t=project.screens.find(x=>x.id===id);
        return '<button type="button" class="structure-detail-item" data-structure-select="visual:'+esc(id)+'"><span class="structure-detail-bullet">↗</span><span>'+esc(t?.name||id)+'</span></button>';
      }).join('')||'<div class="structure-detail-note">No hay navegación explícita entre pantallas.</div>')+'</div></div>';
      root.innerHTML='<div class="structure-detail-kicker">Pantalla del modelo visual</div><h3>'+esc(s.name)+'</h3><p class="structure-detail-id">'+esc(s.id)+'</p><p class="structure-detail-note">Los componentes de esta pantalla se pueden editar en el lienzo Diseño.</p><div class="structure-detail-section"><strong>Contenido</strong><div class="structure-detail-list"><div class="structure-detail-item"><span class="structure-detail-bullet">▣</span><span>'+comps.length+' componentes</span></div><div class="structure-detail-item"><span class="structure-detail-bullet">⌘</span><span>'+flows.length+' flujos relacionados</span></div></div></div>'+routes('Salidas',outgoing)+routes('Entradas',incoming)+'<div class="structure-detail-actions"><button type="button" class="btn primary small" data-structure-open-design="'+esc(s.id)+'">Abrir en Diseño</button></div>';
    }
    root.querySelectorAll('[data-structure-select]').forEach(btn=>btn.addEventListener('click',()=>{structureSelection=btn.dataset.structureSelect;structureScope=structureSelection.startsWith('native:')?'native':'visual';renderStructure();}));
    root.querySelectorAll('[data-structure-open-code]').forEach(btn=>btn.addEventListener('click',()=>openStructureSource(Number(btn.dataset.structureOpenCode))));
    root.querySelectorAll('[data-structure-open-design]').forEach(btn=>btn.addEventListener('click',()=>{selectScreen(btn.dataset.structureOpenDesign);setActiveView('design');}));
  }
  function renderStructure(){
    if(!$('#structureView'))return;
    ensureProjectScreens();
    const source=structureSourceCode();
    if(!structureAnalysis||structureAnalysis.source!==source)structureAnalysis=scanNativeStructure(source);
    if(structureScope==='auto')structureScope=structureAnalysis.available?'native':'visual';
    if(structureScope==='native'&&!structureAnalysis.available)structureScope='visual';
    const isValid=structureSelection&&(structureScope==='native'?structureAnalysis.states.some(s=>'native:'+s.id===structureSelection):project.screens.some(s=>'visual:'+s.id===structureSelection));
    if(!isValid)structureSelection=structureScope==='native'?'native:'+structureAnalysis.states[0].id:'visual:'+project.currentScreen;
    $('#structureSummary').textContent=project.screens.length+' pantallas visuales · '+structureAnalysis.states.length+' estados de código';
    $('#structureScopeNative').classList.toggle('active',structureScope==='native');
    $('#structureScopeNative').disabled=!structureAnalysis.available;
    $('#structureScopeVisual').classList.toggle('active',structureScope==='visual');
    renderStructureTree();renderStructureMap();renderStructureDetails();
  }
  function openStructureSource(line){
    setActiveView('code');
    const editor=$('#codeEditor'),target=Math.max(1,Number(line)||1),lines=(editor.value||'').split('\n');
    const start=lines.slice(0,target-1).reduce((sum,text)=>sum+text.length+1,0),end=start+(lines[target-1]||'').length;
    editor.focus();editor.setSelectionRange(start,end);editor.scrollTop=Math.max(0,(target-3)*17.27);updateGutter();
  }

  function selectScreen(id){
    ensureProjectScreens();const target=project.screens.find(screen=>screen.id===id);if(!target)return;
    project.currentScreen=id;selectedId=null;$('#canvasBreadcrumb').textContent=target.name;
    renderScreenSwitcher();renderCanvas();renderInspector();renderHierarchy();
  }
  function renderScreenSwitcher(){
    const root=$('#screenSwitcher');if(!root)return;ensureProjectScreens();
    root.innerHTML=project.screens.map(screen=>`<button class="screen-tab ${screen.id===project.currentScreen?'active':''}" data-screen-select="${esc(screen.id)}" title="Cambiar a ${esc(screen.name)}">${esc(screen.name)}</button>`).join('')+
      '<button class="screen-switcher-action" id="addScreenButton" title="Crear otra pantalla">＋ Pantalla</button><button class="screen-switcher-action" id="manageScreensButton" title="Renombrar o eliminar pantallas">Gestionar</button>';
    root.querySelectorAll('[data-screen-select]').forEach(button=>button.addEventListener('click',()=>selectScreen(button.dataset.screenSelect)));
    $('#addScreenButton').onclick=()=>openNewScreenDialog();$('#manageScreensButton').onclick=()=>openScreenManager();
  }
  function openNewScreenDialog(initialName=''){
    const name=initialName||`Pantalla ${project.screens.length+1}`;
    openModal('Nueva pantalla',`<p>Crea una pantalla independiente. Sus componentes quedan aislados de los otros menús y la navegación puede dirigirse a ella desde Flujos.</p><div class="form-field"><label>Nombre de la pantalla</label><input id="newScreenName" maxlength="48" value="${esc(name)}" /></div>`,[
      {text:'Cancelar',class:'ghost',action:closeModal},
      {text:'Crear pantalla',class:'primary',action:()=>{const label=String($('#newScreenName')?.value||'').trim();if(!label){toast('Escribe un nombre para la pantalla.','warn');return;}if(project.screens.some(screen=>screen.name.toLocaleLowerCase()===label.toLocaleLowerCase())){toast('Ya existe una pantalla con ese nombre.','warn');return;}snapshot();const id='screen-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,6);project.screens.push({id,name:label.slice(0,48)});project.currentScreen=id;selectedId=null;changed('Pantalla creada');closeModal();renderAll();toast('Pantalla creada: '+label);}}
    ]);
    setTimeout(()=>$('#newScreenName')?.focus(),0);
  }
  function openScreenManager(){
    ensureProjectScreens();
    const rows=()=>project.screens.map(screen=>`<div class="screen-manager-row" data-screen-row="${esc(screen.id)}"><input aria-label="Nombre de pantalla" maxlength="48" value="${esc(screen.name)}" data-screen-name="${esc(screen.id)}" /><button class="btn secondary small" data-screen-open="${esc(screen.id)}">Abrir</button><button class="btn ghost small" data-screen-rename="${esc(screen.id)}">Renombrar</button><button class="btn ghost small" data-screen-delete="${esc(screen.id)}" ${project.screens.length===1?'disabled title="Debe quedar al menos una pantalla"':''}>Eliminar</button></div>`).join('');
    openModal('Gestionar pantallas y menús',`<p>Cada pantalla tiene sus propios componentes. Cambia de pantalla para editar sus capas desde la pestaña <b>Jerarquía</b>; la navegación entre ellas se define en <b>Flujos</b>.</p><div id="screenManagerRows">${rows()}</div>`,[
      {text:'Cerrar',class:'ghost',action:closeModal},
      {text:'＋ Añadir pantalla',class:'secondary',action:()=>{closeModal();openNewScreenDialog();}}
    ]);
    const root=$('#screenManagerRows');if(!root)return;
    root.querySelectorAll('[data-screen-open]').forEach(button=>button.onclick=()=>{const id=button.dataset.screenOpen;closeModal();selectScreen(id);});
    root.querySelectorAll('[data-screen-rename]').forEach(button=>button.onclick=()=>{const id=button.dataset.screenRename;const input=Array.from(root.querySelectorAll('[data-screen-name]')).find(el=>el.dataset.screenName===id);const label=String(input?.value||'').trim();if(!label){toast('El nombre no puede quedar vacío.','warn');return;}if(project.screens.some(screen=>screen.id!==id&&screen.name.toLocaleLowerCase()===label.toLocaleLowerCase())){toast('Ya existe otra pantalla con ese nombre.','warn');return;}snapshot();const screen=project.screens.find(x=>x.id===id);if(screen)screen.name=label.slice(0,48);changed('Pantalla renombrada');closeModal();renderAll();toast('Nombre de pantalla actualizado.');});
    root.querySelectorAll('[data-screen-delete]').forEach(button=>button.onclick=()=>{const id=button.dataset.screenDelete;if(project.screens.length<=1)return;const screen=project.screens.find(x=>x.id===id);if(!screen)return;confirmDialog('Eliminar pantalla',`Se eliminará «${screen.name}», sus componentes y los flujos que dependan de ellos.`,()=>{snapshot();const componentIds=new Set(project.components.filter(c=>c.screenId===id).map(c=>c.id));project.components=project.components.filter(c=>c.screenId!==id);project.flows=project.flows.filter(f=>!componentIds.has(f.componentId)&&!componentIds.has(f.targetId)&&!(f.action==='navigate'&&f.targetScreen===id));project.screens=project.screens.filter(s=>s.id!==id);if(project.currentScreen===id)project.currentScreen=project.screens[0].id;selectedId=null;changed('Pantalla eliminada');renderAll();toast('Pantalla eliminada.');});});
  }
  function moveLayer(componentId,direction){
    const list=screenComponents().slice().sort((a,b)=>(Number(a.zIndex)||1)-(Number(b.zIndex)||1));const index=list.findIndex(c=>c.id===componentId);const next=index+direction;if(index<0||next<0||next>=list.length)return;snapshot();const first=list[index],other=list[next];const firstZ=Number(first.zIndex)||index+1,otherZ=Number(other.zIndex)||next+1;first.zIndex=otherZ;other.zIndex=firstZ;if(first.zIndex===other.zIndex){first.zIndex=index+1;other.zIndex=next+1;}changed('Orden de capas actualizado');renderCanvas();renderHierarchy();
  }

  function fitCanvasToViewport(){
    const wrap=$('.canvas-stage-wrap'),stage=$('#canvasStage');if(!wrap||!stage)return false;
    const style=getComputedStyle(wrap),horizontal=(parseFloat(style.paddingLeft)||0)+(parseFloat(style.paddingRight)||0),vertical=(parseFloat(style.paddingTop)||0)+(parseFloat(style.paddingBottom)||0);
    const availableWidth=wrap.clientWidth-horizontal,availableHeight=wrap.clientHeight-vertical;if(availableWidth<1||availableHeight<1)return false;
    const width=Math.floor(Math.min(availableWidth,availableHeight*(16/9))),height=Math.floor(width*(9/16));if(width<1||height<1)return false;
    const changedSize=stage.style.width!==`${width}px`||stage.style.height!==`${height}px`;if(changedSize){stage.style.width=`${width}px`;stage.style.height=`${height}px`;}return changedSize;
  }
  function toggleLayerIsolation(id=selectedId){
    if(!id)return;isolatedLayerId=isolatedLayerId===id?null:id;if(isolatedLayerId)selectedId=id;
    renderCanvas();renderHierarchy();const button=$('#isolateLayerBtn');if(button){button.disabled=!selectedId;button.classList.toggle('toggled',!!selectedId&&isolatedLayerId===selectedId);button.title=isolatedLayerId?'Mostrar todas las capas':'Aislar capa seleccionada';}
    $('#canvasState').textContent=isolatedLayerId?`Aislando capa: ${component(isolatedLayerId)?.label||isolatedLayerId}`:'Diseño listo';
  }
  function renderCanvas(){
    fitCanvasToViewport();renderScreenSwitcher();ensureProjectScreens();const activeScreen=project.screens.find(screen=>screen.id===project.currentScreen);if(activeScreen)$('#canvasBreadcrumb').textContent=activeScreen.name;
    const stage=$('#canvasStage'),root=$('#canvasElements');root.innerHTML='';stage.querySelector('.isolation-banner')?.remove();stage.style.backgroundColor=project.theme?.background||'#101827';const comps=screenComponents();if(isolatedLayerId&&!comps.some(c=>c.id===isolatedLayerId))isolatedLayerId=null;const isolationActive=!!isolatedLayerId&&!isPreview;stage.classList.toggle('has-items',comps.length>0);stage.classList.toggle('show-grid',showGrid);stage.classList.toggle('isolating-layer',isolationActive);$('#gridBtn').classList.toggle('toggled',showGrid);$('#zoomValue').textContent=zoom+'%';
    for(const c of comps){if(isPreview&&!c.visible)continue;if(isolationActive&&c.id!==isolatedLayerId)continue;const imageAsset=c.type==='image'?project.assets.find(a=>a.id===c.assetId&&a.dataUrl):null;const el=document.createElement('div');el.className='canvas-item '+c.type+(imageAsset?' asset-image':'')+(c.id===selectedId&&!isPreview?' selected':'')+(!c.visible&&!isPreview?' layer-hidden':'');el.dataset.id=c.id;el.title=`${c.label||c.id} (${Math.round(c.x)}, ${Math.round(c.y)})`;
      const itemBackground=c.type==='image'?(imageAsset?'transparent':''):c.bg==='transparent'?'transparent':c.bg;
      const renderedWidth=c.w/1920*stage.clientWidth,renderedHeight=c.h/1080*stage.clientHeight;let renderedFont=Math.max(10,c.font)*stage.clientHeight/1080;if(c.type==='title'){renderedFont=Math.min(renderedFont,renderedWidth/Math.max(1,String(c.label||'').length*.62),renderedHeight*.86);}
      Object.assign(el.style,{left:(c.x/1920*100)+'%',top:(c.y/1080*100)+'%',width:(c.w/1920*100)+'%',height:(c.h/1080*100)+'%',background:itemBackground,color:c.fg,border:c.type==='text'||c.type==='title'||c.type==='separator'?'0':`1px solid ${c.custom?.border||'#ffffff1b'}`,fontSize:renderedFont+'px',opacity:clamp(c.opacity??100,0,100)/100*(c.visible?1:.28),zIndex:c.zIndex||1});
      if(c.type==='title')el.style.fontWeight='750'; if(c.type==='text')el.style.lineHeight='1.4'; if(c.type==='panel')el.style.borderRadius='9px'; if(c.type==='card')el.style.borderRadius='9px';
      if(c.type==='toggle'){el.innerHTML=`<span class="switch-track ${c.checked?'on':''}"></span><span>${esc(c.label)}</span>`;}
      else if(c.type==='progress'){el.innerHTML=`<div class="progress-fill" style="width:${clamp(c.value,0,100)}%;height:100%"></div>`;}
      else if(c.type==='slider'){el.innerHTML=`<span>${esc(c.label)} · ${esc(c.value)}%</span><div class="slider-track"></div>`;}
      else if(c.type==='list'){el.innerHTML=(c.items||[]).map((t,i)=>`<div class="list-row">${i===0?'› ':''}${esc(t)}</div>`).join('');}
      else if(c.type==='image'){if(imageAsset){el.innerHTML=`<img alt="${esc(c.label)}" src="${imageAsset.dataUrl}">`;}else el.innerHTML=`<span style="font-size:22px">▧</span><span style="font-size:10px">${esc(c.label||'Imagen')} · importar recurso</span>`;}
      else if(c.type==='gauge'){el.innerHTML=`${esc(c.value)}%`;el.style.borderTopColor=c.fg;}
      else if(c.type==='separator'){el.style.background=c.bg;el.style.border='none';}
      else if(c.type==='input'){el.style.justifyContent='flex-start';el.style.textAlign='left';el.innerHTML=`<span style="opacity:.65">▤</span>&nbsp; ${esc(c.label)}`;}
      else if(c.type==='stepper'){el.innerHTML=`${esc(c.label)} <span style="margin-left:auto">− &nbsp;${esc(c.value)}&nbsp; +</span>`;el.style.justifyContent='space-between';el.style.padding='0 12px';}
      else if(c.type==='select'){el.innerHTML=`${esc(c.label)} <span style="margin-left:auto">⌄</span>`;el.style.justifyContent='space-between';el.style.padding='0 12px';}
      else if(c.type==='carousel'){el.innerHTML=`‹ &nbsp; ${esc(c.items?.[0]||c.label)} &nbsp; ›`;}
      else if(c.type==='badge'){el.textContent=c.label;}
      else if(c.type==='panel'){if(c.label)el.innerHTML=`<span style="font-size:${(c.font*stage.clientHeight/1080)*.55}px;opacity:.7;align-self:flex-start;padding:8px">${esc(c.label)}</span>`;}
      else el.textContent=c.label||'';
      if(c.id===selectedId&&!isPreview){const res=document.createElement('span');res.className='resize-handle';res.style.cssText='position:absolute;right:0;bottom:0;width:10px;height:10px;background:#aa9eff;border:1px solid #fff;border-radius:2px;cursor:nwse-resize;z-index:9';res.title='Cambiar tamaño';el.append(res);}
      if(isPreview){el.style.cursor=['button','toggle','slider','stepper','select','carousel','list','input'].includes(c.type)?'pointer':'default';el.addEventListener('click',ev=>{ev.stopPropagation();runComponent(c);});}
      else {el.addEventListener('pointerdown',ev=>startMove(ev,c));el.addEventListener('click',ev=>{ev.stopPropagation();selectComponent(c.id);});}
      root.append(el);
    }
    const oldBanner=stage.querySelector('.preview-banner');if(oldBanner)oldBanner.remove();const oldIsolation=stage.querySelector('.isolation-banner');if(oldIsolation)oldIsolation.remove();
    if(isPreview){const b=document.createElement('div');b.className='preview-banner';b.innerHTML='<span>▷ VISTA PREVIA INTERACTIVA</span><button>Salir ×</button>';b.querySelector('button').onclick=stopPreview;stage.append(b);}
    else if(isolationActive){const b=document.createElement('div');b.className='isolation-banner';b.innerHTML=`<span>CAPA AISLADA · ${esc(component(isolatedLayerId)?.label||isolatedLayerId)}</span><button type="button">Mostrar todas</button>`;b.querySelector('button').onclick=()=>toggleLayerIsolation(isolatedLayerId);stage.append(b);}
    const isolateButton=$('#isolateLayerBtn');if(isolateButton){isolateButton.disabled=!selectedId||!component(selectedId);isolateButton.classList.toggle('toggled',!!selectedId&&isolatedLayerId===selectedId);isolateButton.title=isolatedLayerId?'Mostrar todas las capas':'Aislar capa seleccionada';}
    $('#selectionPosition').textContent=selectedId&&component(selectedId)?`${component(selectedId).label} · X ${Math.round(component(selectedId).x)} · Y ${Math.round(component(selectedId).y)}`:'Sin selección';
  }
  function startMove(ev,c){if(ev.button!==0||isPreview)return;const el=ev.currentTarget;selectComponent(c.id);const isResize=ev.target.classList.contains('resize-handle');const stage=$('#canvasStage').getBoundingClientRect();dragInfo={id:c.id,isResize,startX:ev.clientX,startY:ev.clientY,baseX:c.x,baseY:c.y,baseW:c.w,baseH:c.h,stageW:stage.width,stageH:stage.height,moved:false};try{el.setPointerCapture(ev.pointerId);}catch{}
    const move=e=>{if(!dragInfo||dragInfo.id!==c.id)return;const dx=(e.clientX-dragInfo.startX)/dragInfo.stageW*1920,dy=(e.clientY-dragInfo.startY)/dragInfo.stageH*1080;if(Math.abs(dx)+Math.abs(dy)>1)dragInfo.moved=true;if(dragInfo.isResize){c.w=clamp(dragInfo.baseW+dx,32,1920-c.x);c.h=clamp(dragInfo.baseH+dy,3,1080-c.y);}else{c.x=clamp(dragInfo.baseX+dx,0,1920-c.w);c.y=clamp(dragInfo.baseY+dy,0,1080-c.h);}const node=$(`.canvas-item[data-id="${c.id}"]`);if(node){node.style.left=(c.x/1920*100)+'%';node.style.top=(c.y/1080*100)+'%';node.style.width=(c.w/1920*100)+'%';node.style.height=(c.h/1080*100)+'%';}$('#selectionPosition').textContent=`${c.label} · X ${Math.round(c.x)} · Y ${Math.round(c.y)}`;};
    const end=()=>{document.removeEventListener('pointermove',move);document.removeEventListener('pointerup',end);if(dragInfo?.moved){changed('Posición actualizada');renderInspector();renderHierarchy();}dragInfo=null;};document.addEventListener('pointermove',move);document.addEventListener('pointerup',end,{once:true});
  }
  function runComponent(c){
    if(c.type==='toggle'){c.checked=!c.checked;renderCanvas();runFlowsFor(c.id,'change');return;}
    if(c.type==='slider'){c.value=(Number(c.value)+c.step>c.max)?c.min:Number(c.value)+c.step;renderCanvas();runFlowsFor(c.id,'change');return;}
    if(c.type==='stepper'){c.value=c.value>=c.max?c.min:Number(c.value)+1;renderCanvas();runFlowsFor(c.id,'change');return;}
    if(c.type==='select'||c.type==='carousel'){c.custom.selected=((c.custom.selected||0)+1)%(c.items?.length||1);toast(`${c.label}: ${c.items?.[c.custom.selected]||''}`);runFlowsFor(c.id,'activate');return;}
    if(c.type==='input'){showTextPrompt(c);return;}
    runFlowsFor(c.id,'activate');const has=project.flows.some(f=>f.componentId===c.id&&f.event==='activate');if(!has&&c.type==='button')toast(`«${c.label}» activado. Asigna un flujo para ejecutar una acción.`,'warn');
  }
  function runSingleFlow(f,id=''){
    switch(f.action){
      case'notify':toast(f.message||`Evento: ${component(id)?.label||'inicio'}`);break;
      case'setText':{const target=component(f.targetId);if(target){if(target.type==='input')target.custom.text=f.value||f.message||'';else target.label=f.value||f.message||'Texto actualizado';renderCanvas();}else toast('La acción no tiene un componente de destino.','warn');break;}
      case'toggleVisibility':{const target=component(f.targetId);if(target){target.visible=!target.visible;renderCanvas();}break;}
      case'setValue':{const target=component(f.targetId);if(target){if(target.type==='toggle')target.checked=/^(true|1|sí|si|on)$/i.test(String(f.value));else if(['select','carousel','list'].includes(target.type)){target.custom.selected=clamp(Math.round(Number(f.value)||0),0,Math.max(0,(target.items?.length||1)-1));}else target.value=clamp(f.value,Number(target.min)||0,Number(target.max)||100);renderCanvas();}break;}
      case'navigate':{const targetScreen=project.screens.find(s=>s.id===f.targetScreen);if(targetScreen){project.currentScreen=targetScreen.id;$('#canvasBreadcrumb').textContent=targetScreen.name;renderCanvas();renderHierarchy();renderInspector();toast(`Pantalla: ${targetScreen.name}`);}else toast(`Pantalla inexistente: ${f.targetScreen||'sin destino'}`,'warn');break;}
      case'changeColor':project.theme.background=f.value||'#7865f6';renderCanvas();break;
      default:toast(`Evento de ${component(id)?.label||'control'} ejecutado.`);
    }
  }
  function runFlowsFor(id,event){const fs=project.flows.filter(f=>f.enabled!==false&&f.componentId===id&&(f.event===event||f.event==='any'));fs.forEach(f=>runSingleFlow(f,id));}
  function runStartFlows(){project.flows.filter(f=>f.enabled!==false&&f.event==='start').forEach(f=>runSingleFlow(f,''));}
  function showTextPrompt(c){openModal('Introducir texto',`<div class="form-field"><label>Valor para «${esc(c.label)}»</label><input id="promptValue" value="${esc(c.custom.text||'')}" placeholder="Texto…"></div>`,[{text:'Cancelar',class:'ghost',action:closeModal},{text:'Aplicar',class:'primary',action:()=>{c.custom.text=$('#promptValue').value;toast('Valor de texto actualizado');closeModal();runFlowsFor(c.id,'change');}}]);setTimeout(()=>$('#promptValue')?.focus(),50);}
  function stopPreview(){isPreview=false;if(previewSnapshot){project=previewSnapshot;previewSnapshot=null;$('#projectName').value=project.name||'MiHomebrew';$('#backendSelect').value=project.backend||'sharp';if(!component(selectedId))selectedId=null;}$('#previewBtn').textContent='▷ Vista previa';renderAll();log('Vista previa detenida; estado de diseño restaurado.');}
  function togglePreview(){if(isPreview){stopPreview();return;}if(!screenComponents().length){toast('Añade al menos un componente antes de previsualizar.','warn');return;}previewSnapshot=clone(project);isPreview=true;setActiveView('design');runStartFlows();renderCanvas();$('#previewBtn').textContent='■ Detener vista previa';log('Vista previa interactiva iniciada. Simula ratón/teclado; el comportamiento final depende del runtime nativo.');}

  function renderInspector(){const root=$('#inspectorPane'),c=component(selectedId);if(!c){root.innerHTML=`<div class="empty-selection"><div class="empty-icon">◈</div><strong>Sin selección</strong><br>Selecciona un componente del lienzo o de la jerarquía para editar sus propiedades.<br><br><span class="pill">1920 × 1080</span></div>`;return;}
    const spec=TYPES[c.type]||TYPES.button;
    root.innerHTML=`<div class="inspector-top"><div class="inspector-icon">${spec.icon}</div><div style="min-width:0;flex:1"><div class="inspector-name">${esc(c.label||spec.name)}</div><div class="inspector-type">${spec.name} · <span style="color:#69758f">${c.id.slice(0,13)}</span></div></div><button class="mini-action" id="deleteSelected" title="Eliminar">⌫</button></div>
      <div class="inspector-section"><div class="section-heading">GENERAL <button id="renameSelected">Renombrar ID</button></div><div class="inspector-field"><label>Texto / etiqueta</label><input data-prop="label" value="${esc(c.label)}"></div><div class="inspector-grid"><div class="inspector-field"><label>Visible</label><select data-prop="visible"><option value="true" ${c.visible?'selected':''}>Sí</option><option value="false" ${!c.visible?'selected':''}>No</option></select></div><div class="inspector-field"><label>Opacidad (%)</label><input type="number" data-prop="opacity" min="0" max="100" value="${c.opacity??100}"></div></div></div>
      <div class="inspector-section"><div class="section-heading">POSICIÓN Y TAMAÑO</div><div class="inspector-grid"><div class="inspector-field"><label>X</label><input type="number" data-prop="x" min="0" max="1920" value="${Math.round(c.x)}"></div><div class="inspector-field"><label>Y</label><input type="number" data-prop="y" min="0" max="1080" value="${Math.round(c.y)}"></div><div class="inspector-field"><label>Ancho</label><input type="number" data-prop="w" min="1" max="1920" value="${Math.round(c.w)}"></div><div class="inspector-field"><label>Alto</label><input type="number" data-prop="h" min="1" max="1080" value="${Math.round(c.h)}"></div></div><div class="section-note">Coordenadas del diseño lógico (px de 1920 × 1080). El runtime distribuye los controles mediante el toolkit de interfaz de su backend.</div></div>
      <div class="inspector-section"><div class="section-heading">APARIENCIA</div><div class="inspector-grid"><div class="inspector-field"><label>Fondo</label><div class="color-field"><input type="color" data-prop="bg" value="${isColor(c.bg)?c.bg:'#101827'}"><input type="text" data-prop="bgText" value="${esc(c.bg)}"></div></div><div class="inspector-field"><label>Texto</label><div class="color-field"><input type="color" data-prop="fg" value="${isColor(c.fg)?c.fg:'#ffffff'}"><input type="text" data-prop="fgText" value="${esc(c.fg)}"></div></div></div><div class="inspector-field"><label>Tamaño de texto</label><input type="number" data-prop="font" min="8" max="160" value="${c.font}"></div></div>
      ${['toggle','slider','stepper','progress','gauge'].includes(c.type)?`<div class="inspector-section"><div class="section-heading">VALOR</div><div class="inspector-grid"><div class="inspector-field"><label>Valor</label><input type="number" data-prop="value" value="${c.value}" min="-100000" max="100000"></div><div class="inspector-field"><label>Máximo</label><input type="number" data-prop="max" value="${c.max}" min="1" max="100000"></div><div class="inspector-field"><label>Mínimo</label><input type="number" data-prop="min" value="${c.min}" min="-100000" max="100000"></div><div class="inspector-field"><label>Paso</label><input type="number" data-prop="step" value="${c.step}" min="1" max="10000"></div></div>${c.type==='toggle'?`<div class="inspector-field"><label>Estado inicial</label><select data-prop="checked"><option value="true" ${c.checked?'selected':''}>Activado</option><option value="false" ${!c.checked?'selected':''}>Desactivado</option></select></div>`:''}</div>`:''}
      ${['select','carousel','list'].includes(c.type)?`<div class="inspector-section"><div class="section-heading">OPCIONES</div><div class="inspector-field"><label>Una opción por línea</label><textarea data-prop="items">${esc((c.items||[]).join('\n'))}</textarea></div></div>`:''}
      ${c.type==='image'?`<div class="inspector-section"><div class="section-heading">RECURSO</div><div class="inspector-field"><label>Imagen vinculada</label><select data-prop="assetId"><option value="">Sin imagen</option>${project.assets.filter(a=>a.dataUrl?.startsWith('data:image/')).map(a=>`<option value="${esc(a.id)}" ${c.assetId===a.id?'selected':''}>${esc(a.name)}</option>`).join('')}</select></div><button id="replaceImage" class="btn secondary small">Elegir archivo de imagen</button></div>`:''}
      <div class="inspector-section"><div class="section-heading">COMPORTAMIENTO <button id="makeFlow">＋ Flujo</button></div><div class="inspector-field"><label>Acción visual por defecto</label><select data-prop="action"><option value="none" ${c.action==='none'?'selected':''}>Sin acción</option><option value="notify" ${c.action==='notify'?'selected':''}>Mostrar notificación</option></select></div><div class="inspector-field"><label>Mensaje de acción</label><input data-prop="actionMessage" value="${esc(c.actionMessage||'')}" placeholder="Acción completada"></div><div class="section-note">Configura las acciones avanzadas en la pestaña «Flujos». Los tipos de API específicos se exponen según el backend activo.</div></div>`;
    root.querySelectorAll('[data-prop]').forEach(el=>{const handler=()=>updateProperty(c,el.dataset.prop,el.value,el);el.addEventListener('change',handler);if(['label','actionMessage','bgText','fgText'].includes(el.dataset.prop))el.addEventListener('input',()=>{if(el.dataset.prop==='label'||el.dataset.prop==='actionMessage')handler();});});
    $('#deleteSelected').onclick=()=>deleteComponent(c.id);$('#renameSelected').onclick=()=>renameId(c);$('#makeFlow').onclick=()=>{setActiveView('logic');addFlow(c.id);};if($('#replaceImage'))$('#replaceImage').onclick=()=>{activeAssetId=c.id;$('#assetFileInput').click();};
  }
  function isColor(s){return typeof s==='string'&&/^#[\da-f]{6}$/i.test(s);}
  function updateProperty(c,key,val,el){
    snapshot();if(key==='bgText')key='bg';if(key==='fgText')key='fg';
    if(['visible','checked'].includes(key))c[key]=val==='true';else if(['x','y','w','h','font','opacity','value','min','max','step'].includes(key))c[key]=Number(val)||0;else if(key==='items')c.items=val.split('\n').map(s=>s.trim()).filter(Boolean);else if(key==='assetId')c.assetId=val||null;else c[key]=val;
    c.x=clamp(c.x,0,1920-1);c.y=clamp(c.y,0,1080-1);c.w=clamp(c.w,1,1920-c.x);c.h=clamp(c.h,1,1080-c.y);if(key==='label')c.label=val;
    changed('Propiedad actualizada');renderCanvas();renderHierarchy();scheduleAnalysis();
  }
  function renameId(c){openModal('Cambiar identificador',`<div class="form-field"><label>Identificador técnico</label><input id="newIdInput" value="${esc(c.id)}"></div><div class="section-note">Los flujos enlazados se actualizarán al cambiar el ID.</div>`,[{text:'Cancelar',class:'ghost',action:closeModal},{text:'Cambiar',class:'primary',action:()=>{let v=$('#newIdInput').value.trim();if(!/^[a-zA-Z_][a-zA-Z0-9_-]{1,63}$/.test(v)){toast('ID inválido: utiliza letras, números, _ o - y no empieces por un número.','error');return;}if(project.components.some(x=>x.id===v&&x!==c)){toast('Ya existe un componente con ese ID.','error');return;}snapshot();const old=c.id;c.id=v;project.flows.forEach(f=>{if(f.componentId===old)f.componentId=v;if(f.targetId===old)f.targetId=v;});selectedId=v;closeModal();changed('ID actualizado');renderCanvas();renderInspector();renderHierarchy();}}]);}
  function deleteComponent(id){const c=component(id);if(!c)return;openModal('Eliminar componente',`<p>¿Eliminar «${esc(c.label)}» del proyecto? Las acciones que lo referencian también se revisarán.</p>`,[{text:'Cancelar',class:'ghost',action:closeModal},{text:'Eliminar',class:'primary',action:()=>{snapshot();project.components=project.components.filter(x=>x.id!==id);selectedId=null;closeModal();changed('Componente eliminado');renderCanvas();renderInspector();renderHierarchy();renderFlows();}}]);}
  function renderHierarchy(){
    const root=$('#hierarchyPane');ensureProjectScreens();const comps=screenComponents().slice().sort((a,b)=>(Number(b.zIndex)||1)-(Number(a.zIndex)||1));
    root.innerHTML=`<div class="hierarchy-head"><span>CAPAS · ${esc(project.screens.find(s=>s.id===project.currentScreen)?.name||'Pantalla')} (${comps.length})</span><button class="mini-action" id="hierarchySort">Ordenar por Y</button></div><div class="layer-front-note">Parte superior = capa delante. Usa ↑ / ↓ para cambiar el orden.</div>`;
    if(!comps.length){root.innerHTML+=`<div class="empty-selection">Esta pantalla no contiene capas.<br>Añade componentes desde Bloques.</div>`;return;}
    comps.forEach((c,visualIndex)=>{
      const row=document.createElement('div');row.className='tree-row layer-row'+(selectedId===c.id?' selected':'');row.draggable=true;
      row.innerHTML=`<span class="tree-icon">${TYPES[c.type]?.icon||'◈'}</span><span class="tree-label" title="${esc(c.label||c.id)}">${esc(c.label||TYPES[c.type]?.name||c.type)}</span><span class="tree-type">z${Number(c.zIndex)||1}</span><span class="layer-order-controls"><button data-layer-up="${esc(c.id)}" title="Traer una capa delante" ${visualIndex===0?'disabled':''}>↑</button><button data-layer-down="${esc(c.id)}" title="Enviar una capa detrás" ${visualIndex===comps.length-1?'disabled':''}>↓</button><button class="tree-eye" data-layer-eye="${esc(c.id)}" title="Mostrar/ocultar">${c.visible?'◉':'○'}</button><button class="layer-isolate ${isolatedLayerId===c.id?'active':''}" data-layer-isolate="${esc(c.id)}" title="Aislar esta capa" aria-pressed="${isolatedLayerId===c.id?'true':'false'}">◎</button></span>`;
      row.addEventListener('click',e=>{const eye=e.target.closest('[data-layer-eye]');if(eye){e.stopPropagation();snapshot();c.visible=!c.visible;changed('Visibilidad actualizada');renderCanvas();renderHierarchy();return;}if(e.target.closest('.layer-order-controls'))return;selectComponent(c.id);});
      row.querySelector('[data-layer-isolate]')?.addEventListener('click',e=>{e.stopPropagation();toggleLayerIsolation(c.id);});
      row.querySelector('[data-layer-up]')?.addEventListener('click',e=>{e.stopPropagation();moveLayer(c.id,1);});row.querySelector('[data-layer-down]')?.addEventListener('click',e=>{e.stopPropagation();moveLayer(c.id,-1);});
      row.addEventListener('dragstart',e=>{e.dataTransfer.setData('application/x-ps5-homebrew-layer',c.id);e.dataTransfer.effectAllowed='move';});
      row.addEventListener('dragover',e=>{if(e.dataTransfer.types.includes('application/x-ps5-homebrew-layer')){e.preventDefault();row.style.borderColor='#8f7dff';}});row.addEventListener('dragleave',()=>row.style.borderColor='transparent');
      row.addEventListener('drop',e=>{e.preventDefault();row.style.borderColor='transparent';const id=e.dataTransfer.getData('application/x-ps5-homebrew-layer');if(!id||id===c.id)return;const dragged=component(id);if(!dragged||dragged.screenId!==c.screenId)return;const ordered=screenComponents().slice().sort((a,b)=>(Number(b.zIndex)||1)-(Number(a.zIndex)||1));const from=ordered.findIndex(x=>x.id===id),to=ordered.findIndex(x=>x.id===c.id);if(from<0||to<0)return;snapshot();ordered.splice(from,1);ordered.splice(to,0,dragged);ordered.forEach((x,i)=>x.zIndex=ordered.length-i);changed('Orden de capas reorganizado');renderCanvas();renderHierarchy();});
      root.append(row);
    });
    $('#hierarchySort').onclick=()=>{snapshot();const sorted=screenComponents().slice().sort((a,b)=>a.y-b.y||a.x-b.x);sorted.forEach((c,i)=>c.zIndex=i+1);changed('Capas ordenadas por posición Y');renderCanvas();renderHierarchy();};
  }

  function flowTemplate(id){const c=component(id)||screenComponents().find(x=>x.type==='button')||screenComponents()[0];return {id:'flow-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,5),componentId:c?.id||'',event:'activate',action:'notify',message:'Acción ejecutada',targetId:'',value:'',targetScreen:project.currentScreen||project.screens?.[0]?.id||'screen-main',enabled:true};}
  function addFlow(componentId){snapshot();const f=flowTemplate(componentId||selectedId);project.flows.push(f);changed('Flujo creado');renderFlows();const node=$(`[data-flow-id="${f.id}"]`);node?.scrollIntoView({behavior:'smooth',block:'center'});}
  function renderFlows(){const root=$('#logicCanvas');root.innerHTML='';if(!project.flows.length){root.innerHTML=`<div class="add-flow-empty"><div style="font-size:28px;color:#9585ff;margin-bottom:12px">⌘</div><strong style="color:#c2cae0">Aún no hay flujos definidos</strong><br>Vincula acciones a botones, interruptores y otros controles.<br><br><button id="flowEmptyAdd" class="btn primary">＋ Crear primer flujo</button><div class="section-note" style="margin-top:12px">Un flujo combina un disparador, un evento y una acción validada por el analizador.</div></div>`;$('#flowEmptyAdd').onclick=()=>addFlow();return;}
    project.flows.forEach((f,i)=>{const c=component(f.componentId);const card=document.createElement('div');card.className='flow-card';card.dataset.flowId=f.id;const opts=project.components.map(x=>`<option value="${esc(x.id)}" ${x.id===f.componentId?'selected':''}>${esc(x.label)} · ${esc(x.id.slice(0,8))}</option>`).join('');const targets=project.components.map(x=>`<option value="${esc(x.id)}" ${x.id===f.targetId?'selected':''}>${esc(x.label)}</option>`).join('');card.innerHTML=`<div class="flow-card-head"><span class="flow-pill">SI / CUANDO</span><strong>${esc(c?.label||'Componente no asignado')}</strong><span class="pill">${i+1}</span><button class="flow-delete" title="Eliminar flujo">×</button></div><div class="flow-fields"><div><label>Componente que dispara</label><select data-flow-prop="componentId"><option value="">Selecciona componente</option>${opts}</select></div><div><label>Evento</label><select data-flow-prop="event">${[['activate','Al activar'],['change','Al cambiar valor'],['start','Al iniciar'],['any','Cualquier evento']].map(([v,t])=>`<option value="${v}" ${f.event===v?'selected':''}>${t}</option>`).join('')}</select></div><div><label>Acción a ejecutar</label><select data-flow-prop="action">${[['notify','Mostrar notificación'],['setText','Cambiar texto de elemento'],['toggleVisibility','Mostrar / ocultar'],['setValue','Cambiar valor'],['changeColor','Cambiar fondo de pantalla'],['navigate','Solicitar navegación']].map(([v,t])=>`<option value="${v}" ${f.action===v?'selected':''}>${t}</option>`).join('')}</select></div><div><label>Destino (si procede)</label><select data-flow-prop="targetId"><option value="">Sin destino</option>${targets}</select></div>${f.action==='navigate'?`<div style="grid-column:1/-1"><label>Pantalla destino</label><select data-flow-prop="targetScreen">${project.screens.map(screen=>`<option value="${esc(screen.id)}" ${screen.id===f.targetScreen?'selected':''}>${esc(screen.name)}</option>`).join('')}</select></div>`:f.action==='notify'?`<div style="grid-column:1/-1"><label>Mensaje</label><input data-flow-prop="message" value="${esc(f.message)}"></div>`:`<div><label>Valor / texto</label><input data-flow-prop="value" value="${esc(f.value)}"></div><div><label>Mensaje de confirmación</label><input data-flow-prop="message" value="${esc(f.message)}"></div>`}</div><div class="flow-footer">${f.enabled?'Flujo activo':'Flujo desactivado'} · Cambios comprobados por el analizador estático. Las llamadas a servicios exclusivos del backend se implementan mediante sus API nativas.</div>`;
      card.querySelector('.flow-delete').onclick=()=>{snapshot();project.flows=project.flows.filter(x=>x.id!==f.id);changed('Flujo eliminado');renderFlows();};card.querySelectorAll('[data-flow-prop]').forEach(el=>el.addEventListener('change',()=>{snapshot();const key=el.dataset.flowProp;f[key]=el.value;changed('Flujo actualizado');renderFlows();}));root.append(card);if(i<project.flows.length-1){const connect=document.createElement('div');connect.className='flow-connect';root.append(connect);}});
  }

  function hasNativeCodegen(){
    return Boolean(window.PS5HSNativeCodegen && typeof window.PS5HSNativeCodegen.generate === 'function');
  }
  async function ensureNativeCodegen(){
    if(hasNativeCodegen()) return window.PS5HSNativeCodegen;
    await new Promise((resolve,reject)=>{
      const script=document.createElement('script');
      script.src=new URL('runtime/native-generator.js',document.baseURI).href;
      script.async=true;
      script.onload=resolve;
      script.onerror=()=>reject(new Error('No se pudo cargar runtime/native-generator.js. Comprueba que la carpeta runtime está junto a index.html y vuelve a iniciar Homebrew Studio desde start.bat.'));
      document.head.appendChild(script);
    });
    if(!hasNativeCodegen()) throw new Error('El generador nativo se ha cargado, pero no expone PS5HSNativeCodegen.generate. Reinstala los archivos de Homebrew Studio y comprueba la consola del navegador.');
    return window.PS5HSNativeCodegen;
  }

  function generateCode(){
    if ((project.backend === 'opengl-ui' || project.backend === 'vulkan-ui') && hasNativeCodegen()) {
      return window.PS5HSNativeCodegen.generate(project, project.backend);
    }
    const comps=screenComponents().slice().sort((a,b)=>a.y-b.y||a.x-b.x);
    const lines=[];
    const q=s=>JSON.stringify(String(s??''));
    const field=c=>'_ui_'+slug(c.id).replace(/-/g,'_');
    const csType=c=>({title:'Label',text:'TextBlock',button:'Button',toggle:'Checkbox',slider:'Slider',stepper:'Stepper',select:'OptionSelector',carousel:'Carousel',list:'ListView',progress:'ProgressBar',badge:'Label',image:'Image',input:'TextBox',gauge:'Gauge',separator:'Separator',panel:'DecorPanel',card:'DecorPanel'})[c.type]||'UiElement';
    const componentById=id=>project.components.find(x=>x.id===id);
    const supportedTextTypes=new Set(['title','text','button','toggle','slider','stepper','select','badge','panel','card','input']);
    const valueProperty=c=>({slider:'Value',stepper:'Value',toggle:'Checked',select:'SelectedIndex',carousel:'SelectedIndex',list:'SelectedIndex',progress:'Value',gauge:'Value'})[c?.type]||null;
    const targetValue=(c,v)=>{
      if(c.type==='toggle')return /^(true|1|sí|si|on)$/i.test(String(v))?'true':'false';
      if(['select','carousel','list','stepper'].includes(c.type))return String(Math.max(0,Math.round(Number(v)||0)));
      if(c.type==='slider')return String(clamp(Number(v)||0,Number(c.min)||0,Number(c.max)||100).toFixed(3)+'f');
      if(['progress','gauge'].includes(c.type))return String(clamp((Number(v)||0)/100,0,1).toFixed(3)+'f');
      return null;
    };
    const bodyFor=f=>{
      const target=componentById(f.targetId),ref=target?field(target):null;
      if(f.action==='notify')return `_status = ${q(f.message||'Acción ejecutada')};`;
      if(f.action==='setText'&&target&&supportedTextTypes.has(target.type))return `${ref}.Text = ${q(f.value||'')};`;
      if(f.action==='toggleVisibility'&&target)return `${ref}.Visible = !${ref}.Visible;`;
      if(f.action==='setValue'&&target&&valueProperty(target)){const v=targetValue(target,f.value);if(v!==null)return `${ref}.${valueProperty(target)} = ${v};`;}
      if(f.action==='changeColor'&&isColor(f.value||'#7562f7'))return `_screen = new UiScreen(Screen.Root, new UiTheme { Background = ${colorToCsharp(f.value||'#7562f7')}, Panel = Screen.Theme.Panel, PanelFocused = Screen.Theme.PanelFocused, Accent = Screen.Theme.Accent, Text = Screen.Theme.Text, TextMuted = Screen.Theme.TextMuted, Border = Screen.Theme.Border, Padding = Screen.Theme.Padding, Spacing = Screen.Theme.Spacing, TextScale = Screen.Theme.TextScale, Font = Screen.Theme.Font }) { Cancelled = () => _exit = true };`;
      return '';
    };
    const handlers=(c,events)=>project.flows.filter(f=>f.enabled!==false&&f.componentId===c.id&&(events.includes(f.event)||f.event==='any')).map(bodyFor).filter(Boolean).join(' ');
    const defaultHandler=c=>c.action==='notify'?`_status = ${q(c.actionMessage||'Acción completada')};`:'';
    const widget=c=>{
      const lab=q(c.label||TYPES[c.type]?.name||c.type),onActivate=handlers(c,['activate']),onChange=handlers(c,['change','activate']),onToggle=[handlers(c,['change']),handlers(c,['activate'])].filter(Boolean).join(' ');
      switch(c.type){
        case'title':return `new Label(${lab}) { Scale = ${clamp(Math.round(c.font/12),2,8)}, TextColor = ${colorToCsharp(c.fg)} }`;
        case'text':return `new TextBlock(${lab}) { Alignment = TextAlignment.Left, TextColor = ${colorToCsharp(c.fg)} }`;
        case'button':{const action=[onActivate,onActivate?'':defaultHandler(c)].filter(Boolean).join(' ');return action?`new Button(${lab}, () => { ${action} })`:`new Button(${lab})`;}
        case'toggle':return `new Checkbox(${lab}, ${c.checked?'true':'false'}${onToggle?`, changed: value => { ${onToggle} }`:''})`;
        case'slider':return `new Slider(${lab}, ${Number(c.min)||0}f, ${Number(c.max)||100}f, ${clamp(c.value,c.min,c.max)}f, step: ${Math.max(1,Number(c.step)||1)}f${onChange?`, changed: value => { ${onChange} }`:''})`;
        case'stepper':return `new Stepper(${lab}, ${Math.round(c.value||1)}, ${Math.round(c.min||0)}, ${Math.round(c.max||100)}, step: ${Math.max(1,Math.round(Number(c.step)||1))}, format: n => n.ToString()${onChange?`, changed: value => { ${onChange} }`:''})`;
        case'select':return `new OptionSelector(${lab}, new[] { ${(c.items||['Opción 1','Opción 2']).map(q).join(', ')} }, selected: ${clamp(c.custom?.selected||0,0,Math.max(0,(c.items||[]).length-1))}${onChange?`, changed: index => { ${onChange} }`:''})`;
        case'carousel':return `new Carousel(new[] { ${(c.items||['Opción 1','Opción 2']).map(q).join(', ')} }${onChange?`, changed: index => { ${onChange} }`:''}${onActivate?`, activated: index => { ${onActivate} }`:''})`;
        case'list':return `new ListView(new[] { ${(c.items||['Elemento 1','Elemento 2']).map(q).join(', ')} }) { Activated = index => { ${onActivate} } }`;
        case'progress':return `new ProgressBar(${clamp((Number(c.value)||0)/100,0,1).toFixed(3)}f)`;
        case'badge':return `new Label(${lab}) { Scale = 2, TextColor = ${colorToCsharp(c.fg)} }`;
        case'input':return `new TextBox(${lab}, ${q(c.custom?.text||'')}, "Escribe aquí", activated: input => { _editingTextBox = input; _afterInput = () => { ${onChange} }; _inputDialog = TextInputDialog.Open(input.Label, maxLength: 128, placeholder: input.Placeholder, initialText: input.Text); ${onActivate} })`;
        case'separator':return 'new Separator()';
        case'panel':case'card':return `new DecorPanel(${lab}, ${Math.max(24,Math.round(c.h*.88))}, ${colorToCsharp(isColor(c.bg)?c.bg:'#202a40')}, ${colorToCsharp(isColor(c.fg)?c.fg:'#e8edff')}, ${clamp(Math.round((Number(c.font)||24)/12),1,6)})`;
        case'gauge':return `new Gauge(${clamp((Number(c.value)||0)/100,0,1).toFixed(3)}f)`;
        case'image':{const asset=project.assets.find(a=>a.id===c.assetId&&a.dataUrl&&String(a.fileName||'').toLowerCase().endsWith('.png'));if(asset)return `new Image(LoadImage_${Math.max(1,usedImages.findIndex(a=>a.id===asset.id)+1)}().AsSurface(), blend: true) { MaxWidth = ${Math.max(1,Math.round(c.w/1920*1720))}, MaxHeight = ${Math.max(1,Math.round(c.h/1080*920))} }`;return `new Label(${q(c.label+' (sin recurso PNG compatible)')})`;}
        default:return `new Label(${lab})`;
      }
    };
    const usedImages=[...new Map(comps.filter(c=>c.type==='image').map(c=>project.assets.find(a=>a.id===c.assetId&&a.dataUrl&&String(a.fileName||'').toLowerCase().endsWith('.png'))).filter(Boolean).map(a=>[a.id,a])).values()];
    lines.push('// Generado por PS5 Homebrew Studio desde el modelo visual.');
    lines.push('using System;','using SharpProspero.Application;','using SharpProspero.Graphics;','using SharpProspero.Ui;','using SharpProspero.Platform;','using SharpProspero.Interop.Dialog;');
    if(usedImages.length)lines.push('using SharpProspero.Storage;','using SharpProspero.Modules;','using SharpProspero.Interop.Sysmodule;');
    lines.push('','namespace SampleApp;','','internal sealed class VisualApp : ProsperoApp','{');
    lines.push('    private UiScreen? _screen;','    private bool _exit;','    private string _status = "Listo";','    private TextInputDialog? _inputDialog;','    private TextBox? _editingTextBox;','    private Action? _afterInput;');
    if(usedImages.length){lines.push('    private SystemModule? _pngDecoder;','    private readonly System.Collections.Generic.List<PngImage> _ownedImages = new();');}
    for(const c of comps)lines.push(`    private ${csType(c)} ${field(c)} = null!;`);
    lines.push('    private UiScreen Screen => _screen ??= BuildScreen();','','    protected override void OnLoad()','    {');
    if(usedImages.length)lines.push('        _pngDecoder = SystemModule.Load(SystemModuleId.PngDec);');
    lines.push('        _screen = BuildScreen();');
    for(const f of project.flows.filter(f=>f.enabled!==false&&f.event==='start')){const body=bodyFor(f);if(body)lines.push('        '+body);}
    lines.push('    }','','    private UiScreen BuildScreen()','    {','        var root = new StackPanel();');
    // The target toolkit uses layout panels: the editor groups nearby Y positions into rows.
    const rows=[];
    for(const c of comps){
      const center=c.y+c.h/2;
      let row=rows.find(r=>Math.abs(r.cy-center)<=Math.max(34,Math.min(c.h,100)*.38));
      if(!row){row={cy:center,items:[]};rows.push(row);}
      row.items.push(c);
      row.cy=(row.cy*(row.items.length-1)+center)/row.items.length;
    }
    rows.sort((a,b)=>a.cy-b.cy);
    for(const row of rows){
      row.items.sort((a,b)=>a.x-b.x);
      for(const c of row.items){
        lines.push(`        ${field(c)} = ${widget(c)};`);
        if(!c.visible)lines.push(`        ${field(c)}.Visible = false;`);
      }
      if(row.items.length===1)lines.push(`        root.Add(${field(row.items[0])});`);
      else lines.push(`        root.Add(new Row()${row.items.map(c=>`\n            .Add(${field(c)})`).join('')});`);
    }
    const bg=isColor(project.theme?.background)?colorToCsharp(project.theme.background):'Color.FromRgb(16, 24, 39)';
    const accent=isColor(project.theme?.accent)?colorToCsharp(project.theme.accent):'Color.FromRgb(120, 101, 246)';
    const fg=isColor(project.theme?.text)?colorToCsharp(project.theme.text):'Color.White';
    lines.push('','        var theme = new UiTheme','        {',`            Background = ${bg},`,`            Accent = ${accent},`,`            Text = ${fg}`,'        };','        return new UiScreen(root, theme) { Cancelled = () => _exit = true };','    }','','    protected override void OnFrame(FrameContext context)','    {','        if (_inputDialog is not null && _inputDialog.Update() == TextInputState.Finished)','        {','            if (_inputDialog.EndStatus == ImeDialogEndStatus.Ok && _editingTextBox is not null) { _editingTextBox.Text = _inputDialog.Text; _afterInput?.Invoke(); }','            _inputDialog.Dispose(); _inputDialog = null; _editingTextBox = null; _afterInput = null;','        }','        context.Surface.Clear(Screen.Theme.Background);','        Screen.Update(UiInput.From(context.Input, context.PreviousInput));','        Screen.Render(context.Surface, margin: 60);','        if (_status != "Listo") context.Surface.DrawTextCentered(_status, context.Surface.Height - 30, 1, Color.FromRgb(0x9A, 0xA4, 0xBC));','        if (_exit) context.RequestExit();','    }','','    protected override void OnUnload()','    {','        if (_inputDialog is not null) { _inputDialog.Dispose(); _inputDialog = null; }', ...(usedImages.length?['        foreach (var image in _ownedImages) image.Dispose();','        _ownedImages.Clear();','        _pngDecoder?.Dispose(); _pngDecoder = null;']:[]),'    }');
    if(usedImages.length){usedImages.forEach((asset,i)=>{lines.push('',`    private PngImage LoadImage_${i+1}()`,`    {`,`        var image = PngImage.Decode(PackageFile.ReadAllBytes(${q('/app0/assets/'+asset.fileName)}));`,'        _ownedImages.Add(image);','        return image;','    }');});}
    lines.push('}', '', 'internal sealed class DecorPanel : UiElement', '{', '    private readonly int _height;', '    private readonly Color _fill;', '    private readonly Color _foreground;', '    private readonly int _scale;', '    public DecorPanel(string text, int height, Color fill, Color foreground, int scale) { Text = text; _height = Math.Max(24, height); _fill = fill; _foreground = foreground; _scale = Math.Clamp(scale, 1, 6); }', '    public string Text { get; set; }', '    public override int Measure(int width, UiTheme theme) => _height;', '    public override void Draw(Surface surface, UiTheme theme, UiElement? focused)', '    {', '        surface.FillRect(Bounds.X, Bounds.Y, Bounds.Width, Bounds.Height, _fill);', '        surface.DrawRect(Bounds.X, Bounds.Y, Bounds.Width, Bounds.Height, ReferenceEquals(focused, this) ? theme.Accent : theme.Border);', '        int maxChars = Math.Max(0, (Bounds.Width - 20) / (8 * _scale));', '        string shown = Text ?? string.Empty;', '        if (shown.Length > maxChars) shown = maxChars > 3 ? shown.Substring(0, maxChars - 3) + "..." : shown.Substring(0, maxChars);', '        surface.DrawText(shown, Bounds.X + 10, Bounds.Y + 10, _scale, _foreground);', '    }', '}', '', 'internal static class Program', '{', '    private static void Main()', '    {', '        using (var app = new VisualApp()) app.Run();', '        ProcessExit.Exit();', '    }', '}');
    return lines.join('\n');
  }
  function colorToCsharp(value){if(!isColor(value))return 'Color.White';const n=parseInt(value.slice(1),16);return `Color.FromRgb(0x${value.slice(1,3)}, 0x${value.slice(3,5)}, 0x${value.slice(5,7)})`;}
  function renderCode(){const editor=$('#codeEditor');editor.value=project.manualCode?(project.customCode||''):generateCode();const nativeBackend=['opengl-ui','vulkan-ui'].includes(project.backend);$('#codeFileName').textContent=nativeBackend?'ps5hs-screen.cpp':'Program.cs';$('#codeLanguageBadge').textContent=nativeBackend?(project.backend==='vulkan-ui'?'C++20 · Vulkan / RADV':'C++20 · OpenGL'):'C# · SharpProspero';$('#codeStatus').textContent=project.manualCode?'Código fuente editado manualmente':(nativeBackend?'Código C++ generado desde el modelo visual':'Código C# generado desde el modelo visual');editor.setAttribute('aria-label',nativeBackend?'Código fuente C++20':'Código fuente C#');updateGutter();}
  function updateGutter(){const n=($('#codeEditor').value||'').split('\n').length;$('#codeGutter').textContent=Array.from({length:n},(_,i)=>i+1).join('\n');}

  let analysisTimer=null;
  function scheduleAnalysis(){clearTimeout(analysisTimer);analysisTimer=setTimeout(runAnalysis,230);}
  function runAnalysis(){const d=[];const add=(severity,title,message,location='Proyecto',fix='')=>d.push({severity,title,message,location,fix});const comps=project.components;
    if(!comps.length)add('info','Lienzo vacío','Añade componentes para empezar a construir la interfaz.','Diseño');
    for(const c of comps){
      if(['select','carousel','list'].includes(c.type)&&(!Array.isArray(c.items)||c.items.length===0))add('error','Control sin opciones','Este componente necesita al menos una opción para generar un widget nativo válido.',`Componente ${c.label}`,'Añade una o más opciones.');
      if(['stepper','slider','progress','gauge'].includes(c.type)&&Number(c.min)>=Number(c.max))add('error','Intervalo numérico inválido','El mínimo debe ser estrictamente inferior al máximo.',`Componente ${c.label}`,'Corrige el rango.');
    }
    const ids=new Set();for(const c of comps){if(ids.has(c.id))add('error','Identificador duplicado',`El identificador «${c.id}» está repetido.`,`Componente ${c.label||c.id}`,'Cambia el ID técnico.');ids.add(c.id);
      if(c.x<0||c.y<0||c.x+c.w>1920||c.y+c.h>1080)add('warning','Elemento fuera del lienzo',`El área de «${c.label}» rebasa el marco de 1920 × 1080.`,`Componente ${c.label}`,'Ajusta posición y tamaño.');
      if(!c.label&&c.type!=='separator')add('warning','Elemento sin etiqueta','El control no contiene texto o título. Puede ser intencionado en iconos e imágenes.',`Componente ${c.id}`);
      if(['button','toggle','slider','stepper','select','carousel','input'].includes(c.type)&&!project.flows.some(f=>f.componentId===c.id))add('info','Sin flujo asociado',`«${c.label}» no tiene acciones del editor de lógica vinculadas.`,`Componente ${c.label}`,'Añade un flujo si debe producir un efecto.');
      if(c.type==='image'&&!project.assets.some(a=>a.id===c.assetId))add('warning','Imagen sin recurso','Selecciona o importa una imagen para este componente.',`Componente ${c.label}`,'Panel Recursos → Importar recurso.');
      if(!c.visible)add('info','Elemento oculto',`«${c.label}» está marcado como no visible.`,`Componente ${c.label}`);
      if(c.w<20||c.h<10)add('warning','Tamaño reducido',`El elemento «${c.label}» podría resultar difícil de seleccionar o leer.`,`Componente ${c.label}`);
      if(['slider','progress','gauge'].includes(c.type)&&c.min>=c.max)add('error','Intervalo inválido','El mínimo debe ser inferior al máximo.',`Componente ${c.label}`,'Corrige min y max.');
    }
    for(const f of project.flows){if(f.event!=='start'&&!component(f.componentId))add('error','Flujo sin disparador',`El flujo ${f.id} apunta a un componente que ya no existe.`,`Flujo ${f.id}`,'Elige un componente válido.');if(['setText','toggleVisibility','setValue'].includes(f.action)&&!component(f.targetId))add('error','Acción sin destino',`La acción «${f.action}» requiere un componente de destino válido.`,`Flujo ${f.id}`,'Selecciona un destino.');if(f.action==='setText'&&component(f.targetId)&&!['title','text','button','toggle','slider','stepper','select','badge','panel','card','input'].includes(component(f.targetId).type))add('error','Destino incompatible con Cambiar texto','El tipo de componente seleccionado no expone una propiedad de texto modificable en el generador actual.',`Flujo ${f.id}`,'Selecciona un control con texto.');if(f.action==='setValue'&&component(f.targetId)&&!['slider','stepper','toggle','select','carousel','list','progress','gauge'].includes(component(f.targetId).type))add('error','Destino incompatible con Cambiar valor','El tipo seleccionado no expone una propiedad de valor compatible.',`Flujo ${f.id}`,'Selecciona un control con valor.');if(f.action==='navigate'&&!project.screens.some(s=>s.id===f.targetScreen))add('warning','Pantalla de destino no definida',`La pantalla «${f.targetScreen}» no existe en el proyecto actual.`,`Flujo ${f.id}`,'Crea la pantalla o cambia el destino.');}
    if(project.backend==='sharp'&&comps.some(c=>c.screenId===(project.currentScreen||'screen-main')&&c.bg&&c.bg!=='transparent'&&!['panel','card'].includes(c.type)))add('warning','Estilos por componente parcialmente traducidos','El toolkit nativo aplica un tema global; no reproduce de forma exacta todos los fondos de color por componente, las coordenadas absolutas ni los tamaños del lienzo. Revisa el código y el layout en la vista previa nativa.','Backend SharpProspero','Ajusta UiTheme o implementa un widget nativo personalizado.');
    if(project.backend==='sharp' && new Set(comps.map(c=>'_ui_'+slug(c.id).replace(/-/g,'_'))).size!==comps.length)add('error','Colisión de identificadores C#','Dos IDs visuales distintos se convierten en el mismo nombre de campo C#.','Código generado','Renombra los controles para que su identificador normalizado sea único.');
    if(project.backend==='sharp'&&project.flows.some(f=>f.enabled!==false&&component(f.componentId)&&component(f.componentId).screenId!==(project.currentScreen||'screen-main')))add('error','Disparador de otra pantalla','El generador visual actual construye la pantalla activa y no puede conectar eventos de controles de otras pantallas.','Flujos','Mueve el flujo a un control de la pantalla activa o cambia la pantalla seleccionada.');
    if(project.backend==='sharp'&&project.flows.some(f=>f.enabled!==false&&f.action==='navigate'))add('error','Navegación entre pantallas aún no compilable','El editor permite definir destinos, pero el backend visual actual compila una pantalla a la vez. No se generará una falsa navegación.','Flujos','Mantén acciones notify/cambiar texto/visibilidad/valor/color en este build, o elimina la navegación antes de compilar.');
    if(project.backend==='sharp'&&project.flows.some(f=>f.enabled!==false&&f.action==='changeColor'&&!isColor(f.value||'#7562f7')))add('error','Color de destino inválido','La acción de color necesita un valor hexadecimal válido.','Flujos','Usa #RRGGBB.');
    if(project.backend==='sharp'&&project.components.some(c=>c.screenId===(project.currentScreen||'screen-main')&&c.type==='image'&&!project.assets.some(a=>a.id===c.assetId&&a.dataUrl&&String(a.fileName||'').toLowerCase().endsWith('.png'))))add('error','Recurso de imagen no compatible con el backend nativo','El renderizador de SharpProspero de esta versión requiere una imagen PNG importada para incluirla en el módulo. El elemento permanece en el modelo y no se sustituye por una imagen ficticia.','Recursos','Importa un PNG y asígnalo al elemento.');
    if(project.backend==='sharp'&&project.flows.some(f=>f.enabled!==false&&['setText','toggleVisibility','setValue'].includes(f.action)&&component(f.targetId)&&component(f.targetId).screenId!==(project.currentScreen||'screen-main')))add('error','Acción dirigida a otra pantalla','El generador nativo actual genera la pantalla activa; no puede referenciar un control de otra pantalla.','Flujos','Selecciona un destino de la pantalla activa.');
    if(project.backend==='sharp'&&project.components.some(c=>c.screenId===(project.currentScreen||'screen-main')&&c.type==='input'))add('info','Teclado en pantalla integrado','El código nativo conecta el control TextBox con TextInputDialog del SDK y actualiza el valor al confirmar.','Componente de texto');
    if(project.backend==='sharp'||project.backend==='sharp-payload'){if(!sdkStatus?.sdks?.find(s=>s.id==='sharp')?.installed)add('warning','SharpProspero no instalado','La edición y vista previa local están disponibles, pero el generador nativo necesita el SDK descargado desde GitHub.','Backend SharpProspero','Abre SDKs y descarga SharpProspero.');if(!sdkStatus?.prerequisites?.dotnet10)add('warning','.NET 10 no detectado','El compilador nativo de SharpProspero requiere .NET 10.','Entorno de compilación','Ejecuta Configurar entorno.');if(!sdkStatus?.prerequisites?.wsl)add('warning','WSL no detectado','En Windows, SharpProspero usa WSL para compilar NativeAOT para la arquitectura de la consola.','Entorno de compilación','Instala WSL y .NET 10 dentro de la distribución.');}
    else {const entry=REPO_CATALOG.find(x=>x.id===project.backend);if(entry&&!sdkStatus?.sdks?.some(s=>s.id===project.backend&&s.installed))add('warning','Backend no instalado',`No se ha detectado el repositorio ${entry.name}.`,`Backend ${entry.name}`,'Descarga el SDK desde el panel SDKs.');}
    const nativeUiBackend=['opengl-ui','vulkan-ui'].includes(project.backend);
    if(project.backend!=='sharp'&&project.backend!=='sharp-payload'&&!nativeUiBackend&&project.components.length)add('error','El backend elegido no es un renderer de UI','Los demás SDK son payload/title/plugin toolchains con otros idiomas y formatos; no se presentará código C# como si fuese compilable por ellos.','Backend','Usa SharpProspero · Aplicación, Native UI · OpenGL o Native UI · Vulkan.');
    if(nativeUiBackend){
      add('info','Generación nativa C++20 activada',project.backend==='opengl-ui'?'El código se genera como un Concept del kit ps5-homebrew-ui y se inyecta en su proyecto OpenGL upstream.':'El código se genera como pantalla del kit PS5_VKHomebrewUI e invoca el generador real de PS5 Vulkan Template.','Backend nativo');
      if(comps.some(c=>c.type==='image'&&c.assetId))add('info','Texturas RGBA preparadas para runtime nativo','El build empaqueta hasta 16 imágenes por pantalla, limitadas a 512×512, y las sube al renderer OpenGL/Vulkan en inicialización. Revisa las licencias de cada recurso antes de distribuir el título.','Recursos','Las imágenes se convierten a RGBA8 predecodificado con límites estrictos antes del empaquetado.');
      if(project.backend==='opengl-ui'&&comps.some(c=>c.type==='image'&&c.assetId&&project.assets.some(a=>a.id===c.assetId&&a.dataUrl?.startsWith('data:image/'))))add('info','Texturas OpenGL preparadas','Las imágenes vinculadas se convierten a RGBA8 y se limitan a 512×512 antes de empaquetarlas en assets/ps5hs.','Recursos');
      if(['opengl-ui','vulkan-ui'].includes(project.backend)&&new Set(comps.filter(c=>c.type==='image'&&c.assetId).map(c=>c.assetId)).size>16)add('error','Límite de texturas nativas','Cada backend C++ admite hasta 16 imágenes únicas como texturas RGBA8 por título.','Recursos','Reduce el número de imágenes vinculadas a 16 o menos para que el paquete no omita recursos.');
      if(comps.some(c=>c.type==='input'))add('info','Teclado nativo en pantalla','El campo input abre un teclado navegable por cruceta; permite letras A–Z, números, puntuación básica, espacio, borrar, limpiar, aceptar y cancelar.','Entrada nativa','El teclado integrado es ASCII; no sustituye un IME del sistema para escritura multilingüe.');
      if(project.flows.some(f=>f.enabled!==false&&f.action==='navigate'&&!project.screens.some(s=>s.id===f.targetScreen)))add('error','Destino de navegación no definido','El flujo apunta a una pantalla que no existe en el modelo.','Flujos','Crea la pantalla o elige un destino válido.');
    }
    if(project.backend==='sharp-payload'&&project.components.length)add('error','Payload no equivale a una aplicación visual','Un payload ELF se carga dentro de un proceso existente y no aloja el toolkit de pantalla de una aplicación.','Backend','Selecciona SharpProspero · Aplicación para esta interfaz.');
    allDiagnostics=d;$('#diagCount').textContent=d.filter(x=>x.severity==='error').length;$('#problemCount').textContent=d.filter(x=>x.severity==='error'||x.severity==='warning').length;renderDiagnostics();return d;
  }
  function renderDiagnostics(){const root=$('#diagnosticsList');const filter=$('#diagFilter')?.value||'all';const list=allDiagnostics.filter(d=>filter==='all'||d.severity===filter);if(!list.length){root.innerHTML=`<div class="diag-empty"><div style="font-size:26px;color:#6f61ce;margin-bottom:10px">✓</div><strong style="color:#c7d1e6">No hay diagnósticos que mostrar</strong><br>Los cambios se analizan automáticamente al editar.</div>`;return;}root.innerHTML=list.map(d=>`<div class="diagnostic-row" data-diagnostic-location="${esc(d.location)}"><div class="diag-symbol ${d.severity}">${d.severity==='error'?'×':d.severity==='warning'?'!':'i'}</div><div class="diag-main"><div class="diag-title">${esc(d.title)}</div><div class="diag-message">${esc(d.message)}</div><div class="diag-meta">${esc(d.location)}${d.fix?' · Solución: '+esc(d.fix):''}</div></div></div>`).join('');}

  function renderDock(){const root=$('#dockContent');if(activeDock==='output'){root.innerHTML=outputLines.slice(-90).map(l=>`<div class="output-line"><span class="output-time">${l.time}</span><span class="${l.level==='ERROR'?'output-error':l.level==='WARN'?'output-warn':'output-ok'}">${esc(l.level)}</span><span>${esc(l.text)}</span></div>`).join('')||'<div class="output-line">Sin mensajes.</div>';root.scrollTop=root.scrollHeight;}else if(activeDock==='problems'){const d=allDiagnostics.filter(x=>x.severity==='error'||x.severity==='warning');root.innerHTML=d.length?d.map(x=>`<div class="output-line"><span class="output-time">${x.severity.toUpperCase()}</span><span class="${x.severity==='error'?'output-error':'output-warn'}">${esc(x.title)}</span><span>${esc(x.message)} · ${esc(x.location)}</span></div>`).join(''):'<div class="output-line"><span class="output-ok">✓</span><span>No hay errores ni advertencias del analizador visual.</span></div>';}else{root.innerHTML=sdkStatus?`<div class="output-line"><span class="output-ok">ROOT</span><span>${esc(sdkStatus.root||'')}</span></div><div class="output-line"><span class="output-ok">WORKSPACE</span><span>${esc(sdkStatus.workspace||'')}</span></div>${(sdkStatus.prerequisites?.items||[]).map(x=>`<div class="output-line"><span class="${x.ok?'output-ok':'output-warn'}">${x.ok?'OK':'MISSING'}</span><span>${esc(x.name)}${x.version?' · '+esc(x.version):''}</span></div>`).join('')}${(sdkStatus.sdks||[]).map(x=>`<div class="output-line"><span class="${x.installed?'output-ok':'output-warn'}">${x.installed?'FOUND':'ABSENT'}</span><span>${esc(x.name)} · ${esc(x.folder)}</span></div>`).join('')}`:'El estado del entorno todavía no está disponible.';}}

  function renderAssetList(){const root=$('#assetList');if(!root)return;if(!project.assets.length){project.fontAssetId='';root.innerHTML='<div class="empty-screen">No hay recursos importados.<br>Usa «Importar recurso» para añadir imágenes, audio o datos al proyecto.</div>';return;}root.innerHTML=project.assets.map(a=>`<div class="asset-row"><div class="asset-preview">${a.dataUrl?.startsWith('data:image/')?`<img alt="" src="${a.dataUrl}">`:'◈'}</div><span class="asset-name" title="${esc(a.name)}">${esc(a.name)}</span><span class="asset-size">${formatBytes(a.size||0)}</span><button class="tree-eye" data-asset-remove="${a.id}" title="Quitar recurso">×</button></div>`).join('');root.querySelectorAll('[data-asset-remove]').forEach(el=>el.onclick=()=>{snapshot();project.assets=project.assets.filter(a=>a.id!==el.dataset.assetRemove);project.components.forEach(c=>{if(c.assetId===el.dataset.assetRemove)c.assetId=null;});changed('Recurso eliminado');renderAssetList();renderCanvas();renderInspector();});renderUnicodeFontPicker();}
  function formatBytes(bytes){return bytes<1024?`${bytes} B`:bytes<1024*1024?`${(bytes/1024).toFixed(1)} KB`:`${(bytes/1024/1024).toFixed(1)} MB`;}
  function renderUnicodeFontPicker(){
    const root=$('#assetList');if(!root)return;
    const fontAssets=project.assets.filter(a=>/\.ttf$/i.test(String(a.fileName||a.name||''))&&String(a.dataUrl||'').startsWith('data:'));
    if(project.fontAssetId&&!fontAssets.some(a=>a.id===project.fontAssetId))project.fontAssetId='';
    const picker=document.createElement('div');picker.className='form-field';picker.style.marginBottom='12px';
    const label=document.createElement('label');label.textContent='Fuente Unicode para compilación nativa (TTF)';
    const select=document.createElement('select');select.id='nativeFontAssetSelect';select.style.width='100%';select.style.marginTop='6px';
    const defaultOption=document.createElement('option');defaultOption.value='';defaultOption.textContent='Fuente predeterminada del backend';select.append(defaultOption);
    for(const asset of fontAssets){const option=document.createElement('option');option.value=asset.id;option.textContent=asset.name||asset.fileName;option.selected=asset.id===project.fontAssetId;select.append(option);}
    const help=document.createElement('small');help.textContent='Importa un .ttf con «Importar recurso». Se hornean los glifos usados por el proyecto en OpenGL y Vulkan. Si la fuente no contiene un carácter requerido, la compilación mostrará el codepoint ausente.';
    picker.append(label,select,help);root.prepend(picker);
    select.onchange=event=>{snapshot();project.fontAssetId=event.target.value||'';changed('Fuente de compilación actualizada');toast(project.fontAssetId?'Fuente Unicode seleccionada':'Se usará la fuente predeterminada');};
  }

  function renderSdkSideStatus(){const root=$('#sdkSideStatus');if(!root)return;root.innerHTML=REPO_CATALOG.map(s=>{const found=sdkStatus?.sdks?.find(x=>x.id===s.id);return `<div style="padding:8px 2px;border-bottom:1px solid #242b3b;display:flex;gap:8px;align-items:center"><span style="color:${found?.installed?'var(--green)':'var(--dim)'}">${found?.installed?'●':'○'}</span><div style="min-width:0;flex:1"><div style="font-size:10px;color:#d7dced">${esc(s.name)}</div><div style="font-size:8px;color:#6d7892;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(s.role)}</div></div><span style="font-size:8px;color:${found?.installed?'var(--green)':'var(--muted)'}">${found?.installed?'INSTALADO':'NO INSTALADO'}</span></div>`;}).join('');}
  async function refreshStatus(){try{sdkStatus=await api('status');renderSdkSideStatus();if(activePanel==='templates')renderSourceCatalog($('#sourceSearch')?.value||'', $('.source-filter.active')?.dataset.sourceFilter||'all');else await renderNativeProjects();scheduleAnalysis();renderDock();log('Entorno actualizado.','INFO');}catch(e){log('No se pudo consultar el estado del entorno: '+e.message,'WARN');}}

  function openModal(title,body,actions=[]){const layer=$('#modalLayer');layer.innerHTML=`<div class="modal"><div class="modal-head"><strong>${esc(title)}</strong><button id="modalClose" aria-label="Cerrar">×</button></div><div class="modal-body">${body}</div><div class="modal-actions" id="modalActions"></div></div>`;layer.classList.remove('hidden');$('#modalClose').onclick=closeModal;actions.forEach(a=>{const b=document.createElement('button');b.className='btn '+(a.class||'ghost');b.textContent=a.text;b.onclick=a.action;$('#modalActions').append(b);});layer.onclick=e=>{if(e.target===layer)closeModal();};}
  function closeModal(){$('#modalLayer').classList.add('hidden');$('#modalLayer').innerHTML='';}
  function confirmDialog(title,message,run){openModal(title,`<p>${esc(message)}</p>`,[{text:'Cancelar',class:'ghost',action:closeModal},{text:'Continuar',class:'primary',action:()=>{closeModal();run();}}]);}
  function projectPayload(){if(!isProjectOpen)throw new Error('No hay un proyecto visual abierto. Usa Nuevo o Abrir antes de guardar/exportar/compilar.');project.name=$('#projectName').value.trim()||'MiHomebrew';project.backend=$('#backendSelect').value;return clone(project);}
  async function saveProject(){if(!isProjectOpen){toast('No hay un proyecto visual abierto.','warn');return null;}const data=projectPayload();try{const source=data.manualCode?$('#codeEditor').value:generateCode();const response=await api('save',{project:data,programCode:source});savedState();log(`Proyecto guardado: ${response.path||data.name}`);toast('Proyecto guardado');return response;}catch(e){try{localStorage.setItem(STORAGE_KEY,JSON.stringify(data));savedState();log('Guardado local del navegador (servicio de Windows no disponible): '+e.message,'WARN');toast('Guardado local en el navegador','warn');}catch(_){toast('No se ha podido guardar el proyecto.','error');}return null;}}
  function importProjectFile(file){const reader=new FileReader();reader.onload=()=>{try{const data=JSON.parse(reader.result);if(data.format!=='ps5vproj'&&!Array.isArray(data.components))throw new Error('El archivo no tiene el formato PS5 Homebrew Studio.');project=Object.assign(freshProject(),data);isProjectOpen=true;setProjectOpenState(true);$('#projectName').value=project.name||'MiHomebrew';$('#projectName').placeholder='Nombre del proyecto';$('#backendSelect').value=project.backend||'sharp';selectedId=null;isPreview=false;previewSnapshot=null;undoStack=[];redoStack=[];savedState();renderAll();toast('Proyecto abierto correctamente');log('Proyecto importado desde archivo.');}catch(e){toast('No se puede abrir: '+e.message,'error');}};reader.readAsText(file);}
  async function exportProject(){if(!isProjectOpen){toast('No hay un proyecto visual abierto para exportar.','warn');return;}const data=projectPayload();try{const source=data.manualCode?$('#codeEditor').value:generateCode();const result=await api('export-zip',{project:data,programCode:source});const a=document.createElement('a');a.href=result.url;a.download=result.fileName||`${slug(data.name)}.zip`;document.body.append(a);a.click();a.remove();toast('ZIP de proyecto exportado');log('ZIP exportado al directorio de descargas.');}catch(e){const blob=new Blob([JSON.stringify(data,null,2)],{type:'application/json'});downloadBlob(blob,`${slug(data.name)}.ps5vproj`);toast('Proyecto exportado como .ps5vproj; servicio ZIP no disponible.','warn');log('Exportado en formato .ps5vproj: '+e.message,'WARN');}}
  function downloadBlob(blob,filename){const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=filename;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(a.href),2000);}
  function newProject(){if(!isProjectOpen){loadFresh();return;}if(isDirty){confirmDialog('Crear nuevo proyecto','Hay cambios sin guardar. Crear otro proyecto reemplazará el estado actual del editor.',()=>loadFresh());}else loadFresh();}
  function loadFresh(){
    project=freshProject();project.name='MiHomebrew';isProjectOpen=true;
    $('#projectName').value=project.name;$('#projectName').placeholder='Nombre del proyecto';$('#backendSelect').value='sharp';
    selectedId=null;isPreview=false;previewSnapshot=null;undoStack=[];redoStack=[];activeAssetId=null;
    try{localStorage.removeItem(STORAGE_KEY);}catch{}
    setProjectOpenState(true);savedState();renderAll();log('Nuevo proyecto creado.');
  }
  function unloadProjectState(){
    if(isPreview)stopPreview();
    project=freshProject();project.name='';project.components=[];project.flows=[];project.assets=[];project.screens=[{id:'screen-main',name:'Pantalla principal'}];project.currentScreen='screen-main';project.settings=Object.assign({},project.settings,{titleId:''});
    selectedId=null;isPreview=false;previewSnapshot=null;undoStack=[];redoStack=[];activeAssetId=null;allDiagnostics=[];isDirty=false;
    $('#projectName').value='';$('#projectName').placeholder='Sin proyecto abierto';$('#backendSelect').value='sharp';
    try{localStorage.setItem(STORAGE_KEY,JSON.stringify({format:'ps5hs-closed',closed:true}));}catch{try{localStorage.removeItem(STORAGE_KEY);}catch{}}
    setProjectOpenState(false);renderAll();
    $('#dirtyPill').textContent='SIN PROYECTO';$('#dirtyPill').classList.add('saved');
    $('#canvasState').textContent='No hay proyecto visual abierto. Las carpetas nativas, compilaciones y paquetes se conservan.';
    log('Proyecto visual cerrado. Los archivos nativos y artefactos del workspace no se han eliminado.','INFO');
    toast('Proyecto cerrado; las compilaciones se conservan.');
  }
  function closeCurrentProject(){
    if(!isProjectOpen)return;
    if(!isDirty){unloadProjectState();return;}
    openModal('Cerrar proyecto','Hay cambios sin guardar. Cerrar el proyecto solo descarga el modelo visual del editor; no elimina fuentes nativas ni paquetes compilados.',[
      {text:'Cancelar',class:'ghost',action:closeModal},
      {text:'Descartar y cerrar',class:'secondary',action:()=>{closeModal();unloadProjectState();}},
      {text:'Guardar y cerrar',class:'primary',action:async()=>{const saved=await saveProject();if(saved){closeModal();unloadProjectState();}}}
    ]);
  }
  function openProject(){openModal('Abrir proyecto',`<p>Abre un archivo <code>.ps5vproj</code> o JSON exportado, o recupera un proyecto guardado en el espacio de trabajo de Windows.</p><button id="chooseProjectFile" class="btn secondary">Seleccionar archivo local</button><div id="savedProjectList" style="margin-top:14px"></div>`,[{text:'Cerrar',class:'ghost',action:closeModal}]);$('#chooseProjectFile').onclick=()=>{$('#projectFileInput').click();closeModal();};const list=$('#savedProjectList');api('projects').then(res=>{if(!res.projects?.length){list.innerHTML='<div class="empty-screen">Todavía no hay proyectos guardados en el espacio de trabajo de Windows.</div>';return;}list.innerHTML=res.projects.map(p=>`<div class="asset-row"><div class="asset-preview">◈</div><span class="asset-name">${esc(p.name)}</span><button class="btn small secondary" data-project-open="${esc(p.file)}">Abrir</button></div>`).join('');list.querySelectorAll('[data-project-open]').forEach(b=>b.onclick=async()=>{try{const out=await api('load',{file:b.dataset.projectOpen});project=Object.assign(freshProject(),out.project);isProjectOpen=true;setProjectOpenState(true);$('#projectName').value=project.name;$('#projectName').placeholder='Nombre del proyecto';$('#backendSelect').value=project.backend;selectedId=null;savedState();closeModal();renderAll();toast('Proyecto cargado');}catch(e){toast(e.message,'error');}});}).catch(e=>{list.innerHTML=`<div class="empty-screen">No se pudo consultar el espacio de trabajo de Windows: ${esc(e.message)}<br>También puedes abrir archivos .ps5vproj.</div>`;});}

  async function installSdks(ids){if(!ids?.length)return;openModal('Gestor de SDK',`<p>Se descargan fuentes de GitHub a <code>toolchains/</code>. La categoría Proyectos usa git clone con submódulos para conservar el árbol real; algunos repositorios son grandes y fijan dependencias específicas. etaHEN-Plugins mantiene la dependencia libNidResolver separada. Revisa licencia y requisitos de cada upstream.</p><div class="build-progress"><span></span></div><div id="sdkInstallProgress">Preparando descargas…</div>`,[{text:'Cancelar vista',class:'ghost',action:closeModal}]);$('#sdkInstallProgress').textContent=`Clonando ${ids.length} repositorio(s). Las fuentes de la categoría Proyectos se clonan con Git y submódulos; las descargas pueden ser grandes.`;log(`Gestor de SDK: iniciando descarga de ${ids.join(', ')}.`);
    try{const res=await api('sdk-install',{ids});closeModal();sdkStatus=await api('status');renderSdkSideStatus();if(activePanel==='templates')renderSourceCatalog($('#sourceSearch')?.value||'', $('.source-filter.active')?.dataset.sourceFilter||'all');scheduleAnalysis();log(res.message||'Repositorios descargados.');(res.results||[]).forEach(r=>log(`${r.name}: ${r.message}`,r.ok?'INFO':'WARN'));toast('Descarga de repositorios finalizada');openModal('Resultado de descarga de repositorios',`<p>${esc(res.message||'Proceso completado.')}</p>${(res.results||[]).map(r=>`<div class="asset-row"><span style="color:${r.ok?'var(--green)':'var(--yellow)'}">${r.ok?'✓':'!'}</span><span class="asset-name">${esc(r.name)}</span><span class="asset-size">${esc(r.message)}</span></div>`).join('')}`, [{text:'Cerrar',class:'primary',action:closeModal}]);}catch(e){closeModal();log('Fallo al descargar repositorios: '+e.message,'ERROR');toast('No se completó la descarga: '+e.message,'error');}
  }
  function openSetup(){openModal('Configurar entorno de compilación',`<p>PS5 Homebrew Studio comprueba dependencias de los backends seleccionados. La configuración de Windows puede instalar paquetes o habilitar WSL; WSL puede requerir privilegios y reiniciar Windows.</p><div class="system-tile"><strong>SharpProspero · ruta recomendada para apps visuales</strong><p>Requiere SDK descargado, .NET 10 SDK en Windows, WSL con una distribución Linux y .NET 10 dentro de WSL. Ejecuta el diagnóstico antes de compilar.</p></div><div class="system-tile"><strong>PS5SDK · payload ELF</strong><p>Requiere CMake ≥ 3.20, Ninja y Clang/LLD. El SDK no crea títulos completos, según su README.</p></div><div class="system-tile"><strong>ps5link · título nativo</strong><p>Requiere host compiler + make, ps5-payload-sdk/prospero-clang, SharpProspero para firmar y un libc.prx compatible de un firmware de destino. La librería Sony no se redistribuye.</p></div><div class="form-field"><label>Acción</label><select id="setupAction"><option value="diagnose">Solo comprobar herramientas (recomendado)</option><option value="git">Instalar Git for Windows mediante winget</option><option value="dotnet">Instalar .NET 10 mediante winget</option><option value="wsl">Instalar WSL + Debian (puede requerir reinicio y administrador)</option><option value="all">Instalar Git, .NET 10 e intentar instalar WSL</option></select></div><div class="section-note">No se descargarán firmware, claves de Sony ni binarios propietarios. El SDK no puede suministrar componentes privados como libc.prx.</div>`,[{text:'Cancelar',class:'ghost',action:closeModal},{text:'Ejecutar',class:'primary',action:async()=>{const action=$('#setupAction').value;closeModal();await runSetup(action);}}]);}
  async function runSetup(action){log('Configuración de entorno: '+action);openModal('Configurando entorno',`<p>Ejecutando comprobaciones e instalación solicitada desde PowerShell de Windows…</p><div class="build-progress"><span></span></div><div id="setupProgress">No cierres la aplicación mientras se ejecuta el proceso.</div>`,[{text:'Cerrar ventana',class:'ghost',action:closeModal}]);try{const res=await api('setup',{action});$('#setupProgress').textContent=(res.output||res.message||'').slice(-5000);await refreshStatus();if(!res.ok)log(res.message||'Hay requisitos pendientes.','WARN');else log(res.message||'Configuración finalizada.');}catch(e){$('#setupProgress').textContent=e.message;log('La configuración no ha finalizado: '+e.message,'ERROR');}setTimeout(()=>{if(!$('#modalLayer').classList.contains('hidden')){const body=$('.modal-body');body?.insertAdjacentHTML('beforeend','<p>Revisa la salida. Si WSL informa que requiere reiniciar Windows, termina la configuración del sistema y vuelve a comprobar.</p>');}},100);}
  async function prepareNativeImageAssets(data,backend){
    if(!['opengl-ui','vulkan-ui'].includes(backend))return [];
    const wanted=[...new Set((data.components||[]).filter(c=>c.type==='image'&&c.assetId).map(c=>String(c.assetId)))];
    const results=[];const safeIds=new Map();
    for(const rawId of wanted){
      const id=rawId.replace(/[^A-Za-z0-9_-]/g,'_').slice(0,80);
      if(!id)throw new Error(`El ID de recurso «${rawId}» no produce un nombre de archivo seguro.`);
      if(safeIds.has(id)){if(safeIds.get(id)!==rawId)throw new Error(`Dos recursos producen el mismo ID nativo («${id}»). Cambia sus ID técnicos antes de compilar.`);continue;}
      safeIds.set(id,rawId);
      if(results.length>=16)break;
      const asset=(data.assets||[]).find(a=>String(a.id)===rawId);
      if(!asset||!String(asset.dataUrl||'').startsWith('data:image/'))continue;
      const img=new Image();img.decoding='async';img.src=asset.dataUrl;
      try{if(typeof img.decode==='function')await img.decode();else await new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;});}catch{throw new Error(`No se pudo decodificar la imagen «${asset.name||id}».`);}
      if(!(img.naturalWidth>0&&img.naturalHeight>0))throw new Error(`La imagen «${asset.name||id}» no tiene dimensiones válidas.`);
      const scale=Math.min(1,512/img.naturalWidth,512/img.naturalHeight);
      const width=Math.max(1,Math.round(img.naturalWidth*scale));const height=Math.max(1,Math.round(img.naturalHeight*scale));
      const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;
      const ctx=canvas.getContext('2d',{willReadFrequently:true});if(!ctx)throw new Error('El navegador no dispone de Canvas 2D para preparar texturas.');
      ctx.clearRect(0,0,width,height);ctx.drawImage(img,0,0,width,height);
      const pixels=ctx.getImageData(0,0,width,height).data;
      const bytes=new Uint8Array(8+pixels.length);const view=new DataView(bytes.buffer);view.setUint32(0,width,true);view.setUint32(4,height,true);bytes.set(pixels,8);
      let binary='';const chunk=0x8000;for(let i=0;i<bytes.length;i+=chunk)binary+=String.fromCharCode(...bytes.subarray(i,i+chunk));
      results.push({id,width,height,base64:btoa(binary),encoding:'rgba8-little-endian-v1',sourceName:String(asset.fileName||asset.name||rawId)});
    }
    return results;
  }

  function nativeModificationOptionsMarkup(backend, requiredKeys, visibleKeys) {
    const policyApi=window.PS5HSNativeModificationPolicy;
    if(!policyApi)throw new Error('No se ha cargado el catálogo de permisos de modificaciones nativas.');
    // Do not carry consent from a different project or a previous operation.
    const current=policyApi.defaults();
    const required=new Set(requiredKeys||policyApi.requiredForBackend(backend));
    const visible=visibleKeys?new Set(visibleKeys):null;
    const rows=policyApi.entriesForBackend(backend).filter(entry=>!visible||visible.has(entry.key)).map(entry=>'<label class="native-change-row" for="nativeMod-'+entry.key+'"><input id="nativeMod-'+entry.key+'" type="checkbox"'+(current[entry.key]===true?' checked':'')+'><span><strong>'+esc(entry.label)+(required.has(entry.key)?' · requerido':'')+'</strong><small>'+esc(entry.description)+'</small></span></label>').join('');
    return '<section class="native-modification-policy"><h3>Control explícito de modificaciones</h3><p>Ningún cambio a fuentes upstream se autoriza por defecto. Marca los permisos para esta operación; el servidor los valida y registra los cambios realizados.</p>'+rows+'</section>';
  }
  function nativeBuildModificationKeys(templateId, needsInit=false) {
    const keys=['allowExecuteUpstreamBuildTools'];
    if(needsInit)keys.unshift('allowExecuteUpstreamGenerationTools');
    if(templateId==='nativecpp'||templateId==='hui-gl')keys.push('allowWindowsBuildEntrypointPatch','normalizeBuildFiles');
    if(templateId==='vulkan-template')keys.push('normalizeBuildFiles','allowVulkanBuildHelperRestore');
    if(templateId==='hui-gl')keys.push('allowOpenGlRuntimeProfile','allowOpenGlEuropeanAtlas');
    return [...new Set(keys)];
  }
  function nativeBuildModificationOptionsMarkup(templateId, storedPolicy, needsInit=false) {
    // Prior consent is not authorization for the next build; each operation starts denied.
    const policy=window.PS5HSNativeModificationPolicy.defaults();
    const keys=nativeBuildModificationKeys(templateId,needsInit);
    const rows=keys.map(key=>{const entry=window.PS5HSNativeModificationPolicy.getEntry(key);return '<label class="native-change-row" for="nativeBuildMod-'+key+'"><input id="nativeBuildMod-'+key+'" type="checkbox"'+(policy[key]===true?' checked':'')+'><span><strong>'+esc(entry.label)+(entry.required?' · requerido':'')+'</strong><small>'+esc(entry.description)+'</small></span></label>';}).join('');
    return '<section class="native-modification-policy"><h3>Permisos explícitos para esta operación</h3><p>El servidor no inicia el pipeline ni aplica las modificaciones controladas por el IDE hasta validar los permisos requeridos. Los cambios anteriores se conservan; desmarcar un permiso no los revierte automáticamente.</p>'+rows+'</section>';
  }
  function nativeBuildModificationPolicyFromUi(templateId, storedPolicy, needsInit=false) {
    const policy=window.PS5HSNativeModificationPolicy.defaults();
    nativeBuildModificationKeys(templateId,needsInit).forEach(key=>{const control=$('#nativeBuildMod-'+key);policy[key]=!!control?.checked;});
    return window.PS5HSNativeModificationPolicy.normalize(policy);
  }
  function nativeGenerationConsentMarkup() {
    const entry=window.PS5HSNativeModificationPolicy.getEntry('allowExecuteUpstreamGenerationTools');
    return '<section class="native-modification-policy"><h3>Permiso de ejecución upstream</h3><p>La creación ejecutará el generador/inicializador de código que pertenece a la plantilla descargada. Revisa el repositorio y su commit antes de aceptarlo.</p><label class="native-change-row" for="native-create-upstream"><input id="native-create-upstream" type="checkbox"><span><strong>'+esc(entry.label)+' · requerido</strong><small>'+esc(entry.description)+'</small></span></label></section>';
  }
  async function buildNativeVisualProject(){
    if(!isProjectOpen){toast('No hay un proyecto visual abierto. Usa Nuevo o Abrir.','warn');return;}
    if(buildBusy)return;
    const backend=project.backend;
    const defaultName=slug(project.name||'MiHomebrew').replace(/^[^A-Za-z0-9]+/,'').slice(0,40)||'MiHomebrew';
    const preferredId=String(project.settings?.titleId||'').toUpperCase();
    const titleId=/^PPSA\d{5}$/.test(preferredId)?preferredId:'PPSA'+String(Math.floor(Math.random()*90000)+10000);
    const label=backend==='vulkan-ui'?'Vulkan / RADV':'OpenGL 4.6';
    openModal('Generar y compilar pantalla nativa',`<p>El modelo visual se convertirá en una clase C++20 que implementa la interfaz real del kit upstream. Homebrew Studio creará un proyecto independiente y ejecutará sus herramientas de compilación; no marcará éxito sin un artefacto verificable.</p><div class="form-field"><label>Nombre del título y carpeta de destino (ASCII, máximo 40 caracteres)</label><input id="nativeVisualName" maxlength="40" value="${esc(defaultName)}" /></div><div class="form-field"><label>TITLE_ID</label><input id="nativeVisualTitleId" maxlength="9" value="${esc(titleId)}" pattern="PPSA[0-9]{5}" /></div><label class="check-row"><input id="nativeVisualOverwrite" type="checkbox" /> Sobrescribir si la carpeta existente pertenece a Homebrew Studio y usa la misma plantilla</label>${nativeModificationOptionsMarkup(backend,['allowExecuteUpstreamGenerationTools','allowExecuteUpstreamBuildTools',backend==='opengl-ui'?'allowOpenGlTemplateIntegration':'allowVulkanTemplateIntegration'])}<div class="presentation-before-build"><h3>Presentación de la app (opcional, antes de compilar)</h3><p>Selecciona los recursos de la tarjeta de esta app. Los campos vacíos mantienen los archivos creados por la plantilla. Imágenes convertidas con las herramientas upstream a los formatos PS5.</p><div class="form-field"><label>Icono · PNG/JPEG/BMP/TIFF</label><input id="nativeVisualIcon" type="file" accept=".png,.jpg,.jpeg,.bmp,.tif,.tiff,.dds"><small>icon0.png · 512 × 512</small></div><div class="form-field"><label>Fondo al seleccionar · imagen</label><input id="nativeVisualSelectionBg" type="file" accept=".png,.jpg,.jpeg,.bmp,.tif,.tiff,.dds"><small>pic0.dds · 3840 × 2160 BC7</small></div><div class="form-field"><label>Fondo durante el lanzamiento · imagen</label><input id="nativeVisualLaunchBg" type="file" accept=".png,.jpg,.jpeg,.bmp,.tif,.tiff,.dds"><small>pic1.dds · 3840 × 2160 BC7</small></div><div class="form-field"><label>Música de selección · AT9/MP3/WAV/OGG/M4A/AAC/FLAC</label><input id="nativeVisualAudio" type="file" accept=".at9,.mp3,.wav,.ogg,.m4a,.aac,.flac,audio/*"><small>snd0.at9 · ATRAC9 en bucle, 48 kHz y máximo 2 MiB. Audio convencional requiere FFmpeg y codificador ATRAC9.</small></div></div><div class="system-tile"><strong>Backend: ${esc(label)} · C++20</strong><p>${backend==='vulkan-ui'?'Se requiere WSL/Linux, CMake/Ninja, Clang/LLVM, PS5_Vulkan, PS5_Mesa y la revisión fijada del PS5_PayloadSDK. La preparación inicial del driver puede ser intensiva.':'Se requiere WSL/Linux, Clang/LLD, Make, la plantilla Native App Boilerplate y las dependencias OpenGL de upstream.'}</p><p>El código de interfaz se genera desde componentes, temas y flujos. OpenGL y Vulkan empaquetan hasta 16 imágenes RGBA8 de 512×512 y crean sus texturas mediante la API nativa del renderer. Los campos input incluyen teclado en pantalla ASCII navegable con la cruceta.</p></div><div class="build-progress"><span></span></div><pre id="nativeVisualOutput" style="font:10px/1.55 Consolas,monospace;color:#aeb8cf;white-space:pre-wrap;word-break:break-word;max-height:28vh;overflow:auto">Preparado para generar C++20.</pre>`,[
      {text:'Cancelar',class:'ghost',action:closeModal},
      {text:'Generar y compilar',class:'primary',action:async()=>{
        const name=$('#nativeVisualName')?.value.trim()||'';
        const tid=$('#nativeVisualTitleId')?.value.trim().toUpperCase()||'';
        if(!/^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$/.test(name)){toast('Nombre no válido: usa entre 1 y 40 caracteres ASCII.','error');return;}
        if(!/^PPSA\d{5}$/.test(tid)){toast('TITLE_ID debe tener el formato PPSA12345.','error');return;}
        const policyApi=window.PS5HSNativeModificationPolicy;
         const nativeModifications=policyApi.normalize(Object.fromEntries(policyApi.entriesForBackend(backend).map(entry=>[entry.key,$('#nativeMod-'+entry.key)?.checked===true])));
         const missingPermissions=policyApi.missingForBackend(backend,nativeModifications,false);
         if(missingPermissions.length){toast('Para continuar debes autorizar expresamente: '+missingPermissions.map(key=>policyApi.getEntry(key)?.label||key).join(', ')+'.','warn');return;}
         project.settings=project.settings||{};project.settings.nativeModifications=nativeModifications;
         const output=$('#nativeVisualOutput');const buttons=$('#modalActions button');buttons.forEach(b=>b.disabled=true);
        buildBusy=true;$('#buildBtn').disabled=true;$('#buildBtn').textContent='⟳ Compilando';setDock('output');
        let buildOutcome='error';
        if(output)output.textContent='Preparando código C++20…';
        log(`Generación visual nativa ${backend}: ${name} (${tid}).`);
        try{
          project.name=name;project.settings=project.settings||{};project.settings.titleId=tid;
          $('#projectName').value=name;
          const data=projectPayload();data.name=name;data.backend=backend;data.settings=data.settings||{};data.settings.titleId=tid;
          const nativeCodegen=data.manualCode?null:await ensureNativeCodegen();
          const code=data.manualCode?$('#codeEditor').value:nativeCodegen.generate(data,backend);
          if(!code||code.length<2000){throw new Error('El generador no produjo una pantalla C++20 válida. Regenera el código e inténtalo de nuevo.');}
          const nativeAssets=await prepareNativeImageAssets(data,backend);
          let nativeFont=null;
          if(data.fontAssetId){
            const selectedFont=(data.assets||[]).find(asset=>asset.id===data.fontAssetId);
            if(!selectedFont)throw new Error('La fuente seleccionada ya no está en la lista de recursos.');
            if(!nativeModifications.allowCustomUnicodeFont)throw new Error('Has seleccionado una fuente TTF personalizada. Autoriza expresamente la modificación de font-baker en el panel «Control explícito de modificaciones» y vuelve a intentarlo.');nativeFont=window.PS5HSUnicodeFonts.prepareFontAsset(selectedFont);
            nativeFont.codepoints=window.PS5HSUnicodeFonts.collectCodepoints(data);
          }
          const presentationFiles={icon:$('#nativeVisualIcon')?.files?.[0]||null,selectionBackground:$('#nativeVisualSelectionBg')?.files?.[0]||null,launchBackground:$('#nativeVisualLaunchBg')?.files?.[0]||null,audio:$('#nativeVisualAudio')?.files?.[0]||null};
          if(Object.values(presentationFiles).some(Boolean)&&!nativeModifications.allowExecuteUpstreamAssetTools){toast('Autoriza expresamente el conversor de recursos de presentación. No se ha creado ni modificado ningún título.','warn');return;}
          const presentationLimits={icon:8*1024*1024,selectionBackground:20*1024*1024,launchBackground:20*1024*1024,audio:20*1024*1024};
          for(const [key,file] of Object.entries(presentationFiles)){if(file&&file.size>presentationLimits[key])throw new Error(`${file.name} supera el máximo permitido de ${Math.round(presentationLimits[key]/1024/1024)} MiB.`);}
          const wirePresentation={};for(const [key,file] of Object.entries(presentationFiles)){if(file)wirePresentation[key]=await encodePresentationFile(file);}
          const wireProject=clone(data);
          // The source model carries names and links, while image pixels travel once as bounded RGBA assets.
          wireProject.assets=(wireProject.assets||[]).map(a=>{const item=Object.assign({},a);delete item.dataUrl;return item;});
          if(output)output.textContent=`Pantalla generada (${code.length.toLocaleString('es-ES')} caracteres). Recursos RGBA preparados: ${nativeAssets.length}. Iniciando pipeline upstream…`;
          const visualBuildPayload=Object.assign({project:wireProject,programCode:code,backend,titleId:tid,nativeAssets,overwriteExisting:!!$('#nativeVisualOverwrite')?.checked,nativeFont},wirePresentation);
          visualBuildPayload.nativeModifications=nativeModifications;
          const startedJob=await api('build-visual-native/start',visualBuildPayload);
          if(!startedJob.ok||!startedJob.jobId)throw new Error(startedJob.message||'El servidor no inició la tarea de compilación.');
          let status=null,lastLog='';
          while(true){
            status=await api('build-jobs/'+startedJob.jobId);
            const currentLog=String(status.log||'');
            if(currentLog!==lastLog){const box=$('#nativeVisualOutput');if(box){box.textContent=currentLog||'Esperando salida del proceso…';box.scrollTop=box.scrollHeight;}lastLog=currentLog;}
            if(status.done)break;
            await new Promise(resolve=>setTimeout(resolve,450));
          }
          const result=status.result||{ok:false,message:'El trabajador terminó sin resultado legible.',output:lastLog};
          const logText=(result.output||result.message||lastLog||'Proceso finalizado.')+(result.path?'\n\nProyecto: '+result.path:'')+(result.artifact?'\nArtefacto: '+result.artifact:'');
          const box=$('#nativeVisualOutput');if(box){box.textContent=logText;box.scrollTop=box.scrollHeight;}
          if(result.ok){buildOutcome='success';setLastPostBuildPath(result.path||'');log(result.message||'Código visual convertido y compilado.', 'INFO');if(result.artifact)log('Artefacto verificado: '+result.artifact,'INFO');toast('Pantalla nativa compilada correctamente');
            try{localStorage.setItem(STORAGE_KEY,JSON.stringify(project));savedState();}catch{}
            const actions=$('#modalActions');
            if(actions&&!actions.querySelector('[data-post-build="ultrapack"]')){
              const packButton=document.createElement('button');packButton.className='btn secondary';packButton.dataset.postBuild='ultrapack';packButton.textContent='Empaquetar con UltraPack';packButton.onclick=()=>packageNativeWithUltraPack(result.path);actions.append(packButton);
            }
          }else{buildOutcome='error';log(result.message||'La generación o compilación nativa ha fallado.','ERROR');if(result.path)log('El proyecto upstream se conserva para corrección: '+result.path,'WARN');toast('Error de compilación. Consulta el registro para ver el diagnóstico.','error');}
          if(result.diagnostics){result.diagnostics.forEach(d=>allDiagnostics.push(d));renderDiagnostics();}
          if(activePanel==='templates')await renderNativeProjects();
        }catch(e){const box=$('#nativeVisualOutput');if(box)box.textContent=e.message;log('Error de generación/compilación nativa: '+e.message,'ERROR');toast('No se completó el build nativo.','error');}
        finally{buildBusy=false;$('#buildBtn').disabled=false;$('#buildBtn').innerHTML=buildOutcome==='success'?'<span>✓</span> Completado':buildOutcome==='error'?'<span>!</span> Error · Reintentar':'<span>▶</span> Compilar';$$('#modalActions button').forEach(b=>b.disabled=false);await refreshStatus();if(activePanel==='templates')await renderNativeProjects();}
      }}
    ]);
  }

  async function buildSharpWithConsent(){
    const policyApi=window.PS5HSNativeModificationPolicy;
    if(!policyApi){toast('Falta el catálogo de permisos. Reinicia el IDE antes de compilar.','error');return;}
    const requiredKeys=['allowSharpTemplateIntegration','allowExecuteUpstreamBuildTools'];
    const savedPolicy=policyApi.normalize(project.settings?.nativeModifications);
    const savedTitleId=String(project.settings?.titleId||'').toUpperCase();
    const form='<p>SharpProspero copiará la plantilla UI administrada por Homebrew Studio, escribirá el código y los metadatos del título y ejecutará <code>build/build-app.ps1</code>. Debes autorizar por separado la integración de fuentes/recursos y la ejecución de la herramienta de compilación. La salida anterior se conservará.</p>'+
      '<div class="form-field"><label>TITLE_ID explícito (PPSA12345)</label><input id="sharpBuildTitleId" maxlength="9" value="'+esc(/^PPSA\d{5}$/.test(savedTitleId)?savedTitleId:'')+'" placeholder="PPSA12345" pattern="PPSA[0-9]{5}"><small>No se generará un TITLE_ID aleatorio de forma automática.</small></div>'+
      nativeModificationOptionsMarkup('sharp',requiredKeys)+
      '<pre id="sharpBuildOutput" style="font:10px/1.55 Consolas,monospace;color:#aeb8cf;white-space:pre-wrap;word-break:break-word;max-height:32vh;overflow:auto">Esperando autorización. Aún no se ha creado ni modificado ningún archivo.</pre>';
    openModal('SharpProspero · permisos explícitos de compilación',form,[
      {text:'Cancelar',class:'ghost',action:closeModal},
      {text:'Autorizar y compilar',class:'primary',action:async()=>{
        const titleId=String($('#sharpBuildTitleId')?.value||'').trim().toUpperCase();
        if(!/^PPSA\d{5}$/.test(titleId)||titleId==='PPSA00000'){toast('Introduce un TITLE_ID válido PPSA12345. No se ha modificado nada.','error');return;}
        const nativeModifications=policyApi.normalize(Object.fromEntries(policyApi.entriesForBackend('sharp').map(entry=>[entry.key,$('#nativeMod-'+entry.key)?.checked===true])));
        const missing=policyApi.missingForPermissions(nativeModifications,requiredKeys);
        if(missing.length){toast('Autoriza expresamente: '+missing.map(key=>policyApi.getEntry(key)?.label||key).join(', ')+'. No se ha modificado nada.','warn');return;}
        const output=$('#sharpBuildOutput');
        const buttons=$('#modalActions button');buttons.forEach(button=>button.disabled=true);
        buildBusy=true;$('#buildBtn').disabled=true;$('#buildBtn').textContent='⟳ Compilando';setDock('output');
        let outcome='error';
        try{
          project.settings=project.settings||{};
          project.settings.titleId=titleId;
          project.settings.nativeModifications=nativeModifications;
          project.name=$('#projectName').value.trim()||project.name||'MiHomebrew';
          project.backend='sharp';
          const data=projectPayload();
          data.name=project.name;data.backend='sharp';data.settings=data.settings||{};
          data.settings.titleId=titleId;data.settings.nativeModifications=nativeModifications;
          const code=data.manualCode?$('#codeEditor').value:generateCode();
          if(!code||code.length<20)throw new Error('No se ha generado código C# para SharpProspero.');
          if(output)output.textContent='Permisos validados. Preparando plantilla y metadatos…';
          const result=await api('build',{project:data,programCode:code,backend:'sharp',output:'Package',nativeModifications});
          if(output)output.textContent=(result.message||'Proceso finalizado.')+'\n\n'+(result.output||'Sin salida del SDK.')+(result.artifact?'\n\nArtefacto verificado: '+result.artifact:'');
          if(result.ok){outcome='success';log(result.message||'Compilación SharpProspero completada.');if(result.artifact)log('Artefacto SharpProspero: '+result.artifact);toast('Compilación SharpProspero completada');}
          else{outcome='error';log(result.message||'La compilación SharpProspero ha fallado.','ERROR');toast('Compilación SharpProspero fallida. Revisa la salida.','error');}
          if(result.diagnostics){result.diagnostics.forEach(d=>allDiagnostics.push(d));renderDiagnostics();}
          try{localStorage.setItem(STORAGE_KEY,JSON.stringify(project));savedState();}catch{}
        }catch(error){if(output)output.textContent='No se completó el proceso.\n'+error.message;log('SharpProspero: '+error.message,'ERROR');toast('No se completó SharpProspero.','error');}
        finally{buildBusy=false;$('#buildBtn').disabled=false;$('#buildBtn').innerHTML=outcome==='success'?'<span>✓</span> Completado':outcome==='error'?'<span>!</span> Error · Reintentar':'<span>▶</span> Compilar';buttons.forEach(button=>button.disabled=false);await refreshStatus();}
      }}
    ]);
  }

  async function buildProject(){if(!isProjectOpen){toast('No hay un proyecto visual abierto. Usa Nuevo o Abrir.','warn');return;}if(buildBusy)return;project.name=$('#projectName').value.trim()||'MiHomebrew';project.backend=$('#backendSelect').value;const errors=runAnalysis().filter(d=>d.severity==='error');if(errors.length){setActiveView('diagnostics');toast(`Hay ${errors.length} error(es) que deben corregirse antes de compilar.`,'error');return;}if(!project.components.length&&(project.backend.startsWith('sharp')||['opengl-ui','vulkan-ui'].includes(project.backend))){toast('Añade al menos un componente antes de compilar la pantalla.','warn');return;}if(['opengl-ui','vulkan-ui'].includes(project.backend)){return buildNativeVisualProject();}if(project.backend==='sharp'){return buildSharpWithConsent();}buildBusy=true;$('#buildBtn').disabled=true;$('#buildBtn').textContent='⟳ Compilando';setDock('output');log(`Inicio de compilación real con backend ${project.backend}.`);openModal('Compilación del proyecto',`<p>El IDE guardará el modelo, generará los archivos nativos y ejecutará las herramientas del backend. El contador permanecerá activo durante el proceso; los diagnósticos y la salida se mostrarán al recibir la respuesta real del SDK.</p><div class="build-progress"><span></span></div><pre id="buildProgress" style="font:10px/1.55 Consolas,monospace;color:#aeb8cf;white-space:pre-wrap;word-break:break-word;max-height:42vh;overflow:auto">Preparando proyecto…</pre>`,[{text:'Cerrar ventana',class:'ghost',action:closeModal}]);const buildStarted=Date.now();const buildHeartbeat=setInterval(()=>{const progress=$('#buildProgress');if(progress)progress.textContent='Compilación en ejecución. Tiempo transcurrido: '+Math.floor((Date.now()-buildStarted)/1000)+' s.\nLa salida real y los diagnósticos aparecerán cuando el SDK devuelva el control.';},1000);try{const data=projectPayload();if(!data.manualCode)data.customCode='';const code=data.manualCode?$('#codeEditor').value:generateCode();const result=await api('build',{project:data,programCode:code,backend:data.backend,output:'Package'});$('#buildProgress').textContent=result.output||result.message||'Proceso finalizado.';if(result.ok){log(result.message||'Compilación finalizada correctamente.');if(result.artifact)log(`Artefacto: ${result.artifact}`);toast('Compilación finalizada correctamente');}else{log(result.message||'La compilación ha fallado.','ERROR');toast('La compilación no ha terminado correctamente.','error');}if(result.diagnostics){result.diagnostics.forEach(d=>allDiagnostics.push(d));renderDiagnostics();}}catch(e){$('#buildProgress').textContent=e.message;log('Error al invocar el backend: '+e.message,'ERROR');toast('Error en el proceso de compilación.','error');}finally{clearInterval(buildHeartbeat);buildBusy=false;$('#buildBtn').disabled=false;$('#buildBtn').innerHTML='<span>▶</span> Compilar';await refreshStatus();}}

  function renderAll(){renderSidePanel();renderCanvas();renderInspector();renderHierarchy();renderFlows();renderCode();runAnalysis();setActiveView(activeView);setRightPane(activeRight);if(activeView==='structure')renderStructure();}
  function addAsset(file){if(!file)return;const id='asset-'+Date.now().toString(36);const reader=new FileReader();reader.onload=()=>{const dataUrl=reader.result;const asset={id,name:file.name,fileName:slug(file.name.replace(/\.[^.]+$/,''))+file.name.slice(file.name.lastIndexOf('.')),mime:file.type||'application/octet-stream',size:file.size,dataUrl};snapshot();project.assets.push(asset);if(activeAssetId){const c=component(activeAssetId);if(c)c.assetId=id;activeAssetId=null;}else if(file.type.startsWith('image/')){const c=makeComponent('image');c.label=file.name;c.assetId=id;}changed('Recurso importado');renderAssetList();renderCanvas();renderInspector();toast('Recurso importado: '+file.name);log(`Recurso importado: ${file.name} (${formatBytes(file.size)}).`);};reader.onerror=()=>toast('No se pudo leer el archivo.','error');reader.readAsDataURL(file);}

  function getLastPostBuildPath(){try{return localStorage.getItem('ps5hs:last-built-native-path')||'';}catch{return '';}}
  function setLastPostBuildPath(path){try{if(path)localStorage.setItem('ps5hs:last-built-native-path',path);else localStorage.removeItem('ps5hs:last-built-native-path');}catch{}const pack=$('#postBuildPackBtn');if(pack){pack.disabled=!path;pack.title=path?'Empaquetar el último título nativo compilado':'Compila un título nativo para habilitar esta acción';}}
  setLastPostBuildPath(getLastPostBuildPath());

  // Events: drag/drop, panels, tabs, keyboard shortcuts and project operations.
  $$('.rail-item').forEach(b=>b.addEventListener('click',()=>setActivePanel(b.dataset.panel)));
  $$('.editor-tab').forEach(b=>b.addEventListener('click',()=>setActiveView(b.dataset.view)));
  $('#structureRefreshBtn').onclick=()=>{structureAnalysis=null;renderStructure();toast('Estructura de menús y transiciones actualizada.');};$('#structureSearch').addEventListener('input',renderStructureTree);$$('[data-structure-scope]').forEach(button=>button.addEventListener('click',()=>{structureScope=button.dataset.structureScope;structureSelection=null;renderStructure();}));
  $$('.right-tab').forEach(b=>b.addEventListener('click',()=>setRightPane(b.dataset.right)));
  $$('.dock-tab').forEach(b=>b.addEventListener('click',()=>setDock(b.dataset.dock)));
  $('#newProjectBtn').onclick=newProject;$('#openProjectBtn').onclick=openProject;$('#closeProjectBtn').onclick=closeCurrentProject;$('#saveProjectBtn').onclick=saveProject;$('#exportProjectBtn').onclick=exportProject;$('#buildBtn').onclick=buildProject;$('#postBuildPackBtn').onclick=()=>packageNativeWithUltraPack(getLastPostBuildPath());$('#integrationSettingsBtn')?.addEventListener('click',openIntegrationSettings);$('#previewBtn').onclick=togglePreview;$('#addFlowBtn').onclick=()=>addFlow();$('#recheckBtn').onclick=()=>{runAnalysis();renderDiagnostics();log('Análisis estático ejecutado.');};$('#diagFilter').onchange=renderDiagnostics;
  $('#dismissNotice').onclick=()=>$('#noticeStrip').remove();$('#dockToggle').onclick=()=>{$('.bottom-dock').classList.toggle('collapsed');$('#dockToggle').textContent=$('.bottom-dock').classList.contains('collapsed')?'⌃':'⌄';};$('#gridBtn').onclick=()=>{showGrid=!showGrid;renderCanvas();};$('#isolateLayerBtn').onclick=()=>toggleLayerIsolation();$('#fitBtn').onclick=()=>{zoom=100;fitCanvasToViewport();$('#canvasStage').style.transform='scale(1)';$('#canvasStage').style.transformOrigin='center center';$('#zoomValue').textContent='100%';renderCanvas();};$('#centerBtn').onclick=()=>{screenComponents().forEach(c=>{c.x=clamp(c.x,0,1920-c.w);c.y=clamp(c.y,0,1080-c.h);});renderCanvas();changed('Lienzo comprobado');};
  $('#backendSelect').onchange=()=>{const previous=project.backend;project.backend=$('#backendSelect').value;if(previous!==project.backend&&project.manualCode){project.manualCode=false;project.customCode='';toast('Se regenerará el código para el nuevo backend.','warn');}changed('Backend actualizado');renderCode();runAnalysis();};
  $('#projectName').addEventListener('input',()=>{if(!isProjectOpen){setProjectOpenState(true);project.name=$('#projectName').value;changed('Proyecto visual abierto');return;}project.name=$('#projectName').value;changed('Nombre del proyecto actualizado');});
  $('#projectFileInput').onchange=e=>{if(e.target.files?.[0])importProjectFile(e.target.files[0]);e.target.value='';};$('#assetFileInput').onchange=e=>{addAsset(e.target.files?.[0]);e.target.value='';};
  $('#canvasStage').addEventListener('dragover',e=>{if(e.dataTransfer.types.includes('application/x-ps5-component')){e.preventDefault();$('#canvasStage').classList.add('is-drop-target');}});$('#canvasStage').addEventListener('dragleave',e=>{if(!$('#canvasStage').contains(e.relatedTarget))$('#canvasStage').classList.remove('is-drop-target');});$('#canvasStage').addEventListener('drop',e=>{e.preventDefault();$('#canvasStage').classList.remove('is-drop-target');const type=e.dataTransfer.getData('application/x-ps5-component');if(!type)return;const r=$('#canvasStage').getBoundingClientRect();const x=(e.clientX-r.left)/r.width*1920,y=(e.clientY-r.top)/r.height*1080;makeComponent(type,x,y);});$('#canvasStage').addEventListener('click',e=>{if(e.target===$('#canvasStage')||e.target===$('#canvasElements')){if(!isPreview)selectComponent(null);}});
  $('#regenerateCodeBtn').onclick=()=>{project.manualCode=false;project.customCode='';renderCode();changed('Código regenerado');toast('Código regenerado desde el modelo visual');};$('#copyCodeBtn').onclick=async()=>{try{await navigator.clipboard.writeText($('#codeEditor').value);toast('Código copiado al portapapeles');}catch{ $('#codeEditor').select();document.execCommand('copy');toast('Código copiado');}};
  $('#codeEditor').addEventListener('input',()=>{project.manualCode=true;project.customCode=$('#codeEditor').value;$('#codeStatus').textContent='Código fuente editado manualmente';updateGutter();changed('Código editado');});$('#codeEditor').addEventListener('scroll',()=>{$('#codeGutter').scrollTop=$('#codeEditor').scrollTop;});
  window.addEventListener('keydown',e=>{if(e.ctrlKey&&e.key.toLowerCase()==='s'){e.preventDefault();saveProject();}if(e.key==='Escape'&&isPreview)stopPreview();if(e.key==='Delete'&&!isPreview&&!['INPUT','TEXTAREA','SELECT'].includes(document.activeElement.tagName)&&selectedId)deleteComponent(selectedId);if(!isPreview&&selectedId&&!['INPUT','TEXTAREA','SELECT'].includes(document.activeElement.tagName)&&['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)){e.preventDefault();const c=component(selectedId);if(c){snapshot();const step=e.shiftKey?10:1;if(e.key==='ArrowLeft')c.x=clamp(c.x-step,0,1920-c.w);if(e.key==='ArrowRight')c.x=clamp(c.x+step,0,1920-c.w);if(e.key==='ArrowUp')c.y=clamp(c.y-step,0,1080-c.h);if(e.key==='ArrowDown')c.y=clamp(c.y+step,0,1080-c.h);changed('Posición actualizada');renderCanvas();renderInspector();}}});
  // Initial state: restore autosaved design only if it is a Studio project. No mock SDK/toolchain state is shown.
  try{const stored=localStorage.getItem(STORAGE_KEY);if(stored){const parsed=JSON.parse(stored);if(parsed.format==='ps5hs-closed'&&parsed.closed){project=freshProject();project.name='';isProjectOpen=false;$('#projectName').value='';$('#projectName').placeholder='Sin proyecto abierto';setProjectOpenState(false);}else if(parsed.format==='ps5vproj'){project=Object.assign(freshProject(),parsed);isProjectOpen=true;setProjectOpenState(true);$('#projectName').value=project.name;$('#projectName').placeholder='Nombre del proyecto';$('#backendSelect').value=project.backend;savedState();}}}catch{}
  // Browser recovery autosave is independent from explicit project saving.
  setInterval(()=>{if(!isProjectOpen)return;try{localStorage.setItem(STORAGE_KEY,JSON.stringify(project));}catch{}},12000);
  const stageWrap=$('.canvas-stage-wrap');if(stageWrap&&window.ResizeObserver){const stageObserver=new ResizeObserver(()=>{if(fitCanvasToViewport()&&activeView==='design')renderCanvas();});stageObserver.observe(stageWrap);}window.addEventListener('resize',()=>{if(fitCanvasToViewport()&&activeView==='design')renderCanvas();});
  setProjectOpenState(isProjectOpen);renderAll();if(!isProjectOpen){$('#dirtyPill').textContent='SIN PROYECTO';$('#canvasState').textContent='No hay proyecto visual abierto. Las carpetas nativas y sus artefactos se conservan.';}log('PS5 Homebrew Studio v1.1.9 inicializado.');log('Editor visual: lienzo adaptable, capas aislables, pantallas múltiples, inspector, flujos y código generado.');log('Backend SharpProspero: C# / NativeAOT. Backend OpenGL/Vulkan: generación C++20 desde el modelo visual y compilación upstream.');log('La compilación requiere dependencias reales; solo se informa éxito cuando el proceso termina correctamente y se verifica el artefacto.');
  refreshStatus();
})();
