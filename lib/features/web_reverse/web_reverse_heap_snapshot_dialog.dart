/// Heap Snapshot 抓取面板 — 包装 [WebReverseSessionController.takeHeapSnapshot]。
///
/// HeapProfiler.takeHeapSnapshot → 拼接 .heapsnapshot 文本 → 落盘
/// （Chrome DevTools / Edge DevTools 的 Memory tab 可加载）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_session_controller.dart';

const double _kHeapDialogMaxWidth = 640;

Future<void> showWebReverseHeapSnapshotDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _HeapDialog(controller: controller),
  );
}

class _HeapDialog extends StatefulWidget {
  const _HeapDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_HeapDialog> createState() => _HeapDialogState();
}

class _HeapDialogState extends State<_HeapDialog> {
  bool _busy = false;
  String _status = '';
  String _lastSaved = '';
  int _lastBytes = 0;

  Future<void> _take() async {
    final loc = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status = loc?.webReverseHeapTaking ?? 'Taking heap snapshot...';
    });
    ({String json, int bytes})? r;
    try {
      r = await widget.controller.takeHeapSnapshot();
    } catch (e, s) {
      silentLog('web-reverse', 'heap-snapshot.take', e, s);
    }
    if (!mounted) return;
    if (r == null || r.json.isEmpty) {
      setState(() {
        _busy = false;
        _status = loc?.webReverseHeapFailed ?? 'Snapshot failed or empty';
      });
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/openhand_heap_$ts.heapsnapshot');
    await file.writeAsString(r.json);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastSaved = file.path;
      _lastBytes = r!.bytes;
      final mb = (_lastBytes / 1024 / 1024).toStringAsFixed(2);
      _status =
          loc?.webReverseHeapSaved(file.path, mb) ??
          'Saved: ${file.path} ($mb MB)';
    });
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        loc?.webReverseHeapSavedToast ?? 'Snapshot saved',
      );
    }
  }

  Future<void> _copyPath() async {
    late final WebReverseClipboardCopyResult copied;
    try {
      copied = await setWebReverseClipboardText(_lastSaved);
    } catch (e, s) {
      silentLog('web-reverse', 'heap-snapshot.clipboard', e, s);
      return;
    }
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    final loc = AppLocalizations.of(context);
    if (m != null) {
      OpenHandSnackBar.showSuccessOn(
        context,
        m,
        webReverseClipboardSnackMessage(
          isZh: loc?.localeName.startsWith('zh') ?? false,
          base: loc?.webReverseHeapPathCopied ?? 'Path copied',
          result: copied,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: _kHeapDialogMaxWidth,
      backgroundColor: cs.surfaceContainer,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.memory_rounded,
            title: 'Heap Snapshot',
            subtitle:
                loc?.webReverseHeapSubtitle ??
                'HeapProfiler.takeHeapSnapshot → .heapsnapshot',
            closeEnabled: !_busy,
            onClose: () => Navigator.of(context).pop(),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(
              children: [
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.flash_on_rounded, color: cs.secondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _status.isEmpty
                        ? (loc?.webReverseHeapEmptyHint ??
                              'Click below to capture current page V8 heap snapshot.\nLarge pages may produce 50MB+ files.')
                        : _status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          buildOpenHandDialogActionsBar(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            spacing: 10,
            actions: [
              if (_lastSaved.isNotEmpty)
                OpenHandDialogActionButton.secondary(
                  label: loc?.webReverseHeapCopyPath ?? 'Copy path',
                  icon: Icons.copy_rounded,
                  onPressed: _copyPath,
                ),
              OpenHandDialogActionButton.secondary(
                label: loc?.webReverseHeapTake ?? 'Take Snapshot',
                icon: Icons.camera_alt_rounded,
                busy: _busy,
                onPressed: _busy ? null : _take,
              ),
              OpenHandDialogActionButton.primary(
                label: loc?.commonClose ?? 'Close',
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
