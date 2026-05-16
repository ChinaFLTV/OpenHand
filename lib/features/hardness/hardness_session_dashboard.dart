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

import '../../app/model/openhand_shortcut.dart';
import '../../app/state/settings_controller.dart';
import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/animated_expandable.dart';
import '../../shared/ui/animated_menu.dart';
import '../../shared/ui/animated_overlay.dart';
import '../../shared/ui/error_snackbar.dart';
import '../../shared/ui/model_search_selector.dart';
import '../../shared/ui/oh_pill.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../ai/model/ai_model_config.dart';
import '../home/message_path_linking.dart';
import 'hardness_cli_catalog.dart';
import 'hardness_orchestrator.dart';
import 'model/hardness_phase.dart';
import 'model/hardness_role_config.dart';
import 'model/hardness_session_config.dart';
import 'widgets/hardness_pending_replay_badge.dart';

// 2026-04-27 Split scaffolding (step 0). The implementation is being
// progressively extracted into per-section part files. Each part shares the
// same library scope, so all private types remain accessible without
// changing call sites.
part 'hardness_session_dashboard.header.part.dart';
part 'hardness_session_dashboard.phase_card.part.dart';
part 'hardness_session_dashboard.log_views.part.dart';
part 'hardness_session_dashboard.streaming.part.dart';
part 'hardness_session_dashboard.tool_trace.part.dart';
part 'hardness_session_dashboard.segment_body.part.dart';
part 'hardness_session_dashboard.markdown.part.dart';
part 'hardness_session_dashboard.composer.part.dart';
part 'hardness_session_dashboard.model_dropdown.part.dart';
part 'hardness_session_dashboard.changed_files.part.dart';
part 'hardness_session_dashboard.streaming_smart.part.dart';
part 'hardness_session_dashboard.file_hover.part.dart';
part 'hardness_session_dashboard.steering.part.dart';

void _showHardnessSnackBar(BuildContext context, SnackBar snackBar) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  OpenHandSnackBar.show(context, messenger, snackBar);
}

// Pre-compiled regex for detecting log-level prefixes in output lines.
final RegExp _logLevelPattern = RegExp(
  r'\b(ERROR|ERR|WARN|WARNING|INFO|DEBUG|TRACE)\b',
  caseSensitive: false,
);

// Matches terminal separator lines (any run of dashes/equals/underscores).
final RegExp _heSeparatorLinePattern = RegExp(r'^[-=_]{3,}$');

// Matches <tool_calls>…</tool_calls> XML blocks that some models embed
// alongside native tool_calls.  Stripped to avoid raw XML in the UI.
final RegExp _heInlineToolCallsXmlPattern = RegExp(
  r'<tool_calls>\s*[\s\S]*?</tool_calls>',
  multiLine: true,
);

// Matches the setext-style == / ^^ underline that the md parser turns into
// an H1/H2.  Both styles are escaped so they render as plain text.
final RegExp _heSetextEscapePattern = RegExp(r'(^|\n)(\s*)(=+|\^+)(?=\n|$)');

