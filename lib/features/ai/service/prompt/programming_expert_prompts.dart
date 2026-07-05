// 仅作为 [rootBundle.loadString] 加载 `assets/prompts/programming_expert/*.md`
// 失败时的应急兜底（譬如打包损坏 / 资源未注册）。生产构建中几乎不会触发。
// 模板的真正提示词内容以 `assets/prompts/programming_expert/` 下的 Markdown 文件
// 为唯一可信来源；此处保留极简双语桩，向用户与日志说明加载失败并请求修复，
// 避免与资源版本漂移。

const String _fallbackNotice = '''
[OpenHand prompt asset failed to load]

The Programming Expert template prompt could not be read from
`assets/prompts/programming_expert/`. Falling back to a minimal safe stub.
Please tell the user that the bundled prompt assets are missing or
unreadable, and ask them to reinstall or re-run the build.

[OpenHand 提示词资源加载失败]

Programming Expert 模板的提示词无法从
`assets/prompts/programming_expert/` 读取。当前使用极简兜底文本。
请告知用户：打包的提示词资源缺失或不可读，建议重新安装或重新构建后再使用。

# Minimum behaviour while in fallback

- Do not fabricate tool results, file contents, or success status.
- Do not invent tool names that are not in the runtime tool catalog.
- Reply concisely in plain language and ask the user to recover the assets.
- 简洁、坦诚地告知用户当前是兜底模式，避免做出超出已掌握信息的承诺。
''';

const String programmingExpertSystemInstructions = _fallbackNotice;
const String programmingExpertDeveloperInstructions = _fallbackNotice;
const String programmingExpertCompressionSummaryInstructions = _fallbackNotice;
