import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';

Future<OpenRouterSyncResult?> showOpenRouterModelSyncDialog(
  BuildContext context,
) {
  return showAnimatedDialog<OpenRouterSyncResult>(
    context: context,
    barrierDismissible: false,
    dismissOnEscape: false,
    builder: (_) => const _OpenRouterModelSyncDialog(),
  );
}

class _OpenRouterModelSyncDialog extends StatefulWidget {
  const _OpenRouterModelSyncDialog();

  @override
  State<_OpenRouterModelSyncDialog> createState() =>
      _OpenRouterModelSyncDialogState();
}

class _OpenRouterModelSyncDialogState
    extends State<_OpenRouterModelSyncDialog> {
  final OpenRouterModelSyncService _service = OpenRouterModelSyncService();
  OpenRouterSyncProgress _progress = const OpenRouterSyncProgress(
    phase: OpenRouterSyncPhase.fetching,
    total: 0,
    processed: 0,
    upserted: 0,
    skipped: 0,
    failed: 0,
    speed: 0,
    elapsed: Duration.zero,
    detail: '正在准备同步',
  );
  OpenRouterSyncResult? _result;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final result = await _service.sync(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _progress = OpenRouterSyncProgress(
          phase: OpenRouterSyncPhase.completed,
          total: result.total,
          processed: result.processed,
          upserted: result.upserted,
          skipped: result.skipped,
          failed: result.failed,
          speed:
              result.processed /
              (result.elapsed.inMilliseconds / 1000).clamp(
                0.001,
                double.infinity,
              ),
          elapsed: result.elapsed,
          detail: '同步完成',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _progress = OpenRouterSyncProgress(
          phase: OpenRouterSyncPhase.failed,
          total: _progress.total,
          processed: _progress.processed,
          upserted: _progress.upserted,
          skipped: _progress.skipped,
          failed: _progress.failed,
          speed: _progress.speed,
          elapsed: _progress.elapsed,
          detail: '同步失败',
          error: error,
        );
      });
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const l10n = openHandLocalizedText;
    final isRunning = _result == null && _error == null;
    final colorScheme = Theme.of(context).colorScheme;
    return buildOpenHandDialog(
      maxWidth: 700,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 24, 26, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_sync_rounded, color: colorScheme.primary),
                kOpenHandHGap12,
                Expanded(
                  child: Text(
                    l10n(
                      context,
                      zh: '从 OpenRouter 同步模型参数',
                      zhHant: '從 OpenRouter 同步模型參數',
                      en: 'Sync model parameters from OpenRouter',
                      fr: 'Synchroniser les paramètres depuis OpenRouter',
                      de: 'Modellparameter von OpenRouter synchronisieren',
                      ja: 'OpenRouter からモデルパラメータを同期',
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            kOpenHandGap18,
            Text(
              _progress.detail,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            kOpenHandGap12,
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _progress.fraction),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: isRunning && _progress.total == 0 ? null : value,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            kOpenHandGap12,
            _buildStats(context),
            if (_error != null) ...[
              kOpenHandGap12,
              Text(
                '${l10n(context, zh: '错误：', zhHant: '錯誤：', en: 'Error: ', fr: 'Erreur : ', de: 'Fehler: ', ja: 'エラー: ')}$_error',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.error),
              ),
            ],
            kOpenHandGap12,
            Center(
              child: OpenHandDialogActionButton.primary(
                label: isRunning
                    ? l10n(
                        context,
                        zh: '同步中',
                        zhHant: '同步中',
                        en: 'Syncing',
                        fr: 'Synchronisation',
                        de: 'Synchronisierung',
                        ja: '同期中',
                      )
                    : l10n(
                        context,
                        zh: '完成',
                        zhHant: '完成',
                        en: 'Done',
                        fr: 'Terminé',
                        de: 'Fertig',
                        ja: '完了',
                      ),
                onPressed: isRunning
                    ? null
                    : () => Navigator.of(context).pop(_result),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats(BuildContext context) {
    const spacing = 10.0;
    const minimumCardWidth = 160.0;
    final labels = <String, String>{
      '处理': '${_progress.processed} / ${_progress.total}',
      '写入': '${_progress.upserted}',
      '跳过': '${_progress.skipped}',
      '失败': '${_progress.failed}',
      '速度': '${_progress.speed.toStringAsFixed(1)} 条/秒',
      '耗时': _formatDuration(_progress.elapsed),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final columns = !availableWidth.isFinite
            ? 3
            : availableWidth >= minimumCardWidth * 3 + spacing * 2
            ? 3
            : availableWidth >= minimumCardWidth * 2 + spacing
            ? 2
            : 1;
        final cardWidth = availableWidth.isFinite
            ? (availableWidth - spacing * (columns - 1)) / columns
            : 200.0;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: labels.entries
              .map(
                (entry) => SizedBox(
                  width: cardWidth,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key),
                        Flexible(
                          child: Text(
                            entry.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  static String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m ${seconds % 60}s';
  }
}
