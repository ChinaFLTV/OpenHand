import 'package:flutter/material.dart';

/// 面板内的空态提示：居中一行次级说明。
///
/// 全库有 69 处各写一遍：字号在 bodySmall / bodyMedium / bodyLarge 之间摇摆，
/// 内边距从 12 到 32 都有，一半干脆没有。同样是「这里没有内容」，在不同面板里
/// 却是不同的字号和留白，看起来不像同一个应用。
///
/// 与 [FeatureStateCard] 的分工：那个是页面级空态（图标 + 标题 + 说明 + 操作），
/// 分量重；这里是面板内、卡片内的轻量提示，只有一行字。
class OpenHandInlineEmptyState extends StatelessWidget {
  const OpenHandInlineEmptyState({
    super.key,
    required this.message,
    this.dense = false,
    this.textAlign = TextAlign.center,
  });

  final String message;

  /// 紧凑档：用于卡片内、侧栏这类空间本就局促的位置。
  final bool dense;

  final TextAlign textAlign;

  /// 两档内边距。标准档给主面板留出呼吸，紧凑档只留最小间隙。
  static const double _kStandardPadding = 24;
  static const double _kDensePadding = 16;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        (dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(dense ? _kDensePadding : _kStandardPadding),
        child: Text(message, textAlign: textAlign, style: style),
      ),
    );
  }
}
