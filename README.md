# Vibe Finder

This repository is configured for AI-first development.

## Source Of Truth

- Repository-wide behavior and workflow rules: `AGENTS.md`
- Pipeline architecture and runbook (source discovery): [docs/pipeline.md](docs/pipeline.md)
- Pipeline architecture and runbook (event crawl): [docs/events-pipeline.md](docs/events-pipeline.md)
- PR routing rule: `.github/instructions/pr-creation.instructions.md`

## Pipelines

- Source discovery pipeline (on demand): updates `data/sources/bratislava-event-sources.yaml`
- Event crawl pipeline (daily): updates `data/events/bratislava-events.yaml`
- Both pipelines write run artifacts to timestamped folders for auditability.

## Deterministic Script Entry Points

Source pipeline:
- `ruby scripts/pipeline/validate_sources_yaml.rb <yaml_file> [--stage N] [--date YYYY-MM-DD]`
- `ruby scripts/pipeline/count_sources.rb <yaml_file>`
- `ruby scripts/pipeline/stage3_merge_catalog.rb <run_id>`

Event pipeline:
- `ruby scripts/events-pipeline/validate_events_yaml.rb <yaml_file> [--stage N] [--date YYYY-MM-DD]`
- `ruby scripts/events-pipeline/count_events.rb <yaml_file>`
- `ruby scripts/events-pipeline/stage1_crawl_events.rb <run_id> <run_date>`
- `ruby scripts/events-pipeline/stage1_source_report.rb <run_id>`
- `ruby scripts/events-pipeline/stage1_5_crawl_and_dedup_events.rb <run_id> <run_date> [--max-sources N]`
- `ruby scripts/events-pipeline/stage2_dedup_events.rb <run_id> [run_date]`
- `ruby scripts/events-pipeline/stage3_merge_events_catalog.rb <run_id>`

## Pull Requests

When asked to create/open/submit a PR, this repo routes to the `pr-creator` agent.
PR creation is `gh` CLI only. If `gh` is unavailable, authenticate/install it first.

## Documentation Rule

Keep Markdown concise, non-duplicated, and optimized for AI parsing. For stage reports, keep YAML as canonical machine-readable output and keep Markdown as presentation output.
