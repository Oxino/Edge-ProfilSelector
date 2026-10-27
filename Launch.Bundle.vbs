' Lanceur silencieux d'Edge Profil Selector (version BUNDLE optimisée).
' Démarre le bundle mono-fichier SANS fenêtre console noire et sans profil,
' pour le lancement le plus rapide.
'
' Prérequis : avoir généré EdgeSelector.Bundle.ps1 via build.ps1.
Dim shell, scriptDir
Set shell = CreateObject("WScript.Shell")

' Répertoire de ce lanceur (= racine du projet)
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

' 0 = fenêtre cachée, False = ne pas attendre la fin
shell.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptDir & "EdgeSelector.Bundle.ps1""", 0, False

Set shell = Nothing
