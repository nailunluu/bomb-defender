@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build Windows.ps1"
if errorlevel 1 (
 echo Build failed. Check the message above.
 pause
 exit /b 1
)
echo EXE package is ready in dist\Bomb Defender.zip
pause
