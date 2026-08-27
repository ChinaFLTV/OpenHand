import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../../features/ai/service/session_io/ai_session_jsonl_exporter.dart';
import '../../l10n/app_localizations.dart';
import 'animated_dialog.dart';
import 'openhand_dialog_action_button.dart';

/// 单次导出的等待上限：超过即视为卡死，取消并按失败收场。
///
/// 导出走的是本地文件写入，正常量级远达不到分钟级；给上限只是不让某次异常
/// 卡住的写入把进度弹窗永久钉在屏幕上。
const Duration kOpenHandExportTimeout = Duration(minutes: 5);

/// Listenable controller backing the export progress dialog. Holds the
/// current progress payload, a cancellation token, and the latest result.
class ExportProgressController extends ChangeNotifier {
  ExportProgressController({required this.cancelToken});

  final ExportCancelToken cancelToken;

  ExportProgress _progress = const ExportProgress(processed: 0, total: 0);
  ExportProgress get progress => _progress;

  bool _finished = false;
  bool get finished => _finished;
  bool _disposed = false;

  void updateProgress(ExportProgress next) {
    if (_finished || _disposed) return;
    _progress = next;
    notifyListeners();
  }

  void markFinished() {
    if (_finished || _disposed) return;
    _finished = true;
    notifyListeners();
  }

  void requestCancel() {
    if (_finished || _disposed) return;
    cancelToken.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

/// Modal dialog that surfaces real-time export progress and lets the user
/// cancel a running export. The dialog is non-dismissible: the only ways
/// to leave are pressing Cancel, completion, or the caller closing it.
class ExportProgressDialog extends StatelessWidget {
  const ExportProgressDialog({
    super.key,
    required this.controller,
    required this.title,
    required this.subtitle,
    required this.cancelLabel,
  });

  final ExportProgressController controller;
  final String title;
  final String subtitle;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      child: buildOpenHandAlertDialog(
        title: Text(title),
        content: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final progress = controller.progress;
            final isCancelling =
                controller.cancelToken.isCancelled && !controller.finished;
            return SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subtitle, style: theme.textTheme.bodyMedium),
                  kOpenHandGap16,
                  ClipRRect(
                    borderRadius: BorderRadius.circular(kOpenHandRadius8),
                    child: LinearProgressIndicator(
                      value: progress.total > 0 ? progress.fraction : null,
                      minHeight: 8,
                    ),
                  ),
                  kOpenHandGap12,
                  Text(
                    progress.total > 0
                        ? '${progress.processed} / ${progress.total}'
                        : '...',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (isCancelling) ...[
                    kOpenHandGap8,
                    Text(
                      l10n.exportProgressCancelling,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final disabled =
                  controller.finished || controller.cancelToken.isCancelled;
              return OpenHandDialogActionButton.secondary(
                onPressed: disabled ? null : controller.requestCancel,
                label: cancelLabel,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 打开受跟踪的导出进度弹窗；路由关闭时取消未完成任务并释放 [controller]。
OpenHandDialogSession<void> showExportProgressDialog({
  required BuildContext context,
  required ExportProgressController controller,
  required String title,
  required String subtitle,
  required String cancelLabel,
}) {
  final session = showTrackedAnimatedDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => ExportProgressDialog(
      controller: controller,
      title: title,
      subtitle: subtitle,
      cancelLabel: cancelLabel,
    ),
  );
  unawaited(
    session.closed.whenComplete(() {
      if (!controller.finished) controller.cancelToken.cancel();
      controller.dispose();
    }),
  );
  return session;
}

/// 跑一次带进度弹窗的导出：建取消令牌 → 开弹窗 → 执行 → 收弹窗。
///
/// 四处导出流程此前各写一遍这几步。少一步 [ExportProgressController.markFinished]
/// 就会让弹窗关闭时把一次已完成的导出当成用户取消，回头去 cancel 它；而
/// dismiss 写在 `try` 外还是里，决定了导出抛异常时弹窗会不会留在屏幕上。
///
/// [run] 拿到令牌与控制器后自行决定超时与失败取值，因此批量导出这类返回值不是
/// [ExportResult] 的流程也能共用。
Future<T> runWithExportProgressDialog<T>({
  required BuildContext context,
  required String title,
  required String subtitle,
  required String cancelLabel,
  required String logTag,
  required String logAction,
  required Future<T> Function(
    ExportCancelToken cancelToken,
    ExportProgressController controller,
  )
  run,
}) async {
  final cancelToken = ExportCancelToken();
  final controller = ExportProgressController(cancelToken: cancelToken);
  final session = showExportProgressDialog(
    context: context,
    controller: controller,
    title: title,
    subtitle: subtitle,
    cancelLabel: cancelLabel,
  );
  try {
    return await run(cancelToken, controller);
  } finally {
    controller.markFinished();
    await session.dismiss(logTag: logTag, logAction: logAction);
  }
}
