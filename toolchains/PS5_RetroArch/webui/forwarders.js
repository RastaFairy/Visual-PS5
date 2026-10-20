/* Game Forwarder: home screen tiles that each open one game in RetroArch
 * (src/ps5_forwarders.h). The picture of a tile is drawn here, square, from the media of
 * its game, and sent to the console as a 512x512 PNG. */
'use strict';
let forwarders = { tiles: [], cores: [], shadowmount: {} }, forwarderEdit = null, forwarderStamp = Date.now();
const FORWARDER_STATES = {
  installed: 'On the home screen',
  waiting: 'Appears on the home screen once RetroArch closes',
  updating: 'Its new name or picture shows once RetroArch closes',
  removing: 'Leaves the home screen once RetroArch closes',
  unknown: 'ShadowMountPlus is not answering',
};
// The games a tile can open: the library's in the content folder (a path inside it) or on
// a USB or extended storage drive (its own path).
function forwarderGames() {
  const out = [];
  for (const system of library.systems)
    for (const game of system.games) {
      const rom = game.path.startsWith('/app0/content/') ? game.path.slice(14) : game.path;
      if (rom[0] !== '/' || /^\/mnt\/(usb|ext)/.test(rom)) out.push({ system, game, rom });
    }
  return out;
}
function forwarderIcon(id) { return `/api/forwarders/icon?id=${id}&v=${forwarderStamp}`; }
async function loadForwarders() {
  const list = $('#forwarders-list');
  try {
    const [tiles, games] = await Promise.all([api('/api/forwarders', { signal: AbortSignal.timeout(60000) }),
      library.systems.length ? null : api('/api/library', { signal: AbortSignal.timeout(60000) })]);
    forwarders = tiles;
    if (games) library = games;
  } catch (error) { list.replaceChildren(element('p', error.message, 'list-message')); return; }
  const smp = forwarders.shadowmount;
  $('#forwarders-status').textContent = smp.answers ? `ShadowMountPlus ${smp.version} puts the tiles on the home screen.` : smp.error;
  $('#forwarders-status').classList.toggle('inline-error', !smp.answers);
  $('#forwarder-new').disabled = !smp.answers;
  const games = forwarderGames();
  list.replaceChildren();
  if (!forwarders.tiles.length) list.append(element('p', 'No tiles yet. Make one for a game you play often.', 'list-message'));
  for (const tile of forwarders.tiles) {
    const card = element('article', undefined, 'forwarder-card'), info = element('div', undefined, 'forwarder-info');
    const picture = document.createElement('img'); picture.alt = ''; picture.src = forwarderIcon(tile.id);
    const game = games.find(entry => entry.rom === tile.rom), core = forwarders.cores.find(entry => entry.id === tile.core);
    info.append(named('strong', tile.name), named('span', game ? gameName(game.game) : tile.rom, 'muted'),
      core ? named('small', core.name) : element('small', 'Automatic'),
      element('span', FORWARDER_STATES[tile.state] || tile.state, `forwarder-state ${tile.state}`));
    const actions = element('div', undefined, 'forwarder-actions');
    const edit = element('button', 'Edit', 'secondary'), remove = element('button', 'Delete', 'secondary');
    edit.disabled = remove.disabled = tile.state === 'removing' || !smp.answers;
    edit.addEventListener('click', () => openForwarder(tile));
    remove.addEventListener('click', () => deleteForwarder(tile));
    actions.append(edit, remove); card.append(picture, info, actions); list.append(card);
  }
}
function openForwarder(tile) {
  forwarderEdit = { tile, drawn: Promise.resolve(false) };
  $('#forwarder-editor-title').textContent = tile ? 'Edit tile' : 'New tile';
  $('#forwarder-save').textContent = tile ? 'Save' : 'Create tile';
  const cores = $('#forwarder-core'), games = forwarderGames(), entry = tile && games.find(game => game.rom === tile.rom);
  cores.replaceChildren(new Option('Automatic', ''));
  for (const core of forwarders.cores) cores.add(namedOption(core.name, core.id));
  $('#forwarder-exit').checked = tile ? tile.exit_after_game : true;
  $('#forwarder-badge').checked = false;
  drawSystems();
  chooseSystem(entry ? entry.system.id : tile ? '' : games[0]?.system.id || '', tile?.rom);
  if (tile) { $('#forwarder-name').value = tile.name; cores.value = tile.core; }
  $('#forwarder-error').hidden = true;
  $('#forwarder-editor').hidden = false;
  $('#forwarder-editor').scrollIntoView({ behavior: 'smooth', block: 'start' });
}
// The system first, each behind its icon as on the Games page, then one of its games.
function drawSystems() {
  const list = $('#forwarder-systems'), games = forwarderGames();
  list.replaceChildren();
  for (const system of library.systems) {
    const count = games.filter(entry => entry.system === system).length;
    if (!count) continue;
    const item = element('li');
    item.setAttribute('role', 'option'); item.dataset.system = system.id; item.tabIndex = -1;
    item.append(systemIcon(system.id), named('span', system.name), named('small', String(count)));
    item.addEventListener('click', () => { chooseSystem(system.id); $('#forwarder-system').focus(); });
    item.addEventListener('keydown', event => {
      const items = [...list.children], at = items.indexOf(item);
      const move = { ArrowDown: at + 1, ArrowUp: at - 1, Home: 0, End: items.length - 1 }[event.key];
      const act = { Enter: 'choose', ' ': 'choose', Escape: 'close', Tab: 'leave' }[event.key];
      if (move !== undefined) { event.preventDefault(); items[(move + items.length) % items.length].focus(); }
      else if (act === 'choose') { event.preventDefault(); chooseSystem(system.id); $('#forwarder-system').focus(); }
      else if (act === 'close') { closeSystems(); $('#forwarder-system').focus(); }
      else if (act === 'leave') closeSystems();
    });
    list.append(item);
  }
}
function openSystems() {
  const list = $('#forwarder-systems');
  list.hidden = false; $('#forwarder-system').setAttribute('aria-expanded', 'true');
  (list.querySelector('[aria-selected="true"]') || list.firstElementChild)?.focus();
}
function closeSystems() { $('#forwarder-systems').hidden = true; $('#forwarder-system').setAttribute('aria-expanded', 'false'); }
// A system chosen: its games, by name; the first one, or the tile's (rom) when editing.
function chooseSystem(id, rom) {
  const system = library.systems.find(entry => entry.id === id), select = $('#forwarder-game');
  const chevron = element('span', undefined, 'system-chevron'); chevron.setAttribute('aria-hidden', 'true');
  $('#forwarder-system').replaceChildren(systemIcon(id), named('span', system ? system.name : ''), chevron);
  for (const item of $('#forwarder-systems').children) item.setAttribute('aria-selected', String(item.dataset.system === id));
  closeSystems();
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });
  const games = forwarderGames().filter(entry => entry.system === system).sort((a, b) => collator.compare(gameName(a.game), gameName(b.game)));
  select.replaceChildren(...games.map(entry => namedOption(gameName(entry.game), entry.rom)));
  if (rom && !games.some(entry => entry.rom === rom)) select.prepend(namedOption(rom, rom));
  select.value = rom || games[0]?.rom || '';
  gameChosen(!rom);
}
function chosenGame() { return forwarderGames().find(entry => entry.rom === $('#forwarder-game').value); }
// The pictures a tile can show: these four always (greyed out when the game has none yet),
// the others when the game has them.
const FORWARDER_KINDS = ['cover', 'box3d', 'logo', 'physical'], FORWARDER_EXTRA_KINDS = ['screenshot', 'title', 'fanart'];
function pictureKind() { return $('input[name="forwarder-media"]:checked')?.value || ''; }
// A game chosen: its name and core as the tile's, and the pictures its media offers.
function gameChosen(fill) {
  const entry = chosenGame(), media = entry?.game.media || [];
  if (fill && entry) {
    $('#forwarder-name').value = gameName(entry.game).slice(0, 128);
    $('#forwarder-core').value = (entry.game.core || '').split('/').pop().replace(/_libretro\.so$/, '');
  }
  for (const choice of $$('input[name="forwarder-media"]')) {
    const kind = choice.value;
    choice.closest('label').hidden = kind === 'current' ? !forwarderEdit.tile : kind === 'retroarch' ? !!forwarderEdit.tile
      : FORWARDER_EXTRA_KINDS.includes(kind) && !media.includes(kind);
    choice.disabled = !['current', 'retroarch'].includes(kind) && !media.includes(kind);
  }
  $('#forwarder-media-hint').hidden = FORWARDER_KINDS.every(kind => media.includes(kind));
  const first = forwarderEdit.tile ? 'current' : [...FORWARDER_KINDS, ...FORWARDER_EXTRA_KINDS].find(kind => media.includes(kind)) || 'retroarch';
  $(`input[name="forwarder-media"][value="${first}"]`).checked = true;
  pictureChosen();
}
// A cutout (a 3D box, a logo, a cartridge or disc) fits in the square; a picture fills it.
function pictureChosen() {
  $('#forwarder-fill').checked = !['box3d', 'logo', 'physical'].includes(pictureKind());
  drawPicture();
}
function loadImage(source) {
  return new Promise(resolve => {
    if (!source) return resolve(null);
    const image = new Image();
    image.onload = () => resolve(image); image.onerror = () => resolve(null);
    image.src = source;
  });
}
// The square picture: the media fills it (cropped) or fits in it, and the system's icon,
// when chosen, sits in the bottom right corner on a dark plate.
function drawPicture() {
  const kind = pictureKind(), entry = chosenGame(), plain = kind === 'current' || kind === 'retroarch';
  const source = kind === 'current' ? forwarderIcon(forwarderEdit.tile.id) : kind === 'retroarch' ? 'assets/retroarch.svg'
    : entry ? mediaUrl(entry.system.id, entry.game, kind) : '';
  $('#forwarder-fill').disabled = $('#forwarder-badge').disabled = plain;
  const badge = !plain && $('#forwarder-badge').checked && entry ? SYSTEM_ICONS[entry.system.id] : '';
  const drawing = forwarderEdit.drawn = Promise.all([loadImage(source), loadImage(badge)]).then(([image, icon]) => {
    if (forwarderEdit.drawn !== drawing || !image) return false;
    const context = $('#forwarder-canvas').getContext('2d');
    const width = image.naturalWidth || 300, height = image.naturalHeight || 200;
    const fill = $('#forwarder-fill').checked && !plain;
    const scale = kind === 'retroarch' ? 320 / width : (fill ? Math.max : Math.min)(512 / width, 512 / height);
    context.fillStyle = '#1b1325'; context.fillRect(0, 0, 512, 512);
    context.drawImage(image, (512 - width * scale) / 2, (512 - height * scale) / 2, width * scale, height * scale);
    if (icon) {
      const size = 168, at = 512 - size - 20, art = size * 1.25; // the artwork keeps a transparent margin
      context.save();
      context.beginPath();
      if (context.roundRect) context.roundRect(at, at, size, size, 32); else context.rect(at, at, size, size);
      context.fillStyle = '#100a18b8'; context.fill(); context.clip();
      context.drawImage(icon, at + (size - art) / 2, at + (size - art) / 2, art, art);
      context.restore();
    }
    return true;
  });
}
async function saveForwarder(event) {
  event.preventDefault();
  const tile = { name: $('#forwarder-name').value.trim(), rom: $('#forwarder-game').value,
    core: $('#forwarder-core').value, exit_after_game: $('#forwarder-exit').checked };
  const editing = forwarderEdit.tile, kind = pictureKind(), button = $('#forwarder-save'), problem = $('#forwarder-error');
  const label = button.textContent;
  button.disabled = true; button.textContent = 'Saving…'; problem.hidden = true;
  try {
    const id = editing ? editing.id : (await api('/api/forwarders', { method: 'POST', body: JSON.stringify(tile) })).id;
    if (editing) await api(`/api/forwarders/edit?id=${id}`, { method: 'POST', body: JSON.stringify(tile) });
    if (kind !== 'current' && kind !== 'retroarch') {
      if (!(await forwarderEdit.drawn)) throw new Error(i18n.t('This picture could not be drawn. Choose another one.'));
      const png = await new Promise(resolve => $('#forwarder-canvas').toBlob(resolve, 'image/png'));
      await api(`/api/forwarders/icon?id=${id}`, { method: 'PUT', body: png });
    }
    forwarderStamp = Date.now();
    $('#forwarder-editor').hidden = true;
    announce(editing ? 'Tile saved.' : 'Tile created. It appears on the home screen once RetroArch closes.');
    await loadForwarders();
  } catch (error) { problem.textContent = error.message; problem.hidden = false; }
  finally { button.disabled = false; button.textContent = label; }
}
async function deleteForwarder(tile) {
  if (!confirm(i18n.t(`Delete the tile ${tile.name}?`))) return;
  try {
    const { state } = await api(`/api/forwarders/delete?id=${tile.id}`, { method: 'POST' });
    announce(state === 'removed' ? 'Tile removed.' : 'The tile leaves the home screen once RetroArch closes.');
    await loadForwarders();
  } catch (error) { announce(error.message, true); }
}
$('#forwarder-new').addEventListener('click', () => openForwarder(null));
$('#forwarder-cancel').addEventListener('click', () => { $('#forwarder-editor').hidden = true; });
$('#refresh-forwarders').addEventListener('click', loadForwarders);
$('#forwarder-game').addEventListener('change', () => gameChosen(true));
$('#forwarder-media').addEventListener('change', pictureChosen);
$('#forwarder-fill').addEventListener('change', drawPicture);
$('#forwarder-badge').addEventListener('change', drawPicture);
$('#forwarder-system').addEventListener('click', () => ($('#forwarder-systems').hidden ? openSystems() : closeSystems()));
$('#forwarder-system').addEventListener('keydown', event => {
  if ({ ArrowDown: true, ArrowUp: true }[event.key]) { event.preventDefault(); openSystems(); }
});
document.addEventListener('click', event => { if (!event.target.closest('.system-picker')) closeSystems(); });
$('#forwarder-form').addEventListener('submit', saveForwarder);
function forwardersShown() { if (pageFromHash() === 'forwarders') loadForwarders(); }
window.addEventListener('hashchange', forwardersShown);
forwardersShown();
