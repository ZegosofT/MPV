# update-mpv.ps1
# Launched ELEVATED (UAC) by the uosc "Update MPV" menu item.
# Sequence: close all mpv -> run the updater -> relaunch mpv.
# The relaunched mpv auto-resumes the last file at its saved position
# (handled by history.lua + save-position-on-quit).

$ErrorActionPreference = 'SilentlyContinue'

$updater = 'C:\Users\TOM-DESKTOP\Documents\Tom\_Software\MPV\updater.bat'
$mpvExe  = 'C:\Users\TOM-DESKTOP\Documents\Tom\_Software\MPV\mpv.exe'

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
Start-Process explorer.exe -ArgumentList $mpvExe
