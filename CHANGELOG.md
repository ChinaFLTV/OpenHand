# Changelog

All notable changes to OpenHand will be documented in this file.

## Unreleased

### Added

- **Siri 助手 thread template**:
  - New `siri_helper` built-in thread template with a Siri-style system prompt
    while preserving the default template's capability surface.
  - Template is visible only on Apple devices and is rejected at runtime on
    non-Apple platforms to avoid mismatched expectations.
  - Thread-template selection UI now adapts its card grid to available width,
    so added templates keep the dialog smooth and balanced.

- **ToolSearch loaded-tools dialog** polish (Phases 9–17):
  - History export popup now shows tooltips per item (CSV / Markdown / JSON
    hints) explaining whether the action targets the clipboard or a file.
  - "Import from JSON" entry next to Clear: pick a JSON dump produced by
    `ToolSearchHistorySerializer.toJson` and preview its entries (timestamp,
    source, query, +added / total) in a read-only dialog. Parse failures
    surface the FormatException via SnackBar instead of crashing.
  - Reusable `OhPill` shared widget in `lib/shared/ui/oh_pill.dart`
    with widget tests covering icon / label / InkWell wiring and overflow
    behaviour.
  - `ToolSearchHistoryExportPrefs` (sqflite-backed KV) for "last save
    directory" memory; covered by 7 unit tests (round-trip, overwrite,
    whitespace trim, empty-string-clear, no-collision with main settings
    row).
  - Settings → MCP debug: **Replay last cancel** action that re-fires the
    most recently undone ToolSearch replay via the new
    `ToolSearchReplayDispatcher.replayLastCancelled()`. Disabled when
    nothing is replayable; toast distinguishes fired vs no-op.
  - `HarnessPendingReplayBadge` extracted as a public widget with
    injectable `tickInterval` / `nowProvider` for deterministic testing.

### Added

- **Hermes Talker thread template** with end-to-end self-learning:
  - New `memory` builtin tool (list / append / upsert_profile / update / delete),
    template-scoped to `hermes_talker` only (alongside `skill_manager`).
  - `SelfLearningScheduler` + `SelfLearningRunner` pair that scans Hermes Talker
    sessions from the last 7 days and dispatches a restricted sub-agent to
    persist lasting insights into the user profile and `自主学习`-tagged
    memories.
  - System-managed cron entry `self_learning.hermes_talker` (`*/5 * * * *`,
    scriptType=agent) seeded on app start. System cron rows show a lock icon
    and cannot be edited or deleted; the enabled toggle stays live.
  - Settings → Hermes Talker: master toggle + concurrency slider (1..10,
    default 5).
  - New `AiSessionMessageKind.selfLearning` and dedicated chat card.

### Changed

- Global **Memory Tone Policy** appended to every template's system and
  developer instructions. The assistant no longer announces when a reply
  draws on stored memories.
- `CronScriptType.agent` added for system-managed jobs.
- `AiBuiltinToolKind.memory` enum value added; all exhaustive switches
  updated (harness affinity treats it as un-categorized, settings icon uses
  `psychology_rounded`).
