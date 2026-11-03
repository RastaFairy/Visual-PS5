'use strict';
/* PS5HS i18n (1.1.59): diccionario estático por clave (UI fija) + traducción profunda por
 * texto original (mensajes de diagnósticos, consola, builds). El idioma persiste en
 * localStorage y el HTML estático se localiza mediante data-i18n / data-i18n-ph. */
(() => {
  const LANG_KEY = 'ps5hs-lang-v1';
  const STRINGS = {
    es: {
      'btn.new': 'Nuevo', 'btn.open': 'Abrir', 'btn.save': 'Guardar', 'btn.closeProject': 'Cerrar proyecto', 'btn.exportProject': 'Exportar proyecto', 'btn.tools': 'Herramientas', 'btn.pack': 'Empaquetar', 'btn.build': 'Compilar', 'btn.preview': 'Vista previa',
      'rail.blocks': 'Bloques', 'rail.logic': 'Lógica', 'rail.systems': 'Sistemas', 'rail.assets': 'Recursos', 'rail.files': 'Archivos', 'rail.projects': 'Proyectos', 'rail.sdks': 'SDKs', 'rail.docs': 'Docs',
      'tab.design': 'Diseño', 'tab.structure': 'Estructura', 'tab.logic': 'Flujos', 'tab.game': 'Juego 3D', 'tab.compute': 'Vulkan Compute', 'tab.code': 'Código', 'tab.diagnostics': 'Diagnósticos', 'tab.console': 'Consola PS5', 'tab.inspector': 'Inspector', 'tab.hierarchy': 'Jerarquía',
      'label.target': 'DESTINO', 'dock.output': 'Salida', 'dock.problems': 'Problemas', 'dock.environment': 'Entorno', 'dock.exportLog': 'Exportar log',
      'crumb.project': 'Proyecto', 'crumb.console': 'Consola PS5',
      'console.disconnected': 'Sin conectar', 'console.clear': 'Limpiar', 'console.connection': 'CONEXIÓN', 'console.hostLabel': 'IP de la consola', 'console.autoKlog': 'Capturar klog automáticamente (klogsrv · 3232)', 'console.test': 'Probar conexión', 'console.stop': 'Detener captura', 'console.hint': 'Requiere klogsrv/ftpsrv activos en la consola. El IDE solo habla con esta IP y nunca expone tu equipo a la red.', 'console.ftpHeading': 'DESPLIEGUE FTP', 'console.portLabel': 'Puerto FTP', 'console.folderLabel': 'Carpeta local del título', 'console.remoteLabel': 'Ruta remota', 'console.userLabel': 'Usuario FTP', 'console.userHint': '(vacío = anónimo)', 'console.passLabel': 'Contraseña', 'console.deploy': 'Desplegar título', 'console.ftpNote': 'Sube eboot.bin, sce_sys y sce_module con --ftp-create-dirs al puerto configurado. Registra la carpeta con ShadowMountPlus si aún no aparece en el inicio.', 'console.elfHeading': 'ELF LOADER · 9021', 'console.elfLabel': 'ELF local', 'console.sendElf': 'Enviar payload', 'console.elfNote': 'Envía el ELF al loader de etaHEN/kstuff. Los títulos de ps5link se lanzan desde la pantalla de inicio, no desde aquí.', 'console.filterPh': 'Filtrar líneas (EXEC, NoDraw, gc_gfx, 0x80…)', 'console.autoscroll': 'Autoscroll', 'console.download': 'Descargar .txt',
      'panel.components.title': 'Componentes', 'panel.components.sub': 'Arrastra elementos al lienzo', 'panel.logic.title': 'Lógica visual', 'panel.logic.sub': 'Eventos y comportamientos', 'panel.systems.title': 'Subsistemas', 'panel.systems.sub': 'Capacidades del entorno', 'panel.assets.title': 'Recursos', 'panel.assets.sub': 'Archivos del proyecto', 'panel.files.title': 'Archivos del proyecto', 'panel.files.sub': 'Explora y edita los archivos reales en disco', 'panel.sdk.title': 'SDK y toolchains', 'panel.sdk.sub': 'Backends comunitarios', 'panel.templates.title': 'Proyectos y motores', 'panel.templates.sub': 'Repositorios reales de PS5', 'panel.docs.title': 'Documentación técnica', 'panel.docs.sub': 'Capacidades y límites del IDE'
    },
    en: {
      'btn.new': 'New', 'btn.open': 'Open', 'btn.save': 'Save', 'btn.closeProject': 'Close project', 'btn.exportProject': 'Export project', 'btn.tools': 'Tools', 'btn.pack': 'Package', 'btn.build': 'Build', 'btn.preview': 'Preview',
      'rail.blocks': 'Blocks', 'rail.logic': 'Logic', 'rail.systems': 'Systems', 'rail.assets': 'Assets', 'rail.files': 'Files', 'rail.projects': 'Projects', 'rail.sdks': 'SDKs', 'rail.docs': 'Docs',
      'tab.design': 'Design', 'tab.structure': 'Structure', 'tab.logic': 'Flows', 'tab.game': '3D Game', 'tab.compute': 'Vulkan Compute', 'tab.code': 'Code', 'tab.diagnostics': 'Diagnostics', 'tab.console': 'PS5 Console', 'tab.inspector': 'Inspector', 'tab.hierarchy': 'Hierarchy',
      'label.target': 'TARGET', 'dock.output': 'Output', 'dock.problems': 'Problems', 'dock.environment': 'Environment', 'dock.exportLog': 'Export log',
      'crumb.project': 'Project', 'crumb.console': 'PS5 Console',
      'console.disconnected': 'Not connected', 'console.clear': 'Clear', 'console.connection': 'CONNECTION', 'console.hostLabel': 'Console IP', 'console.autoKlog': 'Capture klog automatically (klogsrv · 3232)', 'console.test': 'Test connection', 'console.stop': 'Stop capture', 'console.hint': 'Requires klogsrv/ftpsrv running on the console. The IDE only talks to this IP and never exposes your computer to the network.', 'console.ftpHeading': 'FTP DEPLOY', 'console.portLabel': 'FTP port', 'console.folderLabel': 'Local title folder', 'console.remoteLabel': 'Remote path', 'console.userLabel': 'FTP user', 'console.userHint': '(empty = anonymous)', 'console.passLabel': 'Password', 'console.deploy': 'Deploy title', 'console.ftpNote': 'Uploads eboot.bin, sce_sys and sce_module with --ftp-create-dirs to the configured port. Register the folder with ShadowMountPlus if it does not show up on the home screen yet.', 'console.elfHeading': 'ELF LOADER · 9021', 'console.elfLabel': 'Local ELF', 'console.sendElf': 'Send payload', 'console.elfNote': 'Sends the ELF to the etaHEN/kstuff loader. ps5link titles launch from the home screen, not from here.', 'console.filterPh': 'Filter lines (EXEC, NoDraw, gc_gfx, 0x80…)', 'console.autoscroll': 'Autoscroll', 'console.download': 'Download .txt',
      'panel.components.title': 'Components', 'panel.components.sub': 'Drag elements onto the canvas', 'panel.logic.title': 'Visual logic', 'panel.logic.sub': 'Events and behaviors', 'panel.systems.title': 'Subsystems', 'panel.systems.sub': 'Environment capabilities', 'panel.assets.title': 'Assets', 'panel.assets.sub': 'Project files', 'panel.files.title': 'Project files', 'panel.files.sub': 'Browse and edit the real files on disk', 'panel.sdk.title': 'SDKs and toolchains', 'panel.sdk.sub': 'Community backends', 'panel.templates.title': 'Projects and engines', 'panel.templates.sub': 'Real PS5 repositories', 'panel.docs.title': 'Technical documentation', 'panel.docs.sub': 'Capabilities and IDE limits'
    }
  };

  /* Traducción profunda: clave = texto original en español tal como lo emite el código,
   * valor = texto en inglés. Los textos ausentes se muestran en español (fallback). */
  const DEEP = {
    'Cambios pendientes': 'Pending changes',
    'Nombre del proyecto actualizado': 'Project name updated',
    'Proyecto visual abierto': 'Visual project opened',
    'No se puede guardar mientras se compila.': 'Cannot save while a build is running.',
    'No se puede abrir mientras se compila': 'Cannot open projects while a build is running',
    'No se puede cambiar de proyecto mientras se compila.': 'Cannot switch projects while a build is running.',
    'No se puede compilar mientras se compila.': 'Cannot build while a build is running.',
    'Backend actualizado': 'Backend updated',
    'Se regenerará el código para el nuevo backend.': 'The code will be regenerated for the new backend.',
    'Código editado': 'Code edited',
    'Código regenerado desde el modelo visual': 'Code regenerated from the visual model',
    'Fuente regenerado desde Juego 3D y Flujos': 'Source regenerated from 3D Game and Flows',
    'Código copiado al portapapeles': 'Code copied to the clipboard',
    'Proyecto cargado': 'Project loaded',
    'Proyecto cargado; nombre antiguo normalizado.': 'Project loaded; legacy name normalized.',
    'Proyecto guardado': 'Project saved',
    'Snapshot restaurado en el editor. Guárdalo para hacerlo definitivo.': 'Snapshot restored in the editor. Save it to make it permanent.',
    'Indica la IP de la consola y la carpeta local del título.': 'Enter the console IP and the local title folder.',
    'El puerto FTP debe estar entre 1 y 65535.': 'The FTP port must be between 1 and 65535.',
    'Desplegando…': 'Deploying…',
    'Título desplegado': 'Title deployed',
    'Regístralo con ShadowMountPlus y arranca desde el inicio.': 'Register it with ShadowMountPlus and launch from the home screen.',
    'Despliegue FTP completado: ': 'FTP deploy completed: ',
    'Despliegue FTP fallido: ': 'FTP deploy failed: ',
    'Despliegue FTP: ': 'FTP deploy: ',
    'ELF enviado (': 'ELF sent (',
    ' bytes)': ' bytes)',
    'Payload enviado al elfldr.': 'Payload sent to elfldr.',
    'Envío ELF fallido: ': 'ELF upload failed: ',
    'Error FTP: ': 'FTP error: ',
    'Error elfldr: ': 'elfldr error: ',
    'Falta la IP de la consola': 'Console IP is missing',
    'Conectado a ': 'Connected to ',
    ' · ': ' · ',
    ' líneas': ' lines',
    'Error: ': 'Error: ',
    'Captura klog detenida por el usuario.': 'Klog capture stopped by the user.',
    'Captura detenida': 'Capture stopped',
    'No hay líneas de klog que descargar todavía.': 'No klog lines to download yet.',
    'Registro klog descargado.': 'Klog log downloaded.',
    'Entorno actualizado.': 'Environment refreshed.',
    'No se pudo consultar el estado del entorno: ': 'Could not query the environment state: ',
    'Diagnósticos del compilador: ': 'Compiler diagnostics: ',
    ' entrada(s) añadidas al panel.': ' entry(ies) added to the panel.',
    'Archivo guardado en disco': 'File saved to disk',
    'Archivo guardado: ': 'File saved: ',
    'No se pudo guardar el archivo: ': 'Could not save the file: ',
    'Abre o crea un proyecto para editar sus archivos.': 'Open or create a project to edit its files.',
    'Creado: ': 'Created: ',
    'Archivo creado en el proyecto: ': 'File created in project: ',
    'Carpeta creado en el proyecto: ': 'Folder created in project: ',
    'No se pudo crear: ': 'Could not create: ',
    'Renombrado a ': 'Renamed to ',
    'No se pudo renombrar: ': 'Could not rename: ',
    'Eliminado: ': 'Deleted: ',
    'Archivo eliminado del proyecto: ': 'File deleted from project: ',
    'No se pudo eliminar: ': 'Could not delete: ',
    'Se reemplazaron todas las coincidencias.': 'All matches were replaced.',
    'No hubo coincidencias que reemplazar.': 'No matches to replace.',
    'No hay líneas de klog que descargar.': 'No klog lines to download.',
    /* Diagnósticos (runAnalysis) */
    'Lienzo vacío': 'Empty canvas',
    'Añade componentes para empezar a construir la interfaz.': 'Add components to start building the interface.',
    'Navegación sin cambio de pantalla': 'Navigation without a screen change',
    'Acción de flujo no implementada': 'Unimplemented flow action',
    'Opacidad por componente no traducida': 'Per-component opacity not translated',
    'Colisión de identificadores C#': 'C# identifier collision',
    'Componentes fuera de la pantalla compilada': 'Components outside the compiled screen',
    'Disparador de otra pantalla': 'Trigger from another screen',
    'Navegación entre pantallas aún no compilable': 'Cross-screen navigation not yet compilable',
    'Color de destino inválido': 'Invalid target color',
    'Recurso de imagen no compatible con el backend nativo': 'Image asset not compatible with the native backend',
    'Acción dirigida a otra pantalla': 'Action targeting another screen',
    'Teclado en pantalla integrado': 'Built-in on-screen keyboard',
    'SharpProspero no instalado': 'SharpProspero not installed',
    '.NET 10 no detectado': '.NET 10 not detected',
    'WSL no detectado': 'WSL not detected',
    'SDK payload no validado': 'Payload SDK not validated',
    'PS5 Payload SDK disponible': 'PS5 Payload SDK available',
    'Backend no instalado': 'Backend not installed',
    'El backend elegido no es un renderer de UI': 'The chosen backend is not a UI renderer',
    'Motor visual AGC desactivado': 'AGC visual engine disabled',
    'Escena de juego incompleta': 'Incomplete game scene',
    'Punto de inicio no asignado': 'Spawn point not assigned',
    'Meta no asignada': 'Goal not assigned',
    'Inicio sin colisión': 'Spawn without collision',
    'Colisión crítica desactivada': 'Critical collision disabled',
    'Objetivo fuera de alcance': 'Target out of reach',
    'La escena no protege el inicio': 'The scene does not protect the spawn',
    'El motor visual contiene llamadas C manuales': 'The visual engine contains manual C calls',
    'Interfaz de juego vacía': 'Empty game interface',
    'Motor visual AGC activado': 'AGC visual engine enabled',
    'Código AGC manual': 'Manual AGC code',
    'El proyecto contiene controles de interfaz': 'The project contains interface controls',
    'Tema nativo incompleto': 'Incomplete native theme',
    'Color de texto inválido': 'Invalid text color',
    'Color de fondo inválido': 'Invalid background color',
    'Paso numérico inválido': 'Invalid numeric step',
    'Generación nativa C++20 activada': 'Native C++20 generation enabled',
    'Texturas RGBA preparadas para runtime nativo': 'RGBA textures ready for native runtime',
    'Texturas OpenGL preparadas': 'OpenGL textures ready',
    'Imagen nativa sin recurso válido': 'Native image without a valid asset',
    'Límite de texturas nativas': 'Native texture limit',
    'Teclado nativo en pantalla': 'Native on-screen keyboard',
    'Destino de navegación no definido': 'Navigation target not defined',
    'Payload no equivale a una aplicación visual': 'A payload is not a visual application',
    'Un payload no compila el lienzo visual': 'A payload does not compile the visual canvas',
    'Los flujos visuales no se incluyen en un payload': 'Visual flows are not included in a payload',
    'Los recursos del editor no se enlazan al payload': 'Editor assets are not linked into the payload',
    'Backend no validado para compilación offline': 'Backend not validated for offline builds',
    'Imágenes no soportadas por el puente AGC': 'Images not supported by the AGC bridge',
    'La escena 3D supera el presupuesto de vértices AGC': 'The 3D scene exceeds the AGC vertex budget',
    'La escena 3D se acerca al límite de vértices AGC': 'The 3D scene is approaching the AGC vertex budget',
    'La interfaz supera el presupuesto de vértices UI': 'The interface exceeds the UI vertex budget',
    'La interfaz se acerca al límite de vértices UI': 'The interface is approaching the UI vertex budget',
    'Presupuesto de vértices AGC': 'AGC vertex budget',
    'Escena de juego': 'Game scene',
    'Diseño': 'Design',
    'Escena de juego · Activar escena': 'Game scene · Enable scene'
  };

  let lang = 'es';
  try { lang = localStorage.getItem(LANG_KEY) || 'es'; } catch { lang = 'es'; }
  if (lang !== 'en' && lang !== 'es') lang = 'es';

  const t = (key) => (STRINGS[lang] || STRINGS.es)[key] ?? STRINGS.es[key] ?? key;
  /* tr(): traducción profunda por texto original (diagnósticos, consola, builds). */
  const tr = (text) => {
    const s = String(text ?? '');
    if (lang !== 'en') return s;
    if (DEEP[s]) return DEEP[s];
    /* Prefijos dinámicos: 'Conectado a X · N líneas', códigos traducidos del klog, etc. */
    for (const [es, en] of Object.entries(DEEP)) {
      if (es.endsWith(': ') && s.startsWith(es)) return en + s.slice(es.length);
      if (es.endsWith(' (') && s.startsWith(es)) return en + s.slice(es.length);
    }
    return s;
  };

  function applyStaticI18n() {
    document.documentElement.lang = lang === 'en' ? 'en-GB' : 'es-ES';
    document.querySelectorAll('[data-i18n]').forEach(el => {
      const text = t(el.dataset.i18n);
      const first = el.firstChild;
      if (first && first.nodeType === Node.TEXT_NODE && !first.textContent.includes('▶')) first.textContent = text; else el.textContent = text;
    });
    document.querySelectorAll('[data-i18n-ph]').forEach(el => { el.placeholder = t(el.dataset.i18nPh); });
    const sel = document.querySelector('#uiLangSelect');
    if (sel && sel.value !== lang) sel.value = lang;
  }

  let changeHandler = null;
  function setLang(next) {
    if (next !== 'en' && next !== 'es') return;
    lang = next;
    try { localStorage.setItem(LANG_KEY, lang); } catch {}
    applyStaticI18n();
    if (changeHandler) changeHandler(lang);
  }

  window.PS5HSI18N = {
    t,
    tr,
    applyStaticI18n,
    setLang,
    get lang() { return lang; },
    set onLanguageChange(fn) { changeHandler = typeof fn === 'function' ? fn : null; }
  };
  const sel = document.querySelector('#uiLangSelect');
  if (sel) {
    sel.value = lang;
    sel.addEventListener('change', () => setLang(sel.value));
  }
  applyStaticI18n();
})();
