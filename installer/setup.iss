; FRAMPP 安装器（Inno Setup 6/7）
; 构建：installer/scripts/build-installer.ps1（会自动准备 dist/staging 并调用 ISCC）

#define MyAppName "FRAMPP"
#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif
#ifndef Channel
  #define Channel "8.5"
#endif
#ifndef Env
  #define Env "windows-x64"
#endif
#define MyAppPublisher "FRAMPP contributors"
#define MyAppURL "https://github.com/wangbo5825/frampp"

[Setup]
AppId={{9E1F4A6C-3B2D-4C5E-8F7A-1D2E3F4A5B6C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\FRAMPP
DefaultGroupName=FRAMPP
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist\installer
OutputBaseFilename=frampp-setup-{#Channel}-{#MyAppVersion}-{#Env}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\frankenphp\frankenphp.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
Source: "..\dist\staging\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs; Excludes: "data\*|logs\*|*.pid"
Source: "..\agent\*"; DestDir: "{app}\agent"; Flags: recursesubdirs
Source: "..\installer\scripts\*"; DestDir: "{app}\installer\scripts"; Flags: recursesubdirs
Source: "..\installer\config\*"; DestDir: "{app}\installer\config"; Flags: recursesubdirs
Source: "..\installer\templates\*"; DestDir: "{app}\installer\templates"; Flags: recursesubdirs
Source: "..\docs\*"; DestDir: "{app}\docs"; Flags: recursesubdirs
Source: "..\README.md"; DestDir: "{app}\docs"; Flags: isreadme
Source: "..\LICENSE"; DestDir: "{app}"

[Icons]
Name: "{group}\FRAMPP 控制面板"; Filename: "http://127.0.0.1:8081/"
Name: "{group}\默认站点"; Filename: "http://127.0.0.1:8080/"
Name: "{group}\卸载 FRAMPP"; Filename: "{uninstallexe}"

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\scripts\init.ps1"" -RuntimeDir ""{app}"""; Flags: runhidden; StatusMsg: "正在初始化 FRAMPP 运行时..."
Filename: "{app}\frankenphp\frankenphp.exe"; Parameters: "php-cli ""{app}\control-panel\bin\frampp"" start all --home ""{app}"""; Flags: runhidden nowait; StatusMsg: "正在启动服务..."
Filename: "http://127.0.0.1:8081/"; Description: "打开控制面板"; Flags: postinstall nowait shellexec skipifsilent

[UninstallRun]
Filename: "{app}\frankenphp\frankenphp.exe"; Parameters: "php-cli ""{app}\control-panel\bin\frampp"" stop all --home ""{app}"""; Flags: runhidden
Filename: "taskkill.exe"; Parameters: "/IM frankenphp.exe /F"; Flags: runhidden
Filename: "taskkill.exe"; Parameters: "/IM mariadbd.exe /F"; Flags: runhidden
Filename: "taskkill.exe"; Parameters: "/IM redis-server.exe /F"; Flags: runhidden

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\logs"
Type: files; Name: "{app}\Caddyfile"
Type: files; Name: "{app}\frankenphp\php.ini"
Type: files; Name: "{app}\redis\redis.conf"
