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
- .github/agents/bratislava-events-crawler.agent.md: Events Stage 1 — crawls sources and extracts upcoming events with categories.
- .github/agents/bratislava-events-dedup.agent.md: Events Stage 2 — deduplicates events by (title, date, venue).
- .github/agents/bratislava-events-merge.agent.md: Events Stage 3 — merges into canonical events catalog, archives past events.
- .github/agents/pr-creator.agent.md: Creates pull requests from current changes using a deterministic git/PR flow.
- .github/instructions/pr-creation.instructions.md: Routes "create PR" style requests to the `pr-creator` custom agent.
- scripts/pipeline/validate_sources_yaml.rb: Reusable YAML/schema validator for source pipeline artifacts.
- scripts/pipeline/count_sources.rb: Reusable source counter for source pipeline artifacts.
- scripts/events-pipeline/validate_events_yaml.rb: Reusable YAML/schema validator for event pipeline artifacts.
- scripts/events-pipeline/count_events.rb: Reusable event counter for event pipeline artifacts.
- scripts/events-pipeline/stage1_crawl_events.rb: Deterministic Stage 1 crawler with live per-source progress output.
- scripts/events-pipeline/stage2_dedup_events.rb: Deterministic Stage 2 event deduplication script.
- scripts/events-pipeline/stage3_merge_events_catalog.rb: Deterministic Stage 3 catalog merge script.
- data/sources/bratislava-event-sources.yaml: Canonical event source catalog (YAML contract).
- data/events/categories.yaml: Canonical category taxonomy for event classification.
- data/events/bratislava-events.yaml: Canonical events catalog (YAML contract).
- docs/pipeline.md: Source discovery pipeline architecture documentation.
- docs/events-pipeline.md: Event crawl pipeline architecture documentation.

## Event Source Discovery Pipeline

The source discovery pipeline is a three-stage agent chain that runs on-demand to maintain the canonical list of web sources. Each stage writes its output to `data/pipeline/YYYY-MM-DD_HHMMSS/` for full auditability.

See [docs/pipeline.md](docs/pipeline.md) for architecture, data flow, directory structure, and how to run.

## Event Crawl Pipeline

The event crawl pipeline is a separate three-stage agent chain that runs daily to maintain the canonical events catalog. It reads the source catalog as input and writes to `data/events-pipeline/YYYY-MM-DD_HHMMSS/`.

Long-running Stage 1 runs should stream live progress, including the current source, remaining source count, and source-local event count when cheap to compute.

See [docs/events-pipeline.md](docs/events-pipeline.md) for architecture, data flow, directory structure, and how to run.

## Category Taxonomy

Events are classified using a flat category taxonomy defined in `data/events/categories.yaml`. Events can have multiple categories. Categories cover genres (techno, jazz, metal, etc.) and scene tags (underground, queer, open_air, festival) that are orthogonal and can stack.

## Source Catalog Contract

- Machine-readable source metadata contracts are stored in `data/sources/`.
- Contracts must include stable `contract` and `schema_version` fields.
- Backward-incompatible changes require a schema version bump.

## Working Agreement

When a new recurring preference or rule is discovered:
1. Update AGENTS.md first.
2. Add a scoped instruction file if the rule is only for certain files or folders.
3. Keep instructions short, explicit, and testable.

## Pull Request Requests

When you ask to create/open/submit a pull request, the repository routes that request to the `pr-creator` custom agent.
The workflow is deterministic:
1. Check git status/branch/remotes.
2. Create feature branch if currently on `main`.
3. Commit all current changes.
4. Push branch.
5. Create PR via `gh pr create` or open the GitHub PR URL fallback.

## Suggested Prompt Pattern

Use prompts like:
- "Implement X and update AGENTS.md with any new reusable rule."
- "Before coding, propose instruction updates for this task."
- "Apply this rule and persist it in AGENTS.md if reusable."

## Why This Process Helps

- Reduces hidden assumptions.
- Preserves team conventions in versioned files.
- Makes AI behavior more predictable over time.
