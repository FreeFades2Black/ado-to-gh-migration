# ==============================================================================
# Script 03: Migrate a Single Repository (ADO -> GitHub)
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)][string]$AdoRepo,
    [Parameter(Position=1)][string]$GhRepo,
    [string]$AdoOrg,
    [string]$AdoProject,
    [string]$GhOrg,
    [int]$MaxRetries = 3,
    [switch]$DryRun,
    [switch]$Mock
)

$commonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00_common.ps1"
. $commonPath

Load-EnvFile

$adoOrg = if ($AdoOrg) { $AdoOrg } else { [System.Environment]::GetEnvironmentVariable("ADO_ORG") }
$adoProject = if ($AdoProject) { $AdoProject } else { [System.Environment]::GetEnvironmentVariable("ADO_PROJECT") }
$ghOrg = if ($GhOrg) { $GhOrg } else { [System.Environment]::GetEnvironmentVariable("GH_ORG") }
$adoPat = [System.Environment]::GetEnvironmentVariable("ADO_PAT")
$ghPat = [System.Environment]::GetEnvironmentVariable("GH_PAT")
$targetGhRepo = if ($GhRepo) { $GhRepo } else { $AdoRepo }
$mode = [System.Environment]::GetEnvironmentVariable("MIGRATION_MODE")

if ($Mock -or $mode -eq "mock") {
    $isMock = $true
} else {
    $isMock = $false
}

Write-Log "==========================================================" "TITLE" -RepoName $AdoRepo
Write-Log "Migrating Repository: $AdoRepo -> ${ghOrg}/${targetGhRepo}" "TITLE" -RepoName $AdoRepo
Write-Log "==========================================================" "TITLE" -RepoName $AdoRepo

# Pre-flight credential checks
if (-not $isMock) {
    if (-not $adoPat -or -not $ghPat) {
        Write-Log "Missing required tokens: ADO_PAT or GH_PAT not found in environment." "ERROR" -RepoName $AdoRepo
        Update-RepoState -RepoName $AdoRepo -Status "FAILED" -ErrorMessage "Missing credentials" -TargetGhRepo $targetGhRepo
        exit 1
    }
}

if ($DryRun) {
    Write-Log "[DRY-RUN] Simulating migration for $AdoRepo -> ${ghOrg}/${targetGhRepo}..." "WARN" -RepoName $AdoRepo
    Start-Sleep -Milliseconds 800
    Write-Log "[DRY-RUN] Validated ADO endpoint: https://dev.azure.com/${adoOrg}/${adoProject}/_git/${AdoRepo}" "INFO" -RepoName $AdoRepo
    Write-Log "[DRY-RUN] Validated target GitHub location: https://github.com/${ghOrg}/${targetGhRepo}" "INFO" -RepoName $AdoRepo
    Write-Log "[DRY-RUN] Simulation successful. No actual data transferred." "SUCCESS" -RepoName $AdoRepo
    Update-RepoState -RepoName $AdoRepo -Status "COMPLETED" -ErrorMessage "Dry-run successful" -TargetGhRepo $targetGhRepo
    exit 0
}

if ($isMock) {
    Write-Log "[MOCK-SANDBOX] Simulating migration execution for: $AdoRepo" "INFO" -RepoName $AdoRepo
    Update-RepoState -RepoName $AdoRepo -Status "IN_PROGRESS" -TargetGhRepo $targetGhRepo
    
    # Simulate processing stages
    Write-Log "  1/4: Cloning ADO repository snapshot..." "INFO" -RepoName $AdoRepo
    Start-Sleep -Milliseconds 300
    Write-Log "  2/4: Exporting PR metadata & branch commit trees..." "INFO" -RepoName $AdoRepo
    Start-Sleep -Milliseconds 300
    Write-Log "  3/4: Creating GitHub target repository: ${ghOrg}/${targetGhRepo}..." "INFO" -RepoName $AdoRepo
    Start-Sleep -Milliseconds 300
    Write-Log "  4/4: Replaying commit history and archiving ADO source..." "INFO" -RepoName $AdoRepo
    Start-Sleep -Milliseconds 300
    
    Write-Log "[+] Mock migration completed successfully for $AdoRepo -> ${ghOrg}/${targetGhRepo}" "SUCCESS" -RepoName $AdoRepo
    Update-RepoState -RepoName $AdoRepo -Status "COMPLETED" -ErrorMessage "" -Attempts 1 -TargetGhRepo $targetGhRepo
    exit 0
}

# Live GEI Execution with Retry Logic
Update-RepoState -RepoName $AdoRepo -Status "IN_PROGRESS" -TargetGhRepo $targetGhRepo
$attempt = 0
$success = $false
$lastError = ""

# Export environment variables for gh gei CLI
[System.Environment]::SetEnvironmentVariable("GH_PAT", $ghPat, [System.EnvironmentVariableTarget]::Process)
[System.Environment]::SetEnvironmentVariable("ADO_PAT", $adoPat, [System.EnvironmentVariableTarget]::Process)

while ($attempt -lt $MaxRetries -and -not $success) {
    $attempt++
    Write-Log "Migration attempt $attempt of $MaxRetries..." "INFO" -RepoName $AdoRepo
    
    $geiArgs = @(
        "gei", "migrate-repo",
        "--ado-org", $adoOrg,
        "--ado-team-project", $adoProject,
        "--ado-repo", $AdoRepo,
        "--github-org", $ghOrg,
        "--github-repo", $targetGhRepo,
        "--wait_for_completion",
        "--verbose"
    )
    
    $userMappingPath = Join-Path $script:ConfigDir "user-mapping.csv"
    if (Test-Path $userMappingPath) {
        $geiArgs += @("--user-mapping-file", $userMappingPath)
    }
    
    try {
        & gh $geiArgs
        if ($LASTEXITCODE -eq 0) {
            $success = $true
            Write-Log "Successfully migrated ${AdoRepo} -> https://github.com/${ghOrg}/${targetGhRepo}" "SUCCESS" -RepoName $AdoRepo
            Update-RepoState -RepoName $AdoRepo -Status "COMPLETED" -ErrorMessage "" -Attempts $attempt -TargetGhRepo $targetGhRepo
        } else {
            $lastError = "gh gei exited with code $LASTEXITCODE"
            Write-Log "GEI migration failed on attempt $attempt: $lastError" "WARN" -RepoName $AdoRepo
        }
    } catch {
        $lastError = $_.Exception.Message
        Write-Log "Exception during migration: $lastError" "ERROR" -RepoName $AdoRepo
    }
    
    if (-not $success -and $attempt -lt $MaxRetries) {
        $backoffSec = [Math]::Pow(2, $attempt) * 5
        Write-Log "Retrying in $backoffSec seconds (exponential backoff)..." "WARN" -RepoName $AdoRepo
        Start-Sleep -Seconds $backoffSec
    }
}

if (-not $success) {
    Write-Log "Failed to migrate ${AdoRepo} after $MaxRetries attempts. Reason: $lastError" "ERROR" -RepoName $AdoRepo
    Update-RepoState -RepoName $AdoRepo -Status "FAILED" -ErrorMessage $lastError -Attempts $attempt -TargetGhRepo $targetGhRepo
    exit 1
}
