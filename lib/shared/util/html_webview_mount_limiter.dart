import 'dart:collection';
import 'dart:math' as math;

/// Concurrency gate for expensive HTML WebView platform views.
///
/// Only a bounded number of HTML cards may mount at once; waiters are
/// granted on release with an optional post-frame schedule hook so the
/// drain never re-enters layout/build synchronously.
class HtmlWebViewMountLimiter {
  HtmlWebViewMountLimiter({
    int maxMounted = defaultMaxMounted,
    void Function(void Function() task)? scheduleGranted,
  }) : maxMounted = math.max(1, maxMounted),
       _scheduleGranted = scheduleGranted;

  static const int defaultMaxMounted = 2;

  final int maxMounted;
  final void Function(void Function() task)? _scheduleGranted;
  final Set<int> _activeIds = <int>{};
  final Queue<HtmlWebViewMountPermit> _waiting =
      Queue<HtmlWebViewMountPermit>();
  int _nextId = 0;

  int get activeCount => _activeIds.length;

  int get waitingCount => _waiting.length;

  HtmlWebViewMountPermit request(
    void Function() onGranted, {
    bool priority = false,
  }) {
    final permit = HtmlWebViewMountPermit._(++_nextId, this, onGranted);
    if (_activeIds.length < maxMounted) {
      _activeIds.add(permit.id);
      permit._granted = true;
      return permit;
    }
    if (priority) {
      _waiting.addFirst(permit);
    } else {
      _waiting.addLast(permit);
    }
    return permit;
  }

  void release(HtmlWebViewMountPermit permit) {
    if (permit._released) {
      return;
    }
    permit._released = true;
    if (permit._granted) {
      _activeIds.remove(permit.id);
    } else {
      _waiting.remove(permit);
    }
    _drain();
  }

  void clear() {
    for (final permit in _waiting) {
      permit._released = true;
    }
    _waiting.clear();
    _activeIds.clear();
  }

  void _drain() {
    while (_activeIds.length < maxMounted && _waiting.isNotEmpty) {
      final permit = _waiting.removeFirst();
      if (permit._released) {
        continue;
      }
      permit._granted = true;
      _activeIds.add(permit.id);
      final schedule = _scheduleGranted;
      if (schedule == null) {
        if (!permit._released) {
          permit._onGranted();
        }
      } else {
        schedule(() {
          if (!permit._released) {
            permit._onGranted();
          }
        });
      }
    }
  }
}

class HtmlWebViewMountPermit {
  HtmlWebViewMountPermit._(this.id, this._owner, this._onGranted);

  final int id;
  final HtmlWebViewMountLimiter _owner;
  final void Function() _onGranted;
  bool _granted = false;
  bool _released = false;

  bool get granted => _granted && !_released;

  bool get released => _released;

  void release() => _owner.release(this);
}
