import 'package:flutter/material.dart';

import 'openhand_palette.dart';
import 'openhand_theme_preset.dart';

abstract final class OpenHandTheme {
  // 2026-04-25 perf — ThemeData construction (ColorScheme.fromSeed +
  // OpenHandPalette + ~30 component sub-themes) is non-trivial and runs on
  // every OpenHandApp.build(). MaterialApp rebuilds frequently from
  // SettingsController notifications even when neither brightness nor
  // preset changed (e.g. unrelated locale or model-list updates), so cache
  // by (brightness, preset.id) to avoid recomputing identical themes.
  // Bounded to 8 entries (2 brightnesses × N presets); cheap LRU eviction.
  static final Map<String, ThemeData> _cache = <String, ThemeData>{};
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
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }
    if (_cache.length >= _cacheLimit) {
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
          borderRadius: BorderRadius.circular(32),
          side: BorderSide(color: palette.outlineSoft),
        ),
      ),
      chipTheme: baseTheme.chipTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.secondaryContainer,
        // 2026-05-04: 仅设置 backgroundColor / selectedColor 不够 ——
        // ChoiceChip / FilterChip 在 selected 状态下的 label/勾标
        // 默认会落回 baseTheme（M3 默认 onSurfaceVariant /主题
        // primary），与我们在 selectedColor 改用的
        // secondaryContainer 配色脱节，肉眼看就是"按下后的高亮
        // 跟主题不搭"。这里把 secondaryLabelStyle 与 checkmark
        // 都拉到 onSecondaryContainer，再用 WidgetStateBorderSide
        // 让 selected 边框升一级到 secondary 主色，整体保持
        // M3 secondary 容器调性。
        labelStyle: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: TextStyle(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
        checkmarkColor: colorScheme.onSecondaryContainer,
        iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return BorderSide(
              color: colorScheme.secondary.withValues(alpha: 0.55),
            );
          }
          return BorderSide(color: palette.outlineSoft);
        }),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
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
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.secondaryContainer;
            }
            return colorScheme.surfaceContainerHigh;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onSecondaryContainer;
            }
            return colorScheme.onSurfaceVariant;
          }),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ),
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
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: palette.outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: palette.outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
          borderRadius: BorderRadius.circular(24),
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
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: baseTheme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
