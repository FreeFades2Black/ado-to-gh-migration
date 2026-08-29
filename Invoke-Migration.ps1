# ==============================================================================
# Azure DevOps to GitHub Enterprise Migration Suite (Main CLI Entry Point)
# ==============================================================================
[CmdletBinding()]
param(
    [ValidateSet("all", "prereqs", "inventory", "migrate-single", "bulk", "verify", "test", "menu")][string]$Action = "menu",
    [ValidateSet("live", "mock")][string]$Mode,
    [string]$Repo,
    [switch]$DryRun,
    [switch]$ResumeOnly,
    [switch]$Force
)

$rootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir = Join-Path $rootDir "scripts"
$commonPath = Join-Path $scriptsDir "00_common.ps1"
. $commonPath

Load-EnvFile

if ($Mode) {
    [System.Environment]::SetEnvironmentVariable("MIGRATION_MODE", $Mode, [System.EnvironmentVariableTarget]::Process)
}

function Show-Banner {
    Clear-Host
    Write-Host @"
================================================================================
   AZURE DEVOPS TO GITHUB ENTERPRISE MIGRATION SUITE
   Powered by GitHub Enterprise Importer (GEI) & PowerShell Automation
================================================================================
"@ -ForegroundColor Cyan
}

function Show-Menu {
    Show-Banner
    Write-Host " [1] Check & Install Prerequisites (gh, gh-gei, git)" -ForegroundColor Yellow
    Write-Host " [2] Inventory ADO Repositories (Generate Manifest)" -ForegroundColor Yellow
    Write-Host " [3] Migrate a Single Repository" -ForegroundColor Yellow
    Write-Host " [4] Run Bulk Migration Orchestrator" -ForegroundColor Yellow
    Write-Host " [5] Post-Migration Integrity Verification" -ForegroundColor Yellow
    Write-Host " [6] Run End-to-End Mock Sandbox Test Suite" -ForegroundColor Green
    Write-Host " [0] Exit" -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
    
    $choice = Read-Host "Select an option [0-6]"
    switch ($choice) {
        "1" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "01_prereqs.ps1") }
        "2" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "02_inventory_repos.ps1") }
        "3" {
            $target = Read-Host "Enter ADO repository name to migrate"
            if ($target) {
                & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "03_migrate_repo.ps1") -AdoRepo $target
            }
        }
        "4" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "04_bulk_migrate.ps1") }
        "5" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "05_verify_migration.ps1") }
        "6" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rootDir "mock\test_mock_migration.ps1") }
        "0" { exit 0 }
        default { Write-Host "Invalid option." -ForegroundColor Red }
    }
}

# Non-interactive CLI Routing
switch ($Action) {
    "prereqs" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "01_prereqs.ps1")
    }
    "inventory" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "02_inventory_repos.ps1")
    }
    "migrate-single" {
        if (-not $Repo) { Write-Log "Specify -Repo <name> for single migration." "ERROR"; exit 1 }
        $argsList = @("-AdoRepo", $Repo)
        if ($DryRun) { $argsList += "-DryRun" }
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "03_migrate_repo.ps1") @argsList
    }
    "bulk" {
        $argsList = @()
        if ($DryRun) { $argsList += "-DryRun" }
        if ($ResumeOnly) { $argsList += "-ResumeOnly" }
        if ($Force) { $argsList += "-ForceAll" }
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "04_bulk_migrate.ps1") @argsList
    }
    "verify" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "05_verify_migration.ps1")
    }
    "test" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rootDir "mock\test_mock_migration.ps1")
    }
    "all" {
        Write-Log "Executing full migration pipeline..." "TITLE"
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "01_prereqs.ps1")
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "02_inventory_repos.ps1")
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "04_bulk_migrate.ps1")
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsDir "05_verify_migration.ps1")
    }
    "menu" {
        Show-Menu
    }
}
