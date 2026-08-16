import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight.dart' as highlight;
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../app/model/openhand_shortcut.dart';
import '../../../app/state/settings_controller.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_expandable.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/error_snackbar.dart';
import '../../../shared/ui/interaction_timings.dart';
import '../../../shared/ui/markdown_ast_sanitizer.dart';
import '../../../shared/ui/markdown_math.dart';
import '../../../shared/ui/markdown_surface_tones.dart';
import '../../../shared/ui/model_search_selector.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_animated_title_text.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_console_log_panel.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_file_hover_popup.dart';
import '../../../shared/ui/openhand_inline_empty_state.dart';
import '../../../shared/ui/openhand_metadata_tiles.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_sweep_shimmer.dart';
import '../../../shared/ui/openhand_tap_region.dart';
import '../../../shared/ui/openhand_trailing_toolbar.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/ui/spring_entrance.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/structured_text_format.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/text_normalization.dart';
import '../../../shared/util/timer_safety.dart';
import '../../../shared/util/unified_diff.dart' show unifiedDiffLinesFromText;
import '../../ai/index.dart';
import '../../home/index.dart';
import '../model/harness_phase.dart';
import '../model/harness_role_config.dart';
import '../model/harness_session_config.dart';
import '../service/harness_cli_catalog.dart';
import '../service/harness_orchestrator.dart';
import 'harness_pending_replay_badge.dart';
part 'harness_session_dashboard.header.part.dart';
part 'harness_session_dashboard.phase_card.part.dart';
part 'harness_session_dashboard.log_views.part.dart';
part 'harness_session_dashboard.streaming.part.dart';
part 'harness_session_dashboard.tool_trace.part.dart';
part 'harness_session_dashboard.segment_body.part.dart';
part 'harness_session_dashboard.markdown.part.dart';
part 'harness_session_dashboard.composer.part.dart';
part 'harness_session_dashboard.model_dropdown.part.dart';
part 'harness_session_dashboard.changed_files.part.dart';
part 'harness_session_dashboard.streaming_smart.part.dart';
part 'harness_session_dashboard.file_hover.part.dart';
part 'harness_session_dashboard.steering.part.dart';


// 预编译日志级别前缀正则，避免重复创建。
final RegExp _logLevelPattern = RegExp(
  r'\b(ERROR|ERR|WARN|WARNING|INFO|DEBUG|TRACE)\b',
  caseSensitive: false,
);

// 匹配由横线、等号或下划线组成的终端分隔行。
final RegExp _heSeparatorLinePattern = RegExp(r'^[-=_]{3,}$');

// 匹配模型重复嵌入到文本中的工具调用 XML。
final RegExp _heInlineToolCallsXmlPattern = RegExp(
  r'<tool_calls>\s*[\s\S]*?</tool_calls>',
  multiLine: true,
);

// 匹配会被 Markdown 误判为标题的 Setext 下划线。
final RegExp _heSetextEscapePattern = RegExp(r'(^|\n)(\s*)(=+|\^+)(?=\n|$)');

/// 提取首条命令并将其余日志整理为可渲染的 Markdown。
({String? command, String body}) _heSplitLogForMarkdown(List<String> lines) {
  String? command;
  final out = <String>[];
  String? prev;

  for (final raw in lines) {
    final trimmed = raw.trim();

    // 状态装饰已由界面表达，无需重复渲染。
    if (trimmed.isNotEmpty &&
        (trimmed.startsWith('▶ ') ||
            trimmed.startsWith('✓ ') ||
            trimmed.startsWith('✗ ') ||
            trimmed.startsWith('⚠ '))) {
      continue;
    }

    if (command == null && raw.startsWith('> ')) {
      command = raw.substring(2);
      continue;
    }

    // 将终端分隔线转换为 Markdown 水平线。
    if (_heSeparatorLinePattern.hasMatch(trimmed)) {
      if (prev != null && out.isNotEmpty && out.last.isNotEmpty) out.add('');
      out.add('---');
      out.add('');
      prev = null;
      continue;
    }

    // 将 CLI 角色标记转换为段落分隔线。
    if (trimmed.length <= 12 &&
        const {
          'user',
          'codex',
          'assistant',
          'exec',
          'function',
          'tool',
        }.contains(trimmed.toLowerCase())) {
      if (prev != null && out.isNotEmpty && out.last.isNotEmpty) out.add('');
      out.add('---');
      out.add('');
      prev = null;
      continue;
    }

    out.add(raw);
    if (trimmed.isNotEmpty) prev = trimmed;
  }

  // 转义可能生成虚假标题的 Setext 标记。
  final joined = out
      .join('\n')
      .trim()
      .replaceAllMapped(
        _heSetextEscapePattern,
        (m) => '${m[1]}${m[2]}\\${m[3]}',
      );

  return (command: command, body: joined);
}

String _heAiModelConfigLabel(AiModelConfig config) {
  final label = config.providerLabel;
  final protocolLabel = config.protocolType.storageValue;
  return '$label ($protocolLabel)';
}

String _heHarnessPhaseLabel(BuildContext context, HarnessPhase phase) {
  return switch (phase) {
    HarnessPhase.metaCollection => openHandLocalizedText(
      context,
      zh: '元数据采集',
      zhHant: '元資料採集',
      en: 'Meta Collection',
      fr: 'Collecte des métadonnées',
      de: 'Metadaten-Erfassung',
      ja: 'メタデータ収集',
    ),
    HarnessPhase.reading => openHandLocalizedText(
      context,
      zh: '调查',
      zhHant: '調查',
      en: 'Reading',
      fr: 'Investigation',
      de: 'Analyse',
      ja: '調査',
    ),
    HarnessPhase.planning => openHandLocalizedText(
      context,
      zh: '规划',
      zhHant: '規劃',
      en: 'Planning',
      fr: 'Planification',
      de: 'Planung',
      ja: '計画',
    ),
    HarnessPhase.implementing => openHandLocalizedText(
      context,
      zh: '实施',
      zhHant: '實施',
      en: 'Implementing',
      fr: 'Implémentation',
      de: 'Umsetzung',
      ja: '実装',
    ),
    HarnessPhase.reviewing => openHandLocalizedText(
      context,
      zh: '验收',
      zhHant: '驗收',
      en: 'Reviewing',
      fr: 'Revue',
      de: 'Prüfung',
      ja: 'レビュー',
    ),
  };
}

String _heHarnessNotConfiguredText(BuildContext context) {
  return openHandNotConfiguredLabel(context);
}

String _heDescribeAiModelConfig(
  BuildContext context,
  List<AiModelConfig> settingsModels,
  String? configId, {
  String? urlModeModelId,
}) {
  final trimmedConfigId = configId?.trim() ?? '';
  if (trimmedConfigId.isEmpty) {
    return _heHarnessNotConfiguredText(context);
  }

  final matchedConfig = settingsModels
      .where((item) => item.id == trimmedConfigId)
      .firstOrNull;
  if (matchedConfig != null) {
    final effectiveModelId = urlModeModelId?.trim();
    if (effectiveModelId != null && effectiveModelId.isNotEmpty) {
      return '$effectiveModelId (${matchedConfig.providerLabel})';
    }
    return _heAiModelConfigLabel(matchedConfig);
  }

  return openHandLocalizedText(
    context,
    zh: '已删除配置 · $trimmedConfigId',
    zhHant: '已刪除設定 · $trimmedConfigId',
    en: 'Deleted config · $trimmedConfigId',
    fr: 'Configuration supprimée · $trimmedConfigId',
    de: 'Gelöschte Konfiguration · $trimmedConfigId',
    ja: '削除済み設定 · $trimmedConfigId',
  );
}

String? _hePreferredAiModelConfigId({
  required List<AiModelConfig> settingsModels,
  required String? configuredId,
  String? fallbackId,
}) {
  final trimmedConfiguredId = configuredId?.trim();
  if (trimmedConfiguredId != null &&
      trimmedConfiguredId.isNotEmpty &&
      settingsModels.any((item) => item.id == trimmedConfiguredId)) {
    return trimmedConfiguredId;
  }

  final trimmedFallbackId = fallbackId?.trim();
  if (trimmedFallbackId != null &&
      trimmedFallbackId.isNotEmpty &&
      settingsModels.any((item) => item.id == trimmedFallbackId)) {
    return trimmedFallbackId;
  }

  return settingsModels.isEmpty ? null : settingsModels.first.id;
}

/// Harness 输出片段类型。
enum _HeSegmentKind {
  command,
  assistant,
  thinking,
  toolCall,
  toolResult,
  output,
  userInput,
  handoff,
}

/// 已分类的 CLI 输出片段。
class _HeOutputSegment {
  _HeOutputSegment({required this.kind, this.roleLabel, List<String>? lines})
    : lines = lines ?? [];

  final _HeSegmentKind kind;
  final String? roleLabel;
  final List<String> lines;

  /// 返回适合 Markdown 渲染的片段正文。
  String get markdownBody {
    final out = <String>[];
    String? prev;
    for (final raw in lines) {
      final trimmed = raw.trim();
      if (_heSeparatorLinePattern.hasMatch(trimmed)) {
        if (prev != null && out.isNotEmpty && out.last.isNotEmpty) out.add('');
        out.add('---');
        out.add('');
        prev = null;
        continue;
      }
      out.add(raw);
      if (trimmed.isNotEmpty) prev = trimmed;
    }
    final joined = out
        .join('\n')
        .trim()
        .replaceAllMapped(
          _heSetextEscapePattern,
          (m) => '${m[1]}${m[2]}\\${m[3]}',
        );
    return joined;
  }

  bool get isEmpty => lines.every((l) => l.trim().isEmpty);
}

String _heSegmentWidgetKey(_HeOutputSegment segment, int index) {
  final firstNonEmpty = segment.lines.firstWhere(
    (line) => line.trim().isNotEmpty,
    orElse: () => '',
  );
  return [
    index,
    segment.kind.name,
    segment.roleLabel ?? '',
    firstNonEmpty.hashCode,
  ].join('|');
}

/// 表示新会话轮次的 CLI 角色标记。
const Set<String> _heRoleMarkers = {
  'user',
  'codex',
  'thinking',
  'assistant',
  'exec',
  'function',
  'tool',
};

/// 将 CLI 角色标记映射为输出类型。
_HeSegmentKind _kindFromRoleMarker(String marker) => switch (marker) {
  'assistant' => _HeSegmentKind.assistant,
  'codex' => _HeSegmentKind.thinking,
  'thinking' => _HeSegmentKind.thinking,
  'exec' => _HeSegmentKind.toolCall,
  'function' => _HeSegmentKind.toolCall,
  'tool' => _HeSegmentKind.toolResult,
  'user' => _HeSegmentKind.output,
  _ => _HeSegmentKind.output,
};

