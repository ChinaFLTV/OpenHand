part of 'openhand_home_page.dart';

class _ComposerPanel extends StatefulWidget {
  const _ComposerPanel({
    required this.currentSession,
    required this.liveRuntimeToolPreview,
    required this.controller,
    required this.selectedModel,
    required this.availableModels,
    required this.onModelSelected,
    required this.focusNode,
    required this.composerHeight,
    required this.isCollapsed,
    required this.onCollapsedChanged,
    required this.autoFollowEnabled,
    required this.onToggleAutoFollow,
    required this.sendPhase,
    required this.canStopSending,
    required this.sessionMode,
    required this.onSessionModeChanged,
    required this.pendingAttachments,
    required this.attachmentsEnabled,
    required this.onPickAttachments,
    required this.onRemoveAttachment,
    required this.onReorderAttachments,
    required this.onSend,
    required this.onStop,
    required this.creationMode,
    required this.onCreationModeChanged,
    required this.fullAccessPermission,
    required this.onToggleFullAccessPermission,
    required this.editingMessageId,
    required this.onCancelEditing,
    required this.queuedMessages,
    required this.onRemoveQueuedMessage,
    required this.onMoveQueuedMessage,
    required this.onEditQueuedMessage,
  });

  final AiSession? currentSession;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final TextEditingController controller;
  final AiModelConfig? selectedModel;
  final List<AiModelConfig> availableModels;
  final void Function(String providerConfigId, String modelId) onModelSelected;
  final FocusNode focusNode;
  final double composerHeight;
  final bool isCollapsed;
  final ValueChanged<bool> onCollapsedChanged;
  final bool autoFollowEnabled;
  final VoidCallback onToggleAutoFollow;
  final AiSendPhase sendPhase;
  final bool canStopSending;
  final AiSessionMode sessionMode;
  final ValueChanged<AiSessionMode> onSessionModeChanged;
  final List<_ComposerAttachmentDraft> pendingAttachments;
  final bool attachmentsEnabled;
  final Future<void> Function() onPickAttachments;
  final ValueChanged<String> onRemoveAttachment;
  final void Function(int oldIndex, int newIndex) onReorderAttachments;
  final Future<void> Function() onSend;
  final Future<void> Function() onStop;
  final _CreationMode creationMode;
  final ValueChanged<_CreationMode> onCreationModeChanged;
  final bool fullAccessPermission;
  final ValueChanged<bool> onToggleFullAccessPermission;
  final String? editingMessageId;
  final Future<void> Function() onCancelEditing;
  final List<_QueuedMessage> queuedMessages;
  final ValueChanged<int> onRemoveQueuedMessage;
  final void Function(int from, int to) onMoveQueuedMessage;
  final void Function(int index, String newText) onEditQueuedMessage;

  @override
  State<_ComposerPanel> createState() => _ComposerPanelState();
}

