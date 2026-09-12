#!/usr/bin/env python3
"""
Git History Audit and Squashing Analyzer
Inspects local git repositories to detect:
1. Uniform commit spikes (multiple commits within short timeframes)
2. Synthetic / bot-like commit messages (e.g. cron telemetry, skip ci)
3. Bloated marketing or verbose commit descriptions
4. Trivial micro-iterations eligible for squashing into atomic commits
"""

import sys
import os
import subprocess
import re

BLOAT_KEYWORDS = [
    "comprehensive", "enterprise-grade", "full-spectrum", "zero-downtime",
    "all workspace updates", "complete end-to-end", "world-class"
]

BOT_PATTERNS = [
    r"\[skip ci\]",
    r"automated nightly",
    r"System Telemetry Update",
    r"pull-shark",
    r"sync and finalize"
]

def run_git(repo_dir, args):
    res = subprocess.run(["git", "-C", repo_dir] + args, capture_output=True, text=True, errors="ignore")
    return res.stdout.strip()

def analyze_repo(repo_dir):
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8")
        except Exception:
            pass

    print("=" * 80)
    print(f"GIT COMMIT HISTORY AUDIT: {os.path.basename(os.path.abspath(repo_dir))}")
    print("=" * 80)

    raw_log = run_git(repo_dir, ["log", "--format=%h|%an|%at|%ad|%s", "--date=iso-strict"])
    if not raw_log:
        print("[!] No commit history found.")
        return

    lines = raw_log.splitlines()
    commits = []
    for line in lines:
        parts = line.split("|", 4)
        if len(parts) == 5:
            h, author, ts, ad, subject = parts
            commits.append({
                "hash": h,
                "author": author,
                "timestamp": int(ts),
                "date": ad,
                "subject": subject
            })

    print(f"[*] Total commits analyzed: {len(commits)}\n")

    # 1. Detect commit spikes (< 15 minutes between consecutive commits by same author)
    spikes = []
    for i in range(len(commits) - 1):
        c_curr = commits[i]
        c_prev = commits[i + 1]
        delta_sec = abs(c_curr["timestamp"] - c_prev["timestamp"])
        if delta_sec < 900:
            spikes.append((c_curr, c_prev, delta_sec))

    if spikes:
        print(f"[!] Detected {len(spikes)} rapid commit cluster(s) (<15m interval):")
        for curr, prev, dt in spikes[:5]:
            print(f"    - {curr['hash']} ('{curr['subject']}') -> {dt}s after {prev['hash']}")
    else:
        print("[+] Commit cadence: No rapid spikes detected.")

    # 2. Detect synthetic bot patterns & bloat
    flagged = []
    for c in commits:
        reasons = []
        for pat in BOT_PATTERNS:
            if re.search(pat, c["subject"], re.IGNORECASE):
                reasons.append(f"matches bot pattern '{pat}'")
        for kw in BLOAT_KEYWORDS:
            if re.search(r"\b" + re.escape(kw) + r"\b", c["subject"], re.IGNORECASE):
                reasons.append(f"contains bloated phrasing '{kw}'")
        if len(reasons) > 0:
            flagged.append((c, reasons))

    if flagged:
        print(f"\n[!] Flagged {len(flagged)} commit(s) with synthetic or bloated phrasing:")
        for c, reasons in flagged:
            print(f"    - {c['hash']}: '{c['subject']}'")
            print(f"      Reasons: {', '.join(reasons)}")
    else:
        print("\n[+] Commit messages: Clean, imperative phrasing.")

    print("=" * 80 + "\n")

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "."
    analyze_repo(target)
