# update-zego-config.ps1
# Updates the local mpv config to the latest from GitHub.
#  * If this folder is a git clone (and git is installed): a fast `git fetch`
#    pulls ONLY the changed objects (often a few KB) and resets to them, so it
#    is near-instant. This is the normal case on a machine set up with git.
#  * Otherwise (a plain ZIP install): streams the repo ZIP and overwrites.
# No admin rights needed.
# Launched by the "Update config" button (About & Updates).

$ErrorActionPreference = 'Stop'

# ====== CONFIG (edit if you fork / rename the repo or use another branch) ======
$repoUrl       = 'https://github.com/ZegosofT/MPV.git'
$branch        = 'main'
$zipUrl        = 'https://github.com/ZegosofT/MPV/archive/refs/heads/main.zip'
$extractedName = 'MPV-main'   # GitHub names the folder <repo>-<branch>
# ===============================================================================

$cfg = Join-Path $env:APPDATA 'mpv'

Write-Host "===== Zego Config Updater =====" -ForegroundColor Cyan
Write-Host "Target: $cfg"
Write-Host ""

function Finish($ok) {
    Write-Host ""
    if ($ok) {
        Write-Host "Done! Config updated successfully." -ForegroundColor Green
        Write-Host "Switch back to mpv and press Ctrl+R (or restart) to apply." -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "Press any key to close..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit
}

# ---- FAST PATH: git (downloads only the delta on an existing clone) ----
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $cfg '.git'))) {
    try {
        Write-Host "[git] Fetching latest changes (delta only)..."
        & git -C $cfg fetch $repoUrl $branch
        if ($LASTEXITCODE -ne 0) { throw "git fetch returned $LASTEXITCODE" }
        & git -C $cfg reset --hard FETCH_HEAD
        if ($LASTEXITCODE -ne 0) { throw "git reset returned $LASTEXITCODE" }
        Finish $true
    }
    catch {
        Write-Host "git update failed ($($_.Exception.Message)); falling back to ZIP download..." -ForegroundColor Yellow
    }
}

# ---- FALLBACK: streamed ZIP download (for plain ZIP installs without git) ----
$tmp = Join-Path $env:TEMP ('mpv_cfg_update_' + [guid]::NewGuid().ToString())
$zip = "$tmp.zip"
try {
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    Write-Host "[1/3] Downloading latest config..."
    # PS 5.1: a visible progress bar throttles the download to a crawl, so
    # silence it and stream the bytes ourselves (fast + a simple live counter).
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $req  = [System.Net.HttpWebRequest]::Create($zipUrl)
    $req.UserAgent = 'zego-config-updater'
    $resp = $req.GetResponse()
    $in   = $resp.GetResponseStream()
    $out  = [System.IO.File]::Create($zip)
    $buf  = [byte[]]::new(1MB)
    $sum  = 0; $mark = 0
    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
        $out.Write($buf, 0, $n)
        $sum += $n
        if (($sum - $mark) -ge 4MB) { $mark = $sum; Write-Host ("`r      {0} MB downloaded..." -f [int]($sum / 1MB)) -NoNewline }
    }
    $out.Close(); $in.Close(); $resp.Close()
    Write-Host ("`r      {0} MB downloaded.            " -f [int]($sum / 1MB))

    Write-Host "[2/3] Extracting..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)

    $src = Join-Path $tmp $extractedName
    if (-not (Test-Path $src)) {
        # Fallback: GitHub may name it differently - grab the only subfolder.
        $src = (Get-ChildItem -Path $tmp -Directory | Select-Object -First 1).FullName
    }

    Write-Host "[3/3] Updating config files..."
    Copy-Item -Path (Join-Path $src '*') -Destination $cfg -Recurse -Force

    Finish $true
}
catch {
    Write-Host ""
    Write-Host "Update FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check your internet connection and try again."
    Finish $false
}
finally {
    if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
