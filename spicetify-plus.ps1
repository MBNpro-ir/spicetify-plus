[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$UpstreamRoot = '.upstream',
    [switch]$NoPause,
    [switch]$BypassAdmin
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:RepoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:CatalogPath = Join-Path $script:RepoRoot 'spicetify-plus.catalog.json'
$script:UpstreamRoot = if ([System.IO.Path]::IsPathRooted($UpstreamRoot)) {
    [System.IO.Path]::GetFullPath($UpstreamRoot)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $script:RepoRoot $UpstreamRoot))
}
$script:Catalog = $null
$script:AppName = 'Spicetify Plus'
$script:AppVersion = '2.0.0'
$script:UserAgent = 'Spicetify-Plus/2.0.0'
$script:LastSpicetifyExitCode = 0
$script:LastSpicetifyCommandSucceeded = $false
$script:LastApplySucceeded = $false
$Global:githubToken = ''

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message = 'OK')
    Write-Host $Message -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

function Wait-IfNeeded {
    if (-not $NoPause) {
        [void](Read-Host 'Press Enter to continue')
    }
}

function Confirm-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host "$Prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $Default
    }
    return ($answer -eq 'y' -or $answer -eq 'yes')
}

function Get-SpicetifyPlusConfigPath {
    $userName = $env:USERNAME
    $configDir = Join-Path $env:USERPROFILE "users\$userName\spicetify plus"
    if (-not (Test-Path -LiteralPath $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }
    return $configDir
}

function Get-GitHubTokenFilePath {
    return (Join-Path (Get-SpicetifyPlusConfigPath) 'github_token.txt')
}

function Import-GitHubToken {
    try {
        $path = Get-GitHubTokenFilePath
        if (Test-Path -LiteralPath $path) {
            $token = (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim()
            if (-not [string]::IsNullOrWhiteSpace($token)) {
                $env:GITHUB_TOKEN = $token
                return $token
            }
        }
    } catch {
        Write-Warn "Could not load GitHub token: $($_.Exception.Message)"
    }
    return ''
}

function Save-GitHubToken {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }

    $path = Get-GitHubTokenFilePath
    $Token.Trim() | Out-File -FilePath $path -Encoding UTF8 -Force
    $Global:githubToken = $Token.Trim()
    $env:GITHUB_TOKEN = $Global:githubToken
    return $true
}

function Remove-GitHubToken {
    $path = Get-GitHubTokenFilePath
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
    $Global:githubToken = ''
    $env:GITHUB_TOKEN = $null
}

function Get-GitHubHeaders {
    $headers = @{
        'User-Agent' = $script:UserAgent
        'Accept' = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    if (-not [string]::IsNullOrWhiteSpace($Global:githubToken)) {
        $headers['Authorization'] = "Bearer $Global:githubToken"
    }
    return $headers
}

function Invoke-GitHubApi {
    param([string]$Uri)

    try {
        return Invoke-RestMethod -Uri $Uri -Headers (Get-GitHubHeaders) -TimeoutSec 45 -ErrorAction Stop
    } catch {
        $message = $_.Exception.Message
        if ($message -like '*403*' -or $message -like '*rate limit*') {
            throw "GitHub API rate limit or access error for $Uri. Configure a token from the token menu. Details: $message"
        }
        throw
    }
}

function Get-Catalog {
    if (-not $script:Catalog) {
        if (-not (Test-Path -LiteralPath $script:CatalogPath)) {
            throw "Catalog file not found: $script:CatalogPath"
        }
        $script:Catalog = Get-Content -LiteralPath $script:CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $script:Catalog
}

function Get-SafeRepoName {
    param([string]$Repo)
    return ($Repo -replace '/', '__')
}

function Get-LocalRepoPath {
    param(
        [string]$Repo,
        [ValidateSet('spicetify', 'community')]
        [string]$Kind
    )
    return (Join-Path (Join-Path $script:UpstreamRoot $Kind) (Get-SafeRepoName $Repo))
}

function Test-PathUnderRoot {
    param(
        [string]$Path,
        [string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-TreeSafe {
    param(
        [string]$Path,
        [string]$AllowedRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    if (-not (Test-PathUnderRoot -Path $Path -Root $AllowedRoot)) {
        throw "Refusing to remove outside allowed root. Path=$Path Root=$AllowedRoot"
    }
    Remove-Item -LiteralPath $Path -Recurse -Force
}

function New-TempDirectory {
    param([string]$Name)
    $root = [System.IO.Path]::GetTempPath()
    $path = Join-Path $root ($Name + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Get-WindowsArchitectureName {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        return 'arm64'
    }
    if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') {
        return 'x64'
    }
    return 'x32'
}

function Select-ReleaseAsset {
    param(
        [object]$Release,
        [string]$Regex,
        [string]$Repo
    )

    foreach ($asset in @($Release.assets)) {
        if ($asset.name -match $Regex) {
            return $asset
        }
    }
    throw "No release asset matching '$Regex' found for $Repo release $($Release.tag_name)."
}

function Get-AssetSha256 {
    param([object]$Asset)

    if ($Asset.PSObject.Properties.Name -contains 'digest' -and $Asset.digest -match '^sha256:(.+)$') {
        return $matches[1]
    }
    return ''
}

function Invoke-DownloadFile {
    param(
        [string]$Uri,
        [string]$OutFile,
        [string]$Sha256 = ''
    )

    $dir = Split-Path -Parent $OutFile
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Write-Info "Downloading to $OutFile"
    $downloadUri = [uri]$Uri
    $headers = @{ 'User-Agent' = $script:UserAgent }
    if ($downloadUri.Host -in @('api.github.com', 'github.com')) {
        $headers = Get-GitHubHeaders
    }
    Invoke-WebRequest -Uri $Uri -Headers $headers -UseBasicParsing -OutFile $OutFile -TimeoutSec 120 -ErrorAction Stop

    $downloadedFile = Get-Item -LiteralPath $OutFile
    Write-Ok ("Download completed ({0:N2} MB)." -f ($downloadedFile.Length / 1MB))

    if (-not [string]::IsNullOrWhiteSpace($Sha256)) {
        Write-Info 'Verifying SHA256 checksum...'
        $actual = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $Sha256.ToLowerInvariant()) {
            throw "SHA256 mismatch for $Uri. Expected $Sha256, got $actual"
        }
        Write-Ok 'SHA256 checksum verified.'
    }
}

function Expand-ZipToDirectory {
    param(
        [string]$ZipFile,
        [string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        Remove-TreeSafe -Path $Destination -AllowedRoot ([System.IO.Path]::GetTempPath())
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Expand-Archive -LiteralPath $ZipFile -DestinationPath $Destination -Force
}

function Get-LatestRelease {
    param([string]$Repo)
    return Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases/latest"
}

function Select-TaggedReleaseAsset {
    param(
        [string]$Repo,
        [string]$TagRegex,
        [string]$AssetRegex
    )

    $releases = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/releases?per_page=50"
    foreach ($release in @($releases)) {
        if ($release.tag_name -match $TagRegex) {
            $asset = Select-ReleaseAsset -Release $release -Regex $AssetRegex -Repo $Repo
            return [pscustomobject]@{ Release = $release; Asset = $asset }
        }
    }
    throw "No release matching '$TagRegex' found for $Repo."
}

function Test-GitHubRef {
    param(
        [string]$Repo,
        [string]$Branch
    )
    [void](Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/git/ref/heads/$Branch")
}

function Test-GitHubPath {
    param(
        [string]$Repo,
        [string]$Ref,
        [string]$Path
    )
    [void](Invoke-GitHubApi -Uri "https://api.github.com/repos/$Repo/contents/$Path`?ref=$Ref")
}

function Resolve-CliAsset {
    $catalog = Get-Catalog
    $release = Get-LatestRelease -Repo $catalog.official.cli.repo
    $arch = Get-WindowsArchitectureName
    $regex = "windows-$([regex]::Escape($arch))\.zip$"
    $asset = Select-ReleaseAsset -Release $release -Regex $regex -Repo $catalog.official.cli.repo
    return [pscustomobject]@{
        Release = $release
        Asset = $asset
        Version = ($release.tag_name -replace '^v', '')
        Sha256 = Get-AssetSha256 -Asset $asset
    }
}

function Resolve-MarketplaceAsset {
    $catalog = Get-Catalog
    $release = Get-LatestRelease -Repo $catalog.official.marketplace.repo
    $asset = Select-ReleaseAsset -Release $release -Regex $catalog.official.marketplace.assetRegex -Repo $catalog.official.marketplace.repo
    return [pscustomobject]@{
        Release = $release
        Asset = $asset
        Version = ($release.tag_name -replace '^v', '')
        Sha256 = Get-AssetSha256 -Asset $asset
    }
}

function Resolve-CommunityApp {
    param([object]$App)

    try {
        $resolver = $App.resolver
        $downloadUrl = ''
        $sha256 = ''
        $releaseTag = ''
        $sourcePath = ''

        if ($resolver.type -eq 'latestReleaseAsset') {
            $release = Get-LatestRelease -Repo $App.repo
            $asset = Select-ReleaseAsset -Release $release -Regex $resolver.assetRegex -Repo $App.repo
            $downloadUrl = $asset.browser_download_url
            $sha256 = Get-AssetSha256 -Asset $asset
            $releaseTag = $release.tag_name
        } elseif ($resolver.type -eq 'taggedReleaseAsset') {
            $pair = Select-TaggedReleaseAsset -Repo $App.repo -TagRegex $resolver.tagRegex -AssetRegex $resolver.assetRegex
            $downloadUrl = $pair.Asset.browser_download_url
            $sha256 = Get-AssetSha256 -Asset $pair.Asset
            $releaseTag = $pair.Release.tag_name
        } elseif ($resolver.type -eq 'branchArchive') {
            Test-GitHubRef -Repo $App.repo -Branch $resolver.branch
            $downloadUrl = "https://github.com/$($App.repo)/archive/refs/heads/$($resolver.branch).zip"
            if ($resolver.PSObject.Properties.Name -contains 'path') {
                $sourcePath = [string]$resolver.path
            }
        } elseif ($resolver.type -eq 'repositoryPath') {
            Test-GitHubPath -Repo $App.repo -Ref $resolver.ref -Path $resolver.path
            $downloadUrl = "https://github.com/$($App.repo)/archive/refs/heads/$($resolver.ref).zip"
            $sourcePath = [string]$resolver.path
        } else {
            throw "Unknown resolver type '$($resolver.type)'."
        }

        $status = if ($App.status -eq 'deprecated') { 'Deprecated' } else { 'Available' }
        return [pscustomobject]@{
            Name = $App.name
            DisplayName = $App.displayName
            Repo = $App.repo
            InstallName = $App.installName
            Status = $status
            Reason = ''
            DownloadUrl = $downloadUrl
            Sha256 = $sha256
            ReleaseTag = $releaseTag
            SourcePath = $sourcePath
        }
    } catch {
        return [pscustomobject]@{
            Name = $App.name
            DisplayName = $App.displayName
            Repo = $App.repo
            InstallName = $App.installName
            Status = 'Unavailable'
            Reason = $_.Exception.Message
            DownloadUrl = ''
            Sha256 = ''
            ReleaseTag = ''
            SourcePath = ''
        }
    }
}

function Get-SpicetifyExecutablePath {
    $command = Get-Command -Name spicetify -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $localExe = Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'
    if (Test-Path -LiteralPath $localExe) {
        return $localExe
    }

    return ''
}

function Invoke-Spicetify {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $spicetifyExe = Get-SpicetifyExecutablePath
    if ([string]::IsNullOrWhiteSpace($spicetifyExe)) {
        Write-Warn 'Spicetify is not installed or could not be found.'
        $script:LastSpicetifyExitCode = 127
        return
    }

    $spicetifyArgs = @()
    if ($BypassAdmin) {
        $spicetifyArgs += '--bypass-admin'
    }
    $spicetifyArgs += $Arguments

    # Keep native stdout attached to the console. Spicetify's interactive
    # spinners can stop early when their output is redirected through a pipeline.
    & $spicetifyExe @spicetifyArgs
    $script:LastSpicetifyExitCode = $LASTEXITCODE
}

function Invoke-SpicetifyWithOutput {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $spicetifyExe = Get-SpicetifyExecutablePath
    if ([string]::IsNullOrWhiteSpace($spicetifyExe)) {
        return [pscustomobject]@{
            Output = 'Spicetify is not installed or could not be found.'
            ExitCode = 127
        }
    }

    $spicetifyArgs = @()
    if ($BypassAdmin) {
        $spicetifyArgs += '--bypass-admin'
    }
    $spicetifyArgs += $Arguments
    $output = (& $spicetifyExe @spicetifyArgs 2>&1 | Out-String).Trim()
    return [pscustomobject]@{
        Output = $output
        ExitCode = $LASTEXITCODE
    }
}

function Test-SpicetifyCommand {
    return -not [string]::IsNullOrWhiteSpace((Get-SpicetifyExecutablePath))
}

function Invoke-SpicetifyMenuCommand {
    param(
        [string[]]$Arguments,
        [string]$SuccessMessage = 'Command finished.'
    )

    $script:LastSpicetifyCommandSucceeded = $false
    if (-not (Test-SpicetifyCommand)) {
        Write-Warn 'Spicetify is not installed.'
        return
    }

    Write-Info "Running: spicetify $($Arguments -join ' ')"
    Invoke-Spicetify @Arguments
    $code = $script:LastSpicetifyExitCode
    if ($code -eq 0) {
        Write-Ok $SuccessMessage
        $script:LastSpicetifyCommandSucceeded = $true
        return
    }

    Write-Warn "Spicetify exited with code $code. Check the output above."
}

function Get-SpicetifyConfigValue {
    param([string]$Key)

    if (-not (Test-SpicetifyCommand)) {
        return @()
    }

    $result = Invoke-SpicetifyWithOutput 'config' $Key
    if ($result.ExitCode -ne 0) {
        return @()
    }

    $text = $result.Output.Trim()
    if ($text -match '=\s*(.*)$') {
        $text = $matches[1].Trim()
    } elseif ($text -match "^\s*$([regex]::Escape($Key))\s+(.+)$") {
        $text = $matches[1].Trim()
    }

    if ([string]::IsNullOrWhiteSpace($text) -or $text -eq $Key) {
        return @()
    }

    return @($text -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Invoke-SafeSpicetifyBackupApply {
    $script:LastApplySucceeded = $false
    if (-not (Test-SpicetifyCommand)) {
        Write-Warn 'Spicetify is not installed.'
        return
    }

    Write-Info 'Running: spicetify apply'
    Invoke-Spicetify 'apply'
    $code = $script:LastSpicetifyExitCode
    if ($code -eq 0) {
        Write-Ok 'Spicetify changes applied.'
        $script:LastApplySucceeded = $true
        return
    }

    Write-Warn "Apply exited with code $code. A usable backup may not exist yet."
    Write-Info 'Running fallback: spicetify backup apply'
    Invoke-Spicetify 'backup' 'apply'
    $code = $script:LastSpicetifyExitCode
    if ($code -eq 0) {
        Write-Ok 'Spicetify backup was created and changes were applied.'
        $script:LastApplySucceeded = $true
        return
    }

    Write-Warn "Backup & Apply exited with code $code. Check the Spicetify output above."
    Write-Warn 'If it reports an outdated or modified backup, use Restore Spotify to Original, then run Backup & Apply again.'
}

function Request-SpicetifyBackupApply {
    param(
        [string]$Prompt = 'Apply Spicetify changes now with spicetify backup apply?'
    )

    $script:LastApplySucceeded = $false
    if (Confirm-YesNo -Prompt $Prompt -Default $true) {
        Invoke-SafeSpicetifyBackupApply
        return
    }

    Write-Info 'Install/configuration finished. Run Backup & Apply later to activate changes in Spotify.'
}

function Add-SpicetifyToPath {
    param([string]$Folder)

    $target = [EnvironmentVariableTarget]::User
    $path = [Environment]::GetEnvironmentVariable('PATH', $target)
    if ($path -notlike "*$Folder*") {
        $newPath = if ([string]::IsNullOrWhiteSpace($path)) { $Folder } else { "$path;$Folder" }
        [Environment]::SetEnvironmentVariable('PATH', $newPath, $target)
        $env:PATH = "$env:PATH;$Folder"
    }
}

function Install-Spicetify {
    param(
        [switch]$Force,
        [switch]$SkipApply
    )

    if ((Test-SpicetifyCommand) -and -not $Force) {
        Write-Ok 'Spicetify is already installed.'
        Write-Info 'Use Update Spicetify if you want to refresh the CLI.'
        if (-not $SkipApply) {
            Request-SpicetifyBackupApply -Prompt 'Spicetify is already installed. Apply it to Spotify now?'
        }
        return
    }

    $resolved = Resolve-CliAsset
    $installRoot = Join-Path $env:LOCALAPPDATA 'spicetify'
    $tempRoot = New-TempDirectory -Name 'spicetify-cli'
    $zipPath = Join-Path $tempRoot 'spicetify.zip'

    try {
        Write-Info "Downloading Spicetify CLI $($resolved.Release.tag_name) for Windows..."
        Invoke-DownloadFile -Uri $resolved.Asset.browser_download_url -OutFile $zipPath -Sha256 $resolved.Sha256

        if (-not (Test-Path -LiteralPath $installRoot)) {
            New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        }

        Write-Info "Extracting to $installRoot"
        Expand-Archive -LiteralPath $zipPath -DestinationPath $installRoot -Force
        Write-Ok 'Spicetify CLI files extracted.'
        Add-SpicetifyToPath -Folder $installRoot
        Write-Ok "Spicetify CLI $($resolved.Release.tag_name) installed."
        if (-not $SkipApply) {
            Request-SpicetifyBackupApply -Prompt 'Spicetify CLI is installed. Apply it to Spotify now?'
        }
    } finally {
        Remove-TreeSafe -Path $tempRoot -AllowedRoot ([System.IO.Path]::GetTempPath())
    }
}

function Update-Spicetify {
    if (-not (Test-SpicetifyCommand)) {
        Write-Warn 'Spicetify is not installed. Install it first.'
        return
    }

    $configPath = Join-Path $env:APPDATA 'spicetify\config-xpui.ini'
    $tempRoot = New-TempDirectory -Name 'spicetify-config-backup'
    $backupPath = Join-Path $tempRoot 'config-xpui.ini'

    try {
        if (Test-Path -LiteralPath $configPath) {
            Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
        }

        Install-Spicetify -Force -SkipApply

        if (Test-Path -LiteralPath $backupPath) {
            $configDir = Split-Path -Parent $configPath
            if (-not (Test-Path -LiteralPath $configDir)) {
                New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $backupPath -Destination $configPath -Force
        }
        Request-SpicetifyBackupApply -Prompt 'Spicetify was updated. Apply current configuration to Spotify now?'
    } finally {
        Remove-TreeSafe -Path $tempRoot -AllowedRoot ([System.IO.Path]::GetTempPath())
    }
}

function Install-Marketplace {
    if (-not (Test-SpicetifyCommand)) {
        Write-Warn 'Spicetify is not installed. Installing Spicetify first.'
        Install-Spicetify -SkipApply
    }
    if (-not (Test-SpicetifyCommand)) {
        throw 'Spicetify CLI could not be found after installation. Cannot install Marketplace.'
    }

    $resolved = Resolve-MarketplaceAsset
    $pathResult = Invoke-SpicetifyWithOutput 'path' 'userdata'
    if ($pathResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($pathResult.Output)) {
        throw "Could not resolve Spicetify userdata path. $($pathResult.Output)"
    }

    $userData = $pathResult.Output.Trim()
    if (-not (Test-Path -LiteralPath $userData -PathType Container)) {
        $userData = Join-Path $env:APPDATA 'spicetify'
    }

    $marketAppPath = Join-Path $userData 'CustomApps\marketplace'
    $marketThemePath = Join-Path $userData 'Themes\marketplace'
    $tempRoot = New-TempDirectory -Name 'spicetify-marketplace'
    $zipPath = Join-Path $tempRoot 'marketplace.zip'
    $extractPath = Join-Path $tempRoot 'extract'

    try {
        Write-Info "Downloading Marketplace $($resolved.Release.tag_name)..."
        Invoke-DownloadFile -Uri $resolved.Asset.browser_download_url -OutFile $zipPath -Sha256 $resolved.Sha256

        $customAppsRoot = Split-Path -Parent $marketAppPath
        $themesRoot = Split-Path -Parent $marketThemePath
        New-Item -ItemType Directory -Path $customAppsRoot, $themesRoot -Force | Out-Null
        Remove-TreeSafe -Path $marketAppPath -AllowedRoot $customAppsRoot
        Remove-TreeSafe -Path $marketThemePath -AllowedRoot $themesRoot
        New-Item -ItemType Directory -Path $marketAppPath, $marketThemePath -Force | Out-Null

        Write-Info 'Extracting Marketplace package...'
        Expand-ZipToDirectory -ZipFile $zipPath -Destination $extractPath
        $distPath = Join-Path $extractPath 'marketplace-dist'
        if (-not (Test-Path -LiteralPath $distPath)) {
            throw 'Marketplace zip did not contain marketplace-dist.'
        }
        Write-Info 'Copying Marketplace files...'
        Copy-Item -Path (Join-Path $distPath '*') -Destination $marketAppPath -Recurse -Force

        Write-Info 'Updating Spicetify Marketplace configuration...'
        Invoke-Spicetify 'config' 'custom_apps' 'spicetify-marketplace-' '-q'
        Invoke-Spicetify 'config' 'custom_apps' 'marketplace'
        Invoke-Spicetify 'config' 'inject_css' '1' 'replace_colors' '1'

        $catalog = Get-Catalog
        Invoke-DownloadFile -Uri $catalog.official.marketplace.placeholderColorUrl -OutFile (Join-Path $marketThemePath 'color.ini')

        $currentTheme = (Invoke-SpicetifyWithOutput 'config' 'current_theme').Output.Trim()
        $setTheme = $true
        if (-not [string]::IsNullOrWhiteSpace($currentTheme) -and $currentTheme -ne 'marketplace') {
            $setTheme = Confirm-YesNo -Prompt "Current theme is '$currentTheme'. Replace it with Marketplace placeholder?" -Default $false
        }
        if ($setTheme) {
            Invoke-Spicetify 'config' 'current_theme' 'marketplace'
        }

        Request-SpicetifyBackupApply -Prompt 'Marketplace is installed. Apply it to Spotify now?'
        if (-not $script:LastApplySucceeded) {
            Write-Warn 'Marketplace files/config were installed, but Spotify was not patched yet.'
            Write-Warn 'Run Settings -> Backup & Apply Changes to activate Marketplace in Spotify.'
            return
        }
        Write-Ok 'Marketplace installed and applied. Restart Spotify if the sidebar item is not visible.'
    } finally {
        Remove-TreeSafe -Path $tempRoot -AllowedRoot ([System.IO.Path]::GetTempPath())
    }
}

function Test-SpotifyInstalled {
    $desktop = $false
    foreach ($regPath in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        if (Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Spotify*' }) {
            $desktop = $true
        }
    }
    if (Test-Path -LiteralPath (Join-Path $env:APPDATA 'Spotify\Spotify.exe')) {
        $desktop = $true
    }
    $store = Get-AppxPackage -Name '*SpotifyMusic*' -ErrorAction SilentlyContinue
    return ($desktop -or $store)
}

function Test-SpotifyRunning {
    return [bool](Get-Process -Name Spotify -ErrorAction SilentlyContinue)
}

function Wait-SpotifyInstaller {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 180
    )

    $startedAt = Get-Date
    $deadline = $startedAt.AddSeconds($TimeoutSeconds)
    $nextStatusAt = $startedAt.AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        if ($Process.HasExited) {
            return 'Exited'
        }
        if (Test-SpotifyInstalled) {
            return 'Installed'
        }
        if (Test-SpotifyRunning) {
            return 'Running'
        }
        if ((Get-Date) -ge $nextStatusAt) {
            $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
            Write-Info "Spotify installer is still running (${elapsed}s elapsed)..."
            $nextStatusAt = (Get-Date).AddSeconds(10)
        }
        Start-Sleep -Seconds 2
    }

    if ($Process.HasExited) {
        return 'Exited'
    }
    if (Test-SpotifyInstalled) {
        return 'Installed'
    }
    if (Test-SpotifyRunning) {
        return 'Running'
    }
    return 'Timeout'
}

function Install-Spotify {
    if (Test-SpotifyInstalled) {
        Write-Ok 'Spotify is already installed.'
        return
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if (Confirm-YesNo -Prompt 'Install Spotify with winget first?' -Default $true) {
            winget install --id Spotify.Spotify --source winget --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -eq 0) {
                Write-Ok 'Spotify installed with winget.'
                return
            }
            Write-Warn 'winget install failed; falling back to SpotifySetup.exe.'
        }
    }

    $tempRoot = New-TempDirectory -Name 'spotify-setup'
    $installer = Join-Path $tempRoot 'SpotifySetup.exe'
    try {
        Write-Info 'Downloading SpotifySetup.exe...'
        Invoke-DownloadFile -Uri 'https://download.spotify.com/SpotifySetup.exe' -OutFile $installer
        Write-Info 'Starting Spotify installer. Waiting for install detection, not for Spotify to close...'
        $process = Start-Process -FilePath $installer -ArgumentList '/SILENT' -PassThru
        $state = Wait-SpotifyInstaller -Process $process -TimeoutSeconds 180
        if ($state -eq 'Timeout') {
            Write-Warn 'Spotify installer is still running after 180 seconds. It may need user action in the Spotify window.'
            Write-Warn 'The menu will continue; close Spotify or rerun Install Spotify later if installation did not complete.'
            return
        }
        if (Test-SpotifyInstalled -or (Test-SpotifyRunning)) {
            Write-Ok "Spotify installer state: $state. Spotify appears installed or running."
            return
        }
        Write-Ok "Spotify installer finished with state: $state."
    } finally {
        try {
            Remove-TreeSafe -Path $tempRoot -AllowedRoot ([System.IO.Path]::GetTempPath())
        } catch {
            Write-Warn "Could not remove temporary Spotify installer folder yet: $($_.Exception.Message)"
        }
    }
}

function Update-Spotify {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget upgrade --id Spotify.Spotify --source winget --accept-package-agreements --accept-source-agreements
        return
    }
    Write-Info 'Spotify desktop usually updates itself after restart.'
    Write-Info 'If needed, remove and reinstall Spotify from this menu.'
}

function Remove-Spotify {
    Write-Warn 'This removes Spotify. It does not run during self-test or validation.'
    $confirm = Read-Host 'Type REMOVE SPOTIFY to continue'
    if ($confirm -ne 'REMOVE SPOTIFY') {
        Write-Warn 'Cancelled.'
        return
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget uninstall --id Spotify.Spotify --source winget
    }

    $appx = Get-AppxPackage -Name '*SpotifyMusic*' -ErrorAction SilentlyContinue
    if ($appx) {
        $appx | Remove-AppxPackage
    }
    Write-Ok 'Spotify uninstall commands finished.'
}

function Remove-Spicetify {
    Write-Warn 'This removes the local Spicetify CLI folder. User config is preserved unless you explicitly remove it yourself.'
    $confirm = Read-Host 'Type REMOVE SPICETIFY to continue'
    if ($confirm -ne 'REMOVE SPICETIFY') {
        Write-Warn 'Cancelled.'
        return
    }

    if (Test-SpicetifyCommand) {
        Invoke-Spicetify 'restore'
    }
    $installRoot = Join-Path $env:LOCALAPPDATA 'spicetify'
    Remove-TreeSafe -Path $installRoot -AllowedRoot $env:LOCALAPPDATA
    Write-Ok 'Spicetify CLI folder removed.'
}

function Get-OfficialExtensions {
    $catalog = Get-Catalog
    $local = Join-Path (Get-LocalRepoPath -Repo $catalog.official.cli.repo -Kind 'spicetify') $catalog.official.cli.extensionsPath
    if (Test-Path -LiteralPath $local) {
        return @(Get-ChildItem -LiteralPath $local -Filter '*.js' -File | Sort-Object Name | ForEach-Object { $_.Name })
    }

    $items = Invoke-GitHubApi -Uri "https://api.github.com/repos/$($catalog.official.cli.repo)/contents/$($catalog.official.cli.extensionsPath)?ref=main"
    return @($items | Where-Object { $_.type -eq 'file' -and $_.name -like '*.js' } | Sort-Object name | ForEach-Object { $_.name })
}

function Get-OfficialBuiltInCustomApps {
    $catalog = Get-Catalog
    return @($catalog.official.builtInCustomApps)
}

function Request-ApplyAfterChange {
    if (Confirm-YesNo -Prompt 'Apply changes now with spicetify backup apply?' -Default $true) {
        Invoke-SafeSpicetifyBackupApply
    } else {
        Write-Info 'Changes are configured. Run Backup & Apply later to activate them.'
    }
}

function Find-AppSourcePath {
    param(
        [string]$ExtractRoot,
        [string]$InstallName,
        [string]$RelativePath = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($RelativePath)) {
        $direct = Join-Path $ExtractRoot $RelativePath
        if (Test-Path -LiteralPath (Join-Path $direct 'manifest.json')) {
            return $direct
        }
        $rootDir = Get-ChildItem -LiteralPath $ExtractRoot -Directory | Select-Object -First 1
        if ($rootDir) {
            $nested = Join-Path $rootDir.FullName $RelativePath
            if (Test-Path -LiteralPath (Join-Path $nested 'manifest.json')) {
                return $nested
            }
        }
    }

    if ((Test-Path -LiteralPath (Join-Path $ExtractRoot 'manifest.json')) -and (Test-Path -LiteralPath (Join-Path $ExtractRoot 'index.js'))) {
        return $ExtractRoot
    }

    $manifestDirs = @(Get-ChildItem -LiteralPath $ExtractRoot -Recurse -Filter 'manifest.json' -File | ForEach-Object { $_.Directory.FullName })
    foreach ($dir in $manifestDirs) {
        if ((Split-Path -Leaf $dir) -eq $InstallName -and (Test-Path -LiteralPath (Join-Path $dir 'index.js'))) {
            return $dir
        }
    }
    foreach ($dir in $manifestDirs) {
        if (Test-Path -LiteralPath (Join-Path $dir 'index.js')) {
            return $dir
        }
    }
    throw "Could not find a custom app folder with manifest.json and index.js in $ExtractRoot."
}

function Install-CommunityApp {
    param([object]$App)

    $resolved = Resolve-CommunityApp -App $App
    if ($resolved.Status -eq 'Unavailable') {
        Write-Fail "Unavailable: $($resolved.Reason)"
        return
    }
    if ($resolved.Status -eq 'Deprecated') {
        Write-Warn "$($App.displayName) is deprecated. Repo: $($App.repo)"
        if (-not (Confirm-YesNo -Prompt 'Install deprecated app anyway?' -Default $false)) {
            return
        }
    }

    $customAppsRoot = Join-Path $env:APPDATA 'spicetify\CustomApps'
    $target = Join-Path $customAppsRoot $resolved.InstallName
    $tempRoot = New-TempDirectory -Name "spicetify-app-$($resolved.InstallName)"
    $zipPath = Join-Path $tempRoot 'source.zip'
    $extractRoot = Join-Path $tempRoot 'extract'

    try {
        New-Item -ItemType Directory -Path $customAppsRoot -Force | Out-Null
        Write-Info "Downloading $($App.displayName) from $($App.repo)..."
        Invoke-DownloadFile -Uri $resolved.DownloadUrl -OutFile $zipPath -Sha256 $resolved.Sha256
        Write-Info "Extracting $($App.displayName)..."
        Expand-ZipToDirectory -ZipFile $zipPath -Destination $extractRoot

        $source = Find-AppSourcePath -ExtractRoot $extractRoot -InstallName $resolved.InstallName -RelativePath $resolved.SourcePath
        Remove-TreeSafe -Path $target -AllowedRoot $customAppsRoot
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Write-Info "Copying files to $target"
        Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force

        Write-Info "Adding $($resolved.InstallName) to Spicetify configuration..."
        Invoke-Spicetify 'config' 'custom_apps' $resolved.InstallName
        Write-Ok "$($App.displayName) installed and configured."
        Request-ApplyAfterChange
    } finally {
        Remove-TreeSafe -Path $tempRoot -AllowedRoot ([System.IO.Path]::GetTempPath())
    }
}

function Show-ExtensionsMenu {
    while ($true) {
        Clear-Host
        Write-Host '--- Extensions ---' -ForegroundColor Yellow
        $current = @(Get-SpicetifyConfigValue -Key 'extensions')
        Write-Host "Current: $(if ($current.Count) { $current -join ' | ' } else { '(none)' })"
        Write-Host '[1] Install built-in extension'
        Write-Host '[2] Remove extension'
        Write-Host '[3] Clear extensions'
        Write-Host '[0] Back'
        $choice = Read-Host 'Choose'

        if ($choice -eq '0') { return }
        if ($choice -eq '1') {
            $extensions = @(Get-OfficialExtensions)
            for ($i = 0; $i -lt $extensions.Count; $i++) {
                Write-Host "[$($i + 1)] $($extensions[$i])"
            }
            $selection = Read-Host 'Extension number'
            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $extensions.Count) {
                $name = $extensions[[int]$selection - 1]
                Invoke-Spicetify 'config' 'extensions' $name
                Write-Ok "Configured $name."
                Request-ApplyAfterChange
            }
            Wait-IfNeeded
        } elseif ($choice -eq '2') {
            if (-not $current.Count) { Write-Warn 'No extensions configured.'; Wait-IfNeeded; continue }
            for ($i = 0; $i -lt $current.Count; $i++) { Write-Host "[$($i + 1)] $($current[$i])" }
            $selection = Read-Host 'Extension number to remove'
            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $current.Count) {
                $name = $current[[int]$selection - 1]
                Invoke-Spicetify 'config' 'extensions' "$name-"
                Write-Ok "Removed $name from config."
                Request-ApplyAfterChange
            }
            Wait-IfNeeded
        } elseif ($choice -eq '3') {
            foreach ($name in $current) {
                Invoke-Spicetify 'config' 'extensions' "$name-"
            }
            Write-Ok 'Extensions cleared from config.'
            Request-ApplyAfterChange
            Wait-IfNeeded
        }
    }
}

function Show-CustomAppsMenu {
    $catalog = Get-Catalog
    while ($true) {
        Clear-Host
        Write-Host '--- Custom Apps ---' -ForegroundColor Yellow
        $current = @(Get-SpicetifyConfigValue -Key 'custom_apps')
        Write-Host "Current: $(if ($current.Count) { $current -join ' | ' } else { '(none)' })"
        Write-Host '[1] Install built-in custom app'
        Write-Host '[2] Install community custom app'
        Write-Host '[3] Remove custom app'
        Write-Host '[4] List community app status'
        Write-Host '[0] Back'
        $choice = Read-Host 'Choose'

        if ($choice -eq '0') { return }
        if ($choice -eq '1') {
            $apps = @(Get-OfficialBuiltInCustomApps)
            for ($i = 0; $i -lt $apps.Count; $i++) {
                Write-Host "[$($i + 1)] $($apps[$i].name) - $($apps[$i].description)"
            }
            $selection = Read-Host 'App number'
            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $apps.Count) {
                $app = $apps[[int]$selection - 1]
                Invoke-Spicetify 'config' 'custom_apps' $app.name
                Write-Ok "Configured $($app.name)."
                Request-ApplyAfterChange
            }
            Wait-IfNeeded
        } elseif ($choice -eq '2') {
            $apps = @($catalog.communityApps)
            for ($i = 0; $i -lt $apps.Count; $i++) {
                $marker = if ($apps[$i].status -eq 'deprecated') { ' [Deprecated]' } else { '' }
                Write-Host "[$($i + 1)] $($apps[$i].name)$marker - $($apps[$i].description)"
            }
            $selection = Read-Host 'App number'
            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $apps.Count) {
                Install-CommunityApp -App $apps[[int]$selection - 1]
            }
            Wait-IfNeeded
        } elseif ($choice -eq '3') {
            if (-not $current.Count) { Write-Warn 'No custom apps configured.'; Wait-IfNeeded; continue }
            for ($i = 0; $i -lt $current.Count; $i++) { Write-Host "[$($i + 1)] $($current[$i])" }
            $selection = Read-Host 'App number to remove'
            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $current.Count) {
                $name = $current[[int]$selection - 1]
                Invoke-Spicetify 'config' 'custom_apps' "$name-"
                Write-Ok "Removed $name from config."
                Request-ApplyAfterChange
            }
            Wait-IfNeeded
        } elseif ($choice -eq '4') {
            foreach ($app in @($catalog.communityApps)) {
                $resolved = Resolve-CommunityApp -App $app
                $line = "{0,-24} {1,-12} {2}" -f $resolved.Name, $resolved.Status, $resolved.Repo
                if ($resolved.Status -eq 'Unavailable') {
                    Write-Fail "$line - $($resolved.Reason)"
                } elseif ($resolved.Status -eq 'Deprecated') {
                    Write-Warn $line
                } else {
                    Write-Ok $line
                }
            }
            Wait-IfNeeded
        }
    }
}

function Get-AvailableThemes {
    $catalog = Get-Catalog
    $root = Get-LocalRepoPath -Repo $catalog.official.themes.repo -Kind 'spicetify'
    if (-not (Test-Path -LiteralPath $root)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $root -Directory | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'color.ini')) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'user.css'))
    } | Sort-Object Name)
}

