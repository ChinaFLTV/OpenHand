/// 网络条件限速模拟面板。
///
/// 通过 `Network.emulateNetworkConditions` 模拟弱网，便于复现移动端慢速场景。
/// 也提供 `Network.setCacheDisabled` 一键禁用缓存，模拟首次访问。
///
/// 单位换算：CDP 接受 bytes/s（吞吐量）+ ms（延迟）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
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

class _Preset {
  const _Preset({
    required this.id,
    required this.zh,
    required this.en,
    required this.offline,
    required this.downKbps,
    required this.upKbps,
    required this.latencyMs,
  });
  final String id;
  final String zh;
  final String en;
  final bool offline;
  final int downKbps; // 0 = unlimited
  final int upKbps;
  final int latencyMs;
}

const _presets = <_Preset>[
  _Preset(
      id: 'no-throttle',
      zh: '不限速',
      en: 'No throttle',
      offline: false,
      downKbps: 0,
      upKbps: 0,
      latencyMs: 0),
  _Preset(
      id: 'offline',
      zh: '离线',
      en: 'Offline',
      offline: true,
      downKbps: 0,
      upKbps: 0,
      latencyMs: 0),
  _Preset(
      id: 'gprs',
      zh: 'GPRS (50/20kbps, 500ms)',
      en: 'GPRS (50/20kbps, 500ms)',
      offline: false,
      downKbps: 50,
      upKbps: 20,
      latencyMs: 500),
  _Preset(
      id: 'slow-3g',
      zh: '慢速 3G (400/400kbps, 400ms)',
      en: 'Slow 3G (400/400kbps, 400ms)',
      offline: false,
      downKbps: 400,
      upKbps: 400,
      latencyMs: 400),
  _Preset(
      id: 'fast-3g',
      zh: '快速 3G (1.6/750kbps, 150ms)',
      en: 'Fast 3G (1.6/750kbps, 150ms)',
      offline: false,
      downKbps: 1600,
      upKbps: 750,
      latencyMs: 150),
  _Preset(
      id: '4g',
      zh: '4G (4/3 Mbps, 80ms)',
      en: '4G (4/3 Mbps, 80ms)',
      offline: false,
      downKbps: 4000,
      upKbps: 3000,
      latencyMs: 80),
  _Preset(
      id: 'wifi',
      zh: '弱 Wi-Fi (10/5 Mbps, 40ms)',
      en: 'Weak Wi-Fi (10/5 Mbps, 40ms)',
      offline: false,
      downKbps: 10000,
      upKbps: 5000,
      latencyMs: 40),
];

class _ThrottleDialog extends StatefulWidget {
  const _ThrottleDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_ThrottleDialog> createState() => _ThrottleDialogState();
}

class _ThrottleDialogState extends State<_ThrottleDialog> {
  String _selectedId = 'no-throttle';
  final TextEditingController _downCtrl = TextEditingController(text: '0');
  final TextEditingController _upCtrl = TextEditingController(text: '0');
  final TextEditingController _latencyCtrl = TextEditingController(text: '0');
  bool _customOffline = false;
  bool _disableCache = false;
  bool _applying = false;
  String _status = '';

