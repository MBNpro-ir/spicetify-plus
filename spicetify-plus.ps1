# We set this to 'SilentlyContinue' globally and handle errors manually in each function.
$ErrorActionPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Global:githubToken = ""

# Global variable to track if changes have been applied in current session
$Global:changesApplied = $false

# Function to get user-specific config directory
function Get-SpicetifyPlusConfigPath {
    $userName = $env:USERNAME
    $configDir = "$env:USERPROFILE\users\$userName\spicetify plus"
    if (-not (Test-Path -Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }
    return $configDir
}

# Function to get GitHub token file path
function Get-GitHubTokenFilePath {
    $configDir = Get-SpicetifyPlusConfigPath
    return "$configDir\github_token.txt"
}

# Function to save GitHub token to file
function Save-GitHubToken {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }

    try {
        $tokenFilePath = Get-GitHubTokenFilePath
        $Token | Out-File -FilePath $tokenFilePath -Encoding UTF8 -Force

        # Also set the environment variable immediately
        $env:GITHUB_TOKEN = $Token

        return $true
    }
    catch {
        Write-Host "Error saving GitHub token: $($_.Exception.Message)" -ForegroundColor 'Red'
        return $false
    }
}

# Function to load GitHub token from file
function Load-GitHubToken {
    try {
        $tokenFilePath = Get-GitHubTokenFilePath
        if (Test-Path -Path $tokenFilePath) {
            $token = Get-Content -Path $tokenFilePath -Raw -Encoding UTF8
            if ($token) {
                $token = $token.Trim()
                # Set environment variable when loading token
                if (-not [string]::IsNullOrWhiteSpace($token)) {
                    $env:GITHUB_TOKEN = $token
                }
                return $token
            }
        }
        return ""
    }
    catch {
        Write-Host "Error loading GitHub token: $($_.Exception.Message)" -ForegroundColor 'Red'
        return ""
    }
}

# Function to validate GitHub token
function Test-GitHubTokenValidity {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return @{ IsValid = $false; Message = "Token is empty" }
    }

    try {
        $testUrl = 'https://api.github.com/user'
        $testHeaders = @{
            "Authorization" = "Bearer $Token"
            "User-Agent" = "Spicetify-Plus/1.0"
        }

        # Add timeout to prevent hanging
        $testResult = Invoke-RestMethod -Uri $testUrl -Headers $testHeaders -TimeoutSec 30 -ErrorAction Stop
        return @{
            IsValid = $true;
            Message = "Valid token for user: $($testResult.login)";
            UserInfo = $testResult
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Host "Debug: Error details - $errorMessage" -ForegroundColor 'Gray'

        if ($errorMessage -like "*401*" -or $errorMessage -like "*Bad credentials*" -or $errorMessage -like "*Unauthorized*") {
            return @{ IsValid = $false; Message = "Invalid or expired token" }
        }
        elseif ($errorMessage -like "*403*" -or $errorMessage -like "*rate limit*") {
            return @{ IsValid = $true; Message = "Rate limited but token appears valid" }
        }
        elseif ($errorMessage -like "*timeout*" -or $errorMessage -like "*timed out*") {
            return @{ IsValid = $false; Message = "Connection timeout - please check your internet connection" }
        }
        else {
            return @{ IsValid = $false; Message = "Network error: $errorMessage" }
        }
    }
}

# Function to update GitHub token environment variable
function Update-GitHubTokenEnvironment {
    if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
        $env:GITHUB_TOKEN = $Global:githubToken
    } else {
        # Clear environment variable if no token
        $env:GITHUB_TOKEN = $null
    }
}