function Get-ColorSchemes {
    param([string]$ColorIni)
    if (-not (Test-Path -LiteralPath $ColorIni)) {
        return @()
    }
    return @(Select-String -LiteralPath $ColorIni -Pattern '^\s*\[([^\]]+)\]' | ForEach-Object { $_.Matches[0].Groups[1].Value })
}

function Show-ThemesMenu {
    while ($true) {
        Clear-Host
        Write-Host '--- Themes ---' -ForegroundColor Yellow
        Write-Host '[1] Install theme from .upstream'
        Write-Host '[2] Refresh upstream references'
        Write-Host '[3] Clear current theme'
        Write-Host '[0] Back'
        $choice = Read-Host 'Choose'

        if ($choice -eq '0') { return }
        if ($choice -eq '2') {
            Update-UpstreamReferences
            Wait-IfNeeded
            continue
        }
        if ($choice -eq '3') {
            Invoke-Spicetify 'config' 'current_theme' ''
            Request-ApplyAfterChange
            Wait-IfNeeded
            continue
        }
        if ($choice -eq '1') {
            $themes = @(Get-AvailableThemes)
            if (-not $themes.Count) {
                Write-Warn 'No local themes found. Run Refresh Upstream References first.'
                Wait-IfNeeded
                continue
            }
            for ($i = 0; $i -lt $themes.Count; $i++) {
                Write-Host "[$($i + 1)] $($themes[$i].Name)"
            }
            $selection = Read-Host 'Theme number'
            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $themes.Count) {
                $theme = $themes[[int]$selection - 1]
                $themeRoot = Join-Path $env:APPDATA 'spicetify\Themes'
                $target = Join-Path $themeRoot $theme.Name
                New-Item -ItemType Directory -Path $themeRoot -Force | Out-Null
                Remove-TreeSafe -Path $target -AllowedRoot $themeRoot
                Copy-Item -LiteralPath $theme.FullName -Destination $target -Recurse -Force
                Invoke-Spicetify 'config' 'current_theme' $theme.Name

                $schemes = @(Get-ColorSchemes -ColorIni (Join-Path $target 'color.ini'))
                if ($schemes.Count -gt 0) {
                    Write-Host "Color schemes: $($schemes -join ', ')"
                    $scheme = Read-Host 'Color scheme (blank to keep current/default)'
                    if (-not [string]::IsNullOrWhiteSpace($scheme)) {
                        Invoke-Spicetify 'config' 'color_scheme' $scheme
                    }
                }
                Write-Ok "Configured theme $($theme.Name)."
                Request-ApplyAfterChange
            }
            Wait-IfNeeded
        }
    }
}

