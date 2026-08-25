import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../../l10n/app_localizations.dart';
import 'animated_dialog.dart';
import 'error_source.dart';
import 'openhand_clipboard.dart';
import 'openhand_dialog_action_button.dart';
import 'openhand_safe_scrollbar.dart';
import 'openhand_snack_bar.dart';
import 'openhand_typography.dart';

export 'error_source.dart' show AiErrorSource;

const Duration _kFriendlyErrorDetailsSnackDuration = Duration(seconds: 6);

/// 把可能很长的「现象 / 原因 / 建议」三段式错误文案以**对用户友好**的方式
/// 展示在 SnackBar 上：
///   · SnackBar 主文本只截取第一非空行（作者设计为简短中英标题）
///   · 当原始文本含有多行时，附带「详情」动作按钮，点击后
///     弹出 AlertDialog 用 SelectableText 完整展示，便于复制与排查
///
/// 这样用户既不会被 SnackBar 截断的长报错气死，也能在需要时拿到完整
/// 排错信息。同时也避免到处堆砌 dialog 重复样板。
void showFriendlyErrorSnackBar(
  BuildContext context, {
  required String? message,
  required String fallback,
  List<AiErrorSource>? sources,
}) {
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  final raw = (message ?? '').trim();
  final effective = raw.isEmpty ? fallback : raw;
  // 拆出第一非空行作为 SnackBar 主标题。
  final lines = effective
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  final headline = lines.isEmpty ? fallback : lines.first;
  final hasDetails =
      lines.length > 1 || (sources != null && sources.isNotEmpty);
  // SnackBarAction 的 onPressed 触发时，调用方 context 往往已离开树
  // （例如发出 SnackBar 的临时 widget 已 dispose），此时再用它去
  // showAnimatedDialog 会触发「Looking up a deactivated widget's
  // ancestor is unsafe」断言。这里提前抓住根 Navigator 的 context，
  // 它由 MaterialApp 持有，生命周期与 App 一致，可在异步回调里安全使用。
  final rootNavigator = Navigator.maybeOf(context, rootNavigator: true);
  if (rootNavigator == null || !rootNavigator.mounted) return;
  final rootContext = rootNavigator.context;
  replaceOpenHandSnack(
    context,
    headline,
    kind: OpenHandSnackKind.error,
    maxLines: 2,
    duration: hasDetails
        ? _kFriendlyErrorDetailsSnackDuration
        : kOpenHandSnackBarDetailedDuration,
    action: hasDetails
        ? SnackBarAction(
            label: l10n.commonDetails,
            onPressed: () {
              if (!rootContext.mounted) return;
              showFriendlyErrorDetailsDialog(
                rootContext,
                fullText: effective,
                sources: sources,
              );
            },
          )
        : null,
  );
}

/// 弹出可滚动 / 可选中 / 可一键复制的错误详情对话框。
///
/// 任何带有「现象 / 原因 / 建议」三段式诊断文案的 UI（SnackBar、会话气泡
/// banner、设置页测试结果等）都可以共用同一个查看体验。
void showFriendlyErrorDetailsDialog(
  BuildContext context, {
  required String fullText,
  String? title,
  List<AiErrorSource>? sources,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      final theme = Theme.of(dialogContext);
      final effectiveSources = sources;
      final hasSources =
          effectiveSources != null && effectiveSources.isNotEmpty;
      return buildOpenHandAlertDialog(
        icon: Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
        title: Text(title ?? l10n.sessMetaErrorDetail),
        content: buildOpenHandDialogConstrainedContent(
          maxWidth: 680,
          maxHeight: 560,
          child: hasSources
              ? _MultiSourceErrorBody(
                  fullText: fullText,
                  sources: effectiveSources,
                  theme: theme,
                )
              : _ErrorDetailsScrollBody(fullText: fullText, theme: theme),
        ),
        actions: <Widget>[
          OpenHandDialogActionButton.secondary(
            onPressed: () async {
              await copyOpenHandTextToClipboard(
                context: dialogContext,
                text: fullText,
                logTag: 'error_snackbar',
                successMessage: l10n.commonCopiedToClipboard,
                // 触发复制时，唤出本弹窗的错误提示条通常仍在展示，
                // 需顶替掉它，否则「已复制」要排队等它自然消失。
                replaceCurrentSnack: true,
              );
            },
            icon: Icons.copy_all_outlined,
            label: l10n.commonCopy,
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: l10n.commonClose,
          ),
        ],
      );
    },
  );
}

class _ErrorDetailsScrollBody extends StatefulWidget {
  const _ErrorDetailsScrollBody({required this.fullText, required this.theme});

  final String fullText;
  final ThemeData theme;

