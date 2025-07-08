# We set this to 'SilentlyContinue' globally and handle errors manually in each function.
$ErrorActionPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Global:githubToken = ""

function Write-Success {
    [CmdletBinding()] param()
    process { Write-Host -Object ' > OK' -ForegroundColor 'Green' }
}

function Write-Error-Message {
    param([string]$Message)
    Write-Host "`nAn error occurred:`n$Message" -ForegroundColor 'Red'
}

function Test-PowerShellVersion {
    Write-Host -Object 'Checking if your PowerShell version is compatible...' -NoNewline
    if ($PSVersionTable.PSVersion -ge [version]'5.1') {
        Write-Success
        return $true
    }
    Write-Host -Object ' > FAILED' -ForegroundColor 'Red'
    Write-Warning -Message 'PowerShell 5.1 or higher is required.'
    return $false
}

function Test-GitHubToken {
    Write-Host -Object 'Checking GitHub API token status...' -NoNewline

    if ([string]::IsNullOrWhiteSpace($Global:githubToken)) {
        Write-Host " > NOT SET" -ForegroundColor 'Yellow'
        Write-Host "   Note: Script will work without token but may encounter GitHub rate limits." -ForegroundColor 'Gray'
        Write-Host "   To avoid rate limits, add a GitHub Personal Access Token to line 4 of this script." -ForegroundColor 'Gray'
        return $false
    }

    try {
        $testUrl = 'https://api.github.com/user'
        $testHeaders = @{ "Authorization" = "Bearer $Global:githubToken" }
        $testResult = Invoke-RestMethod -Uri $testUrl -Headers $testHeaders -ErrorAction Stop
        Write-Host " > VALID" -ForegroundColor 'Green'
        Write-Host "   GitHub API authenticated as: $($testResult.login)" -ForegroundColor 'Gray'
        Write-Host "   Environment variable GITHUB_TOKEN is set for Spicetify CLI" -ForegroundColor 'Gray'
        return $true
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($errorMessage -like "*401*" -or $errorMessage -like "*Bad credentials*" -or $errorMessage -like "*Unauthorized*") {
            Write-Host " > INVALID" -ForegroundColor 'Red'
            Write-Host "   Your GitHub token is expired or incorrect. Please update line 4 of this script." -ForegroundColor 'Gray'
        }
        elseif ($errorMessage -like "*403*" -or $errorMessage -like "*rate limit*") {
            Write-Host " > RATE LIMITED" -ForegroundColor 'Yellow'
            Write-Host "   GitHub API rate limit reached, but token appears to be valid." -ForegroundColor 'Gray'
            return $true
        }
        else {
            Write-Host " > UNKNOWN" -ForegroundColor 'Yellow'
            Write-Host "   Unable to verify token: $errorMessage" -ForegroundColor 'Gray'
        }
        return $false
    }
}

function Press-EnterToContinue {
    Read-Host -Prompt "Press Enter to return to the menu..."
}

function Install-Spotify {
    # FINAL, CORRECTED FIX: Initialize the variable OUTSIDE and BEFORE the try block.
    $tempFilePath = $null
    try {
        Write-Host "Checking for Spotify installation..." -ForegroundColor 'Cyan'
        $spotifyExeInstalled = $false
        $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
        foreach ($path in $regPaths) {
            if (Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Spotify*' }) {
                $spotifyExeInstalled = $true
                break
            }
        }
        $spotifyUwpInstalled = Get-AppxPackage -Name "*SpotifyMusic*" -ErrorAction SilentlyContinue

        if ($spotifyExeInstalled -or $spotifyUwpInstalled) {
            Write-Host "Spotify is already installed." -ForegroundColor 'Green'
            return
        }

        Write-Host "Spotify not found. Downloading and installing automatically..." -ForegroundColor 'Yellow'
        $spotifySetupUrl = 'https://download.spotify.com/SpotifySetup.exe'
        $tempFilePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "SpotifySetup.exe"

        Write-Host "Downloading from $spotifySetupUrl..." -NoNewline
        Invoke-WebRequest -Uri $spotifySetupUrl -OutFile $tempFilePath -ErrorAction Stop
        Write-Success
        Write-Host "Installing Spotify silently... Please wait." -NoNewline
        Start-Process -FilePath $tempFilePath -ArgumentList "/SILENT" -Wait -ErrorAction Stop
        Write-Success
        Write-Host "Spotify installed successfully." -ForegroundColor 'Green'
    }
    catch {
        Write-Error-Message $_.Exception.Message
    }
    finally {
        # This block now works safely because $tempFilePath is guaranteed to exist (even if it's $null).
        if ($tempFilePath -and (Test-Path -Path $tempFilePath)) {
            Remove-Item -Path $tempFilePath -Force
        }
    }
}

function Remove-Spotify {
    try {
        Write-Host "Attempting to uninstall Spotify..." -ForegroundColor 'Cyan'

        # Check for UWP/Microsoft Store version first
        $spotifyUwp = Get-AppxPackage -Name "*SpotifyMusic*" -ErrorAction SilentlyContinue
        if ($spotifyUwp) {
            Write-Host "Found Spotify (Microsoft Store version). Uninstalling..." -ForegroundColor 'Yellow'
            Remove-AppxPackage -Package $spotifyUwp.PackageFullName -ErrorAction Stop
            Write-Host "Spotify uninstalled successfully." -ForegroundColor 'Green'
            return
        }

        # Check for standard version in registry
        $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
        foreach ($path in $regPaths) {
            $regKeys = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Spotify*' }
            if ($regKeys) {
                foreach ($regKey in $regKeys) {
                    if ($regKey.UninstallString) {
                        Write-Host "Found Spotify: $($regKey.DisplayName)" -ForegroundColor 'Yellow'

                        # Parse the UninstallString properly
                        $uninstallString = $regKey.UninstallString.Trim()

                        # Handle quoted paths
                        if ($uninstallString.StartsWith('"')) {
                            $endQuote = $uninstallString.IndexOf('"', 1)
                            if ($endQuote -gt 0) {
                                $exePath = $uninstallString.Substring(1, $endQuote - 1)
                                $arguments = $uninstallString.Substring($endQuote + 1).Trim()
                            } else {
                                $exePath = $uninstallString.Trim('"')
                                $arguments = ""
                            }
                        } else {
                            # Split by first space
                            $spaceIndex = $uninstallString.IndexOf(' ')
                            if ($spaceIndex -gt 0) {
                                $exePath = $uninstallString.Substring(0, $spaceIndex)
                                $arguments = $uninstallString.Substring($spaceIndex + 1)
                            } else {
                                $exePath = $uninstallString
                                $arguments = ""
                            }
                        }

                        # Check if the executable exists
                        if (Test-Path -Path $exePath) {
                            Write-Host "Running uninstaller: $exePath" -ForegroundColor 'Yellow'

                            # Add silent flag if not already present
                            if ($arguments -notlike "**/S*" -and $arguments -notlike "**/s*" -and $arguments -notlike "*/S*" -and $arguments -notlike "*/s*") {
                                $arguments += " /S"
                            }

                            Start-Process -FilePath $exePath -ArgumentList $arguments.Trim() -Wait -ErrorAction Stop
                            Write-Host "Spotify uninstaller finished successfully." -ForegroundColor 'Green'
                            return
                        } else {
                            Write-Warning "Uninstaller not found at: $exePath"
                        }
                    }
                }
            }
        }

        # Alternative method: Try to find Spotify installation and manually remove
        $spotifyPaths = @(
            "$env:APPDATA\Spotify",
            "$env:LOCALAPPDATA\Spotify"
        )

        $foundInstallation = $false
        foreach ($path in $spotifyPaths) {
            if (Test-Path -Path $path) {
                $foundInstallation = $true
                Write-Host "Found Spotify installation at: $path" -ForegroundColor 'Yellow'

                # Kill Spotify processes
                Get-Process -Name "Spotify*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

                # Remove the directory
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "Removed Spotify folder: $path" -ForegroundColor 'Green'
            }
        }

        if ($foundInstallation) {
            Write-Host "Spotify has been manually removed." -ForegroundColor 'Green'
        } else {
            Write-Warning "Could not find any Spotify installation to remove."
        }
    }
    catch {
        Write-Error-Message $_.Exception.Message
    }
}

