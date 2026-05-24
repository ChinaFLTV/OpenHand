// 2026-05-24 — 消息内容渲染格式。
//
// 用户可在「全局设置 → AI 设置 → 会话设置」中切换 AI 侧消息卡片的渲染
// 形式。默认 markdown 与现状一致；plainText 性能最优，直接以纯文本展示；
// html 通过第三方渲染库展示，渲染失败时按 [AiHtmlRenderFallback] 降级。
//
// 该枚举随 Prompt 注入与运行时上下文一起传递，下游 prompt builder
// 会在非 markdown 模式下追加对应的 output_format reminder。

enum AiMessageContentFormat {
  markdown,
  plainText,
  html;

  /// 持久化用的稳定 token；不要随便改值，会影响向后兼容。
  String get storageKey {
    switch (this) {
      case AiMessageContentFormat.markdown:
        return 'markdown';
      case AiMessageContentFormat.plainText:
        return 'plain_text';
      case AiMessageContentFormat.html:
        return 'html';
    }
  }

  static AiMessageContentFormat fromStorageKey(
    Object? value, {
    AiMessageContentFormat fallback = AiMessageContentFormat.markdown,
  }) {
    if (value is! String) return fallback;
    switch (value) {
      case 'markdown':
        return AiMessageContentFormat.markdown;
      case 'plain_text':
      case 'plaintext':
        return AiMessageContentFormat.plainText;
      case 'html':
        return AiMessageContentFormat.html;
    }
    return fallback;
  }
}

/// HTML 渲染失败时的回退策略。仅在 [AiMessageContentFormat.html] 下有意义。
///
/// markdown：尝试用 Markdown 解析（再失败则强制 plainText）。
/// plainText：直接以纯文本兜底，最快。
enum AiHtmlRenderFallback {
  markdown,
  plainText;

  String get storageKey {
    switch (this) {
      case AiHtmlRenderFallback.markdown:
        return 'markdown';
      case AiHtmlRenderFallback.plainText:
        return 'plain_text';
    }
  }

  static AiHtmlRenderFallback fromStorageKey(
    Object? value, {
    AiHtmlRenderFallback fallback = AiHtmlRenderFallback.markdown,
  }) {
    if (value is! String) return fallback;
    switch (value) {
      case 'markdown':
        return AiHtmlRenderFallback.markdown;
      case 'plain_text':
      case 'plaintext':
        return AiHtmlRenderFallback.plainText;
    }
    return fallback;
  }
}

const AiMessageContentFormat defaultAiMessageContentFormat =
    AiMessageContentFormat.markdown;
const AiHtmlRenderFallback defaultAiHtmlRenderFallback =
    AiHtmlRenderFallback.markdown;

/// HTML 内容丰富度。仅在 [AiMessageContentFormat.html] 下生效，控制
/// 注入给模型的 `output_format` reminder 强度：
///
/// - balanced：克制、黑白灰主色调、结构化优先，token 成本最低。
/// - rich：放开色彩、卡片、徽章、图表，鼓励信息可视化。
/// - vivid：最高浓度——大胆渐变、霓虹/玻璃拟态、强对比配色与视觉冲击。
enum AiHtmlContentRichness {
  balanced,
  rich,
  vivid;

  String get storageKey {
    switch (this) {
      case AiHtmlContentRichness.balanced:
        return 'balanced';
      case AiHtmlContentRichness.rich:
        return 'rich';
      case AiHtmlContentRichness.vivid:
        return 'vivid';
    }
  }

  static AiHtmlContentRichness fromStorageKey(
    Object? value, {
    AiHtmlContentRichness fallback = AiHtmlContentRichness.balanced,
  }) {
    if (value is! String) return fallback;
    switch (value) {
      case 'balanced':
        return AiHtmlContentRichness.balanced;
      case 'rich':
        return AiHtmlContentRichness.rich;
      case 'vivid':
        return AiHtmlContentRichness.vivid;
    }
    return fallback;
  }
}

const AiHtmlContentRichness defaultAiHtmlContentRichness =
    AiHtmlContentRichness.balanced;
