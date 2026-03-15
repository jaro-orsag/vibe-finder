# Vibe Finder

This repository is configured for AI-first development.

## What AI-First Means Here

- You interact mainly by prompting the AI.
- You avoid writing code manually whenever possible.
- Behavioral rules are captured in instruction files, especially AGENTS.md.

## Files Added

- AGENTS.md: Repository-wide source of truth for agent behavior and workflow policy.
- .github/agents/ai-first.agent.md: Specialized agent mode reinforcing prompt-driven development.
- .github/agents/bratislava-sources-scout.agent.md: Stage 1 — discovers Bratislava-area event source webpages.
- .github/agents/bratislava-sources-dedup.agent.md: Stage 2 — deduplicates raw discovery output.
- .github/agents/bratislava-sources-merge.agent.md: Stage 3 — merges into canonical catalog, archives previous version.
- scripts/pipeline/validate_sources_yaml.rb: Reusable YAML/schema validator for pipeline and catalog artifacts.
- scripts/pipeline/count_sources.rb: Reusable source counter for pipeline and catalog artifacts.
- data/sources/bratislava-event-sources.yaml: Canonical event source catalog (YAML contract).
- docs/pipeline.md: Full pipeline architecture documentation.

## Event Source Discovery Pipeline

The pipeline is a three-stage agent chain intended to run daily. Each stage writes its output to `data/pipeline/YYYY-MM-DD/` for full auditability.

See [docs/pipeline.md](docs/pipeline.md) for architecture, data flow, directory structure, and how to run.

## Source Catalog Contract

- Machine-readable source metadata contracts are stored in `data/sources/`.
- Contracts must include stable `contract` and `schema_version` fields.
- Backward-incompatible changes require a schema version bump.

## Working Agreement

When a new recurring preference or rule is discovered:
1. Update AGENTS.md first.
2. Add a scoped instruction file if the rule is only for certain files or folders.
3. Keep instructions short, explicit, and testable.

## Suggested Prompt Pattern

Use prompts like:
- "Implement X and update AGENTS.md with any new reusable rule."
- "Before coding, propose instruction updates for this task."
- "Apply this rule and persist it in AGENTS.md if reusable."

## Why This Process Helps

- Reduces hidden assumptions.
- Preserves team conventions in versioned files.
- Makes AI behavior more predictable over time.