function Get-Spicetify {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { $architecture = 'x64' }
    elseif ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $architecture = 'arm64' }
    else { $architecture = 'x32' }

    Write-Host 'Fetching the latest spicetify version...' -NoNewline
    $latestRelease = $null
    $apiUrl = 'https://api.github.com/repos/spicetify/cli/releases/latest'
    $useToken = $false

    # Check if GitHub token is provided and not empty
    if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
        $headers = @{ "Authorization" = "Bearer $Global:githubToken" }
        try {
            $latestRelease = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
            $useToken = $true
            Write-Host " (using GitHub API token)" -ForegroundColor 'Green'
        }
        catch {
            $errorMessage = $_.Exception.Message
            if ($errorMessage -like "*401*" -or $errorMessage -like "*Bad credentials*" -or $errorMessage -like "*Unauthorized*") {
                Write-Host "`n" # New line after the "Fetching..." message
                Write-Warning "GitHub API token is invalid or expired. Proceeding without authentication."
                Write-Host "Tip: Update your GitHub token in the script or remove it to avoid this warning." -ForegroundColor 'Yellow'

                # Try without token
                try {
                    $latestRelease = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
                    Write-Host "Successfully fetched version without authentication." -ForegroundColor 'Green'
                }
                catch {
                    Write-Host "`nError: Failed to fetch Spicetify version from GitHub API." -ForegroundColor 'Red'
                    Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor 'Red'
                    throw
                }
            }
            elseif ($errorMessage -like "*403*" -or $errorMessage -like "*rate limit*") {
                Write-Host "`n" # New line after the "Fetching..." message
                Write-Warning "GitHub API rate limit exceeded with your token. Trying without authentication..."

                # Try without token
                try {
                    $latestRelease = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
                    Write-Host "Successfully fetched version without authentication." -ForegroundColor 'Green'
                }
                catch {
                    Write-Host "`nError: GitHub API rate limit exceeded and fallback failed." -ForegroundColor 'Red'
                    Write-Host "Please wait a moment and try again, or provide a valid GitHub API token." -ForegroundColor 'Yellow'
                    throw
                }
            }
            else {
                Write-Host "`n" # New line after the "Fetching..." message
                Write-Warning "Error with GitHub API token. Trying without authentication..."

                # Try without token
                try {
                    $latestRelease = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
                    Write-Host "Successfully fetched version without authentication." -ForegroundColor 'Green'
                }
                catch {
                    Write-Host "`nError: Failed to fetch Spicetify version." -ForegroundColor 'Red'
                    Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor 'Red'
                    throw
                }
            }
        }
    }
    else {
        # No token provided
        try {
            $latestRelease = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
            Write-Host " (no GitHub API token - may encounter rate limits)" -ForegroundColor 'Yellow'
        }
        catch {
            $errorMessage = $_.Exception.Message
            if ($errorMessage -like "*403*" -or $errorMessage -like "*rate limit*") {
                Write-Host "`n" # New line after the "Fetching..." message
                Write-Host "GitHub API rate limit exceeded. To avoid this, please add a GitHub API token to the script." -ForegroundColor 'Red'
                Write-Host "Instructions: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token" -ForegroundColor 'Yellow'
            }
            else {
                Write-Host "`nError: Failed to fetch Spicetify version from GitHub API." -ForegroundColor 'Red'
                Write-Host "Error details: $errorMessage" -ForegroundColor 'Red'
            }
            throw
        }
    }

    $targetVersion = $latestRelease.tag_name -replace 'v', ''
    if (-not $useToken) {
        Write-Success
    }

    $archivePath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "spicetify.zip")

    # Use GitHub token for download if available and working
    Write-Host "Downloading spicetify v$targetVersion..." -NoNewline
    try {
        if ($useToken) {
            $downloadHeaders = @{ "Authorization" = "Bearer $Global:githubToken" }
            Invoke-WebRequest -Uri "https://github.com/spicetify/cli/releases/download/v$targetVersion/spicetify-$targetVersion-windows-$architecture.zip" -UseBasicParsing -OutFile $archivePath -Headers $downloadHeaders -ErrorAction Stop
        }
        else {
            Invoke-WebRequest -Uri "https://github.com/spicetify/cli/releases/download/v$targetVersion/spicetify-$targetVersion-windows-$architecture.zip" -UseBasicParsing -OutFile $archivePath -ErrorAction Stop
        }
        Write-Success
    }
    catch {
        # If download with token fails, try without token
        if ($useToken) {
            Write-Host " (retrying without token)" -ForegroundColor 'Yellow'
            Invoke-WebRequest -Uri "https://github.com/spicetify/cli/releases/download/v$targetVersion/spicetify-$targetVersion-windows-$architecture.zip" -UseBasicParsing -OutFile $archivePath -ErrorAction Stop
            Write-Success
        }
        else {
            throw
        }
    }

    return $archivePath
}

function Move-OldSpicetifyFolder {
    $spicetifyOldFolderPath = "$HOME\spicetify-cli"
    $spicetifyFolderPath = "$env:LOCALAPPDATA\spicetify"

    if (Test-Path -Path $spicetifyOldFolderPath) {
        Write-Host 'Moving the old spicetify folder...' -NoNewline
        if (-not (Test-Path -Path $spicetifyFolderPath)) {
            New-Item -Path $spicetifyFolderPath -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path "$spicetifyOldFolderPath\*" -Destination $spicetifyFolderPath -Recurse -Force
        Remove-Item -Path $spicetifyOldFolderPath -Recurse -Force
        Write-Success
    }
}

function Install-Spicetify {
    try {
        if (Get-Command -Name 'spicetify' -ErrorAction SilentlyContinue) {
            Write-Host "Spicetify is already installed." -ForegroundColor 'Green'

            # Ask about marketplace installation
            $installMarketplace = Read-Host "Do you want to install Spicetify Marketplace? (y/n)"
            if ($installMarketplace -eq 'y' -or $installMarketplace -eq 'Y') {
                Install-Marketplace
            }
            return
        }

        Write-Host 'Installing Spicetify...' -ForegroundColor 'Cyan'
        $spicetifyFolderPath = "$env:LOCALAPPDATA\spicetify"

        # Move old folder if exists
        Move-OldSpicetifyFolder

        # Get and install Spicetify
        $archivePath = Get-Spicetify
        Write-Host 'Extracting spicetify...' -NoNewline
        Expand-Archive -Path $archivePath -DestinationPath $spicetifyFolderPath -Force -ErrorAction Stop
        Write-Success
        Add-SpicetifyToPath $spicetifyFolderPath
        Remove-Item -Path $archivePath -Force -ErrorAction SilentlyContinue

        # GitHub token is managed internally by this script only
        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            Write-Host "GitHub API token is configured in this script." -ForegroundColor 'Green'
            Write-Host "This will help avoid rate limits when downloading from GitHub." -ForegroundColor 'Cyan'
        }
        else {
            Write-Host "No GitHub API token provided. Downloads may encounter rate limits." -ForegroundColor 'Yellow'
            Write-Host "To add a token, update the \$Global:githubToken variable at the top of this script." -ForegroundColor 'Gray'
        }

        Write-Host 'Spicetify was successfully installed!' -ForegroundColor 'Green'
        Write-Host "`nRun" -NoNewline
        Write-Host ' spicetify -h ' -NoNewline -ForegroundColor 'Cyan'
        Write-Host 'to get started'

        # Ask about marketplace installation
        $installMarketplace = Read-Host "`nDo you also want to install Spicetify Marketplace? It will become available within the Spotify client, where you can easily install themes and extensions. (y/n)"
        if ($installMarketplace -eq 'y' -or $installMarketplace -eq 'Y') {
            Install-Marketplace
        } else {
            Write-Host 'Spicetify Marketplace installation skipped' -ForegroundColor 'Yellow'
        }
    }
    catch {
        Write-Error-Message $_.Exception.Message
    }
}

