# Instructions feature

## 职责
管理用户自定义的全局/项目指令（user instructions），供 AI 系统提示拼接使用。

## 对外 API
- `InstructionsController` — Provider 提供，含 entries 与增删改方法；启动时未初始化，首次访问时懒加载
- `UserInstructionEntry` — 领域模型（barrel 再导出）
- `InstructionsModule.bootstrap()` / `InstructionsModule.providers(m)`
- `InstructionsView` — 设置页内的指令编辑 widget

## 依赖
- `data/instructions_store.dart`（SQLite 持久化）

## 不变量
- 同一 id 在 entries 内唯一
- 持久化串行化由 InstructionsStore 内部 mutationQueue 保证
- 启动时不阻塞主线程（lazy init）
