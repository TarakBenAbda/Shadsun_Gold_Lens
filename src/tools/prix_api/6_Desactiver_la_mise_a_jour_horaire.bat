@echo off
rem Shadsun Gold Lens - 6_Desactiver_la_mise_a_jour_horaire (Auteur : Tarak Ben Abda - novembre 2026)
cd /d "%~dp0"
call "%~dp0trouver_python.cmd" || goto :fin
set PYTHONUTF8=1
"%PY%" sgl_prix_api.py deplanifier
:fin
echo.
pause