function Install-Marketplace {
    try {
        Write-Host 'Setting up Spicetify Marketplace...' -ForegroundColor 'Cyan'

        # GitHub token is managed internally by this script to avoid API rate limits
        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            Write-Host 'GitHub API token is available - will use for downloads to avoid rate limits.' -ForegroundColor 'Cyan'
        } else {
            Write-Host 'No GitHub API token - downloads may encounter rate limits.' -ForegroundColor 'Yellow'
        }

        # Get Spicetify userdata path
        Write-Host "Getting Spicetify userdata path..." -ForegroundColor 'Cyan'
        $result = Invoke-SpicetifyWithOutput "path" "userdata"
        if ([string]::IsNullOrWhiteSpace($result) -or $result.Contains("error")) {
            Write-Host "Error: Failed to get Spicetify path. Details:" -ForegroundColor 'Red'
            Write-Host $result -ForegroundColor 'Red'
            Write-Host "Make sure Spicetify is properly installed and try again." -ForegroundColor 'Yellow'
            return
        }
        $spiceUserDataPath = $result.Trim()

        if (-not (Test-Path -Path $spiceUserDataPath -PathType 'Container')) {
            $spiceUserDataPath = "$env:APPDATA\spicetify"
        }

        $marketAppPath = "$spiceUserDataPath\CustomApps\marketplace"
        $marketThemePath = "$spiceUserDataPath\Themes\marketplace"

        # Check if theme is installed
        Write-Host "Checking current theme configuration..." -ForegroundColor 'Cyan'
        $isThemeInstalled = $false
        try {
            $themeCheck = Invoke-SpicetifyWithOutput "path" "-s"
            $isThemeInstalled = (-not [string]::IsNullOrWhiteSpace($themeCheck) -and -not $themeCheck.Contains("error"))
        } catch {
            $isThemeInstalled = $false
        }

        $currentTheme = ""
        try {
            $themeResult = Invoke-SpicetifyWithOutput "config" "current_theme"
            if (-not [string]::IsNullOrWhiteSpace($themeResult) -and -not $themeResult.Contains("error")) {
                $currentTheme = $themeResult.Split('=')[-1].Trim()
            }
        } catch {
            $currentTheme = ""
        }

        $setTheme = $true

        Write-Host 'Removing and creating Marketplace folders...' -ForegroundColor 'Cyan'
        try {
            # Remove existing directories if they exist
            if (Test-Path $marketAppPath) {
                Remove-Item -Path $marketAppPath -Recurse -Force -ErrorAction 'Stop'
            }
            if (Test-Path $marketThemePath) {
                Remove-Item -Path $marketThemePath -Recurse -Force -ErrorAction 'Stop'
            }

            # Create new directories
            New-Item -Path $marketAppPath -ItemType 'Directory' -Force -ErrorAction 'Stop' | Out-Null
            New-Item -Path $marketThemePath -ItemType 'Directory' -Force -ErrorAction 'Stop' | Out-Null
            Write-Host "Marketplace directories created successfully." -ForegroundColor 'Green'
        }
        catch {
            Write-Host "Error: Failed to create Marketplace directories. $($_.Exception.Message)" -ForegroundColor 'Red'
            return
        }

        Write-Host 'Downloading Marketplace...' -ForegroundColor 'Cyan'
        $marketArchivePath = "$marketAppPath\marketplace.zip"
        $unpackedFolderPath = "$marketAppPath\marketplace-dist"

        try {
            # Try downloading with GitHub token if available
            if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
                try {
                    $downloadHeaders = @{ "Authorization" = "Bearer $Global:githubToken" }
                    Invoke-WebRequest -Uri 'https://github.com/spicetify/marketplace/releases/latest/download/marketplace.zip' -UseBasicParsing -OutFile $marketArchivePath -Headers $downloadHeaders -ErrorAction Stop
                    Write-Host "Marketplace downloaded successfully (using GitHub token)." -ForegroundColor 'Green'
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -like "*401*" -or $errorMessage -like "*Bad credentials*") {
                        Write-Warning "GitHub token invalid for download. Trying without authentication..."
                        Invoke-WebRequest -Uri 'https://github.com/spicetify/marketplace/releases/latest/download/marketplace.zip' -UseBasicParsing -OutFile $marketArchivePath -ErrorAction Stop
                        Write-Host "Marketplace downloaded successfully (without authentication)." -ForegroundColor 'Green'
                    }
                    else {
                        throw
                    }
                }
            }
            else {
                Invoke-WebRequest -Uri 'https://github.com/spicetify/marketplace/releases/latest/download/marketplace.zip' -UseBasicParsing -OutFile $marketArchivePath -ErrorAction Stop
                Write-Host "Marketplace downloaded successfully (no GitHub token)." -ForegroundColor 'Green'
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            if ($errorMessage -like "*403*" -or $errorMessage -like "*rate limit*") {
                Write-Host "Error: GitHub download rate limit exceeded." -ForegroundColor 'Red'
                Write-Host "Please add a valid GitHub API token to avoid rate limits." -ForegroundColor 'Yellow'
            }
            else {
                Write-Host "Error downloading Marketplace: $errorMessage" -ForegroundColor 'Red'
            }
            return
        }

        Write-Host 'Unzipping and installing...' -ForegroundColor 'Cyan'
        try {
            Expand-Archive -Path $marketArchivePath -DestinationPath $marketAppPath -Force -ErrorAction Stop

            if (Test-Path $unpackedFolderPath) {
                Get-ChildItem -Path $unpackedFolderPath | Move-Item -Destination $marketAppPath -Force -ErrorAction Stop
                Remove-Item -Path $unpackedFolderPath -Force -ErrorAction Stop
            }

            Remove-Item -Path $marketArchivePath -Force -ErrorAction Stop
            Write-Host "Marketplace files extracted and organized successfully." -ForegroundColor 'Green'
        }
        catch {
            Write-Host "Error extracting Marketplace: $($_.Exception.Message)" -ForegroundColor 'Red'
            return
        }

        Write-Host 'Configuring Spicetify for Marketplace...' -ForegroundColor 'Cyan'
        try {
            # Remove any old marketplace app configuration
            Invoke-Spicetify "config" "custom_apps" "spicetify-marketplace-" "-q" | Out-Null

            # Add marketplace to custom apps
            Invoke-Spicetify "config" "custom_apps" "marketplace" | Out-Null

            # Enable required settings
            Invoke-Spicetify "config" "inject_css" "1" "replace_colors" "1" | Out-Null

            Write-Host "Spicetify configuration updated successfully." -ForegroundColor 'Green'
        }
        catch {
            Write-Host "Error configuring Spicetify: $($_.Exception.Message)" -ForegroundColor 'Red'
            return
        }

        Write-Host 'Downloading placeholder theme...' -ForegroundColor 'Cyan'
        try {
            # Try downloading with GitHub token if available
            if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
                try {
                    $downloadHeaders = @{ "Authorization" = "Bearer $Global:githubToken" }
                    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/spicetify/marketplace/main/resources/color.ini' -UseBasicParsing -OutFile "$marketThemePath\color.ini" -Headers $downloadHeaders -ErrorAction Stop
                    Write-Host "Placeholder theme downloaded successfully (using GitHub token)." -ForegroundColor 'Green'
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    if ($errorMessage -like "*401*" -or $errorMessage -like "*Bad credentials*") {
                        Write-Warning "GitHub token invalid for theme download. Trying without authentication..."
                        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/spicetify/marketplace/main/resources/color.ini' -UseBasicParsing -OutFile "$marketThemePath\color.ini" -ErrorAction Stop
                        Write-Host "Placeholder theme downloaded successfully (without authentication)." -ForegroundColor 'Green'
                    }
                    else {
                        throw
                    }
                }
            }
            else {
                Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/spicetify/marketplace/main/resources/color.ini' -UseBasicParsing -OutFile "$marketThemePath\color.ini" -ErrorAction Stop
                Write-Host "Placeholder theme downloaded successfully (no GitHub token)." -ForegroundColor 'Green'
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            if ($errorMessage -like "*403*" -or $errorMessage -like "*rate limit*") {
                Write-Host "Error: GitHub download rate limit exceeded for theme." -ForegroundColor 'Red'
                Write-Host "Please add a valid GitHub API token to avoid rate limits." -ForegroundColor 'Yellow'
            }
            else {
                Write-Host "Error downloading placeholder theme: $errorMessage" -ForegroundColor 'Red'
            }
            return
        }

        Write-Host 'Applying Marketplace configuration...' -ForegroundColor 'Cyan'
        try {
            if ($isThemeInstalled -and ($currentTheme -ne 'marketplace')) {
                $response = Read-Host 'Local theme found. Do you want to replace it with a placeholder to install themes from the Marketplace? (y/n)'
                if ($response -eq 'n' -or $response -eq 'N') {
                    $setTheme = $false
                    Write-Host "Keeping current theme: $currentTheme" -ForegroundColor 'Yellow'
                }
            }

            if ($setTheme) {
                Write-Host "Setting marketplace as current theme..." -ForegroundColor 'Cyan'
                Invoke-Spicetify "config" "current_theme" "marketplace" | Out-Null
            }

            Invoke-SafeSpicetifyBackup | Out-Null
            Invoke-SafeSpicetifyApply | Out-Null

            Write-Host 'Spicetify Marketplace installed successfully! 🎉' -ForegroundColor 'Green'
            Write-Host 'Open Spotify and look for the "Marketplace" icon in the top bar.' -ForegroundColor 'Cyan'
            Write-Host 'If you don''t see it, try restarting Spotify.' -ForegroundColor 'Yellow'
        }
        catch {
            Write-Host "Error applying Marketplace configuration: $($_.Exception.Message)" -ForegroundColor 'Red'
            Write-Host "You may need to run backup and apply operations manually from the Settings menu." -ForegroundColor 'Yellow'
        }
    }
    catch {
        Write-Error-Message $_.Exception.Message
    }
}

