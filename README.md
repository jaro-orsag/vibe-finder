# Vibe Finder

This repository is configured for AI-first development.

## Source Of Truth

- Repository-wide behavior and workflow rules: `AGENTS.md`
- Pipeline architecture and runbook (source discovery): [docs/pipeline.md](docs/pipeline.md)
- Pipeline architecture and runbook (event crawl): [docs/events-pipeline.md](docs/events-pipeline.md)
- Pipeline architecture and runbook (event crawl v2 isolated): [docs/events-pipeline-v2.md](docs/events-pipeline-v2.md)
- PR routing rule: `.github/instructions/pr-creation.instructions.md`
- Markdown cleanup routing rule: `.github/instructions/markdown-cleanup.instructions.md`

## Pipelines

- Source discovery pipeline (on demand): updates `data/sources/bratislava-event-sources.yaml`
- Event crawl pipeline (daily): updates `data/events/bratislava-events.yaml`
- Event crawl pipeline v2 (isolated, Java/Spring): writes run artifacts to `data/events-pipeline-v2/{RUN_ID}/`
- Both pipelines write run artifacts to timestamped folders for auditability.

## Runbooks

- Source discovery runbook and scripts: [docs/pipeline.md](docs/pipeline.md)
- Event crawl runbook and scripts: [docs/events-pipeline.md](docs/events-pipeline.md)
- Event crawl v2 runbook and app entrypoint: [docs/events-pipeline-v2.md](docs/events-pipeline-v2.md)
- Deterministic script policy: `AGENTS.md`

## Pull Requests

When asked to create/open/submit a PR, this repo routes to the `pr-creator` agent.
PR creation is `gh` CLI only. If `gh` is unavailable, authenticate/install it first.
