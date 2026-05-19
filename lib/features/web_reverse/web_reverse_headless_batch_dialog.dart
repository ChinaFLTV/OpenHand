import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_headless_batch.dart';
import 'web_reverse_session_controller.dart';

/// Headless 批量采集对话框：用户贴一批 URL，选输出目录，逐个跑、实时进度。
/// 复用 controller 现有 `_browserCdp` 连接，所以不会再启第二个浏览器进程。
Future<void> showWebReverseHeadlessBatchDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required bool isZh,
}) async {
  await showAnimatedDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _HeadlessBatchDialog(controller: controller, isZh: isZh),
  );
}

class _HeadlessBatchDialog extends StatefulWidget {
  const _HeadlessBatchDialog({required this.controller, required this.isZh});
  final WebReverseSessionController controller;
  final bool isZh;

  @override
  State<_HeadlessBatchDialog> createState() => _HeadlessBatchDialogState();
}

class _HeadlessBatchDialogState extends State<_HeadlessBatchDialog> {
  final TextEditingController _urlsCtrl = TextEditingController();
  String? _outDir;
  bool _captureScreenshot = true;
  bool _captureNetwork = true;
  bool _captureConsole = true;
  bool _running = false;
  WebReverseHeadlessBatch? _runner;
  final List<HeadlessBatchProgress> _progress = <HeadlessBatchProgress>[];
  List<HeadlessBatchUrlResult>? _results;

  @override
  void dispose() {
    _urlsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickOutDir() async {
    final loc = AppLocalizations.of(context);
    final path = await getDirectoryPath(confirmButtonText:
        loc?.webReverseHeadlessBatchPickOutputDir ?? 'Pick output dir');
    if (path != null && mounted) setState(() => _outDir = path);
  }

  List<String> _parsedUrls() {
    return _urlsCtrl.text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty &&
            (e.startsWith('http://') || e.startsWith('https://')))
        .toList();
  }

