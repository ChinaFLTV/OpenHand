# Hermes Talker Thread Template Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a new thread template `hermes_talker` (v1.0.0) that behaves like the Default template but adds (a) a built-in `skill_manager` tool for CRUD on local skills, (b) a background self-learning cron that every 5 min dispatches a restricted sub-agent to turn recent conversation into durable memory/profile updates, and (c) a new in-conversation message card that renders self-learning outcomes.

**Architecture:**
- **Template** registered in `AiPromptTemplateRepository` with its own prompt assets under `assets/prompts/hermes_talker/`. Its resolved tool catalog is the Default catalog PLUS the new `skill_manager` built-in.
- **`skill_manager` tool** is a pure-Dart port of `hermes-agent/tools/skill_manager_tool.py` and the create/edit slice of `skills_tool.py`. It targets the user's globally-configured skills directory (`SettingsController.skillsStoragePath`), supports 6 actions (`create|edit|patch|delete|write_file|remove_file`), atomic writes, frontmatter validation, path-traversal defense, and stays inside the registry pattern used by `AiTodoWriteTool`.
- **Self-learning** uses the existing Cron system via a new `CronScriptType.agent` variant. A single system-managed cron entry `self_learning.hermes_talker` is seeded on first launch. Its executor is a `SelfLearningScheduler` that owns a bounded semaphore worker pool (default 5) and spawns per-session sub-agents. Each sub-agent has **only** `skill_manager` and `memory` builtins.
- **Memory model** gains a new `UserMemoryEntry.type = 'user_profile'` value: exactly one profile entry per workspace (upserted), while regular self-learned memories remain `type = 'user'` tagged `自主学习`. DB schema already stores `type` — no migration needed.
- **Messaging** gains `AiSessionMessageKind.selfLearning` plus a dedicated card in `_home_tool_call_widgets.dart`, rendered like a tool-call card (collapsible, icon, header chips) but with its own color + icon.
- **Tone guideline** (applies to ALL templates, per user) — prompt libraries are updated to say: when memory content informs a reply, weave it in naturally; never cite "I remember from memory" or imply surveillance.

**Tech Stack:** Flutter/Dart (SDK 3.11.0), provider + ChangeNotifier, sqflite_common_ffi, existing `AiToolRegistry`, existing `CronsController`, Dart async/`Completer`/`Semaphore`.

---

## Reading List Before Starting (skim once)

- `lib/features/ai/service/ai_prompt_template_repository.dart` — template registry, default prompts
- `lib/features/ai/service/ai_tool_runtime_service.dart:72-93` (`AiBuiltinToolKind`) & `:1119-1688` (`_builtinTools`)
- `lib/features/ai/tools/ai_tool_registry.dart` — how tools are registered, sub-tool injection pattern
- `lib/features/ai/tools/ai_todo_write_tool.dart` — reference "pure computation" tool pattern
- `lib/features/ai/tools/ai_write_tool.dart` and `ai_edit_tool.dart` — reference filesystem-writing tool pattern with atomic/validation behavior
- `lib/features/ai/model/ai_session_message.dart` — `AiSessionMessageKind` enum + factory constructors
- `lib/features/memory/model/user_memory_entry.dart` and `lib/features/memory/data/memory_store.dart`
- `lib/features/memory/memory_controller.dart` — queue pattern for concurrent writes
- `lib/features/crons/crons_controller.dart`, `crons_executor.dart`, `cron_parser.dart`
- `lib/app/model/cron_config.dart` — `CronEntry`, `CronScriptType`
- `lib/features/home/_home_tool_call_widgets.dart` — tool-call card rendering reference
- `lib/app/state/settings_controller.dart` — `skillsStoragePath` getter, update methods
- `/Users/liguanda/Public/PythonProjects/hermes-agent/tools/skill_manager_tool.py` — reference semantics for each action
- `/Users/liguanda/Public/PythonProjects/hermes-agent/gateway/run.py:857-962` — `_flush_memories_for_session` reference

---

## Task 1: Extend `UserMemoryEntry.type` to support user profile

**Files:**
- Modify: `lib/features/memory/model/user_memory_entry.dart`
- Test: `test/features/memory/user_memory_entry_test.dart` (create if missing)

