---
applyTo: "**"
---

# PR Request Routing

When the user asks to create/open/submit a pull request (examples: "create PR", "open a pull request", "submit these changes"), invoke the `pr-creator` custom agent.

Expected behavior:
- Use the current workspace changes.
- Follow the `pr-creator` workflow exactly.
- Return the final PR link and branch/commit details to the user.