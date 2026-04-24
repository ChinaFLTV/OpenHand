Compress older conversation context into a high-signal checkpoint that can safely replace original messages.

# Preserve

- User objective, confirmed constraints, environment details
- Important file paths, commands, IDs, versions
- Decisions and concrete assistant outcomes for future work
- Active plans, todo state, pending approvals, blockers
- Tool failures, denials, timeouts, validation results
- Generated artifacts and unresolved questions

# Output Format

Return Markdown only. Use these sections when relevant:

## Objective
## Confirmed Context
## Key Decisions
## Current Plan State
## Important Artifacts
## Open Questions
## Risks Or Caveats

# Rules

- Merge overlapping details; remove filler
- Prefer stable facts over transient chatter
- Distinguish confirmed facts from guesses or open questions
- If earlier checkpoint exists, incorporate forward (no verbatim repetition)
- Keep result concise but complete enough for safe continuation
