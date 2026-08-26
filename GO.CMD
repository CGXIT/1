@echo off
::============================================================================
::
::  AutoUpgrade.CMD - Windows Edition/OOBE Upgrade   (standalone, single-file)
::
::  Just double-click (or curl-download and run). That's it.
::    - On OOBE   : runs immediately (defaultuser0 is already admin)
::    - On Desktop: asks for admin, then runs
::  Skips anything already done. Never reboots unless edition was upgraded.
::
::  Visual style mirrors the family "Theme" (Core\Theme\Opt.Theme.ps1): same
::  semantic colors + step checklist + progress bar, done in PURE CMD so this
::  stays a zero-dependency single file. Overrides: set GO_NOCOLOR=1 (no ANSI)
::  or GO_ASCII=1 (ASCII glyphs) if a console renders poorly.
::
::  NOTE: params below MIRROR Core\config\Opt.Registry.psd1 [AutoUpgrade] section.
::        Keep them in sync by hand (this file ships alone, can't read psd1).
::============================================================================

::---------------------------------------------------------------- Auto UAC elevate
:: fltmc needs admin; a good proxy. OOBE(defaultuser0)=admin, no prompt. Desktop=UAC.
:: _ELEVATED re-entry guard: if EDR/policy blocks fltmc even when already admin, a naive
:: relaunch would loop forever. The relaunched (elevated) instance gets AU_ELEVATED as arg1
:: -> skip the elevate check entirely (asked once; reg ops fail harmlessly if somehow not admin).
if "%~1"=="AU_ELEVATED" goto :au_elevated
:: SECURITY: cmd searches the CURRENT DIR before PATH, and these run BEFORE the line-48 safe-PATH reset while CWD is still
:: the launch folder (Downloads etc). A co-planted fltmc.bat / powershell.bat would hijack the elevation gate (pre-UAC,
:: user-priv, but a fake-prompt escalation vector). Kill CWD-first search + call both by absolute path. (Audit 2026-07-15)
set "NoDefaultCurrentDirectoryInExePath=1"
"%SystemRoot%\System32\fltmc.exe" >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    set "SELF=%~f0"
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs -ArgumentList 'AU_ELEVATED'"
    exit /b
)
:au_elevated

setlocal EnableExtensions EnableDelayedExpansion
title AutoUpgrade

:: ------- params (MIRROR of Opt.Registry.psd1 [AutoUpgrade]) -------
set "ScriptVersion=11AUG2026"
set "ProGenericKey=VK7JG-NPHTM-C97JM-9MPGT-3V66T"
:: N editions (CoreN / CoreSingleLanguageN) need the Pro N generic key; non-N key -> 0xC004F050. (Audit 2026-07-15)
set "ProGenericKeyN=2B87N-8KFHP-DKV6R-YKQYG-DPBQM"
set "StateKey=HKLM\SOFTWARE\AutoUpgrade"
set "PolicyVer=2"
set "OobeRegion=Singapore"
set "OobeKeyboard=US"

:: ------- safe PATH -------
set "Path=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem"
cd /d "%~dp0"