function Show-ConfigSettingsMenu {
    $toggles = @(
        'inject_css',
        'inject_theme_js',
        'replace_colors',
        'overwrite_assets',
        'always_enable_devtools',
        'check_spicetify_update',
        'disable_sentry',
        'disable_ui_logging',
        'remove_rtl_rule',
        'expose_apis',
        'experimental_features',
        'home_config',
        'sidebar_config'
    )
    while ($true) {
        Clear-Host
        Write-Host '--- Config Settings ---' -ForegroundColor Yellow
        for ($i = 0; $i -lt $toggles.Count; $i++) {
            $value = @(Get-SpicetifyConfigValue -Key $toggles[$i]) -join '|'
            if ([string]::IsNullOrWhiteSpace($value)) { $value = '(blank)' }
            Write-Host "[$($i + 1)] $($toggles[$i]) = $value"
        }
        Write-Host '[0] Back'
        $selection = Read-Host 'Setting number'
        if ($selection -eq '0') { return }
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $toggles.Count) {
            $key = $toggles[[int]$selection - 1]
            $value = Read-Host "New value for $key"
            Invoke-Spicetify 'config' $key $value
            Write-Ok "Set $key."
            Request-ApplyAfterChange
            Wait-IfNeeded
        }
    }
}

function Show-LaunchFlagsMenu {
    while ($true) {
        Clear-Host
        Write-Host '--- Spotify Launch Flags ---' -ForegroundColor Yellow
        $flags = @(Get-SpicetifyConfigValue -Key 'spotify_launch_flags')
        Write-Host "Current: $(if ($flags.Count) { $flags -join ' | ' } else { '(none)' })"
        Write-Warn 'Current Spicetify CLI exposes this field but does not write it via "spicetify config".'
        Write-Warn 'This menu is read-only until upstream supports changing spotify_launch_flags through the CLI.'
        Write-Host '[0] Back'
        $choice = Read-Host 'Choose'
        if ($choice -eq '0') { return }
    }
}

