import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../app/theme/openhand_palette.dart';
import 'markdown_inline_code.dart';
import 'markdown_surface_tones.dart';
import 'openhand_spacing.dart';
import 'openhand_typography.dart';

/// 线程消息与独立详情共用的 Markdown 视觉配置。
class OpenHandMessageMarkdownThemeData {
  const OpenHandMessageMarkdownThemeData({
    required this.styleSheet,
    required this.inlineCodeBuilder,
  });

  factory OpenHandMessageMarkdownThemeData.resolve({
    required ThemeData theme,
    required Color backgroundColor,
    required Color textColor,
    bool useDarkCodeSurface = false,
    bool useCustomCodeBlockBuilder = true,
  }) {
    final cacheKey = Object.hash(
      theme.brightness.index,
      theme.colorScheme.primary.toARGB32(),
      theme.colorScheme.primaryContainer.toARGB32(),
      theme.textTheme.bodyLarge?.fontSize,
      theme.textTheme.bodyMedium?.fontSize,
      backgroundColor.toARGB32(),
      textColor.toARGB32(),
      useDarkCodeSurface,
      useCustomCodeBlockBuilder,
    );
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }
    final result = _build(
      theme: theme,
      backgroundColor: backgroundColor,
      textColor: textColor,
      useDarkCodeSurface: useDarkCodeSurface,
      useCustomCodeBlockBuilder: useCustomCodeBlockBuilder,
    );
    _cache[cacheKey] = result;
    while (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    return result;
  }

  static OpenHandMessageMarkdownThemeData _build({
    required ThemeData theme,
    required Color backgroundColor,
    required Color textColor,
    required bool useDarkCodeSurface,
    required bool useCustomCodeBlockBuilder,
  }) {
    final colorScheme = theme.colorScheme;
    final palette = theme.extension<OpenHandPalette>();
    final tones = OpenHandMarkdownSurfaceTones.resolve(
      colorScheme: colorScheme,
      background: backgroundColor,
    );
    final overlayBase = tones.overlayBase;
    final inlineCodeSurface = Color.alphaBlend(
      overlayBase.withValues(alpha: tones.isDark ? 0.12 : 0.055),
      backgroundColor,
    );
    final borderColor =
        palette?.outlineSoft.withValues(alpha: tones.isDark ? 0.72 : 0.88) ??
        Color.alphaBlend(
          overlayBase.withValues(alpha: tones.isDark ? 0.18 : 0.12),
          backgroundColor,
        );
    final quoteSurface = Color.alphaBlend(
      tones.accent.withValues(alpha: tones.isDark ? 0.16 : 0.07),
      tones.elevatedSurface,
    );
    final secondaryTextColor = textColor.withValues(
      alpha: tones.isDark ? 0.92 : 0.88,
    );
    final bodyFontSize = theme.textTheme.bodyMedium?.fontSize ?? 14;
    final bodyStyle = openHandMessageBodyTextStyle(theme, color: textColor);
    final headingStyle = bodyStyle.copyWith(height: 1.24, letterSpacing: -0.22);
    final codeStyle =
        theme.textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: bodyFontSize * 0.92,
          fontWeight: FontWeight.w500,
          height: 1.28,
        ) ??
        TextStyle(
          color: textColor,
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: bodyFontSize * 0.92,
          fontWeight: FontWeight.w500,
          height: 1.28,
        );
    return OpenHandMessageMarkdownThemeData(
      inlineCodeBuilder: OpenHandMarkdownInlineCodeBuilder(
        textStyle: codeStyle,
        backgroundColor: inlineCodeSurface,
      ),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        a: bodyStyle.copyWith(
          color: tones.link,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: tones.link.withValues(alpha: 0.78),
        ),
        p: bodyStyle,
        pPadding: EdgeInsets.zero,
        code: codeStyle,
        h1: headingStyle.copyWith(
          fontSize: bodyFontSize * 1.46,
          fontWeight: FontWeight.w800,
        ),
        h1Padding: const EdgeInsets.only(top: 4, bottom: 2),
        h2: headingStyle.copyWith(
          fontSize: bodyFontSize * 1.28,
          fontWeight: FontWeight.w800,
        ),
        h2Padding: const EdgeInsets.only(top: 3, bottom: 1),
        h3: headingStyle.copyWith(
          fontSize: bodyFontSize * 1.15,
          fontWeight: FontWeight.w700,
        ),
        h3Padding: const EdgeInsets.only(top: 2),
        h4: headingStyle.copyWith(
          fontSize: bodyFontSize * 1.07,
          fontWeight: FontWeight.w700,
        ),
        h4Padding: const EdgeInsets.only(top: 1),
        h5: headingStyle.copyWith(fontWeight: FontWeight.w700),
        h6: headingStyle.copyWith(
          color: secondaryTextColor,
          fontWeight: FontWeight.w700,
        ),
        em: bodyStyle.copyWith(fontStyle: FontStyle.italic),
        strong: bodyStyle.copyWith(fontWeight: FontWeight.w700),
        del: bodyStyle.copyWith(decoration: TextDecoration.lineThrough),
        blockquote: bodyStyle.copyWith(color: secondaryTextColor),
        blockSpacing: 10,
        listIndent: 22,
        listBullet: bodyStyle.copyWith(
          color: secondaryTextColor,
          fontWeight: FontWeight.w700,
        ),
        listBulletPadding: const EdgeInsets.only(right: 7),
        tableHead: bodyStyle.copyWith(fontWeight: FontWeight.w700),
        tableBody: bodyStyle.copyWith(
          fontSize: bodyFontSize * 0.95,
          height: 1.42,
        ),
        tableBorder: TableBorder.all(
          color: borderColor,
          borderRadius: kOpenHandBorderRadius12,
        ),
        tablePadding: const EdgeInsets.symmetric(vertical: 2),
        tableCellsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        tableCellsDecoration: BoxDecoration(color: tones.subtleSurface),
        tableHeadCellsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        tableHeadCellsDecoration: BoxDecoration(color: tones.elevatedSurface),
        tableColumnWidth: const IntrinsicColumnWidth(),
        blockquotePadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        blockquoteDecoration: BoxDecoration(
          color: quoteSurface,
          borderRadius: kOpenHandBorderRadius12,
          border: Border(left: BorderSide(color: tones.accent, width: 2.5)),
        ),
        codeblockPadding: useCustomCodeBlockBuilder
            ? EdgeInsets.zero
            : const EdgeInsets.all(14),
        codeblockDecoration: useCustomCodeBlockBuilder
            ? const BoxDecoration()
            : BoxDecoration(
                color: useDarkCodeSurface
                    ? colorScheme.surfaceContainerHighest
                    : tones.elevatedSurface,
                borderRadius: kOpenHandBorderRadius12,
                border: Border.all(color: borderColor),
              ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: borderColor)),
        ),
      ),
    );
  }

  static const int _cacheLimit = 64;
  static final LinkedHashMap<int, OpenHandMessageMarkdownThemeData> _cache =
      LinkedHashMap<int, OpenHandMessageMarkdownThemeData>();

  final MarkdownStyleSheet styleSheet;
  final OpenHandMarkdownInlineCodeBuilder inlineCodeBuilder;
}
