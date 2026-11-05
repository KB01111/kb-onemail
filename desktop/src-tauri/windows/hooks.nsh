!include "LogicLib.nsh"
!include "FileFunc.nsh"

; Preserve the existing identifier-based WebView2 data directory and all sessions.
; Never run an uninstaller obtained from a registry string.
Var BetterBoxOldDir
Var BetterBoxOldExe

!macro NSIS_HOOK_PREINSTALL
  StrCpy $BetterBoxOldDir ""
  ReadRegStr $0 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BetterBox" "DisplayName"
  ReadRegStr $1 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BetterBox" "DisplayVersion"
  ReadRegStr $2 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BetterBox" "InstallLocation"
  ${If} $0 == "BetterBox"
  ${AndIf} $1 == "0.2.1"
    ; Tauri records InstallLocation as a quoted directory, not an executable command.
    StrCpy $7 $2 1
    StrCpy $8 $2 1 -1
    ${If} $7 == '$\"'
    ${AndIf} $8 == '$\"'
      StrCpy $2 $2 -1 1
    ${EndIf}
    ; Only the old default per-user install is eligible for automatic cleanup.
    GetFullPathName $3 "$LOCALAPPDATA\BetterBox"
    GetFullPathName $4 "$2"
    ${If} $3 == $4
      StrCpy $BetterBoxOldExe "$4\betterbox-desktop.exe"
      IfFileExists "$BetterBoxOldExe" 0 migration_checked
      GetDLLVersion "$BetterBoxOldExe" $5 $6
      ; 0.2.1.0 is encoded as high=2 low=65536 in the PE version resource.
      ${If} $5 == 2
      ${AndIf} $6 == 65536
        StrCpy $BetterBoxOldDir "$4"
        ; Reuse only this verified legacy installation directory.
        StrCpy $INSTDIR "$4"
        ; The Tauri section selected its output directory before this hook.
        SetOutPath "$INSTDIR"
      ${EndIf}
    ${EndIf}
  ${EndIf}
  migration_checked:
!macroend

