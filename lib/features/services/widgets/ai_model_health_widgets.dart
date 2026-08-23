import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../ai_model_health_controller.dart';
import '../model/ai_model_health.dart';

// 输入框主题的 60px 边框加辅助说明后的统一表单高度。
const double _aiHealthControlHeight = 84;

class AiModelHealthSettingsPanel extends StatefulWidget {
  const AiModelHealthSettingsPanel({super.key, this.showRequestMode = false});

  final bool showRequestMode;

  @override
  State<AiModelHealthSettingsPanel> createState() =>
      _AiModelHealthSettingsPanelState();
}

class _AiModelHealthSettingsPanelState
    extends State<AiModelHealthSettingsPanel> {
  late final TextEditingController _intervalController;
  late final FocusNode _intervalFocusNode;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController();
    _intervalFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _intervalFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AiModelHealthController>();
    final settings = controller.settings;
    final usesSystemProxy =
        settings.useSystemProxy ||
        settings.requestMode == AiModelHealthRequestMode.systemProxy;
    if (!_intervalFocusNode.hasFocus &&
        _intervalController.text != '${settings.intervalMinutes}') {
      _intervalController.text = '${settings.intervalMinutes}';
    }
    final text = openHandTextResolver(context);
    final theme = Theme.of(context);
    final settingTitleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w800,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            text(zh: '定时健康巡检', en: 'Scheduled health checks'),
            style: settingTitleStyle,
          ),
          subtitle: Text(
            text(
              zh: '按固定间隔检查所有提供商的所有模型，并保存每次结果。',
              en: 'Check every configured model on a fixed interval and retain each result.',
            ),
          ),
          value: settings.enabled,
          onChanged: (value) => controller.updateSettings(enabled: value),
          thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
            return states.contains(WidgetState.selected)
                ? const Icon(Icons.check_rounded, size: 16)
                : const Icon(Icons.close_rounded, size: 16);
          }),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: _aiHealthControlHeight,
                child: TextField(
                  controller: _intervalController,
                  focusNode: _intervalFocusNode,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: text(zh: '巡检间隔（分钟）', en: 'Interval (minutes)'),
                    helperText: text(
                      zh: '范围 1-1440 分钟。',
                      en: 'Range: 1-1440 minutes.',
                    ),
                  ),
                  onSubmitted: (value) {
                    final minutes = int.tryParse(value);
                    if (minutes != null) {
                      controller.updateSettings(intervalMinutes: minutes);
                    }
                  },
                ),
              ),
            ),
            kOpenHandHGap12,
            SizedBox(
              width: 150,
              height: _aiHealthControlHeight,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: text(zh: '测试线程', en: 'Test threads'),
                ),
                child: DropdownButtonHideUnderline(
                  child: AnimatedDropdownButton<int>(
                    isExpanded: true,
                    value: settings.concurrency,
                    items: [
                      for (final value in const <int>[1, 2, 4, 8, 16, 32])
                        DropdownMenuItem(value: value, child: Text('$value')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        controller.updateSettings(concurrency: value);
                      }
                    },
                  ),
                ),
              ),
            ),
            kOpenHandHGap12,
            SizedBox(
              height: _aiHealthControlHeight,
              child: FilledButton.tonalIcon(
                onPressed: controller.checking ? null : controller.checkAll,
                icon: controller.checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering_rounded),
                label: Text(text(zh: '立即巡检', en: 'Run now')),
              ),
            ),
          ],
        ),
        if (!widget.showRequestMode)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              text(zh: '使用系统代理', en: 'Use system proxy'),
              style: settingTitleStyle,
            ),
            subtitle: Text(
              text(
                zh: '健康巡检请求通过应用当前系统代理设置发出。',
                en: 'Send health-check requests through the app system proxy.',
              ),
            ),
            value: usesSystemProxy,
            onChanged: (value) => controller.updateSettings(
              useSystemProxy: value,
              requestMode: value
                  ? AiModelHealthRequestMode.systemProxy
                  : AiModelHealthRequestMode.direct,
            ),
            thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
              return states.contains(WidgetState.selected)
                  ? const Icon(Icons.check_rounded, size: 16)
                  : const Icon(Icons.close_rounded, size: 16);
            }),
          ),
        if (widget.showRequestMode) ...[
          kOpenHandGap8,
          SizedBox(
            height: _aiHealthControlHeight,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: text(zh: '巡检请求模式', en: 'Health-check request mode'),
              ),
              child: DropdownButtonHideUnderline(
                child: AnimatedDropdownButton<AiModelHealthRequestMode>(
                  isExpanded: true,
                  value: settings.requestMode,
                  items: [
                    for (final mode in AiModelHealthRequestMode.values)
                      DropdownMenuItem(
                        value: mode,
                        child: Text(_modeLabel(context, mode)),
                      ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) {
                      controller.updateSettings(requestMode: mode);
                    }
                  },
                ),
              ),
            ),
          ),
        ],
        if (controller.records.isNotEmpty) ...[
          kOpenHandGap8,
          Text(
            text(
              zh: '已保存 ${controller.records.length} 条巡检记录',
              en: '${controller.records.length} retained health records',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  String _modeLabel(BuildContext context, AiModelHealthRequestMode mode) {
    return switch (mode) {
      AiModelHealthRequestMode.direct => openHandLocalizedText(
        context,
        zh: '直连',
        en: 'Direct',
      ),
      AiModelHealthRequestMode.systemProxy => openHandLocalizedText(
        context,
        zh: '系统代理',
        en: 'System proxy',
      ),
      AiModelHealthRequestMode.proxyPool => openHandLocalizedText(
        context,
        zh: '代理池代理',
        en: 'Proxy pool',
      ),
    };
  }
}

class AiModelHealthIndicator extends StatelessWidget {
  const AiModelHealthIndicator({
    super.key,
    required this.provider,
    required this.modelId,
    this.barCount = 24,
    this.compact = false,
  });

  final AiModelConfig provider;
  final String modelId;
  final int barCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AiModelHealthController>();
    final records = controller.recordsFor(provider.id, modelId);
    final bars = List<AiModelHealthRecord?>.filled(barCount, null);
    for (var index = 0; index < records.length && index < barCount; index++) {
      bars[barCount - index - 1] = records[index];
    }
    final colors = Theme.of(context).colorScheme;
    final indicator = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final record in bars)
          _HealthBar(
            record: record,
            emptyColor: colors.outlineVariant.withValues(alpha: 0.45),
            compact: compact,
          ),
      ],
    );
    if (records.isNotEmpty) return indicator;
    return Tooltip(
      message: openHandLocalizedText(
        context,
        zh: '暂无巡检记录',
        en: 'No health records yet',
      ),
      child: indicator,
    );
  }
}

