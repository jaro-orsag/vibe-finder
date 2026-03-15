---
name: bratislava-events-merge
model: GPT-5.3-Codex
description: "Use when you need to merge deduplicated events (Stage 2 artifact) into the canonical events catalog, archiving past events and preserving all existing IDs. Events Pipeline Stage 3."
---

# Events Pipeline Stage 3 — Catalog Merge

## Inputs
1. `data/events-pipeline/{RUN_ID}/2_deduped.yaml`
2. `data/events/bratislava-events.yaml` (canonical events catalog)

## Outputs
1. Archive of previous full catalog → `data/events/archive/bratislava-events_{RUN_ID}.yaml`
2. Updated canonical catalog → `data/events/bratislava-events.yaml`
3. Merge report → `data/events-pipeline/{RUN_ID}/3_merge_report.yaml`

## Matching
Match by normalized `(title, date, venue_name)` — NOT by ID. Stage 1 IDs are provisional.
Preserve canonical IDs for events already in the catalog. Assign a new stable ID for net-new events.

## Merge rules
- **New event** (not in catalog) → add it with a new stable ID: `evt_YYYYMMDD_<venue_slug>_<title_slug>`.
- **Existing event**:
  - Never downgrade `confidence`.
  - Merge `source_urls` (union, deduplicated).
  - Union `categories`.
  - Update optional enrichment fields only when new value is richer (non-null over null, longer `description`).
- **Absent from Stage 2 but in catalog** → keep unchanged (source may have been temporarily unavailable).
- **Cancelled events** → update `status: cancelled` if Stage 2 reports cancellation; never delete.

## Archival of past events
Before writing the updated catalog:
1. Archive the full current catalog: `data/events/archive/bratislava-events_{RUN_ID}.yaml`
2. Separate events where `date < today` into monthly archive files: `data/events/archive/bratislava-events-past_{YYYY-MM}.yaml`
   - Append to the monthly file if it already exists; do not overwrite past entries.
3. Remove those past events from the active catalog.
4. Merge in new/updated events from Stage 2.

## Key invariants
- Original canonical IDs are never changed or removed.
- Confidence is never downgraded.
- `source_urls` never shrinks.
- The canonical catalog is always archived before overwrite.

## Output policy
- Sort `events` by `date` ascending, then by `title`.
- Valid YAML only, all required fields present.
- After writing, run validate and count scripts:
  ```
  ruby scripts/events-pipeline/validate_events_yaml.rb data/events/bratislava-events.yaml
  ruby scripts/events-pipeline/count_events.rb data/events/bratislava-events.yaml
  ```

## Merge report format
```yaml
run_id: "{RUN_ID}"
pipeline_stage: 3
input_count: N
added: N
updated: N
unchanged: N
archived_past: N
```
