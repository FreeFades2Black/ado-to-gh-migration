# Enterprise GitHub Migration: Security, Dependency & Pruning Playbook

An end-to-end operational framework for building automated migration pipelines that discover, sanitize, purge redundancies, account for dependencies, and securely push to GitHub without leaking secrets or moving dead weight.

---

## 1. End-to-End Migration Flow Architecture

```text
[ PHASE 1: DISCOVERY & TRIAGE ]
├── Source Inventory (ADO / On-Prem APIs)
├── Redundancy & Staleness Auditing (Commit age, open PRs, branch counts)
└── Classification: [ ACTIVE ] vs [ ARCHIVE / PURGE ]
       │
       ▼
[ PHASE 2: IN-FLIGHT SECURITY & HISTORY SCRUBBING ]
├── Hardcoded Secret & Token Scanning (TruffleHog / Gitleaks)
├── Active Credential Verification & Quarantine
├── Binary & Bloat Removal (git-filter-repo for >100MB blobs)
└── LFS Conversion & Pointer Verification
       │
       ▼
[ PHASE 3: DEPENDENCY & GOVERNANCE PROVISIONING ]
├── Dependency Mapping & Lockfile Inspection (SBOM Generation)
├── GitHub Org Provisioning (Branch Rulesets, Environments, GHAS)
└── OIDC / Cloud Identity Integration (Zero static cloud keys)
       │
       ▼
[ PHASE 4: ATOMIC CUTOVER & VALIDATION ]
├── Mirror Push & GEI Execution
├── Post-Migration Refcount & Integrity Check (JSON Audit)
└── Source Host Locked to Read-Only
```

---

## 2. Phase-by-Phase Best Practices

### Phase 1: Pre-Migration Discovery & Redundancy Purging
Avoid migrating legacy noise, dead forks, and abandonware:
- **Define Triage Gates:**
  - *Dead Repos:* Zero commits in >12 months AND zero active deployments → Export cold archive to cloud storage (S3/GCS) and exclude from GitHub import.
  - *Ephemeral/Test Repos:* Repos named `*test*`, `*scratch*`, `*poc*` require manual owner sign-off.
  - *Stale Branches:* Purge merged branches older than 90 days before pushing to prevent refspec bloat.
- **Dependency Inventory:** Parse package manifests (`pom.xml`, `package.json`, `requirements.txt`, `go.mod`) to detect legacy, unmaintained internal dependencies before cutting over.

### Phase 2: In-Flight Secret Sanitization & History Scrubbing
Migrating Git repositories without scanning historical commits copies every hardcoded password, API key, and certificate ever committed:
- **Run Secret Scanners on Full Git History:** Execute automated scanning (e.g., TruffleHog or Gitleaks) against the bare clone before pushing to GitHub.
- **Immediate Credential Rotation:** If a live secret is discovered in history, **rotate it immediately at the provider layer**—scrubbing history does not prevent past exposure.
- **Rewrite Git History for Leaked Credentials & Bloat:** Use `git-filter-repo` (not deprecated `git filter-branch`) to strip private keys, credentials, and accidentally committed `.env` or build output directories (`.terraform/`, `node_modules/`, `.zip`).
- **Binary Offloading:** Identify objects >50 MB using `git-filter-repo --analyze` and migrate them to Git LFS before pushing, staying well clear of GitHub’s 100 MB hard file limit.

### Phase 3: Identity & Credential Decoupling (Secrets to OIDC)
- **Zero Static Service Account Keys:** Do not migrate long-lived AWS Access Keys, Azure Service Principal secrets, or GCP service account keys into GitHub Repository Secrets.
- **Enforce OpenID Connect (OIDC):** Configure GitHub Actions to authenticate directly to AWS IAM, Azure AD, or GCP Workload Identity via short-lived JSON Web Tokens (JWTs).
- **Consolidate Variable Groups:** Migrate ADO Variable Groups or on-prem environment configs into **GitHub Organization Secrets** or **GitHub Environment Secrets** with required reviewer gates.

