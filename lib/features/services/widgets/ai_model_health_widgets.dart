import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../ai_model_health_controller.dart';
import '../model/ai_model_health.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(text(zh: '定时健康巡检', en: 'Scheduled health checks')),
          subtitle: Text(
            text(
              zh: '按固定间隔检查所有提供商的所有模型，并保存每次结果。',
              en: 'Check every configured model on a fixed interval and retain each result.',
            ),
          ),
          value: settings.enabled,
          onChanged: (value) => controller.updateSettings(enabled: value),
        ),
        Row(
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
            FilledButton.tonalIcon(
              onPressed: controller.checking ? null : controller.checkAll,
              icon: controller.checking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering_rounded),
              label: Text(text(zh: '立即巡检', en: 'Run now')),
            ),
          ],
        ),
        if (!widget.showRequestMode)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(text(zh: '使用系统代理', en: 'Use system proxy')),
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
          ),
        if (widget.showRequestMode) ...[
          kOpenHandGap8,
          InputDecorator(
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
    return Tooltip(
      message: openHandLocalizedText(
        context,
        zh: records.isEmpty ? '暂无巡检记录' : '健康巡检历史',
        en: records.isEmpty ? 'No health records yet' : 'Health-check history',
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final record in bars)
            _HealthBar(
              record: record,
              emptyColor: colors.outlineVariant.withValues(alpha: 0.45),
              compact: compact,
            ),
        ],
      ),
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
    final bar = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: compact ? 3 : 4,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    final content = record == null
        ? bar
        : Tooltip(
            richMessage: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(text: '${record!.providerName}\n'),
                TextSpan(
                  text: '${record!.modelId}\n',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text:
                      '${record!.success ? '健康' : '异常'} · '
                      '${record!.latencyMs} ms · 耗时 ${record!.durationMs} ms\n',
                ),
                TextSpan(
                  text:
                      '${record!.checkedAt.toLocal()} · '
                      '${record!.requestMode.storageValue}\n',
                ),
                if (record!.host.isNotEmpty)
                  TextSpan(
                    text:
                        '${record!.host}${record!.port == null ? '' : ':${record!.port}'}\n',
                  ),
                if (record!.responseCode != null)
                  TextSpan(text: 'HTTP ${record!.responseCode}\n'),
                if (record!.errorMessage.isNotEmpty)
                  TextSpan(text: record!.errorMessage),
              ],
            ),
            child: bar,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.2),
      child: content,
    );
  }
}