**Step 1: Add constant + helpers**

In `user_memory_entry.dart`, below `static const String userType = 'user';` add:

```dart
  static const String userProfileType = 'user_profile';
  static const String autoLearnedTag = '自主学习';
  static const String userProfileEntryId = 'system:user-profile';

  bool get isUserProfile => type == userProfileType;
  bool get isAutoLearned => tags.any((t) => t == autoLearnedTag);
```

**Step 2: Test existing + new behavior**

```dart
test('userProfile entries are flagged', () {
  final entry = UserMemoryEntry(
    id: UserMemoryEntry.userProfileEntryId,
    type: UserMemoryEntry.userProfileType,
    createdAt: DateTime.utc(2026, 4, 25),
    content: 'User is a Flutter developer.',
    tags: const [],
  );
  expect(entry.isUserProfile, isTrue);
  expect(entry.isAutoLearned, isFalse);
});

test('autoLearned tag is detected', () {
  final entry = UserMemoryEntry(
    id: 'm-1',
    type: UserMemoryEntry.userType,
    createdAt: DateTime.utc(2026, 4, 25),
    content: 'preference: prefers concise code reviews',
    tags: const [UserMemoryEntry.autoLearnedTag],
  );
  expect(entry.isAutoLearned, isTrue);
});
```

Run: `flutter test test/features/memory/user_memory_entry_test.dart` — expect PASS.

**Step 3: Commit**

```bash
git add lib/features/memory/model/user_memory_entry.dart test/features/memory/user_memory_entry_test.dart
git commit -m "feat(memory): add user_profile type and 自主学习 tag constants"
```

---

## Task 2: `MemoryStore` — helpers for profile upsert + tag queries

**Files:**
- Modify: `lib/features/memory/data/memory_store.dart`
- Test: `test/features/memory/memory_store_test.dart` (append)

**Step 1: Add methods**

```dart
Future<UserMemoryEntry?> loadUserProfile() async {
  final entries = await load();
  for (final e in entries) {
    if (e.type == UserMemoryEntry.userProfileType) return e;
  }
  return null;
}

Future<List<UserMemoryEntry>> loadByTag(String tag) async {
  final entries = await load();
  return entries
      .where((e) => e.tags.any((t) => t.toLowerCase() == tag.toLowerCase()))
      .toList();
}

/// Upserts a single user_profile entry. Only one profile is allowed; older
/// profile rows are deleted before the new one is written to keep the model
/// invariant (`exactly one profile`) honest.
Future<UserMemoryEntry> upsertUserProfile({
  required String content,
  List<String> tags = const <String>[],
}) async {
  final normalizedContent = UserMemoryEntry.normalizeContent(content);
  if (normalizedContent.isEmpty) {
    throw ArgumentError.value(content, 'content', 'Profile content cannot be empty.');
  }
  final existing = await loadUserProfile();
  final effectiveTags = UserMemoryEntry.normalizeTags(tags);
  final entry = UserMemoryEntry(
    id: existing?.id ?? UserMemoryEntry.userProfileEntryId,
    type: UserMemoryEntry.userProfileType,
    createdAt: DateTime.now().toUtc(),
    content: normalizedContent,
    tags: effectiveTags,
  );
  if (existing == null) {
    await insertEntry(entry);
  } else {
    await updateEntry(entry);
  }
  return entry;
}
```

**Step 2: Tests**

Upsert twice, assert only one profile exists; `loadByTag('自主学习')` returns only tagged entries.

**Step 3: Commit**

```bash
git add lib/features/memory/data/memory_store.dart test/features/memory/memory_store_test.dart
git commit -m "feat(memory): profile upsert + tag query helpers"
```

---

## Task 3: `MemoryController` — expose profile + tag methods

**Files:** Modify `lib/features/memory/memory_controller.dart`

Add `userProfile` getter, `upsertUserProfile`, and `memoriesWithTag(tag)`. All go through the existing operation queue so concurrent updates from the UI vs the self-learning worker can't interleave.

