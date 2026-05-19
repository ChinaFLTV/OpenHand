import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
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

/// 渐进式：先 [cleanWebReverseProfileLocks]，再 [hasWebReverseProfileLocks]
/// 二次校验；只要还有锁就弹窗询问用户是否「重置整个 profile」。重置只对
/// 含有 `web_reverse` 关键词且长度 ≥ 16 的路径放行，规避误删用户其他目录。
///
/// 该函数会自行通过 [ScaffoldMessenger] 弹反馈 SnackBar，调用方拿到
/// outcome 即可。SnackBar 颜色按结果分级：
///   - cleaned / reset：浅色 secondaryContainer
///   - resetCancelled / failed：errorContainer
///   - nothingToDo：默认主题色
Future<ProgressiveProfileOutcome> runProgressiveProfileResolve(
  BuildContext context, {
  required String userDataDir,
  required bool isZh,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final loc = AppLocalizations.of(context);

  void toast({
    required String text,
    Color? bg,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;
    // 2026-05-25 — 旧版按 bg 区分语义；统一改走 OpenHandSnackBar 的
    // info/success/error 变体，沿用全局图标+motion+关闭按钮的现代风格。
    if (bg == cs.errorContainer) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        text,
        duration: duration,
      );
    } else if (bg == cs.secondaryContainer) {
      OpenHandSnackBar.showSuccessOn(
        context,
        messenger,
        text,
        duration: duration,
      );
    } else {
      OpenHandSnackBar.showInfoOn(context, messenger, text, duration: duration);
    }
  }

  if (userDataDir.trim().isEmpty) {
    toast(
      text:
          loc?.webReverseProfileEmptyPath ?? 'Empty profile path; nothing done',
      bg: cs.errorContainer,
    );
    return ProgressiveProfileOutcome.failed;
  }

  // ① 第一步：清理 SingletonLock 等残留锁文件。
  ({int deleted, List<String> messages}) cleanResult;
  try {
    cleanResult = await cleanWebReverseProfileLocks(userDataDir);
  } catch (error, stack) {
    silentLog('web_reverse_profile_actions', 'clean step', error, stack);
    toast(
      text:
          loc?.webReverseProfileCleanFailed('$error') ?? 'Clean failed: $error',
      bg: cs.errorContainer,
    );
    return ProgressiveProfileOutcome.failed;
  }

  // ② 二次确认：清理后是否还有锁残留？某些权限受保护的锁文件 delete 会
  // 静默失败，hasWebReverseProfileLocks 用 file.exists() 兜底判断。
  final stillLocked = await hasWebReverseProfileLocks(userDataDir);

  if (!stillLocked) {
    if (cleanResult.deleted > 0) {
      toast(
        text:
            loc?.webReverseProfileCleaned(cleanResult.deleted) ??
            'Cleared ${cleanResult.deleted} lock file(s); profile is healthy',
        bg: cs.secondaryContainer,
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

  // ③ 仍有锁 → 引导用户走更激进的"重置整个 profile"。
  if (!context.mounted) return ProgressiveProfileOutcome.failed;
  final ok = await showAnimatedDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        loc?.webReverseProfileResetTitle ??
            'Locks still present — reset profile?',
      ),
      content: Text(
        loc?.webReverseProfileResetBody(userDataDir) ??
            'Cleaned SingletonLock residues but locks still exist.\n\nProceeding will recursively delete:\n$userDataDir\n\nCookies / Login Data / extensions / history under this profile will be lost; a fresh profile is rebuilt on next launch.',
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          label: loc?.commonCancel ?? 'Cancel',
        ),
        OpenHandDialogActionButton.destructive(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          label: loc?.webReverseProfileResetConfirm ?? 'Reset now',
        ),
      ],
    ),
  );
  if (ok != true) {
    toast(
      text:
          loc?.webReverseProfileKept ??
          'Profile kept; locks may still block next launch.',
      bg: cs.errorContainer,
    );
    return ProgressiveProfileOutcome.resetCancelled;
  }

  // ④ 重置：路径安全策略 → 递归删除。
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
      bg: cs.secondaryContainer,
    );
    return ProgressiveProfileOutcome.reset;
  } catch (error, stack) {
    silentLog('web_reverse_profile_actions', 'reset step', error, stack);
    if (!context.mounted) return ProgressiveProfileOutcome.failed;
    toast(
      text:
          loc?.webReverseProfileResetFailed('$error') ?? 'Reset failed: $error',
      bg: cs.errorContainer,
    );
    return ProgressiveProfileOutcome.failed;
  }
}
