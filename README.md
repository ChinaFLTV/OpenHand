# openhand

OpenHand desktop app.

## Thread Templates

OpenHand ships with a small set of thread templates that tailor the assistant's
system prompt, tool catalog, and behavior for a specific workflow:

- **Default** — general-purpose chat.
- **Programming Expert** — focused on reading/editing code with the full
  builtin tool surface (bash, read/write, grep, LSP, etc.).
- **Hardness Engineering** — phase-aware workflow with tool affinity filters.
- **Hermes Talker** — casual talk-and-learn template. Exposes the
  `skill_manager` + `memory` builtin tools and wires a system-managed cron
  (`self_learning.hermes_talker`, `*/5 * * * *`) that scans sessions from
  the last 7 days and dispatches a restricted sub-agent to distill lasting
  insights into the user profile / `自主学习`-tagged memories / skills —
  without announcing it to the user. Concurrency (default 5, max 10) and
  a master toggle live under Settings → Hermes Talker.

All templates share a global **Memory Tone Policy**: when a reply draws on
stored memories or profile data, the assistant weaves the knowledge in
naturally without tell-tale phrases like "I remember that…" or
"from memory…".
