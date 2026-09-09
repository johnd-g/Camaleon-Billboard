; =========================
; Camaleon Billboard - installer.iss
; =========================

[Setup]
AppId={{a8c3e1f2-7b94-4d6e-9c21-5f0e8a4b2d71}
AppName=Camaleon Billboard
AppVersion=1.0.2
AppPublisher=Camaleon Systems Inc
DefaultDirName={commonpf}\CamaleonBillboard
DefaultGroupName=Camaleon Billboard
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=dist
OutputBaseFilename=CamaleonBillboard_Setup
Compression=lzma2/ultra64
SolidCompression=yes
CloseApplications=force
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no
RestartIfNeededByRun=no
DisableProgramGroupPage=yes
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\camaleon_billboard.exe
ShowLanguageDialog=auto
LanguageDetectionMethod=uilanguage

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[CustomMessages]
english.TaskVerbose=Show detailed installation (verbose)
spanish.TaskVerbose=Ver instalación en modo detallado (verbose)
english.TaskStartMenuIcon=Create a Start Menu shortcut
spanish.TaskStartMenuIcon=Crear acceso en el Menú Inicio
english.StatusGrantingPermissions=Granting write permissions...
spanish.StatusGrantingPermissions=Otorgando permisos de escritura...
english.StatusInstallVCRedistX64=Installing Visual C++ Redistributable (x64)...
spanish.StatusInstallVCRedistX64=Instalando Visual C++ Redistributable (x64)...
english.StatusInstallVCRedistX86=Installing Visual C++ Redistributable (x86)...
spanish.StatusInstallVCRedistX86=Instalando Visual C++ Redistributable (x86)...
english.StatusCopyVCRuntimeInstalled=Updating Visual C++ runtime files...
spanish.StatusCopyVCRuntimeInstalled=Actualizando archivos del runtime de Visual C++...
english.StatusCopyVCRuntimeFallback=Updating Visual C++ runtime files...
spanish.StatusCopyVCRuntimeFallback=Actualizando archivos del runtime de Visual C++...
english.StatusCopyVCRuntimeLastResort=Updating Visual C++ runtime files...
spanish.StatusCopyVCRuntimeLastResort=Actualizando archivos del runtime de Visual C++...
english.LogVCWarn=A required system component could not be verified. Setup may still work.
spanish.LogVCWarn=No se pudo verificar un componente del sistema. La instalación puede funcionar igual.
english.LogDone=Installation completed successfully.
spanish.LogDone=Instalación completada correctamente.
english.StatusStopCamaleon=Closing Camaleon Billboard...
spanish.StatusStopCamaleon=Cerrando Camaleon Billboard...
english.RepairPageCaption=Camaleon Billboard is already installed
spanish.RepairPageCaption=Camaleon Billboard ya está instalado
english.RepairPageDescription=Recommended: update and keep your data
spanish.RepairPageDescription=Recomendado: actualizar y conservar tus datos
english.RepairPageSubCaption=An existing installation was found. Setup will refresh program files and dependencies. Choose full reinstall only if you want to wipe app data.
spanish.RepairPageSubCaption=Se encontró una instalación existente. Se actualizarán archivos y dependencias. Elige reinstalación completa solo si quieres borrar los datos de la app.
english.RepairOptionUpdate=Update (recommended — keep app data)
spanish.RepairOptionUpdate=Actualizar (recomendado — conservar datos)
english.RepairOptionReinstall=Full reinstall (wipe program folder and app data)
spanish.RepairOptionReinstall=Reinstalación completa (borra carpeta del programa y datos de la app)
english.LogUpdateMode=Update mode: installing this version over the existing one; app data will be kept.
spanish.LogUpdateMode=Modo actualización: se instala esta versión sobre la existente; se conservarán los datos.
english.LogReinstallMode=Full reinstall mode: previous program files and app data will be removed.
spanish.LogReinstallMode=Modo reinstalación completa: se eliminarán archivos y datos previos.
english.LogMariaDBFound=MariaDB/MySQL was found on this computer (optional — Billboard can also use a remote database).
spanish.LogMariaDBFound=Se encontró MariaDB/MySQL en este equipo (opcional — Billboard también puede usar una BD remota).
english.LogMariaDBRemote=No local MariaDB/MySQL detected. Connect Billboard to the database via QR or manual settings after install.
spanish.LogMariaDBRemote=No se detectó MariaDB/MySQL local. Conecta Billboard a la BD con QR o ajustes manuales tras instalar.
english.MariaDBHint=Billboard needs a MySQL/MariaDB database. No local database will be installed. After setup, scan the QR code or enter host/user/password manually.
spanish.MariaDBHint=Billboard necesita una base MySQL/MariaDB. No se instalará una base local. Tras el setup, escanea el código QR o ingresa host/usuario/contraseña manualmente.

[Tasks]
Name: "verbose";        Description: "{cm:TaskVerbose}"
Name: "desktopicon";    Description: "{cm:CreateDesktopIcon}"
Name: "startmenuicon";  Description: "{cm:TaskStartMenuIcon}"

[Dirs]
Name: "{app}"; Permissions: users-modify
Name: "{app}\data"; Permissions: users-modify
Name: "{app}\data\flutter_assets"; Permissions: users-modify
Name: "{commonappdata}\CamaleonBillboard"; Permissions: users-modify

[InstallDelete]
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}"
Type: filesandordirs; Name: "{commonappdata}\CamaleonBillboard"; Check: ShouldWipeAppData