function Clear-SpicetifyBackup {
    Write-Warn 'This clears Spicetify backup files. Restore Spotify first if it is currently modified.'
    $confirm = Read-Host 'Type CLEAR BACKUP to continue'
    if ($confirm -ne 'CLEAR BACKUP') {
        Write-Warn 'Cancelled.'
        return
    }

    Invoke-SpicetifyMenuCommand -Arguments @('clear') -SuccessMessage 'Backup files cleared.'
}

function Show-SpotifyUpdateBlockingMenu {
    while ($true) {
        Clear-Host
        Write-Host '--- Spotify Updates ---' -ForegroundColor Yellow
        Write-Host '[1] Block Spotify updates'
        Write-Host '[2] Unblock Spotify updates'
        Write-Host '[0] Back'
        $choice = Read-Host 'Choose'
        if ($choice -eq '0') { return }

        if ($choice -eq '1') {
            if (Confirm-YesNo -Prompt 'Patch Spotify executable to block updates?' -Default $false) {
                Invoke-SpicetifyMenuCommand -Arguments @('spotify-updates', 'block') -SuccessMessage 'Spotify updates blocked.'
                Wait-IfNeeded
            }
        } elseif ($choice -eq '2') {
            if (Confirm-YesNo -Prompt 'Unblock Spotify updates?' -Default $true) {
                Invoke-SpicetifyMenuCommand -Arguments @('spotify-updates', 'unblock') -SuccessMessage 'Spotify updates unblocked.'
                Wait-IfNeeded
            }
        }
    }
}

