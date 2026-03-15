---
applyTo: "**"
---

# PR Request Routing

When the user asks to create/open/submit a pull request (examples: "create PR", "open a pull request", "submit these changes"), invoke the `pr-creator` custom agent.

Expected behavior:
- Use the current workspace changes.
- Follow the `pr-creator` workflow exactly.
- If current branch is `last-pr`, switch to `main`, create a fresh `feat/<short-topic>` branch, and apply changes there.
- Create PRs with `gh` CLI only (no VS Code web-page fallback).
- Return the final PR link and branch/commit details to the user.