# Azure DevOps to GitHub Migration Suite

An automation toolkit and operational testbed for discovering, sanitizing, migrating, and verifying Git repositories transitioning from Azure DevOps (ADO) to GitHub Enterprise or GitHub.com.

---

## Architecture and Migration Lifecycle

```text
[ SOURCE: AZURE DEVOPS ]                 [ DUAL-RUN OPERATIONS GATEWAY ]              [ TARGET: GITHUB ENTERPRISE ]
├── Git Repositories       ───────►      ├── Real-Time Traffic Mirroring (Shadow)  ──► ├── Git Repositories (Full History)
├── Commit Trees & Tags    (GEI CLI)     ├── Payload & Response Diff Engine            ├── Semantic Version Tags
├── Branches & PR Metadata               ├── Dynamic Canary Traffic Split (0-100%)     ├── Converted GitHub Actions CI
└── Pipelines (YAML)                     └── Local Telemetry Dashboard                 └── Zero-Trust OIDC Integration
```

---

## Azure DevOps to GitHub Actions Pipeline Translation Guide

Translating Azure DevOps (ADO) YAML pipelines into GitHub Actions YAML workflows involves mapping structural concepts, triggers, runner pools, and built-in tasks to their GitHub equivalents.

### 1. Core Concept Mapping

| Azure DevOps Concept | GitHub Actions Equivalent | Description |
| :--- | :--- | :--- |
| **Pipeline file location** | `azure-pipelines.yml` (root) | `.github/workflows/<name>.yml` |
| **Pipeline structure** | `stages` $\rightarrow$ `jobs` $\rightarrow$ `steps` | `jobs` $\rightarrow$ `steps` *(stages map to job dependencies `needs:`)* |
| **Triggers** | `trigger:` / `pr:` | `on: push:` / `on: pull_request:` |
| **Manual / Scheduled** | `schedules:` | `on: schedule:` / `on: workflow_dispatch:` |
| **Runner / Agent Pool** | `pool: vmImage: 'ubuntu-latest'` | `runs-on: ubuntu-latest` |
| **Scripts / Commands** | `script:` / `bash:` / `powershell:` | `run: \|` |
| **Built-in Tasks** | `task: TaskName@Version` | `uses: action-name@vX` |
| **Variables** | `variables:` | `env:` / `vars.` |
| **Secrets / Variable Groups**| Azure KeyVault / Variable Groups | `${{ secrets.SECRET_NAME }}` / Environments |
| **Artifacts** | `PublishBuildArtifacts@1` | `actions/upload-artifact@v4` |

---

### 2. Common Built-in Tasks Translation

| Azure DevOps Task | GitHub Actions Equivalent Action |
| :--- | :--- |
| **Code Checkout** *(implicit in ADO)* | `uses: actions/checkout@v4` |
| `task: UsePythonVersion@0` | `uses: actions/setup-python@v5` |
| `task: NodeTool@0` | `uses: actions/setup-node@v4` |
| `task: SetupDotnet@2` | `uses: actions/setup-dotnet@v4` |
| `task: PublishBuildArtifacts@1` | `uses: actions/upload-artifact@v4` |
| `task: DownloadBuildArtifacts@0`| `uses: actions/download-artifact@v4` |
| `task: Docker@2` | `uses: docker/build-push-action@v5` |
| `task: AzureCLI@2` | `uses: azure/login@v2` + `run: az ...` |
| `task: Kubernetes@1` | `uses: azure/k8s-set-context@v4` |

---

### 3. Side-by-Side Pipeline Code Example

#### Azure DevOps Pipeline (`azure-pipelines.yml`)
```yaml
trigger:
  branches:
    include:
      - main
      - releases/*

pool:
  vmImage: 'ubuntu-latest'

variables:
  PYTHON_VERSION: '3.12'
  ENVIRONMENT: 'production'

steps:
  - task: UsePythonVersion@0
    inputs:
      versionSpec: '$(PYTHON_VERSION)'
    displayName: 'Setup Python'

  - script: |
      python -m pip install --upgrade pip
      pip install -r requirements.txt
    displayName: 'Install Dependencies'

  - script: pytest tests/ --junitxml=junit.xml
    displayName: 'Run Unit Tests'

  - task: PublishTestResults@2
    inputs:
      testResultsFiles: '**/junit.xml'
    condition: succeededOrFailed()
```

#### Converted GitHub Actions Workflow (`.github/workflows/ci.yml`)
```yaml
name: CI Pipeline

on:
  push:
    branches:
      - main
      - 'releases/**'
  pull_request:
    branches: [ main ]
  workflow_dispatch:

env:
  PYTHON_VERSION: '3.12'
  ENVIRONMENT: 'production'

jobs:
  build-and-test:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Install Dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt

      - name: Run Unit Tests
        run: pytest tests/ --junitxml=junit.xml

      - name: Publish Test Results
        if: always()
        uses: EnricoMi/publish-unit-test-result-action@v2
        with:
          files: '**/junit.xml'
```

---

### 4. Technical Considerations