function Show-RefreshWatchMenu {
    while ($true) {
        Clear-Host
        Write-Host '--- Refresh & Watch ---' -ForegroundColor Yellow
        Write-Host '[1] Refresh active theme'
        Write-Host '[2] Refresh extensions'
        Write-Host '[3] Refresh custom apps'
        Write-Host '[4] Watch active theme'
        Write-Host '[5] Watch extensions'
        Write-Host '[6] Watch custom apps'
        Write-Host '[7] Watch all with live refresh'
        Write-Host '[0] Back'
        $choice = Read-Host 'Choose'
        if ($choice -eq '0') { return }

        switch ($choice) {
            '1' { Invoke-SpicetifyMenuCommand -Arguments @('refresh') -SuccessMessage 'Active theme refreshed.'; Wait-IfNeeded }
            '2' { Invoke-SpicetifyMenuCommand -Arguments @('-e', 'refresh') -SuccessMessage 'Extensions refreshed.'; Wait-IfNeeded }
            '3' { Invoke-SpicetifyMenuCommand -Arguments @('-a', 'refresh') -SuccessMessage 'Custom apps refreshed.'; Wait-IfNeeded }
            '4' {
                Write-Warn 'Watch mode keeps running until you stop it with Ctrl+C.'
                if (Confirm-YesNo -Prompt 'Start watch mode for active theme?' -Default $false) {
                    Invoke-SpicetifyMenuCommand -Arguments @('-s', 'watch') -SuccessMessage 'Watch mode ended.'
                }
                Wait-IfNeeded
            }
            '5' {
                Write-Warn 'Watch mode keeps running until you stop it with Ctrl+C.'
                if (Confirm-YesNo -Prompt 'Start watch mode for extensions?' -Default $false) {
                    Invoke-SpicetifyMenuCommand -Arguments @('-e', 'watch') -SuccessMessage 'Watch mode ended.'
                }
                Wait-IfNeeded
            }
            '6' {
                Write-Warn 'Watch mode keeps running until you stop it with Ctrl+C.'
                if (Confirm-YesNo -Prompt 'Start watch mode for custom apps?' -Default $false) {
                    Invoke-SpicetifyMenuCommand -Arguments @('-a', 'watch') -SuccessMessage 'Watch mode ended.'
                }
                Wait-IfNeeded
            }
            '7' {
                Write-Warn 'Watch mode keeps running until you stop it with Ctrl+C.'
                if (Confirm-YesNo -Prompt 'Start watch mode for theme, extensions, and custom apps?' -Default $false) {
                    Invoke-SpicetifyMenuCommand -Arguments @('-l', 'watch') -SuccessMessage 'Watch mode ended.'
                }
                Wait-IfNeeded
            }
        }
    }
}

