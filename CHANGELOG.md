# Changelog

All notable changes to OpenHand will be documented in this file.

## Unreleased

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
  updated (hardness affinity treats it as un-categorized, settings icon uses
  `psychology_rounded`).
