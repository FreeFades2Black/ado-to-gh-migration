# 🚀 Azure DevOps to GitHub Enterprise Migration Suite & Dual-Run Operations Gateway

An enterprise-grade automation framework and live operational testbed for discovering, sanitizing, migrating, and verifying repositories from Azure DevOps (ADO) to GitHub Enterprise with **zero downtime, 100% commit parity, and zero performance loss**.

---

## 🌟 Core Architecture & Capabilities

```text
[ SOURCE: AZURE DEVOPS ]                 [ DUAL-RUN OPERATIONS GATEWAY ]              [ TARGET: GITHUB ENTERPRISE ]
├── Git Repositories       ───────►      ├── Real-Time Traffic Mirroring (Shadow)  ──► ├── Git Repositories (Full History)
├── Commit Trees & Tags    (GEI CLI)     ├── Payload & Response Diff Engine            ├── Semantic Version Tags
├── Branches & PR Metadata               ├── Dynamic Canary Traffic Split (0-100%)     ├── Converted GitHub Actions CI
└── Pipelines (YAML)                     └── Live Performance Telemetry Dashboard      └── Zero-Trust OIDC Integration
```

---

## 🔄 Azure DevOps to GitHub Actions Pipeline Translation Guide

Translating **Azure DevOps (ADO) YAML pipelines** into **GitHub Actions YAML workflows** involves mapping structural concepts, triggers, runner pools, and built-in tasks to their GitHub equivalents.

### 1. Core Architectural Concept Mapping

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

### 2. Common Built-in Tasks Translation (Rosetta Stone)

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

#### 🟠 Azure DevOps Pipeline (`azure-pipelines.yml`)
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

#### 🟢 Converted GitHub Actions Workflow (`.github/workflows/ci.yml`)
```yaml
name: CI Pipeline

on:
  push:
    branches:
      - main
      - 'releases/**'
  pull_request:
    branches: [ main ]
  workflow_dispatch: # Allows manual trigger

env:
  PYTHON_VERSION: '3.12'
  ENVIRONMENT: 'production'

jobs:
  build-and-test:
    runs-on: ubuntu-latest

    steps:
      # Step 1: Explicit checkout required in GitHub Actions
      - name: Checkout Code
        uses: actions/checkout@v4

      # Step 2: Tool setup using Marketplace Action
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      # Step 3: Run Shell Script
      - name: Install Dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt

      # Step 4: Run Tests
      - name: Run Unit Tests
        run: pytest tests/ --junitxml=junit.xml

      # Step 5: Test Reporting with Execution Condition
      - name: Publish Test Results
        if: always() # Equivalent to succeededOrFailed()
        uses: EnricoMi/publish-unit-test-result-action@v2
        with:
          files: '**/junit.xml'
```

---

### 4. Key Differences to Watch Out For

1. **Explicit Checkout:**
   * In Azure DevOps, the pipeline automatically checks out code before step 1.
   * In GitHub Actions, you **must explicitly add** `- uses: actions/checkout@v4` as your first step.
2. **Conditional Execution:**
   * ADO: `condition: succeededOrFailed()`, `condition: always()`
   * GitHub Actions: `if: always()`, `if: success()`, `if: failure()`, `if: cancelled()`
3. **Cloud Authentication (Service Connections vs OIDC):**
   * In ADO, service connections store Azure Service Principals or AWS keys.
   * In GitHub Actions, best practice is to configure **OpenID Connect (OIDC)** with `permissions: id-token: write` so workflows authenticate to AWS/Azure using short-lived JWT tokens without static secrets.
4. **Multi-Job Dependencies:**
   * ADO uses `dependsOn: JobA` inside `stages:`.
   * GitHub Actions uses `needs: job-a` at the job level.

---

## 🛡️ 4-Phase Enterprise Security & Governance Lifecycle

1. **Phase 1: Discovery & Triage (`scripts/02_triage_audit.py`)**
   - Automatically audits commit staleness (>365 days -> `COLD_ARCHIVE` exclusion gate).
   - Scans dependency lockfiles to generate Software Bill of Materials (SBOM) metadata.
   - Filters ephemeral test repos (`*poc*`, `*scratch*`, `*test*`).

2. **Phase 2: In-Flight Secret Sanitization (`scripts/03_sanitize_and_scrub.py`)**
   - Scans full commit history for leaked credentials (AWS keys, GitHub PATs, private keys).
   - Scrubs sensitive files (`.env`, `*.key`, `*.pfx`, `*.tfstate`).
   - Identifies binary blobs >50MB and migrates them to Git LFS tracking.

3. **Phase 3: Zero-Trust OIDC Governance (`templates/oidc_zero_trust_pipeline.yml`)**
   - Enforces **Zero Static Cloud Keys** in GitHub Repository Secrets.
   - Authenticates GitHub Actions directly with AWS IAM & Azure Managed Identity via short-lived OIDC JWTs.

4. **Phase 4: Post-Migration Cryptographic Audit (`scripts/05_compliance_audit.py`)**
   - Verifies `source_commits == target_commits` with SHA tree parity.
   - Exports certified compliance reports to `config/compliance-audit-report.json`.

---

## 📊 Dual-Run Operations Gateway

