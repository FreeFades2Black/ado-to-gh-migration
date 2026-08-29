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
├── README.md                              # Master Architecture Documentation
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
