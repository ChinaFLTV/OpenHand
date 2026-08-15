/// 结构化错误源。
///
/// 用于在一条错误中携带多个来源（如双端点测试同时失败、或原始错误 + 探测补充），
/// 避免把多条结构化文案字符串拼接导致标题重复、解析错乱。每个源由 `label`
/// （如「Responses 接口」）与 `body`（该源的完整结构化诊断文案）组成。
class AiErrorSource {
  const AiErrorSource({required this.label, required this.body});

  final String label;
  final String body;
}
