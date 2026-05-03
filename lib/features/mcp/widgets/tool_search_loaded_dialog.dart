import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';

/// 弹出 [ToolSearchLoadedDialog] 的便捷入口。
/// 复用方：[OpenHandHomePage] 的 SnackBar action、MCP 设置页快捷入口、
/// 以及未来其它需要展示「本会话已加载 MCP 工具」的场景。
Future<void> showToolSearchLoadedDialog(
  BuildContext context, {
  required List<String> names,
  void Function()? onClear,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        ToolSearchLoadedDialog(initialNames: names, onClear: onClear),
  );
}

/// 列出本会话已通过 `ToolSearch` 加载的 MCP 工具完整名（含 `mcp__` 前缀）。
/// 每行右侧提供「复制 select:NAME」按钮；当 [onClear] 非空时，标题栏显示
/// 「清空已加载列表」按钮。
class ToolSearchLoadedDialog extends StatefulWidget {
  const ToolSearchLoadedDialog({
    super.key,
    required this.initialNames,
    this.onClear,
  });

  final List<String> initialNames;
  final void Function()? onClear;

  @override
  State<ToolSearchLoadedDialog> createState() => _ToolSearchLoadedDialogState();
}

class _ToolSearchLoadedDialogState extends State<ToolSearchLoadedDialog> {
  late List<String> _names = List<String>.unmodifiable(widget.initialNames);

  void _handleClear() {
    final onClear = widget.onClear;
    if (onClear == null) return;
    onClear();
    setState(() {
      _names = const <String>[];
    });
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(l10n.snackToolSearchLoadedClearedToast),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleCopy(String name) async {
    await Clipboard.setData(ClipboardData(text: 'select:$name'));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(l10n.snackToolSearchLoadedCopiedToast),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(l10n.snackToolSearchLoadedDialogTitle)),
          if (widget.onClear != null && _names.isNotEmpty)
            TextButton.icon(
              onPressed: _handleClear,
              icon: const Icon(Icons.delete_sweep_rounded, size: 16),
              label: Text(l10n.snackToolSearchLoadedClearAction),
            ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: _names.isEmpty
            ? Text('—', style: Theme.of(context).textTheme.bodyMedium)
            : Scrollbar(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _names.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final name = _names[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.extension_rounded, size: 18),
                      title: SelectableText(
                        name,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      trailing: IconButton(
                        tooltip:
                            '${l10n.snackToolSearchLoadedCopyAction}$name',
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () => _handleCopy(name),
                      ),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.snackToolSearchLoadedDialogClose),
        ),
      ],
    );
  }
}
