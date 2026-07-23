/// Cron 执行历史的冷启动自动清理 worker。
///
/// 设计目标：
/// * 仅在 **冷启动** 后异步触发一次（main.dart 调用），不做轮询、不
///   驻留后台 Timer，避免无限循环 / 死循环 / 资源泄漏。
/// * 全局 single-flight：同一进程内若重复调用，后续调用直接 short-circuit。
/// * 全程 try/catch + [silentLog]，绝不向调用方抛异常。
/// * 设置项变更后重新冷启动才会生效；这是一个"轻量"清理路径，避免
///   与正常运行时的写入路径竞争锁。
library;

import 'dart:async';

import '../../../app/state/settings_controller.dart';
import '../../../app/support/silent_log.dart';
import '../crons_controller.dart';

/// 控制全进程仅执行一次的标志位。即使被误调多次，也只生效首次。
bool _hasRunInThisProcess = false;
const Duration _cleanupTimeout = Duration(seconds: 30);

/// 冷启动后异步运行：根据设置项决定是否清理 cron 执行历史。
///
/// 调用方应使用 `unawaited(...)`：本函数永不抛异常。
///
/// * [settings] — 读取 `cronAutoCleanupEnabled` / `cronAutoCleanupRetentionDays`。
/// * [crons] — 用于实际删除历史记录。
Future<void> runCronHistoryCleanupOnce({
  required SettingsController settings,
  required CronsController crons,
}) async {
  if (_hasRunInThisProcess) return;
  _hasRunInThisProcess = true;

  try {
    if (!settings.cronAutoCleanupEnabled) return;
    final retention = settings.cronAutoCleanupRetentionDays;
    if (retention <= 0) return;

    final cutoff = DateTime.now().subtract(Duration(days: retention));

    // 用 timeout 兜底，防止 SQLite 写锁互相阻塞导致无限等待。
    final affected = await crons
        .purgeHistoryOlderThan(cutoff)
        .timeout(_cleanupTimeout, onTimeout: () => -1);

    if (affected < 0) {
      silentLog(
        'cron_history_cleanup_worker',
        '清理超时',
        'maxWait=$_cleanupTimeout retentionDays=$retention',
      );
    }
  } catch (error, stack) {
    silentLog('cron_history_cleanup_worker', '发生意外异常', error, stack);
  }
}
