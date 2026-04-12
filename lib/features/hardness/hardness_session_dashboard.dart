import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app/model/openhand_shortcut.dart';
import '../../app/state/settings_controller.dart';
import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/animated_menu.dart';
import '../../shared/widgets/animated_overlay.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../ai/model/ai_model_config.dart';
import '../home/message_path_linking.dart';
import 'hardness_cli_catalog.dart';
import 'hardness_orchestrator.dart';
import 'model/hardness_phase.dart';
import 'model/hardness_role_config.dart';
import 'model/hardness_session_config.dart';

// Pre-compiled regex for detecting log-level prefixes in output lines.
final RegExp _logLevelPattern = RegExp(
  r'\b(ERROR|ERR|WARN|WARNING|INFO|DEBUG|TRACE)\b',
  caseSensitive: false,
);

// Matches terminal separator lines (any run of dashes/equals/underscores).
final RegExp _heSeparatorLinePattern = RegExp(r'^[-=_]{3,}$');

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

/// Encodes (providerConfigId, modelId) as a compound dropdown key.
String _heEncodeModelKey(String configId, String modelId) =>
    '$configId\t$modelId';

/// Decodes a compound key back to (providerConfigId, modelId).
(String configId, String modelId)? _heDecodeModelKey(String? key) {
  if (key == null) return null;
  final parts = key.split('\t');
  if (parts.length != 2) return null;
  return (parts[0], parts[1]);
}