[Files]
; Binario principal (Flutter Release)
Source: "build\windows\x64\runner\Release\camaleon_billboard.exe"; DestDir: "{app}"; Flags: ignoreversion

; DLLs y otros (mismo nivel que el EXE)
Source: "build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion

; Estructura crítica 'data' (app.so, icudtl.dat, flutter_assets\...)
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

; Dependencia: VC++ Redistributable
Source: "thirdparty\VC_redist.x64.exe";  DestDir: "{tmp}"; Flags: deleteafterinstall; Check: IsWin64
Source: "thirdparty\VC_redist.x86.exe";  DestDir: "{tmp}"; Flags: deleteafterinstall; Check: not IsWin64
Source: "thirdparty\vcruntime140_1.dll"; DestDir: "{tmp}"; Flags: deleteafterinstall skipifsourcedoesntexist

[Icons]
Name: "{group}\Camaleon Billboard"; Filename: "{app}\camaleon_billboard.exe"; WorkingDir: "{app}"; \
  Tasks: startmenuicon; Check: ShouldCreateStartMenuIcon
Name: "{autodesktop}\Camaleon Billboard"; Filename: "{app}\camaleon_billboard.exe"; WorkingDir: "{app}"; \
  Tasks: desktopicon; Check: ShouldCreateDesktopIcon
Name: "{group}\{cm:UninstallProgram,Camaleon Billboard}"; Filename: "{uninstallexe}"; Tasks: startmenuicon; Check: ShouldCreateStartMenuIcon

[Run]
; 0) Permisos recursivos en {app}
Filename: "{sys}\icacls.exe"; \
  Parameters: """{app}"" /grant *S-1-5-32-545:(OI)(CI)M /T /C"; \
  Flags: runhidden waituntilterminated; StatusMsg: "{cm:StatusGrantingPermissions}"

; 0.5a) Visual C++ Redistributable x64 — siempre (idempotente si ya está instalado)
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; \
  StatusMsg: "{cm:StatusInstallVCRedistX64}"; \
  Flags: waituntilterminated; Check: IsWin64

; 0.5b) Visual C++ Redistributable x86 — siempre (idempotente si ya está instalado)
Filename: "{tmp}\VC_redist.x86.exe"; Parameters: "/install /quiet /norestart"; \
  StatusMsg: "{cm:StatusInstallVCRedistX86}"; \
  Flags: waituntilterminated; Check: not IsWin64

; 0.6a) Copiar vcruntime140_1.dll si VC++ ya está instalado pero falta la DLL
Filename: "{sys}\cmd.exe"; \
  Parameters: "/c copy /Y ""{tmp}\vcruntime140_1.dll"" ""{sys}\vcruntime140_1.dll"""; \
  Flags: runhidden waituntilterminated; \
  StatusMsg: "{cm:StatusCopyVCRuntimeInstalled}"; \
  Check: VCRedistInstalledButDllMissing

; 0.6b) Copiar vcruntime140_1.dll a System32 si aún falta después de instalar (fallback)
Filename: "{sys}\cmd.exe"; \
  Parameters: "/c copy /Y ""{tmp}\vcruntime140_1.dll"" ""{sys}\vcruntime140_1.dll"""; \
  Flags: runhidden waituntilterminated; \
  StatusMsg: "{cm:StatusCopyVCRuntimeFallback}"; \
  Check: StillNeedsVCRuntimeDll

; 0.6c) Copiar vcruntime140_1.dll como último recurso
Filename: "{sys}\cmd.exe"; \
  Parameters: "/c copy /Y ""{tmp}\vcruntime140_1.dll"" ""{sys}\vcruntime140_1.dll"""; \
  Flags: runhidden waituntilterminated; \
  StatusMsg: "{cm:StatusCopyVCRuntimeLastResort}"; \
  Check: FinalDllCopyNeeded

