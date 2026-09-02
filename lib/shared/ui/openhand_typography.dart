/// 全局排版 token —— 收敛散落在各处的字体族字面量。
///
/// 约定：代码、日志、终端、报文、哈希等一切需要等宽对齐的文本，一律使用
/// [kOpenHandMonospaceFontFamily]，不再逐处书写具体字体名。
///
/// 为什么不写 `'SF Mono'` / `'Menlo'` / `'JetBrains Mono'` 这类具体族名：
/// Flutter 的 `TextStyle.fontFamily` 只接受**单个**族名，既不解析 CSS 风格的
/// 逗号列表，也不会在族名缺失时回退到等宽族——具体族名在缺少该字体的平台上会
/// 静默退回默认比例字体，直接破坏列对齐。`'monospace'` 是各平台字体管理器都
/// 认识的通用族名，由系统解析到本机最合适的等宽字体。
library;

import 'package:flutter/material.dart';

import 'openhand_spacing.dart';

const String kOpenHandMonospaceFontFamily = 'monospace';

/// 代码 / 差异面板正文的等宽字号与行高。
const double kOpenHandCodeBodyFontSize = 12.5;
const double kOpenHandCodeBodyLineHeight = 1.34;

/// 代码块正文样式：等宽族 + 表格数字对齐，主题缺失 bodySmall 时给出等价兜底。
TextStyle openHandCodeBodyTextStyle(ThemeData theme, {required Color color}) {
  const features = <FontFeature>[FontFeature.tabularFigures()];
  return theme.textTheme.bodySmall?.copyWith(
        fontFamily: kOpenHandMonospaceFontFamily,
        fontSize: kOpenHandCodeBodyFontSize,
        height: kOpenHandCodeBodyLineHeight,
        color: color,
        fontFeatures: features,
      ) ??
      const TextStyle(
        fontFamily: kOpenHandMonospaceFontFamily,
        fontSize: kOpenHandCodeBodyFontSize,
        height: kOpenHandCodeBodyLineHeight,
        fontFeatures: features,
      ).copyWith(color: color);
}

/// 图标与次级短文本组成的紧凑行内标签。
class OpenHandInlineIconLabel extends StatelessWidget {
  const OpenHandInlineIconLabel({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.iconSize = 14,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: foreground),
        kOpenHandHGap4,
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: foreground),
        ),
      ],
    );
  }
}
