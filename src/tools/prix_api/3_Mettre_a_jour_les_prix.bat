@echo off
rem Shadsun Gold Lens - 3_Mettre_a_jour_les_prix (Auteur : Tarak Ben Abda - novembre 2026)
cd /d "%~dp0"
call "%~dp0trouver_python.cmd" || goto :fin
set PYTHONUTF8=1
"%PY%" sgl_prix_api.py maj
:fin
echo.
pause
