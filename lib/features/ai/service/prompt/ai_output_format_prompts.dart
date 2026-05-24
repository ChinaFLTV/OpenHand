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

  static String _html = _fallbackHtml;
  static String _plainText = _fallbackPlainText;
  static bool _loaded = false;
  static Future<void>? _loading;

  static String get html => _html;
  static String get plainText => _plainText;
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
      ]);
      final loadedHtml = results[0].trim();
      final loadedPlain = results[1].trim();
      if (loadedHtml.isNotEmpty) _html = loadedHtml;
      if (loadedPlain.isNotEmpty) _plainText = loadedPlain;
      _loaded = true;
    } catch (error, stack) {
      silentLog('AiOutputFormatPrompts', 'load', error, stack);
    }
  }
}

const String _fallbackHtml =
    '<output_format mode="html">\n'
    '  <rule>标题从 ## 起；保持紧凑结构化；信息密度高</rule>\n'
    '  <rule>仅允许内联 style 属性，禁止 &lt;style&gt;/class/伪类</rule>\n'
    '  <rule>仅输出片段（div / span / details / table 等），禁止整页骨架</rule>\n'
    '  <rule>图形限于：流程图、架构图、状态机、对比矩阵、数据图表</rule>\n'
    '</output_format>';

const String _fallbackPlainText =
    '<output_format mode="plain-text">\n'
    '  <rule>纯文本输出，禁止任何 Markdown / HTML / 代码围栏</rule>\n'
    '  <rule>段落用空行分隔，代码用四空格缩进</rule>\n'
    '  <rule>保持高信息密度与紧凑行文</rule>\n'
    '</output_format>';
