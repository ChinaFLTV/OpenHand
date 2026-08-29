import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/ai/model/ai_model_config.dart';
import '../util/localized_text.dart';
import 'animated_menu.dart';
import 'collision_safe_animated_switcher.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';

// ── Layout ──────────────────────────────────────────────────────────────────
const double _kReasoningPopupWidth = 300;
const double _kReasoningPopupEntryHeight = 168;
const double _kReasoningPopupEstimatedHeight = 186;
const double _kReasoningPopupGap = 8;
const double _kThumbSize = 28;
const double _kTrackHeight = 32;
const Duration _kLabelSwitchDuration = kOpenHandMotion280;

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
      Color.lerp(dark ? darkGreenLeft : greenLeft, dark ? darkBlueLeft : blueLeft, lowBlend)!,
      dark ? darkPurpleLeft : purpleLeft,
      maxBlend,
    )!;
    final deep = Color.lerp(
      Color.lerp(toneAt(greenTones, 0), toneAt(blueTones, 0), lowBlend)!,
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
  await showAnimatedMenu<String>(
    context: context,
    position: RelativeRect.fromRect(anchorRect, Offset.zero & overlayBox.size),
    constraints: BoxConstraints(minWidth: popupWidth, maxWidth: popupWidth),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    ),
    color: Colors.transparent,
    elevation: 0,
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
    final progress = (_slider100 / 100).clamp(0.0, 1.0);
    final displayIndex = _indexFromProgress(progress, widget.options.length);
    final option = widget.options[displayIndex];
    final maxBlend = _smoothstep(0.55, 1.0, progress);
    final pixelBlend = _smoothstep(0.18, 0.55, progress);
    final isMax = displayIndex == widget.options.length - 1 && widget.options.length > 1;

    final panel = Container(
      width: widget.width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: dark
              ? const Color(0x1FA855F7)
              : const Color(0x408CA0FF),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const <Color>[
                  Color(0xFF0E0A16),
                  Color(0xFF140E20),
                  Color(0xFF0C0818),
                ]
              : const <Color>[
                  Color(0xFFFBFCFF),
                  Color(0xFFF2F5FF),
                  Color(0xFFF7F4FF),
                ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: dark
                ? Colors.black.withValues(alpha: 0.45)
                : const Color(0x141A2344),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                openHandLocalizedText(context, zh: '推理强度', en: 'Effort'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: dark
                      ? const Color(0xFF8880A0)
                      : const Color(0xFF5A6180),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: openHandMotionDuration(context, _kLabelSwitchDuration),
                  switchInCurve: kOpenHandSwitchInCurve,
                  switchOutCurve: kOpenHandSwitchOutCurve,
                  layoutBuilder: buildCollisionSafeAnimatedSwitcherLayout,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.12),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    option.labelForLocaleName(localeName),
                    key: ValueKey<String>(option.value),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: 'Georgia',
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                      foreground: isMax
                          ? (Paint()
                              ..shader = ui.Gradient.linear(
                                Offset.zero,
                                const Offset(120, 0),
                                const <Color>[
                                  Color(0xFFB39AD6),
                                  Color(0xFF9D86E0),
                                  Color(0xFF8BB0FF),
                                  Color(0xFFA88FE8),
                                ],
                              ))
                          : null,
                      color: isMax
                          ? null
                          : Color.lerp(
                              const Color(0xBF58BC8A),
                              dark
                                  ? const Color(0xFFC084FC)
                                  : const Color(0xFF3B5BD8),
                              progress,
                            ),
                      shadows: maxBlend > 0.2 && !isMax
                          ? <Shadow>[
                              Shadow(
                                color: (dark
                                        ? const Color(0xFFC084FC)
                                        : const Color(0xFF3B5BD8))
                                    .withValues(alpha: 0.35 * maxBlend),
                                blurRadius: 10,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: dark
                      ? const Color(0xFF8880A0)
                      : const Color(0xFF5A6180),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                openHandLocalizedText(context, zh: '更快', en: 'Faster'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: dark
                      ? const Color(0xFF8880A0)
                      : const Color(0xFF5A6180),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                openHandLocalizedText(context, zh: '更智能', en: 'Smarter'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: dark
                      ? const Color(0xFF8880A0)
                      : const Color(0xFF5A6180),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
                      i == 0
                          ? 'OFF'
                          : i == widget.options.length - 1
                          ? 'MAX'
                          : widget.options[i].labelForLocaleName(localeName),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: i == displayIndex
                            ? (dark
                                  ? const Color(0xFFC084FC)
                                  : const Color(0xFF3B5BD8))
                            : (dark
                                  ? const Color(0xFF6A6080)
                                  : const Color(0xFF8B92AD)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                AnimatedBuilder(
                  animation: _fxClock,
                  builder: (context, _) {
                    return CustomPaint(
                      size: Size(widget.width - 22, _kTrackHeight),
                      painter: _EffortTrackPainter(
                        progress: progress,
                        divisions: math.max(1, widget.options.length - 1),
                        dark: dark,
                        pixelBlend: pixelBlend,
                        maxBlend: maxBlend,
                        timeMs: _fxClock.value * 12000,
                        reducedMotion: !openHandTickerMotionEnabled(context),
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
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
                    tickMarkShape: SliderTickMarkShape.noTickMark,
                  ),
                  child: Slider(
                    value: _slider100,
                    max: 100,
                    semanticFormatterCallback: (value) => widget
                        .options[_indexFromProgress(value / 100, widget.options.length)]
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
    );

    return SizedBox(
      width: widget.width,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? const <Color>[
                            Color(0x4DA855F7),
                            Color(0x263B82F6),
                            Color(0x33A855F7),
                          ]
                        : const <Color>[
                            Color(0x407AA2FF),
                            Color(0x1F3B82F6),
                            Color(0x2EA855F7),
                          ],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(3),
            child: panel,
          ),
        ],
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
  });

  final double progress;
  final int divisions;
  final bool dark;
  final double pixelBlend;
  final double maxBlend;
  final double timeMs;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, (size.height - _kTrackHeight) / 2, size.width, _kTrackHeight),
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
        ..color = dark
            ? const Color(0x2EA855F7)
            : const Color(0x458B93A3),
    );

    final thumbPad = _kThumbSize / 2;
    final thumbX = thumbPad + (size.width - _kThumbSize) * progress;
    final fillRight = thumbX.clamp(0.0, size.width);

    if (maxBlend > 0.02 && fillRight > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, fillRight, size.height));
      canvas.drawRRect(
        track,
        Paint()
          ..shader = LinearGradient(
            colors: _EffortPalettes.trackMaxGradient(dark: dark),
          ).createShader(track.outerRect)
          ..color = Colors.white.withValues(alpha: 0.35 + maxBlend * 0.65),
      );
      canvas.restore();
    }

    // 低档流光底色。
    if (progress > 0.01 && pixelBlend < 0.98) {
      final fillColor = _EffortPalettes.resolveFill(progress, dark: dark);
      final streamRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          track.left,
          track.top,
          fillRight,
          track.bottom,
        ),
        const Radius.circular(10),
      );
      canvas.save();
      canvas.clipRRect(track);
      canvas.drawRRect(
        streamRect,
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[
              fillColor.withValues(alpha: 0.15),
              fillColor.withValues(alpha: 0.55 + progress * 0.25),
            ],
          ).createShader(streamRect.outerRect)
          ..color = Colors.white.withValues(alpha: 1 - pixelBlend),
      );
      if (!reducedMotion) {
        _paintStreamSparks(canvas, size, fillRight, fillColor);
      }
      canvas.restore();
    }

    if (pixelBlend > 0.01) {
      canvas.saveLayer(
        track.outerRect,
        Paint()..color = Colors.white.withValues(alpha: pixelBlend),
      );
      canvas.clipRRect(track);
      _paintPixelField(canvas, size, fillRight);
      canvas.restore();
    }

    if (pixelBlend < 0.95) {
      for (var i = 0; i <= divisions; i++) {
        final t = i / math.max(1, divisions);
        final x = thumbPad + (size.width - _kThumbSize) * t;
        final active = t <= progress + 0.001;
        canvas.drawCircle(
          Offset(x, size.height / 2),
          2,
          Paint()
            ..color = (active
                    ? (dark ? const Color(0xFFC084FC) : const Color(0xFF3B5BD8))
                    : (dark ? const Color(0x4DA855F7) : const Color(0x333B5BD8)))
                .withValues(alpha: (1 - pixelBlend) * (active ? 1 : 0.7)),
        );
      }
    }

    // Thumb
    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(thumbX, size.height / 2),
        width: _kThumbSize,
        height: _kThumbSize,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      thumbRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const <Color>[
                  Color(0xFFF4EEFB),
                  Color(0xFFDCCFEE),
                  Color(0xFFCBB8E6),
                ]
              : const <Color>[
                  Color(0xFFFFFFFF),
                  Color(0xFFE8ECFA),
                  Color(0xFFD8DEF4),
                ],
        ).createShader(thumbRect.outerRect),
    );
    canvas.drawRRect(
      thumbRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = dark
            ? const Color(0x26A855F7)
            : const Color(0x263B5BD8),
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

  void _paintPixelField(Canvas canvas, Size size, double fillRight) {
    final cell = size.width < 280 ? 5.0 : 6.0;
    final gap = 0.2 + 0.9 * maxBlend;
    final maskFrac = (fillRight / size.width).clamp(0.0, 1.0);
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
        if (nX > maskFrac) continue;
        final revealAlpha = _smoothstep(frontier - 0.1 * maskFrac, frontier + 0.07 * maskFrac, nX);
        if (revealAlpha <= 0.002) continue;

        final base = (math.sin(column * 12.9898 + row * 78.233) * 43758.5453).abs() % 1;
        final tempo = (math.sin(column * 7.13 + row * 19.41) * 19341.731).abs() % 1;
        final phase = (math.sin(column * 31.17 + row * 11.93) * 28437.123).abs() % 1;
        final period = 500 + tempo * 1500;
        final localTime = elapsed + phase * period;
        final cycle = (localTime / period).floor();
        final cycleProgress = (localTime % period) / period;
        final cycleHash =
            (math.sin(column * 17.17 + row * 41.73 + cycle * 13.11) * 24634.6345).abs() % 1;
        final pulseCenter = 0.2 + cycleHash * 0.55;
        final pulseWidth = 0.12;
        final pulseDistance = (cycleProgress - pulseCenter) / pulseWidth;
        final flicker = math.exp(-pulseDistance * pulseDistance * 1.45) * (cycleHash > 0.12 ? 1 : 0.26);
        final wave = math.pow(0.5 + 0.5 * math.cos((nX + flow + row * 0.06) * math.pi * 2), 5).toDouble();
        final light = math.max(flicker * 0.7, wave * 0.45);

        final green = _EffortPalettes.toneAt(_EffortPalettes.greenTones, nX);
        final blue = _EffortPalettes.toneAt(_EffortPalettes.blueTones, nX);
        final purple = _EffortPalettes.toneAt(_EffortPalettes.purpleTones, nX);
        final color = Color.lerp(
          Color.lerp(green, blue, lowBlend)!,
          purple,
          maxBlend,
        )!;
        final highlight = Color.lerp(color, Colors.white, light * 0.55)!;
        final alpha = revealAlpha * _mix(0.82, 0.7 + base * 0.2, maxBlend) * (0.75 + light * 0.25);
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
        reducedMotion != oldDelegate.reducedMotion;
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