; 7) Lanzar app
Filename: "{app}\camaleon_billboard.exe"; Description: "{cm:LaunchProgram,Camaleon Billboard}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: filesandordirs; Name: "{commonappdata}\CamaleonBillboard"

[Code]
var
  PageRepair: TInputOptionWizardPage;
  LogMemo: TMemo;
  G_LastStatus: string;
  G_AlreadyInstalled: Boolean;
  G_StatusTimerId: LongWord;
  G_WizardHwnd: LongWord;
  G_MariaDBWasInstalled: Boolean;

const
  MYSQL_EXE = '\bin\mysql.exe';
  INSTALLER_LOG_NAME = 'camaleon_billboard_installer.log';
  STATUS_TIMER_ID = 1;
  CAMALEON_UNINSTALL_KEY = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{a8c3e1f2-7b94-4d6e-9c21-5f0e8a4b2d71}_is1';

var
  G_LogTempPath: string;
  G_LogFinalPath: string;
  G_LogMirrorToApp: Boolean;
  G_Verbose: Boolean;

function SetTimer(hWnd, nIDEvent, uElapse, lpTimerFunc: LongWord): LongWord;
  external 'SetTimer@user32.dll stdcall';
function KillTimer(hWnd, nIDEvent: LongWord): LongWord;
  external 'KillTimer@user32.dll stdcall';

procedure StopCamaleonProcesses; forward;

procedure AppendToMemo(const Line: string);
begin
  if Assigned(LogMemo) then
  begin
    LogMemo.Lines.Add(Line);
    LogMemo.SelStart := Length(LogMemo.Text);
    LogMemo.SelLength := 0;
  end;
end;

procedure WriteLogLine(const Msg: string; const ToMemo: Boolean);
var
  line: string;
