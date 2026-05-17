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
    if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) return;
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

  /// 把外部浏览器窗口最小化（macOS 用 AppleScript `set miniaturized`，
  /// Windows 用 ShowWindow SW_MINIMIZE，Linux X11 用 wmctrl `-b add,hidden`）。
  /// 用于 dashboard 切到「浏览器」tab、由 Flutter 端 screencast 接管显示后，
  /// 把真实浏览器窗口隐藏起来；切回非浏览器 tab 再调 [showBrowserWindow] 还原。
  Future<void> hideBrowserWindow() async {
    try {
      if (Platform.isMacOS) {
        final script = '''
tell application "System Events"
  if exists process "$browserAppName" then
    set p to process "$browserAppName"
    repeat with w in (windows of p whose subrole is "AXStandardWindow")
      try
        set value of attribute "AXMinimized" of w to true
      end try
    end repeat
  end if
end tell
''';
        await runProcessWithTimeout(
          '/usr/bin/osascript',
          ['-e', script],
          timeout: const Duration(seconds: 1),
          tag: 'web_reverse_window_dock',
        );
      } else if (Platform.isLinux) {
        final res = await runProcessWithTimeout(
          'wmctrl',
          const ['-lG'],
          timeout: const Duration(seconds: 1),
          tag: 'web_reverse_window_dock',
        );
        final raw = res?.stdout.toString() ?? '';
        for (final line in raw.split('\n')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length < 8) continue;
          final title = parts.sublist(7).join(' ').toLowerCase();
          if (title.contains(browserAppName.toLowerCase())) {
            await runProcessWithTimeout(
              'wmctrl',
              ['-i', '-r', parts[0], '-b', 'add,hidden'],
              timeout: const Duration(seconds: 1),
              tag: 'web_reverse_window_dock',
            );
          }
        }
      } else if (Platform.isWindows) {
        final script = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern int EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
}
"@
$matchTitle = "''' +
            browserAppName +
            r'''"
$proc = [W+EnumProc] {
  param($h, $l)
  $sb = New-Object System.Text.StringBuilder 256
  [W]::GetWindowText($h, $sb, 256) | Out-Null
  if ($sb.ToString() -like "*$matchTitle*") { [W]::ShowWindow($h, 6) | Out-Null }
  return $true
}
[W]::EnumWindows($proc, [IntPtr]::Zero) | Out-Null
''';
        await runProcessWithTimeout(
          'powershell.exe',
          ['-NoProfile', '-Command', script],
          timeout: const Duration(seconds: 2),
          tag: 'web_reverse_window_dock',
        );
      }
    } catch (_) {}
  }

  /// 取消最小化、把窗口拉回前台。与 [hideBrowserWindow] 对称。
  Future<void> showBrowserWindow() async {
    try {
      if (Platform.isMacOS) {
        final script = '''
tell application "System Events"
  if exists process "$browserAppName" then
    set p to process "$browserAppName"
    repeat with w in (windows of p whose subrole is "AXStandardWindow")
      try
        set value of attribute "AXMinimized" of w to false
      end try
    end repeat
  end if
end tell
''';
        await runProcessWithTimeout(
          '/usr/bin/osascript',
          ['-e', script],
          timeout: const Duration(seconds: 1),
          tag: 'web_reverse_window_dock',
        );
      } else if (Platform.isLinux) {
        final res = await runProcessWithTimeout(
          'wmctrl',
          const ['-lG'],
          timeout: const Duration(seconds: 1),
          tag: 'web_reverse_window_dock',
        );
        final raw = res?.stdout.toString() ?? '';
        for (final line in raw.split('\n')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length < 8) continue;
          final title = parts.sublist(7).join(' ').toLowerCase();
          if (title.contains(browserAppName.toLowerCase())) {
            await runProcessWithTimeout(
              'wmctrl',
              ['-i', '-r', parts[0], '-b', 'remove,hidden'],
              timeout: const Duration(seconds: 1),
              tag: 'web_reverse_window_dock',
            );
          }
        }
      } else if (Platform.isWindows) {
        final script = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern int EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
}
"@
$matchTitle = "''' +
            browserAppName +
            r'''"
$proc = [W+EnumProc] {
  param($h, $l)
  $sb = New-Object System.Text.StringBuilder 256
  [W]::GetWindowText($h, $sb, 256) | Out-Null
  if ($sb.ToString() -like "*$matchTitle*") { [W]::ShowWindow($h, 9) | Out-Null }
  return $true
}
[W]::EnumWindows($proc, [IntPtr]::Zero) | Out-Null
''';
        await runProcessWithTimeout(
          'powershell.exe',
          ['-NoProfile', '-Command', script],
          timeout: const Duration(seconds: 2),
          tag: 'web_reverse_window_dock',
        );
      }
    } catch (_) {}
  }

  Future<void> _tick() async {
    if (!_running) return;
    try {
      if (Platform.isMacOS) {
        final bounds = await _readOpenHandBoundsMacOS();
        if (bounds == null) return;
        await _moveBrowserWindowMacOS(bounds);
      } else if (Platform.isLinux) {
        final bounds = await _readOpenHandBoundsLinux();
        if (bounds == null) return;
        await _moveBrowserWindowLinux(bounds);
      } else if (Platform.isWindows) {
        final bounds = await _readOpenHandBoundsWindows();
        if (bounds == null) return;
        await _moveBrowserWindowWindows(bounds);
      }
    } catch (_) {
      // 静默吞掉单 tick 错误，下个 tick 会自然重试。
    }
  }

  // ── macOS ────────────────────────────────────────────────────────────

  /// 通过 System Events 读 OpenHand 主窗口的 bounds（屏幕坐标 x, y, w, h）。
  Future<_Bounds?> _readOpenHandBoundsMacOS() async {
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
  Future<void> _moveBrowserWindowMacOS(_Bounds parent) async {
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

  // ── Linux ────────────────────────────────────────────────────────────
  // 依赖 `wmctrl`（绝大多数 X11 桌面默认装）。
  // - `wmctrl -lG` 输出每个窗口的 wid + x y w h + host + title。
  // - `wmctrl -i -r <wid> -e 0,x,y,w,h` 改窗口位置/尺寸。
  // - Wayland 下大概率失败；当前阶段不专门处理。

  Future<_Bounds?> _readOpenHandBoundsLinux() async {
    final result = await runProcessWithTimeout(
      'wmctrl',
      const ['-lG'],
      timeout: const Duration(seconds: 1),
      tag: 'web_reverse_window_dock',
    );
    final raw = result?.stdout.toString() ?? '';
    if (raw.isEmpty) return null;
    for (final line in raw.split('\n')) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 8) continue;
      final title = parts.sublist(7).join(' ');
      final tl = title.toLowerCase();
      if (!tl.contains('openhand')) continue;
      final x = int.tryParse(parts[2]);
      final y = int.tryParse(parts[3]);
      final w = int.tryParse(parts[4]);
      final h = int.tryParse(parts[5]);
      if (x == null || y == null || w == null || h == null) continue;
      return _Bounds(x, y, w, h);
    }
    return null;
  }

  Future<void> _moveBrowserWindowLinux(_Bounds parent) async {
    final result = await runProcessWithTimeout(
      'wmctrl',
      const ['-lG'],
      timeout: const Duration(seconds: 1),
      tag: 'web_reverse_window_dock',
    );
    final raw = result?.stdout.toString() ?? '';
    String? wid;
    for (final line in raw.split('\n')) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 8) continue;
      final title = parts.sublist(7).join(' ').toLowerCase();
      // 命中浏览器主窗——按进程名宽松匹配。
      if (title.contains(browserAppName.toLowerCase())) {
        wid = parts[0];
        break;
      }
    }
    if (wid == null) return;
    final newX = parent.x + parent.w + gap;
    final newY = parent.y;
    const newW = 720;
    final newH = parent.h;
    await runProcessWithTimeout(
      'wmctrl',
      ['-i', '-r', wid, '-e', '0,$newX,$newY,$newW,$newH'],
      timeout: const Duration(seconds: 1),
      tag: 'web_reverse_window_dock',
    );
  }

  // ── Windows ──────────────────────────────────────────────────────────
  // 用 PowerShell + Win32 API。FindWindow + MoveWindow 单条 ps1 一次性完成。

  Future<_Bounds?> _readOpenHandBoundsWindows() async {
    const script = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  public struct RECT { public int L; public int T; public int R; public int B; }
}
"@
$matchTitle = "OpenHand"
$found = [IntPtr]::Zero
$proc = [W+EnumProc] {
  param($h, $l)
  $sb = New-Object System.Text.StringBuilder 256
  [W]::GetWindowText($h, $sb, 256) | Out-Null
  if ($sb.ToString() -like "*$matchTitle*") { $script:found = $h; return $false }
  return $true
}
[W]::EnumWindows($proc, [IntPtr]::Zero) | Out-Null
if ($script:found -ne [IntPtr]::Zero) {
  $r = New-Object W+RECT
  [W]::GetWindowRect($script:found, [ref]$r) | Out-Null
  Write-Output ("{0},{1},{2},{3}" -f $r.L, $r.T, ($r.R - $r.L), ($r.B - $r.T))
}
''';
    final result = await runProcessWithTimeout(
      'powershell.exe',
      ['-NoProfile', '-Command', script],
      timeout: const Duration(seconds: 2),
      tag: 'web_reverse_window_dock',
    );
    final raw = result?.stdout.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(',');
    if (parts.length != 4) return null;
    final x = int.tryParse(parts[0].trim());
    final y = int.tryParse(parts[1].trim());
    final w = int.tryParse(parts[2].trim());
    final h = int.tryParse(parts[3].trim());
    if (x == null || y == null || w == null || h == null) return null;
    return _Bounds(x, y, w, h);
  }

  Future<void> _moveBrowserWindowWindows(_Bounds parent) async {
    final newX = parent.x + parent.w + gap;
    final newY = parent.y;
    const newW = 720;
    final newH = parent.h;
    final script = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int h2, bool repaint);
  [DllImport("user32.dll")] public static extern int EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
}
"@
$matchTitle = "''' +
        browserAppName +
        r'''"
$found = [IntPtr]::Zero
$proc = [W+EnumProc] {
  param($h, $l)
  $sb = New-Object System.Text.StringBuilder 256
  [W]::GetWindowText($h, $sb, 256) | Out-Null
  if ($sb.ToString() -like "*$matchTitle*") { $script:found = $h; return $false }
  return $true
}
[W]::EnumWindows($proc, [IntPtr]::Zero) | Out-Null
if ($script:found -ne [IntPtr]::Zero) {
  [W]::MoveWindow($script:found, ''' +
        '$newX, $newY, $newW, $newH' +
        r''', $true) | Out-Null
}
''';
    await runProcessWithTimeout(
      'powershell.exe',
      ['-NoProfile', '-Command', script],
      timeout: const Duration(seconds: 2),
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
