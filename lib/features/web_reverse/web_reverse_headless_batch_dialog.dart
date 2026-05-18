import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

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
    final path = await getDirectoryPath(confirmButtonText:
        widget.isZh ? '选择输出目录' : 'Pick output dir');
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
    if (urls.isEmpty || _outDir == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        widget.isZh
            ? '请先填入至少一条 http(s):// URL，并选好输出目录'
            : 'Need at least one http(s):// URL and an output directory',
        duration: const Duration(seconds: 3),
      );
      return;
    }
    final cdp = widget.controller.browserCdpForBatch;
    if (cdp == null) {
      OpenHandSnackBar.showErrorOn(
        context,
        messenger,
        widget.isZh
            ? '浏览器尚未启动，请先在主面板启动会话再来批量采集'
            : 'Browser is not running yet — start a session first',
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
    setState(() {
      _running = false;
      _results = results;
      _runner = null;
    });
    final ok = results.where((r) => r.ok).length;
    OpenHandSnackBar.showSuccessOn(
      context,
      messenger,
      widget.isZh
          ? '批量采集结束：$ok/${results.length} 成功'
          : 'Batch finished: $ok/${results.length} ok',
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
    final isZh = widget.isZh;
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
                    isZh ? 'Headless 批量采集' : 'Headless batch capture',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: isZh ? '关闭' : 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _running
                        ? null
                        : () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isZh
                    ? '逐 URL 后台开新 tab，加载完成后保存网络响应索引 / 控制台日志 / 截图。使用当前浏览器进程，复用 cookie 与 Hook。'
                    : 'Open each URL in a background tab, then save network response index, console log and screenshot. Reuses the current browser process (cookies + hooks apply).',
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
                  labelText: isZh ? 'URL 列表（每行一条）' : 'URL list (one per line)',
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
                        labelText: isZh ? '输出目录' : 'Output directory',
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(
                        _outDir ?? (isZh ? '（未选）' : '(not selected)'),
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
                    label: Text(isZh ? '选择' : 'Choose'),
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
                    label: Text(isZh ? '网络' : 'Network'),
                    onSelected: _running
                        ? null
                        : (v) => setState(() => _captureNetwork = v),
                  ),
                  FilterChip(
                    selected: _captureConsole,
                    label: Text(isZh ? '控制台' : 'Console'),
                    onSelected: _running
                        ? null
                        : (v) => setState(() => _captureConsole = v),
                  ),
                  FilterChip(
                    selected: _captureScreenshot,
                    label: Text(isZh ? '截图' : 'Screenshot'),
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
                    label: Text(isZh ? '开始批量' : 'Start batch'),
                  ),
                  const SizedBox(width: 8),
                  if (_running)
                    FilledButton.tonalIcon(
                      onPressed: _cancel,
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: Text(isZh ? '停止' : 'Stop'),
                    ),
                  const Spacer(),
                  Text(
                    isZh
                        ? '${_progress.length} / ${_parsedUrls().length} 条事件'
                        : '${_progress.length} / ${_parsedUrls().length} events',
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
                            isZh ? '尚无进度' : 'No progress yet',
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
                                      ? (isZh
                                          ? '${r.networkCount} 网络 · ${r.consoleCount} 日志 · ${r.outDir}'
                                          : '${r.networkCount} net · ${r.consoleCount} log · ${r.outDir}')
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
                                _phaseLabel(p.phase, isZh) +
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

  String _phaseLabel(HeadlessBatchPhase phase, bool isZh) {
    switch (phase) {
      case HeadlessBatchPhase.starting:
        return isZh ? '准备' : 'Preparing';
      case HeadlessBatchPhase.navigating:
        return isZh ? '导航中' : 'Navigating';
      case HeadlessBatchPhase.waitingLoad:
        return isZh ? '等待 load' : 'Waiting load';
      case HeadlessBatchPhase.capturingScreenshot:
        return isZh ? '截图中' : 'Capturing screenshot';
      case HeadlessBatchPhase.done:
        return isZh ? '完成' : 'Done';
      case HeadlessBatchPhase.failed:
        return isZh ? '失败' : 'Failed';
      case HeadlessBatchPhase.cancelled:
        return isZh ? '已取消' : 'Cancelled';
    }
  }
}
