import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/hover_lift.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../model/ai_exposure_models.dart';
import '../services_controller.dart';

const double kServiceDialogItemActionGap = 8;
const BorderRadius kServiceInteractiveBorderRadius = BorderRadius.all(
  Radius.circular(kOpenHandRadius8),
);
const Color _kServiceColorHighValue = Color(0xffa855f7);
const Color _kServiceColorCyan = Color(0xff0891b2);

/// Matches the first decimal number (with optional sign and fractional part)
/// embedded in an arbitrary field value. Used by metric/record presentations
/// to extract sortable numerics from free-form text.
final RegExp _kNumericFieldRegex =
    RegExp(r'-?\d+(?:\.\d+)?');

/// Heuristic keywords indicating a healthy service status. Chinese terms are
/// matched as substrings (no word boundaries); English terms require word
/// boundaries to avoid false positives such as "enabled" inside "disabled".
final RegExp _kHealthyKeywordRegex = RegExp(
  r'正常|可用|就绪|完成|启用|满足|成功|已配置|\bhealthy\b|\bready\b|\bconnected\b|\benabled\b|\bavailable\b|\bconfigured\b|\bsuccess(?:ful|ed|ing)?\b|\bcomplete(?:d)?\b|\bonline\b|\bactive\b|\brunning\b',
  caseSensitive: false,
);

/// Heuristic keywords indicating an unhealthy service status. Shares the same
/// boundary conventions as [_kHealthyKeywordRegex]. The `fail` stem captures
/// "fail", "failed", "failing", "failure" and "fails".
final RegExp _kUnhealthyKeywordRegex = RegExp(
  r'异常|失败|阻塞|停用|未启用|未配置|不可用|\bunhealthy\b|\bunavailable\b|\bdisconnected\b|\bdisabled\b|\bunconfigured\b|\bfail(?:ure|ed|ing|s)?\b|\bblocked\b|\berror\b|\boffline\b|\btimeout\b|\bdown\b',
  caseSensitive: false,
);


enum ServiceDialogHeaderActionTone { neutral, primary }

double serviceProgressRatio({
  required num value,
  required num maximum,
  double minimumVisible = 0,
}) {
  final safeValue = value.toDouble();
  final safeMaximum = maximum.toDouble();
  if (!safeValue.isFinite ||
      !safeMaximum.isFinite ||
      safeValue <= 0 ||
      safeMaximum <= 0) {
    return 0;
  }
  final safeMinimum = minimumVisible.isFinite
      ? minimumVisible.clamp(0.0, 1.0).toDouble()
      : 0.0;
  return (safeValue / safeMaximum).clamp(safeMinimum, 1.0).toDouble();
}

double _finiteServiceValue(double value, {double fallback = 0}) {
  return value.isFinite ? value : fallback;
}

double _serviceProgressValue(double? value) {
  if (value == null) return 0;
  if (value.isNaN) return 0;
  if (value == double.infinity) return 1;
  if (value == double.negativeInfinity) return 0;
  return value.clamp(0.0, 1.0).toDouble();
}

double _serviceProgressHeight(double value) {
  if (!value.isFinite || value <= 0) return 1;
  return value;
}

class ServiceAnimatedProgressBar extends StatelessWidget {
  const ServiceAnimatedProgressBar({
    super.key,
    required this.value,
    this.minHeight = 4,
    this.color,
    this.backgroundColor,
  });

  final double? value;
  final double minHeight;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final height = _serviceProgressHeight(minHeight);
    final target = value == null ? null : _serviceProgressValue(value);
    if (target == null) {
      return LinearProgressIndicator(
        minHeight: height,
        color: color,
        backgroundColor: backgroundColor,
      );
    }
    return ServiceAnimatedValue(
      value: target,
      builder: (context, animatedValue) => LinearProgressIndicator(
        value: _serviceProgressValue(animatedValue),
        minHeight: height,
        color: color,
        backgroundColor: backgroundColor,
      ),
    );
  }
}

typedef ServiceAnimatedValueBuilder =
    Widget Function(BuildContext context, double value);

class ServiceAnimatedValue extends StatelessWidget {
  const ServiceAnimatedValue({
    super.key,
    required this.value,
    required this.builder,
    this.initialValue = 0,
  });

  final double value;
  final double initialValue;
  final ServiceAnimatedValueBuilder builder;

  @override
  Widget build(BuildContext context) {
    final safeValue = _finiteServiceValue(value);
    final safeInitialValue = _finiteServiceValue(initialValue);
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: safeInitialValue, end: safeValue),
      duration: motion.entranceDuration,
      curve: motion.curve.curve,
      builder: (context, animatedValue, _) => builder(context, animatedValue),
    );
  }
}

typedef ServiceAnimatedChartBuilder =
    Widget Function(BuildContext context, List<OpenHandChartSeries> series);

class ServiceAnimatedChart extends StatefulWidget {
  const ServiceAnimatedChart({
    super.key,
    required this.series,
    required this.builder,
  });

  final List<OpenHandChartSeries> series;
  final ServiceAnimatedChartBuilder builder;

  @override
  State<ServiceAnimatedChart> createState() => _ServiceAnimatedChartState();
}

