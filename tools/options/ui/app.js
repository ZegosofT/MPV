'use strict';

let BINDS = [];
let SETTINGS = [];
let SETTINGS_PAGES = [];
let activePage = 'keybinds';

const $ = (sel) => document.querySelector(sel);

// modal refs
const modal = $('#modal'), modalTitle = $('#modal-title');
const keyInput = $('#m-key'), cmdInput = $('#m-cmd');
const captureBtn = $('#m-capture'), warnEl = $('#m-warn');
let editCtx = null, capturing = false;

// ---- pywebview bootstrap ---------------------------------------------------
function whenReady(fn) {
  if (window.pywebview && window.pywebview.api) fn();
  else window.addEventListener('pywebviewready', fn, { once: true });
}

whenReady(reloadData);

async function reloadData() {
  const data = await window.pywebview.api.get_data();
  BINDS = data.binds || [];
  $('#paths').textContent = data.input_conf || '';
  $('#paths').title = `binds: ${data.input_conf}\nkeywords: ${data.keywords_path}`;
  const s = await window.pywebview.api.get_settings();
  SETTINGS = s.settings || [];
  SETTINGS_PAGES = s.pages || [];
  buildMenu();
  render();
}

// ---- left menu -------------------------------------------------------------
function buildMenu() {
  const nav = $('#menu');
  nav.innerHTML = '';
  const pages = [{ id: 'keybinds', label: 'Keybinds', n: BINDS.length }]
    .concat(SETTINGS_PAGES.map(p => ({ id: p, label: p })));
  for (const p of pages) {
    const el = document.createElement('div');
    el.className = 'menu-item' + (p.id === activePage ? ' active' : '');
    const n = (p.n != null) ? `<span class="n">${p.n}</span>` : '';
    el.innerHTML = `<span>${escapeHtml(p.label)}</span>${n}`;
    el.onclick = () => { activePage = p.id; buildMenu(); render(); };
    nav.appendChild(el);
  }
}

// ---- page switch -----------------------------------------------------------
function render() {
  const isKb = activePage === 'keybinds';
  $('#panel-title').textContent = isKb ? 'Keybinds' : activePage;
  $('#kb-tools').hidden = !isKb;
  $('#keybinds-view').hidden = !isKb;
  $('#settings-view').hidden = isKb;
  if (isKb) renderKeybinds();
  else renderSettings(activePage);
}

// ============================================================================
//  KEYBINDS view
// ============================================================================
function renderKeybinds() {
  const q = $('#filter').value.trim().toLowerCase();
  const rows = $('#rows');
  rows.innerHTML = '';

  const visible = BINDS.filter(b => {
    if (!q) return true;
    const hay = [b.key, b.command, b.note, (b.keywords || []).join(' ')].join(' ').toLowerCase();
    return hay.includes(q);
  });

  let lastSection = null;
  for (const b of visible) {
    if (b.section !== lastSection) {
      lastSection = b.section;
      rows.appendChild(renderGroup(b.section));
    }
    rows.appendChild(renderBindRow(b));
  }

  $('#count').textContent = `${visible.length} of ${BINDS.length} binds`;
  $('#empty').hidden = visible.length !== 0;
}

function renderGroup(name) {
  const tr = document.createElement('tr');
  tr.className = 'group';
  tr.innerHTML = `<td colspan="4">${escapeHtml(name)}</td>`;
  return tr;
}

function renderBindRow(b) {
  const tr = document.createElement('tr');

  const tdKey = document.createElement('td');
  tdKey.innerHTML = `<span class="key-badge">${escapeHtml(b.key)}</span>`;

  const tdCmd = document.createElement('td');
  if (b.command) {
    tdCmd.innerHTML = `<span class="cmd">${escapeHtml(b.command)}` +
      (b.note ? ` <span class="note"># ${escapeHtml(b.note)}</span>` : '') + `</span>`;
  } else {
    tdCmd.innerHTML = `<span class="cmd empty">(unbound)</span>`;
  }

  const tdKw = document.createElement('td');
  tdKw.className = 'kw-cell';
  tdKw.appendChild(bindKeywordEditor(b));

  const tdAct = document.createElement('td');
  tdAct.className = 'actions';
  tdAct.append(
    iconBtn('✎', 'Edit', () => openEditor('edit', b)),
    iconBtn('🗑', 'Delete', () => confirmDelete(tdAct, b), 'danger')
  );

  tr.append(tdKey, tdCmd, tdKw, tdAct);
  return tr;
}

