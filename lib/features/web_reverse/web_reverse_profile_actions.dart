import 'dart:io';

import 'package:flutter/material.dart';
import '../../shared/ui/animated_dialog.dart';

import '../../app/support/silent_log.dart';
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

  void toast({
    required String text,
    Color? bg,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;
    // 2026-05-25 — 旧版按 bg 区分语义；统一改走 OpenHandSnackBar 的
    // info/success/error 变体，沿用全局图标+motion+关闭按钮的现代风格。
    if (bg == cs.errorContainer) {
      OpenHandSnackBar.showErrorOn(context, messenger, text, duration: duration);
    } else if (bg == cs.secondaryContainer) {
      OpenHandSnackBar.showSuccessOn(context, messenger, text, duration: duration);
    } else {
      OpenHandSnackBar.showInfoOn(context, messenger, text, duration: duration);
    }
  }

  if (userDataDir.trim().isEmpty) {
    toast(
      text: isZh ? 'Profile 路径为空，未执行' : 'Empty profile path; nothing done',
      bg: cs.errorContainer,
    );
    return ProgressiveProfileOutcome.failed;
  }

  // ① 第一步：清理 SingletonLock 等残留锁文件。
  ({int deleted, List<String> messages}) cleanResult;
  try {
    cleanResult = await cleanWebReverseProfileLocks(userDataDir);
  } catch (error, stack) {
    silentLog(
      'web_reverse_profile_actions',
      'clean step',
      error,
      stack,
    );
    toast(
      text: isZh ? '清理失败：$error' : 'Clean failed: $error',
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
        text: isZh
            ? '已清理 ${cleanResult.deleted} 个锁文件，profile 已恢复'
            : 'Cleared ${cleanResult.deleted} lock file(s); profile is healthy',
        bg: cs.secondaryContainer,
      );
      return ProgressiveProfileOutcome.cleaned;
    }
    toast(
      text: isZh
          ? '未发现残留锁文件。如仍无法启动，请查看诊断卡片其他根因。'
          : 'No residual locks. If launch still fails, see other causes in diagnosis.',
    );
    return ProgressiveProfileOutcome.nothingToDo;
  }

  // ③ 仍有锁 → 引导用户走更激进的"重置整个 profile"。
  if (!context.mounted) return ProgressiveProfileOutcome.failed;
  final ok = await showAnimatedDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(isZh ? '锁仍未清干净，是否重置 profile？' : 'Locks still present — reset profile?'),
      content: Text(
        isZh
            ? '已尝试清理 SingletonLock 等残留，但仍检测到锁文件。\n\n'
                '继续操作会递归删除：\n$userDataDir\n\n'
                '该 profile 下的 Cookies / Login Data / 已安装扩展 / 浏览历史 等数据将全部丢失，'
                '下次启动会重建一个全新 profile。'
            : 'Cleaned SingletonLock residues but locks still exist.\n\n'
                'Proceeding will recursively delete:\n$userDataDir\n\n'
                'Cookies / Login Data / extensions / history under this profile will be lost; a fresh profile is rebuilt on next launch.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(isZh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(isZh ? '确认重置' : 'Reset now'),
        ),
      ],
    ),
  );
  if (ok != true) {
    toast(
      text: isZh
          ? '已保留 profile，但锁仍可能阻止下次启动。'
          : 'Profile kept; locks may still block next launch.',
      bg: cs.errorContainer,
    );
    return ProgressiveProfileOutcome.resetCancelled;
  }

  // ④ 重置：路径安全策略 → 递归删除。
  try {
    if (!userDataDir.contains('web_reverse') || userDataDir.length < 16) {
      throw const FileSystemException(
        '安全策略拒绝：路径不在 OpenHand web_reverse 子目录中',
      );
    }
    final d = Directory(userDataDir);
    if (await d.exists()) {
      await d.delete(recursive: true);
    }
    if (!context.mounted) return ProgressiveProfileOutcome.reset;
    toast(
      text: isZh
          ? '已重置 profile：$userDataDir（60 秒内不可重复操作）'
          : 'Profile reset: $userDataDir (60s cool-down)',
      bg: cs.secondaryContainer,
    );
    return ProgressiveProfileOutcome.reset;
  } catch (error, stack) {
    silentLog(
      'web_reverse_profile_actions',
      'reset step',
      error,
      stack,
    );
    if (!context.mounted) return ProgressiveProfileOutcome.failed;
    toast(
      text: isZh ? '重置失败：$error' : 'Reset failed: $error',
      bg: cs.errorContainer,
    );
    return ProgressiveProfileOutcome.failed;
  }
}
