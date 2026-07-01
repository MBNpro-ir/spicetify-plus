[CmdletBinding()]
param(
    [string]$InputFile = '..\spicetify-plus.ps1',
    [string]$OutputFile = '..\spicetify-plus.exe',
    [string]$Version = '2.0.0'
)

$ErrorActionPreference = 'Stop'

function Import-LocalPs2Exe {
    $command = Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue
    if ($command) {
        return
    }

    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $repoRoot = Resolve-Path (Join-Path $scriptRoot '..')
    $toolsRoot = Join-Path $repoRoot '.tools'
    New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null

    $module = Get-ChildItem -Path $toolsRoot -Recurse -Filter 'ps2exe.psd1' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $module) {
        Write-Host "Downloading ps2exe into .tools..." -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -Confirm:$false | Out-Null
        }
        Save-Module -Name ps2exe -Path $toolsRoot -Repository PSGallery -Force -Confirm:$false -ErrorAction Stop
        $module = Get-ChildItem -Path $toolsRoot -Recurse -Filter 'ps2exe.psd1' -ErrorAction Stop | Select-Object -First 1
    }

    Import-Module $module.FullName -Force -ErrorAction Stop
}

Import-LocalPs2Exe

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = Resolve-Path (Join-Path $scriptRoot '..')
$inputCandidate = if ([System.IO.Path]::IsPathRooted($InputFile)) { $InputFile } else { Join-Path $scriptRoot $InputFile }
$outputCandidate = if ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path $scriptRoot $OutputFile }
$inputPath = Resolve-Path $inputCandidate
$outputPath = [System.IO.Path]::GetFullPath($outputCandidate)

$params = @{
    inputFile = $inputPath.Path
    outputFile = $outputPath
    title = 'Spicetify Plus'
    description = 'Menu-driven Windows wrapper for Spicetify CLI and Marketplace'
    company = 'MBN'
    product = 'Spicetify Plus'
    version = $Version
    copyright = 'MBN'
}

Write-Host "Building $outputPath" -ForegroundColor Cyan
Invoke-PS2EXE @params
Write-Host "Built $outputPath" -ForegroundColor Green
