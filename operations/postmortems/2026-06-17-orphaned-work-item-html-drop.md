# Incident Post-Mortem: Malformed ADO Rich-Text HTML Blocking Work Item Migration

**Incident Date:** 2026-06-17  
**Impact Duration:** 50 minutes  
**Severity:** SEV-3  
**Root Cause:** Legacy ADO work items authored in 2019 contained unclosed `<font>` and `<div>` tags in description fields. The markdown converter crashed on unclosed tags, halting batch issue creation for 14 enterprise projects.

## Timeline
* **14:00 UTC:** Bulk migration phase 3 (Work Items to Issues) initiated for 1,200 work items.
* **14:12 UTC:** Script halted at work item #482 with `XmlException: Unexpected end tag`.
* **14:30 UTC:** Triage identified malformed inline HTML from legacy Word copy-pastes.
* **14:42 UTC:** Added BeautifulSoup HTML sanitization step before markdown conversion.
* **14:50 UTC:** Migration resumed cleanly; all 1,200 issues migrated with cross-reference tags.

## Corrective Actions
1. Implemented robust HTML entity sanitization pipeline in `scripts/03_sanitize_and_scrub.py`.
2. Added unit test verifying unclosed HTML tags convert gracefully to sanitized GitHub markdown.
