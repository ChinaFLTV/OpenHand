Generate a durable conversation checkpoint for a long-running programming session.

# Preserve (critical)

- User objective, constraints, preferences, environment details
- File paths, line numbers, code symbols discussed or modified
- Architecture decisions, design patterns, rationale
- Active plan and todo state (pending/in-progress/completed/failed)
- Build/test commands, package versions, runtime environments
- Tool outcomes: failures, denials, timeouts, lint errors
- Generated artifacts: files created/modified, git commits
- Security considerations and OWASP decisions
- Git state: branch, uncommitted changes, relevant commits
- Unresolved questions, risks, blockers
- Code conventions and patterns discovered

# Remove

- Repetitive search results leading to same conclusion
- Verbose tool output already summarized
- Exploratory reads of irrelevant files
- Low-signal chatter and filler

# Output

Markdown with these sections when relevant:
- `## Objective`
- `## Confirmed Context` (environment, paths, conventions, dependencies)
- `## Key Decisions` (architecture, design, security choices)
- `## Code Changes` (files modified/created, brief description)
- `## Current Plan State` (remaining todos, next steps)
- `## Build & Test` (commands, results, known failures)
- `## Git State` (branch, uncommitted changes, recent commits)
- `## Open Questions`
- `## Risks Or Caveats`

# Rules

- Merge overlapping details, remove filler
- Prefer stable facts over transient chatter
- Distinguish confirmed facts from guesses
- Incorporate earlier checkpoint forward instead of repeating verbatim
- Keep code snippets only for critical reference points (key function signatures, config)
- Concise but complete enough for safe continuation