# Load GitHub token on script start
$Global:githubToken = Load-GitHubToken

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
        Write-Host "   To set a token, go to Settings > GitHub API Token Settings." -ForegroundColor 'Gray'
        return $false
    }

    # Ensure environment variable is set
    Update-GitHubTokenEnvironment

    $validation = Test-GitHubTokenValidity -Token $Global:githubToken

    if ($validation.IsValid) {
        Write-Host " > VALID" -ForegroundColor 'Green'
        if ($validation.UserInfo) {
            Write-Host "   GitHub API authenticated as: $($validation.UserInfo.login)" -ForegroundColor 'Gray'
        }
        Write-Host "   Environment variable GITHUB_TOKEN is configured for Spicetify CLI" -ForegroundColor 'Gray'
        return $true
    } else {
        if ($validation.Message -like "*Rate limited*") {
            Write-Host " > RATE LIMITED" -ForegroundColor 'Yellow'
            Write-Host "   GitHub API rate limit reached, but token appears to be valid." -ForegroundColor 'Gray'
            Write-Host "   Environment variable GITHUB_TOKEN is configured for Spicetify CLI" -ForegroundColor 'Gray'
            return $true
        } else {
            Write-Host " > INVALID" -ForegroundColor 'Red'
            Write-Host "   $($validation.Message)" -ForegroundColor 'Gray'
            Write-Host "   Use Settings > GitHub API Token Settings to update your token." -ForegroundColor 'Gray'
            return $false
        }
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

function Update-Spotify {
    try {
        Write-Host "Checking for Spotify updates..." -ForegroundColor 'Cyan'

        # Check if Spotify is installed
        $spotifyExeInstalled = $false
        $regPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')
        foreach ($path in $regPaths) {
            if (Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Spotify*' }) {
                $spotifyExeInstalled = $true
                break
            }
        }
        $spotifyUwpInstalled = Get-AppxPackage -Name "*SpotifyMusic*" -ErrorAction SilentlyContinue

        if (-not ($spotifyExeInstalled -or $spotifyUwpInstalled)) {
            Write-Warning "Spotify is not installed. Use option [1] to install Spotify first."
            return
        }

        if ($spotifyUwpInstalled) {
            Write-Host "Spotify (Microsoft Store version) updates automatically." -ForegroundColor 'Green'
            Write-Host "No manual update required." -ForegroundColor 'Cyan'
            return
        }

        # For desktop version, Spotify updates itself automatically
        # We can force a reinstall to get the latest version
        Write-Host "Spotify desktop version updates automatically when you restart the app." -ForegroundColor 'Green'
        Write-Host "To force update, you can:" -ForegroundColor 'Cyan'
        Write-Host "1. Close Spotify completely" -ForegroundColor 'Gray'
        Write-Host "2. Restart Spotify - it will check for updates automatically" -ForegroundColor 'Gray'
        Write-Host "3. Or use option [3] to remove and then [1] to reinstall with latest version" -ForegroundColor 'Gray'
    }
    catch {
        Write-Error-Message $_.Exception.Message
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
            Write-Host "Use option [5] to install Spicetify Marketplace or [6] to update Spicetify." -ForegroundColor 'Cyan'
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
        Write-Host "`nTo install Spicetify Marketplace, use option [5] from the main menu." -ForegroundColor 'Cyan'
    }
    catch {
        Write-Error-Message $_.Exception.Message
    }
}

function Update-Spicetify {
    try {
        if (-not (Get-Command -Name 'spicetify' -ErrorAction SilentlyContinue)) {
            Write-Warning "Spicetify is not installed. Use option [4] to install Spicetify first."
            return
        }

        Write-Host "Checking for Spicetify updates..." -ForegroundColor 'Cyan'

        # Get current version
        $currentVersionOutput = Invoke-SpicetifyWithOutput "version"
        $currentVersion = ""
        if ($currentVersionOutput -match "spicetify version (\d+\.\d+\.\d+)") {
            $currentVersion = $matches[1]
            Write-Host "Current Spicetify version: v$currentVersion" -ForegroundColor 'Gray'
        } else {
            Write-Host "Could not determine current Spicetify version." -ForegroundColor 'Yellow'
        }

        # Get latest version from GitHub
        Write-Host "Fetching latest Spicetify version..." -NoNewline
        $latestVersion = ""
        try {
            if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
                $headers = @{ "Authorization" = "Bearer $Global:githubToken" }
                $latestRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/spicetify/cli/releases/latest' -Headers $headers -ErrorAction Stop
            } else {
                $latestRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/spicetify/cli/releases/latest' -ErrorAction Stop
            }
            $latestVersion = $latestRelease.tag_name -replace 'v', ''
            Write-Success
            Write-Host "Latest Spicetify version: v$latestVersion" -ForegroundColor 'Gray'
        }
        catch {
            Write-Host " > FAILED" -ForegroundColor 'Red'
            Write-Warning "Could not fetch latest version from GitHub. Error: $($_.Exception.Message)"
            return
        }

        # Compare versions
        if ($currentVersion -eq $latestVersion) {
            Write-Host "Spicetify is already up to date! (v$currentVersion)" -ForegroundColor 'Green'
            return
        }

        if ([string]::IsNullOrWhiteSpace($currentVersion)) {
            Write-Host "Unable to compare versions. Proceeding with update..." -ForegroundColor 'Yellow'
        } else {
            Write-Host "Update available: v$currentVersion -> v$latestVersion" -ForegroundColor 'Cyan'
        }

        # Perform update
        Write-Host "Updating Spicetify..." -ForegroundColor 'Cyan'
        $spicetifyFolderPath = "$env:LOCALAPPDATA\spicetify"

        # Backup current config if exists
        $configBackupPath = "$env:TEMP\spicetify_config_backup.ini"
        $configPath = "$env:APPDATA\spicetify\config-xpui.ini"
        if (Test-Path $configPath) {
            Write-Host "Backing up current configuration..." -NoNewline
            Copy-Item -Path $configPath -Destination $configBackupPath -Force -ErrorAction SilentlyContinue
            Write-Success
        }

        # Download and install latest version
        $archivePath = Get-Spicetify
        Write-Host 'Extracting updated spicetify...' -NoNewline
        Expand-Archive -Path $archivePath -DestinationPath $spicetifyFolderPath -Force -ErrorAction Stop
        Write-Success
        Remove-Item -Path $archivePath -Force -ErrorAction SilentlyContinue

        # Restore config if backup exists
        if (Test-Path $configBackupPath) {
            Write-Host "Restoring configuration..." -NoNewline
            Copy-Item -Path $configBackupPath -Destination $configPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $configBackupPath -Force -ErrorAction SilentlyContinue
            Write-Success
        }

        Write-Host "Spicetify has been successfully updated to v$latestVersion!" -ForegroundColor 'Green'
        Write-Host "Note: You may need to run 'Backup & Apply Changes' from Settings to apply updates." -ForegroundColor 'Cyan'
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
        # Use quiet flag to avoid GitHub API calls
        Invoke-Spicetify "-q" "restore" | Out-Null
        Write-Success

        # Remove both Local and Roaming spicetify folders
        $spicetifyLocalPath = "$env:LOCALAPPDATA\spicetify"
        $spicetifyRoamingPath = "$env:APPDATA\spicetify"

        Write-Host "Step 2: Removing Spicetify files from Local folder..." -NoNewline
        if (Test-Path -Path $spicetifyLocalPath) {
            Remove-Item -Path $spicetifyLocalPath -Recurse -Force -ErrorAction Stop
        }
        Write-Success

        Write-Host "Step 3: Removing Spicetify files from Roaming folder..." -NoNewline
        if (Test-Path -Path $spicetifyRoamingPath) {
            Remove-Item -Path $spicetifyRoamingPath -Recurse -Force -ErrorAction Stop
        }
        Write-Success

        Write-Host "Step 4: Cleaning Spicetify from your PATH environment variable..." -NoNewline
        $user = [EnvironmentVariableTarget]::User
        $currentPath = [Environment]::GetEnvironmentVariable('PATH', $user)
        # Remove both possible spicetify paths from PATH
        $newPath = ($currentPath.Split(';') | Where-Object {
            $_ -notlike "*$spicetifyLocalPath*" -and
            $_ -notlike "*$spicetifyRoamingPath*" -and
            $_ -notlike "*spicetify*"
        }) -join ';'
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
        # Ensure GitHub token environment variable is always up to date
        Update-GitHubTokenEnvironment
        
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
        # Ensure GitHub token environment variable is always up to date
        Update-GitHubTokenEnvironment
        
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
    Write-Host "|     Welcome to the All-in-One Spicetify Manager BY MBN       |" -ForegroundColor 'White'
    Write-Host "|      This script helps you install and manage Spotify        |" -ForegroundColor 'Gray'
    Write-Host "|           and the Spicetify customization tool.              |" -ForegroundColor 'Gray'
    Write-Host "+==============================================================+" -ForegroundColor 'Cyan'
    Write-Host "|  Spotify :                                                   |" -ForegroundColor 'Yellow'
    Write-Host "|  [1] Install Spotify                                         |" -ForegroundColor 'White'
    Write-Host "|  [2] Update Spotify                                          |" -ForegroundColor 'White'
    Write-Host "|  [3] Remove Spotify                                          |" -ForegroundColor 'White'
    Write-Host "|                                                              |" -ForegroundColor 'Cyan'
    Write-Host "|  Spicetify :                                                 |" -ForegroundColor 'Green'
    Write-Host "|  [4] Install Spicetify                                       |" -ForegroundColor 'White'
    Write-Host "|  [5] Install Spicetify Marketplace                           |" -ForegroundColor 'White'
    Write-Host "|  [6] Update Spicetify                                        |" -ForegroundColor 'White'
    Write-Host "|  [7] Spicetify Settings                                      |" -ForegroundColor 'White'
    Write-Host "|  [8] Remove Spicetify                                        |" -ForegroundColor 'White'
    Write-Host "|                                                              |" -ForegroundColor 'Cyan'
    Write-Host "|  [9] GitHub API Token Settings                               |" -ForegroundColor 'Magenta'
    Write-Host "|                                                              |" -ForegroundColor 'Cyan'
    Write-Host "|  [0] Exit                                                    |" -ForegroundColor 'White'
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
    Write-Host "|   Extensions & Apps:                                         |" -ForegroundColor 'Gray'
    Write-Host "|     [6] Manage Extensions                                    |" -ForegroundColor 'White'
    Write-Host "|     [7] Manage Custom Apps                                   |" -ForegroundColor 'White'
    Write-Host "|                                                              |" -ForegroundColor 'Magenta'
    Write-Host "|   Configuration:                                             |" -ForegroundColor 'Gray'
    Write-Host "|     [8] Manage Toggles (CSS, Sentry, etc.)                   |" -ForegroundColor 'White'
    Write-Host "|     [9] Manage Text/Path Settings (Theme, etc.)              |" -ForegroundColor 'White'
    Write-Host "|    [10] Manage Spotify Launch Flags                          |" -ForegroundColor 'White'
    Write-Host "|                                                              |" -ForegroundColor 'Magenta'
    Write-Host "|   Debug:                                                     |" -ForegroundColor 'Gray'
    Write-Host "|    [11] Show Raw Spicetify Config Output                     |" -ForegroundColor 'Yellow'
    Write-Host "|                                                              |" -ForegroundColor 'Magenta'
    Write-Host "|    [12] Back to Main Menu                                    |" -ForegroundColor 'White'
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

function Get-SpicetifyConfigValue {
    param(
        [string]$ConfigKey
    )

    # Get the full config output and parse it properly
    $fullConfigOutput = Invoke-SpicetifyWithOutput "config"
    $configValue = ""
    $configArray = @()

    if ($fullConfigOutput) {
        # Parse the full config output to find our key
        $lines = $fullConfigOutput -split "`r?`n"
        foreach ($line in $lines) {
            $line = $line.Trim()
            # Look for lines that start with our config key followed by = or space
            if ($line -match "^$([regex]::Escape($ConfigKey))\s*=\s*(.*)$") {
                $configValue = $matches[1].Trim()
                break
            } elseif ($line -match "^$([regex]::Escape($ConfigKey))\s+(.*)$") {
                $configValue = $matches[1].Trim()
                break
            }
        }

        # Parse pipe-separated values only if we found a real value
        if ($configValue -and $configValue -ne "" -and $configValue -ne $ConfigKey) {
            $configArray = $configValue.Split('|') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne "" }
        }
    }

    # Only return what's actually configured in Spicetify config
    return @{
        RawValue = $configValue
        Array = $configArray
    }
}

function Test-SpicetifyApplied {
    # Check if changes have been applied in current session first
    if ($Global:changesApplied) {
        return $true
    }

    # Simple and reliable method to check if Spicetify has been applied
    try {
        # Method 1: Check if backup files exist (most reliable indicator)
        $backupPaths = @(
            "$env:APPDATA\Spotify\Apps\xpui.spa.bak",
            "$env:LOCALAPPDATA\Spotify\Apps\xpui.spa.bak"
        )

        foreach ($backupPath in $backupPaths) {
            if (Test-Path $backupPath) {
                $Global:changesApplied = $true
                return $true
            }
        }

        # Method 2: Check if inject_css is enabled and there are extensions/apps configured
        $configOutput = Invoke-SpicetifyWithOutput "config"
        $cssEnabled = $configOutput -like "*inject_css*1*"
        $hasExtensions = $configOutput -like "*extensions*" -and $configOutput -notlike "*extensions =*" -and $configOutput -notlike "*extensions  *"
        $hasCustomApps = $configOutput -like "*custom_apps*" -and $configOutput -notlike "*custom_apps =*" -and $configOutput -notlike "*custom_apps  *"

        # If CSS is enabled and we have extensions or custom apps, likely applied
        if ($cssEnabled -and ($hasExtensions -or $hasCustomApps)) {
            $Global:changesApplied = $true
            return $true
        }

        return $false
    }
    catch {
        return $false
    }
}

function Get-InstalledItemsFromFileSystem {
    param(
        [string]$ItemType
    )

    $installedItems = @()

    # Define paths to check
    $paths = @()

    if ($ItemType -eq "extensions") {
        $paths = @(
            "$env:APPDATA\spicetify\Extensions",
            "$env:LOCALAPPDATA\spicetify\Extensions"
        )
        $fileExtension = "*.js"
    } elseif ($ItemType -eq "custom_apps") {
        $paths = @(
            "$env:APPDATA\spicetify\CustomApps",
            "$env:LOCALAPPDATA\spicetify\CustomApps"
        )
        $fileExtension = $null  # For custom apps, we look for directories
    }

    foreach ($path in $paths) {
        if (Test-Path $path) {
            try {
                if ($ItemType -eq "extensions") {
                    # For extensions, get .js files
                    $items = Get-ChildItem -Path $path -Filter $fileExtension -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
                } else {
                    # For custom apps, get directories
                    $items = Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
                }

                if ($items) {
                    $installedItems += $items
                }
            } catch {
                # Ignore errors when accessing directories
            }
        }
    }

    # Remove duplicates and return
    return $installedItems | Sort-Object | Get-Unique
}

function Manage-GitHubToken {
    while ($true) {
        try {
            Clear-Host
            Write-Host "--- GitHub API Token Configuration ---" -ForegroundColor 'Yellow'

            # Show current token status
            if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
                $maskedToken = $Global:githubToken.Substring(0, [Math]::Min(10, $Global:githubToken.Length)) + "..." +
                              $Global:githubToken.Substring([Math]::Max(0, $Global:githubToken.Length - 4))
                Write-Host "Current token: $maskedToken" -ForegroundColor 'Cyan'

                # Test current token
                $tokenTest = Test-GitHubTokenValidity -Token $Global:githubToken
                if ($tokenTest.IsValid) {
                    Write-Host "Token status: Valid" -ForegroundColor 'Green'
                    if ($tokenTest.UserInfo) {
                        Write-Host "  Authenticated as: $($tokenTest.UserInfo.login)" -ForegroundColor 'Cyan'
                    }
                } else {
                    Write-Host "Token status: $($tokenTest.Message)" -ForegroundColor 'Red'
                }

                $configPath = Get-SpicetifyPlusConfigPath
                Write-Host "Token stored in: $configPath" -ForegroundColor 'Gray'
            } else {
                Write-Host "Current token: Not set" -ForegroundColor 'Red'
            }

            Write-Host ""
            Write-Host "Options:" -ForegroundColor 'White'
            Write-Host "[1] Set/Update GitHub API Token"
            Write-Host "[2] Test current token"
            Write-Host "[3] Show GitHub token info"
            Write-Host "[4] Remove saved token"
            Write-Host "[5] Back to Settings Menu"

            $choice = Read-Host "Choose an option (1-5)"

            switch ($choice) {
                '1' {
                    Write-Host ""
                    Write-Host "Enter your GitHub Personal Access Token:" -ForegroundColor 'Cyan'
                    Write-Host "Note: The token will be validated before saving." -ForegroundColor 'Gray'

                    # Use regular Read-Host for better compatibility
                    $newTokenPlain = Read-Host "GitHub Token"

                    if ([string]::IsNullOrWhiteSpace($newTokenPlain)) {
                        Write-Host "No token entered. Operation cancelled." -ForegroundColor 'Yellow'
                        Press-EnterToContinue
                        continue
                    }

                    Write-Host "Validating token..." -ForegroundColor 'Cyan'
                    Write-Host "This may take a few seconds..." -ForegroundColor 'Gray'

                    $validation = Test-GitHubTokenValidity -Token $newTokenPlain

                    if ($validation.IsValid) {
                        Write-Host "Token is valid!" -ForegroundColor 'Green'
                        if ($validation.UserInfo) {
                            Write-Host "  Authenticated as: $($validation.UserInfo.login)" -ForegroundColor 'Cyan'
                            Write-Host "  Account type: $($validation.UserInfo.type)" -ForegroundColor 'Cyan'
                        }

                        Write-Host "Saving token..." -ForegroundColor 'Cyan'
                        if (Save-GitHubToken -Token $newTokenPlain) {
                            $Global:githubToken = $newTokenPlain
                            # Ensure environment variable is set immediately
                            Update-GitHubTokenEnvironment
                            Write-Host "Token saved successfully!" -ForegroundColor 'Green'
                            $configPath = Get-SpicetifyPlusConfigPath
                            Write-Host "Token stored in: $configPath" -ForegroundColor 'Gray'
                            Write-Host "Environment variable GITHUB_TOKEN has been updated." -ForegroundColor 'Gray'
                        } else {
                            Write-Host "Failed to save token." -ForegroundColor 'Red'
                        }
                    } else {
                        Write-Host "Token validation failed: $($validation.Message)" -ForegroundColor 'Red'
                        Write-Host "Token was not saved. Please check your token and try again." -ForegroundColor 'Yellow'
                        Write-Host ""
                        Write-Host "Common issues:" -ForegroundColor 'Yellow'
                        Write-Host "- Make sure you copied the complete token" -ForegroundColor 'Gray'
                        Write-Host "- Check your internet connection" -ForegroundColor 'Gray'
                        Write-Host "- Verify the token hasn't expired" -ForegroundColor 'Gray'
                    }

                    # Clear the plain text token from memory
                    $newTokenPlain = $null
                    Press-EnterToContinue
                }
                '2' {
                    if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
                        Write-Host "Testing GitHub token..." -ForegroundColor 'Cyan'
                        $validation = Test-GitHubTokenValidity -Token $Global:githubToken

                        if ($validation.IsValid) {
                            Write-Host "Token is valid!" -ForegroundColor 'Green'
                            if ($validation.UserInfo) {
                                Write-Host "  Authenticated as: $($validation.UserInfo.login)" -ForegroundColor 'Cyan'
                                Write-Host "  Account type: $($validation.UserInfo.type)" -ForegroundColor 'Cyan'
                                if ($validation.UserInfo.plan) {
                                    Write-Host "  Plan: $($validation.UserInfo.plan.name)" -ForegroundColor 'Cyan'
                                }
                            }
                        } else {
                            Write-Host "Token test failed: $($validation.Message)" -ForegroundColor 'Red'
                        }
                    } else {
                        Write-Warning "No GitHub token available to test."
                    }
                    Press-EnterToContinue
                }
                '3' {
                    Write-Host "GitHub Token Information:" -ForegroundColor 'Cyan'
                    Write-Host "To create a GitHub Personal Access Token:" -ForegroundColor 'White'
                    Write-Host "1. Go to: https://github.com/settings/tokens" -ForegroundColor 'Gray'
                    Write-Host "2. Click 'Generate new token (classic)'" -ForegroundColor 'Gray'
                    Write-Host "3. Give it a name (e.g., 'Spicetify Plus')" -ForegroundColor 'Gray'
                    Write-Host "4. Set expiration (optional, but recommended)" -ForegroundColor 'Gray'
                    Write-Host "5. No scopes/permissions are required for public repos" -ForegroundColor 'Gray'
                    Write-Host "6. Click 'Generate token' and copy the token" -ForegroundColor 'Gray'
                    Write-Host "7. Use option [1] above to set your token" -ForegroundColor 'Gray'
                    Write-Host ""
                    Write-Host "Benefits of using a GitHub token:" -ForegroundColor 'White'
                    Write-Host "- Avoid GitHub API rate limits" -ForegroundColor 'Gray'
                    Write-Host "- Faster downloads from GitHub" -ForegroundColor 'Gray'
                    Write-Host "- More reliable operation" -ForegroundColor 'Gray'
                    Press-EnterToContinue
                }
                '4' {
                    if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
                        $confirm = Read-Host "Are you sure you want to remove the saved token? (y/N)"
                        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                            try {
                                $tokenFilePath = Get-GitHubTokenFilePath
                                if (Test-Path -Path $tokenFilePath) {
                                    Remove-Item -Path $tokenFilePath -Force
                                }
                                $Global:githubToken = ""
                                # Clear environment variable
                                $env:GITHUB_TOKEN = $null
                                Write-Host "Token removed successfully." -ForegroundColor 'Green'
                            }
                            catch {
                                Write-Host "Error removing token: $($_.Exception.Message)" -ForegroundColor 'Red'
                            }
                        } else {
                            Write-Host "Operation cancelled." -ForegroundColor 'Yellow'
                        }
                    } else {
                        Write-Host "No token to remove." -ForegroundColor 'Yellow'
                    }
                    Press-EnterToContinue
                }
                '5' {
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
}

function Manage-Extensions {
    while ($true) {
        try {
            Clear-Host
            Write-Host "--- Extensions Management ---" -ForegroundColor 'Yellow'

            # Get current extensions and check if applied
            $extensionsConfig = Get-SpicetifyConfigValue "extensions"
            $currentExtensions = $extensionsConfig.Array
            $isApplied = Test-SpicetifyApplied

            Write-Host "Current Extensions: " -NoNewline
            if ($currentExtensions.Count -gt 0) {
                $statusText = if ($isApplied) { "APPLIED" } else { "NOT APPLIED" }
                $statusColor = if ($isApplied) { 'Green' } else { 'Yellow' }
                Write-Host ($currentExtensions -join ' | ') -NoNewline -ForegroundColor 'Cyan'
                Write-Host " [$statusText]" -ForegroundColor $statusColor
            } else {
                Write-Host "(No extensions installed)" -ForegroundColor 'Gray'
            }
            Write-Host "---------------------------------------"
            Write-Host "[1] Install Extension"
            Write-Host "[2] Remove Extension"
            Write-Host "[3] List Available Extensions"
            Write-Host "[4] Clear All Extensions"
            if ($currentExtensions.Count -gt 0 -and -not $isApplied) {
                Write-Host "[5] Apply New Changes" -ForegroundColor 'Green'
                Write-Host "[6] Back to Settings Menu"
            } else {
                Write-Host "[5] Back to Settings Menu"
            }
            $choice = Read-Host -Prompt "Choose an option"

            # Determine the correct back option based on whether Apply button is shown
            $backOption = if ($currentExtensions.Count -gt 0 -and -not $isApplied) { '6' } else { '5' }

            if ($choice -eq $backOption) { break }
            elseif ($choice -eq '5' -and $currentExtensions.Count -gt 0 -and -not $isApplied) {
                # Apply new changes
                Write-Host "Applying extension changes..." -ForegroundColor 'Cyan'
                if (Invoke-SafeSpicetifyBackup) {
                    if (Invoke-SafeSpicetifyApply) {
                        Write-Host "Extensions applied successfully!" -ForegroundColor 'Green'
                        $Global:changesApplied = $true
                    } else {
                        Write-Host "Apply completed but there may be issues." -ForegroundColor 'Yellow'
                        $Global:changesApplied = $true
                    }
                } else {
                    Write-Host "Backup failed - skipping apply." -ForegroundColor 'Red'
                }
                Press-EnterToContinue
                continue
            }
            elseif ($choice -eq '1') {
                $availableExtensions = @(
                    @{ Name = "autoSkipVideo.js"; Description = "Auto skip videos that can't play in your region"; Category = "Main" },
                    @{ Name = "bookmark.js"; Description = "Store and browse pages, play tracks or tracks in specific time"; Category = "Main" },
                    @{ Name = "autoSkipExplicit.js"; Description = "Auto skip explicit tracks (Christian Spotify)"; Category = "Main" },
                    @{ Name = "fullAppDisplay.js"; Description = "Minimal album cover art display with blur effect"; Category = "Main" },
                    @{ Name = "keyboardShortcut.js"; Description = "Vim-like keyboard shortcuts for navigation"; Category = "Main" },
                    @{ Name = "loopyLoop.js"; Description = "Mark start/end points and loop track portions"; Category = "Main" },
                    @{ Name = "popupLyrics.js"; Description = "Pop-up window with current song's lyrics"; Category = "Main" },
                    @{ Name = "shuffle+.js"; Description = "Better shuffle using Fisher-Yates algorithm"; Category = "Main" },
                    @{ Name = "trashbin.js"; Description = "Throw songs/artists to trash and auto-skip them"; Category = "Main" },
                    @{ Name = "webnowplaying.js"; Description = "For Rainmeter users - WebNowPlaying plugin support"; Category = "Main" },
                    @{ Name = "auto-skip-tracks-by-duration.js"; Description = "Auto skip tracks based on their duration (useful for SFX)"; Category = "Community" },
                    @{ Name = "djMode.js"; Description = "DJ Mode - Setup client for audiences to queue songs without player control"; Category = "Legacy" },
                    @{ Name = "newRelease.js"; Description = "Aggregate new releases from favorite artists and podcasts"; Category = "Legacy" },
                    @{ Name = "queueAll.js"; Description = "Add 'Queue All' button to carousels for easy bulk queuing"; Category = "Legacy" }
                )

                Write-Host "--- Available Extensions ---" -ForegroundColor 'Yellow'
                Write-Host ""
                # Display all extensions with sequential numbering
                $displayIndex = 1

                Write-Host "Main Extensions:" -ForegroundColor 'Cyan'
                $mainExtensions = $availableExtensions | Where-Object { $_.Category -eq "Main" }
                for ($j = 0; $j -lt $mainExtensions.Length; $j++) {
                    $isInstalled = $currentExtensions -contains $mainExtensions[$j].Name
                    if ($isInstalled) {
                        $status = if ($isApplied) { "[INSTALLED]" } else { "[INSTALLED - Not Applied]" }
                        $statusColor = if ($isApplied) { 'Green' } else { 'Yellow' }
                    } else {
                        $status = "[NOT INSTALLED]"
                        $statusColor = 'Gray'
                    }
                    Write-Host "[$displayIndex] $($mainExtensions[$j].Name) " -NoNewline -ForegroundColor 'Cyan'
                    Write-Host $status -NoNewline -ForegroundColor $statusColor
                    Write-Host " - $($mainExtensions[$j].Description)" -ForegroundColor 'Gray'
                    $displayIndex++
                }
                Write-Host ""
                Write-Host "Community Extensions:" -ForegroundColor 'Green'
                $communityExtensions = $availableExtensions | Where-Object { $_.Category -eq "Community" }
                if ($communityExtensions.Length -gt 0) {
                    for ($j = 0; $j -lt $communityExtensions.Length; $j++) {
                        $extName = $communityExtensions[$j].Name
                        $extDesc = $communityExtensions[$j].Description
                        $isInstalled = $currentExtensions -contains $extName
                        if ($isInstalled) {
                            $status = if ($isApplied) { "[INSTALLED]" } else { "[INSTALLED - Not Applied]" }
                            $statusColor = if ($isApplied) { 'Green' } else { 'Yellow' }
                        } else {
                            $status = "[NOT INSTALLED]"
                            $statusColor = 'Gray'
                        }
                        Write-Host "[$displayIndex] $extName " -NoNewline -ForegroundColor 'Cyan'
                        Write-Host $status -NoNewline -ForegroundColor $statusColor
                        Write-Host " - $extDesc" -ForegroundColor 'Gray'
                        $displayIndex++
                    }
                } else {
                    Write-Host "  No community extensions available." -ForegroundColor 'Gray'
                }
                Write-Host ""
                Write-Host "Legacy Extensions (for Spicetify 1.2.1 or below):" -ForegroundColor 'Yellow'
                $legacyExtensions = $availableExtensions | Where-Object { $_.Category -eq "Legacy" }
                for ($j = 0; $j -lt $legacyExtensions.Length; $j++) {
                    $isInstalled = $currentExtensions -contains $legacyExtensions[$j].Name
                    if ($isInstalled) {
                        $status = if ($isApplied) { "[INSTALLED]" } else { "[INSTALLED - Not Applied]" }
                        $statusColor = if ($isApplied) { 'Green' } else { 'Yellow' }
                    } else {
                        $status = "[NOT INSTALLED]"
                        $statusColor = 'Gray'
                    }
                    Write-Host "[$displayIndex] $($legacyExtensions[$j].Name) " -NoNewline -ForegroundColor 'Cyan'
                    Write-Host $status -NoNewline -ForegroundColor $statusColor
                    Write-Host " - $($legacyExtensions[$j].Description)" -ForegroundColor 'Gray'
                    $displayIndex++
                }
                $backOption = $availableExtensions.Length + 1
                Write-Host "[$backOption] Back to Extensions Menu" -ForegroundColor 'Yellow'

                $extChoice = Read-Host -Prompt "Enter number of extension to install (1-$($availableExtensions.Length)) or $backOption to go back"

                if ($extChoice -eq $backOption) {
                    continue
                }
                elseif ($extChoice -match '^\d+$' -and $extChoice -gt 0 -and $extChoice -le $availableExtensions.Length) {
                    $selectedExt = $availableExtensions[[int]$extChoice - 1]

                    if ($currentExtensions -contains $selectedExt.Name) {
                        Write-Warning "Extension '$($selectedExt.Name)' is already installed."
                        Press-EnterToContinue
                    } else {
                        Write-Host "Installing extension: $($selectedExt.Name)..." -ForegroundColor 'Cyan'
                        Invoke-Spicetify "config" "extensions" "$($selectedExt.Name)" | Out-Null
                        Write-Host "Extension '$($selectedExt.Name)' installed successfully!" -ForegroundColor 'Green'
                        Write-Host "Description: $($selectedExt.Description)" -ForegroundColor 'Gray'
                        Write-Host "Note: Run 'Backup & Apply Changes' to activate the extension." -ForegroundColor 'Yellow'
                        Start-Sleep -Seconds 2
                        continue
                    }
                } else {
                    Write-Warning "Invalid selection."
                    Press-EnterToContinue
                }
            }
            elseif ($choice -eq '2') {
                if ($currentExtensions.Count -eq 0) {
                    Write-Warning "No extensions to remove."
                    Press-EnterToContinue
                    continue
                }

                Write-Host "--- Installed Extensions ---" -ForegroundColor 'Yellow'
                for ($j = 0; $j -lt $currentExtensions.Count; $j++) {
                    Write-Host "[$($j+1)] $($currentExtensions[$j])" -ForegroundColor 'Cyan'
                }
                $backOption = $currentExtensions.Count + 1
                Write-Host "[$backOption] Back to Extensions Menu" -ForegroundColor 'Yellow'

                $extChoice = Read-Host -Prompt "Enter number of extension to remove (1-$($currentExtensions.Count)) or $backOption to go back"

                if ($extChoice -eq $backOption) {
                    continue
                }
                elseif ($extChoice -match '^\d+$' -and $extChoice -gt 0 -and $extChoice -le $currentExtensions.Count) {
                    $selectedExt = $currentExtensions[[int]$extChoice - 1]
                    Write-Host "Removing extension: $selectedExt..." -ForegroundColor 'Cyan'
                    Invoke-Spicetify "config" "extensions" "$selectedExt-" | Out-Null
                    Write-Host "Extension '$selectedExt' removed successfully!" -ForegroundColor 'Green'
                    Write-Host "Note: Run 'Backup & Apply Changes' to deactivate the extension." -ForegroundColor 'Yellow'
                    Start-Sleep -Seconds 2
                    continue
                } else {
                    Write-Warning "Invalid selection."
                    Press-EnterToContinue
                }
            }
            elseif ($choice -eq '3') {
                Write-Host "--- All Available Extensions ---" -ForegroundColor 'Yellow'
                Write-Host ""
                Write-Host "=== MAIN EXTENSIONS ===" -ForegroundColor 'Cyan'
                Write-Host ""
                Write-Host "Auto Skip Videos (autoSkipVideo.js):" -ForegroundColor 'Cyan'
                Write-Host "  Auto skip videos that can't play in your region" -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Bookmark (bookmark.js):" -ForegroundColor 'Cyan'
                Write-Host "  Store and browse pages, play tracks or tracks in specific time" -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Christian Spotify (autoSkipExplicit.js):" -ForegroundColor 'Cyan'
                Write-Host "  Auto skip explicit tracks. Toggle option in Profile menu." -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Full App Display (fullAppDisplay.js):" -ForegroundColor 'Cyan'
                Write-Host "  Minimal album cover art display with blur effect background" -ForegroundColor 'Gray'
                Write-Host "  Activating button located in top bar. Double click to exit." -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Keyboard Shortcut (keyboardShortcut.js):" -ForegroundColor 'Cyan'
                Write-Host "  Vim-like keyboard shortcuts for navigation" -ForegroundColor 'Gray'
                Write-Host "  Ctrl+Tab/Shift+Tab, PageUp/Down, J/K, G/Shift+G, F for navigation" -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Loopy Loop (loopyLoop.js):" -ForegroundColor 'Cyan'
                Write-Host "  Mark start/end points on progress bar and loop track portions" -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Pop-up Lyrics (popupLyrics.js):" -ForegroundColor 'Cyan'
                Write-Host "  Pop-up window with current song's lyrics" -ForegroundColor 'Gray'
                Write-Host "  Click microphone icon in top bar to open lyrics window" -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Shuffle+ (shuffle+.js):" -ForegroundColor 'Cyan'
                Write-Host "  Better shuffle using Fisher-Yates algorithm with zero bias" -ForegroundColor 'Gray'
                Write-Host "  Right click album/playlist for 'Play with Shuffle+' option" -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Trash Bin (trashbin.js):" -ForegroundColor 'Cyan'
                Write-Host "  Throw songs/artists to trash and auto-skip them" -ForegroundColor 'Gray'
                Write-Host "  Adds 'Throw to Trashbin' option in right click menu" -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Web Now Playing (webnowplaying.js):" -ForegroundColor 'Cyan'
                Write-Host "  For Rainmeter users - WebNowPlaying plugin support" -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "=== COMMUNITY EXTENSIONS ===" -ForegroundColor 'Green'
                Write-Host ""
                Write-Host "Auto Skip Tracks by Duration (auto-skip-tracks-by-duration.js):" -ForegroundColor 'Cyan'
                Write-Host "  Automatically skip tracks based on their duration" -ForegroundColor 'Gray'
                Write-Host "  Especially useful for skipping SFX in local files collection" -ForegroundColor 'Gray'
                Write-Host "  Settings can be found in user settings (implemented using spcr-settings)" -ForegroundColor 'Gray'
                Write-Host "  Warning: Be careful not to cause skipping loops!" -ForegroundColor 'Yellow'
                Write-Host ""
                Write-Host "=== LEGACY EXTENSIONS (Spicetify 1.2.1 or below) ===" -ForegroundColor 'Yellow'
                Write-Host ""
                Write-Host "DJ Mode (djMode.js):" -ForegroundColor 'Cyan'
                Write-Host "  Setup client for audiences to choose and queue songs" -ForegroundColor 'Gray'
                Write-Host "  Prevents audience from controlling player directly" -ForegroundColor 'Gray'
                Write-Host "  Play buttons add to queue instead of playing directly" -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "New Release (newRelease.js):" -ForegroundColor 'Cyan'
                Write-Host "  Aggregate new releases from favorite artists and podcasts" -ForegroundColor 'Gray'
                Write-Host "  Right click Bell icon to open settings menu" -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Queue All (queueAll.js):" -ForegroundColor 'Cyan'
                Write-Host "  Add 'Queue All' button to carousels for easy bulk queuing" -ForegroundColor 'Gray'
                Write-Host "  Available for songs and albums carousels (not playlists)" -ForegroundColor 'Gray'
                Write-Host ""
                Press-EnterToContinue
            }
            elseif ($choice -eq '4') {
                if ($currentExtensions.Count -eq 0) {
                    Write-Warning "No extensions to clear."
                    Press-EnterToContinue
                    continue
                }

                Write-Host "--- Clear Extensions Options ---" -ForegroundColor 'Yellow'
                Write-Host "[1] Remove All Extensions ($($currentExtensions.Count) extensions)" -ForegroundColor 'Red'
                Write-Host "[2] Select Extensions to Remove" -ForegroundColor 'Cyan'
                Write-Host "[3] Back to Extensions Menu" -ForegroundColor 'Yellow'

                $clearChoice = Read-Host -Prompt "Choose an option (1-3)"

                if ($clearChoice -eq '3') {
                    continue
                }
                elseif ($clearChoice -eq '1') {
                    $confirmation = Read-Host "Are you sure you want to remove ALL extensions? This will remove $($currentExtensions.Count) extension(s). (y/n)"
                    if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
                        Write-Host "Removing all extensions..." -ForegroundColor 'Cyan'
                        # Remove extensions one by one to avoid empty string issue
                        foreach ($ext in $currentExtensions) {
                            Write-Host "  Removing: $ext" -ForegroundColor 'Gray'
                            Invoke-Spicetify "config" "extensions" "$ext-" | Out-Null
                        }
                        Write-Host "All extensions have been removed successfully!" -ForegroundColor 'Green'
                        Write-Host "Note: Run 'Backup & Apply Changes' to deactivate all extensions." -ForegroundColor 'Yellow'
                        Start-Sleep -Seconds 2
                        continue
                    } else {
                        Write-Host "Clear operation cancelled." -ForegroundColor 'Yellow'
                        Press-EnterToContinue
                    }
                }
                elseif ($clearChoice -eq '2') {
                    Write-Host "--- Select Extensions to Remove ---" -ForegroundColor 'Yellow'
                    Write-Host "Current Extensions:" -ForegroundColor 'Cyan'

                    $selectedExtensions = @()

                    while ($true) {
                        Write-Host ""
                        for ($j = 0; $j -lt $currentExtensions.Count; $j++) {
                            $isSelected = $selectedExtensions -contains $currentExtensions[$j]
                            $marker = if ($isSelected) { "[X]" } else { "[ ]" }
                            $color = if ($isSelected) { 'Green' } else { 'Cyan' }
                            Write-Host "[$($j+1)] $marker $($currentExtensions[$j])" -ForegroundColor $color
                        }

                        $toggleAllOption = $currentExtensions.Count + 1
                        $removeSelectedOption = $currentExtensions.Count + 2
                        $backOption = $currentExtensions.Count + 3

                        Write-Host ""
                        Write-Host "[$toggleAllOption] Toggle All" -ForegroundColor 'Yellow'
                        Write-Host "[$removeSelectedOption] Remove Selected ($($selectedExtensions.Count) selected)" -ForegroundColor 'Red'
                        Write-Host "[$backOption] Back to Clear Options" -ForegroundColor 'Yellow'

                        $extChoice = Read-Host -Prompt "Enter number to toggle selection, or choose action"

                        if ($extChoice -eq $backOption) {
                            break
                        }
                        elseif ($extChoice -eq $toggleAllOption) {
                            if ($selectedExtensions.Count -eq $currentExtensions.Count) {
                                $selectedExtensions = @()
                                Write-Host "All extensions deselected." -ForegroundColor 'Yellow'
                            } else {
                                $selectedExtensions = $currentExtensions.Clone()
                                Write-Host "All extensions selected." -ForegroundColor 'Green'
                            }
                        }
                        elseif ($extChoice -eq $removeSelectedOption) {
                            if ($selectedExtensions.Count -eq 0) {
                                Write-Warning "No extensions selected for removal."
                                Start-Sleep -Seconds 1
                                continue
                            }

                            $confirmation = Read-Host "Are you sure you want to remove $($selectedExtensions.Count) selected extension(s)? (y/n)"
                            if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
                                Write-Host "Removing selected extensions..." -ForegroundColor 'Cyan'
                                foreach ($ext in $selectedExtensions) {
                                    Write-Host "  Removing: $ext" -ForegroundColor 'Gray'
                                    Invoke-Spicetify "config" "extensions" "$ext-" | Out-Null
                                }
                                Write-Host "$($selectedExtensions.Count) extension(s) removed successfully!" -ForegroundColor 'Green'
                                Write-Host "Note: Run 'Backup & Apply Changes' to deactivate the extensions." -ForegroundColor 'Yellow'
                                Start-Sleep -Seconds 2
                                break
                            } else {
                                Write-Host "Remove operation cancelled." -ForegroundColor 'Yellow'
                                Start-Sleep -Seconds 1
                            }
                        }
                        elseif ($extChoice -match '^\d+$' -and $extChoice -gt 0 -and $extChoice -le $currentExtensions.Count) {
                            $selectedExt = $currentExtensions[[int]$extChoice - 1]
                            if ($selectedExtensions -contains $selectedExt) {
                                $selectedExtensions = $selectedExtensions | Where-Object { $_ -ne $selectedExt }
                                Write-Host "Deselected: $selectedExt" -ForegroundColor 'Yellow'
                            } else {
                                $selectedExtensions += $selectedExt
                                Write-Host "Selected: $selectedExt" -ForegroundColor 'Green'
                            }
                        } else {
                            Write-Warning "Invalid selection."
                            Start-Sleep -Seconds 1
                        }
                    }
                } else {
                    Write-Warning "Invalid selection."
                    Press-EnterToContinue
                }
            }
            else {
                Write-Warning "Invalid selection."
                Press-EnterToContinue
            }
        }
        catch {
            Write-Error-Message $_.Exception.Message
            Press-EnterToContinue
        }
    }
}

