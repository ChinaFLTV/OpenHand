import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../util/timer_safety.dart';
import 'animated_dialog.dart';
import 'bounded_animation.dart';
import 'motion_preference.dart';

/// 按稳定标识保留退场行；数据可立即更新，视图在动画结束后释放。
class OpenHandAnimatedSliverList extends StatefulWidget {
  const OpenHandAnimatedSliverList({
    super.key,
    required this.children,
    required this.settings,
  });

  final List<Widget> children;
  final DialogAnimationSettings settings;

  @override
  State<OpenHandAnimatedSliverList> createState() =>
      _OpenHandAnimatedSliverListState();
}

class _OpenHandAnimatedSliverListState
    extends State<OpenHandAnimatedSliverList> {
  late List<_ListEntry> _entries = [
    for (final child in widget.children)
      _ListEntry(child, entering: true, expand: false),
  ];
  bool _reordering = false;

  @override
  void didUpdateWidget(covariant OpenHandAnimatedSliverList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = {for (final entry in _entries) entry.child.key!: entry};
    final nextKeys = widget.children.map((child) => child.key!).toSet();
    assert(nextKeys.length == widget.children.length);
    _reordering =
        nextKeys.length == previous.length &&
        nextKeys.containsAll(previous.keys) &&
        _entries.every((entry) => entry.present);
    final next = <_ListEntry>[];
    for (final child in widget.children) {
      final entry = previous[child.key] ?? _ListEntry(child, entering: true);
      entry.removal?.cancel();
      entry
        ..removal = null
        ..child = child
        ..present = true;
      next.add(entry);
    }
    for (var index = 0; index < _entries.length; index++) {
      final entry = _entries[index];
      if (nextKeys.contains(entry.child.key)) continue;
      entry.present = false;
      final duration = widget.settings.exitDuration;
      if (duration == Duration.zero) {
        entry.removal?.cancel();
        continue;
      }
      next.insert(index.clamp(0, next.length), entry);
      if (oldWidget.settings.exitDuration != duration) {
        entry.removal?.cancel();
        entry.removal = null;
      }
      if (entry.removal == null) {
        // 从首个退场帧计时，离屏行也能按时释放，不依赖是否参与绘制。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              entry.present ||
              entry.removal != null ||
              !_entries.contains(entry)) {
            return;
          }
          entry.removal = startSafeTimer(widget.settings.exitDuration, () {
            if (!mounted || entry.present) return;
            setState(() => _entries.remove(entry));
          });
        });
      }
    }
    _entries = next;
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.removal?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final indices = {
      for (var i = 0; i < _entries.length; i++) _entries[i].child.key!: i,
    };
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final entry = _entries[index];
          final entering = entry.entering;
          entry.entering = false;
          return _AnimatedListRow(
            key: entry.child.key,
            present: entry.present,
            entering: entering,
            expand: entry.expand,
            index: index,
            reordering: _reordering,
            settings: widget.settings,
            child: entry.child,
          );
        },
        childCount: _entries.length,
        findChildIndexCallback: (key) => indices[key],
      ),
    );
  }
}

class _ListEntry {
  _ListEntry(this.child, {required this.entering, this.expand = true});

  Widget child;
  bool entering;
  final bool expand;
  bool present = true;
  Timer? removal;
}

class _AnimatedListRow extends StatefulWidget {
  const _AnimatedListRow({
    super.key,
    required this.present,
    required this.entering,
    required this.expand,
    required this.index,
    required this.reordering,
    required this.settings,
    required this.child,
  });

  final bool present;
  final bool entering;
  final bool expand;
  final int index;
  final bool reordering;
  final DialogAnimationSettings settings;
  final Widget child;

  @override
  State<_AnimatedListRow> createState() => _AnimatedListRowState();
}

class _AnimatedListRowState extends State<_AnimatedListRow>
    with TickerProviderStateMixin {
  late bool _animateExtent = widget.expand;
  late final _presence = AnimationController(
    vsync: this,
    value: widget.entering ? 0 : 1,
  );
  late final _move = AnimationController(vsync: this, value: 1);
  Animatable<Offset> _offset = Tween(begin: Offset.zero, end: Offset.zero);

  @override
  void initState() {
    super.initState();
    _syncPresence();
  }

  @override
  void didUpdateWidget(covariant _AnimatedListRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPresence();
    if (widget.settings.entranceDuration == Duration.zero) {
      _move.value = 1;
    } else if (widget.reordering && oldWidget.index != widget.index) {
      final current = _offset.evaluate(_move);
      _offset = Tween(
        begin: current + Offset(0, (oldWidget.index - widget.index).toDouble()),
        end: Offset.zero,
      ).chain(CurveTween(curve: kOpenHandEntranceCurve));
      _move
        ..duration = widget.settings.entranceDuration
        ..forward(from: 0);
    }
  }

  void _syncPresence() {
    if (!widget.present) _animateExtent = true;
    final duration = widget.present
        ? widget.settings.entranceDuration
        : widget.settings.exitDuration;
    _presence
      ..duration = widget.settings.entranceDuration
      ..reverseDuration = widget.settings.exitDuration;
    if (duration == Duration.zero) {
      _presence.value = widget.present ? 1 : 0;
    } else if (widget.present && _presence.status != AnimationStatus.forward) {
      _presence.forward();
    } else if (!widget.present && _presence.status != AnimationStatus.reverse) {
      _presence.reverse();
    }
  }

  @override
  void dispose() {
    _presence.dispose();
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.present,
      child: ExcludeSemantics(
        excluding: !widget.present,
        child: AnimatedBuilder(
          animation: Listenable.merge([_presence, _move]),
          child: ExcludeFocus(excluding: !widget.present, child: widget.child),
          builder: (context, child) => FractionalTranslation(
            translation: _offset.evaluate(_move),
            child: SizeTransition(
              sizeFactor: !_animateExtent
                  ? const AlwaysStoppedAnimation(1.0)
                  : openHandBoundedCurveAnimation(
                      parent: _presence,
                      curve: kOpenHandSwitchInCurve,
                      reverseCurve: kOpenHandSwitchOutCurve,
                    ),
              alignment: Alignment.topCenter,
              child: buildAnimationStyleTransition(
                animation: _presence,
                settings: widget.settings,
                child: child!,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
