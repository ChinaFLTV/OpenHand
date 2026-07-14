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
- 增删改由 `MemoryController` 操作队列串行化，并使用 SQLite 行级原子写入
- 启动不阻塞主线程，首次访问前 entries 为空