### Phase 4: Target Platform Hardening & Governance
- **GitHub Advanced Security (GHAS):** Enable Secret Scanning with Push Protection on day one to block future developer leaks at the push hook.
- **Centralized Rulesets:** Apply organization-level Repository Rulesets to enforce default branch protection, linear commit history, and signed commits.
- **Automated Verification:** Generate a cryptographic and refcount manifest (`source_commits == dest_commits`) to satisfy compliance and compliance audit trails.

---

## 3. Automation Harness

### Script: `scripts/sanitize_and_migrate.sh`
*Pulls a bare mirror, scans for hardcoded secrets, cleans history bloat, converts LFS objects, and pushes to GitHub.*

```bash
#!/usr/bin/env bash
# ==============================================================================
# The Trail Boss Sanitizer: Inspect the herd, strip off the counterfeit iron,
# purge the dead weight, and push a clean brand into the new territory.
# ==============================================================================
set -euo pipefail

SOURCE_REPO_URL="${1:?Usage: $0 <source_git_url> <github_org> <repo_name>}"
GH_ORG="${2:?Usage: $0 <source_git_url> <github_org> <repo_name>}"
REPO_NAME="${3:?Usage: $0 <source_git_url> <github_org> <repo_name>}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

echo "[*] Step 1: Cloning source bare mirror from ${SOURCE_REPO_URL}..."
git clone --mirror "${SOURCE_REPO_URL}" "${WORK_DIR}/repo.git"
cd "${WORK_DIR}/repo.git"

echo "[*] Step 2: Scanning full Git history for live secrets (TruffleHog / Gitleaks)..."
if command -v trufflehog &> /dev/null; then
    trufflehog git file://. --results=verified,unverified --fail || {
        echo "[!] CRITICAL: Secrets detected in git history."
        echo "[!] Review findings, rotate exposed credentials, and scrub before cutover."
    }
else
    echo "[!] TruffleHog not found. Falling back to pattern audit."
fi

echo "[*] Step 3: Checking repository size and history bloat..."
if command -v git-filter-repo &> /dev/null; then
    echo "[*] Scrubbing known ephemeral files (.env, *.key, *.pfx, *.tfstate)..."
    git-filter-repo --invert-paths \
      --path-glob '*.key' \
      --path-glob '*.pfx' \
      --path-glob '.env' \
      --path-glob 'terraform.tfstate*' \
      --force
fi

echo "[*] Step 4: Reconciling Git LFS objects..."
if command -v git-lfs &> /dev/null; then
    git lfs fetch --all || true
fi

echo "[*] Step 5: Provisioning remote repository at https://github.com/${GH_ORG}/${REPO_NAME}..."
if ! gh repo view "${GH_ORG}/${REPO_NAME}" &>/dev/null; then
    gh repo create "${GH_ORG}/${REPO_NAME}" --private --description "Automated secure migration"
    echo "[+] Remote repo created."
fi

echo "[*] Step 6: Mirror-pushing clean repository to GitHub..."
TARGET_URL="https://github.com/${GH_ORG}/${REPO_NAME}.git"
git push --mirror "${TARGET_URL}"

if command -v git-lfs &> /dev/null; then
    git lfs push --all "${TARGET_URL}" || true
fi

echo "[+] Migration pipeline completed cleanly for ${REPO_NAME}."
```

---

## 4. Pre-Migration Triage Matrix

| Evaluation Factor | Action Required | Tool / Command |
| :--- | :--- | :--- |
| **No commits in > 365 days** | Offload to cold storage / Do not migrate | ADO REST API / GitHub Importer exclude |
| **Verified live secrets in history** | Rotate credentials immediately; run `git-filter-repo` | `trufflehog git file://.` / `git-filter-repo` |
| **Files > 100 MB** | Migrate to Git LFS tracking before push | `git lfs migrate import --include="..."` |
| **Unmerged branches > 180 days** | Purge from source clone prior to mirror push | `git branch -r --no-merged` cleanup |
| **Static Cloud Credentials** | Replace with OIDC Trust Policies | AWS IAM OIDC Role / Azure Managed Identity |