function Install-SpicetifyHistory {
    try {
        Write-Host "Installing Spicetify History..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\spicetify-history"

        # Download latest release
        Write-Host "Downloading latest release..." -NoNewline
        $releaseUrl = "https://api.github.com/repos/bc9123/spicetify-history/releases/latest"

        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $headers = @{ "Authorization" = "Bearer $Global:githubToken" }
            $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -ErrorAction Stop
        } else {
            $release = Invoke-RestMethod -Uri $releaseUrl -ErrorAction Stop
        }

        $downloadUrl = $release.zipball_url
        $zipFile = "$env:TEMP\spicetify-history.zip"

        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $headers = @{ "Authorization" = "Bearer $Global:githubToken" }
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -Headers $headers -ErrorAction Stop
        } else {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        }
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        $tempExtractPath = "$env:TEMP\spicetify-history-extract"
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Find the extracted folder (GitHub creates folder with commit hash)
        $extractedFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
        Move-Item -Path $extractedFolder.FullName -Destination $targetDir -Force

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "spicetify-history" | Out-Null
        Write-Success

        Write-Host "Spicetify History installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install Spicetify History: $($_.Exception.Message)"
        return $false
    }
}

function Install-WMPotifyNowPlaying {
    try {
        Write-Host "Installing WMPotify NowPlaying..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\wmpvis"

        # Download latest release
        Write-Host "Downloading latest release..." -NoNewline
        $releaseUrl = "https://api.github.com/repos/Ingan121/Spicetify-CustomApps/releases/latest"

        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $headers = @{ "Authorization" = "Bearer $Global:githubToken" }
            $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -ErrorAction Stop
        } else {
            $release = Invoke-RestMethod -Uri $releaseUrl -ErrorAction Stop
        }

        # Find WMPotify NowPlaying asset
        $asset = $release.assets | Where-Object { $_.name -like "*WMPotify*NowPlaying*" -or $_.name -like "*wmpvis*" }
        if (-not $asset) {
            $asset = $release.assets | Select-Object -First 1  # Fallback to first asset
        }

        $zipFile = "$env:TEMP\wmpvis.zip"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipFile -ErrorAction Stop
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $targetDir -Force

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "wmpvis" | Out-Null
        Write-Success

        Write-Host "WMPotify NowPlaying installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install WMPotify NowPlaying: $($_.Exception.Message)"
        return $false
    }
}