  Future<void> _start() async {
    if (_running) return;
    final urls = _parsedUrls();
    final messenger = ScaffoldMessenger.of(context);
    final loc0 = AppLocalizations.of(context);
    if (urls.isEmpty || _outDir == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        loc0?.webReverseHeadlessBatchNeedUrlAndDir
            ?? 'Need at least one http(s):// URL and an output directory',
        duration: const Duration(seconds: 3),
      );
      return;
    }
    final cdp = widget.controller.browserCdpForBatch;
    if (cdp == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        loc0?.webReverseHeadlessBatchBrowserNotReady
            ?? 'Browser is not running yet — start a session first',
        duration: const Duration(seconds: 3),
      );
      return;
    }
    setState(() {
      _running = true;
      _progress.clear();
      _results = null;
    });
    final runner = WebReverseHeadlessBatch(
      cdp: cdp,
      urls: urls,
      outputDir: _outDir!,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress.add(p));
      },
    );
    _runner = runner;
    final results = await runner.run();
    if (!mounted) return;
    final loc1 = AppLocalizations.of(context);
    setState(() {
      _running = false;
      _results = results;
      _runner = null;
    });
    final ok = results.where((r) => r.ok).length;
    OpenHandSnackBar.showSuccessOn(
      context,
      messenger,
      loc1?.webReverseHeadlessBatchFinished(ok, results.length)
          ?? 'Batch finished: $ok/${results.length} ok',
      duration: const Duration(seconds: 3),
    );
  }

  void _cancel() {
    _runner?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.dynamic_feed_rounded,
                      size: 22, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    loc?.webReverseHeadlessBatchTitle ?? 'Headless batch capture',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: loc?.webReverseHeadlessBatchClose ?? 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _running
                        ? null
                        : () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                loc?.webReverseHeadlessBatchDesc
                    ?? 'Open each URL in a background tab, then save network response index, console log and screenshot. Reuses the current browser process (cookies + hooks apply).',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _urlsCtrl,
                minLines: 6,
                maxLines: 10,
                enabled: !_running,
                decoration: InputDecoration(
                  labelText: loc?.webReverseHeadlessBatchUrlsLabel
                      ?? 'URL list (one per line)',
                  hintText: 'https://example.com/page1\nhttps://example.com/page2',
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: loc?.webReverseHeadlessBatchOutputDirLabel
                            ?? 'Output directory',
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(
                        _outDir ?? (loc?.webReverseHeadlessBatchNotSelected ?? '(not selected)'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _running ? null : _pickOutDir,
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: Text(loc?.webReverseHeadlessBatchChoose ?? 'Choose'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilterChip(
                    selected: _captureNetwork,
                    label: Text(loc?.webReverseHeadlessBatchNetwork ?? 'Network'),
                    onSelected: _running
                        ? null
                        : (v) => setState(() => _captureNetwork = v),
                  ),
                  FilterChip(
                    selected: _captureConsole,
                    label: Text(loc?.webReverseHeadlessBatchConsole ?? 'Console'),
                    onSelected: _running
                        ? null
                        : (v) => setState(() => _captureConsole = v),
                  ),
                  FilterChip(
                    selected: _captureScreenshot,
                    label: Text(loc?.webReverseHeadlessBatchScreenshot ?? 'Screenshot'),
                    onSelected: _running
                        ? null
                        : (v) => setState(() => _captureScreenshot = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _running ? null : _start,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(loc?.webReverseHeadlessBatchStart ?? 'Start batch'),
                  ),
                  const SizedBox(width: 8),
                  if (_running)
                    FilledButton.tonalIcon(
                      onPressed: _cancel,
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: Text(loc?.webReverseHeadlessBatchStop ?? 'Stop'),
                    ),
                  const Spacer(),
                  Text(
                    loc?.webReverseHeadlessBatchEventCount(
                            _progress.length, _parsedUrls().length)
                        ?? '${_progress.length} / ${_parsedUrls().length} events',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: _progress.isEmpty && _results == null
                      ? Center(
                          child: Text(
                            loc?.webReverseHeadlessBatchNoProgress ?? 'No progress yet',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          reverse: true,
                          itemCount: _progress.length +
                              (_results == null ? 0 : _results!.length),
                          itemBuilder: (ctx, i) {
                            final results = _results;
                            if (results != null && i < results.length) {
                              final r = results[results.length - 1 - i];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  r.ok
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.error_outline_rounded,
                                  color: r.ok ? Colors.green : cs.error,
                                  size: 18,
                                ),
                                title: Text(
                                  r.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 12),
                                ),
                                subtitle: Text(
                                  r.ok
                                      ? (loc?.webReverseHeadlessBatchResultStats(
                                              r.networkCount, r.consoleCount, r.outDir ?? "")
                                          ?? '${r.networkCount} net · ${r.consoleCount} log · ${r.outDir}')
                                      : (r.error ?? 'failed'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall,
                                ),
                              );
                            }
                            final idx = i -
                                (results == null ? 0 : results.length);
                            final p =
                                _progress[_progress.length - 1 - idx];
                            return ListTile(
                              dense: true,
                              leading: _phaseIcon(p.phase, cs),
                              title: Text(
                                '#${p.index + 1}/${p.total}  ${p.url}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12),
                              ),
                              subtitle: Text(
                                _phaseLabel(p.phase, loc) +
                                    (p.message != null && p.message!.isNotEmpty
                                        ? ' — ${p.message}'
                                        : ''),
                                style: theme.textTheme.labelSmall,
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phaseIcon(HeadlessBatchPhase phase, ColorScheme cs) {
    switch (phase) {
      case HeadlessBatchPhase.starting:
        return Icon(Icons.hourglass_top_rounded, size: 18, color: cs.primary);
      case HeadlessBatchPhase.navigating:
        return Icon(Icons.travel_explore_rounded,
            size: 18, color: cs.primary);
      case HeadlessBatchPhase.waitingLoad:
        return Icon(Icons.cloud_download_outlined,
            size: 18, color: cs.primary);
      case HeadlessBatchPhase.capturingScreenshot:
        return Icon(Icons.camera_alt_outlined, size: 18, color: cs.primary);
      case HeadlessBatchPhase.done:
        return const Icon(Icons.check_circle_outline_rounded,
            size: 18, color: Colors.green);
      case HeadlessBatchPhase.failed:
        return Icon(Icons.error_outline_rounded, size: 18, color: cs.error);
      case HeadlessBatchPhase.cancelled:
        return Icon(Icons.block_rounded, size: 18, color: cs.onSurfaceVariant);
    }
  }

  String _phaseLabel(HeadlessBatchPhase phase, AppLocalizations? loc) {
    switch (phase) {
      case HeadlessBatchPhase.starting:
        return loc?.webReverseHeadlessBatchPhaseStarting ?? 'Preparing';
      case HeadlessBatchPhase.navigating:
        return loc?.webReverseHeadlessBatchPhaseNavigating ?? 'Navigating';
      case HeadlessBatchPhase.waitingLoad:
        return loc?.webReverseHeadlessBatchPhaseWaitingLoad ?? 'Waiting load';
      case HeadlessBatchPhase.capturingScreenshot:
        return loc?.webReverseHeadlessBatchPhaseCapturingScreenshot
            ?? 'Capturing screenshot';
      case HeadlessBatchPhase.done:
        return loc?.webReverseHeadlessBatchPhaseDone ?? 'Done';
      case HeadlessBatchPhase.failed:
        return loc?.webReverseHeadlessBatchPhaseFailed ?? 'Failed';
      case HeadlessBatchPhase.cancelled:
        return loc?.webReverseHeadlessBatchPhaseCancelled ?? 'Cancelled';
    }
  }
}