function Remove-Spicetify {
    try {
        if (-not (Get-Command -Name 'spicetify' -ErrorAction SilentlyContinue)) {
            Write-Warning "Spicetify does not appear to be installed."
            return
        }
        Write-Host "Removing Spicetify..." -ForegroundColor 'Cyan'
        Write-Host "Step 1: Restoring Spotify to its original state..." -NoNewline
        Invoke-Spicetify "restore" | Out-Null
        Write-Success
        $spicetifyFolderPath = "$env:LOCALAPPDATA\spicetify"
        Write-Host "Step 2: Removing Spicetify files from '$spicetifyFolderPath'..." -NoNewline
        Remove-Item -Path $spicetifyFolderPath -Recurse -Force -ErrorAction Stop
        Write-Success
        Write-Host "Step 3: Cleaning Spicetify from your PATH environment variable..." -NoNewline
        $user = [EnvironmentVariableTarget]::User
        $currentPath = [Environment]::GetEnvironmentVariable('PATH', $user)
        $newPath = ($currentPath.Split(';') | Where-Object { $_ -notlike "*$spicetifyFolderPath*" }) -join ';'
        [Environment]::SetEnvironmentVariable('PATH', $newPath, $user)
        $env:PATH = $newPath
        Write-Success
        Write-Host "Spicetify has been completely removed." -ForegroundColor 'Green'
    }
    catch {
        Write-Error-Message $_.Exception.Message
    }
}

function Add-SpicetifyToPath {
    [CmdletBinding()]
    param (
        [string]$spicetifyFolderPath
    )
    begin {
        Write-Host -Object 'Making spicetify available in the PATH...' -NoNewline
        $user = [EnvironmentVariableTarget]::User
        $path = [Environment]::GetEnvironmentVariable('PATH', $user)
        $spicetifyOldFolderPath = "$HOME\spicetify-cli"
    }
    process {
        $path = $path -replace "$([regex]::Escape($spicetifyOldFolderPath))\\*;*", ''
        if ($path -notlike "*$spicetifyFolderPath*") {
            $path = "$path;$spicetifyFolderPath"
        }
    }
    end {
        [Environment]::SetEnvironmentVariable('PATH', $path, $user)
        $env:PATH = $path
        Write-Success
    }
}

function Invoke-Spicetify {
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )
    try {
        # Set GitHub token as environment variable for Spicetify CLI
        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $env:GITHUB_TOKEN = $Global:githubToken
        }
        
        # Check if this is a backup or apply command that might hit GitHub API
        $isBackupOrApply = $Arguments[0] -eq 'backup' -or $Arguments[0] -eq 'apply'
        
        if ($isBackupOrApply) {
            # Add quiet flag to reduce GitHub API calls
            $spicetifyArgs = @('--bypass-admin', '-q') + $Arguments
        } else {
            $spicetifyArgs = @('--bypass-admin') + $Arguments
        }
        
        $output = & spicetify $spicetifyArgs 2>&1

        if ($LASTEXITCODE -eq 0) {
            if ($output) {
                Write-Host $output -ForegroundColor 'Green'
            }
        } else {
            # Check if error is related to GitHub rate limit
            $outputString = $output | Out-String
            if ($outputString -like "*rate limit exceeded*" -and $isBackupOrApply) {
                Write-Host "GitHub rate limit detected, but operation may have succeeded partially." -ForegroundColor 'Yellow'
                Write-Host $output -ForegroundColor 'Yellow'
                # Return 0 if the operation actually succeeded despite rate limit warning
                if ($outputString -like "*success*" -or $outputString -like "*OK*") {
                    return 0
                }
            } else {
                Write-Host "Spicetify command failed with exit code $LASTEXITCODE" -ForegroundColor 'Red'
                if ($output) {
                    Write-Host $output -ForegroundColor 'Red'
                }
            }
        }

        return $LASTEXITCODE
    }
    catch {
        Write-Host "Error executing spicetify: $($_.Exception.Message)" -ForegroundColor 'Red'
        return 1
    }
}

function Invoke-SpicetifyWithOutput {
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )
    try {
        # Set GitHub token as environment variable for Spicetify CLI
        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $env:GITHUB_TOKEN = $Global:githubToken
        }
        
        $spicetifyArgs = @('--bypass-admin') + $Arguments
        $output = (& spicetify $spicetifyArgs 2>&1 | Out-String).Trim()
        return $output
    }
    catch {
        Write-Host "Error executing spicetify: $($_.Exception.Message)" -ForegroundColor 'Red'
        return ""
    }
}

