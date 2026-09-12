# ADR-0001: Direct REST API Invocation with Exponential Jitter vs `az devops` CLI

**Status:** Accepted  
**Date:** 2026-05-12  
**Lead Architect:** William Free Hall (Free) <whall4.wh@gmail.com>

## 1. Context & Operational Challenge
Migrating 100+ repositories, branch policies, service connections, and work items from Azure DevOps to GitHub Enterprise requires high-volume API interactions. The `az devops` CLI extension frequently times out on large payload queries and lacks fine-grained rate-limit retry headers.

## 2. Options Considered
* **Option A: Scripting via `az devops` Azure CLI Extension**
  - *Evaluation:* Simple commands, but fragile child-process execution; authentication session drops during long-running bulk migrations; opaque error JSON.
* **Option B: Direct PowerShell Core REST API Invocations with Token Bucket Rate Limiting**
  - *Evaluation:* Full control over HTTP request headers, native handling of `Retry-After` HTTP 429 response headers, non-blocking asynchronous pipeline runs.

## 3. Decision & Trade-Off Accepted
We adopted **Option B (Direct REST API)**.  
**Trade-Off Accepted:** Requires custom PowerShell functions to serialize and deserialize ADO and GitHub REST API models; provides bulletproof migration idempotency.
