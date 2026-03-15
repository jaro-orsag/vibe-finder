---
name: bratislava-events-dedup
model: GPT-5.3-Codex
description: "Use when you need to deduplicate raw crawled events (Stage 1 artifact). Events Pipeline Stage 2: reads 1_crawled.yaml, merges duplicate event entries, writes 2_deduped.yaml and 2_dedup_report.yaml."
---

# Events Pipeline Stage 2 — Deduplication

Reads `data/events-pipeline/{RUN_ID}/1_crawled.yaml`, writes:
- `2_deduped.yaml` (deduplicated event list, same schema)
- `2_dedup_report.yaml` (machine-readable merge log)

## Dedup key
Two events are duplicates when **all** of the following match after normalization:
- `title`: lowercase, strip punctuation, collapse whitespace
- `date`: exact YYYY-MM-DD
- `venue_name`: lowercase, strip punctuation, collapse whitespace

**URL is NOT the dedup key.** The same event appears on many platforms with different URLs.

## Dedup rules (in order)
1. **Identical dedup key** → merge into one entry:
   - Keep the highest `confidence` level.
   - Merge `source_urls` (union, deduplicated).
   - Union all `categories`.
   - Keep the richest optional fields: prefer non-null, prefer longer `description`, prefer non-null `ticket_url` and `price`.
2. **Partial title match with same date + venue** → flag with `confidence: low` but keep as separate entries when in doubt. Do not silently merge when titles differ significantly.

## Output policy
- Sort by `date` ascending, then by `title`.
- All required fields must be present on every entry.
- Valid YAML only.
- After writing, run validate and count scripts:
  ```
  ruby scripts/events-pipeline/validate_events_yaml.rb data/events-pipeline/{RUN_ID}/2_deduped.yaml --stage 2 --date {YYYY-MM-DD}
  ruby scripts/events-pipeline/count_events.rb data/events-pipeline/{RUN_ID}/2_deduped.yaml
  ```

## Dedup report format
```yaml
run_id: "{RUN_ID}"
pipeline_stage: 2
input_count: N
output_count: N
merged_count: N
merges:
  - kept_id: evt_...
    merged_from:
      - evt_...
    reason: "identical title+date+venue"
```
