@echo off
cd /d "%APPDATA%\mpv"

echo Checking mpv Git status...
git status

echo.
echo Adding changes...
git add .

echo.
set /p msg="Commit message (Enter for default): "
if "%msg%"=="" set msg=Update mpv config

echo.
echo Committing changes...
git commit -m "%msg%"

echo.
echo Uploading to GitHub...
git push

echo.
echo Done.
pause