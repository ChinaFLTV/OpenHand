import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/ai/model/ai_model_config.dart';
import '../util/localized_text.dart';
import 'animated_menu.dart';
import 'collision_safe_animated_switcher.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_spacing.dart';

// ── Layout ──────────────────────────────────────────────────────────────────
const double _kReasoningPopupWidth = 300;
const double _kReasoningPopupEntryHeight = 142;
const double _kReasoningPopupEstimatedHeight = 158;
const double _kReasoningPopupGap = 8;
const double _kThumbSize = 22;
const double _kTrackHeight = 32;
const Duration _kLabelSwitchDuration = kOpenHandMotion280;
/// 末档判定：进度或紫段混合足够高时视为满轨。
const double _kMaxTierProgress = 0.995;
const double _kMaxTierBlend = 0.9;
/// 非末档：主岸线左侧开始碎裂 / 右侧飞沫漫出（贴拇指，避免过渡带过宽）。
const double _kTideSoftLead = 0.09;
const double _kTideSoftSpill = 0.055;
const double _kTideWaveAmp = 0.055;
const double _kTideSprayAmp = 0.032;
const double _kTideFoamAmp = 0.018;
/// 底轨/流光比像素潮汐略宽收束，避免矩形软切抢戏。
const double _kTideUnderlaySoft = 0.13;

/// 潮汐前沿占位：起伏岸线 + 随机空洞/飞沫（与 Web effortTidePresence 对齐）。
double _effortTidePresence({
  required double nX,
  required double maskFrac,
  required bool isMaxTier,
  required int row,
  required int column,
  required double base,
  required double phase,
  required double elapsed,
}) {
  if (isMaxTier) return 1;
  final tide = math.sin(nX * 21 + row * 2.15 + elapsed * 0.0017 + base * 6.283);
  final spray = math.sin(
    column * 2.61 + row * 5.07 + elapsed * 0.0026 + phase * math.pi * 2,
  );
  final foam = math.sin(
    column * 9.17 + row * 1.41 + base * 13.7 + elapsed * 0.0011,
  );
  final shore = maskFrac -
      _kTideSoftLead +
      tide * _kTideWaveAmp +
      spray * _kTideSprayAmp +
      foam * _kTideFoamAmp;
  const span = _kTideSoftLead + _kTideSoftSpill;
  final t = (nX - shore) / span;
  if (t <= 0) return 1;
  if (t >= 1.2) return 0;
  // 前半仍较实，后段才急速碎裂成飞沫，过渡带紧凑贴拇指。
  final density = math.pow(1 - t.clamp(0.0, 1.0), 2.35).toDouble();
  final gate =
      base * 0.52 + phase * 0.33 + ((column * 17 + row * 31) % 97) / 97 * 0.15;
  if (t < 0.28) return (0.82 + density * 0.18).clamp(0.08, 1.0);
  if (gate > density * 0.98) return 0;
  if (t > 0.52 && gate > density * 0.58) return 0;
  if (t > 0.78 && gate > density * 0.34) return 0;
  return (density * (0.55 + 0.45 * (0.5 + 0.5 * tide))).clamp(0.08, 1.0);
}

/// Codex 风格色板：Low 绿 → High 蓝 → MAX 紫（派生自 dsh-effort-slider）。
abstract final class _EffortPalettes {
  static const List<Color> greenTones = <Color>[
    Color(0xFF2EA86C),
    Color(0xFF40B27A),
    Color(0xFF58BC8A),
    Color(0xFF74C69A),
    Color(0xFF96D2AE),
  ];
  static const List<Color> blueTones = <Color>[
    Color(0xFF487EEE),
    Color(0xFF568AF0),
    Color(0xFF6898F2),
    Color(0xFF7CA6F3),
    Color(0xFF92B6F4),
  ];
  static const List<Color> purpleTones = <Color>[
    Color(0xFF9660CD),
    Color(0xFF9C76C8),
    Color(0xFFA68CCE),
    Color(0xFFAA9ACE),
    Color(0xFFB6A8CE),
  ];
  static const Color greenLeft = Color(0xFFD6E0D4);
  static const Color blueLeft = Color(0xFFD4DAE2);
  static const Color purpleLeft = Color(0xFFD2CED6);
  static const Color darkGreenLeft = Color(0xFF16261C);
  static const Color darkBlueLeft = Color(0xFF1A182C);
  static const Color darkPurpleLeft = Color(0xFF181328);

