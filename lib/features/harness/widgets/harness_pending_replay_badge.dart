import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/ui/oh_pill.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/timer_safety.dart';

/// Harness 顶栏的 ToolSearch 重放撤销入口，按截止时间刷新剩余秒数。
class HarnessPendingReplayBadge extends StatefulWidget {
  const HarnessPendingReplayBadge({
    super.key,
    required this.isZh,
    required this.deadlineListenable,
    this.onCancel,
  });

  final bool isZh;
  final ValueListenable<DateTime?> deadlineListenable;
  final VoidCallback? onCancel;

  @override
  State<HarnessPendingReplayBadge> createState() =>
      _HarnessPendingReplayBadgeState();
}

class _HarnessPendingReplayBadgeState extends State<HarnessPendingReplayBadge> {
  static const Duration _tickInterval = Duration(milliseconds: 250);

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.deadlineListenable.addListener(_onDeadlineChanged);
    _onDeadlineChanged();
  }

  @override
  void didUpdateWidget(covariant HarnessPendingReplayBadge oldWidget) {
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
        _tickInterval,
        (_) {
          if (!mounted) return;
          if (widget.deadlineListenable.value == null) {
            _ticker?.cancel();
            _ticker = null;
          }
          setState(() {});
        },
        min: kOpenHandFramePeriodicTimerInterval,
        max: const Duration(minutes: 1),
      );
    }
    if (mounted) setState(() {});
  }

  int? _remainingSeconds() {
    final dl = widget.deadlineListenable.value;
    if (dl == null) return null;
    final ms = dl.difference(DateTime.now()).inMilliseconds;
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