function iconBtn(label, title, onClick, extra) {
  const b = document.createElement('button');
  b.className = 'icon-btn' + (extra ? ' ' + extra : '');
  b.textContent = label; b.title = title; b.onclick = onClick;
  return b;
}

function confirmDelete(td, b) {
  td.innerHTML = '';
  const span = document.createElement('span');
  span.className = 'confirm'; span.textContent = 'Delete?';
  const yes = iconBtn('✓', 'Confirm delete', async () => {
    const res = await window.pywebview.api.delete_bind(b.line, b.key);
    if (!res.ok) { toast(res.error || 'Delete failed', true); renderKeybinds(); return; }
    await reloadData();
    toast('Deleted — Reload & Close to apply');
  }, 'danger');
  const no = iconBtn('✗', 'Cancel', () => renderKeybinds());
  td.append(span, yes, no);
}

function bindKeywordEditor(b) {
  return chipEditor(b.keywords || [], async (list) => {
    b.keywords = await window.pywebview.api.set_keywords(b.key, list);
    return b.keywords;
  });
}

// ============================================================================
//  SETTINGS view (schema-driven)
// ============================================================================
function renderSettings(page) {
  const view = $('#settings-view');
  view.innerHTML = '';
  const items = SETTINGS.filter(s => s.page === page);
  let lastSection = null;
  for (const s of items) {
    if (s.type === 'about') { view.appendChild(aboutPanel()); continue; }
    if (s.section !== lastSection) {
      lastSection = s.section;
      const h = document.createElement('div');
      h.className = 'set-section-title';
      h.textContent = s.section;
      view.appendChild(h);
    }
    view.appendChild(renderSettingRow(s));
  }
  if (items.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = 'No settings here yet.';
    view.appendChild(empty);
  }
  $('#count').textContent = items.some(s => s.type === 'about') ? '' : `${items.length} settings`;
}

// ---- About & Updates panel -------------------------------------------------
function aboutPanel() {
  const box = document.createElement('div'); box.className = 'about';
  refreshAbout(box);
  return box;
}

async function refreshAbout(box) {
  const a = await window.pywebview.api.get_about();
  box.innerHTML = '';

  const mpvSec = aboutSection('mpv');
  mpvSec.appendChild(aboutRow('Version', a.mpv_version));
  mpvSec.appendChild(aboutActions(mkBtn('Update mpv…', 'btn primary', async () => {
    const r = await window.pywebview.api.update_mpv();
    toast(r && r.ok ? 'Launching mpv updater — accept the UAC prompt.' : (r && r.error) || 'Failed', !(r && r.ok));
  })));
  box.appendChild(mpvSec);

  const buildSec = aboutSection('This build');
  buildSec.appendChild(aboutRow('Base', aboutLink(a.base_label, a.base_url)));
  buildSec.appendChild(aboutRow('Customized by', aboutLink(a.author + ' — GitHub', a.author_url)));
  buildSec.appendChild(aboutRow('Config version', a.config_version));

  const status = document.createElement('div'); status.className = 'about-status';
  const check = mkBtn('Check for update', 'btn', async () => {
    status.textContent = 'Checking…';
    const r = await window.pywebview.api.check_config_update();
    if (!r.ok) { status.textContent = 'Check failed: ' + (r.error || ''); return; }
    status.textContent = r.update_available
      ? `🔔 Update available: ${r.local} → ${r.remote}`
      : `✓ Up to date (${r.local}).`;
  });
  const updCfg = mkBtn('Update config…', 'btn primary', async () => {
    const r = await window.pywebview.api.update_config();
    toast(r && r.ok ? 'Updating config — follow the window, then Reload mpv.' : (r && r.error) || 'Failed', !(r && r.ok));
  });
  buildSec.appendChild(aboutActions(check, updCfg));
  buildSec.appendChild(status);
  box.appendChild(buildSec);
}

