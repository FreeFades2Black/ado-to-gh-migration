# ==============================================================================
# Script 04: Bulk Orchestrator for Repository Migrations
# ==============================================================================
[CmdletBinding()]
param(
    [string]$ManifestFile = (Join-Path $script:ConfigDir "repos.csv"),
    [switch]$ResumeOnly,
    [switch]$ForceAll,
    [switch]$DryRun,
    [switch]$Mock
)

$commonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00_common.ps1"
. $commonPath

Load-EnvFile

Write-Log "==========================================================" "TITLE"
Write-Log "Azure DevOps to GitHub Bulk Migration Orchestrator" "TITLE"
Write-Log "==========================================================" "TITLE"

if (-not (Test-Path $ManifestFile)) {
    Write-Log "Manifest file not found at $ManifestFile. Run 02_inventory_repos.ps1 first!" "ERROR"
    exit 1
}

$repos = Import-Csv -Path $ManifestFile
if (-not $repos -or $repos.Count -eq 0) {
    Write-Log "Manifest at $ManifestFile is empty." "WARN"
    exit 0
}

$state = Get-MigrationState
$total = $repos.Count
$current = 0
$successful = 0
$failed = 0
$skipped = 0

Write-Log "Total repositories in manifest: $total" "INFO"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$migrateScript = Join-Path $scriptDir "03_migrate_repo.ps1"

foreach ($repo in $repos) {
    $current++
    $repoName = $repo.repo_name
    $percent = [Math]::Round(($current / $total) * 100)
    
    # Check state for resume
    $repoState = $state.repositories.PSObject.Properties[$repoName].Value
    if ($repoState -and $repoState.status -eq "COMPLETED" -and -not $ForceAll) {
        Write-Log "[$current/$total - $percent%] Skipping $repoName (Already completed in state)." "SUCCESS"
        $skipped++
        continue
    }
    
    if ($ResumeOnly -and $repoState -and $repoState.status -ne "FAILED" -and $repoState.status -ne "PENDING") {
        Write-Log "[$current/$total - $percent%] Skipping $repoName (ResumeOnly active)." "INFO"
        $skipped++
        continue
    }
    
    Write-Log "----------------------------------------------------------" "INFO"
    Write-Log "[$current/$total - $percent%] Processing: $repoName" "INFO"
    Write-Log "----------------------------------------------------------" "INFO"
    
    $argsList = @("-AdoRepo", $repoName)
    if ($DryRun) { $argsList += "-DryRun" }
    if ($Mock) { $argsList += "-Mock" }
    
    & powershell -NoProfile -ExecutionPolicy Bypass -File $migrateScript @argsList
    
    # Reload state to get latest outcome
    $state = Get-MigrationState
    $outcome = $state.repositories.PSObject.Properties[$repoName].Value
    
    if ($outcome -and $outcome.status -eq "COMPLETED") {
        $successful++
    } else {
        $failed++
        $failedLog = Join-Path $script:ConfigDir "failed_repos.log"
        Add-Content -Path $failedLog -Value "$repoName (Failed at $(Get-Date -Format 'o'))"
    }
}

Write-Log "==========================================================" "TITLE"
Write-Log "Bulk Migration Summary Report" "TITLE"
Write-Log "==========================================================" "TITLE"
Write-Log "Total Processed : $total" "INFO"
Write-Log "Successful      : $successful" "SUCCESS"
Write-Log "Skipped         : $skipped" "INFO"
Write-Log "Failed          : $failed" $(if ($failed -gt 0) { "ERROR" } else { "INFO" })

# Print final state table
$finalState = Get-MigrationState
$tableData = @()
foreach ($prop in $finalState.repositories.PSObject.Properties) {
    $tableData += [PSCustomObject]@{
        Repository = $prop.Name
        Status     = $prop.Value.status
        Attempts   = $prop.Value.attempts
        Updated    = $prop.Value.updated_at
        Error      = $prop.Value.error_message
    }
}
$tableData | Format-Table -AutoSize
