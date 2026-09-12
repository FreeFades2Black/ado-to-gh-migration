# ADR-0002: Mapping ADO Branch Policies to GitHub Repository Rulesets over Classic Protection

**Status:** Accepted  
**Date:** 2026-05-29  
**Lead Architect:** William Free Hall (Free) <whall4.wh@gmail.com>

## 1. Context & Operational Challenge
Azure DevOps branch policies support complex configuration matrices (minimum reviewers, build validation triggers, work item linking, merge strategies). We evaluated how to translate these rules to GitHub Enterprise.

## 2. Options Considered
* **Option A: GitHub Classic Branch Protection API (`/branches/{branch}/protection`)**
  - *Evaluation:* Legacy API; cannot enforce rules across multiple branches via pattern matching; cannot enforce linear commit history or bypass lists cleanly.
* **Option B: GitHub Repository Rulesets API (`/repos/{owner}/{repo}/rulesets`)**
  - *Evaluation:* Modern declarative JSON schema; supports target branch fnmatch patterns (e.g. `refs/heads/main`, `refs/heads/release/*`), granular bypass actors, and automated import/export.

## 3. Decision & Trade-Off Accepted
We adopted **Option B (GitHub Rulesets)**.  
**Trade-Off Accepted:** Requires GitHub Enterprise Cloud / Server; policy translator must convert ADO GUIDs to GitHub Ruleset conditions.