!macro NSIS_HOOK_POSTINSTALL
  ; Windows Search reads the app icon from its Start menu shortcut. Explicitly
  ; set the icon path so it does not fall back to the generic application icon.
  CreateShortCut "$SMPROGRAMS\KB OneMail.lnk" "$INSTDIR\kb-onemail.exe" "" "$INSTDIR\kb-onemail.exe" 0 SW_SHOWNORMAL "" "KB OneMail"
  ; A toast can reactivate this application from Action Center after it exits.
  WriteRegStr HKCU "Software\Classes\AppUserModelId\dev.kevinjbridgelal.betterbox" "DisplayName" "KB OneMail"
  WriteRegStr HKCU "Software\Classes\AppUserModelId\dev.kevinjbridgelal.betterbox" "IconUri" "$INSTDIR\kb-onemail.exe"
  ; Advertise an app-specific mailto ProgID; leave the user's default choice intact.
  WriteRegStr HKCU "Software\Clients\Mail\KB OneMail\Capabilities" "ApplicationName" "KB OneMail"
  WriteRegStr HKCU "Software\Clients\Mail\KB OneMail\Capabilities" "ApplicationDescription" "KB OneMail Windows email client"
  WriteRegStr HKCU "Software\Clients\Mail\KB OneMail\Capabilities" "ApplicationIcon" "$INSTDIR\kb-onemail.exe,0"
  WriteRegStr HKCU "Software\Clients\Mail\KB OneMail\Capabilities\UrlAssociations" "mailto" "KBOneMail.Mailto"
  WriteRegStr HKCU "Software\RegisteredApplications" "KB OneMail" "Software\Clients\Mail\KB OneMail\Capabilities"
  WriteRegStr HKCU "Software\Classes\KBOneMail.Mailto" "" "KB OneMail mail link"
  WriteRegStr HKCU "Software\Classes\KBOneMail.Mailto" "URL Protocol" ""
  WriteRegStr HKCU "Software\Classes\KBOneMail.Mailto\DefaultIcon" "" "$INSTDIR\kb-onemail.exe,0"
  WriteRegStr HKCU "Software\Classes\KBOneMail.Mailto\shell\open\command" "" '$\"$INSTDIR\kb-onemail.exe$\" $\"%1$\"'
  ${If} $BetterBoxOldDir != ""
    ; Only remove the exact validated executable. Never remove a directory/profile.
    Delete "$BetterBoxOldExe"
    ${IfNot} ${FileExists} "$BetterBoxOldExe"
      ; Preserve other product records unless they still point at the validated path.
      ReadRegStr $0 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BetterBox" "InstallLocation"
      StrCpy $7 $0 1
      StrCpy $8 $0 1 -1
      ${If} $7 == '$\"'
      ${AndIf} $8 == '$\"'
        StrCpy $0 $0 -1 1
      ${EndIf}
      GetFullPathName $1 "$0"
      ${If} $1 == $BetterBoxOldDir
        DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\BetterBox"
      ${EndIf}
      ; Pass validated data through the environment, never interpolate it as code.
      System::Call 'kernel32::SetEnvironmentVariable(t "KB_ONEMAIL_OLD_EXE", t "$BetterBoxOldExe") i .r0'
      System::Call 'kernel32::SetEnvironmentVariable(t "KB_ONEMAIL_NEW_EXE", t "$INSTDIR\kb-onemail.exe") i .r0'
      nsExec::ExecToLog `"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -WindowStyle Hidden -Command "$$shell=New-Object -ComObject WScript.Shell; foreach($$folder in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('Programs'))) { $$link=Join-Path $$folder 'BetterBox.lnk'; if(Test-Path -LiteralPath $$link){$$target=$$shell.CreateShortcut($$link).TargetPath; if([string]::Equals($$target,$$env:KB_ONEMAIL_OLD_EXE,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $$link}} }; $$pins=Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'; if(Test-Path -LiteralPath $$pins){foreach($$item in Get-ChildItem -LiteralPath $$pins -Filter '*.lnk' -File){$$shortcut=$$shell.CreateShortcut($$item.FullName); if([string]::Equals($$shortcut.TargetPath,$$env:KB_ONEMAIL_OLD_EXE,[StringComparison]::OrdinalIgnoreCase)){$$shortcut.TargetPath=$$env:KB_ONEMAIL_NEW_EXE; $$shortcut.WorkingDirectory=[IO.Path]::GetDirectoryName($$env:KB_ONEMAIL_NEW_EXE); $$shortcut.IconLocation=$$env:KB_ONEMAIL_NEW_EXE+',0'; $$shortcut.Description='KB OneMail'; $$shortcut.Save()}}}"`
      System::Call 'kernel32::SetEnvironmentVariable(t "KB_ONEMAIL_OLD_EXE", p 0) i .r0'
      System::Call 'kernel32::SetEnvironmentVariable(t "KB_ONEMAIL_NEW_EXE", p 0) i .r0'
    ${EndIf}
  ${EndIf}
!macroend

!macro NSIS_HOOK_POSTUNINSTALL
  ReadRegStr $0 HKCU "Software\Classes\KBOneMail.Mailto\shell\open\command" ""
  ${If} $0 == '$\"$INSTDIR\kb-onemail.exe$\" $\"%1$\"'
    DeleteRegKey HKCU "Software\Classes\KBOneMail.Mailto"
    DeleteRegKey HKCU "Software\Clients\Mail\KB OneMail"
    ReadRegStr $0 HKCU "Software\RegisteredApplications" "KB OneMail"
    ${If} $0 == "Software\Clients\Mail\KB OneMail\Capabilities"
      DeleteRegValue HKCU "Software\RegisteredApplications" "KB OneMail"
    ${EndIf}
  ${EndIf}
  ReadRegStr $0 HKCU "Software\Classes\AppUserModelId\dev.kevinjbridgelal.betterbox" "IconUri"
  ${If} $0 == "$INSTDIR\kb-onemail.exe"
    DeleteRegKey HKCU "Software\Classes\AppUserModelId\dev.kevinjbridgelal.betterbox"
  ${EndIf}
!macroend