```dart
UserMemoryEntry? get userProfile {
  for (final e in _entries) {
    if (e.type == UserMemoryEntry.userProfileType) return e;
  }
  return null;
}

List<UserMemoryEntry> memoriesWithTag(String tag) {
  final needle = tag.toLowerCase();
  return _entries
      .where((e) => e.tags.any((t) => t.toLowerCase() == needle))
      .toList(growable: false);
}

Future<UserMemoryEntry> upsertUserProfile({
  required String content,
  List<String> tags = const <String>[],
}) {
  return _enqueue(() async {
    final entry = await _store.upsertUserProfile(content: content, tags: tags);
    await _refreshFromStore();
    return entry;
  });
}
```

Commit: `feat(memory): controller exposes profile upsert + tag query`.

---

## Task 4: Memory panel UI — show profile + auto-learned group, hide internal id

**Files:** Modify `lib/features/memory/memory_view.dart` (or equivalent)

**Step 1** — inspect the current list rendering and add a top card for `userProfile` if present (label: "User Profile" / "用户画像"). Show auto-learned entries in their own collapsible section with a `自主学习` chip. Profile is editable (opens regular edit dialog) but `id` stays fixed.

**Step 2** — add a delete-guard: deleting the profile asks explicit confirmation with warning "Self-learning will recreate this on next cycle".

Commit: `feat(memory): profile + auto-learned memory sections in memory panel`.

---

## Task 5: Add `AiSessionMessageKind.selfLearning`

**Files:**
- Modify: `lib/features/ai/model/ai_session_message.dart`
- Test: `test/features/ai/model/ai_session_message_test.dart`

**Step 1:**

```dart
enum AiSessionMessageKind {
  user('user'),
  assistant('assistant'),
  reasoning('reasoning'),
  toolCall('tool_call'),
  tool('tool'),
  compressionPoint('compression_point'),
  mcp('mcp'),
  skill('skill'),
  hook('hook'),
  selfLearning('self_learning'),
  status('status');
  // ...
}
```

Add a factory:

```dart
factory AiSessionMessage.selfLearning({
  required String id,
  required String content,
  required DateTime createdAt,
  required Map<String, Object?> metadata,
}) {
  return AiSessionMessage(
    id: id,
    kind: AiSessionMessageKind.selfLearning,
    role: AiSessionMessageRole.system,
    content: content.trim(),
    createdAt: createdAt.toUtc(),
    characterCount: countCharacters(content),
    metadata: metadata,
  );
}
```

Extend `isConversationTurn` switch to include `AiSessionMessageKind.selfLearning => true` (counts as a turn so "last message is selfLearning" can be checked).

**Step 2:** Test serialize round-trip, `isVisible == true`, `isConversationTurn == true`.

**Step 3:** Commit `feat(session): add selfLearning message kind`.

---

## Task 6: Self-learning message card in UI

**Files:** Modify `lib/features/home/_home_tool_call_widgets.dart` and the parent message dispatcher (grep for a `switch` on `AiSessionMessageKind` that renders tool cards).

**Step 1** — add `_SelfLearningCard` widget: collapsed shows "自我学习 · [N] memories updated · [elapsed]"; expanded shows a) list of changed memory ids + summaries (read from `message.metadata['memory_changes']`), b) skill changes from `message.metadata['skill_changes']`, c) profile diff summary. Icon: `Icons.psychology_alt_rounded`. Header color: themed tertiary.

**Step 2** — ensure layout matches `_ToolCallBody` conventions (`_ExpandableToolSection`, `_ToolExecutionChip`).

**Step 3** — golden test or widget-pump test rendering the card with sample metadata.

Commit: `feat(home): render selfLearning message card`.

---

## Task 7: Register new built-in tool kind + enum

**Files:** Modify `lib/features/ai/service/ai_tool_runtime_service.dart`

**Step 1** — add to `AiBuiltinToolKind`:

```dart
enum AiBuiltinToolKind {
  // ... existing 20 values
  skillManager('skill_manager'),
}
```

**Step 2** — do NOT register in `_builtinTools` yet (that requires `SettingsController`, handled via registry factory). The enum just needs to exist first so the rest of the code compiles.

Commit: `chore(ai): reserve skill_manager enum value`.

