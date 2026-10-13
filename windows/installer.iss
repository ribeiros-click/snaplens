; Instalador do SnapLens para Windows (Inno Setup 6). Gerado por build.ps1.
; Instala por usuário (sem pedir administrador), cria atalho no Menu Iniciar e opção de iniciar com o Windows.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6F1C2B9E-5D3A-4E8F-9B21-5A7C3E0D4F11}
AppName=SnapLens
AppVersion={#AppVersion}
AppPublisher=ribeiros.click
AppPublisherURL=https://lens.ribeiros.click/
AppSupportURL=https://github.com/ribeiros-click/snaplens
DefaultDirName={localappdata}\Programs\SnapLens
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=dist
OutputBaseFilename=SnapLens-Setup
SetupIconFile=SnapLens\Assets\SnapLens.ico
UninstallDisplayIcon={app}\SnapLens.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
CloseApplications=yes

[Languages]
Name: "pt_BR"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "it"; MessagesFile: "compiler:Languages\Italian.isl"

[Tasks]
Name: "startup"; Description: "{cm:AutoStartProgram,SnapLens}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "dist\SnapLens\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{userprograms}\SnapLens"; Filename: "{app}\SnapLens.exe"
Name: "{userdesktop}\SnapLens"; Filename: "{app}\SnapLens.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "SnapLens"; ValueData: """{app}\SnapLens.exe"" --background"; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\SnapLens.exe"; Description: "{cm:LaunchProgram,SnapLens}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "taskkill.exe"; Parameters: "/F /IM SnapLens.exe"; Flags: runhidden; RunOnceId: "KillSnapLens"
