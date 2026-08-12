/// 地理位置 / 时区 / 语言环境覆盖面板。
///
/// 通过 CDP 协议直接修改当前 target 的环境：
///   - `Emulation.setGeolocationOverride` {latitude, longitude, accuracy}
///   - `Emulation.setTimezoneOverride` {timezoneId}
///   - `Emulation.setLocaleOverride` {locale}
///
/// 这些覆盖一直生效到 target 关闭或显式 clear。提供预设城市快捷按钮。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

class _GeoPreset {
  const _GeoPreset(this.name, this.lat, this.lng, this.tz, this.locale);
  final String name;
  final double lat;
  final double lng;
  final String tz;
  final String locale;
}

const List<_GeoPreset> _presets = <_GeoPreset>[
  _GeoPreset('北京', 39.9042, 116.4074, 'Asia/Shanghai', 'zh-CN'),
  _GeoPreset('上海', 31.2304, 121.4737, 'Asia/Shanghai', 'zh-CN'),
  _GeoPreset('香港', 22.3193, 114.1694, 'Asia/Hong_Kong', 'zh-HK'),
  _GeoPreset('Tokyo', 35.6762, 139.6503, 'Asia/Tokyo', 'ja-JP'),
  _GeoPreset('Seoul', 37.5665, 126.9780, 'Asia/Seoul', 'ko-KR'),
  _GeoPreset('Singapore', 1.3521, 103.8198, 'Asia/Singapore', 'en-SG'),
  _GeoPreset('London', 51.5074, -0.1278, 'Europe/London', 'en-GB'),
  _GeoPreset('Paris', 48.8566, 2.3522, 'Europe/Paris', 'fr-FR'),
  _GeoPreset('Berlin', 52.5200, 13.4050, 'Europe/Berlin', 'de-DE'),
  _GeoPreset('New York', 40.7128, -74.0060, 'America/New_York', 'en-US'),
  _GeoPreset('Los Angeles', 34.0522, -118.2437, 'America/Los_Angeles', 'en-US'),
  _GeoPreset(
    'San Francisco',
    37.7749,
    -122.4194,
    'America/Los_Angeles',
    'en-US',
  ),
  _GeoPreset('Sydney', -33.8688, 151.2093, 'Australia/Sydney', 'en-AU'),
  _GeoPreset('São Paulo', -23.5505, -46.6333, 'America/Sao_Paulo', 'pt-BR'),
  _GeoPreset('Moscow', 55.7558, 37.6173, 'Europe/Moscow', 'ru-RU'),
];
const double _kMinLatitude = -90;
const double _kMaxLatitude = 90;
const double _kMinLongitude = -180;
const double _kMaxLongitude = 180;
const double _kDefaultGeolocationAccuracy = 50;

Future<void> showWebReverseGeoOverrideDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _GeoOverrideDialog(controller: controller),
  );
}

class _GeoOverrideDialog extends StatefulWidget {
  const _GeoOverrideDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_GeoOverrideDialog> createState() => _GeoOverrideDialogState();
}

class _GeoOverrideDialogState extends State<_GeoOverrideDialog> {
  final _latCtl = TextEditingController(text: '39.9042');
  final _lngCtl = TextEditingController(text: '116.4074');
  final _accCtl = TextEditingController(text: '50');
  final _tzCtl = TextEditingController(text: 'Asia/Shanghai');
  final _localeCtl = TextEditingController(text: 'zh-CN');

  bool _enableGeo = true;
  bool _enableTz = true;
  bool _enableLocale = true;
  bool _busy = false;
  String? _lastStatus;

  @override
  void dispose() {
    _latCtl.dispose();
    _lngCtl.dispose();
    _accCtl.dispose();
    _tzCtl.dispose();
    _localeCtl.dispose();
    super.dispose();
  }

  void _applyPreset(_GeoPreset p) {
    setState(() {
      _latCtl.text = p.lat.toString();
      _lngCtl.text = p.lng.toString();
      _tzCtl.text = p.tz;
      _localeCtl.text = p.locale;
    });
  }

  Future<Map<String, Object?>?> _callCdp(
    String method,
    Map<String, Object?> params,
  ) async {
    return widget.controller.sendRawCdp(
      method: method,
      paramsJson: jsonEncode(params),
    );
  }

  Future<void> _apply() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _lastStatus = null;
    });
    final errors = <String>[];
    try {
      if (_enableGeo) {
        final lat = optionalDoubleFromValue(_latCtl.text);
        final lng = optionalDoubleFromValue(_lngCtl.text);
        final acc =
            optionalNonNegativeDoubleFromValue(_accCtl.text) ??
            _kDefaultGeolocationAccuracy;
        if (lat == null || lng == null) {
          errors.add('lat/lng 解析失败');
        } else if (lat < _kMinLatitude || lat > _kMaxLatitude) {
          errors.add('latitude 需在 $_kMinLatitude-$_kMaxLatitude 之间');
        } else if (lng < _kMinLongitude || lng > _kMaxLongitude) {
          errors.add('longitude 需在 $_kMinLongitude-$_kMaxLongitude 之间');
        } else {
          final r = await _callCdp('Emulation.setGeolocationOverride', {
            'latitude': lat,
            'longitude': lng,
            'accuracy': acc,
          });
          if (r != null && r['error'] != null) errors.add('geo: ${r['error']}');
        }
      }
      if (_enableTz) {
        final tz = _tzCtl.text.trim();
        if (tz.isEmpty) {
          errors.add('timezone 为空');
        } else {
          final r = await _callCdp('Emulation.setTimezoneOverride', {
            'timezoneId': tz,
          });
          if (r != null && r['error'] != null) errors.add('tz: ${r['error']}');
        }
      }
      if (_enableLocale) {
        final loc = _localeCtl.text.trim();
        if (loc.isEmpty) {
          errors.add('locale 为空');
        } else {
          final r = await _callCdp('Emulation.setLocaleOverride', {
            'locale': loc,
          });
          if (r != null && r['error'] != null) {
            errors.add('locale: ${r['error']}');
          }
        }
      }
    } catch (e, st) {
      silentLog('web_reverse_geo_override', '应用地理位置覆盖', e, st);
      errors.add('$e');
    }
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _lastStatus = errors.isEmpty
          ? (loc?.webReverseGeoOverridesApplied ?? 'Overrides applied')
          : errors.join('; ');
    });
    if (errors.isEmpty) {
      showOpenHandSuccessSnack(
        context,
        loc?.webReverseGeoEnvOverridesApplied ??
            'Environment overrides applied',
      );
    } else {
      showOpenHandErrorSnack(context, errors.join('; '));
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);
    Object? failure;
    try {
      await _callCdp('Emulation.clearGeolocationOverride', const {});
      // CDP 没有 clearTimezone/clearLocale 等单独方法，用空字符串重置。
      await _callCdp('Emulation.setTimezoneOverride', {'timezoneId': ''});
      await _callCdp('Emulation.setLocaleOverride', const {});
    } catch (e, st) {
      silentLog('web_reverse_geo_override', '清除地理位置覆盖', e, st);
      failure = e;
    }
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _lastStatus = failure == null
          ? (loc?.webReverseGeoOverridesCleared ?? 'Overrides cleared')
          : '${loc?.webReverseGeoOverridesCleared ?? 'Overrides cleared'}: $failure';
    });
    if (failure == null) {
      showOpenHandSuccessSnack(
        context,
        loc?.webReverseGeoEnvOverridesCleared ??
            'Cleared environment overrides',
      );
    } else {
      showOpenHandErrorSnack(context, '$failure');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      backgroundColor: cs.surfaceContainer,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.public_rounded,
            title: loc?.webReverseGeoTitle ?? 'Geo / TZ / Locale Override',
            subtitle:
                'Emulation.setGeolocationOverride / setTimezoneOverride / setLocaleOverride',
            onClose: () => Navigator.of(context).pop(),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc?.webReverseGeoCityPresets ?? 'City Presets',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  kOpenHandGap8,
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in _presets)
                        ActionChip(
                          label: Text(p.name),
                          onPressed: () => _applyPreset(p),
                        ),
                    ],
                  ),
                  kOpenHandGap18,
                  Row(
                    children: [
                      Checkbox(
                        value: _enableGeo,
                        onChanged: (v) =>
                            setState(() => _enableGeo = v ?? true),
                      ),
                      Expanded(
                        child: Text(
                          loc?.webReverseGeoEnableGeo ??
                              'Enable geolocation override',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _latCtl,
                          enabled: _enableGeo,
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      kOpenHandHGap8,
                      Expanded(
                        child: TextField(
                          controller: _lngCtl,
                          enabled: _enableGeo,
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      kOpenHandHGap8,
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _accCtl,
                          enabled: _enableGeo,
                          decoration: const InputDecoration(
                            labelText: 'Accuracy(m)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  kOpenHandGap14,
                  Row(
                    children: [
                      Checkbox(
                        value: _enableTz,
                        onChanged: (v) => setState(() => _enableTz = v ?? true),
                      ),
                      Expanded(
                        child: Text(
                          loc?.webReverseGeoEnableTz ??
                              'Enable timezone override',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                  kOpenHandGap8,
                  TextField(
                    controller: _tzCtl,
                    enabled: _enableTz,
                    decoration: const InputDecoration(
                      labelText: 'IANA timezone (eg. Asia/Shanghai)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  kOpenHandGap14,
                  Row(
                    children: [
                      Checkbox(
                        value: _enableLocale,
                        onChanged: (v) =>
                            setState(() => _enableLocale = v ?? true),
                      ),
                      Expanded(
                        child: Text(
                          loc?.webReverseGeoEnableLocale ??
                              'Enable locale override',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                  kOpenHandGap8,
                  TextField(
                    controller: _localeCtl,
                    enabled: _enableLocale,
                    decoration: const InputDecoration(
                      labelText: 'Locale (eg. zh-CN / en-US)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (_lastStatus != null) ...[
                    kOpenHandGap14,
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: webReverseSurfaceCardDecoration(
                        cs,
                        radius: 8,
                      ),
                      child: Text(
                        _lastStatus!,
                        style: const TextStyle(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  kOpenHandGap12,
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer.withValues(alpha: 0.35),
                      borderRadius: kWebReverseRadiusMedium,
                    ),
                    child: Text(
                      loc?.webReverseGeoTip ??
                          'Tip: overrides apply immediately within current target and persist across reloads. Inspect via navigator.geolocation, Intl.DateTimeFormat().resolvedOptions().timeZone, navigator.language. Hard-reload after override if a site caches detection.',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          buildWebReverseDialogFooter(
            context,
            actions: [
              OpenHandDialogActionButton.secondary(
                label: loc?.webReverseGeoClear ?? 'Clear',
                onPressed: _busy ? null : _clear,
              ),
              OpenHandDialogActionButton.primary(
                label: _busy
                    ? (loc?.webReverseGeoWorking ?? 'Working…')
                    : (loc?.webReverseGeoApply ?? 'Apply Overrides'),
                onPressed: _busy ? null : _apply,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