begin
  line := GetDateTimeString('yyyy-mm-dd hh:nn:ss', '-', ':') + ' - ' + Msg;
  if G_LogTempPath <> '' then
    SaveStringToFile(G_LogTempPath, line + #13#10, True);

  if G_LogMirrorToApp and (G_LogFinalPath <> '') then
    SaveStringToFile(G_LogFinalPath, line + #13#10, True);

  if ToMemo then
    AppendToMemo(Msg);
end;

procedure LogDebug(const Msg: string);
begin
  WriteLogLine(Msg, G_Verbose);
end;

procedure LogUser(const Msg: string);
begin
  WriteLogLine(Msg, True);
end;

procedure SyncStatusToMemo;
var
  s: string;
begin
  if WizardForm = nil then Exit;
  s := Trim(WizardForm.StatusLabel.Caption);
  if (s <> '') and (s <> G_LastStatus) then
  begin
    G_LastStatus := s;
    LogUser(s);
  end;
end;

procedure StatusTimerProc(Wnd, Msg, TimerID, Time: LongWord);
begin
  SyncStatusToMemo;
end;

function RegHiveName(hive: Integer): string;
begin
  if hive = HKCU then Result := 'HKCU' else Result := 'HKLM';
end;

function BoolToStr(B: Boolean): string;
begin
  if B then Result := 'True' else Result := 'False';
end;

function ServiceExists(ServiceName: string): Boolean;
var
  tmp: string;
begin
  Result := RegQueryStringValue(HKLM, 'SYSTEM\CurrentControlSet\Services\' + ServiceName, 'ImagePath', tmp);
  LogDebug('ServiceExists(' + ServiceName + ') -> ' + BoolToStr(Result));
end;

function FirstExistingPath(var OutPath: string; Paths: TArrayOfString): Boolean;
var
  i: Integer;
begin
  for i := 0 to GetArrayLength(Paths)-1 do
    if FileExists(Paths[i]) then
    begin
      OutPath := Paths[i];
      Result := True; Exit;
    end;
  Result := False;
end;

function LastPosStr(const SubStr, S: string): Integer;
var
  i, n: Integer;
begin
  Result := 0; n := Length(SubStr);
  if n = 0 then Exit;
  for i := Length(S) - n + 1 downto 1 do
    if Copy(S, i, n) = SubStr then begin Result := i; Exit; end;
end;

function SearchUninstallRegistryFor(productKeywords: TArrayOfString): string;
var
  baseHK: array[0..2] of Integer;
  baseKeys: array[0..2] of string;
  hive, i, j: Integer;
  subKeys: TArrayOfString;
  subKeyName, displayName, installLocation, uninstallString, subKeyFull: string;
  pExe, exeStart: Integer;
begin
  Result := '';
  baseHK[0] := HKLM; baseKeys[0] := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';
  baseHK[1] := HKLM; baseKeys[1] := 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall';
  baseHK[2] := HKCU; baseKeys[2] := 'Software\Microsoft\Windows\CurrentVersion\Uninstall';

  for hive := 0 to 2 do
    if RegGetSubkeyNames(baseHK[hive], baseKeys[hive], subKeys) then
      for i := 0 to GetArrayLength(subKeys) - 1 do
      begin
        subKeyName := subKeys[i]; subKeyFull := baseKeys[hive] + '\' + subKeyName;
        if RegQueryStringValue(baseHK[hive], subKeyFull, 'DisplayName', displayName) then
          for j := 0 to GetArrayLength(productKeywords) - 1 do
            if (displayName <> '') and (Pos(LowerCase(productKeywords[j]), LowerCase(displayName)) > 0) then
            begin
              if RegQueryStringValue(baseHK[hive], subKeyFull, 'InstallLocation', installLocation) and (installLocation <> '') then
              begin
                Result := installLocation;
                LogDebug('Found InstallLocation in ' + RegHiveName(baseHK[hive]) + ': ' + Result + ' for ' + displayName); Exit;
              end;
              if RegQueryStringValue(baseHK[hive], subKeyFull, 'UninstallString', uninstallString) and (uninstallString <> '') then
              begin
                if (Length(uninstallString) > 0) and (uninstallString[1] = '"') then
                  uninstallString := Copy(uninstallString, 2, Length(uninstallString) - 1);
                pExe := LastPosStr('.exe', LowerCase(uninstallString));
                if pExe > 0 then
                begin
                  exeStart := pExe;
                  while (exeStart > 1) and (uninstallString[exeStart] <> '\') do Dec(exeStart);
                  if exeStart > 1 then Result := Copy(uninstallString, 1, exeStart - 1)
                  else Result := ExtractFilePath(uninstallString);
                  LogDebug('Extracted path from UninstallString ' + RegHiveName(baseHK[hive]) + ': ' + Result + ' for ' + displayName); Exit;
                end
                else
                begin
                  Result := ExtractFilePath(uninstallString);
                  if Result <> '' then begin
                    LogDebug('Fallback path from UninstallString ' + RegHiveName(baseHK[hive]) + ': ' + Result + ' for ' + displayName); Exit;
                  end;
                end;
              end;
            end;
      end;
end;

function GetInstallLocationFromUninstall(): string;
var res: string; keywords: TArrayOfString;
begin
  SetArrayLength(keywords, 1); keywords[0] := 'mariadb';
  res := SearchUninstallRegistryFor(keywords);
  if res <> '' then LogDebug('GetInstallLocationFromUninstall -> ' + res)
               else LogDebug('GetInstallLocationFromUninstall -> not found');
  Result := res;
end;

function GetServiceImageDir(const ServiceName: string): string;
var img: string;
begin
  Result := '';
  if RegQueryStringValue(HKLM, 'SYSTEM\CurrentControlSet\Services\' + ServiceName, 'ImagePath', img) then
  begin
    if (Length(img) > 0) and (img[1] = '"') then img := Copy(img, 2, Length(img) - 1);
    Result := ExtractFilePath(img);
    LogDebug('Service ' + ServiceName + ' ImagePath dir: ' + Result);
  end;
end;

function GetMysqlPath(Param: string): string;
var p, registryPath, svcBin: string; candidatePaths: TArrayOfString;
begin
  svcBin := GetServiceImageDir('MySQLMaria');
  if (svcBin <> '') and FileExists(svcBin + 'mysql.exe') then
  begin Result := svcBin + 'mysql.exe'; LogDebug('GetMysqlPath: found via MySQLMaria service ' + Result); Exit; end;

  svcBin := GetServiceImageDir('MariaDB');
  if (svcBin <> '') and FileExists(svcBin + 'mysql.exe') then
  begin Result := svcBin + 'mysql.exe'; LogDebug('GetMysqlPath: found via MariaDB service ' + Result); Exit; end;

  SetArrayLength(candidatePaths, 6);
  candidatePaths[0] := ExpandConstant('{commonpf}')   + '\MariaDB 10.3' + MYSQL_EXE;
  candidatePaths[1] := ExpandConstant('{commonpf}')   + '\MariaDB' + MYSQL_EXE;
  candidatePaths[2] := ExpandConstant('{commonpf64}') + '\MariaDB' + MYSQL_EXE;
  candidatePaths[3] := ExpandConstant('{commonpf}')   + '\MariaDB Server' + MYSQL_EXE;
  candidatePaths[4] := ExpandConstant('{commonpf64}') + '\MariaDB Server' + MYSQL_EXE;
  candidatePaths[5] := ExpandConstant('{commonpf}')   + '\Camaleon Systems\bin' + MYSQL_EXE;

  if FirstExistingPath(p, candidatePaths) then begin LogDebug('GetMysqlPath: found candidate ' + p); Result := p; Exit; end;

  registryPath := GetInstallLocationFromUninstall();
  if registryPath <> '' then
  begin
    p := registryPath; if (p[Length(p)] <> '\') then p := p + '\';
    if FileExists(p + 'bin\mysql.exe') then begin Result := p + 'bin\mysql.exe'; LogDebug('GetMysqlPath: found via registry ' + Result); end
    else if FileExists(p + 'mysql.exe') then begin Result := p + 'mysql.exe'; LogDebug('GetMysqlPath: found via registry ' + Result); end
    else begin Result := ''; LogDebug('GetMysqlPath: registry path found but mysql.exe not present in ' + p); end;
    Exit;
  end;

  LogDebug('GetMysqlPath: no mysql found');
  Result := '';
end;

{ Solo detección informativa: Billboard NO instala MariaDB (usa BD remota). }
function IsMariaDBInstalled(): Boolean;
begin
  Result := (GetMysqlPath('') <> '') or ServiceExists('MySQLMaria') or ServiceExists('MariaDB');
  LogDebug('IsMariaDBInstalled -> ' + BoolToStr(Result));
end;

{ MySQL ODBC 3.51 (solo verificación; Billboard usa mysql1). }
function IsMySqlOdbcInstalled(): Boolean;
begin
  Result := RegValueExists(HKLM, 'SOFTWARE\WOW6432Node\ODBC\ODBCINST.INI\ODBC Drivers', 'MySQL ODBC 3.51 Driver');
  if not Result then
    Result := RegValueExists(HKLM, 'SOFTWARE\ODBC\ODBCINST.INI\ODBC Drivers', 'MySQL ODBC 3.51 Driver');
  LogDebug('IsMySqlOdbcInstalled -> ' + BoolToStr(Result));
end;

function NeedsVB6(): Boolean;
begin
  if IsWin64 then Result := not FileExists(ExpandConstant('{syswow64}\msvbvm60.dll'))
             else Result := not FileExists(ExpandConstant('{sys}\msvbvm60.dll'));
  LogDebug('NeedsVB6 (info only, not installed by Billboard) -> ' + BoolToStr(Result));
end;

function JavaHomeHasBin(const JavaHome: string): Boolean;
begin
  Result := (JavaHome <> '') and FileExists(AddBackslash(JavaHome) + 'bin\java.exe');
end;

function ReadJavaHomeFromKey(const RootKey: Integer; const SubKey: string; var OutHome: string): Boolean;
begin
  Result := RegQueryStringValue(RootKey, SubKey, 'JavaHome', OutHome) and JavaHomeHasBin(OutHome);
end;

function IsJre8Installed(): Boolean;
var
  ver, home: string;
begin
  Result := False;

  if RegQueryStringValue(HKLM, 'SOFTWARE\JavaSoft\Java Runtime Environment', 'CurrentVersion', ver) then
    if (Copy(ver, 1, 3) = '1.8') and ReadJavaHomeFromKey(HKLM, 'SOFTWARE\JavaSoft\Java Runtime Environment\' + ver, home) then
    begin Result := True; LogDebug('IsJre8Installed -> True (JRE ' + ver + ' @ ' + home + ')'); Exit; end;

  if RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\JavaSoft\Java Runtime Environment', 'CurrentVersion', ver) then
    if (Copy(ver, 1, 3) = '1.8') and ReadJavaHomeFromKey(HKLM, 'SOFTWARE\WOW6432Node\JavaSoft\Java Runtime Environment\' + ver, home) then
    begin Result := True; LogDebug('IsJre8Installed -> True (WOW JRE ' + ver + ' @ ' + home + ')'); Exit; end;

  if RegQueryStringValue(HKLM, 'SOFTWARE\JavaSoft\JRE', 'CurrentVersion', ver) then
    if (Copy(ver, 1, 3) = '1.8') and ReadJavaHomeFromKey(HKLM, 'SOFTWARE\JavaSoft\JRE\' + ver, home) then
    begin Result := True; LogDebug('IsJre8Installed -> True (JRE key ' + ver + ' @ ' + home + ')'); Exit; end;

  if DirExists(ExpandConstant('{commonpf64}\Java\jre1.8.0_503')) or
     DirExists(ExpandConstant('{commonpf}\Java\jre1.8.0_503')) then
  begin Result := True; LogDebug('IsJre8Installed -> True (jre1.8.0_503 folder)'); Exit; end;

  LogDebug('IsJre8Installed -> False');
end;

function IsJdk17Installed(): Boolean;
var
  ver, home: string;
begin
  Result := False;

  if RegQueryStringValue(HKLM, 'SOFTWARE\JavaSoft\JDK', 'CurrentVersion', ver) then
    if (Copy(ver, 1, 2) = '17') and ReadJavaHomeFromKey(HKLM, 'SOFTWARE\JavaSoft\JDK\' + ver, home) then
    begin Result := True; LogDebug('IsJdk17Installed -> True (JDK ' + ver + ' @ ' + home + ')'); Exit; end;

  if ReadJavaHomeFromKey(HKLM, 'SOFTWARE\JavaSoft\JDK\17', home) or
     ReadJavaHomeFromKey(HKLM, 'SOFTWARE\JavaSoft\JDK\17.0.12', home) then
  begin Result := True; LogDebug('IsJdk17Installed -> True @ ' + home); Exit; end;

  if FileExists(ExpandConstant('{commonpf64}\Java\jdk-17\bin\java.exe')) or
     FileExists(ExpandConstant('{commonpf}\Java\jdk-17\bin\java.exe')) or
     FileExists(ExpandConstant('{commonpf64}\Java\jdk-17.0.12\bin\java.exe')) or
     FileExists(ExpandConstant('{commonpf}\Java\jdk-17.0.12\bin\java.exe')) then
  begin Result := True; LogDebug('IsJdk17Installed -> True (jdk-17 folder)'); Exit; end;

  LogDebug('IsJdk17Installed -> False');
end;

function IsCamaleonAlreadyInstalled(): Boolean;
begin
  Result :=
    RegKeyExists(HKLM, CAMALEON_UNINSTALL_KEY) or
    RegKeyExists(HKCU, CAMALEON_UNINSTALL_KEY) or
    FileExists(ExpandConstant('{commonpf}\CamaleonBillboard\camaleon_billboard.exe')) or
    FileExists(ExpandConstant('{commonpf64}\CamaleonBillboard\camaleon_billboard.exe'));
  LogDebug('IsCamaleonAlreadyInstalled -> ' + BoolToStr(Result));
end;

function IsUpdateMode(): Boolean;
begin
  Result := G_AlreadyInstalled and Assigned(PageRepair) and PageRepair.Values[0];
end;

function IsFullReinstallMode(): Boolean;
begin
  Result := G_AlreadyInstalled and Assigned(PageRepair) and PageRepair.Values[1];
end;

function ShouldWipeAppData(): Boolean;
begin
  Result := not IsUpdateMode();
end;

function IsPreserveAppDataMode(): Boolean;
begin
  Result := IsUpdateMode();
end;

function VCRuntimeDllExists(): Boolean;
var
  sys32Path, sysWow64Path: string;
begin
  sys32Path := ExpandConstant('{sys}\vcruntime140_1.dll');
  sysWow64Path := ExpandConstant('{syswow64}\vcruntime140_1.dll');

  Result := FileExists(sys32Path);
  if IsWin64 and not Result then
    Result := FileExists(sysWow64Path);

  LogDebug('VCRuntimeDllExists -> ' + BoolToStr(Result) + ' (checked: ' + sys32Path + ')');
end;

function IsVCRedistInstalled(): Boolean;
var
  version: string;
  regPath: string;
begin
  Result := False;

  if IsWin64 then
  begin
    regPath := 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64';
    if RegQueryStringValue(HKLM, regPath, 'Version', version) then
    begin
      Result := True;
      LogDebug('IsVCRedistInstalled -> True (x64 found in registry: ' + version + ')');
      Exit;
    end;

    regPath := 'SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64';
    if RegQueryStringValue(HKLM, regPath, 'Version', version) then
    begin
      Result := True;
      LogDebug('IsVCRedistInstalled -> True (x64 found in WOW6432Node: ' + version + ')');
      Exit;
    end;
  end
  else
  begin
    regPath := 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x86';
    if RegQueryStringValue(HKLM, regPath, 'Version', version) then
    begin
      Result := True;
      LogDebug('IsVCRedistInstalled -> True (x86 found in registry: ' + version + ')');
      Exit;
    end;
  end;

  LogDebug('IsVCRedistInstalled -> False (not found in registry)');
end;

function NeedsVCRedist(): Boolean;
var
  arch: string;
  dllExists, redistInstalled: Boolean;
begin
  dllExists := VCRuntimeDllExists();
  redistInstalled := IsVCRedistInstalled();

  Result := not dllExists and not redistInstalled;

  if IsWin64 then arch := 'x64' else arch := 'x86';

  if Result then
    LogDebug('>>> EJECUTANDO PASO 0.5a/0.5b: Instalando VC++ Redistributable (' + arch + ')')
  else
    LogDebug('NeedsVCRedist (' + arch + ') -> False (DLL exists: ' + BoolToStr(dllExists) +
               ', Redist installed: ' + BoolToStr(redistInstalled) + ')');
end;

function VCRedistInstalledButDllMissing(): Boolean;
begin
  Result := IsVCRedistInstalled() and not VCRuntimeDllExists() and FileExists(ExpandConstant('{tmp}\vcruntime140_1.dll'));
  if Result then
    LogDebug('>>> EJECUTANDO PASO 0.6a: VC++ instalado pero DLL falta - copiando directamente')
  else
    LogDebug('VCRedistInstalledButDllMissing -> False (no se ejecuta paso 0.6a)');
end;

function StillNeedsVCRuntimeDll(): Boolean;
var
  wasJustInstalled: Boolean;
begin
  wasJustInstalled := IsVCRedistInstalled();
  Result := not VCRuntimeDllExists() and wasJustInstalled and FileExists(ExpandConstant('{tmp}\vcruntime140_1.dll'));
  if Result then
    LogDebug('>>> EJECUTANDO PASO 0.6b: VC++ instalado pero DLL aun falta - copiando como fallback')
  else
    LogDebug('StillNeedsVCRuntimeDll -> False (no se ejecuta paso 0.6b)');
end;

function FinalDllCopyNeeded(): Boolean;
begin
  Result := not VCRuntimeDllExists() and FileExists(ExpandConstant('{tmp}\vcruntime140_1.dll'));
  if Result then
    LogDebug('>>> EJECUTANDO PASO 0.6c [ULTIMO RECURSO]: DLL aun falta - copiando sin importar estado de VC++')
  else
    LogDebug('FinalDllCopyNeeded -> False (DLL ya presente o archivo fuente no disponible)');
end;

function ShouldCreateDesktopIcon: Boolean;
begin
  Result := not FileExists(ExpandConstant('{autodesktop}\Camaleon Billboard.lnk'));
end;

function ShouldCreateStartMenuIcon: Boolean;
begin
  Result := not FileExists(ExpandConstant('{group}\Camaleon Billboard.lnk'));
end;

procedure InitializeWizard;
var
  L, T, W, H: Integer;
begin
  G_LogTempPath    := ExpandConstant('{tmp}') + '\' + INSTALLER_LOG_NAME;
  G_LogFinalPath   := '';
  G_LogMirrorToApp := False;
  G_Verbose        := False;
  G_LastStatus     := '';
  G_MariaDBWasInstalled := False;
  G_AlreadyInstalled := IsCamaleonAlreadyInstalled();

  if G_AlreadyInstalled then
  begin
    PageRepair := CreateInputOptionPage(wpWelcome,
      CustomMessage('RepairPageCaption'),
      CustomMessage('RepairPageDescription'),
      CustomMessage('RepairPageSubCaption'),
      True, False);
    PageRepair.Add(CustomMessage('RepairOptionUpdate'));
    PageRepair.Add(CustomMessage('RepairOptionReinstall'));
    PageRepair.Values[0] := True;
  end
  else
    PageRepair := nil;

  LogMemo := TMemo.Create(WizardForm.InstallingPage);
  LogMemo.Parent := WizardForm.InstallingPage;

  L := WizardForm.ProgressGauge.Left;
  T := WizardForm.ProgressGauge.Top + WizardForm.ProgressGauge.Height + ScaleY(8);
  W := WizardForm.InstallingPage.ClientWidth  - L - ScaleX(8);
  H := WizardForm.InstallingPage.ClientHeight - T - ScaleY(8);

  LogMemo.SetBounds(L, T, W, H);
  LogMemo.ScrollBars := ssBoth;
  LogMemo.ReadOnly := True;
  LogMemo.WantReturns := True;
  LogMemo.WantTabs := True;

  G_WizardHwnd := WizardForm.Handle;
  G_StatusTimerId := SetTimer(G_WizardHwnd, STATUS_TIMER_ID, 250, CreateCallback(@StatusTimerProc));
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (PageRepair <> nil) and (PageID = PageRepair.ID) then
    Result := not G_AlreadyInstalled
  else if PageID = wpSelectDir then
    Result := IsPreserveAppDataMode();
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  sAnsi: AnsiString;
begin
  if CurStep = ssInstall then
  begin
    StopCamaleonProcesses;

    G_Verbose := WizardIsTaskSelected('verbose');
    LogDebug('Verbose selected -> ' + BoolToStr(G_Verbose));

    if G_Verbose then
    begin
      G_LogFinalPath := ExpandConstant('{app}\' + INSTALLER_LOG_NAME);
      LogDebug('Log final path set to ' + G_LogFinalPath);
    end;

    if Assigned(LogMemo) then
      LogMemo.Lines.Clear;
    G_LastStatus := '';

    if G_MariaDBWasInstalled then
      LogUser(CustomMessage('LogMariaDBFound'))
    else
      LogUser(CustomMessage('LogMariaDBRemote'));

    if IsUpdateMode() then
      LogUser(CustomMessage('LogUpdateMode'))
    else if IsFullReinstallMode() then
      LogUser(CustomMessage('LogReinstallMode'));

    LogDebug('=== VERIFICACION INICIAL ===');
    VCRuntimeDllExists();
    IsVCRedistInstalled();
    NeedsVCRedist();
    IsMariaDBInstalled();
    IsMySqlOdbcInstalled();
    NeedsVB6();
    IsJre8Installed();
    IsJdk17Installed();
    LogDebug('=== FIN VERIFICACION INICIAL ===');
    LogDebug('Nota: Billboard solo INSTALA VC++ Redistributable; MariaDB/Java/VB6/ODBC no se instalan (app usa mysql1 + BD remota).');
  end;

  if CurStep = ssPostInstall then
  begin
    LogDebug('--- PostInstall: a continuación se ejecutan las tareas [Run] ---');
    SyncStatusToMemo;
  end;

  if CurStep = ssDone then
  begin
    LogDebug('=== VERIFICACION FINAL: vcruntime140_1.dll ===');
    if VCRuntimeDllExists() then
      LogDebug('EXITO: vcruntime140_1.dll presente en el sistema')
    else
    begin
      LogDebug('ADVERTENCIA: vcruntime140_1.dll AUN NO ENCONTRADA');
      LogUser(CustomMessage('LogVCWarn'));
    end;

    LogDebug('=== VERIFICACION FINAL (resto deps, solo log) ===');
    LogDebug('MariaDB local -> ' + BoolToStr(IsMariaDBInstalled()));
    LogDebug('MySQL ODBC 3.51 -> ' + BoolToStr(IsMySqlOdbcInstalled()));
    LogDebug('VB6 needed -> ' + BoolToStr(NeedsVB6()));
    LogDebug('JRE 8 -> ' + BoolToStr(IsJre8Installed()));
    LogDebug('JDK 17 -> ' + BoolToStr(IsJdk17Installed()));

    G_LogMirrorToApp := G_Verbose;
    if G_Verbose and (G_LogFinalPath <> '') and LoadStringFromFile(G_LogTempPath, sAnsi) then
      SaveStringToFile(G_LogFinalPath, String(sAnsi), False);

    if G_Verbose and FileExists(G_LogTempPath) and LoadStringFromFile(G_LogTempPath, sAnsi) then
    begin
      LogMemo.Lines.Text := String(sAnsi);
      LogMemo.SelStart := Length(LogMemo.Text);
      LogMemo.SelLength := 0;
    end;

    LogUser(CustomMessage('LogDone'));
  end;
end;

procedure StopCamaleonProcesses;
var
  ResultCode: Integer;
begin
  if WizardForm <> nil then
    WizardForm.StatusLabel.Caption := CustomMessage('StatusStopCamaleon');
  LogDebug('>>> Stopping Camaleon Billboard before file copy');

  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM camaleon_billboard.exe /T',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  LogDebug('taskkill camaleon_billboard.exe -> ' + IntToStr(ResultCode));

  Sleep(1000);
end;

function PrepareToInstall(var NeedsRestart: Boolean): string;
begin
  G_Verbose := WizardIsTaskSelected('verbose');
  G_MariaDBWasInstalled := IsMariaDBInstalled();

  { Aviso informativo: no se instala BD local. }
  if not G_MariaDBWasInstalled then
    MsgBox(CustomMessage('MariaDBHint'), mbInformation, MB_OK);

  StopCamaleonProcesses;
  Result := '';
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
end;

function InitializeUninstall(): Boolean;
begin
  StopCamaleonProcesses;
  Result := True;
end;

procedure DeinitializeSetup();
begin
  if (G_StatusTimerId <> 0) and (G_WizardHwnd <> 0) then
  begin
    KillTimer(G_WizardHwnd, STATUS_TIMER_ID);
    G_StatusTimerId := 0;
  end;
end;

procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);
begin
  SyncStatusToMemo;
end;