  @override
  State<_ErrorDetailsScrollBody> createState() =>
      _ErrorDetailsScrollBodyState();
}

class _ErrorDetailsScrollBodyState extends State<_ErrorDetailsScrollBody> {
  final ScrollController _scrollController = ScrollController();
  late _FriendlyErrorDetails _details = _FriendlyErrorDetails.parse(
    widget.fullText,
  );

  @override
  void didUpdateWidget(_ErrorDetailsScrollBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullText != widget.fullText) {
      _details = _FriendlyErrorDetails.parse(widget.fullText);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    final showStructuredSections = details.sections.isNotEmpty;
    final primaryText = details.structured ? details.summary : details.rawText;
    return PrimaryScrollController.none(
      child: OpenHandSafeScrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          primary: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ErrorSummaryBlock(text: primaryText, theme: widget.theme),
              if (showStructuredSections) ...[
                kOpenHandGap16,
                for (var i = 0; i < details.sections.length; i++) ...[
                  if (i > 0) kOpenHandGap14,
                  _ErrorDetailSectionBlock(
                    section: details.sections[i],
                    theme: widget.theme,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorSummaryBlock extends StatelessWidget {
  const _ErrorSummaryBlock({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.report_problem_rounded,
            size: 20,
            color: colorScheme.error,
          ),
        ),
        kOpenHandHGap10,
        Expanded(
          child: SelectableText(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.48,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorDetailSectionBlock extends StatelessWidget {
  const _ErrorDetailSectionBlock({required this.section, required this.theme});

  final _FriendlyErrorSection section;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, color: colorScheme.outlineVariant),
        kOpenHandGap12,
        Text(
          section.title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
            letterSpacing: 0,
          ),
        ),
        kOpenHandGap6,
        SelectableText(
          section.body,
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.48,
            color: colorScheme.onSurfaceVariant,
            fontFamily: section.monospace ? kOpenHandMonospaceFontFamily : null,
          ),
        ),
      ],
    );
  }
}

/// 多源错误详情正文。顶部展示整条错误摘要 + 上下文行（如请求方法/地址），
/// 下方为每个 [AiErrorSource] 渲染一张独立卡片（带彩色 chip 头 + 标题 +
/// 复用解析器分段的原因/建议/原文），避免多端点失败时重复标题串台。
/// 复用 [showAnimatedDialog] 的进退场动画。
class _MultiSourceErrorBody extends StatefulWidget {
  const _MultiSourceErrorBody({
    required this.fullText,
    required this.sources,
    required this.theme,
  });

  final String fullText;
  final List<AiErrorSource> sources;
  final ThemeData theme;

  @override
  State<_MultiSourceErrorBody> createState() => _MultiSourceErrorBodyState();
}

class _MultiSourceErrorBodyState extends State<_MultiSourceErrorBody> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final headline = _headlineFromText(widget.fullText);
    final contextLines = _contextLinesFromText(widget.fullText);
    return PrimaryScrollController.none(
      child: OpenHandSafeScrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          primary: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ErrorSummaryBlock(text: headline, theme: theme),
              if (contextLines.isNotEmpty) ...[
                kOpenHandGap8,
                _ErrorContextBlock(lines: contextLines, theme: theme),
              ],
              kOpenHandGap16,
              for (var i = 0; i < widget.sources.length; i++) ...[
                if (i > 0) kOpenHandGap12,
                _ErrorSourceCard(
                  source: widget.sources[i],
                  accentIndex: i,
                  theme: theme,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部摘要下方的次要上下文行（如请求方法/地址），以小字等宽展示，避免
/// 多源视图中这些调试信息被吞掉。
class _ErrorContextBlock extends StatelessWidget {
  const _ErrorContextBlock({required this.lines, required this.theme});

  final List<String> lines;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: kOpenHandBorderRadius10,
      ),
      child: SelectableText(
        lines.join('\n'),
        style: theme.textTheme.bodySmall?.copyWith(
          height: 1.45,
          color: colorScheme.onSurfaceVariant,
          fontFamily: kOpenHandMonospaceFontFamily,
        ),
      ),
    );
  }
}

class _ErrorSourceCard extends StatelessWidget {
  const _ErrorSourceCard({
    required this.source,
    required this.accentIndex,
    required this.theme,
  });

  final AiErrorSource source;
  final int accentIndex;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    // 交替用 errorContainer / surfaceContainerHighest 作底色，层次分明。
    final isAccent = accentIndex.isEven;
    final bg = isAccent
        ? colorScheme.errorContainer.withValues(alpha: 0.32)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.72);
    final chipBg = isAccent
        ? colorScheme.error.withValues(alpha: 0.16)
        : colorScheme.primary.withValues(alpha: 0.12);
    final chipFg = isAccent
        ? colorScheme.onErrorContainer.withValues(alpha: 0.92)
        : colorScheme.onSurfaceVariant;
    final details = _FriendlyErrorDetails.parse(source.body);
    final showStructured = details.sections.isNotEmpty;
    final primaryText = details.structured ? details.summary : details.rawText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: kOpenHandBorderRadius8,
            ),
            child: Text(
              source.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: chipFg,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          kOpenHandGap8,
          SelectableText(
            primaryText,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.48,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          if (showStructured) ...[
            kOpenHandGap8,
            for (var i = 0; i < details.sections.length; i++) ...[
              if (i > 0) kOpenHandGap10,
              _ErrorDetailSectionBlock(
                section: details.sections[i],
                theme: theme,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

String _headlineFromText(String text) {
  final normalized = text.replaceAll('\r\n', '\n').trim();
  if (normalized.isEmpty) return 'unknown error';
  return normalized
      .split('\n')
      .map((line) => line.trimRight())
      .firstWhere((line) => line.isNotEmpty, orElse: () => normalized);
}

/// 取 `fullText` 中除第一行外的非空上下文行（如请求方法/地址）。
List<String> _contextLinesFromText(String text) {
  final lines = text.replaceAll('\r\n', '\n').trim().split('\n');
  if (lines.length <= 1) return const <String>[];
  return lines
      .sublist(1)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

class _FriendlyErrorDetails {
  const _FriendlyErrorDetails({
    required this.rawText,
    required this.summary,
    required this.sections,
    required this.structured,
  });

  final String rawText;
  final String summary;
  final List<_FriendlyErrorSection> sections;
  final bool structured;

  static _FriendlyErrorDetails parse(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').trim();
    final rawText = normalized.isEmpty ? 'unknown error' : normalized;
    final sections = <_FriendlyErrorSection>[];
    var currentTitle = '概览';
    var structured = false;
    final buffer = <String>[];

    void flush() {
      final body = buffer.join('\n').trim();
      if (body.isEmpty) return;
      sections.add(
        _FriendlyErrorSection(
          title: currentTitle,
          body: body,
          monospace: _isRawErrorSection(currentTitle),
        ),
      );
      buffer.clear();
    }

    for (final line in rawText.split('\n')) {
      final trimmed = line.trimRight();
      final heading = _errorHeading(trimmed);
      if (heading == null) {
        buffer.add(trimmed);
        continue;
      }
      structured = true;
      flush();
      currentTitle = heading.title;
      if (heading.inlineBody.isNotEmpty) {
        buffer.add(heading.inlineBody);
      }
    }
    flush();

    final summary = sections.isEmpty
        ? rawText
        : sections.first.body
              .split('\n')
              .firstWhere(
                (line) => line.trim().isNotEmpty,
                orElse: () => sections.first.body,
              );
    final detailSections = sections.length <= 1
        ? <_FriendlyErrorSection>[]
        : sections.sublist(1);
    return _FriendlyErrorDetails(
      rawText: rawText,
      summary: summary.trim().isEmpty ? rawText : summary.trim(),
      sections: detailSections,
      structured: structured,
    );
  }
}

class _FriendlyErrorSection {
  const _FriendlyErrorSection({
    required this.title,
    required this.body,
    this.monospace = false,
  });

  final String title;
  final String body;
  final bool monospace;
}

class _ParsedErrorHeading {
  const _ParsedErrorHeading({required this.title, required this.inlineBody});

  final String title;
  final String inlineBody;
}

/// 「现象 / 原因 / 建议」等段落标题，中英双语。诊断文案逐行匹配，
/// 编译一次复用，避免每行都新建 [RegExp]。
final RegExp _kErrorHeadingPattern = RegExp(
  r'^(现象|概览|原因|建议|排查建议|服务端原文|服务端响应|原始响应|详情|完整信息|Summary|Reason|Suggestion|Troubleshooting|Server response|Raw response|Details)\s*[:：]\s*(.*)$',
  caseSensitive: false,
);

_ParsedErrorHeading? _errorHeading(String line) {
  final match = _kErrorHeadingPattern.firstMatch(line.trimLeft());
  if (match == null) return null;
  return _ParsedErrorHeading(
    title: match.group(1)!.trim(),
    inlineBody: match.group(2)!.trim(),
  );
}

bool _isRawErrorSection(String title) {
  final normalized = title.trim().toLowerCase();
  return normalized.contains('raw') ||
      normalized.contains('原始') ||
      normalized.contains('响应') ||
      normalized.contains('response');
}
