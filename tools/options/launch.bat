@echo off
REM ============================================================
REM  mpv Options GUI launcher
REM  Double-click to open. Uses the self-contained Python runtime
REM  bundled in tools\options\runtime -> no install required.
REM ============================================================
setlocal
cd /d "%~dp0"

if exist "runtime\python.exe" (
    REM Self-contained bundle: just run it (console stays for error visibility).
    "runtime\python.exe" app.py
    if errorlevel 1 pause
    exit /b 0
)

REM --- Source-only fallback: no bundled runtime, use the system Python ---
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
