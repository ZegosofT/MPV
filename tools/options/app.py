"""
mpv Options GUI — backend (v1, read-only for binds).

Parses input.conf and shows it in a native window (pywebview + WebView2).
Keywords are PERSONAL and stored separately in ~~/bind_keywords.json, keyed by
the bind's key (which is unique in input.conf), so tagging a bind never touches
the shared input.conf. v2 will add create / edit / rebind (writing input.conf
with a .bak backup first).

`import webview` is intentionally deferred into main() so the parser can be
unit-tested / run without the GUI dependency installed.
"""

import json
import os
import re
import shutil
import threading

# tools/options/app.py  ->  <mpv config root>
MPV_DIR       = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INPUT_CONF    = os.path.join(MPV_DIR, "input.conf")
KEYWORDS_PATH = os.path.join(MPV_DIR, "bind_keywords.json")
UI_DIR        = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui")

# "#  Mouse  #"  -> section "Mouse".  (Plain "####" dividers and "# note" lines are ignored.)
_SECTION_RE = re.compile(r"^#\s+(.+?)\s+#+\s*$")
_DIVIDER_RE = re.compile(r"^#+$")


def _read_text(path):
    """Read a config file as text, tolerant of encoding (é, è, à, ², € ...)."""
    try:
        with open(path, "rb") as f:
            raw = f.read()
    except OSError:
        return None
    for enc in ("utf-8-sig", "utf-8", "cp1252"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def parse_input_conf():
    """Return active binds as a list of dicts: {line, key, command, note, section}."""
    text = _read_text(INPUT_CONF)
    if text is None:
        return []

    binds = []
    section = "General"
    for i, raw in enumerate(text.splitlines()):
        stripped = raw.strip()
        if stripped == "":
            continue
        if stripped.startswith("#"):
            m = _SECTION_RE.match(stripped)
            if m and not _DIVIDER_RE.match(stripped):
                section = m.group(1).strip()
            continue  # comments / disabled binds are skipped in v1

        # Bind line: first whitespace-delimited token is the key, the rest the command.
        parts = raw.split(None, 1)
        key = parts[0]
        rest = parts[1].strip() if len(parts) > 1 else ""

        # Split off a trailing inline comment ("  # ...").  Commands in this config
        # never contain " #", so the first occurrence is safely the comment.
        command, note = rest, ""
        idx = rest.find(" #")
        if idx != -1:
            command = rest[:idx].strip()
            note = rest[idx + 2:].strip().lstrip("#").strip()

        binds.append({
            "line": i,
            "key": key,
            "command": command,
            "note": note,
            "section": section,
        })
    return binds


def load_keywords():
    text = _read_text(KEYWORDS_PATH)
    if not text:
        return {}
    try:
        data = json.loads(text)
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}


