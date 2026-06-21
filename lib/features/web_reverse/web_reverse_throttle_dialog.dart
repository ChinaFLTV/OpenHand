/// 网络条件限速模拟面板。
///
/// 通过 `Network.emulateNetworkConditions` 模拟弱网，便于复现移动端慢速场景。
/// 也提供 `Network.setCacheDisabled` 一键禁用缓存，模拟首次访问。
///
/// 单位换算：CDP 接受 bytes/s（吞吐量）+ ms（延迟）。
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseThrottleDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _ThrottleDialog(controller: controller, isZh: isZh),
  );
}

class _ThrottleDialog extends StatefulWidget {
  const _ThrottleDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_ThrottleDialog> createState() => _ThrottleDialogState();
}

class _ThrottleDialogState extends State<_ThrottleDialog> {
  static const int _kMaxThrottleKbps = 10 * 1000 * 1000;
  static const int _kMaxLatencyMs = 60 * 1000;

  String _selectedId = 'no-throttle';
  final TextEditingController _downCtrl = TextEditingController(text: '0');
  final TextEditingController _upCtrl = TextEditingController(text: '0');
  final TextEditingController _latencyCtrl = TextEditingController(text: '0');
  bool _customOffline = false;
  bool _disableCache = false;
  bool _applying = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    final conditions = widget.controller.networkConditions;
    _disableCache = widget.controller.cacheDisabled;
    _selectedId = conditions.preset.id;
    _loadConditionsToCustom(conditions);
  }

  @override
  void dispose() {
    _downCtrl.dispose();
    _upCtrl.dispose();
    _latencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply({WebReverseThrottlePreset? preset}) async {
    if (_applying) return;
    final loc = AppLocalizations.of(context);
    setState(() {
      _applying = true;
      _status =
          loc?.webReverseThrottleEnableNetwork ?? 'Apply Network state...';
    });
    try {
      bool offline;
      int downKbps;
      int upKbps;
      int latencyMs;
      if (preset != null) {
        offline = preset.isOffline;
        downKbps = preset.downloadKbps;
        upKbps = preset.uploadKbps;
        latencyMs = preset.latencyMs;
      } else {
        offline = _customOffline;
        downKbps = clampedIntFromText(
          _downCtrl.text,
          fallback: 0,
          min: 0,
          max: _kMaxThrottleKbps,
        );
        upKbps = clampedIntFromText(
          _upCtrl.text,
          fallback: 0,
          min: 0,
          max: _kMaxThrottleKbps,
        );
        latencyMs = clampedIntFromText(
          _latencyCtrl.text,
          fallback: 0,
          min: 0,
          max: _kMaxLatencyMs,
        );
      }
      final ok = await widget.controller.setNetworkConditions(
        WebReverseNetworkConditions(
          preset: preset ?? WebReverseThrottlePreset.custom,
          offline: offline,
          latencyMs: latencyMs,
          downloadKbps: downKbps,
          uploadKbps: upKbps,
        ),
      );
      if (!mounted) return;
      if (!ok) {
        _showApplyFailed(loc);
        return;
      }
      final cacheOk = await widget.controller.setCacheDisabled(_disableCache);
      if (!mounted) return;
      if (!cacheOk) {
        _showApplyFailed(loc, reason: 'Network.setCacheDisabled');
        return;
      }
      final current = widget.controller.networkConditions;
      _selectedId = current.preset.id;
      _loadConditionsToCustom(current);
      final summary = current.isNoThrottle
          ? current.preset.displayLabel(widget.isZh)
          : current.offline
          ? (loc?.webReverseThrottleOffline ?? 'Offline')
          : 'down=${current.downloadKbps}kbps · up=${current.uploadKbps}kbps · ${current.latencyMs}ms';
      final body = '$summary · cache=${_disableCache ? 'disabled' : 'enabled'}';
      setState(() {
        _status =
            loc?.webReverseThrottleStatusApplied(body) ?? 'Applied: $body';
      });
      final m = ScaffoldMessenger.maybeOf(context);
      if (m != null) {
        OpenHandSnackBar.showSuccessOn(
          context,
          m,
          loc?.webReverseThrottleConditionsApplied ??
              'Network conditions applied',
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _reset() async {
    const defaultPreset = WebReverseThrottlePreset.none;
    setState(() {
      _selectedId = defaultPreset.id;
      _disableCache = false;
      _customOffline = false;
    });
    await _apply(preset: defaultPreset);
  }

  void _loadPresetToCustom(WebReverseThrottlePreset p) {
    _loadConditionsToCustom(WebReverseNetworkConditions.fromPreset(p));
  }

  void _loadConditionsToCustom(WebReverseNetworkConditions conditions) {
    _customOffline = conditions.offline;
    _downCtrl.text = '${conditions.downloadKbps}';
    _upCtrl.text = '${conditions.uploadKbps}';
    _latencyCtrl.text = '${conditions.latencyMs}';
  }

  void _showApplyFailed(AppLocalizations? loc, {String? reason}) {
    final effectiveReason =
        reason ?? loc?.webReverseThrottleUnknownError ?? 'unknown';
    setState(
      () => _status =
          loc?.webReverseThrottleStatusFailed(effectiveReason) ??
          'Failed: $effectiveReason',
    );
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        loc?.webReverseThrottleApplyFailed ?? 'Apply failed',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final isZh = widget.isZh;
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 720,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.network_check_rounded,
            title: loc?.webReverseThrottleTitle ?? 'Network Throttling',
            subtitle:
                loc?.webReverseThrottleSubtitle ??
                'Network.emulateNetworkConditions: presets or custom kbps/latency',
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc?.webReverseThrottlePresets ?? 'Presets',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: WebReverseThrottlePreset.values
                        .where((p) => p.isSelectable)
                        .map((p) {
                          final selected = _selectedId == p.id;
                          return ChoiceChip(
                            label: Text(p.displayLabel(isZh)),
                            selected: selected,
                            onSelected: _applying
                                ? null
                                : (_) {
                                    setState(() {
                                      _selectedId = p.id;
                                      _loadPresetToCustom(p);
                                    });
                                    _apply(preset: p);
                                  },
                          );
                        })
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    loc?.webReverseThrottleCustom ?? 'Custom',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _downCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText:
                                loc?.webReverseThrottleDownKbps ??
                                'Down kbps (0=∞)',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _upCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText:
                                loc?.webReverseThrottleUpKbps ??
                                'Up kbps (0=∞)',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _latencyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText:
                                loc?.webReverseThrottleLatencyMs ??
                                'Latency ms',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Checkbox(
                        value: _customOffline,
                        onChanged: (v) =>
                            setState(() => _customOffline = v ?? false),
                      ),
                      Text(loc?.webReverseThrottleOffline ?? 'Offline'),
                      const SizedBox(width: 16),
                      Checkbox(
                        value: _disableCache,
                        onChanged: (v) =>
                            setState(() => _disableCache = v ?? false),
                      ),
                      Text(
                        loc?.webReverseThrottleDisableCache ?? 'Disable cache',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OpenHandDialogActionButton.primary(
                        onPressed: _applying
                            ? null
                            : () {
                                setState(() => _selectedId = 'custom');
                                _apply();
                              },
                        icon: Icons.play_arrow_rounded,
                        busy: _applying,
                        label:
                            loc?.webReverseThrottleApplyCustom ??
                            'Apply custom',
                      ),
                      OpenHandDialogActionButton.secondary(
                        onPressed: _applying ? null : _reset,
                        icon: Icons.restart_alt_rounded,
                        label:
                            loc?.webReverseThrottleReset ??
                            'Reset (no throttle)',
                      ),
                    ],
                  ),
                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        _status,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    loc?.webReverseThrottleNotes ?? 'Notes',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    loc?.webReverseThrottleNotesBody ??
                        '· Throttle applies to the entire session of current target; reset or close to restore.\n'
                            '· kbps is converted to bytes/s via *1024/8 before sending; offline ignores throughput.\n'
                            '· Cache disable applies to both Fetch & Disk Cache, useful for cold-load reproduction.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  label: loc?.webReverseThrottleClose ?? 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