function Request-RefreshAfterColorChange {
    if (Confirm-YesNo -Prompt 'Refresh active theme now with spicetify refresh?' -Default $true) {
        Invoke-SpicetifyMenuCommand -Arguments @('refresh') -SuccessMessage 'Active theme refreshed.'
    } else {
        Write-Info 'Color change is saved. Run Refresh active theme later to apply it.'
    }
}

function Show-ThemeColorsMenu {
    while ($true) {
        Clear-Host
        Write-Host '--- Theme Colors ---' -ForegroundColor Yellow
        Write-Host '[1] View current theme colors'
        Write-Host '[2] Change one color'
        Write-Host '[3] Change multiple colors'
        Write-Host '[0] Back'
        $choice = Read-Host 'Choose'
        if ($choice -eq '0') { return }

        if ($choice -eq '1') {
            Invoke-SpicetifyMenuCommand -Arguments @('color') -SuccessMessage 'Colors listed.'
            Wait-IfNeeded
        } elseif ($choice -eq '2') {
            $field = Read-Host 'Color field'
            $value = Read-Host 'Value (hex or r,g,b)'
            if ([string]::IsNullOrWhiteSpace($field) -or [string]::IsNullOrWhiteSpace($value)) {
                Write-Warn 'Field and value are required.'
                Wait-IfNeeded
                continue
            }
            Invoke-SpicetifyMenuCommand -Arguments @('color', $field, $value) -SuccessMessage "Color $field updated."
            if ($script:LastSpicetifyCommandSucceeded) {
                Request-RefreshAfterColorChange
            }
            Wait-IfNeeded
        } elseif ($choice -eq '3') {
            $raw = Read-Host 'Enter pairs: field value field value'
            $parts = @($raw -split '\s+' | Where-Object { $_ })
            if ($parts.Count -eq 0 -or ($parts.Count % 2) -ne 0) {
                Write-Warn 'Enter an even number of values, for example: main ff0000 sidebar 00ff00'
                Wait-IfNeeded
                continue
            }
            $arguments = @('color') + $parts
            Invoke-SpicetifyMenuCommand -Arguments $arguments -SuccessMessage 'Colors updated.'
            if ($script:LastSpicetifyCommandSucceeded) {
                Request-RefreshAfterColorChange
            }
            Wait-IfNeeded
        }
    }
}

