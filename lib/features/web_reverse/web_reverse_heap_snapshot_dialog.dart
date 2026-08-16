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
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/util/byte_size_format.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_session_controller.dart';

Future<void> showWebReverseHeapSnapshotDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
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

  void _finishWithFailure(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = message;
    });
    showOpenHandErrorSnack(context, message);
  }

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
      silentLog('web_reverse_heap_snapshot_dialog', '获取堆快照', e, s);
    }
    if (!mounted) return;
    if (r == null || r.json.isEmpty) {
      _finishWithFailure(
        loc?.webReverseHeapFailed ?? 'Snapshot failed or empty',
      );
      return;
    }
    late final File file;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      file = File('${dir.path}/openhand_heap_$ts.heapsnapshot');
      await writeFileAtomically(file, r.json);
    } catch (e, s) {
      silentLog('web_reverse_heap_snapshot_dialog', '保存堆快照', e, s);
      if (!mounted) return;
      _finishWithFailure(
        loc?.webReverseHeapFailed ?? 'Snapshot failed or empty',
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastSaved = file.path;
      final mb = (r!.bytes / kBytesPerKiB / kBytesPerKiB).toStringAsFixed(2);
      _status =
          loc?.webReverseHeapSaved(file.path, mb) ??
          'Saved: ${file.path} ($mb MB)';
    });
    showOpenHandSuccessSnack(
      context,
      loc?.webReverseHeapSavedToast ?? 'Snapshot saved',
    );
  }

  Future<void> _copyPath() async {
    final loc = AppLocalizations.of(context);
    await copyWebReverseTextToClipboard(
      context: context,
      text: _lastSaved,
      successBase: loc?.webReverseHeapPathCopied ?? 'Path copied',
      logTag: 'web_reverse_heap_snapshot_dialog',
      logAction: '复制堆快照',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    final dialog = buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthStandard,
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
                OpenHandBusyStatusIcon(
                  busy: _busy,
                  icon: Icons.flash_on_rounded,
                  color: cs.secondary,
                ),
                kOpenHandHGap12,
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
    return PopScope(canPop: !_busy, child: dialog);
  }
}