function Invoke-SafeSpicetifyBackup {
    try {
        Write-Host "Creating Spotify backup..." -ForegroundColor 'Cyan'
        
        # Try with quiet flag first
        $result = Invoke-Spicetify "-q" "backup"
        
        if ($result -eq 0) {
            Write-Host "Backup completed successfully." -ForegroundColor 'Green'
            return $true
        }
        
        # If backup failed, check if there's already a backup
        $backupCheckOutput = Invoke-SpicetifyWithOutput "path" "all"
        if ($backupCheckOutput -like "*backup*") {
            Write-Host "Backup already exists, proceeding with existing backup." -ForegroundColor 'Yellow'
            return $true
        }
        
        Write-Host "Backup may have failed, but continuing anyway." -ForegroundColor 'Yellow'
        return $true
    }
    catch {
        Write-Host "Error during backup: $($_.Exception.Message)" -ForegroundColor 'Red'
        return $false
    }
}

function Invoke-SafeSpicetifyApply {
    try {
        Write-Host "Applying Spicetify customizations..." -ForegroundColor 'Cyan'
        
        # Try with quiet flag and no-restart to minimize API calls
        $result = Invoke-Spicetify "-q" "-n" "apply"
        
        if ($result -eq 0) {
            Write-Host "Apply completed successfully." -ForegroundColor 'Green'
            Write-Host "Restarting Spotify..." -ForegroundColor 'Cyan'
            Invoke-Spicetify "restart" | Out-Null
            return $true
        }
        
        # Check if the apply actually worked despite rate limit errors
        $configOutput = Invoke-SpicetifyWithOutput "config"
        if ($configOutput -like "*inject_css*1*" -and $configOutput -like "*replace_colors*1*") {
            Write-Host "Apply operation completed despite GitHub rate limit warnings." -ForegroundColor 'Green'
            Write-Host "Restarting Spotify..." -ForegroundColor 'Cyan'
            Invoke-Spicetify "restart" | Out-Null
            return $true
        }
        
        Write-Host "Apply operation may have partially failed." -ForegroundColor 'Yellow'
        return $false
    }
    catch {
        Write-Host "Error during apply: $($_.Exception.Message)" -ForegroundColor 'Red'
        return $false
    }
}

function Show-MainMenu {
    Clear-Host
    Write-Host "+==============================================================+" -ForegroundColor 'Cyan'
    Write-Host "|        Welcome to the All-in-One Spicetify Manager           |" -ForegroundColor 'White'
    Write-Host "|     This script helps you install and manage Spotify         |" -ForegroundColor 'Gray'
    Write-Host "|             and the Spicetify customization tool.            |" -ForegroundColor 'Gray'
    Write-Host "+==============================================================+" -ForegroundColor 'Cyan'
    Write-Host "|                                                              |" -ForegroundColor 'Cyan'
    Write-Host "|  [1] Install Spotify                                         |" -ForegroundColor 'White'
    Write-Host "|  [2] Install Spicetify                                       |" -ForegroundColor 'White'
    Write-Host "|  [3] Install Spicetify Marketplace                           |" -ForegroundColor 'White'
    Write-Host "|  [4] Spicetify Settings & Actions                            |" -ForegroundColor 'White'
    Write-Host "|                                                              |" -ForegroundColor 'Cyan'
    Write-Host "|  [5] Remove Spotify                                          |" -ForegroundColor 'Yellow'
    Write-Host "|  [6] Remove Spicetify                                        |" -ForegroundColor 'Yellow'
    Write-Host "|                                                              |" -ForegroundColor 'Cyan'
    Write-Host "|  [7] Exit                                                    |" -ForegroundColor 'White'
    Write-Host "|                                                              |" -ForegroundColor 'Cyan'
    Write-Host "+==============================================================+" -ForegroundColor 'Cyan'
}

function Show-SettingsMenu {
    Clear-Host
    Write-Host "+==============================================================+" -ForegroundColor 'Magenta'
    Write-Host "|                  Spicetify Settings & Actions                |" -ForegroundColor 'White'
    Write-Host "+==============================================================+" -ForegroundColor 'Magenta'
    Write-Host "|   Core Actions:                                              |" -ForegroundColor 'Gray'
    Write-Host "|     [1] Backup & Apply Changes                               |" -ForegroundColor 'White'
    Write-Host "|     [2] Restore Spotify to Original                          |" -ForegroundColor 'White'
    Write-Host "|     [3] Force Refresh Theme/Extensions                       |" -ForegroundColor 'White'
    Write-Host "|     [4] Enable/Disable Spotify Developer Tools               |" -ForegroundColor 'White'
    Write-Host "|     [5] Block/Unblock Spotify Updates                        |" -ForegroundColor 'White'
    Write-Host "|                                                              |" -ForegroundColor 'Magenta'
    Write-Host "|   Configuration:                                             |" -ForegroundColor 'Gray'
    Write-Host "|     [6] Manage Toggles (CSS, Sentry, etc.)                   |" -ForegroundColor 'White'
    Write-Host "|     [7] Manage Text/Path Settings (Theme, etc.)              |" -ForegroundColor 'White'
    Write-Host "|     [8] Manage Spotify Launch Flags                          |" -ForegroundColor 'White'
    Write-Host "|     [9] GitHub API Token Settings                            |" -ForegroundColor 'White'
    Write-Host "|                                                              |" -ForegroundColor 'Magenta'
    Write-Host "|   Debug:                                                     |" -ForegroundColor 'Gray'
    Write-Host "|    [10] Show Raw Spicetify Config Output                     |" -ForegroundColor 'Yellow'
    Write-Host "|                                                              |" -ForegroundColor 'Magenta'
    Write-Host "|    [11] Back to Main Menu                                    |" -ForegroundColor 'White'
    Write-Host "+==============================================================+" -ForegroundColor 'Magenta'
}

function Manage-Toggles {
    while ($true) {
        try {
            Clear-Host
            Write-Host "--- Configuration Toggles (0 = Disabled, 1 = Enabled) ---" -ForegroundColor 'Yellow'
            $currentConfig = Invoke-SpicetifyWithOutput "config"
            $toggles = @("inject_css", "inject_theme_js", "replace_colors", "always_enable_devtools", "check_spicetify_update", "disable_sentry", "disable_ui_logging", "remove_rtl_rule", "expose_apis", "experimental_features", "home_config", "sidebar_config")

            $i = 1
            foreach ($toggle in $toggles) {
                $value = ($currentConfig -split '\r?\n' | Where-Object { $_ -match "^$toggle\s" }).Split(' ')[-1]
                $status = if ($value -eq '1') { "[ENABLED]" } else { "[DISABLED]" }
                Write-Host "[$i] Toggle '$toggle' " -NoNewline; Write-Host $status -ForegroundColor $(if ($value -eq '1') { 'Green' } else { 'Red' })
                $i++
            }
            $backOption = $i
            Write-Host "[$backOption] Back to Settings Menu"
            $choice = Read-Host -Prompt "Enter a number to toggle, or '$backOption' to go back"

            if ($choice -eq $backOption) { break }
            elseif ($choice -match '^\d+$' -and $choice -gt 0 -and $choice -lt $backOption) {
                $selectedIndex = [int]$choice - 1
                $selectedToggle = $toggles[$selectedIndex]
                $currentValue = ($currentConfig -split '\r?\n' | Where-Object { $_ -match "^$selectedToggle\s" }).Split(' ')[-1]
                $newValue = if ($currentValue -eq '1') { '0' } else { '1' }
                Invoke-Spicetify "config" "$selectedToggle" "$newValue" | Out-Null
                Write-Host "Toggled '$selectedToggle' to '$newValue'." -ForegroundColor 'Green'
                Start-Sleep -Seconds 1
            }
            else { Write-Warning "Invalid selection."; Press-EnterToContinue }
        }
        catch { Write-Error-Message $_.Exception.Message; Press-EnterToContinue }
    }
}