  static Color toneAt(List<Color> tones, double t) {
    final clamped = t.clamp(0.0, 0.999);
    final scaled = clamped * (tones.length - 1);
    final i = scaled.floor();
    return Color.lerp(tones[i], tones[math.min(i + 1, tones.length - 1)], scaled - i)!;
  }

  static Color resolveFill(double progress, {required bool dark}) {
    final lowBlend = _smoothstep(0.0, 0.55, progress);
    final maxBlend = _smoothstep(0.55, 1.0, progress);
    final left = Color.lerp(
      Color.lerp(dark ? darkGreenLeft : greenLeft, dark ? darkBlueLeft : blueLeft, lowBlend),
      dark ? darkPurpleLeft : purpleLeft,
      maxBlend,
    )!;
    final deep = Color.lerp(
      Color.lerp(toneAt(greenTones, 0), toneAt(blueTones, 0), lowBlend),
      toneAt(purpleTones, 0),
      maxBlend,
    )!;
    return Color.lerp(left, deep, 0.72)!;
  }

  static List<Color> trackMaxGradient({required bool dark}) {
    if (dark) {
      return const <Color>[
        Color(0xFF181228),
        Color(0xFF2E2056),
        Color(0xFF54389C),
        Color(0xFF8F63CD),
      ];
    }
    return const <Color>[
      Color(0xFFEEEBE9),
      Color(0xFFD8C9EC),
      Color(0xFFB08DDC),
      Color(0xFF8F63CD),
    ];
  }
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _mix(double a, double b, double t) => a + (b - a) * t;

int _indexFromProgress(double progress, int count) {
  if (count <= 1) return 0;
  return (progress * (count - 1)).round().clamp(0, count - 1);
}

double _progressFromIndex(int index, int count) {
  if (count <= 1) return 1;
  return index / (count - 1);
}

/// 档位刻度标签：首档/末档走本地化，中间档用模型自带多语言标签。
String _effortTickLabel(
  BuildContext context, {
  required List<AiReasoningEffortOption> options,
  required int index,
  required String localeName,
}) {
  if (index <= 0) {
    return openHandLocalizedText(
      context,
      zh: '关闭',
      en: 'Off',
      zhHant: '關閉',
      ja: 'オフ',
      fr: 'Off',
      de: 'Aus',
    );
  }
  if (index >= options.length - 1) {
    return openHandLocalizedText(
      context,
      zh: '最大',
      en: 'Max',
      zhHant: '最大',
      ja: '最大',
      fr: 'Max',
      de: 'Max',
    );
  }
  return options[index].labelForLocaleName(localeName);
}

/// 在 [anchorContext] 上方打开推理强度选择器，动效遵循全局菜单设置。
Future<void> showReasoningEffortSelector({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<AiReasoningEffortOption> options,
  required String? currentValue,
  required Future<bool> Function(String effort) onChanged,
}) async {
  final selectable = options
      .where((option) => option.isSelectable)
      .toList(growable: false);
  if (selectable.isEmpty) return;
  final anchorBox = anchorContext.findRenderObject();
  final overlayBox = Overlay.maybeOf(anchorContext)?.context.findRenderObject();
  if (anchorBox is! RenderBox ||
      overlayBox is! RenderBox ||
      !anchorBox.hasSize ||
      !overlayBox.hasSize) {
    return;
  }
  final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  final popupTop = math.max(
    8,
    topLeft.dy - _kReasoningPopupEstimatedHeight - _kReasoningPopupGap,
  );
  final anchorRect = Rect.fromLTWH(
    topLeft.dx,
    popupTop.toDouble(),
    anchorBox.size.width,
    0,
  );
  final popupWidth = math
      .min(_kReasoningPopupWidth, math.max(112, overlayBox.size.width - 16))
      .toDouble();
  final colors = Theme.of(context).colorScheme;
  await showAnimatedMenu<String>(
    context: context,
    position: RelativeRect.fromRect(anchorRect, Offset.zero & overlayBox.size),
    constraints: BoxConstraints(minWidth: popupWidth, maxWidth: popupWidth),
    shape: RoundedRectangleBorder(
      borderRadius: kOpenHandBorderRadius16,
      side: BorderSide(
        color: colors.outline.withValues(alpha: 0.55),
      ),
    ),
    color: colors.surfaceContainer,
    items: <PopupMenuEntry<String>>[
      _ReasoningEffortPopupEntry(
        width: popupWidth,
        options: selectable,
        currentValue: currentValue,
        onChanged: onChanged,
      ),
    ],
  );
}

class _ReasoningEffortPopupEntry extends PopupMenuEntry<String> {
  const _ReasoningEffortPopupEntry({
    required this.width,
    required this.options,
    required this.currentValue,
    required this.onChanged,
  });