def save_keywords(data):
    with open(KEYWORDS_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


# ----------------------------------------------------------------------------
# Writing input.conf (v2). We always back up to input.conf.bak first, only touch
# the one target line, and keep the file's comments / section headers intact.
# ----------------------------------------------------------------------------
_PAD = 48  # column where commands align, matching the existing file's style


def _format_bind(key, command, note=""):
    left = key.ljust(_PAD) if len(key) < _PAD else key + " "
    line = left + command
    if note:
        line += "    # " + note
    return line


def _extract_note(raw):
    parts = raw.split(None, 1)
    if len(parts) < 2:
        return ""
    rest = parts[1].strip()
    idx = rest.find(" #")
    return rest[idx + 2:].strip().lstrip("#").strip() if idx != -1 else ""


def _line_key(raw):
    return raw.split(None, 1)[0] if raw.strip() else ""


def _load_lines():
    text = _read_text(INPUT_CONF)
    if text is None:
        return None, None
    newline = "\r\n" if "\r\n" in text else "\n"
    return text.splitlines(), newline


def _backup():
    if os.path.exists(INPUT_CONF):
        shutil.copy2(INPUT_CONF, INPUT_CONF + ".bak")


def _write_lines(lines, newline):
    _backup()
    content = newline.join(lines)
    if not content.endswith(newline):
        content += newline
    with open(INPUT_CONF, "w", encoding="utf-8", newline="") as f:
        f.write(content)


# ============================================================================
#  Settings engine (declarative schema -> generic UI)
#  Each setting is ONE record below; the UI is generated from this list, and
#  each record declares where it persists. Writing always backs up first.
#  To add a setting later: append a record with the right page/section.
# ============================================================================
SCRIPT_OPTS = os.path.join(MPV_DIR, "script-opts")

_window = None  # set in main(); used by reload_and_close()


def _store_path(store):
    # conf files live in script-opts/, json state files in the config root.
    base = SCRIPT_OPTS if store["kind"] == "conf" else MPV_DIR
    return os.path.join(base, store["file"])


def _backup_file(path):
    if os.path.exists(path):
        shutil.copy2(path, path + ".bak")


def _read_conf_value(path, key):
    text = _read_text(path)
    if text is None:
        return None
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("#") or "=" not in s:
            continue
        if s.split("=", 1)[0].strip() == key:
            return s.split("=", 1)[1].strip()
    return None


def _write_conf_value(path, key, raw):
    text = _read_text(path)
    newline = "\r\n" if (text and "\r\n" in text) else "\n"
    lines = text.splitlines() if text is not None else []
    found = False
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("#") or "=" not in s:
            continue
        if s.split("=", 1)[0].strip() == key:
            lines[i] = key + "=" + raw
            found = True
            break
    if not found:
        lines.append(key + "=" + raw)
    _backup_file(path)
    content = newline.join(lines)
    if not content.endswith(newline):
        content += newline
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(content)


def _read_json_value(path, key):
    text = _read_text(path)
    if not text:
        return None
    try:
        data = json.loads(text)
    except ValueError:
        return None
    return data.get(key) if isinstance(data, dict) else None


def _write_json_value(path, key, value):
    text = _read_text(path)
    data = {}
    if text:
        try:
            parsed = json.loads(text)
            if isinstance(parsed, dict):
                data = parsed
        except ValueError:
            pass
    data[key] = value
    _backup_file(path)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _read_store(store):
    if store["kind"] == "conf":
        return _read_conf_value(_store_path(store), store["key"])
    return _read_json_value(_store_path(store), store["key"])


def _write_store(store, encoded):
    if store["kind"] == "conf":
        _write_conf_value(_store_path(store), store["key"], encoded)
    else:
        _write_json_value(_store_path(store), store["key"], encoded)


def _blank(t):
    return {"toggle": False, "number": 0, "keywords": []}.get(t, "")


def _decode(entry, raw):
    """storage -> UI value"""
    t, kind = entry["type"], entry["store"]["kind"]
    if kind == "json":
        if raw is None:
            return entry.get("default", _blank(t))
        if t == "toggle":
            return bool(raw)
        if t == "number":
            return raw if isinstance(raw, (int, float)) else entry.get("default", 0)
        if t == "keywords":
            return raw if isinstance(raw, list) else []
        return raw
    if raw is None:
        return entry.get("default", _blank(t))
    if t == "toggle":
        return raw.strip().lower() in ("yes", "true", "1", "on")
    if t == "number":
        try:
            return int(raw.strip())
        except ValueError:
            try:
                return float(raw.strip())
            except ValueError:
                return entry.get("default", 0)
    if t == "keywords":
        if entry.get("fmt") == "quoted":
            return re.findall(r'"([^"]*)"', raw)
        return [s.strip() for s in raw.split(";") if s.strip()]
    return raw  # text / choice


def _encode(entry, value):
    """UI value -> storage"""
    t, kind = entry["type"], entry["store"]["kind"]
    if kind == "json":
        if t == "toggle":
            return bool(value)
        if t == "number":
            return int(value)
        if t == "keywords":
            return [str(x).strip() for x in (value or []) if str(x).strip()]
        return value
    if t == "toggle":
        if entry.get("boolfmt") == "truefalse":   # anime-mode.conf uses true/false
            return "true" if value else "false"
        return "yes" if value else "no"            # history.conf etc. use yes/no
    if t == "number":
        return str(int(value))
    if t == "keywords":
        items = [str(x).strip() for x in (value or []) if str(x).strip()]
        if entry.get("fmt") == "quoted":
            return ",".join('"%s"' % i for i in items)
        return ";".join(items)
    return str(value)


_SKIP_CONF, _HIST_CONF = "skip_intro.conf", "history.conf"
_ANIME_CONF, _A4K_CONF, _HDR_CONF = "anime-mode.conf", "anime4k.conf", "hdr-mode.conf"
_SKIP_STATE = "skip_intro_state.json"

PAGE_ORDER = ["Video", "Video Enhancement", "Audio", "Subtitles", "Playback", "Interface", "General", "About & Updates"]
# Pages always shown in the sidebar even when they have no settings yet.
_ALWAYS_SHOW_PAGES = ["Video"]

SCHEMA = [
    # ---- Playback : Skip intro / outro ----
    {"id": "skip_enabled", "page": "Playback", "section": "Skip intro / outro",
     "label": "Enable auto-skip", "help": "Master switch for the skip system.",
     "type": "toggle", "default": True, "store": {"kind": "json", "file": _SKIP_STATE, "key": "enabled"}},

    {"id": "skip_intro_on", "page": "Playback", "section": "Skip intro / outro",
     "label": "Skip intros", "type": "toggle", "default": True,
     "store": {"kind": "json", "file": _SKIP_STATE, "key": "skip_intro"}},
    {"id": "intro_titles", "page": "Playback", "section": "Skip intro / outro",
     "label": "Intro chapter names", "help": "Exact chapter titles treated as an intro.",
     "type": "keywords", "fmt": "quoted", "store": {"kind": "conf", "file": _SKIP_CONF, "key": "intro"}},
    {"id": "intro_cd", "page": "Playback", "section": "Skip intro / outro",
     "label": "Intro countdown (s)", "help": "0 = instant, no prompt.", "type": "number",
     "min": 0, "max": 30, "default": 5, "store": {"kind": "conf", "file": _SKIP_CONF, "key": "intro_countdown"}},

    {"id": "skip_opening_on", "page": "Playback", "section": "Skip intro / outro",
     "label": "Skip openings (OP)", "type": "toggle", "default": True,
     "store": {"kind": "json", "file": _SKIP_STATE, "key": "skip_opening"}},
    {"id": "opening_titles", "page": "Playback", "section": "Skip intro / outro",
     "label": "Opening chapter names", "type": "keywords", "fmt": "quoted",
     "store": {"kind": "conf", "file": _SKIP_CONF, "key": "opening"}},
    {"id": "opening_cd", "page": "Playback", "section": "Skip intro / outro",
     "label": "Opening countdown (s)", "type": "number", "min": 0, "max": 30, "default": 5,
     "store": {"kind": "conf", "file": _SKIP_CONF, "key": "opening_countdown"}},

    {"id": "skip_ending_on", "page": "Playback", "section": "Skip intro / outro",
     "label": "Skip endings / previews", "help": "Also controls Preview/PV.", "type": "toggle", "default": True,
     "store": {"kind": "json", "file": _SKIP_STATE, "key": "skip_ending"}},
    {"id": "ending_titles", "page": "Playback", "section": "Skip intro / outro",
     "label": "Ending chapter names", "type": "keywords", "fmt": "quoted",
     "store": {"kind": "conf", "file": _SKIP_CONF, "key": "ending"}},
    {"id": "ending_cd", "page": "Playback", "section": "Skip intro / outro",
     "label": "Ending countdown (s)", "type": "number", "min": 0, "max": 30, "default": 5,
     "store": {"kind": "conf", "file": _SKIP_CONF, "key": "ending_countdown"}},
    {"id": "preview_titles", "page": "Playback", "section": "Skip intro / outro",
     "label": "Preview chapter names", "type": "keywords", "fmt": "quoted",
     "store": {"kind": "conf", "file": _SKIP_CONF, "key": "preview"}},
    {"id": "preview_cd", "page": "Playback", "section": "Skip intro / outro",
     "label": "Preview countdown (s)", "type": "number", "min": 0, "max": 30, "default": 0,
     "store": {"kind": "conf", "file": _SKIP_CONF, "key": "preview_countdown"}},

    # ---- Playback : History ----
    {"id": "hist_exclude", "page": "Playback", "section": "History",
     "label": "Folders excluded from history",
     "help": "Files inside these folders (and subfolders) are never recorded, shown or auto-resumed.",
     "type": "keywords", "fmt": "semicolon", "browse": "folder",
     "store": {"kind": "conf", "file": _HIST_CONF, "key": "exclude"}},
    {"id": "hist_max", "page": "Playback", "section": "History", "label": "Max entries kept",
     "type": "number", "min": 1, "max": 500, "default": 50,
     "store": {"kind": "conf", "file": _HIST_CONF, "key": "max_entries"}},
    {"id": "hist_resume", "page": "Playback", "section": "History",
     "label": "Auto-resume last file on launch", "type": "toggle", "default": True,
     "store": {"kind": "conf", "file": _HIST_CONF, "key": "auto_resume"}},
]

# ---- Video Enhancement page ----
# GLOBAL settings (NOT changed by any preset) come first, ABOVE the preset
# selector. Everything declared AFTER the "presets" entry is preset-controlled.
# (Anime auto-detection + Master shaders are now driven by the per-folder rules.)
SCHEMA += [
    {"id": "sd_mode", "page": "Video Enhancement", "section": "Shaders",
     "label": "SD mode (NNEDI3)", "help": "Clean (denoise) vs Texture (preserve grain) for SD upscaling.",
     "type": "choice", "options": ["clean", "texture"],
     "store": {"kind": "conf", "file": _ANIME_CONF, "key": "sd_mode"}},

    {"id": "hdr_toggle", "page": "Video Enhancement", "section": "HDR",
     "label": "HDR handling", "help": "Passthrough (on) vs tone-map to SDR (off).",
     "type": "choice", "options": ["on", "off"],
     "store": {"kind": "conf", "file": _HDR_CONF, "key": "hdr_toggle"}},
    {"id": "tone_mapping", "page": "Video Enhancement", "section": "HDR",
     "label": "Tone-mapping algorithm", "help": "Curve used to map HDR into the display's range (when tone-mapping).",
     "type": "choice",
     "options": ["st2094-40", "st2094-10", "bt.2390", "reinhard", "mobius", "hable", "gamma", "linear", "clip", "spline"],
     "store": {"kind": "conf", "file": _HDR_CONF, "key": "tone_mapping"}},
    {"id": "target_peak", "page": "Video Enhancement", "section": "HDR",
     "label": "Target peak (nits)", "help": "Assumed display peak brightness used by tone-mapping.",
     "type": "choice",
     "options": ["auto", "100", "200", "300", "400", "600", "1000"],
     "store": {"kind": "conf", "file": _HDR_CONF, "key": "target_peak"}},

    # ---- Preset selector: everything BELOW is what a preset changes ----
    {"id": "presets", "page": "Video Enhancement", "section": "Presets", "type": "presets",
     "label": "Preset",
     "help": "Pick a preset → the settings below change instantly. Edit them, then “Update preset” (save into it) or “Save as new…”. Click Reload to see it in mpv."},

    # PRESET-CONTROLLED settings (shown below the selector).
    {"id": "anime_mode", "page": "Video Enhancement", "section": "Engine",
     "label": "Anime mode", "help": "Auto-detect anime, or force it on / off.",
     "type": "choice", "options": ["auto", "on", "off"],
     "store": {"kind": "conf", "file": _ANIME_CONF, "key": "anime_mode"}},
    {"id": "fidelity", "page": "Video Enhancement", "section": "Engine",
     "label": "Fidelity engine (FSRCNNX) instead of Anime4K",
     "help": "Fidelity preserves the art as drawn; Anime4K reconstructs more aggressively.",
     "type": "toggle", "boolfmt": "truefalse", "default": False,
     "store": {"kind": "conf", "file": _ANIME_CONF, "key": "fidelity"}},
    {"id": "manual_normal_profile", "page": "Video Enhancement", "section": "Engine",
     "label": "Live-action profile",
     "help": "Upscaler profile forced for non-anime content (Auto = let the controller pick).",
     "type": "choice",
     "options": [{"v": "nil", "l": "Auto (none)"}, "4K-Native", "HQ-HD-FSRCNNX", "HQ-HD-NNEDI",
                 "HQ-SD-FSRCNNX", "HQ-SD-Clean", "HQ-SD-Texture", "High-Quality", "Gaming"],
     "store": {"kind": "conf", "file": _ANIME_CONF, "key": "manual_normal_profile"}},
    {"id": "sharpen_enabled", "page": "Video Enhancement", "section": "Engine",
     "label": "Adaptive sharpen", "help": "Content-aware sharpening pass on top of the upscaler.",
     "type": "toggle", "boolfmt": "truefalse", "default": True,
     "store": {"kind": "conf", "file": _ANIME_CONF, "key": "sharpen_enabled"}},
    {"id": "sd_override", "page": "Video Enhancement", "section": "Engine",
     "label": "SD override", "help": "Force the manual SD profile instead of auto-selecting.",
     "type": "toggle", "boolfmt": "truefalse", "default": False,
     "store": {"kind": "conf", "file": _ANIME_CONF, "key": "sd_override"}},
    {"id": "hd_override", "page": "Video Enhancement", "section": "Engine",
     "label": "HD override", "help": "Force the manual HD profile instead of auto-selecting.",
     "type": "toggle", "boolfmt": "truefalse", "default": False,
     "store": {"kind": "conf", "file": _ANIME_CONF, "key": "hd_override"}},
]
for _tier in ("SD", "HD", "FHD", "2K", "4K", "8K"):
    SCHEMA += [
        {"id": "a4k_mode_%s" % _tier, "page": "Video Enhancement", "section": "Anime4K per resolution",
         "label": "%s — mode" % _tier,
         "help": "Anime4K mode (A = de-blur+de-noise, B = de-blur, C = de-noise; doubled = stronger).",
         "type": "choice", "options": ["A", "B", "C", "AA", "BB", "CA"],
         "store": {"kind": "conf", "file": _A4K_CONF, "key": "mode_%s" % _tier}},
        {"id": "a4k_q_%s" % _tier, "page": "Video Enhancement", "section": "Anime4K per resolution",
         "label": "%s — quality" % _tier, "help": "HQ = heavier/better, Fast = lighter.",
         "type": "choice", "options": ["fast", "hq"],
         "store": {"kind": "conf", "file": _A4K_CONF, "key": "quality_%s" % _tier}},
    ]

# ---- Audio page (anime-mode.conf) ----
SCHEMA += [
    {"id": "upmix_active", "page": "Audio", "section": "Processing",
     "label": "7.1 upmix", "help": "Expand stereo to a virtual 7.1 with enhanced bass.",
     "type": "toggle", "boolfmt": "truefalse", "default": False,
     "store": {"kind": "conf", "file": _ANIME_CONF, "key": "upmix_active"}},
    {"id": "night_mode_active", "page": "Audio", "section": "Processing",
     "label": "Night mode (DRC)", "help": "Dynamic range compression — evens out loud/quiet for low-volume listening.",
     "type": "toggle", "boolfmt": "truefalse", "default": False,
     "store": {"kind": "conf", "file": _ANIME_CONF, "key": "night_mode_active"}},
    {"id": "spatial_active", "page": "Audio", "section": "Processing",
     "label": "Spatial audio", "help": "Virtual surround widening.",
     "type": "toggle", "boolfmt": "truefalse", "default": False,
     "store": {"kind": "conf", "file": _ANIME_CONF, "key": "spatial_active"}},
]

# ---- About & Updates page (a single custom panel, rendered specially) ----
SCHEMA += [
    {"id": "about", "page": "About & Updates", "section": "", "type": "about", "label": "About & Updates"},
]


# ---- Presets: named bundles of conf writes --------------------------------
# A preset = a list of [conf_file, key, raw_value] writes. The built-ins below
# mirror the Zego presets in anime_profile_controller.lua EXACTLY, including the
# internal keys (manual_normal_profile / sd_override / hd_override) and the
# Anime4K mode. RTX VSR isn't saved to any file (lost on reload for the Lua
# presets too), so it's out of scope. User presets live in ~~/options_presets.json.
_USER_PRESETS_FILE = "options_presets.json"


def _conf_path(name):
    return os.path.join(SCRIPT_OPTS, name)


# Keys captured when you "Save current as…" a preset.
_PRESET_KEYS = [
    ("anime-mode.conf", "anime_mode"),
    ("anime-mode.conf", "fidelity"),
    ("anime-mode.conf", "manual_normal_profile"),
    ("anime-mode.conf", "sharpen_enabled"),
    ("anime-mode.conf", "sd_override"),
    ("anime-mode.conf", "hd_override"),
]
for _t in ("SD", "HD", "FHD", "2K", "4K", "8K"):
    _PRESET_KEYS.append(("anime4k.conf", "mode_" + _t))
    _PRESET_KEYS.append(("anime4k.conf", "quality_" + _t))


def _anime_writes(mode):
    w = [
        ["anime-mode.conf", "anime_mode", "on"],
        ["anime-mode.conf", "fidelity", "false"],
        ["anime-mode.conf", "manual_normal_profile", "nil"],
        ["anime-mode.conf", "sharpen_enabled", "true"],
        ["anime-mode.conf", "sd_override", "false"],
        ["anime-mode.conf", "hd_override", "false"],
    ]
    for t in ("SD", "HD", "FHD", "2K", "4K", "8K"):
        w.append(["anime4k.conf", "mode_" + t, mode])
        w.append(["anime4k.conf", "quality_" + t, "hq"])
    return w


def _movie_writes(profile, sd_ov, hd_ov):
    return [
        ["anime-mode.conf", "anime_mode", "off"],
        ["anime-mode.conf", "fidelity", "true"],
        ["anime-mode.conf", "manual_normal_profile", profile],
        ["anime-mode.conf", "sharpen_enabled", "true"],
        ["anime-mode.conf", "sd_override", sd_ov],
        ["anime-mode.conf", "hd_override", hd_ov],
    ]


BUILTIN_PRESETS = [
    ("Anime 1440P+", _anime_writes("AA")),
    ("Anime 1080P", _anime_writes("AA")),
    ("Anime 720P", _anime_writes("CA")),
    ("Anime Legacy", _anime_writes("C")),
    ("Movie 1440P+", _movie_writes("4K-Native", "false", "false")),
    ("Movie 1080P", _movie_writes("HQ-HD-FSRCNNX", "false", "true")),
    ("Movie 720P", _movie_writes("HQ-SD-FSRCNNX", "true", "false")),
    ("Gaming", [
        ["anime-mode.conf", "anime_mode", "off"],
        ["anime-mode.conf", "fidelity", "true"],
        ["anime-mode.conf", "manual_normal_profile", "Gaming"],
        ["anime-mode.conf", "sharpen_enabled", "false"],
        ["anime-mode.conf", "sd_override", "false"],
        ["anime-mode.conf", "hd_override", "false"],
    ]),
    ("Off", [
        ["anime-mode.conf", "anime_mode", "off"],
        ["anime-mode.conf", "manual_normal_profile", "nil"],
        ["anime-mode.conf", "sd_override", "false"],
        ["anime-mode.conf", "hd_override", "false"],
    ]),
]


def _write_conf_multi(path, pairs):
    """Set several key=value pairs in one read-modify-write (single backup)."""
    text = _read_text(path)
    newline = "\r\n" if (text and "\r\n" in text) else "\n"
    lines = text.splitlines() if text is not None else []
    remaining = dict(pairs)
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("#") or "=" not in s:
            continue
        k = s.split("=", 1)[0].strip()
        if k in remaining:
            lines[i] = k + "=" + remaining.pop(k)
    for k, v in remaining.items():
        lines.append(k + "=" + v)
    _backup_file(path)
    content = newline.join(lines)
    if not content.endswith(newline):
        content += newline
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(content)


def _load_user_presets():
    text = _read_text(os.path.join(MPV_DIR, _USER_PRESETS_FILE))
    if not text:
        return {}
    try:
        data = json.loads(text)
        return data if isinstance(data, dict) else {}
    except ValueError:
        return {}


def _save_user_presets(data):
    path = os.path.join(MPV_DIR, _USER_PRESETS_FILE)
    _backup_file(path)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _find_preset(name):
    for n, writes in BUILTIN_PRESETS:
        if n == name:
            return writes
    return _load_user_presets().get(name)


# ---- per-folder auto-apply rules: [{folder, preset}, ...] ------------------
_FOLDER_RULES_FILE = "preset_folders.json"


def _load_folder_rules():
    text = _read_text(os.path.join(MPV_DIR, _FOLDER_RULES_FILE))
    if not text:
        return []
    try:
        data = json.loads(text)
        return data if isinstance(data, list) else []
    except ValueError:
        return []


def _save_folder_rules(rules):
    path = os.path.join(MPV_DIR, _FOLDER_RULES_FILE)
    _backup_file(path)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(rules, f, ensure_ascii=False, indent=2)


# ---- About & Updates -------------------------------------------------------
_GITHUB_REPO = "https://github.com/ZegosofT/MPV"
_BASE_REPO   = "https://github.com/Chinna95P/mpv-anime-build"
_VERSION_RAW = "https://raw.githubusercontent.com/ZegosofT/MPV/main/script-opts/zego_version.conf"


def _mpv_exe():
    import winreg
    for root in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
        try:
            with winreg.OpenKey(root, r"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\mpv.exe") as k:
                val, _ = winreg.QueryValueEx(k, None)
                if val and os.path.exists(val):
                    return val
        except OSError:
            pass
    return None


def _mpv_version():
    exe = _mpv_exe()
    if not exe:
        return "unknown"
    try:
        import subprocess
        out = subprocess.run([exe, "--version"], capture_output=True, text=True,
                             timeout=10, creationflags=0x08000000)  # CREATE_NO_WINDOW
        for line in (out.stdout or "").splitlines():
            if line.strip():
                return line.strip()
    except Exception:
        pass
    return "unknown"


def _config_version_from(text):
    if text:
        m = re.search(r"(?m)^\s*version\s*=\s*(.+?)\s*$", text)
        if m:
            return m.group(1).strip()
    return None


def _local_config_version():
    return _config_version_from(_read_text(os.path.join(SCRIPT_OPTS, "zego_version.conf"))) or "unknown"


def _ver_tuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or ""))


