@echo off
setlocal
title FlyMe2TheMoon - Game Data Setup
echo ================================================================
echo           FlyMe2TheMoon - Asset Setup and Converter
echo ================================================================
echo.
echo Checking Python installation...
where python >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo.
    echo [!] ERROR: Python is not found in your system PATH.
    echo Please install Python 3 (with 'Add Python to PATH' enabled) from:
    echo   https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)

python "%~dp0tools\setup_game_data.py"
if %ERRORLEVEL% neq 0 (
    echo.
    echo [!] Setup encountered an error. Please see the messages above.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo Setup finished successfully! You can now launch Godot and play!
pause
