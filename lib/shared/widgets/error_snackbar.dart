import 'package:flutter/material.dart';

import 'animated_dialog.dart';

/// 把可能很长的「现象 / 原因 / 建议」三段式错误文案以**对用户友好**的方式
/// 展示在 SnackBar 上：
///   · SnackBar 主文本只截取第一非空行（作者设计为简短中英标题）
///   · 当原始文本含有多行时，附带「详情 / Details」动作按钮，点击后
///     弹出 AlertDialog 用 SelectableText 完整展示，便于复制 / 排查
///
/// 这样用户既不会被 SnackBar 截断的长报错气死，也能在需要时拿到完整
/// 排错信息。同时也避免到处堆砌 dialog 重复样板。
void showFriendlyErrorSnackBar(
  BuildContext context, {
  required String? message,
  required String fallback,
}) {
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
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        headline,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      duration: hasDetails ? const Duration(seconds: 6) : const Duration(seconds: 4),
      action: hasDetails
          ? SnackBarAction(
              label: '详情 / Details',
              onPressed: () {
                _showErrorDetailsDialog(context, fullText: effective);
              },
            )
          : null,
    ),
  );
}

void _showErrorDetailsDialog(
  BuildContext context,
  {required String fullText}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        title: const Text('错误详情 / Error details'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
          child: Scrollbar(
            child: SingleChildScrollView(
              child: SelectableText(
                fullText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭 / Close'),
          ),
        ],
      );
    },
  );
}
