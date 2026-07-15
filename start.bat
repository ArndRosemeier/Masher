@echo off
setlocal EnableExtensions

set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

rem Prefer the *console* build so SCRIPT ERROR / push_error are visible.
set "GODOT="
if exist "%PROJECT_DIR%\tools\godot_console.exe" set "GODOT=%PROJECT_DIR%\tools\godot_console.exe"
if not defined GODOT if exist "C:\Projekte\InfiniWorld\tools\godot\Godot_v4.6-stable_win64_console.exe" set "GODOT=C:\Projekte\InfiniWorld\tools\godot\Godot_v4.6-stable_win64_console.exe"
if not defined GODOT if exist "%PROJECT_DIR%\tools\godot.exe" set "GODOT=%PROJECT_DIR%\tools\godot.exe"
if not defined GODOT if exist "C:\Projekte\InfiniWorld\tools\godot\Godot_v4.6-stable_win64.exe" set "GODOT=C:\Projekte\InfiniWorld\tools\godot\Godot_v4.6-stable_win64.exe"

if not defined GODOT (
    echo Could not find Godot. Place godot.exe / godot_console.exe in tools\ or update start.bat.
    pause
    exit /b 1
)

echo Starting Masher...
echo   Godot: %GODOT%
echo   Path:  %PROJECT_DIR%
echo   Errors print in this console — do not close it.
echo.

rem Run the game (not the editor). Keep this console attached so crashes are visible.
"%GODOT%" --path "%PROJECT_DIR%" --maximized
set "ERR=%ERRORLEVEL%"

if not "%ERR%"=="0" (
    echo.
    echo Godot exited with code %ERR%.
    pause
    exit /b %ERR%
)

endlocal