/// 将 CLI 输出解析为带类型的片段，并单独提取首条命令。
List<_HeOutputSegment> _heParseOutputSegments(List<String> rawLines) {
  final segments = <_HeOutputSegment>[];
  _HeOutputSegment? current;
  String? commandLine;

  // 匹配“【用户人工验收结果】”一类人工输入标题。
  final manualInputHeaderPattern = RegExp(r'^【用户人工.+】$');
  bool inUserInputSection = false;

  void flushCurrent() {
    if (current != null && !current!.isEmpty) {
      segments.add(current!);
    }
    current = null;
  }

  for (final raw in rawLines) {
    final trimmed = raw.trim();

    // 工具调用标记“⚙”保留给后续分支处理。
    if (trimmed.isNotEmpty &&
        (trimmed.startsWith('▶ ') ||
            trimmed.startsWith('✓ ') ||
            trimmed.startsWith('✗ ') ||
            trimmed.startsWith('⚠ '))) {
      continue;
    }

    // 解析 HarnessApiPhaseRunner 输出的工具调用标记。
    if (trimmed.startsWith('⚙ 工具调用：') || trimmed.startsWith('⚙ Tool call: ')) {
      flushCurrent();
      inUserInputSection = false;
      final toolName = trimmed.startsWith('⚙ 工具调用：')
          ? trimmed.substring('⚙ 工具调用：'.length).trim()
          : trimmed.substring('⚙ Tool call: '.length).trim();
      current = _HeOutputSegment(
        kind: _HeSegmentKind.toolCall,
        roleLabel: toolName.isEmpty ? 'Tool' : toolName,
      );
      continue;
    }

    if (manualInputHeaderPattern.hasMatch(trimmed)) {
      flushCurrent();
      current = _HeOutputSegment(
        kind: _HeSegmentKind.userInput,
        roleLabel: trimmed.substring(1, trimmed.length - 1),
      );
      inUserInputSection = true;
      continue;
    }

    // 确认行结束人工输入片段。
    if (inUserInputSection && trimmed.startsWith('ℹ ')) {
      flushCurrent();
      inUserInputSection = false;
      continue;
    }

    if (commandLine == null && raw.startsWith('> ')) {
      commandLine = raw.substring(2);
      if (inUserInputSection) {
        flushCurrent();
        inUserInputSection = false;
      }
      continue;
    }

    // 合并连续的交接文档行。
    if (trimmed.startsWith('📋 ')) {
      if (current?.kind != _HeSegmentKind.handoff) {
        flushCurrent();
        current = _HeOutputSegment(
          kind: _HeSegmentKind.handoff,
          roleLabel: '交接文档',
        );
      }
      current!.lines.add(raw);
      continue;
    }
    if (current?.kind == _HeSegmentKind.handoff &&
        trimmed.isNotEmpty &&
        !trimmed.startsWith('📋 ')) {
      flushCurrent();
    }

    if (trimmed.length <= 12 &&
        _heRoleMarkers.contains(trimmed.toLowerCase())) {
      flushCurrent();
      inUserInputSection = false;
      current = _HeOutputSegment(
        kind: _kindFromRoleMarker(trimmed.toLowerCase()),
        roleLabel: trimmed,
      );
      continue;
    }

    current ??= _HeOutputSegment(kind: _HeSegmentKind.output);
    current!.lines.add(raw);
  }

  flushCurrent();

  if (commandLine != null) {
    segments.insert(
      0,
      _HeOutputSegment(kind: _HeSegmentKind.command, lines: [commandLine]),
    );
  }

  // 识别文本形式的推理标记。
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    if (seg.kind == _HeSegmentKind.output ||
        seg.kind == _HeSegmentKind.assistant) {
      final firstNonEmpty = seg.lines.firstWhere(
        (l) => l.trim().isNotEmpty,
        orElse: () => '',
      );
      final fl = firstNonEmpty.trim().toLowerCase();
      if (fl.startsWith('<thinking>') ||
          fl.startsWith('<antthinking>') ||
          fl.startsWith('[thinking]') ||
          fl.contains('reasoning:') && fl.length < 30) {
        segments[i] = _HeOutputSegment(
          kind: _HeSegmentKind.thinking,
          roleLabel: seg.roleLabel,
          lines: seg.lines,
        );
      }
    }
  }

  // 删除与原生工具调用重复的文本 XML。
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    if (seg.kind == _HeSegmentKind.output ||
        seg.kind == _HeSegmentKind.assistant ||
        seg.kind == _HeSegmentKind.thinking) {
      final joined = seg.lines.join('\n');
      if (joined.contains('<tool_calls>')) {
        final stripped = joined
            .replaceAll(_heInlineToolCallsXmlPattern, '')
            .replaceAll(kExcessiveNewlinesPattern, '\n\n')
            .trim();
        if (stripped.isEmpty) {
          segments.removeAt(i);
          i--;
        } else {
          segments[i] = _HeOutputSegment(
            kind: seg.kind,
            roleLabel: seg.roleLabel,
            lines: stripped.split('\n'),
          );
        }
      }
    }
  }

  // 将唯一且内容充足的普通输出按助手回复展示。
  final nonCommandSegments = segments.where(
    (s) =>
        s.kind != _HeSegmentKind.command && s.kind != _HeSegmentKind.userInput,
  );
  if (nonCommandSegments.length == 1 &&
      nonCommandSegments.first.kind == _HeSegmentKind.output &&
      nonCommandSegments.first.lines.length > 5) {
    final idx = segments.indexOf(nonCommandSegments.first);
    segments[idx] = _HeOutputSegment(
      kind: _HeSegmentKind.assistant,
      roleLabel: nonCommandSegments.first.roleLabel,
      lines: nonCommandSegments.first.lines,
    );
  }

  return segments;
}

/// 构建适配 Harness 日志表面的 Markdown 样式。
MarkdownStyleSheet _heBuildMarkdownStyleSheet(
  ThemeData theme,
  ColorScheme colorScheme,
) {
  final textColor = colorScheme.onSurface;
  final accent = colorScheme.primary;
  final isDark = theme.brightness == Brightness.dark;
  final surface = colorScheme.surface;
  final codeBlockBg = Color.alphaBlend(
    (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
    surface,
  );
  final borderColor = colorScheme.outlineVariant.withValues(alpha: 0.5);
  final quoteBg = Color.alphaBlend(
    accent.withValues(alpha: isDark ? 0.20 : 0.08),
    surface,
  );

  final body = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    color: textColor,
    height: 1.65,
  );

  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    h1: (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      color: textColor,
      fontWeight: FontWeight.w800,
      height: 1.35,
    ),
    h2: (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: textColor,
      fontWeight: FontWeight.w700,
      height: 1.35,
    ),
    h3: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      color: textColor,
      fontWeight: FontWeight.w700,
      height: 1.35,
    ),
    h4: (theme.textTheme.titleSmall ?? const TextStyle()).copyWith(
      color: textColor,
      fontWeight: FontWeight.w600,
    ),
    code: TextStyle(
      fontFamily: kOpenHandMonospaceFontFamily,
      fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * 0.93,
      color: accent,
      backgroundColor: Colors.transparent,
    ),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: codeBlockBg,
      borderRadius: _br12,
      border: Border.all(color: borderColor),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    blockquoteDecoration: BoxDecoration(
      color: quoteBg,
      borderRadius: kOpenHandBorderRadius16,
      border: Border(left: BorderSide(color: accent, width: 3)),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: borderColor)),
    ),
    tableBorder: TableBorder.symmetric(
      inside: BorderSide(color: borderColor),
      outside: BorderSide(color: borderColor),
    ),
    tableCellsPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    tableHeadCellsPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    tableColumnWidth: const IntrinsicColumnWidth(),
    strong: body.copyWith(fontWeight: FontWeight.w700),
    em: body.copyWith(fontStyle: FontStyle.italic),
    listBullet: body.copyWith(color: accent, fontWeight: FontWeight.w700),
    listBulletPadding: const EdgeInsets.only(right: 8),
    a: body.copyWith(
      color: accent,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: accent.withValues(alpha: 0.6),
    ),
  );
}

// 与首页会话界面共用的圆角规格。
const _br26 = BorderRadius.all(Radius.circular(26));
const _br12 = kOpenHandBorderRadius12;
const _br10 = kOpenHandBorderRadius10;
const _br8 = kOpenHandBorderRadius8;
const _br6 = kOpenHandBorderRadius6;

/// 根据卡片实际背景构建 Markdown 配色，保证跨明暗主题的可读性。
MarkdownStyleSheet _heBuildDarkAwareMarkdownStyleSheet(
  ThemeData theme,
  ColorScheme colorScheme,
  Color cardBg,
  Color? explicitTextColor,
) {
  final tones = OpenHandMarkdownSurfaceTones.resolve(
    colorScheme: colorScheme,
    background: cardBg,
  );
  final bubbleIsDark = tones.isDark;
  final overlayBase = tones.overlayBase;
  final textColor =
      explicitTextColor ??
      (bubbleIsDark ? Colors.white : colorScheme.onSurface);
  final subtleSurface = tones.subtleSurface;
  final elevatedSurface = tones.elevatedSurface;
  final accentColor = tones.accent;
  final linkColor = tones.link;
  final borderColor = Color.alphaBlend(
    overlayBase.withValues(alpha: bubbleIsDark ? 0.18 : 0.12),
    cardBg,
  );
  final quoteSurface = Color.alphaBlend(
    accentColor.withValues(alpha: bubbleIsDark ? 0.22 : 0.10),
    elevatedSurface,
  );
  final secondaryTextColor = textColor.withValues(
    alpha: bubbleIsDark ? 0.92 : 0.88,
  );

  final body = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    color: textColor,
    height: 1.65,
  );

  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    h1: (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      color: textColor,
      fontWeight: FontWeight.w800,
      height: 1.35,
    ),
    h2: (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      color: textColor,
      fontWeight: FontWeight.w700,
      height: 1.35,
    ),
    h3: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      color: textColor,
      fontWeight: FontWeight.w700,
      height: 1.35,
    ),
    h4: (theme.textTheme.titleSmall ?? const TextStyle()).copyWith(
      color: textColor,
      fontWeight: FontWeight.w600,
    ),
    code: TextStyle(
      fontFamily: kOpenHandMonospaceFontFamily,
      fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * 0.93,
      color: textColor,
      backgroundColor: Colors.transparent,
    ),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: bubbleIsDark
          ? Colors.white.withValues(alpha: 0.08)
          : subtleSurface,
      borderRadius: _br12,
      border: Border.all(color: borderColor),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    blockquoteDecoration: BoxDecoration(
      color: quoteSurface,
      borderRadius: kOpenHandBorderRadius16,
      border: Border(left: BorderSide(color: accentColor, width: 3)),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: borderColor)),
    ),
    tableBorder: TableBorder.symmetric(
      inside: BorderSide(color: borderColor),
      outside: BorderSide(color: borderColor),
    ),
    tableCellsPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    tableCellsDecoration: BoxDecoration(color: subtleSurface),
    tableHeadCellsPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    tableHeadCellsDecoration: BoxDecoration(color: elevatedSurface),
    tableColumnWidth: const IntrinsicColumnWidth(),
    strong: body.copyWith(fontWeight: FontWeight.w700),
    em: body.copyWith(fontStyle: FontStyle.italic),
    blockquote: body.copyWith(color: secondaryTextColor),
    listBullet: body.copyWith(
      color: secondaryTextColor,
      fontWeight: FontWeight.w700,
    ),
    listBulletPadding: const EdgeInsets.only(right: 8),
    a: body.copyWith(
      color: linkColor,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: linkColor.withValues(alpha: 0.6),
    ),
  );
}

