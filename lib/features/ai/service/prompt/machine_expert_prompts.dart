// Emergency fallback prompts for the `machine_expert` template.
// The authoritative prompts now live in `assets/prompts/machine_expert/*.md`
// and are loaded at runtime by `AiPromptTemplateRepository`. These constants
// are only used if `rootBundle.loadString` fails to load those assets (e.g.
// corrupted bundle or missing pubspec asset declaration). They intentionally
// stay short and tell both the user and the LLM how to recover.

const String _fallbackNotice = '''
[OpenHand 机器专家提示词资源加载失败 / OpenHand machine_expert prompt asset failed to load]

assets/prompts/machine_expert/*.md 没能从应用包中加载成功。当前是兜底模式，
完整模板提示词不可用。请用户检查应用安装是否完整 / 资源是否被剥离，并
重新打包后重试。

This is an emergency fallback. The full machine_expert template prompt is
not available. Please ask the user to reinstall / re-bundle the application
so that assets/prompts/machine_expert/*.md can be loaded.

底线行为约束 / Hard-line constraints (still apply in fallback mode):
- 不要伪造工具结果或终端输出 / Do not fabricate tool results or terminal output.
- 不要发明未列出的工具名 / Do not invent tool names that are not listed.
- 终端执行只用 MachineTerminal 工具；不要改用 Bash / Use MachineTerminal tools for terminal work; do not switch to Bash.
- 不要越界承诺 / Do not over-commit on tasks you cannot verify.
- 写命令前必须征得用户同意 / Always ask the user before running write-class commands.
''';

const String expertSystemInstructions = _fallbackNotice;
const String expertDeveloperInstructions = _fallbackNotice;
const String expertCompressionSummaryInstructions = _fallbackNotice;
