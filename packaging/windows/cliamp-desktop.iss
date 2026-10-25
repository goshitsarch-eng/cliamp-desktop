; Inno Setup script for the unofficial Cliamp Desktop build. Build it with
; packaging/windows/build.py, which stages the engine DLLs first.
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#define BundleDir "..\..\godot\build\windows"

[Setup]
AppId={{6B0F4F4E-7C2D-4B8A-9A61-3D5C1E0B7A21}
AppName=Cliamp Desktop
AppVersion={#AppVersion}
AppVerName=Cliamp Desktop {#AppVersion}
AppPublisher=goshitsarch-eng (unofficial fork of cliamp)
AppPublisherURL=https://github.com/goshitsarch-eng/cliamp-desktop
AppSupportURL=https://github.com/goshitsarch-eng/cliamp-desktop/issues
DefaultDirName={autopf}\Cliamp Desktop
DefaultGroupName=Cliamp Desktop
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\godot\build\installer
OutputBaseFilename=Cliamp-Desktop-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\godot\icon\icon.ico
UninstallDisplayIcon={app}\Cliamp-Desktop.exe
LicenseFile=..\..\LICENSE
Compression=lzma2/ultra
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\Cliamp-Desktop.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BundleDir}\cliamp.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BundleDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BundleDir}\CLIAMP-LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Cliamp Desktop"; Filename: "{app}\Cliamp-Desktop.exe"
Name: "{autodesktop}\Cliamp Desktop"; Filename: "{app}\Cliamp-Desktop.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Cliamp-Desktop.exe"; Description: "{cm:LaunchProgram,Cliamp Desktop}"; Flags: nowait postinstall skipifsilent
