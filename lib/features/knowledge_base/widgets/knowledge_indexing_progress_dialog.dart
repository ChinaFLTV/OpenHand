import 'package:flutter/material.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/util/localized_text.dart';
import '../service/knowledge_indexing_control.dart';

class KnowledgeIndexingProgressController extends ChangeNotifier {
  KnowledgeIndexingProgressController({
    required this.cancelToken,
    KnowledgeIndexingProgress initialProgress =
        const KnowledgeIndexingProgress(),
  }) : _progress = initialProgress;

  final KnowledgeIndexingCancelToken cancelToken;

  KnowledgeIndexingProgress _progress;
  KnowledgeIndexingProgress get progress => _progress;

  bool _finished = false;
  bool get finished => _finished;

  void updateProgress(KnowledgeIndexingProgress next) {
    if (_finished) return;
    _progress = next;
    notifyListeners();
  }

  void requestCancel() {
    if (_finished || cancelToken.isCancelled) return;
    cancelToken.cancel();
    _progress = _progress.copyWith(phase: KnowledgeIndexingPhase.cancelling);
    notifyListeners();
  }

  void markFinished() {
    if (_finished) return;
    _finished = true;
    notifyListeners();
  }
}

Future<T?> runKnowledgeIndexingProgressTask<T>({
  required BuildContext context,
  required KnowledgeIndexingProgressController controller,
  required String title,
  required String subtitle,
  required Future<T?> Function() task,
}) async {
  var dialogClosed = false;
  final dialogFuture = showKnowledgeIndexingProgressDialog(
    context: context,
    controller: controller,
    title: title,
    subtitle: subtitle,
  ).whenComplete(() => dialogClosed = true);
  try {
    return await task();
  } finally {
    controller.markFinished();
    var requestedClose = false;
    if (!dialogClosed && context.mounted) {
      requestedClose = true;
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (requestedClose) {
      await dialogFuture;
    }
  }
}

Future<void> showKnowledgeIndexingProgressDialog({
  required BuildContext context,
  required KnowledgeIndexingProgressController controller,
  required String title,
  required String subtitle,
}) {
  return showAnimatedDialog<void>(
    context: context,
    barrierDismissible: false,
    dismissOnEscape: false,
    builder: (_) => _KnowledgeIndexingProgressDialog(
      controller: controller,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class _KnowledgeIndexingProgressDialog extends StatelessWidget {
  const _KnowledgeIndexingProgressDialog({
    required this.controller,
    required this.title,
    required this.subtitle,
  });

  final KnowledgeIndexingProgressController controller;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return PopScope(
      canPop: controller.finished,
      child: buildOpenHandAlertDialog(
        title: Text(title),
        content: buildOpenHandDialogConstrainedContent(
          width: 460,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final progress = controller.progress;
              final cancelling = controller.cancelToken.isCancelled;
              return AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _KnowledgeIndexingPulseIcon(cancelling: cancelling),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _phaseLabel(context, progress.phase),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                progress.sourceTitle.trim().isEmpty
                                    ? subtitle
                                    : progress.sourceTitle.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: _KnowledgeIndexingProgressBar(
                        value: progress.fraction,
                        indeterminate: cancelling,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _progressLabel(context, progress),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (progress.detail.trim().isNotEmpty)
                          Text(
                            progress.detail.trim(),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    if (cancelling) ...[
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(
                            alpha: 0.42,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.error.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Text(
                            openHandLocalizedText(
                              context,
                              zh: '正在停止构建并清理已写入的临时向量，请稍候。',
                              en: 'Stopping indexing and cleaning partial vectors. Please wait.',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final disabled =
                  controller.finished || controller.cancelToken.isCancelled;
              return OpenHandDialogActionButton.destructive(
                onPressed: disabled ? null : controller.requestCancel,
                icon: Icons.stop_circle_outlined,
                label: openHandLocalizedText(
                  context,
                  zh: '强制停止',
                  en: 'Force Stop',
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KnowledgeIndexingProgressBar extends StatefulWidget {
  const _KnowledgeIndexingProgressBar({
    required this.value,
    required this.indeterminate,
  });

  final double? value;
  final bool indeterminate;

  @override
  State<_KnowledgeIndexingProgressBar> createState() =>
      _KnowledgeIndexingProgressBarState();
}

class _KnowledgeIndexingProgressBarState
    extends State<_KnowledgeIndexingProgressBar> {
  double _begin = 0;
  double _end = 0;

  @override
  void initState() {
    super.initState();
    final initialValue = _normalizedValue(widget.value);
    _begin = initialValue;
    _end = initialValue;
  }

  @override
  void didUpdateWidget(covariant _KnowledgeIndexingProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.indeterminate || widget.value == null) {
      return;
    }
    final next = _normalizedValue(widget.value);
    if (next == _end) {
      return;
    }
    _begin = _normalizedValue(oldWidget.value ?? _end);
    _end = next;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.indeterminate || widget.value == null) {
      return const LinearProgressIndicator(minHeight: 9);
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _begin, end: _end),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return LinearProgressIndicator(minHeight: 9, value: value);
      },
    );
  }

  double _normalizedValue(double? value) {
    if (value == null || value.isNaN || !value.isFinite) {
      return 0;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }
}

class _KnowledgeIndexingPulseIcon extends StatelessWidget {
  const _KnowledgeIndexingPulseIcon({required this.cancelling});

  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: cancelling
                  ? colorScheme.errorContainer
                  : colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              cancelling ? Icons.stop_circle_outlined : Icons.hub_outlined,
              color: cancelling
                  ? colorScheme.onErrorContainer
                  : colorScheme.onPrimaryContainer,
              size: 28,
            ),
          ),
          if (!reduceMotion && !cancelling)
            Positioned.fill(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: colorScheme.primary,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
        ],
      ),
    );
  }
}

String _phaseLabel(BuildContext context, KnowledgeIndexingPhase phase) {
  final isZh = openHandIsChineseLocale(context);
  return switch (phase) {
    KnowledgeIndexingPhase.preparing => isZh ? '准备构建向量' : 'Preparing index',
    KnowledgeIndexingPhase.parsing => isZh ? '解析文档中' : 'Parsing document',
    KnowledgeIndexingPhase.storing => isZh ? '保存来源中' : 'Storing source',
    KnowledgeIndexingPhase.chunking => isZh ? '切分内容中' : 'Chunking content',
    KnowledgeIndexingPhase.ensuringCollection =>
      isZh ? '检查向量集合' : 'Checking vector collection',
    KnowledgeIndexingPhase.embedding => isZh ? '构建向量中' : 'Building vectors',
    KnowledgeIndexingPhase.upserting => isZh ? '写入向量中' : 'Writing vectors',
    KnowledgeIndexingPhase.finalizing => isZh ? '收尾索引中' : 'Finalizing index',
    KnowledgeIndexingPhase.completed => isZh ? '索引完成' : 'Index completed',
    KnowledgeIndexingPhase.cancelling => isZh ? '正在停止' : 'Stopping',
    KnowledgeIndexingPhase.cancelled => isZh ? '已停止' : 'Stopped',
  };
}

String _progressLabel(
  BuildContext context,
  KnowledgeIndexingProgress progress,
) {
  final isZh = openHandIsChineseLocale(context);
  if (progress.hasChunkProgress) {
    return isZh
        ? '${progress.processedChunks.clamp(0, progress.totalChunks)} / ${progress.totalChunks} 个分块'
        : '${progress.processedChunks.clamp(0, progress.totalChunks)} / ${progress.totalChunks} chunks';
  }
  return isZh ? '正在等待当前步骤完成…' : 'Waiting for the current step…';
}
