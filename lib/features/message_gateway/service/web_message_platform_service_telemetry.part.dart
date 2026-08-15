part of 'web_message_platform_service.dart';

final RegExp _macSwapUsedPattern = RegExp(r'used\s*=\s*([0-9.]+)([MG]?)');

/// 进程级遥测快照（CPU/线程/句柄/Swap），由
/// [_refreshProcessDiagnosticsIfStale] 节流采集，2 秒内复用。
class _ProcessDiagnostics {
  const _ProcessDiagnostics({
    this.cpuPercent,
    this.threadCount,
    this.fileHandleCount,
    this.swapBytes,
  });

  final double? cpuPercent;
  final int? threadCount;
  final int? fileHandleCount;
  final int? swapBytes;
}

/// Linux `/proc/self/stat` + `/proc/stat` 一次原子采样，用于做 CPU 时间差分。
class _LinuxCpuSample {
  const _LinuxCpuSample({required this.processTicks, required this.totalTicks});

  final int processTicks;
  final int totalTicks;
}

/// 解析 macOS `sysctl vm.swapusage` 输出中的 `used = 1234.5M` 数字。
int? _parseMacSwapBytes(String value) {
  final match = _macSwapUsedPattern.firstMatch(value);
  if (match == null) return null;
  final number = optionalDoubleFromValue(match.group(1));
  if (number == null) return null;
  final unit = match.group(2) ?? '';
  final multiplier = unit == 'G'
      ? 1024 * kBytesPerMiB
      : unit == 'M'
      ? kBytesPerMiB
      : 1;
  return (number * multiplier).round();
}
