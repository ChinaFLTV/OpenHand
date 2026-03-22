import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/state/settings_controller.dart';
import '../../app/theme/openhand_palette.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/section_placeholder.dart';
import '../ai/model/ai_model_config.dart';
import '../ai/service/ai_chat_service.dart';
import '../ai/service/ai_protocol_adapter.dart';
import '../memory/memory_view.dart';
import '../mcp/mcp_view.dart';
import '../settings/settings_view.dart';
import '../skills/skills_view.dart';

enum AppSection { workspace, automations, skills, memory, mcp, settings }

enum _MessageRole { user, assistant }

const double _desktopNavigationWidth = 352;
const double _contentPaneGap = 18;
const double _sideBySideLayoutMinWidth = 980;
const double _stackedNavigationMinHeight = 280;
const double _stackedNavigationMaxHeight = 360;
const double _composerMinHeight = 168;
const double _composerDefaultHeight = 196;
const double _composerMaxHeight = 440;

class OpenHandHomePage extends StatefulWidget {
  const OpenHandHomePage({super.key});

  @override
  State<OpenHandHomePage> createState() => _OpenHandHomePageState();
}

class _OpenHandHomePageState extends State<OpenHandHomePage> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();
  final AiChatService _chatService = AiChatService();
  final List<_ChatMessage> _messages = <_ChatMessage>[];

  AppSection _selectedSection = AppSection.workspace;
  double _composerHeight = _composerDefaultHeight;
  bool _isSending = false;

  @override
  void dispose() {
    _composerController.dispose();
    _messageScrollController.dispose();
    _chatService.dispose();
    super.dispose();
  }

  void _selectSection(AppSection section) {
    setState(() {
      _selectedSection = section;
    });
  }

  Future<void> _sendMessage() async {
    final l10n = AppLocalizations.of(context)!;
    final prompt = _composerController.text.trim();
    if (prompt.isEmpty || _isSending) {
      return;
    }

    final settingsController = context.read<SettingsController>();
    final selectedModel = settingsController.selectedAiModel;
    if (selectedModel == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.aiModelSelectionRequired)));
      return;
    }

    setState(() {
      _messages.add(_ChatMessage.user(prompt));
      _composerController.clear();
      _isSending = true;
    });
    _scheduleScrollToBottom();

    try {
      final reply = await _chatService.sendMessage(
        model: selectedModel,
        messages: _messages
            .map((item) => item.toTurn())
            .toList(growable: false),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          _ChatMessage.assistant(
            content: reply,
            modelLabel: selectedModel.displayName,
          ),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final adapter = AiProtocolRegistry.adapterFor(selectedModel.protocolType);
      final message = '$error'.trim();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.chatRequestFailed)));
      setState(() {
        _messages.add(
          _ChatMessage.assistant(
            content:
                '${l10n.chatRequestFailed}\n${adapter.describe(selectedModel)}\n$message',
            modelLabel: selectedModel.displayName,
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        _scheduleScrollToBottom();
      }
    }
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messageScrollController.hasClients) {
        return;
      }
      _messageScrollController.animateTo(
        _messageScrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<OpenHandPalette>()!;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.canvasStart, palette.canvasEnd],
          ),
        ),
        child: SafeArea(
          minimum: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stackedLayout =
                  constraints.maxWidth < _sideBySideLayoutMinWidth;
              final stackedNavigationHeight = (constraints.maxHeight * 0.34)
                  .clamp(
                    _stackedNavigationMinHeight,
                    _stackedNavigationMaxHeight,
                  )
                  .toDouble();
              final navigationPane = _NavigationPane(
                selectedSection: _selectedSection,
                onSectionSelected: _selectSection,
              );
              final contentPane = _ContentPane(
                child: _buildSectionContent(context),
              );

              if (stackedLayout) {
                return Column(
                  children: [
                    SizedBox(
                      height: stackedNavigationHeight,
                      child: navigationPane,
                    ),
                    const SizedBox(height: 16),
                    Expanded(child: contentPane),
                  ],
                );
              }

              return Row(
                children: [
                  SizedBox(
                    width: _desktopNavigationWidth,
                    child: navigationPane,
                  ),
                  const SizedBox(width: _contentPaneGap),
                  Expanded(child: contentPane),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSectionContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settingsController = context.watch<SettingsController>();

    return switch (_selectedSection) {
      AppSection.workspace => _WorkspaceView(
        draftController: _composerController,
        messageScrollController: _messageScrollController,
        messages: _messages,
        selectedModel: settingsController.selectedAiModel,
        availableModels: settingsController.aiModels,
        onModelSelected: (modelId) {
          settingsController.updateSelectedAiModel(modelId);
        },
        composerHeight: _composerHeight,
        onComposerHeightChanged: (nextHeight) {
          setState(() {
            _composerHeight = nextHeight;
          });
        },
        isSending: _isSending,
        onSend: _sendMessage,
      ),
      AppSection.automations => SectionPlaceholder(
        icon: Icons.schedule_send_outlined,
        title: l10n.automationHeadline,
        body: l10n.automationBody,
        footer: l10n.placeholderComingSoon,
        actionLabel: l10n.switchToWorkspace,
        onAction: () => _selectSection(AppSection.workspace),
      ),
      AppSection.skills => const SkillsView(),
      AppSection.memory => const MemoryView(),
      AppSection.mcp => const McpView(),
      AppSection.settings => const SettingsView(),
    };
  }
}

extension on AppSection {
  int get drawerIndex {
    return switch (this) {
      AppSection.workspace => 0,
      AppSection.automations => 1,
      AppSection.skills => 2,
      AppSection.memory => 3,
      AppSection.mcp => 4,
      AppSection.settings => 5,
    };
  }
}

AppSection _sectionFromDrawerIndex(int index) {
  return switch (index) {
    1 => AppSection.automations,
    2 => AppSection.skills,
    3 => AppSection.memory,
    4 => AppSection.mcp,
    5 => AppSection.settings,
    _ => AppSection.workspace,
  };
}

class _NavigationPane extends StatelessWidget {
  const _NavigationPane({
    required this.selectedSection,
    required this.onSectionSelected,
  });

  final AppSection selectedSection;
  final ValueChanged<AppSection> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: NavigationDrawer(
        selectedIndex: selectedSection.drawerIndex,
        onDestinationSelected: (index) {
          onSectionSelected(_sectionFromDrawerIndex(index));
        },
        children: [
          const SizedBox(height: 8),
          NavigationDrawerDestination(
            icon: const Icon(Icons.edit_outlined),
            selectedIcon: const Icon(Icons.edit_rounded),
            label: Text(l10n.newThread),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Icons.history_toggle_off_outlined),
            selectedIcon: const Icon(Icons.schedule_rounded),
            label: Text(l10n.automations),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Icons.extension_outlined),
            selectedIcon: const Icon(Icons.extension_rounded),
            label: Text(l10n.skills),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Icons.psychology_alt_outlined),
            selectedIcon: const Icon(Icons.psychology_alt_rounded),
            label: Text(l10n.memory),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Icons.hub_outlined),
            selectedIcon: const Icon(Icons.hub_rounded),
            label: Text(l10n.mcp),
          ),
          NavigationDrawerDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: Text(l10n.settings),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(l10n.threads, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _ContentPane extends StatelessWidget {
  const _ContentPane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    );
  }
}