function aboutSection(title) {
  const sec = document.createElement('div'); sec.className = 'about-sec';
  const h = document.createElement('h3'); h.textContent = title; sec.appendChild(h);
  return sec;
}
function aboutRow(key, valueOrEl) {
  const row = document.createElement('div'); row.className = 'about-row';
  const k = document.createElement('span'); k.className = 'k'; k.textContent = key;
  const v = document.createElement('span'); v.className = 'v';
  if (valueOrEl instanceof Node) v.appendChild(valueOrEl); else v.textContent = valueOrEl;
  row.append(k, v); return row;
}
function aboutLink(text, url) {
  const a = document.createElement('a'); a.className = 'about-link'; a.href = '#'; a.textContent = text;
  a.onclick = (e) => { e.preventDefault(); window.pywebview.api.open_url(url); };
  return a;
}
function aboutActions() {
  const r = document.createElement('div'); r.className = 'about-actions';
  for (let i = 0; i < arguments.length; i++) r.appendChild(arguments[i]);
  return r;
}

function renderSettingRow(s) {
  const row = document.createElement('div');
  row.className = 'set-row' + (s.type === 'presets' ? ' set-row-block' : '');

  const label = document.createElement('div');
  label.className = 'set-label';
  label.innerHTML = `<div class="name">${escapeHtml(s.label)}</div>` +
    (s.help ? `<div class="help">${escapeHtml(s.help)}</div>` : '');

  const control = document.createElement('div');
  control.className = 'set-control' +
    (s.type === 'keywords' ? ' wide' : '') + (s.type === 'presets' ? ' full' : '');
  control.appendChild(buildControl(s));

  row.append(label, control);
  return row;
}

async function saveSetting(id, value) {
  const res = await window.pywebview.api.set_setting(id, value);
  if (!res || !res.ok) toast((res && res.error) || 'Save failed', true);
}

function buildControl(s) {
  if (s.type === 'presets') return presetManager();
  if (s.type === 'toggle') return toggleControl(s);
  if (s.type === 'number') return numberControl(s);
  if (s.type === 'color') return colorControl(s);
  if (s.type === 'choice') return choiceControl(s);
  if (s.type === 'keywords') {
    const editor = chipEditor(s.value || [], async (list) => { await saveSetting(s.id, list); return list; });
    if (s.browse === 'folder') {
      const box = document.createElement('div'); box.className = 'kw-browse';
      const browse = document.createElement('button'); browse.type = 'button';
      browse.className = 'btn-ghost'; browse.textContent = '📁 Browse…';
      browse.onclick = async () => {
        const folder = await window.pywebview.api.pick_folder();
        if (folder) editor.addItem(folder);
      };
      box.append(editor, browse);
      return box;
    }
    return editor;
  }
  return textControl(s);
}

function toggleControl(s) {
  const lab = document.createElement('label'); lab.className = 'switch';
  const input = document.createElement('input'); input.type = 'checkbox'; input.checked = !!s.value;
  const track = document.createElement('span'); track.className = 'track';
  const knob = document.createElement('span'); knob.className = 'knob';
  input.addEventListener('change', () => { s.value = input.checked; saveSetting(s.id, input.checked); });
  lab.append(input, track, knob);
  return lab;
}