class _ComposerPanelState extends State<_ComposerPanel> {
  List<Widget> _buildModelMenuItems(BuildContext context) {
    final items = <Widget>[];
    final selectedId = widget.selectedModel?.id;
    final selectedModelId = widget.selectedModel?.modelId;
    for (final provider in widget.availableModels) {
      final allIds = provider.allModelIds;
      if (allIds.isEmpty) {
        // Provider with no discovered models — show as single entry.
        final isActive =
            provider.id == selectedId && provider.modelId == selectedModelId;
        items.add(
          MenuItemButton(
            leadingIcon: Icon(
              isActive
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
            ),
            onPressed: () =>
                widget.onModelSelected(provider.id, provider.modelId),
            child: Text(provider.providerLabel),
          ),
        );
      } else {
        // Provider with models — show group header + sub-items.
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              '${provider.providerLabel}  (${provider.protocolType.storageValue})',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        for (final modelId in allIds) {
          final isActive =
              provider.id == selectedId && modelId == selectedModelId;
          items.add(
            MenuItemButton(
              leadingIcon: Icon(
                isActive
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
              ),
              onPressed: () => widget.onModelSelected(provider.id, modelId),
              child: Text(modelId),
            ),
          );
        }
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final selectedModelLabel =
        widget.selectedModel?.displayName ?? l10n.chatModelButton;
    final isCompressing = widget.sendPhase == AiSendPhase.compressing;
    final isSendingMessage = widget.sendPhase == AiSendPhase.sendingMessage;
    final isResponding = widget.sendPhase == AiSendPhase.responding;
    final isBusy = widget.sendPhase != AiSendPhase.idle;
    final canStopSending = widget.canStopSending;
    final modeToggleEnabled = widget.sendPhase == AiSendPhase.idle;
    final runtimeStatus = widget.currentSession == null
        ? null
        : _runtimeToolCatalogStatus(
            widget.currentSession!,
            livePreview: widget.liveRuntimeToolPreview,
          );
    final sendButtonLabel = canStopSending
        ? _localizedText(context, zh: '停止回答', en: 'Stop Response')
        : switch (widget.sendPhase) {
            AiSendPhase.compressing => _localizedText(
              context,
              zh: '消息压缩中',
              en: 'Compressing Messages',
            ),
            AiSendPhase.sendingMessage => l10n.chatSending,
            AiSendPhase.responding => _localizedText(
              context,
              zh: '停止回答',
              en: 'Stop Response',
            ),
            AiSendPhase.awaitingApproval => _localizedText(
              context,
              zh: '等待批准',
              en: 'Awaiting Approval',
            ),
            AiSendPhase.idle => l10n.composerSend,
          };

    final expandedContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.editingMessageId != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: _borderRadius999,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  _localizedText(
                    context,
                    zh: '正在编辑历史消息',
                    en: 'Editing Previous Message',
                  ),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    widget.onCancelEditing();
                  },
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.queuedMessages.isNotEmpty) ...[
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.queuedMessages.length,
            itemBuilder: (context, index) {
              final msg = widget.queuedMessages[index];
              final isFirst = index == 0;
              final isLast = index == widget.queuedMessages.length - 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_empty_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          msg.text.replaceAll('\n', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ),
                      if (msg.attachments.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.attach_file_rounded,
                          size: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${msg.attachments.length}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: isFirst
                            ? null
                            : () =>
                                  widget.onMoveQueuedMessage(index, index - 1),
                        icon: Icon(
                          Icons.arrow_upward_rounded,
                          size: 14,
                          color: isFirst
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.3)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: _localizedText(
                          context,
                          zh: '上移',
                          en: 'Move up',
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: isLast
                            ? null
                            : () =>
                                  widget.onMoveQueuedMessage(index, index + 1),
                        icon: Icon(
                          Icons.arrow_downward_rounded,
                          size: 14,
                          color: isLast
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.3)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: _localizedText(
                          context,
                          zh: '下移',
                          en: 'Move down',
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () async {
                          final edited = await _showEditQueuedMessageDialog(
                            context,
                            msg.text,
                          );
                          if (edited != null && edited.trim().isNotEmpty) {
                            widget.onEditQueuedMessage(index, edited);
                          }
                        },
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: _localizedText(
                          context,
                          zh: '编辑此等待消息',
                          en: 'Edit this queued message',
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () => widget.onRemoveQueuedMessage(index),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: _localizedText(
                          context,
                          zh: '删除此等待消息',
                          en: 'Remove this queued message',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        if (widget.pendingAttachments.isNotEmpty) ...[
          _ReorderableAttachmentWrap(
            attachments: widget.pendingAttachments,
            onReorder: widget.onReorderAttachments,
            onRemove: (filePath) => widget.onRemoveAttachment(filePath),
            onTap: (draft) => _openComposerAttachment(context, draft),
          ),
          const SizedBox(height: 12),
        ],
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            height: widget.composerHeight,
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              expands: true,
              maxLines: null,
              textInputAction: TextInputAction.newline,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(hintText: l10n.composerHint),
            ),
          ),
        ),
      ],
    );

    final actionRow = Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                MenuAnchor(
                  style: MenuStyle(
                    maximumSize: WidgetStatePropertyAll(
                      Size(360, MediaQuery.sizeOf(context).height * 0.5),
                    ),
                  ),
                  menuChildren: _buildModelMenuItems(context),
                  builder: (context, controller, child) {
                    return OutlinedButton.icon(
                      onPressed: widget.availableModels.isEmpty
                          ? null
                          : () {
                              if (controller.isOpen) {
                                controller.close();
                                return;
                              }
                              controller.open();
                            },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      icon: const Icon(Icons.hub_outlined),
                      label: Text(
                        selectedModelLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: widget.attachmentsEnabled
                      ? _localizedText(
                          context,
                          zh: '选择附件（最多 $aiMessageAttachmentLimit 个，支持图片、文本、代码、表格和 PDF）',
                          en: 'Choose attachments (up to $aiMessageAttachmentLimit; images, text, code, spreadsheets, and PDF)',
                        )
                      : _localizedText(
                          context,
                          zh: '当前模型不支持附件',
                          en: 'The selected model does not support attachments',
                        ),
                  child: OutlinedButton.icon(
                    onPressed: widget.attachmentsEnabled
                        ? widget.onPickAttachments
                        : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    icon: const Icon(Icons.attach_file_rounded),
                    label: Text(
                      widget.pendingAttachments.isEmpty
                          ? _localizedText(context, zh: '附件', en: 'Attach')
                          : _localizedText(
                              context,
                              zh: '附件 ${widget.pendingAttachments.length}',
                              en: 'Files ${widget.pendingAttachments.length}',
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _ComposerFullAccessModeButton(
                  fullAccess: widget.fullAccessPermission,
                  enabled: true,
                  onChanged: (bool value) {
                    if (value != widget.fullAccessPermission) {
                      widget.onToggleFullAccessPermission(value);
                    }
                  },
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: _composerModeTooltip(
                    context,
                    widget.sessionMode,
                    runtimeStatus,
                  ),
                  child: _ComposerModeButton(
                    mode: widget.sessionMode,
                    runtimeStatus: runtimeStatus,
                    enabled: modeToggleEnabled,
                    onPressed: () {
                      widget.onSessionModeChanged(
                        widget.sessionMode == AiSessionMode.plan
                            ? AiSessionMode.chat
                            : AiSessionMode.plan,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
        Tooltip(
          message: _localizedText(
            context,
            zh: widget.isCollapsed ? '展开输入框' : '折叠输入框',
            en: widget.isCollapsed ? 'Expand Composer' : 'Collapse Composer',
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: FilledButton(
              onPressed: () => widget.onCollapsedChanged(!widget.isCollapsed),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(52, 52),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: Icon(
                widget.isCollapsed
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: _localizedText(
            context,
            zh: widget.autoFollowEnabled ? '关闭自动滚动' : '开启自动滚动',
            en: widget.autoFollowEnabled
                ? 'Disable Auto Follow'
                : 'Enable Auto Follow',
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: FilledButton(
              onPressed: widget.onToggleAutoFollow,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(52, 52),
                backgroundColor: widget.autoFollowEnabled
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                foregroundColor: widget.autoFollowEnabled
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                side: widget.autoFollowEnabled
                    ? null
                    : BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Icon(
                widget.autoFollowEnabled
                    ? Icons.vertical_align_bottom_rounded
                    : Icons.vertical_align_bottom_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _ComposerCreationModeButton(
          creationMode: widget.creationMode,
          onCreationModeChanged: widget.onCreationModeChanged,
        ),
        const SizedBox(width: 10),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, textValue, _) {
            final hasUserTextOrAttachments =
                textValue.text.trim().isNotEmpty ||
                widget.pendingAttachments.isNotEmpty;
            final isQueueingAction = isBusy && hasUserTextOrAttachments;

            return SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: isQueueingAction
                    ? () => widget.onSend()
                    : canStopSending && !hasUserTextOrAttachments
                    ? () => widget.onStop()
                    : isBusy
                    ? null
                    : () => widget.onSend(),
                icon: isQueueingAction
                    ? const Icon(Icons.queue_play_next_rounded)
                    : canStopSending && !hasUserTextOrAttachments
                    ? const Icon(Icons.stop_rounded)
                    : isCompressing || isSendingMessage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Icon(
                        isResponding
                            ? Icons.stop_rounded
                            : Icons.arrow_upward_rounded,
                      ),
                label: Text(
                  isQueueingAction
                      ? _localizedText(context, zh: '提前发送', en: 'Queue Message')
                      : canStopSending && !hasUserTextOrAttachments
                      ? _localizedText(
                          context,
                          zh: '停止回答',
                          en: 'Stop Responding',
                        )
                      : sendButtonLabel,
                ),
              ),
            );
          },
        ),
      ],
    );

    return Card(
      color: colorScheme.surfaceContainerHigh,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubicEmphasized,
        padding: EdgeInsets.fromLTRB(18, 14, 18, widget.isCollapsed ? 10 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: widget.isCollapsed ? 1 : 0,
                end: widget.isCollapsed ? 0 : 1,
              ),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOutCubicEmphasized,
              child: expandedContent,
              builder: (context, value, child) {
                return ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: value,
                    child: IgnorePointer(
                      ignoring: value < 0.98,
                      child: Opacity(
                        opacity: value.clamp(0, 1).toDouble(),
                        child: child,
                      ),
                    ),
                  ),
                );
              },
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOutCubicEmphasized,
              height: widget.isCollapsed ? 0 : 14,
            ),
            actionRow,
          ],
        ),
      ),
    );
  }
}

class _ComposerFullAccessModeButton extends StatelessWidget {
  const _ComposerFullAccessModeButton({
    required this.fullAccess,
    required this.enabled,
    required this.onChanged,
  });

  final bool fullAccess;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final modeLabel = fullAccess
        ? _localizedText(context, zh: '完全访问权限', en: 'Full Access')
        : _localizedText(context, zh: '默认权限', en: 'Default Access');
    final backgroundColor = !enabled
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.78)
        : fullAccess
        ? const Color(0xFFFBBF24).withValues(alpha: 0.15)
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : fullAccess
        ? const Color(0xFFF59E0B)
        : colorScheme.onSurfaceVariant;
    final borderColor = !enabled
        ? colorScheme.outlineVariant.withValues(alpha: 0.48)
        : fullAccess
        ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
        : colorScheme.outlineVariant;

    return MenuAnchor(
      builder: (context, controller, child) {
        return OutlinedButton(
          onPressed: enabled
              ? () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                }
              : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            side: BorderSide(color: borderColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                fullAccess
                    ? Icons.gpp_maybe_outlined
                    : Icons.admin_panel_settings_outlined,
                size: 18,
                color: foregroundColor,
              ),
              const SizedBox(width: 8),
              Text(
                modeLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: foregroundColor,
              ),
            ],
          ),
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(
            Icons.admin_panel_settings_outlined,
            size: 20,
          ),
          trailingIcon: !fullAccess
              ? const Icon(Icons.check_rounded, size: 20)
              : const SizedBox(width: 20),
          onPressed: () => onChanged(false),
          child: Text(
            _localizedText(context, zh: '默认权限', en: 'Default Access'),
          ),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.gpp_maybe_outlined, size: 20),
          trailingIcon: fullAccess
              ? const Icon(Icons.check_rounded, size: 20)
              : const SizedBox(width: 20),
          onPressed: () => onChanged(true),
          child: Text(_localizedText(context, zh: '完全访问权限', en: 'Full Access')),
        ),
      ],
    );
  }
}

class _ComposerModeButton extends StatelessWidget {
  const _ComposerModeButton({
    required this.mode,
    required this.runtimeStatus,
    required this.enabled,
    required this.onPressed,
  });

  final AiSessionMode mode;
  final _RuntimeToolCatalogStatus? runtimeStatus;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPlanMode = mode == AiSessionMode.plan;
    final modeIcon = _runtimeModeIcon(runtimeStatus, explicitMode: mode);
    final modeLabel = _runtimeModeLabel(
      context,
      runtimeStatus,
      compact: true,
      explicitMode: mode,
    );
    final backgroundColor = !enabled
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.78)
        : isPlanMode
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : isPlanMode
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final accentColor = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.28)
        : colorScheme.primary.withValues(alpha: isPlanMode ? 1 : 0.9);
    final borderColor = !enabled
        ? colorScheme.outlineVariant.withValues(alpha: 0.48)
        : isPlanMode
        ? colorScheme.primary.withValues(alpha: 0.24)
        : colorScheme.outlineVariant;
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: isPlanMode ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                );
              },
              child: Icon(
                modeIcon,
                key: ValueKey<String>('${mode.storageValue}-$modeIcon'),
                size: 16,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              modeLabel,
              key: ValueKey<String>('${mode.storageValue}-$modeLabel'),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Creation mode types for the composer.
enum _CreationMode { none, image, video, audio, deepResearch }

/// A "+" button that opens a popup for creation modes (image, video, audio, deep research).
/// When a supported mode is selected, the button turns active (primary color + mode icon).
class _ComposerCreationModeButton extends StatefulWidget {
  const _ComposerCreationModeButton({
    required this.creationMode,
    required this.onCreationModeChanged,
  });

  final _CreationMode creationMode;
  final ValueChanged<_CreationMode> onCreationModeChanged;

  @override
  State<_ComposerCreationModeButton> createState() =>
      _ComposerCreationModeButtonState();
}

class _ComposerCreationModeButtonState
    extends State<_ComposerCreationModeButton> {
  IconData _iconForMode(_CreationMode mode) => switch (mode) {
    _CreationMode.none => Icons.add_rounded,
    _CreationMode.image => Icons.image_outlined,
    _CreationMode.video => Icons.videocam_outlined,
    _CreationMode.audio => Icons.audiotrack_outlined,
    _CreationMode.deepResearch => Icons.travel_explore_rounded,
  };

  /// Notify the parent of a mode change after the current frame to avoid
  /// mutating the widget tree while the [MouseTracker] is mid-update.
  void _deferModeChange(_CreationMode mode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCreationModeChanged(mode);
    });
  }

  void _selectMode(_CreationMode mode) {
    if (mode == widget.creationMode) {
      // Toggle off.
      _deferModeChange(_CreationMode.none);
      return;
    }
    // Only image generation is currently supported.
    if (mode != _CreationMode.image) {
      final label = switch (mode) {
        _CreationMode.video => _localizedText(
          context,
          zh: '视频生成功能暂不支持，敬请期待',
          en: 'Video generation is not yet supported',
        ),
        _CreationMode.audio => _localizedText(
          context,
          zh: '音频生成功能暂不支持，敬请期待',
          en: 'Audio generation is not yet supported',
        ),
        _CreationMode.deepResearch => _localizedText(
          context,
          zh: '深度研究功能暂不支持，敬请期待',
          en: 'Deep Research is not yet supported',
        ),
        _ => '',
      };
      if (label.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(label),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _deferModeChange(mode);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = widget.creationMode != _CreationMode.none;
    return MenuAnchor(
      builder: (context, controller, child) {
        return Tooltip(
          message: _localizedText(context, zh: '创建', en: 'Create'),
          child: SizedBox(
            width: 52,
            height: 52,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: FilledButton(
                onPressed: () {
                  // When active, toggle off instead of opening the menu.
                  if (isActive) {
                    _deferModeChange(_CreationMode.none);
                    return;
                  }
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(52, 52),
                  backgroundColor: isActive
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  foregroundColor: isActive
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                  side: isActive
                      ? null
                      : BorderSide(color: colorScheme.outlineVariant),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: Icon(
                    _iconForMode(widget.creationMode),
                    key: ValueKey<_CreationMode>(widget.creationMode),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(
            Icons.image_outlined,
            size: 20,
            color: widget.creationMode == _CreationMode.image
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          trailingIcon: widget.creationMode == _CreationMode.image
              ? Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
          onPressed: () => _selectMode(_CreationMode.image),
          child: Text(_localizedText(context, zh: '创建图片', en: 'Create Image')),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.videocam_outlined, size: 20),
          onPressed: () => _selectMode(_CreationMode.video),
          child: Text(
            _localizedText(context, zh: '视频生成', en: 'Generate Video'),
          ),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.audiotrack_outlined, size: 20),
          onPressed: () => _selectMode(_CreationMode.audio),
          child: Text(
            _localizedText(context, zh: '音频生成', en: 'Generate Audio'),
          ),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.travel_explore_rounded, size: 20),
          onPressed: () => _selectMode(_CreationMode.deepResearch),
          child: Text(_localizedText(context, zh: '深度研究', en: 'Deep Research')),
        ),
      ],
    );
  }
}

/// A wrap layout that allows drag-to-reorder of attachment chips.
class _ReorderableAttachmentWrap extends StatefulWidget {
  const _ReorderableAttachmentWrap({
    required this.attachments,
    required this.onReorder,
    required this.onRemove,
    required this.onTap,
  });

  final List<_ComposerAttachmentDraft> attachments;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<String> onRemove;
  final void Function(_ComposerAttachmentDraft draft) onTap;

  @override
  State<_ReorderableAttachmentWrap> createState() =>
      _ReorderableAttachmentWrapState();
}

class _ReorderableAttachmentWrapState
    extends State<_ReorderableAttachmentWrap> {
  int? _dragIndex;
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(widget.attachments.length, (index) {
        final attachment = widget.attachments[index];
        final isDragging = _dragIndex == index;
        final isHovering = _hoverIndex == index;
        return DragTarget<int>(
          onWillAcceptWithDetails: (details) {
            if (details.data != index) {
              setState(() => _hoverIndex = index);
            }
            return details.data != index;
          },
          onLeave: (_) {
            if (_hoverIndex == index) {
              setState(() => _hoverIndex = null);
            }
          },
          onAcceptWithDetails: (details) {
            setState(() => _hoverIndex = null);
            widget.onReorder(details.data, index);
          },
          builder: (context, candidateData, rejectedData) {
            return Draggable<int>(
              data: index,
              onDragStarted: () => setState(() => _dragIndex = index),
              onDragEnd: (_) => setState(() {
                _dragIndex = null;
                _hoverIndex = null;
              }),
              feedback: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                child: Opacity(
                  opacity: 0.85,
                  child: _ComposerAttachmentChip(
                    attachment: attachment,
                    onRemove: () {},
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _ComposerAttachmentChip(
                  attachment: attachment,
                  onRemove: () {},
                ),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                transform: isHovering
                    ? (Matrix4.identity()..scaleByDouble(1.05, 1.05, 1.0, 1.0))
                    : Matrix4.identity(),
                transformAlignment: Alignment.center,
                child: Opacity(
                  opacity: isDragging ? 0.3 : 1.0,
                  child: _ComposerAttachmentChip(
                    attachment: attachment,
                    onRemove: () => widget.onRemove(attachment.filePath),
                    onTap: () => widget.onTap(attachment),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

class _ComposerAttachmentChip extends StatelessWidget {
  const _ComposerAttachmentChip({
    required this.attachment,
    required this.onRemove,
    this.onTap,
  });

  final _ComposerAttachmentDraft attachment;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconForAttachmentKind(attachment.kind),
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  '${attachment.name} · ${aiFormatBytes(attachment.sizeBytes)}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onRemove,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerAttachmentDraft {
  const _ComposerAttachmentDraft({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.sizeBytes,
  });

  final String filePath;
  final String name;
  final AiAttachmentKind kind;
  final int sizeBytes;

  static Future<_ComposerAttachmentDraft> fromPath(String path) async {
    final file = File(path);
    final stat = await file.stat();
    return _ComposerAttachmentDraft(
      filePath: path,
      name: p.basename(path),
      kind: aiAttachmentKindForPath(path),
      sizeBytes: stat.size,
    );
  }
}

IconData _iconForAttachmentKind(AiAttachmentKind kind) {
  return switch (kind) {
    AiAttachmentKind.image => Icons.image_outlined,
    AiAttachmentKind.text => Icons.description_outlined,
    AiAttachmentKind.spreadsheet => Icons.table_chart_outlined,
    AiAttachmentKind.pdf => Icons.picture_as_pdf_outlined,
    AiAttachmentKind.binary => Icons.insert_drive_file_outlined,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// HE session tile shown in the navigation pane threads list.
// Mirrors the visual design of _ThreadTile for consistency.
// ─────────────────────────────────────────────────────────────────────────────