function Install-Enhancify {
    try {
        Write-Host "Installing Enhancify..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\enhancify"

        # Download latest release
        Write-Host "Downloading latest release..." -NoNewline
        $releaseUrl = "https://api.github.com/repos/ECE49595-Team-6/EnhancifyInstall/releases/latest"

        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $headers = @{ "Authorization" = "Bearer $Global:githubToken" }
            $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -ErrorAction Stop
        } else {
            $release = Invoke-RestMethod -Uri $releaseUrl -ErrorAction Stop
        }

        $downloadUrl = $release.zipball_url
        $zipFile = "$env:TEMP\enhancify.zip"

        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $headers = @{ "Authorization" = "Bearer $Global:githubToken" }
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -Headers $headers -ErrorAction Stop
        } else {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        }
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        $tempExtractPath = "$env:TEMP\enhancify-extract"
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Find the extracted folder and look for the app files
        $extractedFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1

        # Look for the actual app folder (might be in a subdirectory)
        $appFolder = Get-ChildItem -Path $extractedFolder.FullName -Directory -Recurse | Where-Object {
            (Test-Path "$($_.FullName)\manifest.json") -or
            (Test-Path "$($_.FullName)\index.js") -or
            (Get-ChildItem -Path $_.FullName -Filter "*.js" -ErrorAction SilentlyContinue).Count -gt 0
        } | Select-Object -First 1

        if ($appFolder) {
            Move-Item -Path $appFolder.FullName -Destination $targetDir -Force
        } else {
            # Fallback: move the entire extracted folder
            Move-Item -Path $extractedFolder.FullName -Destination $targetDir -Force
        }

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "enhancify" | Out-Null
        Write-Success

        Write-Host "Enhancify installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install Enhancify: $($_.Exception.Message)"
        return $false
    }
}

