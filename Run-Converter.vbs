Option Explicit

Dim shell, fso, scriptDir, converterPath, args, i, hostCmd, cmd

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
converterPath = scriptDir & "\ConvertPngToJpg.ps1"

If Not fso.FileExists(converterPath) Then
    WScript.Quit 1
End If

args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " " & QuoteArg(WScript.Arguments.Item(i))
Next

hostCmd = "where pwsh.exe >nul 2>nul && pwsh.exe -NoProfile -STA -ExecutionPolicy Bypass -File " & _
    QuoteArg(converterPath) & args & _
    " || powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File " & QuoteArg(converterPath) & args

cmd = "cmd.exe /c " & hostCmd

' Run hidden and do not wait, so no console windows flash.
shell.Run cmd, 0, False

Function QuoteArg(ByVal s)
    QuoteArg = """" & Replace(s, """", """""") & """"
End Function
