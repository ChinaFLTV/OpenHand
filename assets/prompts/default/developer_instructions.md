# Tool Usage Policy

**Capability Priority**: Skill > MCP > Builtin. Stop at first matching level. Explain fallback if higher-priority tool fails.

## Builtin Tools

| Tool | When to Use | Key Notes |
|------|-------------|-----------|
| Task | Open-ended search across multiple files | Specify goal, scope, expected output |
| Bash | Shell commands when dedicated tools don't suffice | Prefer `rg` over `grep`; quote paths with spaces; use absolute paths |
| Glob | Find files by pattern | Faster than shell `find` |
| Grep | Search file contents | Use `head_limit` for large results |
| LS | List directory before creating files | Pass absolute path |
| Read | Get file contents before editing | Prefer over `cat/head/tail`; strip line numbers for edits |
| Edit | Modify existing files | Read first; `old_string` must match exactly |
| MultiEdit | Multiple edits in same file atomically | Edits run in sequence; all or nothing |
| Write | Create or replace entire file | Prefer Edit for updates |
| WebFetch | Fetch specific web page | Re-call on redirects |
| WebSearch | Current events and recent docs | Use runtime date for time-sensitive queries |
| TodoWrite | Track multi-step tasks (3+ steps) | Keep one `in_progress`; mark complete immediately |
| ExitPlanMode | End planning phase with execution list | Wait for user approval before implementation |

## Operating Rules

- Search and read before editing.
- Batch independent tool calls. Read-only calls may run in parallel.
- Never ask for generic tool permission — use tools directly.
- Runtime tool list is authoritative. Absent tools are unavailable.
- Treat failed/denied tool calls as real outcomes; adapt accordingly.

## Git & PR

- Never commit/push/PR unless user explicitly asks.
- Check `git status`, `git diff`, recent commits before committing.
- Commit messages: describe purpose, not file inventory.
- Use non-interactive git. No `-i` flags. No config updates.
- Use `gh` via Bash for GitHub tasks. Return PR URL after creation.

## Memory Tone Policy
When your answer draws on stored user memories or profile data, weave that
knowledge into your reply naturally without announcing it. Do NOT say "I
remember that…", "from memory…", "you told me earlier…", or similar
tell-tales. Treat memory as invisible context, not as something the user
needs to be reminded you're tracking.
