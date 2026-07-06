import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'animated_dialog.dart';
import 'openhand_dialog_action_button.dart';
import 'openhand_safe_scrollbar.dart';
import 'openhand_snack_bar.dart';

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
}) {
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
  final hasDetails = lines.length > 1;
  final messenger = ScaffoldMessenger.maybeOf(context);
  // SnackBarAction 的 onPressed 触发时，调用方 context 往往已离开树
  // （例如发出 SnackBar 的临时 widget 已 dispose），此时再用它去
  // showAnimatedDialog 会触发「Looking up a deactivated widget's
  // ancestor is unsafe」断言。这里提前抓住根 Navigator 的 context，
  // 它由 MaterialApp 持有，生命周期与 App 一致，可在异步回调里安全使用。
  final rootContext = Navigator.of(context, rootNavigator: true).context;
  OpenHandSnackBar.hideCurrentOn(messenger);
  OpenHandSnackBar.show(
    context,
    messenger,
    OpenHandSnackBar.error(
      context,
      headline,
      maxLines: 2,
      duration: hasDetails
          ? _kFriendlyErrorDetailsSnackDuration
          : kOpenHandSnackBarErrorDuration,
      action: hasDetails
          ? SnackBarAction(
              label: l10n.commonDetails,
              onPressed: () {
                if (!rootContext.mounted) return;
                showFriendlyErrorDetailsDialog(
                  rootContext,
                  fullText: effective,
                );
              },
            )
          : null,
    ),
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
}) {
  _showErrorDetailsDialog(context, fullText: fullText, title: title);
}

void _showErrorDetailsDialog(
  BuildContext context, {
  required String fullText,
  String? title,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      final theme = Theme.of(dialogContext);
      return buildOpenHandAlertDialog(
        icon: Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
        title: Text(title ?? l10n.sessMetaErrorDetail),
        content: buildOpenHandDialogConstrainedContent(
          maxWidth: 680,
          maxHeight: 560,
          child: _ErrorDetailsScrollBody(fullText: fullText, theme: theme),
        ),
        actions: <Widget>[
          OpenHandDialogActionButton.secondary(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: fullText));
              if (!dialogContext.mounted) return;
              final messenger = ScaffoldMessenger.maybeOf(dialogContext);
              OpenHandSnackBar.hideCurrentOn(messenger);
              OpenHandSnackBar.show(
                dialogContext,
                messenger,
                OpenHandSnackBar.success(
                  dialogContext,
                  l10n.commonCopiedToClipboard,
                ),
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final details = _FriendlyErrorDetails.parse(widget.fullText);
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
                const SizedBox(height: 16),
                for (var i = 0; i < details.sections.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
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
        const SizedBox(width: 10),
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
        const SizedBox(height: 12),
        Text(
          section.title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          section.body,
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.48,
            color: colorScheme.onSurfaceVariant,
            fontFamily: section.monospace ? 'monospace' : null,
          ),
        ),
      ],
    );
  }
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

_ParsedErrorHeading? _errorHeading(String line) {
  final match = RegExp(
    r'^(现象|概览|原因|建议|排查建议|服务端原文|服务端响应|原始响应|详情|完整信息|Summary|Reason|Suggestion|Troubleshooting|Server response|Raw response|Details)\s*[:：]\s*(.*)$',
    caseSensitive: false,
  ).firstMatch(line.trimLeft());
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
