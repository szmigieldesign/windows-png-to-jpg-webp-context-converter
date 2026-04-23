Option Explicit

Dim shell, fso, scriptDir, converterPath, args, i, cmd, probeExit

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

probeExit = shell.Run("cmd.exe /c where pwsh.exe >nul 2>nul", 0, True)

If probeExit = 0 Then
    cmd = "pwsh.exe -NoProfile -STA -ExecutionPolicy Bypass -File " & QuoteArg(converterPath) & args
Else
    cmd = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File " & QuoteArg(converterPath) & args
End If

' Run hidden and do not wait, so no console windows flash.
shell.Run cmd, 0, False

Function QuoteArg(ByVal s)
    QuoteArg = """" & Replace(s, """", """""") & """"
End Function