class _ServiceAnimatedChartState extends State<ServiceAnimatedChart> {
  late List<OpenHandChartSeries> _from = _copySeries(widget.series);
  late List<OpenHandChartSeries> _target = _copySeries(widget.series);
  double _progress = 1;
  int _revision = 0;

  @override
  void didUpdateWidget(ServiceAnimatedChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _copySeries(widget.series);
    if (_sameSeries(_target, target)) return;
    _from = _interpolateSeries(_from, _target, _progress);
    _target = target;
    _progress = 0;
    _revision++;
  }

  @override
  Widget build(BuildContext context) {
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    if (_revision == 0 || motion.entranceDuration == Duration.zero) {
      _progress = 1;
      return widget.builder(context, _target);
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(_revision),
      tween: Tween<double>(begin: 0, end: 1),
      duration: motion.entranceDuration,
      curve: motion.curve.curve,
      builder: (context, progress, _) {
        _progress = progress;
        return widget.builder(
          context,
          _interpolateSeries(_from, _target, progress),
        );
      },
    );
  }

  static List<OpenHandChartSeries> _copySeries(
    List<OpenHandChartSeries> series,
  ) => series
      .map(
        (item) => OpenHandChartSeries(
          label: item.label,
          values: item.values
              .map((value) => value.isFinite && value > 0 ? value : 0.0)
              .toList(growable: false),
          color: item.color,
        ),
      )
      .toList(growable: false);

  static List<OpenHandChartSeries> _interpolateSeries(
    List<OpenHandChartSeries> from,
    List<OpenHandChartSeries> target,
    double progress,
  ) {
    final previous = <String, OpenHandChartSeries>{
      for (final item in from) item.label: item,
    };
    return target
        .map((item) {
          final oldValues = previous[item.label]?.values ?? const <double>[];
          final targetLength = item.values.length;
          return OpenHandChartSeries(
            label: item.label,
            values: List<double>.generate(targetLength, (index) {
              final start = _resample(oldValues, index, targetLength);
              return (start + (item.values[index] - start) * progress)
                  .clamp(0, double.infinity)
                  .toDouble();
            }, growable: false),
            color: item.color,
          );
        })
        .toList(growable: false);
  }

  static double _resample(List<double> values, int index, int targetLength) {
    if (values.isEmpty) return 0;
    if (values.length == 1 || targetLength <= 1) return values.last;
    final position = index * (values.length - 1) / (targetLength - 1);
    final lower = position.floor();
    final upper = position.ceil().clamp(0, values.length - 1).toInt();
    if (lower == upper) return values[lower];
    return values[lower] + (values[upper] - values[lower]) * (position - lower);
  }

  static bool _sameSeries(
    List<OpenHandChartSeries> left,
    List<OpenHandChartSeries> right,
  ) {
    if (left.length != right.length) return false;
    for (var seriesIndex = 0; seriesIndex < left.length; seriesIndex++) {
      final a = left[seriesIndex];
      final b = right[seriesIndex];
      if (a.label != b.label || a.color != b.color) return false;
      if (a.values.length != b.values.length) return false;
      for (var valueIndex = 0; valueIndex < a.values.length; valueIndex++) {
        if (a.values[valueIndex] != b.values[valueIndex]) return false;
      }
    }
    return true;
  }
}

class ServiceAnimatedDonutChart extends StatelessWidget {
  const ServiceAnimatedDonutChart({
    super.key,
    required this.values,
    required this.colors,
    required this.trackColor,
    this.child,
  });

  final List<int> values;
  final List<Color> colors;
  final Color trackColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ServiceAnimatedChart(
      series: <OpenHandChartSeries>[
        OpenHandChartSeries(
          label: 'distribution',
          values: values.map((value) => value.toDouble()).toList(growable: false),
          color: colors.firstOrNull ?? Colors.transparent,
        ),
      ],
      builder: (context, series) => RepaintBoundary(
        child: CustomPaint(
          painter: OpenHandDonutChartPainter(
            values: series.first.values,
            colors: colors,
            trackColor: trackColor,
          ),
          child: child,
        ),
      ),
    );
  }
}

String serviceProxyRouteText(
  ServicesController controller,
  OpenHandLocalizedTextResolver text, {
  bool includePoolCount = true,
}) => switch (controller.proxyRoute) {
  AiExposureProxyRoute.pool =>
    includePoolCount
        ? text(
            zh: '代理池 ${controller.proxyConfiguration.activeEndpoints.length} 节点',
            en: 'Proxy pool · ${controller.proxyConfiguration.activeEndpoints.length} nodes',
          )
        : text(zh: '代理池', en: 'Proxy pool'),
  AiExposureProxyRoute.system => text(zh: '系统代理', en: 'System proxy'),
  AiExposureProxyRoute.direct => 'DIRECT',
};

