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
- 持久化串行化由 InstructionsController 的操作队列保证
- 启动时不阻塞主线程（lazy init）

## 本地指令市场
- `data/instruction_market_catalog.dart` 内置 16 个角色，保留来源 ID、素材引用、简介与解读；不请求远程目录或图片。
- 角色提示词由角色、风格、方式、语气四个字段统一生成；角色解读仅用于展示，不注入提示词。
- 添加复用 `InstructionsController.createEntry`，添加后统一停用，由用户在指令板块选择性启用；以来源关键字和正文识别已添加条目。
- 市场沿用共享弹窗、纯色面板与 Markdown 组件，列表和详情各自持有滚动控制器。
