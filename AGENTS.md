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
