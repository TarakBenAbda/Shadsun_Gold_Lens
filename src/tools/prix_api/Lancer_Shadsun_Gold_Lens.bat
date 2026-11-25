@echo off
rem =============================================================================
rem Shadsun Gold Lens - lance l'application avec le Python de ce PC (sans exe)
rem Auteur : Tarak Ben Abda - novembre 2026
rem Pour partager avec un ami sans Python : utilisez plutot ShadsunGoldLens.exe
rem (fabrique une fois avec construire_exe.bat).
rem =============================================================================
cd /d "%~dp0"
call "%~dp0trouver_python.cmd" >nul
if errorlevel 1 (
  call "%~dp0trouver_python.cmd"
  pause
  exit /b 1
)
rem Icone pres de l'horloge (facultative) : pystray, installe une seule fois.
"%PY%" -c "import pystray" 2>nul || "%PY%" -m pip install --quiet pystray pillow
set "PYW=%PYDIR%pythonw.exe"
if not exist "%PYW%" set "PYW=%PY%"
start "" "%PYW%" "%~dp0sgl_app.py"
