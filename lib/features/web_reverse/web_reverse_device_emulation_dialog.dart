/// 设备模拟面板。
///
/// 三个 preset (mobile/tablet/desktop) + 自定义尺寸/DPR/mobile flag/UA override。
/// 内部走 [WebReverseSessionController.setDeviceMetricsPreset] +
/// [WebReverseSessionController.applyResolutionEmulation]。
library;

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseDeviceEmulationDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _DeviceEmuDialog(controller: controller, isZh: isZh),
  );
}

class _DeviceEmuDialog extends StatefulWidget {
  const _DeviceEmuDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  // ignore: unused_field
  final bool isZh;
  @override
  State<_DeviceEmuDialog> createState() => _DeviceEmuDialogState();
}

class _DeviceEmuDialogState extends State<_DeviceEmuDialog> {
  final _w = TextEditingController(text: '1280');
  final _h = TextEditingController(text: '720');
  final _dpr = TextEditingController(text: '2');
  final _ua = TextEditingController();
  bool _mobile = false;
  bool _busy = false;
  String _status = '';

  static const _presets = <WebReverseDevicePreset>[
    WebReverseDevicePreset.mobile375,
    WebReverseDevicePreset.tablet768,
    WebReverseDevicePreset.desktop1440,
  ];

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _dpr.dispose();
    _ua.dispose();
    super.dispose();
  }

  Future<void> _applyPreset(WebReverseDevicePreset p) async {
    final loc = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status = loc?.webReverseDeviceEmuApplyingPreset(p.label) ??
          'Applying ${p.label}...';
      _w.text = '${p.width}';
      _h.text = '${p.height}';
      _dpr.text = '${p.deviceScaleFactor}';
      _mobile = p.mobile;
      _ua.text = p.userAgent ?? '';
    });
    try {
      await widget.controller.setDeviceMetricsPreset(p);
    } catch (e, st) {
      silentLog('web-reverse', 'device-emu.preset', e, st);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status =
          loc?.webReverseDeviceEmuAppliedPreset(p.label) ?? 'Applied ${p.label}';
    });
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(context, m,
          loc?.webReverseDeviceEmuAppliedPreset(p.label) ?? 'Applied ${p.label}');
    }
  }

  Future<void> _applyCustom() async {
    final loc = AppLocalizations.of(context);
    final w = int.tryParse(_w.text.trim()) ?? 0;
    final h = int.tryParse(_h.text.trim()) ?? 0;
    final dpr = double.tryParse(_dpr.text.trim()) ?? 1;
    if (w < 100 || h < 100) {
      setState(() => _status =
          loc?.webReverseDeviceEmuMinSize ?? 'min 100×100');
      return;
    }
    setState(() {
      _busy = true;
      _status = loc?.webReverseDeviceEmuApplyingCustom ??
          'Applying custom metrics...';
    });
    try {
      final preset = WebReverseDevicePreset(
        id: 'custom',
        label: 'Custom',
        width: w,
        height: h,
        deviceScaleFactor: dpr,
        mobile: _mobile,
        userAgent: _ua.text.trim().isEmpty ? null : _ua.text.trim(),
      );
      await widget.controller.setDeviceMetricsPreset(preset);
    } catch (e, st) {
      silentLog('web-reverse', 'device-emu.custom', e, st);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = loc?.webReverseDeviceEmuAppliedCustomSize(
              w, h, dpr.toString()) ??
          'Applied $w×$h @ ${dpr}x';
    });
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
          context, m, loc?.webReverseDeviceEmuApplied ?? 'Applied');
    }
  }

  Future<void> _reset() async {
    final loc = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status = loc?.webReverseDeviceEmuClearingOverrides ??
          'Clearing overrides...';
    });
    try {
      await widget.controller.setDeviceMetricsPreset(null);
    } catch (e, st) {
      silentLog('web-reverse', 'device-emu.reset', e, st);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = loc?.webReverseDeviceEmuResetDone ?? 'Reset to default';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.devices_other_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc?.webReverseDeviceEmuTitle ?? 'Device Emulation',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Emulation.setDeviceMetricsOverride + setUserAgentOverride',
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
                    Text(loc?.webReverseDeviceEmuPresets ?? 'Presets',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _presets
                          .map((p) => OutlinedButton.icon(
                                onPressed: _busy ? null : () => _applyPreset(p),
                                icon: Icon(
                                  p.mobile
                                      ? Icons.phone_iphone_rounded
                                      : Icons.desktop_windows_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                    '${p.label} · ${p.width}×${p.height}@${p.deviceScaleFactor}x'),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 18),
                    Text(loc?.webReverseDeviceEmuCustom ?? 'Custom',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _w,
                            decoration: InputDecoration(
                              labelText: loc?.webReverseDeviceEmuWidth ?? 'Width',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _h,
                            decoration: InputDecoration(
                              labelText: loc?.webReverseDeviceEmuHeight ?? 'Height',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _dpr,
                            decoration: InputDecoration(
                              labelText: 'DPR',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: _mobile,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _mobile = v),
                      title: Text(loc?.webReverseDeviceEmuMobileMode ??
                          'mobile'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ua,
                      decoration: InputDecoration(
                        labelText: 'User-Agent (override)',
                        hintText: loc?.webReverseDeviceEmuUaHint ??
                            'leave empty to keep default',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _applyCustom,
                          icon: const Icon(Icons.check_circle_rounded),
                          label: Text(loc?.webReverseDeviceEmuApplyCustom ??
                              'Apply Custom'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _reset,
                          icon: const Icon(Icons.restore_rounded),
                          label: Text(loc?.webReverseDeviceEmuReset ?? 'Reset'),
                        ),
                      ],
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
              child: SizedBox(
                width: double.infinity,
                child: OpenHandDialogActionButton.primary(
                  label: loc?.webReverseDeviceEmuClose ?? 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