1. **Explicit Checkout:** Azure DevOps automatically checks out code before step 1. GitHub Actions requires an explicit `- uses: actions/checkout@v4` step.
2. **Conditional Execution:** ADO uses `condition: succeededOrFailed()`. GitHub Actions uses `if: always()`, `if: success()`, or `if: failure()`.
3. **Authentication (Service Connections vs OIDC):** Replace long-lived service principal keys with OpenID Connect (`permissions: id-token: write`) to exchange short-lived tokens directly with Azure Managed Identity or AWS IAM.
4. **Job Dependencies:** Map ADO `dependsOn: JobA` inside stages to GitHub Actions `needs: job-a` at the job level.

---

## Migration and Governance Lifecycle

1. **Phase 1: Discovery & Triage (`scripts/02_triage_audit.py`)**
   - Flags inactive repositories (>365 days) for cold archive exclusion.
   - Inspects dependency manifests (`pom.xml`, `package.json`, `requirements.txt`, `go.mod`) to build an SBOM inventory.
   - Categorizes ephemeral test repos (`*poc*`, `*scratch*`, `*test*`).

2. **Phase 2: Secret Sanitization & History Scrubbing (`scripts/03_sanitize_and_scrub.py`)**
   - Scans Git history for exposed cloud keys, PATs, and private keys.
   - Strips ephemeral files (`.env`, `*.key`, `*.pfx`, `*.tfstate`).
   - Identifies objects >50MB for Git LFS migration before hitting GitHub's 100MB limit.

3. **Phase 3: Zero-Trust OIDC Integration (`templates/oidc_zero_trust_pipeline.yml`)**
   - Configures federated token authentication for GitHub Actions.
   - Eliminates static cloud credentials in repository secrets.

4. **Phase 4: Post-Migration Audit (`scripts/05_verify_migration.ps1`, `scripts/05_compliance_audit.py`)**
   - Verifies commit count and ref parity across source and target repositories.
   - Exports JSON audit trails to `config/compliance-audit-report.json`.

---

## Dual-Run Operations Gateway

The `operations-dashboard/` service provides a local reverse proxy on port `8800` to mirror requests between legacy ADO deployment targets and GitHub Actions endpoints, measuring latency differentials and payload hashes during cutover.

```bash
# Run local dual-run simulation gateway (PowerShell / Windows)
cd operations-dashboard
powershell -ExecutionPolicy Bypass -File run_operations.ps1

# Linux / macOS
cd operations-dashboard
./run_operations.sh
```

---

## Repository Structure

```text
ado-to-gh-migration/
├── README.md                              # Master Architecture Documentation & Guide
├── README-PLAYBOOK.md                     # Security & History Scrubbing Playbook
├── Invoke-Migration.ps1                   # Interactive CLI & Pipeline Orchestrator
├── config/
│   ├── repos.csv                          # Discovered repository manifest
│   ├── user-mapping.csv                   # ADO email -> GitHub handle mapping
│   ├── triage-manifest.json               # Phase 1 Triage Audit Report
│   └── compliance-audit-report.json       # Phase 4 Compliance Audit Report
├── scripts/
│   ├── 00_common.ps1                      # Shared logging, state, and environment module
│   ├── 01_prereqs.ps1                     # Toolchain validation (gh, gh-gei, git)
│   ├── 02_inventory_repos.ps1             # ADO REST API inventory discovery
│   ├── 02_triage_audit.py                 # Phase 1 Triage & Staleness Analyzer
│   ├── 03_migrate_repo.ps1                # Single repository migrator with retry backoff
│   ├── 03_sanitize_and_scrub.py           # Phase 2 Secret & Bloat Scrubber
│   ├── 04_bulk_migrate.ps1                # Bulk orchestrator with checkpoint resume
│   ├── 05_verify_migration.ps1            # Post-migration refcount & diff validator
│   └── 05_compliance_audit.py             # Phase 4 Cryptographic Audit Generator
├── templates/
│   └── oidc_zero_trust_pipeline.yml       # OIDC Federated Cloud Auth Template
├── operations-dashboard/
│   ├── operations_gateway.py              # Shadow proxy & live web UI (:8800)
│   ├── service_source_ado.py              # Source ADO build instance (:8801)
│   ├── service_target_github.py           # Target GitHub build instance (:8802)
│   ├── shared_db.py                       # Shared state database layer
│   ├── run_operations.sh                  # Linux launcher script
│   └── run_operations.ps1                 # Windows launcher script
└── mock/
    ├── mock_ado_server.ps1                # Local mock ADO REST API server
    └── test_mock_migration.ps1            # Automated end-to-end sandbox test suite
```

---

## Concrete Test Artifacts & Execution Logs

### Mock End-to-End Test Suite Execution (`mock/test_mock_migration.ps1`)

Raw capture from test execution against local mock ADO REST API:

```text
==========================================================
ADO-to-GitHub Migration Test Suite: Mock End-to-End Run
==========================================================
[*] Starting Mock ADO Server on localhost:8088...

--- Running Test 1: Prerequisites Check ---
[+] Git found: git version 2.42.0.windows.2
[+] GitHub CLI found: gh version 2.97.0 (2026-07-31)
[!] gh-gei extension not installed (skipped for mock sandbox mode).
[*] Active Migration Mode: mock
[+] Running in Mock / Sandbox test mode.
[+] All system prerequisites are satisfied and ready!
[+] [PASS] Prerequisites verification executed

--- Running Test 2: Inventory Discovery ---
[+] Discovered 4 repositories from ADO:
  - frontend-core
  - backend-api
  - shared-utils-lib
  - infra-terraform
[+] Saved repository inventory to: config/repos.csv
[+] [PASS] Inventory generated manifest with 4 repositories

--- Running Test 3: Single Repo Migration ---
[+] Mock migration completed successfully for frontend-core -> FreeFades2Black/frontend-core
[+] [PASS] Single repo migrated and recorded in state

--- Running Test 4: Bulk Migration ---
[*] [1/4 - 25%] Skipping frontend-core (Already completed in state).
[*] [2/4 - 50%] Processing: backend-api -> FreeFades2Black/backend-api
[+] Mock migration completed successfully for backend-api -> FreeFades2Black/backend-api
[*] [3/4 - 75%] Processing: shared-utils-lib -> FreeFades2Black/shared-utils-lib
[+] Mock migration completed successfully for shared-utils-lib -> FreeFades2Black/shared-utils-lib
[*] [4/4 - 100%] Processing: infra-terraform -> FreeFades2Black/infra-terraform
[+] Mock migration completed successfully for infra-terraform -> FreeFades2Black/infra-terraform
[+] [PASS] All 4 repositories marked COMPLETED in state

--- Running Test 5: Checkpoint Resumption ---
[+] [1/4 - 25%] Skipping frontend-core (Already completed in state).
[+] [2/4 - 50%] Skipping backend-api (Already completed in state).
[+] [3/4 - 75%] Skipping shared-utils-lib (Already completed in state).
[+] [4/4 - 100%] Skipping infra-terraform (Already completed in state).
[+] [PASS] Bulk migration idempotent (skips already completed repos)

--- Running Test 6: Post-Migration Audit Verification ---
Repository       ADO_Commits GH_Commits Branches_Match Tags_Match Verdict       
----------       ----------- ---------- -------------- ---------- -------       
frontend-core            142        142           True       True VERIFIED_MATCH
backend-api              142        142           True       True VERIFIED_MATCH
shared-utils-lib         142        142           True       True VERIFIED_MATCH
infra-terraform          142        142           True       True VERIFIED_MATCH

[+] [PASS] Post-migration verification completed successfully
[*] Shutting down mock server...
==========================================================
[+] Test Suite Results: 6 / 6 Tests Passed
==========================================================
```

### Repository Triage Output (`scripts/02_triage_audit.py`)

```text
[*] Auditing repositories in: .
================================================================================
PHASE 1: REPOSITORY TRIAGE AND STALENESS AUDIT MANIFEST
================================================================================
[OK] [ACTIVE] ado-to-gh-migration
   - Last active: 0 days ago | Commits: 7 | Branches: 2
   - Stack: Python, PowerShell | Action: Approved for GitHub Enterprise Migration

[+] Saved Triage Manifest to: config/triage-manifest.json
```

---

## Edge Cases & Engineering Trade-Offs

1. **Large File Blobs and Git LFS Conversion:**
   GitHub strictly rejects single files over 100MB during pushes. If historical commits contain large binaries, running a direct mirror push will fail. Repositories must be audited with `03_sanitize_and_scrub.py` or `git-filter-repo --analyze` to identify objects >50MB and convert them to Git LFS pointer tracking prior to remote migration.

2. **Commit History Rewriting vs. In-Flight PRs:**
   Using `git-filter-repo` to redact leaked API keys or credentials alters commit SHA hashes throughout the Git tree. Any branches or open pull requests created before the rewrite will have disconnected parent SHAs. Sanitization passes must be scheduled during a maintenance freeze window or performed immediately after importing to a private target repository.

3. **PowerShell Variable Scope Disambiguation on Windows:**
   In PowerShell strings, expressions such as `"$attempt: $error"` cause the parser to treat `$attempt:` as a drive-qualified variable name, throwing `Variable reference is not valid`. String interpolations must use explicit curly delimiters (`"${attempt}: $error"`).

4. **Windows Console Character Encoding:**
   Standard Windows command prompts default to legacy code page 1252 (`cp1252`). Python automation scripts printing Unicode decoration or emojis fail with fatal `UnicodeEncodeError` crashes unless `sys.stdout.reconfigure(encoding='utf-8')` is enabled or standard ASCII markers (`[OK]`, `[WARN]`, `[ERROR]`) are used.

5. **Rate Limiting & Exponential Retry Strategy:**
   Azure DevOps REST APIs enforce rate limits per organization. Script `03_migrate_repo.ps1` implements exponential backoff (`Math.Pow(2, attempt) * 5` seconds) up to a maximum of 3 retries to gracefully handle transient network timeouts and HTTP 429 throttling during large migrations.
