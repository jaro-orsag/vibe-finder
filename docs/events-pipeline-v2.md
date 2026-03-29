# Event Crawl Pipeline v2 (Isolated, Java/Spring)

## Purpose

This is a strictly separate implementation of event crawling, designed for iterative algorithm improvement without changing the existing pipeline under `scripts/events-pipeline/` and `data/events-pipeline/`.

- Existing pipeline remains intact and authoritative.
- v2 is experimental and isolated in:
  - `apps/events-pipeline-v2/`
  - `scripts/events-pipeline-v2/`
  - `data/events-pipeline-v2/`

## Core approach

v2 uses content-first crawling instead of URL-pattern assumptions.

- Do not guess source page structure up front.
- Download pages and analyze their actual content.
- Follow discovered links on the same host.
- Extract event candidates from page content.
- Deduplicate event candidates per source if the same event page or event signature appears via multiple crawl paths.
- Keep processing isolated per source (no cross-source dedup or optimization in v2).

## Human-like crawling policy

Some sources can throttle or block bots. v2 uses explicit browser-like behavior:

- Randomized inter-request delay (`minDelayMs` to `maxDelayMs`)
- Browser-like headers (`User-Agent`, `Accept`, `Accept-Language`, `Connection`)
- Redirect following
- Bounded crawl depth and page count per source

Guardrails:

- No credential stuffing, no CAPTCHA bypass, and no auth-wall circumvention.
- Respect legal/terms constraints per source.

## Inputs

- Canonical source catalog from stage-1 source discovery output lineage:
  - `data/sources/bratislava-event-sources.yaml`
- v2 currently ignores social media-like sources (`source_type` containing `social`).

## Outputs

For each run, v2 writes to:

- `data/events-pipeline-v2/{RUN_ID}/run_summary.yaml`
- `data/events-pipeline-v2/{RUN_ID}/failure_summary.yaml`
- `data/events-pipeline-v2/{RUN_ID}/sources/{source_id}/source_report.yaml`
- `data/events-pipeline-v2/{RUN_ID}/sources/{source_id}/events.yaml`
- `data/events-pipeline-v2/{RUN_ID}/sources/{source_id}/crawl.log`

`events.yaml` keeps the same event field format as the original event pipeline output (`contract: bratislava_events`, `events[]` schema).

## Metrics

Primary optimization metric for iterations:

- `unique_events` per source per run

This metric is intentionally source-local in v2:

- No cross-source event merging
- No cross-source dedup assumptions

## Failure reporting

v2 writes:

- Failure counts by category (`failures_by_category`)
- Failure counts by category and by source (`failures_by_category_by_source`)

## Runtime and code constraints

- Java 25
- Spring Boot 4 console application (non-web)
- Clean logs with per-source progress visibility
- Separation of concerns and explicit bounded responsibilities
- Design emphasis: SOLID, clean code, selective GoF patterns, pragmatic DDD boundaries

## Run v2

From repository root:

```bash
bash scripts/events-pipeline-v2/run_v2.sh
```

With explicit run metadata:

```bash
bash scripts/events-pipeline-v2/run_v2.sh 2026-03-29_120000 2026-03-29
```

With a custom label, the script automatically appends `YYYY-MM-DD_HHMMSS`
to the folder name for chronological ordering:

```bash
bash scripts/events-pipeline-v2/run_v2.sh rapid5 2026-03-29
# writes into data/events-pipeline-v2/rapid5_2026-03-29_120000/
```

Focused debug run for selected sources:

```bash
bash scripts/events-pipeline-v2/run_v2.sh 2026-03-29_rapid 2026-03-29 --sourceIds=src_kamdomesta_sk_bratislava,src_citylife_sk_events --maxSources=2
```

Supported extra args:

- `--sourceIds=id1,id2,...` to run only selected sources
- `--maxSources=N` to cap the number of sources for quick iteration

Or run directly via Gradle in `apps/events-pipeline-v2/`:

```bash
gradle bootRun --args="--runId=2026-03-29_120000 --runDate=2026-03-29"
```

## Current scope note

v2 currently implements a production-ready scaffold and contracts for iterative algorithm upgrades.
Extraction quality is intentionally conservative at this stage and should be improved iteratively with benchmark runs against `unique_events` and failure metrics.
