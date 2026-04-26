part of 'openhand_home_page.dart';

Future<bool?> showWriteCommandConfirmationDialog(
  BuildContext context, {
  required BashCommandApprovalRequest request,
}) {
  return showAnimatedDialog<bool>(
    context: context,
    builder: (dialogContext) =>
        _WriteCommandConfirmationDialog(request: request),
  );
}

class _WriteCommandConfirmationDialog extends StatefulWidget {
  const _WriteCommandConfirmationDialog({required this.request});

  final BashCommandApprovalRequest request;

  @override
  State<_WriteCommandConfirmationDialog> createState() =>
      _WriteCommandConfirmationDialogState();
}

class _WriteCommandConfirmationDialogState
    extends State<_WriteCommandConfirmationDialog> {
  final ScrollController _bodyScrollController = ScrollController();
  final FocusNode _shortcutFocusNode = FocusNode();
  bool _isExpanded = false;

  bool get _isLongCommand =>
      widget.request.command.length > 150 ||
      widget.request.command.contains('\n');

  String get _shortenedCommand {
    if (!_isLongCommand) {
      return widget.request.command;
    }
    final command = widget.request.command.trim();
    final firstLine = command.split('\n').first;
    if (firstLine.length > 120) {
      return '${firstLine.substring(0, 120)}... [omitted ${command.length - 120} chars]';
    }
    return '$firstLine\n... [omitted ${command.length - firstLine.length} chars]';
  }

  void _closeWithResult(bool approved) {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(approved);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _shortcutFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _shortcutFocusNode.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    return Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _closeWithResult(false);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _closeWithResult(true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 860,
            maxHeight: screenSize.height * 0.78,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localizedText(
                    context,
                    zh: '确认执行写命令',
                    en: 'Confirm Write Command',
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Scrollbar(
                    controller: _bodyScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _bodyScrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _localizedText(
                              context,
                              zh: '该 bash 命令可能修改文件或系统状态，需要你确认后才会真正执行。',
                              en: 'This bash command may modify files or system state. OpenHand needs your approval before running it.',
                            ),
                          ),
                          if (_isExpanded)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SelectableText(
                                  widget.request.command,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        fontFamily: 'monospace',
                                        height: 1.45,
                                      ),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                              ),
                              child: SelectableText(
                                _shortenedCommand,
                                maxLines: 3,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontFamily: 'monospace',
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      height: 1.45,
                                    ),
                              ),
                            ),
                          if (_isLongCommand)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _isExpanded = !_isExpanded;
                                  });
                                },
                                icon: Icon(
                                  _isExpanded
                                      ? Icons.unfold_less_rounded
                                      : Icons.unfold_more_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  _isExpanded
                                      ? _localizedText(
                                          context,
                                          zh: '收起命令',
                                          en: 'Collapse',
                                        )
                                      : _localizedText(
                                          context,
                                          zh: '查看完整命令',
                                          en: 'View Full Command',
                                        ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            '${_localizedText(context, zh: '工作目录', en: 'Working Directory')}: ${widget.request.workingDirectory}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _localizedText(
                    context,
                    zh: '快捷键：Enter 确认，Esc 取消',
                    en: 'Shortcuts: Enter confirms, Esc cancels',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OpenHandDialogActionButton.secondary(
                      onPressed: () => _closeWithResult(false),
                      label: AppLocalizations.of(context)!.commonCancel,
                    ),
                    const SizedBox(width: 12),
                    OpenHandDialogActionButton.primary(
                      onPressed: () => _closeWithResult(true),
                      label: _localizedText(
                        context,
                        zh: '允许执行',
                        en: 'Run Command',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
