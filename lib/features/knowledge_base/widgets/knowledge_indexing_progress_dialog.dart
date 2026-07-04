import 'package:flutter/material.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_preference.dart';
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
                duration: openHandMotionDuration(
                  context,
                  const Duration(milliseconds: 220),
                ),
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
                              zhHant: '正在停止建構並清理已寫入的臨時向量，請稍候。',
                              en: 'Stopping indexing and cleaning partial vectors. Please wait.',
                              fr: 'Arrêt de l’indexation et nettoyage des vecteurs partiels. Patientez.',
                              de: 'Indexierung wird gestoppt und Teilvektoren werden bereinigt. Bitte warten.',
                              ja: 'インデックス作成を停止し、一時ベクトルをクリーンアップしています。お待ちください。',
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
                  zhHant: '強制停止',
                  en: 'Force Stop',
                  fr: 'Forcer l’arrêt',
                  de: 'Stopp erzwingen',
                  ja: '強制停止',
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
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _begin, end: _end),
      duration: openHandMotionDuration(
        context,
        const Duration(milliseconds: 380),
      ),
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
    final motionEnabled = openHandTickerMotionEnabled(context);
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
          if (motionEnabled && !cancelling)
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
  return switch (phase) {
    KnowledgeIndexingPhase.preparing => openHandLocalizedText(
      context,
      zh: '准备构建向量',
      zhHant: '準備建構向量',
      en: 'Preparing index',
      fr: 'Préparation de l’index',
      de: 'Index wird vorbereitet',
      ja: 'インデックスを準備中',
    ),
    KnowledgeIndexingPhase.parsing => openHandLocalizedText(
      context,
      zh: '解析文档中',
      zhHant: '正在解析文件',
      en: 'Parsing document',
      fr: 'Analyse du document',
      de: 'Dokument wird geparst',
      ja: 'ドキュメントを解析中',
    ),
    KnowledgeIndexingPhase.storing => openHandLocalizedText(
      context,
      zh: '保存来源中',
      zhHant: '正在儲存來源',
      en: 'Storing source',
      fr: 'Enregistrement de la source',
      de: 'Quelle wird gespeichert',
      ja: 'ソースを保存中',
    ),
    KnowledgeIndexingPhase.chunking => openHandLocalizedText(
      context,
      zh: '切分内容中',
      zhHant: '正在切分內容',
      en: 'Chunking content',
      fr: 'Découpage du contenu',
      de: 'Inhalt wird segmentiert',
      ja: 'コンテンツを分割中',
    ),
    KnowledgeIndexingPhase.ensuringCollection => openHandLocalizedText(
      context,
      zh: '检查向量集合',
      zhHant: '檢查向量集合',
      en: 'Checking vector collection',
      fr: 'Vérification de la collection vectorielle',
      de: 'Vektorsammlung wird geprüft',
      ja: 'ベクトルコレクションを確認中',
    ),
    KnowledgeIndexingPhase.embedding => openHandLocalizedText(
      context,
      zh: '构建向量中',
      zhHant: '正在建構向量',
      en: 'Building vectors',
      fr: 'Création des vecteurs',
      de: 'Vektoren werden erstellt',
      ja: 'ベクトルを構築中',
    ),
    KnowledgeIndexingPhase.upserting => openHandLocalizedText(
      context,
      zh: '写入向量中',
      zhHant: '正在寫入向量',
      en: 'Writing vectors',
      fr: 'Écriture des vecteurs',
      de: 'Vektoren werden geschrieben',
      ja: 'ベクトルを書き込み中',
    ),
    KnowledgeIndexingPhase.finalizing => openHandLocalizedText(
      context,
      zh: '收尾索引中',
      zhHant: '正在完成索引',
      en: 'Finalizing index',
      fr: 'Finalisation de l’index',
      de: 'Index wird abgeschlossen',
      ja: 'インデックスを仕上げ中',
    ),
    KnowledgeIndexingPhase.completed => openHandLocalizedText(
      context,
      zh: '索引完成',
      zhHant: '索引完成',
      en: 'Index completed',
      fr: 'Index terminé',
      de: 'Index abgeschlossen',
      ja: 'インデックス完了',
    ),
    KnowledgeIndexingPhase.cancelling => openHandLocalizedText(
      context,
      zh: '正在停止',
      zhHant: '正在停止',
      en: 'Stopping',
      fr: 'Arrêt en cours',
      de: 'Wird gestoppt',
      ja: '停止中',
    ),
    KnowledgeIndexingPhase.cancelled => openHandLocalizedText(
      context,
      zh: '已停止',
      zhHant: '已停止',
      en: 'Stopped',
      fr: 'Arrêté',
      de: 'Gestoppt',
      ja: '停止済み',
    ),
  };
}

String _progressLabel(
  BuildContext context,
  KnowledgeIndexingProgress progress,
) {
  if (progress.hasChunkProgress) {
    final processed = progress.processedChunks.clamp(0, progress.totalChunks);
    return openHandLocalizedText(
      context,
      zh: '$processed / ${progress.totalChunks} 个分块',
      zhHant: '$processed / ${progress.totalChunks} 個分塊',
      en: '$processed / ${progress.totalChunks} chunks',
      fr: '$processed / ${progress.totalChunks} fragments',
      de: '$processed / ${progress.totalChunks} Abschnitte',
      ja: '$processed / ${progress.totalChunks} チャンク',
    );
  }
  return openHandLocalizedText(
    context,
    zh: '正在等待当前步骤完成…',
    zhHant: '正在等待目前步驟完成…',
    en: 'Waiting for the current step…',
    fr: 'En attente de l’étape en cours…',
    de: 'Warten auf den aktuellen Schritt…',
    ja: '現在のステップの完了を待機中…',
  );
}
