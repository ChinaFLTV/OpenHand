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

## 后续 manifest 工作

未来引入 `assets/prompts/manifest.yaml`：
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
