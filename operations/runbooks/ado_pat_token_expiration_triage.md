# Operational Runbook: ADO PAT Scope Failure & Secondary Rate-Limit Triage

**Severity:** P2 / Migration Batch Stalled  
**Target Systems:** Azure DevOps REST API, GitHub Enterprise Importer

## Diagnostic Workflow

### 1. Verify ADO Personal Access Token (PAT) Scopes
```powershell
$headers = @{ Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$env:ADO_PAT")) }
Invoke-RestMethod -Uri "https://dev.azure.com/$env:ADO_ORG/_apis/projects?api-version=7.0" -Headers $headers
```
If HTTP 401/403: Verify PAT contains `Code (Full)`, `Work Items (Read & Write)`, and `Identity (Read)`.

### 2. Diagnose GitHub Secondary Rate-Limit Throttling
Inspect response headers for `x-ratelimit-remaining` and `retry-after`:
```powershell
$resp = Invoke-WebRequest -Uri "https://api.github.com/rate_limit" -Headers @{ Authorization = "Bearer $env:GH_PAT" }
$resp.Headers["x-ratelimit-remaining"]
```

### 3. Step-by-Step Remediation
1. If rate limited, sleep for the duration indicated by `retry-after` (typically 60s).
2. Re-run migration script in idempotent resume mode:
   ```powershell
   .\Invoke-Migration.ps1 -Resume -StateFile config\migration-state.json
   ```