/// 扫描数据源展示名。除「手工目标」外都是产品专名，不随语言变化，因此
/// 只把它开放给调用方本地化；扫描弹窗与监控洞察两套 UI 共用同一份映射。
String aiExposureSourceDisplayName(
  AiExposureSource source, {
  String manualLabel = '手工目标',
}) => switch (source) {
  AiExposureSource.manual => manualLabel,
  AiExposureSource.github => 'GitHub',
  AiExposureSource.githubArtifact => 'GitHub Artifact',
  AiExposureSource.gitee => 'Gitee',
  AiExposureSource.gitcode => 'GitCode',
  AiExposureSource.fofa => 'FOFA',
  AiExposureSource.shodan => 'Shodan',
  AiExposureSource.nodeseek => 'NodeSeek',
  AiExposureSource.linuxDo => 'LINUX DO',
  AiExposureSource.v2ex => 'V2EX',
};

/// 扫描数据源图标，与 [aiExposureSourceDisplayName] 配套。
IconData aiExposureSourceIcon(AiExposureSource source) => switch (source) {
  AiExposureSource.manual => Icons.edit_location_alt_outlined,
  AiExposureSource.github => Icons.code_rounded,
  AiExposureSource.githubArtifact => Icons.inventory_2_outlined,
  AiExposureSource.gitee => Icons.code_rounded,
  AiExposureSource.gitcode => Icons.account_tree_outlined,
  AiExposureSource.fofa => Icons.public_rounded,
  AiExposureSource.shodan => Icons.radar_rounded,
  AiExposureSource.nodeseek => Icons.forum_outlined,
  AiExposureSource.linuxDo => Icons.terminal_rounded,
  AiExposureSource.v2ex => Icons.explore_outlined,
};

class ServiceDialogHeaderIconButton extends StatelessWidget {
  const ServiceDialogHeaderIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.tone = ServiceDialogHeaderActionTone.neutral,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final ServiceDialogHeaderActionTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isPrimary = tone == ServiceDialogHeaderActionTone.primary;
    final background = isPrimary
        ? colors.primary
        : colors.surfaceContainerHighest;
    final foreground = isPrimary ? colors.onPrimary : colors.onSurfaceVariant;
    final interactionColor = isPrimary ? colors.onPrimary : colors.primary;

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.surfaceContainerHighest.withValues(alpha: 0.48);
          }
          final opacity = states.contains(WidgetState.pressed)
              ? 0.14
              : states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
              ? 0.08
              : 0.0;
          return opacity == 0
              ? background
              : Color.alphaBlend(
                  interactionColor.withValues(alpha: opacity),
                  background,
                );
        }),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: 0.38)
              : foreground,
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: kOpenHandBorderRadius8,
          ),
        ),
      ),
    );
  }
}

class ServiceDialogCompactIconButton extends StatelessWidget {
  const ServiceDialogCompactIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.foregroundColor,
    this.size = 40,
  }) : assert(size > 0);

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final Color? foregroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = foregroundColor ?? colors.onSurfaceVariant;
    final buttonSize = Size.square(size);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(buttonSize),
        maximumSize: WidgetStatePropertyAll(buttonSize),
        fixedSize: WidgetStatePropertyAll(buttonSize),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: 0.38)
              : color,
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return Colors.transparent;
          if (states.contains(WidgetState.pressed)) {
            return color.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return color.withValues(alpha: 0.08);
          }
          return Colors.transparent;
        }),
        shape: const WidgetStatePropertyAll(CircleBorder()),
      ),
    );
  }
}

class ServiceDialogInteractionTheme extends StatelessWidget {
  const ServiceDialogInteractionTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const shape = RoundedRectangleBorder(
      borderRadius: kOpenHandBorderRadius8,
    );
    return Theme(
      data: theme.copyWith(
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        focusColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        cardTheme: theme.cardTheme.copyWith(
          margin: const EdgeInsets.all(0),
          color: colors.surfaceContainerHighest.withValues(alpha: 0.24),
          surfaceTintColor: Colors.transparent,
          shape: shape.copyWith(side: BorderSide(color: colors.outlineVariant)),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.28),
          border: const OutlineInputBorder(
            borderRadius: kOpenHandBorderRadius8,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: kOpenHandBorderRadius8,
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: kOpenHandBorderRadius8,
            borderSide: BorderSide(color: colors.primary, width: 1.4),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            shape: const WidgetStatePropertyAll(shape),
            side: WidgetStatePropertyAll(
              BorderSide(color: colors.outlineVariant),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest.withValues(alpha: 0.2);
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant;
            }),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
            shape: const WidgetStatePropertyAll(shape),
          ),
        ),
      ),
      child: child,
    );
  }
}

enum ServiceDetailPresentation {
  metric,
  composition,
  ranking,
  timeline,
  process,
  health,
  record,
  log,
}

class ServiceDetailField {
  const ServiceDetailField({required this.label, required this.value});

  final String label;
  final String value;
}

class ServiceDetailDatum {
  const ServiceDetailDatum({
    required this.label,
    required this.value,
    this.valueLabel,
    this.helper,
    this.color,
    this.highlighted = false,
  });

  final String label;
  final double value;
  final String? valueLabel;
  final String? helper;
  final Color? color;
  final bool highlighted;
}

String formatServiceDetailValue(Object? value) {
  if (value == null) return '--';
  if (value is String) return value.trim().isEmpty ? '--' : value;
  if (value is DateTime) return value.toLocal().toIso8601String();
  if (value is Map || value is Iterable) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } on JsonUnsupportedObjectError {
      return '$value';
    }
  }
  return '$value';
}

