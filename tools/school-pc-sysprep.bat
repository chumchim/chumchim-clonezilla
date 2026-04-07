@echo off
title ChumChim - Sysprep (Final Step)
color 0C
echo.
echo  ============================================
echo    ChumChim - Sysprep
echo    FINAL STEP before Clone!
echo  ============================================
echo.
echo  WARNING: After Sysprep, PC will SHUT DOWN.
echo  You cannot use this PC until Clone is done.
echo.
echo  Sysprep will:
echo    - Reset computer name (each PC gets unique name)
echo    - Reset SID (fixes network conflicts)
echo    - Prepare for new hardware (driver detection)
echo    - Reset activation (must re-activate after install)
echo.
echo  Make sure you have ALREADY run:
echo    school-pc-optimize.bat
echo.
echo  Press any key to start Sysprep...
echo  Or close this window to cancel.
echo.
pause

:: Check admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    echo Right-click ^> Run as Administrator
    pause
    exit /b 1
)

echo.
echo [1/3] Preparing Sysprep...

:: Remove AppX packages that commonly block Sysprep (targeted, safe)
echo   Removing AppX packages that block Sysprep...
powershell -Command "Get-AppxPackage -AllUsers | Where-Object {$_.Name -match 'Cortana|YourPhone|FeedbackHub|549981C3F5F10|WindowsCommunicationsApps|MicrosoftEdge|BingWeather|BingNews|CandyCrush|Disney|Xbox|GamingApp|Solitaire|Clipchamp|Teams|Todos|Maps|GetHelp|Getstarted|Paint3D|3DBuilder|3DViewer|People|Skype'} | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue" 2>nul
powershell -Command "Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -match 'Cortana|YourPhone|FeedbackHub|549981C3F5F10|WindowsCommunicationsApps|BingWeather|BingNews|CandyCrush|Disney|Xbox|GamingApp|Solitaire|Clipchamp|Teams|Todos|Maps|GetHelp|Getstarted|Paint3D|3DBuilder|3DViewer|People|Skype'} | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue" 2>nul

:: Disable AppX Sysprep generalize check
echo   Disabling AppX Sysprep checks...
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\Microsoft.549981C3F5F10_8wekyb3d8bbwe" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\Microsoft.YourPhone_8wekyb3d8bbwe" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\Microsoft.WindowsFeedbackHub_8wekyb3d8bbwe" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\Microsoft.WindowsCommunicationsApps_8wekyb3d8bbwe" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\Microsoft.MicrosoftEdge.Stable_8wekyb3d8bbwe" /f >nul 2>&1

:: Disable Sysprep AppX validation (force bypass)
reg add "HKLM\SYSTEM\Setup\Sysprep\Settings\Microsoft-Windows-AppxSysprep" /v CleanupState /t REG_DWORD /d 0 /f >nul 2>&1
takeown /f "%SystemRoot%\System32\Sysprep\ActionFiles\Generalize.xml" >nul 2>&1
icacls "%SystemRoot%\System32\Sysprep\ActionFiles\Generalize.xml" /grant Administrators:F >nul 2>&1

:: Remove AppxSysprep from Generalize.xml (main fix!)
echo   Removing AppxSysprep from Generalize.xml...
powershell -Command "$x = Get-Content 'C:\Windows\System32\Sysprep\ActionFiles\Generalize.xml' -Raw; $x = $x -replace '(?s)<imaging[^>]*>.*?AppX-Sysprep.*?</imaging>', ''; Set-Content 'C:\Windows\System32\Sysprep\ActionFiles\Generalize.xml' $x -Force"

echo   Done!

echo [2/3] Creating unattend.xml...

:: Create unattend.xml for Sysprep (auto setup on first boot)
mkdir "%SystemRoot%\System32\Sysprep" 2>nul
(
echo ^<?xml version="1.0" encoding="utf-8"?^>
echo ^<unattend xmlns="urn:schemas-microsoft-com:unattend"^>
echo   ^<settings pass="oobeSystem"^>
echo     ^<component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"^>
echo       ^<OOBE^>
echo         ^<HideEULAPage^>true^</HideEULAPage^>
echo         ^<HideLocalAccountScreen^>true^</HideLocalAccountScreen^>
echo         ^<HideOnlineAccountScreens^>true^</HideOnlineAccountScreens^>
echo         ^<HideWirelessSetupInOOBE^>true^</HideWirelessSetupInOOBE^>
echo         ^<ProtectYourPC^>3^</ProtectYourPC^>
echo         ^<SkipMachineOOBE^>true^</SkipMachineOOBE^>
echo         ^<SkipUserOOBE^>true^</SkipUserOOBE^>
echo       ^</OOBE^>
echo       ^<UserAccounts^>
echo         ^<LocalAccounts^>
echo           ^<LocalAccount wcm:action="add"^>
echo             ^<Name^>Student^</Name^>
echo             ^<Group^>Administrators^</Group^>
echo             ^<Password^>
echo               ^<Value^>^</Value^>
echo               ^<PlainText^>true^</PlainText^>
echo             ^</Password^>
echo           ^</LocalAccount^>
echo         ^</LocalAccounts^>
echo       ^</UserAccounts^>
echo       ^<AutoLogon^>
echo         ^<Enabled^>true^</Enabled^>
echo         ^<Username^>Student^</Username^>
echo         ^<Password^>
echo           ^<Value^>^</Value^>
echo           ^<PlainText^>true^</PlainText^>
echo         ^</Password^>
echo         ^<LogonCount^>1^</LogonCount^>
echo       ^</AutoLogon^>
echo       ^<TimeZone^>SE Asia Standard Time^</TimeZone^>
echo     ^</component^>
echo     ^<component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"^>
echo       ^<InputLocale^>0409:00000409^</InputLocale^>
echo       ^<SystemLocale^>en-US^</SystemLocale^>
echo       ^<UILanguage^>en-US^</UILanguage^>
echo       ^<UserLocale^>en-US^</UserLocale^>
echo     ^</component^>
echo   ^</settings^>
echo ^</unattend^>
) > "%SystemRoot%\System32\Sysprep\unattend.xml"
echo   Done!

echo [3/3] Running Sysprep...
echo.
echo   PC will shut down after Sysprep completes.
echo   Then boot from ChumChim USB to Clone.
echo.

:: Run Sysprep: generalize + OOBE + shutdown
"%SystemRoot%\System32\Sysprep\sysprep.exe" /generalize /oobe /shutdown /unattend:"%SystemRoot%\System32\Sysprep\unattend.xml"

if %errorlevel% neq 0 (
    echo.
    echo   Sysprep FAILED!
    echo   Check: C:\Windows\System32\Sysprep\Panther\setuperr.log
    echo.
    pause
    exit /b 1
)
