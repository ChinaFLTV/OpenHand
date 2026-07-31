// 输出格式控制 Prompt 片段的运行时缓存。
// 真正的可维护内容存放在 [assets/prompts/_shared/output_format_html_*.md] 与
// [assets/prompts/_shared/output_format_plaintext.md]。本类负责在 app boot
// 阶段把它们一次性加载进进程内常量，供 [AiPromptBuilder] 同步读取。
// 加载失败时使用最小兜底文本，保留非 Markdown 模式的基本格式约束。

import 'package:flutter/services.dart';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../model/ai_message_content_format.dart';

class AiOutputFormatPrompts {
  AiOutputFormatPrompts._();

  static const String htmlBalancedAssetPath =
      'assets/prompts/_shared/output_format_html_balanced.md';
  static const String htmlRichAssetPath =
      'assets/prompts/_shared/output_format_html_rich.md';
  static const String htmlVividAssetPath =
      'assets/prompts/_shared/output_format_html_vivid.md';
  static const String plainTextAssetPath =
      'assets/prompts/_shared/output_format_plaintext.md';
  static const String gptChatRulesAssetPath =
      'assets/prompts/_shared/output_format_gpt_chat_rules.md';

  static String _htmlBalanced = _fallbackHtmlBalanced;
  static String _htmlRich = _fallbackHtmlRich;
  static String _htmlVivid = _fallbackHtmlVivid;
  static String _plainText = _fallbackPlainText;
  static String _gptChatRules = _fallbackGptChatRules;
  static bool _loaded = false;
  static final OpenHandSingleFlight<void> _loadFlight =
      OpenHandSingleFlight<void>();

  static String get plainText => _plainText;
  static String get gptChatRules => _gptChatRules;

  static String htmlFor(AiHtmlContentRichness richness) {
    switch (richness) {
      case AiHtmlContentRichness.balanced:
        return _htmlBalanced;
      case AiHtmlContentRichness.rich:
        return _htmlRich;
      case AiHtmlContentRichness.vivid:
        return _htmlVivid;
    }
  }

  /// 根据当前应用主题生成 theme_context 提示词片段。
  /// 在 HTML 模式下注入到 prompt，引导模型生成与当前界面亮度/配色一致的内容。
  /// 主题元数据已同时写入 [3s] Static Session State (theme 字段)，
  /// 此处仅保留 HTML 专属的视觉指令，避免信息重复。
  static String themeContextFor({
    required String brightness,
    required String presetName,
    required String primaryColor,
  }) {
    final isDark = brightness == 'dark';
    final directive = isDark
        ? '深色主题：使用深色背景、浅色正文、深色卡片体系；禁止大面积白底/浅色内容。'
        : '浅色主题：使用浅色背景、深色正文、浅色卡片体系；禁止大面积黑底/深色内容。';
    return '<theme_context mode="$brightness" preset="$presetName" primary="$primaryColor">'
        '$directive 可结合主题色 $primaryColor 做视觉表达，避免纯黑白单调。</theme_context>';
  }

  static Future<void> ensureLoaded([AssetBundle? bundle]) {
    if (_loaded) return Future<void>.value();
    return _loadFlight.run(() => _load(bundle ?? rootBundle));
  }

  static Future<void> _load(AssetBundle bundle) async {
    try {
      final results = await Future.wait<String>(<Future<String>>[
        bundle.loadString(htmlBalancedAssetPath, cache: false),
        bundle.loadString(htmlRichAssetPath, cache: false),
        bundle.loadString(htmlVividAssetPath, cache: false),
        bundle.loadString(plainTextAssetPath, cache: false),
        bundle.loadString(gptChatRulesAssetPath, cache: false),
      ]);
      final loadedBalanced = results[0].trim();
      final loadedRich = results[1].trim();
      final loadedVivid = results[2].trim();
      final loadedPlain = results[3].trim();
      final loadedGpt = results[4].trim();
      if (loadedBalanced.isNotEmpty) _htmlBalanced = loadedBalanced;
      if (loadedRich.isNotEmpty) _htmlRich = loadedRich;
      if (loadedVivid.isNotEmpty) _htmlVivid = loadedVivid;
      if (loadedPlain.isNotEmpty) _plainText = loadedPlain;
      if (loadedGpt.isNotEmpty) _gptChatRules = loadedGpt;
      _loaded = true;
    } catch (error, stack) {
      silentLog('ai_output_format_prompts', '加载输出格式提示词', error, stack);
    }
  }
}