List<ServiceDetailField> serviceDetailFieldsFromMap(
  Map<String, Object?> values, {
  Map<String, String> labels = const <String, String>{},
}) => values.entries
    .map(
      (entry) => ServiceDetailField(
        label: labels[entry.key] ?? entry.key,
        value: formatServiceDetailValue(entry.value),
      ),
    )
    .toList(growable: false);

Future<void> showServiceDetailsDialog(
  BuildContext context, {
  required String title,
  required List<ServiceDetailField> fields,
  String? subtitle,
  IconData icon = Icons.manage_search_rounded,
  Color? accentColor,
  required ServiceDetailPresentation presentation,
  List<ServiceDetailDatum> data = const <ServiceDetailDatum>[],
}) => showAnimatedDialog<void>(
  context: context,
  builder: (dialogContext) => buildOpenHandResponsiveDialogShell(
    context: dialogContext,
    maxWidth: kOpenHandDialogWidthWide,
    maxHeight: kOpenHandDialogHeightTall,
    maxWidthFraction: 0.92,
    maxHeightFraction: 0.9,
    minAvailableWidth: 300,
    horizontalMargin: 24,
    verticalMargin: 48,
    expandToMax: true,
    child: ServiceDialogInteractionTheme(
      child: _ServiceDetailsDialog(
        title: title,
        subtitle: subtitle,
        icon: icon,
        accentColor: accentColor,
        presentation: presentation,
        data: data,
        fields: fields,
      ),
    ),
  ),
);

class ServiceInteractiveSurface extends StatefulWidget {
  const ServiceInteractiveSurface({
    super.key,
    required this.onTap,
    required this.child,
    this.tooltip,
    this.padding = const EdgeInsets.all(10),
    this.margin = EdgeInsets.zero,
    this.color,
    this.borderColor,
    this.showDetailsIcon = true,
    this.reserveDetailsIconSpace = false,
    this.detailsIconColor,
  });

  final VoidCallback? onTap;
  final Widget child;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final Color? borderColor;
  final bool showDetailsIcon;
  final bool reserveDetailsIconSpace;
  final Color? detailsIconColor;

  @override
  State<ServiceInteractiveSurface> createState() =>
      _ServiceInteractiveSurfaceState();
}

class _ServiceInteractiveSurfaceState extends State<ServiceInteractiveSurface> {
  bool _hovered = false;
  bool _focused = false;

  @override
  void didUpdateWidget(ServiceInteractiveSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onTap == null) {
      _hovered = false;
      _focused = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final interactive = widget.onTap != null;
    final showDetailsSlot =
        widget.showDetailsIcon &&
        (interactive || widget.reserveDetailsIconSpace);
    final detailsColor = widget.detailsIconColor ?? colors.primary;
    final emphasized = interactive && (_hovered || _focused);
    final motionDuration = openHandMotionDuration(
      context,
      kOpenHandMotion160,
    );
    final content = showDetailsSlot
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: widget.child),
              kOpenHandHGap10,
              Padding(
                // 预留位移动画的绘制空间，避免右侧按钮被圆角材质裁剪。
                padding: const EdgeInsets.only(right: 2),
                child: AnimatedOpacity(
                  opacity: interactive ? 1 : 0,
                  duration: motionDuration,
                  curve: Curves.easeOutCubic,
                  child: AnimatedContainer(
                    duration: motionDuration,
                    curve: Curves.easeOutCubic,
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    transform: Matrix4.translationValues(
                      emphasized ? 2 : 0,
                      0,
                      0,
                    ),
                    decoration: BoxDecoration(
                      color: detailsColor.withValues(
                        alpha: emphasized ? 0.16 : 0.08,
                      ),
                      borderRadius: kServiceInteractiveBorderRadius,
                      border: Border.all(
                        color: detailsColor.withValues(
                          alpha: emphasized ? 0.3 : 0.16,
                        ),
                      ),
                    ),
                    child: ExcludeSemantics(
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: detailsColor.withValues(
                          alpha: emphasized ? 1 : 0.82,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )
        : widget.child;
    if (!interactive) {
      return Padding(
        padding: widget.margin,
        child: Material(
          color: widget.color ?? Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: kServiceInteractiveBorderRadius,
            side: widget.borderColor == null
                ? BorderSide.none
                : BorderSide(color: widget.borderColor!),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: widget.padding, child: content),
        ),
      );
    }
    final label =
        widget.tooltip ??
        openHandLocalizedText(context, zh: '查看完整详情', en: 'View full details');
    final surface = Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: kServiceInteractiveBorderRadius,
        side: widget.borderColor == null
            ? BorderSide.none
            : BorderSide(color: widget.borderColor!),
      ),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        color: widget.color ?? Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          onHover: (value) {
            if (_hovered == value) return;
            setState(() => _hovered = value);
          },
          onFocusChange: (value) {
            if (_focused == value) return;
            setState(() => _focused = value);
          },
          borderRadius: kServiceInteractiveBorderRadius,
          child: Padding(padding: widget.padding, child: content),
        ),
      ),
    );
    return Padding(
      padding: widget.margin,
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          child: HoverLift(liftDistance: 1, child: surface),
        ),
      ),
    );
  }
}

