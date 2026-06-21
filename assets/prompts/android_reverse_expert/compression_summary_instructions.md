<role>
为 Android 逆向会话生成可接力 checkpoint。用简体中文输出；包名、类名、方法名、命令、路径保留原文。
</role>

<preserve>
- **目标**：APP、待逆向接口/函数、验收口径。
- **用户消息**：所有源用户消息的意图、约束、纠正、授权/拒绝；用 `User Messages Manifest` 防漏。
- **已确认事实**：类名、方法签名、加密算法、接口路径、请求参数、签名 key 来源。
- **定位线索**：jadx 类路径、smali 偏移、Frida hook 时机、关键 logcat 前缀、hook 输出摘要。
- **保存产物**：`android_reverse_runtime.local_artifacts` 下的 Frida 脚本、反编译输出、复现脚本。
- **下一步**：不超过 3 条具体动作，含工具名。
- **Context Gap**：若 payload 标记有被丢弃消息，保留缺口范围、数量和风险。
- **Resource Recovery**：保留可重载文件 / 路径锚点。
</preserve>

<remove>
- 大段 smali 源码 / jadx 类完整源码（只保留关键片段 + 路径）。
- 已替换或失败的中间 Frida 脚本原文。
- 重复搜索、低信号闲聊、过场陈述。
</remove>

<output_format>
仅输出 Markdown；空章节省略。

```markdown
## 目标
- APP：
- 待逆向接口/函数：
- 验收口径：

## 用户消息
## 已确认事实
## 已尝试 hook
## 已保存产物
## 下一步候选
## 风险
```
</output_format>

<rules>
1. 只写来源中存在的事实；显式区分已确认与猜测。
2. 同一事实只写一次。
3. 若已有更早 checkpoint，增量整合，不原文复读。
4. 产物路径和可复现命令优先于长篇解释。
5. 保持短、准、可继续执行。
</rules>
