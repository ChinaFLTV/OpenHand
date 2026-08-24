import 'package:flutter/material.dart';

import '../../app/theme/openhand_status_colors.dart';
import 'oh_pill.dart';
import 'openhand_spacing.dart';

/// 与设置页「请求追踪」表行同高，供其它列表复用双行 Token / 耗时。
const double kOpenHandTableMetricRowHeight = 74;
const double kOpenHandTableMetricBodyMaxHeight = 444;
const String kOpenHandTableMetricEmpty = '—';
const String kOpenHandTableMetricTokenInputMarker = '↑';
const String kOpenHandTableMetricTokenOutputMarker = '↓';
const String kOpenHandTableMetricTokenCacheMarker = '↻';
const double kOpenHandTableMetricStatusDotSize = 7;
const double kOpenHandTableMetricStatusFillOpacity = 0.12;
const double kOpenHandTableMetricStatusBorderOpacity = 0.28;
const EdgeInsets kOpenHandTableMetricStatusPadding = EdgeInsets.symmetric(
  horizontal: 10,
  vertical: 5,
);

enum OpenHandTableMetricColumnKind { none, token, cost, duration, status }

OpenHandTableMetricColumnKind classifyOpenHandTableMetricHeader(String header) {
  final value = header.trim().toLowerCase();
  if (value == 'token') return OpenHandTableMetricColumnKind.token;
  if (value.contains('成本') || value == 'cost') {
    return OpenHandTableMetricColumnKind.cost;
  }
  if (value.contains('耗时') ||
      value.contains('latency') ||
      value == 'duration' ||
      value == 'avg' ||
      value == 'p95') {
    return OpenHandTableMetricColumnKind.duration;
  }
  if (value.contains('状态') || value == 'status') {
    return OpenHandTableMetricColumnKind.status;
  }
  return OpenHandTableMetricColumnKind.none;
}

bool openHandIsTableMetricHeader(String header) =>
    classifyOpenHandTableMetricHeader(header) !=
    OpenHandTableMetricColumnKind.none;

bool openHandTableMetricHeaderCenters(String header) =>
    classifyOpenHandTableMetricHeader(header) ==
    OpenHandTableMetricColumnKind.status;

Color openHandTableMetricRequestStatusColor(ColorScheme colors, String status) {
  return switch (status.trim().toLowerCase()) {
    'success' || 'ok' || 'healthy' => OpenHandStatusColors.success,
    'timeout' || 'timed_out' => OpenHandStatusColors.warning,
    'cancelled' || 'canceled' || 'idle' => colors.onSurfaceVariant,
    'failed' ||
    'fail' ||
    'error' ||
    'denied' ||
    'rejected' ||
    'outage' => OpenHandStatusColors.error,
    _ => colors.onSurfaceVariant,
  };
}

String openHandTableMetricInteger(int value) {
  final text = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 == 0) buffer.write(',');
    buffer.write(text[index]);
  }
  return buffer.toString();
}

String openHandTableMetricCompactNumber(int value, {int decimals = 1}) {
  final abs = value.abs();
  if (abs >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(decimals)}亿';
  }
  if (abs >= 10000) {
    return '${(value / 10000).toStringAsFixed(decimals)}万';
  }
  if (abs >= 1000) {
    return '${(value / 1000).toStringAsFixed(decimals)}k';
  }
  return '$value';
}

String openHandTableMetricMoney(double value) {
  if (!value.isFinite) return kOpenHandTableMetricEmpty;
  if (value == 0) return r'$0.0000';
  if (value.abs() < 0.0001) return r'<$0.0001';
  return '\$${value.toStringAsFixed(value.abs() < 1 ? 4 : 2)}';
}

String openHandTableMetricDuration(num milliseconds) {
  if (!milliseconds.isFinite) return kOpenHandTableMetricEmpty;
  final value = milliseconds.toDouble();
  if (value < 0) return kOpenHandTableMetricEmpty;
  if (value < 1000) return '${value.round()}ms';
  if (value < 60000) return '${(value / 1000).toStringAsFixed(1)}s';
  return '${(value / 60000).toStringAsFixed(1)}m';
}

