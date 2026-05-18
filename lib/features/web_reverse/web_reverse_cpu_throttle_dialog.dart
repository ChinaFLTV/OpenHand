/// CPU 限速面板。
///
/// 通过 `Emulation.setCPUThrottlingRate {rate}` 模拟低端 CPU（1× 无限速，
/// 4× = 慢 4 倍 ≈ Slow 4G 手机）。状态保留在 dialog 本地，关闭后由
/// 浏览器侧继续生效（CDP 状态），需要用户手动 Reset 才能恢复。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseCpuThrottleDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _CpuThrottleDialog(controller: controller, isZh: isZh),
  );
}

class _CpuThrottleDialog extends StatefulWidget {
  const _CpuThrottleDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_CpuThrottleDialog> createState() => _CpuThrottleDialogState();
}

class _CpuThrottleDialogState extends State<_CpuThrottleDialog> {
  double _rate = 1;
  bool _busy = false;
  String _status = '';

  static const _presets = <(String, double)>[
    ('1× (off)', 1),
    ('2×', 2),
    ('4× (mid)', 4),
    ('6× (low)', 6),
    ('10× (very low)', 10),
    ('20× (lab)', 20),
  ];

  Future<void> _apply(double rate) async {
    final isZh = widget.isZh;
    setState(() {
      _rate = rate;
      _busy = true;
      _status =
          isZh ? '设置 CPU 限速 ${rate.toStringAsFixed(1)}×...' : 'Throttling ${rate}x...';
    });
    Map<String, Object?>? r;
    try {
      r = await widget.controller.sendRawCdp(
        method: 'Emulation.setCPUThrottlingRate',
        paramsJson: jsonEncode({'rate': rate}),
      );
    } catch (e, st) {
      silentLog('web-reverse', 'cpu-throttle.apply', e, st);
    }
    if (!mounted) return;
    if (r == null || r['error'] != null) {
      setState(() {
        _busy = false;
        _status =
            isZh ? '失败: ${r?['error'] ?? 'unknown'}' : 'Failed: ${r?['error'] ?? 'unknown'}';
      });
      return;
    }
    setState(() {
      _busy = false;
      _status = rate <= 1
          ? (isZh ? 'CPU 限速已关闭' : 'CPU throttle off')
          : (isZh
              ? '当前 CPU 限速 ${rate.toStringAsFixed(1)}×'
              : 'CPU throttled ${rate.toStringAsFixed(1)}×');
    });
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        rate <= 1
            ? (isZh ? '已恢复' : 'Reset')
            : (isZh
                ? '已应用 ${rate.toStringAsFixed(1)}× 限速'
                : 'Applied ${rate.toStringAsFixed(1)}× throttle'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 540),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.speed_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isZh ? 'CPU 限速' : 'CPU Throttling',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Emulation.setCPUThrottlingRate',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isZh ? '常用预设' : 'Presets',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _presets
                          .map((p) => ChoiceChip(
                                label: Text(p.$1),
                                selected: (_rate - p.$2).abs() < 1e-3,
                                onSelected: _busy
                                    ? null
                                    : (_) => _apply(p.$2),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      isZh
                          ? '滑动调节 ${_rate.toStringAsFixed(1)}×'
                          : 'Slider ${_rate.toStringAsFixed(1)}×',
                      style: theme.textTheme.labelLarge,
                    ),
                    Slider(
                      value: _rate,
                      min: 1,
                      max: 20,
                      divisions: 38,
                      label: '${_rate.toStringAsFixed(1)}×',
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _rate = v),
                      onChangeEnd: _busy ? null : (v) => _apply(v),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        isZh
                            ? '注意：CDP CPU 限速作用于渲染进程，不影响 GPU/网络。关闭窗口后限速仍生效，请手动选择 1×（off）或点「重置」恢复。'
                            : 'Throttling stays active after dialog closes. Pick 1× (off) or Reset to clear.',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_status.isNotEmpty)
              Container(
                width: double.infinity,
                color: cs.surfaceContainerHigh,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  _status,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : () => _apply(1),
                    icon: const Icon(Icons.restore_rounded),
                    label: Text(isZh ? '重置 (1×)' : 'Reset (1×)'),
                  ),
                  const Spacer(),
                  OpenHandDialogActionButton.primary(
                    label: isZh ? '关闭' : 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
