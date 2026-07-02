import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_snack_bar.dart';
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

/// 渐进式：先 [cleanWebReverseProfileLocks]，再 [hasWebReverseProfileLocks]
/// 二次校验；只要还有锁就弹窗询问用户是否「重置整个 profile」。重置只对
/// 含有 `web_reverse` 关键词且长度 ≥ 16 的路径放行，规避误删用户其他目录。
///
/// 该函数会自行通过 [ScaffoldMessenger] 弹反馈 SnackBar，调用方拿到
/// outcome 即可。
Future<ProgressiveProfileOutcome> runProgressiveProfileResolve(
  BuildContext context, {
  required String userDataDir,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final loc = AppLocalizations.of(context);

  void toast({
    required String text,
    _ProfileToastTone tone = _ProfileToastTone.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;
    switch (tone) {
      case _ProfileToastTone.error:
        OpenHandSnackBar.showErrorOn(
          context,
          messenger,
          text,
          duration: duration,
        );
      case _ProfileToastTone.success:
        OpenHandSnackBar.showSuccessOn(
          context,
          messenger,
          text,
          duration: duration,
        );
      case _ProfileToastTone.info:
        OpenHandSnackBar.showInfoOn(
          context,
          messenger,
          text,
          duration: duration,
        );
    }
  }

  if (userDataDir.trim().isEmpty) {
    toast(
      text:
          loc?.webReverseProfileEmptyPath ?? 'Empty profile path; nothing done',
      tone: _ProfileToastTone.error,
    );
    return ProgressiveProfileOutcome.failed;
  }

  late final int deletedLockCount;
  try {
    deletedLockCount = (await cleanWebReverseProfileLocks(userDataDir)).deleted;
  } catch (error, stack) {
    silentLog('web_reverse_profile_actions', 'clean step', error, stack);
    toast(
      text:
          loc?.webReverseProfileCleanFailed('$error') ?? 'Clean failed: $error',
      tone: _ProfileToastTone.error,
    );
    return ProgressiveProfileOutcome.failed;
  }

  // Some protected lock files may survive delete attempts.
  final stillLocked = await hasWebReverseProfileLocks(userDataDir);

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
        loc?.webReverseProfileResetBody(userDataDir) ??
        'Cleaned SingletonLock residues but locks still exist.\n\nProceeding will recursively delete:\n$userDataDir\n\nCookies / Login Data / extensions / history under this profile will be lost; a fresh profile is rebuilt on next launch.',
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
    if (!userDataDir.contains('web_reverse') || userDataDir.length < 16) {
      throw const FileSystemException('安全策略拒绝：路径不在 OpenHand web_reverse 子目录中');
    }
    final d = Directory(userDataDir);
    if (await d.exists()) {
      await d.delete(recursive: true);
    }
    if (!context.mounted) return ProgressiveProfileOutcome.reset;
    toast(
      text:
          loc?.webReverseProfileResetDone(userDataDir) ??
          'Profile reset: $userDataDir (60s cool-down)',
      tone: _ProfileToastTone.success,
    );
    return ProgressiveProfileOutcome.reset;
  } catch (error, stack) {
    silentLog('web_reverse_profile_actions', 'reset step', error, stack);
    if (!context.mounted) return ProgressiveProfileOutcome.failed;
    toast(
      text:
          loc?.webReverseProfileResetFailed('$error') ?? 'Reset failed: $error',
      tone: _ProfileToastTone.error,
    );
    return ProgressiveProfileOutcome.failed;
  }
}
