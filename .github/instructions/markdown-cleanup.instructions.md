---
applyTo: "**"
---

# Markdown Cleanup Request Routing

When the user asks for markdown or documentation cleanup (examples: "markdown cleanup", "md cleanup", "cleanup docs", "deduplicate markdown"), invoke the `markdown-cleanup` custom agent.

Expected behavior:
- Audit and normalize Markdown files for concision, consistency, and AI readability.
- Verify orphan/unused files or script references before removing anything.
- Keep stage reports policy consistent: YAML canonical + Markdown presentation.
- Prefer restoring historical artifacts from git history over rerunning pipelines unless the user explicitly asks to rerun.
- Return a clear summary of findings, edits, and any unresolved risks.
