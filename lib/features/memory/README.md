# Memory feature

## 职责
管理用户长期记忆（user memory），供 AI 在 self-learning 子代理与运行时上下文中读取。

## 对外 API
- `MemoryController` — Provider 提供，含 entries 与增删改方法；启动时未初始化，首次 `refresh()` 触发 sqlite 读取
- `UserMemoryEntry` — 领域模型（barrel 再导出）
- `MemoryModule.bootstrap()` / `MemoryModule.providers(m)`
- `MemoryView` — 设置页内的 memory 编辑 widget
- barrel: `features/memory/index.dart`

## 依赖
- `data/memory_store.dart`（SQLite 持久化）

## 不变量
- 同一 id 在 entries 内唯一
- 最多 1024 条、总 UTF-8 负载 16 MiB；单条正文与标签边界由 Store 统一校验
- 加载严格校验字段、UTC 时间与标签 JSON；损坏快照禁止普通写入
- 历史总量超限时只加载受限快照，仅允许删除或缩小并在每次成功后重载
- 增删改由 `MemoryController` 串行化，SQLite 事务成功后才发布内存快照
- 显式清空同时写入 legacy 迁移标记，可从损坏源安全恢复
- 启动不阻塞主线程，首次访问前 entries 为空
