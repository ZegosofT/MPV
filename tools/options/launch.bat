@echo off
REM ============================================================
REM  mpv Options GUI launcher
REM  Double-click to open. Installs pywebview on first run.
REM ============================================================
setlocal
cd /d "%~dp0"

py -c "import webview" 1>nul 2>nul
if errorlevel 1 (
    echo Installing pywebview ^(first run only^)...
    py -m pip install --user pywebview
    if errorlevel 1 (
        echo.
        echo Failed to install pywebview. Make sure Python is installed ^(py --version^).
        pause
        exit /b 1
    )
)

py app.py
if errorlevel 1 pause