const Color _hePendingTone = kHarnessStatusIdleTone;
const Color _heRunningTone = kHarnessStatusRunningTone;
const Color _heCompletedTone = kHarnessStatusCompletedTone;
const Color _hePausedTone = kHarnessStatusCancelledTone;
const Color _heFailedTone = kHarnessStatusFailedTone;

({Color tone, Color background, Color border, Color text}) _hePhasePalette(
  ThemeData theme,
  ColorScheme colorScheme,
  HarnessPhaseStatus status, {
  bool reviewVerdictFail = false,
}) {
  final tone = switch (status) {
    HarnessPhaseStatus.pending || HarnessPhaseStatus.skipped => _hePendingTone,
    HarnessPhaseStatus.paused || HarnessPhaseStatus.cancelled => _hePausedTone,
    HarnessPhaseStatus.running => _heRunningTone,
    HarnessPhaseStatus.completed =>
      reviewVerdictFail ? _heFailedTone : _heCompletedTone,
    HarnessPhaseStatus.failed => _heFailedTone,
  };
  final backgroundAlpha = switch (status) {
    HarnessPhaseStatus.pending || HarnessPhaseStatus.skipped =>
      theme.brightness == Brightness.dark ? 0.18 : 0.08,
    HarnessPhaseStatus.paused || HarnessPhaseStatus.cancelled =>
      theme.brightness == Brightness.dark ? 0.26 : 0.13,
    HarnessPhaseStatus.running =>
      theme.brightness == Brightness.dark ? 0.28 : 0.14,
    HarnessPhaseStatus.completed =>
      theme.brightness == Brightness.dark ? 0.30 : 0.15,
    HarnessPhaseStatus.failed =>
      theme.brightness == Brightness.dark ? 0.24 : 0.12,
  };
  return (
    tone: tone,
    background: Color.alphaBlend(
      tone.withValues(alpha: backgroundAlpha),
      colorScheme.surface,
    ),
    border: tone.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.58 : 0.30,
    ),
    text:
        Color.lerp(
          tone,
          colorScheme.onSurface,
          theme.brightness == Brightness.dark ? 0.10 : 0.16,
        ) ??
        tone,
  );
}

/// Harness 会话面板控制器。
class HarnessSessionPaneController {
  _HarnessSessionPaneState? _state;

  void _attach(_HarnessSessionPaneState state) {
    _state = state;
  }

  void _detach(_HarnessSessionPaneState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  Future<bool> invokeShortcut(OpenHandShortcutAction action) async {
    return await _state?._handleShortcutAction(action) ?? false;
  }

  bool shouldAllowEditableShortcut(OpenHandShortcutAction action) {
    return _state?._shouldAllowEditableShortcut(action) ?? false;
  }
}

class _HeManualPhaseCopy {
  const _HeManualPhaseCopy({
    required this.actionLabel,
    required this.switchBackLabel,
    required this.title,
    required this.helperText,
    required this.hintText,
    required this.emptyMessage,
    required this.activeBannerText,
    required this.queuedBannerText,
    required this.icon,
  });

  final String actionLabel;
  final String switchBackLabel;
  final String title;
  final String helperText;
  final String hintText;
  final String emptyMessage;
  final String activeBannerText;
  final String queuedBannerText;
  final IconData icon;
}

class HarnessSessionPane extends StatefulWidget {
  const HarnessSessionPane({
    super.key,
    required this.config,
    required this.orchestrator,
    required this.isZh,
    required this.onRestart,
    required this.fullAccessPermission,
    required this.onToggleFullAccessPermission,
    required this.onConfigChanged,
    this.sessionTitle,
    this.updatedAtLabel,
    this.sessionId,
    this.createdAtLabel,
    this.sessionCreatedAt,
    this.sessionUpdatedAt,
    this.controller,
    this.filePathRoots = const [],
    this.replayPendingDeadlineListenable,
    this.onCancelPendingReplay,
  });

  final HarnessSessionConfig config;
  final HarnessOrchestrator orchestrator;
  final bool isZh;

  /// 会话标题。
  final String? sessionTitle;

  /// 元数据弹窗使用的预格式化更新时间。
  final String? updatedAtLabel;

  /// 元数据弹窗使用的会话标识。
  final String? sessionId;

  /// 元数据弹窗使用的预格式化创建时间。
  final String? createdAtLabel;

  final DateTime? sessionCreatedAt;
  final DateTime? sessionUpdatedAt;

  /// 重启已停止的会话。
  final VoidCallback onRestart;

  /// 是否允许自动推进。
  final bool fullAccessPermission;

  /// 切换自动推进权限。
  final ValueChanged<bool> onToggleFullAccessPermission;

  /// 更新待执行阶段的 CLI 或模型配置。
  final ValueChanged<HarnessSessionConfig> onConfigChanged;

  final HarnessSessionPaneController? controller;

  /// 消息文件路径的候选根目录。
  final List<String> filePathRoots;

  /// 可选的 ToolSearch 重放反悔窗口 deadline。传入后，会在会话
  /// header 右侧出现一个「撤销 Ns」倒计时 chip。顶层从
  /// `ToolSearchReplayDispatcher.pendingDeadlineListenable` 取。
  final ValueListenable<DateTime?>? replayPendingDeadlineListenable;

  /// 点击「撤销 Ns」chip 时回调，通常接到
  /// [ToolSearchReplayDispatcher.cancel] 立即取消重放。
  final VoidCallback? onCancelPendingReplay;

  @override
  State<HarnessSessionPane> createState() => _HarnessSessionPaneState();
}

class _HarnessSessionPaneState extends State<HarnessSessionPane> {
  final ScrollController _feedController = ScrollController();
  final TextEditingController _manualPhaseController = TextEditingController();
  final FocusNode _manualPhaseFocusNode = FocusNode();

  /// 阶段展开偏好；未记录时自动决定。
  final Map<HarnessPhaseLog, bool> _expandedOverrides = {};
  bool _composerCollapsed = false;
  bool _autoFollowEnabled = true;
  bool _shouldAutoFollowFeed = true;
  bool _manualPhaseSubmitting = false;
  bool _lastAwaitingManualPhaseInput = false;

  /// 当前选中的阶段日志。
  HarnessPhaseLog? _selectedPhaseLog;

  /// 避免同一帧重复注册滚动回调。
  bool _scrollCallbackQueued = false;

  bool _queuedForcedFeedScrollToBottom = false;
  bool _pendingAnimatedFeedScrollToBottom = false;
  final AutoFollowProgrammaticScrollWindow _feedProgrammaticScrollWindow =
      AutoFollowProgrammaticScrollWindow();
  bool _userFeedScrollInProgress = false;
  final Stopwatch _feedScrollActivityStopwatch = Stopwatch()..start();
  Duration? _lastFeedPointerSignalScrollAt;
  // 慢速滚动期间每个 pointer-signal tick 都包成 start→update→end，
  // 中途 _userFeedScrollInProgress=false 会让 layout-change / 流式 feed
  // 触发的 jumpTo 抢到一帧，造成视口抽搐。给 scroll-end 加 220 ms 宽限，
  // 期间任何新的滚动活动都续期。
  Timer? _userFeedScrollGraceTimer;
  static const Duration _userFeedScrollEndGraceDuration = Duration(
    milliseconds: 220,
  );

  /// 动态高度稳定前需要继续执行的滚动帧数。
  int _scrollSettlePasses = 0;