function Install-Lyrixed {
    try {
        Write-Host "Installing Lyrixed..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\lyrixed"

        # Download latest release
        Write-Host "Downloading latest release..." -NoNewline
        $downloadUrl = "https://github.com/Nuzair46/Lyrixed/releases/latest/download/lyrixed.zip"
        $zipFile = "$env:TEMP\lyrixed.zip"

        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Expand-Archive -Path $zipFile -DestinationPath $targetDir -Force

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "lyrixed" | Out-Null
        Write-Success

        Write-Host "Lyrixed installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install Lyrixed: $($_.Exception.Message)"
        return $false
    }
}

function Install-HistoryInSidebar {
    try {
        Write-Host "Installing History in Sidebar..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\history-in-sidebar"

        # Download from specific branch
        Write-Host "Downloading from GitHub..." -NoNewline
        $downloadUrl = "https://github.com/Bergbok/Spicetify-Creations/archive/refs/heads/dist/history-in-sidebar.zip"
        $zipFile = "$env:TEMP\history-in-sidebar.zip"

        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        $tempExtractPath = "$env:TEMP\history-in-sidebar-extract"
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Find the extracted folder and rename it
        $extractedFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
        Move-Item -Path $extractedFolder.FullName -Destination $targetDir -Force

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "history-in-sidebar" | Out-Null
        Write-Success

        Write-Host "History in Sidebar installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install History in Sidebar: $($_.Exception.Message)"
        return $false
    }
}

function Install-PlaylistTags {
    try {
        Write-Host "Installing Playlist Tags..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\playlist-tags"

        # Download from specific branch
        Write-Host "Downloading from GitHub..." -NoNewline
        $downloadUrl = "https://github.com/Bergbok/Spicetify-Creations/archive/refs/heads/dist/playlist-tags.zip"
        $zipFile = "$env:TEMP\playlist-tags.zip"

        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        $tempExtractPath = "$env:TEMP\playlist-tags-extract"
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Find the extracted folder and rename it
        $extractedFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
        Move-Item -Path $extractedFolder.FullName -Destination $targetDir -Force

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "playlist-tags" | Out-Null
        Write-Success

        Write-Host "Playlist Tags installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install Playlist Tags: $($_.Exception.Message)"
        return $false
    }
}

function Install-BetterLibrary {
    try {
        Write-Host "Installing Better Library..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\betterLibrary"

        # Download latest release
        Write-Host "Downloading latest release..." -NoNewline
        $releaseUrl = "https://api.github.com/repos/Sowgro/betterLibrary/releases/latest"

        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $headers = @{ "Authorization" = "Bearer $Global:githubToken" }
            $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -ErrorAction Stop
        } else {
            $release = Invoke-RestMethod -Uri $releaseUrl -ErrorAction Stop
        }

        $downloadUrl = $release.zipball_url
        $zipFile = "$env:TEMP\betterLibrary.zip"

        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $headers = @{ "Authorization" = "Bearer $Global:githubToken" }
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -Headers $headers -ErrorAction Stop
        } else {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        }
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        $tempExtractPath = "$env:TEMP\betterLibrary-extract"
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Find the extracted folder and look for CustomApps/betterLibrary
        $extractedFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
        $betterLibraryPath = "$($extractedFolder.FullName)\CustomApps\betterLibrary"

        if (Test-Path $betterLibraryPath) {
            Move-Item -Path $betterLibraryPath -Destination $targetDir -Force
        } else {
            # Fallback: look for any folder with betterLibrary files
            $appFolder = Get-ChildItem -Path $extractedFolder.FullName -Directory -Recurse | Where-Object {
                Test-Path "$($_.FullName)\manifest.json" -or Test-Path "$($_.FullName)\index.js"
            } | Select-Object -First 1

            if ($appFolder) {
                Move-Item -Path $appFolder.FullName -Destination $targetDir -Force
            } else {
                throw "Could not find betterLibrary app files in the downloaded archive"
            }
        }

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "betterLibrary" | Out-Null
        Write-Success

        Write-Host "Better Library installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install Better Library: $($_.Exception.Message)"
        return $false
    }
}