---

## Task 8: `AiSkillManagerTool` — core class + `create`

**Files:**
- Create: `lib/features/ai/tools/ai_skill_manager_tool.dart`
- Test: `test/features/ai/tools/ai_skill_manager_tool_test.dart`

**Step 1 (failing test first):**

```dart
void main() {
  late Directory tmp;
  setUp(() async { tmp = await Directory.systemTemp.createTemp('skills_'); });
  tearDown(() async { if (tmp.existsSync()) tmp.deleteSync(recursive: true); });

  test('create writes SKILL.md with frontmatter and rejects invalid names', () async {
    final tool = AiSkillManagerTool(skillsDirProvider: () => tmp.path);
    final goodResult = await _execute(tool, action: 'create', name: 'my-skill', content: '''---
name: my-skill
description: Test skill
version: 1.0.0
---

# My Skill

Body.''');
    expect(goodResult.status, BashToolExecutionStatus.success);
    expect(File('${tmp.path}/my-skill/SKILL.md').existsSync(), isTrue);

    final bad = await _execute(tool, action: 'create', name: 'Bad Name!', content: '...');
    expect(bad.status, BashToolExecutionStatus.failed);
  });
}
```

**Step 2** — implement class skeleton with `execute()` dispatching on `args['action']`. Only `create` needs to pass here.

Semantics (ported from `skill_manager_tool.py`):
- `_validateName`: regex `^[a-z0-9][a-z0-9._-]*$`, max 64 chars.
- `_validateCategory`: single directory segment, same regex, max 64.
- `_validateFrontmatter`: must start with `---\n…\n---\n`, parsed with `package:yaml`, must include `name` + `description`, description ≤ 1024 chars, body non-empty.
- `_validateContentSize`: SKILL.md ≤ 100_000 chars.
- Name collision check: scan `<skillsDir>/**/SKILL.md` before creating.
- Skill dir: `<skillsDir>/[<category>/]<name>/SKILL.md`.
- Atomic write: same-directory temp file + `File.rename`.

**Step 3** — run test, verify PASS.

**Step 4** — Commit: `feat(ai): skill_manager create action`.

---

## Task 9: `AiSkillManagerTool` — `edit` + `delete`

Add actions with their own tests. `edit` is full rewrite (frontmatter still valid), `delete` removes the directory tree + cleans empty category dir, refuses if the skill is outside `skillsDirProvider()`.

Test: create, edit (new body), verify content; delete, verify gone; delete nonexistent returns failure result.

Commit: `feat(ai): skill_manager edit + delete`.

---

## Task 10: `AiSkillManagerTool` — `patch` with unique-match requirement

**Files:** same as above.

**Step 1** — test cases:
- Patch with unique `old_string` succeeds.
- Patch with non-unique match **and `replace_all=false`** fails with helpful error listing occurrences.
- Patch with `replace_all=true` replaces all.
- Patch that would break frontmatter returns validation error WITHOUT writing.

**Step 2** — implement using plain `String.indexOf` / `String.replaceAll`; we don't port the Python `fuzzy_match` (no equivalent in this repo, YAGNI).

**Step 3** — re-run frontmatter validation post-patch only when `file_path` is empty (i.e. patching SKILL.md).

Commit: `feat(ai): skill_manager patch with unique-match enforcement`.

---

## Task 11: `AiSkillManagerTool` — `write_file` + `remove_file`

**Files:** same.

- Restrict `file_path` first segment to `{references, templates, scripts, assets}`.
- Reject path-traversal (`..`) — reuse logic similar to `ai_write_tool.dart` if a helper already exists; otherwise add a small `_isWithin(parent, child)` using `path.normalize`.
- `remove_file` cleans up empty parent subdirs (but never removes the skill dir or the skills root).

Tests: write to allowed + disallowed paths, remove existing + missing, path-traversal rejected.

Commit: `feat(ai): skill_manager write_file + remove_file`.

---

## Task 12: Register `AiSkillManagerTool` in registry and wire `SettingsController`

