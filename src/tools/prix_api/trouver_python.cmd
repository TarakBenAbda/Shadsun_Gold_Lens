@echo off
rem =============================================================================
rem Shadsun Gold Lens - recherche de Python (Anaconda, Miniconda, python.org, py)
rem Auteur : Tarak Ben Abda - novembre 2026
rem Ordre : python_chemin.txt, Anaconda/Miniconda, python.org, lanceur py,
rem         python du PATH (sauf le raccourci du Microsoft Store).
rem Resultat : variable PY (chemin de python.exe), PATH complete pour Anaconda.
rem =============================================================================
set "PY="
if exist "%~dp0python_chemin.txt" set /p PY=<"%~dp0python_chemin.txt"
if defined PY set "PY=%PY:"=%"
if defined PY if exist "%PY%" goto :trouve
set "PY="
call :essai "%USERPROFILE%\anaconda3\python.exe"
call :essai "%USERPROFILE%\Anaconda3\python.exe"
call :essai "%USERPROFILE%\miniconda3\python.exe"
call :essai "%LOCALAPPDATA%\anaconda3\python.exe"
call :essai "%LOCALAPPDATA%\miniconda3\python.exe"
call :essai "%ProgramData%\anaconda3\python.exe"
call :essai "%ProgramData%\Anaconda3\python.exe"
call :essai "%ProgramData%\miniconda3\python.exe"
call :essai "C:\anaconda3\python.exe"
call :essai "C:\Anaconda3\python.exe"
if defined PY goto :trouve
for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do call :essai "%%~D\python.exe"
for /d %%D in ("%ProgramFiles%\Python3*") do call :essai "%%~D\python.exe"
if defined PY goto :trouve
for /f "delims=" %%I in ('where py 2^>nul') do call :essai "%%~I"
if defined PY goto :trouve
for /f "delims=" %%I in ('where python 2^>nul ^| findstr /v /i "WindowsApps"') do call :essai "%%~I"
if defined PY goto :trouve
echo.
echo Python introuvable automatiquement.
echo Solution : ouvrez Spyder, tapez dans la console :
echo     import sys; print(sys.executable)
echo puis copiez le chemin affiche dans un fichier python_chemin.txt
echo place dans ce dossier (une seule ligne, sans guillemets).
exit /b 1
:trouve
for %%F in ("%PY%") do set "PYDIR=%%~dpF"
set "PATH=%PYDIR%;%PYDIR%Library\bin;%PYDIR%Scripts;%PATH%"
echo Python utilise : %PY%
exit /b 0
:essai
if defined PY exit /b 0
if exist "%~1" set "PY=%~1"
exit /b 0
