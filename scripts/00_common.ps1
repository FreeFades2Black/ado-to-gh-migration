# ==============================================================================
# Common Utilities & Shared Functions for ADO to GitHub Migration Suite
# ==============================================================================

# Script Root & Default Paths
$script:RootPath = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:ConfigDir = Join-Path $script:RootPath "config"
$script:LogDir = Join-Path $script:RootPath "logs"
$script:StateFile = Join-Path $script:ConfigDir "migration-state.json"

# Ensure runtime directories exist
if (-not (Test-Path $script:ConfigDir)) { New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null }
if (-not (Test-Path $script:LogDir)) { New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null }

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR", "DEBUG", "TITLE")][string]$Level = "INFO",
        [string]$RepoName = $null
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARN"    = "Yellow"
        "ERROR"   = "Red"
        "DEBUG"   = "DarkGray"
        "TITLE"   = "Magenta"
    }
    
    $prefix = switch ($Level) {
        "INFO"    { "[*]" }
        "SUCCESS" { "[+]" }
        "WARN"    { "[!]" }
        "ERROR"   { "[-]" }
        "DEBUG"   { "[?]" }
        "TITLE"   { "===" }
    }
    
    $formattedMsg = "[$timestamp] $prefix $Message"
    Write-Host $formattedMsg -ForegroundColor $colorMap[$Level]
    
    # Global log
    $globalLog = Join-Path $script:LogDir "migration_$(Get-Date -Format 'yyyyMMdd').log"
    Add-Content -Path $globalLog -Value $formattedMsg -ErrorAction SilentlyContinue
    
    # Repo-specific log if supplied
    if ($RepoName) {
        $repoLog = Join-Path $script:LogDir "repo_${RepoName}.log"
        Add-Content -Path $repoLog -Value $formattedMsg -ErrorAction SilentlyContinue
    }
}

function Load-EnvFile {
    param([string]$Path = (Join-Path $script:RootPath ".env"))
    
    if (-not (Test-Path $Path)) {
        $examplePath = Join-Path $script:RootPath ".env.example"
        if (Test-Path $examplePath) {
            Write-Log "No .env found. Creating .env from .env.example..." "WARN"
            Copy-Item $examplePath $Path
        } else {
            Write-Log ".env file not found at $Path" "WARN"
            return $false
        }
    }
    
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $key = $parts[0].Trim()
            $value = $parts[1].Trim().Trim('"').Trim("'")
            [System.Environment]::SetEnvironmentVariable($key, $value, [System.EnvironmentVariableTarget]::Process)
        }
    }
    Write-Log "Loaded environment configuration from $Path" "DEBUG"
    return $true
}

function Get-MigrationState {
    if (Test-Path $script:StateFile) {
        try {
            $json = Get-Content $script:StateFile -Raw -Encoding UTF8
            return ($json | ConvertFrom-Json)
        } catch {
            Write-Log "Failed to parse state file. Initializing empty state." "WARN"
        }
    }
    return [PSCustomObject]@{
        last_updated = (Get-Date -Format "o")
        repositories = @{}
    }
}

function Save-MigrationState {
    param([Parameter(Mandatory=$true)]$State)
    $State.last_updated = (Get-Date -Format "o")
    $json = $State | ConvertTo-Json -Depth 10
    Set-Content -Path $script:StateFile -Value $json -Encoding UTF8
}

function Update-RepoState {
    param(
        [Parameter(Mandatory=$true)][string]$RepoName,
        [Parameter(Mandatory=$true)][ValidateSet("PENDING", "IN_PROGRESS", "COMPLETED", "FAILED", "SKIPPED")][string]$Status,
        [string]$ErrorMessage = "",
        [int]$Attempts = 1,
        [string]$TargetGhRepo = ""
    )
    $state = Get-MigrationState
    if (-not $state.repositories) {
        $state | Add-Member -NotePropertyName "repositories" -NotePropertyValue ([PSCustomObject]@{})
    }
    
    $repoObj = [PSCustomObject]@{
        status = $Status
        updated_at = (Get-Date -Format "o")
        error_message = $ErrorMessage
        attempts = $Attempts
        target_gh_repo = $TargetGhRepo
    }
    
    if ($state.repositories.PSObject.Properties[$RepoName]) {
        $state.repositories.$RepoName = $repoObj
    } else {
        $state.repositories | Add-Member -NotePropertyName $RepoName -NotePropertyValue $repoObj
    }
    
    Save-MigrationState -State $state
}

function Test-Prerequisites {
    param([switch]$RequireGEI = $true)
    
    Write-Log "Validating system prerequisites..." "INFO"
    $allPassed = $true
    
    # 1. Git
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVer = (git --version)
        Write-Log "Git found: $gitVer" "SUCCESS"
    } else {
        Write-Log "Git is NOT installed or not in PATH." "ERROR"
        $allPassed = $false
    }
    
    # 2. GitHub CLI (gh)
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ghVer = (gh --version | Select-Object -First 1)
        Write-Log "GitHub CLI found: $ghVer" "SUCCESS"
        
        # 3. GEI Extension
        if ($RequireGEI) {
            $extensions = gh extension list
            if ($extensions -match "gei") {
                Write-Log "GitHub Enterprise Importer (gh-gei) extension is installed." "SUCCESS"
            } else {
                Write-Log "gh-gei extension is missing. Run 'gh extension install github/gh-gei'" "WARN"
                $allPassed = $false
            }
        }
    } else {
        Write-Log "GitHub CLI (gh) is NOT installed. Install via: winget install GitHub.cli" "ERROR"
        $allPassed = $false
    }
    
    return $allPassed
}

Export-ModuleMember -Function Write-Log, Load-EnvFile, Get-MigrationState, Save-MigrationState, Update-RepoState, Test-Prerequisites -Variable RootPath, ConfigDir, LogDir, StateFile -ErrorAction SilentlyContinue