function Install-Visualizer {
    try {
        Write-Host "Installing Spicetify Visualizer..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\visualizer"

        # Download from dist branch
        Write-Host "Downloading from GitHub..." -NoNewline
        $downloadUrl = "https://github.com/Konsl/spicetify-visualizer/archive/refs/heads/dist.zip"
        $zipFile = "$env:TEMP\visualizer.zip"

        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        $tempExtractPath = "$env:TEMP\visualizer-extract"
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Find the extracted folder and move files
        $extractedFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

        # Copy all files from extracted folder to target directory
        Get-ChildItem -Path $extractedFolder.FullName -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $targetDir -Force
        }

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "visualizer" | Out-Null
        Write-Success

        Write-Host "Spicetify Visualizer installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install Spicetify Visualizer: $($_.Exception.Message)"
        return $false
    }
}

function Install-SpicetifyStats {
    try {
        Write-Host "Installing Spicetify Stats..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\stats"

        # Get the latest STATS release
        Write-Host "Fetching latest Stats release..." -NoNewline
        $repo = "harbassan/spicetify-apps"

        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $headers = @{ "Authorization" = "Bearer $Global:githubToken" }
            $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases" -Headers $headers -ErrorAction Stop
        } else {
            $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases" -ErrorAction Stop
        }

        $latestStatsRelease = $releases | Where-Object { $_.tag_name -match "stats-v[0-9]+\.[0-9]+\.[0-9]+" } | Select-Object -First 1

        if (-not $latestStatsRelease) {
            throw "Could not find a Stats release"
        }

        $downloadUrl = $latestStatsRelease.assets[0].browser_download_url
        $zipFile = "$env:TEMP\spicetify-stats.zip"

        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        $tempExtractPath = "$env:TEMP\spicetify-stats-extract"
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force
        Move-Item -Path "$tempExtractPath\*" -Destination $targetDir -Force

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "stats" | Out-Null
        Write-Success

        Write-Host "Spicetify Stats installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install Spicetify Stats: $($_.Exception.Message)"
        return $false
    }
}

function Install-SpicetifyLibrary {
    try {
        Write-Host "Installing Spicetify Library..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\library"

        # Get the latest LIBRARY release
        Write-Host "Fetching latest Library release..." -NoNewline
        $repo = "harbassan/spicetify-apps"

        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $headers = @{ "Authorization" = "Bearer $Global:githubToken" }
            $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases" -Headers $headers -ErrorAction Stop
        } else {
            $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases" -ErrorAction Stop
        }

        $latestLibraryRelease = $releases | Where-Object { $_.tag_name -match "library-v[0-9]+\.[0-9]+\.[0-9]+" } | Select-Object -First 1

        if ($latestLibraryRelease) {
            $downloadUrl = $latestLibraryRelease.assets[0].browser_download_url
        } else {
            # Fallback to direct link
            $downloadUrl = "https://github.com/harbassan/spicetify-apps/releases/download/library-v1.1.0/spicetify-library.release.zip"
        }

        $zipFile = "$env:TEMP\spicetify-library.zip"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        $tempExtractPath = "$env:TEMP\spicetify-library-extract"
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force
        Move-Item -Path "$tempExtractPath\*" -Destination $targetDir -Force

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "library" | Out-Null
        Write-Success

        Write-Host "Spicetify Library installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install Spicetify Library: $($_.Exception.Message)"
        return $false
    }
}

function Install-PithayaApp {
    param(
        [string]$AppName,
        [string]$DisplayName
    )

    try {
        Write-Host "Installing $DisplayName..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\$AppName"

        # Download from specific branch
        Write-Host "Downloading from GitHub..." -NoNewline
        $downloadUrl = "https://github.com/Pithaya/spicetify-apps-dist/archive/refs/heads/dist/$AppName.zip"
        $zipFile = "$env:TEMP\$AppName.zip"

        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        $tempExtractPath = "$env:TEMP\$AppName-extract"
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Find the extracted folder and move files
        $extractedFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

        # Copy all files from extracted folder to target directory
        Get-ChildItem -Path $extractedFolder.FullName -File | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $targetDir -Force
        }

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "$AppName" | Out-Null
        Write-Success

        Write-Host "$DisplayName installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install $DisplayName`: $($_.Exception.Message)"
        return $false
    }
}

function Install-NameThatTune {
    try {
        Write-Host "Installing Name That Tune..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\name-that-tune"

        # Download from dist branch
        Write-Host "Downloading from GitHub..." -NoNewline
        $downloadUrl = "https://github.com/theRealPadster/name-that-tune/archive/refs/heads/dist.zip"
        $zipFile = "$env:TEMP\name-that-tune.zip"

        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        $tempExtractPath = "$env:TEMP\name-that-tune-extract"
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Find the extracted folder and rename it
        $extractedFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
        Move-Item -Path $extractedFolder.FullName -Destination $targetDir -Force

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "name-that-tune" | Out-Null
        Write-Success

        Write-Host "Name That Tune installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install Name That Tune: $($_.Exception.Message)"
        return $false
    }
}

function Install-CombinedPlaylists {
    try {
        Write-Host "Installing Combined Playlists..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\combined-playlists"

        # Download from dist branch
        Write-Host "Downloading from GitHub..." -NoNewline
        $downloadUrl = "https://github.com/jeroentvb/spicetify-combined-playlists/archive/refs/heads/dist.zip"
        $zipFile = "$env:TEMP\combined-playlists.zip"

        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        $tempExtractPath = "$env:TEMP\combined-playlists-extract"
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Find the extracted folder and look for the combined-playlists folder
        $extractedFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
        $combinedPlaylistsPath = "$($extractedFolder.FullName)\combined-playlists"

        if (Test-Path $combinedPlaylistsPath) {
            Move-Item -Path $combinedPlaylistsPath -Destination $targetDir -Force
        } else {
            # Fallback: rename the extracted folder
            Move-Item -Path $extractedFolder.FullName -Destination $targetDir -Force
        }

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "combined-playlists" | Out-Null
        Write-Success

        Write-Host "Combined Playlists installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install Combined Playlists: $($_.Exception.Message)"
        return $false
    }
}

function Install-BeatSaber {
    try {
        Write-Host "Installing Beat Saber Integration..." -ForegroundColor 'Cyan'

        # Create CustomApps directory if it doesn't exist
        $customAppsPath = "$env:APPDATA\spicetify\CustomApps"
        if (-not (Test-Path $customAppsPath)) {
            New-Item -ItemType Directory -Path $customAppsPath -Force | Out-Null
        }

        $targetDir = "$customAppsPath\beatsaber"

        # Download latest release
        Write-Host "Downloading latest release..." -NoNewline
        $releaseUrl = "https://api.github.com/repos/kuba2k2/spicetify-beat-saber/releases/latest"

        if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
            $headers = @{ "Authorization" = "Bearer $Global:githubToken" }
            $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -ErrorAction Stop
        } else {
            $release = Invoke-RestMethod -Uri $releaseUrl -ErrorAction Stop
        }

        # Find the dist zip file (not the .spa file)
        $asset = $release.assets | Where-Object { $_.name -like "*beatsaber-dist*" -and $_.name -like "*.zip" }
        if (-not $asset) {
            # Fallback to direct link
            $downloadUrl = "https://github.com/kuba2k2/spicetify-beat-saber/releases/download/v2.3.0/beatsaber-dist-2.3.0.zip"
        } else {
            $downloadUrl = $asset.browser_download_url
        }

        $zipFile = "$env:TEMP\beatsaber.zip"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -ErrorAction Stop
        Write-Success

        # Extract and setup
        Write-Host "Extracting and setting up..." -NoNewline
        if (Test-Path $targetDir) {
            Remove-Item -Path $targetDir -Recurse -Force
        }

        $tempExtractPath = "$env:TEMP\beatsaber-extract"
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force
        }

        Expand-Archive -Path $zipFile -DestinationPath $tempExtractPath -Force

        # Find the beatsaber directory in the extracted files
        $beatSaberPath = Get-ChildItem -Path $tempExtractPath -Directory -Recurse | Where-Object { $_.Name -eq "beatsaber" } | Select-Object -First 1

        if ($beatSaberPath) {
            Move-Item -Path $beatSaberPath.FullName -Destination $targetDir -Force
        } else {
            # Fallback: move the first directory found
            $extractedFolder = Get-ChildItem -Path $tempExtractPath -Directory | Select-Object -First 1
            Move-Item -Path $extractedFolder.FullName -Destination $targetDir -Force
        }

        # Cleanup
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success

        # Configure Spicetify
        Write-Host "Configuring Spicetify..." -NoNewline
        Invoke-Spicetify "config" "custom_apps" "beatsaber" | Out-Null
        Write-Success

        Write-Host "Beat Saber Integration installed successfully!" -ForegroundColor 'Green'
        Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'
        Write-Host "Additional Note: For full functionality, install spicetify-beat-saber-backend separately." -ForegroundColor 'Cyan'

        return $true
    }
    catch {
        Write-Host " > FAILED" -ForegroundColor 'Red'
        Write-Error-Message "Failed to install Beat Saber Integration: $($_.Exception.Message)"
        return $false
    }
}

