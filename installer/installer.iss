#ifndef AppVersion
  #define AppVersion "0.3.3"
#endif

#ifndef PublishDir
  #define PublishDir "..\build\publish\win-x64"
#endif

#define AppName "Image Converter"
#define AppPublisher "szmigieldesign"
#define AppPublisherURL "https://github.com/szmigieldesign/windows-png-to-jpg-webp-context-converter"

[Setup]
AppId={{23B20991-7D53-431A-9F94-9D49670E8D16}}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppPublisherURL}
DefaultDirName={localappdata}\Programs\Image Converter
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
UninstallDisplayIcon={app}\ImageConverter.exe
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\VERSION"; DestDir: "{app}"; Flags: ignoreversion

[Run]
Filename: "{app}\ImageConverter.exe"; Parameters: "register-shell --install-dir ""{app}"""; Flags: postinstall runhidden waituntilterminated skipifsilent; StatusMsg: "Registering Explorer context menu entries..."

[UninstallRun]
Filename: "{app}\ImageConverter.exe"; Parameters: "unregister-shell"; Flags: runhidden waituntilterminated; RunOnceId: "RemoveContextMenuEntries"
