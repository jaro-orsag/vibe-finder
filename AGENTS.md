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
- Prefer persisted scripts under `scripts/pipeline/` for recurring checks (validation/counting) instead of ad-hoc inline one-liners in terminal commands.

## Deterministic Pipeline Checks

Use these scripts for repeatable validation steps:
- `ruby scripts/pipeline/validate_sources_yaml.rb <yaml_file> [--stage N] [--date YYYY-MM-DD]`
- `ruby scripts/pipeline/count_sources.rb <yaml_file>`

Avoid re-generating equivalent `ruby -e` snippets when these scripts cover the same check.

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
