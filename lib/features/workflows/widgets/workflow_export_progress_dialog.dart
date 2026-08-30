import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
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

const Duration _kProgressAnimationDuration = kOpenHandMotion360;

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
    extends State<_WorkflowExportProgressDialog>
    with SingleTickerProviderStateMixin {
  _ExportStatus _status = _ExportStatus.processing;
  double _targetProgress = 0.04;
  String _message = '正在准备导出任务…';
  String? _outputPath;
  String? _error;
  late final AnimationController _progressController;
  late Animation<double> _progressAnimation;
  Curve _progressCurve = kOpenHandSwitchInCurve;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: _kProgressAnimationDuration,
    );
    _progressAnimation = const AlwaysStoppedAnimation<double>(0.04);
    scheduleMicrotask(_run);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    _progressController.duration = motionSettings.duration;
    _progressCurve = motionSettings.curve.curve;
    if ((!openHandTickerMotionEnabled(context) ||
            motionSettings.disablesAnimation) &&
        _progressAnimation.value != _targetProgress) {
      _settleProgressAnimation();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final path = await widget.task((progress, message) {
        if (!mounted || _status != _ExportStatus.processing) return;
        final boundedProgress = progress.isFinite
            ? progress.clamp(0.0, 0.98).toDouble()
            : _targetProgress;
        _animateProgressTo(boundedProgress, message: message);
      });
      if (!mounted) return;
      _animateProgressTo(1);
      setState(() {
        _status = _ExportStatus.succeeded;
        _message = '${widget.formatLabel} 已成功导出';
        _outputPath = path;
      });
    } catch (error, stack) {
      silentLog('工作流导出', '导出工作流', error, stack);
      if (!mounted) return;
      _animateProgressTo(1);
      setState(() {
        _status = _ExportStatus.failed;
        _message = '${widget.formatLabel} 导出失败';
        _error = error.toString().trim().isEmpty ? '未知错误。' : '$error';
      });
    }
  }

  void _animateProgressTo(double progress, {String? message}) {
    final safeProgress = progress.isFinite
        ? progress.clamp(0.0, 1.0).toDouble()
        : _targetProgress;
    final nextTarget = safeProgress < _targetProgress
        ? _targetProgress
        : safeProgress;
    _targetProgress = nextTarget;
    if (!openHandTickerMotionEnabled(context) ||
        _progressController.duration == Duration.zero) {
      _settleProgressAnimation();
      if (mounted) {
        setState(() {
          if (message != null) _message = message;
        });
      }
      return;
    }
    final oldValue = _progressAnimation.value;
    if (oldValue != nextTarget) {
      _progressAnimation = Tween<double>(begin: oldValue, end: nextTarget)
          .animate(
            CurvedAnimation(parent: _progressController, curve: _progressCurve),
          );
      _progressController.forward(from: 0);
    }
    if (mounted) {
      setState(() {
        if (message != null) _message = message;
      });
    }
  }

  void _settleProgressAnimation() {
    _progressController.stop();
    _progressAnimation = AlwaysStoppedAnimation<double>(_targetProgress);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final motionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
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
                SizedBox.square(
                  dimension: 32,
                  child: _status == _ExportStatus.processing
                      ? CircularProgressIndicator(strokeWidth: 2.6, color: tone)
                      : Icon(icon, color: tone, size: 30),
                ),
                kOpenHandHGap12,
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
              child: AnimatedBuilder(
                animation: _progressController,
                builder: (context, _) => LinearProgressIndicator(
                  minHeight: 6,
                  value: _progressAnimation.value,
                  color: tone,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
            ),
            kOpenHandGap16,
            AnimatedSwitcher(
              duration: motionSettings.entranceDuration,
              reverseDuration: motionSettings.exitDuration,
              switchInCurve: motionSettings.curve.curve,
              switchOutCurve: motionSettings.curve.reverseCurve,
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
      return Row(
        key: const ValueKey<String>('workflow-export-processing'),
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: colors.primary),
          kOpenHandHGap8,
          Expanded(
            child: Text(
              '正在生成完整工作流内容，请稍候。关闭弹窗不会中断文件写入。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
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
        Text(
          failed ? '错误详情' : '文件位置',
          style: theme.textTheme.labelLarge?.copyWith(
            color: tone,
            fontWeight: FontWeight.w800,
          ),
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
