# mpv Options GUI

A small native-window app to browse (and, later, edit) the mpv keybindings in
`input.conf`, plus your own personal keywords for finding binds quickly.

Built on **Python + pywebview** (uses the WebView2 runtime already on Windows 11).

## Run
- **From mpv** (normal use): right-click menu → **Options**
  (or bind a key to `script-binding options_gui/open`). This launches it
  **without a console window** (via `pyw`), through `scripts/options_gui.lua`.
- **First run / setup:** double-click **`launch.bat`** once — it installs the
  `pywebview` dependency (that step uses a visible console). After that, the
  mpv launch works silently.
- From a terminal: `py app.py`.

Shortcut inside the window: **Ctrl+F** focuses the filter box.

## What it does
- Reads `input.conf` and lists every active bind, with the file's section
  headers (Mouse, F-Keys, A–Z, …) shown as separators.
- **Filter box** searches keys, commands *and* your keywords.
- **Keywords** column: tag any bind with your own words to find it later.
  Type and press Enter/comma to add, Backspace on an empty field to remove the
  last one. Keywords are **personal** and stored in `~~/bind_keywords.json`
  (keyed by the bind's key) — editing them never touches `input.conf`.
- **Edit raw file** (small button, top-right): opens `input.conf` in your text
  editor for the rare case you want to edit it directly. Normally unused.
- **+ New bind / ✎ Edit / 🗑 Delete.** Editing writes `input.conf`, but always
  backs it up to `input.conf.bak` first, only rewrites the target line, and
  keeps your comments & sections intact. New binds land in a `#  Custom  #`
  section at the end. Rebinding a key migrates its keywords automatically.
- **🎯 Capture**: press a shortcut and it fills in the mpv key name
  (AZERTY-aware — reads the produced character, e.g. `²`, `&`, `CTRL+ALT+€`).
  You can also type the key by hand (e.g. `MBTN_LEFT`, `WHEEL_UP`).

## Settings pages (beyond Keybinds)
The left menu also holds **setting pages** generated from a declarative schema in
`app.py` (`SCHEMA`). Each setting is one record saying its page/section, control
type and where it persists (a `script-opts/*.conf` key or a state JSON key).
Changing a control writes the file immediately (with a `.bak` backup).

- Implemented: **Video** (anime mode/engine, Anime4K per resolution, HDR),
  **Audio** (processing), **Playback** (skip intro/outro, history) — all backed
  by `script-opts/*.conf` + state JSON. Pending: **Subtitles / Interface /
  General** (these lean on `mpv.conf` keys, which sit inside profiles and need a
  profile-aware writer) and the 15-band EQ (needs per-band frequency labels).
- To add a setting: append a record to `SCHEMA` — no UI code needed.

## Reload / Reload & Close
Two footer buttons: **Reload** (apply now, keep the window open to test) and
**Reload & Close**. Both send one command to a running mpv through its existing
IPC pipe `\\.\pipe\mpvpipe` (already set by mpv.conf's `[SVP-Windows-Patch]`
profile for normal video) to trigger your `reload_mpv/reload`. If mpv isn't
running — or for 8K / audio-only where that pipe is off — changes simply apply
next launch.

## Files
| File | Role |
|------|------|
| `app.py` | Backend: parse `input.conf`, load/save keywords |
| `ui/` | The web interface (HTML/CSS/JS) shown in the native window |
| `launch.bat` | Double-click launcher |
