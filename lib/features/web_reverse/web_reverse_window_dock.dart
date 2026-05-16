import 'dart:async';
import 'dart:io';

import '../../app/support/safe_subprocess.dart';

/// macOS 窗口吸附：周期性把外部浏览器窗口贴到 OpenHand 主窗口右侧。
///
/// 实现策略：纯 osascript，避免引入额外的 native plugin（包体零增长）。
/// 方案：每 800ms 用 System Events 找一次进程的窗口、读 OpenHand 主窗口
/// bounds、把浏览器窗口移到正右方。窗口被用户手动拖动后，下一个 tick 会
/// 自动重新吸附。
///
/// 用户体验取舍：
/// - 不强行 always-on-top（otherwise 会让浏览器抢焦点干扰输入）。
/// - 关闭 dock 时浏览器窗口位置保持不变，由用户自由处理。
class WebReverseWindowDock {
  WebReverseWindowDock({
    required this.browserAppName,
    this.gap = 12,
    this.tickInterval = const Duration(milliseconds: 800),
  });

  /// macOS 进程名（Activity Monitor 可见的 process name）。
  /// 例：'Google Chrome' / 'Microsoft Edge' / 'Brave Browser' / 'Chromium'。
  final String browserAppName;

  /// 主窗口与浏览器窗口之间的间距（像素）。
  final int gap;

  /// 吸附 tick 间隔。过快会增加 osascript 调用开销；过慢用户拖动后回弹有迟滞。
  final Duration tickInterval;

  Timer? _timer;
  bool _running = false;

  bool get isRunning => _running;

  /// 启动周期吸附。重复 start 是幂等操作。
  void start() {
    if (!Platform.isMacOS) return;
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(tickInterval, (_) => unawaited(_tick()));
    // 立即跑一次，避免首次最长等 [tickInterval]。
    unawaited(_tick());
  }

  /// 停止吸附。浏览器窗口位置保留。
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (!_running) return;
    try {
      final bounds = await _readOpenHandBounds();
      if (bounds == null) return;
      await _moveBrowserWindow(bounds);
    } catch (_) {
      // 静默吞掉单 tick 错误，下个 tick 会自然重试。
    }
  }

  /// 通过 System Events 读 OpenHand 主窗口的 bounds（屏幕坐标 x, y, w, h）。
  Future<_Bounds?> _readOpenHandBounds() async {
    // 进程名取自 macOS 应用 bundle 的 CFBundleName。Flutter 默认使用项目名
    // 'openhand'，发布版可能改为 'OpenHand'；这里两个都试。
    for (final procName in const ['openhand', 'OpenHand']) {
      final script = '''
tell application "System Events"
  if exists process "$procName" then
    set p to process "$procName"
    set winList to (windows of p whose subrole is "AXStandardWindow")
    if (count of winList) > 0 then
      set w to item 1 of winList
      set thePos to position of w
      set theSize to size of w
      return (item 1 of thePos as text) & "," & (item 2 of thePos as text) & "," & (item 1 of theSize as text) & "," & (item 2 of theSize as text)
    end if
  end if
end tell
return ""
''';
      final result = await runProcessWithTimeout(
        '/usr/bin/osascript',
        ['-e', script],
        timeout: const Duration(seconds: 1),
        tag: 'web_reverse_window_dock',
      );
      final raw = result?.stdout.toString().trim();
      if (raw == null || raw.isEmpty) continue;
      final parts = raw.split(',');
      if (parts.length != 4) continue;
      final x = int.tryParse(parts[0].trim());
      final y = int.tryParse(parts[1].trim());
      final w = int.tryParse(parts[2].trim());
      final h = int.tryParse(parts[3].trim());
      if (x == null || y == null || w == null || h == null) continue;
      return _Bounds(x, y, w, h);
    }
    return null;
  }

  /// 把浏览器主窗口移到 OpenHand 主窗口的右侧，高度对齐。
  Future<void> _moveBrowserWindow(_Bounds parent) async {
    final newX = parent.x + parent.w + gap;
    final newY = parent.y;
    final newH = parent.h;
    // 浏览器窗口宽度让 macOS 自己决定（System Events 不强制改 size 时窗口
    // 会保留上次大小）；这里只对齐左上角与高度。宽度按 720 兜底，避免新 profile
    // 下窗口默认贴满整个屏幕。
    const newW = 720;
    final script = '''
tell application "System Events"
  if exists process "$browserAppName" then
    set p to process "$browserAppName"
    set winList to (windows of p whose subrole is "AXStandardWindow")
    if (count of winList) > 0 then
      set w to item 1 of winList
      set position of w to {$newX, $newY}
      set size of w to {$newW, $newH}
    end if
  end if
end tell
''';
    await runProcessWithTimeout(
      '/usr/bin/osascript',
      ['-e', script],
      timeout: const Duration(seconds: 1),
      tag: 'web_reverse_window_dock',
    );
  }
}

class _Bounds {
  const _Bounds(this.x, this.y, this.w, this.h);
  final int x;
  final int y;
  final int w;
  final int h;
}