/// 三档 HTML 兜底提示词共用的硬性约束；仅在资源加载失败时使用。
const String _fallbackHtmlHardRules = """
  <directive>本轮只输出一个自包含 HTML 片段。首字符必须是 &lt;div&gt;；禁止 Markdown；禁止任何前导或尾随解释文字。</directive>
  <hard-rules>
    <item>根容器必须是带内联 style 的单个 &lt;div&gt;；所有可见文本都必须包在 HTML 标签内</item>
    <item>禁止 ```、`、#、**、-、1.、&gt;、|---| 等 Markdown 格式语法；需要标题、列表、引用、表格时必须改用 HTML 标签</item>
    <item>禁止 &lt;style&gt;、&lt;script&gt;、class、外链 CSS/JS、&lt;iframe&gt;、&lt;object&gt;、&lt;embed&gt;</item>
    <item>只允许内联 style；禁止 &lt;!DOCTYPE&gt; / &lt;html&gt; / &lt;head&gt; / &lt;body&gt; 整页骨架</item>
  </hard-rules>""";

const String _fallbackHtmlBalanced =
    '<output_format mode="html">$_fallbackHtmlHardRules'
    """
  <layout>
    <item>对比/决策：优先表格或双列卡片</item>
    <item>流程/步骤：优先时间线或步骤卡片</item>
    <item>指标/数据：优先指标卡片 + 紧凑表格</item>
    <item>长内容：先摘要，再用 &lt;details&gt; 折叠次要信息</item>
  </layout>
  <visual>
    <item>balanced 档位保持浅色、克制、企业风格；主色 #3182ce，推荐 #38a169，风险 #e53e3e</item>
  </visual>
</output_format>""";

const String _fallbackHtmlRich =
    '<output_format mode="html">$_fallbackHtmlHardRules'
    """
  <layout>
    <item>对比/决策：优先矩阵表格或对比卡片</item>
    <item>流程/步骤：优先时间线、步骤卡片或节点流</item>
    <item>指标/数据：优先指标卡片、徽章、进度条和紧凑表格</item>
    <item>长内容：先摘要，再用 &lt;details&gt; 折叠次要信息</item>
  </layout>
  <visual>
    <item>rich 档位允许更明显的色彩、卡片、徽章、轻渐变和流程节点，但仍以可读性和信息密度为先</item>
  </visual>
</output_format>""";

const String _fallbackHtmlVivid =
    '<output_format mode="html">$_fallbackHtmlHardRules'
    """
  <layout>
    <item>对比/决策：优先矩阵表格、对比卡片和节点流</item>
    <item>流程/步骤：优先节点流、时间线或步骤卡片</item>
    <item>指标/数据：优先指标卡片网格、徽章、进度条和紧凑表格</item>
    <item>长内容：先摘要，再用 &lt;details&gt; 折叠次要信息</item>
  </layout>
  <visual>
    <item>vivid 档位允许大胆渐变、强对比、玻璃感、彩色徽章和节点式流程，但所有视觉块都必须服务于信息表达并保持可读性</item>
  </visual>
</output_format>""";

const String _fallbackPlainText =
    '<output_format mode="plain-text">\n'
    '  <rule>纯文本输出，禁止任何 Markdown / HTML / 代码围栏</rule>\n'
    '  <rule>段落用空行分隔，代码用四空格缩进</rule>\n'
    '  <rule>保持高信息密度与紧凑行文</rule>\n'
    '</output_format>';

const String _fallbackGptChatRules =
    '<chat_rules model="gpt">\n'
    '  <anti-habit>禁止机械性开头总结与"下一步推荐"模板化回复；禁止散乱罗列；禁止无脑垂直长清单；禁止代码话题中不假思索堆代码块</anti-habit>\n'
    '  <require>积极使用 &lt;table&gt;/&lt;details&gt;/Flexbox 卡片提升信息密度；回复架构必须经过设计</require>\n'
    '</chat_rules>';