function numberControl(s) {
  const input = document.createElement('input'); input.type = 'number';
  if (s.min != null) input.min = s.min;
  if (s.max != null) input.max = s.max;
  if (s.step != null) input.step = s.step;
  input.value = s.value;
  input.addEventListener('change', () => {
    let v = parseInt(input.value, 10);
    if (isNaN(v)) v = (s.min != null ? s.min : 0);
    if (s.min != null) v = Math.max(s.min, v);
    if (s.max != null) v = Math.min(s.max, v);
    input.value = v; s.value = v; saveSetting(s.id, v);
  });
  return input;
}

function textControl(s) {
  const input = document.createElement('input'); input.type = 'text'; input.value = s.value || '';
  input.addEventListener('change', () => { s.value = input.value; saveSetting(s.id, input.value); });
  return input;
}

function choiceControl(s) {
  const sel = document.createElement('select');
  (s.options || []).forEach(o => {
    const value = (o && typeof o === 'object') ? o.v : o;   // supports {v,l} or a plain string
    const label = (o && typeof o === 'object') ? o.l : o;
    const opt = document.createElement('option');
    opt.value = value; opt.textContent = label;
    if (value === s.value) opt.selected = true;
    sel.appendChild(opt);
  });
  sel.addEventListener('change', () => { s.value = sel.value; saveSetting(s.id, sel.value); });
  return sel;
}

