#ifndef AppVersion
  #define AppVersion "0.3.3"
#endif

#define AppName "PNG/JPEG/WEBP/AVIF Converter Context Menu Tool"
#define AppPublisher "szmigieldesign"
#define AppPublisherURL "https://github.com/szmigieldesign/windows-png-to-jpg-webp-context-converter"

[Setup]
AppId={{A4D5A1B7-38A5-4E6B-9B0B-42C1D4A8A1F0}}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppPublisherURL}
DefaultDirName={localappdata}\Programs\PNG-JPG-WebP-AVIF-Converter
DefaultGroupName={#AppName}
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputDir=..\release
OutputBaseFilename=Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\ConvertPngToJpg.ps1
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\src\ConvertPngToJpg.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\Install-ImageConverter.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\install-context-menu.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\uninstall-context-menu.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\Uninstall-ImageConverter.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\Run-Converter.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\Run-Converter.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\VERSION"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\Setup.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\Uninstall.cmd"; DestDir: "{app}"; Flags: ignoreversion

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Install-ImageConverter.ps1"" -NoCopy"; Flags: postinstall runhidden waituntilterminated; StatusMsg: "Configuring ImageMagick and the context menu..."

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall-context-menu.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "RemoveContextMenuEntries"
