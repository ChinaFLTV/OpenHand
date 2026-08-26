import 'package:flutter/material.dart';

import 'motion_durations.dart';
import 'openhand_spacing.dart';

const double _startupFailureMaxWidth = 720;
const double _startupFailureCompactBreakpoint = 560;

/// 在完整应用依赖尚未就绪时展示的独立启动失败页面。
class OpenHandStartupFailureApp extends StatelessWidget {
  const OpenHandStartupFailureApp({
    super.key,
    required this.title,
    required this.reason,
    required this.suggestionsTitle,
    required this.suggestions,
  });

  final String title;
  final String reason;
  final String suggestionsTitle;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: Scaffold(
        body: _StartupFailureBody(
          title: title,
          reason: reason,
          suggestionsTitle: suggestionsTitle,
          suggestions: suggestions,
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2563EB),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
    );
  }
}

class _StartupFailureBody extends StatelessWidget {
  const _StartupFailureBody({
    required this.title,
    required this.reason,
    required this.suggestionsTitle,
    required this.suggestions,
  });

  final String title;
  final String reason;
  final String suggestionsTitle;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final duration = media.disableAnimations
        ? Duration.zero
        : kOpenHandMotion520;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _startupFailureCompactBreakpoint;
        final horizontalPadding = compact ? 20.0 : 40.0;
        final verticalPadding = compact ? 24.0 : 40.0;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - verticalPadding * 2).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Center(
              child: TweenAnimationBuilder<double>(
                duration: duration,
                curve: Curves.easeOutBack,
                tween: Tween<double>(begin: 0, end: 1),
                builder: (context, value, child) {
                  final opacity = value.clamp(0.0, 1.0);
                  return Opacity(
                    opacity: opacity,
                    child: Transform.translate(
                      offset: Offset(0, (1 - opacity) * 18),
                      child: Transform.scale(
                        scale: 0.965 + value * 0.035,
                        child: child,
                      ),
                    ),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _startupFailureMaxWidth,
                  ),
                  child: _StartupFailurePanel(
                    title: title,
                    reason: reason,
                    suggestionsTitle: suggestionsTitle,
                    suggestions: suggestions,
                    compact: compact,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StartupFailurePanel extends StatelessWidget {
  const _StartupFailurePanel({
    required this.title,
    required this.reason,
    required this.suggestionsTitle,
    required this.suggestions,
    required this.compact,
  });

  final String title;
  final String reason;
  final String suggestionsTitle;
  final List<String> suggestions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final errorColor = colors.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: kOpenHandBorderRadius8,
              ),
              child: Icon(
                Icons.pan_tool_alt_rounded,
                color: colors.onPrimary,
                size: 21,
              ),
            ),
            kOpenHandHGap12,
            Expanded(
              child: Text(
                'OpenHand',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(
              Icons.notification_important_outlined,
              color: errorColor,
              semanticLabel: title,
            ),
          ],
        ),
        kOpenHandGap18,
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: kOpenHandBorderRadius8,
            side: BorderSide(color: colors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: errorColor,
                      child: const SizedBox(height: 4),
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: colors.primary,
                      child: const SizedBox(height: 4),
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: colors.tertiary,
                      child: const SizedBox(height: 4),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: EdgeInsets.all(compact ? 20 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: errorColor,
                      size: compact ? 34 : 40,
                    ),
                    kOpenHandGap14,
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    kOpenHandGap10,
                    Text(
                      reason,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.55,
                      ),
                    ),
                    if (suggestions.isNotEmpty) ...[
                      kOpenHandGap22,
                      Divider(color: colors.outlineVariant),
                      kOpenHandGap14,
                      Text(
                        suggestionsTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      kOpenHandGap10,
                      for (var index = 0; index < suggestions.length; index++)
                        _StartupSuggestion(
                          index: index + 1,
                          text: suggestions[index],
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StartupSuggestion extends StatelessWidget {
  const _StartupSuggestion({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: index.isEven
                  ? colors.tertiaryContainer
                  : colors.primaryContainer,
              borderRadius: kOpenHandBorderRadius8,
            ),
            child: Text(
              '$index',
              style: theme.textTheme.labelMedium?.copyWith(
                color: index.isEven
                    ? colors.onTertiaryContainer
                    : colors.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          kOpenHandHGap10,
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
