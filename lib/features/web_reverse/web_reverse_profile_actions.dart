import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/support/openhand_paths.dart';
import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/util/bounded_delete.dart';
import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_profile_cleaner.dart';

/// 渐进式解决 profile 冲突的结果，供 UI 决定是否进入冷却期。
enum ProgressiveProfileOutcome {
  /// 没有任何残留锁，未做任何操作（或用户在初始确认时取消）。
  nothingToDo,

  /// 清理成功，锁已不存在，无需再走更激进的重置路径。
  cleaned,

  /// 清理后仍残留锁，用户进一步确认并完成了 user-data-dir 的递归删除。
  reset,

  /// 仍残留锁，但用户在重置确认弹窗里选择了取消。
  resetCancelled,

  /// 清理或重置过程中发生异常（已写入 silentLog）。
  failed,
}

enum _ProfileToastTone { info, success, error }

const BoundedDeletePolicy _profileDeletePolicy = BoundedDeletePolicy(
  maxEntries: 500000,
  maxDepth: 128,
  directoryIdleTimeout: Duration(seconds: 5),
  operationTimeout: Duration(seconds: 30),
  totalTimeout: Duration(minutes: 5),
);

/// 渐进式：先 [cleanWebReverseProfileLocks]，再 [hasWebReverseProfileLocks]
/// 二次校验；只要还有锁就弹窗询问用户是否「重置整个 profile」。重置只对
/// 物理路径位于 OpenHand `web_reverse` 根目录内时才允许重置，规避符号链接
/// 或相似目录名导致的越界删除。
///
/// 该函数会自行弹反馈 SnackBar，调用方拿到 outcome 即可。
Future<ProgressiveProfileOutcome> runProgressiveProfileResolve(
  BuildContext context, {
  required String userDataDir,
}) async {
  final loc = AppLocalizations.of(context);

  void toast({
    required String text,
    _ProfileToastTone tone = _ProfileToastTone.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;
    switch (tone) {
      case _ProfileToastTone.error:
        showOpenHandErrorSnack(context, text, duration: duration);
      case _ProfileToastTone.success:
        showOpenHandSuccessSnack(context, text, duration: duration);
      case _ProfileToastTone.info:
        showOpenHandInfoSnack(context, text, duration: duration);
    }
  }

  final normalizedUserDataDir = nullIfBlank(userDataDir);
  if (normalizedUserDataDir == null) {
    toast(
      text:
          loc?.webReverseProfileEmptyPath ?? 'Empty profile path; nothing done',
      tone: _ProfileToastTone.error,
    );
    return ProgressiveProfileOutcome.failed;
  }

  late final int deletedLockCount;
  try {
    deletedLockCount = (await cleanWebReverseProfileLocks(
      normalizedUserDataDir,
    )).deleted;
  } catch (error, stack) {
    silentLog('web_reverse_profile_actions', '执行清理步骤', error, stack);
    toast(
      text:
          loc?.webReverseProfileCleanFailed('$error') ?? 'Clean failed: $error',
      tone: _ProfileToastTone.error,
    );
    return ProgressiveProfileOutcome.failed;
  }

  // Some protected lock files may survive delete attempts.
  final stillLocked = await hasWebReverseProfileLocks(normalizedUserDataDir);

  if (!stillLocked) {
    if (deletedLockCount > 0) {
      toast(
        text:
            loc?.webReverseProfileCleaned(deletedLockCount) ??
            'Cleared $deletedLockCount lock file(s); profile is healthy',
        tone: _ProfileToastTone.success,
      );
      return ProgressiveProfileOutcome.cleaned;
    }
    toast(
      text:
          loc?.webReverseProfileNoResidual ??
          'No residual locks. If launch still fails, see other causes in diagnosis.',
    );
    return ProgressiveProfileOutcome.nothingToDo;
  }

  if (!context.mounted) return ProgressiveProfileOutcome.failed;
  final ok = await showOpenHandConfirmDialog(
    context: context,
    title:
        loc?.webReverseProfileResetTitle ??
        'Locks still present — reset profile?',
    message:
        loc?.webReverseProfileResetBody(normalizedUserDataDir) ??
        'Cleaned SingletonLock residues but locks still exist.\n\nProceeding will recursively delete:\n$normalizedUserDataDir\n\nCookies / Login Data / extensions / history under this profile will be lost; a fresh profile is rebuilt on next launch.',
    cancelLabel: loc?.commonCancel ?? 'Cancel',
    confirmLabel: loc?.webReverseProfileResetConfirm ?? 'Reset now',
    destructive: true,
  );
  if (!ok) {
    toast(
      text:
          loc?.webReverseProfileKept ??
          'Profile kept; locks may still block next launch.',
      tone: _ProfileToastTone.error,
    );
    return ProgressiveProfileOutcome.resetCancelled;
  }

  try {
    final webReverseRoot = p.join(
      OpenHandPaths.defaultRootDirectoryPath(),
      'web_reverse',
    );
    await deletePathBounded(
      p.absolute(normalizedUserDataDir),
      policy: _profileDeletePolicy,
      allowedRoot: p.absolute(webReverseRoot),
    );
    if (!context.mounted) return ProgressiveProfileOutcome.reset;
    toast(
      text:
          loc?.webReverseProfileResetDone(normalizedUserDataDir) ??
          'Profile reset: $normalizedUserDataDir (60s cool-down)',
      tone: _ProfileToastTone.success,
    );
    return ProgressiveProfileOutcome.reset;
  } catch (error, stack) {
    silentLog('web_reverse_profile_actions', '执行重置步骤', error, stack);
    if (!context.mounted) return ProgressiveProfileOutcome.failed;
    toast(
      text:
          loc?.webReverseProfileResetFailed('$error') ?? 'Reset failed: $error',
      tone: _ProfileToastTone.error,
    );
    return ProgressiveProfileOutcome.failed;
  }
}
