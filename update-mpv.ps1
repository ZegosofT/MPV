# update-mpv.ps1
# Launched ELEVATED (UAC) by the uosc "Update MPV" menu item.
# Sequence: close all mpv -> run the updater -> relaunch mpv.
# The relaunched mpv auto-resumes the last file at its saved position
# (handled by history.lua + save-position-on-quit).

$ErrorActionPreference = 'SilentlyContinue'

# ====== EDIT THIS ======
# Full path to YOUR mpv updater script (.bat). This is unique to your install,
# so it must be set by hand. (The MPV-Anime-Build / shinchiro updater.bat.)
$updater = 'C:\Users\TOM-DESKTOP\Documents\Tom\_Software\MPV\updater.bat'
# =======================

# mpv.exe is auto-detected: first via the "App Paths" registry key that
# mpv-install.bat creates (works without PATH), then via PATH as a fallback.
$mpvExe = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\mpv.exe' -ErrorAction SilentlyContinue).'(default)'
if (-not $mpvExe) { $mpvExe = (Get-Command mpv -ErrorAction SilentlyContinue).Source }

# 1. Close every running mpv instance.
Get-Process mpv | Stop-Process -Force

# 2. Wait until they have all fully exited (max ~10s) so the exe is unlocked.
$tries = 0
while ((Get-Process mpv) -and ($tries -lt 40)) {
    Start-Sleep -Milliseconds 250
    $tries++
}

# 3. Run the updater (this script is already elevated, so no nested UAC).
& $updater

# 4. Relaunch mpv WITHOUT admin rights. Launching via explorer.exe drops the
#    elevated token so mpv runs as the normal user (not as admin).
#    history.lua resumes the last file at its saved position.
if ($mpvExe) {
    Start-Process explorer.exe -ArgumentList $mpvExe
} else {
    # Fallback: let the OS resolve "mpv" if it is on PATH but Get-Command missed it.
    Start-Process explorer.exe -ArgumentList 'mpv'
}