/// Pre-processes raw log lines into content ready for Markdown rendering.
/// Returns a `(command, body)` record:
///   • command — the first `> …` shell command (with prefix stripped)
///   • body    — sanitised Markdown string for the rest of the content
({String? command, String body}) _heSplitLogForMarkdown(List<String> lines) {
  String? command;
  final out = <String>[];
  String? prev; // last non-empty output line

  for (final raw in lines) {
    final trimmed = raw.trim();

    // ── Strip our own status decoration lines ──────────────────────────────
    // ▶  ✓  ✗  ⚠  at the start of a line AND followed by a space = UI chrome
    if (trimmed.isNotEmpty &&
        (trimmed.startsWith('▶ ') ||
            trimmed.startsWith('✓ ') ||
            trimmed.startsWith('✗ ') ||
            trimmed.startsWith('⚠ '))) {
      continue;
    }

    // ── Extract command line (first `> …`) ─────────────────────────────────
    if (command == null && raw.startsWith('> ')) {
      command = raw.substring(2);
      continue;
    }

    // ── Convert terminal separator lines ───────────────────────────────────
    // `--------` immediately after a non-blank line would become a setext H2.
    // Insert a blank line before it, then output it as a proper Markdown HR.
    if (_heSeparatorLinePattern.hasMatch(trimmed)) {
      if (prev != null && out.isNotEmpty && out.last.isNotEmpty) out.add('');
      out.add('---');
      out.add('');
      prev = null;
      continue;
    }

    // ── Role markers emitted by CLI tools ──────────────────────────────────
    // Single-word protocol tokens like `user`, `codex`, `exec`, `assistant`
    // act as conversation-turn dividers in the terminal.  Replace them with
    // a styled horizontal rule so sections are visually separated.
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

  // Escape setext == / ^^ sequences that would create phantom headings.
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

String _heDescribeAiModelConfig(
  List<AiModelConfig> settingsModels,
  String? configId, {
  required bool isZh,
  String? urlModeModelId,
}) {
  final trimmedConfigId = configId?.trim() ?? '';
  if (trimmedConfigId.isEmpty) {
    return isZh ? '未配置' : 'Not configured';
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

  return isZh
      ? '已删除配置 · $trimmedConfigId'
      : 'Deleted config · $trimmedConfigId';
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

// =============================================================================
// Sub-conversation segment model & parser
//
// Splits raw CLI output lines into typed segments so each segment can be
// rendered as an independent mini-card within the phase card, providing a
// structured sub-conversation experience.
// =============================================================================

/// The kind of content a segment represents.
enum _HeSegmentKind {
  /// The CLI command that was executed.
  command,

  /// AI assistant response / main output.
  assistant,

  /// AI reasoning / thinking content.
  thinking,

  /// Tool invocation (exec, function call).
  toolCall,

  /// Tool/function result content.
  toolResult,

  /// General output that doesn't match any role marker.
  output,

  /// User-authored manual input (metaCollection / planning / reviewing).
  userInput,

  /// Handoff document generation / context relay activity.
  handoff,
}

/// A parsed segment of CLI output, tagged with its kind.
class _HeOutputSegment {
  _HeOutputSegment({required this.kind, this.roleLabel, List<String>? lines})
    : lines = lines ?? [];

  final _HeSegmentKind kind;
  final String? roleLabel;
  final List<String> lines;

  /// Returns the trimmed, non-empty content lines joined for Markdown rendering.
  String get markdownBody {
    final out = <String>[];
    String? prev;
    for (final raw in lines) {
      final trimmed = raw.trim();
      // Convert separator lines to proper Markdown HR.
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

/// Role markers emitted by various CLI tools that signal a new conversation turn.
const Set<String> _heRoleMarkers = {
  'user',
  'codex',
  'thinking',
  'assistant',
  'exec',
  'function',
  'tool',
};

/// Maps role marker strings to segment kinds.
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

/// Parses CLI output lines into a list of typed segments.
/// Each role marker (assistant, codex, exec, tool, etc.) starts a new segment.
/// The first `> …` line is extracted as a [_HeSegmentKind.command] segment.
List<_HeOutputSegment> _heParseOutputSegments(List<String> rawLines) {
  final segments = <_HeOutputSegment>[];
  _HeOutputSegment? current;
  String? commandLine;

  /// Pattern matching manual-input headers like 【用户人工验收结果】.
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

    // Strip UI decoration lines (but NOT ⚙ which marks tool calls).
    if (trimmed.isNotEmpty &&
        (trimmed.startsWith('▶ ') ||
            trimmed.startsWith('✓ ') ||
            trimmed.startsWith('✗ ') ||
            trimmed.startsWith('⚠ '))) {
      continue;
    }

    // 2026-04-13: Detect tool call markers: ⚙ 工具调用：{ToolName}
    // These are emitted by HardnessApiPhaseRunner.
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

    // Detect manual-input header — start a userInput segment.
    if (manualInputHeaderPattern.hasMatch(trimmed)) {
      flushCurrent();
      // The header itself (e.g. 【用户人工验收结果】) becomes the roleLabel.
      current = _HeOutputSegment(
        kind: _HeSegmentKind.userInput,
        roleLabel: trimmed.substring(1, trimmed.length - 1),
      );
      inUserInputSection = true;
      continue;
    }

    // End of user input section: ℹ acknowledgment line.
    if (inUserInputSection && trimmed.startsWith('ℹ ')) {
      flushCurrent();
      inUserInputSection = false;
      continue;
    }

    // Extract the CLI command (first `> …` line).
    if (commandLine == null && raw.startsWith('> ')) {
      commandLine = raw.substring(2);
      // A command line also ends the user-input section.
      if (inUserInputSection) {
        flushCurrent();
        inUserInputSection = false;
      }
      continue;
    }

    // Detect handoff markers (📋) — group consecutive handoff lines into a
    // single handoff segment for structured UI treatment.
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
    // If we were in a handoff segment and hit a non-handoff, non-empty line,
    // close the handoff segment.
    if (current?.kind == _HeSegmentKind.handoff &&
        trimmed.isNotEmpty &&
        !trimmed.startsWith('📋 ')) {
      flushCurrent();
    }

    // Detect role markers — start a new segment.
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

    // If no current segment exists, create a generic output segment.
    current ??= _HeOutputSegment(kind: _HeSegmentKind.output);
    current!.lines.add(raw);
  }

  flushCurrent();

  // Prepend the command segment if present.
  if (commandLine != null) {
    segments.insert(
      0,
      _HeOutputSegment(kind: _HeSegmentKind.command, lines: [commandLine]),
    );
  }

  // Post-processing: detect thinking patterns in output/assistant segments.
  // Claude Code prefixes thinking with <thinking>...</thinking> or uses
  // extended thinking markers.
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

  // Post-processing: strip <tool_calls>…</tool_calls> XML that some models
  // embed in the text reply alongside native tool_calls.  These are
  // duplicate representations and would otherwise render as raw XML.
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    if (seg.kind == _HeSegmentKind.output ||
        seg.kind == _HeSegmentKind.assistant ||
        seg.kind == _HeSegmentKind.thinking) {
      final joined = seg.lines.join('\n');
      if (joined.contains('<tool_calls>')) {
        final stripped = joined
            .replaceAll(_heInlineToolCallsXmlPattern, '')
            .replaceAll(RegExp(r'\n{3,}'), '\n\n')
            .trim();
        if (stripped.isEmpty) {
          // The entire segment was just XML tool calls — remove it.
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

  // Post-processing: promote lone "output" segments with substantial content
  // to "assistant" for better visual treatment (AI response card styling).
  // Exclude command and userInput segments from the count so a phase with
  // one AI output + one user input still promotes the AI output correctly.
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

/// Builds a `MarkdownStyleSheet` tuned for the HE log-section surface
/// (nearly-white or nearly-black depending on brightness).
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
      fontFamily: 'monospace',
      fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * 0.93,
      color: accent,
      backgroundColor: Colors.transparent,
    ),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: codeBlockBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    blockquoteDecoration: BoxDecoration(
      color: quoteBg,
      borderRadius: _br16,
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

// Shared border-radius constants matching the home-page conversation UI.
const _br26 = BorderRadius.all(Radius.circular(26));
const _br18 = BorderRadius.all(Radius.circular(18));
const _br16 = BorderRadius.all(Radius.circular(16));
const _br12 = BorderRadius.all(Radius.circular(12));
const _br999 = BorderRadius.all(Radius.circular(999));

/// Builds a markdown stylesheet whose colours are derived from the actual
/// [cardBg] colour rather than from the app theme.  This is critical for
/// always-dark cards (e.g. reasoning/thinking) that sit inside a light-theme
/// app — without it, code blocks, inline code, links, blockquotes, etc. use
/// light-mode colours on a dark background and become unreadable.
///
/// The logic mirrors [_MessageMarkdownThemeData.fromMessageBubble] used by the
/// default thread template.
MarkdownStyleSheet _heBuildDarkAwareMarkdownStyleSheet(
  ThemeData theme,
  ColorScheme colorScheme,
  Color cardBg,
  Color? explicitTextColor,
) {
  final bubbleIsDark =
      ThemeData.estimateBrightnessForColor(cardBg) == Brightness.dark;
  final overlayBase = bubbleIsDark ? Colors.white : Colors.black;
  final textColor =
      explicitTextColor ??
      (bubbleIsDark ? Colors.white : colorScheme.onSurface);
  final subtleSurface = Color.alphaBlend(
    overlayBase.withValues(alpha: bubbleIsDark ? 0.06 : 0.035),
    cardBg,
  );
  final elevatedSurface = Color.alphaBlend(
    overlayBase.withValues(alpha: bubbleIsDark ? 0.11 : 0.06),
    cardBg,
  );
  final accentColor = bubbleIsDark
      ? Color.lerp(colorScheme.primaryContainer, Colors.white, 0.08) ??
            colorScheme.primaryContainer
      : colorScheme.primary;
  final linkColor = bubbleIsDark
      ? Color.lerp(accentColor, Colors.white, 0.08) ?? accentColor
      : accentColor;
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
      fontFamily: 'monospace',
      fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * 0.93,
      color: textColor,
      backgroundColor: Colors.transparent,
    ),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: bubbleIsDark
          ? Colors.white.withValues(alpha: 0.08)
          : subtleSurface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    blockquoteDecoration: BoxDecoration(
      color: quoteSurface,
      borderRadius: _br16,
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

const Color _hePendingTone = Color(0xFF818A98);
const Color _heRunningTone = Color(0xFF2D63B8);
const Color _heCompletedTone = Color(0xFF5F7C53);
const Color _hePausedTone = Color(0xFFD97A33);
const Color _heFailedTone = Color(0xFFC84B4B);

({Color tone, Color background, Color border, Color text}) _hePhasePalette(
  ThemeData theme,
  ColorScheme colorScheme,
  HardnessPhaseStatus status, {
  bool reviewVerdictFail = false,
}) {
  final tone = switch (status) {
    HardnessPhaseStatus.pending ||
    HardnessPhaseStatus.skipped => _hePendingTone,
    HardnessPhaseStatus.paused ||
    HardnessPhaseStatus.cancelled => _hePausedTone,
    HardnessPhaseStatus.running => _heRunningTone,
    HardnessPhaseStatus.completed =>
      reviewVerdictFail ? _heFailedTone : _heCompletedTone,
    HardnessPhaseStatus.failed => _heFailedTone,
  };
  final backgroundAlpha = switch (status) {
    HardnessPhaseStatus.pending || HardnessPhaseStatus.skipped =>
      theme.brightness == Brightness.dark ? 0.18 : 0.08,
    HardnessPhaseStatus.paused || HardnessPhaseStatus.cancelled =>
      theme.brightness == Brightness.dark ? 0.26 : 0.13,
    HardnessPhaseStatus.running =>
      theme.brightness == Brightness.dark ? 0.28 : 0.14,
    HardnessPhaseStatus.completed =>
      theme.brightness == Brightness.dark ? 0.30 : 0.15,
    HardnessPhaseStatus.failed =>
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

// =============================================================================
// HardnessSessionPane — public entry-point (API surface unchanged)
//
// Adopts the same visual language as an AI thread session:
//   • _SessionToolbar-style header with scrollable info pills
//   • scrollable card feed where every HE phase renders as a tool-call card
//     (secondaryContainer bg when running, status-tinted for other states)
// =============================================================================

class HardnessSessionPaneController {
  _HardnessSessionPaneState? _state;

  void _attach(_HardnessSessionPaneState state) {
    _state = state;
  }

  void _detach(_HardnessSessionPaneState state) {
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

class HardnessSessionPane extends StatefulWidget {
  const HardnessSessionPane({
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
    this.controller,
    this.filePathRoots = const [],
    this.replayPendingDeadlineListenable,
    this.onCancelPendingReplay,
  });

  final HardnessSessionConfig config;
  final HardnessOrchestrator orchestrator;
  final bool isZh;

  /// AI-generated or task-derived title shown in the session header.
  final String? sessionTitle;

  /// Pre-formatted updated time used in the toolbar, matching other threads.
  final String? updatedAtLabel;

  /// Unique session identifier for the metadata dialog.
  final String? sessionId;

  /// Pre-formatted creation time for the metadata dialog.
  final String? createdAtLabel;

  /// Called when the user restarts a failed / cancelled / idle session.
  final VoidCallback onRestart;

  /// Whether full-access (auto-advance) is enabled.
  final bool fullAccessPermission;

  /// Toggles full-access permission on/off.
  final ValueChanged<bool> onToggleFullAccessPermission;

  /// Called when user changes CLI/model config for a pending phase.
  final ValueChanged<HardnessSessionConfig> onConfigChanged;

  final HardnessSessionPaneController? controller;

  /// Root directories for file path resolution in message content.
  final List<String> filePathRoots;

  /// 可选的 ToolSearch 重放反悔窗口 deadline。传入后，会在会话
  /// header 右侧出现一个「撤销 Ns」倒计时 chip。顶层从
  /// `ToolSearchReplayDispatcher.pendingDeadlineListenable` 取。
  final ValueListenable<DateTime?>? replayPendingDeadlineListenable;

  /// 点击「撤销 Ns」chip 时回调，通常接到
  /// [ToolSearchReplayDispatcher.cancel] 立即取消重放。
  final VoidCallback? onCancelPendingReplay;

  @override
  State<HardnessSessionPane> createState() => _HardnessSessionPaneState();
}

class _HardnessSessionPaneState extends State<HardnessSessionPane> {
  final ScrollController _feedController = ScrollController();
  final TextEditingController _manualPhaseController = TextEditingController();
  final FocusNode _manualPhaseFocusNode = FocusNode();

  /// Per-phase expansion override: `null` = auto, non-null = user preference.
  final Map<HardnessPhaseLog, bool> _expandedOverrides = {};
  bool _composerCollapsed = false;
  bool _autoFollowEnabled = true;
  bool _shouldAutoFollowFeed = true;
  bool _manualPhaseSubmitting = false;
  bool _lastAwaitingManualPhaseInput = false;

  /// The phase log currently selected (for showing action buttons below card).
  HardnessPhaseLog? _selectedPhaseLog;

  // ── Auto-scroll state ───────────────────────────────────────────────────
  /// Guards against multiple addPostFrameCallback registrations per frame.
  bool _scrollCallbackQueued = false;

  bool _queuedForcedFeedScrollToBottom = false;
  bool _pendingAnimatedFeedScrollToBottom = false;
  bool _programmaticFeedScrollInProgress = false;
  bool _userFeedScrollInProgress = false;

  /// Number of extra settle passes to run after the current scroll.
  /// Settle passes re-invoke the scroll logic every frame until content
  /// stabilises (important when AnimatedSize is transitioning height).
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
  void didUpdateWidget(HardnessSessionPane oldWidget) {
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
      widget.orchestrator.status == HardnessOrchestratorStatus.running;

  bool get _isDone =>
      widget.orchestrator.status != HardnessOrchestratorStatus.idle &&
      widget.orchestrator.status != HardnessOrchestratorStatus.running;

  bool get _canRetryFailedRun =>
      widget.orchestrator.status == HardnessOrchestratorStatus.failed;

  bool _isPhaseConfigEditable(HardnessPhaseLog log) {
    return switch (log.status) {
      HardnessPhaseStatus.pending ||
      HardnessPhaseStatus.paused ||
      HardnessPhaseStatus.failed ||
      HardnessPhaseStatus.skipped => true,
      HardnessPhaseStatus.running ||
      HardnessPhaseStatus.completed ||
      HardnessPhaseStatus.cancelled => false,
    };
  }

  HardnessPhase? get _awaitingManualPhase =>
      widget.orchestrator.awaitingManualPhaseInputPhase;

  bool get _isAwaitingManualPhaseInput => _awaitingManualPhase != null;

  bool get _canSubmitManualPhase =>
      !_manualPhaseSubmitting && _manualPhaseController.text.trim().isNotEmpty;

  HardnessPhase get _effectiveManualPhase =>
      _awaitingManualPhase ?? HardnessPhase.reviewing;

  _HeManualPhaseCopy _manualPhaseCopy(HardnessPhase phase) {
    final isZh = widget.isZh;
    return switch (phase) {
      HardnessPhase.metaCollection => _HeManualPhaseCopy(
        actionLabel: isZh ? '我来研究' : 'I Will Research',
        switchBackLabel: isZh ? '改用 AI 研究' : 'Use AI Research',
        title: isZh ? '人工研究结果' : 'Manual Research Notes',
        helperText: isZh
            ? '请填写你亲自研究得到的项目结构、模块职责、依赖、约定或其他关键观察。发送后，AI 会把这些内容整理为符合 architecture.md 与 conventions.md 规范的文档。'
            : 'Enter the project structure, module responsibilities, dependencies, conventions, or other observations you researched yourself. AI will refine them into architecture.md and conventions.md.',
        hintText: isZh
            ? '例如：核心入口在 lib/main.dart；状态管理集中在 app/state；构建依赖 Flutter + Provider；README 缺少测试命令说明。'
            : 'Example: the main entry is lib/main.dart; state lives under app/state; the project uses Flutter + Provider; README is missing test command details.',
        emptyMessage: isZh
            ? '请先填写研究结果，再发送给 AI 整理。'
            : 'Enter your research notes before sending them for AI refinement.',
        activeBannerText: isZh
            ? '已切换为人工研究。下方输入框已解禁，请填写研究资料后点击发送，AI 会把它整理为符合规范的 architecture / conventions 文档。'
            : 'Manual research is active. The composer below is unlocked. Send your research notes and AI will refine them into the required architecture / conventions documents.',
        queuedBannerText: isZh
            ? '已保留上一份人工研究结果。点击“继续”会直接用它进入 AI 研究；如果想修改，请再次点击“我来研究”。'
            : 'The previous manual research notes are still queued. Continuing will reuse them for AI research; click “I Will Research” again to revise them.',
        icon: Icons.search_rounded,
      ),
      HardnessPhase.planning => _HeManualPhaseCopy(
        actionLabel: isZh ? '我来制定计划' : 'I Will Plan',
        switchBackLabel: isZh ? '改用 AI 规划' : 'Use AI Planning',
        title: isZh ? '人工计划草案' : 'Manual Plan Draft',
        helperText: isZh
            ? '请填写你亲自制定的执行计划草案。发送后，AI 会在此基础上补足步骤粒度、文件指向、验收标准和复杂度标签，并输出规范的 plan 文档。'
            : 'Enter the execution plan draft you created. AI will refine it into the structured plan document with file targets, acceptance criteria, and complexity labels.',
        hintText: isZh
            ? '例如：1. 修改 lib/foo.dart 修复状态同步 [medium]；验收：切换页面后数据一致。'
            : 'Example: 1. Update lib/foo.dart to fix state sync [medium]; acceptance: data stays consistent after navigation.',
        emptyMessage: isZh
            ? '请先填写计划草案，再发送给 AI 润色。'
            : 'Enter your plan draft before sending it for AI refinement.',
        activeBannerText: isZh
            ? '已切换为人工规划。下方输入框已解禁，请填写计划草案后点击发送，AI 会补全并整理为规范的计划文档。'
            : 'Manual planning is active. The composer below is unlocked. Send your draft and AI will refine it into the required plan document.',
        queuedBannerText: isZh
            ? '已保留上一份人工计划草案。点击“继续”会直接用它进入 AI 规划；如果想修改，请再次点击“我来制定计划”。'
            : 'The previous manual plan draft is still queued. Continuing will reuse it for AI planning; click “I Will Plan” again to revise it.',
        icon: Icons.route_rounded,
      ),
      HardnessPhase.reviewing => _HeManualPhaseCopy(
        actionLabel: isZh ? '我来验收' : 'I Will Review',
        switchBackLabel: isZh ? '改用 AI 验收' : 'Use AI Review',
        title: isZh ? '人工验收结果' : 'Manual Acceptance Result',
        helperText: isZh
            ? '请填写你基于资产、页面、交互或其他真实结果完成的人工验收结论。填写后，点击下方的「验收通过」或「验收不通过」按钮提交判定。'
            : 'Enter the acceptance result you derived from real assets, UI, behavior, or other observed outcomes. Then click "Pass" or "Fail" below to submit your verdict.',
        hintText: isZh
            ? '例如：桌面端布局符合预期，但导出图片边缘仍有白边；移动端卡片间距偏大。'
            : 'Example: the desktop layout looks correct, but exported images still show white edges and mobile card spacing is too large.',
        emptyMessage: isZh
            ? '请先填写验收结果，再发送给 AI 分析。'
            : 'Enter your acceptance result before sending it for AI review.',
        activeBannerText: isZh
            ? '已切换为人工验收。下方输入框已解禁，请填写验收结果后点击「验收通过」或「验收不通过」按钮，AI 会据此生成 feedback 并决定后续流程。'
            : 'Manual review is active. The composer below is unlocked. Enter your review result, then click "Pass" or "Fail". AI will generate feedback accordingly.',
        queuedBannerText: isZh
            ? '已保留上一份人工验收结果。点击“继续”会直接用它进入 AI 验收；如果想修改，请再次点击“我来验收”。'
            : 'The previous manual acceptance result is still queued. Continuing will reuse it for AI review; click “I Will Review” again to revise it.',
        icon: Icons.fact_check_outlined,
      ),
      HardnessPhase.reading || HardnessPhase.implementing => _HeManualPhaseCopy(
        actionLabel: isZh ? '我来处理' : 'I Will Handle It',
        switchBackLabel: isZh ? '改用 AI 处理' : 'Use AI',
        title: isZh ? '人工输入' : 'Manual Input',
        helperText: isZh ? '请填写人工输入。' : 'Enter manual input.',
        hintText: isZh ? '输入人工内容…' : 'Enter manual input…',
        emptyMessage: isZh ? '请先填写内容。' : 'Enter the content first.',
        activeBannerText: isZh ? '已切换为人工输入。' : 'Manual input is active.',
        queuedBannerText: isZh
            ? '已保留上一份人工输入。'
            : 'The previous manual input is still queued.',
        icon: Icons.edit_note_rounded,
      ),
    };
  }

  bool _isPhaseExpanded(HardnessPhaseLog log) {
    final override = _expandedOverrides[log];
    if (override != null) return override;
    return log.status == HardnessPhaseStatus.running ||
        log.status == HardnessPhaseStatus.paused ||
        log.status == HardnessPhaseStatus.failed;
  }

  void _setPhaseExpanded(HardnessPhaseLog log, bool expanded) {
    setState(() => _expandedOverrides[log] = expanded);
  }

  String? _phaseApprovalIssue(HardnessPhase phase) {
    final blocker = widget.orchestrator.phaseExecutionBlocker(phase);
    return switch (blocker) {
      HardnessPhaseExecutionBlocker.missingConfig =>
        widget.isZh
            ? '请先为该阶段配置 CLI/模型 或 API 模型，然后再继续执行。'
            : 'Configure the CLI/model or API model for this phase before continuing.',
      HardnessPhaseExecutionBlocker.unsupportedCli =>
        widget.isZh
            ? '当前 CLI 不支持无交互执行，请改为支持 headless 的 CLI。'
            : 'The selected CLI does not support headless execution. Choose a supported CLI.',
      HardnessPhaseExecutionBlocker.missingApiModel =>
        widget.isZh
            ? '所选 API 模型配置无效或已被删除，请在设置中检查。'
            : 'The selected API model configuration is invalid or deleted. Check settings.',
      HardnessPhaseExecutionBlocker.missingApiRunner =>
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
      WidgetsBinding.instance.endOfFrame.then((_) {
        if (!mounted || !_feedController.hasClients) return;
        // 如果用户在底部（auto-follow），确保仍然贴底
        if (_autoFollowEnabled && _shouldAutoFollowFeed) {
          final pos = _feedController.position;
          if (pos.pixels < pos.maxScrollExtent - 1.0) {
            _feedController.jumpTo(pos.maxScrollExtent);
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
    // 2026-04-28: Composer shortcut consumption (no action).
    //
    // _handleGlobalShortcutKeyEvent (HardwareKeyboard) in the home page
    // is the sole executor of send-message / toggle-composer.  Previously
    // this FocusNode handler ALSO performed the action, so the composer
    // toggle ran twice and visually cancelled out (the recurring
    // "Ctrl+P border flash, nothing happens" bug also manifested here).
    // We now only consume the matching keystroke in the focus tree so
    // that DefaultTextEditingShortcuts cannot fire, without invoking the
    // action a second time.
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
        widget.isZh
            ? '当前没有等待中的人工输入阶段。'
            : 'No manual phase input is currently expected.',
      );
      return;
    }
    final content = _manualPhaseController.text.trim();
    if (content.isEmpty) {
      _showComposerMessage(_manualPhaseCopy(awaitingPhase).emptyMessage);
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
          widget.isZh
              ? '人工输入提交失败，请重试。'
              : 'Failed to submit the manual input. Try again.',
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _manualPhaseSubmitting = false);
      _showComposerMessage(
        widget.isZh
            ? '人工输入提交异常，请重试。'
            : 'The manual input submission failed unexpectedly. Try again.',
      );
    }
  }

  /// Submits manual review input with an explicit PASS or FAIL verdict.
  Future<void> _submitManualReviewVerdict({required bool pass}) async {
    final awaitingPhase = _awaitingManualPhase;
    if (awaitingPhase != HardnessPhase.reviewing) {
      return;
    }
    final content = _manualPhaseController.text.trim();
    if (content.isEmpty) {
      _showComposerMessage(
        widget.isZh
            ? '请先填写验收结果，再提交判定。'
            : 'Enter your review result before submitting a verdict.',
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
          widget.isZh
              ? '验收结果提交失败，请重试。'
              : 'Failed to submit the review verdict. Try again.',
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _manualPhaseSubmitting = false);
      _showComposerMessage(
        widget.isZh
            ? '验收结果提交异常，请重试。'
            : 'The review verdict submission failed unexpectedly. Try again.',
      );
    }
  }

  void _showComposerMessage(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    OpenHandSnackBar.show(context, messenger, SnackBar(content: Text(message)));
  }

  void _clearPendingFeedAutoFollowState() {
    _queuedForcedFeedScrollToBottom = false;
    _pendingAnimatedFeedScrollToBottom = false;
    _programmaticFeedScrollInProgress = false;
    _scrollSettlePasses = 0;
  }

  void _handleFeedScroll() {
    if (!_isNearFeedBottom()) {
      return;
    }
    if (!_autoFollowEnabled) {
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
    final explicitUserScrollStart =
        notification is ScrollStartNotification &&
        notification.dragDetails != null;
    final explicitUserScrollUpdate =
        notification is ScrollUpdateNotification &&
        notification.dragDetails != null;
    final explicitUserOverscroll =
        notification is OverscrollNotification &&
        notification.dragDetails != null;
    final explicitUserDirectionChange =
        notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle;
    final explicitUserScroll =
        explicitUserScrollStart ||
        explicitUserScrollUpdate ||
        explicitUserOverscroll ||
        explicitUserDirectionChange;
    final userScrollEnded =
        notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle);

    if (explicitUserScroll) {
      _userFeedScrollInProgress = true;
    } else if (userScrollEnded) {
      _userFeedScrollInProgress = false;
    }

    if (_programmaticFeedScrollInProgress) {
      if (!explicitUserScroll) {
        return false;
      }
      _programmaticFeedScrollInProgress = false;
    }

    final distanceToBottom =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    final isNearBottom = distanceToBottom <= _feedAutoFollowDistanceThreshold;

    if (!_autoFollowEnabled && explicitUserScroll) {
      _shouldAutoFollowFeed = false;
      _clearPendingFeedAutoFollowState();
      return false;
    }

    if (!isNearBottom && explicitUserScroll) {
      _shouldAutoFollowFeed = false;
      _clearPendingFeedAutoFollowState();
      return false;
    }

    if (userScrollEnded &&
        _autoFollowEnabled &&
        _queuedForcedFeedScrollToBottom) {
      _scheduleFeedAutoScroll(force: true);
    }

    if (isNearBottom && _autoFollowEnabled) {
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
    if (_programmaticFeedScrollInProgress || _userFeedScrollInProgress) {
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
        _programmaticFeedScrollInProgress = false;
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
        _programmaticFeedScrollInProgress = true;
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
        _programmaticFeedScrollInProgress = true;
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
    final manualPhaseCopy = _manualPhaseCopy(_effectiveManualPhase);
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
          onCancel: () => _requestCancel(context),
          onRestart: widget.onRestart,
          fullAccessPermission: widget.fullAccessPermission,
          onToggleFullAccess: widget.onToggleFullAccessPermission,
          replayPendingDeadlineListenable:
              widget.replayPendingDeadlineListenable,
          onCancelPendingReplay: widget.onCancelPendingReplay,
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildFeed(context)),
        const SizedBox(height: 16),
        _HeComposer(
          isZh: widget.isZh,
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
          primaryActionLabel: _isAwaitingManualPhaseInput
              ? (widget.isZh
                    ? (_manualPhaseSubmitting ? '发送中' : '发送')
                    : (_manualPhaseSubmitting ? 'Sending' : 'Send'))
              : _isRunning
              ? (widget.isZh ? '中止' : 'Cancel')
              : _canRetryFailedRun
              ? (widget.isZh ? '重试失败阶段' : 'Retry Failed Phase')
              : (_isDone
                    ? (widget.isZh ? '重新执行' : 'Run Again')
                    : (widget.isZh ? '开始执行' : 'Start')),
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
          primaryActionEnabled: _isAwaitingManualPhaseInput
              ? _canSubmitManualPhase
              : true,
          onPrimaryAction: () {
            _handlePrimaryComposerAction();
          },
          isManualReviewPhase:
              _isAwaitingManualPhaseInput &&
              _awaitingManualPhase == HardnessPhase.reviewing,
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

    // No phases yet — differentiate "idle/waiting" from "starting up".
    if (logs.isEmpty) {
      if (orchestrator.status == HardnessOrchestratorStatus.idle) {
        return _HeReadyPlaceholder(
          isZh: widget.isZh,
          onStart: widget.onRestart,
        );
      }
      if (orchestrator.status == HardnessOrchestratorStatus.running) {
        return _InitializingPlaceholder(isZh: widget.isZh);
      }
      return _HeRestoredSessionPlaceholder(
        isZh: widget.isZh,
        status: orchestrator.status,
        onRestart: widget.onRestart,
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleFeedScrollNotification,
      child: Scrollbar(
        controller: _feedController,
        child: ListView.builder(
          controller: _feedController,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
          // Phase cards are tall + carry tool-trace / markdown subtrees.
          // 2026-05-01: lowered 1000 → 400 to stop pre-building two extra
          // off-screen phase cards (each runs synchronous markdown / code
          // highlight passes) when the dashboard first opens; the smaller
          // cache still absorbs short scroll movements without re-layout.
          cacheExtent: 400,
          // +1 if awaiting approval (for the approval banner).
          itemCount:
              logs.length +
              (widget.orchestrator.awaitingApprovalPhase != null ? 1 : 0),
          itemBuilder: (context, index) {
            if (index < logs.length) {
              final log = logs[index];
              final phaseIndex = index;
              final isNotRunning =
                  widget.orchestrator.status !=
                  HardnessOrchestratorStatus.running;
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
                            onToggleExpand: () =>
                                _setPhaseExpanded(log, !_isPhaseExpanded(log)),
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
                                isZh: widget.isZh,
                                onCopyLog: () => _copyLog(context, log),
                                onReExecute: () => _reExecutePhase(phaseIndex),
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
            // Approval banner (last item when awaiting approval).
            if (awaitingApprovalPhase != null) {
              final approvalPhaseCopy = _manualPhaseCopy(awaitingApprovalPhase);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _HePhaseApprovalBanner(
                  isZh: widget.isZh,
                  nextPhase: awaitingApprovalPhase,
                  approvalIssue: approvalIssue,
                  manualPhaseEnabled: widget.orchestrator
                      .isManualPhaseInputActiveFor(awaitingApprovalPhase),
                  hasQueuedManualPhaseInput: widget.orchestrator
                      .hasQueuedManualPhaseInputFor(awaitingApprovalPhase),
                  manualPhaseActionLabel: approvalPhaseCopy.actionLabel,
                  manualPhaseSwitchBackLabel: approvalPhaseCopy.switchBackLabel,
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
                      ? () => widget.orchestrator.setManualPhaseInputRequested(
                          !widget.orchestrator.isManualPhaseInputActiveFor(
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
    );
  }

  void _updatePhaseConfig(
    HardnessPhase phase,
    HardnessRoleConfig newRoleConfig,
  ) {
    final config = widget.config;
    final updated = switch (phase) {
      HardnessPhase.metaCollection => config.copyWith(
        profilerConfig: newRoleConfig,
      ),
      HardnessPhase.reading => config.copyWith(readerConfig: newRoleConfig),
      HardnessPhase.planning => config.copyWith(plannerConfig: newRoleConfig),
      HardnessPhase.implementing => config.copyWith(
        implementerConfig: newRoleConfig,
      ),
      HardnessPhase.reviewing => config.copyWith(reviewerConfig: newRoleConfig),
    };
    widget.onConfigChanged(updated);
  }

  void _copyLog(BuildContext context, HardnessPhaseLog log) {
    Clipboard.setData(ClipboardData(text: log.lines.join('\n')));
    _showHardnessSnackBar(
      context,
      SnackBar(
        content: Text(widget.isZh ? '日志已复制到剪贴板' : 'Log copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _reExecutePhase(int phaseIndex) {
    widget.orchestrator.reExecutePhase(phaseIndex);
  }

  Future<void> _deletePhaseLog(BuildContext context, int phaseIndex) async {
    final isZh = widget.isZh;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isZh ? '删除阶段' : 'Delete Phase'),
        content: Text(
          isZh
              ? '确定删除这个阶段吗？删除后该阶段的执行日志将被移除。'
              : 'Are you sure you want to delete this phase? The execution log will be removed.',
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(ctx).pop(false),
            label: isZh ? '取消' : 'Cancel',
          ),
          OpenHandDialogActionButton.destructive(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: isZh ? '删除' : 'Delete',
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.orchestrator.deletePhaseLog(phaseIndex);
  }

  Future<void> _requestCancel(BuildContext context) async {
    final isZh = widget.isZh;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isZh ? '确认中止' : 'Confirm Cancel'),
        content: Text(
          isZh
              ? '当前会话仍在运行中，确定要中止吗？\nCLI 进程将被终止，已生成的文件会保留。'
              : 'Session is still running. Cancel it?\n'
                    'The active CLI process will be killed. Already-generated files are kept.',
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(ctx).pop(false),
            label: isZh ? '继续运行' : 'Keep Running',
          ),
          OpenHandDialogActionButton.destructive(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: isZh ? '中止' : 'Cancel',
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.orchestrator.cancel();
    }
  }
}

// =============================================================================
// Session header — matches _SessionToolbar visual language exactly:
//   Container(surfaceContainerHigh, br:16, pad h:14 v:6)
//   Row( title + scrollable info pills | token dial )
// =============================================================================
