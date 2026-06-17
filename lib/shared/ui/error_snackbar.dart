import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'animated_dialog.dart';
import 'openhand_dialog_action_button.dart';
import 'openhand_safe_scrollbar.dart';
import 'openhand_snack_bar.dart';

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
  final messenger = ScaffoldMessenger.of(context);
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
          ? const Duration(seconds: 6)
          : const Duration(seconds: 4),
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
}) {
  _showErrorDetailsDialog(context, fullText: fullText);
}

void _showErrorDetailsDialog(BuildContext context, {required String fullText}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      final theme = Theme.of(dialogContext);
      return buildOpenHandAlertDialog(
        title: Text(l10n.sessMetaErrorDetail),
        content: buildOpenHandDialogConstrainedContent(
          maxWidth: 560,
          maxHeight: 480,
          child: _ErrorDetailsScrollBody(fullText: fullText, theme: theme),
        ),
        actions: <Widget>[
          OpenHandDialogActionButton.secondary(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: fullText));
              if (!dialogContext.mounted) return;
              final messenger = ScaffoldMessenger.of(dialogContext);
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
    return PrimaryScrollController.none(
      child: OpenHandSafeScrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          primary: false,
          child: SelectableText(
            widget.fullText,
            style: widget.theme.textTheme.bodyMedium?.copyWith(
              height: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