function colorControl(s) {
  // mpv color is "#AARRGGBB" (alpha first) or "#RRGGBB".
  const wrap = document.createElement('div'); wrap.className = 'color-wrap';
  const v = String(s.value || '').replace(/^#/, '');
  let aa = 'FF', rgb = 'FFFFFF';
  if (v.length === 8) { aa = v.slice(0, 2); rgb = v.slice(2); }
  else if (v.length === 6) { aa = 'FF'; rgb = v; }

  const swatch = document.createElement('input');
  swatch.type = 'color'; swatch.value = '#' + rgb;
  const alpha = document.createElement('input');
  alpha.type = 'range'; alpha.min = 0; alpha.max = 255;
  alpha.value = parseInt(aa, 16) || 0; alpha.className = 'color-alpha';
  const out = document.createElement('span'); out.className = 'color-hex';

  const a2 = () => ('0' + Number(alpha.value).toString(16)).slice(-2).toUpperCase();
  function compose() {
    const h = '#' + a2() + swatch.value.replace(/^#/, '').toUpperCase();
    out.textContent = h + '  ·  ' + Math.round(alpha.value / 255 * 100) + '%';
    return h;
  }
  function save() { const h = compose(); s.value = h; saveSetting(s.id, h); }
  swatch.addEventListener('input', compose);
  swatch.addEventListener('change', save);
  alpha.addEventListener('input', compose);
  alpha.addEventListener('change', save);
  compose();
  wrap.append(swatch, alpha, out);
  return wrap;
}

// ============================================================================
//  Preset manager (select / apply / save-as / delete)
// ============================================================================
function presetManager() {
  const box = document.createElement('div'); box.className = 'preset-mgr';
  refreshPresets(box);
  return box;
}

async function refreshPresets(box) {
  const data = await window.pywebview.api.get_presets();
  box.innerHTML = '';
  const row = document.createElement('div'); row.className = 'preset-row';

  const sel = document.createElement('select'); sel.className = 'preset-select';
  data.presets.forEach(p => {
    const o = document.createElement('option');
    o.value = p.name;
    o.textContent = p.builtin ? p.name : '★ ' + p.name;
    if (p.name === data.current) o.selected = true;
    sel.appendChild(o);
  });

  const isBuiltin = () => { const p = data.presets.find(x => x.name === sel.value); return !p || p.builtin; };

  // Selecting a preset applies it INSTANTLY (writes the settings below + refreshes).
  sel.addEventListener('change', async () => {
    const r = await window.pywebview.api.apply_preset(sel.value);
    if (!r.ok) { toast(r.error || 'Failed', true); return; }
    await reloadData();                       // controls below jump to the preset's values
    toast(sel.value + ' applied — Reload to see it in mpv');
  });

  const update = mkBtn('Update preset', 'btn', async () => {
    const r = await window.pywebview.api.save_preset(sel.value);   // overwrite THIS (user) preset
    if (!r.ok) { toast(r.error || 'Failed', true); return; }
    toast('Saved your changes into “' + sel.value + '”');
  });
  const saveNew = mkBtn('Save as new…', 'btn', () => showSaveAs(box));
  const del = mkBtn('Delete', 'btn', async () => {
    const r = await window.pywebview.api.delete_preset(sel.value);
    if (!r.ok) { toast(r.error || 'Failed', true); return; }
    await refreshPresets(box); toast('Preset deleted');
  });

  // Built-in presets are locked: can't be overwritten or deleted.
  const locked = isBuiltin();
  update.disabled = locked;
  del.disabled = locked;
  update.title = locked ? 'Built-in presets are locked — use “Save as new…”' : 'Save current settings into this preset';
  del.title = locked ? 'Built-in presets can’t be deleted' : '';

  row.append(sel, update, saveNew, del);
  box.appendChild(row);

  renderFolderRules(box, data.presets);
}

// Per-folder auto-apply rules: [folder] → [preset]. Most specific folder wins;
// a folder in no rule plays raw (no enhancement).
async function renderFolderRules(box, presets) {
  const data = await window.pywebview.api.get_folder_rules();
  let rules = data.rules || [];

  const wrap = document.createElement('div'); wrap.className = 'folder-rules';
  const head = document.createElement('div'); head.className = 'fr-head';
  head.textContent = 'Auto-apply by folder — most specific folder wins; a folder in no rule plays raw (no enhancement).';
  wrap.appendChild(head);

  const save = () => window.pywebview.api.save_folder_rules(rules);

  const addBtn = mkBtn('+ Add folder', 'btn', async () => {
    const folder = await window.pywebview.api.pick_folder();
    if (!folder) return;
    rules.push({ folder: folder, preset: (presets[0] ? presets[0].name : 'Off') });
    save(); drawRows();
  });

  const drawRows = () => {
    wrap.querySelectorAll('.fr-row').forEach(r => r.remove());
    rules.forEach((rule, i) => {
      const r = document.createElement('div'); r.className = 'fr-row';
      const folder = document.createElement('input');
      folder.type = 'text'; folder.value = rule.folder; folder.readOnly = true;
      folder.className = 'fr-folder'; folder.title = rule.folder;
      const sel = document.createElement('select'); sel.className = 'fr-preset';
      presets.forEach(p => {
        const o = document.createElement('option');
        o.value = p.name; o.textContent = p.builtin ? p.name : '★ ' + p.name;
        if (p.name === rule.preset) o.selected = true;
        sel.appendChild(o);
      });
      sel.onchange = () => { rule.preset = sel.value; save(); };
      const del = mkBtn('✕', 'fr-del', () => { rules.splice(i, 1); save(); drawRows(); });
      r.append(folder, sel, del);
      wrap.insertBefore(r, addBtn);
    });
  };

  wrap.appendChild(addBtn);
  drawRows();
  box.appendChild(wrap);
}

function showSaveAs(box) {
  const bar = document.createElement('div'); bar.className = 'preset-saveas';
  const input = document.createElement('input');
  input.type = 'text'; input.placeholder = 'New preset name…'; input.autocomplete = 'off';
  const ok = mkBtn('Save', 'btn primary', async () => {
    const name = input.value.trim();
    if (!name) { input.focus(); return; }
    const r = await window.pywebview.api.save_preset(name);
    if (!r.ok) { toast(r.error || 'Failed', true); return; }
    await refreshPresets(box); toast('Saved “' + name + '”');
  });
  const cancel = mkBtn('Cancel', 'btn', () => refreshPresets(box));
  bar.append(input, ok, cancel);
  box.appendChild(bar);
  input.focus();
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') ok.click(); });
}

function mkBtn(label, cls, onClick) {
  const b = document.createElement('button');
  b.type = 'button'; b.className = cls; b.textContent = label; b.onclick = onClick;
  return b;
}

// ============================================================================
//  Shared chip editor (used by bind keywords AND keyword-type settings)
//  `commit(list)` persists and returns the saved list.
// ============================================================================
function chipEditor(initial, commit) {
  const wrap = document.createElement('div'); wrap.className = 'kw';
  let list = (initial || []).slice();
  const input = document.createElement('input'); input.className = 'kw-input';

  const apply = async (next) => { list = (await commit(next)) || next; renderChips(); flashSaved(wrap); };

  const renderChips = () => {
    wrap.querySelectorAll('.chip').forEach(c => c.remove());
    list.forEach((kw, idx) => {
      const chip = document.createElement('span'); chip.className = 'chip';
      const txt = document.createElement('span'); txt.textContent = kw;
      const x = document.createElement('button'); x.className = 'chip-x'; x.type = 'button';
      x.textContent = '×'; x.title = 'Remove';
      x.onmousedown = (e) => e.preventDefault();           // avoid input blur racing the click
      x.onclick = () => { const next = list.slice(); next.splice(idx, 1); apply(next); };
      chip.append(txt, x);
      wrap.insertBefore(chip, input);
    });
    input.placeholder = 'add…';
  };

  const flush = () => {
    const typed = input.value.split(',').map(x => x.trim()).filter(Boolean);
    if (!typed.length) return;
    input.value = '';
    apply([...list, ...typed]);
  };

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ',') { e.preventDefault(); flush(); }
    else if (e.key === 'Backspace' && input.value === '' && list.length) {
      e.preventDefault(); apply(list.slice(0, -1));
    }
  });
  input.addEventListener('blur', () => { if (input.value.trim()) flush(); });

  // Let outside code (e.g. the Browse button) push a value in.
  wrap.addItem = (val) => {
    val = String(val).trim();
    if (val && !list.includes(val)) apply([...list, val]);
  };

  wrap.appendChild(input); renderChips();
  return wrap;
}

