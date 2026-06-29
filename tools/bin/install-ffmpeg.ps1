# install-ffmpeg.ps1
# One-click ffmpeg installer for the mpv clip Slicer, with a download progress bar.
# Lives in tools/bin/ and installs ffmpeg.exe right next to itself.
# No admin rights needed (installs into your own config folder).

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null
$ErrorActionPreference = 'Stop'

$dest = Join-Path $PSScriptRoot 'ffmpeg.exe'
$txt  = Join-Path $PSScriptRoot 'ffmpeg-install.txt'
$url  = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'

# Already installed?
if (Test-Path $dest) {
    [System.Windows.Forms.MessageBox]::Show(
        "ffmpeg is already installed:`n$dest`n`nGo back to mpv and press SAVE clip.",
        'ffmpeg', 'OK', 'Information') | Out-Null
    exit 0
}

$ans = [System.Windows.Forms.MessageBox]::Show(
    "The clip Slicer needs ffmpeg to cut videos losslessly." + [Environment]::NewLine + [Environment]::NewLine +
    "Download and install it automatically now?  (about 160 MB, one-time, fast mirror)" + [Environment]::NewLine + [Environment]::NewLine +
    "Yes = download and install for me" + [Environment]::NewLine +
    "No  = show me the manual steps instead",
    'Install ffmpeg for the Slicer', 'YesNo', 'Question')

if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
    if (Test-Path $txt) { Start-Process notepad.exe $txt }
    exit 0
}

# --- Progress window (normal window: can be minimized; not always-on-top) ---
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Installing ffmpeg'
$form.FormBorderStyle = 'FixedDialog'
$form.MinimizeBox     = $true
$form.MaximizeBox     = $false
$form.StartPosition   = 'CenterScreen'
$form.ClientSize      = New-Object System.Drawing.Size(430, 92)

$label = New-Object System.Windows.Forms.Label
$label.SetBounds(15, 14, 400, 20)
$label.Text = 'Preparing download...'
$form.Controls.Add($label)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.SetBounds(15, 42, 400, 24)
$bar.Minimum = 0; $bar.Maximum = 100; $bar.Value = 0
$form.Controls.Add($bar)

$form.Show()
[System.Windows.Forms.Application]::DoEvents()

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $tmp = Join-Path $env:TEMP ('ffmpeg_dl_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp 'ffmpeg.zip'

    # Manual streamed download so we can drive the progress bar ourselves.
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.UserAgent = 'mpv-config-ffmpeg-installer'
    $resp  = $req.GetResponse()
    $total = $resp.ContentLength
    $in    = $resp.GetResponseStream()
    $out   = [System.IO.File]::Create($zip)
    $buf   = [byte[]]::new(1MB)
    $sum   = 0
    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
        $out.Write($buf, 0, $n)
        $sum += $n
        if ($total -gt 0) {
            $pct = [int](($sum / $total) * 100)
            if ($pct -gt 100) { $pct = 100 }
            $bar.Value  = $pct
            $label.Text = ('Downloading ffmpeg...  {0}%   ({1} / {2} MB)' -f $pct, [int]($sum / 1MB), [int]($total / 1MB))
        } else {
            $label.Text = ('Downloading ffmpeg...  {0} MB' -f [int]($sum / 1MB))
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
    $out.Close(); $in.Close(); $resp.Close()

    $bar.Style  = 'Marquee'
    $label.Text = 'Extracting...'
    [System.Windows.Forms.Application]::DoEvents()

    # Extract ONLY ffmpeg.exe (fast: avoids unzipping ffprobe/ffplay/docs).
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
    $zipObj = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $entry = $zipObj.Entries | Where-Object { $_.Name -eq 'ffmpeg.exe' } | Select-Object -First 1
        if (-not $entry) { throw 'ffmpeg.exe was not found inside the downloaded archive.' }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
    } finally {
        $zipObj.Dispose()
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    $form.Close()
    [System.Windows.Forms.MessageBox]::Show(
        "ffmpeg installed successfully!" + [Environment]::NewLine + [Environment]::NewLine +
        "Go back to mpv and press SAVE clip again.",
        'ffmpeg ready', 'OK', 'Information') | Out-Null
}
catch {
    $form.Close()
    [System.Windows.Forms.MessageBox]::Show(
        "Automatic install failed:" + [Environment]::NewLine + $_.Exception.Message + [Environment]::NewLine + [Environment]::NewLine +
        "Opening the manual steps instead.",
        'ffmpeg install failed', 'OK', 'Warning') | Out-Null
    if (Test-Path $txt) { Start-Process notepad.exe $txt }
    exit 1
}