function Manage-TextSettings {
     while ($true) {
        try {
            Clear-Host
            Write-Host "--- Text & Path Settings ---" -ForegroundColor 'Yellow'
            $currentConfig = Invoke-SpicetifyWithOutput "config"
            $configLines = $currentConfig -split '\r?\n'
            $settings = @("current_theme", "color_scheme", "spotify_path", "prefs_path", "custom_apps", "extensions")

            $i = 1
            foreach ($setting in $settings) {
                $value = '' # Default to empty
                # Find the line that starts with the setting key
                $configLine = $configLines | Where-Object { $_.Trim().StartsWith($setting) } | Select-Object -First 1

                if ($configLine) {
                    # Regex-replace the key and subsequent whitespace to extract only the value.
                    # This handles both lines with and without values correctly.
                    $value = $configLine.Trim() -replace "^$([regex]::Escape($setting))\s*", ""
                }
                
                Write-Host "[$i] Edit '$setting': " -NoNewline; Write-Host $value -ForegroundColor 'Cyan'
                $i++
            }
            $backOption = $i
            Write-Host "[$backOption] Back to Settings Menu"
            $choice = Read-Host -Prompt "Enter a number to edit, or '$backOption' to go back"

            if ($choice -eq $backOption) { break }
            elseif ($choice -match '^\d+$' -and $choice -gt 0 -and $choice -lt $backOption) {
                $selectedSetting = $settings[[int]$choice - 1]
                $newValue = Read-Host -Prompt "Enter new value for '$selectedSetting'"
                Invoke-Spicetify "config" "$selectedSetting" "$newValue" | Out-Null
                Write-Host "Set '$selectedSetting' to '$newValue'." -ForegroundColor 'Green'
                Press-EnterToContinue
            }
            else { Write-Warning "Invalid selection."; Press-EnterToContinue }
        }
        catch { Write-Error-Message $_.Exception.Message; Press-EnterToContinue }
    }
}

function Manage-GitHubToken {
    try {
        Clear-Host
        Write-Host "--- GitHub API Token Configuration ---" -ForegroundColor 'Yellow'

        # Show current token status
        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $maskedToken = $Global:githubToken.Substring(0, 10) + "..." + $Global:githubToken.Substring($Global:githubToken.Length - 4)
            Write-Host "Current token: $maskedToken" -ForegroundColor 'Cyan'

            # Check current token validity
            try {
                $testUrl = 'https://api.github.com/user'
                $testHeaders = @{ "Authorization" = "Bearer $Global:githubToken" }
                $testResult = Invoke-RestMethod -Uri $testUrl -Headers $testHeaders -ErrorAction Stop
                Write-Host "Token status: Valid (authenticated as $($testResult.login))" -ForegroundColor 'Green'
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -like "*401*" -or $errorMessage -like "*Bad credentials*") {
                    Write-Host "Token status: Invalid or expired" -ForegroundColor 'Red'
                }
                elseif ($errorMessage -like "*403*" -or $errorMessage -like "*rate limit*") {
                    Write-Host "Token status: Rate limited (but appears valid)" -ForegroundColor 'Yellow'
                }
                else {
                    Write-Host "Token status: Unknown - $errorMessage" -ForegroundColor 'Gray'
                }
            }
        } else {
            Write-Host "Current token: Not set" -ForegroundColor 'Red'
        }

        Write-Host ""
        Write-Host "Options:" -ForegroundColor 'White'
        Write-Host "[1] Test current token"
        Write-Host "[2] Show GitHub token info"
        Write-Host "[3] Back to Settings Menu"

        $choice = Read-Host "Choose an option (1-3)"

        switch ($choice) {
            '1' {
                if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
                    Write-Host "Testing GitHub token..." -ForegroundColor 'Cyan'
                    try {
                        $testUrl = 'https://api.github.com/user'
                        $testHeaders = @{ "Authorization" = "Bearer $Global:githubToken" }
                        $testResult = Invoke-RestMethod -Uri $testUrl -Headers $testHeaders -ErrorAction Stop
                        Write-Host "Token is valid!" -ForegroundColor 'Green'
                        Write-Host "  Authenticated as: $($testResult.login)" -ForegroundColor 'Cyan'
                        Write-Host "  Account type: $($testResult.type)" -ForegroundColor 'Cyan'
                        if ($testResult.plan) {
                            Write-Host "  Plan: $($testResult.plan.name)" -ForegroundColor 'Cyan'
                        }
                    }
                    catch {
                        $errorMessage = $_.Exception.Message
                        Write-Host "Token test failed!" -ForegroundColor 'Red'
                        if ($errorMessage -like "*401*" -or $errorMessage -like "*Bad credentials*") {
                            Write-Host "  Reason: Invalid or expired token" -ForegroundColor 'Red'
                        }
                        elseif ($errorMessage -like "*403*" -or $errorMessage -like "*rate limit*") {
                            Write-Host "  Reason: Rate limited (token may still be valid)" -ForegroundColor 'Yellow'
                        }
                        else {
                            Write-Host "  Reason: $errorMessage" -ForegroundColor 'Red'
                        }
                    }
                } else {
                    Write-Warning "No GitHub token available to test."
                }
                Press-EnterToContinue
            }
            '2' {
                Write-Host "GitHub Token Information:" -ForegroundColor 'Cyan'
                Write-Host "To create a GitHub Personal Access Token:" -ForegroundColor 'White'
                Write-Host "1. Go to: https://github.com/settings/tokens" -ForegroundColor 'Gray'
                Write-Host "2. Click Generate new token (classic)" -ForegroundColor 'Gray'
                Write-Host "3. Give it a name (e.g., Spicetify Script)" -ForegroundColor 'Gray'
                Write-Host "4. Set expiration (optional, but recommended)" -ForegroundColor 'Gray'
                Write-Host "5. No scopes/permissions are required for public repos" -ForegroundColor 'Gray'
                Write-Host "6. Click Generate token and copy the token" -ForegroundColor 'Gray'
                Write-Host "7. Update line 4 of this script with your token" -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Current script token: " -NoNewline
                if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
                    $maskedToken = $Global:githubToken.Substring(0, 10) + "..." + $Global:githubToken.Substring($Global:githubToken.Length - 4)
                    Write-Host $maskedToken -ForegroundColor 'Cyan'
                } else {
                    Write-Host "Not set" -ForegroundColor 'Red'
                }
                Press-EnterToContinue
            }
            '3' {
                return
            }
            default {
                Write-Warning "Invalid choice."
                Press-EnterToContinue
            }
        }
    }
    catch {
        Write-Error-Message $_.Exception.Message
        Press-EnterToContinue
    }
}

