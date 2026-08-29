#!/usr/bin/env python3
"""
Phase 1: Automated Repository Triage, Staleness & Dependency Evaluator
Discovers repos, audits last commit age, stale branch count, and generates SBOM manifest.
"""

import os
import json
import csv
import subprocess
from datetime import datetime, timezone

def audit_local_repo(repo_path):
    os.chdir(repo_path)
    
    # 1. Last Commit Date
    try:
        ts_str = subprocess.check_output(
            ["git", "log", "-1", "--format=%ct"], text=True
        ).strip()
        last_commit_dt = datetime.fromtimestamp(int(ts_str), tz=timezone.utc)
        days_inactive = (datetime.now(timezone.utc) - last_commit_dt).days
    except Exception:
        days_inactive = 999
        last_commit_dt = None

    # 2. Total Commits & Branches
    commit_count = int(subprocess.check_output(["git", "rev-list", "--count", "HEAD"], text=True).strip())
    branches = subprocess.check_output(["git", "branch", "-a"], text=True).splitlines()
    branch_count = len(branches)

    # 3. Dependency & SBOM Detection
    detected_frameworks = []
    if os.path.exists("requirements.txt") or os.path.exists("pyproject.toml"):
        detected_frameworks.append("Python")
    if os.path.exists("package.json"):
        detected_frameworks.append("Node.js")
    if os.path.exists("pom.xml") or os.path.exists("build.gradle"):
        detected_frameworks.append("Java/JVM")
    if os.path.exists("go.mod"):
        detected_frameworks.append("Go")
    if os.path.exists("Dockerfile") or os.path.exists("docker-compose.yml"):
        detected_frameworks.append("Docker/Container")

    # 4. Triage Classification
    if days_inactive > 365:
        classification = "COLD_ARCHIVE"
        action = "Offload to S3/GCS Cold Storage (Exclude from GitHub)"
    elif any(x in os.path.basename(repo_path).lower() for x in ["test", "scratch", "poc"]):
        classification = "EPHEMERAL"
        action = "Requires Owner Sign-off before migration"
    else:
        classification = "ACTIVE"
        action = "Approved for GitHub Enterprise Migration"

    return {
        "repository": os.path.basename(repo_path),
        "classification": classification,
        "action_required": action,
        "days_inactive": days_inactive,
        "last_commit": last_commit_dt.isoformat() if last_commit_dt else "N/A",
        "commit_count": commit_count,
        "branch_count": branch_count,
        "tech_stack": ", ".join(detected_frameworks) if detected_frameworks else "Generic"
    }

if __name__ == "__main__":
    import sys
    target_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    print(f"[*] Auditing repositories in: {target_dir}")
    
    results = []
    if os.path.exists(os.path.join(target_dir, ".git")):
        results.append(audit_local_repo(target_dir))
    else:
        for sub in os.listdir(target_dir):
            full = os.path.join(target_dir, sub)
            if os.path.isdir(full) and os.path.exists(os.path.join(full, ".git")):
                results.append(audit_local_repo(full))

    print("\n" + "="*80)
    print("PHASE 1: REPOSITORY TRIAGE & STALENESS AUDIT MANIFEST")
    print("="*80)
    for r in results:
        status_color = "🟢" if r['classification'] == "ACTIVE" else ("🟡" if r['classification'] == "EPHEMERAL" else "🔴")
        print(f"{status_color} [{r['classification']}] {r['repository']}")
        print(f"   • Last active: {r['days_inactive']} days ago | Commits: {r['commit_count']} | Branches: {r['branch_count']}")
        print(f"   • Stack: {r['tech_stack']} | Action: {r['action_required']}\n")

    # Export manifest
    os.makedirs("config", exist_ok=True)
    out_file = "config/triage-manifest.json"
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)
    print(f"[+] Saved Triage Manifest to: {out_file}")