List<DropdownMenuItem<String>> _heAiModelConfigDropdownItems(
  BuildContext context, {
  required List<AiModelConfig> settingsModels,
  required String? configuredId,
  required String? configuredModelId,
  required bool isZh,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final items = <DropdownMenuItem<String>>[];
  final trimmedConfiguredId = configuredId?.trim();
  final hasConfiguredId =
      trimmedConfiguredId != null && trimmedConfiguredId.isNotEmpty;
  final hasMatchingConfig =
      hasConfiguredId &&
      settingsModels.any((item) => item.id == trimmedConfiguredId);

  if (hasConfiguredId && !hasMatchingConfig) {
    final deletedModelId = configuredModelId?.trim() ?? '';
    items.add(
      DropdownMenuItem<String>(
        value: _heEncodeModelKey(trimmedConfiguredId, deletedModelId),
        child: Text(
          isZh
              ? '已删除配置 · $trimmedConfiguredId'
              : 'Deleted config · $trimmedConfiguredId',
          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  for (final config in settingsModels) {
    final allIds = config.allModelIds;
    if (allIds.isEmpty) {
      items.add(
        DropdownMenuItem<String>(
          value: _heEncodeModelKey(config.id, config.modelId),
          child: Text(
            _heAiModelConfigLabel(config),
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } else {
      for (final modelId in allIds) {
        items.add(
          DropdownMenuItem<String>(
            value: _heEncodeModelKey(config.id, modelId),
            child: Text(
              '$modelId  (${config.providerLabel})',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }
  }

  return items;
}

String? _heResolvedAiModelConfigDropdownValue(
  List<DropdownMenuItem<String>> items,
  String? configuredId,
  String? configuredModelId,
) {
  final trimmedConfiguredId = configuredId?.trim();
  if (trimmedConfiguredId == null || trimmedConfiguredId.isEmpty) {
    return null;
  }
  final trimmedModelId = configuredModelId?.trim() ?? '';
  final key = _heEncodeModelKey(trimmedConfiguredId, trimmedModelId);
  if (items.any((item) => item.value == key)) return key;
  // Try matching just by config ID (any model within).
  return items
      .where((item) {
        final decoded = _heDecodeModelKey(item.value);
        return decoded != null && decoded.$1 == trimmedConfiguredId;
      })
      .firstOrNull
      ?.value;
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

/// Role markers emitted by various CLI tools that signal a new conversation turn.
const Set<String> _heRoleMarkers = {
  'user',
  'codex',
  'assistant',
  'exec',
  'function',
  'tool',
};

/// Maps role marker strings to segment kinds.
_HeSegmentKind _kindFromRoleMarker(String marker) => switch (marker) {
  'assistant' => _HeSegmentKind.assistant,
  'codex' => _HeSegmentKind.thinking,
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

    // Strip UI decoration lines.
    if (trimmed.isNotEmpty &&
        (trimmed.startsWith('▶ ') ||
            trimmed.startsWith('✓ ') ||
            trimmed.startsWith('✗ ') ||
            trimmed.startsWith('⚠ '))) {
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
    if (current?.kind == _HeSegmentKind.handoff && trimmed.isNotEmpty &&
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
      backgroundColor: codeBlockBg,
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
    if (!mounted ||
        !_isAwaitingManualPhaseInput ||
        _composerCollapsed ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final bindings = context.read<SettingsController>().shortcutBindings;
    final pressedKeyIds = normalizedPressedShortcutKeyIds(<LogicalKeyboardKey>{
      ...HardwareKeyboard.instance.logicalKeysPressed,
      event.logicalKey,
    });
    for (final action in const <OpenHandShortcutAction>[
      OpenHandShortcutAction.sendMessage,
      OpenHandShortcutAction.toggleComposer,
    ]) {
      final shortcutKeyIds = normalizeShortcutKeyIds(
        bindings[action] ?? const <int>[],
      );
      if (shortcutKeyIds.isEmpty) {
        continue;
      }
      if (shortcutKeyIds.length != pressedKeyIds.length ||
          !pressedKeyIds.containsAll(shortcutKeyIds)) {
        continue;
      }
      unawaited(_handleShortcutAction(action));
      return KeyEventResult.handled;
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
    } catch (error, stackTrace) {
      debugPrint('Manual phase input submission failed: $error\n$stackTrace');
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
    } catch (error, stackTrace) {
      debugPrint(
        'Manual review verdict submission failed: $error\n$stackTrace',
      );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    ScaffoldMessenger.of(context).showSnackBar(
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isZh ? '取消' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              isZh ? '删除' : 'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isZh ? '继续运行' : 'Keep Running'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(isZh ? '中止' : 'Cancel'),
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

class _HePaneHeader extends StatelessWidget {
  const _HePaneHeader({
    required this.config,
    required this.orchestrator,
    required this.isZh,
    required this.isRunning,
    required this.isDone,
    required this.sessionTitle,
    required this.updatedAtLabel,
    required this.sessionId,
    required this.createdAtLabel,
    required this.onCancel,
    required this.onRestart,
    required this.fullAccessPermission,
    required this.onToggleFullAccess,
  });

  final HardnessSessionConfig config;
  final HardnessOrchestrator orchestrator;
  final bool isZh;
  final bool isRunning;
  final bool isDone;
  final String? sessionTitle;
  final String? updatedAtLabel;
  final String? sessionId;
  final String? createdAtLabel;
  final VoidCallback onCancel;
  final VoidCallback onRestart;
  final bool fullAccessPermission;
  final ValueChanged<bool> onToggleFullAccess;

  String get _effectiveTitle => (sessionTitle?.trim().isNotEmpty == true)
      ? sessionTitle!
      : (isZh ? 'Hardness Engineering 会话' : 'Hardness Engineering Session');

  /// Returns a label like "元数据采集 1/3" describing current execution position.
  String _phaseProgressLabel() {
    final logs = orchestrator.phaseLogs;
    final total = logs.length;
    final awaitingApproval = orchestrator.awaitingApprovalPhase;
    if (awaitingApproval != null) {
      final idx = logs.indexWhere((l) => l.phase == awaitingApproval);
      final pos = idx >= 0 ? idx + 1 : total;
      final name = isZh
          ? awaitingApproval.displayNameZh
          : awaitingApproval.displayNameEn;
      return isZh
          ? '$name $pos/$total · 待批准'
          : '$name $pos/$total · Awaiting Approval';
    }
    final current = orchestrator.currentPhase;
    if (isRunning && current != null) {
      final idx = logs.indexWhere((l) => l.phase == current);
      final pos = idx >= 0 ? idx + 1 : total;
      final name = isZh ? current.displayNameZh : current.displayNameEn;
      return '$name $pos/$total';
    }
    final completed = logs
        .where((l) => l.status == HardnessPhaseStatus.completed)
        .length;
    final failed = logs
        .where((l) => l.status == HardnessPhaseStatus.failed)
        .length;
    if (total == 0) return isZh ? '待开始' : 'Not started';
    if (failed > 0) {
      return isZh ? '阶段失败 $failed/$total' : '$failed/$total failed';
    }
    if (completed == total) return isZh ? '全部完成 $total' : '$total done';
    return isZh ? '完成 $completed/$total' : '$completed/$total done';
  }

  IconData _phaseProgressIcon() {
    if (orchestrator.awaitingApprovalPhase != null) {
      return Icons.pause_circle_filled_rounded;
    }
    if (isRunning) return Icons.sync_rounded;
    final logs = orchestrator.phaseLogs;
    if (logs.any((l) => l.status == HardnessPhaseStatus.failed)) {
      return Icons.error_outline_rounded;
    }
    if (orchestrator.status == HardnessOrchestratorStatus.completed) {
      return Icons.check_circle_outline_rounded;
    }
    if (orchestrator.status == HardnessOrchestratorStatus.cancelled) {
      return Icons.cancel_outlined;
    }
    return Icons.pending_outlined;
  }

  Color _phaseProgressColor(ColorScheme cs) {
    if (orchestrator.awaitingApprovalPhase != null) {
      return _hePausedTone;
    }
    if (isRunning) return _heRunningTone;
    final logs = orchestrator.phaseLogs;
    if (logs.any((l) => l.status == HardnessPhaseStatus.failed)) {
      return _heFailedTone;
    }
    if (orchestrator.status == HardnessOrchestratorStatus.completed) {
      return _heCompletedTone;
    }
    if (orchestrator.status == HardnessOrchestratorStatus.cancelled) {
      return _hePausedTone;
    }
    return _hePendingTone;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final logs = orchestrator.phaseLogs;
    final reviewRetries = orchestrator.reviewRetryCount;
    final totalLines = logs.fold<int>(0, (sum, l) => sum + l.lines.length);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: <Widget>[
                          ...previousChildren,
                          ...?(currentChild == null
                              ? null
                              : <Widget>[currentChild]),
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      final curved = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                        reverseCurve: Curves.easeInCubic,
                      );
                      final slide = Tween<Offset>(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(curved);
                      final scale = Tween<double>(
                        begin: 0.96,
                        end: 1,
                      ).animate(curved);
                      return ClipRect(
                        child: FadeTransition(
                          opacity: curved,
                          child: SlideTransition(
                            position: slide,
                            child: ScaleTransition(scale: scale, child: child),
                          ),
                        ),
                      );
                    },
                    child: Text(
                      _effectiveTitle,
                      key: ValueKey<String>(_effectiveTitle),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: Row(
                      children: [
                        // ── Phase progress (mirrors runtime mode / template pill) ──
                        _HePill(
                          icon: _phaseProgressIcon(),
                          label: _phaseProgressLabel(),
                          foregroundColor: _phaseProgressColor(colorScheme),
                        ),
                        if (reviewRetries > 0) ...[
                          const SizedBox(width: 8),
                          // ── Review retry counter ──
                          _HePill(
                            icon: Icons.replay_rounded,
                            label: isZh
                                ? '重试 $reviewRetries/3'
                                : 'Retry $reviewRetries/3',
                            foregroundColor: const Color(0xFFF57F17), // amber
                          ),
                        ],
                        const SizedBox(width: 8),
                        const _HePill(
                          icon: Icons.layers_rounded,
                          label:
                              'Hardness Engineering · v$kHardnessOrchestratorDisplayVersion',
                        ),
                        const SizedBox(width: 8),
                        _HePill(
                          icon: Icons.data_object_rounded,
                          label: isZh ? '会话元数据' : 'Session Metadata',
                          onTap: () => _showSessionMetadata(context),
                        ),
                        const SizedBox(width: 8),
                        _HePill(
                          icon: Icons.folder_special_rounded,
                          label: isZh ? '资产文件' : 'Steering Assets',
                          onTap: () => _showSteeringAssets(context),
                        ),
                        if (updatedAtLabel?.isNotEmpty == true) ...[
                          const SizedBox(width: 8),
                          _HePill(
                            icon: Icons.update_rounded,
                            label: updatedAtLabel!,
                          ),
                        ],
                        if (isRunning) ...[
                          const SizedBox(width: 8),
                          _HePill(
                            icon: Icons.stop_circle_outlined,
                            label: isZh ? '中止' : 'Cancel',
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                            onTap: onCancel,
                          ),
                        ],
                        if (isDone &&
                            orchestrator.status !=
                                HardnessOrchestratorStatus.completed) ...[
                          const SizedBox(width: 8),
                          _HePill(
                            icon: Icons.restart_alt_rounded,
                            label:
                                orchestrator.status ==
                                    HardnessOrchestratorStatus.failed
                                ? (isZh ? '重试失败阶段' : 'Retry Failed Phase')
                                : (isZh ? '重新开始' : 'Restart'),
                            onTap: onRestart,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _HeOutputLinesDial(totalLines: totalLines),
        ],
      ),
    );
  }

  void _showSessionMetadata(BuildContext context) {
    showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => _HeSessionMetadataDialog(
        config: config,
        orchestrator: orchestrator,
        isZh: isZh,
        sessionTitle: _effectiveTitle,
        sessionId: sessionId,
        createdAtLabel: createdAtLabel,
        updatedAtLabel: updatedAtLabel,
      ),
    );
  }

  void _showSteeringAssets(BuildContext context) {
    final steeringRoot = p.join(config.persistenceDirectory, 'steering');
    showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _HeSteeringAssetsDialog(steeringRoot: steeringRoot, isZh: isZh),
    );
  }
}

// =============================================================================
// _HeSessionMetadataDialog — full metadata dialog matching _SessionMetadataDialog
// =============================================================================

class _HeSessionMetadataDialog extends StatelessWidget {
  const _HeSessionMetadataDialog({
    required this.config,
    required this.orchestrator,
    required this.isZh,
    required this.sessionTitle,
    this.sessionId,
    this.createdAtLabel,
    this.updatedAtLabel,
  });

  final HardnessSessionConfig config;
  final HardnessOrchestrator orchestrator;
  final bool isZh;
  final String sessionTitle;
  final String? sessionId;
  final String? createdAtLabel;
  final String? updatedAtLabel;

  String _statusLabel(HardnessOrchestratorStatus s) => switch (s) {
    HardnessOrchestratorStatus.idle => isZh ? '准备中' : 'Idle',
    HardnessOrchestratorStatus.running => isZh ? '运行中' : 'Running',
    HardnessOrchestratorStatus.completed => isZh ? '已完成' : 'Completed',
    HardnessOrchestratorStatus.failed => isZh ? '失败' : 'Failed',
    HardnessOrchestratorStatus.cancelled => isZh ? '已中止' : 'Cancelled',
  };

  String _phaseStatusLabel(HardnessPhaseStatus s) => switch (s) {
    HardnessPhaseStatus.pending => isZh ? '等待中' : 'Pending',
    HardnessPhaseStatus.paused => isZh ? '暂停中' : 'Paused',
    HardnessPhaseStatus.running => isZh ? '运行中' : 'Running',
    HardnessPhaseStatus.completed => isZh ? '已完成' : 'Completed',
    HardnessPhaseStatus.failed => isZh ? '失败' : 'Failed',
    HardnessPhaseStatus.cancelled => isZh ? '已中止' : 'Cancelled',
    HardnessPhaseStatus.skipped => isZh ? '已跳过' : 'Skipped',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final logs = orchestrator.phaseLogs;
    final settingsController = Provider.of<SettingsController?>(context);
    final aiModels = settingsController?.aiModels ?? const <AiModelConfig>[];

    final totalPhases = HardnessPhase.values.length;
    final completedPhases = logs
        .where((l) => l.status == HardnessPhaseStatus.completed)
        .length;
    final failedPhases = logs
        .where((l) => l.status == HardnessPhaseStatus.failed)
        .length;
    final totalLogLines = logs.fold<int>(0, (sum, l) => sum + l.lines.length);

    final summaryBlocks = <Widget>[
      _HeSummaryTile(
        label: isZh ? '阶段总数' : 'Total Phases',
        value: '$totalPhases',
      ),
      _HeSummaryTile(
        label: isZh ? '已完成阶段' : 'Completed',
        value: '$completedPhases',
      ),
      _HeSummaryTile(label: isZh ? '失败阶段' : 'Failed', value: '$failedPhases'),
      _HeSummaryTile(
        label: isZh ? '日志总行数' : 'Total Log Lines',
        value: '$totalLogLines',
      ),
      _HeSummaryTile(
        label: isZh ? '执行状态' : 'Status',
        value: _statusLabel(orchestrator.status),
      ),
      _HeSummaryTile(
        label: isZh ? '当前阶段' : 'Current Phase',
        value: orchestrator.currentPhase != null
            ? (isZh
                  ? orchestrator.currentPhase!.displayNameZh
                  : orchestrator.currentPhase!.displayNameEn)
            : '--',
      ),
    ];

    final roleConfigs = <(String, HardnessRoleConfig)>[
      (isZh ? '探档者 (Profiler)' : 'Profiler', config.profilerConfig),
      (isZh ? '调查者 (Reader)' : 'Reader', config.readerConfig),
      (isZh ? '规划者 (Planner)' : 'Planner', config.plannerConfig),
      (isZh ? '实施者 (Implementer)' : 'Implementer', config.implementerConfig),
      (isZh ? '验收者 (Reviewer)' : 'Reviewer', config.reviewerConfig),
    ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 860,
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title row ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isZh ? '当前会话元数据' : 'Current Session Metadata',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sessionTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ── Summary tiles ──
              Wrap(spacing: 12, runSpacing: 12, children: summaryBlocks),
              const SizedBox(height: 18),

              // ── Scrollable sections ──
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Session overview ──
                      _HeMetadataSection(
                        title: isZh ? '会话概览' : 'Session Overview',
                        children: [
                          _HeMetadataEntryRow(
                            label: isZh ? '会话 ID' : 'Session ID',
                            value: sessionId ?? '--',
                          ),
                          _HeMetadataEntryRow(
                            label: isZh ? '模板' : 'Template',
                            value: 'Hardness Engineering',
                          ),
                          _HeMetadataEntryRow(
                            label: isZh ? '创建时间' : 'Created At',
                            value: createdAtLabel ?? '--',
                          ),
                          _HeMetadataEntryRow(
                            label: isZh ? '更新时间' : 'Updated At',
                            value: updatedAtLabel ?? '--',
                          ),
                          _HeMetadataEntryRow(
                            label: isZh ? '执行状态' : 'Status',
                            value: _statusLabel(orchestrator.status),
                          ),
                          if (orchestrator.errorMessage?.isNotEmpty == true)
                            _HeMetadataEntryRow(
                              label: isZh ? '错误信息' : 'Error',
                              value: orchestrator.errorMessage!,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Task config ──
                      _HeMetadataSection(
                        title: isZh ? '任务配置' : 'Task Config',
                        children: [
                          _HeMetadataEntryRow(
                            label: isZh ? '任务描述' : 'Task',
                            value: config.task.isEmpty ? '-' : config.task,
                          ),
                          _HeMetadataEntryRow(
                            label: isZh ? '工作目录' : 'Working Directory',
                            value: config.workingDirectory.isEmpty
                                ? '-'
                                : config.workingDirectory,
                          ),
                          _HeMetadataEntryRow(
                            label: isZh ? '持久化目录' : 'Persistence Directory',
                            value: config.persistenceDirectory.isEmpty
                                ? '-'
                                : config.persistenceDirectory,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Role configs ──
                      _HeMetadataSection(
                        title: isZh ? '角色配置' : 'Role Configs',
                        children: [
                          for (final entry in roleConfigs)
                            _HeMetadataEntryRow(
                              label: entry.$1,
                              value: entry.$2.isUrlMode
                                  ? 'URL/API · ${_heDescribeAiModelConfig(aiModels, entry.$2.aiModelConfigId, isZh: isZh, urlModeModelId: entry.$2.urlModeModelId)}'
                                  : entry.$2.isConfigured
                                  ? '${entry.$2.cliName} · ${describeHardnessCliModel(findHardnessCliByName(entry.$2.cliName), entry.$2.modelId, isZh: isZh)}'
                                  : (isZh ? '未配置' : 'Not configured'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ── Phase status ──
                      _HeMetadataSection(
                        title: isZh ? '阶段状态' : 'Phase Status',
                        children: [
                          for (final log in logs)
                            _HeMetadataEntryRow(
                              label: isZh
                                  ? log.phase.displayNameZh
                                  : log.phase.displayNameEn,
                              value: () {
                                final parts = <String>[
                                  _phaseStatusLabel(log.status),
                                ];
                                if (log.exitCode != null) {
                                  parts.add(
                                    '${isZh ? '退出码' : 'Exit code'}: ${log.exitCode}',
                                  );
                                }
                                parts.add(
                                  '${isZh ? '日志行数' : 'Log lines'}: ${log.lines.length}',
                                );
                                if (log.savedLogPath?.isNotEmpty == true) {
                                  parts.add(
                                    '${isZh ? '日志文件' : 'Log file'}: ${log.savedLogPath}',
                                  );
                                }
                                return parts.join(' · ');
                              }(),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ── Close button ──
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(),
                    label: isZh ? '关闭' : 'Close',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// HE Metadata dialog sub-widgets (matching _SessionMetadataDialog style)
// =============================================================================

class _HeSummaryTile extends StatelessWidget {
  const _HeSummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 188,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeMetadataSection extends StatelessWidget {
  const _HeMetadataSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _HeMetadataEntryRow extends StatelessWidget {
  const _HeMetadataEntryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Q弹 entrance animation wrapper for phase cards.
// Plays a single fade + vertical-slide + subtle scale pop when the card first
// appears in the list. Uses easeOutBack so the card slightly overshoots and
// settles back — giving that characteristic "Q弹丝滑" spring feel.
// =============================================================================

class _HePhaseCardEntrance extends StatefulWidget {
  const _HePhaseCardEntrance({required this.child});

  final Widget child;

  @override
  State<_HePhaseCardEntrance> createState() => _HePhaseCardEntranceState();
}

class _HePhaseCardEntranceState extends State<_HePhaseCardEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    );
    // Opacity: linear 0→1 in the first 60 % of the animation.
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.60, curve: Curves.easeOut),
      ),
    );
    // Scale: 0.94→1.0 with an elastic overshoot — the Q弹 feel.
    _scale = Tween<double>(
      begin: 0.94,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    // Slide: starts 18 px below its final position and rises to 0.
    _slide = Tween<Offset>(
      begin: const Offset(0.0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.topCenter,
        child: SlideTransition(position: _slide, child: widget.child),
      ),
    );
  }
}

// =============================================================================
// Phase card — mirrors an AI tool-call execution card (_MessageBubble w/
// isToolCall = true):
//   • secondaryContainer bg + secondary border  → running
//   • errorContainer bg + error border          → failed
//   • surfaceContainerHighest + light border    → completed
//   • surfaceContainerLow + light border        → pending / skipped
// =============================================================================

class _HePhaseCard extends StatefulWidget {
  const _HePhaseCard({
    super.key,
    required this.log,
    required this.config,
    required this.isZh,
    required this.expanded,
    required this.onToggleExpand,
    required this.onCopyLog,
    this.onRoleConfigChanged,
    this.filePathRoots = const [],
  });

  final HardnessPhaseLog log;
  final HardnessSessionConfig config;
  final bool isZh;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onCopyLog;

  /// If non-null, the phase is pending and the user can change its CLI/model.
  final ValueChanged<HardnessRoleConfig>? onRoleConfigChanged;

  /// Root directories for file path resolution.
  final List<String> filePathRoots;

  @override
  State<_HePhaseCard> createState() => _HePhaseCardState();
}

class _HePhaseCardState extends State<_HePhaseCard> {
  @override
  void didUpdateWidget(covariant _HePhaseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  /// Returns the HardnessRoleConfig that drives this phase.
  /// Mirrors HardnessOrchestrator._roleConfigForPhase.
  HardnessRoleConfig _roleConfig() {
    final c = widget.config;
    return switch (widget.log.phase) {
      HardnessPhase.metaCollection => c.profilerConfig,
      HardnessPhase.reading => c.readerConfig,
      HardnessPhase.planning => c.plannerConfig,
      HardnessPhase.implementing => c.implementerConfig,
      HardnessPhase.reviewing => c.reviewerConfig,
    };
  }

  static const Map<HardnessPhase, IconData> _phaseIcons = {
    HardnessPhase.metaCollection: Icons.manage_search_rounded,
    HardnessPhase.reading: Icons.menu_book_rounded,
    HardnessPhase.planning: Icons.route_rounded,
    HardnessPhase.implementing: Icons.code_rounded,
    HardnessPhase.reviewing: Icons.fact_check_rounded,
  };

  IconData get _statusIcon {
    // Completed reviewing phases with FAIL verdict use a warning icon.
    if (widget.log.status == HardnessPhaseStatus.completed &&
        widget.log.reviewVerdictFail) {
      return Icons.unpublished_rounded;
    }
    return switch (widget.log.status) {
      HardnessPhaseStatus.pending => Icons.radio_button_unchecked_rounded,
      HardnessPhaseStatus.paused => Icons.pause_circle_filled_rounded,
      HardnessPhaseStatus.running => Icons.play_circle_outline_rounded,
      HardnessPhaseStatus.completed => Icons.check_circle_rounded,
      HardnessPhaseStatus.failed => Icons.error_rounded,
      HardnessPhaseStatus.cancelled => Icons.cancel_rounded,
      HardnessPhaseStatus.skipped => Icons.remove_circle_outline_rounded,
    };
  }

  String _statusText() {
    final isZh = widget.isZh;
    // Completed reviewing phases with FAIL verdict show distinct text.
    if (widget.log.status == HardnessPhaseStatus.completed &&
        widget.log.reviewVerdictFail) {
      return isZh ? '验收未通过' : 'Review Failed';
    }
    return switch (widget.log.status) {
      HardnessPhaseStatus.pending => isZh ? '等待中' : 'Pending',
      HardnessPhaseStatus.paused => isZh ? '暂停中' : 'Paused',
      HardnessPhaseStatus.running => isZh ? '运行中' : 'Running',
      HardnessPhaseStatus.completed => isZh ? '执行完成' : 'Completed',
      HardnessPhaseStatus.failed => isZh ? '执行失败' : 'Failed',
      HardnessPhaseStatus.cancelled => isZh ? '执行中止' : 'Cancelled',
      HardnessPhaseStatus.skipped => isZh ? '已跳过' : 'Skipped',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final log = widget.log;
    final isZh = widget.isZh;
    final settingsController = Provider.of<SettingsController?>(context);
    final aiModels = settingsController?.aiModels ?? const <AiModelConfig>[];

    final isRunning = log.status == HardnessPhaseStatus.running;
    final isPaused = log.status == HardnessPhaseStatus.paused;
    final isFailed = log.status == HardnessPhaseStatus.failed;
    final isCancelled = log.status == HardnessPhaseStatus.cancelled;
    final palette = _hePhasePalette(
      theme,
      colorScheme,
      log.status,
      reviewVerdictFail: log.reviewVerdictFail,
    );
    final backgroundColor = palette.background;
    final borderColor = palette.border;
    final textColor = palette.text;

    final phaseIcon = _phaseIcons[log.phase] ?? Icons.timelapse_rounded;
    final phaseName = isZh ? log.phase.displayNameZh : log.phase.displayNameEn;
    final roleConfig = _roleConfig();

    // Animate color & border transitions when status changes (e.g. pending →
    // running → completed). AnimatedContainer handles backgroundColor and
    // borderColor interpolation automatically.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: _br26,
        border: Border.all(
          color: borderColor,
          width: (isRunning || isFailed || isPaused || isCancelled) ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.06 : 0.04,
            ),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card header pill (mirrors _ToolCallMetaRow) ───────────────
            _HePhaseMetaRow(
              log: log,
              phaseName: phaseName,
              phaseIcon: phaseIcon,
              statusText: _statusText(),
              statusIcon: _statusIcon,
              textColor: textColor,
              expanded: widget.expanded,
              onToggle: widget.onToggleExpand,
            ),

            // ── Info chips (mirrors _ToolCallBody chip Wrap) ──────────────
            if (roleConfig.isUrlMode ||
                roleConfig.cliName.isNotEmpty ||
                roleConfig.modelId.isNotEmpty ||
                log.exitCode != null ||
                log.savedLogPath != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (roleConfig.isUrlMode)
                    const _HeChip(icon: Icons.cloud_rounded, label: 'URL/API'),
                  if (!roleConfig.isUrlMode && roleConfig.cliName.isNotEmpty)
                    _HeChip(
                      icon: Icons.terminal_rounded,
                      label: roleConfig.cliName,
                    ),
                  if (roleConfig.isUrlMode &&
                      (roleConfig.aiModelConfigId?.trim().isNotEmpty ?? false))
                    _HeChip(
                      icon: Icons.layers_rounded,
                      label: _heDescribeAiModelConfig(
                        aiModels,
                        roleConfig.aiModelConfigId,
                        isZh: isZh,
                        urlModeModelId: roleConfig.urlModeModelId,
                      ),
                    ),
                  if (!roleConfig.isUrlMode && roleConfig.modelId.isNotEmpty)
                    _HeChip(
                      icon: Icons.layers_rounded,
                      label: describeHardnessCliModel(
                        findHardnessCliByName(roleConfig.cliName),
                        roleConfig.modelId,
                        isZh: isZh,
                      ),
                    ),
                  if (log.exitCode != null)
                    _HeChip(
                      icon: log.exitCode == 0
                          ? Icons.check_circle_outline_rounded
                          : Icons.flag_outlined,
                      label: '${isZh ? '退出码' : 'Exit'}: ${log.exitCode}',
                    ),
                  if (log.savedLogPath != null)
                    _HeChip(
                      icon: Icons.save_outlined,
                      label: isZh ? '已保存日志' : 'Log saved',
                    ),
                  if (log.changedFiles.isNotEmpty)
                    _HeChip(
                      icon: Icons.difference_rounded,
                      label:
                          '${log.changedFiles.length} ${isZh ? '个文件变动' : 'files changed'}',
                    ),
                ],
              ),
            ],

            // ── Edit CLI/model for retryable and not-yet-executed phases ───
            if (widget.onRoleConfigChanged != null) ...[
              const SizedBox(height: 10),
              _HePendingPhaseEditor(
                roleConfig: roleConfig,
                isZh: isZh,
                onChanged: widget.onRoleConfigChanged!,
              ),
            ],

            // ── Expandable log section ────────────────────────────────────
            if (widget.expanded) ...[
              const SizedBox(height: 12),
              _HeLogSection(
                log: log,
                isZh: isZh,
                onCopy: widget.onCopyLog,
                filePathRoots: widget.filePathRoots,
              ),
              // ── File changes list ─────────────────────────────────────
              if (log.changedFiles.isNotEmpty) ...[
                const SizedBox(height: 12),
                _HeChangedFilesList(files: log.changedFiles, isZh: isZh),
              ],
            ] else if (log.lines.isNotEmpty) ...[
              // Collapsed preview: last meaningful log line.
              // Skip UI-decoration lines (✓ ✗ ▶ ⚠ ℹ prefixes) and manual
              // input headers (【…】) so internal status markers never leak
              // into the preview.
              Builder(
                builder: (context) {
                  final previewLine = log.lines.lastWhere((l) {
                    final t = l.trim();
                    if (t.isEmpty) return false;
                    if (t.startsWith('✓ ') ||
                        t.startsWith('✗ ') ||
                        t.startsWith('▶ ') ||
                        t.startsWith('⚠ ') ||
                        t.startsWith('ℹ ')) {
                      return false;
                    }
                    if (t.startsWith('【') && t.endsWith('】')) return false;
                    return true;
                  }, orElse: () => '');
                  if (previewLine.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      previewLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        color: textColor.withValues(alpha: 0.60),
                      ),
                    ),
                  );
                },
              ),
            ],

            // ── Failure hint beneath expanded failed cards ────────────────
            if (isFailed && widget.expanded) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isZh
                          ? '本阶段执行失败，请检查上方日志以了解详情。'
                          : 'This phase failed. Review the log above for details.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// _HePhaseActionBar — action buttons shown below a selected phase card,
// matching the _MessageActionButton pattern from AI thread messages.
// =============================================================================

class _HePhaseActionBar extends StatelessWidget {
  const _HePhaseActionBar({
    required this.isZh,
    required this.onCopyLog,
    required this.onReExecute,
    required this.onDelete,
  });

  final bool isZh;
  final VoidCallback onCopyLog;
  final VoidCallback onReExecute;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onCopyLog,
          style: buttonStyle,
          icon: const Icon(Icons.content_copy_outlined, size: 16),
          label: Text(isZh ? '复制' : 'Copy'),
        ),
        OutlinedButton.icon(
          onPressed: onReExecute,
          style: buttonStyle,
          icon: const Icon(Icons.replay_rounded, size: 16),
          label: Text(isZh ? '重新执行' : 'Re-execute'),
        ),
        OutlinedButton.icon(
          onPressed: onDelete,
          style: buttonStyle,
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: Text(isZh ? '删除' : 'Delete'),
        ),
      ],
    );
  }
}

// =============================================================================
// Sweep-shimmer pill — replicates _SweepBadge from openhand_home_page for use
// inside the hardness dashboard without introducing a cross-feature import.
// Plays a left-to-right grey shimmer on loop while a phase is running.
// =============================================================================

class _HeSweepPill extends StatefulWidget {
  const _HeSweepPill({
    required this.child,
    required this.backgroundColor,
    required this.sweepColor,
  });

  final Widget child;
  final Color backgroundColor;
  final Color sweepColor;

  @override
  State<_HeSweepPill> createState() => _HeSweepPillState();
}

class _HeSweepPillState extends State<_HeSweepPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const br = BorderRadius.all(Radius.circular(999));
    return ClipRRect(
      borderRadius: br,
      child: AnimatedBuilder(
        animation: _ctrl,
        child: widget.child,
        builder: (context, child) {
          final start = -1.8 + (_ctrl.value * 2.8);
          final end = start + 0.9;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: br,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(start, 0),
                        end: Alignment(end, 0),
                        colors: [
                          Colors.transparent,
                          widget.sweepColor,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                child ?? const SizedBox.shrink(),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Phase card header pill — mirrors _ToolCallMetaRow
// =============================================================================

class _HePhaseMetaRow extends StatelessWidget {
  const _HePhaseMetaRow({
    required this.log,
    required this.phaseName,
    required this.phaseIcon,
    required this.statusText,
    required this.statusIcon,
    required this.textColor,
    required this.expanded,
    required this.onToggle,
  });

  final HardnessPhaseLog log;
  final String phaseName;
  final IconData phaseIcon;
  final String statusText;
  final IconData statusIcon;
  final Color textColor;
  final bool expanded;
  final VoidCallback onToggle;

  bool get _isRunning => log.status == HardnessPhaseStatus.running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Status-icon indicator with AnimatedSwitcher — transitions smoothly when
    // the phase status changes (pending → running → completed).
    // While running the icon position is kept empty; the sweep animation on
    // the pill itself already signals activity.
    final statusIndicator = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      child: SizedBox(
        key: ValueKey<HardnessPhaseStatus>(log.status),
        width: 16,
        height: 16,
        // Running state: no spinner — the pill sweep conveys activity.
        child: _isRunning
            ? null
            : Icon(
                statusIcon,
                size: 16,
                color: textColor.withValues(alpha: 0.88),
              ),
      ),
    );

    final pillInnerContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          statusIndicator,
          // Add spacing only when the icon slot is occupied (non-running).
          if (!_isRunning) const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$phaseName · $statusText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: textColor.withValues(alpha: 0.88),
              ),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: textColor.withValues(alpha: 0.72),
              size: 18,
            ),
          ),
        ],
      ),
    );

    // When running: wrap the pill in the sweep-shimmer overlay.
    // When idle/done: use a plain container (no animation overhead).
    final pillBackground = Colors.black.withValues(alpha: 0.08);
    final pillDecoratedChild = _isRunning
        ? _HeSweepPill(
            backgroundColor: pillBackground,
            sweepColor: textColor.withValues(alpha: 0.14),
            child: pillInnerContent,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: pillBackground,
              borderRadius: _br999,
            ),
            child: pillInnerContent,
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: _br999,
        overlayColor: WidgetStatePropertyAll<Color>(
          textColor.withValues(alpha: 0.06),
        ),
        child: pillDecoratedChild,
      ),
    );
  }
}

// =============================================================================
// _HeLogSection — smart log panel
//
// • Running phase  → live monospace tail (last 50 lines, auto-scroll)
// • Done phase     → "Smart" view (default): extracted command chip +
//                    full Markdown-rendered content
//                    "Raw" toggle: classic coloured monospace
// =============================================================================

class _HeLogSection extends StatefulWidget {
  const _HeLogSection({
    required this.log,
    required this.isZh,
    required this.onCopy,
    this.filePathRoots = const [],
  });

  final HardnessPhaseLog log;
  final bool isZh;
  final VoidCallback onCopy;
  final List<String> filePathRoots;

  @override
  State<_HeLogSection> createState() => _HeLogSectionState();
}

class _HeLogSectionState extends State<_HeLogSection> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final log = widget.log;
    final isRunning = log.status == HardnessPhaseStatus.running;
    final lines = log.lines;
    final isZh = widget.isZh;

    // Running phases change content every frame — AnimatedSize cannot settle
    // in a SliverList (the size-change listener fires markNeedsLayout during
    // performLayout, causing a crash). Use a plain wrapper here.
    return Material(
      color: colorScheme.surface.withValues(alpha: 0.78),
      borderRadius: _br16,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section header row ────────────────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.terminal_rounded,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  isZh ? '执行输出' : 'Output',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                // Raw / rendered toggle (only shown when phase is done)
                if (!isRunning && lines.isNotEmpty) ...[
                  _HeSmallPill(
                    icon: _showRaw
                        ? Icons.auto_awesome_rounded
                        : Icons.code_rounded,
                    label: _showRaw
                        ? (isZh ? '渲染' : 'Rendered')
                        : (isZh ? '原始' : 'Raw'),
                    onTap: () => setState(() => _showRaw = !_showRaw),
                  ),
                  const SizedBox(width: 8),
                ],
                _HeSmallPill(
                  icon: Icons.copy_rounded,
                  label: isZh ? '复制' : 'Copy',
                  onTap: widget.onCopy,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Content area ──────────────────────────────────────────────
            if (lines.isEmpty)
              _HeEmptyOutputPlaceholder(isZh: isZh)
            else if (isRunning)
              _HeStreamingSubConversation(
                lines: lines,
                isZh: isZh,
                theme: theme,
                colorScheme: colorScheme,
                filePathRoots: widget.filePathRoots,
              )
            else if (_showRaw)
              _HeRawFullView(
                lines: lines,
                colorScheme: colorScheme,
                onCopy: widget.onCopy,
                isZh: isZh,
              )
            else
              _HeSubConversationView(
                lines: lines,
                isZh: isZh,
                theme: theme,
                colorScheme: colorScheme,
                filePathRoots: widget.filePathRoots,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Empty placeholder ──────────────────────────────────────────────────────

class _HeEmptyOutputPlaceholder extends StatelessWidget {
  const _HeEmptyOutputPlaceholder({required this.isZh});
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isZh ? '等待输出…' : 'Waiting for output…',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Raw full view (manual toggle) ─────────────────────────────────────────

class _HeRawFullView extends StatefulWidget {
  const _HeRawFullView({
    required this.lines,
    required this.colorScheme,
    required this.onCopy,
    required this.isZh,
  });

  final List<String> lines;
  final ColorScheme colorScheme;
  final VoidCallback onCopy;
  final bool isZh;

  static const int _previewCount = 30;

  @override
  State<_HeRawFullView> createState() => _HeRawFullViewState();
}

class _HeRawFullViewState extends State<_HeRawFullView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    final theme = Theme.of(context);
    final colorScheme = widget.colorScheme;
    final shortened = !_expanded && lines.length > _HeRawFullView._previewCount;
    final display = shortened
        ? lines.sublist(0, _HeRawFullView._previewCount)
        : lines;
    final hidden = shortened ? lines.length - _HeRawFullView._previewCount : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          cacheExtent: 400,
          itemCount: display.length,
          itemBuilder: (_, i) =>
              _LogLine(line: display[i], colorScheme: colorScheme),
        ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () => setState(() => _expanded = true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: _br999,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.isZh
                          ? '显示全部 ${lines.length} 行'
                          : 'Show all ${lines.length} lines',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Smart view (markdown rendered) ────────────────────────────────────────
// For large payloads (>3 000 lines) the log-splitting is offloaded to a
// background isolate via compute() so the UI thread stays responsive.

class _HeSmartView extends StatefulWidget {
  const _HeSmartView({
    required this.lines,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    required this.filePathRoots,
  });

  final List<String> lines;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final List<String> filePathRoots;

  // Threshold: below this, parse on the UI thread synchronously (faster
  // round-trip); above it, hand off to an isolate.
  static const int _isolateThreshold = 3000;

  @override
  State<_HeSmartView> createState() => _HeSmartViewState();
}

// Top-level function required by compute() — must not be a closure.
({String? command, String body}) _heSplitLogForMarkdownCompute(
  List<String> lines,
) => _heSplitLogForMarkdown(lines);

class _HeSmartViewState extends State<_HeSmartView> {
  ({String? command, String body})? _parsed;

  @override
  void initState() {
    super.initState();
    _parse(widget.lines);
  }

  @override
  void didUpdateWidget(_HeSmartView old) {
    super.didUpdateWidget(old);
    if (old.lines != widget.lines) {
      _parsed = null;
      _parse(widget.lines);
    }
  }

  void _parse(List<String> lines) {
    if (lines.length > _HeSmartView._isolateThreshold) {
      compute(_heSplitLogForMarkdownCompute, lines).then((result) {
        if (mounted) setState(() => _parsed = result);
      });
    } else {
      _parsed = _heSplitLogForMarkdown(lines);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;

    // Show a lightweight spinner while the isolate is working.
    if (_parsed == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              widget.isZh ? '正在处理…' : 'Processing…',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final (:command, :body) = _parsed!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (command != null) ...[
          _HeCommandStrip(command: command),
          const SizedBox(height: 10),
        ],
        if (body.isNotEmpty)
          _HeMarkdownContent(
            content: body,
            isZh: widget.isZh,
            theme: widget.theme,
            colorScheme: colorScheme,
            filePathRoots: widget.filePathRoots,
          )
        else
          Text(
            widget.isZh ? '（无文本输出）' : '(no text output)',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// _HeSubConversationView — Structured sub-conversation rendering (completed phase)
//
// Parses CLI output into typed segments and renders each as an independent
// mini-card within the phase card, providing a structured conversation feel
// that matches the AI thread template's visual language.
// =============================================================================

class _HeSubConversationView extends StatefulWidget {
  const _HeSubConversationView({
    required this.lines,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    this.filePathRoots = const [],
  });

  final List<String> lines;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final List<String> filePathRoots;

  @override
  State<_HeSubConversationView> createState() => _HeSubConversationViewState();
}

class _HeSubConversationViewState extends State<_HeSubConversationView> {
  List<_HeOutputSegment>? _segments;

  @override
  void initState() {
    super.initState();
    _parseSegments();
  }

  @override
  void didUpdateWidget(_HeSubConversationView old) {
    super.didUpdateWidget(old);
    if (old.lines != widget.lines) _parseSegments();
  }

  void _parseSegments() {
    if (widget.lines.length > 3000) {
      compute(_heParseOutputSegmentsIsolate, widget.lines).then((result) {
        if (mounted) setState(() => _segments = result);
      });
    } else {
      _segments = _heParseOutputSegments(widget.lines);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final segments = _segments;

    if (segments == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              widget.isZh ? '正在处理…' : 'Processing…',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (segments.isEmpty) {
      return Text(
        widget.isZh ? '（无文本输出）' : '(no text output)',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: segments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _HeSegmentMiniCard(
        segment: segments[index],
        isZh: widget.isZh,
        theme: widget.theme,
        colorScheme: colorScheme,
        filePathRoots: widget.filePathRoots,
      ),
    );
  }
}

/// Top-level function for isolate use in compute().
List<_HeOutputSegment> _heParseOutputSegmentsIsolate(List<String> lines) =>
    _heParseOutputSegments(lines);

// =============================================================================
// _HeStreamingSubConversation — Streaming sub-conversation (running phase)
//
// Similar to _HeSubConversationView but operates on a tail of lines and
// includes streaming indicators.
// =============================================================================

class _HeStreamingSubConversation extends StatefulWidget {
  const _HeStreamingSubConversation({
    required this.lines,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    this.filePathRoots = const [],
  });

  final List<String> lines;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final List<String> filePathRoots;

  static const int _tailSize = 80;

  @override
  State<_HeStreamingSubConversation> createState() =>
      _HeStreamingSubConversationState();
}

class _HeStreamingSubConversationState
    extends State<_HeStreamingSubConversation> {
  List<_HeOutputSegment>? _segments;
  List<_HeOutputSegment>? _olderSegments;
  int _lastHiddenAbove = 0;
  int _lastSegmentCount = 0;
  int _contentRevision = 0;
  bool _showEarlierSegments = false;
  bool _olderSegmentsLoading = false;
  int _olderSegmentWindowStart = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _HeStreamingSubConversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildIfNeeded();
  }

  void _rebuildIfNeeded() {
    final lines = widget.lines;
    final start = lines.length > _HeStreamingSubConversation._tailSize
        ? lines.length - _HeStreamingSubConversation._tailSize
        : 0;
    final display = lines.length > _HeStreamingSubConversation._tailSize
        ? lines.sublist(start)
        : lines;
    _lastHiddenAbove = start;
    _segments = _heParseOutputSegments(display);
    final newCount = _segments?.length ?? 0;
    if (newCount > _lastSegmentCount) {
      _contentRevision++;
    }
    _lastSegmentCount = newCount;

    if (!_showEarlierSegments) {
      _olderSegments = null;
      _olderSegmentsLoading = false;
      _olderSegmentWindowStart = -1;
      return;
    }

    _ensureOlderSegments(start);
  }

  void _ensureOlderSegments(int start) {
    if (!_showEarlierSegments || start <= 0) {
      _olderSegments = null;
      _olderSegmentsLoading = false;
      _olderSegmentWindowStart = -1;
      return;
    }
    if (_olderSegmentWindowStart == start && _olderSegments != null) {
      return;
    }
    final olderLines = widget.lines.sublist(0, start);
    _olderSegmentWindowStart = start;
    if (olderLines.length > 3000) {
      _olderSegmentsLoading = true;
      compute(_heParseOutputSegmentsIsolate, olderLines).then((result) {
        if (!mounted ||
            !_showEarlierSegments ||
            _olderSegmentWindowStart != start) {
          return;
        }
        setState(() {
          _olderSegments = result;
          _olderSegmentsLoading = false;
        });
      });
      return;
    }
    _olderSegments = _heParseOutputSegments(olderLines);
    _olderSegmentsLoading = false;
  }

  void _toggleEarlierSegments() {
    setState(() {
      _showEarlierSegments = !_showEarlierSegments;
      if (!_showEarlierSegments) {
        _olderSegments = null;
        _olderSegmentsLoading = false;
        _olderSegmentWindowStart = -1;
      }
    });
    if (_showEarlierSegments) {
      _ensureOlderSegments(_lastHiddenAbove);
    }
  }

  Widget _buildSegmentList(
    List<_HeOutputSegment> segments, {
    required bool animateLast,
  }) {
    final colorScheme = widget.colorScheme;
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: segments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final card = _HeSegmentMiniCard(
          segment: segments[index],
          isZh: widget.isZh,
          theme: widget.theme,
          colorScheme: colorScheme,
          filePathRoots: widget.filePathRoots,
          isStreaming: animateLast && index == segments.length - 1,
        );
        if (!animateLast || index != segments.length - 1) {
          return card;
        }
        return TweenAnimationBuilder<double>(
          key: ValueKey<int>(_contentRevision),
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutBack,
          builder: (_, value, child) {
            final clamped = value.clamp(0.0, 1.0);
            return Opacity(
              opacity: clamped,
              child: Transform.translate(
                offset: Offset(0.0, 12.0 * (1.0 - clamped)),
                child: Transform.scale(
                  scale: 0.96 + 0.04 * clamped,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              ),
            );
          },
          child: card,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final segments = _segments ?? [];
    final olderSegments = _olderSegments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_lastHiddenAbove > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: colorScheme.surface.withValues(alpha: 0.82),
              borderRadius: _br16,
              child: InkWell(
                onTap: _toggleEarlierSegments,
                borderRadius: _br16,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _showEarlierSegments
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.isZh
                              ? (_showEarlierSegments
                                    ? '收起更早的子消息 · $_lastHiddenAbove 行'
                                    : '展开更早的子消息 · $_lastHiddenAbove 行')
                              : (_showEarlierSegments
                                    ? 'Hide earlier sub-messages · $_lastHiddenAbove lines'
                                    : 'Show earlier sub-messages · $_lastHiddenAbove lines'),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_showEarlierSegments) ...[
          if (_olderSegmentsLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isZh
                        ? '正在加载更早的子消息…'
                        : 'Loading earlier sub-messages…',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.72,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (olderSegments != null && olderSegments.isNotEmpty) ...[
            RepaintBoundary(
              child: _buildSegmentList(olderSegments, animateLast: false),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (segments.isNotEmpty) _buildSegmentList(segments, animateLast: true),
        // Streaming indicator.
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.isZh ? '正在输出…' : 'Streaming…',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.60),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// _HeSegmentMiniCard — Renders a single output segment as a styled mini-card
// matching the AI thread template's visual language for thinking, tool call,
// and assistant response messages.
// =============================================================================

class _HeSegmentMiniCard extends StatefulWidget {
  const _HeSegmentMiniCard({
    required this.segment,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    this.filePathRoots = const [],
    this.isStreaming = false,
  });

  final _HeOutputSegment segment;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final List<String> filePathRoots;
  final bool isStreaming;

  @override
  State<_HeSegmentMiniCard> createState() => _HeSegmentMiniCardState();
}

class _HeSegmentMiniCardState extends State<_HeSegmentMiniCard> {
  bool _expanded = true;

  static const _maxPreviewChars = 600;

  @override
  Widget build(BuildContext context) {
    final seg = widget.segment;
    final colorScheme = widget.colorScheme;
    final isDark = widget.theme.brightness == Brightness.dark;

    if (seg.kind == _HeSegmentKind.toolCall ||
        seg.kind == _HeSegmentKind.toolResult) {
      return _HeStructuredToolTraceCard(
        segment: seg,
        isZh: widget.isZh,
        theme: widget.theme,
        colorScheme: colorScheme,
        isStreaming: widget.isStreaming,
      );
    }

    // ── Special rendering for manual review verdict segments ─────────
    if (seg.kind == _HeSegmentKind.userInput) {
      final verdictInfo = _parseReviewVerdict(seg);
      if (verdictInfo != null) {
        return _HeReviewVerdictCard(
          isPass: verdictInfo.isPass,
          comment: verdictInfo.comment,
          roleLabel:
              seg.roleLabel ?? (widget.isZh ? '用户人工验收结果' : 'Manual Review'),
          isZh: widget.isZh,
          theme: widget.theme,
          colorScheme: colorScheme,
        );
      }
    }

    // ── Determine card style by segment kind ────────────────────────────
    final (
      IconData icon,
      String label,
      Color cardBg,
      Color cardBorder,
      Color cardText,
      double borderRadius,
    ) = switch (seg.kind) {
      _HeSegmentKind.command => (
        Icons.terminal_rounded,
        widget.isZh ? '执行命令' : 'Command',
        colorScheme.surfaceContainerHighest,
        colorScheme.outlineVariant.withValues(alpha: 0.30),
        colorScheme.onSurface,
        16.0,
      ),
      _HeSegmentKind.thinking => (
        Icons.psychology_alt_outlined,
        widget.isZh ? '思考' : 'Thinking',
        isDark ? const Color(0xFF18181B) : colorScheme.surfaceContainerHighest,
        isDark
            ? Colors.white.withValues(alpha: 0.10)
            : colorScheme.outlineVariant.withValues(alpha: 0.20),
        isDark ? Colors.white.withValues(alpha: 0.87) : colorScheme.onSurface,
        18.0,
      ),
      _HeSegmentKind.toolCall || _HeSegmentKind.toolResult => (
        Icons.build_circle_outlined,
        widget.isZh ? '工具调用' : 'Tool Call',
        colorScheme.secondaryContainer,
        colorScheme.secondary.withValues(alpha: 0.35),
        colorScheme.onSecondaryContainer,
        26.0,
      ),
      _HeSegmentKind.assistant => (
        Icons.auto_awesome_rounded,
        widget.isZh ? 'AI 回复' : 'AI Response',
        colorScheme.surfaceContainerHigh,
        colorScheme.outlineVariant.withValues(alpha: isDark ? 0.18 : 0.10),
        colorScheme.onSurface,
        26.0,
      ),
      _HeSegmentKind.output => (
        Icons.info_outline_rounded,
        widget.isZh ? '输出' : 'Output',
        colorScheme.surfaceContainerLow,
        colorScheme.outlineVariant.withValues(alpha: 0.15),
        colorScheme.onSurface,
        16.0,
      ),
      _HeSegmentKind.userInput => (
        Icons.person_rounded,
        seg.roleLabel ?? (widget.isZh ? '用户输入' : 'User Input'),
        Color.alphaBlend(
          colorScheme.tertiary.withValues(alpha: isDark ? 0.22 : 0.12),
          colorScheme.surface,
        ),
        colorScheme.tertiary.withValues(alpha: isDark ? 0.40 : 0.28),
        colorScheme.onSurface,
        18.0,
      ),
      _HeSegmentKind.handoff => (
        Icons.swap_horiz_rounded,
        seg.roleLabel ?? (widget.isZh ? '交接文档' : 'Handoff'),
        Color.alphaBlend(
          colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10),
          colorScheme.surface,
        ),
        colorScheme.primary.withValues(alpha: isDark ? 0.45 : 0.30),
        colorScheme.onSurface,
        18.0,
      ),
    };

    // ── Special rendering for command segments ──────────────────────────
    if (seg.kind == _HeSegmentKind.command) {
      return _HeCommandStrip(command: seg.lines.join('\n'));
    }

    final body = seg.markdownBody;
    final needsCollapse = body.length > _maxPreviewChars && !widget.isStreaming;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: isDark ? 0.04 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────────────
            InkWell(
              onTap: needsCollapse
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              borderRadius: _br999,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 14,
                      color: cardText.withValues(alpha: 0.72),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: widget.theme.textTheme.labelMedium?.copyWith(
                        color: cardText.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (needsCollapse) ...[
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: cardText.withValues(alpha: 0.50),
                          size: 16,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ── Body ──────────────────────────────────────────────────
            if (body.isNotEmpty)
              _HeSegmentBody(
                content: body,
                expanded: _expanded || !needsCollapse,
                isZh: widget.isZh,
                theme: widget.theme,
                colorScheme: colorScheme,
                textColor: cardText,
                filePathRoots: widget.filePathRoots,
                onExpand: () => setState(() => _expanded = true),
              )
            else
              Text(
                widget.isZh ? '（无内容）' : '(empty)',
                style: TextStyle(
                  color: cardText.withValues(alpha: 0.45),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final RegExp _heToolStatusPattern = RegExp(
  r'\b(succeeded|failed|timed out|timed-out|cancelled|canceled|denied|rejected|blocked)(?:\s+in\s+([0-9]+(?:\.[0-9]+)?(?:ms|s|sec|secs|m|min|mins)))?\b',
  caseSensitive: false,
);

final RegExp _heToolExitCodePattern = RegExp(
  r'(?:exit(?:\s+code)?|code)\s*[:=]\s*(-?\d+)',
  caseSensitive: false,
);

class _HeToolPresentation {
  const _HeToolPresentation({
    required this.label,
    required this.icon,
    required this.isCommandLike,
  });

  final String label;
  final IconData icon;
  final bool isCommandLike;
}

class _HeParsedToolHeader {
  const _HeParsedToolHeader({
    required this.command,
    required this.workingDirectory,
    required this.status,
    required this.durationMs,
    required this.inlineResult,
  });

  final String command;
  final String workingDirectory;
  final String status;
  final int durationMs;
  final String inlineResult;

  static _HeParsedToolHeader? tryParse(
    String line, {
    required bool isStreaming,
  }) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final statusMatch = _heToolStatusPattern.firstMatch(trimmed);
    var prefix = trimmed;
    var status = '';
    var durationMs = 0;
    var inlineResult = '';

    if (statusMatch != null) {
      status = _heNormalizeToolStatus(statusMatch.group(1) ?? '');
      durationMs = _heParseToolDurationToMs(statusMatch.group(2) ?? '');
      prefix = trimmed.substring(0, statusMatch.start).trimRight();
      var trailing = trimmed.substring(statusMatch.end).trimLeft();
      if (trailing.startsWith(':')) {
        trailing = trailing.substring(1).trimLeft();
      }
      inlineResult = trailing;
    }

    final split = _heSplitToolCommandAndDirectory(prefix);
    final command = split?.command ?? prefix;
    final workingDirectory = split?.workingDirectory ?? '';
    final looksLikeHeader = split != null || _heLooksLikeToolCommand(command);
    if (!looksLikeHeader) {
      return null;
    }

    return _HeParsedToolHeader(
      command: command,
      workingDirectory: workingDirectory,
      status: status.isEmpty && isStreaming ? 'running' : status,
      durationMs: durationMs,
      inlineResult: inlineResult,
    );
  }
}

class _HeStructuredToolTrace {
  const _HeStructuredToolTrace({
    required this.presentation,
    required this.status,
    required this.durationMs,
    required this.command,
    required this.workingDirectory,
    required this.argumentsText,
    required this.stdout,
    required this.stderr,
    required this.resultText,
    required this.exitCode,
    required this.statusIcon,
    required this.headerLabel,
    required this.outcomeLabel,
    required this.inputPreview,
    required this.outputPreview,
  });

  factory _HeStructuredToolTrace.fromSegment(
    _HeOutputSegment segment, {
    required bool isZh,
    required bool isStreaming,
  }) {
    final lines = List<String>.from(segment.lines);
    final firstContentIndex = _heIndexOfFirstMeaningfulLine(lines);
    final firstContentLine = firstContentIndex >= 0
        ? lines[firstContentIndex].trim()
        : '';
    final parsedHeader = _HeParsedToolHeader.tryParse(
      firstContentLine,
      isStreaming: isStreaming,
    );
    final presentation = _heToolPresentationForSegment(
      segment,
      parsedHeader,
      isZh: isZh,
    );

    final outputLines = <String>[];
    if (parsedHeader != null) {
      if (parsedHeader.inlineResult.isNotEmpty) {
        outputLines.add(parsedHeader.inlineResult);
      }
      if (firstContentIndex >= 0 && firstContentIndex + 1 < lines.length) {
        outputLines.addAll(lines.skip(firstContentIndex + 1));
      }
    } else if (segment.kind == _HeSegmentKind.toolResult) {
      outputLines.addAll(lines);
    }

    final outputText = _heNormalizeToolText(outputLines.join('\n'));
    final exitCode = _heExtractToolExitCode(outputLines);
    var status = parsedHeader?.status ?? '';
    if (status.isEmpty && isStreaming) {
      status = 'running';
    }
    if (status.isEmpty && exitCode != null) {
      status = exitCode == 0 ? 'success' : 'failed';
    }
    if (status.isEmpty &&
        segment.kind == _HeSegmentKind.toolResult &&
        outputText.isNotEmpty) {
      status = 'success';
    }

    final useErrorChannel =
        status == 'failed' ||
        status == 'timed_out' ||
        status == 'denied' ||
        status == 'rejected';
    final stdout =
        segment.kind != _HeSegmentKind.toolResult &&
            outputText.isNotEmpty &&
            !useErrorChannel
        ? outputText
        : '';
    final stderr = outputText.isNotEmpty && useErrorChannel ? outputText : '';
    final resultText =
        segment.kind == _HeSegmentKind.toolResult && stderr.isEmpty
        ? outputText
        : '';

    final argumentsText = _heBuildStructuredToolArguments(
      segment,
      parsedHeader,
    );
    final durationMs = parsedHeader?.durationMs ?? 0;
    final actionLabel = _heToolActionLabel(
      isZh: isZh,
      status: status,
      isCommandLike: presentation.isCommandLike,
    );
    final durationSuffix = durationMs > 0
        ? ' (${_heFormatToolDuration(durationMs)})'
        : '';

    return _HeStructuredToolTrace(
      presentation: presentation,
      status: status,
      durationMs: durationMs,
      command: parsedHeader?.command ?? '',
      workingDirectory: parsedHeader?.workingDirectory ?? '',
      argumentsText: argumentsText,
      stdout: _heFormatStructuredToolContent(stdout),
      stderr: _heFormatStructuredToolContent(stderr),
      resultText: _heFormatStructuredToolContent(resultText),
      exitCode: exitCode,
      statusIcon: _heToolStatusIcon(status),
      headerLabel: '${presentation.label} · $actionLabel$durationSuffix',
      outcomeLabel: _heToolOutcomeLabel(isZh: isZh, status: status),
      inputPreview: _heBuildStructuredToolInputPreview(
        command: parsedHeader?.command ?? '',
        argumentsText: argumentsText,
      ),
      outputPreview: _heBuildStructuredToolOutputPreview(
        isZh: isZh,
        status: status,
        stdout: stdout,
        stderr: stderr,
        resultText: resultText,
      ),
    );
  }

  final _HeToolPresentation presentation;
  final String status;
  final int durationMs;
  final String command;
  final String workingDirectory;
  final String argumentsText;
  final String stdout;
  final String stderr;
  final String resultText;
  final int? exitCode;
  final IconData statusIcon;
  final String headerLabel;
  final String outcomeLabel;
  final String inputPreview;
  final String outputPreview;

  bool get hasInputSection =>
      command.isNotEmpty || argumentsText.trim().isNotEmpty;

  bool get hasOutputSection =>
      stdout.isNotEmpty ||
      stderr.isNotEmpty ||
      resultText.isNotEmpty ||
      status.isNotEmpty ||
      exitCode != null;
}

class _HeStructuredToolTraceCard extends StatefulWidget {
  const _HeStructuredToolTraceCard({
    required this.segment,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    required this.isStreaming,
  });

  final _HeOutputSegment segment;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final bool isStreaming;

  @override
  State<_HeStructuredToolTraceCard> createState() =>
      _HeStructuredToolTraceCardState();
}

class _HeStructuredToolTraceCardState
    extends State<_HeStructuredToolTraceCard> {
  bool _inputExpanded = true;
  bool _outputExpanded = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final data = _HeStructuredToolTrace.fromSegment(
      widget.segment,
      isZh: widget.isZh,
      isStreaming: widget.isStreaming,
    );
    final isToolCall = widget.segment.kind == _HeSegmentKind.toolCall;
    final cardColor = isToolCall
        ? Color.alphaBlend(
            colorScheme.secondary.withValues(alpha: 0.14),
            colorScheme.surfaceContainerHighest,
          )
        : colorScheme.surfaceContainerHigh;
    final borderColor = isToolCall
        ? colorScheme.secondary.withValues(alpha: 0.28)
        : colorScheme.outlineVariant.withValues(alpha: 0.28);
    final textColor = isToolCall
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;
    final subtleSurface = Color.alphaBlend(
      Colors.white.withValues(
        alpha: widget.theme.brightness == Brightness.dark ? 0.05 : 0.55,
      ),
      cardColor,
    );

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: _br26,
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(
              alpha: widget.theme.brightness == Brightness.dark ? 0.05 : 0.035,
            ),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: subtleSurface,
                borderRadius: _br999,
                border: Border.all(color: borderColor.withValues(alpha: 0.7)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(data.statusIcon, size: 18, color: textColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      data.headerLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: widget.theme.textTheme.labelLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeChip(
                  icon: data.presentation.icon,
                  label: data.presentation.label,
                ),
                if (data.workingDirectory.isNotEmpty)
                  _HeChip(
                    icon: Icons.folder_outlined,
                    label:
                        '${widget.isZh ? '目录' : 'Dir'}: ${data.workingDirectory}',
                  ),
                if (data.outcomeLabel.isNotEmpty)
                  _HeChip(icon: data.statusIcon, label: data.outcomeLabel),
                if (data.durationMs > 0 || data.status == 'running')
                  _HeChip(
                    icon: Icons.timer_outlined,
                    label:
                        '${widget.isZh ? '耗时' : 'Elapsed'}: ${_heFormatToolDuration(data.durationMs)}',
                  ),
                if (data.exitCode != null)
                  _HeChip(
                    icon: Icons.flag_outlined,
                    label: '${widget.isZh ? '退出码' : 'Exit'}: ${data.exitCode}',
                  ),
              ],
            ),
            if (data.hasInputSection) ...[
              const SizedBox(height: 10),
              _HeStructuredToolSection(
                title: widget.isZh ? '工具入参' : 'Tool Input',
                preview: data.inputPreview,
                expanded: _inputExpanded,
                onToggle: () {
                  setState(() {
                    _inputExpanded = !_inputExpanded;
                  });
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data.command.isNotEmpty)
                      _HeToolTextPanel(
                        label: widget.isZh ? 'command' : 'command',
                        content: '\$ ${data.command}',
                        isZh: widget.isZh,
                        theme: widget.theme,
                        colorScheme: colorScheme,
                      ),
                    if (data.command.isNotEmpty) const SizedBox(height: 10),
                    if (data.argumentsText.trim().isNotEmpty)
                      _HeToolTextPanel(
                        label: widget.isZh ? 'arguments' : 'arguments',
                        content: data.argumentsText,
                        isZh: widget.isZh,
                        theme: widget.theme,
                        colorScheme: colorScheme,
                      ),
                  ],
                ),
              ),
            ],
            if (data.hasOutputSection) ...[
              const SizedBox(height: 10),
              _HeStructuredToolSection(
                title: widget.isZh ? '结果输出' : 'Tool Output',
                preview: data.outputPreview,
                expanded: _outputExpanded,
                onToggle: () {
                  setState(() {
                    _outputExpanded = !_outputExpanded;
                  });
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data.stdout.isNotEmpty)
                      _HeToolTextPanel(
                        label: 'stdout',
                        content: data.stdout,
                        isZh: widget.isZh,
                        theme: widget.theme,
                        colorScheme: colorScheme,
                      ),
                    if (data.stderr.isNotEmpty) ...[
                      if (data.stdout.isNotEmpty) const SizedBox(height: 10),
                      _HeToolTextPanel(
                        label: 'stderr',
                        content: data.stderr,
                        isZh: widget.isZh,
                        theme: widget.theme,
                        colorScheme: colorScheme,
                        isError: true,
                      ),
                    ],
                    if (data.resultText.isNotEmpty) ...[
                      if (data.stdout.isNotEmpty || data.stderr.isNotEmpty)
                        const SizedBox(height: 10),
                      _HeToolTextPanel(
                        label: widget.isZh ? 'result' : 'result',
                        content: data.resultText,
                        isZh: widget.isZh,
                        theme: widget.theme,
                        colorScheme: colorScheme,
                      ),
                    ],
                    if (data.stdout.isEmpty &&
                        data.stderr.isEmpty &&
                        data.resultText.isEmpty)
                      Text(
                        widget.isZh
                            ? '当前还没有工具输出。'
                            : 'There is no tool output yet.',
                        style: widget.theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeStructuredToolSection extends StatelessWidget {
  const _HeStructuredToolSection({
    required this.title,
    required this.preview,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String preview;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.82),
      borderRadius: _br16,
      child: InkWell(
        onTap: onToggle,
        borderRadius: _br16,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (!expanded && preview.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
              ],
              if (expanded) ...[const SizedBox(height: 12), child],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeToolTextPanel extends StatefulWidget {
  const _HeToolTextPanel({
    required this.label,
    required this.content,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    this.isError = false,
  });

  final String label;
  final String content;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final bool isError;

  @override
  State<_HeToolTextPanel> createState() => _HeToolTextPanelState();
}

class _HeToolTextPanelState extends State<_HeToolTextPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final normalized = widget.content.trimRight();
    final lines = const LineSplitter().convert(normalized);
    final isLong = normalized.length > 900 || lines.length > 18;
    final displayText = isLong && !_expanded
        ? '${lines.take(15).join('\n')}\n\n... [${widget.isZh ? '已折叠，点击右上角展开完整内容' : 'collapsed, expand to view the full content'}]'
        : normalized;
    final accentColor = widget.isError
        ? widget.colorScheme.error
        : widget.colorScheme.onSurfaceVariant;
    final panelSurface = widget.isError
        ? Color.alphaBlend(
            widget.colorScheme.error.withValues(alpha: 0.08),
            widget.colorScheme.surface,
          )
        : widget.colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelSurface,
        borderRadius: _br16,
        border: Border.all(
          color: widget.isError
              ? widget.colorScheme.error.withValues(alpha: 0.24)
              : widget.colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: widget.theme.textTheme.labelLarge?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: normalized.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: normalized));
                      },
                tooltip: widget.isZh ? '复制' : 'Copy',
                icon: const Icon(Icons.content_copy_rounded, size: 16),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  foregroundColor: widget.colorScheme.onSurfaceVariant,
                  minimumSize: const Size(32, 32),
                ),
              ),
              if (isLong)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  },
                  tooltip: widget.isZh
                      ? (_expanded ? '收起' : '展开全部')
                      : (_expanded ? 'Collapse' : 'Expand'),
                  icon: Icon(
                    _expanded
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                    size: 16,
                  ),
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    foregroundColor: widget.colorScheme.primary,
                    minimumSize: const Size(32, 32),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.66,
              ),
              borderRadius: _br16,
              border: Border.all(
                color: widget.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: SelectableText(
                      displayText,
                      style: widget.theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.45,
                        color: widget.isError
                            ? widget.colorScheme.onErrorContainer
                            : widget.colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

({String command, String workingDirectory})? _heSplitToolCommandAndDirectory(
  String raw,
) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final inIndex = trimmed.lastIndexOf(' in ');
  if (inIndex <= 0) {
    return _heLooksLikeToolCommand(trimmed)
        ? (command: trimmed, workingDirectory: '')
        : null;
  }
  final command = trimmed.substring(0, inIndex).trimRight();
  final workingDirectory = trimmed.substring(inIndex + 4).trimLeft();
  if (!_heLooksLikeToolWorkingDirectory(workingDirectory) ||
      !_heLooksLikeToolCommand(command)) {
    return _heLooksLikeToolCommand(trimmed)
        ? (command: trimmed, workingDirectory: '')
        : null;
  }
  return (command: command, workingDirectory: workingDirectory);
}

_HeToolPresentation _heToolPresentationForSegment(
  _HeOutputSegment segment,
  _HeParsedToolHeader? parsedHeader, {
  required bool isZh,
}) {
  final role = (segment.roleLabel ?? '').trim().toLowerCase();
  final command = (parsedHeader?.command ?? '').toLowerCase();
  if (role == 'exec' ||
      command.contains('/bin/zsh') ||
      command.contains('/bin/bash') ||
      command.contains(' zsh ') ||
      command.contains(' bash ')) {
    return const _HeToolPresentation(
      label: 'Bash',
      icon: Icons.terminal_rounded,
      isCommandLike: true,
    );
  }
  if (segment.kind == _HeSegmentKind.toolResult || role == 'tool') {
    return _HeToolPresentation(
      label: isZh ? '工具结果' : 'Tool Result',
      icon: Icons.output_rounded,
      isCommandLike: false,
    );
  }
  if (role == 'function') {
    return _HeToolPresentation(
      label: isZh ? '工具' : 'Tool',
      icon: Icons.build_circle_outlined,
      isCommandLike: false,
    );
  }
  return _HeToolPresentation(
    label: isZh ? '工具' : 'Tool',
    icon: Icons.build_circle_outlined,
    isCommandLike: segment.kind == _HeSegmentKind.toolCall,
  );
}

String _heBuildStructuredToolArguments(
  _HeOutputSegment segment,
  _HeParsedToolHeader? parsedHeader,
) {
  if (parsedHeader != null) {
    final arguments = <String, Object?>{
      if (parsedHeader.command.isNotEmpty) 'cmd': parsedHeader.command,
      if (parsedHeader.workingDirectory.isNotEmpty)
        'cwd': parsedHeader.workingDirectory,
      if ((segment.roleLabel ?? '').trim().isNotEmpty)
        'channel': segment.roleLabel!.trim().toLowerCase(),
    };
    if (arguments.isNotEmpty) {
      return const JsonEncoder.withIndent('  ').convert(arguments);
    }
  }
  if (segment.kind == _HeSegmentKind.toolCall) {
    return _heFormatStructuredToolContent(segment.lines.join('\n'));
  }
  return '';
}

String _heBuildStructuredToolInputPreview({
  required String command,
  required String argumentsText,
}) {
  if (command.isNotEmpty) {
    return '\$ $command';
  }
  final lines = const LineSplitter()
      .convert(argumentsText)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  return lines.isEmpty ? '{}' : lines.first;
}

String _heBuildStructuredToolOutputPreview({
  required bool isZh,
  required String status,
  required String stdout,
  required String stderr,
  required String resultText,
}) {
  final stderrLine = _heLastNonEmptyToolLine(stderr);
  if (stderrLine.isNotEmpty) {
    return 'stderr · $stderrLine';
  }
  final stdoutLine = _heLastNonEmptyToolLine(stdout);
  if (stdoutLine.isNotEmpty) {
    return 'stdout · $stdoutLine';
  }
  final resultLine = _heLastNonEmptyToolLine(resultText);
  if (resultLine.isNotEmpty) {
    return 'result · $resultLine';
  }
  if (status == 'running' || status.isEmpty) {
    return isZh ? '工具运行中，等待新的输出...' : 'Tool is running. Waiting for output...';
  }
  return isZh ? '点击展开查看工具输出' : 'Expand to inspect tool output';
}

String _heNormalizeToolStatus(String rawStatus) {
  switch (rawStatus.trim().toLowerCase()) {
    case 'succeeded':
      return 'success';
    case 'failed':
      return 'failed';
    case 'timed out':
    case 'timed-out':
      return 'timed_out';
    case 'cancelled':
    case 'canceled':
      return 'cancelled';
    case 'denied':
      return 'denied';
    case 'rejected':
      return 'rejected';
    case 'blocked':
      return 'denied';
    default:
      return rawStatus.trim().toLowerCase();
  }
}

String _heToolActionLabel({
  required bool isZh,
  required String status,
  required bool isCommandLike,
}) {
  switch (status) {
    case 'running':
      return isZh ? (isCommandLike ? '执行中' : '调用中') : 'Running';
    case 'success':
      return isZh ? (isCommandLike ? '执行完成' : '调用完成') : 'Completed';
    case 'cancelled':
      return isZh ? '已停止' : 'Stopped';
    case 'denied':
      return isZh ? '已拦截' : 'Blocked';
    case 'rejected':
      return isZh ? '已拒绝' : 'Rejected';
    case 'timed_out':
      return isZh ? (isCommandLike ? '执行超时' : '调用超时') : 'Timed Out';
    case 'failed':
      return isZh ? (isCommandLike ? '执行失败' : '调用失败') : 'Failed';
    default:
      return isZh
          ? (isCommandLike ? '准备执行' : '工具调用')
          : (isCommandLike ? 'Preparing' : 'Tool Call');
  }
}

String _heToolOutcomeLabel({required bool isZh, required String status}) {
  switch (status) {
    case 'running':
      return isZh ? '运行中' : 'Running';
    case 'success':
      return isZh ? '执行成功' : 'Succeeded';
    case 'cancelled':
      return isZh ? '已停止' : 'Stopped';
    case 'denied':
      return isZh ? '已被禁止' : 'Denied';
    case 'rejected':
      return isZh ? '用户拒绝' : 'Rejected';
    case 'timed_out':
      return isZh ? '执行超时' : 'Timed Out';
    case 'failed':
      return isZh ? '执行失败' : 'Failed';
    default:
      return '';
  }
}

IconData _heToolStatusIcon(String status) {
  switch (status) {
    case 'running':
      return Icons.play_circle_outline_rounded;
    case 'success':
      return Icons.check_circle_outline_rounded;
    case 'cancelled':
      return Icons.stop_circle_outlined;
    case 'denied':
      return Icons.block_rounded;
    case 'rejected':
      return Icons.cancel_outlined;
    case 'timed_out':
      return Icons.timer_off_outlined;
    case 'failed':
      return Icons.error_outline_rounded;
    default:
      return Icons.terminal_rounded;
  }
}

int _heParseToolDurationToMs(String rawDuration) {
  final trimmed = rawDuration.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return 0;
  }
  final numeric = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(trimmed);
  final value = double.tryParse(numeric?.group(1) ?? '0') ?? 0;
  if (trimmed.endsWith('ms')) {
    return value.round();
  }
  if (trimmed.endsWith('min') ||
      trimmed.endsWith('mins') ||
      trimmed.endsWith('m')) {
    return (value * 60000).round();
  }
  return (value * 1000).round();
}

String _heFormatToolDuration(int durationMs) {
  final totalSeconds = (durationMs / 1000).floor();
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes}m ${seconds}s';
}

int _heIndexOfFirstMeaningfulLine(List<String> lines) {
  for (var index = 0; index < lines.length; index += 1) {
    if (lines[index].trim().isNotEmpty) {
      return index;
    }
  }
  return -1;
}

bool _heLooksLikeToolCommand(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  return trimmed.startsWith('/') ||
      trimmed.startsWith('./') ||
      trimmed.startsWith('../') ||
      trimmed.startsWith('~/') ||
      trimmed.contains(' -') ||
      trimmed.contains("'") ||
      trimmed.contains('"');
}

bool _heLooksLikeToolWorkingDirectory(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  return trimmed.startsWith('/') ||
      trimmed.startsWith('./') ||
      trimmed.startsWith('../') ||
      trimmed.startsWith('~/');
}

int? _heExtractToolExitCode(List<String> lines) {
  for (final line in lines) {
    final match = _heToolExitCodePattern.firstMatch(line);
    final code = int.tryParse(match?.group(1) ?? '');
    if (code != null) {
      return code;
    }
  }
  return null;
}

String _heFormatStructuredToolContent(String rawContent) {
  final normalized = _heNormalizeToolText(rawContent);
  if (normalized.isEmpty) {
    return '';
  }
  if ((normalized.startsWith('{') && normalized.endsWith('}')) ||
      (normalized.startsWith('[') && normalized.endsWith(']'))) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(normalized));
    } catch (_) {
      return normalized;
    }
  }
  return normalized;
}

String _heNormalizeToolText(String rawContent) {
  return rawContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();
}

String _heLastNonEmptyToolLine(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  return lines.isEmpty ? '' : lines.last;
}

bool _heShouldRenderSegmentAsLogLines(String content) {
  final lines = const LineSplitter().convert(content);
  if (lines.isEmpty || lines.any((line) => line.contains('```'))) {
    return false;
  }

  var matchedLines = 0;
  var markdownishLines = 0;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (_logLevelPattern.hasMatch(trimmed) ||
        trimmed.startsWith('>') ||
        trimmed.startsWith('✓ ') ||
        trimmed.startsWith('✗ ') ||
        trimmed.startsWith('⚠ ') ||
        trimmed.startsWith('▶ ')) {
      matchedLines += 1;
      continue;
    }
    if (trimmed.startsWith('#') ||
        trimmed.startsWith('- ') ||
        trimmed.startsWith('* ') ||
        trimmed.startsWith('|')) {
      markdownishLines += 1;
    }
  }
  return matchedLines > 0 && markdownishLines == 0;
}

class _HeStructuredLogLines extends StatelessWidget {
  const _HeStructuredLogLines({required this.lines, required this.colorScheme});

  final List<String> lines;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: lines.length,
      itemBuilder: (context, index) =>
          _LogLine(line: lines[index], colorScheme: colorScheme),
    );
  }
}

// =============================================================================
// _HeReviewVerdictInfo — parsed review verdict from a userInput segment
// =============================================================================

class _HeReviewVerdictInfo {
  const _HeReviewVerdictInfo({required this.isPass, required this.comment});
  final bool isPass;
  final String comment;
}

/// Parses a userInput segment to detect PASS/FAIL verdict lines.
_HeReviewVerdictInfo? _parseReviewVerdict(_HeOutputSegment seg) {
  if (seg.kind != _HeSegmentKind.userInput) return null;
  final lines = seg.lines;
  if (lines.isEmpty) return null;

  // Look at the first non-empty line for PASS/FAIL.
  bool? isPass;
  int verdictLineIndex = -1;
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    if (trimmed.isEmpty) continue;
    if (trimmed == 'PASS') {
      isPass = true;
      verdictLineIndex = i;
      break;
    }
    if (trimmed == 'FAIL') {
      isPass = false;
      verdictLineIndex = i;
      break;
    }
    // First non-empty line is not PASS/FAIL — not a verdict segment.
    break;
  }
  if (isPass == null) return null;

  // Collect remaining content as comment.
  final commentLines = <String>[];
  for (var i = verdictLineIndex + 1; i < lines.length; i++) {
    commentLines.add(lines[i]);
  }
  final comment = commentLines.join('\n').trim();
  return _HeReviewVerdictInfo(isPass: isPass, comment: comment);
}

// =============================================================================
// _HeReviewVerdictCard — styled card for manual review verdict
// =============================================================================

class _HeReviewVerdictCard extends StatelessWidget {
  const _HeReviewVerdictCard({
    required this.isPass,
    required this.comment,
    required this.roleLabel,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
  });

  final bool isPass;
  final String comment;
  final String roleLabel;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final verdictColor = isPass ? _heCompletedTone : _heFailedTone;
    final bgAlpha = isDark ? 0.22 : 0.10;
    final borderAlpha = isDark ? 0.45 : 0.32;

    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          verdictColor.withValues(alpha: bgAlpha),
          colorScheme.surface,
        ),
        borderRadius: _br18,
        border: Border.all(
          color: verdictColor.withValues(alpha: borderAlpha),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: isDark ? 0.06 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header with role label ──────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.person_rounded,
                  size: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.60),
                ),
                const SizedBox(width: 6),
                Text(
                  roleLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.60),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Verdict banner ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: verdictColor.withValues(alpha: isDark ? 0.20 : 0.12),
                borderRadius: _br12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPass ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    size: 22,
                    color: verdictColor,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isPass
                        ? (isZh ? '验收通过' : 'Review Passed')
                        : (isZh ? '验收未通过' : 'Review Failed'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: verdictColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            // ── Comment body ────────────────────────────────────────
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                comment,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.85),
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// _HeSegmentBody — renders markdown content within a segment card
// =============================================================================

class _HeSegmentBody extends StatelessWidget {
  const _HeSegmentBody({
    required this.content,
    required this.expanded,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    required this.textColor,
    required this.onExpand,
    this.filePathRoots = const [],
  });

  final String content;
  final bool expanded;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final Color textColor;
  final VoidCallback onExpand;
  final List<String> filePathRoots;

  static const int _previewChars = 500;

  String get _displayContent {
    if (expanded) return content;
    final cut = content.lastIndexOf(RegExp(r'\s'), _previewChars);
    final end = cut > 0 ? cut : _previewChars;
    return '${content.substring(0, end.clamp(0, content.length))}…';
  }

  @override
  Widget build(BuildContext context) {
    final displayContent = _displayContent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_heShouldRenderSegmentAsLogLines(displayContent))
          _HeStructuredLogLines(
            lines: const LineSplitter().convert(displayContent),
            colorScheme: colorScheme,
          )
        else
          _HeSafeMarkdownBody(
            content: displayContent,
            theme: theme,
            colorScheme: colorScheme,
            filePathRoots: filePathRoots,
            textColor: textColor,
          ),
        if (!expanded) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onExpand,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: _br16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.expand_more_rounded,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isZh ? '展开全部' : 'Show full content',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Command strip ─────────────────────────────────────────────────────────

class _HeCommandStrip extends StatefulWidget {
  const _HeCommandStrip({required this.command});
  final String command;

  @override
  State<_HeCommandStrip> createState() => _HeCommandStripState();
}

class _HeCommandStripState extends State<_HeCommandStrip>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _turn;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _turn = Tween<double>(
      begin: 0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: _br16,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.terminal_rounded, size: 14, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                firstCurve: Curves.easeOutCubic,
                secondCurve: Curves.easeOutCubic,
                crossFadeState: _expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: Text(
                  widget.command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
                secondChild: SelectableText(
                  widget.command,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            RotationTransition(
              turns: _turn,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Markdown content with collapse/expand ─────────────────────────────────

class _HeSafeMarkdownBody extends StatefulWidget {
  const _HeSafeMarkdownBody({
    required this.content,
    required this.theme,
    required this.colorScheme,
    this.filePathRoots = const [],
    this.textColor,
  });

  final String content;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final List<String> filePathRoots;
  final Color? textColor;

  @override
  State<_HeSafeMarkdownBody> createState() => _HeSafeMarkdownBodyState();
}

class _HeSafeMarkdownBodyState extends State<_HeSafeMarkdownBody>
    implements MarkdownBuilderDelegate {
  List<Widget>? _children;
  String? _lastSanitised;
  int? _lastThemeHash;
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _HeSafeMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildIfNeeded();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _rebuildIfNeeded() {
    final sanitised = _heSanitizeMarkdownSource(widget.content);
    final themeHash = Object.hashAll(<Object?>[
      widget.theme.brightness,
      widget.colorScheme.surface.toARGB32(),
      widget.colorScheme.primary.toARGB32(),
      widget.textColor?.toARGB32(),
      widget.filePathRoots.join('\u0000'),
    ]);

    if (sanitised == _lastSanitised && themeHash == _lastThemeHash) {
      return;
    }

    _lastSanitised = sanitised;
    _lastThemeHash = themeHash;
    if (sanitised.isEmpty) {
      _children = const <Widget>[];
      return;
    }

    _disposeRecognizers();
    _parseMarkdown(sanitised);
  }

  void _parseMarkdown(String source) {
    final effectiveStyleSheet = MarkdownStyleSheet.fromTheme(
      widget.theme,
    ).merge(_heBuildMarkdownStyleSheet(widget.theme, widget.colorScheme));

    final inlineSyntaxes = widget.filePathRoots.isNotEmpty
        ? <md.InlineSyntax>[
            MessagePathCodeSyntax(candidateRoots: widget.filePathRoots),
            MessageFilePathSyntax(candidateRoots: widget.filePathRoots),
          ]
        : const <md.InlineSyntax>[];

    final builders = <String, MarkdownElementBuilder>{
      'pre': _HeDiffBuilder(colorScheme: widget.colorScheme),
      if (widget.filePathRoots.isNotEmpty) ...{
        'openhand-file-resolved': _HeFilePathBuilder(
          textColor: widget.textColor ?? widget.colorScheme.onSurface,
        ),
        'openhand-file-pending': _HeFilePathBuilder(
          textColor: widget.textColor ?? widget.colorScheme.onSurface,
        ),
      },
    };

    try {
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        inlineSyntaxes: inlineSyntaxes,
        encodeHtml: false,
      );
      final astNodes = document.parseLines(
        const LineSplitter().convert(source),
      );
      final builder = MarkdownBuilder(
        delegate: this,
        selectable: true,
        styleSheet: effectiveStyleSheet,
        imageDirectory: null,
        imageBuilder: null,
        checkboxBuilder: null,
        bulletBuilder: null,
        builders: builders,
        paddingBuilders: const <String, MarkdownPaddingBuilder>{},
        listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
      );
      _children = builder.build(astNodes);
    } catch (_) {
      final fallbackStyle = TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: widget.textColor ?? widget.colorScheme.onSurface,
      );
      _children = <Widget>[SelectableText(source, style: fallbackStyle)];
    }
  }

  void _disposeRecognizers() {
    if (_recognizers.isEmpty) {
      return;
    }
    final local = List<GestureRecognizer>.from(_recognizers);
    _recognizers.clear();
    for (final recognizer in local) {
      recognizer.dispose();
    }
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer();
    _recognizers.add(recognizer);
    final resolvedPath = resolveMarkdownMessageLinkPath(
      href,
      widget.filePathRoots,
    );
    if (resolvedPath != null) {
      recognizer.onTap = () {
        Clipboard.setData(ClipboardData(text: resolvedPath.resolvedPath));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Path copied: ${resolvedPath.resolvedPath}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      };
    }
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    final normalizedCode = code.replaceAll(RegExp(r'\n$'), '');
    final resolvedPath = resolveExistingMessagePath(
      normalizedCode,
      widget.filePathRoots,
    );
    if (resolvedPath == null) {
      return TextSpan(text: normalizedCode, style: styleSheet.code);
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        Clipboard.setData(ClipboardData(text: resolvedPath.resolvedPath));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Path copied: ${resolvedPath.resolvedPath}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      };
    _recognizers.add(recognizer);
    final linkColor = widget.colorScheme.primary;
    return TextSpan(
      text: normalizedCode,
      recognizer: recognizer,
      style: styleSheet.code?.copyWith(
        color: linkColor,
        decoration: TextDecoration.underline,
        decorationColor: linkColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    if (children == null || children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _HeMarkdownContent extends StatefulWidget {
  const _HeMarkdownContent({
    required this.content,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    this.filePathRoots = const [],
  });

  final String content;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final List<String> filePathRoots;

  // When the rendered content looks long, start collapsed.
  static const int _collapseCharThreshold = 1800;
  static const int _previewChars = 1200;

  @override
  State<_HeMarkdownContent> createState() => _HeMarkdownContentState();
}

class _HeMarkdownContentState extends State<_HeMarkdownContent>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  bool get _needsCollapse =>
      widget.content.length > _HeMarkdownContent._collapseCharThreshold;

  String get _displayContent {
    if (!_needsCollapse || _expanded) return widget.content;
    // Find the last word boundary before the char limit.
    final cut = widget.content.lastIndexOf(
      RegExp(r'\s'),
      _HeMarkdownContent._previewChars,
    );
    final end = cut > 0 ? cut : _HeMarkdownContent._previewChars;
    return '${widget.content.substring(0, end)}…';
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..value = 1.0;
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _expand() {
    _fadeCtrl.value = 0;
    setState(() => _expanded = true);
    _fadeCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    final isZh = widget.isZh;
    final colorScheme = widget.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeTransition(
          opacity: _fadeAnim,
          child: _HeSafeMarkdownBody(
            content: _displayContent,
            theme: widget.theme,
            colorScheme: colorScheme,
            filePathRoots: widget.filePathRoots,
          ),
        ),
        if (_needsCollapse && !_expanded) ...[
          const SizedBox(height: 6),
          // Fading gradient overlay + expand button
          ClipRect(
            child: Column(
              children: [
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colorScheme.surface.withValues(alpha: 0),
                        colorScheme.surface.withValues(alpha: 0.80),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _expand,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: _br16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isZh ? '展开全部内容' : 'Show full content',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// _HeSmallPill — compact action chip used in the log section header
// =============================================================================

class _HeSmallPill extends StatelessWidget {
  const _HeSmallPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: _br999,
      child: InkWell(
        onTap: onTap,
        borderRadius: _br999,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: colorScheme.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Log line — renders one CLI output line with level-based colouring
// Used only in the raw view.
// =============================================================================

class _LogLine extends StatelessWidget {
  const _LogLine({required this.line, required this.colorScheme});

  final String line;
  final ColorScheme colorScheme;

  Color? _resolveColor() {
    if (line.startsWith('\u2713')) return const Color(0xFF4CAF50);
    if (line.startsWith('\u2717')) return colorScheme.error;
    if (line.startsWith('>')) return colorScheme.primary;
    if (line.startsWith('\u25b6')) return colorScheme.secondary;
    if (line.startsWith('\u26a0')) return colorScheme.tertiary;
    final match = _logLevelPattern.firstMatch(line);
    if (match != null) {
      final level = match.group(0)!.toUpperCase();
      switch (level) {
        case 'ERROR':
        case 'ERR':
          return colorScheme.error;
        case 'WARN':
        case 'WARNING':
          return const Color(0xFFF59E0B);
        case 'INFO':
          return colorScheme.primary;
        case 'DEBUG':
          return colorScheme.onSurfaceVariant.withValues(alpha: 0.65);
        case 'TRACE':
          return colorScheme.onSurfaceVariant.withValues(alpha: 0.45);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    FontWeight? weight;
    final color = _resolveColor();
    if (line.startsWith('\u2713') ||
        line.startsWith('\u2717') ||
        line.startsWith('\u25b6')) {
      weight = FontWeight.w600;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: SelectableText(
        line.isEmpty ? '\u200B' : line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.55,
          color: color ?? colorScheme.onSurface.withValues(alpha: 0.87),
          fontWeight: weight,
        ),
      ),
    );
  }
}

// =============================================================================
// _HeDiffBuilder — MarkdownElementBuilder that intercepts fenced code blocks
// whose language tag is "diff" or "patch" and renders them with a dedicated
// side-by-side / unified diff widget instead of a plain code block.
// =============================================================================

class _HeDiffBuilder extends MarkdownElementBuilder {
  _HeDiffBuilder({required this.colorScheme});

  final ColorScheme colorScheme;

  static final _diffLangRe = RegExp(
    r'\blanguage-(diff|patch|udiff)\b',
    caseSensitive: false,
  );

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // We intercept <pre> elements.  The child <code> carries the language class
    // and the text content.
    if (element.tag != 'pre') return null;

    final codeEl = element.children
        ?.whereType<md.Element>()
        .where((e) => e.tag == 'code')
        .firstOrNull;

    if (codeEl == null) return null;

    final cls = codeEl.attributes['class'] ?? '';
    if (!_diffLangRe.hasMatch(cls)) return null;

    // Collect plain text from all descendant text nodes.
    final buf = StringBuffer();
    void collect(md.Node node) {
      if (node is md.Text) {
        buf.write(node.text);
      } else if (node is md.Element) {
        node.children?.forEach(collect);
      }
    }

    codeEl.children?.forEach(collect);

    final rawText = buf.toString();
    if (rawText.isEmpty) return null;

    return _HeDiffBlock(rawDiff: rawText, colorScheme: colorScheme);
  }
}

// =============================================================================
// _HeDiffBlock — renders a unified diff with coloured line backgrounds.
// =============================================================================

class _HeDiffBlock extends StatelessWidget {
  const _HeDiffBlock({required this.rawDiff, required this.colorScheme});

  final String rawDiff;
  final ColorScheme colorScheme;

  static const _addedBg = Color(0xFF1A3D1A);
  static const _addedBgLight = Color(0xFFE6F4E6);
  static const _removedBg = Color(0xFF3D1A1A);
  static const _removedBgLight = Color(0xFFF4E6E6);
  static const _hunkBg = Color(0xFF1A2B3D);
  static const _hunkBgLight = Color(0xFFE6EEF4);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lines = rawDiff.split('\n');

    // Remove a trailing empty line that the Markdown parser often appends.
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final trimmed = lines;

    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: _br16,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.40),
          ),
        ),
        child: ClipRRect(
          borderRadius: _br16,
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            addRepaintBoundaries: false, // each row is simple — skip overhead
            itemCount: trimmed.length,
            itemBuilder: (_, i) =>
                _DiffLine(line: trimmed[i], isDark: isDark, cs: colorScheme),
          ),
        ),
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line, required this.isDark, required this.cs});

  final String line;
  final bool isDark;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    Color? bg;
    Color fg;
    FontWeight weight = FontWeight.normal;

    if (line.startsWith('+++') || line.startsWith('---')) {
      fg = cs.secondary;
      weight = FontWeight.w600;
    } else if (line.startsWith('+')) {
      bg = isDark
          ? _HeDiffBlock._addedBg.withValues(alpha: 0.55)
          : _HeDiffBlock._addedBgLight;
      fg = isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    } else if (line.startsWith('-')) {
      bg = isDark
          ? _HeDiffBlock._removedBg.withValues(alpha: 0.55)
          : _HeDiffBlock._removedBgLight;
      fg = isDark ? const Color(0xFFE57373) : cs.error;
    } else if (line.startsWith('@@')) {
      bg = isDark
          ? _HeDiffBlock._hunkBg.withValues(alpha: 0.55)
          : _HeDiffBlock._hunkBgLight;
      fg = isDark ? const Color(0xFF90CAF9) : cs.primary;
      weight = FontWeight.w600;
    } else {
      fg = cs.onSurface.withValues(alpha: 0.80);
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
      child: SelectableText(
        line.isEmpty ? '\u200B' : line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.6,
          color: fg,
          fontWeight: weight,
        ),
      ),
    );
  }
}

/// Closes an unterminated fenced code block so the Markdown parser/// never produces garbage output on streaming/partial content.
String _heCloseUnterminatedCodeBlock(String source) {
  final fenceRe = RegExp(r'^[ ]{0,3}(`{3,}|~{3,})[^\n]*$', multiLine: true);
  String? openFence;
  String? openMarker;
  for (final match in fenceRe.allMatches(source)) {
    final delim = match.group(1)!;
    final marker = delim[0];
    if (openFence == null) {
      openFence = delim;
      openMarker = marker;
    } else if (marker == openMarker && delim.length >= openFence.length) {
      openFence = null;
      openMarker = null;
    }
  }
  if (openFence == null) return source;
  return '$source\n$openFence';
}

String _heSanitizeMarkdownSource(String source) {
  if (source.isEmpty) {
    return source;
  }
  final escapedSetext = source.replaceAllMapped(
    _heSetextEscapePattern,
    (m) => '${m[1]}${m[2]}\\${m[3]}',
  );
  return _heCloseUnterminatedCodeBlock(escapedSetext);
}

// =============================================================================
// _HePill — matches _ToolbarPill (surfaceContainerHighest bg, primary icon, h:32)
// =============================================================================

class _HePill extends StatelessWidget {
  const _HePill({
    required this.icon,
    required this.label,
    this.onTap,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedForeground = foregroundColor ?? theme.colorScheme.primary;
    final child = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: _br999,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: resolvedForeground),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor ?? theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      borderRadius: _br999,
      child: InkWell(
        onTap: onTap,
        borderRadius: _br999,
        overlayColor: WidgetStatePropertyAll<Color>(
          theme.colorScheme.primary.withValues(alpha: 0.08),
        ),
        child: child,
      ),
    );
  }
}

// =============================================================================
// _HeOutputLinesDial — mirrors _TokenDial but for CLI output lines
// Displays total output lines from all phase logs as a proxy for activity.
// =============================================================================

class _HeOutputLinesDial extends StatelessWidget {
  const _HeOutputLinesDial({required this.totalLines});

  final int totalLines;

  String _format(int n) {
    if (n == 0) return '--';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: _br999,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terminal_rounded, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            _format(totalLines),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Lines',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// _HeChip — matches _ToolExecutionChip (surface overlay bg, rounded)
// =============================================================================

class _HeChip extends StatelessWidget {
  const _HeChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: _br999,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

// =============================================================================
// _HeReadyPlaceholder — idle orchestrator (restored from disk); tap Start
// =============================================================================

class _HeReadyPlaceholder extends StatelessWidget {
  const _HeReadyPlaceholder({required this.isZh, required this.onStart});

  final bool isZh;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction_rounded,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            isZh
                ? '就绪，点击下方按钮以启动本次会话'
                : 'Ready \u2014 press Start to run the session',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(isZh ? '开始执行' : 'Start'),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// _InitializingPlaceholder — spinner while phases are being set up
// =============================================================================

class _InitializingPlaceholder extends StatelessWidget {
  const _InitializingPlaceholder({required this.isZh});

  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isZh ? '初始化中...' : 'Initializing\u2026',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _HeRestoredSessionPlaceholder extends StatelessWidget {
  const _HeRestoredSessionPlaceholder({
    required this.isZh,
    required this.status,
    required this.onRestart,
  });

  final bool isZh;
  final HardnessOrchestratorStatus status;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, title) = switch (status) {
      HardnessOrchestratorStatus.completed => (
        Icons.check_circle_rounded,
        isZh ? '历史会话已恢复' : 'Historical session restored',
      ),
      HardnessOrchestratorStatus.failed => (
        Icons.error_rounded,
        isZh ? '历史失败会话已恢复' : 'Failed session restored',
      ),
      HardnessOrchestratorStatus.cancelled => (
        Icons.cancel_rounded,
        isZh ? '历史中止会话已恢复' : 'Cancelled session restored',
      ),
      _ => (
        Icons.history_rounded,
        isZh ? '历史会话已恢复' : 'Historical session restored',
      ),
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isZh
                  ? '该会话来自旧版持久化数据，未保存可回放的阶段日志，因此无法还原阶段卡片。'
                  : 'This session was restored from an older persisted snapshot that did not save replayable phase logs.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRestart,
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(isZh ? '重新执行' : 'Run Again'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// _HeComposer — HE composer with active permission toggle, collapse state,
// auto-follow control, and a conditional manual-review input.
// =============================================================================

class _HeComposer extends StatelessWidget {
  const _HeComposer({
    required this.isZh,
    required this.isCollapsed,
    required this.onCollapsedChanged,
    required this.autoFollowEnabled,
    required this.onToggleAutoFollow,
    required this.fullAccessPermission,
    required this.onToggleFullAccessPermission,
    required this.manualPhaseEnabled,
    required this.manualPhaseTitle,
    required this.manualPhaseController,
    required this.manualPhaseFocusNode,
    required this.manualPhaseHelperText,
    required this.manualPhaseHintText,
    required this.primaryActionLabel,
    required this.primaryActionIcon,
    required this.primaryActionEnabled,
    required this.onPrimaryAction,
    this.isManualReviewPhase = false,
    this.onReviewPass,
    this.onReviewFail,
    this.reviewSubmitting = false,
  });

  final bool isZh;
  final bool isCollapsed;
  final ValueChanged<bool> onCollapsedChanged;
  final bool autoFollowEnabled;
  final VoidCallback onToggleAutoFollow;
  final bool fullAccessPermission;
  final ValueChanged<bool> onToggleFullAccessPermission;
  final bool manualPhaseEnabled;
  final String manualPhaseTitle;
  final TextEditingController manualPhaseController;
  final FocusNode manualPhaseFocusNode;
  final String manualPhaseHelperText;
  final String manualPhaseHintText;
  final String primaryActionLabel;
  final IconData primaryActionIcon;
  final bool primaryActionEnabled;
  final VoidCallback onPrimaryAction;

  /// Whether the manual input is for the reviewing phase.
  final bool isManualReviewPhase;

  /// Callback for explicit PASS verdict during manual review.
  final VoidCallback? onReviewPass;

  /// Callback for explicit FAIL verdict during manual review.
  final VoidCallback? onReviewFail;

  /// Whether a review verdict is currently being submitted.
  final bool reviewSubmitting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disabledFg = colorScheme.onSurface.withValues(alpha: 0.38);
    final disabledBorder = colorScheme.outlineVariant.withValues(alpha: 0.48);
    final disabledBg = colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.78,
    );

    Widget disabledOutlinedButton({
      required IconData icon,
      required String label,
    }) {
      return SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: null,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            disabledForegroundColor: disabledFg,
            side: BorderSide(color: disabledBorder),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: disabledBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    // The permission button — active, not disabled.
    final buttonFg = fullAccessPermission
        ? const Color(0xFFF59E0B)
        : colorScheme.onSurfaceVariant;
    final buttonBg = fullAccessPermission
        ? const Color(0xFFFBBF24).withValues(alpha: 0.15)
        : colorScheme.surfaceContainerHighest;
    final buttonBorderColor = fullAccessPermission
        ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
        : colorScheme.outlineVariant;
    final permissionButton = SizedBox(
      height: 52,
      child: Builder(
        builder: (btnContext) {
          return OutlinedButton(
            onPressed: () {
              final button =
                  btnContext.findRenderObject()! as RenderBox;
              final overlay = Navigator.of(btnContext)
                  .overlay!
                  .context
                  .findRenderObject()! as RenderBox;
              final position = RelativeRect.fromRect(
                Rect.fromPoints(
                  button.localToGlobal(Offset.zero, ancestor: overlay),
                  button.localToGlobal(
                    button.size.bottomRight(Offset.zero),
                    ancestor: overlay,
                  ),
                ),
                Offset.zero & overlay.size,
              );
              showAnimatedMenu<bool>(
                context: btnContext,
                position: position,
                items: [
                  PopupMenuItem<bool>(
                    value: false,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isZh ? '默认权限' : 'Default Access',
                          ),
                        ),
                        if (!fullAccessPermission)
                          const Icon(Icons.check_rounded, size: 20)
                        else
                          const SizedBox(width: 20),
                      ],
                    ),
                  ),
                  PopupMenuItem<bool>(
                    value: true,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.gpp_maybe_outlined,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isZh ? '完全访问权限' : 'Full Access',
                          ),
                        ),
                        if (fullAccessPermission)
                          const Icon(Icons.check_rounded, size: 20)
                        else
                          const SizedBox(width: 20),
                      ],
                    ),
                  ),
                ],
              ).then((value) {
                if (value != null) onToggleFullAccessPermission(value);
              });
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              backgroundColor: buttonBg,
              foregroundColor: buttonFg,
              side: BorderSide(color: buttonBorderColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  fullAccessPermission
                      ? Icons.gpp_maybe_outlined
                      : Icons.admin_panel_settings_outlined,
                  size: 18,
                  color: buttonFg,
                ),
                const SizedBox(width: 8),
                Text(
                  fullAccessPermission
                      ? (isZh ? '完全访问权限' : 'Full Access')
                      : (isZh ? '默认权限' : 'Default Access'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: buttonFg,
                ),
              ],
            ),
          );
        },
      ),
    );

    final manualPhaseTitleStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: colorScheme.primary,
    );
    final manualPhaseHelperStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      height: 1.45,
    );
    final manualPhaseHintStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
    );
    final manualPhaseInputStyle = theme.textTheme.bodyMedium?.copyWith(
      height: 1.45,
    );

    double measureTextHeight(String text, TextStyle? style, double maxWidth) {
      if (!maxWidth.isFinite || maxWidth <= 0) {
        return 0;
      }

      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
      )..layout(maxWidth: maxWidth);

      return painter.size.height;
    }

    final expandedContent = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubicEmphasized,
      width: double.infinity,
      height: manualPhaseEnabled ? 176 : 80,
      decoration: BoxDecoration(
        color: manualPhaseEnabled
            ? colorScheme.surfaceContainerLow
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: _br16,
        border: Border.all(
          color: manualPhaseEnabled
              ? colorScheme.primary.withValues(alpha: 0.28)
              : disabledBorder,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: manualPhaseEnabled
          ? LayoutBuilder(
              builder: (context, constraints) {
                const titleGap = 6.0;
                const editorGap = 10.0;
                const minEditorHeight = 48.0;

                final titleHeight = measureTextHeight(
                  manualPhaseTitle,
                  manualPhaseTitleStyle,
                  constraints.maxWidth,
                );
                final helperHeight = measureTextHeight(
                  manualPhaseHelperText,
                  manualPhaseHelperStyle,
                  constraints.maxWidth,
                );
                final canShowHelper =
                    constraints.maxHeight >=
                    titleHeight + titleGap + helperHeight;
                final reservedHeight =
                    titleHeight + (canShowHelper ? titleGap + helperHeight : 0);
                final remainingHeight = constraints.maxHeight - reservedHeight;
                final canShowEditor =
                    remainingHeight >= editorGap + minEditorHeight;
                final editorHeight = canShowEditor
                    ? (remainingHeight - editorGap).clamp(0.0, double.infinity)
                    : 0.0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manualPhaseTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: manualPhaseTitleStyle,
                    ),
                    if (canShowHelper) ...[
                      const SizedBox(height: titleGap),
                      Text(
                        manualPhaseHelperText,
                        style: manualPhaseHelperStyle,
                      ),
                    ],
                    if (canShowEditor) ...[
                      const SizedBox(height: editorGap),
                      SizedBox(
                        height: editorHeight,
                        child: TextField(
                          controller: manualPhaseController,
                          focusNode: manualPhaseFocusNode,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            hintText: manualPhaseHintText,
                            hintStyle: manualPhaseHintStyle,
                          ),
                          style: manualPhaseInputStyle,
                        ),
                      ),
                    ],
                  ],
                );
              },
            )
          : Align(
              alignment: Alignment.topLeft,
              child: Text(
                isZh
                    ? 'Hardness Engineering 使用自动化流水线，不支持手动输入'
                    : 'Hardness Engineering uses an automated pipeline; manual input is not available',
                style: theme.textTheme.bodyMedium?.copyWith(color: disabledFg),
              ),
            ),
    );

    final actionRow = Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                disabledOutlinedButton(icon: Icons.hub_outlined, label: '--'),
                const SizedBox(width: 10),
                disabledOutlinedButton(
                  icon: Icons.attach_file_rounded,
                  label: isZh ? '附件' : 'Attach',
                ),
                const SizedBox(width: 10),
                permissionButton,
                const SizedBox(width: 10),
                disabledOutlinedButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: isZh ? '聊天模式' : 'Chat Mode',
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
        Tooltip(
          message: isZh
              ? (isCollapsed ? '展开输入框' : '折叠输入框')
              : (isCollapsed ? 'Expand Composer' : 'Collapse Composer'),
          child: SizedBox(
            width: 52,
            height: 52,
            child: FilledButton(
              onPressed: () => onCollapsedChanged(!isCollapsed),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(52, 52),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: Icon(
                isCollapsed
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          height: 52,
          child: FilledButton(
            onPressed: onToggleAutoFollow,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(52, 52),
              backgroundColor: autoFollowEnabled
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              foregroundColor: autoFollowEnabled
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
              side: autoFollowEnabled
                  ? null
                  : BorderSide(color: colorScheme.outlineVariant),
            ),
            child: Icon(
              autoFollowEnabled
                  ? Icons.vertical_align_bottom_rounded
                  : Icons.vertical_align_bottom_outlined,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // When manual review is active for the reviewing phase, show
        // explicit Pass / Fail verdict buttons instead of a single Send.
        if (manualPhaseEnabled && isManualReviewPhase) ...[
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: (primaryActionEnabled && !reviewSubmitting)
                  ? onReviewFail
                  : null,
              icon: Icon(
                reviewSubmitting
                    ? Icons.hourglass_top_rounded
                    : Icons.thumb_down_alt_rounded,
                size: 18,
              ),
              label: Text(
                reviewSubmitting
                    ? (isZh ? '提交中' : 'Submitting')
                    : (isZh ? '验收不通过' : 'Fail'),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(
                  color: colorScheme.error.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: (primaryActionEnabled && !reviewSubmitting)
                  ? onReviewPass
                  : null,
              icon: Icon(
                reviewSubmitting
                    ? Icons.hourglass_top_rounded
                    : Icons.thumb_up_alt_rounded,
                size: 18,
              ),
              label: Text(
                reviewSubmitting
                    ? (isZh ? '提交中' : 'Submitting')
                    : (isZh ? '验收通过' : 'Pass'),
              ),
            ),
          ),
        ] else
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: primaryActionEnabled ? onPrimaryAction : null,
              icon: Icon(primaryActionIcon, size: 18),
              label: Text(primaryActionLabel),
            ),
          ),
      ],
    );

    return Card(
      color: colorScheme.surfaceContainerHigh,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubicEmphasized,
        padding: EdgeInsets.fromLTRB(18, 14, 18, isCollapsed ? 10 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: isCollapsed ? 1 : 0,
                end: isCollapsed ? 0 : 1,
              ),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOutCubicEmphasized,
              child: expandedContent,
              builder: (context, value, child) {
                return ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: value,
                    child: IgnorePointer(
                      ignoring: value < 0.98,
                      child: Opacity(
                        opacity: value.clamp(0, 1).toDouble(),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOutCubicEmphasized,
              height: isCollapsed ? 0 : 14,
            ),
            actionRow,
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// _HePhaseApprovalBanner — shown between phases when user approval is needed
// =============================================================================

class _HePhaseApprovalBanner extends StatelessWidget {
  const _HePhaseApprovalBanner({
    required this.isZh,
    required this.nextPhase,
    this.approvalIssue,
    required this.manualPhaseEnabled,
    required this.hasQueuedManualPhaseInput,
    required this.manualPhaseActionLabel,
    required this.manualPhaseSwitchBackLabel,
    required this.manualPhaseActiveDescription,
    required this.manualPhaseQueuedDescription,
    required this.manualPhaseIcon,
    this.onManualPhaseToggle,
    required this.onApprove,
    required this.onReject,
  });

  final bool isZh;
  final HardnessPhase nextPhase;
  final String? approvalIssue;
  final bool manualPhaseEnabled;
  final bool hasQueuedManualPhaseInput;
  final String manualPhaseActionLabel;
  final String manualPhaseSwitchBackLabel;
  final String manualPhaseActiveDescription;
  final String manualPhaseQueuedDescription;
  final IconData manualPhaseIcon;
  final VoidCallback? onManualPhaseToggle;
  final VoidCallback? onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const accent = _hePausedTone;
    final backgroundColor = Color.alphaBlend(
      accent.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.24 : 0.12,
      ),
      colorScheme.surface,
    );
    final phaseName = isZh ? nextPhase.displayNameZh : nextPhase.displayNameEn;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: _br16,
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pause_circle_filled_rounded,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isZh
                      ? '即将推进到下一阶段：$phaseName'
                      : 'Ready to advance to next phase: $phaseName',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isZh
                ? '请确认是否继续执行，或中止流水线。'
                : 'Confirm to continue, or abort the pipeline.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (onManualPhaseToggle != null && manualPhaseEnabled) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  accent.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.16 : 0.10,
                  ),
                  colorScheme.surface,
                ),
                borderRadius: _br16,
                border: Border.all(color: accent.withValues(alpha: 0.24)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(manualPhaseIcon, size: 16, color: accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      manualPhaseActiveDescription,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (onManualPhaseToggle != null &&
              hasQueuedManualPhaseInput) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  colorScheme.primary.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.14 : 0.08,
                  ),
                  colorScheme.surface,
                ),
                borderRadius: _br16,
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      manualPhaseQueuedDescription,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (approvalIssue != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  _heFailedTone.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.18 : 0.08,
                  ),
                  colorScheme.surface,
                ),
                borderRadius: _br16,
                border: Border.all(
                  color: _heFailedTone.withValues(alpha: 0.24),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: _heFailedTone,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      approvalIssue!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onManualPhaseToggle != null) ...[
                OutlinedButton.icon(
                  onPressed: onManualPhaseToggle,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent.withValues(alpha: 0.34)),
                  ),
                  icon: Icon(
                    manualPhaseEnabled
                        ? Icons.smart_toy_outlined
                        : manualPhaseIcon,
                    size: 18,
                  ),
                  label: Text(
                    manualPhaseEnabled
                        ? manualPhaseSwitchBackLabel
                        : manualPhaseActionLabel,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              OutlinedButton(
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  side: BorderSide(
                    color: colorScheme.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(isZh ? '中止' : 'Abort'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onApprove,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(isZh ? '继续' : 'Continue'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// _HePendingPhaseEditor — allows changing CLI/model for a pending phase
// =============================================================================

class _HePendingPhaseEditor extends StatelessWidget {
  const _HePendingPhaseEditor({
    required this.roleConfig,
    required this.isZh,
    required this.onChanged,
  });

  final HardnessRoleConfig roleConfig;
  final bool isZh;
  final ValueChanged<HardnessRoleConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cliNames = kHardnessCliCatalog
        .where((c) => c.supportsHeadless)
        .toList();
    final settingsController = Provider.of<SettingsController?>(
      context,
      listen: false,
    );
    final settingsModels =
        settingsController?.aiModels ?? const <AiModelConfig>[];
    final configuredAiModelConfigId = roleConfig.aiModelConfigId?.trim();
    final hasConfiguredAiModelConfig =
        configuredAiModelConfigId != null &&
        configuredAiModelConfigId.isNotEmpty;
    final hasMatchingAiModelConfig =
        hasConfiguredAiModelConfig &&
        settingsModels.any((item) => item.id == configuredAiModelConfigId);
    final effectiveAiModelConfigId = _hePreferredAiModelConfigId(
      settingsModels: settingsModels,
      configuredId: roleConfig.aiModelConfigId,
      fallbackId: settingsController?.selectedAiModelId,
    );
    final aiModelConfigItems = _heAiModelConfigDropdownItems(
      context,
      settingsModels: settingsModels,
      configuredId: roleConfig.aiModelConfigId,
      configuredModelId: roleConfig.urlModeModelId,
      isZh: isZh,
    );
    final selectedAiModelConfigId = _heResolvedAiModelConfigDropdownValue(
      aiModelConfigItems,
      roleConfig.aiModelConfigId,
      roleConfig.urlModeModelId,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.65),
        borderRadius: _br16,
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isZh ? '更改执行配置' : 'Change Execution Config',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          // Execution mode toggle row.
          Row(
            children: [
              ChoiceChip(
                label: Text('CLI', style: theme.textTheme.bodySmall),
                selected: roleConfig.isCliMode,
                onSelected: (selected) {
                  if (selected) {
                    onChanged(
                      roleConfig.copyWith(
                        executionMode: HardnessExecutionMode.cli,
                      ),
                    );
                  }
                },
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('URL/API', style: theme.textTheme.bodySmall),
                selected: roleConfig.isUrlMode,
                onSelected: (selected) {
                  if (selected) {
                    onChanged(
                      roleConfig.copyWith(
                        executionMode: HardnessExecutionMode.url,
                        aiModelConfigId: effectiveAiModelConfigId,
                        clearAiModelConfigId:
                            effectiveAiModelConfigId == null &&
                            !hasConfiguredAiModelConfig,
                      ),
                    );
                  }
                },
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (roleConfig.isUrlMode)
            DropdownButtonFormField<String>(
              key: const ValueKey<String>('he-api-model-config-dropdown'),
              initialValue: selectedAiModelConfigId,
              decoration: InputDecoration(
                labelText: isZh ? 'API 模型' : 'API Model',
                helperText: settingsModels.isEmpty
                    ? (isZh
                          ? '请先在设置中配置 API 模型提供商，然后在这里选择。'
                          : 'Configure API model providers in Settings first, then choose one here.')
                    : (hasConfiguredAiModelConfig && !hasMatchingAiModelConfig)
                    ? (isZh
                          ? '当前配置已在设置中删除，请重新选择有效模型。'
                          : 'The current config was deleted from Settings. Choose a valid model.')
                    : null,
                helperMaxLines: 2,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              style: theme.textTheme.bodySmall,
              items: aiModelConfigItems,
              onChanged: settingsModels.isEmpty
                  ? null
                  : (value) {
                      if (value == null) return;
                      final decoded = _heDecodeModelKey(value);
                      if (decoded != null) {
                        onChanged(
                          roleConfig.copyWith(
                            aiModelConfigId: decoded.$1,
                            urlModeModelId: decoded.$2,
                          ),
                        );
                      }
                    },
            )
          else
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        cliNames.any((c) => c.name == roleConfig.cliName)
                        ? roleConfig.cliName
                        : null,
                    decoration: InputDecoration(
                      labelText: 'CLI',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: cliNames.map((cli) {
                      return DropdownMenuItem(
                        value: cli.name,
                        child: Text(
                          cli.name,
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final currentModelId = roleConfig.modelId.trim();
                      onChanged(
                        roleConfig.copyWith(
                          cliName: value,
                          modelId: currentModelId,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeModelDropdown(
                    roleConfig: roleConfig,
                    isZh: isZh,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HeModelDropdown extends StatelessWidget {
  const _HeModelDropdown({
    required this.roleConfig,
    required this.isZh,
    required this.onChanged,
  });

  final HardnessRoleConfig roleConfig;
  final bool isZh;
  final ValueChanged<HardnessRoleConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cli = kHardnessCliCatalog
        .where((c) => c.name == roleConfig.cliName)
        .firstOrNull;
    final models = cli?.knownModels ?? const [];
    final configuredModelId = roleConfig.modelId.trim();

    if (models.isEmpty) {
      // Free-form text field for model ID.
      return TextFormField(
        key: ValueKey<String>('he-model-text-${roleConfig.cliName}'),
        initialValue: roleConfig.modelId,
        decoration: InputDecoration(
          labelText: isZh ? '模型' : 'Model',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        style: theme.textTheme.bodySmall,
        onChanged: (value) =>
            onChanged(roleConfig.copyWith(modelId: value.trim())),
      );
    }

    final items = <DropdownMenuItem<String>>[];
    if (configuredModelId.isNotEmpty && !models.contains(configuredModelId)) {
      items.add(
        DropdownMenuItem<String>(
          value: configuredModelId,
          child: Text(
            describeHardnessCliModel(cli, configuredModelId, isZh: isZh),
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: items.any((item) => item.value == configuredModelId)
          ? configuredModelId
          : (models.contains(configuredModelId) ? configuredModelId : null),
      decoration: InputDecoration(
        labelText: isZh ? '模型' : 'Model',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        ...items,
        ...models.map((m) {
          return DropdownMenuItem(
            value: m,
            child: Text(
              describeHardnessCliModel(cli, m, isZh: isZh),
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
      ],
      onChanged: (value) {
        if (value == null) return;
        onChanged(roleConfig.copyWith(modelId: value));
      },
    );
  }
}

// =============================================================================
// _HeChangedFilesList — shows files changed during a phase execution
// =============================================================================

class _HeChangedFilesList extends StatelessWidget {
  const _HeChangedFilesList({required this.files, required this.isZh});

  final List<HardnessChangedFile> files;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: _br16,
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.difference_rounded,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                isZh
                    ? '文件变动 (${files.length})'
                    : 'Changed Files (${files.length})',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final (icon, iconColor) = switch (file.changeType) {
                HardnessFileChangeType.added => (
                  Icons.add_circle_outline_rounded,
                  const Color(0xFF4CAF50),
                ),
                HardnessFileChangeType.modified => (
                  Icons.edit_outlined,
                  colorScheme.primary,
                ),
                HardnessFileChangeType.deleted => (
                  Icons.remove_circle_outline_rounded,
                  colorScheme.error,
                ),
              };
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: _br999,
                  onTap: () => _showDiffDialog(context, file),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 14, color: iconColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            file.relativePath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showDiffDialog(BuildContext context, HardnessChangedFile file) {
    showAnimatedDialog(
      context: context,
      builder: (ctx) => _HeFileDiffDialog(file: file, isZh: isZh),
    );
  }
}

// =============================================================================
// _HeFileDiffDialog — full-width dialog showing file content diff.
// Computes diff asynchronously in an isolate to keep the UI responsive.
// =============================================================================

/// Isolate-friendly top-level function for diff computation.
List<String> _computeDiffIsolate(List<Object> args) {
  final before = (args[0] as String).split('\n');
  final after = (args[1] as String).split('\n');
  return _computeSimpleUnifiedDiff(before, after);
}

class _HeFileDiffDialog extends StatefulWidget {
  const _HeFileDiffDialog({required this.file, required this.isZh});

  final HardnessChangedFile file;
  final bool isZh;

  @override
  State<_HeFileDiffDialog> createState() => _HeFileDiffDialogState();
}

class _HeFileDiffDialogState extends State<_HeFileDiffDialog> {
  List<String>? _diffLines;
  bool _computing = true;

  @override
  void initState() {
    super.initState();
    _computeDiff();
  }

  Future<void> _computeDiff() async {
    final before = widget.file.beforeContent ?? '';
    final after = widget.file.afterContent ?? '';
    try {
      final result = await compute(_computeDiffIsolate, <Object>[
        before,
        after,
      ]);
      if (mounted) {
        setState(() {
          _diffLines = result;
          _computing = false;
        });
      }
    } catch (_) {
      // Fallback: compute on main thread.
      if (!mounted) return;
      final result = _computeSimpleUnifiedDiff(
        before.split('\n'),
        after.split('\n'),
      );
      if (mounted) {
        setState(() {
          _diffLines = result;
          _computing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isZh = widget.isZh;
    final file = widget.file;
    final diffLines = _diffLines ?? const <String>[];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 900,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ──
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.relativePath,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _DiffStatChip(
                              label: _changeTypeLabel(),
                              color: switch (file.changeType) {
                                HardnessFileChangeType.added => const Color(
                                  0xFF4CAF50,
                                ),
                                HardnessFileChangeType.modified =>
                                  colorScheme.primary,
                                HardnessFileChangeType.deleted =>
                                  colorScheme.error,
                              },
                            ),
                            if (!_computing) ...[
                              const SizedBox(width: 8),
                              Text(
                                '${diffLines.where((l) => l.startsWith('+')).length - 1} additions, '
                                '${diffLines.where((l) => l.startsWith('-')).length - 1} deletions',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // ── Diff view ──
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: _br16,
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.40),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: _br16,
                    child: _computing
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  Text(
                                    isZh ? '正在计算差异…' : 'Computing diff…',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: diffLines.length,
                            itemBuilder: (_, i) => _DiffLine(
                              line: diffLines[i],
                              isDark: isDark,
                              cs: colorScheme,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: _computing
                        ? null
                        : () {
                            Clipboard.setData(
                              ClipboardData(text: diffLines.join('\n')),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isZh ? 'Diff 已复制' : 'Diff copied',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                    label: isZh ? '复制 Diff' : 'Copy Diff',
                  ),
                  const SizedBox(width: 10),
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(),
                    label: isZh ? '关闭' : 'Close',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _changeTypeLabel() {
    return switch (widget.file.changeType) {
      HardnessFileChangeType.added => widget.isZh ? '新增文件' : 'Added',
      HardnessFileChangeType.modified => widget.isZh ? '已修改' : 'Modified',
      HardnessFileChangeType.deleted => widget.isZh ? '已删除' : 'Deleted',
    };
  }
}

class _DiffStatChip extends StatelessWidget {
  const _DiffStatChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: _br999,
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Computes a unified diff between two lists of lines using the Myers
/// algorithm with proper backtracking and hunk generation. Context lines
/// default to 3 around each change.
List<String> _computeSimpleUnifiedDiff(
  List<String> before,
  List<String> after,
) {
  if (before.isEmpty && after.isEmpty) return const [];
  if (before.isEmpty) {
    return [
      '--- /dev/null',
      '+++ b/file',
      '@@ -0,0 +1,${after.length} @@',
      ...after.map((l) => '+$l'),
    ];
  }
  if (after.isEmpty) {
    return [
      '--- a/file',
      '+++ /dev/null',
      '@@ -1,${before.length} +0,0 @@',
      ...before.map((l) => '-$l'),
    ];
  }

  // For very large files, fall back to a simple line-by-line comparison.
  if (before.length + after.length > 10000) {
    return _fallbackDiff(before, after);
  }

  // ── Myers diff (forward pass) ──────────────────────────────────────
  final n = before.length;
  final m = after.length;
  final max = n + m;
  final size = 2 * max + 1;
  final v = List<int>.filled(size, 0);
  final traces = <List<int>>[];

  var found = false;
  for (var d = 0; d <= max && !found; d++) {
    traces.add(List<int>.from(v));
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[k - 1 + max] < v[k + 1 + max])) {
        x = v[k + 1 + max];
      } else {
        x = v[k - 1 + max] + 1;
      }
      var y = x - k;
      while (x < n && y < m && before[x] == after[y]) {
        x++;
        y++;
      }
      v[k + max] = x;
      if (x >= n && y >= m) {
        found = true;
        break;
      }
    }
  }

  // ── Backtrack to produce the edit script (in forward order) ────────
  final editScript = <({String type, String text})>[];
  var bx = n, by = m;
  for (var d = traces.length - 1; d > 0; d--) {
    final vPrev = traces[d - 1];
    final k = bx - by;
    int prevK;
    if (k == -d || (k != d && vPrev[k - 1 + max] < vPrev[k + 1 + max])) {
      prevK = k + 1;
    } else {
      prevK = k - 1;
    }
    final prevX = vPrev[prevK + max];
    final prevY = prevX - prevK;

    // Diagonal (equal) lines
    while (bx > prevX && by > prevY) {
      bx--;
      by--;
      editScript.add((type: ' ', text: before[bx]));
    }
    if (bx == prevX && by > prevY) {
      by--;
      editScript.add((type: '+', text: after[by]));
    } else if (by == prevY && bx > prevX) {
      bx--;
      editScript.add((type: '-', text: before[bx]));
    }
  }
  // Any remaining diagonal at d=0
  while (bx > 0 && by > 0) {
    bx--;
    by--;
    editScript.add((type: ' ', text: before[bx]));
  }
  while (bx > 0) {
    bx--;
    editScript.add((type: '-', text: before[bx]));
  }
  while (by > 0) {
    by--;
    editScript.add((type: '+', text: after[by]));
  }

  // Reverse because we built it backwards
  final edits = editScript.reversed.toList();

  // ── Generate unified-diff hunks with 3-line context ────────────────
  const contextSize = 3;
  final result = <String>['--- a/file', '+++ b/file'];

  // Find change regions.
  final changeIndices = <int>[];
  for (var i = 0; i < edits.length; i++) {
    if (edits[i].type != ' ') changeIndices.add(i);
  }
  if (changeIndices.isEmpty) return const []; // identical files

  // Group changes into hunks.
  final hunkRanges = <(int, int)>[];
  var hunkStart = (changeIndices.first - contextSize).clamp(0, edits.length);
  var hunkEnd = (changeIndices.first + contextSize + 1).clamp(0, edits.length);

  for (var ci = 1; ci < changeIndices.length; ci++) {
    final s = (changeIndices[ci] - contextSize).clamp(0, edits.length);
    final e = (changeIndices[ci] + contextSize + 1).clamp(0, edits.length);
    if (s <= hunkEnd) {
      // Merge with current hunk.
      hunkEnd = e;
    } else {
      hunkRanges.add((hunkStart, hunkEnd));
      hunkStart = s;
      hunkEnd = e;
    }
  }
  hunkRanges.add((hunkStart, hunkEnd));

  // Emit each hunk.
  for (final (start, end) in hunkRanges) {
    var beforeLine = 0;
    var afterLine = 0;
    // Count lines up to hunk start.
    for (var i = 0; i < start; i++) {
      if (edits[i].type != '+') beforeLine++;
      if (edits[i].type != '-') afterLine++;
    }
    final hunkBeforeStart = beforeLine + 1;
    final hunkAfterStart = afterLine + 1;
    var hunkBeforeCount = 0;
    var hunkAfterCount = 0;
    final hunkLines = <String>[];
    for (var i = start; i < end; i++) {
      final e = edits[i];
      hunkLines.add('${e.type}${e.text}');
      if (e.type != '+') hunkBeforeCount++;
      if (e.type != '-') hunkAfterCount++;
    }
    result.add(
      '@@ -$hunkBeforeStart,$hunkBeforeCount '
      '+$hunkAfterStart,$hunkAfterCount @@',
    );
    result.addAll(hunkLines);
  }

  return result;
}

List<String> _fallbackDiff(List<String> before, List<String> after) {
  final result = <String>['--- a/file', '+++ b/file'];
  final maxLen = before.length > after.length ? before.length : after.length;
  var diffStart = -1;
  final hunks = <String>[];

  for (var i = 0; i < maxLen; i++) {
    final bLine = i < before.length ? before[i] : null;
    final aLine = i < after.length ? after[i] : null;
    if (bLine == aLine) {
      if (hunks.isNotEmpty) {
        result.add('@@ -${diffStart + 1} @@');
        result.addAll(hunks);
        hunks.clear();
        diffStart = -1;
      }
      continue;
    }
    if (diffStart < 0) diffStart = i;
    if (bLine != null) hunks.add('-$bLine');
    if (aLine != null) hunks.add('+$aLine');
  }
  if (hunks.isNotEmpty) {
    result.add('@@ -${(diffStart < 0 ? 0 : diffStart) + 1} @@');
    result.addAll(hunks);
  }

  return result;
}

// =============================================================================
// _HeStreamingSmartView — StatefulWidget that caches the parsed markdown AST
// between rebuilds during streaming, only re-parsing when the content actually
// changes. Uses _SafeMarkdownBody-style manual AST parsing + MarkdownBuilder
// for reliability and performance during rapid streaming updates.
// =============================================================================

class _HeStreamingSmartView extends StatefulWidget {
  const _HeStreamingSmartView({
    required this.lines,
    required this.isZh,
    required this.theme,
    required this.colorScheme,
    required this.filePathRoots,
  });

  final List<String> lines;
  final bool isZh;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final List<String> filePathRoots;

  @override
  State<_HeStreamingSmartView> createState() => _HeStreamingSmartViewState();
}

class _HeStreamingSmartViewState extends State<_HeStreamingSmartView>
    implements MarkdownBuilderDelegate {
  static const int _tailSize = 80;

  List<Widget>? _markdownChildren;
  String? _lastSanitised;
  String? _lastCommand;
  int _lastHiddenAbove = 0;
  int? _lastThemeHash;
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];

  // Revision counter that increments whenever a new rendered block is added.
  // Used to key a TweenAnimationBuilder so only newly-appeared blocks
  // animate — existing blocks stay stable.
  int _contentRevision = 0;
  int _lastChildCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _HeStreamingSmartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildIfNeeded();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _rebuildIfNeeded() {
    final lines = widget.lines;
    final start = lines.length > _tailSize ? lines.length - _tailSize : 0;
    final display = lines.length > _tailSize ? lines.sublist(start) : lines;
    final hiddenAbove = start;
    _lastHiddenAbove = hiddenAbove;

    final parsed = _heSplitLogForMarkdown(display);
    final body = parsed.body;
    _lastCommand = parsed.command;

    final sanitised = _heSanitizeMarkdownSource(body);
    final themeHash = Object.hashAll(<Object?>[
      widget.theme.brightness,
      widget.colorScheme.surface.toARGB32(),
      widget.colorScheme.primary.toARGB32(),
    ]);

    if (sanitised == _lastSanitised && themeHash == _lastThemeHash) return;
    _lastSanitised = sanitised;
    _lastThemeHash = themeHash;

    if (sanitised.isEmpty) {
      _markdownChildren = null;
      _lastChildCount = 0;
      return;
    }

    _disposeRecognizers();
    _parseMarkdown(sanitised);

    // If a new rendered block was added, bump the revision so the last block
    // gets a fresh fade-in animation (Q弹 entrance for new content chunks).
    final newCount = _markdownChildren?.length ?? 0;
    if (newCount > _lastChildCount) {
      _contentRevision++;
    }
    _lastChildCount = newCount;
  }

  void _parseMarkdown(String source) {
    final effectiveStyleSheet = MarkdownStyleSheet.fromTheme(
      widget.theme,
    ).merge(_heBuildMarkdownStyleSheet(widget.theme, widget.colorScheme));

    final inlineSyntaxes = widget.filePathRoots.isNotEmpty
        ? <md.InlineSyntax>[
            MessagePathCodeSyntax(candidateRoots: widget.filePathRoots),
            MessageFilePathSyntax(candidateRoots: widget.filePathRoots),
          ]
        : const <md.InlineSyntax>[];

    final builders = <String, MarkdownElementBuilder>{
      'pre': _HeDiffBuilder(colorScheme: widget.colorScheme),
      if (widget.filePathRoots.isNotEmpty) ...{
        'openhand-file-resolved': _HeFilePathBuilder(
          textColor: widget.colorScheme.onSurface,
        ),
        'openhand-file-pending': _HeFilePathBuilder(
          textColor: widget.colorScheme.onSurface,
        ),
      },
    };

    try {
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        inlineSyntaxes: inlineSyntaxes,
        encodeHtml: false,
      );
      final astNodes = document.parseLines(
        const LineSplitter().convert(source),
      );
      final builder = MarkdownBuilder(
        delegate: this,
        selectable: false,
        styleSheet: effectiveStyleSheet,
        imageDirectory: null,
        imageBuilder: null,
        checkboxBuilder: null,
        bulletBuilder: null,
        builders: builders,
        paddingBuilders: const <String, MarkdownPaddingBuilder>{},
        listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
      );
      _markdownChildren = builder.build(astNodes);
    } catch (_) {
      // Fallback to plain text on parse error.
      _markdownChildren = <Widget>[
        Text(
          source,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: widget.colorScheme.onSurface,
          ),
        ),
      ];
    }
  }

  void _disposeRecognizers() {
    if (_recognizers.isEmpty) return;
    final local = List<GestureRecognizer>.from(_recognizers);
    _recognizers.clear();
    for (final r in local) {
      r.dispose();
    }
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer();
    _recognizers.add(recognizer);
    final resolvedPath = resolveMarkdownMessageLinkPath(
      href,
      widget.filePathRoots,
    );
    if (resolvedPath != null) {
      recognizer.onTap = () {
        Clipboard.setData(ClipboardData(text: resolvedPath.resolvedPath));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Path copied: ${resolvedPath.resolvedPath}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      };
    }
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    final normalizedCode = code.replaceAll(RegExp(r'\n$'), '');
    final resolvedPath = resolveExistingMessagePath(
      normalizedCode,
      widget.filePathRoots,
    );
    if (resolvedPath == null) {
      return TextSpan(text: normalizedCode, style: styleSheet.code);
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        Clipboard.setData(ClipboardData(text: resolvedPath.resolvedPath));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Path copied: ${resolvedPath.resolvedPath}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      };
    _recognizers.add(recognizer);
    final linkColor = widget.colorScheme.primary;
    return TextSpan(
      text: normalizedCode,
      recognizer: recognizer,
      style: styleSheet.code?.copyWith(
        color: linkColor,
        decoration: TextDecoration.underline,
        decorationColor: linkColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final isZh = widget.isZh;
    final children = _markdownChildren;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_lastHiddenAbove > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '… $_lastHiddenAbove ${_lastHiddenAbove == 1 ? 'line' : 'lines'} above',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (_lastCommand != null) ...[
          _HeCommandStrip(command: _lastCommand!),
          const SizedBox(height: 8),
        ],
        if (children != null && children.isNotEmpty)
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.white],
              stops: [0.0, 0.08],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: () {
              // Wrap the last rendered block in a Q弹 entrance animation:
              // whenever a new markdown block appears (_contentRevision ticks),
              // it fades in and slides up slightly. Existing blocks stay on
              // screen without flickering.
              Widget animatedLast(Widget w) => TweenAnimationBuilder<double>(
                key: ValueKey<int>(_contentRevision),
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                builder: (_, v, child) => Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0.0, 6.0 * (1.0 - v)),
                    child: child,
                  ),
                ),
                child: w,
              );
              if (children.length == 1) {
                return animatedLast(children.single);
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...children.take(children.length - 1),
                  animatedLast(children.last),
                ],
              );
            }(),
          ),
        // Streaming indicator
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isZh ? '正在输出…' : 'Streaming…',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.60),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// _HeFilePathBuilder — renders file path elements detected in markdown content.
// Supports both resolved (cached) and pending (async-resolved) paths following
// the same _AsyncFilePathChip pattern from the main chat.
// =============================================================================

class _HeFilePathBuilder extends MarkdownElementBuilder {
  _HeFilePathBuilder({required this.textColor});

  final Color textColor;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.tag == 'openhand-file-resolved') {
      final resolvedPath = (element.attributes['resolved_path'] ?? '').trim();
      final displayPath = element.textContent.trim();
      final isDirectory =
          (element.attributes['entity_type'] ?? '').trim() == 'directory';
      return Text.rich(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _HeFilePathChipInline(
              displayPath: displayPath,
              resolvedPath: resolvedPath,
              isDirectory: isDirectory,
              textColor: textColor,
            ),
          ),
        ),
      );
    }

    // Pending path — async resolve, then show chip or fallback.
    final normalizedPath = element.attributes['normalized_path'] ?? '';
    final candidateRoots = (element.attributes['candidate_roots'] ?? '').split(
      '\r',
    );
    final fullMatch = element.textContent;
    final trailing = element.attributes['trailing'] ?? '';
    final isCodeSpan = element.attributes['is_code_span'] == 'true';

    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _HeAsyncFilePathChip(
          normalizedPath: normalizedPath,
          candidateRoots: candidateRoots,
          fullMatch: fullMatch,
          trailing: trailing,
          isCodeSpan: isCodeSpan,
          parentStyle: parentStyle,
          textColor: textColor,
        ),
      ),
    );
  }
}

/// Async file-path chip that resolves paths in the background, matching
/// the _AsyncFilePathChip pattern from the main thread chat.
class _HeAsyncFilePathChip extends StatefulWidget {
  const _HeAsyncFilePathChip({
    required this.normalizedPath,
    required this.candidateRoots,
    required this.fullMatch,
    required this.trailing,
    required this.isCodeSpan,
    required this.parentStyle,
    required this.textColor,
  });

  final String normalizedPath;
  final List<String> candidateRoots;
  final String fullMatch;
  final String trailing;
  final bool isCodeSpan;
  final TextStyle? parentStyle;
  final Color textColor;

  @override
  State<_HeAsyncFilePathChip> createState() => _HeAsyncFilePathChipState();
}

class _HeAsyncFilePathChipState extends State<_HeAsyncFilePathChip> {
  Future<MessageResolvedPath?>? _future;

  @override
  void initState() {
    super.initState();
    _future = resolveExistingMessagePathAsync(
      widget.normalizedPath,
      widget.candidateRoots,
    );
  }

  @override
  void didUpdateWidget(_HeAsyncFilePathChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.normalizedPath != widget.normalizedPath ||
        oldWidget.candidateRoots.join('|') != widget.candidateRoots.join('|')) {
      _future = resolveExistingMessagePathAsync(
        widget.normalizedPath,
        widget.candidateRoots,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MessageResolvedPath?>(
      future: _future,
      builder: (context, snapshot) {
        final resolvedPath = snapshot.data;
        if (resolvedPath == null) {
          // Not resolved — show as code span or plain text.
          if (widget.isCodeSpan) {
            return _buildCodeSpan(context, widget.fullMatch);
          }
          final isExplicit =
              widget.normalizedPath.startsWith('~/') ||
              widget.normalizedPath.startsWith('./') ||
              widget.normalizedPath.startsWith('../') ||
              looksLikeAbsoluteMessagePath(widget.normalizedPath);
          if (isExplicit) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _HeFilePathChipInline(
                      displayPath: widget.normalizedPath,
                      resolvedPath: widget.normalizedPath,
                      isDirectory: widget.trailing.contains('/'),
                      isUnresolved: true,
                      textColor: widget.textColor,
                    ),
                  ),
                ),
                if (widget.trailing.isNotEmpty)
                  Text(widget.trailing, style: widget.parentStyle),
              ],
            );
          }
          return Text(widget.fullMatch, style: widget.parentStyle);
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _HeFilePathChipInline(
                  displayPath: resolvedPath.displayPath,
                  resolvedPath: resolvedPath.resolvedPath,
                  isDirectory: resolvedPath.isDirectory,
                  textColor: widget.textColor,
                ),
              ),
            ),
            if (widget.trailing.isNotEmpty)
              Text(widget.trailing, style: widget.parentStyle),
          ],
        );
      },
    );
  }

  Widget _buildCodeSpan(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: widget.textColor.withValues(alpha: 0.80),
        ),
      ),
    );
  }
}

class _HeFilePathChipInline extends StatelessWidget {
  const _HeFilePathChipInline({
    required this.displayPath,
    required this.resolvedPath,
    required this.isDirectory,
    this.isUnresolved = false,
    required this.textColor,
  });

  final String displayPath;
  final String resolvedPath;
  final bool isDirectory;
  final bool isUnresolved;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Match _FilePathChip reference: surface-based background + textColor.
    final chipColor = theme.colorScheme.surface.withValues(alpha: 0.68);
    final borderColor = textColor.withValues(alpha: 0.24);
    final labelStyle =
        theme.textTheme.labelMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ) ??
        TextStyle(color: textColor, fontWeight: FontWeight.w700);

    return _HeFileHoverPopup(
      resolvedPath: resolvedPath,
      isUnresolved: isUnresolved,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: _br999,
          onTap: isUnresolved ? null : () => _openPath(context),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isUnresolved
                  ? chipColor.withValues(alpha: 0.3)
                  : chipColor,
              borderRadius: _br999,
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUnresolved
                      ? Icons.help_outline
                      : isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 14,
                  color: isUnresolved
                      ? textColor.withValues(alpha: 0.5)
                      : textColor.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Text(
                      displayPath,
                      overflow: TextOverflow.ellipsis,
                      style: isUnresolved
                          ? labelStyle.copyWith(
                              color: textColor.withValues(alpha: 0.5),
                            )
                          : labelStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPath(BuildContext context) {
    _heOpenPathInFileBrowser(context, resolvedPath, isDirectory: isDirectory);
  }
}

// =============================================================================
// _HeFileHoverPopup — Ctrl/Cmd+hover overlay showing file/directory metadata.
// Mirrors the _FileHoverPopup pattern from openhand_home_page.dart.
// =============================================================================

class _HeFileHoverPopup extends StatefulWidget {
  const _HeFileHoverPopup({
    required this.resolvedPath,
    required this.child,
    this.isUnresolved = false,
  });

  final String resolvedPath;
  final Widget child;
  final bool isUnresolved;

  @override
  State<_HeFileHoverPopup> createState() => _HeFileHoverPopupState();
}

class _HeFileHoverPopupState extends State<_HeFileHoverPopup> {
  OverlayEntry? _overlayEntry;
  bool _isHovered = false;
  bool _showScheduled = false;
  bool _hideScheduled = false;

  bool get _isModifierPressed {
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;
    return pressed.contains(PhysicalKeyboardKey.controlLeft) ||
        pressed.contains(PhysicalKeyboardKey.controlRight) ||
        pressed.contains(PhysicalKeyboardKey.metaLeft) ||
        pressed.contains(PhysicalKeyboardKey.metaRight);
  }

  void _showOverlay() {
    if (widget.isUnresolved || _overlayEntry != null || _showScheduled) return;
    // Defer overlay insertion to avoid mutating the widget tree during
    // MouseTracker._deviceUpdatePhase, which triggers the
    // !_debugDuringDeviceUpdate re-entrancy assertion.
    _showScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showScheduled = false;
      if (!mounted || !_isHovered || _overlayEntry != null) return;
      _showOverlayNow();
    });
  }

  void _showOverlayNow() {
    if (widget.isUnresolved || _overlayEntry != null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.sizeOf(context);

    var targetLeft = offset.dx;
    if (targetLeft + 320 > screenSize.width - 16) {
      targetLeft = screenSize.width - 320 - 16;
      if (targetLeft < 8) targetLeft = 8;
    }

    var targetTop = offset.dy + size.height + 6;
    const estimatedHeight = 140.0;
    if (targetTop + estimatedHeight > screenSize.height - 16) {
      targetTop = offset.dy - estimatedHeight - 6;
    }

    final resolvedPath = widget.resolvedPath;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: targetLeft,
        top: targetTop,
        child: IgnorePointer(
          child: FadeInOverlayContent(
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    overlayContext,
                  ).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(overlayContext).dividerColor,
                  ),
                ),
                width: 320,
                child: FutureBuilder<FileStat>(
                  future: FileStat.stat(resolvedPath),
                  builder: (ctx, snapshot) {
                    final theme = Theme.of(ctx);
                    final colorScheme = theme.colorScheme;
                    final isZhLocale =
                        Localizations.localeOf(ctx).languageCode == 'zh';

                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 40,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    final stat = snapshot.data!;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          resolvedPath,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _HeStatRow(
                          isZhLocale ? '类型' : 'Type',
                          stat.type.toString(),
                        ),
                        _HeStatRow(
                          isZhLocale ? '大小' : 'Size',
                          '${stat.size} bytes',
                        ),
                        _HeStatRow(
                          isZhLocale ? '修改于' : 'Modified',
                          '${stat.modified}',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    try {
      Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
    } catch (_) {
      _overlayEntry = null;
    }
  }

  void _hideOverlay() {
    if (_overlayEntry == null && !_showScheduled) return;
    _showScheduled = false;
    final entry = _overlayEntry;
    _overlayEntry = null;
    if (entry == null) return;
    // Defer overlay removal to avoid mutating the widget tree during
    // MouseTracker._deviceUpdatePhase.
    if (_hideScheduled) return;
    _hideScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hideScheduled = false;
      entry.remove();
    });
  }

  @override
  void didUpdateWidget(_HeFileHoverPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resolvedPath != widget.resolvedPath ||
        oldWidget.isUnresolved != widget.isUnresolved) {
      _hideOverlay();
    }
  }

  @override
  void deactivate() {
    // Synchronous removal since the widget is leaving the tree.
    _showScheduled = false;
    _hideScheduled = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isHovered = false;
    super.deactivate();
  }

  bool _handleKey(KeyEvent event) {
    if (!mounted || !_isHovered || widget.isUnresolved) return false;
    if (_isModifierPressed) {
      _showOverlay();
    } else {
      _hideOverlay();
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    _hideOverlay();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _isHovered = true;
        if (!widget.isUnresolved && _isModifierPressed) _showOverlay();
      },
      onHover: (_) {
        if (!widget.isUnresolved) {
          if (_isModifierPressed) {
            _showOverlay();
          } else {
            _hideOverlay();
          }
        }
      },
      onExit: (_) {
        _isHovered = false;
        _hideOverlay();
      },
      child: widget.child,
    );
  }
}

class _HeStatRow extends StatelessWidget {
  const _HeStatRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Top-level helper — opens a path in the system file browser (Finder / Explorer
// / Nautilus), mirroring _openResolvedMessagePath from openhand_home_page.dart.
// =============================================================================

Future<void> _heOpenPathInFileBrowser(
  BuildContext context,
  String path, {
  required bool isDirectory,
}) async {
  try {
    late final ProcessResult result;
    if (Platform.isMacOS) {
      // `-R` reveals the file in its parent Finder window; for directories
      // just open the directory itself.
      result = await Process.run(
        'open',
        isDirectory ? <String>[path] : <String>['-R', path],
      );
    } else if (Platform.isWindows) {
      result = await Process.run(
        'explorer',
        isDirectory ? <String>[path] : <String>['/select,$path'],
      );
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', <String>[
        isDirectory ? path : File(path).parent.path,
      ]);
    } else {
      throw const FileSystemException('Unsupported platform.');
    }
    if (result.exitCode == 0) return;
    final msg = '${result.stderr}'.trim();
    throw FileSystemException(
      msg.isEmpty ? 'Unable to open file location.' : msg,
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localizations.localeOf(context).languageCode.startsWith('zh')
              ? '打开文件位置失败：$error'
              : 'Failed to open file location: $error',
        ),
      ),
    );
  }
}

// =============================================================================
// _HeSteeringAssetsDialog — breadcrumb directory browser for steering files
// =============================================================================

class _HeSteeringAssetsDialog extends StatefulWidget {
  const _HeSteeringAssetsDialog({
    required this.steeringRoot,
    required this.isZh,
  });

  final String steeringRoot;
  final bool isZh;

  @override
  State<_HeSteeringAssetsDialog> createState() =>
      _HeSteeringAssetsDialogState();
}

class _HeSteeringAssetsDialogState extends State<_HeSteeringAssetsDialog> {
  /// The path segments relative to steeringRoot. Empty = root.
  late List<String> _pathSegments;

  /// Cached entries for the current directory.
  List<_HeSteeringEntry> _entries = const [];

  /// Whether we're still scanning.
  bool _loading = true;

  static const _directoryDescriptions = <String, (String, String)>{
    'meta': ('元信息 — 架构、约定、配置', 'Meta — architecture, conventions, config'),
    'plan': ('规划 — 阶段计划文件', 'Plans — phase planning files'),
    'feedback': ('反馈 — 验收与审查反馈', 'Feedback — review & acceptance feedback'),
    'handoff': ('交接 — 阶段间交接文件', 'Handoff — inter-phase handoff files'),
    'lesson': ('记忆 — 经验教训文件', 'Lessons — lessons learned files'),
    'log': ('日志 — 运行日志', 'Logs — runtime log files'),
  };

  @override
  void initState() {
    super.initState();
    _pathSegments = [];
    _scanDirectory();
  }

  String get _currentAbsolutePath => _pathSegments.isEmpty
      ? widget.steeringRoot
      : p.joinAll([widget.steeringRoot, ..._pathSegments]);

  void _navigateTo(List<String> segments) {
    setState(() {
      _pathSegments = List.of(segments);
      _loading = true;
    });
    _scanDirectory();
  }

  Future<void> _scanDirectory() async {
    final dir = Directory(_currentAbsolutePath);
    final entries = <_HeSteeringEntry>[];
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;
          final isDir = entity is Directory;
          FileStat? stat;
          try {
            stat = await entity.stat();
          } catch (_) {}
          entries.add(
            _HeSteeringEntry(
              name: name,
              isDirectory: isDir,
              absolutePath: entity.path,
              size: stat?.size,
              modified: stat?.modified,
            ),
          );
        }
      }
    } catch (_) {
      // Permission denied or directory does not exist — show empty.
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _onEntryTap(_HeSteeringEntry entry) {
    if (entry.isDirectory) {
      _navigateTo([..._pathSegments, entry.name]);
    } else {
      _openFileEditor(entry);
    }
  }

  void _openFileEditor(_HeSteeringEntry entry) {
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => _HeSteeringFileEditorDialog(
        filePath: entry.absolutePath,
        isZh: widget.isZh,
      ),
    ).then((_) {
      // Refresh in case file was modified.
      _scanDirectory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 780,
          maxHeight: MediaQuery.of(context).size.height * 0.80,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title row ──
              Row(
                children: [
                  Icon(
                    Icons.folder_special_rounded,
                    color: colorScheme.primary,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.isZh ? '资产文件浏览器' : 'Steering Assets Browser',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Breadcrumb ──
              _HeBreadcrumb(
                segments: _pathSegments,
                isZh: widget.isZh,
                onNavigate: _navigateTo,
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),

              // ── File list ──
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _entries.isEmpty
                    ? Center(
                        child: Text(
                          widget.isZh ? '此目录为空' : 'This directory is empty',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 2),
                        itemBuilder: (ctx, i) {
                          final entry = _entries[i];
                          return _HeSteeringEntryTile(
                            entry: entry,
                            isZh: widget.isZh,
                            description:
                                entry.isDirectory && _pathSegments.isEmpty
                                ? _directoryDescriptions[entry.name]
                                : null,
                            onTap: () => _onEntryTap(entry),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Entry model ──

class _HeSteeringEntry {
  const _HeSteeringEntry({
    required this.name,
    required this.isDirectory,
    required this.absolutePath,
    this.size,
    this.modified,
  });

  final String name;
  final bool isDirectory;
  final String absolutePath;
  final int? size;
  final DateTime? modified;
}

// ── Breadcrumb ──

class _HeBreadcrumb extends StatelessWidget {
  const _HeBreadcrumb({
    required this.segments,
    required this.isZh,
    required this.onNavigate,
  });

  final List<String> segments;
  final bool isZh;
  final void Function(List<String>) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final items = <Widget>[
      _breadcrumbChip(
        context,
        label: isZh ? 'steering' : 'steering',
        icon: Icons.home_rounded,
        onTap: () => onNavigate([]),
        isLast: segments.isEmpty,
      ),
    ];
    for (var i = 0; i < segments.length; i++) {
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      );
      final isLast = i == segments.length - 1;
      items.add(
        _breadcrumbChip(
          context,
          label: segments[i],
          icon: isLast ? Icons.folder_open_rounded : Icons.folder_rounded,
          onTap: isLast ? null : () => onNavigate(segments.sublist(0, i + 1)),
          isLast: isLast,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items),
    );
  }

  Widget _breadcrumbChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    VoidCallback? onTap,
    bool isLast = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: isLast
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isLast
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                  color: isLast
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Entry tile ──

class _HeSteeringEntryTile extends StatelessWidget {
  const _HeSteeringEntryTile({
    required this.entry,
    required this.isZh,
    this.description,
    required this.onTap,
  });

  final _HeSteeringEntry entry;
  final bool isZh;
  final (String, String)? description;
  final VoidCallback onTap;

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  IconData get _icon {
    if (entry.isDirectory) return Icons.folder_rounded;
    final ext = p.extension(entry.name).toLowerCase();
    return switch (ext) {
      '.md' => Icons.description_rounded,
      '.json' => Icons.data_object_rounded,
      '.log' => Icons.receipt_long_rounded,
      '.yaml' || '.yml' => Icons.settings_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  Color _iconColor(ColorScheme cs) {
    if (entry.isDirectory) return cs.primary;
    final ext = p.extension(entry.name).toLowerCase();
    return switch (ext) {
      '.md' => cs.tertiary,
      '.json' => cs.secondary,
      '.log' => cs.onSurfaceVariant,
      _ => cs.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final desc = description;
    final descText = desc != null ? (isZh ? desc.$1 : desc.$2) : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(_icon, size: 24, color: _iconColor(colorScheme)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (descText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          descText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!entry.isDirectory && entry.size != null) ...[
                const SizedBox(width: 8),
                Text(
                  _formatSize(entry.size!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (entry.modified != null) ...[
                const SizedBox(width: 12),
                Text(
                  _formatDate(entry.modified!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                entry.isDirectory
                    ? Icons.chevron_right_rounded
                    : Icons.open_in_new_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// _HeSteeringFileEditorDialog — Markdown editor with live preview
// =============================================================================

class _HeSteeringFileEditorDialog extends StatefulWidget {
  const _HeSteeringFileEditorDialog({
    required this.filePath,
    required this.isZh,
  });

  final String filePath;
  final bool isZh;

  @override
  State<_HeSteeringFileEditorDialog> createState() =>
      _HeSteeringFileEditorDialogState();
}

class _HeSteeringFileEditorDialogState
    extends State<_HeSteeringFileEditorDialog> {
  late final TextEditingController _controller;
  late final FocusNode _editorFocusNode;
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  String? _error;
  bool _showPreview = true;

  /// The text as last saved (or as loaded). Used to detect real changes
  /// vs cursor-only movements (which also fire the controller listener).
  String _savedText = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _editorFocusNode = FocusNode();
    _loadFile();
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final content = await File(widget.filePath).readAsString();
      if (!mounted) return;
      setState(() {
        _controller.text = content;
        _savedText = content;
        _loading = false;
      });
      _controller.addListener(_onEdit);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onEdit() {
    // Fire only when the text itself has changed, not on mere cursor movement.
    final nowDirty = _controller.text != _savedText;
    if (nowDirty != _dirty) setState(() => _dirty = nowDirty);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await File(widget.filePath).writeAsString(_controller.text);
      if (!mounted) return;
      setState(() {
        _savedText = _controller.text;
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isZh ? '文件已保存' : 'File saved'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isZh ? '保存失败：$e' : 'Save failed: $e')),
      );
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final result = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.isZh ? '放弃更改？' : 'Discard changes?'),
        content: Text(
          widget.isZh
              ? '你有未保存的更改，确定要放弃吗？'
              : 'You have unsaved changes. Discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(widget.isZh ? '取消' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(widget.isZh ? '放弃' : 'Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Format helpers ─────────────────────────────────────────────────────────

  void _refocus() => _editorFocusNode.requestFocus();

  /// Wraps current selection (or cursor position) with [prefix]/[suffix].
  void _wrapInline(String prefix, [String? suffix]) {
    suffix ??= prefix;
    final v = _controller.value;
    final text = v.text;
    final sel = v.selection;
    if (!sel.isValid) return;

    final String newText;
    final TextSelection newSel;
    if (sel.isCollapsed) {
      final before = text.substring(0, sel.start);
      final after = text.substring(sel.start);
      newText = '$before$prefix$suffix$after';
      newSel = TextSelection.collapsed(offset: sel.start + prefix.length);
    } else {
      final before = text.substring(0, sel.start);
      final selected = text.substring(sel.start, sel.end);
      final after = text.substring(sel.end);
      newText = '$before$prefix$selected$suffix$after';
      newSel = TextSelection(
        baseOffset: sel.start,
        extentOffset:
            sel.start + prefix.length + selected.length + suffix.length,
      );
    }
    _controller.value = v.copyWith(text: newText, selection: newSel);
    _refocus();
  }

  /// Prefixes every line covered by the selection with [prefix].
  void _prefixLines(String prefix) {
    final v = _controller.value;
    final text = v.text;
    final sel = v.selection;
    if (!sel.isValid) return;

    final lineStart =
        text.lastIndexOf('\n', sel.start > 0 ? sel.start - 1 : 0) + 1;
    var lineEnd = text.indexOf('\n', sel.end);
    if (lineEnd == -1) lineEnd = text.length;

    final block = text.substring(lineStart, lineEnd);
    final prefixed = block.split('\n').map((l) => '$prefix$l').join('\n');

    _controller.value = v.copyWith(
      text:
          '${text.substring(0, lineStart)}$prefixed${text.substring(lineEnd)}',
      selection: TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + prefixed.length,
      ),
    );
    _refocus();
  }

  /// Inserts [snippet] at cursor, optionally placing cursor at [cursorOffset].
  void _insertSnippet(String snippet, {int? cursorOffset}) {
    final v = _controller.value;
    final text = v.text;
    final sel = v.selection;
    final offset = sel.isValid ? sel.start : text.length;
    final end = sel.isValid && !sel.isCollapsed ? sel.end : offset;
    final newText =
        '${text.substring(0, offset)}$snippet${text.substring(end)}';
    _controller.value = v.copyWith(
      text: newText,
      selection: TextSelection.collapsed(
        offset: offset + (cursorOffset ?? snippet.length),
      ),
    );
    _refocus();
  }

  // ── Format actions ─────────────────────────────────────────────────────────

  void _applyHeading(int level) => _prefixLines('${'#' * level} ');
  void _applyBold() => _wrapInline('**');
  void _applyItalic() => _wrapInline('*');
  void _applyStrikethrough() => _wrapInline('~~');
  void _applyInlineCode() => _wrapInline('`');
  void _applyBlockquote() => _prefixLines('> ');
  void _applyBulletList() => _prefixLines('- ');

  void _applyCodeBlock() => _insertSnippet('```\n\n```\n', cursorOffset: 4);

  void _applyOrderedList() {
    final v = _controller.value;
    final text = v.text;
    final sel = v.selection;
    if (!sel.isValid) return;
    final lineStart =
        text.lastIndexOf('\n', sel.start > 0 ? sel.start - 1 : 0) + 1;
    var lineEnd = text.indexOf('\n', sel.end);
    if (lineEnd == -1) lineEnd = text.length;
    final block = text.substring(lineStart, lineEnd);
    var i = 1;
    final prefixed = block.split('\n').map((l) => '${i++}. $l').join('\n');
    _controller.value = v.copyWith(
      text:
          '${text.substring(0, lineStart)}$prefixed${text.substring(lineEnd)}',
      selection: TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + prefixed.length,
      ),
    );
    _refocus();
  }

  void _insertLink() {
    final v = _controller.value;
    final text = v.text;
    final sel = v.selection;
    if (sel.isValid && !sel.isCollapsed) {
      // Wrap selection as link text; select "url" placeholder for easy editing.
      final selected = text.substring(sel.start, sel.end);
      final snippet = '[$selected](url)';
      final newText =
          '${text.substring(0, sel.start)}$snippet${text.substring(sel.end)}';
      // "url" is at sel.start + 1 + selected.length + 2 = sel.start + selected.length + 3
      final urlStart = sel.start + selected.length + 3;
      _controller.value = v.copyWith(
        text: newText,
        selection: TextSelection(
          baseOffset: urlStart,
          extentOffset: urlStart + 3,
        ),
      );
    } else {
      // No selection: insert [](url) with cursor between brackets.
      final offset = sel.isValid ? sel.start : text.length;
      _controller.value = v.copyWith(
        text: '${text.substring(0, offset)}[](url)${text.substring(offset)}',
        selection: TextSelection.collapsed(offset: offset + 1),
      );
    }
    _refocus();
  }

  void _insertHR() => _insertSnippet('\n\n---\n\n');

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fileName = p.basename(widget.filePath);
    final isMarkdown = fileName.endsWith('.md');

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1060,
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title row ──
                Row(
                  children: [
                    Icon(
                      Icons.edit_document,
                      size: 22,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            p.dirname(widget.filePath),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (isMarkdown)
                      IconButton(
                        tooltip: _showPreview
                            ? (widget.isZh ? '隐藏预览' : 'Hide preview')
                            : (widget.isZh ? '显示预览' : 'Show preview'),
                        onPressed: () =>
                            setState(() => _showPreview = !_showPreview),
                        icon: Icon(
                          _showPreview
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 20,
                        ),
                      ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () async {
                        if (await _confirmDiscard()) {
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 6),

                // ── Markdown toolbar ──
                if (isMarkdown && !_loading && _error == null) ...[
                  _buildToolbar(theme, colorScheme),
                  const SizedBox(height: 6),
                ],

                // ── Body ──
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                          child: SelectableText(
                            _error!,
                            style: TextStyle(color: colorScheme.error),
                          ),
                        )
                      : isMarkdown && _showPreview
                      ? Row(
                          children: [
                            Expanded(
                              child: _buildEditorPane(theme, colorScheme),
                            ),
                            const SizedBox(width: 10),
                            VerticalDivider(
                              width: 1,
                              color: colorScheme.outlineVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildPreviewPane(theme, colorScheme),
                            ),
                          ],
                        )
                      : _buildEditorPane(theme, colorScheme),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 10),

                // ── Action row ──
                Row(
                  children: [
                    if (!_loading && _error == null)
                      ListenableBuilder(
                        listenable: _controller,
                        builder: (_, _) {
                          final t = _controller.text;
                          final words = t.trim().isEmpty
                              ? 0
                              : t
                                    .trim()
                                    .split(RegExp(r'\s+'))
                                    .where((w) => w.isNotEmpty)
                                    .length;
                          return Text(
                            widget.isZh
                                ? '${t.length} 字符  $words 词'
                                : '${t.length} chars  $words words',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    const Spacer(),
                    if (_dirty)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          widget.isZh ? '有未保存的更改' : 'Unsaved changes',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    // Both buttons use the same style/size so they are
                    // visually consistent.
                    OutlinedButton(
                      onPressed: () async {
                        if (await _confirmDiscard()) {
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(88, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      child: Text(widget.isZh ? '关闭' : 'Close'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _dirty && !_saving ? _save : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(88, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      child: _saving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.save_rounded, size: 17),
                                const SizedBox(width: 6),
                                Text(widget.isZh ? '保存' : 'Save'),
                              ],
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme, ColorScheme colorScheme) {
    final sep = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 18,
        child: VerticalDivider(width: 1, color: colorScheme.outlineVariant),
      ),
    );
    final zh = widget.isZh;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Headings
            _MdToolbarBtn(
              label: 'H₁',
              tooltip: zh ? '一级标题' : 'Heading 1',
              onTap: () => _applyHeading(1),
            ),
            _MdToolbarBtn(
              label: 'H₂',
              tooltip: zh ? '二级标题' : 'Heading 2',
              onTap: () => _applyHeading(2),
            ),
            _MdToolbarBtn(
              label: 'H₃',
              tooltip: zh ? '三级标题' : 'Heading 3',
              onTap: () => _applyHeading(3),
            ),
            sep,
            // Inline styles
            _MdToolbarBtn(
              icon: Icons.format_bold,
              tooltip: zh ? '粗体 **text**' : 'Bold **text**',
              onTap: _applyBold,
            ),
            _MdToolbarBtn(
              icon: Icons.format_italic,
              tooltip: zh ? '斜体 *text*' : 'Italic *text*',
              onTap: _applyItalic,
            ),
            _MdToolbarBtn(
              icon: Icons.format_strikethrough,
              tooltip: zh ? '删除线 ~~text~~' : 'Strikethrough ~~text~~',
              onTap: _applyStrikethrough,
            ),
            _MdToolbarBtn(
              icon: Icons.code,
              tooltip: zh ? '内联代码 `code`' : 'Inline code `code`',
              onTap: _applyInlineCode,
            ),
            sep,
            // Block
            _MdToolbarBtn(
              icon: Icons.data_object_rounded,
              tooltip: zh ? '代码块' : 'Code block',
              onTap: _applyCodeBlock,
            ),
            _MdToolbarBtn(
              icon: Icons.format_quote_rounded,
              tooltip: zh ? '引用块 > text' : 'Blockquote > text',
              onTap: _applyBlockquote,
            ),
            sep,
            // Lists
            _MdToolbarBtn(
              icon: Icons.format_list_bulleted,
              tooltip: zh ? '无序列表 - item' : 'Bullet list - item',
              onTap: _applyBulletList,
            ),
            _MdToolbarBtn(
              icon: Icons.format_list_numbered,
              tooltip: zh ? '有序列表 1. item' : 'Ordered list 1. item',
              onTap: _applyOrderedList,
            ),
            sep,
            // Misc
            _MdToolbarBtn(
              icon: Icons.link_rounded,
              tooltip: zh ? '插入链接 [text](url)' : 'Insert link [text](url)',
              onTap: _insertLink,
            ),
            _MdToolbarBtn(
              icon: Icons.horizontal_rule_rounded,
              tooltip: zh ? '分隔线 ---' : 'Horizontal rule ---',
              onTap: _insertHR,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorPane(ThemeData theme, ColorScheme colorScheme) {
    // Clip.antiAliasWithSaveLayer composites to a separate layer before
    // blending, fully eliminating the white-corner bleed that Clip.antiAlias
    // produces when a Dialog's white background shows through the rounded
    // edges during anti-aliasing.
    return Container(
      clipBehavior: Clip.antiAliasWithSaveLayer,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _editorFocusNode,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          height: 1.55,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          // Transparent fill prevents InputDecorator from painting its own
          // opaque background on top of the Container's background colour.
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.all(14),
          hintText: widget.isZh ? '在此编辑文件内容…' : 'Edit file content here…',
        ),
      ),
    );
  }

  Widget _buildPreviewPane(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      clipBehavior: Clip.antiAliasWithSaveLayer,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: colorScheme.surfaceContainerHigh,
            child: Text(
              widget.isZh ? '预览' : 'Preview',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (_, _) => _HeSafeMarkdownBody(
                  content: _controller.text,
                  theme: theme,
                  colorScheme: colorScheme,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// _MdToolbarBtn — compact toolbar button (icon or text label)
// =============================================================================

class _MdToolbarBtn extends StatelessWidget {
  const _MdToolbarBtn({
    this.icon,
    this.label,
    required this.tooltip,
    required this.onTap,
  }) : assert(icon != null || label != null);

  final IconData? icon;
  final String? label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 17, color: colorScheme.onSurfaceVariant)
                  : Text(
                      label!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
