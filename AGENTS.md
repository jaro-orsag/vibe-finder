# AGENTS

## AI-First Repository Policy

This repository is run in an AI-first way.

Rules:
- Humans should avoid manual code writing whenever possible.
- Preferred inputs are prompts and instruction updates.
- Repository behavior should be controlled through AGENTS.md and instruction files.

## Mandatory Agent Behavior

When working in this repo, agents must:
- Suggest AGENTS.md updates whenever a new reusable instruction appears.
- Keep AGENTS.md as the source of truth for repo-wide rules.
- Propose scoped instruction files when rules apply only to specific paths or file types.
- Prefer persisted scripts under `scripts/pipeline/` or `scripts/events-pipeline/` for recurring checks (validation/counting) instead of ad-hoc inline one-liners in terminal commands.
- Route pull request creation requests to the `pr-creator` custom agent.

## Markdown Hygiene

When editing Markdown in this repository:
- Keep files concise and AI-readable.
- Avoid repeating the same rule across multiple files; link to the canonical document instead.
- Prefer short sections with explicit headings, bullet lists, and command examples.
- Treat generated artifacts under `data/**` as non-authoritative docs.
- For stage reports, keep YAML as canonical machine-readable output and keep Markdown as presentation output.

## Pull Request Workflow

When the user asks to create/open/submit a pull request, use the `pr-creator` agent and follow this deterministic flow:
1. Inspect git status, branch, and remotes.
2. If on `main`, create `feat/<short-topic>` branch.
3. Stage all current changes and create one descriptive commit.
4. Push branch with upstream.
5. Attempt `gh pr create` first.
6. If `gh` is unavailable, stop and ask the user to install/authenticate `gh`.

## Deterministic Pipeline Checks

Use these scripts for repeatable validation steps:
- `ruby scripts/pipeline/validate_sources_yaml.rb <yaml_file> [--stage N] [--date YYYY-MM-DD]`
- `ruby scripts/pipeline/count_sources.rb <yaml_file>`

Avoid re-generating equivalent `ruby -e` snippets when these scripts cover the same check.

For long-running pipeline runs, agents must stream operational progress to the user instead of waiting for stage completion.
- Event Crawl Stage 1 progress must include the current source ID/name, current source index/total, remaining sources, and the number of events found so far for the current source when that count is cheap to compute.
- When deterministic scripts exist for a pipeline stage, prefer running those scripts and relaying their stdout progress rather than treating the stage as a silent black box.
- For historical artifact recovery, prefer `git restore` from repository history instead of rerunning pipeline stages unless the user explicitly asks to rerun.

When introducing source catalogs intended as machine-readable contracts between agents:
- Store contract YAML files under `data/sources/`.
- Use explicit `contract` and `schema_version` fields.
- Keep field names stable; evolve compatibility through schema version bumps.
- For event-source discovery, prioritize high recall and include mainstream plus underground scenes; use confidence levels instead of aggressive filtering.
- When merging newly discovered sources into an existing catalog, preserve original canonical IDs and deduplicate semantically by source URL/path, not only by exact ID.

## Event Source Discovery Pipeline

The pipeline runs as three sequential agents. Each agent writes its output to a dated folder for auditability. See `docs/pipeline.md` for full architecture.

| Stage | Agent | Input | Output |
|-------|-------|-------|--------|
| 1 | `bratislava-sources-scout` | — | `data/pipeline/{run_id}/1_discovered.yaml` |
| 2 | `bratislava-sources-dedup` | Stage 1 output | `data/pipeline/{run_id}/2_deduped.yaml`, `2_dedup_report.yaml` |
| 3 | `bratislava-sources-merge` | Stage 2 output + canonical catalog | Updated `data/sources/bratislava-event-sources.yaml`, archive, `3_merge_report.yaml` |

Where `run_id` should be `YYYY-MM-DD_HHMMSS` for new runs (date-only remains backward compatible).

Pipeline invariants:
- Stage 1 never reads the canonical catalog.
- Original canonical IDs are never changed or removed.
- Confidence is never downgraded by a merge run.
- The canonical catalog is archived before every Stage 3 overwrite.

## Event Crawl Pipeline

A separate daily pipeline crawls each source and maintains the canonical events catalog. See `docs/events-pipeline.md` for full architecture.

| Stage | Agent | Input | Output |
|-------|-------|-------|--------|
| 1 | `bratislava-events-crawler` | `data/sources/bratislava-event-sources.yaml` | `data/events-pipeline/{run_id}/1_crawled.yaml` |
| 2 | `bratislava-events-dedup` | Stage 1 output | `data/events-pipeline/{run_id}/2_deduped.yaml`, `2_dedup_report.yaml` |
| 3 | `bratislava-events-merge` | Stage 2 output + canonical events catalog | Updated `data/events/bratislava-events.yaml`, archives, `3_merge_report.yaml` |

Event pipeline invariants:
- Stage 1 never reads the canonical events catalog.
- Original canonical event IDs are never changed or removed.
- Confidence is never downgraded by a merge run.
- `source_urls` never shrinks — all observed URLs are preserved.
- The canonical catalog is archived before every Stage 3 overwrite.
- Past events are moved to monthly archive files (`data/events/archive/bratislava-events-past_{YYYY-MM}.yaml`), not deleted.
- Dedup key is `(title, date, venue_name)` normalized — NOT URL.
- Category values must come from `data/events/categories.yaml`.

Event pipeline scripts:
- `ruby scripts/events-pipeline/validate_events_yaml.rb <yaml_file> [--stage N] [--date YYYY-MM-DD]`
- `ruby scripts/events-pipeline/count_events.rb <yaml_file>`
- `ruby scripts/events-pipeline/stage1_crawl_events.rb <run_id> <run_date>`
- `ruby scripts/events-pipeline/stage1_source_report.rb <run_id>`
- `ruby scripts/events-pipeline/stage1_5_crawl_and_dedup_events.rb <run_id> <run_date> [--max-sources N]`
- `ruby scripts/events-pipeline/stage2_dedup_events.rb <run_id> [run_date]`
- `ruby scripts/events-pipeline/stage3_merge_events_catalog.rb <run_id>`

## Instruction Hierarchy

Use this order:
1. AGENTS.md for repository-wide defaults.
2. .github/instructions/*.instructions.md for scoped rules.
3. .github/agents/*.agent.md for specialized agent modes.
4. User-level instructions for personal, cross-repo preferences.

## Change Management

When introducing a new workflow rule:
1. Add or update AGENTS.md first.
2. Add scoped instruction files if needed.
3. Reference the change in README.md if it affects human process.
