import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'oh_pill.dart';
import 'openhand_spacing.dart';
import 'openhand_typography.dart';

/// 编程专家文件编辑器与弹窗/工作流代码编辑器共用的尺寸与色值。
const double kOpenHandEditorFontSizeDefault = 13;
const double kOpenHandEditorFontSizeMin = 8;
const double kOpenHandEditorFontSizeMax = 32;
const double kOpenHandEditorLineHeight = 1.55;
const double kOpenHandEditorHeaderHeight = 30;
const double kOpenHandEditorStatusBarHeight = 24;
const double kOpenHandEditorTextPaddingLeft = 8;
const double kOpenHandEditorTextPaddingRight = 12;
const double kOpenHandEditorTextPaddingTop = 10;
const double kOpenHandEditorTextPaddingBottom = 10;
const double kOpenHandEditorToolbarFieldHeight = 30;
const double kOpenHandEditorToolbarFieldRadius = 6;
const double kOpenHandEditorToolbarFieldFontSize = 13;
const double kOpenHandEditorToolbarSurfaceAlpha = 0.95;
const double kOpenHandEditorHairline = 0.5;
const double kOpenHandEditorHairlineStrongAlpha = 0.25;
const double kOpenHandEditorHairlineSoftAlpha = 0.2;
const double kOpenHandEditorMaxEstimatedContentWidth = 32000;
const Color kOpenHandEditorDarkSurfaceText = Color(0xFFE5EDF5);
const Color kOpenHandEditorLightSurfaceText = Color(0xFF111827);

const EdgeInsets kOpenHandEditorContentPadding = EdgeInsets.only(
  top: kOpenHandEditorTextPaddingTop,
  bottom: kOpenHandEditorTextPaddingBottom,
  left: kOpenHandEditorTextPaddingLeft,
  right: kOpenHandEditorTextPaddingRight,
);

enum OpenHandEditorToolbarEdge { top, bottom }

BoxDecoration openHandEditorChromeDecoration(
  ColorScheme colorScheme, {
  BorderRadius borderRadius = BorderRadius.zero,
}) {
  return BoxDecoration(
    color: colorScheme.surfaceContainerLow,
    borderRadius: borderRadius,
    border: Border.all(
      color: colorScheme.outlineVariant.withValues(
        alpha: kOpenHandEditorHairlineSoftAlpha,
      ),
      width: kOpenHandEditorHairline,
    ),
  );
}

BoxDecoration openHandEditorToolbarSurface(
  ColorScheme colorScheme, {
  OpenHandEditorToolbarEdge edge = OpenHandEditorToolbarEdge.bottom,
}) {
  final divider = BorderSide(
    color: colorScheme.outlineVariant.withValues(
      alpha: kOpenHandEditorHairlineStrongAlpha,
    ),
    width: kOpenHandEditorHairline,
  );
  return BoxDecoration(
    color: colorScheme.surfaceContainerHigh.withValues(
      alpha: kOpenHandEditorToolbarSurfaceAlpha,
    ),
    border: edge == OpenHandEditorToolbarEdge.top
        ? Border(top: divider)
        : Border(bottom: divider),
  );
}

BoxDecoration openHandEditorStatusBarDecoration(ColorScheme colorScheme) {
  return BoxDecoration(
    color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
    border: Border(
      top: BorderSide(
        color: colorScheme.outlineVariant.withValues(
          alpha: kOpenHandEditorHairlineSoftAlpha,
        ),
        width: kOpenHandEditorHairline,
      ),
    ),
  );
}

InputDecoration openHandEditorToolbarInputDecoration(
  ColorScheme colorScheme, {
  String? hintText,
}) {
  final outlineBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(kOpenHandEditorToolbarFieldRadius),
    borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(
      fontSize: kOpenHandEditorToolbarFieldFontSize,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    isDense: true,
    border: outlineBorder,
    enabledBorder: outlineBorder,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kOpenHandEditorToolbarFieldRadius),
      borderSide: BorderSide(color: colorScheme.primary),
    ),
    filled: true,
    fillColor: colorScheme.surface,
  );
}

