' Lanceur silencieux d'Edge Profil Selector.
' Démarre le script PowerShell SANS fenêtre console noire et sans profil,
' pour un lancement plus rapide et visuellement propre.
Dim shell, scriptDir
Set shell = CreateObject("WScript.Shell")

' Répertoire de ce lanceur (= racine du projet)
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

' 0 = fenêtre cachée, False = ne pas attendre la fin
shell.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptDir & "EdgeSelector.ps1""", 0, False

Set shell = Nothing
