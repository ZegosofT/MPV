# update-zego-config.ps1
# Downloads the latest config from GitHub as a ZIP and overwrites the local
# mpv config folder. Works WITHOUT git — for users who downloaded the ZIP and
# dropped it in %APPDATA%\mpv. No admin rights needed.
# Launched by the "Update Zego Config MPV" menu item.

$ErrorActionPreference = 'Stop'

# ====== CONFIG (edit if you fork / rename the repo or use another branch) ======
$zipUrl        = 'https://github.com/ZegosofT/MPV/archive/refs/heads/main.zip'
$extractedName = 'MPV-main'   # GitHub names the folder <repo>-<branch>
# ===============================================================================

$cfg = Join-Path $env:APPDATA 'mpv'
$tmp = Join-Path $env:TEMP ('mpv_cfg_update_' + [guid]::NewGuid().ToString())
$zip = "$tmp.zip"

Write-Host "===== Zego Config Updater =====" -ForegroundColor Cyan
Write-Host "Target: $cfg"
Write-Host ""

try {
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    Write-Host "[1/3] Downloading latest config..."
    Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing

    Write-Host "[2/3] Extracting..."
    Expand-Archive -Path $zip -DestinationPath $tmp -Force

    $src = Join-Path $tmp $extractedName
    if (-not (Test-Path $src)) {
        # Fallback: GitHub may name it differently — grab the only subfolder.
        $src = (Get-ChildItem -Path $tmp -Directory | Select-Object -First 1).FullName
    }

    Write-Host "[3/3] Updating config files..."
    Copy-Item -Path (Join-Path $src '*') -Destination $cfg -Recurse -Force

    Write-Host ""
    Write-Host "Done! Config updated successfully." -ForegroundColor Green
    Write-Host "Switch back to mpv and press Ctrl+R (or restart) to apply." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "Update FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check your internet connection and try again."
}
finally {
    if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "Press any key to close..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
