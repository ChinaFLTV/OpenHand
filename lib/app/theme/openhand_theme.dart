import 'dart:collection';

import 'package:flutter/material.dart';

import '../../shared/ui/interaction_timings.dart';
import '../../shared/ui/openhand_spacing.dart';
import 'openhand_palette.dart';
import 'openhand_theme_preset.dart';

abstract final class OpenHandTheme {
  /// 主题构造（ColorScheme.fromSeed + OpenHandPalette + 三十来个组件子主题）
  /// 开销不小，而 MaterialApp 会因为 SettingsController 的任意通知重建——
  /// 语言、模型列表变化同样会触发，此时亮度与预设其实没变。按
  /// (brightness, preset) 缓存即可避开重复构造。
  ///
  /// 预设有二十种上下，两种亮度合计四十余个组合，缓存放不下全部，所以淘汰
  /// 策略必须是 LRU 而不是插入序：当前正在用的那一对（亮 + 暗）始终是最近
  /// 使用的，永远不会被挤掉；换预设时被淘汰的是早已不用的旧主题。
  static final LinkedHashMap<String, ThemeData> _cache =
      LinkedHashMap<String, ThemeData>();
  static const int _cacheLimit = 8;

  static ThemeData light(OpenHandThemePreset preset) =>
      _cachedTheme(Brightness.light, preset);

  static ThemeData dark(OpenHandThemePreset preset) =>
      _cachedTheme(Brightness.dark, preset);

