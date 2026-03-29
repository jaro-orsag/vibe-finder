---
name: bratislava-events-crawler-v2
model: GPT-5.3-Codex
description: "Use when you need the isolated Java/Spring Events Pipeline v2 crawl run. This does not replace the original Ruby-based events pipeline."
---

# Events Pipeline v2 — Source-Isolated Crawler

## Role

Run the v2 crawler implementation in `apps/events-pipeline-v2/`.

This is an experimental, strictly separated pipeline implementation for iterative algorithm work.

## Input

- `data/sources/bratislava-event-sources.yaml`
- Include active non-social sources only.

## Output

Write run artifacts to `data/events-pipeline-v2/{RUN_ID}/`:

- `run_summary.yaml`
- `failure_summary.yaml`
- `sources/{source_id}/source_report.yaml`
- `sources/{source_id}/events.yaml`
- `sources/{source_id}/crawl.log`

## Rules

- No cross-source dedup or optimization.
- Deduplicate only within one source crawl.
- Use content-first extraction (analyze fetched documents; do not rely on guessed URL templates).
- Make human-like crawl behavior explicit (delay/jitter and browser-like headers).
- Keep logs explicit and source-scoped.

## Run command

From repository root:

```bash
bash scripts/events-pipeline-v2/run_v2.sh {RUN_ID} {RUN_DATE}
```

Or inside app directory:

```bash
gradle bootRun --args="--runId={RUN_ID} --runDate={RUN_DATE}"
```
