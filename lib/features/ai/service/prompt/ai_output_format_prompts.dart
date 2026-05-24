// 2026-05-24 — 输出格式控制 Prompt 片段的运行时缓存。
//
// 真正的可维护内容存放在 [assets/prompts/_shared/output_format_html.md] 与
// [assets/prompts/_shared/output_format_plaintext.md]。本类负责在 app boot
// 阶段把它们一次性加载进进程内常量，供 [AiPromptBuilder] 同步读取。
//
// 加载失败时会回退到内置的最小兜底文本，保证非 Markdown 模式仍能向模型
// 传递基本格式约束（与 [programming_expert_prompts.dart] 同一模式）。

import 'package:flutter/services.dart';

import '../../../../app/support/silent_log.dart';

class AiOutputFormatPrompts {
  AiOutputFormatPrompts._();

  static const String htmlAssetPath =
      'assets/prompts/_shared/output_format_html.md';
  static const String plainTextAssetPath =
      'assets/prompts/_shared/output_format_plaintext.md';
  static const String gptChatRulesAssetPath =
      'assets/prompts/_shared/output_format_gpt_chat_rules.md';

  static String _html = _fallbackHtml;
  static String _plainText = _fallbackPlainText;
  static String _gptChatRules = _fallbackGptChatRules;
  static bool _loaded = false;
  static Future<void>? _loading;

  static String get html => _html;
  static String get plainText => _plainText;
  static String get gptChatRules => _gptChatRules;
  static bool get isLoaded => _loaded;

  static Future<void> ensureLoaded([AssetBundle? bundle]) {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load(bundle ?? rootBundle).whenComplete(() {
      _loading = null;
    });
  }

  static Future<void> _load(AssetBundle bundle) async {
    try {
      final results = await Future.wait<String>(<Future<String>>[
        bundle.loadString(htmlAssetPath),
        bundle.loadString(plainTextAssetPath),
        bundle.loadString(gptChatRulesAssetPath),
      ]);
      final loadedHtml = results[0].trim();
      final loadedPlain = results[1].trim();
      final loadedGpt = results[2].trim();
      if (loadedHtml.isNotEmpty) _html = loadedHtml;
      if (loadedPlain.isNotEmpty) _plainText = loadedPlain;
      if (loadedGpt.isNotEmpty) _gptChatRules = loadedGpt;
      _loaded = true;
    } catch (error, stack) {
      silentLog('AiOutputFormatPrompts', 'load', error, stack);
    }
  }
}

const String _fallbackHtml =
    '<output_format mode="html">\n'
    '  <directive>本轮回复必须是一段自包含 HTML 片段。禁止任何 Markdown 语法。</directive>\n'
    '  <forbid-markdown>禁止 #、**、*、`、```、-、+、1.、&gt; 等所有 Markdown 标记</forbid-markdown>\n'
    '  <required-tags>标题用 &lt;h2&gt;/&lt;h3&gt;；段落 &lt;p&gt;；列表 &lt;ul&gt;/&lt;ol&gt;/&lt;li&gt;；代码 &lt;pre&gt;&lt;code&gt;；表格 &lt;table&gt;；折叠 &lt;details&gt;</required-tags>\n'
    '  <style-rules>仅允许内联 style；禁止 &lt;style&gt;/class/外链 CSS</style-rules>\n'
    '  <boundary>禁止 &lt;!DOCTYPE&gt;/&lt;html&gt;/&lt;head&gt;/&lt;body&gt; 整页骨架；禁止 &lt;script&gt;/&lt;iframe&gt;</boundary>\n'
    '</output_format>';

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