def _reload_mpv():
    """One-shot 'reload' to a running mpv via its IPC pipe (\\.\pipe\mpvpipe, set
    by the [SVP-Windows-Patch] profile in mpv.conf for normal video). Returns
    False (no-op) if the pipe isn't open (mpv not running, or 8K / audio-only)."""
    try:
        with open(r"\\.\pipe\mpvpipe", "r+b", buffering=0) as pipe:
            pipe.write(json.dumps({"command": ["script-binding", "reload_mpv/reload"]}).encode("utf-8") + b"\n")
        return True
    except OSError:
        return False


class Api:
    """Exposed to the web UI as window.pywebview.api.*"""

    def get_data(self):
        binds = parse_input_conf()
        kw = load_keywords()
        for b in binds:
            b["keywords"] = kw.get(b["key"], [])
        return {
            "binds": binds,
            "input_conf": INPUT_CONF,
            "keywords_path": KEYWORDS_PATH,
        }

    def set_keywords(self, key, keywords):
        """Set (or clear) the personal keyword list for a bind key."""
        kw = load_keywords()
        cleaned = []
        for item in (keywords or []):
            item = str(item).strip()
            if item and item not in cleaned:
                cleaned.append(item)
        if cleaned:
            kw[key] = cleaned
        else:
            kw.pop(key, None)
        save_keywords(kw)
        return cleaned

    # ---- writing input.conf (each call backs up to input.conf.bak first) ----
    def add_bind(self, key, command):
        key, command = (key or "").strip(), (command or "").strip()
        if not key:
            return {"ok": False, "error": "Key is empty."}
        if not command:
            return {"ok": False, "error": "Command is empty."}
        lines, newline = _load_lines()
        if lines is None:
            return {"ok": False, "error": "Cannot read input.conf."}
        header = "#  Custom  #"
        if header not in lines:                       # create a Custom section once
            while lines and lines[-1].strip() == "":
                lines.pop()
            lines += ["", "#" * len(header), header, "#" * len(header)]
        lines.append(_format_bind(key, command))
        _write_lines(lines, newline)
        return {"ok": True}

    def update_bind(self, line, old_key, new_key, command):
        new_key, command = (new_key or "").strip(), (command or "").strip()
        if not new_key:
            return {"ok": False, "error": "Key is empty."}
        if not command:
            return {"ok": False, "error": "Command is empty."}
        lines, newline = _load_lines()
        if lines is None:
            return {"ok": False, "error": "Cannot read input.conf."}
        if not (0 <= line < len(lines)) or _line_key(lines[line]) != old_key:
            return {"ok": False, "error": "Bind moved (file changed). Reload and retry."}
        note = _extract_note(lines[line])             # keep any inline comment
        lines[line] = _format_bind(new_key, command, note)
        _write_lines(lines, newline)
        if new_key != old_key:                        # migrate personal keywords
            kw = load_keywords()
            if old_key in kw:
                kw[new_key] = kw.pop(old_key)
                save_keywords(kw)
        return {"ok": True}

    def delete_bind(self, line, old_key):
        lines, newline = _load_lines()
        if lines is None:
            return {"ok": False, "error": "Cannot read input.conf."}
        if not (0 <= line < len(lines)) or _line_key(lines[line]) != old_key:
            return {"ok": False, "error": "Bind moved (file changed). Reload and retry."}
        del lines[line]
        _write_lines(lines, newline)
        kw = load_keywords()
        if old_key in kw:
            kw.pop(old_key)
            save_keywords(kw)
        return {"ok": True}

    def open_input_conf(self):
        """Open input.conf in the OS default handler (text editor)."""
        try:
            os.startfile(INPUT_CONF)  # Windows: ShellExecute on the file
            return {"ok": True}
        except OSError as e:
            return {"ok": False, "error": str(e)}

    # ---- settings engine ----
    def get_settings(self):
        out = []
        for e in SCHEMA:
            out.append({
                "id": e["id"], "page": e["page"], "section": e["section"],
                "label": e["label"], "help": e.get("help", ""),
                "type": e["type"], "options": e.get("options"),
                "min": e.get("min"), "max": e.get("max"), "step": e.get("step"),
                "browse": e.get("browse"),
                "value": (_decode(e, _read_store(e["store"])) if "store" in e else None),
            })
        pages = [p for p in PAGE_ORDER
                 if p in _ALWAYS_SHOW_PAGES or any(e["page"] == p for e in SCHEMA)]
        return {"pages": pages, "settings": out}

    def set_setting(self, sid, value):
        entry = next((e for e in SCHEMA if e["id"] == sid), None)
        if not entry:
            return {"ok": False, "error": "unknown setting: " + str(sid)}
        try:
            _write_store(entry["store"], _encode(entry, value))
        except OSError as exc:
            return {"ok": False, "error": str(exc)}
        return {"ok": True}

    def pick_folder(self):
        """Open the native folder picker; return the chosen path (or None)."""
        import webview
        try:
            result = _window.create_file_dialog(webview.FOLDER_DIALOG) if _window else None
        except Exception:
            return None
        return result[0] if result else None

    def reload(self):
        """Reload a running mpv but keep this window open (for testing)."""
        return {"reloaded": _reload_mpv()}

    def reload_and_close(self):
        reloaded = _reload_mpv()
        threading.Timer(0.15, lambda: _window.destroy() if _window else None).start()
        return {"reloaded": reloaded}

    # ---- presets ----
    def get_presets(self):
        users = _load_user_presets()
        presets = [{"name": n, "builtin": True} for n, _ in BUILTIN_PRESETS]
        presets += [{"name": n, "builtin": False} for n in users]
        current = _read_conf_value(_conf_path("anime-mode.conf"), "custom_preset")
        if current in (None, "", "nil"):
            current = "Off"
        return {"presets": presets, "current": current}

    def apply_preset(self, name):
        writes = _find_preset(name)
        if writes is None:
            return {"ok": False, "error": "unknown preset: " + str(name)}
        writes = list(writes) + [["anime-mode.conf", "custom_preset", name]]
        by_file = {}
        for f, k, v in writes:
            by_file.setdefault(f, {})[k] = v
        try:
            for f, pairs in by_file.items():
                _write_conf_multi(_conf_path(f), pairs)
        except OSError as exc:
            return {"ok": False, "error": str(exc)}
        return {"ok": True}

    def save_preset(self, name):
        name = (name or "").strip()
        if not name:
            return {"ok": False, "error": "Name required."}
        if any(n == name for n, _ in BUILTIN_PRESETS):
            return {"ok": False, "error": "That name is a built-in preset."}
        writes = []
        for f, k in _PRESET_KEYS:
            v = _read_conf_value(_conf_path(f), k)
            if v is not None:
                writes.append([f, k, v])
        users = _load_user_presets()
        users[name] = writes
        _save_user_presets(users)
        return {"ok": True}

    def delete_preset(self, name):
        users = _load_user_presets()
        if name not in users:
            return {"ok": False, "error": "Not a user preset."}
        del users[name]
        _save_user_presets(users)
        return {"ok": True}

    # ---- per-folder auto-apply rules ----
    def get_folder_rules(self):
        return {"rules": _load_folder_rules()}

    def save_folder_rules(self, rules):
        cleaned = []
        for r in (rules or []):
            folder = str((r or {}).get("folder", "")).strip()
            preset = str((r or {}).get("preset", "")).strip()
            if folder and preset:
                cleaned.append({"folder": folder, "preset": preset})
        _save_folder_rules(cleaned)
        return {"ok": True}

    # ---- About & Updates ----
    def get_about(self):
        return {
            "mpv_version": _mpv_version(),
            "config_version": _local_config_version(),
            "config_dir": MPV_DIR,
            "base_label": "MPV-Anime-Build — Chinna95P",
            "base_url": _BASE_REPO,
            "author": "ZegosofT",
            "author_url": _GITHUB_REPO,
        }

    def open_url(self, url):
        try:
            os.startfile(url)
            return {"ok": True}
        except OSError as e:
            return {"ok": False, "error": str(e)}

    def check_config_update(self):
        import urllib.request
        local = _local_config_version()
        try:
            with urllib.request.urlopen(_VERSION_RAW, timeout=10) as r:
                remote = _config_version_from(r.read().decode("utf-8", errors="replace")) or "unknown"
        except Exception as exc:
            return {"ok": False, "error": str(exc), "local": local}
        available = remote != "unknown" and _ver_tuple(remote) > _ver_tuple(local)
        return {"ok": True, "local": local, "remote": remote, "update_available": available}

    def update_config(self):
        ps = os.path.join(MPV_DIR, "update-zego-config.ps1")
        if not os.path.exists(ps):
            return {"ok": False, "error": "update-zego-config.ps1 not found."}
        try:
            import subprocess
            subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps])
            return {"ok": True}
        except Exception as exc:
            return {"ok": False, "error": str(exc)}

    def update_mpv(self):
        ps = os.path.join(MPV_DIR, "update-mpv.ps1")
        if not os.path.exists(ps):
            return {"ok": False, "error": "update-mpv.ps1 not found."}
        try:
            import subprocess
            # Elevated (UAC) — same as the uosc "Update MPV" menu item.
            inner = ("Start-Process powershell -Verb RunAs -ArgumentList "
                     "'-NoProfile','-ExecutionPolicy','Bypass','-File','%s'" % ps)
            subprocess.Popen(["powershell", "-NoProfile", "-Command", inner])
            return {"ok": True}
        except Exception as exc:
            return {"ok": False, "error": str(exc)}


