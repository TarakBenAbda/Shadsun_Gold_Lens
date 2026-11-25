@echo off
rem Shadsun Gold Lens - mise a jour sans fenetre, pour le Planificateur de taches
rem Auteur : Tarak Ben Abda - novembre 2026
cd /d "%~dp0"
call "%~dp0trouver_python.cmd" > derniere_maj.log 2>&1 || exit /b 1
set PYTHONUTF8=1
"%PY%" sgl_prix_api.py maj --journal >> derniere_maj.log 2>&1
