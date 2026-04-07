$ErrorActionPreference = 'Continue'

Write-Host "=== ChumChim Post-Install ===" -ForegroundColor Cyan

# === 1. OPTIMIZE ===
Write-Host "[1/5] Optimizing..." -ForegroundColor Yellow
Set-Service wuauserv -StartupType Disabled -EA SilentlyContinue
Set-Service UsoSvc -StartupType Disabled -EA SilentlyContinue
Set-MpPreference -DisableRealtimeMonitoring $true -EA SilentlyContinue
'WSearch','DiagTrack','dmwappushservice','XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc' | ForEach-Object { Set-Service $_ -StartupType Disabled -EA SilentlyContinue }
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name AllowCortana -Value 0 -PropertyType DWORD -Force -EA SilentlyContinue | Out-Null
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name NoLockScreen -Value 1 -PropertyType DWORD -Force -EA SilentlyContinue | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableFirstLogonAnimation -Value 0 -PropertyType DWORD -Force -EA SilentlyContinue | Out-Null
'SubscribedContent-338389Enabled','SubscribedContent-310093Enabled','SubscribedContent-338388Enabled','SilentInstalledAppsEnabled','SystemPaneSuggestionsEnabled' | ForEach-Object {
    New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name $_ -Value 0 -PropertyType DWORD -Force -EA SilentlyContinue | Out-Null
}
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name HideFileExt -Value 0 -EA SilentlyContinue
New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Value 0 -PropertyType DWORD -Force -EA SilentlyContinue | Out-Null
Write-Host "  Done!" -ForegroundColor Green

# === 2. LANGUAGE ===
Write-Host "[2/5] Setting language..." -ForegroundColor Yellow
Set-WinUserLanguageList -LanguageList en-US,th-TH -Force -EA SilentlyContinue
Set-WinSystemLocale th-TH -EA SilentlyContinue
Set-WinHomeLocation -GeoId 227 -EA SilentlyContinue
tzutil /s "SE Asia Standard Time"
Write-Host "  Done!" -ForegroundColor Green

# === 3. INSTALL OFFICE ===
Write-Host "[3/5] Installing Office..." -ForegroundColor Yellow
$odtDir = "C:\Scripts\ODT"
New-Item -ItemType Directory -Path $odtDir -Force | Out-Null

# Download ODT
$setupPath = "$odtDir\setup.exe"
if (-not (Test-Path $setupPath)) {
    Write-Host "  Downloading Office Deployment Tool..."
    try {
        Invoke-WebRequest -Uri 'https://officecdn.microsoft.com/pr/wsus/setup.exe' -OutFile $setupPath -UseBasicParsing
    } catch {
        Write-Host "  Cannot download ODT. Check internet." -ForegroundColor Red
    }
}

if (Test-Path $setupPath) {
    # Config XML — Office with Word, Excel, PowerPoint only
    $configXml = "$odtDir\config.xml"
    @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="PerpetualVL2021">
    <Product ID="ProPlus2021Volume">
      <Language ID="en-us" />
      <Language ID="th-th" />
      <ExcludeApp ID="Access" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="OneDrive" />
      <ExcludeApp ID="OneNote" />
      <ExcludeApp ID="Outlook" />
      <ExcludeApp ID="Publisher" />
      <ExcludeApp ID="Teams" />
    </Product>
  </Add>
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Property Name="AUTOACTIVATE" Value="0" />
  <Updates Enabled="FALSE" />
  <Display Level="None" AcceptEULA="TRUE" />
</Configuration>
"@ | Set-Content $configXml -Encoding UTF8

    # Download Office
    Write-Host "  Downloading Office files (~1-2 GB)..."
    & $setupPath /download $configXml

    # Install Office
    Write-Host "  Installing Office..."
    & $setupPath /configure $configXml
    Write-Host "  Office installed!" -ForegroundColor Green
} else {
    Write-Host "  Skipped (no internet or ODT failed)" -ForegroundColor Yellow
}

# === 4. UWF (Unified Write Filter) ===
Write-Host "[4/5] Setting up UWF..." -ForegroundColor Yellow
$uwf = Get-WindowsOptionalFeature -Online -FeatureName "Client-UnifiedWriteFilter" -EA SilentlyContinue
if ($uwf) {
    Enable-WindowsOptionalFeature -Online -FeatureName "Client-UnifiedWriteFilter" -All -NoRestart -EA SilentlyContinue | Out-Null
    Write-Host "  UWF enabled!" -ForegroundColor Green
} else {
    Write-Host "  UWF not available on this edition" -ForegroundColor Yellow
}

# Create Teacher shortcuts (avoid brackets in filename)
New-Item -ItemType Directory -Path "C:\Users\Public\Desktop" -Force -EA SilentlyContinue | Out-Null

"@echo off`ntitle Freeze PC`necho This will FREEZE the PC.`necho After restart, changes will be lost.`necho.`npause`nuwfmgr volume protect C:`nuwfmgr filter enable`nshutdown /r /t 5 /f" | Out-File "C:\Users\Public\Desktop\Teacher-Freeze-PC.bat" -Encoding ASCII
"@echo off`ntitle Unfreeze PC`necho This will UNFREEZE the PC.`necho Changes will be saved permanently.`necho.`npause`nuwfmgr filter disable`nshutdown /r /t 5 /f" | Out-File "C:\Users\Public\Desktop\Teacher-Unfreeze-PC.bat" -Encoding ASCII
Write-Host "  Desktop shortcuts created!" -ForegroundColor Green

# === 5. ACTIVATE ===
Write-Host "[5/5] Activating Windows..." -ForegroundColor Yellow
cscript //nologo C:\Windows\System32\slmgr.vbs /skms kms8.msguides.com
cscript //nologo C:\Windows\System32\slmgr.vbs /ato
Write-Host "  Done!" -ForegroundColor Green

# Cleanup RunOnce
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "PostInstall" -EA SilentlyContinue

Write-Host ""
Write-Host "=== POST-INSTALL COMPLETE ===" -ForegroundColor Green
Write-Host "  Office: Word, Excel, PowerPoint (Thai+English)"
Write-Host "  UWF: Teacher-Freeze/Unfreeze on Desktop"
Write-Host "  Language: English + Thai"
Write-Host "  Optimized for school use"
Write-Host ""
Write-Host "  Next: Sysprep then Clone with ChumChim"