function Show-PathInfo {
    if (-not (Test-SpicetifyCommand)) {
        Write-Warn 'Spicetify is not installed.'
        return
    }
    foreach ($commandArgs in @(@('path'), @('path', 'userdata'), @('path', 'all'), @('-c'), @('-e', 'path'), @('-a', 'path'), @('-s', 'path'))) {
        Write-Host "spicetify $($commandArgs -join ' ')" -ForegroundColor Cyan
        $result = Invoke-SpicetifyWithOutput @commandArgs
        Write-Host $result.Output
        Write-Host ''
    }
}

function Update-UpstreamReferences {
    $scriptPath = Join-Path $script:RepoRoot 'tools\refresh-upstream.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Missing $scriptPath"
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -UpstreamRoot $script:UpstreamRoot
}

function Test-UpstreamCliCompatibility {
    $catalog = Get-Catalog
    $cliRoot = Get-LocalRepoPath -Repo $catalog.official.cli.repo -Kind 'spicetify'
    if (-not (Test-Path -LiteralPath $cliRoot)) {
        Write-Warn "Local CLI source is not cloned: $cliRoot"
        Write-Warn 'Run Refresh Upstream References for source-level CLI compatibility checks.'
        return
    }

    $mainPath = Join-Path $cliRoot 'spicetify.go'
    $configPath = Join-Path $cliRoot 'src\utils\config.go'
    $editConfigPath = Join-Path $cliRoot 'src\cmd\config.go'
    if (-not (Test-Path -LiteralPath $mainPath) -or -not (Test-Path -LiteralPath $configPath) -or -not (Test-Path -LiteralPath $editConfigPath)) {
        throw 'Local CLI source is missing spicetify.go, src\utils\config.go, or src\cmd\config.go.'
    }

    $mainText = Get-Content -LiteralPath $mainPath -Raw
    $configText = Get-Content -LiteralPath $configPath -Raw
    $editConfigText = Get-Content -LiteralPath $editConfigPath -Raw

    $commandsUsed = @(
        'backup',
        'apply',
        'auto',
        'restore',
        'refresh',
        'enable-devtools',
        'clear',
        'spotify-updates',
        'path',
        'config',
        'config-dir',
        'color',
        'watch',
        'update',
        'upgrade'
    )
    $missingCommands = @($commandsUsed | Where-Object { $mainText -notmatch "\b$([regex]::Escape($_))\b" })
    if ($missingCommands.Count) {
        throw "CLI compatibility failed. Missing command(s) in upstream source: $($missingCommands -join ', ')"
    }
    Write-Ok "CLI commands used by menu are present: $($commandsUsed -join ', ')"

    $flagsUsed = @('-q', '--quiet', '-e', '--extension', '-a', '--app', '-s', '--style', '-l', '--live-refresh', '-c', '--config', '--bypass-admin')
    $missingFlags = @($flagsUsed | Where-Object { $mainText -notlike "*$_*" })
    if ($missingFlags.Count) {
        throw "CLI compatibility failed. Missing flag(s) in upstream source: $($missingFlags -join ', ')"
    }
    Write-Ok "CLI flags used by menu are present: $($flagsUsed -join ', ')"

    $configKeysUsed = @(
        'extensions',
        'custom_apps',
        'inject_css',
        'inject_theme_js',
        'replace_colors',
        'overwrite_assets',
        'always_enable_devtools',
        'check_spicetify_update',
        'disable_sentry',
        'disable_ui_logging',
        'remove_rtl_rule',
        'expose_apis',
        'experimental_features',
        'home_config',
        'sidebar_config',
        'current_theme',
        'color_scheme',
        'spotify_launch_flags'
    )
    $configKeys = @([regex]::Matches($configText, '"([a-z][a-z_]+)"\s*:') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $missingConfigKeys = @($configKeysUsed | Where-Object { $configKeys -notcontains $_ })
    if ($missingConfigKeys.Count) {
        throw "CLI compatibility failed. Missing config key(s) in upstream source: $($missingConfigKeys -join ', ')"
    }
    Write-Ok "Config keys used by menu are present: $($configKeysUsed -join ', ')"

    if ($editConfigText -match 'case\s+"spotify_launch_flags"\s*:\s*continue') {
        Write-Warn 'spotify_launch_flags is exposed by CLI but not writable through spicetify config; menu keeps it read-only.'
    }
}

function Invoke-SelfTest {
    $catalog = Get-Catalog
    Write-Host "$script:AppName $script:AppVersion self-test" -ForegroundColor Cyan
    Write-Host "Catalog: $script:CatalogPath"
    Write-Host "Upstream root: $script:UpstreamRoot"
    Write-Host ''

    $cli = Resolve-CliAsset
    Write-Ok "CLI latest: $($cli.Release.tag_name) asset=$($cli.Asset.name)"

    $market = Resolve-MarketplaceAsset
    Write-Ok "Marketplace latest: $($market.Release.tag_name) asset=$($market.Asset.name)"

    Write-Host ''
    Write-Host 'CLI compatibility:' -ForegroundColor Cyan
    Test-UpstreamCliCompatibility

    Write-Host ''
    Write-Host 'Official repositories:' -ForegroundColor Cyan
    foreach ($repo in @($catalog.official.repos)) {
        try {
            $r = Invoke-GitHubApi -Uri "https://api.github.com/repos/$repo"
            $state = if ($r.archived) { 'Archived' } else { 'Active' }
            Write-Ok ("{0,-36} {1,-9} updated={2}" -f $repo, $state, $r.updated_at)
        } catch {
            Write-Fail ("{0,-36} Unavailable - {1}" -f $repo, $_.Exception.Message)
        }
    }

    Write-Host ''
    $extensions = @(Get-OfficialExtensions)
    Write-Ok "Official extensions found: $($extensions.Count) ($($extensions -join ', '))"

    $appsPath = $catalog.official.cli.customAppsPath
    $apps = Invoke-GitHubApi -Uri "https://api.github.com/repos/$($catalog.official.cli.repo)/contents/$appsPath`?ref=main"
    $appNames = @($apps | Where-Object { $_.type -eq 'dir' } | ForEach-Object { $_.name })
    Write-Ok "Built-in custom apps found: $($appNames -join ', ')"
    $catalogAppNames = @($catalog.official.builtInCustomApps | ForEach-Object { $_.name })
    $missingBuiltIns = @($appNames | Where-Object { $catalogAppNames -notcontains $_ })
    $staleBuiltIns = @($catalogAppNames | Where-Object { $appNames -notcontains $_ })
    if ($missingBuiltIns.Count -or $staleBuiltIns.Count) {
        throw "Built-in custom app catalog mismatch. Missing from catalog: $($missingBuiltIns -join ', '); stale in catalog: $($staleBuiltIns -join ', ')"
    }
    Write-Ok 'Built-in custom app catalog matches upstream CLI.'

    $themeRepoPath = Get-LocalRepoPath -Repo $catalog.official.themes.repo -Kind 'spicetify'
    if (Test-Path -LiteralPath $themeRepoPath) {
        $themes = @(Get-AvailableThemes)
        Write-Ok "Local official themes with color.ini/user.css: $($themes.Count)"
    } else {
        Write-Warn "Local themes not cloned yet: $themeRepoPath"
    }

    Write-Host ''
    Write-Host 'Community apps:' -ForegroundColor Cyan
    foreach ($app in @($catalog.communityApps)) {
        $resolved = Resolve-CommunityApp -App $app
        $line = "{0,-24} {1,-12} {2}" -f $resolved.Name, $resolved.Status, $resolved.Repo
        if ($resolved.Status -eq 'Unavailable') {
            Write-Fail "$line - $($resolved.Reason)"
        } elseif ($resolved.Status -eq 'Deprecated') {
            Write-Warn $line
        } else {
            Write-Ok $line
        }
    }

    Write-Host ''
    if (Test-SpicetifyCommand) {
        Write-Host 'Installed Spicetify read-only checks:' -ForegroundColor Cyan
        foreach ($commandArgs in @(@('--version'), @('path', 'userdata'), @('config'))) {
            $result = Invoke-SpicetifyWithOutput @commandArgs
            $firstLine = (($result.Output -split '\r?\n') | Select-Object -First 1)
            Write-Ok ("spicetify {0} -> exit {1}: {2}" -f ($commandArgs -join ' '), $result.ExitCode, $firstLine)
        }
    } else {
        Write-Warn 'Spicetify command not found; installed CLI read-only checks skipped.'
    }
}

function Show-GitHubTokenMenu {
    while ($true) {
        Clear-Host
        Write-Host '--- GitHub Token ---' -ForegroundColor Yellow
        if ([string]::IsNullOrWhiteSpace($Global:githubToken)) {
            Write-Host 'Current: not set'
        } else {
            $mask = $Global:githubToken.Substring(0, [Math]::Min(8, $Global:githubToken.Length)) + '...'
            Write-Host "Current: $mask"
        }
        Write-Host '[1] Set token'
        Write-Host '[2] Test token'
        Write-Host '[3] Remove token'
        Write-Host '[0] Back'
        $choice = Read-Host 'Choose'
        if ($choice -eq '0') { return }
        if ($choice -eq '1') {
            $token = Read-Host 'GitHub token'
            if (Save-GitHubToken -Token $token) { Write-Ok 'Token saved.' }
            Wait-IfNeeded
        } elseif ($choice -eq '2') {
            try {
                $rate = Invoke-GitHubApi -Uri 'https://api.github.com/rate_limit'
                Write-Ok "Core rate remaining: $($rate.resources.core.remaining)"
            } catch {
                Write-Fail $_.Exception.Message
            }
            Wait-IfNeeded
        } elseif ($choice -eq '3') {
            Remove-GitHubToken
            Write-Ok 'Token removed.'
            Wait-IfNeeded
        }
    }
}

function Show-SettingsMenu {
    while ($true) {
        Clear-Host
        Write-Host '================ Spicetify Settings ================' -ForegroundColor Cyan
        Write-Host '[1] Backup & Apply Changes'
        Write-Host '[2] Auto Check & Apply'
        Write-Host '[3] Restore Spotify to Original'
        Write-Host '[4] Refresh active theme'
        Write-Host '[5] Enable Developer Tools'
        Write-Host '[6] Manage Extensions'
        Write-Host '[7] Manage Custom Apps'
        Write-Host '[8] Manage Themes'
        Write-Host '[9] Manage Config Settings'
        Write-Host '[10] Manage Spotify Launch Flags'
        Write-Host '[11] Show Path Information'
        Write-Host '[12] Run Self Test'
        Write-Host '[13] Refresh Upstream References'
        Write-Host '[14] Clear Backup Files'
        Write-Host '[15] Block/Unblock Spotify Updates'
        Write-Host '[16] Advanced Refresh & Watch'
        Write-Host '[17] Manage Theme Colors'
        Write-Host '[18] Open Config Directory'
        Write-Host '[0] Back'
        $choice = Read-Host 'Choose'

        switch ($choice) {
            '1' { Invoke-SafeSpicetifyBackupApply; Wait-IfNeeded }
            '2' { Invoke-SpicetifyMenuCommand -Arguments @('auto') -SuccessMessage 'Auto command finished.'; Wait-IfNeeded }
            '3' { Invoke-SpicetifyMenuCommand -Arguments @('restore') -SuccessMessage 'Restore command finished.'; Wait-IfNeeded }
            '4' { Invoke-SpicetifyMenuCommand -Arguments @('refresh') -SuccessMessage 'Refresh command finished.'; Wait-IfNeeded }
            '5' { Invoke-SpicetifyMenuCommand -Arguments @('enable-devtools') -SuccessMessage 'Developer tools enabled.'; Wait-IfNeeded }
            '6' { Show-ExtensionsMenu }
            '7' { Show-CustomAppsMenu }
            '8' { Show-ThemesMenu }
            '9' { Show-ConfigSettingsMenu }
            '10' { Show-LaunchFlagsMenu }
            '11' { Show-PathInfo; Wait-IfNeeded }
            '12' { Invoke-SelfTest; Wait-IfNeeded }
            '13' { Update-UpstreamReferences; Wait-IfNeeded }
            '14' { Clear-SpicetifyBackup; Wait-IfNeeded }
            '15' { Show-SpotifyUpdateBlockingMenu }
            '16' { Show-RefreshWatchMenu }
            '17' { Show-ThemeColorsMenu }
            '18' { Invoke-SpicetifyMenuCommand -Arguments @('config-dir') -SuccessMessage 'Config directory opened.'; Wait-IfNeeded }
            '0' { return }
            default { Write-Warn 'Invalid choice.'; Wait-IfNeeded }
        }
    }
}

function Show-MainMenu {
    Clear-Host
    Write-Host '=====================================================' -ForegroundColor Cyan
    Write-Host "                 $script:AppName v$script:AppVersion"
    Write-Host '=====================================================' -ForegroundColor Cyan
    Write-Host '[1] Install Spotify'
    Write-Host '[2] Update Spotify'
    Write-Host '[3] Remove Spotify'
    Write-Host '[4] Install Spicetify'
    Write-Host '[5] Install Spicetify Marketplace'
    Write-Host '[6] Update Spicetify'
    Write-Host '[7] Spicetify Settings'
    Write-Host '[8] Remove Spicetify'
    Write-Host '[9] GitHub API Token Settings'
    Write-Host '[10] Run Self Test'
    Write-Host '[0] Exit'
}

function Start-Interactive {
    while ($true) {
        Show-MainMenu
        $choice = Read-Host 'Choose'
        try {
            switch ($choice) {
                '1' { Install-Spotify; Wait-IfNeeded }
                '2' { Update-Spotify; Wait-IfNeeded }
                '3' { Remove-Spotify; Wait-IfNeeded }
                '4' { Install-Spicetify; Wait-IfNeeded }
                '5' { Install-Marketplace; Wait-IfNeeded }
                '6' { Update-Spicetify; Wait-IfNeeded }
                '7' { Show-SettingsMenu }
                '8' { Remove-Spicetify; Wait-IfNeeded }
                '9' { Show-GitHubTokenMenu }
                '10' { Invoke-SelfTest; Wait-IfNeeded }
                '0' { return }
                default { Write-Warn 'Invalid choice.'; Wait-IfNeeded }
            }
        } catch {
            Write-Fail $_.Exception.Message
            Wait-IfNeeded
        }
    }
}

$Global:githubToken = Import-GitHubToken

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

Start-Interactive
