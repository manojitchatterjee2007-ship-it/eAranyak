; Script generated for এখন আরণ্যক (Ekhon Aranyak)

#define MyAppName "এখন আরণ্যক"
#define MyAppEnglishName "Ekhon Aranyak"
#define MyAppVersion "1.0"
#define MyAppPublisher "Manojit Chatterjee"
#define MyAppExeName "earanyak.exe"
#define SourceDir "build\windows\x64\runner\Release"

[Setup]
AppId={{D3F79C81-7A3D-4A2D-A904-4F8A38BE4F22}
AppName={#MyAppEnglishName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppEnglishName}
DefaultGroupName={#MyAppEnglishName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=Ekhon_Aranyak_Setup
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Main executable
Source: "{#SourceDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; All dependent DLLs, plugins, and data assets
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppEnglishName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppEnglishName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; IconFilename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppEnglishName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent