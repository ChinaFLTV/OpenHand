/// Rendering 调试面板。
///
/// 集中暴露 Chrome DevTools "Rendering" 抽屉里那批 paint/layout 可视化开关
/// 以及媒体仿真：Paint flashing / Layout shift regions / Layer borders /
/// Scroll bottlenecks / Web Vitals overlay / FPS meter / CPU 节流 / 强制
/// prefers-color-scheme + prefers-reduced-motion + print 媒体。
///
/// 所有开关直连 CDP，关闭弹窗后效果仍保留在目标页面上，让逆向 / UI 走查
/// 的同事可以一边截屏一边切换可视化层。
library;

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseRenderingDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _RenderingDialog(controller: controller, isZh: isZh),
  );
}

class _RenderingDialog extends StatefulWidget {
  const _RenderingDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_RenderingDialog> createState() => _RenderingDialogState();
}

class _RenderingDialogState extends State<_RenderingDialog> {
  bool _busy = false;
  String _status = '';

  bool _paintRects = false;
  bool _layoutShift = false;
  bool _layerBorders = false;
  bool _scrollBottleneck = false;
  bool _hitTest = false;
  bool _fps = false;
  bool _webVitals = false;

  double _cpuThrottle = 1.0; // 1x, 2x, 4x, 6x, 20x
  String _colorScheme = 'auto'; // auto / light / dark
  String _reducedMotion = 'auto'; // auto / reduce / no-preference
  String _mediaType = 'auto'; // auto / screen / print

  Future<Map<String, Object?>?> _send(
    String method, {
    Map<String, Object?>? params,
  }) async {
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      final res = await widget.controller.sendRawCdp(
        method: method,
        paramsJson: params == null
            ? null
            : _encodeParams(params),
      );
      if (!mounted) return res;
      final err = res?['error'];
      if (err != null) {
        setState(() => _status = '$method · $err');
      }
      return res;
    } catch (e, st) {
      silentLog('web_reverse_rendering_dialog', 'send.$method', e, st);
      if (mounted) setState(() => _status = '$method · $e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _encodeParams(Map<String, Object?> params) {
    // 简单 JSON 编码，避开 dart:convert 依赖（与同目录其它 dialog 风格一致）。
    final buf = StringBuffer('{');
    var first = true;
    params.forEach((k, v) {
      if (!first) buf.write(',');
      first = false;
      buf.write('"$k":');
      if (v is bool || v is num) {
        buf.write('$v');
      } else if (v == null) {
        buf.write('null');
      } else if (v is List) {
        buf.write('[');
        for (var i = 0; i < v.length; i++) {
          if (i > 0) buf.write(',');
          final item = v[i];
          if (item is Map) {
            buf.write(_encodeParams(item.cast<String, Object?>()));
          } else if (item is String) {
            buf.write('"${item.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"');
          } else {
            buf.write('$item');
          }
        }
        buf.write(']');
      } else if (v is Map) {
        buf.write(_encodeParams(v.cast<String, Object?>()));
      } else {
        final s = v.toString().replaceAll(r'\', r'\\').replaceAll('"', r'\"');
        buf.write('"$s"');
      }
    });
    buf.write('}');
    return buf.toString();
  }

  Future<void> _toggleOverlay(
    String key,
    bool value, {
    void Function(bool)? localApply,
  }) async {
    if (localApply != null) localApply(value);
    setState(() {});
    await _send(key, params: {'result': value});
  }

  Future<void> _applyCpuThrottle(double rate) async {
    setState(() => _cpuThrottle = rate);
    await _send('Emulation.setCPUThrottlingRate', params: {'rate': rate});
  }

  Future<void> _applyEmulatedMedia() async {
    final features = <Map<String, Object?>>[];
    if (_colorScheme != 'auto') {
      features.add({'name': 'prefers-color-scheme', 'value': _colorScheme});
    }
    if (_reducedMotion != 'auto') {
      features.add({'name': 'prefers-reduced-motion', 'value': _reducedMotion});
    }
    final params = <String, Object?>{
      'media': _mediaType == 'auto' ? '' : _mediaType,
      'features': features,
    };
    await _send('Emulation.setEmulatedMedia', params: params);
  }

  Future<void> _resetAll() async {
    setState(() {
      _paintRects = false;
      _layoutShift = false;
      _layerBorders = false;
      _scrollBottleneck = false;
      _hitTest = false;
      _fps = false;
      _webVitals = false;
      _cpuThrottle = 1.0;
      _colorScheme = 'auto';
      _reducedMotion = 'auto';
      _mediaType = 'auto';
    });
    await _send('Overlay.setShowPaintRects', params: {'result': false});
    await _send('Overlay.setShowLayoutShiftRegions', params: {'result': false});
    await _send('Overlay.setShowDebugBorders', params: {'result': false});
    await _send(
      'Overlay.setShowScrollBottleneckRects',
      params: {'show': false},
    );
    await _send('Overlay.setShowHitTestBorders', params: {'show': false});
    await _send('Overlay.setShowFPSCounter', params: {'show': false});
    await _send('Overlay.setShowWebVitals', params: {'show': false});
    await _send('Emulation.setCPUThrottlingRate', params: {'rate': 1.0});
    await _send('Emulation.setEmulatedMedia', params: {
      'media': '',
      'features': const <Map<String, Object?>>[],
    });
    if (mounted) {
      final m = ScaffoldMessenger.maybeOf(context);
      if (m != null) {
        OpenHandSnackBar.showSuccessOn(
          context,
          m,
          AppLocalizations.of(context)?.webReverseRenderingResetSuccess ?? 'Rendering overrides reset',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.layers_rounded, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)?.webReverseRenderingTitle ?? 'Rendering',
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          AppLocalizations.of(context)?.webReverseRenderingSubtitle ??
                              'Paint · Layout shift · Layers · FPS · media · CPU throttle',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context)?.webReverseRenderingResetAll ?? 'Reset all',
                    onPressed: _busy ? null : _resetAll,
                    icon: const Icon(Icons.restart_alt_rounded),
                  ),
                  IconButton(
                    tooltip: AppLocalizations.of(context)?.webReverseRenderingClose ?? 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                children: [
                  _sectionTitle(AppLocalizations.of(context)?.webReverseRenderingSectionOverlays ?? 'Overlays'),
                  _switchTile(
                    icon: Icons.brush_rounded,
                    title: 'Paint flashing',
                    subtitle: AppLocalizations.of(context)?.webReverseRenderingPaintFlashingDesc ??
                        'Highlight repainted regions',
                    value: _paintRects,
                    onChanged: (v) => _toggleOverlay(
                      'Overlay.setShowPaintRects',
                      v,
                      localApply: (b) => _paintRects = b,
                    ),
                  ),
                  _switchTile(
                    icon: Icons.swap_vert_rounded,
                    title: 'Layout shift regions',
                    subtitle: AppLocalizations.of(context)?.webReverseRenderingLayoutShiftDesc ??
                        'Visualize CLS regions',
                    value: _layoutShift,
                    onChanged: (v) => _toggleOverlay(
                      'Overlay.setShowLayoutShiftRegions',
                      v,
                      localApply: (b) => _layoutShift = b,
                    ),
                  ),
                  _switchTile(
                    icon: Icons.grid_4x4_rounded,
                    title: 'Layer borders',
                    subtitle: AppLocalizations.of(context)?.webReverseRenderingLayerBordersDesc ??
                        'Composited layer borders',
                    value: _layerBorders,
                    onChanged: (v) => _toggleOverlay(
                      'Overlay.setShowDebugBorders',
                      v,
                      localApply: (b) => _layerBorders = b,
                    ),
                  ),
                  _switchTile(
                    icon: Icons.swipe_rounded,
                    title: 'Scroll bottleneck regions',
                    subtitle: AppLocalizations.of(context)?.webReverseRenderingScrollBottleneckDesc ??
                        'Slow-scroll regions',
                    value: _scrollBottleneck,
                    onChanged: (v) async {
                      setState(() => _scrollBottleneck = v);
                      await _send(
                        'Overlay.setShowScrollBottleneckRects',
                        params: {'show': v},
                      );
                    },
                  ),
                  _switchTile(
                    icon: Icons.touch_app_rounded,
                    title: 'Hit-test borders',
                    subtitle: AppLocalizations.of(context)?.webReverseRenderingHitTestDesc ??
                        'Element hit-test borders',
                    value: _hitTest,
                    onChanged: (v) async {
                      setState(() => _hitTest = v);
                      await _send(
                        'Overlay.setShowHitTestBorders',
                        params: {'show': v},
                      );
                    },
                  ),
                  _switchTile(
                    icon: Icons.speed_rounded,
                    title: 'FPS meter',
                    subtitle: AppLocalizations.of(context)?.webReverseRenderingFpsDesc ??
                        'Live FPS overlay',
                    value: _fps,
                    onChanged: (v) async {
                      setState(() => _fps = v);
                      await _send(
                        'Overlay.setShowFPSCounter',
                        params: {'show': v},
                      );
                    },
                  ),
                  _switchTile(
                    icon: Icons.insights_rounded,
                    title: 'Web Vitals overlay',
                    subtitle: AppLocalizations.of(context)?.webReverseRenderingWebVitalsDesc ??
                        'LCP / CLS / INP floating layer',
                    value: _webVitals,
                    onChanged: (v) async {
                      setState(() => _webVitals = v);
                      await _send(
                        'Overlay.setShowWebVitals',
                        params: {'show': v},
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle(AppLocalizations.of(context)?.webReverseRenderingSectionPerf ?? 'Performance emulation'),
                  _cpuThrottleRow(cs, tt),
                  const SizedBox(height: 12),
                  _sectionTitle(AppLocalizations.of(context)?.webReverseRenderingSectionMedia ?? 'Media emulation'),
                  _segmentRow(
                    label: AppLocalizations.of(context)?.webReverseRenderingLabelColorScheme ?? 'Color scheme',
                    value: _colorScheme,
                    options: const ['auto', 'light', 'dark'],
                    onChanged: (v) {
                      setState(() => _colorScheme = v);
                      _applyEmulatedMedia();
                    },
                  ),
                  _segmentRow(
                    label: AppLocalizations.of(context)?.webReverseRenderingLabelReducedMotion ?? 'Reduced motion',
                    value: _reducedMotion,
                    options: const ['auto', 'reduce', 'no-preference'],
                    onChanged: (v) {
                      setState(() => _reducedMotion = v);
                      _applyEmulatedMedia();
                    },
                  ),
                  _segmentRow(
                    label: AppLocalizations.of(context)?.webReverseRenderingLabelMediaType ?? 'Media type',
                    value: _mediaType,
                    options: const ['auto', 'screen', 'print'],
                    onChanged: (v) {
                      setState(() => _mediaType = v);
                      _applyEmulatedMedia();
                    },
                  ),
                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: cs.errorContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _status,
                        style: tt.bodySmall?.copyWith(color: cs.onErrorContainer),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(
                children: [
                  if (_busy)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                  const Spacer(),
                  OpenHandDialogActionButton.primary(
                    label: AppLocalizations.of(context)?.webReverseRenderingClose ?? 'Close',
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

  Widget _sectionTitle(String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: value
            ? cs.primaryContainer.withValues(alpha: 0.42)
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? cs.primary.withValues(alpha: 0.4) : cs.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: value ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: _busy ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget _cpuThrottleRow(ColorScheme cs, TextTheme tt) {
    const presets = [1.0, 2.0, 4.0, 6.0, 20.0];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory_rounded, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(
                AppLocalizations.of(context)?.webReverseRenderingCpuThrottling ?? 'CPU throttling',
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_cpuThrottle.toStringAsFixed(_cpuThrottle == _cpuThrottle.truncateToDouble() ? 0 : 1)}x',
                  style: tt.labelMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in presets)
                OutlinedButton(
                  onPressed: _busy ? null : () => _applyCpuThrottle(p),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(56, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    backgroundColor: (_cpuThrottle - p).abs() < 0.01
                        ? cs.primaryContainer
                        : null,
                    foregroundColor: (_cpuThrottle - p).abs() < 0.01
                        ? cs.onPrimaryContainer
                        : cs.onSurface,
                  ),
                  child: Text('${p.toStringAsFixed(0)}x'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segmentRow({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final o in options)
                  ChoiceChip(
                    label: Text(o),
                    selected: value == o,
                    onSelected: _busy ? null : (_) => onChanged(o),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