The suite includes an active **Dual-Run Operations Gateway** running on port `8800`:
* **Live Web Dashboard:** Real-time latency comparison (ms), throughput gauges, and discrepancy audit stream.
* **Zero-Downtime Canary Cutover:** Slider controlling primary route traffic between legacy ADO and modernized GitHub builds.

---

## 📁 Repository Structure

```text
ado-to-gh-migration/
├── README.md                              # Master Architecture Documentation & Conversion Guide
├── README-PLAYBOOK.md                     # Enterprise Migration Security Playbook
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
│   ├── 03_migrate_repo.ps1                # Resilient single migrator with exponential backoff
│   ├── 03_sanitize_and_scrub.py           # Phase 2 Secret & Bloat Scrubber
│   ├── 04_bulk_migrate.ps1                # Bulk orchestrator with checkpoint resume support
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

## 🚀 Quickstart

```bash
# Launch the Operations Dashboard on Omarchy
cd operations-dashboard
./run_operations.sh

# Open Dashboard in your browser:
# http://192.168.50.53:8800
```

---

## 🌐 Omarchy Migration & GitOps Ecosystem Map

All repositories in this project are interconnected and indexed under the GitHub topic [`omarchy-gitops-ecosystem`](https://github.com/topics/omarchy-gitops-ecosystem):

| Repository | Role in Ecosystem | Service Route / Port | Primary Topic Tags |
| :--- | :--- | :---: | :--- |
| 🎛️ [**`ado-to-gh-migration`**](https://github.com/FreeFades2Black/ado-to-gh-migration) | **Master Migration Suite & Operations Gateway** | `:8800` (Gateway) | `migration-toolkit`, `dual-run-canary` |
| ⚡ [**`omarchy-gitops-forge`**](https://github.com/FreeFades2Black/omarchy-gitops-forge) | **1,000-Commit Forge & CI Matrix Testbed** | CI Matrix Engine | `1000-commits`, `ci-cd-matrix` |
| 🔐 [**`omarchy-auth-service`**](https://github.com/FreeFades2Black/omarchy-auth-service) | **OAuth2 & JWT Zero-Trust Identity Service** | `:8810` / Gateway | `oauth2`, `zero-trust` |
| 💳 [**`omarchy-payment-vault`**](https://github.com/FreeFades2Black/omarchy-payment-vault) | **Encrypted Transaction Settlement Gateway** | `:8820` / Gateway | `payments`, `encryption` |
| 📈 [**`omarchy-analytics-engine`**](https://github.com/FreeFades2Black/omarchy-analytics-engine) | **Real-Time Streaming Telemetry & Metrics** | `:8830` / Gateway | `telemetry`, `analytics` |
| 📦 [**`omarchy-order-fulfillment`**](https://github.com/FreeFades2Black/omarchy-order-fulfillment) | **Distributed Logistics & Order Dispatch Engine** | `:8840` / Gateway | `logistics`, `order-routing` |

---

---

## 🔍 Internal Code Architecture & Comprehensive Inline Documentation

> **Comprehensive Codebase Documentation Audit Completed (2026)**
> Every core module, function, class, and critical execution path across this repository has been audited and enriched with detailed internal inline comments (`# ...`) and comprehensive docstrings. Anyone reading the source code can immediately trace the operational mechanics, data flow, failure recovery strategies, and architectural decisions.

### 🧩 Key Codebase Modules & Internal Mechanics Walkthrough

| File / Component | Purpose & Internal Mechanics |
| :--- | :--- |
| [`operations-dashboard/operations_gateway.py`](operations-dashboard/operations_gateway.py) | FastAPI reverse proxy gateway mirroring 50/50 live traffic between legacy ADO and target GitHub clusters. |
| [`operations-dashboard/shared_db.py`](operations-dashboard/shared_db.py) | SQLite persistent datastore maintaining transaction logs, latency metrics, and parity audit discrepancies. |
| [`operations-dashboard/service_source_ado.py`](operations-dashboard/service_source_ado.py) | Legacy Azure DevOps service node simulating enterprise SQLite processing and legacy pipeline execution. |
| [`operations-dashboard/service_target_github.py`](operations-dashboard/service_target_github.py) | Migrated GitHub Enterprise service node simulating containerized GitHub Actions execution. |
| [`scripts/02_triage_audit.py`](scripts/02_triage_audit.py) | Automated pre-migration repo auditor scanning branch protections, PR policies, and secret leakage. |
| [`scripts/03_sanitize_and_scrub.py`](scripts/03_sanitize_and_scrub.py) | Secret scrubber removing hardcoded tokens, internal domains, and legacy credentials prior to migration. |
| [`scripts/05_compliance_audit.py`](scripts/05_compliance_audit.py) | Post-migration compliance scanner validating SOC2/FedRAMP controls and OIDC zero-trust enforcement. |

### 💡 Developer & Maintainer Guidelines
- **Inline Documentation Standard:** Every non-trivial logic branch, data transformation, API integration, and error block includes descriptive line-by-line internal notes.
- **Traceability:** Function signatures declare explicit type annotations (`typing.Dict`, `typing.List`, `typing.Optional`) and descriptive parameter/return docstrings.
- **Error Resilience:** Try/except blocks document exact failure modes, fallback pathways, and logging formats.
