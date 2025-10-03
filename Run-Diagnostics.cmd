@echo off
echo PPPoE Diagnostic Toolkit v11
echo =============================
echo.

:: Change to the directory where this script is located
cd /d "%~dp0"
echo Working directory: %CD%
echo.

where pwsh >nul 2>&1
if errorlevel 1 (
  echo ERROR: PowerShell 7 not found
  pause
  exit /b 1
)

echo Running diagnostics...
pwsh -NoProfile -ExecutionPolicy Bypass -File "Invoke-PppoeDiagnostics.ps1"
echo.
echo Press any key to close...
pause >nul