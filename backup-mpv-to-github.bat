@echo off
cd /d "%APPDATA%\mpv"

echo Checking mpv Git status...
git status

echo.
echo Adding changes...
git add .

echo.
echo Committing changes...
git commit -m "Update mpv config"

echo.
echo Uploading to GitHub...
git push

echo.
echo Done.
pause