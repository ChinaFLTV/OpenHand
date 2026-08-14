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
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseDeviceEmulationDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _DeviceEmuDialog(controller: controller),
  );
}

class _DeviceEmuDialog extends StatefulWidget {
  const _DeviceEmuDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_DeviceEmuDialog> createState() => _DeviceEmuDialogState();
}

class _DeviceEmuDialogState extends State<_DeviceEmuDialog> {
  static const int _kMinDeviceMetric = 100;
  static const double _kDefaultDeviceScaleFactor = 1;
  static const double _kMinDeviceScaleFactor = 0.1;
  static const double _kMaxDeviceScaleFactor = 10;

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

  Future<bool> _setDevicePreset(
    WebReverseDevicePreset? preset, {
    required String action,
  }) async {
    try {
      return await widget.controller.setDeviceMetricsPreset(preset);
    } catch (error, stack) {
      silentLog('web_reverse_device_emulation_dialog', action, error, stack);
      return false;
    }
  }

  void _showApplyFailed(AppLocalizations? loc) {
    final message = loc?.tlCallFailed ?? 'Failed';
    setState(() {
      _busy = false;
      _status = message;
    });
    showOpenHandErrorSnack(context, message);
  }

  Future<void> _applyPreset(WebReverseDevicePreset p) async {
    final loc = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status =
          loc?.webReverseDeviceEmuApplyingPreset(p.label) ??
          'Applying ${p.label}...';
      _w.text = '${p.width}';
      _h.text = '${p.height}';
      _dpr.text = '${p.deviceScaleFactor}';
      _mobile = p.mobile;
      _ua.text = p.userAgent ?? '';
    });
    final ok = await _setDevicePreset(p, action: '应用设备模拟预设');
    if (!mounted) return;
    if (!ok) {
      _showApplyFailed(loc);
      return;
    }
    setState(() {
      _busy = false;
      _status =
          loc?.webReverseDeviceEmuAppliedPreset(p.label) ??
          'Applied ${p.label}';
    });
    showOpenHandSuccessSnack(
      context,
      loc?.webReverseDeviceEmuAppliedPreset(p.label) ?? 'Applied ${p.label}',
    );
  }

  Future<void> _applyCustom() async {
    final loc = AppLocalizations.of(context);
    final w = intFromValue(_w.text, fallback: 0);
    final h = intFromValue(_h.text, fallback: 0);
    final dpr = clampedDoubleFromText(
      _dpr.text,
      fallback: _kDefaultDeviceScaleFactor,
      min: _kMinDeviceScaleFactor,
      max: _kMaxDeviceScaleFactor,
    );
    if (w < _kMinDeviceMetric || h < _kMinDeviceMetric) {
      setState(
        () => _status =
            loc?.webReverseDeviceEmuMinSize ??
            'min $_kMinDeviceMetric×$_kMinDeviceMetric',
      );
      return;
    }
    setState(() {
      _busy = true;
      _status =
          loc?.webReverseDeviceEmuApplyingCustom ??
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
        userAgent: nullIfBlank(_ua.text),
      );
      final ok = await _setDevicePreset(preset, action: '应用自定义设备模拟参数');
      if (!mounted) return;
      if (!ok) {
        _showApplyFailed(loc);
        return;
      }
    } catch (error, stack) {
      silentLog(
        'web_reverse_device_emulation_dialog',
        '应用自定义设备模拟',
        error,
        stack,
      );
      if (!mounted) return;
      _showApplyFailed(loc);
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status =
          loc?.webReverseDeviceEmuAppliedCustomSize(w, h, dpr.toString()) ??
          'Applied $w×$h @ ${dpr}x';
    });
    showOpenHandSuccessSnack(
      context,
      loc?.webReverseDeviceEmuApplied ?? 'Applied',
    );
  }

  Future<void> _reset() async {
    final loc = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status =
          loc?.webReverseDeviceEmuClearingOverrides ?? 'Clearing overrides...';
    });
    final ok = await _setDevicePreset(null, action: '重置设备模拟参数');
    if (!mounted) return;
    if (!ok) {
      _showApplyFailed(loc);
      return;
    }
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
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      maxHeight: kOpenHandDialogHeightStandard,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.devices_other_rounded,
            title: loc?.webReverseDeviceEmuTitle ?? 'Device Emulation',
            subtitle:
                'Emulation.setDeviceMetricsOverride + setUserAgentOverride',
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc?.webReverseDeviceEmuPresets ?? 'Presets',
                    style: theme.textTheme.labelLarge,
                  ),
                  kOpenHandGap6,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _presets
                        .map(
                          (p) => OutlinedButton.icon(
                            onPressed: _busy ? null : () => _applyPreset(p),
                            icon: Icon(
                              p.mobile
                                  ? Icons.phone_iphone_rounded
                                  : Icons.desktop_windows_rounded,
                              size: 16,
                            ),
                            label: Text(
                              '${p.label} · ${p.width}×${p.height}@${p.deviceScaleFactor}x',
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  kOpenHandGap18,
                  Text(
                    loc?.webReverseDeviceEmuCustom ?? 'Custom',
                    style: theme.textTheme.labelLarge,
                  ),
                  kOpenHandGap6,
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _w,
                          decoration: InputDecoration(
                            labelText: loc?.webReverseDeviceEmuWidth ?? 'Width',
                            border: const OutlineInputBorder(
                              borderRadius: kOpenHandBorderRadius10,
                            ),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      kOpenHandHGap10,
                      Expanded(
                        child: TextField(
                          controller: _h,
                          decoration: InputDecoration(
                            labelText:
                                loc?.webReverseDeviceEmuHeight ?? 'Height',
                            border: const OutlineInputBorder(
                              borderRadius: kOpenHandBorderRadius10,
                            ),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      kOpenHandHGap10,
                      Expanded(
                        child: TextField(
                          controller: _dpr,
                          decoration: const InputDecoration(
                            labelText: 'DPR',
                            border: OutlineInputBorder(
                              borderRadius: kOpenHandBorderRadius10,
                            ),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  kOpenHandGap10,
                  SwitchListTile(
                    value: _mobile,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _mobile = v),
                    title: Text(loc?.webReverseDeviceEmuMobileMode ?? 'mobile'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  kOpenHandGap12,
                  TextField(
                    controller: _ua,
                    decoration: InputDecoration(
                      labelText: 'User-Agent (override)',
                      hintText:
                          loc?.webReverseDeviceEmuUaHint ??
                          'leave empty to keep default',
                      border: const OutlineInputBorder(
                        borderRadius: kOpenHandBorderRadius10,
                      ),
                    ),
                    minLines: 2,
                    maxLines: 4,
                  ),
                  kOpenHandGap14,
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OpenHandDialogActionButton.primary(
                        onPressed: _busy ? null : _applyCustom,
                        icon: Icons.check_circle_rounded,
                        label:
                            loc?.webReverseDeviceEmuApplyCustom ??
                            'Apply Custom',
                      ),
                      OpenHandDialogActionButton.secondary(
                        onPressed: _busy ? null : _reset,
                        icon: Icons.restore_rounded,
                        label: loc?.webReverseDeviceEmuReset ?? 'Reset',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          buildWebReverseStatusBar(context, status: _status),
          buildOpenHandDialogFooter(
            primaryLabel: loc?.webReverseDeviceEmuClose ?? 'Close',
            onPrimaryPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
