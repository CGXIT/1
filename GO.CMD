@echo off
::============================================================================
::
::  GO.CMD Beta V1 - OOBE / Desktop unified setup
::
::  Just double-click. That's it.
::    - On OOBE  : runs immediately
::    - On Desktop : asks for admin, then runs
::  Skips anything already done. Never reboots unless edition was upgraded.
::
::============================================================================

::---------------------------------------------------------------- Auto UAC elevate
:: If not admin, relaunch with admin rights via PowerShell. Works on both OOBE
:: (no UAC prompt, runs immediately as defaultuser0 already admin) and Desktop
:: (UAC prompt appears, user clicks Yes).
fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

setlocal EnableExtensions EnableDelayedExpansion
title Setup Beta V1

set "ScriptVersion=1.0"
set "ProGenericKey=VK7JG-NPHTM-C97JM-9MPGT-3V66T"
set "StateKey=HKLM\SOFTWARE\AutoOOBE"
set "PolicyVer=2"

:: Safe PATH
set "Path=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem"

:: Log file
cd /d "%~dp0"
set "LogFile=%~dp0SETUP-%COMPUTERNAME%.log"
echo. > "%LogFile%" 2>nul
if errorlevel 1 set "LogFile=%TEMP%\SETUP-%COMPUTERNAME%.log"

color 1F
cls

::============================================================================
:: Banner + scenario detection
::============================================================================
echo.
echo  ============================================================
echo    Hands-Free window Upgrading v%ScriptVersion%
echo  ============================================================
echo.

:: Detect scenario: OOBE or Desktop
set "Scenario=DESKTOP"
if /i "%USERNAME%"=="defaultuser0" set "Scenario=OOBE"
tasklist /FI "IMAGENAME eq oobeldr.exe" 2>nul | find /i "oobeldr" >nul && set "Scenario=OOBE"
reg query "HKLM\SYSTEM\Setup" /v OOBEInProgress 2>nul | find "0x1" >nul && set "Scenario=OOBE"

:: Detect Windows
set "WinName=" & set "WinBuild=" & set "WinVer="
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName 2^>nul ^| findstr ProductName') do set "WinName=%%B"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber 2^>nul ^| findstr CurrentBuildNumber') do set "WinBuild=%%A"
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion 2^>nul ^| findstr DisplayVersion') do set "WinVer=%%A"

set "CurEdition="
for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v EditionID 2^>nul ^| findstr EditionID') do set "CurEdition=%%A"

call :LOG "============================================================"
call :LOG "  SETUP v%ScriptVersion% started  Time: %DATE% %TIME%"
call :LOG "  Computer: %COMPUTERNAME%  User: %USERNAME%"
call :LOG "  Windows: %WinName%  Build: %WinBuild% (%WinVer%)"
call :LOG "  Edition: %CurEdition%   Scenario: %Scenario%"
call :LOG "============================================================"

echo   Scenario   : %Scenario%
echo   Computer   : %COMPUTERNAME%
echo   Windows    : %WinName% Build %WinBuild% (%WinVer%)
echo   Edition    : %CurEdition%
echo.
echo   This will take about 30 seconds. Do not close the window.
echo.
ping -n 4 127.0.0.1 >nul

::============================================================================
:: STEP 1/5 : BypassNRO  (only meaningful in OOBE, harmless on Desktop)
::============================================================================
echo  ----------------------------------------------------------
echo   [1/5] BypassNRO  (allow local account in OOBE)
echo  ----------------------------------------------------------
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO 2>nul | find "0x1" >nul
if !errorlevel!==0 (
    echo         [SKIP] already set
    call :LOG "[1/5] BypassNRO already set"
) else (
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f >nul 2>&1
    if !errorlevel!==0 (
        echo         [OK] applied
        call :LOG "[1/5] BypassNRO applied"
    ) else (
        echo         [WARN] write failed
        call :LOG "[1/5] BypassNRO FAILED"
    )
)
echo.

::============================================================================
:: STEP 2/5 : Language / FOD download blocks
::============================================================================
echo  ----------------------------------------------------------
echo   [2/5] Block auto language pack / FOD downloads
echo  ----------------------------------------------------------

:: Check if already done at current policy version
set "AlreadyDone=0"
for /f "tokens=3" %%A in ('reg query "%StateKey%" /v LangPolicyVer 2^>nul ^| findstr LangPolicyVer') do (
    set /a "PrevVer=%%A" 2>nul
    if !PrevVer! GEQ %PolicyVer% set "AlreadyDone=1"
)