  final double width;
  final List<AiReasoningEffortOption> options;
  final String? currentValue;
  final Future<bool> Function(String effort) onChanged;

  @override
  double get height => _kReasoningPopupEntryHeight;

  @override
  bool represents(String? value) => false;

  @override
  State<_ReasoningEffortPopupEntry> createState() =>
      _ReasoningEffortPopupEntryState();
}

class _ReasoningEffortPopupEntryState extends State<_ReasoningEffortPopupEntry>
    with SingleTickerProviderStateMixin {
  late double _slider100;
  late String _persistedValue;
  String? _pendingValue;
  bool _saving = false;
  int _lastHapticIndex = -1;
  late final AnimationController _fxClock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void initState() {
    super.initState();
    final normalizedCurrent = widget.currentValue?.trim().toLowerCase();
    final resolved = widget.options.indexWhere(
      (option) => option.value.toLowerCase() == normalizedCurrent,
    );
    final index = resolved < 0 ? widget.options.length ~/ 2 : resolved;
    _slider100 = _progressFromIndex(index, widget.options.length) * 100;
    _persistedValue = widget.options[index].value;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFx();
  }

  @override
  void dispose() {
    _fxClock.dispose();
    super.dispose();
  }

  void _syncFx() {
    final progress = (_slider100 / 100).clamp(0.0, 1.0);
    final want =
        progress > 0.02 && openHandTickerMotionEnabled(context);
    if (want) {
      if (!_fxClock.isAnimating) _fxClock.repeat();
      return;
    }
    _fxClock
      ..stop()
      ..value = 0;
  }

  void _selectRaw(double value) {
    final next = value.clamp(0.0, 100.0);
    if ((next - _slider100).abs() < 0.01) return;
    final nextIndex = _indexFromProgress(next / 100, widget.options.length);
    setState(() => _slider100 = next);
    _syncFx();
    if (nextIndex != _lastHapticIndex) {
      _lastHapticIndex = nextIndex;
      HapticFeedback.selectionClick();
    }
  }

  void _commit(double value) {
    final nextIndex = _indexFromProgress(value / 100, widget.options.length);
    final snapped = _progressFromIndex(nextIndex, widget.options.length) * 100;
    final effort = widget.options[nextIndex].value;
    setState(() => _slider100 = snapped);
    _lastHapticIndex = nextIndex;
    _syncFx();
    if (!_saving && effort.toLowerCase() == _persistedValue.toLowerCase()) {
      return;
    }
    if (_pendingValue?.toLowerCase() == effort.toLowerCase()) return;
    _pendingValue = effort;
    if (_saving) return;
    _saving = true;
    unawaited(_drainPendingChanges());
  }

  Future<void> _drainPendingChanges() async {
    try {
      while (_pendingValue != null) {
        final effort = _pendingValue!;
        _pendingValue = null;
        var saved = false;
        try {
          saved = await widget.onChanged(effort);
        } catch (_) {
          // 错误提示由调用方负责，此处仅回滚到最近一次持久化值。
        }
        if (saved) {
          _persistedValue = effort;
          continue;
        }
        if (_pendingValue == null && mounted) {
          final persistedIndex = widget.options.indexWhere(
            (option) =>
                option.value.toLowerCase() == _persistedValue.toLowerCase(),
          );
          if (persistedIndex >= 0) {
            setState(() {
              _slider100 =
                  _progressFromIndex(persistedIndex, widget.options.length) *
                  100;
            });
          }
        }
      }
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final localeName = Localizations.localeOf(context).toLanguageTag();
    if (widget.options.isEmpty) {
      return SizedBox(width: widget.width, height: _kReasoningPopupEntryHeight);
    }
    final progress = (_slider100 / 100).clamp(0.0, 1.0);
    final displayIndex = _indexFromProgress(progress, widget.options.length)
        .clamp(0, widget.options.length - 1);
    final option = widget.options[displayIndex];
    final maxBlend = _smoothstep(0.55, 1.0, progress);
    final pixelBlend = _smoothstep(0.18, 0.55, progress);
    final axisStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    final statusColor = Color.lerp(
      colorScheme.onSurfaceVariant,
      Color.lerp(
        const Color(0xFF2EA86C),
        Color.lerp(
          const Color(0xFF3B5BD8),
          const Color(0xFF9660CD),
          maxBlend,
        ),
        _smoothstep(0.0, 0.7, progress),
      ),
      0.82,
    );

    return SizedBox(
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      openHandLocalizedText(
                        context,
                        zh: '更快',
                        en: 'Faster',
                        zhHant: '更快',
                        ja: '高速',
                        fr: 'Plus rapide',
                        de: 'Schneller',
                      ),
                      style: axisStyle,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: openHandMotionDuration(
                        context,
                        _kLabelSwitchDuration,
                      ),
                      switchInCurve: kOpenHandSwitchInCurve,
                      switchOutCurve: kOpenHandSwitchOutCurve,
                      layoutBuilder: buildCollisionSafeAnimatedSwitcherLayout,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.1),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        option.labelForLocaleName(localeName),
                        key: ValueKey<String>(option.value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: axisStyle?.copyWith(color: statusColor),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      openHandLocalizedText(
                        context,
                        zh: '更智能',
                        en: 'Smarter',
                        zhHant: '更智慧',
                        ja: '高精度',
                        fr: 'Plus intelligent',
                        de: 'Intelligenter',
                      ),
                      style: axisStyle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 16,
              child: Stack(
                children: <Widget>[
                  for (var i = 0; i < widget.options.length; i++)
                    Align(
                      alignment: Alignment(
                        -1 + 2 * (i / math.max(1, widget.options.length - 1)),
                        0,
                      ),
                      child: Text(
                        _effortTickLabel(
                          context,
                          options: widget.options,
                          index: i,
                          localeName: localeName,
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: i == displayIndex
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.62,
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: <Widget>[
                  AnimatedBuilder(
                    animation: _fxClock,
                    builder: (context, _) {
                      return CustomPaint(
                        size: Size(widget.width - 28, _kTrackHeight + 8),
                        painter: _EffortTrackPainter(
                          progress: progress,
                          divisions: math.max(1, widget.options.length - 1),
                          dark: dark,
                          pixelBlend: pixelBlend,
                          maxBlend: maxBlend,
                          timeMs: _fxClock.value * 12000,
                          reducedMotion: !openHandTickerMotionEnabled(context),
                          outlineColor: colorScheme.outlineVariant,
                        ),
                      );
                    },
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 0,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: Colors.transparent,
                      overlayColor: Colors.transparent,
                      thumbShape: const _InvisibleThumb(size: _kThumbSize),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 0,
                      ),
                      tickMarkShape: SliderTickMarkShape.noTickMark,
                    ),
                    child: Slider(
                      value: _slider100,
                      max: 100,
                      semanticFormatterCallback: (value) => widget
                          .options[_indexFromProgress(
                            value / 100,
                            widget.options.length,
                          )]
                          .labelForLocaleName(localeName),
                      onChanged: _selectRaw,
                      onChangeEnd: _commit,
                    ),
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

class _EffortTrackPainter extends CustomPainter {
  _EffortTrackPainter({
    required this.progress,
    required this.divisions,
    required this.dark,
    required this.pixelBlend,
    required this.maxBlend,
    required this.timeMs,
    required this.reducedMotion,
    required this.outlineColor,
  });

  final double progress;
  final int divisions;
  final bool dark;
  final double pixelBlend;
  final double maxBlend;
  final double timeMs;
  final bool reducedMotion;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final trackTop = (size.height - _kTrackHeight) / 2;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackTop, size.width, _kTrackHeight),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      track,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const <Color>[Color(0xFF1C1428), Color(0xFF110B1C)]
              : const <Color>[Color(0xFFE6E8EC), Color(0xFFD5D8DE)],
        ).createShader(track.outerRect),
    );
    canvas.drawRRect(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outlineColor.withValues(alpha: 0.72),
    );

    const thumbPad = _kThumbSize / 2;
    final thumbX = thumbPad + (size.width - _kThumbSize) * progress;
    final isMaxTier =
        progress >= _kMaxTierProgress || maxBlend >= _kMaxTierBlend;
    // 末档满轨；非末档填到拇指，再由潮水柔边自然漫过交界。
    final fillRight = isMaxTier ? size.width : thumbX.clamp(0.0, size.width);
    final accent = _EffortPalettes.resolveFill(progress, dark: dark);
    final cy = size.height / 2;

    if (maxBlend > 0.02 && fillRight > 0) {
      canvas.save();
      canvas.clipRRect(track);
      // 非末档底轨提前收束，把交界留给像素潮汐碎裂。
      final maxEnd = isMaxTier
          ? size.width
          : math.max(0.0, fillRight - size.width * _kTideUnderlaySoft * 0.35);
      if (maxEnd > 1) {
        canvas.drawRect(
          Rect.fromLTRB(0, trackTop, maxEnd, trackTop + _kTrackHeight),
          Paint()
            ..shader = LinearGradient(
              colors: <Color>[
                ..._EffortPalettes.trackMaxGradient(dark: dark).map(
                  (c) => c.withValues(alpha: 0.35 + maxBlend * 0.65),
                ),
                if (!isMaxTier) const Color(0x00000000),
              ],
              stops: isMaxTier
                  ? null
                  : const <double>[0, 0.28, 0.52, 0.74, 1],
            ).createShader(
              Rect.fromLTRB(0, trackTop, maxEnd, trackTop + _kTrackHeight),
            ),
        );
      }
      canvas.restore();
    }

    if (progress > 0.01 && pixelBlend < 0.98) {
      canvas.save();
      canvas.clipRRect(track);
      final streamEnd = isMaxTier
          ? size.width
          : math.max(0.0, fillRight - size.width * 0.02);
      canvas.drawRect(
        Rect.fromLTRB(0, trackTop, streamEnd, trackTop + _kTrackHeight),
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[
              accent.withValues(alpha: 0.14),
              accent.withValues(alpha: 0.52 + progress * 0.28),
              accent.withValues(alpha: isMaxTier ? 0.42 : 0.12),
              if (!isMaxTier) accent.withValues(alpha: 0),
            ],
            stops: isMaxTier
                ? const <double>[0, 0.55, 1]
                : const <double>[0, 0.48, 0.78, 1],
          ).createShader(
            Rect.fromLTRB(0, trackTop, streamEnd, trackTop + _kTrackHeight),
          )
          ..color = Colors.white.withValues(alpha: 1 - pixelBlend),
      );
      if (!reducedMotion) {
        _paintStreamSparks(canvas, size, fillRight, accent);
      }
      canvas.restore();
    }

    if (pixelBlend > 0.01) {
      canvas.save();
      canvas.clipRRect(track);
      _paintPixelField(
        canvas,
        size,
        maskFrac: isMaxTier ? 1 : (thumbX / size.width).clamp(0.0, 1.0),
        isMaxTier: isMaxTier,
      );
      canvas.restore();
    }

    if (pixelBlend < 0.95) {
      for (var i = 0; i <= divisions; i++) {
        final t = i / math.max(1, divisions);
        final x = thumbPad + (size.width - _kThumbSize) * t;
        final active = t <= progress + 0.001;
        canvas.drawCircle(
          Offset(x, cy),
          2,
          Paint()
            ..color = (active ? accent : outlineColor).withValues(
              alpha: (1 - pixelBlend) * (active ? 0.9 : 0.45),
            ),
        );
      }
    }

    // 圆形毛玻璃拇指：光晕随色轨染色，避免白块硬切特效区。
    canvas.drawCircle(
      Offset(thumbX, cy),
      16,
      Paint()
        ..color = accent.withValues(alpha: 0.2 + maxBlend * 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(
      Offset(thumbX, cy),
      _kThumbSize / 2,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Color.lerp(Colors.white, accent, 0.12)!,
            Color.lerp(
              dark ? const Color(0xFFE8E0F4) : const Color(0xFFF4F6FC),
              accent,
              0.28,
            )!,
          ],
        ).createShader(
          Rect.fromCircle(center: Offset(thumbX, cy), radius: _kThumbSize / 2),
        ),
    );
    canvas.drawCircle(
      Offset(thumbX, cy),
      _kThumbSize / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = accent.withValues(alpha: 0.48 + maxBlend * 0.2),
    );
    canvas.drawCircle(
      Offset(thumbX - 2.2, cy - 2.4),
      3.2,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  void _paintStreamSparks(Canvas canvas, Size size, double fillRight, Color accent) {
    final t = timeMs / 1000;
    final cy = size.height / 2;
    for (var i = 0; i < 14; i++) {
      final seed = i * 17.13;
      final spd = 0.35 + (seed * 0.13) % 0.55;
      final loop = (t * spd * 0.28 + seed) % 1;
      final head = progress * math.pow(loop, 0.45);
      final x = head * fillRight;
      final y = cy + math.sin(seed + t * 2.1) * (size.height * 0.22);
      final twinkle = 0.45 + 0.55 * math.sin(t * (3 + seed % 2) + seed);
      canvas.drawCircle(
        Offset(x, y),
        1.2 + (seed % 1.4),
        Paint()..color = accent.withValues(alpha: 0.35 + twinkle * 0.4),
      );
    }
  }

  void _paintPixelField(
    Canvas canvas,
    Size size, {
    required double maskFrac,
    required bool isMaxTier,
  }) {
    final cell = size.width < 280 ? 5.0 : 6.0;
    final gap = 0.2 + 0.9 * maxBlend;
    final elapsed = reducedMotion ? 0.0 : timeMs;
    final reveal = reducedMotion ? 1.0 : _smoothstep(0, 1, elapsed / 1000);
    final frontier = maskFrac * (1 - reveal);
    final lowBlend = _smoothstep(0.0, 0.55, progress);
    final columns = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    final flow = reducedMotion ? 0.0 : elapsed / 4000;

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final x = column * cell;
        final y = row * cell;
        final nX = (x + cell * 0.5) / size.width;
        final base = (math.sin(column * 12.9898 + row * 78.233) * 43758.5453).abs() % 1;
        final phase = (math.sin(column * 31.17 + row * 11.93) * 28437.123).abs() % 1;
        final tidePresence = _effortTidePresence(
          nX: nX,
          maskFrac: maskFrac,
          isMaxTier: isMaxTier,
          row: row,
          column: column,
          base: base,
          phase: phase,
          elapsed: elapsed,
        );
        if (tidePresence <= 0.02) continue;

        final revealAlpha = _smoothstep(
          frontier - 0.1 * maskFrac,
          frontier + 0.07 * maskFrac,
          nX,
        );
        if (revealAlpha <= 0.002) continue;

        final tempo = (math.sin(column * 7.13 + row * 19.41) * 19341.731).abs() % 1;
        final period = 500 + tempo * 1500;
        final localTime = elapsed + phase * period;
        final cycle = (localTime / period).floor();
        final cycleProgress = (localTime % period) / period;
        final cycleHash =
            (math.sin(column * 17.17 + row * 41.73 + cycle * 13.11) * 24634.6345).abs() % 1;
        final pulseCenter = 0.2 + cycleHash * 0.55;
        const pulseWidth = 0.12;
        final pulseDistance = (cycleProgress - pulseCenter) / pulseWidth;
        final flicker = math.exp(-pulseDistance * pulseDistance * 1.45) * (cycleHash > 0.12 ? 1 : 0.26);
        final wave = math.pow(0.5 + 0.5 * math.cos((nX + flow + row * 0.06) * math.pi * 2), 5).toDouble();
        final light = math.max(flicker * 0.7, wave * 0.45);

        final green = _EffortPalettes.toneAt(_EffortPalettes.greenTones, nX);
        final blue = _EffortPalettes.toneAt(_EffortPalettes.blueTones, nX);
        final purple = _EffortPalettes.toneAt(_EffortPalettes.purpleTones, nX);
        final color = Color.lerp(
          Color.lerp(green, blue, lowBlend),
          purple,
          maxBlend,
        )!;
        final highlight = Color.lerp(color, Colors.white, light * 0.55)!;
        final alpha = revealAlpha *
            tidePresence *
            _mix(0.82, 0.7 + base * 0.2, maxBlend) *
            (0.75 + light * 0.25);
        if (alpha < 0.02) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + gap * 0.5, y + gap * 0.5, cell - gap, cell - gap),
            const Radius.circular(1.2),
          ),
          Paint()..color = highlight.withValues(alpha: alpha.clamp(0.0, 1.0)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EffortTrackPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        divisions != oldDelegate.divisions ||
        dark != oldDelegate.dark ||
        pixelBlend != oldDelegate.pixelBlend ||
        maxBlend != oldDelegate.maxBlend ||
        timeMs != oldDelegate.timeMs ||
        reducedMotion != oldDelegate.reducedMotion ||
        outlineColor != oldDelegate.outlineColor;
  }
}

class _InvisibleThumb extends SliderComponentShape {
  const _InvisibleThumb({required this.size});

  final double size;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.square(size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {}
}
