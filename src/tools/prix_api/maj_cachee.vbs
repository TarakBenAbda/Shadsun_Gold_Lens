'=============================================================================
' Shadsun Gold Lens - lance la mise a jour des prix sans fenetre visible
' (utilise par la tache horaire creee par 5_Activer_la_mise_a_jour_horaire)
' Auteur : Tarak Ben Abda - novembre 2026
'=============================================================================
Option Explicit
Dim sh, fso, dossier
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dossier = fso.GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = dossier
sh.Run """" & dossier & "\4_Mise_a_jour_automatique.bat""", 0, True