TextStyle openHandEditorBaseStyle(double fontSize) => TextStyle(
  fontFamily: kOpenHandMonospaceFontFamily,
  fontSize: fontSize,
  height: kOpenHandEditorLineHeight,
  letterSpacing: 0,
);

Color openHandEditorSurfaceTextColor({required bool darkSurface}) {
  return darkSurface
      ? kOpenHandEditorDarkSurfaceText
      : kOpenHandEditorLightSurfaceText;
}

double openHandEditorLineNumberTextWidth({
  required int lineCount,
  required double fontSize,
}) {
  final digits = math.max(1, '$lineCount'.length);
  final painter = TextPainter(
    text: TextSpan(
      text: List<String>.filled(digits, '8').join(),
      style: TextStyle(
        fontFamily: kOpenHandMonospaceFontFamily,
        fontSize: fontSize,
        height: kOpenHandEditorLineHeight,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return painter.width.ceilToDouble();
}

double openHandEditorGutterWidth({
  required int lineCount,
  required double fontSize,
  bool hasDiagnostics = false,
}) {
  final basePadding = hasDiagnostics ? 62.0 : 40.0;
  final minimumWidth = hasDiagnostics ? 88.0 : 60.0;
  return math.max(
    minimumWidth,
    openHandEditorLineNumberTextWidth(
          lineCount: lineCount,
          fontSize: fontSize,
        ) +
        basePadding,
  );
}

double openHandEditorPreviewGutterWidth({
  required int lineCount,
  required double fontSize,
}) {
  return math.max(
    56.0,
    openHandEditorLineNumberTextWidth(
          lineCount: lineCount,
          fontSize: fontSize,
        ) +
        32.0,
  );
}

/// 查找 / 跳转 / 诊断条上的 16px 图标按钮。
class OpenHandEditorFindBarButton extends StatelessWidget {
  const OpenHandEditorFindBarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.colorScheme,
    this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final ColorScheme colorScheme;
  final VoidCallback? onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive
            ? colorScheme.primaryContainer.withValues(alpha: 0.6)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(kOpenHandRadius4),
        child: InkWell(
          borderRadius: BorderRadius.circular(kOpenHandRadius4),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              icon,
              size: 16,
              color: onPressed == null
                  ? colorScheme.onSurfaceVariant.withValues(alpha: 0.3)
                  : isActive
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 页签行 / 面包屑右侧的 17px 圆形操作按钮。
class OpenHandEditorHeaderActionButton extends StatelessWidget {
  const OpenHandEditorHeaderActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = onPressed == null
        ? color.withValues(alpha: 0.35)
        : color;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: kOpenHandPillBorderRadius,
        child: InkWell(
          borderRadius: kOpenHandPillBorderRadius,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 17, color: resolvedColor),
          ),
        ),
      ),
    );
  }
}

/// 状态栏紧凑芯片：图标 13 + 11px 标签。
class OpenHandEditorStatusChip extends StatelessWidget {
  const OpenHandEditorStatusChip({
    super.key,
    required this.colorScheme,
    required this.icon,
    required this.label,
    this.onPressed,
    this.tooltip,
    this.foregroundColor,
    this.active = false,
  });

  final ColorScheme colorScheme;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? foregroundColor;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final resolvedForeground = (foregroundColor ?? colorScheme.onSurfaceVariant)
        .withValues(alpha: onPressed == null ? 0.35 : 1);
    final chip = Material(
      color: active
          ? colorScheme.primaryContainer.withValues(alpha: 0.6)
          : Colors.transparent,
      borderRadius: kOpenHandBorderRadius8,
      child: InkWell(
        borderRadius: kOpenHandBorderRadius8,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: resolvedForeground),
              kOpenHandHGap5,
              Text(
                label,
                style: TextStyle(fontSize: 11, color: resolvedForeground),
              ),
            ],
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) {
      return chip;
    }
    return Tooltip(message: tooltip, child: chip);
  }
}