function Manage-CustomApps {
    while ($true) {
        try {
            Clear-Host
            Write-Host "--- Custom Apps Management ---" -ForegroundColor 'Yellow'

            # Get current custom apps and check if applied
            $appsConfig = Get-SpicetifyConfigValue "custom_apps"
            $currentApps = $appsConfig.Array
            $isApplied = Test-SpicetifyApplied

            Write-Host "Current Custom Apps: " -NoNewline
            if ($currentApps.Count -gt 0) {
                $statusText = if ($isApplied) { "APPLIED" } else { "NOT APPLIED" }
                $statusColor = if ($isApplied) { 'Green' } else { 'Yellow' }
                Write-Host ($currentApps -join ' | ') -NoNewline -ForegroundColor 'Cyan'
                Write-Host " [$statusText]" -ForegroundColor $statusColor
            } else {
                Write-Host "(No custom apps installed)" -ForegroundColor 'Gray'
            }
            Write-Host "---------------------------------------"
            Write-Host "[1] Install Custom App"
            Write-Host "[2] Remove Custom App"
            Write-Host "[3] List Available Custom Apps"
            Write-Host "[4] Clear All Custom Apps"
            if ($currentApps.Count -gt 0 -and -not $isApplied) {
                Write-Host "[5] Apply New Changes" -ForegroundColor 'Green'
                Write-Host "[6] Back to Settings Menu"
            } else {
                Write-Host "[5] Back to Settings Menu"
            }
            $choice = Read-Host -Prompt "Choose an option"

            # Determine the correct back option based on whether Apply button is shown
            $backOption = if ($currentApps.Count -gt 0 -and -not $isApplied) { '6' } else { '5' }

            if ($choice -eq $backOption) { break }
            elseif ($choice -eq '5' -and $currentApps.Count -gt 0 -and -not $isApplied) {
                # Apply new changes
                Write-Host "Applying custom app changes..." -ForegroundColor 'Cyan'
                if (Invoke-SafeSpicetifyBackup) {
                    if (Invoke-SafeSpicetifyApply) {
                        Write-Host "Custom apps applied successfully!" -ForegroundColor 'Green'
                        $Global:changesApplied = $true
                    } else {
                        Write-Host "Apply completed but there may be issues." -ForegroundColor 'Yellow'
                        $Global:changesApplied = $true
                    }
                } else {
                    Write-Host "Backup failed - skipping apply." -ForegroundColor 'Red'
                }
                Press-EnterToContinue
                continue
            }
            elseif ($choice -eq '1') {
                # Refresh current apps and applied status for accurate display
                $appsConfig = Get-SpicetifyConfigValue "custom_apps"
                $currentApps = $appsConfig.Array
                $isApplied = Test-SpicetifyApplied

                $availableApps = @(
                    @{ Name = "reddit"; Description = "Fetch posts from Spotify link sharing subreddits"; Category = "Official" },
                    @{ Name = "new-releases"; Description = "Aggregate new releases from favorite artists and podcasts"; Category = "Official" },
                    @{ Name = "lyrics-plus"; Description = "Get lyrics from various providers (Musixmatch, Netease, LRCLIB)"; Category = "Official" },
                    @{ Name = "history-in-sidebar"; Description = "Adds a shortcut to the 'Recently Played' panel to the sidebar"; Category = "Community" },
                    @{ Name = "playlist-tags"; Description = "Improved way of organizing and sharing playlists with tags"; Category = "Community" },
                    @{ Name = "spicetify-history"; Description = "Track your Spotify listening history with timestamps and export functionality"; Category = "Community" },
                    @{ Name = "wmpvis"; Description = "WMP-like visualization screen with lyrics overlay (WMPotify NowPlaying)"; Category = "Community" },
                    @{ Name = "enhancify"; Description = "Enhanced Spotify experience with additional features"; Category = "Community" },
                    @{ Name = "lyrixed"; Description = "Bring back lyrics feature for freemium users"; Category = "Community" },
                    @{ Name = "betterLibrary"; Description = "Enhanced library experience with improved organization"; Category = "Community" },
                    @{ Name = "visualizer"; Description = "Audio visualizer with customizable effects"; Category = "Community" },
                    @{ Name = "stats"; Description = "Detailed listening statistics and analytics"; Category = "Community" },
                    @{ Name = "library"; Description = "Enhanced library management and organization"; Category = "Community" },
                    @{ Name = "eternal-jukebox"; Description = "Create infinite loops of your favorite songs"; Category = "Community" },
                    @{ Name = "better-local-files"; Description = "Improved local file management and playback"; Category = "Community" },
                    @{ Name = "playlist-maker"; Description = "Advanced playlist creation and management tools"; Category = "Community" },
                    @{ Name = "name-that-tune"; Description = "Music guessing game with your Spotify library"; Category = "Community" },
                    @{ Name = "combined-playlists"; Description = "Combine multiple playlists into one with auto-sync"; Category = "Community" },
                    @{ Name = "beatsaber"; Description = "Beat Saber map availability and download integration"; Category = "Community" }
                )

                Write-Host "--- Available Custom Apps ---" -ForegroundColor 'Yellow'
                Write-Host ""
                Write-Host "Official Custom Apps:" -ForegroundColor 'Cyan'
                $officialApps = $availableApps | Where-Object { $_.Category -eq "Official" }
                for ($j = 0; $j -lt $officialApps.Length; $j++) {
                    $globalIndex = [array]::IndexOf($availableApps, $officialApps[$j]) + 1
                    $isInstalled = $currentApps -contains $officialApps[$j].Name
                    if ($isInstalled) {
                        $status = if ($isApplied) { "[INSTALLED]" } else { "[INSTALLED - Not Applied]" }
                        $statusColor = if ($isApplied) { 'Green' } else { 'Yellow' }
                    } else {
                        $status = "[NOT INSTALLED]"
                        $statusColor = 'Gray'
                    }
                    Write-Host "[$globalIndex] $($officialApps[$j].Name) " -NoNewline -ForegroundColor 'Cyan'
                    Write-Host $status -NoNewline -ForegroundColor $statusColor
                    Write-Host " - $($officialApps[$j].Description)" -ForegroundColor 'Gray'
                }
                Write-Host ""
                Write-Host "Community Custom Apps:" -ForegroundColor 'Yellow'
                $communityApps = $availableApps | Where-Object { $_.Category -eq "Community" }
                for ($j = 0; $j -lt $communityApps.Length; $j++) {
                    $globalIndex = [array]::IndexOf($availableApps, $communityApps[$j]) + 1
                    $isInstalled = $currentApps -contains $communityApps[$j].Name
                    if ($isInstalled) {
                        $status = if ($isApplied) { "[INSTALLED]" } else { "[INSTALLED - Not Applied]" }
                        $statusColor = if ($isApplied) { 'Green' } else { 'Yellow' }
                    } else {
                        $status = "[NOT INSTALLED]"
                        $statusColor = 'Gray'
                    }
                    Write-Host "[$globalIndex] $($communityApps[$j].Name) " -NoNewline -ForegroundColor 'Cyan'
                    Write-Host $status -NoNewline -ForegroundColor $statusColor
                    Write-Host " - $($communityApps[$j].Description)" -ForegroundColor 'Gray'
                }
                $backOption = $availableApps.Length + 1
                Write-Host "[$backOption] Back to Custom Apps Menu" -ForegroundColor 'Yellow'

                $appChoice = Read-Host -Prompt "Enter number of custom app to install (1-$($availableApps.Length)) or $backOption to go back"

                if ($appChoice -eq $backOption) {
                    continue
                }
                elseif ($appChoice -match '^\d+$' -and [int]$appChoice -gt 0 -and [int]$appChoice -le $availableApps.Length) {
                    $selectedApp = $availableApps[[int]$appChoice - 1]

                    if ($currentApps -contains $selectedApp.Name) {
                        Write-Warning "Custom app '$($selectedApp.Name)' is already installed."
                        Press-EnterToContinue
                    } else {
                        # Use specialized installation functions for certain apps
                        $installSuccess = $false
                        switch ($selectedApp.Name) {
                            "spicetify-history" {
                                $installSuccess = Install-SpicetifyHistory
                            }
                            "wmpvis" {
                                $installSuccess = Install-WMPotifyNowPlaying
                            }
                            "enhancify" {
                                $installSuccess = Install-Enhancify
                            }
                            "lyrixed" {
                                $installSuccess = Install-Lyrixed
                            }
                            "history-in-sidebar" {
                                $installSuccess = Install-HistoryInSidebar
                            }
                            "playlist-tags" {
                                $installSuccess = Install-PlaylistTags
                            }
                            "betterLibrary" {
                                $installSuccess = Install-BetterLibrary
                            }
                            "visualizer" {
                                $installSuccess = Install-Visualizer
                            }
                            "stats" {
                                $installSuccess = Install-SpicetifyStats
                            }
                            "library" {
                                $installSuccess = Install-SpicetifyLibrary
                            }
                            "eternal-jukebox" {
                                $installSuccess = Install-PithayaApp -AppName "eternal-jukebox" -DisplayName "Eternal Jukebox"
                            }
                            "better-local-files" {
                                $installSuccess = Install-PithayaApp -AppName "better-local-files" -DisplayName "Better Local Files"
                            }
                            "playlist-maker" {
                                $installSuccess = Install-PithayaApp -AppName "playlist-maker" -DisplayName "Playlist Maker"
                            }
                            "name-that-tune" {
                                $installSuccess = Install-NameThatTune
                            }
                            "combined-playlists" {
                                $installSuccess = Install-CombinedPlaylists
                            }
                            "beatsaber" {
                                $installSuccess = Install-BeatSaber
                            }
                            default {
                                # Default installation for official apps
                                Write-Host "Installing custom app: $($selectedApp.Name)..." -ForegroundColor 'Cyan'
                                Invoke-Spicetify "config" "custom_apps" "$($selectedApp.Name)" | Out-Null
                                Write-Host "Custom app '$($selectedApp.Name)' installed successfully!" -ForegroundColor 'Green'
                                Write-Host "Description: $($selectedApp.Description)" -ForegroundColor 'Gray'
                                Write-Host "Note: Run 'Backup & Apply Changes' to activate the custom app." -ForegroundColor 'Yellow'
                                $installSuccess = $true
                            }
                        }

                        if ($installSuccess) {
                            Start-Sleep -Seconds 3
                        } else {
                            Write-Host "Installation failed. Please try again or install manually." -ForegroundColor 'Red'
                            Start-Sleep -Seconds 2
                        }
                        continue
                    }
                } else {
                    Write-Warning "Invalid selection."
                    Press-EnterToContinue
                }
            }
            elseif ($choice -eq '2') {
                if ($currentApps.Count -eq 0) {
                    Write-Warning "No custom apps to remove."
                    Press-EnterToContinue
                    continue
                }

                Write-Host "--- Installed Custom Apps ---" -ForegroundColor 'Yellow'
                for ($j = 0; $j -lt $currentApps.Count; $j++) {
                    Write-Host "[$($j+1)] $($currentApps[$j])" -ForegroundColor 'Cyan'
                }
                $backOption = $currentApps.Count + 1
                Write-Host "[$backOption] Back to Custom Apps Menu" -ForegroundColor 'Yellow'

                $appChoice = Read-Host -Prompt "Enter number of custom app to remove (1-$($currentApps.Count)) or $backOption to go back"

                if ($appChoice -eq $backOption) {
                    continue
                }
                elseif ($appChoice -match '^\d+$' -and $appChoice -gt 0 -and $appChoice -le $currentApps.Count) {
                    $selectedApp = $currentApps[[int]$appChoice - 1]
                    Write-Host "Removing custom app: $selectedApp..." -ForegroundColor 'Cyan'
                    Invoke-Spicetify "config" "custom_apps" "$selectedApp-" | Out-Null
                    Write-Host "Custom app '$selectedApp' removed successfully!" -ForegroundColor 'Green'
                    Write-Host "Note: Run 'Backup & Apply Changes' to deactivate the custom app." -ForegroundColor 'Yellow'
                    Start-Sleep -Seconds 2
                    continue
                } else {
                    Write-Warning "Invalid selection."
                    Press-EnterToContinue
                }
            }
            elseif ($choice -eq '3') {
                Write-Host "--- All Available Custom Apps ---" -ForegroundColor 'Yellow'
                Write-Host ""
                Write-Host "=== OFFICIAL CUSTOM APPS ===" -ForegroundColor 'Cyan'
                Write-Host ""
                Write-Host "Reddit (reddit):" -ForegroundColor 'Cyan'
                Write-Host "  Fetching posts from any Spotify link sharing subreddit." -ForegroundColor 'Gray'
                Write-Host "  You can add, remove, arrange subreddits and customize post visual in config menu." -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "New Releases (new-releases):" -ForegroundColor 'Cyan'
                Write-Host "  Aggregate all new releases from favorite artists, podcasts." -ForegroundColor 'Gray'
                Write-Host "  Time range, release type, and other filters can be customized in config menu." -ForegroundColor 'Gray'
                Write-Host "  Date format is based on your locale code (BCP47)." -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Lyrics Plus (lyrics-plus):" -ForegroundColor 'Cyan'
                Write-Host "  Get access to the current track's lyrics from various lyrics providers." -ForegroundColor 'Gray'
                Write-Host "  Providers: Musixmatch, Netease, LRCLIB" -ForegroundColor 'Gray'
                Write-Host "  Colors, lyrics providers can be customized in config menu." -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "=== COMMUNITY CUSTOM APPS ===" -ForegroundColor 'Yellow'
                Write-Host ""
                Write-Host "History in Sidebar (history-in-sidebar):" -ForegroundColor 'Cyan'
                Write-Host "  Adds a shortcut to the 'Recently Played' panel to the sidebar." -ForegroundColor 'Gray'
                Write-Host "  Provides quick access to your recently played tracks and albums." -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Playlist Tags (playlist-tags):" -ForegroundColor 'Cyan'
                Write-Host "  Introduces an improved way of organizing and sharing playlists with tags." -ForegroundColor 'Gray'
                Write-Host "  Features: Tag filtering with AND/OR options, exclude tags with '!' character" -ForegroundColor 'Gray'
                Write-Host "  Settings: Metadata cache, tracklist cache, import/export tags" -ForegroundColor 'Gray'
                Write-Host "  Right-click tags to remove them from playlists" -ForegroundColor 'Gray'
                Write-Host ""
                Write-Host "Note: Custom apps appear in the left sidebar after installation and applying changes." -ForegroundColor 'Yellow'
                Write-Host ""
                Press-EnterToContinue
            }
            elseif ($choice -eq '4') {
                if ($currentApps.Count -eq 0) {
                    Write-Warning "No custom apps to clear."
                    Press-EnterToContinue
                    continue
                }

                Write-Host "--- Clear Custom Apps Options ---" -ForegroundColor 'Yellow'
                Write-Host "[1] Remove All Custom Apps ($($currentApps.Count) apps)" -ForegroundColor 'Red'
                Write-Host "[2] Select Custom Apps to Remove" -ForegroundColor 'Cyan'
                Write-Host "[3] Back to Custom Apps Menu" -ForegroundColor 'Yellow'

                $clearChoice = Read-Host -Prompt "Choose an option (1-3)"

                if ($clearChoice -eq '3') {
                    continue
                }
                elseif ($clearChoice -eq '1') {
                    $confirmation = Read-Host "Are you sure you want to remove ALL custom apps? This will remove $($currentApps.Count) app(s). (y/n)"
                    if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
                        Write-Host "Removing all custom apps..." -ForegroundColor 'Cyan'
                        # Remove custom apps one by one to avoid empty string issue
                        foreach ($app in $currentApps) {
                            Write-Host "  Removing: $app" -ForegroundColor 'Gray'
                            Invoke-Spicetify "config" "custom_apps" "$app-" | Out-Null
                        }
                        Write-Host "All custom apps have been removed successfully!" -ForegroundColor 'Green'
                        Write-Host "Note: Run 'Backup & Apply Changes' to deactivate all custom apps." -ForegroundColor 'Yellow'
                        Start-Sleep -Seconds 2
                        continue
                    } else {
                        Write-Host "Clear operation cancelled." -ForegroundColor 'Yellow'
                        Press-EnterToContinue
                    }
                }
                elseif ($clearChoice -eq '2') {
                    Write-Host "--- Select Custom Apps to Remove ---" -ForegroundColor 'Yellow'
                    Write-Host "Current Custom Apps:" -ForegroundColor 'Cyan'

                    $selectedApps = @()

                    while ($true) {
                        Write-Host ""
                        for ($j = 0; $j -lt $currentApps.Count; $j++) {
                            $isSelected = $selectedApps -contains $currentApps[$j]
                            $marker = if ($isSelected) { "[X]" } else { "[ ]" }
                            $color = if ($isSelected) { 'Green' } else { 'Cyan' }
                            Write-Host "[$($j+1)] $marker $($currentApps[$j])" -ForegroundColor $color
                        }

                        $toggleAllOption = $currentApps.Count + 1
                        $removeSelectedOption = $currentApps.Count + 2
                        $backOption = $currentApps.Count + 3

                        Write-Host ""
                        Write-Host "[$toggleAllOption] Toggle All" -ForegroundColor 'Yellow'
                        Write-Host "[$removeSelectedOption] Remove Selected ($($selectedApps.Count) selected)" -ForegroundColor 'Red'
                        Write-Host "[$backOption] Back to Clear Options" -ForegroundColor 'Yellow'

                        $appChoice = Read-Host -Prompt "Enter number to toggle selection, or choose action"

                        if ($appChoice -eq $backOption) {
                            break
                        }
                        elseif ($appChoice -eq $toggleAllOption) {
                            if ($selectedApps.Count -eq $currentApps.Count) {
                                $selectedApps = @()
                                Write-Host "All custom apps deselected." -ForegroundColor 'Yellow'
                            } else {
                                $selectedApps = $currentApps.Clone()
                                Write-Host "All custom apps selected." -ForegroundColor 'Green'
                            }
                        }
                        elseif ($appChoice -eq $removeSelectedOption) {
                            if ($selectedApps.Count -eq 0) {
                                Write-Warning "No custom apps selected for removal."
                                Start-Sleep -Seconds 1
                                continue
                            }

                            $confirmation = Read-Host "Are you sure you want to remove $($selectedApps.Count) selected custom app(s)? (y/n)"
                            if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
                                Write-Host "Removing selected custom apps..." -ForegroundColor 'Cyan'
                                foreach ($app in $selectedApps) {
                                    Write-Host "  Removing: $app" -ForegroundColor 'Gray'
                                    Invoke-Spicetify "config" "custom_apps" "$app-" | Out-Null
                                }
                                Write-Host "$($selectedApps.Count) custom app(s) removed successfully!" -ForegroundColor 'Green'
                                Write-Host "Note: Run 'Backup & Apply Changes' to deactivate the custom apps." -ForegroundColor 'Yellow'
                                Start-Sleep -Seconds 2
                                break
                            } else {
                                Write-Host "Remove operation cancelled." -ForegroundColor 'Yellow'
                                Start-Sleep -Seconds 1
                            }
                        }
                        elseif ($appChoice -match '^\d+$' -and $appChoice -gt 0 -and $appChoice -le $currentApps.Count) {
                            $selectedApp = $currentApps[[int]$appChoice - 1]
                            if ($selectedApps -contains $selectedApp) {
                                $selectedApps = $selectedApps | Where-Object { $_ -ne $selectedApp }
                                Write-Host "Deselected: $selectedApp" -ForegroundColor 'Yellow'
                            } else {
                                $selectedApps += $selectedApp
                                Write-Host "Selected: $selectedApp" -ForegroundColor 'Green'
                            }
                        } else {
                            Write-Warning "Invalid selection."
                            Start-Sleep -Seconds 1
                        }
                    }
                } else {
                    Write-Warning "Invalid selection."
                    Press-EnterToContinue
                }
            }
            else {
                Write-Warning "Invalid selection."
                Press-EnterToContinue
            }
        }
        catch {
            Write-Error-Message $_.Exception.Message
            Press-EnterToContinue
        }
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
    $mainChoice = Read-Host -Prompt "Please enter your choice [0-9]"

    # Check if Spicetify is required for certain options
    if (($mainChoice -eq '5' -or $mainChoice -eq '6' -or $mainChoice -eq '7' -or $mainChoice -eq '8') -and -not (Get-Command -Name 'spicetify' -ErrorAction SilentlyContinue)) {
        Write-Warning "Spicetify is not installed. Please install it first (Option 4)."
        Press-EnterToContinue
        continue
    }

    try {
        switch ($mainChoice) {
            '1' { Install-Spotify; Press-EnterToContinue }
            '2' { Update-Spotify; Press-EnterToContinue }
            '3' { Remove-Spotify; Press-EnterToContinue }
            '4' { Install-Spicetify; Press-EnterToContinue }
            '5' { Install-Marketplace; Press-EnterToContinue }
            '6' { Update-Spicetify; Press-EnterToContinue }
            '7' {
                while ($true) {
                    Show-SettingsMenu
                    $settingsChoice = Read-Host -Prompt "Choose an action [1-12]"

                    if ($settingsChoice -eq '12') { break }
                    elseif ($settingsChoice -eq '1') {
                        if (Invoke-SafeSpicetifyBackup) {
                            if (Invoke-SafeSpicetifyApply) {
                                Write-Host "Backup and apply completed successfully!" -ForegroundColor 'Green'
                                $Global:changesApplied = $true
                            } else {
                                Write-Host "Backup completed but apply may have issues." -ForegroundColor 'Yellow'
                                $Global:changesApplied = $true
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
                            Manage-Extensions
                        } catch {
                            Write-Error-Message $_.Exception.Message
                            Press-EnterToContinue
                        }
                    }
                    elseif ($settingsChoice -eq '7') {
                        try {
                            Manage-CustomApps
                        } catch {
                            Write-Error-Message $_.Exception.Message
                            Press-EnterToContinue
                        }
                    }
                    elseif ($settingsChoice -eq '8') {
                        try {
                            Manage-Toggles
                        } catch {
                            Write-Error-Message $_.Exception.Message
                            Press-EnterToContinue
                        }
                    }
                    elseif ($settingsChoice -eq '9') {
                        try {
                            Manage-TextSettings
                        } catch {
                            Write-Error-Message $_.Exception.Message
                            Press-EnterToContinue
                        }
                    }
                    elseif ($settingsChoice -eq '10') {
                        try {
                            Manage-LaunchFlags
                        } catch {
                            Write-Error-Message $_.Exception.Message
                            Press-EnterToContinue
                        }
                    }
                    elseif ($settingsChoice -eq '11') {
                        Write-Host "--- Raw 'spicetify config' output ---" -ForegroundColor 'Yellow'
                        $rawConfig = Invoke-SpicetifyWithOutput "config"
                        Write-Host "====================================="
                        Write-Host $rawConfig
                        Write-Host "====================================="
                        Write-Host "--- End of raw output ---" -ForegroundColor 'Yellow'
                        Press-EnterToContinue
                    }
                    else {
                        Write-Warning "Invalid choice. Please enter a number between 1-12."
                        Press-EnterToContinue
                    }
                }
            }
            '8' { Remove-Spicetify; Press-EnterToContinue }
            '9' {
                try {
                    Manage-GitHubToken
                } catch {
                    Write-Error-Message $_.Exception.Message
                    Press-EnterToContinue
                }
            }
            '0' { Write-Host "Exiting. Goodbye!" -ForegroundColor 'Green'; exit }
            default { Write-Warning "Invalid choice."; Press-EnterToContinue }
        }
    }
    catch {
        Write-Error-Message $_.Exception.Message
        Press-EnterToContinue
    }
}