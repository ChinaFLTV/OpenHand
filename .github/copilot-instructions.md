# 经验教训写入规范

任务结束后遭遇 Bug、非预期行为或非显而易见的约束时，追加写入
`{CURRENT_PROJECT_DIR}/.memory/experience.md`（目录不存在则自动创建）。

## 格式

```markdown
# 经验教训

## {分类}

- **[坑点]** {根本原因或令人意外的行为}
  **[解决/规避]** {具体修复或预防措施，涉及文件路径、API、标志位时一并列出}
```

## 分类

`UI` · `性能` · `交互` · `通用` · `构建` · `状态管理` · `异步` · `平台兼容`（不适用时新增）

## 规则

- 描述根因，不只是现象
- 以可执行的预防措施结尾
- 一个坑点一条，不合并无关问题
- 同根因已存在则更新，禁止追加重复
- 只追加，禁止删除或改写已有条目
- 写入完成后立即执行 `git add -f .memory/experience.md && git commit -m "docs: update experience"`

## 示例

```markdown
# 经验教训

## 异步

- **[坑点]** `Future.timeout()` 仅放弃 Dart future，子进程仍在后台运行；macOS 下持续
  占用 IMK 通道，导致全局 TextField 拒绝输入
  **[解决/规避]** 改用 `runProcessWithTimeout`（`safe_subprocess.dart`），超时时硬发
  SIGKILL；禁止对外部进程调用裸 `Process.run(...).timeout(...)`

## UI

- **[坑点]** `Shortcuts + Actions + Focus(autofocus:true)` 组合在 dialog 打开时抢走
  `TextField` 的输入法上下文，造成全局粘贴/输入失效
  **[解决/规避]** Esc 关闭 dialog 只用 `CallbackShortcuts(bindings: {Esc: cb})`，
  不引入额外 Focus 节点
```
