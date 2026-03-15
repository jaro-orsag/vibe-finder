# Event Source Discovery Pipeline

## Overview

The pipeline discovers and maintains the canonical list of Bratislava-area event sources stored in `data/sources/bratislava-event-sources.yaml`. It is designed to run daily and is composed of three independent agents whose outputs are recorded for full auditability.

```
┌─────────────────────┐     ┌──────────────────────────┐     ┌──────────────────────────┐
│  Stage 1: Scout     │────▶│  Stage 2: Dedup           │────▶│  Stage 3: Merge          │
│  (discovery only)   │     │  (clean & deduplicate)    │     │  (reconcile & update)    │
└─────────────────────┘     └──────────────────────────┘     └──────────────────────────┘
       writes                         writes                          writes
1_discovered.yaml              2_deduped.yaml                bratislava-event-sources.yaml
                               2_dedup_report.yaml           3_merge_report.yaml
                                                             archive/…_{date}.yaml
```

## Agents

| Stage | Agent file | Role |
|-------|-----------|------|
| 1 | `.github/agents/bratislava-sources-scout.agent.md` | Discovers web sources, no catalog access |
| 2 | `.github/agents/bratislava-sources-dedup.agent.md` | Deduplicates Stage 1 output |
| 3 | `.github/agents/bratislava-sources-merge.agent.md` | Merges Stage 2 output into canonical catalog |

## Directory structure

```
data/
  sources/
    bratislava-event-sources.yaml        ← canonical catalog (updated by Stage 3)
    archive/
      bratislava-event-sources_YYYY-MM-DD.yaml  ← snapshot before each Stage 3 run
   pipeline/
      YYYY-MM-DD_HHMMSS/
      1_discovered.yaml          ← Stage 1 raw output
      2_deduped.yaml             ← Stage 2 cleaned output
      2_dedup_report.yaml        ← Stage 2 removal log
      3_merge_report.yaml        ← Stage 3 change log
```

`YYYY-MM-DD` folders are still accepted for backward compatibility, but new runs should use `YYYY-MM-DD_HHMMSS` to preserve same-day audit history.

## Data contract

All pipeline YAML files share the same schema defined in `data/sources/bratislava-event-sources.yaml` under `field_contract` and `required_fields`. The `pipeline_stage` and `run_date` header fields are added by each stage for traceability.

## Running the pipeline manually

Invoke each agent in order, passing today's date as context:

1. **Stage 1** — invoke `bratislava-sources-scout` with prompt:
   > "Run pipeline Stage 1 for {RUN_ID}. Write output to data/pipeline/{RUN_ID}/1_discovered.yaml."

2. **Stage 2** — invoke `bratislava-sources-dedup` with prompt:
   > "Run pipeline Stage 2 for {RUN_ID}. Read data/pipeline/{RUN_ID}/1_discovered.yaml."

3. **Stage 3** — invoke `bratislava-sources-merge` with prompt:
   > "Run pipeline Stage 3 for {RUN_ID}. Read data/pipeline/{RUN_ID}/2_deduped.yaml and the canonical catalog."

## Deterministic validation commands

Use persisted scripts under `scripts/pipeline/` instead of ad-hoc inline snippets:

```bash
ruby scripts/pipeline/validate_sources_yaml.rb data/pipeline/{RUN_ID}/1_discovered.yaml --stage 1 --date {YYYY-MM-DD}
ruby scripts/pipeline/validate_sources_yaml.rb data/pipeline/{RUN_ID}/2_deduped.yaml --stage 2 --date {YYYY-MM-DD}
ruby scripts/pipeline/count_sources.rb data/pipeline/{RUN_ID}/1_discovered.yaml
ruby scripts/pipeline/count_sources.rb data/pipeline/{RUN_ID}/2_deduped.yaml
ruby scripts/pipeline/stage3_merge_catalog.rb {RUN_ID}
```

For canonical catalog checks:

```bash
ruby scripts/pipeline/validate_sources_yaml.rb data/sources/bratislava-event-sources.yaml
ruby scripts/pipeline/count_sources.rb data/sources/bratislava-event-sources.yaml
```

## Auditability

- Every run should use a unique `RUN_ID` folder under `data/pipeline/` for immutable audit history.
- The previous canonical catalog is always archived before overwrite.
- The dedup and merge reports record exactly what changed and why.
- `git log` on `data/sources/bratislava-event-sources.yaml` shows the diff between catalog versions.

## Key invariants

- **Original IDs are never changed.** Stage 3 matches by URL, not by the ID assigned in Stage 1.
- **Entries are never deleted** from the canonical catalog by the pipeline.
- **Confidence is never downgraded** by a merge run.
- **Social channel entries for venues that have their own website are removed** in Stage 2.
