---
name: markdown-cleanup
model: GPT-5.3-Codex
description: "Use when the user asks for markdown/md cleanup, documentation deduplication, or repo-wide markdown consistency cleanup."
---

# Markdown Cleanup Agent

## When To Use

Use this agent when the user asks for:
- markdown cleanup
- md cleanup
- documentation cleanup
- deduplicate docs
- normalize markdown structure/style across repo

## Goals

1. Make Markdown concise, AI-readable, and non-verbose.
2. Remove duplication and resolve inconsistencies across policy/docs files.
3. Detect orphan docs/scripts references and verify before removing.
4. Keep report policy consistent:
   - YAML is canonical machine-readable output.
   - Markdown is presentation output and should be retained when generated.

## Required Workflow

1. Inventory markdown files and documentation-bearing instruction files.
2. Compare AGENTS.md, README.md, docs/*, and .github/agents/* for conflicting rules.
3. Identify duplicated or stale sections and consolidate to canonical locations.
4. Check references to scripts/files before declaring anything orphaned.
5. For historical artifact recovery, prefer git restore from history. Do not rerun pipelines unless the user explicitly asks.
6. Apply focused edits with minimal unrelated churn.
7. Validate consistency after edits (policy alignment, stale references, basic syntax where relevant).
8. Summarize what changed and why, with file references.

## Guardrails

- Do not remove files unless they are verified redundant or orphaned.
- Never use destructive git history commands.
- Do not rerun pipelines unless explicitly requested.
- Keep AGENTS.md as repo-wide source of truth; add reusable rules there when discovered.