class _ServiceDetailsDialog extends StatelessWidget {
  const _ServiceDetailsDialog({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.presentation,
    required this.data,
    required this.fields,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? accentColor;
  final ServiceDetailPresentation presentation;
  final List<ServiceDetailDatum> data;
  final List<ServiceDetailField> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    final tone = accentColor ?? colors.primary;
    final copyPayload = fields
        .map((field) => '${field.label}: ${field.value}')
        .join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: kServiceInteractiveBorderRadius,
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                child: Icon(icon, color: tone),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle?.trim().isNotEmpty == true) ...[
                      kOpenHandGap2,
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ServiceDialogHeaderIconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.outlineVariant),
        Expanded(
          child: fields.isEmpty
              ? Center(
                  child: Text(
                    text(zh: '暂无可用详情。', en: 'No details available.'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ServiceDetailDashboard(
                        title: title,
                        presentation: presentation,
                        data: data,
                        fields: fields,
                        accentColor: tone,
                      ),
                      kOpenHandGap14,
                      _ServiceDetailFacts(fields: fields, accentColor: tone),
                    ],
                  ),
                ),
        ),
        Divider(height: 1, color: colors.outlineVariant),
        buildOpenHandDialogActionsBar(
          actions: [
            OpenHandDialogActionButton.secondary(
              label: text(zh: '关闭', en: 'Close'),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            OpenHandDialogActionButton.primary(
              label: text(zh: '复制全部', en: 'Copy all'),
              onPressed: fields.isEmpty
                  ? null
                  : () => copyOpenHandTextToClipboard(
                      context: context,
                      text: copyPayload,
                      logTag: 'service_details',
                      logAction: '复制全部详情',
                    ),
            ),
          ],
          padding: const EdgeInsets.all(14),
        ),
      ],
    );
  }
}

class _ServiceDetailDashboard extends StatelessWidget {
  const _ServiceDetailDashboard({
    required this.title,
    required this.presentation,
    required this.data,
    required this.fields,
    required this.accentColor,
  });

  final String title;
  final ServiceDetailPresentation presentation;
  final List<ServiceDetailDatum> data;
  final List<ServiceDetailField> fields;
  final Color accentColor;

