@echo off
rem Shadsun Gold Lens - 7_Etat_de_la_mise_a_jour_horaire (Auteur : Tarak Ben Abda - novembre 2026)
rem Affiche : etat de la tache horaire, derniere execution et son resultat,
rem date du fichier des prix, dernieres lignes du journal (journal_maj.txt).
cd /d "%~dp0"
call "%~dp0trouver_python.cmd" || goto :fin
set PYTHONUTF8=1
"%PY%" sgl_prix_api.py etat
:fin
echo.
pause