function Manage-LaunchFlags {
    while ($true) {
        try {
            Clear-Host

            # Get current flags with better parsing
            $configOutput = Invoke-SpicetifyWithOutput "config" "spotify_launch_flags"
            $currentFlagsStr = ""
            $currentFlags = @()

            if ($configOutput) {
                # Try different parsing methods
                if ($configOutput.Contains(' = ')) {
                    $currentFlagsStr = $configOutput.Split(' = ')[-1].Trim()
                } elseif ($configOutput.Contains('=')) {
                    $currentFlagsStr = $configOutput.Split('=')[-1].Trim()
                } else {
                    # If no equals sign, check if the whole output is the value
                    $lines = $configOutput -split "`n"
                    foreach ($line in $lines) {
                        if ($line.Trim() -and -not $line.StartsWith('spotify_launch_flags')) {
                            $currentFlagsStr = $line.Trim()
                            break
                        }
                    }
                }

                # Parse flags
                if ($currentFlagsStr -and $currentFlagsStr -ne "" -and $currentFlagsStr -ne "spotify_launch_flags") {
                    $currentFlags = $currentFlagsStr.Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne "" }
                }
            }

            Write-Host "--- Spotify Launch Flags Management ---" -ForegroundColor 'Yellow'
            Write-Host "Current Flags: " -NoNewline
            if ($currentFlags.Count -gt 0) {
                Write-Host ($currentFlags -join ' | ') -ForegroundColor 'Cyan'
            } else {
                Write-Host "(No flags set)" -ForegroundColor 'Gray'
            }
            Write-Host "---------------------------------------"
            Write-Host "[1] Add a flag"
            Write-Host "[2] Remove a flag"
            Write-Host "[3] Clear all flags"
            Write-Host "[4] Debug: Show raw config output"
            Write-Host "[5] Back to Main Menu"
            $choice = Read-Host -Prompt "Choose an option"

            if ($choice -eq '5') { break }
            elseif ($choice -eq '4') {
                Write-Host "--- Debug Information ---" -ForegroundColor 'Yellow'
                Write-Host "Raw config output:" -ForegroundColor 'Cyan'
                Write-Host "===================" -ForegroundColor 'Gray'
                $debugOutput = Invoke-SpicetifyWithOutput "config" "spotify_launch_flags"
                Write-Host "[$debugOutput]" -ForegroundColor 'White'
                Write-Host "===================" -ForegroundColor 'Gray'
                Write-Host "Parsed currentFlagsStr: [$currentFlagsStr]" -ForegroundColor 'Cyan'
                Write-Host "Parsed currentFlags count: $($currentFlags.Count)" -ForegroundColor 'Cyan'
                if ($currentFlags.Count -gt 0) {
                    for ($i = 0; $i -lt $currentFlags.Count; $i++) {
                        Write-Host "  Flag $($i+1): [$($currentFlags[$i])]" -ForegroundColor 'Cyan'
                    }
                }
                Press-EnterToContinue
            }
            elseif ($choice -eq '1') {
                $availableFlags = @(
                    @{ Flag = "--allow-upgrades"; Description = "Allow Spotify automatic upgrades" },
                    @{ Flag = "--append-log-file"; Description = "Append to existing log file instead of overwriting" },
                    @{ Flag = "--app-directory=<path>"; Description = 'Specify Apps directory (for Microsoft Store version)' },
                    @{ Flag = "--cache-path=<path>"; Description = "Set custom cache directory path" },
                    @{ Flag = "--disable-crash-reporting"; Description = "Disable automatic crash reports to Spotify" },
                    @{ Flag = "--disable-update-restarts"; Description = "Prevent automatic restarts after updates" },
                    @{ Flag = "--minimized"; Description = 'Start Spotify with window minimized (Windows only)' },
                    @{ Flag = "--maximized"; Description = "Start Spotify with window maximized" },
                    @{ Flag = "--mu=<value>"; Description = 'Multiple instances with separate cache directories' },
                    @{ Flag = "--remote-debugging-port=<port>"; Description = "Enable remote debugging on specified port" },
                    @{ Flag = "--remote-allow-origins=<url>"; Description = "Allow remote debugging from specific URL" },
                    @{ Flag = "--show-console"; Description = "Show detailed console log output" },
                    @{ Flag = "--log-file=<path>"; Description = 'Save log output to specified file (.log extension)' },
                    @{ Flag = "--update-endpoint-override=<url>"; Description = 'Override update server (use localhost to disable)' },
                    @{ Flag = "--trace-file=<path>"; Description = "Save performance trace to specified file" },
                    @{ Flag = "--uri=<uri>"; Description = "Auto-navigate to URI when Spotify starts" },
                    @{ Flag = "--username=<username>"; Description = 'Auto-login username (deprecated, does not work anymore)' },
                    @{ Flag = "--password=<password>"; Description = 'Auto-login password (deprecated, does not work anymore)' },
                    @{ Flag = "--enable-chrome-runtime"; Description = 'Switch to Chrome runtime (for older Spotify versions)' },
                    @{ Flag = "--disable-cef-views"; Description = "Disable CEF views rendering system" },
                    @{ Flag = "--enable-cef-views"; Description = "Enable CEF views rendering system" }
                )

                Write-Host "--- Available Flags to Add ---" -ForegroundColor 'Yellow'
                for ($j = 0; $j -lt $availableFlags.Length; $j++) {
                    Write-Host "[$($j+1)] $($availableFlags[$j].Flag)" -NoNewline -ForegroundColor 'Cyan'
                    Write-Host " - $($availableFlags[$j].Description)" -ForegroundColor 'Gray'
                }
                $backOption = $availableFlags.Length + 1
                Write-Host "[$backOption] Back to Launch Flags Menu" -ForegroundColor 'Yellow'

                $flagChoice = Read-Host -Prompt "Enter number of the flag to add (1-$($availableFlags.Length)) or $backOption to go back"

                if ($flagChoice -eq $backOption) {
                    continue  # Go back to launch flags menu
                }
                elseif ($flagChoice -match '^\d+$' -and $flagChoice -gt 0 -and $flagChoice -le $availableFlags.Length) {
                    $selectedFlagObj = $availableFlags[[int]$flagChoice - 1]
                    $newFlag = $selectedFlagObj.Flag

                    if ($newFlag -like "*=<*") {
                        $flagName = $newFlag.Split('=')[0]
                        $placeholder = $newFlag.Split('=')[1]
                        $value = Read-Host -Prompt "This flag requires a value. Enter value for '$flagName' $placeholder"
                        $newFlag = $flagName + "=" + $value
                    }

                    # Check if flag already exists
                    $flagExists = $false
                    $flagBase = $newFlag.Split('=')[0]
                    foreach ($existingFlag in $currentFlags) {
                        if ($existingFlag.StartsWith($flagBase)) {
                            $flagExists = $true
                            break
                        }
                    }

                    if ($flagExists) {
                        Write-Warning "Flag '$flagBase' already exists in the configuration."
                        Write-Host "Description: $($selectedFlagObj.Description)" -ForegroundColor 'Gray'
                        Press-EnterToContinue
                    } else {
                        $currentFlags += $newFlag
                        $newFlagsStr = $currentFlags -join '|'
                        Invoke-Spicetify "config" "spotify_launch_flags" "$newFlagsStr" | Out-Null
                        Write-Host "Flag '$newFlag' added successfully!" -ForegroundColor 'Green'
                        Write-Host "Description: $($selectedFlagObj.Description)" -ForegroundColor 'Gray'
                        Start-Sleep -Seconds 2  # Give user time to read the message
                        continue  # Refresh the menu to show the new flag
                    }
                } else {
                    Write-Warning "Invalid selection. Please enter a number between 1 and $($availableFlags.Length) or $backOption to go back."
                    Press-EnterToContinue
                }
            }
            elseif ($choice -eq '2') {
                if ($currentFlags.Count -eq 0) {
                    Write-Warning "No flags to remove."
                    Press-EnterToContinue
                    continue
                }
                Write-Host "--- Current Flags to Remove ---" -ForegroundColor 'Yellow'
                for ($j = 0; $j -lt $currentFlags.Count; $j++) {
                    Write-Host "[$($j+1)] $($currentFlags[$j])" -ForegroundColor 'Cyan'
                }
                $backOption = $currentFlags.Count + 1
                Write-Host "[$backOption] Back to Launch Flags Menu" -ForegroundColor 'Yellow'

                $flagChoice = Read-Host -Prompt "Enter number of the flag to remove (1-$($currentFlags.Count)) or $backOption to go back"

                if ($flagChoice -eq $backOption) {
                    continue  # Go back to launch flags menu
                }
                elseif ($flagChoice -match '^\d+$' -and $flagChoice -gt 0 -and $flagChoice -le $currentFlags.Count) {
                    $removedFlag = $currentFlags[[int]$flagChoice - 1]
                    $updatedFlags = @()
                    for ($j = 0; $j -lt $currentFlags.Count; $j++) {
                        if ($j -ne [int]$flagChoice - 1) {
                            $updatedFlags += $currentFlags[$j]
                        }
                    }
                    $newFlagsStr = $updatedFlags -join '|'
                    Invoke-Spicetify "config" "spotify_launch_flags" "$newFlagsStr" | Out-Null
                    Write-Host "Flag '$removedFlag' removed successfully!" -ForegroundColor 'Green'
                    Start-Sleep -Seconds 2  # Give user time to read the message
                    continue  # Refresh the menu to show updated flags
                } else {
                    Write-Warning "Invalid selection. Please enter a number between 1 and $($currentFlags.Count) or $backOption to go back."
                    Press-EnterToContinue
                }
            }
            elseif ($choice -eq '3') {
                if ($currentFlags.Count -eq 0) {
                    Write-Warning "No flags to clear."
                    Press-EnterToContinue
                    continue
                }

                $confirmation = Read-Host "Are you sure you want to clear ALL launch flags? This will remove $($currentFlags.Count) flag(s). (y/n)"
                if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
                    Invoke-Spicetify "config" "spotify_launch_flags" "" | Out-Null
                    Write-Host "All launch flags have been cleared successfully!" -ForegroundColor 'Green'
                    Start-Sleep -Seconds 2  # Give user time to read the message
                    continue  # Refresh the menu to show empty flags
                } else {
                    Write-Host "Clear operation cancelled." -ForegroundColor 'Yellow'
                    Press-EnterToContinue
                }
            }
            else { Write-Warning "Invalid selection."; Press-EnterToContinue }
        }
        catch { Write-Error-Message $_.Exception.Message; Press-EnterToContinue }
    }
}

