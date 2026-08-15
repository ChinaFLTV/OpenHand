/// 多账号会话快照切换器。
///
/// "保存当前 cookies + 当前 origin storage" → 命名快照入列表；任意时刻点
/// "应用" 即清空当前 cookies 并回放保存值。导出/导入 JSON 跨设备同步。
library;

import 'package:flutter/material.dart';

import '../../app/support/silent_log.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_clipboard.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/date_time_format.dart';
import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_session_controller.dart';

const int _kAccountSnapshotImportMaxChars = 8 * kBytesPerMiB;

Future<void> showWebReverseAccountSnapshotsDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _AccountSnapshotsDialog(controller: controller),
  );
}

class _AccountSnapshotsDialog extends StatefulWidget {
  const _AccountSnapshotsDialog({required this.controller});
  final WebReverseSessionController controller;
  @override
  State<_AccountSnapshotsDialog> createState() =>
      _AccountSnapshotsDialogState();
}

class _AccountSnapshotsDialogState extends State<_AccountSnapshotsDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_busy) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final loc = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final snap = await widget.controller.captureAccountSnapshot(name);
      if (!mounted) return;
      if (snap != null) {
        _nameCtrl.clear();
        showOpenHandSuccessSnack(
          context,
          loc?.webReverseAccountSnapSavedSnapshot(
                snap.name,
                snap.cookies.length,
              ) ??
              'Saved "${snap.name}" (${snap.cookies.length} cookies)',
        );
      }
    } catch (e, st) {
      silentLog('web_reverse_account_snapshots_dialog', '捕获账户快照', e, st);
      if (mounted) {
        showOpenHandErrorSnack(context, loc?.tlCallFailed ?? 'Failed');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(WebReverseAccountSnapshot snap) async {
    if (_busy) return;
    final loc = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final ok = await widget.controller.restoreAccountSnapshot(snap);
      if (!mounted) return;
      if (ok) {
        showOpenHandSuccessSnack(
          context,
          loc?.webReverseAccountSnapAppliedSnapshot(snap.name) ??
              'Applied "${snap.name}". Refresh the page so JS re-reads it.',
          duration: kOpenHandSnackBarDetailedDuration,
        );
      } else {
        showOpenHandErrorSnack(
          context,
          loc?.webReverseAccountSnapApplyFailedNoCdp ??
              'Apply failed: no CDP session',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(WebReverseAccountSnapshot snap) async {
    await widget.controller.deleteAccountSnapshot(snap.id);
  }

  Future<void> _export() async {
    final loc = AppLocalizations.of(context);
    final list = widget.controller.accountSnapshots
        .map((s) => s.toJson())
        .toList(growable: false);
    final json = prettyPrintJson(list);
    await copyWebReverseTextToClipboard(
      context: context,
      text: json,
      successBase:
          loc?.webReverseAccountSnapCopiedCount(list.length) ??
          'Copied ${list.length} snapshots JSON to clipboard',
      logTag: 'web_reverse_account_snapshots_dialog',
      logAction: '导出账号快照',
    );
  }

  Future<void> _import() async {
    final loc = AppLocalizations.of(context);
    final text = (await getOpenHandClipboardText())?.trim() ?? '';
    if (text.isEmpty) return;
    if (!mounted) return;
    try {
      if (text.length > _kAccountSnapshotImportMaxChars) {
        throw const FormatException('快照 JSON 超过导入上限。');
      }
      final entries = decodeStringKeyedJsonMapList(text);
      if (entries == null) throw const FormatException('快照 JSON 必须为数组。');
      final start =
          entries.length > WebReverseSessionController.maxAccountSnapshots
          ? entries.length - WebReverseSessionController.maxAccountSnapshots
          : 0;
      final importedEntries = entries.skip(start);
      final merged = <WebReverseAccountSnapshot>[
        ...widget.controller.accountSnapshots,
        for (final raw in importedEntries)
          WebReverseAccountSnapshot.fromJson(raw),
      ];
      widget.controller.setAccountSnapshots(merged);
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        loc?.webReverseAccountSnapImportedCount(entries.length - start) ??
            'Imported ${entries.length - start} snapshots',
      );
    } catch (e, st) {
      silentLog('web_reverse_account_snapshots_dialog', '导入账户快照', e, st);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        loc?.webReverseAccountSnapNotSnapshotJson ??
            'Clipboard is not a snapshot JSON',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final snaps = widget.controller.accountSnapshots;
        return buildOpenHandToolDialogShell(
          context: context,
          maxWidth: kOpenHandDialogWidthStandard,
          maxHeight: kOpenHandDialogHeightStandard,
          backgroundColor: cs.surfaceContainer,
          insetPadding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _buildHeader(context, loc),
              Divider(height: 1, color: cs.outlineVariant),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        maxLength: WebReverseSessionController
                            .maxAccountSnapshotNameChars,
                        decoration: InputDecoration(
                          labelText:
                              loc?.webReverseAccountSnapNameLabel ??
                              'Name for current account',
                          hintText:
                              loc?.webReverseAccountSnapNameHint ??
                              'e.g. main / test-001',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _capture(),
                      ),
                    ),
                    kOpenHandHGap12,
                    FilledButton.icon(
                      onPressed: _busy ? null : _capture,
                      icon: const Icon(Icons.bookmark_add_rounded, size: 18),
                      label: Text(
                        loc?.webReverseAccountSnapCapture ?? 'Capture',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: snaps.isEmpty ? null : _export,
                      icon: const Icon(Icons.upload_rounded, size: 16),
                      label: Text(
                        loc?.webReverseAccountSnapExportAll ?? 'Export all',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text(loc?.webReverseAccountSnapImport ?? 'Import'),
                    ),
                    const Spacer(),
                    Text(
                      loc?.webReverseAccountSnapSnapshotsCount(snaps.length) ??
                          '${snaps.length} total',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              kOpenHandGap4,
              Expanded(
                child: snaps.isEmpty
                    ? _buildEmpty(theme, cs, loc)
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        itemCount: snaps.length,
                        separatorBuilder: (_, _) => kOpenHandGap8,
                        itemBuilder: (_, idx) =>
                            _buildRow(theme, cs, loc, snaps[idx]),
                      ),
              ),
              buildWebReverseDialogFooter(
                context,
                actions: [
                  OpenHandDialogActionButton.secondary(
                    label: loc?.webReverseAccountSnapClose ?? 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations? loc) {
    return buildOpenHandToolDialogHeader(
      context: context,
      icon: Icons.switch_account_rounded,
      title: loc?.webReverseAccountSnapTitle ?? 'Account Snapshots',
      subtitle:
          loc?.webReverseAccountSnapSubtitle ??
          'Save cookies + localStorage/sessionStorage; one-click switch between accounts',
      onClose: () => Navigator.of(context).pop(),
    );
  }

  Widget _buildEmpty(ThemeData theme, ColorScheme cs, AppLocalizations? loc) {
    return OpenHandInlineEmptyState(
      icon: Icons.account_circle_outlined,
      dense: true,
      message:
          loc?.webReverseAccountSnapEmptyHint ??
          'No snapshots yet. Type a name above → click "Capture".',
    );
  }

  Widget _buildRow(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations? loc,
    WebReverseAccountSnapshot snap,
  ) {
    final stamp = formatMonthDayHm(snap.capturedAt);
    return Container(
      decoration: webReverseSurfaceCardDecoration(cs),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snap.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                kOpenHandGap2,
                Text(
                  [if (snap.origin.isNotEmpty) snap.origin, stamp].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                kOpenHandGap4,
                Wrap(
                  spacing: 6,
                  children: [
                    _badge(theme, cs, '${snap.cookies.length} cookies'),
                    _badge(theme, cs, '${snap.localStorage.length} local'),
                    _badge(theme, cs, '${snap.sessionStorage.length} session'),
                  ],
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _apply(snap),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: Text(loc?.webReverseAccountSnapApply ?? 'Apply'),
          ),
          IconButton(
            tooltip: loc?.webReverseAccountSnapDelete ?? 'Delete',
            onPressed: () => _delete(snap),
            icon: Icon(Icons.delete_outline_rounded, color: cs.error),
          ),
        ],
      ),
    );
  }

  Widget _badge(ThemeData theme, ColorScheme cs, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: cs.secondaryContainer,
      borderRadius: kOpenHandBorderRadius4,
    ),
    child: Text(
      text,
      style: TextStyle(
        color: cs.onSecondaryContainer,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        fontFamily: kOpenHandMonospaceFontFamily,
      ),
    ),
  );
}