  @override
  void dispose() {
    _downCtrl.dispose();
    _upCtrl.dispose();
    _latencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply({_Preset? preset}) async {
    if (_applying) return;
    setState(() {
      _applying = true;
      _status = widget.isZh ? '启用 Network 域...' : 'Enable Network domain...';
    });
    try {
      // 先确保 Network 域已开启。
      await widget.controller.sendRawCdp(
        method: 'Network.enable',
        paramsJson: '{}',
        useSession: true,
      );
      bool offline;
      int downKbps;
      int upKbps;
      int latencyMs;
      if (preset != null) {
        offline = preset.offline;
        downKbps = preset.downKbps;
        upKbps = preset.upKbps;
        latencyMs = preset.latencyMs;
      } else {
        offline = _customOffline;
        downKbps = int.tryParse(_downCtrl.text.trim()) ?? 0;
        upKbps = int.tryParse(_upCtrl.text.trim()) ?? 0;
        latencyMs = int.tryParse(_latencyCtrl.text.trim()) ?? 0;
      }
      final downBps = downKbps <= 0 ? -1 : (downKbps * 1024 / 8).round();
      final upBps = upKbps <= 0 ? -1 : (upKbps * 1024 / 8).round();
      final params = jsonEncode({
        'offline': offline,
        'latency': latencyMs,
        'downloadThroughput': downBps,
        'uploadThroughput': upBps,
      });
      final r = await widget.controller.sendRawCdp(
        method: 'Network.emulateNetworkConditions',
        paramsJson: params,
        useSession: true,
      );
      // 缓存开关
      await widget.controller.sendRawCdp(
        method: 'Network.setCacheDisabled',
        paramsJson: jsonEncode({'cacheDisabled': _disableCache}),
        useSession: true,
      );
      if (!mounted) return;
      if (r == null || r['error'] != null) {
        setState(() => _status = widget.isZh
            ? '失败：${r?['error'] ?? widget.isZh}'
            : 'Failed: ${r?['error'] ?? 'unknown'}');
        final m = ScaffoldMessenger.maybeOf(context);
        if (m != null) {
          OpenHandSnackBar.showErrorOn(
              context, m, widget.isZh ? '应用失败' : 'Apply failed');
        }
        return;
      }
      setState(() {
        _status = widget.isZh
            ? '已应用：${offline ? '离线' : 'down=${downKbps}kbps · up=${upKbps}kbps · ${latencyMs}ms'} · 缓存=${_disableCache ? '禁用' : '开启'}'
            : 'Applied: ${offline ? 'offline' : 'down=${downKbps}kbps · up=${upKbps}kbps · ${latencyMs}ms'} · cache=${_disableCache ? 'disabled' : 'enabled'}';
      });
      final m = ScaffoldMessenger.maybeOf(context);
      if (m != null) {
        OpenHandSnackBar.showSuccessOn(
            context, m, widget.isZh ? '已应用网络条件' : 'Network conditions applied');
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _reset() async {
    final defaultPreset = _presets.first;
    setState(() {
      _selectedId = defaultPreset.id;
      _disableCache = false;
      _customOffline = false;
    });
    await _apply(preset: defaultPreset);
  }

  void _loadPresetToCustom(_Preset p) {
    _customOffline = p.offline;
    _downCtrl.text = '${p.downKbps}';
    _upCtrl.text = '${p.upKbps}';
    _latencyCtrl.text = '${p.latencyMs}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = widget.isZh;
    return Dialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.network_check_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isZh ? '网络条件模拟' : 'Network Throttling',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          isZh
                              ? 'Network.emulateNetworkConditions：选择预设或自定义 kbps/延迟'
                              : 'Network.emulateNetworkConditions: presets or custom kbps/latency',
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
                    Text(
                      isZh ? '预设档' : 'Presets',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _presets.map((p) {
                        final selected = _selectedId == p.id;
                        return ChoiceChip(
                          label: Text(isZh ? p.zh : p.en),
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
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      isZh ? '自定义' : 'Custom',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
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
                                  isZh ? '下行 kbps (0=不限)' : 'Down kbps (0=∞)',
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
                                  isZh ? '上行 kbps (0=不限)' : 'Up kbps (0=∞)',
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
                              labelText: isZh ? '延迟 ms' : 'Latency ms',
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
                        Text(isZh ? '离线' : 'Offline'),
                        const SizedBox(width: 16),
                        Checkbox(
                          value: _disableCache,
                          onChanged: (v) =>
                              setState(() => _disableCache = v ?? false),
                        ),
                        Text(isZh ? '禁用缓存' : 'Disable cache'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _applying
                              ? null
                              : () {
                                  setState(() => _selectedId = 'custom');
                                  _apply();
                                },
                          icon: _applying
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.play_arrow_rounded, size: 18),
                          label: Text(isZh ? '应用自定义' : 'Apply custom'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _applying ? null : _reset,
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: Text(isZh ? '重置（不限速）' : 'Reset (no throttle)'),
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
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      isZh ? '提示' : 'Notes',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isZh
                          ? '· 限速对当前 target 整个 session 生效，关闭浏览器或调用「不限速」可恢复。\n'
                              '· kbps 经 *1024/8 转换为 bytes/s 下发；离线时吞吐量参数被忽略。\n'
                              '· 禁用缓存对 Fetch/Disk Cache 同时生效，便于复现首次访问。'
                          : '· Throttle applies to the entire session of current target; reset or close to restore.\n'
                              '· kbps is converted to bytes/s via *1024/8 before sending; offline ignores throughput.\n'
                              '· Cache disable applies to both Fetch & Disk Cache, useful for cold-load reproduction.',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
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
