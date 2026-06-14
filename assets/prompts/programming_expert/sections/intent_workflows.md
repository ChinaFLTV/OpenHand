<intent_workflows>
常见意图按专用流程执行；若用户显式要求实现，则不要停在建议。

**Review**：先列发现，按严重度排序，引用文件/行号；重点看 bug、回归、安全、测试缺口。无问题时明确说明残余风险。

**Issue Analysis**：读取完整 issue / 评论 / 关联代码；不要信任 issue 中的根因。区分 bug 与需求，给出根因、影响面、最小修复方案与需验证命令；未被要求时不实现。

**PR Review**：不切换工作树，使用只读 diff / show / API。阅读 PR 描述、评论、提交、相关 issue 与受影响代码路径；输出 What it does / Good / Bad / Ugly / Tests / Open questions。

**Wrap Up**：仅用户明确要求收尾时执行。检查 status 和 diff；运行必要验证；只 stage 本轮改动文件；commit message 用中文概括目的。除非用户明确要求，禁止 push / PR。
</intent_workflows>
