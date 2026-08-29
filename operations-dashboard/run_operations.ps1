# ==============================================================================
# Dual-Run Operations Suite Launcher
# Starts Source App (8001), Target App (8002), and Operations Gateway (8000)
# ==============================================================================
param(
    [switch]$NoBrowser,
    [int]$Simulate = 30
)

$dashboardDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $dashboardDir

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   DUAL-RUN OPERATIONS TESTBED: ZERO-DOWNTIME MIGRATION VALIDATOR" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 1. Initialize Database
Write-Host "[*] Initializing shared database dependency..." -ForegroundColor Yellow
python shared_db.py

# Function to stop existing processes on our ports
function Stop-PortProcess {
    param([int]$Port)
    $conn = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($conn) {
        $pids = $conn.OwningProcess | Select-Object -Unique
        foreach ($p in $pids) {
            Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "[*] Cleaning up existing ports (8800, 8801, 8802)..." -ForegroundColor DarkGray
Stop-PortProcess -Port 8800
Stop-PortProcess -Port 8801
Stop-PortProcess -Port 8802

# 2. Start Source ADO App (8801)
Write-Host "[*] Starting Source Application (ADO Deployment on :8801)..." -ForegroundColor Yellow
$procAdo = [System.Diagnostics.Process]::Start((New-Object System.Diagnostics.ProcessStartInfo -Property @{
    FileName = "python.exe"
    Arguments = "service_source_ado.py"
    WorkingDirectory = $dashboardDir
    WindowStyle = "Hidden"
    CreateNoWindow = $true
    UseShellExecute = $false
}))

# 3. Start Target GitHub App (8802)
Write-Host "[*] Starting Target Application (GitHub Deployment on :8802)..." -ForegroundColor Yellow
$procGh = [System.Diagnostics.Process]::Start((New-Object System.Diagnostics.ProcessStartInfo -Property @{
    FileName = "python.exe"
    Arguments = "service_target_github.py"
    WorkingDirectory = $dashboardDir
    WindowStyle = "Hidden"
    CreateNoWindow = $true
    UseShellExecute = $false
}))

# 4. Start Operations Gateway (8800)
Write-Host "[*] Starting Operations Gateway & Parity Dashboard on :8800..." -ForegroundColor Green
$procGateway = [System.Diagnostics.Process]::Start((New-Object System.Diagnostics.ProcessStartInfo -Property @{
    FileName = "python.exe"
    Arguments = "operations_gateway.py"
    WorkingDirectory = $dashboardDir
    WindowStyle = "Hidden"
    CreateNoWindow = $true
    UseShellExecute = $false
}))

Start-Sleep -Seconds 2

# 5. Verify Health of all 3 Nodes
Write-Host "`n--- Performing Pre-Flight Health Checks ---" -ForegroundColor Cyan
$endpoints = @(
    @{ Name = "Source ADO App"; Url = "http://127.0.0.1:8801/health" },
    @{ Name = "Target GitHub App"; Url = "http://127.0.0.1:8802/health" },
    @{ Name = "Operations Gateway"; Url = "http://127.0.0.1:8800/api/gateway/stats" }
)

$allHealthy = $true
foreach ($ep in $endpoints) {
    try {
        $resp = Invoke-RestMethod -Uri $ep.Url -Method Get -TimeoutSec 3
        Write-Host "  [+] $($ep.Name) is ONLINE and HEALTHY" -ForegroundColor Green
    } catch {
        Write-Host "  [-] $($ep.Name) FAILED health check: $($_.Exception.Message)" -ForegroundColor Red
        $allHealthy = $false
    }
}

if (-not $allHealthy) {
    Write-Host "`n[!] Some services failed to start. Review processes." -ForegroundColor Red
    exit 1
}

# 6. Fire Initial Test Traffic
if ($Simulate -gt 0) {
    Write-Host "`n[*] Firing initial $Simulate dual-run shadow transactions through the Gateway..." -ForegroundColor Cyan
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:8800/api/gateway/simulate/$Simulate" -Method Post | Out-Null
        Start-Sleep -Seconds 2
        $stats = Invoke-RestMethod -Uri "http://127.0.0.1:8800/api/gateway/stats" -Method Get
        Write-Host "  [+] Transactions Processed: $($stats.total_requests)" -ForegroundColor Green
        Write-Host "  [+] Parity Match Rate     : $($stats.parity_rate_percent)%" -ForegroundColor Green
        Write-Host "  [+] Discrepancies         : $($stats.discrepancies)" -ForegroundColor Green
        Write-Host "  [+] ADO Avg Latency       : $($stats.avg_ado_latency_ms) ms" -ForegroundColor Yellow
        Write-Host "  [+] GitHub Avg Latency    : $($stats.avg_gh_latency_ms) ms" -ForegroundColor Green
    } catch {
        Write-Host "[-] Simulation call failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "   DUAL-RUN OPERATIONS DASHBOARD READY: http://127.0.0.1:8800" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "Press Ctrl+C or run 'Stop-Process -Id $($procAdo.Id), $($procGh.Id), $($procGateway.Id)' to stop all services.`n" -ForegroundColor DarkGray

if (-not $NoBrowser) {
    Start-Process "http://127.0.0.1:8800"
}

Write-Host "[*] Operations Gateway is listening on http://127.0.0.1:8800 (Press Ctrl+C to terminate)..." -ForegroundColor Cyan
while ($true) {
    Start-Sleep -Seconds 1
}