function flashSaved(wrap) {
  const cell = wrap.closest('.kw-cell');
  if (!cell) return;
  cell.classList.remove('saved'); void cell.offsetWidth; cell.classList.add('saved');
}

// ============================================================================
//  Add / edit bind dialog
// ============================================================================
function openEditor(mode, bind) {
  editCtx = { mode, line: bind ? bind.line : null, oldKey: bind ? bind.key : null };
  modalTitle.textContent = mode === 'add' ? 'New bind' : 'Edit bind';
  keyInput.value = bind ? bind.key : '';
  cmdInput.value = bind ? bind.command : '';
  warnEl.textContent = '';
  modal.hidden = false;
  stopCapture();
  checkDup();
  (mode === 'add' ? keyInput : cmdInput).focus();
}

function closeEditor() { modal.hidden = true; editCtx = null; stopCapture(); }

function checkDup() {
  const key = keyInput.value.trim();
  warnEl.textContent = '';
  if (!key) return;
  const clash = BINDS.find(b => b.key === key &&
    !(editCtx && b.line === editCtx.line && b.key === editCtx.oldKey));
  if (clash) {
    warnEl.textContent = `⚠ "${key}" is already bound (${clash.command || 'unbound'}). ` +
      `The last matching line in input.conf wins.`;
  }
}

async function saveEditor() {
  const key = keyInput.value.trim();
  const cmd = cmdInput.value.trim();
  if (!key) { warnEl.textContent = 'Key is required.'; return; }
  if (!cmd) { warnEl.textContent = 'Command is required.'; return; }

  const res = editCtx.mode === 'add'
    ? await window.pywebview.api.add_bind(key, cmd)
    : await window.pywebview.api.update_bind(editCtx.line, editCtx.oldKey, key, cmd);

  if (!res.ok) { warnEl.textContent = res.error || 'Failed.'; return; }
  closeEditor();
  await reloadData();
  toast('Saved — Reload & Close to apply');
}