if (-not (Test-PowerShellVersion)) {
    Pause; exit
}

# Configure GitHub token as environment variable if available
if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
    $env:GITHUB_TOKEN = $Global:githubToken
}

# Check GitHub token status (optional - script will work without it)
Test-GitHubToken | Out-Null
Write-Host ""  # Add spacing before main menu

while ($true) {
    Show-MainMenu
    $mainChoice = Read-Host -Prompt "Please enter your choice [1-7]"

    if (($mainChoice -eq '3' -or $mainChoice -eq '4') -and -not (Get-Command -Name 'spicetify' -ErrorAction SilentlyContinue)) {
        Write-Warning "Spicetify is not installed. Please install it first (Option 2)."
        Press-EnterToContinue
        continue
    }

    try {
        switch ($mainChoice) {
            '1' { Install-Spotify; Press-EnterToContinue }
            '2' { Install-Spicetify; Press-EnterToContinue }
            '3' { Install-Marketplace; Press-EnterToContinue }
            '4' {
                while ($true) {
                    Show-SettingsMenu
                    $settingsChoice = Read-Host -Prompt "Choose an action [1-11]"

                    if ($settingsChoice -eq '11') { break }
                    elseif ($settingsChoice -eq '1') {
                        if (Invoke-SafeSpicetifyBackup) {
                            if (Invoke-SafeSpicetifyApply) {
                                Write-Host "Backup and apply completed successfully!" -ForegroundColor 'Green'
                            } else {
                                Write-Host "Backup completed but apply may have issues." -ForegroundColor 'Yellow'
                            }
                        } else {
                            Write-Host "Backup failed - skipping apply." -ForegroundColor 'Red'
                        }
                        Press-EnterToContinue
                    }
                    elseif ($settingsChoice -eq '2') {
                        Write-Host "Restoring Spotify to original state..." -ForegroundColor 'Cyan'
                        Invoke-Spicetify "restore"
                        Write-Host "Restore completed!" -ForegroundColor 'Green'
                        Press-EnterToContinue
                    }
                    elseif ($settingsChoice -eq '3') {
                        Write-Host "Refreshing theme and extensions..." -ForegroundColor 'Cyan'
                        Invoke-Spicetify "refresh" "-e"
                        Write-Host "Refresh completed!" -ForegroundColor 'Green'
                        Press-EnterToContinue
                    }
                    elseif ($settingsChoice -eq '4') {
                        Write-Host "Enabling developer tools..." -ForegroundColor 'Cyan'
                        Invoke-Spicetify "enable-devtools"
                        Write-Host "Developer tools enabled! Press Ctrl + Shift + I in Spotify to use." -ForegroundColor 'Green'
                        Press-EnterToContinue
                    }
                    elseif ($settingsChoice -eq '5') {
                        $action = Read-Host "Do you want to 'block' or 'unblock' Spotify updates?"
                        if ($action -in @('block', 'unblock')) {
                            Write-Host "Executing spotify-updates $action..." -ForegroundColor 'Cyan'
                            Invoke-Spicetify "spotify-updates" $action
                            Write-Host "Spotify updates $action completed!" -ForegroundColor 'Green'
                            Press-EnterToContinue
                        } else {
                            Write-Warning "Invalid input. Please enter 'block' or 'unblock'."
                            Press-EnterToContinue
                        }
                    }
                    elseif ($settingsChoice -eq '6') {
                        try {
                            Manage-Toggles
                        } catch {
                            Write-Error-Message $_.Exception.Message
                            Press-EnterToContinue
                        }
                    }
                    elseif ($settingsChoice -eq '7') {
                        try {
                            Manage-TextSettings
                        } catch {
                            Write-Error-Message $_.Exception.Message
                            Press-EnterToContinue
                        }
                    }
                    elseif ($settingsChoice -eq '8') {
                        try {
                            Manage-LaunchFlags
                        } catch {
                            Write-Error-Message $_.Exception.Message
                            Press-EnterToContinue
                        }
                    }
                    elseif ($settingsChoice -eq '9') {
                        try {
                            Manage-GitHubToken
                        } catch {
                            Write-Error-Message $_.Exception.Message
                            Press-EnterToContinue
                        }
                    }
                    elseif ($settingsChoice -eq '10') {
                        Write-Host "--- Raw 'spicetify config' output ---" -ForegroundColor 'Yellow'
                        $rawConfig = Invoke-SpicetifyWithOutput "config"
                        Write-Host "====================================="
                        Write-Host $rawConfig
                        Write-Host "====================================="
                        Write-Host "--- End of raw output ---" -ForegroundColor 'Yellow'
                        Press-EnterToContinue
                    }
                    else {
                        Write-Warning "Invalid choice. Please enter a number between 1-11."
                        Press-EnterToContinue
                    }
                }
            }
            '5' { Remove-Spotify; Press-EnterToContinue }
            '6' { Remove-Spicetify; Press-EnterToContinue }
            '7' { Write-Host "Exiting. Goodbye!" -ForegroundColor 'Green'; exit }
            default { Write-Warning "Invalid choice."; Press-EnterToContinue }
        }
    }
    catch {
        Write-Error-Message $_.Exception.Message
        Press-EnterToContinue
    }
}