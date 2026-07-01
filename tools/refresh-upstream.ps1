[CmdletBinding()]
param(
    [string]$UpstreamRoot = '.upstream',
    [switch]$CommunityOnly,
    [switch]$OfficialOnly,
    [switch]$IncludeLargeMirrors,
    [int]$CloneTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[refresh] $Message" -ForegroundColor Cyan
}

function Get-SafeRepoName {
    param([string]$Repo)
    return ($Repo -replace '/', '__')
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

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Argument)

    if ([string]::IsNullOrEmpty($Argument)) {
        return '""'
    }
    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0

    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }

        if ($character -eq '"') {
            if ($backslashes -gt 0) {
                [void]$builder.Append('\' * ($backslashes * 2))
                $backslashes = 0
            }
            [void]$builder.Append('\"')
            continue
        }

        if ($backslashes -gt 0) {
            [void]$builder.Append('\' * $backslashes)
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }

    if ($backslashes -gt 0) {
        [void]$builder.Append('\' * ($backslashes * 2))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Stop-ProcessTree {
    param([int]$ProcessId)

    Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-ProcessTree -ProcessId $_.ProcessId }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Invoke-GitTimed {
    param(
        [string[]]$Arguments,
        [int]$TimeoutSeconds,
        [string]$WorkingDirectory = ''
    )

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = 'git'
    $process.StartInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-NativeArgument -Argument $_ }) -join ' ')
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $process.StartInfo.WorkingDirectory = $WorkingDirectory
    }

    [void]$process.Start()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-ProcessTree -ProcessId $process.Id
        throw "git timed out after $TimeoutSeconds seconds: git $($Arguments -join ' ')"
    }

    if ($process.ExitCode -ne 0) {
        throw "git exited with code $($process.ExitCode): git $($Arguments -join ' ')"
    }
}

function Sync-Repo {
    param(
        [string]$Repo,
        [string]$Root,
        [string[]]$ExtraBranches = @()
    )

    $target = Join-Path $Root (Get-SafeRepoName $Repo)
    $url = "https://github.com/$Repo.git"

    if (Test-Path $target) {
        if (-not (Test-Path -LiteralPath (Join-Path $target '.git'))) {
            Write-Step "Removing incomplete clone for $Repo"
            Remove-TreeSafe -Path $target -AllowedRoot $Root
        }
    }

    if (Test-Path $target) {
        Write-Step "Updating $Repo"
        Invoke-GitTimed -Arguments @('-C', $target, 'fetch', '--depth=1', '--filter=blob:none', 'origin') -TimeoutSeconds $CloneTimeoutSeconds
        Invoke-GitTimed -Arguments @('-C', $target, 'pull', '--ff-only') -TimeoutSeconds $CloneTimeoutSeconds
    } else {
        Write-Step "Cloning $Repo"
        Invoke-GitTimed -Arguments @('clone', '--depth=1', '--filter=blob:none', $url, $target) -TimeoutSeconds $CloneTimeoutSeconds
    }

    foreach ($branch in $ExtraBranches) {
        Write-Step "Fetching $Repo branch $branch"
        Invoke-GitTimed -Arguments @('-C', $target, 'fetch', '--depth=1', '--filter=blob:none', 'origin', "refs/heads/${branch}:refs/remotes/origin/${branch}") -TimeoutSeconds $CloneTimeoutSeconds
    }
}

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = Resolve-Path (Join-Path $scriptRoot '..')
$catalogPath = Join-Path $repoRoot 'spicetify-plus.catalog.json'
$catalog = Get-Content -Raw -Path $catalogPath | ConvertFrom-Json
$rootPath = if ([System.IO.Path]::IsPathRooted($UpstreamRoot)) {
    [System.IO.Path]::GetFullPath($UpstreamRoot)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $UpstreamRoot))
}

New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
$officialRoot = Join-Path $rootPath 'spicetify'
$communityRoot = Join-Path $rootPath 'community'
New-Item -ItemType Directory -Path $officialRoot, $communityRoot -Force | Out-Null

if (-not $CommunityOnly) {
    $largeMirrors = @(
        'spicetify/winget-pkgs',
        'spicetify/xpui-archive',
        'spicetify/pkgs',
        'spicetify/classmaps'
    )
    foreach ($repo in $catalog.official.repos) {
        if (-not $IncludeLargeMirrors -and $largeMirrors -contains $repo) {
            Write-Step "Skipping large mirror/archive $repo (use -IncludeLargeMirrors to clone it)"
            continue
        }
        try {
            Sync-Repo -Repo $repo -Root $officialRoot
        } catch {
            Write-Warning $_.Exception.Message
        }
    }
}

if (-not $OfficialOnly) {
    $communityGroups = @{}
    foreach ($app in $catalog.communityApps) {
        if (-not $communityGroups.ContainsKey($app.repo)) {
            $communityGroups[$app.repo] = New-Object System.Collections.Generic.List[string]
        }
        if ($app.resolver.type -eq 'branchArchive') {
            $communityGroups[$app.repo].Add([string]$app.resolver.branch)
        }
    }

    foreach ($repo in $communityGroups.Keys) {
        $branches = $communityGroups[$repo] | Sort-Object -Unique
        try {
            Sync-Repo -Repo $repo -Root $communityRoot -ExtraBranches $branches
        } catch {
            Write-Warning $_.Exception.Message
        }
    }
}

Write-Host "Upstream references are available at: $rootPath" -ForegroundColor Green
