# Event Source Discovery Pipeline

## Purpose

Maintain the canonical source catalog at `data/sources/bratislava-event-sources.yaml` using a 3-stage pipeline.
Stage outputs are written to `data/pipeline/{RUN_ID}/` for auditability.

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

- `data/sources/bratislava-event-sources.yaml` - canonical catalog updated by Stage 3
- `data/sources/archive/bratislava-event-sources_{RUN_ID}.yaml` - snapshot before each Stage 3 run
- `data/pipeline/{RUN_ID}/1_discovered.yaml` - Stage 1 raw output
- `data/pipeline/{RUN_ID}/2_deduped.yaml` - Stage 2 cleaned output
- `data/pipeline/{RUN_ID}/2_dedup_report.yaml` - Stage 2 removal log
- `data/pipeline/{RUN_ID}/3_merge_report.yaml` - Stage 3 change log

`YYYY-MM-DD` folders are backward compatible, but new runs should use `YYYY-MM-DD_HHMMSS`.

## Contract

All source pipeline YAML files follow the schema in `data/sources/bratislava-event-sources.yaml` (`field_contract`, `required_fields`) and include `pipeline_stage` and `run_date`.

## Manual Run (agents)

Invoke stages in order:

1. **Stage 1** (`bratislava-sources-scout`)
   > "Run pipeline Stage 1 for {RUN_ID}. Write output to data/pipeline/{RUN_ID}/1_discovered.yaml."

2. **Stage 2** (`bratislava-sources-dedup`)
   > "Run pipeline Stage 2 for {RUN_ID}. Read data/pipeline/{RUN_ID}/1_discovered.yaml."

3. **Stage 3** (`bratislava-sources-merge`)
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

Canonical catalog checks:

```bash
ruby scripts/pipeline/validate_sources_yaml.rb data/sources/bratislava-event-sources.yaml
ruby scripts/pipeline/count_sources.rb data/sources/bratislava-event-sources.yaml
```

## Key invariants

- **Original IDs are never changed.** Stage 3 matches by URL, not by the ID assigned in Stage 1.
- **Entries are never deleted** from the canonical catalog by the pipeline.
- **Confidence is never downgraded** by a merge run.
- **Social channel entries for venues that have their own website are removed** in Stage 2.

## Report artifacts policy

Use the canonical rule from `AGENTS.md`: YAML is canonical machine-readable output; Markdown is presentation output and should be kept when generated.
