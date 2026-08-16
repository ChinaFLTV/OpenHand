/// Animations 调试面板。
///
/// 通过浏览器 `document.getAnimations()` 拉一份当前活跃 Web Animations
/// 列表（CSS transition / CSS animation / Element.animate / WAAPI），并
/// 借助 CDP `Animation.setPlaybackRate` 全局减速回放，方便逆向 / 视觉
/// 走查复杂的微交互（弹窗 spring、loading 骨架、过渡动画等）。
///
/// 暂不内联 keyframe 编辑（DevTools 官方 Animation panel 才有完整版），
/// 但提供：
///   - 全局 playbackRate 滑杆 + 0/0.25x/0.5x/1x/2x 按钮（CDP 端真正落库）
///   - 一键 Pause / Resume 所有 animation
///   - 列表展示 id / state / currentTime / duration / iterations
///   - 单独 cancel 某条 animation（运行端调用 .cancel()）
///   - 复制 JSON 摘要给逆向分析
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseAnimationsDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _AnimationsDialog(controller: controller, isZh: isZh),
  );
}

class _AnimationsDialog extends StatefulWidget {
  const _AnimationsDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;
  @override
  State<_AnimationsDialog> createState() => _AnimationsDialogState();
}

class _AnimationRow {
  _AnimationRow({
    required this.handle,
    required this.id,
    required this.animationName,
    required this.playState,
    required this.currentTime,
    required this.duration,
    required this.playbackRate,
    required this.iterations,
    required this.targetSelector,
  });
  final int handle; // index in window.__oh_anims snapshot
  final String id;
  final String animationName;
  final String playState;
  final double currentTime;
  final double duration;
  final double playbackRate;
  final double iterations;
  final String targetSelector;
}

class _AnimationsDialogState extends State<_AnimationsDialog> {
  static const int _maxAnimationRows = 1000;
  static const int _maxAnimationNameChars = 512;
  static const int _maxAnimationSelectorChars = 2 * kBytesPerKiB;
  static const int _maxAnimationSnapshotChars = 2 * kBytesPerMiB;