if "!AlreadyDone!"=="1" (
    echo         [SKIP] policy already at version %PolicyVer%
    call :LOG "[2/5] Lang policy already v%PolicyVer%"
) else (
    :: 1. The actual official policy (per Microsoft Learn FOD docs)
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v RestrictLanguagePacksAndFeaturesInstall /t REG_DWORD /d 1 /f >nul 2>&1
    :: 2. Block Store auto-download of LXP
    reg add "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v AutoDownload /t REG_DWORD /d 2 /f >nul 2>&1
    :: 3. Block WU as source for FOD
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing" /v RepairContentServerSource /t REG_DWORD /d 2 /f >nul 2>&1
    :: 4. Lock sign-in input methods
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v BlockUserInputMethodsForSignIn /t REG_DWORD /d 1 /f >nul 2>&1
    :: 5. Prevent LPRemove cleanup
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v BlockCleanupOfUnusedPreinstalledLangPacks /t REG_DWORD /d 1 /f >nul 2>&1
    :: 6. Clean v3.0 garbage value if present
    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v AllowedLanguages /f >nul 2>&1
    :: 7. Disable scheduled tasks (silently OK if they don't exist)
    schtasks /Change /TN "\Microsoft\Windows\LanguageComponentsInstaller\Installation" /Disable >nul 2>&1
    schtasks /Change /TN "\Microsoft\Windows\LanguageComponentsInstaller\ReconcileLanguageResources" /Disable >nul 2>&1
    schtasks /Change /TN "\Microsoft\Windows\MUI\LPRemove" /Disable >nul 2>&1
    :: 8. Refresh GP so it takes effect now (only meaningful on Desktop)
    if /i "%Scenario%"=="DESKTOP" gpupdate /target:computer /force >nul 2>&1

    :: 9. Verify
    reg query "HKLM\SOFTWARE\Policies\Microsoft\Control Panel\International" /v RestrictLanguagePacksAndFeaturesInstall 2>nul | find "0x1" >nul
    if !errorlevel!==0 (
        echo         [OK] applied and verified
        call :LOG "[2/5] Lang blocks applied and verified"
    ) else (
        echo         [WARN] verification failed
        call :LOG "[2/5] Lang blocks FAILED to verify"
    )
)
echo.

::============================================================================
:: STEP 3/5 : Edition upgrade (Home -> Pro)
::============================================================================
echo  ----------------------------------------------------------
echo   [3/5] Upgrade to Pro (if currently Home)
echo  ----------------------------------------------------------
echo %CurEdition% | findstr /i /r "Professional Enterprise Education" >nul
if !errorlevel!==0 (
    echo         [SKIP] already %CurEdition%
    call :LOG "[3/5] Edition skip - already %CurEdition%"
    set "DidUpgrade=0"
) else (
    echo         Running changepk.exe ... this takes 1-3 minutes, please wait
    call :LOG "[3/5] Running changepk for %CurEdition% -> Pro"
    changepk.exe /ProductKey %ProGenericKey%
    set "ChExit=!errorlevel!"
    call :LOG "[3/5] changepk exit code: !ChExit!"
    echo         Waiting 30 seconds for switch to apply...
    ping -n 31 127.0.0.1 >nul

    set "NewEdition="
    for /f "tokens=3" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v EditionID 2^>nul ^| findstr EditionID') do set "NewEdition=%%A"
    echo         New edition: !NewEdition!
    call :LOG "[3/5] New edition: !NewEdition!"
    set "DidUpgrade=1"
)
echo.

::============================================================================
:: STEP 4/5 : Save state record
::============================================================================
echo  ----------------------------------------------------------
echo   [4/5] Save state record
echo  ----------------------------------------------------------
reg add "%StateKey%" /v LastVersion   /t REG_SZ    /d "%ScriptVersion%"  /f >nul 2>&1
reg add "%StateKey%" /v LastRunTime   /t REG_SZ    /d "%DATE% %TIME%"    /f >nul 2>&1
reg add "%StateKey%" /v LastRunUser   /t REG_SZ    /d "%USERNAME%"       /f >nul 2>&1
reg add "%StateKey%" /v LastScenario  /t REG_SZ    /d "%Scenario%"       /f >nul 2>&1
reg add "%StateKey%" /v LangPolicyVer /t REG_DWORD /d %PolicyVer%        /f >nul 2>&1
echo         [OK] saved to %StateKey%
call :LOG "[4/5] State saved"
echo.

::============================================================================
:: STEP 5/5 : Summary
::============================================================================
echo  ----------------------------------------------------------
echo   [5/5] Done
echo  ----------------------------------------------------------
echo.

color 2F
echo  ============================================================
echo    ALL DONE
echo  ============================================================
echo.
echo    Log file : %LogFile%
echo.

if /i "%Scenario%"=="OOBE" (
    echo    You are in OOBE. Next steps on the screen behind:
    echo      1. Region    : Singapore
    echo      2. Keyboard  : US
    echo      3. Network   : connect WiFi  OR  "I don't have internet"
    echo      4. If WiFi   : "Set up for work or school"
    echo                     login with company account
    echo.
    if "%DidUpgrade%"=="1" (
        echo    [INFO] Edition was upgraded. A reboot is recommended
        echo           before continuing OOBE.
    )
) else (
    echo    You are on Desktop. Nothing else to do.
    if "%DidUpgrade%"=="1" (
        echo.
        echo    [INFO] Edition was upgraded - REBOOT REQUIRED to finalize.
    )
)

echo.
echo  ============================================================
echo   Press any key to close this window...
pause >nul
exit /b 0

::============================================================================
:LOG
set "_msg=%~1"
echo [%TIME%] !_msg!>> "%LogFile%"
exit /b 0