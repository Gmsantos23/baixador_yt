' Abre o Baixador sem mostrar nenhuma janela preta.
Option Explicit

Dim fso, sh, pasta, comando
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

pasta = fso.GetParentFolderName(WScript.ScriptFullName)

comando = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ _
        & pasta & "\servidor.ps1"""

sh.Run comando, 0, False
