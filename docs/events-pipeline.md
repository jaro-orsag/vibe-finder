# Event Crawl Pipeline

## Purpose

Maintain the canonical events catalog at `data/events/bratislava-events.yaml` using a daily 3-stage pipeline seeded by `data/sources/bratislava-event-sources.yaml`.

```
[bratislava-event-sources.yaml]  ← produced by Source Discovery Pipeline
           │
           ▼ (input)
┌──────────────────────┐     ┌──────────────────────────┐     ┌──────────────────────────┐
│  Stage 1: Crawler    │────▶│  Stage 2: Dedup           │────▶│  Stage 3: Merge          │
│  (crawl & extract)   │     │  (merge duplicates)       │     │  (reconcile & update)    │
└──────────────────────┘     └──────────────────────────┘     └──────────────────────────┘
       writes                         writes                          writes
1_crawled.yaml                 2_deduped.yaml                bratislava-events.yaml
                               2_dedup_report.yaml           3_merge_report.yaml
                                                             archive/…_{RUN_ID}.yaml
                                                             archive/…-past_{YYYY-MM}.yaml
```

## Agents

| Stage | Agent file | Role |
|-------|-----------|------|
| 1 | `.github/agents/bratislava-events-crawler.agent.md` | Crawls sources, extracts raw events, assigns categories |
| 2 | `.github/agents/bratislava-events-dedup.agent.md` | Deduplicates by `(title, date, venue_name)` |
| 3 | `.github/agents/bratislava-events-merge.agent.md` | Merges into canonical catalog, archives past events |

## Directory structure

```
data/
  events/
    categories.yaml                          ← canonical category taxonomy
    bratislava-events.yaml                   ← canonical events catalog (updated by Stage 3)
    archive/
      bratislava-events_{RUN_ID}.yaml        ← full catalog snapshot before each Stage 3 run
      bratislava-events-past_{YYYY-MM}.yaml  ← expired events archived monthly
  events-pipeline/
    YYYY-MM-DD_HHMMSS/
      1_crawled.yaml                         ← Stage 1 raw output
      2_deduped.yaml                         ← Stage 2 cleaned output
      2_dedup_report.yaml                    ← Stage 2 merge log
      3_merge_report.yaml                    ← Stage 3 change log
```

## Data contract

The canonical catalog and stage artifacts share the schema in `data/events/bratislava-events.yaml` (`field_contract`, `required_fields`).
Artifacts include `pipeline_stage` and `run_date`.

Category values must come from `data/events/categories.yaml`.

### Required event fields
| Field | Type | Notes |
|-------|------|-------|
| `id` | string | stable, `evt_YYYYMMDD_<venue>_<slug>` |
| `title` | string | as listed on source |
| `date` | string | YYYY-MM-DD |
| `venue_name` | string | physical venue |
| `venue_city` | string | usually `Bratislava` |
| `categories` | list | ≥1 IDs from `categories.yaml` |
| `source_urls` | list | all URLs where found |
| `status` | enum | `upcoming` \| `past` \| `cancelled` |
| `confidence` | enum | `high` \| `medium` \| `low` |

### Optional event fields
`time_start`, `time_end`, `description`, `ticket_url`, `price`

## Dedup key
Stage 2 deduplicates by normalized `(title, date, venue_name)`. URL is NOT the key — the same event appears on many platforms with different URLs.

## Running the pipeline manually

Invoke each stage agent in order:

1. **Stage 1** — invoke `bratislava-events-crawler`:
   ```
   Run Events Pipeline Stage 1 for {RUN_ID}. Write output to data/events-pipeline/{RUN_ID}/1_crawled.yaml.
   ```

2. **Stage 2** — invoke `bratislava-events-dedup`:
   ```
   Run Events Pipeline Stage 2 for {RUN_ID}. Read data/events-pipeline/{RUN_ID}/1_crawled.yaml.
   ```

3. **Stage 3** — invoke `bratislava-events-merge`:
   ```
   Run Events Pipeline Stage 3 for {RUN_ID}. Read data/events-pipeline/{RUN_ID}/2_deduped.yaml and the canonical catalog.
   ```

## Deterministic validation commands

```bash
ruby scripts/events-pipeline/validate_events_yaml.rb data/events-pipeline/{RUN_ID}/1_crawled.yaml --stage 1 --date {YYYY-MM-DD}
ruby scripts/events-pipeline/validate_events_yaml.rb data/events-pipeline/{RUN_ID}/2_deduped.yaml --stage 2 --date {YYYY-MM-DD}
ruby scripts/events-pipeline/count_events.rb data/events-pipeline/{RUN_ID}/1_crawled.yaml
ruby scripts/events-pipeline/count_events.rb data/events-pipeline/{RUN_ID}/2_deduped.yaml
```

Standalone crawl+dedup (without Stage 3 merge):
```bash
ruby scripts/events-pipeline/stage1_5_crawl_and_dedup_events.rb {RUN_ID} {YYYY-MM-DD}
ruby scripts/events-pipeline/validate_events_yaml.rb data/events-pipeline/{RUN_ID}/1_5_crawled_deduped.yaml --date {YYYY-MM-DD}
ruby scripts/events-pipeline/count_events.rb data/events-pipeline/{RUN_ID}/1_5_crawled_deduped.yaml
```

Stage 1 source-level diagnostics (from an existing Stage 1 run):
```bash
ruby scripts/events-pipeline/stage1_source_report.rb {RUN_ID}
```
This generates `stage1_source_report.yaml` (canonical) and `stage1_source_report.md` (presentation) for that run.

For canonical catalog checks:
```bash
ruby scripts/events-pipeline/validate_events_yaml.rb data/events/bratislava-events.yaml
ruby scripts/events-pipeline/count_events.rb data/events/bratislava-events.yaml
```

## Relationship to Source Discovery Pipeline

This pipeline is **downstream** of the Source Discovery Pipeline. The two pipelines are independent:

- The Source Discovery Pipeline runs on-demand (when new venues/sources need to be catalogued).
- The Event Crawl Pipeline runs daily.
- Stage 1 of the Event Crawl Pipeline reads `data/sources/bratislava-event-sources.yaml` as input but never modifies it.

## Generated Artifacts Policy

- YAML artifacts are canonical machine-readable outputs.
- Markdown artifacts are presentation outputs and should be kept when generated.

## Key invariants

- Original event IDs are never changed. Stage 3 matches by `(title, date, venue_name)`, not by the provisional ID from Stage 1.
- Entries are never deleted from the active catalog — past events are moved to monthly archive files.
- Confidence is never downgraded by a merge run.
- `source_urls` never shrinks — all observed URLs are preserved.
- The canonical catalog is archived before every Stage 3 overwrite.
- Cancelled events have `status: cancelled` set but are not removed.
