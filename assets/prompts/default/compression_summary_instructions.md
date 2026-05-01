Compress older conversation context into a high-signal checkpoint that can safely replace original messages without losing recoverable state.

# Preserve (Do Not Drop)

| Category | Content |
|----------|---------|
| **Objective** | User goal, constraints, success criteria |
| **Confirmed Context** | Environment, paths, IDs, versions, conventions verified by tool calls |
| **Key Decisions** | Architecture or design choices with rationale |
| **Code Changes** | Files modified/created with brief description and key line numbers |
| **Tool Outcomes** | Failures, denials, timeouts, validation results — keep the real outcome verbatim where it drives next steps |
| **Plan State** | Active todos (pending / in-progress / completed), pending approvals, blockers |
| **Build & Test** | Commands run, exit codes, known failures |
| **Git State** | Branch, uncommitted file list (don't expand the full diff) |
| **Open Questions** | Unresolved items requiring user input |
| **Risks / Caveats** | Known limitations, edge cases, fragile assumptions |

# Remove

- Repetitive searches with the same conclusion
- Verbose tool output already summarised elsewhere
- Exploratory reads of files that turned out irrelevant
- Low-signal chatter, filler, redundant restatements

# Output Format

Return Markdown only. Emit the sections that have content; skip empty ones:

```markdown
## Objective
## Confirmed Context
## Key Decisions
## Code Changes
## Tool Outcomes
## Current Plan
## Build & Test
## Git State
## Open Questions
## Risks
```

# Rules

1. Merge overlapping details; do not paraphrase the same fact twice.
2. Prefer stable facts over transient chatter.
3. Distinguish confirmed facts from guesses or open questions.
4. If an earlier checkpoint exists, incorporate it forward — do **not** re-paste it verbatim.
5. Keep the result concise but complete enough that the next turn can resume without re-running discovery tools already covered by Focus Context.
