'use strict';
(function attachPS5HSProjectContracts(root) {
  const NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$/;
  const TITLE_ID_PATTERN = /^PPSA\d{5}$/;
  const MIN_CANVAS_WIDTH = 640;
  const MIN_CANVAS_HEIGHT = 360;
  const MAX_CANVAS_WIDTH = 7680;
  const MAX_CANVAS_HEIGHT = 4320;

  function normalizeTitleId(value) {
    return String(value ?? '').trim().toUpperCase();
  }
  function isValidTitleId(value) {
    const id = normalizeTitleId(value);
    return TITLE_ID_PATTERN.test(id) && id !== 'PPSA00000';
  }
  function isValidProjectName(value) {
    return NAME_PATTERN.test(String(value ?? '').trim());
  }
  function normalizeLegacyProjectName(value, sourceName) {
    const normalizeCandidate = candidate => {
      let text = String(candidate ?? '').trim();
      if (!text) return '';
      text = text.normalize('NFKD').replace(/[\u0300-\u036f]/g, '');
      text = text.replace(/[^A-Za-z0-9 ._-]+/g, '-').replace(/\s+/g, ' ');
      text = text.replace(/^[^A-Za-z0-9]+/, '').replace(/[ ._-]+$/, '').trim();
      return text;
    };
    const migratedName = normalizeCandidate(value);
    if (isValidProjectName(migratedName)) return migratedName;
    const rawSource = String(sourceName ?? '').trim().split(/[\\/]/).pop() || '';
    const sourceBase = rawSource.replace(/\.ps5vproj$/i, '');
    const recoveredFromFile = normalizeCandidate(sourceBase);
    if (isValidProjectName(recoveredFromFile)) return recoveredFromFile;
    const shortened = migratedName.slice(0, 40).replace(/[ ._-]+$/, '').trim();
    return isValidProjectName(shortened) ? shortened : '';
  }
  function normalizeAssetFilename(originalName) {
    const raw = String(originalName ?? '').trim().split(/[\\/]/).pop() || '';
    if (!raw) throw new Error('El recurso no tiene un nombre de archivo válido.');
    const dot = raw.lastIndexOf('.');
    const candidateExtension = dot > 0 ? raw.slice(dot) : '';
    const hasExtension = /^\.[A-Za-z0-9]{1,12}$/.test(candidateExtension);
    const base = hasExtension ? raw.slice(0, dot) : raw;
    const extension = hasExtension ? candidateExtension.toLowerCase() : '';
    const safeBase = base.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-zA-Z0-9_-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 100);
    if (!safeBase) throw new Error('El nombre del recurso no contiene caracteres de archivo compatibles después de normalizarlo.');
    return safeBase + extension;
  }
  function isRecord(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
  }
  function migrateLegacyScreenContext(value) {
    const migrated = { ...value };
    const components = Array.isArray(value.components) ? value.components.map(component => isRecord(component) ? { ...component } : component) : [];
    const hadScreens = Array.isArray(value.screens) && value.screens.length > 0;
    let screens = Array.isArray(value.screens) ? value.screens.map(screen => isRecord(screen) ? { ...screen } : screen) : [];
    if (Object.hasOwn(value, 'currentScreen') && typeof value.currentScreen !== 'string') throw new Error('currentScreen debe ser un identificador de pantalla explícito.');
    let currentScreen = String(value.currentScreen || '').trim();
    const ids = new Set(screens.filter(isRecord).map(screen => typeof screen.id === 'string' ? screen.id : '').filter(Boolean));
    if (!hadScreens) {
      const referenced = [...new Set(components.filter(isRecord).map(component => component.screenId).filter(id => typeof id === 'string' && id.trim()).map(id => id.trim()))];
      if (referenced.length) {
        screens = referenced.map(id => ({ id, name: id === 'screen-main' ? 'Pantalla principal' : id }));
        referenced.forEach(id => ids.add(id));
      } else if (components.length || currentScreen) {
        const id = currentScreen || 'screen-main';
        screens = [{ id, name: id === 'screen-main' ? 'Pantalla principal' : id }];
        ids.add(id);
      } else {
        throw new Error('El proyecto legado no declara una pantalla ni contiene componentes con los que reconstruir su contexto. No se creará una pantalla vacía de sustitución.');
      }
      if (currentScreen && !ids.has(currentScreen)) throw new Error(`El proyecto legado declara una pantalla activa que no existe: ${currentScreen}.`);
      if (!currentScreen) {
        if (screens.length > 1) throw new Error('El proyecto legado tiene varias pantallas pero no declara cuál estaba activa. Selecciona una pantalla en la versión que guardó el proyecto o corrige el archivo.');
        currentScreen = screens[0].id;
      }
      for (const component of components) {
        if (!isRecord(component)) continue;
        if (typeof component.screenId !== 'string' || !component.screenId.trim()) {
          if (screens.length !== 1) throw new Error(`No puede migrarse el componente ${String(component.id || '(sin ID)')}: no tiene pantalla y hay varios contextos posibles.`);
          component.screenId = screens[0].id;
        }
      }
    } else {
      if (!currentScreen) {
        if (screens.length !== 1) throw new Error('El proyecto legado tiene varias pantallas pero no declara currentScreen; no se elegirá una al azar.');
        currentScreen = String(screens[0]?.id || '');
      }
      for (const component of components) {
        if (!isRecord(component)) continue;
        if (typeof component.screenId !== 'string' || !component.screenId.trim()) {
          if (ids.has(currentScreen)) component.screenId = currentScreen;
          else if (screens.length === 1 && typeof screens[0]?.id === 'string') component.screenId = screens[0].id;
          else throw new Error(`No puede migrarse el componente ${String(component.id || '(sin ID)')}: no tiene pantalla explícita y el proyecto es ambiguo.`);
        }
      }
    }
    migrated.components = components;
    migrated.screens = screens;
    migrated.currentScreen = currentScreen;
    return migrated;
  }
  function normalizeProjectModel(value, defaults, validComponentTypes, validBackends, sourceName) {
    if (!isRecord(value)) throw new Error('El proyecto debe ser un objeto JSON.');
    if (value.format && value.format !== 'ps5vproj') throw new Error('Formato de proyecto no compatible.');
    const legacyProject = value.format === 'ps5vproj' && (!Object.hasOwn(value, 'formatVersion') || value.formatVersion === 1);
    if (legacyProject) value = migrateLegacyScreenContext(value);
    if (value.format === 'ps5vproj' && value.formatVersion === 2) {
      const requiredFields = ['formatVersion','name','backend','resolution','theme','components','flows','assets','fontAssetId','screens','currentScreen','settings','customCode','manualCode'];
      const missing = requiredFields.filter(key => !Object.hasOwn(value, key));
      if (missing.length) throw new Error(`El proyecto v2 está incompleto; faltan campos requeridos: ${missing.join(', ')}. No se completarán silenciosamente.`);
    }
    const project = { ...defaults, ...value };
    for (const key of ['components', 'flows', 'assets', 'screens']) {
      if (Object.hasOwn(value, key) && !Array.isArray(value[key])) throw new Error(`El campo ${key} debe ser una lista.`);
      if (!Array.isArray(project[key])) project[key] = [];
    }
    for (const key of ['theme', 'resolution', 'settings']) {
      if (Object.hasOwn(value, key) && !isRecord(value[key])) throw new Error(`El campo ${key} debe ser un objeto.`);
      project[key] = { ...(isRecord(defaults[key]) ? defaults[key] : {}), ...(isRecord(value[key]) ? value[key] : {}) };
    }
    const gameDefaults = isRecord(defaults.gameScene) ? defaults.gameScene : {
      schemaVersion: 1, enabled: false,
      physics: { moveSpeed: 5.55, acceleration: 9, jumpSpeed: 9.3, gravity: 21, fallLimit: -8, playerHalfHeight: 0.72 },
      player: { spawnPlatformId: '' },
      camera: { followDistance: 8.7, followHeight: 3.4, lookAhead: 3.3 },
      appearance: { skyColor: '#100B20', playerColor: '#7D89FF', playerAccentColor: '#FFD5A5', collectibleColor: '#67F3E8', goalColor: '#FF9A6B', requireCollectibles: true },
      platforms: [], objects: []
    };
    if (Object.hasOwn(value, 'gameScene') && !isRecord(value.gameScene)) throw new Error('gameScene debe ser un objeto de escena 3D.');
    const incomingGame = isRecord(value.gameScene) ? value.gameScene : {};
    if (Object.hasOwn(incomingGame, 'enabled') && typeof incomingGame.enabled !== 'boolean') throw new Error('gameScene.enabled debe ser booleano.');
    if (Object.hasOwn(incomingGame, 'physics') && !isRecord(incomingGame.physics)) throw new Error('gameScene.physics debe ser un objeto.');
    if (Object.hasOwn(incomingGame, 'player') && !isRecord(incomingGame.player)) throw new Error('gameScene.player debe ser un objeto.');
    if (Object.hasOwn(incomingGame, 'camera') && !isRecord(incomingGame.camera)) throw new Error('gameScene.camera debe ser un objeto.');
    if (Object.hasOwn(incomingGame, 'appearance') && !isRecord(incomingGame.appearance)) throw new Error('gameScene.appearance debe ser un objeto.');
    if (Object.hasOwn(incomingGame, 'platforms') && !Array.isArray(incomingGame.platforms)) throw new Error('gameScene.platforms debe ser una lista.');
    if (Object.hasOwn(incomingGame, 'objects') && !Array.isArray(incomingGame.objects)) throw new Error('gameScene.objects debe ser una lista de objetos 3D.');
    project.gameScene = {
      ...gameDefaults,
      ...incomingGame,
      physics: { ...(isRecord(gameDefaults.physics) ? gameDefaults.physics : {}), ...(isRecord(incomingGame.physics) ? incomingGame.physics : {}) },
      player: { ...(isRecord(gameDefaults.player) ? gameDefaults.player : {}), ...(isRecord(incomingGame.player) ? incomingGame.player : {}) },
      camera: { ...(isRecord(gameDefaults.camera) ? gameDefaults.camera : {}), ...(isRecord(incomingGame.camera) ? incomingGame.camera : {}) },
      appearance: { ...(isRecord(gameDefaults.appearance) ? gameDefaults.appearance : {}), ...(isRecord(incomingGame.appearance) ? incomingGame.appearance : {}) },
      platforms: Array.isArray(incomingGame.platforms) ? incomingGame.platforms.map(platform => isRecord(platform) ? { ...platform } : platform) : Array.isArray(gameDefaults.platforms) ? gameDefaults.platforms.map(platform => ({ ...platform })) : [],
      objects: Array.isArray(incomingGame.objects) ? incomingGame.objects.map(object => isRecord(object) ? { ...object } : object) : Array.isArray(gameDefaults.objects) ? gameDefaults.objects.map(object => ({ ...object })) : []
    };
    if (project.gameScene.schemaVersion !== 1) throw new Error(`Versión de escena de juego no compatible: ${String(project.gameScene.schemaVersion)}.`);
    if (!Array.isArray(project.gameScene.platforms) || project.gameScene.platforms.length > 128) throw new Error('La escena admite entre 0 y 128 bloques de plataforma.');
    const platformIds = new Set();
    project.gameScene.platforms = project.gameScene.platforms.map((platform, index) => {
      if (!isRecord(platform)) throw new Error(`El bloque de plataforma ${index + 1} no es válido.`);
      const id = String(platform.id ?? '').trim();
      if (!/^[A-Za-z_][A-Za-z0-9_-]{0,63}$/.test(id) || platformIds.has(id)) throw new Error(`El bloque de plataforma ${index + 1} necesita un identificador seguro y único.`);
      platformIds.add(id);
      for (const key of ['x','height','z','halfWidth','halfDepth']) {
        const n = platform[key];
        if (typeof n !== 'number' || !Number.isFinite(n) || !Number.isFinite(Math.fround(n))) throw new Error(`La plataforma ${id} necesita un valor finito explícito en ${key}.`);
      }
      if (Math.abs(platform.x) > 500 || Math.abs(platform.z) > 500 || Math.abs(platform.height) > 100 || platform.halfWidth < 0.25 || platform.halfWidth > 20 || platform.halfDepth < 0.25 || platform.halfDepth > 20) throw new Error(`La geometría de la plataforma ${id} queda fuera de los límites del editor.`);
      if (typeof platform.checkpoint !== 'boolean' || typeof platform.collectible !== 'boolean' || typeof platform.goal !== 'boolean') throw new Error(`La plataforma ${id} necesita estados explícitos de checkpoint, cristal y meta.`);
      if (typeof platform.color !== 'string' || !/^#[0-9a-f]{6}$/i.test(platform.color)) throw new Error(`La plataforma ${id} necesita un color #RRGGBB válido.`);
      const collisionEnabled = platform.collisionEnabled === undefined ? true : platform.collisionEnabled;
      if (typeof collisionEnabled !== 'boolean') throw new Error('La plataforma ' + id + ' necesita un estado de colisión booleano.');
      const collisionHalfWidth = platform.collisionHalfWidth === undefined ? platform.halfWidth + 0.24 : platform.collisionHalfWidth;
      const collisionHalfHeight = platform.collisionHalfHeight === undefined ? 0.45 : platform.collisionHalfHeight;
      const collisionHalfDepth = platform.collisionHalfDepth === undefined ? platform.halfDepth + 0.24 : platform.collisionHalfDepth;
      const collisionOffsetY = platform.collisionOffsetY === undefined ? 0 : platform.collisionOffsetY;
      for (const [key, n] of [['collisionHalfWidth',collisionHalfWidth],['collisionHalfHeight',collisionHalfHeight],['collisionHalfDepth',collisionHalfDepth],['collisionOffsetY',collisionOffsetY]]) {
        if (typeof n !== 'number' || !Number.isFinite(n) || !Number.isFinite(Math.fround(n))) throw new Error('La plataforma ' + id + ' necesita un valor finito en ' + key + '.');
      }
      if (collisionHalfWidth < 0.1 || collisionHalfWidth > 20.5 || collisionHalfHeight < 0.1 || collisionHalfHeight > 20.5 || collisionHalfDepth < 0.1 || collisionHalfDepth > 20.5 || collisionOffsetY < -2 || collisionOffsetY > 2) throw new Error('La caja de colisión de ' + id + ' está fuera de los límites permitidos.');
      if (!collisionEnabled && (platform.checkpoint || platform.collectible || platform.goal)) throw new Error('La plataforma ' + id + ' no puede tener un cristal, checkpoint o meta si su colisión está desactivada.');
      return { ...platform, id, label: String(platform.label ?? id), collisionEnabled, collisionHalfWidth, collisionHalfHeight, collisionHalfDepth, collisionOffsetY };
    });
    if (!Array.isArray(project.gameScene.objects) || project.gameScene.objects.length > 128) throw new Error('La escena admite hasta 128 objetos 3D adicionales.');
    project.gameScene.objects = project.gameScene.objects.map((object, index) => {
      if (!isRecord(object)) throw new Error(`El objeto 3D ${index + 1} no es válido.`);
      const id = String(object.id ?? '').trim();
      if (!/^[A-Za-z_][A-Za-z0-9_-]{0,63}$/.test(id) || platformIds.has(id)) throw new Error(`El objeto 3D ${index + 1} necesita un identificador seguro y único en la escena.`);
      platformIds.add(id);
      if (!['box','diamond','sphere','cylinder','cone','pyramid'].includes(object.shape)) throw new Error(`El objeto ${id} necesita una forma geométrica compatible.`);
      for (const key of ['x','y','z','halfWidth','halfHeight','halfDepth','rotationY']) {
        const n = object[key];
        if (typeof n !== 'number' || !Number.isFinite(n) || !Number.isFinite(Math.fround(n))) throw new Error(`El objeto ${id} necesita un valor finito explícito en ${key}.`);
      }
      if (Math.abs(object.x) > 500 || Math.abs(object.z) > 500 || Math.abs(object.y) > 100 || object.halfWidth < 0.1 || object.halfWidth > 20.5 || object.halfHeight < 0.1 || object.halfHeight > 20.5 || object.halfDepth < 0.1 || object.halfDepth > 20.5 || object.rotationY < -360 || object.rotationY > 360) throw new Error(`La geometría del objeto ${id} queda fuera de los límites del editor.`);
      if (typeof object.color !== 'string' || !/^#[0-9a-f]{6}$/i.test(object.color)) throw new Error(`El objeto ${id} necesita un color #RRGGBB válido.`);
      const collisionEnabled = object.collisionEnabled === undefined ? false : object.collisionEnabled;
      if (typeof collisionEnabled !== 'boolean') throw new Error(`El objeto ${id} necesita un estado de colisión booleano.`);
      const collisionHalfWidth = object.collisionHalfWidth === undefined ? object.halfWidth : object.collisionHalfWidth;
      const collisionHalfHeight = object.collisionHalfHeight === undefined ? object.halfHeight : object.collisionHalfHeight;
      const collisionHalfDepth = object.collisionHalfDepth === undefined ? object.halfDepth : object.collisionHalfDepth;
      const collisionOffsetY = object.collisionOffsetY === undefined ? 0 : object.collisionOffsetY;
      for (const [key, n] of [['collisionHalfWidth',collisionHalfWidth],['collisionHalfHeight',collisionHalfHeight],['collisionHalfDepth',collisionHalfDepth],['collisionOffsetY',collisionOffsetY]]) {
        if (typeof n !== 'number' || !Number.isFinite(n) || !Number.isFinite(Math.fround(n))) throw new Error(`El colisionador del objeto ${id} necesita un valor finito en ${key}.`);
      }
      if (collisionHalfWidth < 0.1 || collisionHalfWidth > 20.5 || collisionHalfHeight < 0.1 || collisionHalfHeight > 20.5 || collisionHalfDepth < 0.1 || collisionHalfDepth > 20.5 || collisionOffsetY < -20.5 || collisionOffsetY > 20.5) throw new Error(`La caja de colisión del objeto ${id} queda fuera de los límites permitidos.`);
      return { ...object, id, label: String(object.label ?? id), collisionEnabled, collisionHalfWidth, collisionHalfHeight, collisionHalfDepth, collisionOffsetY };
    });
    const scenePhysics = project.gameScene.physics;
    for (const [key, min, max] of [['moveSpeed',0,20],['acceleration',0.1,30],['jumpSpeed',0,30],['gravity',0,50],['fallLimit',-100,-0.1],['playerHalfHeight',0.1,5]]) {
      const n = scenePhysics[key];
      if (typeof n !== 'number' || !Number.isFinite(n) || n < min || n > max) throw new Error(`La física del juego requiere un valor entre ${min} y ${max} para ${key}.`);
    }
    if (project.gameScene.enabled) {
      for (const [key, min, max] of [['followDistance',4,30],['followHeight',1,12],['lookAhead',0,20]]) {
        const n = project.gameScene.camera[key];
        if (typeof n !== 'number' || !Number.isFinite(n) || n < min || n > max) throw new Error(`La cámara del juego requiere un valor entre ${min} y ${max} para ${key}.`);
      }
      for (const key of ['skyColor','playerColor','playerAccentColor','collectibleColor','goalColor']) {
        if (typeof project.gameScene.appearance[key] !== 'string' || !/^#[0-9a-f]{6}$/i.test(project.gameScene.appearance[key])) throw new Error(`La presentación del juego requiere un color #RRGGBB válido para ${key}.`);
      }
      if (typeof project.gameScene.appearance.requireCollectibles !== 'boolean') throw new Error('La regla de victoria requireCollectibles debe ser booleana.');
    }
    const spawnPlatformId = String(project.gameScene.player.spawnPlatformId ?? '');
    if (spawnPlatformId && !project.gameScene.platforms.some(platform => platform.id === spawnPlatformId)) throw new Error(`El punto de inicio apunta a una plataforma inexistente: ${spawnPlatformId}.`);
    project.gameScene.player.spawnPlatformId = spawnPlatformId;
    const goalCount = project.gameScene.platforms.filter(platform => platform.goal).length;
    if (goalCount > 1) throw new Error('La escena solo admite una plataforma de meta.');
    if (Object.hasOwn(value, 'resolution')) {
      if (!Object.hasOwn(value.resolution, 'width') || !Object.hasOwn(value.resolution, 'height')) throw new Error('La resolución debe declarar explícitamente ancho y alto; no se completarán dimensiones faltantes.');
      if (!Number.isSafeInteger(value.resolution.width) || value.resolution.width < MIN_CANVAS_WIDTH || value.resolution.width > MAX_CANVAS_WIDTH || !Number.isSafeInteger(value.resolution.height) || value.resolution.height < MIN_CANVAS_HEIGHT || value.resolution.height > MAX_CANVAS_HEIGHT) throw new Error(`El lienzo debe tener dimensiones enteras entre ${MIN_CANVAS_WIDTH}×${MIN_CANVAS_HEIGHT} y ${MAX_CANVAS_WIDTH}×${MAX_CANVAS_HEIGHT}.`);
    }
    if (Object.hasOwn(value, 'theme')) {
      for (const key of ['background','accent','text']) if (typeof value.theme[key] !== 'string' || !/^#[0-9a-f]{6}$/i.test(value.theme[key])) throw new Error(`El tema necesita declarar explícitamente el color ${key} con formato #RRGGBB.`);
    }
    project.format = 'ps5vproj';
    if (Object.hasOwn(value, 'formatVersion') && (!Number.isInteger(value.formatVersion) || ![1, 2].includes(value.formatVersion))) throw new Error(`Versión de formato no compatible: ${String(value.formatVersion)}.`);
    project.formatVersion = 2;
    if (Object.hasOwn(value, 'name') && typeof value.name !== 'string') throw new Error('El nombre del proyecto debe ser una cadena explícita.');
    project.name = String(project.name ?? '').trim();
    if (legacyProject && (!Object.hasOwn(value, 'name') || !isValidProjectName(project.name))) {
      const recoveredName = normalizeLegacyProjectName(Object.hasOwn(value, 'name') ? project.name : '', sourceName);
      if (recoveredName) project.name = recoveredName;
    }
    if (!isValidProjectName(project.name)) throw new Error('El nombre del proyecto debe tener entre 1 y 40 caracteres ASCII seguros. En proyectos antiguos, usa un nombre de archivo compatible al importarlos; los proyectos v2 no se modifican automáticamente.');
    if (Object.hasOwn(value, 'description') && typeof value.description !== 'string') throw new Error('La descripción del proyecto debe ser texto.');
    project.description = String(project.description ?? '').trim();
    if (project.description.length > 500) throw new Error('La descripción del proyecto no puede superar 500 caracteres.');
    if (Object.hasOwn(value, 'gamePresentation') && !isRecord(value.gamePresentation)) throw new Error('gamePresentation debe ser un objeto de presentación.');
    const incomingGamePresentation = isRecord(value.gamePresentation) ? value.gamePresentation : {};
    project.gamePresentation = { ...(isRecord(defaults.gamePresentation) ? defaults.gamePresentation : {}), ...incomingGamePresentation };
    for (const key of ['iconAssetId', 'audioAssetId']) {
      if (Object.hasOwn(incomingGamePresentation, key) && typeof incomingGamePresentation[key] !== 'string') throw new Error(`gamePresentation.${key} debe ser un identificador de recurso o una cadena vacía.`);
      project.gamePresentation[key] = String(project.gamePresentation[key] || '');
    }
    if (Object.hasOwn(value, 'backend') && typeof value.backend !== 'string') throw new Error('El backend debe ser una cadena explícita.');
    if (Object.hasOwn(value, 'backend') && !value.backend.trim()) throw new Error('El backend explícito no puede estar vacío; selecciona un backend compatible.');
    project.backend = Object.hasOwn(value, 'backend') ? value.backend.trim() : String(defaults.backend);
    if (!validBackends.includes(project.backend)) throw new Error(`Backend de proyecto desconocido: ${project.backend}`);
    if (Object.hasOwn(value, 'customCode') && typeof value.customCode !== 'string') throw new Error('El código manual debe ser una cadena explícita.');
    if (Object.hasOwn(value, 'manualCode') && typeof value.manualCode !== 'boolean') throw new Error('manualCode debe ser una bandera booleana explícita.');
    if (Object.hasOwn(value, 'payloadLanguage') && !['c','cpp'].includes(value.payloadLanguage)) throw new Error('payloadLanguage debe ser c o cpp.');
    if (Object.hasOwn(value, 'payloadBuildMode') && !['managed','upstream-makefile'].includes(value.payloadBuildMode)) throw new Error('payloadBuildMode debe ser managed o upstream-makefile.');
    project.customCode = String(project.customCode ?? '');
    project.manualCode = project.manualCode === true;
    project.payloadLanguage = value.payloadLanguage === 'cpp' ? 'cpp' : 'c';
    project.payloadBuildMode = value.payloadBuildMode === 'upstream-makefile' ? 'upstream-makefile' : 'managed';
    if (project.payloadBuildMode === 'upstream-makefile' && project.backend !== 'payload') throw new Error('upstream-makefile solo es válido para proyectos payload.');
    if (Object.hasOwn(value, 'fontAssetId') && typeof value.fontAssetId !== 'string') throw new Error('fontAssetId debe ser un identificador de recurso explícito o una cadena vacía.');
    if (Object.hasOwn(value, 'currentScreen') && typeof value.currentScreen !== 'string') throw new Error('currentScreen debe ser un identificador de pantalla explícito.');
    project.fontAssetId = String(project.fontAssetId || '');
    project.currentScreen = String(project.currentScreen || '');
    if (Object.hasOwn(value.settings || {}, 'renderTarget')) {
      const target = value.settings.renderTarget;
      if (!isRecord(target)) throw new Error('La referencia de render debe ser un objeto con ancho y alto explícitos.');
      if (!Object.hasOwn(target, 'width') || !Object.hasOwn(target, 'height') || !Number.isSafeInteger(target.width) || target.width < MIN_CANVAS_WIDTH || target.width > MAX_CANVAS_WIDTH || !Number.isSafeInteger(target.height) || target.height < MIN_CANVAS_HEIGHT || target.height > MAX_CANVAS_HEIGHT) throw new Error(`La referencia de render debe tener dimensiones enteras entre ${MIN_CANVAS_WIDTH}×${MIN_CANVAS_HEIGHT} y ${MAX_CANVAS_WIDTH}×${MAX_CANVAS_HEIGHT}.`);
      project.settings.renderTarget = { width: target.width, height: target.height };
    } else if (!isRecord(project.settings.renderTarget) || !Number.isSafeInteger(project.settings.renderTarget.width) || project.settings.renderTarget.width < MIN_CANVAS_WIDTH || project.settings.renderTarget.width > MAX_CANVAS_WIDTH || !Number.isSafeInteger(project.settings.renderTarget.height) || project.settings.renderTarget.height < MIN_CANVAS_HEIGHT || project.settings.renderTarget.height > MAX_CANVAS_HEIGHT) {
      project.settings.renderTarget = { width: 1920, height: 1080 };
    }
    if (Object.hasOwn(value.settings || {}, 'titleId') && typeof value.settings.titleId !== 'string') throw new Error('TITLE_ID debe ser una cadena explícita.');
    project.settings.titleId = normalizeTitleId(project.settings.titleId);
    if (project.settings.titleId && !isValidTitleId(project.settings.titleId)) throw new Error('El TITLE_ID guardado no tiene el formato PPSA12345 válido.');

    const componentIds = new Set();
    const typeSet = new Set(validComponentTypes);
    project.components = project.components.map((component, index) => {
      if (!isRecord(component)) throw new Error(`El componente ${index + 1} no es un objeto válido.`);
      const id = String(component.id ?? '').trim();
      const type = String(component.type ?? '');
      if (!/^[A-Za-z_][A-Za-z0-9_-]{0,63}$/.test(id)) throw new Error(`El componente ${index + 1} necesita un identificador técnico seguro (letras, números, guion o guion bajo).`);
      if (componentIds.has(id)) throw new Error(`Identificador de componente duplicado: ${id}`);
      if (!typeSet.has(type)) throw new Error(`El componente ${id} usa un tipo no compatible: ${type || '(vacío)'}.`);
      componentIds.add(id);
      if (typeof component.label !== 'string') throw new Error(`El componente ${id} necesita una etiqueta textual explícita.`);
      if (!component.label.trim() && type !== 'separator') throw new Error(`El componente ${id} necesita una etiqueta no vacía; solo los separadores pueden carecer de texto.`);
      if (typeof component.screenId !== 'string' || !component.screenId.trim()) throw new Error(`El componente ${id} necesita un identificador de pantalla explícito; no se asignará a una pantalla por defecto.`);
      const normalized = { ...component, id, type, label: component.label };
      for (const field of ['x','y','w','h']) {
        if (normalized[field] === undefined || normalized[field] === null || String(normalized[field]).trim() === '') throw new Error(`El componente ${id} necesita un valor geométrico explícito en ${field}; no se inventarán dimensiones.`);
        const numeric = Number(normalized[field]);
        if (!Number.isFinite(numeric)) throw new Error(`El componente ${id} tiene un valor numérico inválido en ${field}.`);
        normalized[field] = numeric;
      }
      if (normalized.w <= 0 || normalized.h <= 0 || normalized.x < 0 || normalized.y < 0 || normalized.x + normalized.w > project.resolution.width || normalized.y + normalized.h > project.resolution.height) throw new Error(`La geometría del componente ${id} queda fuera del lienzo ${project.resolution.width}×${project.resolution.height} o tiene dimensiones no positivas.`);
      for (const field of ['font','opacity','value','min','max','step']) {
        if (normalized[field] === undefined || normalized[field] === null || String(normalized[field]).trim() === '') throw new Error(`El componente ${id} necesita un valor explícito en ${field}; no se sustituirá por un valor inventado.`);
      }
      for (const field of ['font','opacity','value','min','max','step','zIndex']) {
        if (normalized[field] !== undefined && normalized[field] !== null) {
          const numeric = Number(normalized[field]);
          if (!Number.isFinite(numeric)) throw new Error(`El componente ${id} tiene un valor numérico inválido en ${field}.`);
          normalized[field] = numeric;
        }
      }
      if (normalized.font <= 0) throw new Error(`El componente ${id} necesita un tamaño de fuente mayor que cero.`);
      if (normalized.opacity < 0 || normalized.opacity > 100) throw new Error(`La opacidad del componente ${id} debe estar entre 0 y 100.`);
      if (normalized.min > normalized.max) throw new Error(`El intervalo min/max del componente ${id} está invertido.`);
      if (normalized.step <= 0) throw new Error(`El paso del componente ${id} debe ser mayor que cero.`);
      if (normalized.value < normalized.min || normalized.value > normalized.max) throw new Error(`El valor inicial del componente ${id} queda fuera de su intervalo.`);
      if (['slider','stepper','progress','gauge'].includes(type) && normalized.min >= normalized.max) throw new Error(`El componente ${id} necesita un intervalo con mínimo estrictamente inferior al máximo.`);
      if (type === 'stepper' && ![normalized.value, normalized.min, normalized.max, normalized.step].every(Number.isInteger)) throw new Error(`El stepper ${id} necesita valor, mínimo, máximo y paso enteros.`);
      for (const field of ['visible','checked']) if (!Object.hasOwn(normalized, field) || typeof normalized[field] !== 'boolean') throw new Error(`El componente ${id} debe declarar ${field} como booleano explícito; no se inferirá su estado.`);
      if (normalized.bg !== 'transparent' && !/^#[0-9a-f]{6}$/i.test(String(normalized.bg ?? ''))) throw new Error(`El componente ${id} necesita un color de fondo hexadecimal o el valor explícito «transparent».`);
      if (!/^#[0-9a-f]{6}$/i.test(String(normalized.fg ?? ''))) throw new Error(`El componente ${id} necesita un color de texto hexadecimal explícito.`);
      const action = String(normalized.action ?? 'none');
      if (!['none', 'notify'].includes(action)) throw new Error(`La acción predeterminada ${action} del componente ${id} no está implementada.`);
      if (action === 'notify' && !String(normalized.actionMessage ?? '').trim()) throw new Error(`El componente ${id} necesita un mensaje explícito para su acción de notificación.`);
      normalized.action = action;
      if (normalized.custom === undefined || normalized.custom === null) normalized.custom = {};
      else if (!isRecord(normalized.custom)) throw new Error(`El campo custom del componente ${id} debe ser un objeto.`);
      if (normalized.items === undefined || normalized.items === null) normalized.items = [];
      else if (!Array.isArray(normalized.items) || normalized.items.some(item => typeof item !== 'string')) throw new Error(`La lista items del componente ${id} debe contener texto.`);
      if (Object.hasOwn(normalized.custom, 'text') && typeof normalized.custom.text !== 'string') throw new Error(`El texto personalizado del componente ${id} debe ser una cadena explícita.`);
      if (Object.hasOwn(normalized.custom, 'selected')) {
        const selected = normalized.custom.selected;
        if (typeof selected !== 'number' || !Number.isInteger(selected) || selected < 0 || selected >= normalized.items.length) throw new Error(`La selección inicial del componente ${id} debe ser un índice entero que apunte a una opción existente.`);
      }
      return normalized;
    });

    const assetIds = new Set();
    project.assets = project.assets.map((asset, index) => {
      if (!isRecord(asset)) throw new Error(`El recurso ${index + 1} no es un objeto válido.`);
      const id = String(asset.id ?? '').trim();
      if (!/^[A-Za-z_][A-Za-z0-9_-]{0,79}$/.test(id)) throw new Error(`El recurso ${index + 1} necesita un identificador técnico seguro.`);
      if (assetIds.has(id)) throw new Error(`Identificador de recurso duplicado: ${id}`);
      assetIds.add(id);
      const name = String(asset.name ?? '').trim();
      const fileName = String(asset.fileName ?? '').trim();
      if (!name || name.length > 255) throw new Error(`El recurso ${id} necesita un nombre de archivo explícito de hasta 255 caracteres.`);
      if (!fileName || fileName.length > 128 || fileName === '.' || fileName === '..' || /[\\/]/.test(fileName) || fileName.includes('..') || !/^[A-Za-z0-9_-][A-Za-z0-9_. -]*$/.test(fileName)) throw new Error(`El recurso ${id} tiene un nombre de archivo no seguro o no explícito.`);
      if (typeof asset.dataUrl !== 'string' || !/^data:[^,]+,/.test(asset.dataUrl)) throw new Error(`El recurso ${id} necesita un data URL válido; no se permiten recursos vacíos ni placeholders.`);
      const mime = String(asset.mime ?? '').trim();
      if (!/^[A-Za-z0-9!#$&^_.+-]+\/[A-Za-z0-9!#$&^_.+-]+$/.test(mime)) throw new Error(`El recurso ${id} necesita un tipo MIME explícito y válido.`);
      if (asset.size === undefined || asset.size === null || String(asset.size).trim() === '') throw new Error(`El recurso ${id} necesita un tamaño explícito.`);
      const size = Number(asset.size);
      if (!Number.isSafeInteger(size) || size <= 0 || size > 20 * 1024 * 1024) throw new Error(`El tamaño del recurso ${id} debe estar entre 1 byte y 20 MiB.`);
      return { ...asset, id, name, fileName, mime, size };
    });

    const screenIds = new Set();
    const screenNames = new Set();
    project.screens = project.screens.map((screen, index) => {
      if (!isRecord(screen)) throw new Error(`La pantalla ${index + 1} no es un objeto válido.`);
      const id = String(screen.id ?? '').trim();
      if (!/^[A-Za-z_][A-Za-z0-9_-]{0,63}$/.test(id)) throw new Error(`La pantalla ${index + 1} necesita un identificador técnico seguro.`);
      if (screenIds.has(id)) throw new Error(`Identificador de pantalla duplicado: ${id}`);
      screenIds.add(id);
      const name = String(screen.name ?? '').trim();
      if (!name) throw new Error(`La pantalla ${id} necesita un nombre explícito.`);
      const normalizedName = name.toLocaleLowerCase();
      if (screenNames.has(normalizedName)) throw new Error(`El nombre de pantalla «${name}» está duplicado.`);
      screenNames.add(normalizedName);
      return { ...screen, id, name };
    });
    if (!project.screens.length) throw new Error('El proyecto debe contener al menos una pantalla real; no se creará una pantalla sustitutiva.');
    for (const key of ['background','accent','text']) if (!/^#[0-9a-f]{6}$/i.test(String(project.theme[key] ?? ''))) throw new Error(`El tema necesita un color ${key} explícito con formato #RRGGBB.`);
    const screenIdSet = new Set(project.screens.map(screen => screen.id));
    if (!Object.hasOwn(value, 'currentScreen')) project.currentScreen = project.screens[0].id;
    if (!screenIdSet.has(project.currentScreen)) throw new Error(`La pantalla activa no existe en el proyecto: ${project.currentScreen || '(vacía)'}`);
    project.components = project.components.map(component => {
      const screenId = String(component.screenId || project.currentScreen);
      if (!screenIdSet.has(screenId)) throw new Error(`El componente ${component.id} apunta a una pantalla inexistente: ${screenId}`);
      if (component.assetId !== undefined && component.assetId !== null && component.assetId !== '' && !assetIds.has(String(component.assetId))) throw new Error(`El componente ${component.id} apunta a un recurso inexistente: ${component.assetId}`);
      return { ...component, screenId, assetId: component.assetId === undefined ? null : component.assetId };
    });
    const flowIds = new Set();
    const knownEvents = new Set(['activate','change','start','any']);
    const knownActions = new Set(['notify','setText','toggleVisibility','setValue','changeColor','navigate','callFunction','gameAction']);
    const byComponentId = new Map(project.components.map(component => [component.id, component]));
    project.flows = project.flows.map((flow, index) => {
      if (!isRecord(flow)) throw new Error(`El flujo ${index + 1} no es un objeto válido.`);
      const id = String(flow.id ?? '').trim();
      if (!/^[A-Za-z_][A-Za-z0-9_-]{0,79}$/.test(id)) throw new Error(`El flujo ${index + 1} necesita un identificador técnico seguro.`);
      if (flowIds.has(id)) throw new Error(`Identificador de flujo duplicado: ${id}`);
      flowIds.add(id);
      const event = String(flow.event ?? '');
      const action = String(flow.action ?? '');
      const componentId = String(flow.componentId ?? '');
      const targetId = String(flow.targetId ?? '');
      const targetScreen = String(flow.targetScreen ?? '');
      if (Object.hasOwn(flow, 'enabled') && typeof flow.enabled !== 'boolean') throw new Error(`El campo enabled del flujo ${id} debe ser booleano.`);
      if (!knownEvents.has(event)) throw new Error(`El flujo ${id} usa un evento no compatible: ${event || '(vacío)'}`);
      if (!knownActions.has(action)) throw new Error(`El flujo ${id} usa una acción no compatible: ${action || '(vacía)'}`);
      if (event !== 'start' && !byComponentId.has(componentId)) throw new Error(`El flujo ${id} no tiene un componente de origen válido: ${componentId || '(vacío)'}`);
      if (componentId && !byComponentId.has(componentId)) throw new Error(`El flujo ${id} apunta a un componente de origen inexistente: ${componentId}`);
      if (['setText','toggleVisibility','setValue'].includes(action) && !byComponentId.has(targetId)) throw new Error(`El flujo ${id} necesita un destino válido para ${action}.`);
      if (action === 'setText' && !['title','text','button','toggle','slider','stepper','select','badge','panel','card','input'].includes(byComponentId.get(targetId)?.type)) throw new Error(`El flujo ${id} apunta a un componente que no admite cambio de texto.`);
      if (action === 'setText' && typeof flow.value !== 'string') throw new Error(`El flujo ${id} necesita un valor de texto explícito de tipo cadena.`);
      if (action === 'setValue') {
        const target = byComponentId.get(targetId);
        if (!['slider','stepper','toggle','select','carousel','list','progress','gauge'].includes(target?.type)) throw new Error(`El flujo ${id} apunta a un componente que no admite cambio de valor.`);
        if (target.type === 'toggle' && !/^(true|false|1|0|sí|si|no|on|off)$/i.test(String(flow.value ?? '').trim())) throw new Error(`El flujo ${id} necesita un valor booleano explícito para el interruptor.`);
        if (target.type !== 'toggle') {
          const raw = flow.value;
          const numeric = typeof raw === 'number' ? raw : (typeof raw === 'string' && raw.trim() !== '' ? Number(raw) : NaN);
          if (!Number.isFinite(numeric)) throw new Error(`El flujo ${id} necesita un valor numérico explícito.`);
          if (['select','carousel','list'].includes(target.type)) {
            if (!Number.isInteger(numeric) || !Array.isArray(target.items) || numeric < 0 || numeric >= target.items.length) throw new Error(`El flujo ${id} necesita un índice entero que apunte a una opción real del destino.`);
          } else {
            if (numeric < target.min || numeric > target.max) throw new Error(`El valor del flujo ${id} queda fuera del intervalo del destino ${target.id}.`);
            if (target.type === 'stepper' && !Number.isInteger(numeric)) throw new Error(`El flujo ${id} necesita un valor entero dentro del intervalo del stepper ${target.id}.`);
          }
        }
      }
      if (action === 'navigate' && !screenIdSet.has(targetScreen)) throw new Error(`El flujo ${id} apunta a una pantalla inexistente: ${targetScreen || '(vacía)'}`);
      const sourceScreen = componentId && byComponentId.has(componentId) ? byComponentId.get(componentId).screenId : (event === 'start' ? project.currentScreen : '');
      if (action === 'navigate' && sourceScreen && sourceScreen === targetScreen) throw new Error(`El flujo ${id} navega a la misma pantalla desde la que se dispara; el destino debe ser otra pantalla.`);
      if (action === 'changeColor' && !/^#[0-9a-f]{6}$/i.test(String(flow.value ?? ''))) throw new Error(`El flujo ${id} necesita un color hexadecimal #RRGGBB explícito.`);
      if (action === 'notify' && !String(flow.message ?? '').trim()) throw new Error(`El flujo ${id} necesita un mensaje explícito.`);
      if (action === 'callFunction') {
        if (project.backend !== 'ps5link') throw new Error(`El flujo ${id} solo puede llamar funciones C con el backend ps5link.`);
        if (!/^[A-Za-z_][A-Za-z0-9_]{0,79}$/.test(String(flow.value ?? ''))) throw new Error(`El flujo ${id} necesita un nombre de función C válido.`);
        if (event === 'start' && !componentId) throw new Error(`El flujo ${id} necesita un origen válido para llamar una función C.`);
      }
      if (action === 'gameAction') {
        if (project.backend !== 'ps5link') throw new Error(`El flujo ${id} solo puede usar acciones de juego con el backend ps5link.`);
        const gameAction = String(flow.value ?? '');
        if (!new Set(['start','pause','resume','restart','toggleAudio']).has(gameAction)) throw new Error(`El flujo ${id} usa una acción de juego no compatible: ${gameAction || '(vacía)'}.`);
        const source = byComponentId.get(componentId);
        if (!source) throw new Error(`El flujo ${id} necesita enlazar una acción del juego a un componente visual existente.`);
        const allowedTypes = gameAction === 'toggleAudio' ? ['button','toggle'] : ['button'];
        if (!allowedTypes.includes(source.type)) throw new Error(`El flujo ${id} usa un control incompatible para ${gameAction}; utiliza un botón${gameAction === 'toggleAudio' ? ' o interruptor' : ''}.`);
        const allowedEvents = source.type === 'toggle' ? ['change','any'] : ['activate','any'];
        if (!allowedEvents.includes(event)) throw new Error(`El flujo ${id} usa un evento incompatible con el control ${source.type}.`);
        const duplicate = project.flows.find(other => other !== flow && other.enabled !== false && other.action === 'gameAction' && other.value === gameAction);
        if (duplicate) throw new Error(`La acción integrada ${gameAction} ya está conectada en el flujo ${duplicate.id}; cada acción debe tener un control principal.`);
      }
      return { ...flow, id, event, action, componentId, targetId, targetScreen, message: String(flow.message ?? ''), value: flow.value ?? '' };
    });
    if (project.fontAssetId) {
      if (!assetIds.has(project.fontAssetId)) throw new Error(`La fuente seleccionada hace referencia a un recurso inexistente: ${project.fontAssetId}`);
      const fontAsset = project.assets.find(asset => asset.id === project.fontAssetId);
      if (!fontAsset || !/\.ttf$/i.test(fontAsset.fileName) || !/^data:[^,]+,/.test(fontAsset.dataUrl)) throw new Error('La fuente seleccionada debe ser un recurso TTF real y contener sus datos; no se aceptan fuentes sustitutivas.');
    }
    if (project.gamePresentation.audioAssetId) {
      if (!assetIds.has(project.gamePresentation.audioAssetId)) throw new Error(`La música del título hace referencia a un recurso inexistente: ${project.gamePresentation.audioAssetId}`);
      const audioAsset = project.assets.find(asset => asset.id === project.gamePresentation.audioAssetId);
      if (!audioAsset || !/\.(?:at9|wav|mp3|flac|aiff|aif|aifc)$/i.test(audioAsset.fileName) || !/^data:[^,]+,/.test(audioAsset.dataUrl)) {
        throw new Error('La música de selección debe ser un recurso ATRAC9, WAV, MP3, FLAC o AIFF importado al proyecto.');
      }
    }
    return project;
  }

  function analyzeGameSceneReachability(scene) {
    const platforms = Array.isArray(scene?.platforms) ? scene.platforms : [];
    const objects = Array.isArray(scene?.objects) ? scene.objects : [];
    const physics = scene?.physics || {};
    const nodes = [
      ...platforms.map(platform => ({ id:platform.id, kind:'platform', ref:platform, x:platform.x, z:platform.z,
        top:platform.height+(platform.collisionOffsetY||0), halfWidth:platform.collisionHalfWidth??platform.halfWidth,
        halfDepth:platform.collisionHalfDepth??platform.halfDepth, enabled:platform.collisionEnabled!==false })),
      ...objects.filter(object => object?.collisionEnabled===true).map(object => ({ id:object.id, kind:'object', ref:object, x:object.x, z:object.z,
        top:object.y+(object.collisionOffsetY||0)+(object.collisionHalfHeight??object.halfHeight),
        halfWidth:object.collisionHalfWidth??object.halfWidth, halfDepth:object.collisionHalfDepth??object.halfDepth, enabled:true }))
    ];
    const byId = new Map(platforms.map((p, i) => [p.id, i]));
    const spawnIndex = byId.get(scene?.player?.spawnPlatformId);
    const reachable = new Set();
    if (Number.isInteger(spawnIndex) && platforms[spawnIndex]?.collisionEnabled !== false) reachable.add(spawnIndex);
    const speed = Number(physics.moveSpeed), jump = Number(physics.jumpSpeed), gravity = Number(physics.gravity);
    if (speed > 0 && jump > 0 && gravity > 0 && reachable.size) {
      let changed = true;
      while (changed) {
        changed = false;
        for (const fromIndex of [...reachable]) {
          const from = nodes[fromIndex];
          for (let toIndex = 0; toIndex < nodes.length; toIndex++) {
            if (reachable.has(toIndex)) continue;
            const to = nodes[toIndex];
            if (!to.enabled) continue;
            const rise = to.top - from.top;
            const discriminant = jump * jump - 2 * gravity * rise;
            if (discriminant < 0) continue;
            const landingTime = (jump + Math.sqrt(Math.max(0, discriminant))) / gravity;
            const reach = speed * landingTime;
            const xAllowance = reach + from.halfWidth + to.halfWidth + 0.34;
            const zAllowance = reach + from.halfDepth + to.halfDepth + 0.34;
            if (Math.abs(to.x - from.x) > xAllowance || Math.abs(to.z - from.z) > zAllowance) continue;
            reachable.add(toIndex);
            changed = true;
          }
        }
      }
    }
    const unreachableCriticalPlatforms = platforms.filter((p, i) => (p.goal || p.collectible || p.checkpoint) && !reachable.has(i))
      .map(p => ({ id: p.id, label: p.label || p.id, goal: !!p.goal, collectible: !!p.collectible, checkpoint: !!p.checkpoint }));
    const disabledCriticalPlatforms = platforms.filter(p => p.collisionEnabled===false && (p.goal || p.collectible || p.checkpoint))
      .map(p => ({ id: p.id, label: p.label || p.id }));
    return {
      reachablePlatformIds: [...reachable].filter(i => i<platforms.length).map(i => platforms[i].id),
      reachableObjectIds: [...reachable].filter(i => i>=platforms.length).map(i => nodes[i].id),
      unreachablePlatformIds: platforms.filter((_, i) => !reachable.has(i)).map(p => p.id),
      unreachableCriticalPlatforms,
      disabledCriticalPlatforms,
      spawnValid: Number.isInteger(spawnIndex) && platforms[spawnIndex]?.collisionEnabled !== false
    };
  }

  function resizeIsometricCollisionBox({ deltaX, deltaY, scale, signX, signZ, halfWidth, halfDepth }) {
    const values = [deltaX, deltaY, scale, signX, signZ, halfWidth, halfDepth].map(Number);
    if (!values.every(Number.isFinite) || values[2] <= 0 || ![-1, 1].includes(values[3]) || ![-1, 1].includes(values[4])) {
      throw new Error('Los datos de redimensión de colisión no son válidos.');
    }
    const [screenX, screenY, projectionScale, cornerX, cornerZ, width, depth] = values;
    const worldDeltaX = screenX / (2 * projectionScale) + screenY / projectionScale;
    const worldDeltaZ = screenY / projectionScale - screenX / (2 * projectionScale);
    return {
      collisionHalfWidth: Math.min(20.5, Math.max(0.1, width + cornerX * worldDeltaX)),
      collisionHalfDepth: Math.min(20.5, Math.max(0.1, depth + cornerZ * worldDeltaZ))
    };
  }

  function resizeWorldCollisionBox({ deltaX, deltaZ, signX, signZ, halfWidth, halfDepth }) {
    const values = [deltaX, deltaZ, signX, signZ, halfWidth, halfDepth].map(Number);
    if (!values.every(Number.isFinite) || ![-1, 1].includes(values[2]) || ![-1, 1].includes(values[3])) {
      throw new Error('Los datos de redimensión espacial de colisión no son válidos.');
    }
    const [worldDeltaX, worldDeltaZ, cornerX, cornerZ, width, depth] = values;
    return {
      collisionHalfWidth: Math.min(20.5, Math.max(0.1, width + cornerX * worldDeltaX)),
      collisionHalfDepth: Math.min(20.5, Math.max(0.1, depth + cornerZ * worldDeltaZ))
    };
  }

  const api = Object.freeze({
    version: 2,
    normalizeTitleId,
    isValidTitleId,
    isValidProjectName,
    normalizeLegacyProjectName,
    normalizeAssetFilename,
    normalizeProjectModel,
    analyzeGameSceneReachability,
    resizeIsometricCollisionBox,
    resizeWorldCollisionBox
  });
  if (root) root.PS5HSProjectContracts = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis === 'object' ? globalThis : null);