WINDOW_TITLE = "mpv — Options"


def _apply_window_icon():
    """Best-effort: swap the default Python window icon for mpv's own icon
    (extracted from mpv.exe). Purely cosmetic — any failure is ignored, so the
    app never breaks just because the icon couldn't be set."""
    try:
        import ctypes
        import time
        import winreg
        from ctypes import wintypes

        # Locate mpv.exe via the App Paths registry key (set by mpv-install.bat).
        mpv = None
        for root in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
            try:
                with winreg.OpenKey(
                    root, r"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\mpv.exe"
                ) as k:
                    val, _ = winreg.QueryValueEx(k, None)  # (default) value
                    if val and os.path.exists(val):
                        mpv = val
                        break
            except OSError:
                pass
        if not mpv:
            return

        user32 = ctypes.WinDLL("user32", use_last_error=True)
        shell32 = ctypes.WinDLL("shell32", use_last_error=True)
        user32.FindWindowW.restype = wintypes.HWND
        user32.FindWindowW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR]
        user32.SendMessageW.restype = ctypes.c_void_p
        user32.SendMessageW.argtypes = [wintypes.HWND, wintypes.UINT, ctypes.c_void_p, ctypes.c_void_p]
        shell32.ExtractIconExW.restype = wintypes.UINT
        shell32.ExtractIconExW.argtypes = [
            wintypes.LPCWSTR, ctypes.c_int,
            ctypes.POINTER(wintypes.HICON), ctypes.POINTER(wintypes.HICON), wintypes.UINT,
        ]

        big, small = wintypes.HICON(), wintypes.HICON()
        if shell32.ExtractIconExW(mpv, 0, ctypes.byref(big), ctypes.byref(small), 1) == 0:
            return

        hwnd = None
        for _ in range(120):  # the window may not exist for a few ms (~6s max)
            hwnd = user32.FindWindowW(None, WINDOW_TITLE)
            if hwnd:
                break
            time.sleep(0.05)
        if not hwnd:
            return

        WM_SETICON = 0x0080
        if small:
            user32.SendMessageW(hwnd, WM_SETICON, ctypes.c_void_p(0), small)  # ICON_SMALL (taskbar/alt-tab)
        if big:
            user32.SendMessageW(hwnd, WM_SETICON, ctypes.c_void_p(1), big)    # ICON_BIG  (taskbar/alt-tab)

        # The title-bar (top-left) icon comes from the window CLASS small icon,
        # which WM_SETICON does NOT change — set it on the class too.
        GCLP_HICON, GCLP_HICONSM = -14, -34
        set_class = getattr(user32, "SetClassLongPtrW", None) or user32.SetClassLongW
        set_class.restype = ctypes.c_void_p
        set_class.argtypes = [wintypes.HWND, ctypes.c_int, ctypes.c_void_p]
        if small:
            set_class(hwnd, GCLP_HICONSM, small)
        if big:
            set_class(hwnd, GCLP_HICON, big)

        # Force the non-client area (title bar) to repaint so the icon refreshes.
        user32.SetWindowPos.argtypes = [
            wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int,
            ctypes.c_int, ctypes.c_int, wintypes.UINT,
        ]
        # SWP_NOSIZE|SWP_NOMOVE|SWP_NOZORDER|SWP_FRAMECHANGED
        user32.SetWindowPos(hwnd, None, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0004 | 0x0020)
    except Exception:
        pass


def main():
    import webview  # deferred: GUI dependency only needed when actually launching
    global _window
    api = Api()
    _window = webview.create_window(
        WINDOW_TITLE,
        os.path.join(UI_DIR, "index.html"),
        js_api=api,
        width=1040,
        height=700,
        min_size=(780, 500),
    )
    webview.start(_apply_window_icon)  # runs after the GUI loop starts


if __name__ == "__main__":
    main()
