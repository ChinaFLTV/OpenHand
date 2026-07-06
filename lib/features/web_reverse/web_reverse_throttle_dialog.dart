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
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseThrottleDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return showWebReverseToolDialog<void>(
    context: context,
    builder: (_) => _ThrottleDialog(controller: controller),
  );
}

class _ThrottleDialog extends StatefulWidget {
  const _ThrottleDialog({required this.controller});
  final WebReverseSessionController controller;
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
          ? _presetLabel(current.preset)
          : current.offline
          ? (loc?.webReverseThrottleOffline ?? 'Offline')
          : 'down=${current.downloadKbps}kbps · up=${current.uploadKbps}kbps · ${current.latencyMs}ms';
      final body = '$summary · cache=${_disableCache ? 'disabled' : 'enabled'}';
      setState(() {
        _status =
            loc?.webReverseThrottleStatusApplied(body) ?? 'Applied: $body';
      });
      showWebReverseSuccessSnack(
        context,
        loc?.webReverseThrottleConditionsApplied ??
            'Network conditions applied',
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  String _presetLabel(WebReverseThrottlePreset preset) {
    return switch (preset) {
      WebReverseThrottlePreset.none => openHandLocalizedText(
        context,
        zh: '不限速',
        zhHant: '不限速',
        en: 'No throttling',
        fr: 'Sans limitation',
        de: 'Keine Drosselung',
        ja: '制限なし',
      ),
      WebReverseThrottlePreset.offline => openHandLocalizedText(
        context,
        zh: '离线',
        zhHant: '離線',
        en: 'Offline',
        fr: 'Hors ligne',
        de: 'Offline',
        ja: 'オフライン',
      ),
      WebReverseThrottlePreset.gprs => openHandLocalizedText(
        context,
        zh: 'GPRS (50/20kbps, 500ms)',
        zhHant: 'GPRS (50/20kbps, 500ms)',
        en: 'GPRS (50/20kbps, 500ms)',
        fr: 'GPRS (50/20kbps, 500ms)',
        de: 'GPRS (50/20kbps, 500ms)',
        ja: 'GPRS (50/20kbps, 500ms)',
      ),
      WebReverseThrottlePreset.slow3g => openHandLocalizedText(
        context,
        zh: '慢速 3G (400/400kbps, 400ms)',
        zhHant: '慢速 3G (400/400kbps, 400ms)',
        en: 'Slow 3G',
        fr: '3G lente',
        de: 'Langsames 3G',
        ja: '低速 3G',
      ),
      WebReverseThrottlePreset.fast3g => openHandLocalizedText(
        context,
        zh: '快速 3G (1.6/750kbps, 150ms)',
        zhHant: '快速 3G (1.6/750kbps, 150ms)',
        en: 'Fast 3G',
        fr: '3G rapide',
        de: 'Schnelles 3G',
        ja: '高速 3G',
      ),
      WebReverseThrottlePreset.fourG => openHandLocalizedText(
        context,
        zh: '4G (4/3 Mbps, 80ms)',
        zhHant: '4G (4/3 Mbps, 80ms)',
        en: '4G (4/3 Mbps, 80ms)',
        fr: '4G (4/3 Mbps, 80ms)',
        de: '4G (4/3 Mbps, 80ms)',
        ja: '4G (4/3 Mbps, 80ms)',
      ),
      WebReverseThrottlePreset.weakWifi => openHandLocalizedText(
        context,
        zh: '弱 Wi-Fi (10/5 Mbps, 40ms)',
        zhHant: '弱 Wi-Fi (10/5 Mbps, 40ms)',
        en: 'Weak Wi-Fi (10/5 Mbps, 40ms)',
        fr: 'Wi-Fi faible (10/5 Mbps, 40ms)',
        de: 'Schwaches WLAN (10/5 Mbps, 40ms)',
        ja: '弱い Wi-Fi (10/5 Mbps, 40ms)',
      ),
      WebReverseThrottlePreset.custom => openHandLocalizedText(
        context,
        zh: '自定义',
        zhHant: '自訂',
        en: 'Custom',
        fr: 'Personnalisé',
        de: 'Benutzerdefiniert',
        ja: 'カスタム',
      ),
    };
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
    showWebReverseErrorSnack(
      context,
      loc?.webReverseThrottleApplyFailed ?? 'Apply failed',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
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
                            label: Text(_presetLabel(p)),
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
