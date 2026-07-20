import 'dart:collection';

/// 限制高开销 HTML WebView 平台视图的并发挂载量。
///
/// 等待队列同样有界；超限请求会返回已释放许可，由调用方回退到轻量渲染。
class HtmlWebViewMountLimiter {
  HtmlWebViewMountLimiter({
    int maxMounted = defaultMaxMounted,
    int maxWaiting = defaultMaxWaiting,
    void Function(void Function() task)? scheduleGranted,
  }) : maxMounted = maxMounted.clamp(1, maxAllowedMounted).toInt(),
       maxWaiting = maxWaiting.clamp(0, maxAllowedWaiting).toInt(),
       _scheduleGranted = scheduleGranted;

  static const int defaultMaxMounted = 2;
  static const int defaultMaxWaiting = 64;
  static const int maxAllowedMounted = 16;
  static const int maxAllowedWaiting = 4096;

  final int maxMounted;
  final int maxWaiting;
  final void Function(void Function() task)? _scheduleGranted;
  final LinkedHashMap<int, HtmlWebViewMountPermit> _active =
      LinkedHashMap<int, HtmlWebViewMountPermit>();
  final Queue<HtmlWebViewMountPermit> _waiting =
      Queue<HtmlWebViewMountPermit>();
  int _nextId = 0;

  HtmlWebViewMountPermit request(
    void Function() onGranted, {
    bool priority = false,
    void Function()? onRevoked,
  }) {
    final permit = HtmlWebViewMountPermit._(
      ++_nextId,
      this,
      onGranted,
      onRevoked,
    );
    if (_active.length < maxMounted) {
      _active[permit.id] = permit;
      permit._granted = true;
      return permit;
    }
    if (_waiting.length >= maxWaiting) {
      permit._released = true;
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
      _active.remove(permit.id);
    } else {
      _waiting.remove(permit);
    }
    _drain();
  }

  void revokeOldest() {
    if (_active.isEmpty) return;
    final permit = _active.values.first;
    _active.remove(permit.id);
    permit._granted = false;
    permit._released = true;
    permit._onRevoked?.call();
    _drain();
  }

  void clear() {
    final activePermits = _active.values.toList(growable: false);
    for (final permit in activePermits) {
      permit._granted = false;
      permit._released = true;
    }
    for (final permit in _waiting) {
      permit._released = true;
    }
    _waiting.clear();
    _active.clear();
    for (final permit in activePermits) {
      permit._onRevoked?.call();
    }
  }

  void _drain() {
    while (_active.length < maxMounted && _waiting.isNotEmpty) {
      final permit = _waiting.removeFirst();
      if (permit._released) {
        continue;
      }
      permit._granted = true;
      _active[permit.id] = permit;
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
  HtmlWebViewMountPermit._(
    this.id,
    this._owner,
    this._onGranted,
    this._onRevoked,
  );

  final int id;
  final HtmlWebViewMountLimiter _owner;
  final void Function() _onGranted;
  final void Function()? _onRevoked;
  bool _granted = false;
  bool _released = false;

  bool get granted => _granted && !_released;

  bool get released => _released;

  void release() => _owner.release(this);
}
