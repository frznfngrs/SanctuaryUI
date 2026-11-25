' Runs outlook_sync.ps1 (next to this file) with no window, so a scheduled sync never flashes a
' console over the game. Task Scheduler starts this through wscript.exe (install.ps1).
Dim here
here = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & here & "\outlook_sync.ps1""", 0, False
