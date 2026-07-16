@echo off
setlocal EnableExtensions

set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

set "GODOT="
if exist "%PROJECT_DIR%\tools\godot_console.exe" set "GODOT=%PROJECT_DIR%\tools\godot_console.exe"
if not defined GODOT if exist "C:\Projekte\InfiniWorld\tools\godot\Godot_v4.6-stable_win64_console.exe" set "GODOT=C:\Projekte\InfiniWorld\tools\godot\Godot_v4.6-stable_win64_console.exe"
if not defined GODOT if exist "%PROJECT_DIR%\tools\Godot_v4.6-stable_win64_console.exe" set "GODOT=%PROJECT_DIR%\tools\Godot_v4.6-stable_win64_console.exe"
if not defined GODOT if exist "%PROJECT_DIR%\tools\godot.exe" set "GODOT=%PROJECT_DIR%\tools\godot.exe"

if not defined GODOT (
    echo Could not find Godot.
    exit /b 1
)

rem Forward extra args after -- to the script, e.g.:
rem   simulate_dungeon_gen.bat --trials=64 --presets=all
rem   simulate_dungeon_gen.bat --grid --fixed-poc
"%GODOT%" --headless --path "%PROJECT_DIR%" -s res://scripts/dev/simulate_dungeon_gen.gd -- %*
exit /b %ERRORLEVEL%
