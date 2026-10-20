/* SMB: the shared folder RetroArch's file browser shows under SMB (src/ps5_smb.h). The
 * console signs in, lists the shares and checks the folder; the password goes to it in a
 * request body and is never sent back. */
'use strict';
let smbSaved = null;
function smbServer() {
  return { server: $('#smb-server').value.trim(), user: $('#smb-user').value.trim(),
    password: $('#smb-password').value, workgroup: $('#smb-workgroup').value.trim() };
}
function smbProblem(message) {
  $('#smb-error').textContent = message || '';
  $('#smb-error').hidden = !message;
}
function smbShares(names, chosen) {
  const select = $('#smb-share');
  select.replaceChildren(...names.map(name => namedOption(name, name)));
  if (!names.length) select.add(new Option('This server shares no folders', ''));
  select.value = names.includes(chosen) ? chosen : names[0] || '';
  select.disabled = $('#smb-save').disabled = !names.length;
}
function smbShow(saved) {
  smbSaved = saved;
  $('#smb-server').value = saved.server; $('#smb-user').value = saved.user;
  $('#smb-workgroup').value = saved.workgroup; $('#smb-folder').value = saved.folder;
  $('#smb-password').value = '';
  $('#smb-password').placeholder = saved.password ? i18n.t('Saved on your PS5') : '';
  $('#smb-forget').hidden = !saved.server;
  if (saved.share) smbShares([saved.share], saved.share);
  else {
    $('#smb-share').replaceChildren(new Option('Test the connection to list the shares', ''));
    $('#smb-share').disabled = $('#smb-save').disabled = true;
  }
}
async function loadSmb() {
  smbProblem('');
  try { smbShow(await api('/api/smb')); }
  catch (error) { smbProblem(error.message); }
}
// The console answers once it has signed in, or given up (5 seconds a step).
async function smbAsk(button, busy, path, body, method = 'POST') {
  const label = button.textContent;
  button.disabled = true; button.textContent = busy; smbProblem(''); $('#smb-status').textContent = '';
  try { return await api(path, { method, body: body && JSON.stringify(body), signal: AbortSignal.timeout(60000) }); }
  catch (error) { smbProblem(error.message); return null; }
  finally { button.disabled = false; button.textContent = label; }
}
async function testSmb() {
  const answer = await smbAsk($('#smb-test'), 'Connecting…', '/api/smb/shares', smbServer());
  if (!answer) return;
  smbShares(answer.shares, $('#smb-share').value || smbSaved?.share);
  $('#smb-status').textContent = i18n.t(answer.shares.length ? 'Connected. Choose the share your games are in.'
    : 'Connected, but this server shares no folders.');
}
async function saveSmb(event) {
  event.preventDefault();
  const saved = await smbAsk($('#smb-save'), 'Saving…', '/api/smb',
    { ...smbServer(), share: $('#smb-share').value, folder: $('#smb-folder').value.trim() });
  if (!saved) return;
  smbShow(saved);
  $('#smb-status').textContent = i18n.t('Saved. In RetroArch, Load Content shows this folder under SMB.');
}
async function forgetSmb() {
  if (!confirm(i18n.t('Forget this server? RetroArch stops showing it under SMB.'))) return;
  const saved = await smbAsk($('#smb-forget'), 'Forgetting…', '/api/smb', null, 'DELETE');
  if (!saved) return;
  smbShow(saved);
  $('#smb-status').textContent = i18n.t('The server is forgotten.');
}
// Another server or user is another list of shares.
for (const id of ['#smb-server', '#smb-user'])
  $(id).addEventListener('input', () => {
    $('#smb-share').replaceChildren(new Option('Test the connection to list the shares', ''));
    $('#smb-share').disabled = $('#smb-save').disabled = true;
  });
$('#smb-test').addEventListener('click', testSmb);
$('#smb-form').addEventListener('submit', saveSmb);
$('#smb-forget').addEventListener('click', forgetSmb);
function smbShown() { if (pageFromHash() === 'smb') loadSmb(); }
window.addEventListener('hashchange', smbShown);
smbShown();
