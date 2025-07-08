::[Bat To Exe Converter]
::
::YAwzoRdxOk+EWAjk
::fBw5plQjdCaDJHSh02NwGyJ6b0SkFUefNYky7f+73/iIqEgeQPEDf4bP0qGMYOMf5UvhSYU00kZWl8wDQhJbcXI=
::YAwzuBVtJxjWCl3EqQJgSA==
::ZR4luwNxJguZRRnk
::Yhs/ulQjdF+5
::cxAkpRVqdFKZSjk=
::cBs/ulQjdF+5
::ZR41oxFsdFKZSTk=
::eBoioBt6dFKZSDk=
::cRo6pxp7LAbNWATEpCI=
::egkzugNsPRvcWATEpCI=
::dAsiuh18IRvcCxnZtBJQ
::cRYluBh/LU+EWAnk
::YxY4rhs+aU+IeA==
::cxY6rQJ7JhzQF1fEqQJhSA==
::ZQ05rAF9IBncCkqN+0xwdVsFLA==
::ZQ05rAF9IAHYFVzEqQIjOBJXSRCLOnL6FrkJ+4g=
::eg0/rx1wNQPfEVWB+kM9LVsJDBeSNWi/Erwa8aXr4/+U71gNUOMrfZ2V2LWaQA==
::fBEirQZwNQPfEVWB+kM9LVsJDGQ=
::cRolqwZ3JBvQF1fEqQIkIB4UWQiWNWa7ErBc6eT3ouOJ70ITUaIPd5jeyIeGJewfqlbnZ589wjpcl9lMARpWfxWiYAh0sGFXpCS2J8iIugn4CkmH4gsDC2x3gnfZijJ7Zct4n9EK1i69+Q3wkeUn2Hb7Ub4dVAM=
::dhA7uBVwLU+EWHSm2iI=
::YQ03rBFzNR3SWATElA==
::dhAmsQZ3MwfNWATElA==
::ZQ0/vhVqMQ3MEVWAtB9wSA==
::Zg8zqx1/OA3MEVWAtB9wSA==
::dhA7pRFwIByZRRnMvg2fwZSIkE7LXA==
::Zh4grVQjdCaDJHSh02NwGyJ6b0SkFUefNYky7f+73/iIqEgeQPEDS5/Uzr2IOaAw+ETnfpM/6kwJpNgcBRhdahutd0IkpXtR+GGdMqc=
::YB416Ek+Zm8=
::
::
::978f952a14a936cc963da21a135fa983
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
echo ^|  Spicetify Plus - Updater ^& Runner                              ^|
echo =====================================================================
echo.
echo [+] Initializing PowerShell to download and run the script...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $scriptName = 'spicetify-plus.ps1'; $scriptUrl = 'https://raw.githubusercontent.com/MBNpro-ir/spicetify-plus/main/spicetify-plus.ps1'; Write-Host '=================================================' -ForegroundColor 'Cyan'; Write-Host '|        Downloading Spicetify Plus Script        |' -ForegroundColor 'White'; Write-Host '=================================================' -ForegroundColor 'Cyan'; Write-Host ''; try { Write-Host '- Downloading the latest version from GitHub...' -NoNewline; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptName -ErrorAction Stop; Write-Host ' > OK' -ForegroundColor 'Green'; } catch { Write-Host ' > FAILED' -ForegroundColor 'Red'; Write-Host 'Error: Failed to download the latest version.' -ForegroundColor 'Red'; Write-Host ('Details: ' + $_.Exception.Message) -ForegroundColor 'Gray'; Write-Host '-------------------------------------------------' -ForegroundColor 'Yellow'; if (Test-Path $scriptName) { Write-Host 'Could not update. Attempting to run the existing local version...' -ForegroundColor 'Yellow'; } else { Write-Host 'No local version found. The script cannot proceed.' -ForegroundColor 'Red'; Read-Host 'Press Enter to exit'; exit 1; } } Write-Host ''; Write-Host '- Starting Spicetify Plus script...'; Write-Host '-------------------------------------------------'; & .\\$scriptName; }"

echo.
echo =====================================================================
echo ^|  Script execution has finished. Press any key to exit.          ^|
echo =====================================================================
pause > nul
popd
endlocal 