:: ------- style: ANSI color (Theme palette) + glyphs (progressive enhancement) -------
for /f %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
reg add "HKCU\Console" /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>&1
if defined GO_NOCOLOR (
    set "cA=" & set "cOk=" & set "cWarn=" & set "cErr=" & set "cTxt=" & set "cMut=" & set "c0="
) else (
    set "cA=%ESC%[36m" & set "cOk=%ESC%[32m" & set "cWarn=%ESC%[33m" & set "cErr=%ESC%[31m" & set "cTxt=%ESC%[37m" & set "cMut=%ESC%[90m" & set "c0=%ESC%[0m"
)
:: Glyphs: ASCII only, so every conhost + default bitmap font renders them (no mojibake).
:: (The opt-in GO_UNICODE dots/blocks were removed: many consoles render them as garbage,
::  AND embedding raw UTF-8 glyph bytes in this .CMD risks mis-tokenization under the
::  console's startup OEM codepage - which fires before any chcp. ASCII stays pure + safe.)
set "gDone=*" & set "gCur=>" & set "gPend=." & set "gSkip=." & set "gArrow=>" & set "gBarF=#" & set "gBarE=-"
set "gRuleLine=------------------------------------------------------------------------"

:: ------- unified per-user log (mirrors Opt.Logging.ps1 Resolve-OptLogDir naming) -------
:: Timestamp via PowerShell (locale-independent, clean yyyyMMdd_HHmmss; %DATE% is localized + has weekday).
:: 2026-08-11 FIX: this used bare `powershell`, which can NEVER resolve here - the safe PATH set above is
::   System32;SystemRoot;Wbem and powershell.exe lives in System32\WindowsPowerShell\v1.0 (not on it).
::   So TS always fell back to %RANDOM% and log names came out like stox_AutoUpgrade_18029.log (no date
::   stamp at all -> no chronological sort, and it breaks the {user}_{App}_{stamp} naming every other tool
::   in this repo follows). Absolute path also closes the co-planted powershell.bat hijack the header
::   comment warns about (same reason line 34 already uses the absolute path).
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "TS="
:: no quotes around %PSEXE%: %SystemRoot% never contains spaces, and quoting it inside for /f ('...') would
:: need the awkward doubled-quote cmd /c dance (and breaks outright once 2^>nul follows the closing quote).
for /f %%i in ('%PSEXE% -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do set "TS=%%i"
:: RANDOM fallback keeps the name unique-ish if powershell.exe is genuinely missing/blocked; the AU_ prefix
:: makes that case self-evident in the filename instead of masquerading as a timestamp.
if not defined TS set "TS=AU%RANDOM%"
set "LogFile="
for %%D in ("C:\AutoKit\Logs" "%LOCALAPPDATA%\OptLogs" "%~dp0Logs" "%TEMP%\OptLogs") do (
    if not defined LogFile (
        mkdir "%%~D" >nul 2>&1
        (echo.>"%%~D\.probe") >nul 2>&1
        if exist "%%~D\.probe" (
            del "%%~D\.probe" >nul 2>&1
            set "LogFile=%%~D\%USERNAME%_AutoUpgrade_%TS%.log"
        )
    )
)
if not defined LogFile set "LogFile=%TEMP%\%USERNAME%_AutoUpgrade_%TS%.log"

echo ##STEP 1/5 CHECK 2

:: ------- scenario detection: OOBE or Desktop -------
set "Scenario=DESKTOP"
if /i "%USERNAME%"=="defaultuser0" set "Scenario=OOBE"
tasklist /FI "IMAGENAME eq oobeldr.exe" 2>nul | find /i "oobeldr" >nul && set "Scenario=OOBE"
reg query "HKLM\SYSTEM\Setup" /v OOBEInProgress 2>nul | find "0x1" >nul && set "Scenario=OOBE"

:: ------- detect Windows -------
set "WinName=" & set "WinBuild=" & set "WinVer=" & set "CurEdition="
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName 2^>nul ^| findstr ProductName') do set "WinName=%%B"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber 2^>nul ^| findstr CurrentBuildNumber') do set "WinBuild=%%A"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion 2^>nul ^| findstr DisplayVersion') do set "WinVer=%%A"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v EditionID 2^>nul ^| findstr EditionID') do set "CurEdition=%%A"
:: validate CurrentBuildNumber is all-digits before set /a. Empty/garbage from a failed reg
:: query would silently become 0 -> read as an OLD build -> the 24H2 "BypassNRO may be ignored"
:: caution would be wrongly skipped. Unknown build -> flag it so the caution still shows (fail-safe).
set "BuildNum=0" & set "BuildUnknown="
echo %WinBuild%| findstr /r "^[0-9][0-9]*$" >nul 2>&1
if errorlevel 1 (
    set "BuildUnknown=1"
) else (
    set /a "BuildNum=%WinBuild%" 2>nul
)
:: Win11 caption fix: registry ProductName still says "Windows 10" on Win11 (MS never updated it); build>=22000 corrects the display name. (ASCII-only per rule #1: no CJK in .CMD)
if !BuildNum! GEQ 22000 if defined WinName set "WinName=!WinName:Windows 10=Windows 11!"
:: MaybeNoNRO = build is 24H2+ (>=26100) OR unknown -> BypassNRO may not take effect
set "MaybeNoNRO="
if !BuildNum! GEQ 26100 set "MaybeNoNRO=1"
if defined BuildUnknown set "MaybeNoNRO=1"

call :LOG "============================================================"
call :LOG "  AutoUpgrade %ScriptVersion% started  Time: %DATE% %TIME%"
call :LOG "  Computer: %COMPUTERNAME%  User: %USERNAME%"
call :LOG "  Windows: %WinName%  Build: %WinBuild% (%WinVer%)"
call :LOG "  Edition: %CurEdition%   Scenario: %Scenario%"
call :LOG "============================================================"
>>"%LogFile%" echo Tool=AutoUpgrade
>>"%LogFile%" echo Version=%ScriptVersion%
>>"%LogFile%" echo Mode=%Scenario%
>>"%LogFile%" echo Started=%DATE% %TIME:~0,8%
>>"%LogFile%" echo Machine=%COMPUTERNAME%
>>"%LogFile%" echo User=%USERNAME%

echo ##STEP 1/5 CHECK 12

:: ------- step model (5 steps) -------
set "STL1=BypassNRO (local account)"
set "STL2=Language pack policy"
set "STL3=Upgrade to Pro"
set "STL4=Save state"
set "STL5=Finish"
set "ST1=pending" & set "ST2=pending" & set "ST3=pending" & set "ST4=pending" & set "ST5=pending"
set "DoneCount=0" & set "PCT=0" & set "NOWTX=Starting..."
call :render
ping -n 3 127.0.0.1 >nul

::============================================================================
:: STEP 1 : BypassNRO (build-aware; MS removed it on 24H2+/build>=26100)
::============================================================================
set "ST1=current" & set "PCT=8" & set "NOWTX=Enabling local-account setup (BypassNRO)..."
call :render
echo ##STEP 2/5 BYPASS 18
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO 2>nul | find "0x1" >nul
if !errorlevel!==0 (
    set "ST1=done"
    call :LOG "[1/5] BypassNRO already set"
) else (
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f >nul 2>&1
    if defined MaybeNoNRO (
        rem released 24H2 25H2 BypassNRO value still works so mark done not warn keep BypassMayFail for ms-cxh guidance
        set "ST1=done"
        set "BypassMayFail=1"
        call :LOG "[1/5] BypassNRO applied (build !BuildNum! 24H2+; value works on released builds; ms-cxh fallback shown)"
    ) else (
        set "ST1=done"
        call :LOG "[1/5] BypassNRO applied (build !BuildNum!)"
    )
)
set "DoneCount=1" & set "PCT=20" & set "NOWTX="
call :render
echo ##STEP 2/5 BYPASS 25

::============================================================================
:: STEP 2 : Language / FOD policy   (Audit 2026-07-15)
::   DESKTOP : ensure language packs are FREE to download/use (revert any OOBE block).
::   OOBE    : block auto language-pack/FOD downloads (clean/fast imaging) AND drop a
::             self-unblocker + RunOnce so the first real-user desktop logon frees them.
::   Verify ALL THREE policy hives before stamping done (not 1 of 6 -> no idempotency lie).
::============================================================================
set "ST2=current" & set "PCT=28"
call :render
echo ##STEP 3/5 LANG 35
if /i "%Scenario%"=="DESKTOP" (
    set "NOWTX=Ensuring language packs are unrestricted..."
    call :render
    call :lang_unblock
    set "ST2=done"
    call :LOG "[2/5] Desktop: language packs unblocked (free to download / use)"
) else (
    set "NOWTX=Blocking auto language-pack / FOD downloads (OOBE)..."
    call :render
    set "AlreadyDone=0"
    for /f "tokens=3" %%A in ('reg query "%StateKey%" /v LangPolicyVer 2^>nul ^| findstr LangPolicyVer') do (
        set /a "PrevVer=%%A" 2>nul
        if !PrevVer! GEQ %PolicyVer% set "AlreadyDone=1"
    )
    if "!AlreadyDone!"=="1" (
        set "ST2=done"
        call :LOG "[2/5] Lang policy already v%PolicyVer%"
    ) else (
        reg add "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v RestrictLanguagePacksAndFeaturesInstall /t REG_DWORD /d 1 /f >nul 2>&1
        reg add "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v AutoDownload /t REG_DWORD /d 2 /f >nul 2>&1
        reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing" /v RepairContentServerSource /t REG_DWORD /d 2 /f >nul 2>&1
        reg add "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v BlockUserInputMethodsForSignIn /t REG_DWORD /d 1 /f >nul 2>&1
        reg add "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v BlockCleanupOfUnusedPreinstalledLangPacks /t REG_DWORD /d 1 /f >nul 2>&1
        reg delete "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v AllowedLanguages /f >nul 2>&1
        schtasks /Change /TN "\Microsoft\Windows\LanguageComponentsInstaller\Installation" /Disable >nul 2>&1
        schtasks /Change /TN "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources" /Disable >nul 2>&1
        schtasks /Change /TN "\Microsoft\Windows\MUI\LPRemove" /Disable >nul 2>&1
        if /i "%Scenario%"=="DESKTOP" gpupdate /target:computer /force >nul 2>&1
        rem verify all THREE hives so a silent cross-hive failure is not stamped done and skipped forever
        set "V2ok=1"
        reg query "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v RestrictLanguagePacksAndFeaturesInstall 2>nul | find "0x1" >nul || set "V2ok=0"
        reg query "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v AutoDownload 2>nul | find "0x2" >nul || set "V2ok=0"
        reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing" /v RepairContentServerSource 2>nul | find "0x2" >nul || set "V2ok=0"
        if "!V2ok!"=="1" (
            set "ST2=done"
            call :LOG "[2/5] Lang blocks applied and verified (3 hives)"
        ) else (
            set "ST2=warn"
            call :LOG "[2/5] Lang blocks FAILED to verify - will retry next run" ERROR
        )
    )
    call :lang_write_unblocker
)
set "DoneCount=2" & set "PCT=45" & set "NOWTX="
call :render
echo ##STEP 3/5 LANG 48

::============================================================================
:: STEP 3 : Edition upgrade (Home -> Pro) - existence check + poll (no blind wait)
::============================================================================
set "ST3=current" & set "PCT=50" & set "NOWTX=Checking edition..."
call :render
echo ##STEP 4/5 EDITION 60
set "DidUpgrade=0" & set "RebootForEdition=" & set "NewEdition=%CurEdition%"
rem Policy (supervisor 2026-07-17): this tool ONLY does Home/Core -> Pro. Pro/Enterprise/Education are >= Pro so leave them.
rem Enterprise is a HIGHER tier than Pro and is reached naturally by joining the company domain after Home->Pro -- never changepk it down to Pro.
echo %CurEdition% | findstr /i /r "Professional Enterprise Education" >nul
if !errorlevel!==0 (
    set "ST3=done"
    call :LOG "[3/5] Edition skip - already %CurEdition% - Pro or higher, not downgraded"
) else (
    where changepk.exe >nul 2>&1
    if errorlevel 1 (
        set "ST3=warn"
        call :LOG "[3/5] changepk.exe not found - skipped" WARN
    ) else (
        rem N editions need the Pro N key non-N key fails with 0xC004F050
        set "UpgradeKey=!ProGenericKey!"
        if /i "!CurEdition:~-1!"=="N" set "UpgradeKey=!ProGenericKeyN!"
        set "NOWTX=Upgrading %CurEdition% -> Pro (changepk)..."
        call :render
        call :LOG "[3/5] Running changepk for %CurEdition% -> Pro (key !UpgradeKey:~0,5!...)"
        changepk.exe /ProductKey !UpgradeKey!
        set "ChExit=!errorlevel!"
        call :LOG "[3/5] changepk exit code: !ChExit!"
        rem changepk Home to Pro is reboot-gated EditionID wont flip in this session so verdict is by exit code not a poll
        rem keep one opportunistic EditionID re-read DidUpgrade set only on a genuine staged or switched result
        for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v EditionID 2^>nul ^| findstr EditionID') do set "NewEdition=%%A"
        echo !NewEdition!| findstr /i /r "Professional Enterprise Education" >nul
        if not errorlevel 1 (
            set "ST3=done" & set "DidUpgrade=1"
            call :LOG "[3/5] Edition switched online: !NewEdition!"
        ) else (
            if "!ChExit!"=="0" (
                set "ST3=reboot" & set "DidUpgrade=1" & set "RebootForEdition=1"
                call :LOG "[3/5] Edition upgrade staged (changepk exit 0); takes effect after reboot"
            ) else (
                set "ST3=warn"
                call :LOG "[3/5] changepk failed (exit !ChExit!), still !NewEdition!" WARN
            )
        )
    )
)
set "DoneCount=3" & set "PCT=70" & set "NOWTX="
call :render
echo ##STEP 4/5 EDITION 82

::============================================================================
:: STEP 4 : Save state record
::============================================================================
set "ST4=current" & set "PCT=78" & set "NOWTX=Saving state..."
call :render
reg add "%StateKey%" /v LastVersion   /t REG_SZ    /d "%ScriptVersion%"  /f >nul 2>&1
reg add "%StateKey%" /v LastRunTime   /t REG_SZ    /d "%DATE% %TIME%"    /f >nul 2>&1
reg add "%StateKey%" /v LastRunUser   /t REG_SZ    /d "%USERNAME%"       /f >nul 2>&1
reg add "%StateKey%" /v LastScenario  /t REG_SZ    /d "%Scenario%"       /f >nul 2>&1
:: only stamp LangPolicyVer when STEP 2 actually verified (done) - else a failed/warn lang-block
:: step would be recorded as done and skipped forever next run (idempotency lie). Retry next time.
:: OOBE only: the DESKTOP scenario UNblocks (no block to record) -> stamping there = false 'blocked v2' marker.
if /i "%Scenario%"=="OOBE" if "!ST2!"=="done" reg add "%StateKey%" /v LangPolicyVer /t REG_DWORD /d %PolicyVer% /f >nul 2>&1
set "ST4=done"
call :LOG "[4/5] State saved"
set "DoneCount=4" & set "PCT=90" & set "NOWTX="
call :render

::============================================================================
:: STEP 5 : Finish
::============================================================================
set "ST5=done" & set "DoneCount=5" & set "PCT=100" & set "NOWTX="
call :render
call :LOG "[5/5] Done"
if not defined DidUpgrade set "DidUpgrade=0"
:: real status from step states (was hardcoded SUCCESS -> lied to log digest when a step only warned)
set "RunStatus=SUCCESS"
set /a WarnN=0
if "!ST1!"=="warn" set "RunStatus=PARTIAL" & set /a WarnN+=1
if "!ST2!"=="warn" set "RunStatus=PARTIAL" & set /a WarnN+=1
if "!ST3!"=="warn" set "RunStatus=PARTIAL" & set /a WarnN+=1
if "!ST4!"=="warn" set "RunStatus=PARTIAL" & set /a WarnN+=1
set "ExitN=0"
if not "!RunStatus!"=="SUCCESS" set "ExitN=1"
:: 2026-08-11: schema alignment with Write-LogResult's ##SUMMARY (Core\Opt.Logging.ps1). This footer was
::   hand-written and diverged: no mode / warn / dur / exit / started / ended -> in the digest an AutoUpgrade
::   row showed "-" for every count column and could not be told apart from a log with no footer at all.
::   Keys deliberately match the PS writer's names; "scenario" stays too (old Knowledge rules may key on it).
::   Absent-by-design: ok/fail/skip (this script has no per-item task loop) and err (no OptErrCount here) ->
::   the key is OMITTED rather than written as -1 (negative sentinels read as real numbers - same fix as the
::   PS side got today).
set "END_TS="
for /f %%i in ('%PSEXE% -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do set "END_TS=%%i"
set "SumStarted="
set "SumEnded="
set "DurPart="
if "%TS:~0,2%"=="20" set "SumStarted=,"started":"%TS:~0,4%-%TS:~4,2%-%TS:~6,2% %TS:~9,2%:%TS:~11,2%:%TS:~13,2%""
if "%END_TS:~0,2%"=="20" set "SumEnded=,"ended":"%END_TS:~0,4%-%END_TS:~4,2%-%END_TS:~6,2% %END_TS:~9,2%:%END_TS:~11,2%:%END_TS:~13,2%""
if "%TS:~0,2%"=="20" if "%END_TS:~0,2%"=="20" call :au_dur
>>"%LogFile%" echo ##SUMMARY {"tool":"AutoUpgrade","ver":"%ScriptVersion%","mode":"%Scenario%","status":"!RunStatus!","warn":!WarnN!!DurPart!,"exit":!ExitN!,"scenario":"%Scenario%","edition":"%CurEdition%","build":"%WinBuild%","upgraded":"%DidUpgrade%","machine":"%COMPUTERNAME%","user":"%USERNAME%"!SumStarted!!SumEnded!}
echo ##STEP 5/5 DONE 100
if "%RebootForEdition%"=="1" echo ##REBOOT 1
if "!RunStatus!"=="PARTIAL" echo ##RESULT PARTIAL

echo(
echo   !cOk!ALL DONE!c0!
echo   !cMut!%gRuleLine%!c0!
echo   !cMut!Log!c0!   %LogFile%
echo(
if /i "%Scenario%"=="OOBE" (
    echo   !cA!Next in OOBE ^(screen behind^):!c0!
    echo     Region: %OobeRegion%    Keyboard: %OobeKeyboard%
    echo     Network: connect WiFi  OR  "I don't have internet"
    echo     If WiFi: "Set up for work or school" -^> company account
    if defined BypassMayFail (
        echo(
        echo   !cWarn!If OOBE still forces a Microsoft account:!c0!  ^(build %WinBuild%^)
        echo         1. Shift+F10, then run:  start ms-cxh:localonly
        echo            ^(opens local-account setup directly, no reboot; 24H2 / early 25H2^)
        echo         2. Or click "Domain join instead" ^(edition is now Pro^)
        echo         3. BypassNRO is already set - a reboot may be needed for it to apply
        echo         4. Last resort ^(newest patched builds^): rebuild USB via Rufus ^(local account^)
    )
    if "%RebootForEdition%"=="1" echo   !cWarn![INFO]!c0! Edition upgrade staged - reboot to finalize before continuing.
) else (
    echo   !cTxt!You are on Desktop. Language packs are unrestricted ^(free to add^).!c0!
    if "%RebootForEdition%"=="1" echo   !cWarn![INFO]!c0! Edition upgrade staged - REBOOT REQUIRED to finalize.
)
echo(
if not defined AK_NOPAUSE echo   !cMut!Press any key to close...!c0!
if not defined AK_NOPAUSE pause >nul
exit /b 0

::============================================================================
:: Subroutines
::============================================================================
:render
rem GUI mode: when AK_GUI is set, skip the whole cls+banner+bar+step drawing. GUI panel is driven only by ##STEP markers, not this human-readable stream.
if defined AK_GUI goto :eof
cls
echo(
echo   !cA!AutoUpgrade!c0!   !cMut!%ScriptVersion%!c0!
echo   !cMut!%gRuleLine%!c0!
echo   !cMut!Computer!c0!  %COMPUTERNAME%  !cMut!.!c0!  %USERNAME%  !cMut!.!c0!  %Scenario%
echo   !cMut!System  !c0!  %WinName% Build %WinBuild% ^(%WinVer%^)
echo   !cMut!Edition !c0!  %CurEdition%
echo(
set /a "fill=PCT*24/100"
set "bar="
for /L %%i in (1,1,24) do (
    if %%i LEQ !fill! ( set "bar=!bar!!gBarF!" ) else ( set "bar=!bar!!gBarE!" )
)
echo   !cA!!bar!!c0!   %DoneCount%/5   %PCT%%%
echo(
call :drawstep 1
call :drawstep 2
call :drawstep 3
call :drawstep 4
call :drawstep 5
echo(
if defined NOWTX echo   !cA!!gArrow!!c0! !cTxt!!NOWTX!!c0!
goto :eof

:drawstep
call set "st=%%ST%~1%%"
call set "lb=%%STL%~1%%"
set "g=!gPend!" & set "c=!cMut!"
if "!st!"=="current" ( set "g=!gCur!"  & set "c=!cA!" )
if "!st!"=="done"    ( set "g=!gDone!" & set "c=!cOk!" )
if "!st!"=="warn"    ( set "g=!gDone!" & set "c=!cWarn!" )
if "!st!"=="reboot"  ( set "g=!gDone!" & set "c=!cWarn!" )
echo     !c!!g!!c0!  !cTxt!!lb!!c0!
goto :eof

:lang_unblock
:: Revert every OOBE-time language/FOD restriction so the desktop can freely download + use language packs.
:: Idempotent + harmless if never blocked (reg delete of absent value / enable of already-enabled task = no-op).
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v RestrictLanguagePacksAndFeaturesInstall /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v BlockUserInputMethodsForSignIn /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v BlockCleanupOfUnusedPreinstalledLangPacks /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing" /v RepairContentServerSource /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v AutoDownload /f >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\LanguageComponentsInstaller\Installation" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\MUI\LPRemove" /Enable >nul 2>&1
goto :eof

:lang_write_unblocker
:: OOBE only: drop a self-contained unblocker on the MACHINE (ProgramData survives OOBE->desktop, unlike the USB) and
:: point HKLM RunOnce at it -> the first real-user desktop logon auto-frees language packs. Echoed redirects are ^-escaped
:: so they land inside LangUnblock.cmd (not redirect this echo).
set "AU_DATA=%ProgramData%\AutoUpgrade"
mkdir "%AU_DATA%" >nul 2>&1
set "AU_UNB=%AU_DATA%\LangUnblock.cmd"
> "%AU_UNB%" echo @echo off
>>"%AU_UNB%" echo reg delete "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v RestrictLanguagePacksAndFeaturesInstall /f ^>nul 2^>^&1
>>"%AU_UNB%" echo reg delete "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v BlockUserInputMethodsForSignIn /f ^>nul 2^>^&1
>>"%AU_UNB%" echo reg delete "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v BlockCleanupOfUnusedPreinstalledLangPacks /f ^>nul 2^>^&1
>>"%AU_UNB%" echo reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing" /v RepairContentServerSource /f ^>nul 2^>^&1
>>"%AU_UNB%" echo reg delete "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v AutoDownload /f ^>nul 2^>^&1
>>"%AU_UNB%" echo schtasks /Change /TN "\Microsoft\Windows\LanguageComponentsInstaller\Installation" /Enable ^>nul 2^>^&1
>>"%AU_UNB%" echo schtasks /Change /TN "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources" /Enable ^>nul 2^>^&1
>>"%AU_UNB%" echo schtasks /Change /TN "\Microsoft\Windows\MUI\LPRemove" /Enable ^>nul 2^>^&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v AutoUpgradeLangUnblock /t REG_SZ /d "\"%AU_UNB%\"" /f >nul 2>&1
call :LOG "[2/5] OOBE: wrote LangUnblock.cmd + RunOnce (desktop auto-frees language packs on first logon)"
goto :eof

:au_dur
REM Wall-clock seconds between %TS% and %END_TS% (both yyyyMMdd_HHmmss), pure batch - no extra powershell spawn.
REM The 1HH-100 trick is mandatory: set /a reads a leading-zero pair like 08 as octal and errors out.
REM Cross-midnight runs add a day; only correct for runs under 24h, which is every real AutoUpgrade run.
set /a __s1=(1%TS:~9,2%-100)*3600+(1%TS:~11,2%-100)*60+(1%TS:~13,2%-100)
set /a __s2=(1%END_TS:~9,2%-100)*3600+(1%END_TS:~11,2%-100)*60+(1%END_TS:~13,2%-100)
set /a __d=__s2-__s1
if %__d% lss 0 set /a __d+=86400
set "DurPart=,"dur":%__d%"
goto :eof

:LOG
REM %~1=message, %~2=level (optional, default INFO). Matches unified [ts][LEVEL] log format so LogDigest can extract by level.
set "_msg=%~1"
set "_lvl=%~2"
if not defined _lvl set "_lvl=INFO"
REM redirect-first: if !_msg! ends in a digit, "echo ...N>> file" makes CMD read N>> as a stream-handle
REM redirect (e.g. 2>>), losing/truncating the line. Putting the redirect first removes the digit-adjacency.
>> "%LogFile%" echo [%TIME:~0,8%][!_lvl!] !_msg!
goto :eof
