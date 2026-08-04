/// 定时任务执行历史的冷启动清理任务。
library;

import 'dart:async';

import '../../../app/state/settings_controller.dart';
import '../../../app/support/silent_log.dart';
import '../crons_controller.dart';

bool _hasRunInThisProcess = false;
const Duration _cleanupTimeout = Duration(seconds: 30);

/// 按设置清理一次过期历史；失败只记录日志，不阻断启动。
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

    // 限制调用方等待时间，避免数据库写锁阻塞启动流程。
    final affected = await crons
        .purgeHistoryOlderThan(cutoff)
        .timeout(_cleanupTimeout, onTimeout: () => -1);

    if (affected < 0) {
      silentLog(
        'cron_history_cleanup_worker',
        '清理超时',
        '最大等待时间=$_cleanupTimeout，保留天数=$retention',
      );
    }
  } catch (error, stack) {
    silentLog('cron_history_cleanup_worker', '清理执行历史', error, stack);
  }
}
