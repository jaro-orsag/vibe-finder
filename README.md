# Vibe Finder

This repository is configured for AI-first development.

## Source Of Truth

- Repository-wide behavior and workflow rules: `AGENTS.md`
- Pipeline architecture and runbook (source discovery): [docs/pipeline.md](docs/pipeline.md)
- Pipeline architecture and runbook (event crawl): [docs/events-pipeline.md](docs/events-pipeline.md)
- PR routing rule: `.github/instructions/pr-creation.instructions.md`
- Markdown cleanup routing rule: `.github/instructions/markdown-cleanup.instructions.md`

## Pipelines

- Source discovery pipeline (on demand): updates `data/sources/bratislava-event-sources.yaml`
- Event crawl pipeline (daily): updates `data/events/bratislava-events.yaml`
- Both pipelines write run artifacts to timestamped folders for auditability.

## Script Entry Points

- Source pipeline scripts and usage: [docs/pipeline.md](docs/pipeline.md)
- Event pipeline scripts and usage: [docs/events-pipeline.md](docs/events-pipeline.md)
- Canonical policy for deterministic script usage lives in `AGENTS.md`.

## Pull Requests

When asked to create/open/submit a PR, this repo routes to the `pr-creator` agent.
PR creation is `gh` CLI only. If `gh` is unavailable, authenticate/install it first.

## Documentation Rule

Keep Markdown concise, non-duplicated, and optimized for AI parsing.
For report-format policy, follow `AGENTS.md`.
