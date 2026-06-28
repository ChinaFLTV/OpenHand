# assets/prompts/_shared/

跨 preset 复用的 prompt 片段。规则：

- 片段内容必须能被**任意** preset 直接拼装而不破坏语义；preset 专属内容（如 machine_expert 的终端交互纪律）不放在此处。
- 每个片段顶层必须是单一标签块（如 `<identity>...</identity>`），便于 manifest 拼装时按标签去重。

当前片段：

| 文件 | 内容 |
|---|---|
| `identity.md` | OpenHand 身份纪律 |
| `refusal.md` | 安全/拒绝行为 |
| `tone.md` | 表达风格 / 格式化纪律 |
| `workflow.md` | 四阶段 Research → Synthesis → Implementation → Verification 循环 |

## 当前装配规则

所有线程模板统一走同一套 system prompt 装配流程：

1. 读取模板自己的 `system_instructions.md`。
2. 按固定顺序追加 `_shared/{identity,refusal,tone,workflow}.md`。
3. 若模板正文已含同名顶层标签（如 `<workflow>`），该共享片段自动跳过。
4. 再追加模板专属扩展片段、通用纪律与 Memory Tone Policy。

`siri_helper` 仅覆盖 `system_instructions.md`；`developer_instructions.md`
与 `compression_summary_instructions.md` 通过
`AiPromptTemplatePolicy.promptAssetFileOverrides` 继承 `default`，避免复制同
一份 prompt。

## 后续 manifest 工作

若未来引入 `assets/prompts/manifest.yaml`：
```yaml
presets:
  default:
    sections:
      - _shared/identity.md
      - _shared/refusal.md
      - _shared/tone.md
      - _shared/workflow.md
      - default/_tool_use.md          # preset 专属段
      - default/_compression.md
  machine_expert:
    sections:
      - _shared/identity.md
      - _shared/refusal.md
      - _shared/tone.md
      - machine_expert/_terminal_role.md
      - machine_expert/_terminal_discipline.md
```

构建时由 Dart 端的 `PromptTemplateRepository` 按 manifest 顺序拼装并缓存。
本阶段（P5）仅落骨架；实际 manifest 与 repository 改造留待后续会话。
