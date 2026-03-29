---
applyTo: "apps/events-pipeline-v2/**"
---

# Events Pipeline v2 (Isolated Implementation)

Use these rules when working on the v2 crawler implementation.

## Separation rule

- Keep v2 fully separate from the original events pipeline.
- Do not replace or edit `scripts/events-pipeline/**` unless explicitly asked.
- Keep v2 artifacts under `data/events-pipeline-v2/**` only.

## Architecture rule

- v2 is content-first crawling.
- Do not hardcode source-specific URL path assumptions as primary extraction logic.
- Parse fetched page content and follow discovered links from actual documents.

## Processing rule

- Process each source independently.
- Deduplicate only within the current source run.
- Do not perform cross-source dedup in v2.

## Reporting rule

For each run, always output:

- Run summary with per-source metrics (`unique_events`, pages visited, duration, failure count)
- Failure summary by category
- Failure summary by category and source
- Per-source detailed report, per-source events, and per-source crawl log

## Crawler behavior rule

Make human-like behavior explicit in code:

- Random delay/jitter between requests
- Browser-like headers
- Bounded depth and page limits
- Clear logging around requests, retries/failures, and extracted candidates

Never implement unethical bypass behavior (credentials abuse, CAPTCHA bypass, auth-wall circumvention).