**Files:**
- Modify: `lib/features/ai/tools/ai_tool_registry.dart`
- Modify: `lib/features/ai/service/ai_tool_runtime_service.dart` (the builtin tool list + schema definition)
- Modify: place where `AiToolRegistry.withServiceDependencies(...)` is called (grep for call sites)

**Step 1** — extend `withServiceDependencies` factory to take `String Function() skillsDirProvider`. Wire from `SettingsController.skillsStoragePath`.

**Step 2** — in `_builtinTools` in `ai_tool_runtime_service.dart`, append schema for `skill_manager` with JSON Schema matching the Python file's `SKILL_MANAGE_SCHEMA` (minus Python-only fields). `required: ['action', 'name']`.

**Step 3** — register in `lightweightOnly()` ONLY if tests construct it with a temp dir; otherwise keep it in the service-dependencies branch.

**Step 4** — rebuild tool catalog.

Commit: `feat(ai): wire skill_manager tool into registry and runtime`.

---

## Task 13: Add `hermes_talker` thread template entry + tool filter

**Files:**
- Modify: `lib/features/ai/service/ai_prompt_template_repository.dart`

**Step 1** — append to `_templates`:

```dart
AiThreadTemplate(
  id: 'hermes_talker',
  name: 'Hermes Talker',
  iconName: 'forum_rounded',
  description:
      '在 Default 模板基础上新增 skill_manager 工具与每 5 分钟运行的自我学习能力,持续在对话中积累用户画像与可复用技能。',
  internalVersion: '1.0.0',
  promptAssetDirectory: 'assets/prompts/hermes_talker',
),
```

**Step 2** — extend the `switch` in `loadBundle` with:

```dart
case 'hermes_talker':
  systemFallback = _hermesTalkerSystemInstructions;
  developerFallback = _hermesTalkerDeveloperInstructions;
  compressionFallback = _hermesTalkerCompressionSummaryInstructions;
```

**Step 3** — define the three fallback strings at the bottom of the file. They are copies of the Default fallbacks plus an appended `## Hermes Talker Extensions` section describing: (a) `skill_manager` usage guidance — prefer `patch` over `edit`, save on 5+ successful calls, confirm with user before deletion; (b) memory tone guideline — NEVER say "I remember that…"; weave memory content naturally; (c) awareness that a background self-learning pass runs every 5 min and may insert `selfLearning` messages which the assistant must NEVER respond to in-conversation.

Commit: `feat(ai): register hermes_talker thread template`.

---

## Task 14: Prompt asset files for Hermes Talker

**Files (create):**
- `assets/prompts/hermes_talker/system_instructions.md`
- `assets/prompts/hermes_talker/developer_instructions.md`
- `assets/prompts/hermes_talker/compression_summary_instructions.md`

