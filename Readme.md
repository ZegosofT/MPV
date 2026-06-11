# 🎬 MPV Anime Build — Custom Edition

A heavily customized [mpv](https://mpv.io/) setup built on top of **MPV-Anime-Build**, tuned for
anime, movies/series, gaming clips and everyday video on a high-refresh OLED display.
It auto-detects what you're watching and applies the right upscaling, color and audio
settings — while still letting you override everything by hand.

> **Platform:** Windows · **Tested on:** 1440p OLED, RTX 4070 Super, i5-14600KF
> **UI:** [uosc](https://github.com/tomasklaen/uosc) · **Player core:** mpv (shinchiro build)

---

## 📑 Table of Contents

1. [How to Install & Customize](#-how-to-install--customize)  ⬅ **read this first**
   - [1. Install mpv + this config](#1-install-mpv--this-config)
   - [2. Install ffmpeg (for the Slicer)](#2-install-ffmpeg-for-the-slicer)
   - [3. Edit the machine-specific paths](#3-edit-the-machine-specific-paths)
   - [4. Keyboard layout (AZERTY)](#4-keyboard-layout-azerty)
2. [Quick Start](#-quick-start)
3. [What This Build Does](#-what-this-build-does-in-plain-english)
4. [The Profile System](#-the-profile-system)
   - [Auto-detection](#auto-detection-how-it-decides)
   - [Resolution tiers](#resolution-tiers)
   - [Custom presets (Zego Presets)](#custom-presets-zego-presets)
   - [Fidelity vs Performance](#fidelity-vs-performance-ctrlb)
5. [Keyboard & Mouse Shortcuts](#-keyboard--mouse-shortcuts)
   - [Mouse](#mouse)
   - [Playback & seeking](#playback--seeking)
   - [Volume & speed](#volume--speed)
   - [Picture & quality](#picture--quality)
   - [Audio](#audio)
   - [Subtitles](#subtitles)
   - [Tools & windows](#tools--windows)
   - [Number row (color & UI)](#number-row-color--ui)
6. [Glossary — What Every Option Means](#-glossary--what-every-option-means)
7. [Custom Scripts](#-custom-scripts)
8. [The Right-Click Menu](#-the-right-click-menu)
9. [Where Settings Are Saved](#-where-settings-are-saved)
10. [Credits](#-credits)

---

## 🛠 How to Install & Customize

> **Read this before using the build.** Most of it works out of the box, but a few things
> point to locations that only exist on the original author's PC. This section lists
> everything you must set up or edit yourself.

### 1. Install mpv + this config

1. Download **mpv for Windows** — a [shinchiro build](https://github.com/shinchiro/mpv-winbuild-cmake/releases)
   is recommended (it bundles `mpv.exe`, `mpv.com`, and usually `ffmpeg.exe`). Extract it anywhere.
2. **Run the installer (required).** Open the `installer` subfolder, then right-click
   **`mpv-install.bat` → Run as administrator**. It registers mpv with Windows (file
   associations, Start Menu, and the lookup this build uses to relaunch mpv). Features like
   reload (`Ctrl+R`), Binds Input Test and the Update MPV relaunch depend on it.
3. Copy this whole config folder into **`%APPDATA%\mpv`**
   (paste `%APPDATA%\mpv` into the File Explorer address bar to open it).

### 2. Install ffmpeg (for the Slicer)

**ffmpeg is the only thing this build needs on your PATH.** The **Slicer** (`Ctrl+Alt+C` —
cut a clip to an `_output/` folder) calls it:

1. Download a build from [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) ("release essentials")
   or [BtbN](https://github.com/BtbN/FFmpeg-Builds/releases).
2. Extract it somewhere permanent, e.g. `C:\ffmpeg`. Inside you'll find `C:\ffmpeg\bin\ffmpeg.exe`.
3. **Add `C:\ffmpeg\bin` to your PATH** (same steps as above).
4. Open a new terminal and run `ffmpeg -version` to confirm.

> Shinchiro mpv builds often already include `ffmpeg.exe` next to `mpv.exe` — if that folder
> is on your PATH, the Slicer works with no extra download.
> If you'd rather not touch PATH, open `scripts/slicer.lua` and set
> `local FFMPEG = "C:/full/path/to/ffmpeg.exe"`.

### 3. Edit the machine-specific paths

These point to locations unique to each user. Open each file and change the marked value:

| File | What to set |
|------|-------------|
| `mpv.conf` — `ytdl_hook-ytdl_path` (near the top) | Path to **your** `yt-dlp.exe`, needed for YouTube / streaming. Set it to your yt-dlp, **or delete that line** if yt-dlp is on your PATH or sits next to `mpv.exe`. Without it, YouTube links won't play. |
| `script-modules/file-browser-addons/favorite-folder.lua` | `FAVORITE` — your "home" folder for the `f` shortcut in the file browser (e.g. your anime/movies drive). |
| `update-mpv.ps1` | `$updater` — full path to **your** mpv updater `.bat`. Only needed for the **Update MPV** button. (mpv.exe is auto-detected via the App Paths registry.) |

Everything else inside the config folder uses portable paths (`%APPDATA%\mpv` and mpv's `~~/`)
and needs no editing.

### 4. Keyboard layout (AZERTY)

The number-row shortcuts (`²`, `&`, `é`, `"`, `'`, `è`, `_`, `à`, `(`…) are mapped for a
**French AZERTY** keyboard. On a **QWERTY** keyboard those physical keys send different
characters, so those specific binds will be wrong for you. Either:

- Edit `input.conf` and remap them to your layout, **or**
- Just use the right-click menu / the documented letter-key shortcuts, which are layout-independent.

To see exactly what any key does on *your* keyboard, use **menu → Binds Input Test**.

---

## 🚀 Quick Start

- **Right-click** anywhere (or press `Tab`) → opens the main menu.
- **Left-click** → play/pause. **Double-click** → fullscreen.
- Just play a file — the build detects anime vs movie vs gaming and configures itself.
- Everything auto-configured can be overridden from the menu or with a keybind.

> ⚠️ **Keyboard layout note:** the number-row shortcuts are mapped for an **AZERTY**
> keyboard (`²`, `&`, `é`, `"`, `'`, `è`, `_`, `à`…). On a QWERTY keyboard those keys
> produce different characters, so the number-row binds will differ — see the
> [number row table](#number-row-color--ui).

---

## 💡 What This Build Does (in plain English)

When you open a video, a controller script (`anime_profile_controller.lua`) looks at the
file — its folder, name, audio language and resolution — and decides:

1. **Is it anime or live-action?** (or audio-only, or 8K)
2. **What resolution tier is it?** (SD / HD / FHD / 2K / 4K / 8K)
3. **Which upscaling engine + shaders** give the best result for that combination.

It then applies a matching mpv **profile** plus a chain of GPU **shaders**. The goal:
upscale lower-resolution content to look good on a 1440p+ screen, clean up compression
artifacts, and keep everything smooth — automatically, but fully overridable.

---

## 🧠 The Profile System

### Auto-detection (how it decides)

**Anime** is detected when any of these are true (in "Auto" mode):
- The path contains a folder like `/anime/`, `donghua`, `cartoon`, `animation`.
- The filename/title contains a **CRC32 hash** in brackets, e.g. `[A1B2C3D4]` (very strong anime signal).
- An audio track is **Japanese** (`jpn`/`ja`).
- The title has `[release group]` brackets.

**Live-action** keywords (`live action`, `drama`, `real person`…) override and force the movie path.
**Audio-only** files (no real video track) get a dedicated lightweight profile.
**8K** files skip heavy shaders entirely to avoid GPU overload.

You can force the decision with **Anime Mode**: `Auto` (default), `Force On`, or `Force Off`.

### Resolution tiers

| Tier | Roughly | Typical source |
|------|---------|----------------|
| SD   | < 576p  | DVD, old web rips |
| HD   | 720p    | TV rips |
| FHD  | 1080p   | Blu-ray |
| 2K   | 1440p   | high-res rips |
| 4K   | 2160p   | UHD Blu-ray |
| 8K   | > 2160p | rare; shaders disabled |

The build remembers your Anime4K preference **independently per tier** — e.g. one mode for
720p, another for 1080p — and swaps automatically.

### Custom presets (Zego Presets)

Open with `<` or via **Quality → Upscaling Presets → Zego Presets**. One click sets the
whole pipeline:

| Preset | Engine | Notes |
|--------|--------|-------|
| **Anime 1440P+** | Anime4K HQ, Mode AA | Heaviest restoration; for big screens with GPU headroom |
| **Anime 1080P**  | Anime4K HQ, Mode AA | Consistent look with 1440P+ |
| **Anime 720P**   | Anime4K HQ, Mode CA | Denoise + restore for soft 720p sources |
| **Anime Legacy** | Anime4K HQ, Mode C  | Denoise-only, for noisy/grainy old shows |
| **Movie 1440P+** | `4K-Native` profile | Sharpen + clean downscale, no AI upscaling |
| **Movie 1080P**  | FSRCNNX (HD)        | AI upscale for live-action |
| **Movie 720P**   | FSRCNNX (SD) + Nvidia VSR | Maximum effort for low-res live-action |
| **Gaming**       | Sharp linear scalers, no shaders | Keeps game pixels/UI crisp; no AI softening |
| **Off**          | Neutral | Disables custom processing |
| **HDR Toggle**   | — | Switch HDR passthrough ↔ tone-mapping |

### Fidelity vs Performance (`Ctrl+B`)

For **anime**, two philosophies:
- **Fidelity (FSRCNNX):** preserves the art exactly as drawn (line art, grain).
- **Performance (Anime4K):** aggressive reconstruction — sharper, "cleaner", more processed.

Neither is "better" — it's taste. Toggle with `Ctrl+B`. The choice is remembered per resolution.

---

## ⌨️ Keyboard & Mouse Shortcuts

### Mouse

| Input | Action |
|-------|--------|
| Left click | Play / Pause |
| Double-click | Toggle fullscreen |
| Right click | Open menu |
| Forward button | Next chapter |
| Back button | Previous chapter |
| `Shift+Alt`+Forward | Next playlist item |
| `Shift+Alt`+Back | Smart previous (restart file, or previous episode if near start) |
| Middle click | Skip by your set amount (see `Shift`+Middle) |
| `Shift`+Middle | Set the skip-step amount (prompt; supports `34`, `-14`, or `=2m02-47`) |
| Wheel up / down | Volume ±2 |

### Playback & seeking

| Key | Action |
|-----|--------|
| `Space` / `Left-click` | Play / Pause |
| `←` / `→` | Seek ∓5 s (snaps to keyframes — fast) |
| `Shift+←` / `Shift+→` | Seek ∓5 s (exact frame) |
| `Ctrl+←` / `Ctrl+→` | Step one frame back / forward |
| `PgUp` / `PgDn` | Next / previous chapter |
| `Shift+PgUp` | Next playlist item |
| `Shift+PgDn` | Smart previous |
| `l` | A-B loop (set point A, point B, then loops) |
| `BS` (Backspace) | Reset speed to 1× |
| `Ctrl+R` | Reload mpv (restarts, resumes at same position) |

### Volume & speed

| Key | Action |
|-----|--------|
| `↑` / `↓` | Volume ±5 |
| Wheel | Volume ±2 |
| `Ctrl+↑` / `Ctrl+↓` | Speed ±0.5× |
| `BS` | Reset speed to 1× |

### Picture & quality

| Key | Action | See glossary |
|-----|--------|--------------|
| `d` | Toggle **deinterlace** | [↗](#deinterlace) |
| `b` | Toggle **deband** | [↗](#deband) |
| `g` | Toggle **interpolation** (motion smoothing) | [↗](#interpolation-motion-smoothing) |
| `G` | Cycle interpolation algorithm (`tscale`) | [↗](#interpolation-motion-smoothing) |
| `u` | Cycle **hardware decoder** (auto / no / auto-copy) | [↗](#hardware-decoding-hwdec) |
| `Ctrl+B` | Toggle Fidelity ↔ Performance (FSRCNNX ↔ Anime4K) | [↗](#fidelity-vs-performance-ctrlb) |
| `Ctrl+G` | Master shaders ON/OFF | [↗](#global-shaders) |
| `Ctrl+K` | Toggle adaptive sharpen | [↗](#adaptive-sharpen) |
| `Ctrl+-` | Clear all GLSL shaders immediately | |
| `Q` | Switch SD/HD logic (FSRCNNX ↔ NNEDI3) | [↗](#nnedi3) |
| `Ctrl+Q` | SD mode: Texture ↔ Clean | |
| `H` | HDR mode toggle (passthrough ↔ tone-map) | [↗](#hdr-passthrough-vs-tone-mapping) |
| `Ctrl+X` | Ambient crop (crop black bars + ambient glow) | [↗](#ambient-crop) |
| `Ctrl+P` | Power-saving / low-end mode | [↗](#power-mode) |
| `p` | Rotate video 90/180/270/0 | |
| `P` | Cycle aspect ratio override | |
| `Alt+E` / `Ctrl+Alt+€` | Pan-scan zoom in / out | [↗](#pan-scan) |
| `D` | Open the Anime Build options menu | |
| `<` | Open the Zego Presets menu | |

### Audio

| Key | Action |
|-----|--------|
| `a` | Open audio-track menu |
| `A` | Cycle audio track |
| `m` | Toggle 7.1 upmix (enhanced bass) |
| `Ctrl+Shift+A` | Toggle bitstream passthrough (AC3/DTS/etc.) ↔ PCM |
| `Ctrl+A` | Toggle automatic audio-device switching |
| `F3` / `F4` | Audio delay ∓0.1 s |

### Subtitles

| Key | Action |
|-----|--------|
| `s` | Open subtitle menu |
| `v` | Toggle subtitle visibility |
| `Alt+S` / `Ctrl+Alt+S` | Subtitle size bigger / smaller |
| `Shift+BS` | Reset subtitle size |
| `Ctrl+Alt+Shift+S` | Cycle secondary subtitle |
| `r` / `R` | Subtitle position down / up |
| `F1` / `F2` | Subtitle delay ∓0.1 s |
| `t` | Toggle sub margins (use black bars) |
| `Ctrl+T` | Cycle blend-subtitles (yes / video / no) |
| `y` | Cycle `sub-ass-use-video-data` |

### Tools & windows

| Key | Action |
|-----|--------|
| `e` | Open the in-player file browser |
| `L` | Show the current file in its folder (Windows Explorer) |
| `w` | Open playlist |
| `c` | Flash the clock for 2 s |
| `Alt+C` | Toggle the clock (stays on) |
| `Ctrl+C` | Chapter editor menu (add/rename/delete chapters) |
| `Ctrl+Alt+C` | Slicer menu (cut a clip with ffmpeg → `_output/`) |
| `Ctrl+H` | Recently-played history menu |
| `h` | Toggle all UI elements always-on |
| `&` | Reset all UI elements to auto-hide |
| `é` / `"` / `'` | Toggle timeline / controls / top-bar always-on |
| `f` | Fullscreen |
| `T` / `!` | Toggle always-on-top |
| `i` / `I` | Stats overlay (toggle / page) |
| `Ctrl+I` | Custom "Neon Glass" stats overlay |
| `k` | Show active audio/video filters + shaders |
| `K` | Show current profile info |
| `o` | Cycle OSD level |
| `²` | Open the console |
| `Shift+F5` | Screenshot of the window |
| `Shift+Alt+B` | Open `input.conf` in your editor |

### Number row (color & UI)

> ⚠️ AZERTY layout. The pairs are "number key = decrease, shifted-number = increase".

| Key | Action |
|-----|--------|
| `5` / `(` | Brightness − / + |
| `6` / `-` | Contrast − / + |
| `7` / `è` | Gamma − / + |
| `8` / `_` | Saturation − / + |
| `0` | Reset brightness/contrast/gamma/saturation |
| `Ctrl+&` / `Ctrl+é` | Anime Mode: Force On / Force Off |

> Anime Mode **"Auto"** has no dedicated key — set it from the menu
> (Quality → Anime Build Options → Anime Mode).

---

## 📖 Glossary — What Every Option Means

#### Deinterlace
Old TV/DVD video is often **interlaced**: each frame is split into two half-images
(odd + even scan lines) shown in alternation. On a modern progressive screen this shows
ugly "comb" lines during motion. **Deinterlacing** rebuilds full frames. The build uses
`deinterlace=auto`, so it only kicks in for genuinely interlaced files — you almost never
need to toggle it manually (`d`). Turning it on for normal progressive video would *hurt*
quality, so leave it on auto.

#### Deband
Smooth gradients (skies, fog, shadows) stored in 8-bit color can show visible **stair-step
banding**. Debanding smooths those steps and adds a tiny bit of grain to hide them. Banding
is **more visible on OLED** (true blacks, no backlight noise), so this build enables it.
Toggle with `b`.

#### Interpolation (motion smoothing)
Converts the source frame rate to your monitor's refresh rate by generating in-between
frames — the "soap opera effect". `g` toggles it; `G` cycles the algorithm (`tscale`).
With G-Sync your monitor already matches the video's frame rate, so interpolation is
**off by default** here (anime/film are meant to be seen at their native cadence).

#### Hardware decoding (hwdec)
Whether the GPU decodes the video (fast, low CPU) or the CPU does (`no`). `auto-copy` decodes
on GPU but copies frames back so CPU filters (denoise, autocrop) still work. `u` cycles it.
Some strict GPU modes (e.g. `vulkan`) can't be combined with CPU filters — the build
auto-switches to `auto-copy` when needed and restores afterward.

#### FSRCNNX
A neural-network upscaler that preserves fine detail and texture. Used for **"Fidelity"**
anime mode and for live-action upscaling. Heavier than Anime4K but more faithful to the
source art.

#### Anime4K
A family of shaders designed specifically to make anime look like higher-resolution,
restoring lines and removing artifacts. Used for **"Performance"** anime mode. Modes:
- **A** = de-blur + de-noise · **B** = de-blur only · **C** = de-noise only
- **AA / BB / CA** = double-pass / stronger variants.

#### NNEDI3
A neural edge-directed upscaler, very good for clean line-art and live-action edges.
`Q` switches the SD/HD pipeline between NNEDI3 and FSRCNNX.

#### Adaptive Sharpen
A content-aware sharpening pass added on top of the upscalers. `Ctrl+K` toggles it. Games
don't need it (already sharp); the Gaming preset disables it.

#### Global shaders
The master ON/OFF for the entire shader chain (`Ctrl+G`). When off, mpv uses plain built-in
scaling (Lanczos/Spline) — useful to compare "with vs without" or to troubleshoot.

#### Nvidia VSR
**Video Super Resolution** — Nvidia's RTX-accelerated upscaler (driver-level, Windows/D3D11
only). Used by the "Movie 720P" preset and toggleable. Great for compressed low-res video.

#### HDR: passthrough vs tone-mapping
- **Passthrough** sends the HDR signal straight to the display (best when Windows HDR is ON).
- **Tone-mapping** compresses HDR into SDR range for normal display (when Windows HDR is OFF).

`hdr_detect.lua` picks automatically; `H` forces a manual toggle. On this build the workflow
is: HDR content → enable Windows HDR + mpv passthrough; otherwise leave both off.

#### Ambient Crop
Two actions in one (`Ctrl+X`): **autocrop** removes baked-in black bars, then **ambient mode**
fills any remaining border with a blurred, dimmed glow of the on-screen colors — a
bias-lighting / Ambilight effect. Nice on OLED.

#### Power mode
`Ctrl+P` forces a low-end profile (disables heavy shaders). On laptops it also engages
automatically on battery (`power_manager.lua`). On a desktop it's a manual toggle.

#### Pan-scan
Zooms the picture to fill the screen, cropping the edges (vs letterboxing). `Alt+E` zooms in,
`Ctrl+Alt+€` zooms out.

#### Upmix / Passthrough (audio)
- **7.1 upmix** (`m`) expands stereo to a virtual 7.1 with enhanced bass.
- **Bitstream passthrough** (`Ctrl+Shift+A`) sends raw AC3/DTS/TrueHD to an AV receiver
  instead of decoding to PCM.

#### Sub-scale / smart-prev / skip-step
- **Sub-scale** (`Alt+S` / `Ctrl+Alt+S`) resizes ASS subtitles while keeping your font.
- **Smart previous** restarts the current file if you're past ~5 s in, otherwise jumps to the
  previous episode.
- **Skip-step** lets you define a custom seek amount (e.g. 34 s) and jump by it with a click —
  the prompt even accepts time math like `=1h07m02-1h06m02`.

---

## 🔧 Custom Scripts

| Script | Purpose |
|--------|---------|
| `anime_profile_controller.lua` | The brain — detects content, applies profiles & shaders, builds menus |
| `skip_intro.lua` | OP/ED/Intro/Preview skip with countdown; driven by `skip_intro.conf` (exact chapter-title match) |
| `history.lua` | Recently-played menu + auto-resume last file on launch |
| `chapter_editor.lua` | Add / rename / delete chapters; saved to a `.chapters` sidecar |
| `slicer.lua` | Cut a clip (begin/end) with ffmpeg into an `_output/` folder |
| `clock.lua` | On-screen clock (flash or toggle) |
| `hud_toggle.lua` | Force individual UI elements always-on |
| `sub_scale.lua` | Resize ASS subs without losing your custom font |
| `smart_prev.lua` | Restart-or-previous-episode logic |
| `reload_mpv.lua` | Restart mpv and resume position (also launches Binds Input Test) |
| `zego_update.lua` | Checks your GitHub for a newer config version; one-click update (downloads latest, no git) |
| `auto_anime_preset.lua` | Auto-apply a preset when a file is inside an `/anime/` folder |
| `hdr_detect.lua` | Detect Windows HDR state, auto switch passthrough/tone-map |
| `power_manager.lua` | Battery detection → low-power profile |
| `vsr_auto.lua` | Nvidia RTX VSR control |
| `ambient-manager.lua` | Ambient-glow shader generator |
| `track-selector.lua` | Smart audio/subtitle auto-selection (Japanese-aware) |
| `audio-visualizer.lua` | Visualizers for audio-only files |
| `firequalizer15.lua` | 15-band audio equalizer |
| `Up_Next.lua` | "Up Next" episode card near end of file |
| `file-browser/` | In-player file browser (+ fuzzy-open & favorite-folder addons) |

---

## 🗂 The Right-Click Menu

```
▶ Now Playing        ▸  Show in directory, Subtitles, Audio, Chapters,
                        Stream quality, Synchronization, Skip Options
🎨 Quality           ▸  Upscaling Presets (Zego), Controls, Anime Build Options,
                        Ambient Crop
──────────────
🕘 History
📂 Playlist
🧭 Navigation        ▸
──────────────
⌨ Binds                 (opens input.conf)
🔧 Utils             ▸
⌨ Binds Input Test      (shows what each key is bound to)
⬇ Update            ▸   Update MPV (player) · Update Zego Config (this config from GitHub) · Check now
❓ Help / Shortcuts      (opens this Readme)
──────────────
✕ Quit
```

> The **Update** menu shows a "config update available" hint when your GitHub repo has a newer
> version than what's installed. **Update Zego Config** downloads the latest config from GitHub
> and applies it in one click (no git needed) — then reload with `Ctrl+R`.

---

## 💾 Where Settings Are Saved

| File | What it remembers |
|------|-------------------|
| `script-opts/anime-mode.conf` | Anime mode, fidelity, sharpen, custom preset, audio states |
| `script-opts/anime4k.conf` | Anime4K quality + mode, per resolution tier |
| `script-opts/hdr-mode.conf` | Tone-mapping algorithm, target peak |
| `script-opts/skip_intro.conf` | Which chapter titles to skip + per-type countdowns |
| `skip_intro_state.json` | Skip toggles (Intro/Opening/Ending on/off) |
| `script-opts/firequalizer15.conf` | Equalizer band values |
| `script-opts/zego_version.conf` | Config version — bump before pushing so other installs detect updates |
| `history.json` | Recently-played list |
| `watch_later/` | Resume positions per file |

---

## 🙏 Credits

- Base build: **MPV-Anime-Build** by [Chinna95P](https://github.com/Chinna95P/mpv-anime-build)
- UI: **uosc** by [tomasklaen](https://github.com/tomasklaen/uosc)
- Thumbnails: **thumbfast** · File browser: **CogentRedTester/mpv-file-browser**
- Upscalers: Anime4K, FSRCNNX, NNEDI3, RAVU, FSRCNN, ArtCNN, SSimSuperRes/Downscaler, KrigBilateral
- Player: [mpv](https://mpv.io/)

This is a personal, customized fork — keybindings and paths are tailored to the author's
system and may need editing for your own setup.