  static ThemeData _cachedTheme(
    Brightness brightness,
    OpenHandThemePreset preset,
  ) {
    final key = '${brightness.name}:${preset.name}';
    final cached = _cache.remove(key);
    if (cached != null) {
      // 重新插入到末尾即为「最近使用」。
      return _cache[key] = cached;
    }
    while (_cache.length >= _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    return _cache[key] = _buildTheme(brightness, preset);
  }

  static ThemeData _buildTheme(
    Brightness brightness,
    OpenHandThemePreset preset,
  ) {
    final isDark = brightness == Brightness.dark;
    final seedColor = preset.seedColor;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
      contrastLevel: isDark ? 0.0 : 0.12,
    );
    final palette = OpenHandPalette(
      canvasStart: isDark
          ? colorScheme.surfaceDim
          : Color.lerp(
                  colorScheme.surfaceBright,
                  colorScheme.tertiaryContainer,
                  0.28,
                ) ??
                colorScheme.surfaceBright,
      canvasEnd: isDark
          ? colorScheme.surfaceContainerLowest
          : Color.lerp(
                  colorScheme.surfaceContainerLowest,
                  colorScheme.secondaryContainer,
                  0.24,
                ) ??
                colorScheme.surfaceContainerLowest,
      sidebarBackground: colorScheme.surfaceContainerLow.withValues(
        alpha: isDark ? 0.86 : 0.92,
      ),
      contentBackground: colorScheme.surface.withValues(
        alpha: isDark ? 0.92 : 0.97,
      ),
      composerBackground: colorScheme.surfaceContainerHigh,
      highlight: colorScheme.primary,
      outlineSoft: colorScheme.outlineVariant.withValues(
        alpha: isDark ? 0.72 : 0.9,
      ),
    );
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: colorScheme.surface,
      dividerTheme: DividerThemeData(
        color: palette.outlineSoft,
        space: 1,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow.withValues(
          alpha: isDark ? 0.86 : 0.94,
        ),
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
        surfaceTintColor: colorScheme.surfaceTint,
        margin: EdgeInsets.zero,
       shape: RoundedRectangleBorder(
          borderRadius: kOpenHandBorderRadius32,
          side: BorderSide(color: palette.outlineSoft),
        ),
      ),
      chipTheme: baseTheme.chipTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.primaryContainer,
        // 选中态统一对齐全局 highlight（= colorScheme.primary，
        // 即 sidebar 高亮 / 主操作按钮 / 输入框聚焦边框的同色系）。早期
        // 用 secondaryContainer，在 expressive 调度下会偏到互补色（橄
        // 榄主色 → 粉/淡紫 secondary），与应用其它"被选中/激活"控件
        // 的橄榄绿不一致。这里改成 primaryContainer + onPrimaryContainer，
        // 边框升一级到 primary，整体收回到主色调性。
        labelStyle: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: TextStyle(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
        checkmarkColor: colorScheme.onPrimaryContainer,
        iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.55),
            );
          }
          return BorderSide(color: palette.outlineSoft);
        }),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kOpenHandRadius22)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kOpenHandRadius22),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: palette.outlineSoft),
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kOpenHandRadius22),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primaryContainer;
            }
            return colorScheme.surfaceContainerHigh;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onPrimaryContainer;
            }
            return colorScheme.onSurfaceVariant;
          }),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(kOpenHandRadius18)),
          ),
        ),
      ),
      tooltipTheme: const TooltipThemeData(waitDuration: kOpenHandTooltipWait),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.45 : 0.84,
        ),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kOpenHandRadius24),
          borderSide: BorderSide(color: palette.outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kOpenHandRadius24),
          borderSide: BorderSide(color: palette.outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kOpenHandRadius24),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 3,
        shadowColor: colorScheme.shadow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: kOpenHandBorderRadius16,
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kOpenHandRadius24)),
        selectedTileColor: colorScheme.secondaryContainer.withValues(
          alpha: isDark ? 0.34 : 0.72,
        ),
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kOpenHandRadius24),
        ),
        tileHeight: 58,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return baseTheme.textTheme.titleMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurface,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
            size: 22,
          );
        }),
      ),
      searchBarTheme: SearchBarThemeData(
        constraints: const BoxConstraints(minHeight: 58),
        elevation: const WidgetStatePropertyAll<double>(0),
        backgroundColor: WidgetStatePropertyAll<Color>(
          colorScheme.surfaceContainerHigh,
        ),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: palette.outlineSoft),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(kOpenHandRadius24)),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 18),
        ),
        hintStyle: WidgetStatePropertyAll<TextStyle?>(
          baseTheme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          baseTheme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(kOpenHandRadius22)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.primaryContainer;
            }
            return null;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onPrimaryContainer;
            }
            return colorScheme.onSurface;
          }),
          iconColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onPrimaryContainer;
            }
            return colorScheme.onSurfaceVariant;
          }),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        // inverseSurface 在深色主题下是浅灰色（M3 默认），
        // 与深色主题整体配色不协调。改用 surfaceContainerHigh 在深色主题下
        // 呈现深色调，保持视觉一致性；亮色主题继续用 inverseSurface。
        backgroundColor: isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.inverseSurface,
        contentTextStyle: baseTheme.textTheme.bodyMedium?.copyWith(
          color: isDark ? colorScheme.onSurface : colorScheme.onInverseSurface,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: isDark
            ? colorScheme.primary
            : colorScheme.inversePrimary,
        closeIconColor:
            (isDark ? colorScheme.onSurface : colorScheme.onInverseSurface)
                .withValues(alpha: 0.7),
        // 禁用框架内置的 close icon（它在 M3 下有不可控的白色背景），
        // 改由 OpenHandSnackBar._ensureMotionWrapped 注入无背景的自定义关闭按钮。
        showCloseIcon: false,
        dismissDirection: DismissDirection.down,
        elevation: isDark ? 6 : 4,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kOpenHandRadius14)),
      ),
      textTheme: baseTheme.textTheme.copyWith(
        displaySmall: baseTheme.textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.4,
          height: 1.0,
        ),
        headlineSmall: baseTheme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(height: 1.48),
        bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(height: 1.42),
      ),
      extensions: <ThemeExtension<dynamic>>[palette],
    );
  }
}
