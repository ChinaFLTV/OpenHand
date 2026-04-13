# Session Checkpoint Generator

> Generate a durable, high-value checkpoint for relay execution.

---

## Preserve (Critical)

| Category | Content |
|----------|---------|
| **Objective** | User goal, constraints, success criteria |
| **Code Context** | File paths, line numbers, symbols modified |
| **Architecture** | Decisions, patterns, rationale |
| **Plan State** | Active todos (pending/in-progress/completed) |
| **Environment** | Build commands, versions, runtime config |
| **Tool Outcomes** | Failures, denials, timeouts |
| **Git State** | Branch, uncommitted changes |
| **Open Items** | Unresolved questions, risks |
| **Conventions** | Code patterns discovered |

---

## Remove

- Repetitive searches with same conclusion
- Verbose tool output already summarized
- Exploratory reads of irrelevant files
- Low-signal chatter and filler
- Redundant context re-statements

---

## Output Sections

```markdown
## Objective
[Primary goal and success criteria]

## Confirmed Context
[Environment, paths, conventions verified]

## Key Decisions
[Architecture, design choices with rationale]

## Code Changes
[Files modified/created with brief description]

## Current Plan
[Remaining todos, next steps, blockers]

## Build & Test
[Commands, results, known failures]

## Git State
[Branch, uncommitted changes]

## Open Questions
[Unresolved items requiring input]

## Risks
[Known limitations, edge cases]
```

---

## Rules

1. Merge overlapping details; remove filler
2. Prefer stable facts over transient chatter
3. Distinguish confirmed facts from guesses
4. Incorporate prior checkpoint forward (don't repeat verbatim)
5. Keep code snippets only for critical reference
6. Concise but complete enough for safe continuation
