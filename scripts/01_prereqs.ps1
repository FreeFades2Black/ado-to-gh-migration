# ==============================================================================
# Script 01: Setup & Verify Prerequisites
# ==============================================================================
[CmdletBinding()]
param()

$commonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00_common.ps1"
. $commonPath

Write-Log "==========================================================" "TITLE"
Write-Log "Prerequisites & Tooling Verification" "TITLE"
Write-Log "==========================================================" "TITLE"

$passed = Test-Prerequisites -RequireGEI $false

# Attempt auto-install of gh-gei if gh is present
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $exts = gh extension list
    if ($exts -notmatch "gei") {
        Write-Log "Installing GitHub Enterprise Importer (GEI) extension..." "INFO"
        gh extension install github/gh-gei
        if ($LASTEXITCODE -eq 0) {
            Write-Log "gh-gei successfully installed!" "SUCCESS"
            $passed = $true
        } else {
            Write-Log "Failed to install gh-gei automatically." "ERROR"
            $passed = $false
        }
    } else {
        Write-Log "Checking for gh-gei updates..." "INFO"
        gh extension upgrade gei
        Write-Log "gh-gei extension is up to date." "SUCCESS"
        $passed = $true
    }
}

# Environment validation
Load-EnvFile
$adoOrg = [System.Environment]::GetEnvironmentVariable("ADO_ORG")
$ghOrg = [System.Environment]::GetEnvironmentVariable("GH_ORG")
$mode = [System.Environment]::GetEnvironmentVariable("MIGRATION_MODE")

if (-not $mode) {
    [System.Environment]::SetEnvironmentVariable("MIGRATION_MODE", "live", [System.EnvironmentVariableTarget]::Process)
    $mode = "live"
}

Write-Log "Active Migration Mode: $mode" "INFO"
if ($mode -eq "live") {
    if (-not $adoOrg -or $adoOrg -eq "your-ado-organization") {
        Write-Log "ADO_ORG not configured in .env (current: '$adoOrg')." "WARN"
    }
    if (-not $ghOrg -or $ghOrg -eq "your-target-github-org") {
        Write-Log "GH_ORG not configured in .env (current: '$ghOrg')." "WARN"
    }
} else {
    Write-Log "Running in Mock / Sandbox test mode." "SUCCESS"
}

if ($passed) {
    Write-Log "All system prerequisites are satisfied and ready!" "SUCCESS"
} else {
    Write-Log "Prerequisites check found issues. Review output above." "WARN"
}

exit $(if ($passed) { 0 } else { 1 })
