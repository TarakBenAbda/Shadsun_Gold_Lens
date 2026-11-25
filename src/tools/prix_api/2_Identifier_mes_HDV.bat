@echo off
rem Shadsun Gold Lens - 2_Identifier_mes_HDV (Auteur : Tarak Ben Abda - novembre 2026)
cd /d "%~dp0"
call "%~dp0trouver_python.cmd" || goto :fin
set PYTHONUTF8=1
"%PY%" sgl_prix_api.py identifier
:fin
echo.
pause
