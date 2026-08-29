# ==============================================================================
# Automated End-to-End Test Suite (Mock Sandbox)
# ==============================================================================
[CmdletBinding()]
param()

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$scriptsDir = Join-Path $root "scripts"
$mockDir = Join-Path $root "mock"
$commonPath = Join-Path $scriptsDir "00_common.ps1"
. $commonPath

Write-Log "==========================================================" "TITLE"
Write-Log "ADO-to-GitHub Migration Test Suite: Mock End-to-End Run" "TITLE"
Write-Log "==========================================================" "TITLE"

$passedCount = 0
$totalTests = 6

function Assert-Test {
    param([string]$Name, [bool]$Condition)
    if ($Condition) {
        Write-Log "[PASS] $Name" "SUCCESS"
        $script:passedCount++
    } else {
        Write-Log "[FAIL] $Name" "ERROR"
    }
}

# 1. Start Mock Server in Background Process
Write-Log "Starting Mock ADO Server on localhost:8088..." "INFO"
$serverScript = Join-Path $mockDir "mock_ado_server.ps1"
$serverProc = Start-Process powershell -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$serverScript`"" -PassThru -WindowStyle Hidden

Start-Sleep -Seconds 2

try {
    # Set environment to mock
    [System.Environment]::SetEnvironmentVariable("MIGRATION_MODE", "mock", [System.EnvironmentVariableTarget]::Process)
    [System.Environment]::SetEnvironmentVariable("MOCK_ADO_URL", "http://127.0.0.1:8088", [System.EnvironmentVariableTarget]::Process)
    
    # Test 1: Prerequisites Check
    Write-Log "`n--- Running Test 1: Prerequisites Check ---" "INFO"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "01_prereqs.ps1")
    Assert-Test -Name "Prerequisites verification executed" -Condition ($LASTEXITCODE -eq 0)

    # Test 2: Inventory Repositories
    Write-Log "`n--- Running Test 2: Inventory Discovery ---" "INFO"
    $manifestPath = Join-Path $root "config\repos.csv"
    if (Test-Path $manifestPath) { Remove-Item $manifestPath -Force }
    
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "02_inventory_repos.ps1") -Mock
    $manifestExists = Test-Path $manifestPath
    $manifestRows = if ($manifestExists) { (Import-Csv $manifestPath).Count } else { 0 }
    Assert-Test -Name "Inventory generated manifest with 4 repositories" -Condition ($manifestExists -and $manifestRows -eq 4)

    # Test 3: Single Repository Migration
    Write-Log "`n--- Running Test 3: Single Repo Migration ---" "INFO"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "03_migrate_repo.ps1") -AdoRepo "frontend-core" -Mock
    $state = Get-MigrationState
    $frontendState = $state.repositories."frontend-core"
    Assert-Test -Name "Single repo migrated and recorded in state" -Condition ($frontendState -and $frontendState.status -eq "COMPLETED")

    # Test 4: Bulk Migration & Orchestration
    Write-Log "`n--- Running Test 4: Bulk Migration ---" "INFO"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "04_bulk_migrate.ps1") -Mock
    $state = Get-MigrationState
    $allCompleted = $true
    foreach ($r in @("frontend-core", "backend-api", "shared-utils-lib", "infra-terraform")) {
        if (-not $state.repositories.$r -or $state.repositories.$r.status -ne "COMPLETED") {
            $allCompleted = $false
        }
    }
    Assert-Test -Name "All 4 repositories marked COMPLETED in state" -Condition $allCompleted

    # Test 5: Checkpoint Resumption (Skip Already Completed)
    Write-Log "`n--- Running Test 5: Checkpoint Resumption ---" "INFO"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "04_bulk_migrate.ps1") -Mock
    Assert-Test -Name "Bulk migration idempotent (skips already completed repos)" -Condition ($LASTEXITCODE -eq 0)

    # Test 6: Verification Audit Tool
    Write-Log "`n--- Running Test 6: Post-Migration Audit Verification ---" "INFO"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "05_verify_migration.ps1") -Mock
    Assert-Test -Name "Post-migration verification completed successfully" -Condition ($LASTEXITCODE -eq 0)

} finally {
    # Terminate Mock Server
    Write-Log "Shutting down mock server..." "INFO"
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:8088/stop" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
    } catch {}
    if ($serverProc -and -not $serverProc.HasExited) {
        Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue
    }
}

Write-Log "==========================================================" "TITLE"
Write-Log "Test Suite Results: $passedCount / $totalTests Tests Passed" $(if ($passedCount -eq $totalTests) { "SUCCESS" } else { "ERROR" })
Write-Log "==========================================================" "TITLE"

exit $(if ($passedCount -eq $totalTests) { 0 } else { 1 })
