import 'dart:async';
import 'dart:collection';

/// 限制高开销 HTML WebView 平台视图的并发挂载量。
///
/// 等待队列同样有界；超限请求会返回已释放许可，由调用方回退到轻量渲染。
class HtmlWebViewMountLimiter {
  HtmlWebViewMountLimiter({
    int maxMounted = defaultMaxMounted,
    int maxWaiting = defaultMaxWaiting,
    this._scheduleGranted,
  }) : maxMounted = maxMounted.clamp(1, maxAllowedMounted).toInt(),
       maxWaiting = maxWaiting.clamp(0, maxAllowedWaiting).toInt();

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

  /// 当前是否还有空闲挂载额度（且无人排队）。压力型回退的调用方据此
  /// 决定是否值得重试，避免注定失败的排队churn。
  bool get hasCapacity => _active.length < maxMounted && _waiting.isEmpty;

  HtmlWebViewMountPermit request(
    void Function() onGranted, {
    bool priority = false,
  }) {
    final permit = HtmlWebViewMountPermit._(++_nextId, this, onGranted);
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
        if (!permit._released) _notifyGranted(permit);
      } else {
        try {
          schedule(() {
            if (!permit._released && !_notifyGranted(permit)) {
              _drain();
            }
          });
        } catch (error, stack) {
          _releaseFailedPermit(permit, error, stack);
        }
      }
    }
  }

  bool _notifyGranted(HtmlWebViewMountPermit permit) {
    try {
      permit._onGranted();
      return true;
    } catch (error, stack) {
      _releaseFailedPermit(permit, error, stack);
      return false;
    }
  }

  void _releaseFailedPermit(
    HtmlWebViewMountPermit permit,
    Object error,
    StackTrace stack,
  ) {
    permit._granted = false;
    permit._released = true;
    _active.remove(permit.id);
    _reportCallbackError(error, stack);
  }

  void _reportCallbackError(Object error, StackTrace stack) {
    final zone = Zone.current;
    zone.scheduleMicrotask(() => zone.handleUncaughtError(error, stack));
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
