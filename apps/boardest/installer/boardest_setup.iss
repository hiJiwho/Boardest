; Boardest Inno Setup Script
; 빌드: iscc installer\boardest_setup.iss

#define MyAppName "Boardest"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Boardest Dev"
#define MyAppExeName "boardest.exe"
#define SourceDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
; 출력 경로
OutputDir=..\dist
OutputBaseFilename=Boardest-Setup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
; 아이콘
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardStyle=modern
WizardSmallImageFile=
; 64비트 앱
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
; 최소 윈도우 버전 (Win10)
MinVersion=10.0
; 설치 후 실행 옵션
DisableProgramGroupPage=no
; 언인스톨러 아이콘
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; 메인 실행파일
Source: "{#SourceDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; PPT COM 제어 헬퍼 (Windows PPT 판서 기능용)
Source: "{#SourceDir}\boardest_ppt_helper.exe"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
; Flutter DLL
Source: "{#SourceDir}\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
; 플러그인 DLL
Source: "{#SourceDir}\pdfium.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\pdfrx.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\printing_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\screen_brightness_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\url_launcher_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\video_player_win_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\WebView2Loader.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\webview_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
; data 폴더 전체 (Flutter 에셋)
Source: "{#SourceDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; 시작 메뉴
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
; 바탕화면 (선택)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
