@echo off
setlocal

:: ============================================================================
::  Spicetify Plus - Updater and Runner
::  Author: MBNpro-ir
::  This batch file downloads the latest version of the spicetify-plus.ps1
::  script from GitHub and executes it with Administrator privileges.
:: ============================================================================

:: 1. Check for Administrator privileges and re-launch if necessary.
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    powershell -Command "Start-Process -FilePath '%~s0' -Verb RunAs"
    exit /b
)

:: Set console title
title Spicetify Plus

:: 2. Change directory to the script's location to ensure paths are correct.
pushd "%~dp0"

:: 3. Use PowerShell to download and execute the main script.
echo.
echo =====================================================================
echo ^|  Spicetify Plus - Updater & Runner                              ^|
echo =====================================================================
echo.
echo [+] Initializing PowerShell to download and run the script...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "& {
    $scriptName = 'spicetify-plus.ps1';
    $scriptUrl = 'https://raw.githubusercontent.com/MBNpro-ir/spicetify-plus/main/spicetify-plus.ps1';

    # Custom banner for the PowerShell part
    Write-Host '=================================================' -ForegroundColor 'Cyan'
    Write-Host '|        Downloading Spicetify Plus Script        |' -ForegroundColor 'White'
    Write-Host '=================================================' -ForegroundColor 'Cyan'
    Write-Host ''

    try {
        Write-Host ""- Downloading the latest version from GitHub..."" -NoNewline
        # Use Invoke-WebRequest to download the file
        $ProgressPreference = 'SilentlyContinue'; # Hide download progress bar for a cleaner look
        Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptName -ErrorAction Stop;
        Write-Host ' > OK' -ForegroundColor 'Green';
    } catch {
        Write-Host ' > FAILED' -ForegroundColor 'Red';
        Write-Host ""Error: Failed to download the latest version."" -ForegroundColor 'Red';
        Write-Host ('Details: ' + $_.Exception.Message) -ForegroundColor 'Gray';
        Write-Host '-------------------------------------------------' -ForegroundColor 'Yellow'
        if (Test-Path $scriptName) {
            Write-Host ""Could not update. Attempting to run the existing local version..."" -ForegroundColor 'Yellow';
        } else {
            Write-Host ""No local version found. The script cannot proceed."" -ForegroundColor 'Red';
            Read-Host 'Press Enter to exit';
            exit 1;
        }
    }

    Write-Host """";
    Write-Host ""- Starting Spicetify Plus script...""
    Write-Host ""-------------------------------------------------"";

    # Execute the downloaded script. The script handles its own exit logic.
    & .\$scriptName;
}"

echo.
echo =====================================================================
echo ^|  Script execution has finished. Press any key to exit.          ^|
echo =====================================================================
pause > nul
popd
endlocal 