/// 主数字 + ↑输入 ↓输出 ↻缓存，对齐请求追踪 Token 列。
class OpenHandTokenMetricCell extends StatelessWidget {
  const OpenHandTokenMetricCell({
    super.key,
    required this.total,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cacheReadTokens = 0,
    this.estimated = false,
    this.showBreakdown = true,
    this.alignEnd = true,
  });

  final int total;
  final int promptTokens;
  final int completionTokens;
  final int cacheReadTokens;
  final bool estimated;
  final bool showBreakdown;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final primaryStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final secondaryStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget part(String marker, int amount, Color accent) {
      final active = amount > 0;
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$marker ',
              style: secondaryStyle?.copyWith(
                color: active ? accent : colors.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: openHandTableMetricCompactNumber(amount),
              style: secondaryStyle,
            ),
          ],
        ),
        maxLines: 1,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          '${openHandTableMetricInteger(total)}${estimated ? ' ≈' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: primaryStyle,
        ),
        if (showBreakdown) ...[
          kOpenHandGap3,
          Wrap(
            spacing: 8,
            runSpacing: 2,
            alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
            children: [
              part(
                kOpenHandTableMetricTokenInputMarker,
                promptTokens,
                colors.primary,
              ),
              part(
                kOpenHandTableMetricTokenOutputMarker,
                completionTokens,
                colors.tertiary,
              ),
              if (cacheReadTokens > 0)
                part(
                  kOpenHandTableMetricTokenCacheMarker,
                  cacheReadTokens,
                  OpenHandStatusColors.success,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 有值加粗金额，无值灰色破折号。
class OpenHandCostMetricCell extends StatelessWidget {
  const OpenHandCostMetricCell({
    super.key,
    this.usd,
    this.uncertain = false,
    this.alignEnd = true,
  });

  final double? usd;
  final bool uncertain;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = usd == null || !usd!.isFinite;
    final label = empty
        ? kOpenHandTableMetricEmpty
        : '${uncertain ? '≥' : ''}${openHandTableMetricMoney(usd!)}';
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: empty ? theme.colorScheme.onSurfaceVariant : null,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// 主耗时 + 可选「首字」副行。
class OpenHandDurationMetricCell extends StatelessWidget {
  const OpenHandDurationMetricCell({
    super.key,
    this.durationMs,
    this.firstTokenMs,
    this.firstTokenLabel,
    this.alignEnd = true,
  });

  final num? durationMs;
  final num? firstTokenMs;
  final String? firstTokenLabel;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final empty =
        durationMs == null || !durationMs!.isFinite || durationMs! < 0;
    final primary = empty
        ? kOpenHandTableMetricEmpty
        : openHandTableMetricDuration(durationMs!);
    final firstLabel = firstTokenLabel;
    final firstValue = firstTokenMs == null || !firstTokenMs!.isFinite
        ? kOpenHandTableMetricEmpty
        : openHandTableMetricDuration(firstTokenMs!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: empty ? colors.onSurfaceVariant : null,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (firstLabel != null && firstLabel.isNotEmpty) ...[
          kOpenHandGap3,
          Text(
            '$firstLabel $firstValue',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

/// 圆点 + 胶囊，对齐请求追踪状态列。
class OpenHandTableStatusBadge extends StatelessWidget {
  const OpenHandTableStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.tooltip,
  });

  final String label;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: kOpenHandTableMetricStatusPadding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: kOpenHandTableMetricStatusFillOpacity),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(
          color: color.withValues(
            alpha: kOpenHandTableMetricStatusBorderOpacity,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: kOpenHandTableMetricStatusDotSize,
            height: kOpenHandTableMetricStatusDotSize,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          kOpenHandHGap6,
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    final message = tooltip?.trim();
    if (message == null || message.isEmpty) return badge;
    return Tooltip(message: message, child: badge);
  }
}

/// 主标题 + 灰色副行，对齐请求追踪来源列。
class OpenHandTableStackedCell extends StatelessWidget {
  const OpenHandTableStackedCell({
    super.key,
    required this.primary,
    this.secondary = '',
    this.alignEnd = false,
  });

  final String primary;
  final String secondary;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayPrimary = primary.trim().isEmpty
        ? kOpenHandTableMetricEmpty
        : primary.trim();
    final displaySecondary = secondary.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          displayPrimary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (displaySecondary.isNotEmpty) ...[
          kOpenHandGap3,
          Text(
            displaySecondary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
