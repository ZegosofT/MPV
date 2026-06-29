# update-mpv.ps1
# Launched ELEVATED (UAC) by the uosc "Update MPV" menu item.
# Sequence: close all mpv -> run the mpv build's own updater -> relaunch mpv.
# The relaunched mpv auto-resumes the last file at its saved position
# (handled by history.lua + save-position-on-quit).
#
# No manual editing required: the updater that ships with the mpv build
# (shinchiro `installer\updater.ps1`, or `updater.bat`) is auto-located
# next to mpv.exe.

$ErrorActionPreference = 'SilentlyContinue'

# mpv.exe is auto-detected: first via the "App Paths" registry key that
# mpv-install.bat creates (works without PATH), then via PATH as a fallback.
$mpvExe = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\mpv.exe' -ErrorAction SilentlyContinue).'(default)'
if (-not $mpvExe) { $mpvExe = (Get-Command mpv -ErrorAction SilentlyContinue).Source }

# Locate the updater shipped with the mpv build, next to mpv.exe.
$updater = $null
if ($mpvExe) {
    $mpvDir = Split-Path $mpvExe
    foreach ($c in @(
        (Join-Path $mpvDir 'updater.bat'),
        (Join-Path $mpvDir 'updater.ps1'),
        (Join-Path $mpvDir 'installer\updater.ps1'),
        (Join-Path $mpvDir 'installer\updater.bat'))) {
        if (Test-Path $c) { $updater = $c; break }
    }
}
if (-not $updater) { exit 1 }   # nothing to run; bail quietly

# 1. Close every running mpv instance.
Get-Process mpv -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. Wait until they have all fully exited (max ~10s) so the exe is unlocked.
$tries = 0
while ((Get-Process mpv -ErrorAction SilentlyContinue) -and ($tries -lt 40)) {
    Start-Sleep -Milliseconds 250
    $tries++
}

# 3. Run the updater (this script is already elevated, so no nested UAC),
#    from its own folder so its relative paths resolve.
Push-Location (Split-Path $updater)
if ($updater -match '\.ps1$') {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $updater
} else {
    & $updater
}
Pop-Location

# 4. Relaunch mpv WITHOUT admin rights. Launching via explorer.exe drops the
#    elevated token so mpv runs as the normal user (not as admin).
#    history.lua resumes the last file at its saved position.
if ($mpvExe) {
    Start-Process explorer.exe -ArgumentList $mpvExe
} else {
    Start-Process explorer.exe -ArgumentList 'mpv'
}
