import 'package:flutter/material.dart';

import '../../features/ai/service/session_io/ai_session_jsonl_exporter.dart';
import 'animated_dialog.dart';
import 'openhand_dialog_action_button.dart';

/// Listenable controller backing the export progress dialog. Holds the
/// current progress payload, a cancellation token, and the latest result.
class ExportProgressController extends ChangeNotifier {
  ExportProgressController({required this.cancelToken});

  final ExportCancelToken cancelToken;

  ExportProgress _progress = const ExportProgress(processed: 0, total: 0);
  ExportProgress get progress => _progress;

  bool _finished = false;
  bool get finished => _finished;

  void updateProgress(ExportProgress next) {
    if (_finished) return;
    _progress = next;
    notifyListeners();
  }

  void markFinished() {
    if (_finished) return;
    _finished = true;
    notifyListeners();
  }

  void requestCancel() {
    if (_finished) return;
    cancelToken.cancel();
    notifyListeners();
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
    return PopScope(
      canPop: false,
      child: AlertDialog(
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
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress.total > 0 ? progress.fraction : null,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    progress.total > 0
                        ? '${progress.processed} / ${progress.total}'
                        : '...',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (isCancelling) ...[
                    const SizedBox(height: 8),
                    Text(
                      _localizedText(context, zh: '正在取消…', en: 'Cancelling…'),
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

/// Convenience helper that opens the progress dialog using
/// [showAnimatedDialog] so it inherits the global dialog animation settings.
Future<void> showExportProgressDialog({
  required BuildContext context,
  required ExportProgressController controller,
  required String title,
  required String subtitle,
  required String cancelLabel,
}) {
  return showAnimatedDialog<void>(
    context: context,
    barrierDismissible: false,
    dismissOnEscape: false,
    builder: (dialogContext) => ExportProgressDialog(
      controller: controller,
      title: title,
      subtitle: subtitle,
      cancelLabel: cancelLabel,
    ),
  );
}

String _localizedText(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  final languageCode = Localizations.localeOf(context).languageCode;
  return languageCode.startsWith('zh') ? zh : en;
}
