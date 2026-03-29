---
name: bratislava-sources-scout
model: GPT-5.3-Codex
description: "Use when you need to discover as many web sources as possible that advertise concerts, parties, and shows in Bratislava and surrounding areas (all genres, including underground). Pipeline Stage 1: outputs raw discovery artifact only, does not touch the existing catalog."
---

# Pipeline Stage 1 — Source Discovery

## Role

Stage 1 of 3.
Discover web sources and write a raw artifact.
Do not read or modify the canonical catalog at `data/sources/bratislava-event-sources.yaml`.

## Objective

- Maximize source coverage for concerts, parties, and shows in Bratislava and nearby areas.
- Include mainstream, underground, niche, and international aggregators with Bratislava coverage.

## Input

No canonical catalog input is allowed in this stage.

## Output

Write `data/pipeline/{RUN_ID}/1_discovered.yaml`.
Use `RUN_ID` format `YYYY-MM-DD_HHMMSS` and `run_date` from the date part.

Required header:

```yaml
contract: bratislava_event_sources
schema_version: 1.0.0
pipeline_stage: 1
run_date: "{YYYY-MM-DD}"
sources:
  - ...
```

## Discovery rules

- Discover using Slovak and English search terms: concerts, parties, shows, clubs, collectives, podujatia, koncerty, party, underground, techno, rock, jazz, divadlo, festival, Bratislava.
- Use the `event_listing_urls` field for the specific page where events are listed (not just homepage).
- Multiple entries per domain are allowed when each path has distinct event coverage.
- Include social/platform channels when they are a primary or regularly updated event channel.
- Do not include sources clearly unrelated to live events.
- Keep expanding until discovery saturates (few new unique sources per search batch).

## Quality

- Prioritize recall over precision. Include medium and low-confidence candidates.
- Use `confidence: low` rather than excluding uncertain sources.
- Fill in all required fields for every entry.

## Required fields per source

id, name, homepage_url, event_listing_urls, source_type, event_focus, geo_coverage, languages, access_type, crawl_frequency, robots_txt_checked, confidence, active

## ID naming convention

Use stable snake_case `id` values with `src_` prefix based on domain and path, e.g. `src_goout_net_bratislava`. IDs assigned here are provisional — Stage 3 will reconcile them against canonical IDs.

## Output policy

- Valid YAML only.
- If a field is unknown, omit it rather than guessing a wrong value. Exception: required fields must always be present.
- Do not sort or deduplicate — that is Stage 2's job.
- After writing output, run:
  - `ruby scripts/pipeline/validate_sources_yaml.rb data/pipeline/{RUN_ID}/1_discovered.yaml --stage 1 --date {YYYY-MM-DD}`
  - `ruby scripts/pipeline/count_sources.rb data/pipeline/{RUN_ID}/1_discovered.yaml`
