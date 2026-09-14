import 'package:flutter/material.dart';

/// Markdown 正文按「所在容器的实际背景」推导出的一组基础色。
///
/// 叠加基色、两级表面、强调色、链接色与引用块底色都从这里出，避免会话气泡、
/// Harness 面板和其他 Markdown 表面各写一份后逐渐分叉。
class OpenHandMarkdownSurfaceTones {
  factory OpenHandMarkdownSurfaceTones.resolve({
    required ColorScheme colorScheme,
    required Color background,
  }) {
    final isDark =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
    final overlayBase = isDark ? Colors.white : Colors.black;
    final accent = isDark
        ? Color.lerp(
                colorScheme.primaryContainer,
                Colors.white,
                _kAccentLift,
              ) ??
              colorScheme.primaryContainer
        : colorScheme.primary;
    return OpenHandMarkdownSurfaceTones._(
      isDark: isDark,
      overlayBase: overlayBase,
      subtleSurface: Color.alphaBlend(
        overlayBase.withValues(alpha: isDark ? 0.06 : 0.035),
        background,
      ),
      elevatedSurface: Color.alphaBlend(
        overlayBase.withValues(alpha: isDark ? 0.11 : 0.06),
        background,
      ),
      accent: accent,
      link: isDark
          ? Color.lerp(accent, Colors.white, _kAccentLift) ?? accent
          : accent,
    );
  }

  const OpenHandMarkdownSurfaceTones._({
    required this.isDark,
    required this.overlayBase,
    required this.subtleSurface,
    required this.elevatedSurface,
    required this.accent,
    required this.link,
  });

  /// 深色背景下强调色与链接色朝白色提亮的幅度。
  static const double _kAccentLift = 0.08;

  /// 背景估算出的明暗，决定所有叠加方向。
  final bool isDark;

  /// 叠加基色：深底叠白、浅底叠黑。
  final Color overlayBase;

  /// 轻微抬起的表面（表格斑马纹这类）。
  final Color subtleSurface;

  /// 明显抬起的表面（代码块、引用块底色的基底）。
  final Color elevatedSurface;

  final Color accent;
  final Color link;

  /// 引用块底色：强调色叠在抬起表面上，深浅主题用不同透明度。
  Color get quoteFill => Color.alphaBlend(
    accent.withValues(alpha: isDark ? 0.16 : 0.07),
    elevatedSurface,
  );
}