  bool _busy = false;
  String _status = '';
  double _playbackRate = 1.0;
  List<_AnimationRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    // 进入面板时先把全局 playbackRate 同步为 1.0，避免上一次会话留了 0
    // 让用户错觉 "页面动画全死了"。
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _setPlaybackRate(double rate) async {
    setState(() {
      _playbackRate = rate;
      _busy = true;
    });
    try {
      await widget.controller.sendRawCdp(method: 'Animation.enable');
      final r = await widget.controller.sendRawCdp(
        method: 'Animation.setPlaybackRate',
        paramsJson: jsonEncode({'playbackRate': rate}),
      );
      if (!mounted) return;
      final loc = AppLocalizations.of(context);
      setState(() {
        _busy = false;
        _status = (r != null && r['error'] != null)
            ? (loc?.webReverseAnimationsSetFailed(r['error'].toString()) ??
                  'setPlaybackRate failed: ${r['error']}')
            : (loc?.webReverseAnimationsRateNow(rate.toStringAsFixed(2)) ??
                  'global rate = ${rate.toStringAsFixed(2)}x');
      });
    } catch (e, st) {
      silentLog('web_reverse_animations_dialog', '设置动画播放速率', e, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status =
            AppLocalizations.of(
              context,
            )?.webReverseAnimationsSetError(e.toString()) ??
            'error: $e';
      });
    }
  }

  // 浏览器侧脚本：把当前活跃动画落到 window.__oh_anims 数组，并 stringify
  // 返回出来。把每条 animation 保存原引用，方便后续按 index cancel/pause。
  static const String _snapshotExpr =
      '''
(function(){
  try {
    const anims = document.getAnimations({ subtree: true }).slice(0, $_maxAnimationRows);
    window.__oh_anims = anims;
    const cssEsc = (s) => (window.CSS && CSS.escape) ? CSS.escape(s) : s;
    function selectorOf(el){
      if (!el || !(el instanceof Element)) return '';
      if (el.id) return '#' + cssEsc(el.id);
      const parts = [];
      let cur = el; let depth = 0;
      while (cur && cur.nodeType === 1 && depth < 4) {
        let p = cur.nodeName.toLowerCase();
        if (cur.classList && cur.classList.length) {
          p += '.' + Array.from(cur.classList).slice(0,2).map(cssEsc).join('.');
        }
        parts.unshift(p);
        cur = cur.parentElement; depth++;
      }
      return parts.join(' > ').slice(0, $_maxAnimationSelectorChars);
    }
    const out = anims.map((a, i) => {
      let dur = 0, iters = 1, name = '';
      try {
        const eff = a.effect;
        if (eff) {
          const t = eff.getComputedTiming ? eff.getComputedTiming() : {};
          dur = Number(t.duration) || 0;
          iters = Number(t.iterations) || 1;
          name = ((a.animationName || (eff.target && eff.target.tagName) || '') + '').slice(0, $_maxAnimationNameChars);
        }
      } catch (_) {}
      let tgt = '';
      try { tgt = selectorOf(a.effect && a.effect.target); } catch (_) {}
      return {
        handle: i,
        id: ((a.id || '') + '').slice(0, $_maxAnimationNameChars),
        animationName: name,
        playState: (a.playState || 'idle') + '',
        currentTime: Number(a.currentTime) || 0,
        duration: dur,
        playbackRate: Number(a.playbackRate) || 1,
        iterations: iters,
        target: tgt,
      };
    });
    return JSON.stringify(out);
  } catch (e) { return JSON.stringify({ __err: String(e) }); }
})()
''';

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
    });
    try {
      final r = await widget.controller.evaluateJavaScript(_snapshotExpr);
      if (!mounted) return;
      final value = cdpStringResultValue(r);
      if (value == null) {
        setState(() {
          _busy = false;
          _status =
              AppLocalizations.of(context)?.webReverseAnimationsNoSnapshot ??
              'no snapshot returned';
          _rows = const [];
        });
        return;
      }
      if (value.length > _maxAnimationSnapshotChars) {
        setState(() {
          _busy = false;
          _status = 'animation snapshot exceeds the safety limit';
          _rows = const [];
        });
        return;
      }
      final error = decodeStringKeyedJsonMap(value);
      if (error != null && error['__err'] != null) {
        setState(() {
          _busy = false;
          _status =
              AppLocalizations.of(context)?.webReverseAnimationsBrowserError(
                stringFromValue(error['__err']),
              ) ??
              'browser error: ${error['__err']}';
          _rows = const [];
        });
        return;
      }
      final entries = decodeStringKeyedJsonMapList(value);
      if (entries == null) {
        setState(() {
          _busy = false;
          _status =
              AppLocalizations.of(
                context,
              )?.webReverseAnimationsMalformedSnapshot ??
              'malformed snapshot';
          _rows = const [];
        });
        return;
      }
      final rows = <_AnimationRow>[];
      for (final item in entries.take(_maxAnimationRows)) {
        rows.add(
          _AnimationRow(
            handle: nonNegativeIntFromValue(item['handle'], fallback: 0),
            id: clipText(
              stringFromValue(item['id']),
              _maxAnimationNameChars,
              suffix: '',
            ),
            animationName: clipText(
              stringFromValue(item['animationName']),
              _maxAnimationNameChars,
              suffix: '',
            ),
            playState: clipText(
              stringFromValue(item['playState'], fallback: 'idle'),
              32,
              suffix: '',
            ),
            currentTime: doubleFromValue(item['currentTime'], fallback: 0),
            duration: doubleFromValue(item['duration'], fallback: 0),
            playbackRate: doubleFromValue(item['playbackRate'], fallback: 1),
            iterations: doubleFromValue(item['iterations'], fallback: 1),
            targetSelector: clipText(
              stringFromValue(item['target']),
              _maxAnimationSelectorChars,
              suffix: '',
            ),
          ),
        );
      }
      setState(() {
        _busy = false;
        _rows = rows;
        _status =
            AppLocalizations.of(
              context,
            )?.webReverseAnimationsSnapshotCount(rows.length) ??
            '${rows.length} active animation(s)';
      });
    } catch (e, st) {
      silentLog('web_reverse_animations_dialog', '刷新动画列表', e, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status =
            AppLocalizations.of(
              context,
            )?.webReverseAnimationsSnapshotFailed(e.toString()) ??
            'snapshot failed: $e';
      });
    }
  }

  Future<void> _bulkCommand(String method) async {
    // method ∈ pause / play / cancel — 操作所有 __oh_anims
    setState(() => _busy = true);
    try {
      final expr =
          '(function(){var a=window.__oh_anims||[];var n=0;for(var i=0;i<a.length;i++){try{a[i].$method();n++;}catch(_){}};return n;})()';
      final r = await widget.controller.evaluateJavaScript(expr);
      final result = stringKeyedMapFromValue(r?['result']);
      final n = nonNegativeIntFromValue(result['value'], fallback: 0);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status =
            AppLocalizations.of(
              context,
            )?.webReverseAnimationsBulkInvoked(method, n) ??
            '$method invoked on $n animation(s)';
      });
      await _refresh();
    } catch (e, st) {
      silentLog('web_reverse_animations_dialog', '批量操作动画：$method', e, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status =
            AppLocalizations.of(
              context,
            )?.webReverseAnimationsBulkError(method, e.toString()) ??
            '$method error: $e';
      });
    }
  }

  Future<void> _rowCommand(int handle, String method) async {
    try {
      final expr =
          '(function(){var a=window.__oh_anims&&window.__oh_anims[$handle];if(!a)return 0;try{a.$method();return 1;}catch(_){return -1;}})()';
      await widget.controller.evaluateJavaScript(expr);
    } catch (e, st) {
      silentLog('web_reverse_animations_dialog', '操作单个动画：$method', e, st);
    }
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _copyJson() async {
    final json = prettyPrintJson(
      _rows
          .map(
            (r) => {
              'handle': r.handle,
              'id': r.id,
              'animationName': r.animationName,
              'playState': r.playState,
              'currentTimeMs': r.currentTime,
              'durationMs': r.duration,
              'playbackRate': r.playbackRate,
              'iterations': r.iterations,
              'target': r.targetSelector,
            },
          )
          .toList(),
    );
    final loc = AppLocalizations.of(context);
    await copyWebReverseTextToClipboard(
      context: context,
      text: json,
      successBase: loc?.webReverseAnimationsJsonCopied ?? 'JSON copied',
      logTag: 'web_reverse_animations_dialog',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthWide,
      maxHeight: kOpenHandDialogHeightTall,
      child: Column(
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.animation_rounded,
            title: loc?.webReverseAnimationsTitle ?? 'Animations',
            subtitle:
                loc?.webReverseAnimationsSubtitle ??
                'CDP Animation.setPlaybackRate + document.getAnimations() snapshot',
            actions: [
              IconButton(
                onPressed: _rows.isEmpty ? null : _copyJson,
                icon: const Icon(Icons.copy_rounded),
                tooltip: loc?.webReverseAnimationsCopyJson ?? 'Copy JSON',
              ),
              IconButton(
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: loc?.webReverseAnimationsRefresh ?? 'Refresh',
              ),
            ],
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Text(
                  loc?.webReverseAnimationsGlobalRate ?? 'Global rate',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                kOpenHandHGap10,
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: kOpenHandBorderRadius6,
                  ),
                  child: Text(
                    '${_playbackRate.toStringAsFixed(2)}x',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                for (final preset in const <double>[0, 0.1, 0.25, 0.5, 1, 2])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _setPlaybackRate(preset),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(46, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        backgroundColor: (_playbackRate - preset).abs() < 1e-3
                            ? cs.primaryContainer
                            : null,
                      ),
                      child: Text(
                        preset == 0
                            ? (loc?.webReverseAnimationsPauseSymbol ?? 'Pause')
                            : '${preset}x',
                        style: const TextStyle(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Slider(
              value: _playbackRate.clamp(0.0, 2.0),
              max: 2.0,
              divisions: 40,
              label: '${_playbackRate.toStringAsFixed(2)}x',
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _playbackRate = v),
              onChangeEnd: _busy ? null : (v) => _setPlaybackRate(v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _bulkCommand('pause'),
                  icon: const Icon(Icons.pause_rounded, size: 16),
                  label: Text(
                    loc?.webReverseAnimationsBulkPause ?? 'Pause all',
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _bulkCommand('play'),
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: Text(
                    loc?.webReverseAnimationsBulkResume ?? 'Resume all',
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _bulkCommand('cancel'),
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: Text(
                    loc?.webReverseAnimationsBulkCancel ?? 'Cancel all',
                  ),
                ),
              ],
            ),
          ),
          OpenHandBusyProgressBar(busy: _busy),
          buildWebReverseStatusBar(context, status: _status),
          Expanded(
            child: _rows.isEmpty
                ? OpenHandInlineEmptyState(
                    message:
                        loc?.webReverseAnimationsEmptyState ??
                        'No active animations. Trigger one and refresh.',
                    dense: true,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    itemCount: _rows.length,
                    itemBuilder: (_, i) {
                      final r = _rows[i];
                      final pct = r.duration <= 0
                          ? 0.0
                          : ((r.currentTime % r.duration) / r.duration).clamp(
                              0.0,
                              1.0,
                            );
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: webReverseSurfaceCardDecoration(cs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: r.playState == 'running'
                                        ? cs.primaryContainer
                                        : r.playState == 'paused'
                                        ? cs.tertiaryContainer
                                        : cs.surfaceContainerHighest,
                                    borderRadius: kOpenHandBorderRadius4,
                                  ),
                                  child: Text(
                                    r.playState,
                                    style: TextStyle(
                                      fontFamily: kOpenHandMonospaceFontFamily,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: r.playState == 'running'
                                          ? cs.onPrimaryContainer
                                          : r.playState == 'paused'
                                          ? cs.onTertiaryContainer
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                kOpenHandHGap8,
                                Expanded(
                                  child: SelectableText(
                                    r.animationName.isNotEmpty
                                        ? r.animationName
                                        : (r.id.isNotEmpty
                                              ? r.id
                                              : '<anonymous>'),
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip:
                                      loc?.webReverseAnimationsRowPause ??
                                      'Pause',
                                  icon: const Icon(
                                    Icons.pause_rounded,
                                    size: 16,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _rowCommand(r.handle, 'pause'),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip:
                                      loc?.webReverseAnimationsRowPlay ??
                                      'Play',
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 16,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _rowCommand(r.handle, 'play'),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip:
                                      loc?.webReverseAnimationsRowCancel ??
                                      'Cancel',
                                  icon: const Icon(
                                    Icons.cancel_outlined,
                                    size: 16,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _rowCommand(r.handle, 'cancel'),
                                ),
                              ],
                            ),
                            kOpenHandGap6,
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                kOpenHandRadius3,
                              ),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 5,
                                backgroundColor: cs.surfaceContainerHighest,
                              ),
                            ),
                            kOpenHandGap6,
                            Text(
                              '${r.currentTime.toStringAsFixed(0)} / ${r.duration.toStringAsFixed(0)} ms · rate ${r.playbackRate.toStringAsFixed(2)} · iter ${r.iterations.isInfinite ? '∞' : r.iterations.toStringAsFixed(0)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            if (r.targetSelector.isNotEmpty) ...[
                              kOpenHandGap2,
                              SelectableText(
                                r.targetSelector,
                                maxLines: 1,
                                style: TextStyle(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  fontSize: 10.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          buildOpenHandDialogFooter(
            primaryLabel: loc?.webReverseAnimationsClose ?? 'Close',
            onPrimaryPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