class _WorkspaceView extends StatelessWidget {
  const _WorkspaceView({
    required this.draftController,
    required this.messageScrollController,
    required this.messages,
    required this.selectedModel,
    required this.availableModels,
    required this.onModelSelected,
    required this.composerHeight,
    required this.onComposerHeightChanged,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController draftController;
  final ScrollController messageScrollController;
  final List<_ChatMessage> messages;
  final AiModelConfig? selectedModel;
  final List<AiModelConfig> availableModels;
  final ValueChanged<String> onModelSelected;
  final double composerHeight;
  final ValueChanged<double> onComposerHeightChanged;
  final bool isSending;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxComposerHeight = (constraints.maxHeight - 96)
            .clamp(_composerMinHeight, _composerMaxHeight)
            .toDouble();
        final effectiveComposerHeight = composerHeight
            .clamp(_composerMinHeight, maxComposerHeight)
            .toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: messages.isEmpty
                    ? const _WorkspaceEmptyState(key: ValueKey<String>('empty'))
                    : _MessageList(
                        key: const ValueKey<String>('messages'),
                        controller: messageScrollController,
                        messages: messages,
                      ),
              ),
            ),
            const SizedBox(height: 16),
            _ComposerPanel(
              controller: draftController,
              selectedModel: selectedModel,
              availableModels: availableModels,
              onModelSelected: onModelSelected,
              composerHeight: effectiveComposerHeight,
              maxComposerHeight: maxComposerHeight,
              onComposerHeightChanged: onComposerHeightChanged,
              isSending: isSending,
              onSend: onSend,
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceEmptyState extends StatelessWidget {
  const _WorkspaceEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final emptyStateContent = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(32),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 42,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text(l10n.newThread, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 10),
          Text(
            l10n.appTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.appTagline,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: Center(child: emptyStateContent),
          ),
        );
      },
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    super.key,
    required this.controller,
    required this.messages,
  });

  final ScrollController controller;
  final List<_ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: messages.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final message = messages[index];
        return _MessageBubble(message: message);
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUser = message.role == _MessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isUser
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.modelLabel != null) ...[
                  Text(
                    message.modelLabel!,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SelectableText(
                  message.content,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: isUser
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposerPanel extends StatefulWidget {
  const _ComposerPanel({
    required this.controller,
    required this.selectedModel,
    required this.availableModels,
    required this.onModelSelected,
    required this.composerHeight,
    required this.maxComposerHeight,
    required this.onComposerHeightChanged,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final AiModelConfig? selectedModel;
  final List<AiModelConfig> availableModels;
  final ValueChanged<String> onModelSelected;
  final double composerHeight;
  final double maxComposerHeight;
  final ValueChanged<double> onComposerHeightChanged;
  final bool isSending;
  final Future<void> Function() onSend;

  @override
  State<_ComposerPanel> createState() => _ComposerPanelState();
}

class _ComposerPanelState extends State<_ComposerPanel> {
  double? _dragStartHeight;
  double? _dragStartGlobalY;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final selectedModelLabel =
        widget.selectedModel?.displayName ?? l10n.chatModelButton;

    return Card(
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: (details) {
                    _dragStartHeight = widget.composerHeight;
                    _dragStartGlobalY = details.globalPosition.dy;
                  },
                  onVerticalDragUpdate: (details) {
                    final dragStartHeight = _dragStartHeight;
                    final dragStartGlobalY = _dragStartGlobalY;
                    if (dragStartHeight == null || dragStartGlobalY == null) {
                      return;
                    }
                    final nextHeight =
                        (dragStartHeight -
                                (details.globalPosition.dy - dragStartGlobalY))
                            .clamp(_composerMinHeight, widget.maxComposerHeight)
                            .toDouble();
                    widget.onComposerHeightChanged(nextHeight);
                  },
                  onVerticalDragEnd: (_) {
                    _dragStartHeight = null;
                    _dragStartGlobalY = null;
                  },
                  onVerticalDragCancel: () {
                    _dragStartHeight = null;
                    _dragStartGlobalY = null;
                  },
                  child: Container(
                    width: 88,
                    height: 22,
                    alignment: Alignment.center,
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: widget.composerHeight,
              child: TextField(
                controller: widget.controller,
                expands: true,
                minLines: null,
                maxLines: null,
                textInputAction: TextInputAction.newline,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(hintText: l10n.composerHint),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                MenuAnchor(
                  menuChildren: widget.availableModels
                      .map(
                        (model) => MenuItemButton(
                          leadingIcon: Icon(
                            model.id == widget.selectedModel?.id
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                          ),
                          onPressed: () => widget.onModelSelected(model.id),
                          child: Text(
                            '${model.displayName} · ${model.protocolType.label(l10n)}',
                          ),
                        ),
                      )
                      .toList(growable: false),
                  builder: (context, controller, child) {
                    return SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: widget.availableModels.isEmpty
                            ? null
                            : () {
                                if (controller.isOpen) {
                                  controller.close();
                                  return;
                                }
                                controller.open();
                              },
                        icon: const Icon(Icons.hub_outlined),
                        label: Text(selectedModelLabel),
                      ),
                    );
                  },
                ),
                const Spacer(),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: widget.isSending
                        ? null
                        : () {
                            widget.onSend();
                          },
                    icon: widget.isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Icon(Icons.arrow_upward_rounded),
                    label: Text(
                      widget.isSending ? l10n.chatSending : l10n.composerSend,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.content,
    this.modelLabel,
  });

  const _ChatMessage.user(String content)
    : this(role: _MessageRole.user, content: content);

  const _ChatMessage.assistant({required String content, String? modelLabel})
    : this(
        role: _MessageRole.assistant,
        content: content,
        modelLabel: modelLabel,
      );

  final _MessageRole role;
  final String content;
  final String? modelLabel;

  AiChatTurn toTurn() {
    return AiChatTurn(
      role: role == _MessageRole.user ? AiChatRole.user : AiChatRole.assistant,
      content: content,
    );
  }
}