Copy verbatim from `assets/prompts/default/*.md`, then append the extension sections mirroring the fallbacks. Register the new directory in `pubspec.yaml` (check how `assets/prompts/default` is listed — if it's a wildcard, no change needed).

Run `flutter pub get` and confirm `AssetManifest.json` includes the new files.

Commit: `feat(ai): hermes_talker prompt assets`.

---

## Task 15: Template-scoped tool catalog (include skill_manager only when hermes_talker)

**Files:** Modify the place where `AiResolvedToolCatalog` is built per-session. Grep for `AiResolvedToolCatalog` and/or `builtinToolConfigs`.

**Step 1** — add a template-aware filter: the base built-in set is the Default set (= everything except `skill_manager`). Only include `skill_manager` when `session.templateId == 'hermes_talker'`. This keeps other templates unchanged.

**Step 2** — add a widget test that loads a new session with each of the 4 existing templates and asserts `skill_manager` is NOT in the resolved catalog; then Hermes Talker session and asserts it IS present.

Commit: `feat(ai): include skill_manager in hermes_talker tool catalog`.

---

## Task 16: Extend `CronScriptType` with `agent` variant

**Files:**
- Modify: `lib/app/model/cron_config.dart`
- Modify: `lib/features/crons/crons_executor.dart` (dispatch branch)
- Modify: `lib/features/crons/crons_view.dart` (hide agent-type rows behind a "system" filter OR show them with a read-only chip)

**Step 1** — enum:

```dart
enum CronScriptType {
  command('command', 'Command', '命令'),
  script('script', 'Script', '脚本'),
  agent('agent', 'Agent', 'Agent');
  // ...
}
```

**Step 2** — the executor dispatches `agent` jobs to a new `CronAgentDispatcher` (defined in next task) instead of spawning a shell process. Signature stays result-compatible with `CronExecutionRecord` so history renders correctly.

**Step 3** — UI: show agent-type cron entries with a lock icon + tooltip "System-managed"; editor dialog hides script fields for this type and shows read-only descriptive panel instead.

Commit: `feat(crons): add agent script type`.

---

## Task 17: `SelfLearningScheduler` — worker pool + candidate scan

**Files (create):** `lib/features/ai/service/self_learning_scheduler.dart`

**Step 1 — semaphore:**

```dart
class _Semaphore {
  _Semaphore(this._max);
  final int _max;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> acquire() async {
    if (_active < _max) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _active = (_active - 1).clamp(0, _max);
    }
  }
}
```

**Step 2 — main class:**

```dart
class SelfLearningScheduler {
  SelfLearningScheduler({
    required AiSessionStore sessionStore,
    required AiChatService chatService,
    required MemoryController memoryController,
    required SettingsController settingsController,
    required AiPromptTemplateRepository promptRepository,
    int concurrency = 5,
  }) : _pool = _Semaphore(concurrency),
       _sessionStore = sessionStore,
       _chat = chatService,
       _memory = memoryController,
       _settings = settingsController,
       _prompts = promptRepository;

  Future<SelfLearningTickResult> tick({DateTime? now}) async { /* see below */ }
}
```

**Step 3 — tick body:**
1. `now ??= DateTime.now().toUtc();`
2. Load all sessions with `templateId == 'hermes_talker'` and `createdAt >= now - Duration(days: 7)`.
3. For each, read the newest `displayMessages` entry; skip if `kind == selfLearning` (already learned) or if the session currently has `metadata['self_learning_in_progress'] == true`.
4. `await _pool.acquire()`, spawn `_runForSession(session)` in a fire-and-forget future that releases the pool in `finally`.
5. Collect futures, await all, return `SelfLearningTickResult(scanned, triggered, skipped, errors)`.

**Step 4 — unit tests** with fakes: verify pool cap, skip when latest is `selfLearning`, skip outside 7-day window.

Commit: `feat(ai): self-learning scheduler with bounded worker pool`.

---

## Task 18: `SelfLearningScheduler._runForSession` — sub-agent dispatch

**Files:** same as Task 17.

**Step 1** — Mark session metadata `self_learning_in_progress = true` (prevents double-dispatch across ticks).

**Step 2** — Build sub-agent context:
- Current `userProfile` content (from `MemoryController.userProfile?.content`, empty string if none).
- Current auto-learned memories list (via `memoriesWithTag('自主学习')`).
- Conversation slice: messages AFTER the last `selfLearning` message (or all if none), user + assistant only, deleted excluded.
- Abort early if slice has < 4 messages (mirrors Python `len(history) < 4` guard).

**Step 3** — Construct the flush prompt. Base on the Python prompt at `gateway/run.py:926-952` but translated to Chinese, tailored to OpenHand's memory/skill tools, and explicitly listing the two memory conventions:

```
[系统消息: 这是一次自我学习流程,目的是在不打扰用户的情况下,将本次对话
中沉淀下来的价值信息持久化为长期记忆或技能。请按以下步骤执行:

1. 审视下方对话,提炼出:
   - 用户画像更新 (偏好/角色/关注点/习惯)
   - 通用价值记忆 (不属于画像的经验/事实/决策)
   - 可复用技能 (若本次解决了非平凡的可复现任务)
2. 调用 memory 工具:
   - 对 type=user_profile 的记忆,使用 upsert 而非新建 (全库只允许一条
     user_profile 记忆);在已有画像基础上纠正/精炼,而不是覆盖无关字段。
   - 对 type=user 的自主学习记忆,使用 '自主学习' 标签;优先更新已有相
     关条目,而不是无限新增。
3. 调用 skill_manager 工具 (仅在出现可复用工作流时):
   - 优先使用 patch 细调,而非 edit 全量重写。
   - 默认保存到用户全局设置中的技能目录。
4. 输出自然、零痕迹;不要向用户提及记忆/画像这件事。

---

## 当前用户画像
{{userProfile or '(空)'}}

## 最近的自主学习记忆
{{autoLearnedMemories or '(空)'}}

## 本次需要学习的对话片段
{{conversationSlice}}

完成后不要回复用户,只需调用工具并结束本轮。]
```

**Step 4** — Dispatch via `_chat.runSubAgent(...)` with `allowedBuiltinTools: {memory, skill_manager}` — NO bash, NO web, NO read/write/edit, etc. If the chat service lacks a `runSubAgent` path with tool allow-list, add one (thin wrapper over the existing mechanism used by `AiTaskTool`).

**Step 5** — On completion, capture the list of memory/skill mutations from the tool result stream and build `metadata` for the new `selfLearning` message. Persist the message through the normal session mutation path so the UI picks it up live.

**Step 6** — Error handling: catch all, log, still write a `selfLearning` message with `metadata['status'] = 'error'` + error summary, clear the in-progress flag.

Commit: `feat(ai): dispatch restricted sub-agent for self-learning`.

---

## Task 19: Seed the `self_learning.hermes_talker` cron entry

**Files:**
- Modify: `lib/features/crons/crons_controller.dart` initialization path
- Modify: `lib/features/crons/crons_executor.dart` — branch `CronScriptType.agent` → invoke `SelfLearningScheduler.tick()`

**Step 1** — On controller `init()`, if no entry with `id == 'self_learning.hermes_talker'` exists, insert:

```dart
CronEntry(
  id: 'self_learning.hermes_talker',
  name: 'Hermes Talker 自我学习',
  description: '每 5 分钟扫描最近 7 天的 Hermes Talker 会话,对未学习的会话派发受限子 Agent 更新记忆与技能。',
  scriptType: CronScriptType.agent,
  cronExpression: '*/5 * * * *',
  retryCount: 0,
  timeoutSeconds: 600,
  enabled: true,
  onSuccessNotify: CronNotifyType.log,
  onFailureNotify: CronNotifyType.log,
  tags: const ['system', 'hermes_talker'],
)
```

**Step 2** — When the executor hits `scriptType == agent` with the tag `'hermes_talker'`, call `selfLearningScheduler.tick()` and translate the `SelfLearningTickResult` to a `CronExecutionRecord` (stdout: `scanned=X triggered=Y skipped=Z`; stderr: any per-session errors). Status: `success` if no exception, `failed` otherwise.

**Step 3** — Integration test: fake cron fires → scheduler.tick() invoked; verify idempotence.

Commit: `feat(crons): seed system-managed hermes_talker self-learning job`.

---

## Task 20: Cron editor — hide `agent` type from user-created rows

**Files:** `lib/features/crons/crons_view.dart` editor dialog.

Users can see but not change/delete system-managed `agent` rows. Add a lock icon and disable edit/delete buttons when `tags.contains('system')`. Users CAN toggle enabled (off/on) — some will want to pause self-learning.

Commit: `feat(crons): protect system agent rows from edit/delete`.

---

## Task 21: Settings — self-learning worker pool size + master toggle

**Files:**
- Modify: `lib/app/model/app_settings_snapshot.dart` — add `selfLearningEnabled (bool, default true)`, `selfLearningConcurrency (int, default 5, min 1, max 10)`.
- Modify: `lib/app/state/settings_controller.dart` — getters/setters.
- Modify: `lib/app/data/settings_store.dart` — JSON encode/decode.
- Modify: `lib/features/settings/settings_view.dart` — add UI in a new "Hermes Talker" section.
- Wire through `SelfLearningScheduler._pool` to reflect live concurrency changes (rebuild scheduler or expose `setConcurrency`).

Commit: `feat(settings): self-learning toggle + concurrency`.

---

## Task 22: Global tone guideline — update all template prompts

**Files:** the fallback constant strings inside `ai_prompt_template_repository.dart` and each template's `assets/prompts/*/developer_instructions.md`.

Append a short section to EACH template's developer prompt (not just Hermes Talker):

```
## Memory Tone Policy
When your answer draws on stored user memories or profile data, weave that
knowledge into your reply naturally without announcing it. Do NOT say "I
remember that…", "from memory…", "you told me earlier…", or similar
tell-tales. Treat memory as invisible context, not as something the user
needs to be reminded you're tracking.
```

Commit: `feat(ai): natural tone policy across all templates`.

---

## Task 23: End-to-end test — Hermes Talker session exercises new flow

**Files (create):** `integration_test/hermes_talker_flow_test.dart`

Scenario with fakes:
1. Create Hermes Talker session.
2. Simulate 6 user↔assistant turns.
3. Trigger `SelfLearningScheduler.tick()` directly.
4. Assert: a `selfLearning` message appears, `memoriesWithTag('自主学习')` now has ≥ 1 entry, `userProfile` is non-null.
5. Trigger `.tick()` again immediately → assert no duplicate dispatch (latest message is still the previous `selfLearning`, nothing new).
6. Add a new user turn → tick again → assert a new `selfLearning` is added and ONLY processes messages after the prior learning point.

Commit: `test(ai): hermes_talker self-learning integration flow`.

---

## Task 24: App bootstrap — construct and start `SelfLearningScheduler`

**Files:** `lib/app/bootstrap.dart` or wherever controllers are composed.

**Step 1** — after `CronsController.init()`, construct `SelfLearningScheduler` with the current concurrency setting and pass it into the executor dispatch so the `agent` cron branch can find it.

**Step 2** — wire a listener to `SettingsController.selfLearningConcurrency` so changes update the pool.

Commit: `feat(app): bootstrap self-learning scheduler`.

---

## Task 25: Manual smoke test + docs

**Files:** README note under "Thread Templates" listing Hermes Talker. A short CHANGELOG line.

Manual checklist (run locally):
- [ ] Create Hermes Talker session, send a few messages.
- [ ] `Cron` panel shows the system-managed job (lock icon, cannot delete, can disable).
- [ ] Wait 5 min OR manually trigger the cron entry — a `selfLearning` card appears in-conversation.
- [ ] `Memory` panel shows a profile entry + a "自主学习" section with new entry.
- [ ] Create another Hermes Talker session, ask the assistant to save a reusable "git-worktree-cleanup" skill — confirm it appears in the skills directory.
- [ ] Send a follow-up question that implicitly uses profile content — assistant answers naturally WITHOUT citing memory.

Commit: `docs: mention hermes_talker template in README + CHANGELOG`.

---

## Risks & Considerations

- **Sub-agent cost**: every 5 min per active session can be expensive. Mitigation: skip when latest msg is already `selfLearning`; min-4-message gate; single-flight per session via `self_learning_in_progress` flag.
- **Concurrency correctness**: memory/skill writes from multiple sub-agents MUST go through `MemoryController._enqueue` and the `AiSkillManagerTool` atomic-write path — both are already serialized.
- **Race with user-initiated memory edits**: same queue handles it. Profile upsert always reads latest before writing.
- **Prompt injection via conversation content**: the sub-agent is restricted to two tools (memory + skill_manager), each of which validates/atomic-writes. No `Bash`, no `WebFetch`. The worst an injected prompt can do is write weird memory content — which the user can edit out.
- **Template version bump discipline**: Hermes Talker starts at `1.0.0`. Any change to the system prompt MUST bump `internalVersion` (template dialog shows the version string).
- **Settings concurrency live-update**: if `selfLearningConcurrency` drops while workers are active, existing workers finish at the old pool size — the new cap applies to the next `acquire()`.

---

## Out of Scope (explicitly NOT in this plan)

- Porting the Python `skills_guard` security scanner — OpenHand has no analogue; document as a follow-up.
- Porting Hermes plugin-skill namespace (`plugin:skill`) — OpenHand's skill system is flat.
- Porting `fuzzy_match` — plain `String` ops are enough for v1.
- MCP exposure of `skill_manager` — only surfaced as a built-in, not via MCP.
- Cross-session memory merge logic beyond the profile upsert — if two sessions learn conflicting facts, the latest wins.
