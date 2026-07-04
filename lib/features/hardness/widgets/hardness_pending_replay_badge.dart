import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/ui/oh_pill.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/timer_safety.dart';

/// Hardness header 内的 ToolSearch 重放反悔 chip：监听
/// `ToolSearchReplayDispatcher.pendingDeadlineListenable`，window 内每秒
/// 重建一次显示剩余秒数（向上取整），idle 时折叠不显示。
///
/// 抽到 widgets 以便测试与（潜在的）跨面板复用。
class HardnessPendingReplayBadge extends StatefulWidget {
  const HardnessPendingReplayBadge({
    super.key,
    required this.isZh,
    required this.deadlineListenable,
    this.onCancel,
    this.tickInterval = const Duration(milliseconds: 250),
    this.nowProvider,
  });

  final bool isZh;
  final ValueListenable<DateTime?> deadlineListenable;
  final VoidCallback? onCancel;

  /// Tick refresh granularity. Default 250 ms gives sub-second redraw smoothness
  /// while remaining cheap. Tests override this to drive timing deterministically.
  final Duration tickInterval;

  /// Override "now" for tests. Defaults to `DateTime.now`.
  final DateTime Function()? nowProvider;

  @override
  State<HardnessPendingReplayBadge> createState() =>
      _HardnessPendingReplayBadgeState();
}

class _HardnessPendingReplayBadgeState
    extends State<HardnessPendingReplayBadge> {
  Timer? _ticker;

  DateTime _now() => (widget.nowProvider ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.deadlineListenable.addListener(_onDeadlineChanged);
    _onDeadlineChanged();
  }

  @override
  void didUpdateWidget(covariant HardnessPendingReplayBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadlineListenable != widget.deadlineListenable) {
      oldWidget.deadlineListenable.removeListener(_onDeadlineChanged);
      widget.deadlineListenable.addListener(_onDeadlineChanged);
      _onDeadlineChanged();
    }
  }

  @override
  void dispose() {
    widget.deadlineListenable.removeListener(_onDeadlineChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _onDeadlineChanged() {
    final dl = widget.deadlineListenable.value;
    _ticker?.cancel();
    if (dl == null) {
      _ticker = null;
    } else {
      _ticker = startSafePeriodicTimer(
        widget.tickInterval,
        (_) {
          if (!mounted) return;
          if (widget.deadlineListenable.value == null) {
            _ticker?.cancel();
            _ticker = null;
          }
          setState(() {});
        },
        min: const Duration(milliseconds: 16),
        max: const Duration(minutes: 1),
      );
    }
    if (mounted) setState(() {});
  }

  int? _remainingSeconds() {
    final dl = widget.deadlineListenable.value;
    if (dl == null) return null;
    final ms = dl.difference(_now()).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final secs = _remainingSeconds();
    if (secs == null) return const SizedBox.shrink();
    final label = openHandLocalizedText(
      context,
      zh: '撤销 ${secs}s',
      zhHant: '撤銷 ${secs}s',
      en: 'Cancel ${secs}s',
      fr: 'Annuler ${secs}s',
      de: 'Abbrechen ${secs}s',
      ja: '取り消し ${secs}s',
    );
    return OhPill(
      icon: Icons.history_toggle_off_rounded,
      label: label,
      foregroundColor: const Color(0xFFF57F17), // amber
      onTap: widget.onCancel,
    );
  }
}
