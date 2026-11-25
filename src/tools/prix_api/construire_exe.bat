@echo off
rem =============================================================================
rem Shadsun Gold Lens - fabrication de ShadsunGoldLens.exe
rem Auteur : Tarak Ben Abda - novembre 2026
rem Produit : dist\ShadsunGoldLens.exe, a partager tel quel (Python integre).
rem Necessite Internet la premiere fois (installation de PyInstaller, pystray, Pillow).
rem Ferme d'abord tout ce qui peut bloquer l'ancien exe (application, mise a jour en cours).
rem =============================================================================
setlocal
cd /d "%~dp0"
call "%~dp0trouver_python.cmd"
if errorlevel 1 goto :fin

echo.
echo [1/4] Fermeture de ce qui pourrait bloquer l'ancien exe...
rem /T : ferme aussi les processus enfants (mise a jour lancee par l'application).
taskkill /F /T /IM ShadsunGoldLens.exe >nul 2>&1
rem Version lancee sans exe (Lancer_Shadsun_Gold_Lens.bat) : pythonw avec sgl_app.py.
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like ('*sgl_' + 'app.py*') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
timeout /t 2 /nobreak >nul
rem Anciennes copies mises de cote lors d'une fabrication precedente.
del /f /q "dist\ShadsunGoldLens_ancien_*.exe" >nul 2>&1
if not exist "dist\ShadsunGoldLens.exe" goto :libre
del /f /q "dist\ShadsunGoldLens.exe" >nul 2>&1
if not exist "dist\ShadsunGoldLens.exe" goto :libre
rem Encore bloque (antivirus, Explorateur...) : Windows permet de renommer un exe
rem utilise. On le met de cote ; il sera supprime a la prochaine fabrication.
ren "dist\ShadsunGoldLens.exe" "ShadsunGoldLens_ancien_%RANDOM%.exe" >nul 2>&1
if not exist "dist\ShadsunGoldLens.exe" goto :libre
echo.
echo ERREUR : dist\ShadsunGoldLens.exe ne peut etre ni supprime ni renomme.
echo Processus portant ce nom :
tasklist /FI "IMAGENAME eq ShadsunGoldLens.exe"
echo Redemarrez le PC puis relancez ce fichier.
goto :fin
:libre
echo OK.

echo.
echo [2/4] Installation des outils de fabrication...
"%PY%" -m pip install --upgrade pyinstaller pystray pillow
if errorlevel 1 goto :erreur

echo.
echo [3/4] Icone...
"%PY%" sgl_icon.py ShadsunGoldLens.ico
if errorlevel 1 goto :erreur

echo.
echo [4/4] Fabrication de l'exe (1 a 3 minutes)...
"%PY%" -m PyInstaller --noconfirm --clean --onefile --windowed --name ShadsunGoldLens ^
  --icon ShadsunGoldLens.ico --add-data "addon;addon" --add-data "assets;assets" ^
  --hidden-import pystray._win32 --hidden-import PIL.ImageTk ^
  sgl_app.py
if errorlevel 1 goto :erreur
if not exist "dist\ShadsunGoldLens.exe" goto :erreur

echo.
echo ===========================================================================
echo  Termine : dist\ShadsunGoldLens.exe
echo  Double-cliquez dessus pour l'essayer, puis partagez ce seul fichier.
echo ===========================================================================
explorer "%~dp0dist"
goto :fin

:erreur
echo.
echo ERREUR pendant la fabrication : faites une capture de cette fenetre.

:fin
echo.
pause
endlocal
