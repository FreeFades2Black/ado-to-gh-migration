# ==============================================================================
# Script 02: Inventory Azure DevOps Repositories
# ==============================================================================
[CmdletBinding()]
param(
    [string]$AdoOrg,
    [string]$AdoProject,
    [string]$AdoPat,
    [string]$OutputFile = (Join-Path $script:ConfigDir "repos.csv"),
    [switch]$Mock
)

$commonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00_common.ps1"
. $commonPath

Load-EnvFile

$adoOrg = if ($AdoOrg) { $AdoOrg } else { [System.Environment]::GetEnvironmentVariable("ADO_ORG") }
$adoProject = if ($AdoProject) { $AdoProject } else { [System.Environment]::GetEnvironmentVariable("ADO_PROJECT") }
$adoPat = if ($AdoPat) { $AdoPat } else { [System.Environment]::GetEnvironmentVariable("ADO_PAT") }
$mode = [System.Environment]::GetEnvironmentVariable("MIGRATION_MODE")

if ($Mock -or $mode -eq "mock") {
    $isMock = $true
} else {
    $isMock = $false
}

Write-Log "==========================================================" "TITLE"
Write-Log "Repository Inventory Discovery" "TITLE"
Write-Log "==========================================================" "TITLE"

if ($isMock) {
    Write-Log "Generating inventory from Mock Sandbox Environment..." "INFO"
    $mockUrl = [System.Environment]::GetEnvironmentVariable("MOCK_ADO_URL")
    if (-not $mockUrl) { $mockUrl = "http://127.0.0.1:8088" }
    
    try {
        $response = Invoke-RestMethod -Uri "$mockUrl/_apis/git/repositories?api-version=7.0" -Method Get -TimeoutSec 5
        $repos = $response.value
    } catch {
        Write-Log "Mock server not responding at $mockUrl. Using built-in synthetic test repositories." "WARN"
        $repos = @(
            [PSCustomObject]@{ name = "frontend-core"; id = "a1b2c3d4-0001-4000-8000-000000000001"; size = 45219800; defaultBranch = "refs/heads/main"; isDisabled = $false },
            [PSCustomObject]@{ name = "backend-api"; id = "a1b2c3d4-0002-4000-8000-000000000002"; size = 128940000; defaultBranch = "refs/heads/main"; isDisabled = $false },
            [PSCustomObject]@{ name = "shared-utils-lib"; id = "a1b2c3d4-0003-4000-8000-000000000003"; size = 15200300; defaultBranch = "refs/heads/master"; isDisabled = $false },
            [PSCustomObject]@{ name = "infra-terraform"; id = "a1b2c3d4-0004-4000-8000-000000000004"; size = 8900200; defaultBranch = "refs/heads/main"; isDisabled = $false }
        )
    }
} else {
    if (-not $adoOrg -or -not $adoProject -or -not $adoPat) {
        Write-Log "Missing required ADO credentials (ADO_ORG, ADO_PROJECT, ADO_PAT) in .env" "ERROR"
        exit 1
    }
    
    Write-Log "Querying Azure DevOps REST API: ${adoOrg}/${adoProject}..." "INFO"
    $authHeader = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$adoPat"))
    $headers = @{
        "Authorization" = "Basic $authHeader"
        "Accept" = "application/json"
    }
    
    $apiUrl = "https://dev.azure.com/${adoOrg}/${adoProject}/_apis/git/repositories?api-version=7.0"
    
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers
        $repos = $response.value
    } catch {
        Write-Log "Failed to query ADO API: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

if (-not $repos -or $repos.Count -eq 0) {
    Write-Log "No repositories found for project ${adoProject}." "WARN"
    exit 0
}

Write-Log "Discovered $($repos.Count) repositories." "SUCCESS"

# Export to CSV
$csvRows = @()
$state = Get-MigrationState

foreach ($repo in $repos) {
    $row = [PSCustomObject]@{
        repo_name      = $repo.name
        repo_id        = $repo.id
        size_bytes     = $repo.size
        default_branch = if ($repo.defaultBranch) { $repo.defaultBranch -replace 'refs/heads/', '' } else { 'main' }
        is_disabled    = if ($repo.isDisabled) { "true" } else { "false" }
        status         = "PENDING"
    }
    $csvRows += $row
    
    # Initialize in state if not present
    if (-not $state.repositories.PSObject.Properties[$repo.name]) {
        Update-RepoState -RepoName $repo.name -Status "PENDING" -TargetGhRepo $repo.name
    }
}

$csvRows | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
Write-Log "Saved manifest with $($csvRows.Count) repositories to: $OutputFile" "SUCCESS"

# Display summary table
$csvRows | Format-Table -Property repo_name, size_bytes, default_branch, is_disabled