  List<ServiceDetailDatum> _resolveData(ColorScheme colors) {
    if (data.isNotEmpty) return data;
    if (presentation != ServiceDetailPresentation.metric &&
        presentation != ServiceDetailPresentation.composition &&
        presentation != ServiceDetailPresentation.ranking) {
      return const <ServiceDetailDatum>[];
    }
    final result = <ServiceDetailDatum>[];
    for (final field in fields) {
      final match = _kNumericFieldRegex.firstMatch(field.value);
      final value = match == null ? null : double.tryParse(match.group(0)!);
      if (value == null || !value.isFinite) continue;
      result.add(
        ServiceDetailDatum(
          label: field.label,
          value: value.abs(),
          valueLabel: field.value,
          color: _serviceDetailTone(result.length, colors, accentColor),
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final resolved = _resolveData(colors);
    final (sectionTitle, sectionIcon) = switch (presentation) {
      ServiceDetailPresentation.metric => ('实时指标剖面', Icons.query_stats_rounded),
      ServiceDetailPresentation.composition => (
        '构成与占比',
        Icons.donut_small_rounded,
      ),
      ServiceDetailPresentation.ranking => (
        '排名与相对规模',
        Icons.leaderboard_rounded,
      ),
      ServiceDetailPresentation.timeline => ('事件时间轴', Icons.timeline_rounded),
      ServiceDetailPresentation.process => ('执行路径', Icons.route_rounded),
      ServiceDetailPresentation.health => ('健康诊断', Icons.monitor_heart_rounded),
      ServiceDetailPresentation.record => ('记录完整度', Icons.dataset_rounded),
      ServiceDetailPresentation.log => ('事件上下文', Icons.terminal_rounded),
    };
    final child = switch (presentation) {
      ServiceDetailPresentation.metric => _metric(context, resolved),
      ServiceDetailPresentation.composition => _composition(context, resolved),
      ServiceDetailPresentation.ranking => _ranking(context, resolved),
      ServiceDetailPresentation.timeline => _timeline(context, resolved, false),
      ServiceDetailPresentation.process => _timeline(context, resolved, true),
      ServiceDetailPresentation.health => _health(context, resolved),
      ServiceDetailPresentation.record => _record(context),
      ServiceDetailPresentation.log => _log(context),
    };
    return _ServiceDetailSection(
      title: sectionTitle,
      icon: sectionIcon,
      accentColor: accentColor,
      child: child,
    );
  }

  Widget _metric(BuildContext context, List<ServiceDetailDatum> values) {
    final colors = Theme.of(context).colorScheme;
    final primary = values.firstOrNull;
    final displayValue =
        primary?.valueLabel ??
        fields
            .where((field) => field.label.contains('值'))
            .map((field) => field.value)
            .firstOrNull ??
        '--';
    final donut = _donut(
      context,
      values,
      centerValue: displayValue,
      centerLabel: title,
    );
    final bars = _bars(context, values, showRank: false);
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 620
          ? Column(children: [donut, kOpenHandGap12, bars])
          : Row(
              children: [
                donut,
                kOpenHandHGap20,
                Expanded(
                  child: values.isEmpty
                      ? Text(
                          '当前指标暂未提供可计算样本。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        )
                      : bars,
                ),
              ],
            ),
    );
  }

  Widget _composition(BuildContext context, List<ServiceDetailDatum> values) {
    if (values.isEmpty) return _empty(context, '暂无可计算的构成数据。');
    final total = values.fold<double>(0, (sum, item) => sum + item.value);
    final donut = _donut(
      context,
      values,
      centerValue: formatCompactCount(total),
      centerLabel: '总量',
    );
    final bars = _bars(context, values, showRank: false, total: total);
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 620
          ? Column(children: [donut, kOpenHandGap12, bars])
          : Row(
              children: [
                donut,
                kOpenHandHGap20,
                Expanded(child: bars),
              ],
            ),
    );
  }

  Widget _ranking(BuildContext context, List<ServiceDetailDatum> values) {
    if (values.isEmpty) return _empty(context, '暂无可比较的排名数据。');
    final sorted = [...values]
      ..sort((left, right) => right.value.compareTo(left.value));
    return _bars(context, sorted, showRank: true);
  }

  Widget _timeline(
    BuildContext context,
    List<ServiceDetailDatum> values,
    bool process,
  ) {
    final colors = Theme.of(context).colorScheme;
    final steps = values.isNotEmpty
        ? values
        : fields
              .where(
                (field) => field.value.trim().isNotEmpty && field.value != '--',
              )
              .map(
                (field) => ServiceDetailDatum(
                  label: field.label,
                  value: 1,
                  valueLabel: field.value,
                ),
              )
              .toList(growable: false);
    if (steps.isEmpty) return _empty(context, '暂无轨迹信息。');
    final visible = steps.take(8).toList(growable: false);
    return Column(
      children: visible.indexed
          .map((entry) {
            final item = entry.$2;
            final tone =
                item.color ?? _serviceDetailTone(entry.$1, colors, accentColor);
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 28,
                    child: Column(
                      children: [
                        Container(
                          width: process ? 20 : 12,
                          height: process ? 20 : 12,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tone,
                            shape: BoxShape.circle,
                          ),
                          child: process
                              ? Text(
                                  '${entry.$1 + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                              : null,
                        ),
                        if (entry.$1 < visible.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: tone.withValues(alpha: 0.28),
                            ),
                          ),
                      ],
                    ),
                  ),
                  kOpenHandHGap9,
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (item.valueLabel?.trim().isNotEmpty == true) ...[
                            kOpenHandGap3,
                            Text(
                              item.valueLabel!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                            ),
                          ],
                          if (item.helper?.trim().isNotEmpty == true) ...[
                            kOpenHandGap3,
                            Text(
                              item.helper!,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _health(BuildContext context, List<ServiceDetailDatum> values) {
    final positive = fields.where((field) {
      return _kHealthyKeywordRegex.hasMatch(field.value) &&
          !_kUnhealthyKeywordRegex.hasMatch(field.value);
    }).length;
    final negative = fields
        .where((field) => _kUnhealthyKeywordRegex.hasMatch(field.value))
        .length;
    final measured = positive + negative;
    final finiteValues = values.where((item) => item.value.isFinite);
    final finiteValueCount = finiteValues.length;
    final rawScore = finiteValueCount > 0
        ? finiteValues.fold<double>(0, (sum, item) => sum + item.value) /
              finiteValueCount
        : measured == 0
        ? 0.5
        : positive / measured;
    final normalizedScore = rawScore.isFinite ? rawScore : 0.5;
    final score = normalizedScore > 1
        ? (normalizedScore / 100).clamp(0.0, 1.0).toDouble()
        : normalizedScore.clamp(0.0, 1.0).toDouble();
    final tone = score >= 0.8
        ? OpenHandStatusColors.success
        : score >= 0.5
        ? OpenHandStatusColors.warning
        : OpenHandStatusColors.error;
    final donut = _donut(
      context,
      [
        ServiceDetailDatum(label: '健康', value: score * 100, color: tone),
        ServiceDetailDatum(
          label: '风险',
          value: (1 - score) * 100,
          color: Colors.transparent,
        ),
      ],
      centerValue: '${(score * 100).round()}%',
      centerLabel: score >= 0.8
          ? '健康'
          : score >= 0.5
          ? '需关注'
          : '异常',
    );
    final signals = Column(
      children: [
        _healthRow(
          context,
          Icons.check_circle_outline_rounded,
          '正常信号',
          '$positive',
          OpenHandStatusColors.success,
        ),
        kOpenHandGap10,
        _healthRow(
          context,
          Icons.warning_amber_rounded,
          '风险信号',
          '$negative',
          OpenHandStatusColors.warning,
        ),
        kOpenHandGap10,
        _healthRow(
          context,
          Icons.fact_check_outlined,
          '诊断维度',
          '${fields.length}',
          accentColor,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 620
          ? Column(children: [donut, kOpenHandGap12, signals])
          : Row(
              children: [
                donut,
                kOpenHandHGap20,
                Expanded(child: signals),
              ],
            ),
    );
  }

  Widget _record(BuildContext context) {
    final complete = fields.where((field) {
      final value = field.value.trim();
      return value.isNotEmpty && value != '--' && value.toLowerCase() != 'null';
    }).length;
    final numeric = fields
        .where((field) => _kNumericFieldRegex.hasMatch(field.value))
        .length;
    final longValues = fields
        .where((field) => field.value.length > 48 || field.value.contains('\n'))
        .length;
    final ratio = fields.isEmpty ? 0.0 : complete / fields.length;
    final stats = <Widget>[
      _recordStat(
        context,
        '字段',
        '${fields.length}',
        Icons.view_agenda_outlined,
        accentColor,
      ),
      _recordStat(
        context,
        '有效',
        '$complete',
        Icons.task_alt_rounded,
        OpenHandStatusColors.success,
      ),
      _recordStat(
        context,
        '数值',
        '$numeric',
        Icons.numbers_rounded,
        OpenHandStatusColors.info,
      ),
      _recordStat(
        context,
        '长文本',
        '$longValues',
        Icons.notes_rounded,
        OpenHandStatusColors.warning,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 10.0;
            final columns = constraints.maxWidth >= 720
                ? 4
                : constraints.maxWidth >= 420
                ? 2
                : 1;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final stat in stats) SizedBox(width: width, child: stat),
              ],
            );
          },
        ),
        kOpenHandGap14,
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: kOpenHandPillBorderRadius,
                child: ServiceAnimatedProgressBar(
                  minHeight: 10,
                  value: ratio,
                  color: accentColor,
                  backgroundColor: accentColor.withValues(alpha: 0.11),
                ),
              ),
            ),
            kOpenHandHGap10,
            Text(
              '完整度 ${(ratio * 100).round()}%',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _log(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final level =
        fields
            .where((field) => field.label.contains('级别'))
            .map((field) => field.value)
            .firstOrNull ??
        'INFO';
    final message =
        fields
            .where((field) => field.label.contains('消息'))
            .map((field) => field.value)
            .firstOrNull ??
        fields.last.value;
    final tone = level.toLowerCase().contains('error') || level.contains('错误')
        ? OpenHandStatusColors.error
        : level.toLowerCase().contains('warn') || level.contains('警告')
        ? OpenHandStatusColors.warning
        : accentColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.11),
                borderRadius: kServiceInteractiveBorderRadius,
                border: Border.all(color: tone.withValues(alpha: 0.28)),
              ),
              child: Text(
                level.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            kOpenHandHGap10,
            Expanded(
              child: Text(
                fields
                        .where((field) => field.label.contains('时间'))
                        .map((field) => field.value)
                        .firstOrNull ??
                    '实时事件',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        kOpenHandGap12,
        Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            borderRadius: kServiceInteractiveBorderRadius,
            border: Border.all(color: tone.withValues(alpha: 0.24)),
          ),
          child: SelectableText(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }

  Widget _donut(
    BuildContext context,
    List<ServiceDetailDatum> values, {
    required String centerValue,
    required String centerLabel,
  }) {
    final colors = Theme.of(context).colorScheme;
    final chartValues = values.isEmpty
        ? const <int>[0]
        : values
              .map(
                (item) =>
                    _finiteServiceValue(item.value).round().clamp(0, 1 << 30),
              )
              .toList(growable: false);
    return SizedBox(
      width: 164,
      height: 164,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: 146,
            child: ServiceAnimatedDonutChart(
              values: chartValues,
              colors: values.indexed
                  .map(
                    (entry) =>
                        entry.$2.color ??
                        _serviceDetailTone(entry.$1, colors, accentColor),
                  )
                  .toList(growable: false),
              trackColor: colors.surfaceContainerHighest,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  centerValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                kOpenHandGap3,
                Text(
                  centerLabel,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bars(
    BuildContext context,
    List<ServiceDetailDatum> values, {
    required bool showRank,
    double? total,
  }) {
    if (values.isEmpty) return _empty(context, '暂无数值样本。');
    final colors = Theme.of(context).colorScheme;
    final requestedMaximum = total;
    final maximum =
        requestedMaximum != null &&
            requestedMaximum.isFinite &&
            requestedMaximum > 0
        ? requestedMaximum
        : values.fold<double>(0, (max, item) {
            final value = item.value;
            return value.isFinite && value > max ? value : max;
          });
    final visible = values.take(8).toList(growable: false);
    return Column(
      children: visible.indexed
          .map((entry) {
            final item = entry.$2;
            final tone =
                item.color ?? _serviceDetailTone(entry.$1, colors, accentColor);
            final ratio = serviceProgressRatio(
              value: item.value,
              maximum: maximum,
            );
            final valueLabel = total == null
                ? item.valueLabel ?? formatCompactCount(item.value)
                : '${(ratio * 100).toStringAsFixed(1)}%';
            return Padding(
              padding: EdgeInsets.only(
                bottom: entry.$1 == visible.length - 1 ? 0 : 11,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (showRank)
                        SizedBox(
                          width: 26,
                          child: Text(
                            '${entry.$1 + 1}',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: tone,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: tone,
                          shape: BoxShape.circle,
                        ),
                      ),
                      kOpenHandHGap7,
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                fontWeight: item.highlighted
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                              ),
                        ),
                      ),
                      kOpenHandHGap8,
                      Text(
                        valueLabel,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                  kOpenHandGap6,
                  ClipRRect(
                    borderRadius: kOpenHandPillBorderRadius,
                    child: ServiceAnimatedProgressBar(
                      minHeight: item.highlighted ? 11 : 8,
                      value: ratio,
                      color: tone,
                      backgroundColor: tone.withValues(alpha: 0.11),
                    ),
                  ),
                  if (item.helper?.trim().isNotEmpty == true) ...[
                    kOpenHandGap4,
                    Text(
                      item.helper!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _healthRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color color,
  ) => Row(
    children: [
      Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: kServiceInteractiveBorderRadius,
        ),
        child: Icon(icon, size: 19, color: color),
      ),
      kOpenHandHGap10,
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
      Text(
        value,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );

  Widget _recordStat(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) => Container(
    constraints: const BoxConstraints(minWidth: 130),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: kServiceInteractiveBorderRadius,
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        kOpenHandHGap8,
        Text('$label  ', style: Theme.of(context).textTheme.labelMedium),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _empty(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _ServiceDetailSection extends StatelessWidget {
  const _ServiceDetailSection({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: kServiceInteractiveBorderRadius,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: accentColor),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap14,
          child,
        ],
      ),
    );
  }
}

class _ServiceDetailFacts extends StatelessWidget {
  const _ServiceDetailFacts({required this.fields, required this.accentColor});

  final List<ServiceDetailField> fields;
  final Color accentColor;

  @override
  Widget build(BuildContext context) => _ServiceDetailSection(
    title: openHandLocalizedText(
      context,
      zh: '完整信息',
      en: 'Complete information',
    ),
    icon: Icons.subject_rounded,
    accentColor: accentColor,
    child: Column(
      children: fields.indexed
          .map(
            (entry) => _ServiceDetailFieldRow(
              field: entry.$2,
              showDivider: entry.$1 > 0,
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _ServiceDetailFieldRow extends StatelessWidget {
  const _ServiceDetailFieldRow({
    required this.field,
    required this.showDivider,
  });

  final ServiceDetailField field;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        if (showDivider)
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.7),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 118,
                child: Text(
                  field.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              kOpenHandHGap12,
              Expanded(
                child: SelectableText(
                  field.value,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ),
              kOpenHandHGap4,
              ServiceDialogCompactIconButton(
                tooltip: openHandLocalizedText(
                  context,
                  zh: '复制此字段',
                  en: 'Copy field',
                ),
                size: 32,
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () => copyOpenHandTextToClipboard(
                  context: context,
                  text: field.value,
                  logTag: 'service_details',
                  logAction: '复制详情字段',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Color _serviceDetailTone(int index, ColorScheme colors, Color accentColor) =>
    <Color>[
      accentColor,
      OpenHandStatusColors.success,
      OpenHandStatusColors.info,
      OpenHandStatusColors.warning,
      colors.tertiary,
      _kServiceColorHighValue,
      _kServiceColorCyan,
      OpenHandStatusColors.error,
    ][index % 8];

class ServiceFilterChip extends StatelessWidget {
  const ServiceFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.accentColor,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? icon;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final chipTheme = ChipTheme.of(context);
    final backgroundColor =
        chipTheme.backgroundColor ?? colors.surfaceContainerHigh;
    final selectedColor = accentColor == null
        ? chipTheme.selectedColor ?? colors.primaryContainer
        : Color.alphaBlend(
            accentColor!.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.20 : 0.12,
            ),
            colors.surfaceContainerHigh,
          );
    return FilterChip(
      selected: selected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            IconTheme.merge(data: const IconThemeData(size: 17), child: icon!),
            kOpenHandHGap7,
          ],
          label,
        ],
      ),
      onSelected: onSelected,
      showCheckmark: icon == null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      pressElevation: 0,
      shadowColor: Colors.transparent,
      selectedShadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      side: accentColor == null
          ? null
          : BorderSide(
              color: accentColor!.withValues(alpha: selected ? 0.48 : 0.20),
            ),
      labelStyle: accentColor == null
          ? null
          : TextStyle(
              color: selected ? colors.onSurface : colors.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
      color: WidgetStateProperty.resolveWith((states) {
        final base = states.contains(WidgetState.selected)
            ? selectedColor
            : backgroundColor;
        final alpha = states.contains(WidgetState.pressed)
            ? 0.10
            : states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
            ? 0.05
            : 0.0;
        return alpha == 0
            ? base
            : Color.alphaBlend(colors.primary.withValues(alpha: alpha), base);
      }),
    );
  }
}

class ServiceDialogIconActions extends StatelessWidget {
  const ServiceDialogIconActions({
    super.key,
    required this.children,
    this.spacing = kServiceDialogItemActionGap,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) SizedBox(width: spacing),
        children[index],
      ],
    ],
  );
}
