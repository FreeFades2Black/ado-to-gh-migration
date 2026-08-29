# ==============================================================================
# Mock Azure DevOps REST API Server for Local Sandbox Testing
# ==============================================================================
param(
    [int]$Port = 8088
)

$prefix = "http://127.0.0.1:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Host "[+] Mock ADO Server running on $prefix" -ForegroundColor Green
    Write-Host "[*] Press Ctrl+C or send GET /stop to terminate." -ForegroundColor Cyan
    
    $running = $true
    while ($running) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        $path = $request.Url.AbsolutePath
        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $($request.HttpMethod) $path" -ForegroundColor DarkGray
        
        if ($path -eq "/stop") {
            $running = $false
            $buffer = [System.Text.Encoding]::UTF8.GetBytes("Server stopped.")
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
            break
        }
        
        # Endpoint: /_apis/git/repositories
        if ($path -match "_apis/git/repositories") {
            $mockData = @{
                count = 4
                value = @(
                    @{
                        id = "a1b2c3d4-0001-4000-8000-000000000001"
                        name = "frontend-core"
                        size = 45219800
                        defaultBranch = "refs/heads/main"
                        isDisabled = $false
                        webUrl = "https://dev.azure.com/mock-org/mock-project/_git/frontend-core"
                    },
                    @{
                        id = "a1b2c3d4-0002-4000-8000-000000000002"
                        name = "backend-api"
                        size = 128940000
                        defaultBranch = "refs/heads/main"
                        isDisabled = $false
                        webUrl = "https://dev.azure.com/mock-org/mock-project/_git/backend-api"
                    },
                    @{
                        id = "a1b2c3d4-0003-4000-8000-000000000003"
                        name = "shared-utils-lib"
                        size = 15200300
                        defaultBranch = "refs/heads/master"
                        isDisabled = $false
                        webUrl = "https://dev.azure.com/mock-org/mock-project/_git/shared-utils-lib"
                    },
                    @{
                        id = "a1b2c3d4-0004-4000-8000-000000000004"
                        name = "infra-terraform"
                        size = 8900200
                        defaultBranch = "refs/heads/main"
                        isDisabled = $false
                        webUrl = "https://dev.azure.com/mock-org/mock-project/_git/infra-terraform"
                    }
                )
            }
            
            $jsonString = $mockData | ConvertTo-Json -Depth 10
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonString)
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        } else {
            $response.StatusCode = 404
            $buffer = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.Close()
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
    Write-Host "[+] Mock Server closed." -ForegroundColor Yellow
}
