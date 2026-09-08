import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../app/theme/openhand_theme.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_busy_indicators.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../ai_model_health_controller.dart';
import '../model/ai_model_health.dart';

// 与应用输入框主题边框一致的统一控件高度。
const double _aiHealthControlHeight = 60;
const double _aiHealthTimeoutStackBreakpoint = 560;

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
  late final TextEditingController _connectTimeoutController;
  late final FocusNode _connectTimeoutFocusNode;
  late final TextEditingController _responseTimeoutController;
  late final FocusNode _responseTimeoutFocusNode;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController();
    _intervalFocusNode = FocusNode();
    _connectTimeoutController = TextEditingController();
    _connectTimeoutFocusNode = FocusNode();
    _responseTimeoutController = TextEditingController();
    _responseTimeoutFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _intervalFocusNode.dispose();
    _connectTimeoutController.dispose();
    _connectTimeoutFocusNode.dispose();
    _responseTimeoutController.dispose();
    _responseTimeoutFocusNode.dispose();
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
    if (!_connectTimeoutFocusNode.hasFocus &&
        _connectTimeoutController.text != '${settings.connectTimeoutSeconds}') {
      _connectTimeoutController.text = '${settings.connectTimeoutSeconds}';
    }
    if (!_responseTimeoutFocusNode.hasFocus &&
        _responseTimeoutController.text !=
            '${settings.responseTimeoutSeconds}') {
      _responseTimeoutController.text = '${settings.responseTimeoutSeconds}';
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
          hoverColor: kOpenHandSettingsItemHoverColor,
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
        kOpenHandGap12,
        _buildTimeoutFields(context),
        kOpenHandGap12,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
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
                    isDense: true,
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
              width: 156,
              height: _aiHealthControlHeight,
              child: AnimatedContainer(
                duration: openHandMotionDuration(context, kOpenHandMotion220),
                curve: kOpenHandEmphasizedTransitionCurve,
                child: FilledButton.tonalIcon(
                  onPressed: controller.cancelling
                      ? null
                      : controller.manualChecking
                      ? controller.cancelCheck
                      : controller.checking
                      ? null
                      : controller.checkAll,
                  style: FilledButton.styleFrom(
                    backgroundColor: controller.manualChecking
                        ? theme.colorScheme.error
                        : null,
                    foregroundColor: controller.manualChecking
                        ? theme.colorScheme.onError
                        : null,
                  ),
                  icon: AnimatedSwitcher(
                    duration: openHandMotionDuration(
                      context,
                      kOpenHandMotion200,
                    ),
                    child: controller.cancelling
                        ? const SizedBox.square(
                            key: ValueKey<String>('cancelling'),
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : controller.manualChecking
                        ? const Icon(
                            Icons.stop_rounded,
                            key: ValueKey<String>('stop'),
                          )
                        : controller.checking
                        ? const OpenHandBusyStatusIcon(
                            busy: true,
                            icon: null,
                            key: ValueKey<String>('busy'),
                          )
                        : const Icon(
                            Icons.wifi_tethering_rounded,
                            key: ValueKey<String>('idle'),
                          ),
                  ),
                  label: AnimatedSwitcher(
                    duration: openHandMotionDuration(
                      context,
                      kOpenHandMotion200,
                    ),
                    child: Text(
                      controller.cancelling
                          ? text(zh: '正在停止巡检', en: 'Stopping inspection')
                          : controller.manualChecking
                          ? text(zh: '停止巡检', en: 'Stop inspection')
                          : controller.checking
                          ? text(zh: '正在巡检', en: 'Checking')
                          : text(zh: '立即巡检', en: 'Run now'),
                      key: ValueKey<String>(
                        controller.cancelling
                            ? 'cancelling'
                            : controller.checking
                            ? 'checking'
                            : 'idle',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (!widget.showRequestMode)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            hoverColor: kOpenHandSettingsItemHoverColor,
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
                  isDense: true,
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

  Widget _buildTimeoutFields(BuildContext context) {
    final text = openHandTextResolver(context);
    final theme = Theme.of(context);

    Widget buildField({
      required TextEditingController controller,
      required FocusNode focusNode,
      required String label,
      required String helper,
      required IconData icon,
      required bool connection,
    }) {
      void save() {
        focusNode.unfocus();
        unawaited(_saveTimeout(controller: controller, connection: connection));
      }

      return TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          prefixIcon: Icon(icon),
          suffixText: 's',
        ),
        onSubmitted: (_) => save(),
        onTapOutside: (_) => save(),
      );
    }

    final connectionField = buildField(
      controller: _connectTimeoutController,
      focusNode: _connectTimeoutFocusNode,
      label: text(zh: '连接超时（秒）', en: 'Connection timeout (seconds)'),
      helper: text(
        zh: '范围 ${AiModelProbeTimeoutPolicy.minConnectTimeoutSeconds}-${AiModelProbeTimeoutPolicy.maxConnectTimeoutSeconds} 秒。',
        en: 'Range: ${AiModelProbeTimeoutPolicy.minConnectTimeoutSeconds}-${AiModelProbeTimeoutPolicy.maxConnectTimeoutSeconds} seconds.',
      ),
      icon: Icons.cable_rounded,
      connection: true,
    );
    final responseField = buildField(
      controller: _responseTimeoutController,
      focusNode: _responseTimeoutFocusNode,
      label: text(zh: '响应超时（秒）', en: 'Response timeout (seconds)'),
      helper: text(
        zh: '范围 ${AiModelProbeTimeoutPolicy.minResponseTimeoutSeconds}-${AiModelProbeTimeoutPolicy.maxResponseTimeoutSeconds} 秒。',
        en: 'Range: ${AiModelProbeTimeoutPolicy.minResponseTimeoutSeconds}-${AiModelProbeTimeoutPolicy.maxResponseTimeoutSeconds} seconds.',
      ),
      icon: Icons.timer_outlined,
      connection: false,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.18),
        borderRadius: kOpenHandBorderRadius20,
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.network_check_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                kOpenHandHGap8,
                Expanded(
                  child: Text(
                    text(
                      zh: '模型测试与健康巡检超时',
                      en: 'Model test and health-check timeouts',
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            kOpenHandGap4,
            Text(
              text(
                zh: '右上角测试按钮与健康检查按钮共用这两个配置。',
                en: 'The provider test and health-check buttons share these values.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            kOpenHandGap12,
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < _aiHealthTimeoutStackBreakpoint) {
                  return Column(
                    children: [connectionField, kOpenHandGap12, responseField],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: connectionField),
                    kOpenHandHGap12,
                    Expanded(child: responseField),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveTimeout({
    required TextEditingController controller,
    required bool connection,
  }) async {
    final healthController = context.read<AiModelHealthController>();
    final current = connection
        ? healthController.settings.connectTimeoutSeconds
        : healthController.settings.responseTimeoutSeconds;
    final min = connection
        ? AiModelProbeTimeoutPolicy.minConnectTimeoutSeconds
        : AiModelProbeTimeoutPolicy.minResponseTimeoutSeconds;
    final max = connection
        ? AiModelProbeTimeoutPolicy.maxConnectTimeoutSeconds
        : AiModelProbeTimeoutPolicy.maxResponseTimeoutSeconds;
    final value = int.tryParse(controller.text.trim());
    if (value == null || value < min || value > max) {
      controller.text = '$current';
      if (!mounted) return;
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '请输入 $min-$max 秒之间的整数。',
          en: 'Enter a whole number between $min and $max seconds.',
        ),
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    final saved = await healthController.updateSettings(
      connectTimeoutSeconds: connection ? value : null,
      responseTimeoutSeconds: connection ? null : value,
    );
    if (!mounted) return;
    final persisted = connection
        ? healthController.settings.connectTimeoutSeconds
        : healthController.settings.responseTimeoutSeconds;
    controller.text = '$persisted';
    if (!saved) {
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '保存模型探测超时设置失败。',
          en: 'Failed to save model probe timeout settings.',
        ),
        kind: OpenHandSnackKind.error,
      );
    }
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
    final rawError = record.errorMessage.trim();
    var failurePhase = '${metadata['failure_phase'] ?? ''}'.trim();
    if (!record.success && failurePhase.isEmpty) {
      failurePhase = classifyAiModelProbeFailurePhase(
        rawError,
        responseCode: record.responseCode,
      );
    }
    final failureLabel = switch (failurePhase) {
      'connection_timeout' => text(zh: '连接超时', en: 'Connection timeout'),
      'response_timeout' => text(zh: '响应超时', en: 'Response timeout'),
      'dns' => text(zh: 'DNS 解析', en: 'DNS resolution'),
      'tls' => text(zh: 'TLS 握手或证书', en: 'TLS handshake or certificate'),
      'connection' => text(zh: '网络连接', en: 'Network connection'),
      'http_status' => text(zh: 'HTTP 响应', en: 'HTTP response'),
      'response' => text(zh: '响应处理', en: 'Response handling'),
      _ => text(zh: '未知阶段', en: 'Unknown stage'),
    };
    final verdictLabel = record.success
        ? text(zh: '正常', en: 'Healthy')
        : failurePhase == 'connection_timeout' ||
              failurePhase == 'response_timeout'
        ? text(zh: '超时', en: 'Timed out')
        : text(zh: '异常', en: 'Unhealthy');
    final connectTimeoutSeconds = int.tryParse(
      '${metadata['connect_timeout_seconds'] ?? ''}',
    );
    final responseTimeoutSeconds = int.tryParse(
      '${metadata['response_timeout_seconds'] ?? ''}',
    );
    final timeoutParts = <String>[
      if (connectTimeoutSeconds != null)
        text(
          zh: '连接 ${connectTimeoutSeconds}s',
          en: 'Connect ${connectTimeoutSeconds}s',
        ),
      if (responseTimeoutSeconds != null)
        text(
          zh: '响应 ${responseTimeoutSeconds}s',
          en: 'Response ${responseTimeoutSeconds}s',
        ),
    ];
    final failureAdvice = switch (failurePhase) {
      'connection_timeout' => text(
        zh: '建议检查目标域名、网络与代理；慢链路可提高上方连接超时。',
        en: 'Check the host, network, and proxy. Increase the connection timeout for slow links.',
      ),
      'response_timeout' => text(
        zh: '连接已建立但响应等待超时；可提高上方响应超时或检查服务负载。',
        en: 'The connection opened but the response timed out. Increase the response timeout or inspect provider load.',
      ),
      'dns' => text(
        zh: '请检查域名拼写、DNS 与代理解析能力。',
        en: 'Check the host name, DNS, and proxy resolution.',
      ),
      'tls' => text(
        zh: '请检查证书有效期、系统时间与 TLS 代理。',
        en: 'Check the certificate, system time, and TLS proxy.',
      ),
      'connection' => text(
        zh: '请检查服务端口、网络可达性与代理配置。',
        en: 'Check the service port, network reachability, and proxy settings.',
      ),
      'http_status' => text(
        zh: '服务已响应，请结合响应码检查鉴权、模型 ID 与接口路径。',
        en: 'The service responded. Check authentication, model ID, and endpoint path against the status code.',
      ),
      _ => text(
        zh: '请结合下方请求地址与原始错误检查提供商配置。',
        en: 'Use the request URL and original error to inspect the provider configuration.',
      ),
    };
    final probeType = '${metadata['probe_type'] ?? ''}'.trim();
    final localizedProbeType = _localizedProbeType(context, probeType);
    final requestMethod = '${metadata['request_method'] ?? ''}'.trim();
    final requestUrl = _safeHealthUrl('${metadata['request_url'] ?? ''}');
    final endpoint = record.host.isEmpty
        ? text(zh: '未解析', en: 'Unavailable')
        : '${record.host}${record.port == null ? '' : ':${record.port}'}';
    return OpenHandChartTooltip(
      title: record.modelId,
      subtitle:
          '${record.providerName} · ${formatListDateTime(record.checkedAt)}',
      badge: record.success ? text(zh: '健康', en: 'Healthy') : verdictLabel,
      badgeColor: statusColor,
      summary: record.success
          ? text(
              zh: '本次模型健康巡检通过，请求链路可用。',
              en: 'This model health check passed and the request path is available.',
            )
          : rawError.isEmpty
          ? text(
              zh: '失败阶段：$failureLabel\n未返回可用的现场错误信息。',
              en: 'Failure stage: $failureLabel\nNo original error details were returned.',
            )
          : text(
              zh: '失败阶段：$failureLabel\n现场错误：$rawError',
              en: 'Failure stage: $failureLabel\nOriginal error: $rawError',
            ),
      metrics: [
        OpenHandChartTooltipMetric(
          label: text(zh: '健康判定', en: 'Verdict'),
          value: verdictLabel,
          icon: Icons.monitor_heart_rounded,
          color: statusColor,
        ),
        if (!record.success)
          OpenHandChartTooltipMetric(
            label: text(zh: '失败阶段', en: 'Failure stage'),
            value: failureLabel,
            icon: Icons.error_outline_rounded,
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
          value: _localizedModelKind(context, record.modelKind),
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
        if (timeoutParts.isNotEmpty)
          OpenHandChartTooltipMetric(
            label: text(zh: '超时配置', en: 'Timeouts'),
            value: timeoutParts.join(' · '),
            icon: Icons.timer_outlined,
            color: statusColor,
          ),
      ],
      notes: [
        if (!record.success) failureAdvice,
        if (probeType.isNotEmpty)
          text(
            zh: '探测类型：$localizedProbeType',
            en: 'Probe: $localizedProbeType',
          ),
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

  String _localizedModelKind(BuildContext context, String raw) {
    final text = openHandTextResolver(context);
    return switch (raw.trim().toLowerCase()) {
      'text' => text(zh: '文本模型', en: 'Text model'),
      'embedding' => text(zh: '嵌入模型', en: 'Embedding model'),
      'moderation' => text(zh: '内容审核', en: 'Content moderation'),
      'rerank' => text(zh: '重排序模型', en: 'Reranking model'),
      'image' => text(zh: '图像生成', en: 'Image generation'),
      'image_edit' => text(zh: '图像编辑', en: 'Image editing'),
      'video' => text(zh: '视频生成', en: 'Video generation'),
      'audio' => text(zh: '语音生成', en: 'Speech generation'),
      'transcription' => text(zh: '语音转写', en: 'Speech transcription'),
      'translation' => text(zh: '语音翻译', en: 'Speech translation'),
      'document' => text(zh: '文档处理', en: 'Document processing'),
      'realtime' => text(zh: '实时模型', en: 'Realtime model'),
      _ => text(zh: '未知模型类型', en: 'Unknown model kind'),
    };
  }

  String _localizedProbeType(BuildContext context, String raw) {
    final text = openHandTextResolver(context);
    return switch (raw.trim().toLowerCase()) {
      'model_metadata' => text(zh: '模型元数据探测', en: 'Model metadata probe'),
      'embedding_minimal_input' => text(
        zh: '嵌入最小输入探测',
        en: 'Minimal embedding input probe',
      ),
      'moderation_minimal_input' => text(
        zh: '审核最小输入探测',
        en: 'Minimal moderation input probe',
      ),
      'rerank_minimal_input' => text(
        zh: '重排序最小输入探测',
        en: 'Minimal reranking input probe',
      ),
      'generation_minimal_prompt' => text(
        zh: '生成最小提示词探测',
        en: 'Minimal generation prompt probe',
      ),
      'speech_minimal_input' => text(
        zh: '语音最小输入探测',
        en: 'Minimal speech input probe',
      ),
      'transcription_capability' => text(
        zh: '转写能力探测',
        en: 'Transcription capability probe',
      ),
      'translation_capability' => text(
        zh: '翻译能力探测',
        en: 'Translation capability probe',
      ),
      'document_capability' => text(
        zh: '文档能力探测',
        en: 'Document capability probe',
      ),
      'realtime_model_metadata' => text(
        zh: '实时模型元数据探测',
        en: 'Realtime model metadata probe',
      ),
      'text_availability_probe' => text(
        zh: '文本可用性探测',
        en: 'Text availability probe',
      ),
      _ => text(zh: '未知探测类型', en: 'Unknown probe type'),
    };
  }
}
