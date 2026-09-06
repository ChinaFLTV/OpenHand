/// CPU 限速面板。
///
/// 通过 `Emulation.setCPUThrottlingRate {rate}` 模拟低端 CPU（1× 无限速，
/// 4× = 慢 4 倍 ≈ Slow 4G 手机）。状态保留在 dialog 本地，关闭后由
/// 浏览器侧继续生效（CDP 状态），需要用户手动 Reset 才能恢复。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseCpuThrottleDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _CpuThrottleDialog(controller: controller),
  );
}

class _CpuThrottleDialog extends StatefulWidget {
  const _CpuThrottleDialog({required this.controller});
  final WebReverseSessionController controller;
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
    final loc = AppLocalizations.of(context);
    final rateStr = rate.toStringAsFixed(1);
    setState(() {
      _rate = rate;
      _busy = true;
      _status =
          loc?.webReverseCpuThrottleApplying(rateStr) ??
          'Throttling ${rate}x...';
    });
    Map<String, Object?>? r;
    try {
      r = await widget.controller.sendRawCdp(
        method: 'Emulation.setCPUThrottlingRate',
        paramsJson: jsonEncode({'rate': rate}),
      );
    } catch (e, st) {
      silentLog('web_reverse_cpu_throttle_dialog', '应用 CPU 节流', e, st);
    }
    if (!mounted) return;
    if (r == null || r['error'] != null) {
      final err = '${r?['error'] ?? 'unknown'}';
      setState(() {
        _busy = false;
        _status = loc?.webReverseCpuThrottleFailed(err) ?? 'Failed: $err';
      });
      showOpenHandErrorSnack(
        context,
        loc?.webReverseCpuThrottleFailed(err) ?? 'Failed: $err',
      );
      return;
    }
    setState(() {
      _busy = false;
      _status = rate <= 1
          ? (loc?.webReverseCpuThrottleOff ?? 'CPU throttle off')
          : (loc?.webReverseCpuThrottleCurrent(rateStr) ??
                'CPU throttled $rateStr×');
    });
    showOpenHandSuccessSnack(
      context,
      rate <= 1
          ? (loc?.webReverseCpuThrottleResetDone ?? 'Reset')
          : (loc?.webReverseCpuThrottleApplied(rateStr) ??
                'Applied $rateStr× throttle'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthStandard,
      maxHeight: kOpenHandDialogHeightCompact,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.speed_rounded,
            title: loc?.webReverseCpuThrottleTitle ?? 'CPU Throttling',
            subtitle: 'Emulation.setCPUThrottlingRate',
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc?.webReverseCpuThrottlePresets ?? 'Presets',
                    style: theme.textTheme.labelLarge,
                  ),
                  kOpenHandGap6,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _presets
                        .map(
                          (p) => ChoiceChip(
                            label: Text(p.$1),
                            selected: (_rate - p.$2).abs() < 1e-3,
                            onSelected: _busy ? null : (_) => _apply(p.$2),
                          ),
                        )
                        .toList(),
                  ),
                  kOpenHandGap22,
                  Text(
                    loc?.webReverseCpuThrottleSliderLabel(
                          _rate.toStringAsFixed(1),
                        ) ??
                        'Slider ${_rate.toStringAsFixed(1)}×',
                    style: theme.textTheme.labelLarge,
                  ),
                  kOpenHandGap6,
                  Slider(
                    value: _rate,
                    min: 1,
                    max: 20,
                    divisions: 38,
                    label: '${_rate.toStringAsFixed(1)}×',
                    onChanged: _busy ? null : (v) => setState(() => _rate = v),
                    onChangeEnd: _busy ? null : _apply,
                  ),
                  kOpenHandGap8,
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: webReverseSurfaceCardDecoration(cs),
                    child: Text(
                      loc?.webReverseCpuThrottleNote ??
                          'Throttling stays active after dialog closes. Pick 1× (off) or Reset to clear.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          buildWebReverseStatusBar(context, status: _status),
          buildWebReverseDialogFooter(
            context,
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: _busy ? null : () => _apply(1),
                icon: Icons.restore_rounded,
                label: loc?.webReverseCpuThrottleReset ?? 'Reset (1×)',
              ),
              OpenHandDialogActionButton.primary(
                label: loc?.commonClose ?? 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