// ---- key capture (AZERTY-aware) --------------------------------------------
const SPECIAL_KEYS = {
  ArrowLeft: 'LEFT', ArrowRight: 'RIGHT', ArrowUp: 'UP', ArrowDown: 'DOWN',
  Enter: 'ENTER', Backspace: 'BS', Tab: 'TAB', ' ': 'SPACE', Escape: 'ESC',
  PageUp: 'PGUP', PageDown: 'PGDWN', Home: 'HOME', End: 'END',
  Insert: 'INS', Delete: 'DEL',
};

function mpvKeyFromEvent(e) {
  const k = e.key;
  if (['Control', 'Alt', 'Shift', 'Meta', 'AltGraph', 'Dead'].includes(k)) return null;

  let key, printable = false;
  if (SPECIAL_KEYS[k]) key = SPECIAL_KEYS[k];
  else if (/^F\d{1,2}$/.test(k)) key = k.toUpperCase();
  else if (k.length === 1) { key = k; printable = true; }
  else return null;

  const mods = [];
  if (e.ctrlKey) mods.push('CTRL');
  if (e.altKey) mods.push('ALT');
  if (e.shiftKey && !printable) mods.push('SHIFT');
  if (e.metaKey) mods.push('META');
  return mods.concat(key).join('+');
}

function startCapture() {
  capturing = true; keyInput.value = '';
  keyInput.placeholder = 'Press a shortcut…  (Esc to cancel)';
  captureBtn.textContent = '● listening'; captureBtn.classList.add('listening');
  keyInput.focus();
}
function stopCapture() {
  capturing = false; captureBtn.textContent = '🎯 Capture';
  captureBtn.classList.remove('listening'); keyInput.placeholder = 'e.g. CTRL+ALT+x';
}

// ---- events ----------------------------------------------------------------
$('#filter').addEventListener('input', renderKeybinds);
$('#new-bind').addEventListener('click', () => openEditor('add'));
$('#open-raw').addEventListener('click', async () => {
  const res = await window.pywebview.api.open_input_conf();
  toast(res && res.ok ? 'Opened input.conf in your editor' : (res && res.error) || 'Could not open input.conf', !(res && res.ok));
});
$('#reload-only').addEventListener('click', async () => {
  const res = await window.pywebview.api.reload();
  toast(res && res.reloaded ? 'Reloading mpv…' : 'Saved — applies next time mpv starts');
});
$('#reload-close').addEventListener('click', async () => {
  const res = await window.pywebview.api.reload_and_close();
  toast(res && res.reloaded ? 'Reloading mpv…' : 'Saved — applies next time mpv starts');
});
$('#m-cancel').addEventListener('click', closeEditor);
$('#m-save').addEventListener('click', saveEditor);
captureBtn.addEventListener('click', () => capturing ? stopCapture() : startCapture());
keyInput.addEventListener('input', checkDup);
modal.addEventListener('mousedown', (e) => { if (e.target === modal) closeEditor(); });

document.addEventListener('keydown', (e) => {
  if (capturing) {
    e.preventDefault(); e.stopPropagation();
    if (e.key === 'Escape') { stopCapture(); return; }
    const k = mpvKeyFromEvent(e);
    if (k) { keyInput.value = k; stopCapture(); checkDup(); }
    return;
  }
  if (e.ctrlKey && (e.key === 'f' || e.key === 'F')) {
    if (activePage === 'keybinds') { e.preventDefault(); const f = $('#filter'); f.focus(); f.select(); }
    return;
  }
  if (modal.hidden) return;
  if (e.key === 'Escape') { e.preventDefault(); closeEditor(); }
  else if (e.key === 'Enter') { e.preventDefault(); saveEditor(); }
});

// ---- misc ------------------------------------------------------------------
let toastTimer;
function toast(msg, isError) {
  const t = $('#toast');
  t.textContent = msg;
  t.classList.toggle('error', !!isError);
  t.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, 2800);
}

function escapeHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