  static const double _feedAutoFollowDistanceThreshold = 36;
  static const double _feedAutoFollowAnimatedDistanceThreshold = 80;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _manualPhaseFocusNode.onKeyEvent = _handleManualPhaseFocusNodeKeyEvent;
    _manualPhaseController.addListener(_onManualPhaseDraftChanged);
    _feedController.addListener(_handleFeedScroll);
    widget.orchestrator.addListener(_onOrchestratorUpdated);
    _lastAwaitingManualPhaseInput =
        widget.orchestrator.awaitingManualPhaseInput;
    if (_lastAwaitingManualPhaseInput) {
      _seedManualPhaseDraftFromQueuedInput();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.orchestrator.awaitingManualPhaseInput) {
          return;
        }
        _manualPhaseFocusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(HarnessSessionPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (!identical(oldWidget.orchestrator, widget.orchestrator)) {
      oldWidget.orchestrator.removeListener(_onOrchestratorUpdated);
      widget.orchestrator.addListener(_onOrchestratorUpdated);
      _expandedOverrides.clear();
      _lastAwaitingManualPhaseInput =
          widget.orchestrator.awaitingManualPhaseInput;
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    widget.orchestrator.removeListener(_onOrchestratorUpdated);
    _manualPhaseController.removeListener(_onManualPhaseDraftChanged);
    _manualPhaseController.dispose();
    _manualPhaseFocusNode.dispose();
    _feedController.removeListener(_handleFeedScroll);
    _feedController.dispose();
    _userFeedScrollGraceTimer?.cancel();
    _userFeedScrollGraceTimer = null;
    super.dispose();
  }

  void _onManualPhaseDraftChanged() {
    if (!mounted || !widget.orchestrator.awaitingManualPhaseInput) {
      return;
    }
    setState(() {});
  }

  void _seedManualPhaseDraftFromQueuedInput({bool overrideExisting = false}) {
    final awaitingPhase = widget.orchestrator.awaitingManualPhaseInputPhase;
    if (awaitingPhase == null ||
        !widget.orchestrator.hasQueuedManualPhaseInputFor(awaitingPhase)) {
      return;
    }
    final queued = widget.orchestrator.queuedManualPhaseInput?.trim();
    if (queued == null || queued.isEmpty) {
      return;
    }
    if (!overrideExisting && _manualPhaseController.text.trim().isNotEmpty) {
      return;
    }
    _manualPhaseController.value = TextEditingValue(
      text: queued,
      selection: TextSelection.collapsed(offset: queued.length),
    );
  }

  void _onOrchestratorUpdated() {
    if (!mounted) return;
    final awaitingManualPhaseInput =
        widget.orchestrator.awaitingManualPhaseInput;
    final shouldExpandComposer =
        awaitingManualPhaseInput &&
        !_lastAwaitingManualPhaseInput &&
        _composerCollapsed;
    final shouldFocusManualPhaseInput =
        awaitingManualPhaseInput && !_lastAwaitingManualPhaseInput;
    final shouldSeedManualPhaseDraft =
        awaitingManualPhaseInput &&
        (!_lastAwaitingManualPhaseInput ||
            _manualPhaseController.text.trim().isEmpty);
    final shouldClearManualPhaseDraft =
        !awaitingManualPhaseInput &&
        !widget.orchestrator.hasQueuedManualPhaseInput &&
        _manualPhaseController.text.isNotEmpty;

    setState(() {
      if (shouldExpandComposer) {
        _composerCollapsed = false;
      }
      if (!awaitingManualPhaseInput && _manualPhaseSubmitting) {
        _manualPhaseSubmitting = false;
      }
    });

    _lastAwaitingManualPhaseInput = awaitingManualPhaseInput;

    if (shouldSeedManualPhaseDraft) {
      _seedManualPhaseDraftFromQueuedInput();
    }

    if (shouldClearManualPhaseDraft) {
      _manualPhaseController.clear();
    }
    if (shouldFocusManualPhaseInput) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.orchestrator.awaitingManualPhaseInput) {
          return;
        }
        _manualPhaseFocusNode.requestFocus();
      });
    }
    _scheduleFeedAutoScroll();
  }

  bool get _isRunning =>
      widget.orchestrator.status == HarnessOrchestratorStatus.running;

  bool get _isDone =>
      widget.orchestrator.status != HarnessOrchestratorStatus.idle &&
      widget.orchestrator.status != HarnessOrchestratorStatus.running;

  bool get _canRetryFailedRun =>
      widget.orchestrator.status == HarnessOrchestratorStatus.failed;

  bool _isPhaseConfigEditable(HarnessPhaseLog log) {
    return switch (log.status) {
      HarnessPhaseStatus.pending ||
      HarnessPhaseStatus.paused ||
      HarnessPhaseStatus.failed ||
      HarnessPhaseStatus.skipped => true,
      HarnessPhaseStatus.running ||
      HarnessPhaseStatus.completed ||
      HarnessPhaseStatus.cancelled => false,
    };
  }

  HarnessPhase? get _awaitingManualPhase =>
      widget.orchestrator.awaitingManualPhaseInputPhase;

  bool get _isAwaitingManualPhaseInput => _awaitingManualPhase != null;

  bool get _canSubmitManualPhase =>
      !_manualPhaseSubmitting && _manualPhaseController.text.trim().isNotEmpty;

  HarnessPhase get _effectiveManualPhase =>
      _awaitingManualPhase ?? HarnessPhase.reviewing;

  _HeManualPhaseCopy _manualPhaseCopy(
    BuildContext context,
    HarnessPhase phase,
  ) {
    return switch (phase) {
      HarnessPhase.metaCollection => _HeManualPhaseCopy(
        actionLabel: openHandLocalizedText(
          context,
          zh: '我来研究',
          zhHant: '我來研究',
          en: 'I Will Research',
          fr: 'Je recherche',
          de: 'Ich recherchiere',
          ja: '自分で調査',
        ),
        switchBackLabel: openHandLocalizedText(
          context,
          zh: '改用 AI 研究',
          zhHant: '改用 AI 研究',
          en: 'Use AI Research',
          fr: 'Utiliser la recherche IA',
          de: 'KI-Recherche nutzen',
          ja: 'AI 調査に切り替え',
        ),
        title: openHandLocalizedText(
          context,
          zh: '人工研究结果',
          zhHant: '人工研究結果',
          en: 'Manual Research Notes',
          fr: 'Notes de recherche manuelle',
          de: 'Manuelle Recherche Notizen',
          ja: '手動調査メモ',
        ),
        helperText: openHandLocalizedText(
          context,
          zh: '请填写你亲自研究得到的项目结构、模块职责、依赖、约定或其他关键观察。发送后，AI 会整理为 architecture.md 与 conventions.md。',
          zhHant:
              '請填寫你親自研究得到的專案結構、模組職責、依賴、慣例或其他關鍵觀察。傳送後，AI 會整理為 architecture.md 與 conventions.md。',
          en: 'Enter the structure, module responsibilities, dependencies, conventions, or key observations you researched. AI will refine them into architecture.md and conventions.md.',
          fr: 'Saisissez la structure, les responsabilités, dépendances, conventions ou observations clés. L’IA les affinera dans architecture.md et conventions.md.',
          de: 'Erfasse Struktur, Modulzuständigkeiten, Abhängigkeiten, Konventionen oder wichtige Beobachtungen. Die KI verfeinert sie zu architecture.md und conventions.md.',
          ja: '調査した構成、モジュール責務、依存関係、規約、重要な観察を入力してください。AI が architecture.md と conventions.md に整理します。',
        ),
        hintText: openHandLocalizedText(
          context,
          zh: '例如：核心入口在 lib/main.dart；状态管理集中在 app/state；构建依赖 Flutter + Provider。',
          zhHant:
              '例如：核心入口在 lib/main.dart；狀態管理集中在 app/state；建置依賴 Flutter + Provider。',
          en: 'Example: main entry is lib/main.dart; state lives under app/state; build uses Flutter + Provider.',
          fr: 'Exemple : entrée principale dans lib/main.dart ; état dans app/state ; build Flutter + Provider.',
          de: 'Beispiel: Einstieg in lib/main.dart; State unter app/state; Build mit Flutter + Provider.',
          ja: '例：主入口は lib/main.dart、状態管理は app/state、ビルドは Flutter + Provider。',
        ),
        emptyMessage: openHandLocalizedText(
          context,
          zh: '请先填写研究结果，再发送给 AI 整理。',
          zhHant: '請先填寫研究結果，再傳送給 AI 整理。',
          en: 'Enter your research notes before sending them for AI refinement.',
          fr: 'Saisissez vos notes avant de les envoyer à l’IA.',
          de: 'Gib zuerst deine Recherche ein, bevor die KI sie verfeinert.',
          ja: 'AI に整理させる前に調査メモを入力してください。',
        ),
        activeBannerText: openHandLocalizedText(
          context,
          zh: '已切换为人工研究。请填写研究资料后点击发送，AI 会整理为规范文档。',
          zhHant: '已切換為人工研究。請填寫研究資料後點擊傳送，AI 會整理為規範文件。',
          en: 'Manual research is active. Send your notes and AI will refine them into the required documents.',
          fr: 'La recherche manuelle est active. Envoyez vos notes pour que l’IA les structure.',
          de: 'Manuelle Recherche ist aktiv. Sende deine Notizen, damit die KI sie strukturiert.',
          ja: '手動調査が有効です。メモを送信すると AI が必要な文書に整理します。',
        ),
        queuedBannerText: openHandLocalizedText(
          context,
          zh: '已保留上一份人工研究结果。点击“继续”会复用它；如需修改，请再次点击“我来研究”。',
          zhHant: '已保留上一份人工研究結果。點擊「繼續」會重用；如需修改，請再次點擊「我來研究」。',
          en: 'Previous manual research notes are queued. Continue to reuse them, or choose "I Will Research" again to revise.',
          fr: 'Les notes précédentes sont en file. Continuez pour les réutiliser, ou choisissez de rechercher à nouveau.',
          de: 'Vorherige Notizen sind vorgemerkt. Fortfahren nutzt sie erneut; wähle erneut manuelle Recherche zum Ändern.',
          ja: '前回の手動調査メモが残っています。続行で再利用し、変更する場合は再度選択してください。',
        ),
        icon: Icons.search_rounded,
      ),
      HarnessPhase.planning => _HeManualPhaseCopy(
        actionLabel: openHandLocalizedText(
          context,
          zh: '我来制定计划',
          zhHant: '我來制定計畫',
          en: 'I Will Plan',
          fr: 'Je planifie',
          de: 'Ich plane',
          ja: '自分で計画',
        ),
        switchBackLabel: openHandLocalizedText(
          context,
          zh: '改用 AI 规划',
          zhHant: '改用 AI 規劃',
          en: 'Use AI Planning',
          fr: 'Utiliser la planification IA',
          de: 'KI-Planung nutzen',
          ja: 'AI 計画に切り替え',
        ),
        title: openHandLocalizedText(
          context,
          zh: '人工计划草案',
          zhHant: '人工计划草案',
          en: 'Manual Plan Draft',
          fr: 'Brouillon de plan manuel',
          de: 'Manueller Planentwurf',
          ja: '手動計画ドラフト',
        ),
        helperText: openHandLocalizedText(
          context,
          zh: '请填写你制定的执行计划草案。发送后，AI 会补足步骤、文件指向、验收标准和复杂度标签。',
          zhHant: '請填寫你制定的執行計畫草案。傳送後，AI 會補足步驟、檔案指向、驗收標準和複雜度標籤。',
          en: 'Enter your execution plan draft. AI will refine steps, file targets, acceptance criteria, and complexity labels.',
          fr: 'Saisissez votre plan. L’IA affinera les étapes, fichiers, critères d’acceptation et labels de complexité.',
          de: 'Erfasse deinen Planentwurf. Die KI ergänzt Schritte, Dateien, Akzeptanzkriterien und Komplexitätslabels.',
          ja: '実行計画ドラフトを入力してください。AI が手順、対象ファイル、受け入れ基準、複雑度ラベルを補います。',
        ),
        hintText: openHandLocalizedText(
          context,
          zh: '例如：1. 修改 lib/foo.dart 修复状态同步 [medium]；验收：切换页面后数据一致。',
          zhHant: '例如：1. 修改 lib/foo.dart 修復狀態同步 [medium]；驗收：切換頁面後資料一致。',
          en: 'Example: 1. Update lib/foo.dart to fix state sync [medium]; acceptance: data stays consistent after navigation.',
          fr: 'Exemple : 1. Modifier lib/foo.dart pour corriger la synchro [medium] ; acceptation : données cohérentes après navigation.',
          de: 'Beispiel: 1. lib/foo.dart für State-Sync ändern [medium]; Abnahme: Daten bleiben nach Navigation konsistent.',
          ja: '例：1. lib/foo.dart で状態同期を修正 [medium]；受け入れ：画面遷移後もデータが一致。',
        ),
        emptyMessage: openHandLocalizedText(
          context,
          zh: '请先填写计划草案，再发送给 AI 润色。',
          zhHant: '請先填寫計畫草案，再傳送給 AI 潤色。',
          en: 'Enter your plan draft before sending it for AI refinement.',
          fr: 'Saisissez le brouillon avant de l’envoyer à l’IA.',
          de: 'Gib zuerst deinen Planentwurf ein, bevor die KI ihn verfeinert.',
          ja: 'AI に整理させる前に計画ドラフトを入力してください。',
        ),
        activeBannerText: openHandLocalizedText(
          context,
          zh: '已切换为人工规划。请填写计划草案后点击发送，AI 会整理为规范计划文档。',
          zhHant: '已切換為人工規劃。請填寫計畫草案後點擊傳送，AI 會整理為規範計畫文件。',
          en: 'Manual planning is active. Send your draft and AI will refine it into the required plan document.',
          fr: 'La planification manuelle est active. Envoyez le brouillon pour que l’IA le structure.',
          de: 'Manuelle Planung ist aktiv. Sende den Entwurf, damit die KI ihn strukturiert.',
          ja: '手動計画が有効です。ドラフトを送信すると AI が必要な計画文書に整理します。',
        ),
        queuedBannerText: openHandLocalizedText(
          context,
          zh: '已保留上一份人工计划草案。点击“继续”会复用它；如需修改，请再次点击“我来制定计划”。',
          zhHant: '已保留上一份人工计划草案。點擊「繼續」會重用；如需修改，請再次點擊「我來制定計畫」。',
          en: 'Previous manual plan draft is queued. Continue to reuse it, or choose "I Will Plan" again to revise.',
          fr: 'Le plan précédent est en file. Continuez pour le réutiliser, ou planifiez à nouveau pour le modifier.',
          de: 'Der vorherige Plan ist vorgemerkt. Fortfahren nutzt ihn erneut; wähle erneut manuelle Planung zum Ändern.',
          ja: '前回の手動計画が残っています。続行で再利用し、変更する場合は再度選択してください。',
        ),
        icon: Icons.route_rounded,
      ),
      HarnessPhase.reviewing => _HeManualPhaseCopy(
        actionLabel: openHandLocalizedText(
          context,
          zh: '我来验收',
          zhHant: '我來驗收',
          en: 'I Will Review',
          fr: 'Je valide',
          de: 'Ich prüfe',
          ja: '自分でレビュー',
        ),
        switchBackLabel: openHandLocalizedText(
          context,
          zh: '改用 AI 验收',
          zhHant: '改用 AI 驗收',
          en: 'Use AI Review',
          fr: 'Utiliser la revue IA',
          de: 'KI-Prüfung nutzen',
          ja: 'AI レビューに切り替え',
        ),
        title: openHandLocalizedText(
          context,
          zh: '人工验收结果',
          zhHant: '人工驗收結果',
          en: 'Manual Acceptance Result',
          fr: 'Résultat de validation manuelle',
          de: 'Manuelles Prüfergebnis',
          ja: '手動レビュー結果',
        ),
        helperText: openHandLocalizedText(
          context,
          zh: '请填写基于资产、页面、交互或真实结果得到的验收结论，然后点击“验收通过”或“验收不通过”。',
          zhHant: '請填寫基於資產、頁面、互動或真實結果得到的驗收結論，然後點擊「驗收通過」或「驗收不通過」。',
          en: 'Enter the acceptance result from real assets, UI, behavior, or outcomes, then click "Pass" or "Fail".',
          fr: 'Saisissez le résultat issu des assets, de l’UI, du comportement ou des constats, puis cliquez sur "Valider" ou "Refuser".',
          de: 'Erfasse das Prüfergebnis aus Assets, UI, Verhalten oder Beobachtungen und wähle dann "Bestehen" oder "Ablehnen".',
          ja: '資産、UI、挙動、実結果に基づくレビュー結果を入力し、「合格」または「不合格」を選択してください。',
        ),
        hintText: openHandLocalizedText(
          context,
          zh: '例如：桌面端布局符合预期，但导出图片边缘仍有白边；移动端卡片间距偏大。',
          zhHant: '例如：桌面端佈局符合預期，但匯出圖片邊緣仍有白邊；行動端卡片間距偏大。',
          en: 'Example: desktop layout looks correct, but exported images still show white edges and mobile card spacing is too large.',
          fr: 'Exemple : le layout desktop est correct, mais les exports gardent des bords blancs et l’espacement mobile est trop grand.',
          de: 'Beispiel: Desktop-Layout passt, aber Exporte haben weiße Ränder und mobile Kartenabstände sind zu groß.',
          ja: '例：デスクトップ配置は想定通りだが、画像書き出しに白い縁が残り、モバイルのカード間隔が大きい。',
        ),
        emptyMessage: openHandLocalizedText(
          context,
          zh: '请先填写验收结果，再提交判定。',
          zhHant: '請先填寫驗收結果，再提交判定。',
          en: 'Enter your acceptance result before submitting a verdict.',
          fr: 'Saisissez le résultat avant de soumettre le verdict.',
          de: 'Gib zuerst das Prüfergebnis ein, bevor du entscheidest.',
          ja: '判定を送信する前にレビュー結果を入力してください。',
        ),
        activeBannerText: openHandLocalizedText(
          context,
          zh: '已切换为人工验收。请填写验收结果后点击“验收通过”或“验收不通过”。',
          zhHant: '已切換為人工驗收。請填寫驗收結果後點擊「驗收通過」或「驗收不通過」。',
          en: 'Manual review is active. Enter the result, then click "Pass" or "Fail".',
          fr: 'La revue manuelle est active. Saisissez le résultat, puis choisissez "Valider" ou "Refuser".',
          de: 'Manuelle Prüfung ist aktiv. Erfasse das Ergebnis und wähle "Bestehen" oder "Ablehnen".',
          ja: '手動レビューが有効です。結果を入力し、「合格」または「不合格」を選択してください。',
        ),
        queuedBannerText: openHandLocalizedText(
          context,
          zh: '已保留上一份人工验收结果。点击“继续”会复用它；如需修改，请再次点击“我来验收”。',
          zhHant: '已保留上一份人工驗收結果。點擊「繼續」會重用；如需修改，請再次點擊「我來驗收」。',
          en: 'Previous manual acceptance result is queued. Continue to reuse it, or choose "I Will Review" again to revise.',
          fr: 'Le résultat précédent est en file. Continuez pour le réutiliser, ou relancez la revue manuelle pour modifier.',
          de: 'Das vorherige Prüfergebnis ist vorgemerkt. Fortfahren nutzt es erneut; wähle erneut manuelle Prüfung zum Ändern.',
          ja: '前回の手動レビュー結果が残っています。続行で再利用し、変更する場合は再度選択してください。',
        ),
        icon: Icons.fact_check_outlined,
      ),
      HarnessPhase.reading || HarnessPhase.implementing => _HeManualPhaseCopy(
        actionLabel: openHandLocalizedText(
          context,
          zh: '我来处理',
          zhHant: '我來處理',
          en: 'I Will Handle It',
          fr: 'Je le traite',
          de: 'Ich übernehme',
          ja: '自分で処理',
        ),
        switchBackLabel: openHandLocalizedText(
          context,
          zh: '改用 AI 处理',
          zhHant: '改用 AI 處理',
          en: 'Use AI',
          fr: 'Utiliser l’IA',
          de: 'KI nutzen',
          ja: 'AI に切り替え',
        ),
        title: openHandLocalizedText(
          context,
          zh: '人工输入',
          zhHant: '人工輸入',
          en: 'Manual Input',
          fr: 'Saisie manuelle',
          de: 'Manuelle Eingabe',
          ja: '手動入力',
        ),
        helperText: openHandLocalizedText(
          context,
          zh: '请填写人工输入。',
          zhHant: '請填寫人工輸入。',
          en: 'Enter manual input.',
          fr: 'Saisissez l’entrée manuelle.',
          de: 'Gib die manuelle Eingabe ein.',
          ja: '手動入力を記入してください。',
        ),
        hintText: openHandLocalizedText(
          context,
          zh: '输入人工内容…',
          zhHant: '輸入人工內容…',
          en: 'Enter manual input…',
          fr: 'Saisir le contenu manuel…',
          de: 'Manuelle Eingabe eingeben…',
          ja: '手動内容を入力…',
        ),
        emptyMessage: openHandLocalizedText(
          context,
          zh: '请先填写内容。',
          zhHant: '請先填寫內容。',
          en: 'Enter the content first.',
          fr: 'Saisissez d’abord le contenu.',
          de: 'Gib zuerst den Inhalt ein.',
          ja: '先に内容を入力してください。',
        ),
        activeBannerText: openHandLocalizedText(
          context,
          zh: '已切换为人工输入。',
          zhHant: '已切換為人工輸入。',
          en: 'Manual input is active.',
          fr: 'La saisie manuelle est active.',
          de: 'Manuelle Eingabe ist aktiv.',
          ja: '手動入力が有効です。',
        ),
        queuedBannerText: openHandLocalizedText(
          context,
          zh: '已保留上一份人工输入。',
          zhHant: '已保留上一份人工輸入。',
          en: 'The previous manual input is still queued.',
          fr: 'La saisie manuelle précédente est en file.',
          de: 'Die vorherige manuelle Eingabe ist vorgemerkt.',
          ja: '前回の手動入力が残っています。',
        ),
        icon: Icons.edit_note_rounded,
      ),
    };
  }

  bool _isPhaseExpanded(HarnessPhaseLog log) {
    final override = _expandedOverrides[log];
    if (override != null) return override;
    return log.status == HarnessPhaseStatus.running ||
        log.status == HarnessPhaseStatus.paused ||
        log.status == HarnessPhaseStatus.failed;
  }

  void _setPhaseExpanded(HarnessPhaseLog log, bool expanded) {
    setState(() => _expandedOverrides[log] = expanded);
  }

  String? _phaseApprovalIssue(HarnessPhase phase) {
    final blocker = widget.orchestrator.phaseExecutionBlocker(phase);
    return switch (blocker) {
      HarnessPhaseExecutionBlocker.missingConfig =>
        widget.isZh
            ? '请先为该阶段配置 CLI/模型 或 API 模型，然后再继续执行。'
            : 'Configure the CLI/model or API model for this phase before continuing.',
      HarnessPhaseExecutionBlocker.unsupportedCli =>
        widget.isZh
            ? '当前 CLI 不支持无交互执行，请改为支持 headless 的 CLI。'
            : 'The selected CLI does not support headless execution. Choose a supported CLI.',
      HarnessPhaseExecutionBlocker.missingApiModel =>
        widget.isZh
            ? '所选 API 模型配置无效或已被删除，请在设置中检查。'
            : 'The selected API model configuration is invalid or deleted. Check settings.',
      HarnessPhaseExecutionBlocker.missingApiRunner =>
        widget.isZh
            ? 'API 运行时未初始化，请重启应用。'
            : 'API runtime not initialized. Restart the application.',
      null => null,
    };
  }

  void _setComposerCollapsedState(
    bool collapsed, {
    bool requestFocusWhenExpanded = false,
  }) {
    final wasCollapsed = _composerCollapsed;
    if (wasCollapsed != collapsed) {
      setState(() => _composerCollapsed = collapsed);
      // 补偿 scroll offset：当 composer 展开/折叠时，feed 区域高度变化会
      // 导致滚动位置跳动。在下一帧测量高度差并反向补偿，保持可视内容稳定。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_feedController.hasClients) return;
        // 用户正在拖动 feed 时跳过补偿，避免与触摸 / 滚轮事件抢占
        // ScrollPosition.pixels（同样的"鬼畜"问题）。
        if (_userFeedScrollInProgress) return;
        // 如果用户在底部（auto-follow），确保仍然贴底
        if (_autoFollowEnabled && _shouldAutoFollowFeed) {
          final pos = _feedController.position;
          if (pos.pixels < pos.maxScrollExtent - 1.0) {
            _beginProgrammaticFeedScroll();
            _feedController.jumpTo(pos.maxScrollExtent);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _endProgrammaticFeedScroll();
              }
            });
          }
        }
      });
    }
    if (collapsed) {
      if (_manualPhaseFocusNode.hasFocus) {
        _manualPhaseFocusNode.unfocus();
      }
      return;
    }
    if (!requestFocusWhenExpanded || !_isAwaitingManualPhaseInput) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _composerCollapsed || !_isAwaitingManualPhaseInput) {
        return;
      }
      if (_manualPhaseFocusNode.canRequestFocus) {
        _manualPhaseFocusNode.requestFocus();
      }
    });
  }

  bool _shouldAllowEditableShortcut(OpenHandShortcutAction action) {
    if (_composerCollapsed || !_manualPhaseFocusNode.hasFocus) {
      return false;
    }
    return action == OpenHandShortcutAction.sendMessage ||
        action == OpenHandShortcutAction.toggleComposer;
  }

  KeyEventResult _handleManualPhaseFocusNodeKeyEvent(
    FocusNode node,
    KeyEvent event,
  ) {
    // 全局键盘处理器负责执行动作，此处只消费快捷键以避免重复触发。
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final settingsController = Provider.of<SettingsController?>(
      context,
      listen: false,
    );
    if (settingsController == null) {
      return KeyEventResult.ignored;
    }
    final pressedKeyIds = normalizedPressedShortcutKeyIds(<LogicalKeyboardKey>{
      ...HardwareKeyboard.instance.logicalKeysPressed,
      event.logicalKey,
    });
    if (pressedKeyIds.isEmpty) {
      return KeyEventResult.ignored;
    }
    for (final action in <OpenHandShortcutAction>[
      OpenHandShortcutAction.sendMessage,
      OpenHandShortcutAction.toggleComposer,
    ]) {
      final binding = normalizeShortcutKeyIds(
        settingsController.shortcutBindings[action] ?? const <int>[],
      );
      if (binding.isEmpty || binding.length != pressedKeyIds.length) continue;
      if (pressedKeyIds.containsAll(binding)) {
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<bool> _handleShortcutAction(OpenHandShortcutAction action) async {
    switch (action) {
      case OpenHandShortcutAction.sendMessage:
        await _handlePrimaryComposerAction();
        return true;
      case OpenHandShortcutAction.toggleComposer:
        _setComposerCollapsedState(
          !_composerCollapsed,
          requestFocusWhenExpanded: _composerCollapsed,
        );
        return true;
      case OpenHandShortcutAction.toggleAutoFollow:
        _toggleAutoFollow();
        return true;
      case OpenHandShortcutAction.selectPreviousModel:
      case OpenHandShortcutAction.selectNextModel:
      case OpenHandShortcutAction.selectPreviousSession:
      case OpenHandShortcutAction.selectNextSession:
      case OpenHandShortcutAction.undoLastFileMutation:
        return false;
    }
  }

  Future<void> _handlePrimaryComposerAction() async {
    if (_isAwaitingManualPhaseInput) {
      await _submitManualPhaseInput();
      return;
    }
    if (_isRunning) {
      await _requestCancel(context);
      return;
    }
    widget.onRestart();
  }

  Future<void> _submitManualPhaseInput() async {
    final awaitingPhase = _awaitingManualPhase;
    if (awaitingPhase == null) {
      _showComposerMessage(
        openHandLocalizedText(
          context,
          zh: '当前没有等待中的人工输入阶段。',
          zhHant: '目前沒有等待中的人工輸入階段。',
          en: 'No manual phase input is currently expected.',
          fr: 'Aucune phase de saisie manuelle n’est attendue.',
          de: 'Aktuell wird keine manuelle Phaseneingabe erwartet.',
          ja: '現在、手動入力待ちのフェーズはありません。',
        ),
      );
      return;
    }
    final content = _manualPhaseController.text.trim();
    if (content.isEmpty) {
      _showComposerMessage(
        _manualPhaseCopy(context, awaitingPhase).emptyMessage,
      );
      return;
    }
    if (_manualPhaseSubmitting) {
      return;
    }

    setState(() => _manualPhaseSubmitting = true);
    try {
      final submitted = widget.orchestrator.submitManualPhaseInput(content);
      if (!submitted && mounted) {
        setState(() => _manualPhaseSubmitting = false);
        _showComposerMessage(
          openHandLocalizedText(
            context,
            zh: '人工输入提交失败，请重试。',
            zhHant: '人工輸入提交失敗，請重試。',
            en: 'Failed to submit the manual input. Try again.',
            fr: 'Échec de l’envoi manuel. Réessayez.',
            de: 'Manuelle Eingabe konnte nicht gesendet werden. Erneut versuchen.',
            ja: '手動入力の送信に失敗しました。再試行してください。',
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _manualPhaseSubmitting = false);
      _showComposerMessage(
        openHandLocalizedText(
          context,
          zh: '人工输入提交异常，请重试。',
          zhHant: '人工輸入提交異常，請重試。',
          en: 'The manual input submission failed unexpectedly. Try again.',
          fr: 'L’envoi manuel a échoué de façon inattendue. Réessayez.',
          de: 'Manuelle Eingabe ist unerwartet fehlgeschlagen. Erneut versuchen.',
          ja: '手動入力の送信で予期しないエラーが発生しました。再試行してください。',
        ),
      );
    }
  }

  /// 提交带明确通过或失败结论的人工验收内容。
  Future<void> _submitManualReviewVerdict({required bool pass}) async {
    final awaitingPhase = _awaitingManualPhase;
    if (awaitingPhase != HarnessPhase.reviewing) {
      return;
    }
    final content = _manualPhaseController.text.trim();
    if (content.isEmpty) {
      _showComposerMessage(
        openHandLocalizedText(
          context,
          zh: '请先填写验收结果，再提交判定。',
          zhHant: '請先填寫驗收結果，再提交判定。',
          en: 'Enter your review result before submitting a verdict.',
          fr: 'Saisissez le résultat avant de soumettre le verdict.',
          de: 'Gib zuerst das Prüfergebnis ein, bevor du entscheidest.',
          ja: '判定を送信する前にレビュー結果を入力してください。',
        ),
      );
      return;
    }
    if (_manualPhaseSubmitting) {
      return;
    }

    setState(() => _manualPhaseSubmitting = true);
    try {
      final submitted = widget.orchestrator.submitManualPhaseInput(
        content,
        reviewVerdict: pass,
      );
      if (!submitted && mounted) {
        setState(() => _manualPhaseSubmitting = false);
        _showComposerMessage(
          openHandLocalizedText(
            context,
            zh: '验收结果提交失败，请重试。',
            zhHant: '驗收結果提交失敗，請重試。',
            en: 'Failed to submit the review verdict. Try again.',
            fr: 'Échec de l’envoi du verdict. Réessayez.',
            de: 'Prüfurteil konnte nicht gesendet werden. Erneut versuchen.',
            ja: 'レビュー判定の送信に失敗しました。再試行してください。',
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _manualPhaseSubmitting = false);
      _showComposerMessage(
        openHandLocalizedText(
          context,
          zh: '验收结果提交异常，请重试。',
          zhHant: '驗收結果提交異常，請重試。',
          en: 'The review verdict submission failed unexpectedly. Try again.',
          fr: 'L’envoi du verdict a échoué de façon inattendue. Réessayez.',
          de: 'Prüfurteil ist unerwartet fehlgeschlagen. Erneut versuchen.',
          ja: 'レビュー判定の送信で予期しないエラーが発生しました。再試行してください。',
        ),
      );
    }
  }

  void _showComposerMessage(String message) {
    if (!mounted) {
      return;
    }
    showOpenHandInfoSnack(context, message);
  }

  void _clearPendingFeedAutoFollowState() {
    _queuedForcedFeedScrollToBottom = false;
    _pendingAnimatedFeedScrollToBottom = false;
    _feedProgrammaticScrollWindow.cancel();
    _scrollSettlePasses = 0;
  }

  bool _isProgrammaticFeedScrollInProgress() {
    return _feedProgrammaticScrollWindow.active;
  }

  bool _isProgrammaticFeedScrollCommandBusy() {
    return _feedProgrammaticScrollWindow.busy;
  }

  void _beginProgrammaticFeedScroll() {
    _feedProgrammaticScrollWindow.begin();
  }

  void _endProgrammaticFeedScroll() {
    _feedProgrammaticScrollWindow.end();
  }

  void _handleFeedPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    _feedProgrammaticScrollWindow.cancel();
    _lastFeedPointerSignalScrollAt = _feedScrollActivityStopwatch.elapsed;
    _markUserFeedScrollInProgress();
    _scheduleUserFeedScrollEndGrace();
  }

  bool _hasRecentFeedPointerSignalScrollActivity() {
    final last = _lastFeedPointerSignalScrollAt;
    if (last == null) {
      return false;
    }
    return _feedScrollActivityStopwatch.elapsed - last <=
        kAutoFollowPointerSignalActivityWindow;
  }

  /// 标记用户正在滚动 feed；取消任何待执行的 scroll-end 宽限。
  void _markUserFeedScrollInProgress() {
    _userFeedScrollGraceTimer?.cancel();
    _userFeedScrollGraceTimer = null;
    _userFeedScrollInProgress = true;
  }

  /// scroll-end 后延迟 [_userFeedScrollEndGraceDuration] 才真正放手，
  /// 桥接 trackpad / 滚轮连续 tick 之间的空窗。
  void _scheduleUserFeedScrollEndGrace() {
    _userFeedScrollGraceTimer?.cancel();
    _userFeedScrollGraceTimer = startSafeTimer(
      _userFeedScrollEndGraceDuration,
      () {
        _userFeedScrollGraceTimer = null;
        if (!mounted) {
          return;
        }
        _userFeedScrollInProgress = false;
      },
    );
  }

  void _handleFeedScroll() {
    if (!_isNearFeedBottom()) {
      return;
    }
    if (!_autoFollowEnabled) {
      return;
    }
    // 用户拖动 / trackpad tick 进行中时不允许 pixel 监听重新启用自动跟随，
    // 否则一旦贴近底部就会
    // 在下一帧把视口拉走。
    if (_userFeedScrollInProgress) {
      return;
    }
    if (!_shouldAutoFollowFeed) {
      _shouldAutoFollowFeed = true;
    }
    if (_queuedForcedFeedScrollToBottom) {
      _queuedForcedFeedScrollToBottom = false;
    }
  }

  bool _handleFeedScrollNotification(ScrollNotification notification) {
    final programmaticScroll = _isProgrammaticFeedScrollInProgress();
    final recentPointerSignalScroll =
        _hasRecentFeedPointerSignalScrollActivity();
    final explicitUserScroll = isExplicitUserScrollNotification(
      notification,
      programmaticScroll: programmaticScroll,
    );
    final userScrollEnded = isUserScrollEndNotification(notification);
    final implicitPointerSignalScroll =
        isImplicitPointerSignalScrollNotification(
          notification,
          programmaticScroll: programmaticScroll,
          recentPointerSignalScroll: recentPointerSignalScroll,
        );
    final userScrollActivity =
        explicitUserScroll || implicitPointerSignalScroll;

    if (userScrollActivity) {
      _markUserFeedScrollInProgress();
    } else if (userScrollEnded) {
      _scheduleUserFeedScrollEndGrace();
    }

    if (programmaticScroll) {
      if (!explicitUserScroll) {
        return false;
      }
      _feedProgrammaticScrollWindow.cancel();
    }

    final distanceToBottom =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    final isNearBottom = distanceToBottom <= _feedAutoFollowDistanceThreshold;

    if (!_autoFollowEnabled && userScrollActivity) {
      _shouldAutoFollowFeed = false;
      _clearPendingFeedAutoFollowState();
      return false;
    }

    final userScrolledUpwardFromBottom =
        notification is UserScrollNotification &&
        notification.direction == ScrollDirection.reverse &&
        distanceToBottom > 0;
    final pointerSignalScrolledUpwardFromBottom =
        implicitPointerSignalScroll &&
        notification is ScrollUpdateNotification &&
        (notification.scrollDelta ?? 0) < -0.5 &&
        distanceToBottom > 0;

    if ((!isNearBottom && userScrollActivity) ||
        userScrolledUpwardFromBottom ||
        pointerSignalScrolledUpwardFromBottom) {
      _shouldAutoFollowFeed = false;
      _clearPendingFeedAutoFollowState();
      return false;
    }

    if (userScrollEnded &&
        _autoFollowEnabled &&
        _queuedForcedFeedScrollToBottom) {
      _scheduleFeedAutoScroll(force: true);
    }

    if (isNearBottom && _autoFollowEnabled && userScrollEnded) {
      _shouldAutoFollowFeed = true;
    }
    return false;
  }

  bool _isNearFeedBottom() {
    if (!_feedController.hasClients) {
      return true;
    }
    final position = _feedController.position;
    return position.maxScrollExtent - position.pixels <=
        _feedAutoFollowDistanceThreshold;
  }

  void _toggleAutoFollow() {
    final nextValue = !_autoFollowEnabled;
    setState(() {
      _autoFollowEnabled = nextValue;
      if (nextValue) {
        _shouldAutoFollowFeed = true;
      } else {
        _shouldAutoFollowFeed = false;
        _clearPendingFeedAutoFollowState();
      }
    });
    if (nextValue) {
      _scheduleFeedAutoScroll(force: true, animated: false);
    }
  }

  void _scheduleFeedAutoScroll({
    bool force = false,
    bool animated = true,
    bool allowSettlePasses = true,
  }) {
    if (!force &&
        (!_autoFollowEnabled ||
            !_shouldAutoFollowFeed ||
            _userFeedScrollInProgress)) {
      return;
    }
    if (force) {
      _shouldAutoFollowFeed = true;
      _queuedForcedFeedScrollToBottom = true;
    }
    _pendingAnimatedFeedScrollToBottom =
        _pendingAnimatedFeedScrollToBottom || (animated && !_isRunning);
    if (allowSettlePasses) {
      final newPasses = _isRunning ? 22 : (animated ? 4 : 3);
      if (_scrollSettlePasses < newPasses) {
        _scrollSettlePasses = newPasses;
      }
    }
    if (_isProgrammaticFeedScrollCommandBusy() || _userFeedScrollInProgress) {
      return;
    }
    if (_scrollCallbackQueued) {
      return;
    }

    _scrollCallbackQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollCallbackQueued = false;
      if (!mounted) {
        _clearPendingFeedAutoFollowState();
        return;
      }
      if (_userFeedScrollInProgress) {
        return;
      }

      final shouldForce = _queuedForcedFeedScrollToBottom;
      final shouldAnimate = _pendingAnimatedFeedScrollToBottom;
      _queuedForcedFeedScrollToBottom = false;
      _pendingAnimatedFeedScrollToBottom = false;
      if (!shouldForce && (!_autoFollowEnabled || !_shouldAutoFollowFeed)) {
        _scrollSettlePasses = 0;
        return;
      }
      if (!_feedController.hasClients) {
        _scrollSettlePasses = 0;
        return;
      }

      final position = _feedController.position;
      final target = position.maxScrollExtent
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      final distance = (target - position.pixels).abs();

      void clearProgrammaticScrollFlag() {
        _endProgrammaticFeedScroll();
      }

      void scheduleSettlePass() {
        if (!mounted || _scrollSettlePasses <= 0) {
          return;
        }
        _scrollSettlePasses -= 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _userFeedScrollInProgress) {
            _scrollSettlePasses = 0;
            return;
          }
          _scheduleFeedAutoScroll(animated: false, allowSettlePasses: false);
        });
      }

      if (distance >= 1 &&
          shouldAnimate &&
          distance > _feedAutoFollowAnimatedDistanceThreshold) {
        _beginProgrammaticFeedScroll();
        _feedController
            .animateTo(
              target,
              duration: Duration(
                milliseconds: (100 + distance * 0.12).clamp(100, 280).round(),
              ),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
              clearProgrammaticScrollFlag();
              scheduleSettlePass();
            });
        return;
      }
      if (distance >= 1) {
        _beginProgrammaticFeedScroll();
        _feedController.jumpTo(target);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          clearProgrammaticScrollFlag();
          scheduleSettlePass();
        });
        return;
      }
      scheduleSettlePass();
    });
  }

  @override
  Widget build(BuildContext context) {
    final manualPhaseCopy = _manualPhaseCopy(context, _effectiveManualPhase);
    final primaryActionLabel = _isAwaitingManualPhaseInput
        ? (_manualPhaseSubmitting
              ? openHandSendingLabel(context)
              : openHandLocalizedText(
                  context,
                  zh: '发送',
                  zhHant: '傳送',
                  en: 'Send',
                  fr: 'Envoyer',
                  de: 'Senden',
                  ja: '送信',
                ))
        : _isRunning
        ? _heCancelLabel(context)
        : _canRetryFailedRun
        ? _heRetryFailedPhaseLabel(context)
        : (_isDone ? _heRunAgainLabel(context) : _heStartLabel(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HePaneHeader(
          config: widget.config,
          orchestrator: widget.orchestrator,
          isZh: widget.isZh,
          isRunning: _isRunning,
          isDone: _isDone,
          sessionTitle: widget.sessionTitle,
          updatedAtLabel: widget.updatedAtLabel,
          sessionId: widget.sessionId,
          createdAtLabel: widget.createdAtLabel,
          sessionCreatedAt: widget.sessionCreatedAt,
          sessionUpdatedAt: widget.sessionUpdatedAt,
          onCancel: () => _requestCancel(context),
          onRestart: widget.onRestart,
          fullAccessPermission: widget.fullAccessPermission,
          onToggleFullAccess: widget.onToggleFullAccessPermission,
          replayPendingDeadlineListenable:
              widget.replayPendingDeadlineListenable,
          onCancelPendingReplay: widget.onCancelPendingReplay,
        ),
        kOpenHandGap12,
        Expanded(child: _buildFeed(context)),
        kOpenHandGap16,
        _HeComposer(
          isCollapsed: _composerCollapsed,
          onCollapsedChanged: (collapsed) => _setComposerCollapsedState(
            collapsed,
            requestFocusWhenExpanded: !collapsed,
          ),
          autoFollowEnabled: _autoFollowEnabled,
          onToggleAutoFollow: _toggleAutoFollow,
          fullAccessPermission: widget.fullAccessPermission,
          onToggleFullAccessPermission: widget.onToggleFullAccessPermission,
          manualPhaseEnabled: _isAwaitingManualPhaseInput,
          manualPhaseTitle: manualPhaseCopy.title,
          manualPhaseController: _manualPhaseController,
          manualPhaseFocusNode: _manualPhaseFocusNode,
          manualPhaseHelperText: manualPhaseCopy.helperText,
          manualPhaseHintText: manualPhaseCopy.hintText,
          primaryActionLabel: primaryActionLabel,
          primaryActionIcon: _isAwaitingManualPhaseInput
              ? (_manualPhaseSubmitting
                    ? Icons.hourglass_top_rounded
                    : Icons.send_rounded)
              : _isRunning
              ? Icons.stop_rounded
              : _canRetryFailedRun
              ? Icons.replay_circle_filled_rounded
              : (_isDone
                    ? Icons.restart_alt_rounded
                    : Icons.play_arrow_rounded),
          primaryActionEnabled:
              !_isAwaitingManualPhaseInput || _canSubmitManualPhase,
          onPrimaryAction: () {
            _handlePrimaryComposerAction();
          },
          isManualReviewPhase:
              _isAwaitingManualPhaseInput &&
              _awaitingManualPhase == HarnessPhase.reviewing,
          onReviewPass: () => _submitManualReviewVerdict(pass: true),
          onReviewFail: () => _submitManualReviewVerdict(pass: false),
          reviewSubmitting: _manualPhaseSubmitting,
        ),
      ],
    );
  }

  Widget _buildFeed(BuildContext context) {
    final orchestrator = widget.orchestrator;
    final logs = orchestrator.phaseLogs;
    final awaitingApprovalPhase = orchestrator.awaitingApprovalPhase;
    final approvalIssue = awaitingApprovalPhase == null
        ? null
        : _phaseApprovalIssue(awaitingApprovalPhase);

    // 无阶段时区分等待启动与正在启动。
    if (logs.isEmpty) {
      if (orchestrator.status == HarnessOrchestratorStatus.idle) {
        return _HeReadyPlaceholder(
          isZh: widget.isZh,
          onStart: widget.onRestart,
        );
      }
      if (orchestrator.status == HarnessOrchestratorStatus.running) {
        return _InitializingPlaceholder(isZh: widget.isZh);
      }
      return _HeRestoredSessionPlaceholder(
        isZh: widget.isZh,
        status: orchestrator.status,
        onRestart: widget.onRestart,
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _handleFeedPointerSignal,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleFeedScrollNotification,
        child: OpenHandSafeScrollbar(
          controller: _feedController,
          child: ListView.builder(
            controller: _feedController,
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
            // 缓存少量阶段卡片，平衡桌面滚动流畅度与离屏构建成本。
            cacheExtent: 1800,
            // 等待审批时追加一张审批卡片。
            itemCount:
                logs.length +
                (widget.orchestrator.awaitingApprovalPhase != null ? 1 : 0),
            itemBuilder: (context, index) {
              if (index < logs.length) {
                final log = logs[index];
                final phaseIndex = index;
                final isNotRunning =
                    widget.orchestrator.status !=
                    HarnessOrchestratorStatus.running;
                final isSelected = _selectedPhaseLog == log;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _HePhaseCardEntrance(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        if (_selectedPhaseLog == log) return;
                        setState(() => _selectedPhaseLog = log);
                      },
                      child: TapRegion(
                        enabled: isSelected,
                        onTapOutside: (_) {
                          if (_selectedPhaseLog != log) return;
                          setState(() => _selectedPhaseLog = null);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _HePhaseCard(
                              key: ObjectKey(log),
                              log: log,
                              config: widget.config,
                              isZh: widget.isZh,
                              expanded: _isPhaseExpanded(log),
                              onToggleExpand: () => _setPhaseExpanded(
                                log,
                                !_isPhaseExpanded(log),
                              ),
                              onCopyLog: () => _copyLog(context, log),
                              onRoleConfigChanged: _isPhaseConfigEditable(log)
                                  ? (newRoleConfig) => _updatePhaseConfig(
                                      log.phase,
                                      newRoleConfig,
                                    )
                                  : null,
                              filePathRoots: widget.filePathRoots,
                            ),
                            if (isSelected && isNotRunning)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: _HePhaseActionBar(
                                  onCopyLog: () => _copyLog(context, log),
                                  onReExecute: () =>
                                      _reExecutePhase(phaseIndex),
                                  onDelete: () =>
                                      _deletePhaseLog(context, phaseIndex),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }
              if (awaitingApprovalPhase != null) {
                final approvalPhaseCopy = _manualPhaseCopy(
                  context,
                  awaitingApprovalPhase,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _HePhaseApprovalBanner(
                    nextPhase: awaitingApprovalPhase,
                    approvalIssue: approvalIssue,
                    manualPhaseEnabled: widget.orchestrator
                        .isManualPhaseInputActiveFor(awaitingApprovalPhase),
                    hasQueuedManualPhaseInput: widget.orchestrator
                        .hasQueuedManualPhaseInputFor(awaitingApprovalPhase),
                    manualPhaseActionLabel: approvalPhaseCopy.actionLabel,
                    manualPhaseSwitchBackLabel:
                        approvalPhaseCopy.switchBackLabel,
                    manualPhaseActiveDescription:
                        approvalPhaseCopy.activeBannerText,
                    manualPhaseQueuedDescription:
                        approvalPhaseCopy.queuedBannerText,
                    manualPhaseIcon: approvalPhaseCopy.icon,
                    onManualPhaseToggle:
                        widget.orchestrator.supportsManualPhaseInput(
                              awaitingApprovalPhase,
                            ) &&
                            approvalIssue == null
                        ? () =>
                              widget.orchestrator.setManualPhaseInputRequested(
                                !widget.orchestrator
                                    .isManualPhaseInputActiveFor(
                                      awaitingApprovalPhase,
                                    ),
                              )
                        : null,
                    onApprove: approvalIssue == null
                        ? () => widget.orchestrator.resolvePhaseApproval(true)
                        : null,
                    onReject: () =>
                        widget.orchestrator.resolvePhaseApproval(false),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  void _updatePhaseConfig(HarnessPhase phase, HarnessRoleConfig newRoleConfig) {
    final config = widget.config;
    final updated = switch (phase) {
      HarnessPhase.metaCollection => config.copyWith(
        profilerConfig: newRoleConfig,
      ),
      HarnessPhase.reading => config.copyWith(readerConfig: newRoleConfig),
      HarnessPhase.planning => config.copyWith(plannerConfig: newRoleConfig),
      HarnessPhase.implementing => config.copyWith(
        implementerConfig: newRoleConfig,
      ),
      HarnessPhase.reviewing => config.copyWith(reviewerConfig: newRoleConfig),
    };
    widget.onConfigChanged(updated);
  }

  void _copyLog(BuildContext context, HarnessPhaseLog log) {
    unawaited(
      copyOpenHandTextToClipboard(
        logTag: 'harness',
        context: context,
        text: log.lines.join('\n'),
        successMessage: openHandLocalizedText(
          context,
          zh: '日志已复制到剪贴板',
          zhHant: '日誌已複製到剪貼簿',
          en: 'Log copied to clipboard',
          fr: 'Journal copié dans le presse-papiers',
          de: 'Log in die Zwischenablage kopiert',
          ja: 'ログをクリップボードにコピーしました',
        ),
        logAction: '复制阶段日志',
      ),
    );
  }

  void _reExecutePhase(int phaseIndex) {
    widget.orchestrator.reExecutePhase(phaseIndex);
  }

  Future<void> _deletePhaseLog(BuildContext context, int phaseIndex) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '删除阶段',
        zhHant: '刪除階段',
        en: 'Delete Phase',
        fr: 'Supprimer la phase',
        de: 'Phase löschen',
        ja: 'フェーズを削除',
      ),
      message: openHandLocalizedText(
        context,
        zh: '确定删除这个阶段吗？删除后该阶段的执行日志将被移除。',
        zhHant: '確定要刪除此階段嗎？刪除後此階段的執行日誌將被移除。',
        en: 'Are you sure you want to delete this phase? The execution log will be removed.',
        fr: 'Voulez-vous supprimer cette phase ? Son journal d’exécution sera supprimé.',
        de: 'Diese Phase wirklich löschen? Das Ausführungslog wird entfernt.',
        ja: 'このフェーズを削除しますか？実行ログも削除されます。',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandDeleteLabel(context),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    widget.orchestrator.deletePhaseLog(phaseIndex);
  }

  Future<void> _requestCancel(BuildContext context) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '确认中止',
        zhHant: '確認中止',
        en: 'Confirm Cancel',
        fr: 'Confirmer l’annulation',
        de: 'Abbruch bestätigen',
        ja: '中止を確認',
      ),
      message: openHandLocalizedText(
        context,
        zh: '当前会话仍在运行中，确定要中止吗？\nCLI 进程将被终止，已生成的文件会保留。',
        zhHant: '目前會話仍在執行中，確定要中止嗎？\nCLI 行程將被終止，已生成的檔案會保留。',
        en: 'Session is still running. Cancel it?\nThe active CLI process will be killed. Already-generated files are kept.',
        fr: 'La session est encore en cours. L’annuler ?\nLe processus CLI actif sera arrêté. Les fichiers déjà générés sont conservés.',
        de: 'Die Sitzung läuft noch. Abbrechen?\nDer aktive CLI-Prozess wird beendet. Bereits erzeugte Dateien bleiben erhalten.',
        ja: 'セッションはまだ実行中です。中止しますか？\n実行中の CLI プロセスは終了され、生成済みファイルは保持されます。',
      ),
      cancelLabel: openHandLocalizedText(
        context,
        zh: '继续运行',
        zhHant: '繼續執行',
        en: 'Keep Running',
        fr: 'Continuer',
        de: 'Weiter ausführen',
        ja: '実行を続ける',
      ),
      confirmLabel: _heCancelLabel(context),
      destructive: true,
    );
    if (confirmed == true && mounted) {
      widget.orchestrator.cancel();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 本库内共用的文案
//
// 下列标签原先在同一个库的多个 part 里各写了一份多语言字面量，改一处措辞就
// 得同步改两到三处。
// ─────────────────────────────────────────────────────────────────────────────

String _heCancelLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '中止',
    zhHant: '中止',
    en: 'Cancel',
    fr: 'Annuler',
    de: 'Abbrechen',
    ja: '中止',
  );
}

String _heRetryFailedPhaseLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '重试失败阶段',
    zhHant: '重試失敗階段',
    en: 'Retry Failed Phase',
    fr: 'Réessayer la phase échouée',
    de: 'Fehlgeschlagene Phase wiederholen',
    ja: '失敗したフェーズを再試行',
  );
}

String _heRunAgainLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '重新执行',
    zhHant: '重新執行',
    en: 'Run Again',
    fr: 'Relancer',
    de: 'Erneut ausführen',
    ja: '再実行',
  );
}

String _heStartLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '开始执行',
    zhHant: '開始執行',
    en: 'Start',
    fr: 'Démarrer',
    de: 'Starten',
    ja: '開始',
  );
}