class _HealthBar extends StatelessWidget {
  const _HealthBar({
    required this.record,
    required this.emptyColor,
    required this.compact,
  });

  final AiModelHealthRecord? record;
  final Color emptyColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = record == null
        ? emptyColor
        : record!.success
        ? const Color(0xff32c887)
        : colorScheme.error;
    final height = compact ? 16.0 : 22.0;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: openHandMotionDuration(context, kOpenHandMotion260),
      curve: kOpenHandEmphasizedTransitionCurve,
      builder: (context, animatedColor, _) {
        final visibleColor = animatedColor ?? color;
        final bar = DecoratedBox(
          decoration: BoxDecoration(
            color: visibleColor,
            borderRadius: BorderRadius.circular(2),
          ),
          child: SizedBox(width: compact ? 3 : 4, height: height),
        );
        final content = record == null
            ? bar
            : OpenHandChartTooltipTrigger(
                tooltip: _healthRecordTooltip(context, record!),
                accent: visibleColor,
                child: bar,
              );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.2),
          child: content,
        );
      },
    );
  }

  OpenHandChartTooltip _healthRecordTooltip(
    BuildContext context,
    AiModelHealthRecord record,
  ) {
    final text = openHandTextResolver(context);
    final statusColor = record.success
        ? OpenHandStatusColors.success
        : OpenHandStatusColors.error;
    final modeLabel = switch (record.requestMode) {
      AiModelHealthRequestMode.direct => text(zh: '直连', en: 'Direct'),
      AiModelHealthRequestMode.systemProxy => text(
        zh: '系统代理',
        en: 'System proxy',
      ),
      AiModelHealthRequestMode.proxyPool => text(zh: '代理池代理', en: 'Proxy pool'),
    };
    final metadata = record.metadata;
    final probeType = '${metadata['probe_type'] ?? ''}'.trim();
    final requestMethod = '${metadata['request_method'] ?? ''}'.trim();
    final requestUrl = _safeHealthUrl('${metadata['request_url'] ?? ''}');
    final endpoint = record.host.isEmpty
        ? text(zh: '未解析', en: 'Unavailable')
        : '${record.host}${record.port == null ? '' : ':${record.port}'}';
    return OpenHandChartTooltip(
      title: record.modelId,
      subtitle:
          '${record.providerName} · ${formatListDateTime(record.checkedAt)}',
      badge: record.success
          ? text(zh: '健康', en: 'Healthy')
          : text(zh: '异常', en: 'Unhealthy'),
      badgeColor: statusColor,
      summary: record.success
          ? text(
              zh: '本次模型健康巡检通过，请求链路可用。',
              en: 'This model health check passed and the request path is available.',
            )
          : text(
              zh: '本次模型健康巡检未通过，请根据失败信息检查配置或服务状态。',
              en: 'This model health check failed. Review the error and provider status.',
            ),
      metrics: [
        OpenHandChartTooltipMetric(
          label: text(zh: '健康判定', en: 'Verdict'),
          value: record.success
              ? text(zh: '正常', en: 'Healthy')
              : text(zh: '异常', en: 'Unhealthy'),
          hint: record.status,
          icon: Icons.monitor_heart_rounded,
          color: statusColor,
        ),
        OpenHandChartTooltipMetric(
          label: text(zh: '延迟', en: 'Latency'),
          value: '${record.latencyMs} ms',
          icon: Icons.speed_rounded,
          color: statusColor,
        ),
        OpenHandChartTooltipMetric(
          label: text(zh: '耗时', en: 'Duration'),
          value: '${record.durationMs} ms',
          icon: Icons.timer_outlined,
          color: statusColor,
        ),
        OpenHandChartTooltipMetric(
          label: text(zh: '响应码', en: 'Status code'),
          value: record.responseCode == null
              ? '—'
              : 'HTTP ${record.responseCode}',
          icon: Icons.http_rounded,
          color: record.success
              ? OpenHandStatusColors.success
              : OpenHandStatusColors.error,
        ),
        OpenHandChartTooltipMetric(
          label: text(zh: '请求模式', en: 'Request mode'),
          value: modeLabel,
          icon: Icons.route_rounded,
          color: statusColor,
        ),
        OpenHandChartTooltipMetric(
          label: text(zh: '模型类型', en: 'Model kind'),
          value: record.modelKind,
          icon: Icons.category_outlined,
          color: statusColor,
        ),
        if (requestMethod.isNotEmpty)
          OpenHandChartTooltipMetric(
            label: text(zh: '请求方法', en: 'Method'),
            value: requestMethod,
            icon: Icons.swap_horiz_rounded,
            color: statusColor,
          ),
        OpenHandChartTooltipMetric(
          label: text(zh: '巡检端点', en: 'Endpoint'),
          value: endpoint,
          icon: Icons.dns_outlined,
          color: statusColor,
        ),
      ],
      notes: [
        if (record.errorMessage.trim().isNotEmpty) record.errorMessage.trim(),
        if (probeType.isNotEmpty)
          text(zh: '探测类型：$probeType', en: 'Probe: $probeType'),
        if (requestUrl.isNotEmpty)
          text(zh: '请求地址：$requestUrl', en: 'Request URL: $requestUrl'),
        text(zh: '代理：$modeLabel', en: 'Proxy: $modeLabel'),
      ],
    );
  }

  String _safeHealthUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return '';
    return uri.replace(userInfo: '', query: '', fragment: '').toString();
  }
}
