import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_spacing.dart';

typedef WorkflowExportTask =
    Future<String> Function(void Function(double progress, String message));

Future<void> showWorkflowExportProgressDialog({
  required BuildContext context,
  required String formatLabel,
  required WorkflowExportTask task,
}) {
  return showAnimatedDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _WorkflowExportProgressDialog(formatLabel: formatLabel, task: task),
  );
}

enum _ExportStatus { processing, succeeded, failed }

class _WorkflowExportProgressDialog extends StatefulWidget {
  const _WorkflowExportProgressDialog({
    required this.formatLabel,
    required this.task,
  });

  final String formatLabel;
  final WorkflowExportTask task;

  @override
  State<_WorkflowExportProgressDialog> createState() =>
      _WorkflowExportProgressDialogState();
}

class _WorkflowExportProgressDialogState
    extends State<_WorkflowExportProgressDialog> {
  _ExportStatus _status = _ExportStatus.processing;
  double _progress = 0.04;
  String _message = '正在准备导出任务…';
  String? _outputPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_run);
  }

  Future<void> _run() async {
    try {
      final path = await widget.task((progress, message) {
        if (!mounted || _status != _ExportStatus.processing) return;
        setState(() {
          _progress = progress.clamp(0, 0.98);
          _message = message;
        });
      });
      if (!mounted) return;
      setState(() {
        _status = _ExportStatus.succeeded;
        _progress = 1;
        _message = '${widget.formatLabel} 已成功导出';
        _outputPath = path;
      });
    } catch (error, stack) {
      silentLog('工作流导出', '导出工作流', error, stack);
      if (!mounted) return;
      setState(() {
        _status = _ExportStatus.failed;
        _progress = 1;
        _message = '${widget.formatLabel} 导出失败';
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final succeeded = _status == _ExportStatus.succeeded;
    final failed = _status == _ExportStatus.failed;
    final tone = failed
        ? colors.error
        : succeeded
        ? OpenHandStatusColors.success
        : colors.primary;
    final icon = failed
        ? Icons.error_outline_rounded
        : succeeded
        ? Icons.task_alt_rounded
        : Icons.file_upload_outlined;
    return buildOpenHandDialog(
      maxWidth: kOpenHandDialogWidthCompact,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: kOpenHandBorderRadius14,
                  ),
                  alignment: Alignment.center,
                  child: _status == _ExportStatus.processing
                      ? SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: tone,
                          ),
                        )
                      : Icon(icon, color: tone, size: 28),
                ),
                kOpenHandHGap14,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _status == _ExportStatus.processing
                            ? '正在导出工作流'
                            : succeeded
                            ? '导出完成'
                            : '导出失败',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      kOpenHandGap4,
                      Text(
                        _message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox.square(
                  dimension: 42,
                  child: IconButton(
                    key: const ValueKey<String>(
                      'workflow-export-progress-close',
                    ),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      shape: const RoundedRectangleBorder(
                        borderRadius: kOpenHandBorderRadius12,
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ],
            ),
            kOpenHandGap20,
            ClipRRect(
              borderRadius: kOpenHandBorderRadius8,
              child: LinearProgressIndicator(
                minHeight: 8,
                value: _progress,
                color: tone,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
            kOpenHandGap16,
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _resultPanel(context),
            ),
            if (_status != _ExportStatus.processing) ...[
              kOpenHandGap18,
              Center(
                child: OpenHandDialogActionButton.primary(
                  label: '完成',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultPanel(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (_status == _ExportStatus.processing) {
      return Container(
        key: const ValueKey<String>('workflow-export-processing'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.34),
          borderRadius: kOpenHandBorderRadius14,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: colors.primary),
            kOpenHandHGap12,
            Expanded(
              child: Text(
                '正在生成完整工作流内容，请稍候。关闭弹窗不会中断文件写入。',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }
    final failed = _status == _ExportStatus.failed;
    final tone = failed ? colors.error : OpenHandStatusColors.success;
    final detail = failed ? _error ?? '未知错误。' : _outputPath ?? '';
    return Column(
      key: ValueKey<String>(
        failed ? 'workflow-export-failed' : 'workflow-export-succeeded',
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              failed ? Icons.error_outline_rounded : Icons.folder_open_rounded,
              size: 18,
              color: tone,
            ),
            kOpenHandHGap8,
            Text(
              failed ? '错误详情' : '文件位置',
              style: theme.textTheme.labelLarge?.copyWith(
                color: tone,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        kOpenHandGap8,
        SelectableText(
          detail,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
      ],
    );
  }
}
