import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight.dart' as highlight;
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app/model/app_info.dart';
import '../../app/state/settings_controller.dart';
import '../../app/support/openhand_paths.dart';
import '../../app/theme/openhand_palette.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../../shared/widgets/section_placeholder.dart';
import '../ai/ai_session_controller.dart';
import '../ai/model/ai_model_config.dart';
import '../ai/model/ai_session.dart';
import '../ai/model/ai_session_message.dart';
import '../ai/model/ai_session_runtime_context.dart';
import '../ai/model/ai_thread_template.dart';
import '../ai/service/ai_bash_tool_service.dart';
import '../memory/memory_controller.dart';
import '../memory/memory_view.dart';
import '../mcp/mcp_view.dart';
import '../settings/settings_view.dart';
import '../skills/skills_view.dart';
import 'tool_call_argument_parser.dart';

enum AppSection { workspace, automations, skills, memory, mcp, settings }

const double _desktopNavigationWidth = 352;
const double _contentPaneGap = 18;
const double _sideBySideLayoutMinWidth = 980;
const double _stackedNavigationMinHeight = 280;
const double _stackedNavigationMaxHeight = 360;
const double _composerMinHeight = 168;
const double _composerDefaultHeight = 196;
const double _composerMaxHeight = 440;
const double _autoFollowDistanceThreshold = 96;

class OpenHandHomePage extends StatefulWidget {
  const OpenHandHomePage({super.key});

  @override
  State<OpenHandHomePage> createState() => _OpenHandHomePageState();
}

class _OpenHandHomePageState extends State<OpenHandHomePage> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();

  AppSection _selectedSection = AppSection.workspace;
  double _composerHeight = _composerDefaultHeight;
  bool _composerCollapsed = false;
  bool _autoFollowEnabled = true;
  String? _submittingSessionId;
  bool _shouldAutoFollowMessages = true;
  bool _pendingForcedScrollToBottom = false;
  bool _scrollToBottomCallbackQueued = false;
  bool _pendingAnimatedScrollToBottom = false;
  String? _lastAutoScrollSignature;

  AiSendPhase _effectiveSendPhase(AiSessionController sessionController) {
    final currentSessionId = sessionController.currentSessionId;
    final controllerPhase = sessionController.sendPhaseForSession(
      currentSessionId,
    );
    if (controllerPhase != AiSendPhase.idle) {
      return controllerPhase;
    }
    return _submittingSessionId == currentSessionId
        ? AiSendPhase.sendingMessage
        : AiSendPhase.idle;
  }

  @override
  void initState() {
    super.initState();
    _messageScrollController.addListener(_handleMessageScroll);
  }

  @override
  void dispose() {
    _messageScrollController.removeListener(_handleMessageScroll);
    _composerController.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  void _handleMessageScroll() {
    final nextValue = _isNearBottom();
    if (nextValue == _shouldAutoFollowMessages) {
      return;
    }
    _shouldAutoFollowMessages = nextValue;
    if (nextValue) {
      _pendingForcedScrollToBottom = false;
    }
  }

  bool _handleMessageScrollNotification(ScrollNotification notification) {
    if (!mounted) {
      return false;
    }
    final distanceToBottom =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    final isNearBottom = distanceToBottom <= _autoFollowDistanceThreshold;
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        !isNearBottom) {
      _shouldAutoFollowMessages = false;
      _pendingForcedScrollToBottom = false;
      return false;
    }
    if (isNearBottom) {
      _shouldAutoFollowMessages = true;
    }
    return false;
  }

  void _selectSection(AppSection section) {
    setState(() {
      _selectedSection = section;
    });
  }

  void _toggleAutoFollow() {
    final nextValue = !_autoFollowEnabled;
    setState(() {
      _autoFollowEnabled = nextValue;
      if (!nextValue) {
        _pendingForcedScrollToBottom = false;
      } else {
        _shouldAutoFollowMessages = true;
        _pendingForcedScrollToBottom = true;
      }
    });
    if (nextValue) {
      _scheduleScrollToBottom(force: true, animated: true);
    }
  }

  Future<void> _createSessionFromDialog() async {
    final sessionController = context.read<AiSessionController>();
    final templateId = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return _ThreadTemplateDialog(templates: sessionController.templates);
      },
    );
    if (!mounted || templateId == null) {
      return;
    }
    final created = await sessionController.createSession(
      templateId: templateId,
      runtimeContext: _buildRuntimeContext(),
    );
    if (!mounted) {
      return;
    }
    if (!created) {
      final l10n = AppLocalizations.of(context)!;
      final errorMessage = sessionController.lastErrorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage ?? l10n.chatRequestFailed)),
      );
      return;
    }
    setState(() {
      _selectedSection = AppSection.workspace;
      _pendingForcedScrollToBottom = true;
    });
  }

  AiSessionRuntimeContext _buildRuntimeContext() {
    final settingsController = context.read<SettingsController>();
    final memoryController = context.read<MemoryController>();
    final appInfo = context.read<AppInfo>();
    return AiSessionRuntimeContext(
      localeTag: settingsController.locale.toLanguageTag(),
      appVersion: appInfo.version,
      appBuildNumber: appInfo.buildNumber,
      settingsFilePath: settingsController.settingsFilePath,
      skillsStoragePath: settingsController.skillsStoragePath,
      mcpServersFilePath: settingsController.mcpServersFilePath,
      userMemoryFilePath: settingsController.userMemoryFilePath,
      compressionThresholdChars:
          settingsController.aiMessageCompressionThresholdChars,
      memoryEnabled: settingsController.memoryEnabled,
      memoryEntries: settingsController.memoryEnabled
          ? memoryController.entries
          : const [],
    );
  }

  Future<void> _sendMessage() async {
    final l10n = AppLocalizations.of(context)!;
    final prompt = _composerController.text.trim();
    if (prompt.isEmpty) {
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

    final sessionController = context.read<AiSessionController>();
    if (sessionController.currentSession == null) {
      await _createSessionFromDialog();
      if (!mounted || sessionController.currentSession == null) {
        return;
      }
    }
    final targetSessionId = sessionController.currentSessionId;
    if (targetSessionId == null || _submittingSessionId == targetSessionId) {
      return;
    }

    _composerController.clear();
    setState(() {
      _submittingSessionId = targetSessionId;
      _pendingForcedScrollToBottom = true;
    });
    try {
      final sent = await sessionController.sendMessage(
        sessionId: targetSessionId,
        content: prompt,
        model: selectedModel,
        runtimeContext: _buildRuntimeContext(),
        denyCommandRules: settingsController.aiDenyCommandRules,
        requireWriteCommandConfirmation:
            settingsController.aiWriteCommandConfirmationEnabled,
        confirmWriteCommand: _confirmWriteCommand,
      );
      if (!mounted) {
        return;
      }
      if (!sent) {
        if (sessionController.currentSessionId == targetSessionId) {
          _composerController.text = prompt;
        }
        final errorMessage = sessionController.lastErrorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage ?? l10n.chatRequestFailed)),
        );
        return;
      }
      await sessionController.completeEditingMessage();
      if (!mounted) {
        return;
      }
      if (sessionController.didCompressInLastSend) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.threadCompressionNotice)));
      }
      _scheduleScrollToBottom(force: true, animated: true);
    } finally {
      if (mounted) {
        setState(() {
          if (_submittingSessionId == targetSessionId) {
            _submittingSessionId = null;
          }
        });
      } else if (_submittingSessionId == targetSessionId) {
        _submittingSessionId = null;
      }
    }
  }

  Future<void> _stopResponding() async {
    final sessionController = context.read<AiSessionController>();
    final sessionId = sessionController.currentSessionId;
    if (sessionId == null) {
      return;
    }
    await sessionController.stopResponding(sessionId);
  }

  void _scheduleScrollToBottom({bool force = false, bool animated = false}) {
    if (!force && !_shouldAutoFollowMessages) {
      return;
    }
    _pendingAnimatedScrollToBottom = _pendingAnimatedScrollToBottom || animated;
    if (_scrollToBottomCallbackQueued) {
      return;
    }
    _scrollToBottomCallbackQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomCallbackQueued = false;
      final shouldAnimate = _pendingAnimatedScrollToBottom;
      _pendingAnimatedScrollToBottom = false;
      final activePosition = _activeMessageScrollPosition();
      if (activePosition == null) {
        return;
      }
      final targetOffset = activePosition.maxScrollExtent
          .clamp(activePosition.minScrollExtent, activePosition.maxScrollExtent)
          .toDouble();
      final distance = (targetOffset - activePosition.pixels).abs();
      if (distance < 1) {
        return;
      }
      if (shouldAnimate && distance > 24) {
        _messageScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      _messageScrollController.jumpTo(targetOffset);
    });
  }

  bool _isNearBottom() {
    final activePosition = _activeMessageScrollPosition();
    if (activePosition == null) {
      return true;
    }
    return activePosition.maxScrollExtent - activePosition.pixels <=
        _autoFollowDistanceThreshold;
  }

  void _maybeAutoFollowSession(AiSession? session) {
    final nextSignature = _sessionAutoScrollSignature(session);
    if (_lastAutoScrollSignature == nextSignature) {
      return;
    }
    _lastAutoScrollSignature = nextSignature;
    if (nextSignature == null) {
      return;
    }
    final shouldForce = _pendingForcedScrollToBottom;
    _pendingForcedScrollToBottom = false;
    if (!_autoFollowEnabled && !shouldForce) {
      return;
    }
    if (!_shouldAutoFollowMessages && !shouldForce) {
      return;
    }
    _scheduleScrollToBottom(force: true);
  }

  String? _sessionAutoScrollSignature(AiSession? session) {
    final currentSession = session;
    if (currentSession == null) {
      return null;
    }
    final displayMessages = _displayMessages(currentSession);
    if (displayMessages.isEmpty) {
      return null;
    }
    final lastMessage = displayMessages.last;
    return [
      currentSession.id,
      displayMessages.length,
      lastMessage.id,
      lastMessage.kind.storageValue,
      lastMessage.characterCount,
      '${_toolExecutionStdout(lastMessage).length}',
      '${_toolExecutionStderr(lastMessage).length}',
    ].join('|');
  }

  ScrollPosition? _activeMessageScrollPosition() {
    if (!_messageScrollController.hasClients) {
      return null;
    }
    final positions = _messageScrollController.positions.toList(
      growable: false,
    );
    if (positions.isEmpty) {
      return null;
    }
    return positions.last;
  }

  Future<bool> _confirmWriteCommand(BashCommandApprovalRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          _WriteCommandConfirmationDialog(request: request),
    );
    return confirmed == true;
  }

  Future<void> _renameSession(AiSession session) async {
    final controller = context.read<AiSessionController>();
    final titleController = TextEditingController(text: session.title);
    final submitted = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _localizedText(dialogContext, zh: '重命名线程', en: 'Rename Thread'),
          ),
          content: TextField(
            controller: titleController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: _localizedText(
                dialogContext,
                zh: '输入线程标题',
                en: 'Enter a thread title',
              ),
            ),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: AppLocalizations.of(context)!.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(titleController.text.trim()),
              label: AppLocalizations.of(context)!.commonSave,
            ),
          ],
        );
      },
    );
    titleController.dispose();
    if (!mounted || submitted == null || submitted.trim().isEmpty) {
      return;
    }
    final renamed = await controller.renameSession(session.id, submitted);
    if (!mounted || renamed) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.lastErrorMessage ??
              _localizedText(context, zh: '线程重命名失败。', en: 'Rename failed.'),
        ),
      ),
    );
  }

  Future<void> _deleteSession(AiSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _localizedText(dialogContext, zh: '删除线程', en: 'Delete Thread'),
          ),
          content: Text(session.title),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: AppLocalizations.of(context)!.commonCancel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: AppLocalizations.of(context)!.commonDelete,
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final controller = context.read<AiSessionController>();
    final deleted = await controller.deleteSession(session.id);
    if (!mounted || deleted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.lastErrorMessage ??
              _localizedText(context, zh: '线程删除失败。', en: 'Delete failed.'),
        ),
      ),
    );
  }

  Future<void> _editMessage(AiSessionMessage message) async {
    final content = await context
        .read<AiSessionController>()
        .beginEditingMessage(message.id);
    if (!mounted || content == null) {
      return;
    }
    _composerController
      ..text = content
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: content.length),
      );
    setState(() {
      _selectedSection = AppSection.workspace;
      _composerCollapsed = false;
    });
    _scheduleScrollToBottom();
  }

  Future<void> _copyMessage(AiSessionMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localizedText(context, zh: '消息内容已复制。', en: 'Message copied.'),
        ),
      ),
    );
  }

  Future<void> _cancelEditingMessage() async {
    final controller = context.read<AiSessionController>();
    final cancelled = await controller.cancelEditingMessage();
    if (!mounted || cancelled) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          controller.lastErrorMessage ??
              _localizedText(
                context,
                zh: '恢复编辑前的会话状态失败。',
                en: 'Failed to restore the previous conversation state.',
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<OpenHandPalette>()!;
    final sessionController = context.watch<AiSessionController>();

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
                sessions: sessionController.sessions,
                currentSessionId: sessionController.currentSessionId,
                onCreateThreadRequested: _createSessionFromDialog,
                onSessionSelected: (sessionId) async {
                  await sessionController.selectSession(sessionId);
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _selectedSection = AppSection.workspace;
                    _pendingForcedScrollToBottom = true;
                  });
                  _scheduleScrollToBottom(force: true, animated: true);
                },
                onRenameSession: _renameSession,
                onDeleteSession: _deleteSession,
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
    final sessionController = context.watch<AiSessionController>();
    if (_selectedSection == AppSection.workspace) {
      _maybeAutoFollowSession(sessionController.currentSession);
    }

    return switch (_selectedSection) {
      AppSection.workspace => _WorkspaceView(
        draftController: _composerController,
        messageScrollController: _messageScrollController,
        onMessageScrollNotification: _handleMessageScrollNotification,
        currentSession: sessionController.currentSession,
        selectedModel: settingsController.selectedAiModel,
        availableModels: settingsController.aiModels,
        onModelSelected: (modelId) {
          settingsController.updateSelectedAiModel(modelId);
        },
        composerHeight: _composerHeight,
        composerCollapsed: _composerCollapsed,
        onComposerHeightChanged: (nextHeight) {
          setState(() {
            _composerHeight = nextHeight;
          });
        },
        onComposerCollapsedChanged: (collapsed) {
          setState(() {
            _composerCollapsed = collapsed;
          });
        },
        autoFollowEnabled: _autoFollowEnabled,
        onToggleAutoFollow: _toggleAutoFollow,
        sendPhase: _effectiveSendPhase(sessionController),
        onSend: _sendMessage,
        onStop: _stopResponding,
        onCreateThreadRequested: _createSessionFromDialog,
        editingMessageId: sessionController.editingMessageId,
        onCancelEditing: _cancelEditingMessage,
        onEditMessage: _editMessage,
        onCopyMessage: _copyMessage,
      ),
      AppSection.automations => SectionPlaceholder(
        icon: Icons.schedule_send_outlined,
        title: l10n.automationHeadline,
        body: l10n.automationBody,
        footer: l10n.placeholderComingSoon,
        actionLabel: l10n.newThread,
        onAction: _createSessionFromDialog,
      ),
      AppSection.skills => const SkillsView(),
      AppSection.memory => const MemoryView(),
      AppSection.mcp => const McpView(),
      AppSection.settings => const SettingsView(),
    };
  }
}

extension on AppSection {
  int? get drawerIndex {
    return switch (this) {
      AppSection.workspace => null,
      AppSection.automations => 0,
      AppSection.skills => 1,
      AppSection.memory => 2,
      AppSection.mcp => 3,
      AppSection.settings => 4,
    };
  }
}

AppSection _sectionFromDrawerIndex(int index) {
  return switch (index) {
    0 => AppSection.automations,
    1 => AppSection.skills,
    2 => AppSection.memory,
    3 => AppSection.mcp,
    4 => AppSection.settings,
    _ => AppSection.workspace,
  };
}

class _NavigationPane extends StatelessWidget {
  const _NavigationPane({
    required this.selectedSection,
    required this.sessions,
    required this.currentSessionId,
    required this.onCreateThreadRequested,
    required this.onSessionSelected,
    required this.onRenameSession,
    required this.onDeleteSession,
    required this.onSectionSelected,
  });

  final AppSection selectedSection;
  final List<AiSession> sessions;
  final String? currentSessionId;
  final Future<void> Function() onCreateThreadRequested;
  final Future<void> Function(String sessionId) onSessionSelected;
  final Future<void> Function(AiSession session) onRenameSession;
  final Future<void> Function(AiSession session) onDeleteSession;
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
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: onCreateThreadRequested,
              icon: const Icon(Icons.add_comment_rounded),
              label: Text(l10n.newThread),
            ),
          ),
          const SizedBox(height: 12),
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
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                l10n.threadsEmptyBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: sessions
                    .map(
                      (session) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ThreadTile(
                          session: session,
                          isSelected: currentSessionId == session.id,
                          onTap: () => onSessionSelected(session.id),
                          onRename: () => onRenameSession(session),
                          onDelete: () => onDeleteSession(session),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
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

  @override
  void dispose() {
    _bodyScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Dialog(
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
                        const SizedBox(height: 16),
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
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(false),
                    label: AppLocalizations.of(context)!.commonCancel,
                  ),
                  const SizedBox(width: 12),
                  OpenHandDialogActionButton.primary(
                    onPressed: () => Navigator.of(context).pop(true),
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
    );
  }
}

class _WorkspaceView extends StatelessWidget {
  const _WorkspaceView({
    required this.draftController,
    required this.messageScrollController,
    required this.onMessageScrollNotification,
    required this.currentSession,
    required this.selectedModel,
    required this.availableModels,
    required this.onModelSelected,
    required this.composerHeight,
    required this.composerCollapsed,
    required this.onComposerHeightChanged,
    required this.onComposerCollapsedChanged,
    required this.autoFollowEnabled,
    required this.onToggleAutoFollow,
    required this.sendPhase,
    required this.onSend,
    required this.onStop,
    required this.onCreateThreadRequested,
    required this.editingMessageId,
    required this.onCancelEditing,
    required this.onEditMessage,
    required this.onCopyMessage,
  });

  final TextEditingController draftController;
  final ScrollController messageScrollController;
  final bool Function(ScrollNotification notification)
  onMessageScrollNotification;
  final AiSession? currentSession;
  final AiModelConfig? selectedModel;
  final List<AiModelConfig> availableModels;
  final ValueChanged<String> onModelSelected;
  final double composerHeight;
  final bool composerCollapsed;
  final ValueChanged<double> onComposerHeightChanged;
  final ValueChanged<bool> onComposerCollapsedChanged;
  final bool autoFollowEnabled;
  final VoidCallback onToggleAutoFollow;
  final AiSendPhase sendPhase;
  final Future<void> Function() onSend;
  final Future<void> Function() onStop;
  final Future<void> Function() onCreateThreadRequested;
  final String? editingMessageId;
  final Future<void> Function() onCancelEditing;
  final Future<void> Function(AiSessionMessage message) onEditMessage;
  final Future<void> Function(AiSessionMessage message) onCopyMessage;

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
              child: currentSession == null
                  ? _WorkspaceEmptyState(
                      key: const ValueKey<String>('no-session'),
                    )
                  : currentSession!.messages.isEmpty
                  ? _WorkspaceEmptyState(
                      key: ValueKey<String>(currentSession!.id),
                      session: currentSession,
                    )
                  : _SessionTranscript(
                      key: ValueKey<String>('messages-${currentSession!.id}'),
                      controller: messageScrollController,
                      onScrollNotification: onMessageScrollNotification,
                      session: currentSession!,
                      sendPhase: sendPhase,
                      onEditMessage: onEditMessage,
                      onCopyMessage: onCopyMessage,
                    ),
            ),
            const SizedBox(height: 16),
            _ComposerPanel(
              controller: draftController,
              selectedModel: selectedModel,
              availableModels: availableModels,
              onModelSelected: onModelSelected,
              composerHeight: effectiveComposerHeight,
              isCollapsed: composerCollapsed,
              onCollapsedChanged: onComposerCollapsedChanged,
              autoFollowEnabled: autoFollowEnabled,
              onToggleAutoFollow: onToggleAutoFollow,
              sendPhase: sendPhase,
              onSend: onSend,
              onStop: onStop,
              editingMessageId: editingMessageId,
              onCancelEditing: onCancelEditing,
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceEmptyState extends StatelessWidget {
  const _WorkspaceEmptyState({super.key, this.session});

  final AiSession? session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = session?.title ?? l10n.newThread;
    final subtitle = session?.templateName ?? l10n.appTitle;
    final emptyStateContent = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
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
          Text(title, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 10),
          Text(
            subtitle,
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

class _SessionTranscript extends StatefulWidget {
  const _SessionTranscript({
    super.key,
    required this.controller,
    required this.onScrollNotification,
    required this.session,
    required this.sendPhase,
    required this.onEditMessage,
    required this.onCopyMessage,
  });

  final ScrollController controller;
  final bool Function(ScrollNotification notification) onScrollNotification;
  final AiSession session;
  final AiSendPhase sendPhase;
  final Future<void> Function(AiSessionMessage message) onEditMessage;
  final Future<void> Function(AiSessionMessage message) onCopyMessage;

  @override
  State<_SessionTranscript> createState() => _SessionTranscriptState();
}

class _SessionTranscriptState extends State<_SessionTranscript> {
  String? _selectedMessageId;
  String? _visibleErrorId;
  String? _pendingPresentedErrorId;

  @override
  void initState() {
    super.initState();
    _syncVisibleError();
  }

  @override
  void didUpdateWidget(covariant _SessionTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id ||
        oldWidget.session.recentErrors != widget.session.recentErrors) {
      _syncVisibleError();
    }
  }

  void _syncVisibleError() {
    final visibleError = _resolveUserVisibleError(widget.session);
    final visibleErrorId = visibleError?.id;
    final hasCurrentVisibleError =
        _visibleErrorId != null &&
        widget.session.recentErrors.any((error) => error.id == _visibleErrorId);
    if (visibleError != null && visibleErrorId != null) {
      _visibleErrorId = visibleErrorId;
      _markErrorAsPresented(visibleError);
      return;
    }
    if (!hasCurrentVisibleError) {
      _visibleErrorId = null;
    }
  }

  void _markErrorAsPresented(AiSessionErrorRecord error) {
    if (error.hasBeenPresented || _pendingPresentedErrorId == error.id) {
      return;
    }
    _pendingPresentedErrorId = error.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await context.read<AiSessionController>().markErrorAsPresented(
        sessionId: widget.session.id,
        errorId: error.id,
      );
      if (!mounted || _pendingPresentedErrorId != error.id) {
        return;
      }
      _pendingPresentedErrorId = null;
    });
  }

  AiSessionErrorRecord? _resolveUserVisibleError(AiSession session) {
    for (final error in session.recentErrors) {
      if (error.stage == 'title_generation') {
        continue;
      }
      if (!error.hasBeenPresented) {
        return error;
      }
    }
    final visibleErrorId = _visibleErrorId;
    if (visibleErrorId == null) {
      return null;
    }
    for (final error in session.recentErrors) {
      if (error.id == visibleErrorId && error.stage != 'title_generation') {
        return error;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final displayMessages = _displayMessages(session);
    final userVisibleError = _resolveUserVisibleError(session);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SessionToolbar(session: session),
        const SizedBox(height: 14),
        if (session.latestCompressionAt != null) ...[
          _CompressionNoticeCard(session: session),
          const SizedBox(height: 14),
        ],
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: widget.onScrollNotification,
            child: ListView.separated(
              controller: widget.controller,
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: displayMessages.length,
              separatorBuilder: (context, index) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final message = displayMessages[index];
                return _MessageBubble(
                  key: ValueKey<String>(message.id),
                  message: message,
                  sessionTitle: session.title,
                  sessionEnvironment: session.environment,
                  showReasoningSweep:
                      widget.sendPhase == AiSendPhase.responding &&
                      _isStreamingReasoningMessage(message),
                  isSelected: _selectedMessageId == message.id,
                  onSelect: () {
                    setState(() {
                      _selectedMessageId = _selectedMessageId == message.id
                          ? null
                          : message.id;
                    });
                  },
                  onDeselect: () {
                    if (_selectedMessageId != message.id) {
                      return;
                    }
                    setState(() {
                      _selectedMessageId = null;
                    });
                  },
                  onEdit: message.kind == AiSessionMessageKind.user
                      ? () => widget.onEditMessage(message)
                      : null,
                  onCopy: () => widget.onCopyMessage(message),
                );
              },
            ),
          ),
        ),
        if (userVisibleError != null) ...[
          const SizedBox(height: 12),
          Text(
            userVisibleError.message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _SessionToolbar extends StatelessWidget {
  const _SessionToolbar({required this.session});

  final AiSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: Row(
                      children: [
                        _ToolbarPill(
                          icon: Icons.layers_rounded,
                          label:
                              '${session.templateName} · v${session.templateInternalVersion}',
                        ),
                        const SizedBox(width: 8),
                        _ToolbarPill(
                          icon: Icons.data_object_rounded,
                          label: _localizedText(
                            context,
                            zh: '会话元数据',
                            en: 'Session Metadata',
                          ),
                          onTap: () {
                            _showSessionMetadataDialog(context, session);
                          },
                        ),
                        const SizedBox(width: 8),
                        _ToolbarPill(
                          icon: Icons.update_rounded,
                          label: _formatDateTime(session.updatedAt),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _TokenDial(totalTokens: session.statistics.totalTokens ?? 0),
        ],
      ),
    );
  }
}

class _ToolbarPill extends StatelessWidget {
  const _ToolbarPill({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return child;
    }
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        overlayColor: WidgetStatePropertyAll(
          theme.colorScheme.primary.withValues(alpha: 0.08),
        ),
        child: child,
      ),
    );
  }
}

Future<void> _showSessionMetadataDialog(
  BuildContext context,
  AiSession session,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _SessionMetadataDialog(session: session),
  );
}

class _SessionMetadataDialog extends StatelessWidget {
  const _SessionMetadataDialog({required this.session});

  final AiSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statistics = session.statistics;
    final environment = session.environment;
    final recentErrors = session.recentErrors
        .where((error) => error.stage != 'title_generation')
        .toList(growable: false);
    final summaryBlocks = <Widget>[
      _MetadataSummaryTile(
        label: _localizedText(context, zh: '消息总数', en: 'Messages'),
        value: '${statistics.totalMessageCount}',
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: 'Prompt 构建', en: 'Prompt Builds'),
        value: '${statistics.promptBuildCount}',
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: '压缩次数', en: 'Compressions'),
        value: '${statistics.compressionRunCount}',
      ),
      _MetadataSummaryTile(
        label: _localizedText(context, zh: '总 Token', en: 'Total Tokens'),
        value: '${statistics.totalTokens ?? 0}',
      ),
    ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 860,
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _localizedText(
                            context,
                            zh: '当前会话元数据',
                            en: 'Current Session Metadata',
                          ),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          session.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(spacing: 12, runSpacing: 12, children: summaryBlocks),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '会话概览',
                          en: 'Session Overview',
                        ),
                        children: [
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'session_id',
                            ),
                            value: session.id,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(context, 'template'),
                            value:
                                '${session.templateName} · v${session.templateInternalVersion}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'created_at',
                            ),
                            value: _formatDateTime(session.createdAt),
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'updated_at',
                            ),
                            value: _formatDateTime(session.updatedAt),
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'last_model',
                            ),
                            value:
                                session.lastUsedModelLabel ??
                                session.lastUsedModelId ??
                                '-',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'compression_checkpoint',
                            ),
                            value:
                                session.latestCompressionCheckpointMessageId ??
                                '-',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'latest_compression_at',
                            ),
                            value: session.latestCompressionAt == null
                                ? '-'
                                : _formatDateTime(session.latestCompressionAt!),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '统计信息',
                          en: 'Statistics',
                        ),
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '用户', en: 'User')} ${statistics.userMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '助手', en: 'Assistant')} ${statistics.assistantMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '工具', en: 'Tool')} ${statistics.toolMessageCount}',
                              ),
                              _MetadataChip(
                                label: 'MCP ${statistics.mcpMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '技能', en: 'Skill')} ${statistics.skillMessageCount}',
                              ),
                              _MetadataChip(
                                label:
                                    '${_localizedText(context, zh: '压缩', en: 'Compression')} ${statistics.compressionPointCount}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'total_input_characters',
                            ),
                            value: '${statistics.totalInputCharacters}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'total_output_characters',
                            ),
                            value: '${statistics.totalOutputCharacters}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'total_prompt_characters',
                            ),
                            value: '${statistics.totalPromptCharacters}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'last_prompt_system_message_count',
                            ),
                            value: '${statistics.lastPromptSystemMessageCount}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'last_prompt_history_message_count',
                            ),
                            value:
                                '${statistics.lastPromptHistoryMessageCount}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '运行环境',
                          en: 'Environment',
                        ),
                        children: [
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'locale_tag',
                            ),
                            value: environment.localeTag,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(context, 'platform'),
                            value: environment.platform,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'app_version',
                            ),
                            value:
                                '${environment.appVersion} (${environment.appBuildNumber})',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'compression_threshold_chars',
                            ),
                            value: '${environment.compressionThresholdChars}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'application_directory',
                            ),
                            value: environment.applicationDirectory,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'home_directory',
                            ),
                            value: environment.homeDirectory,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'settings_file',
                            ),
                            value: environment.settingsFilePath,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'skills_storage',
                            ),
                            value: environment.skillsStoragePath,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'mcp_servers_file',
                            ),
                            value: environment.mcpServersFilePath,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'user_memory_file',
                            ),
                            value: environment.userMemoryFilePath,
                          ),
                          _MetadataEntryRow(
                            label: _localizedMetadataField(
                              context,
                              'sessions_directory',
                            ),
                            value: environment.sessionsDirectoryPath,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '最近异常',
                          en: 'Recent Errors',
                        ),
                        children: recentErrors.isEmpty
                            ? [
                                Text(
                                  _localizedText(
                                    context,
                                    zh: '当前没有需要关注的会话异常。',
                                    en: 'There are no session errors to review.',
                                  ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ]
                            : recentErrors
                                  .map(
                                    (error) => _MetadataErrorCard(error: error),
                                  )
                                  .toList(growable: false),
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '最后一次 Prompt 元数据',
                          en: 'Last Prompt Metadata',
                        ),
                        children: [
                          _MetadataJsonPanel(
                            content: const JsonEncoder.withIndent(
                              '  ',
                            ).convert(session.lastPromptMetadata),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: () => Navigator.of(context).pop(),
                    label: _localizedText(context, zh: '关闭', en: 'Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataSection extends StatelessWidget {
  const _MetadataSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _MetadataSummaryTile extends StatelessWidget {
  const _MetadataSummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 188,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataEntryRow extends StatelessWidget {
  const _MetadataEntryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetadataErrorCard extends StatelessWidget {
  const _MetadataErrorCard({required this.error});

  final AiSessionErrorRecord error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error.stage,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onErrorContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            error.message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onErrorContainer,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatDateTime(error.createdAt)} · ${error.hasBeenPresented ? _localizedText(context, zh: '已展示', en: 'Presented') : _localizedText(context, zh: '未展示', en: 'Pending')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onErrorContainer.withValues(alpha: 0.84),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataJsonPanel extends StatelessWidget {
  const _MetadataJsonPanel({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF17181C),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontFamily: 'monospace',
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _CompressionNoticeCard extends StatelessWidget {
  const _CompressionNoticeCard({required this.session});

  final AiSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            Icons.summarize_rounded,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.threadCompressionNotice,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.sessionTitle,
    required this.sessionEnvironment,
    required this.showReasoningSweep,
    required this.isSelected,
    required this.onSelect,
    required this.onDeselect,
    required this.onCopy,
    this.onEdit,
  });

  final AiSessionMessage message;
  final String sessionTitle;
  final AiSessionEnvironment sessionEnvironment;
  final bool showReasoningSweep;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onDeselect;
  final Future<void> Function() onCopy;
  final Future<void> Function()? onEdit;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _compressionExpanded = false;
  bool _reasoningExpanded = false;

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _compressionExpanded = false;
      _reasoningExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final message = widget.message;
    final isUser = message.kind == AiSessionMessageKind.user;
    final isCompressionPoint =
        message.kind == AiSessionMessageKind.compressionPoint;
    final isReasoning = message.kind == AiSessionMessageKind.reasoning;
    final isToolCall = message.kind == AiSessionMessageKind.toolCall;
    final isToolResult = message.kind == AiSessionMessageKind.tool;
    final isStatus = message.kind == AiSessionMessageKind.status;
    final isBashToolCall = isToolCall && _toolCallName(message) == 'bash';

    final alignment = isCompressionPoint
        ? Alignment.center
        : isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final borderRadius = BorderRadius.circular(isReasoning ? 18 : 26);
    final backgroundColor = isCompressionPoint
        ? colorScheme.tertiaryContainer
        : isUser
        ? colorScheme.primaryContainer
        : isReasoning
        ? const Color(0xFF18181B)
        : isToolCall
        ? colorScheme.secondaryContainer
        : isToolResult
        ? colorScheme.surfaceContainerHighest
        : isStatus
        ? colorScheme.surfaceContainer
        : colorScheme.surfaceContainerHigh;
    final textColor = isCompressionPoint
        ? colorScheme.onTertiaryContainer
        : isUser
        ? colorScheme.onPrimaryContainer
        : isReasoning
        ? Colors.white
        : isToolCall
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;
    final markdownStyleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge?.copyWith(color: textColor),
      codeblockDecoration: BoxDecoration(
        color: isReasoning
            ? Colors.white.withValues(alpha: 0.08)
            : colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontFamily: 'monospace',
      ),
    );
    final filePathRoots = _messageFilePathRoots(
      widget.sessionEnvironment,
      message,
    );
    final filePathParseKey = filePathRoots.join('|');
    final markdownBuilders = <String, MarkdownElementBuilder>{
      'pre': _HighlightedCodeBlockBuilder(
        theme: theme,
        baseColor: textColor,
        darkSurface: isReasoning || isToolCall,
      ),
      'openhand-file': _FilePathMarkdownBuilder(
        textColor: textColor,
        onOpenPath: _openResolvedMessagePath,
      ),
    };
    final inlineSyntaxes = <md.InlineSyntax>[
      _ExistingFilePathSyntax(candidateRoots: filePathRoots),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSelect,
      child: TapRegion(
        enabled: widget.isSelected,
        onTapOutside: (_) => widget.onDeselect(),
        child: Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: borderRadius,
                    border: isToolCall
                        ? Border.all(color: colorScheme.secondary, width: 1.2)
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isCompressionPoint)
                          _MessageMetaRow(
                            icon: Icons.summarize_rounded,
                            label: AppLocalizations.of(
                              context,
                            )!.threadCompressionCheckpointLabel,
                            color: textColor,
                          )
                        else if (isReasoning)
                          _ReasoningMetaRow(
                            message: message,
                            color: textColor,
                            showSweep: widget.showReasoningSweep,
                            expanded: _reasoningExpanded,
                            onTap: () {
                              setState(() {
                                _reasoningExpanded = !_reasoningExpanded;
                              });
                            },
                          )
                        else if (isToolCall)
                          _ToolCallMetaRow(message: message, color: textColor)
                        else if (isToolResult)
                          _MessageMetaRow(
                            icon: Icons.inventory_2_outlined,
                            label: _localizedText(
                              context,
                              zh: '工具结果',
                              en: 'Tool Result',
                            ),
                            color: textColor,
                          )
                        else if (message.modelLabel != null)
                          Text(
                            message.modelLabel!,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: isUser
                                  ? textColor.withValues(alpha: 0.86)
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (isCompressionPoint ||
                            isReasoning ||
                            isToolCall ||
                            isToolResult ||
                            message.modelLabel != null)
                          const SizedBox(height: 10),
                        if (isCompressionPoint)
                          _CompressionCheckpointBody(
                            content: message.content,
                            expanded: _compressionExpanded,
                            onToggle: () {
                              setState(() {
                                _compressionExpanded = !_compressionExpanded;
                              });
                            },
                            textColor: textColor,
                            fadeColor: backgroundColor,
                            styleSheet: markdownStyleSheet,
                            builders: markdownBuilders,
                            inlineSyntaxes: inlineSyntaxes,
                            parseKey: filePathParseKey,
                          )
                        else if (isReasoning)
                          _ReasoningBody(
                            content: message.content,
                            expanded: _reasoningExpanded,
                            textColor: textColor,
                            fadeColor: backgroundColor,
                            styleSheet: markdownStyleSheet,
                            builders: markdownBuilders,
                            inlineSyntaxes: inlineSyntaxes,
                            parseKey: filePathParseKey,
                          )
                        else if (isBashToolCall)
                          _BashToolCallBody(message: message)
                        else
                          _SafeMarkdownBody(
                            data: message.content.isEmpty
                                ? ' '
                                : message.content,
                            selectable: true,
                            builders: markdownBuilders,
                            styleSheet: markdownStyleSheet,
                            inlineSyntaxes: inlineSyntaxes,
                            parseKey: filePathParseKey,
                          ),
                        const SizedBox(height: 10),
                        Text(
                          _formatDateTime(message.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: textColor.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.isSelected)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        _MessageActionButton(
                          onPressed: widget.onCopy,
                          icon: Icons.content_copy_outlined,
                          label: _localizedText(context, zh: '复制', en: 'Copy'),
                        ),
                        if (widget.onEdit != null)
                          _MessageActionButton(
                            onPressed: widget.onEdit,
                            icon: Icons.edit_outlined,
                            label: AppLocalizations.of(context)!.commonEdit,
                          ),
                      ],
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

class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final Future<void> Function()? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );
  }
}

class _CompressionCheckpointBody extends StatelessWidget {
  const _CompressionCheckpointBody({
    required this.content,
    required this.expanded,
    required this.onToggle,
    required this.textColor,
    required this.fadeColor,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.parseKey,
  });

  final String content;
  final bool expanded;
  final VoidCallback onToggle;
  final Color textColor;
  final Color fadeColor;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final String parseKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toggleLabel = _localizedText(
      context,
      zh: expanded ? '收起摘要' : '展开摘要',
      en: expanded ? 'Collapse Summary' : 'Expand Summary',
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(18),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      toggleLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: textColor.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: textColor.withValues(alpha: 0.82),
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topLeft,
                  child: expanded
                      ? KeyedSubtree(
                          key: const ValueKey<String>('compression-expanded'),
                          child: _SafeMarkdownBody(
                            data: content.isEmpty ? ' ' : content,
                            selectable: true,
                            builders: builders,
                            styleSheet: styleSheet,
                            inlineSyntaxes: inlineSyntaxes,
                            parseKey: parseKey,
                          ),
                        )
                      : KeyedSubtree(
                          key: const ValueKey<String>('compression-preview'),
                          child: _MarkdownPreviewBody(
                            data: content.isEmpty ? ' ' : content,
                            maxHeight: 122,
                            styleSheet: styleSheet,
                            builders: builders,
                            inlineSyntaxes: inlineSyntaxes,
                            parseKey: '$parseKey|compression-preview',
                            fadeColor: fadeColor,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasoningBody extends StatelessWidget {
  const _ReasoningBody({
    required this.content,
    required this.expanded,
    required this.textColor,
    required this.fadeColor,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.parseKey,
  });

  final String content;
  final bool expanded;
  final Color textColor;
  final Color fadeColor;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final String parseKey;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topLeft,
        child: expanded
            ? KeyedSubtree(
                key: const ValueKey<String>('reasoning-expanded'),
                child: _SafeMarkdownBody(
                  data: content.isEmpty ? ' ' : content,
                  selectable: true,
                  builders: builders,
                  styleSheet: styleSheet,
                  inlineSyntaxes: inlineSyntaxes,
                  parseKey: parseKey,
                ),
              )
            : KeyedSubtree(
                key: const ValueKey<String>('reasoning-preview'),
                child: _MarkdownPreviewBody(
                  data: content.isEmpty ? ' ' : content,
                  maxHeight: 142,
                  styleSheet: styleSheet,
                  builders: builders,
                  inlineSyntaxes: inlineSyntaxes,
                  parseKey: '$parseKey|reasoning-preview',
                  fadeColor: fadeColor,
                ),
              ),
      ),
    );
  }
}

class _MarkdownPreviewBody extends StatefulWidget {
  const _MarkdownPreviewBody({
    required this.data,
    required this.maxHeight,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.parseKey,
    required this.fadeColor,
  });

  final String data;
  final double maxHeight;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final String parseKey;
  final Color fadeColor;

  @override
  State<_MarkdownPreviewBody> createState() => _MarkdownPreviewBodyState();
}

class _MarkdownPreviewBodyState extends State<_MarkdownPreviewBody> {
  double? _contentHeight;

  @override
  void didUpdateWidget(covariant _MarkdownPreviewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parseKey != widget.parseKey) {
      _contentHeight = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final measuredHeight = _contentHeight;
    final effectiveHeight = measuredHeight == null
        ? widget.maxHeight
        : math.min(measuredHeight, widget.maxHeight);
    final showFade =
        measuredHeight != null && measuredHeight > widget.maxHeight + 0.5;
    return LayoutBuilder(
      builder: (context, constraints) {
        final constrainedWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return SizedBox(
          height: effectiveHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: constrainedWidth,
                    maxWidth: constrainedWidth,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: _MeasureSize(
                      onChange: (size) {
                        if (!mounted) {
                          return;
                        }
                        final nextHeight = size.height;
                        final currentHeight = _contentHeight;
                        if (currentHeight != null &&
                            (currentHeight - nextHeight).abs() < 0.5) {
                          return;
                        }
                        setState(() {
                          _contentHeight = nextHeight;
                        });
                      },
                      child: IgnorePointer(
                        ignoring: true,
                        child: _SafeMarkdownBody(
                          data: widget.data,
                          selectable: false,
                          builders: widget.builders,
                          styleSheet: widget.styleSheet,
                          inlineSyntaxes: widget.inlineSyntaxes,
                          parseKey: widget.parseKey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showFade)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 26,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            widget.fadeColor.withValues(alpha: 0),
                            widget.fadeColor.withValues(alpha: 0.96),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMeasureSize(onChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size;
    if (newSize == null || _oldSize == newSize) {
      return;
    }
    _oldSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onChange(newSize);
    });
  }
}

class _SafeMarkdownBody extends StatefulWidget {
  const _SafeMarkdownBody({
    required this.data,
    required this.styleSheet,
    this.selectable = false,
    this.builders = const <String, MarkdownElementBuilder>{},
    this.inlineSyntaxes = const <md.InlineSyntax>[],
    this.parseKey = '',
  });

  final String data;
  final MarkdownStyleSheet styleSheet;
  final bool selectable;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final String parseKey;

  @override
  State<_SafeMarkdownBody> createState() => _SafeMarkdownBodyState();
}

class _SafeMarkdownBodyState extends State<_SafeMarkdownBody>
    implements MarkdownBuilderDelegate {
  List<Widget>? _children;
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];
  int? _lastThemeSignature;
  String? _lastData;
  bool? _lastSelectable;
  String? _lastBuilderSignature;
  String? _lastParseKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeSignature = _computeThemeSignature();
    if (_children == null || _lastThemeSignature != themeSignature) {
      _lastThemeSignature = themeSignature;
      _parseMarkdown();
    }
  }

  @override
  void didUpdateWidget(covariant _SafeMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final builderSignature = _builderSignature();
    if (_lastData != widget.data ||
        _lastSelectable != widget.selectable ||
        _lastBuilderSignature != builderSignature ||
        _lastParseKey != widget.parseKey) {
      _parseMarkdown();
      return;
    }
    final themeSignature = _computeThemeSignature();
    if (_lastThemeSignature != themeSignature) {
      _lastThemeSignature = themeSignature;
      _parseMarkdown();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _parseMarkdown() {
    final effectiveStyleSheet = MarkdownStyleSheet.fromTheme(
      Theme.of(context),
    ).merge(widget.styleSheet);
    _lastThemeSignature = _computeThemeSignature();
    _lastData = widget.data;
    _lastSelectable = widget.selectable;
    _lastBuilderSignature = _builderSignature();
    _lastParseKey = widget.parseKey;
    _disposeRecognizers();
    try {
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        inlineSyntaxes: widget.inlineSyntaxes,
        encodeHtml: false,
      );
      final astNodes = document.parseLines(
        const LineSplitter().convert(
          _sanitizeMarkdownSource(widget.data.isEmpty ? ' ' : widget.data),
        ),
      );
      _sanitizeMarkdownAst(astNodes);
      final builder = MarkdownBuilder(
        delegate: this,
        selectable: widget.selectable,
        styleSheet: effectiveStyleSheet,
        imageDirectory: null,
        imageBuilder: null,
        checkboxBuilder: null,
        bulletBuilder: null,
        builders: widget.builders,
        paddingBuilders: const <String, MarkdownPaddingBuilder>{},
        fitContent: true,
        listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
        onSelectionChanged: null,
        onTapText: null,
        softLineBreak: false,
      );
      _children = builder.build(astNodes);
    } catch (_) {
      _children = <Widget>[
        SelectableText(widget.data, style: effectiveStyleSheet.p),
      ];
    }
  }

  int _computeThemeSignature() {
    final theme = Theme.of(context);
    return Object.hashAll(<Object?>[
      theme.brightness,
      theme.colorScheme.surface.toARGB32(),
      theme.colorScheme.onSurface.toARGB32(),
      theme.colorScheme.primary.toARGB32(),
      widget.styleSheet.p?.color?.toARGB32(),
      widget.styleSheet.code?.color?.toARGB32(),
    ]);
  }

  String _builderSignature() {
    final keys = widget.builders.keys.toList(growable: false)..sort();
    return keys.join('|');
  }

  String _sanitizeMarkdownSource(String source) {
    return source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAllMapped(
          RegExp(r'(^|\n)(\s*)(=+|\^+)(?=\n|$)'),
          (match) => '${match[1]}${match[2]}\\${match[3]}',
        );
  }

  void _sanitizeMarkdownAst(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is! md.Element) {
        continue;
      }
      if (node.tag == 'ol') {
        final start = node.attributes['start'];
        if (start != null && int.tryParse(start.trim()) == null) {
          node.attributes.remove('start');
        }
      }
      final children = node.children;
      if (children != null && children.isNotEmpty) {
        _sanitizeMarkdownAst(children);
      }
    }
  }

  void _disposeRecognizers() {
    if (_recognizers.isEmpty) {
      return;
    }
    final localRecognizers = List<GestureRecognizer>.from(_recognizers);
    _recognizers.clear();
    for (final recognizer in localRecognizers) {
      recognizer.dispose();
    }
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final recognizer = TapGestureRecognizer();
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    final normalizedCode = code.replaceAll(RegExp(r'\n$'), '');
    return TextSpan(text: normalizedCode, style: styleSheet.code);
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    if (children == null || children.isEmpty) {
      return const SizedBox.shrink();
    }
    if (children.length == 1) {
      return children.single;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _BashToolCallBody extends StatefulWidget {
  const _BashToolCallBody({required this.message});

  final AiSessionMessage message;

  @override
  State<_BashToolCallBody> createState() => _BashToolCallBodyState();
}

class _BashToolCallBodyState extends State<_BashToolCallBody> {
  bool _commandExpanded = false;
  bool _resultExpanded = false;

  @override
  void didUpdateWidget(covariant _BashToolCallBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _commandExpanded = false;
      _resultExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final command = _toolExecutionCommand(message);
    final workingDirectory = _toolExecutionWorkingDirectory(message);
    final stdout = _toolExecutionStdout(message);
    final stderr = _toolExecutionStderr(message);
    final exitCode = _toolExecutionExitCode(message);
    final status = _toolExecutionStatus(message);
    final hasResultContent =
        stdout.trim().isNotEmpty ||
        stderr.trim().isNotEmpty ||
        exitCode != null ||
        status.isNotEmpty;
    final commandPlaceholder = _localizedText(
      context,
      zh: '正在解析命令参数...',
      en: 'Parsing command arguments...',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ExpandableToolSection(
          title: _localizedText(context, zh: '执行命令', en: 'Command'),
          preview: command.isEmpty ? commandPlaceholder : '\$ $command',
          expanded: _commandExpanded,
          onToggle: () {
            setState(() {
              _commandExpanded = !_commandExpanded;
            });
          },
          child: command.isEmpty
              ? Text(
                  commandPlaceholder,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : _ToolCodePanel(content: '\$ $command', theme: theme),
        ),
        const SizedBox(height: 10),
        _ExpandableToolSection(
          title: _localizedText(context, zh: '执行结果', en: 'Output'),
          preview: hasResultContent
              ? _toolExecutionPreview(context, message)
              : _localizedText(context, zh: '暂无输出', en: 'No output yet'),
          expanded: _resultExpanded,
          onToggle: () {
            setState(() {
              _resultExpanded = !_resultExpanded;
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stdout.trim().isNotEmpty)
                _ToolOutputPanel(
                  label: 'stdout',
                  content: stdout.trimRight(),
                  theme: theme,
                ),
              if (stderr.trim().isNotEmpty) ...[
                if (stdout.trim().isNotEmpty) const SizedBox(height: 10),
                _ToolOutputPanel(
                  label: 'stderr',
                  content: stderr.trimRight(),
                  theme: theme,
                  isError: true,
                ),
              ],
              if (stdout.trim().isEmpty && stderr.trim().isEmpty)
                Text(
                  _localizedText(
                    context,
                    zh: '当前还没有命令输出。',
                    en: 'There is no command output yet.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (workingDirectory.isNotEmpty)
              _ToolExecutionChip(
                icon: Icons.folder_outlined,
                label:
                    '${_localizedText(context, zh: '目录', en: 'Dir')}: $workingDirectory',
              ),
            if (status.isNotEmpty)
              _ToolExecutionChip(
                icon: _toolCallStatusIcon(message),
                label: _toolExecutionOutcomeLabel(context, status),
              ),
            if (_toolExecutionDurationMs(message) > 0 || status == 'running')
              _ToolExecutionChip(
                icon: Icons.timer_outlined,
                label:
                    '${_localizedText(context, zh: '耗时', en: 'Elapsed')}: ${_formatToolExecutionDuration(_toolExecutionDurationMs(message))}',
              ),
            if (exitCode != null)
              _ToolExecutionChip(
                icon: Icons.flag_outlined,
                label:
                    '${_localizedText(context, zh: '退出码', en: 'Exit')}: $exitCode',
              ),
          ],
        ),
      ],
    );
  }
}

class _ExpandableToolSection extends StatelessWidget {
  const _ExpandableToolSection({
    required this.title,
    required this.preview,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String preview;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (!expanded && preview.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
              ],
              if (expanded) ...[const SizedBox(height: 12), child],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolCodePanel extends StatelessWidget {
  const _ToolCodePanel({required this.content, required this.theme});

  final String content;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF202126),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          content,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontFamily: 'monospace',
            height: 1.42,
          ),
        ),
      ),
    );
  }
}

class _ToolOutputPanel extends StatelessWidget {
  const _ToolOutputPanel({
    required this.label,
    required this.content,
    required this.theme,
    this.isError = false,
  });

  final String label;
  final String content;
  final ThemeData theme;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: isError
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _ToolCodePanel(content: content, theme: theme),
      ],
    );
  }
}

class _ToolExecutionChip extends StatelessWidget {
  const _ToolExecutionChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

String _toolCallName(AiSessionMessage message) =>
    '${message.metadata['tool_name'] ?? ''}'.trim();

String _toolExecutionStatus(AiSessionMessage message) =>
    '${message.metadata['tool_execution_status'] ?? ''}'.trim();

bool _shouldSweepToolCallBadge(AiSessionMessage message) {
  if (_toolCallName(message) != 'bash') {
    return false;
  }
  final status = _toolExecutionStatus(message);
  return status.isEmpty || status == 'running';
}

String _toolExecutionCommand(AiSessionMessage message) {
  final executionCommand = '${message.metadata['tool_execution_command'] ?? ''}'
      .trim();
  if (executionCommand.isNotEmpty) {
    return executionCommand;
  }
  final rawArguments = '${message.metadata['tool_arguments'] ?? ''}'.trim();
  if (rawArguments.isEmpty) {
    return '';
  }
  return parseBashToolCommandFromArguments(rawArguments);
}

String _toolExecutionWorkingDirectory(AiSessionMessage message) {
  final executionDirectory =
      '${message.metadata['tool_execution_working_directory'] ?? ''}'.trim();
  if (executionDirectory.isNotEmpty) {
    return executionDirectory;
  }
  final rawArguments = '${message.metadata['tool_arguments'] ?? ''}'.trim();
  if (rawArguments.isEmpty) {
    return '';
  }
  return parseBashToolWorkingDirectoryFromArguments(rawArguments);
}

String _toolExecutionStdout(AiSessionMessage message) =>
    '${message.metadata['tool_execution_stdout'] ?? ''}';

String _toolExecutionStderr(AiSessionMessage message) =>
    '${message.metadata['tool_execution_stderr'] ?? ''}';

bool _isStreamingReasoningMessage(AiSessionMessage message) {
  return message.kind == AiSessionMessageKind.reasoning &&
      message.metadata[aiSessionMessageMetadataStreamingKey] == true;
}

int _reasoningElapsedMs(AiSessionMessage message) {
  final elapsed = DateTime.now()
      .toUtc()
      .difference(message.createdAt.toUtc())
      .inMilliseconds;
  return math.max(0, elapsed);
}

int? _toolExecutionExitCode(AiSessionMessage message) {
  final value = message.metadata['tool_execution_exit_code'];
  if (value is int) {
    return value;
  }
  return int.tryParse('${value ?? ''}'.trim());
}

IconData _toolCallStatusIcon(AiSessionMessage message) {
  return switch (_toolExecutionStatus(message)) {
    'running' => Icons.play_circle_outline_rounded,
    'cancelled' => Icons.stop_circle_outlined,
    'success' => Icons.check_circle_outline_rounded,
    'denied' => Icons.block_rounded,
    'rejected' => Icons.cancel_outlined,
    'timed_out' => Icons.timer_off_outlined,
    'failed' => Icons.error_outline_rounded,
    'invalid_arguments' => Icons.warning_amber_rounded,
    _ => Icons.terminal_rounded,
  };
}

String _toolCallStatusLabel(BuildContext context, AiSessionMessage message) {
  final status = _toolExecutionStatus(message);
  if (_toolCallName(message) != 'bash') {
    return _localizedText(context, zh: '工具调用', en: 'Tool Call');
  }
  final durationMs = _toolExecutionDurationMs(message);
  final suffix = durationMs <= 0
      ? ''
      : ' (${_formatToolExecutionDuration(durationMs)})';
  return switch (status) {
    '' => _localizedText(context, zh: '准备执行命令', en: 'Preparing Command'),
    'running' =>
      '${_localizedText(context, zh: '正在运行命令', en: 'Running Command')}$suffix',
    'cancelled' =>
      '${_localizedText(context, zh: '命令已停止', en: 'Command Stopped')}$suffix',
    'success' =>
      '${_localizedText(context, zh: '命令执行完成', en: 'Command Completed')}$suffix',
    'denied' => _localizedText(context, zh: '命令已拦截', en: 'Command Blocked'),
    'rejected' => _localizedText(context, zh: '命令已拒绝', en: 'Command Rejected'),
    'timed_out' =>
      '${_localizedText(context, zh: '命令执行超时', en: 'Command Timed Out')}$suffix',
    'failed' =>
      '${_localizedText(context, zh: '命令执行失败', en: 'Command Failed')}$suffix',
    'invalid_arguments' => _localizedText(
      context,
      zh: '命令参数无效',
      en: 'Invalid Command',
    ),
    _ => _localizedText(context, zh: '工具调用', en: 'Tool Call'),
  };
}

String _toolExecutionOutcomeLabel(BuildContext context, String status) {
  return switch (status) {
    'running' => _localizedText(context, zh: '运行中', en: 'Running'),
    'cancelled' => _localizedText(context, zh: '已停止', en: 'Stopped'),
    'success' => _localizedText(context, zh: '执行成功', en: 'Succeeded'),
    'denied' => _localizedText(context, zh: '已被禁止', en: 'Denied'),
    'rejected' => _localizedText(context, zh: '用户拒绝', en: 'Rejected'),
    'timed_out' => _localizedText(context, zh: '执行超时', en: 'Timed Out'),
    'failed' => _localizedText(context, zh: '执行失败', en: 'Failed'),
    'invalid_arguments' => _localizedText(context, zh: '参数无效', en: 'Invalid'),
    _ => status,
  };
}

String _toolExecutionPreview(BuildContext context, AiSessionMessage message) {
  final stderrLine = _lastNonEmptyToolOutputLine(_toolExecutionStderr(message));
  if (stderrLine.isNotEmpty) {
    return 'stderr · $stderrLine';
  }
  final stdoutLine = _lastNonEmptyToolOutputLine(_toolExecutionStdout(message));
  if (stdoutLine.isNotEmpty) {
    return 'stdout · $stdoutLine';
  }
  if (_shouldSweepToolCallBadge(message)) {
    return _localizedText(
      context,
      zh: '命令准备中，等待新的输出...',
      en: 'Command is starting. Waiting for output...',
    );
  }
  return _localizedText(
    context,
    zh: '点击展开查看命令输出',
    en: 'Expand to inspect command output',
  );
}

String _lastNonEmptyToolOutputLine(String content) {
  final lines = const LineSplitter()
      .convert(content)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) {
    return '';
  }
  return lines.last;
}

int _toolExecutionDurationMs(AiSessionMessage message) {
  final rawValue =
      message.metadata['tool_execution_elapsed_ms'] ??
      message.metadata['tool_execution_duration_ms'] ??
      0;
  if (rawValue is int) {
    return rawValue;
  }
  return int.tryParse('$rawValue'.trim()) ?? 0;
}

String _formatToolExecutionDuration(int durationMs) {
  final totalSeconds = (durationMs / 1000).floor();
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes}m ${seconds}s';
}

final Map<String, _ResolvedMessagePath?> _resolvedMessagePathCache =
    <String, _ResolvedMessagePath?>{};
final RegExp _detectedFilePathTrailingPattern = RegExp(
  r'''[),.;:!?\]\}'"]+$''',
);

List<String> _messageFilePathRoots(
  AiSessionEnvironment environment,
  AiSessionMessage message,
) {
  final roots = <String>{};
  void addRoot(String? rawPath) {
    if (rawPath == null) {
      return;
    }
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return;
    }
    roots.add(p.normalize(trimmed));
  }

  void addParentRoot(String? rawPath) {
    if (rawPath == null) {
      return;
    }
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return;
    }
    addRoot(p.dirname(trimmed));
  }

  addRoot(Directory.current.path);
  addRoot(environment.applicationDirectory);
  addRoot(environment.homeDirectory);
  addRoot(_toolExecutionWorkingDirectory(message));
  addRoot(environment.skillsStoragePath);
  addRoot(environment.sessionsDirectoryPath);
  addParentRoot(environment.settingsFilePath);
  addParentRoot(environment.mcpServersFilePath);
  addParentRoot(environment.userMemoryFilePath);
  return roots.toList(growable: false);
}

_ResolvedMessagePath? _resolveExistingMessagePath(
  String rawPath,
  List<String> candidateRoots,
) {
  final displayPath = rawPath.trim();
  if (displayPath.isEmpty) {
    return null;
  }
  final cacheKey = '${candidateRoots.join('|')}::$displayPath';
  if (_resolvedMessagePathCache.containsKey(cacheKey)) {
    return _resolvedMessagePathCache[cacheKey];
  }

  final candidates = <String>{};
  if (displayPath == '~' ||
      displayPath.startsWith('~/') ||
      displayPath.startsWith(r'~\')) {
    candidates.add(
      OpenHandPaths.normalizePath(
        displayPath,
        defaultPath: OpenHandPaths.homeDirectoryPath(),
      ),
    );
  }
  if (_looksLikeAbsoluteMessagePath(displayPath)) {
    candidates.add(p.normalize(displayPath));
  } else {
    for (final root in candidateRoots) {
      if (root.trim().isEmpty) {
        continue;
      }
      candidates.add(p.normalize(p.join(root, displayPath)));
    }
  }

  _ResolvedMessagePath? resolved;
  for (final candidate in candidates) {
    final entityType = FileSystemEntity.typeSync(candidate, followLinks: true);
    if (entityType == FileSystemEntityType.notFound) {
      continue;
    }
    final isDirectory =
        entityType == FileSystemEntityType.directory ||
        Directory(candidate).existsSync();
    resolved = _ResolvedMessagePath(
      displayPath: displayPath,
      resolvedPath: p.normalize(candidate),
      isDirectory: isDirectory,
    );
    break;
  }
  _resolvedMessagePathCache[cacheKey] = resolved;
  return resolved;
}

bool _looksLikeAbsoluteMessagePath(String path) {
  return path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

Future<void> _openResolvedMessagePath(
  BuildContext context,
  _ResolvedMessagePath resolvedPath,
) async {
  try {
    late final ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run(
        'open',
        resolvedPath.isDirectory
            ? <String>[resolvedPath.resolvedPath]
            : <String>['-R', resolvedPath.resolvedPath],
      );
    } else if (Platform.isWindows) {
      result = await Process.run(
        'explorer',
        resolvedPath.isDirectory
            ? <String>[resolvedPath.resolvedPath]
            : <String>['/select,${resolvedPath.resolvedPath}'],
      );
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', <String>[
        resolvedPath.isDirectory
            ? resolvedPath.resolvedPath
            : p.dirname(resolvedPath.resolvedPath),
      ]);
    } else {
      throw const FileSystemException('Unsupported platform.');
    }
    if (result.exitCode == 0) {
      return;
    }
    final message = '${result.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty ? 'Unable to open file location.' : message,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localizedText(
            context,
            zh: '打开文件位置失败：$error',
            en: 'Failed to open file location: $error',
          ),
        ),
      ),
    );
  }
}

class _ResolvedMessagePath {
  const _ResolvedMessagePath({
    required this.displayPath,
    required this.resolvedPath,
    required this.isDirectory,
  });

  final String displayPath;
  final String resolvedPath;
  final bool isDirectory;
}

class _ExistingFilePathSyntax extends md.InlineSyntax {
  _ExistingFilePathSyntax({required this.candidateRoots})
    : super(
        r'''(^|[\s(>"'])((?:~\/|\.{1,2}\/|\/|[A-Za-z]:[\\/]|(?:[A-Za-z0-9_.-]+[\\/]))[^\s<>()\[\]{}]+)''',
      );

  final List<String> candidateRoots;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final prefix = match[1] ?? '';
    final matchedPath = match[2] ?? '';
    final normalizedPath = matchedPath.replaceFirst(
      _detectedFilePathTrailingPattern,
      '',
    );
    if (normalizedPath.isEmpty) {
      return false;
    }
    final trailing = matchedPath.substring(normalizedPath.length);
    final resolvedPath = _resolveExistingMessagePath(
      normalizedPath,
      candidateRoots,
    );
    if (resolvedPath == null) {
      return false;
    }
    if (prefix.isNotEmpty) {
      parser.addNode(md.Text(prefix));
    }
    parser.addNode(
      md.Element.text('openhand-file', resolvedPath.displayPath)
        ..attributes['resolved_path'] = resolvedPath.resolvedPath
        ..attributes['entity_type'] = resolvedPath.isDirectory
            ? 'directory'
            : 'file',
    );
    if (trailing.isNotEmpty) {
      parser.addNode(md.Text(trailing));
    }
    return true;
  }
}

class _FilePathMarkdownBuilder extends MarkdownElementBuilder {
  _FilePathMarkdownBuilder({required this.textColor, required this.onOpenPath});

  final Color textColor;
  final Future<void> Function(
    BuildContext context,
    _ResolvedMessagePath resolvedPath,
  )
  onOpenPath;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final resolvedPath = (element.attributes['resolved_path'] ?? '').trim();
    final displayPath = element.textContent.trim();
    final isDirectory =
        (element.attributes['entity_type'] ?? '').trim() == 'directory';
    final theme = Theme.of(context);
    final chipColor = theme.colorScheme.surface.withValues(alpha: 0.68);
    final borderColor = textColor.withValues(alpha: 0.24);
    final labelStyle =
        theme.textTheme.labelMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ) ??
        TextStyle(color: textColor, fontWeight: FontWeight.w700);
    return Text.rich(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: resolvedPath,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  onOpenPath(
                    context,
                    _ResolvedMessagePath(
                      displayPath: displayPath,
                      resolvedPath: resolvedPath,
                      isDirectory: isDirectory,
                    ),
                  );
                },
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: chipColor,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDirectory
                            ? Icons.folder_outlined
                            : Icons.insert_drive_file_outlined,
                        size: 14,
                        color: textColor.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Text(
                          displayPath,
                          overflow: TextOverflow.ellipsis,
                          style: labelStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
    required this.isCollapsed,
    required this.onCollapsedChanged,
    required this.autoFollowEnabled,
    required this.onToggleAutoFollow,
    required this.sendPhase,
    required this.onSend,
    required this.onStop,
    required this.editingMessageId,
    required this.onCancelEditing,
  });

  final TextEditingController controller;
  final AiModelConfig? selectedModel;
  final List<AiModelConfig> availableModels;
  final ValueChanged<String> onModelSelected;
  final double composerHeight;
  final bool isCollapsed;
  final ValueChanged<bool> onCollapsedChanged;
  final bool autoFollowEnabled;
  final VoidCallback onToggleAutoFollow;
  final AiSendPhase sendPhase;
  final Future<void> Function() onSend;
  final Future<void> Function() onStop;
  final String? editingMessageId;
  final Future<void> Function() onCancelEditing;

  @override
  State<_ComposerPanel> createState() => _ComposerPanelState();
}

class _ComposerPanelState extends State<_ComposerPanel> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final selectedModelLabel =
        widget.selectedModel?.displayName ?? l10n.chatModelButton;
    final isCompressing = widget.sendPhase == AiSendPhase.compressing;
    final isSendingMessage = widget.sendPhase == AiSendPhase.sendingMessage;
    final isResponding = widget.sendPhase == AiSendPhase.responding;
    final sendButtonLabel = switch (widget.sendPhase) {
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
              borderRadius: BorderRadius.circular(999),
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
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: SizedBox(
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
        ),
      ],
    );

    final actionRow = Row(
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
                  child: Text(model.displayName),
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
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: isCompressing || isSendingMessage
                ? null
                : isResponding
                ? () {
                    widget.onStop();
                  }
                : () {
                    widget.onSend();
                  },
            icon: isCompressing || isSendingMessage
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
            label: Text(sendButtonLabel),
          ),
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

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.session,
    required this.isSelected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final AiSession session;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = isSelected
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerLow;
    final titleColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    return GestureDetector(
      onSecondaryTapDown: (details) async {
        final selected = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          items: [
            PopupMenuItem<String>(
              value: 'rename',
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.commonEdit),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.commonDelete),
                ],
              ),
            ),
          ],
        );
        if (selected == 'rename') {
          onRename();
        } else if (selected == 'delete') {
          onDelete();
        }
      },
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Text(
              session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(color: titleColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageMetaRow extends StatelessWidget {
  const _MessageMetaRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _ReasoningMetaRow extends StatefulWidget {
  const _ReasoningMetaRow({
    required this.message,
    required this.color,
    required this.showSweep,
    required this.expanded,
    required this.onTap,
  });

  final AiSessionMessage message;
  final Color color;
  final bool showSweep;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_ReasoningMetaRow> createState() => _ReasoningMetaRowState();
}

class _ReasoningMetaRowState extends State<_ReasoningMetaRow> {
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _syncElapsedTimer();
  }

  @override
  void didUpdateWidget(covariant _ReasoningMetaRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showSweep != widget.showSweep ||
        oldWidget.message.id != widget.message.id ||
        oldWidget.message.createdAt != widget.message.createdAt) {
      _syncElapsedTimer();
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _syncElapsedTimer() {
    _elapsedTimer?.cancel();
    if (!widget.showSweep) {
      return;
    }
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = _localizedText(context, zh: '思考', en: 'Reasoning');
    final elapsedText = widget.showSweep
        ? ' (${_formatToolExecutionDuration(_reasoningElapsedMs(widget.message))})'
        : '';
    final pillContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.psychology_alt_outlined,
          size: 18,
          color: widget.color.withValues(alpha: widget.showSweep ? 0.94 : 0.88),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$labelText$elapsedText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: widget.color.withValues(
                alpha: widget.showSweep ? 0.94 : 0.88,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        AnimatedRotation(
          turns: widget.expanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: widget.color.withValues(alpha: 0.78),
            size: 18,
          ),
        ),
      ],
    );
    final capsule = widget.showSweep
        ? _SweepBadge(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            borderColor: Colors.white.withValues(alpha: 0.14),
            sweepColor: const Color(0x33E5E7EB),
            child: pillContent,
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: pillContent,
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(999),
        overlayColor: WidgetStatePropertyAll(
          Colors.white.withValues(alpha: 0.03),
        ),
        child: capsule,
      ),
    );
  }
}

class _ToolCallMetaRow extends StatelessWidget {
  const _ToolCallMetaRow({required this.message, required this.color});

  final AiSessionMessage message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSweep = _shouldSweepToolCallBadge(message);
    final effectiveColor = showSweep
        ? theme.colorScheme.onSurfaceVariant
        : color;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_toolCallStatusIcon(message), size: 18, color: effectiveColor),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _toolCallStatusLabel(context, message),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(color: effectiveColor),
          ),
        ),
      ],
    );
    if (showSweep) {
      return _SweepBadge(child: row);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: row,
    );
  }
}

class _SweepBadge extends StatefulWidget {
  const _SweepBadge({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.backgroundColor,
    this.borderColor,
    this.sweepColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? sweepColor;

  @override
  State<_SweepBadge> createState() => _SweepBadgeState();
}

class _SweepBadgeState extends State<_SweepBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const borderRadius = BorderRadius.all(Radius.circular(999));
    return ClipRRect(
      borderRadius: borderRadius,
      child: AnimatedBuilder(
        animation: _controller,
        child: Padding(padding: widget.padding, child: widget.child),
        builder: (context, child) {
          final start = -1.8 + (_controller.value * 2.8);
          final end = start + 0.9;
          final sweepColor =
              widget.sweepColor ??
              theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2);
          final backgroundColor =
              widget.backgroundColor ?? theme.colorScheme.surfaceContainerHigh;
          final borderColor =
              widget.borderColor ??
              theme.colorScheme.outlineVariant.withValues(alpha: 0.45);
          return DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: borderRadius,
              border: borderColor.a <= 0
                  ? null
                  : Border.all(color: borderColor),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(start, 0),
                        end: Alignment(end, 0),
                        colors: [
                          Colors.transparent,
                          sweepColor,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                child ?? const SizedBox.shrink(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HighlightedCodeBlockBuilder extends MarkdownElementBuilder {
  _HighlightedCodeBlockBuilder({
    required ThemeData theme,
    required Color baseColor,
    required bool darkSurface,
  }) : _baseStyle =
           theme.textTheme.bodyMedium?.copyWith(
             color: baseColor,
             fontFamily: 'monospace',
             height: 1.48,
           ) ??
           TextStyle(color: baseColor, fontFamily: 'monospace', height: 1.48),
       _containerColor = darkSurface
           ? Colors.white.withValues(alpha: 0.08)
           : theme.colorScheme.surface.withValues(alpha: 0.9),
       _borderColor = darkSurface
           ? Colors.white.withValues(alpha: 0.08)
           : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
       _darkSurface = darkSurface;

  final TextStyle _baseStyle;
  final Color _containerColor;
  final Color _borderColor;
  final bool _darkSurface;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final codeElement = _findCodeElement(element);
    final rawCode = (codeElement?.textContent ?? element.textContent)
        .replaceFirst(RegExp(r'\n$'), '');
    final language = _extractLanguage(codeElement);
    final content = rawCode.isEmpty ? ' ' : rawCode;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _containerColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText.rich(_buildHighlightedText(content, language)),
      ),
    );
  }

  md.Element? _findCodeElement(md.Element element) {
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'code') {
        return child;
      }
    }
    return null;
  }

  String? _extractLanguage(md.Element? element) {
    final classes = (element?.attributes['class'] ?? '').trim();
    if (classes.isEmpty) {
      return null;
    }
    for (final name in classes.split(' ')) {
      if (name.startsWith('language-') && name.length > 9) {
        return name.substring(9);
      }
      if (name.startsWith('lang-') && name.length > 5) {
        return name.substring(5);
      }
    }
    return null;
  }

  TextSpan _buildHighlightedText(String source, String? language) {
    try {
      final parsed = highlight.highlight.parse(
        source,
        language: language,
        autoDetection: language == null,
      );
      return TextSpan(
        style: _baseStyle,
        children: _buildHighlightedNodes(parsed.nodes),
      );
    } catch (_) {
      if (language != null) {
        try {
          final parsed = highlight.highlight.parse(source, autoDetection: true);
          return TextSpan(
            style: _baseStyle,
            children: _buildHighlightedNodes(parsed.nodes),
          );
        } catch (_) {}
      }
      return TextSpan(text: source, style: _baseStyle);
    }
  }

  List<InlineSpan> _buildHighlightedNodes(List<highlight.Node>? nodes) {
    if (nodes == null || nodes.isEmpty) {
      return <InlineSpan>[TextSpan(style: _baseStyle)];
    }
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node.value != null) {
        spans.add(
          TextSpan(text: node.value, style: _styleForClass(node.className)),
        );
        continue;
      }
      spans.add(
        TextSpan(
          style: _styleForClass(node.className),
          children: _buildHighlightedNodes(node.children),
        ),
      );
    }
    return spans;
  }

  TextStyle _styleForClass(String? className) {
    final classes = (className ?? '').split(' ');
    var style = _baseStyle;
    if (classes.any((item) => item == 'comment' || item == 'quote')) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFF7DD3A7) : const Color(0xFF5B7C68),
        fontStyle: FontStyle.italic,
      );
    }
    if (classes.any((item) => item == 'keyword' || item == 'selector-tag')) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFFF9A8D4) : const Color(0xFFB42367),
        fontWeight: FontWeight.w700,
      );
    }
    if (classes.any((item) => item == 'string' || item == 'regexp')) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
      );
    }
    if (classes.any((item) => item == 'number' || item == 'literal')) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
      );
    }
    if (classes.any(
      (item) =>
          item == 'title' ||
          item == 'function' ||
          item == 'title.function_' ||
          item == 'title.class_',
    )) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFF67E8F9) : const Color(0xFF0F766E),
        fontWeight: FontWeight.w700,
      );
    }
    if (classes.any(
      (item) =>
          item == 'type' ||
          item == 'built_in' ||
          item == 'class' ||
          item == 'params',
    )) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFFC4B5FD) : const Color(0xFF6D28D9),
        fontWeight: FontWeight.w600,
      );
    }
    if (classes.any((item) => item == 'meta' || item == 'attr')) {
      return style.copyWith(
        color: _darkSurface ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
      );
    }
    return style;
  }
}

class _TokenDial extends StatefulWidget {
  const _TokenDial({required this.totalTokens});

  final int totalTokens;

  @override
  State<_TokenDial> createState() => _TokenDialState();
}

class _TokenDialState extends State<_TokenDial> {
  late int _previousTokens;

  @override
  void initState() {
    super.initState();
    _previousTokens = widget.totalTokens;
  }

  @override
  void didUpdateWidget(covariant _TokenDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.totalTokens != widget.totalTokens) {
      _previousTokens = oldWidget.totalTokens;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ringColor = colorScheme.outlineVariant.withValues(alpha: 0.75);
    final activeColor = colorScheme.primary;
    final previousTurns = _previousTokens <= 0
        ? 0.0
        : (math.min(_previousTokens, 9999) / 9999);
    final turns = widget.totalTokens <= 0
        ? 0.0
        : (math.min(widget.totalTokens, 9999) / 9999);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 2.6,
                  color: ringColor,
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: previousTurns, end: turns),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return CircularProgressIndicator(
                      value: value,
                      strokeWidth: 2.6,
                      color: activeColor,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: _previousTokens, end: widget.totalTokens),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Text(
                '$value',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSurface,
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          Text(
            _localizedText(context, zh: 'Token', en: 'Token'),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadTemplateDialog extends StatelessWidget {
  const _ThreadTemplateDialog({required this.templates});

  final List<AiThreadTemplate> templates;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.threadTemplateDialogTitle),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.threadTemplateDialogBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: templates
                  .map(
                    (template) => _ThreadTemplateCard(
                      template: template,
                      onTap: () => Navigator.of(context).pop(template.id),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
      ],
    );
  }
}

class _ThreadTemplateCard extends StatelessWidget {
  const _ThreadTemplateCard({required this.template, required this.onTap});

  final AiThreadTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      width: 260,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    template.iconData,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(template.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  template.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'v${template.internalVersion}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
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

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

List<AiSessionMessage> _displayMessages(AiSession session) {
  final visibleMessages = session.visibleMessages;
  final toolCallIds = visibleMessages
      .where((message) => message.kind == AiSessionMessageKind.toolCall)
      .map((message) => '${message.metadata['tool_call_id'] ?? ''}'.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
  return visibleMessages
      .where((message) {
        if (message.kind != AiSessionMessageKind.tool) {
          return true;
        }
        final toolCallId = '${message.metadata['tool_call_id'] ?? ''}'.trim();
        return toolCallId.isEmpty || !toolCallIds.contains(toolCallId);
      })
      .toList(growable: false);
}

String _localizedText(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  final languageCode = Localizations.localeOf(context).languageCode;
  return languageCode.startsWith('zh') ? zh : en;
}

String _localizedMetadataField(BuildContext context, String field) {
  return switch (field) {
    'session_id' => _localizedText(context, zh: '会话 ID', en: 'Session ID'),
    'template' => _localizedText(context, zh: '模板', en: 'Template'),
    'created_at' => _localizedText(context, zh: '创建时间', en: 'Created At'),
    'updated_at' => _localizedText(context, zh: '更新时间', en: 'Updated At'),
    'last_model' => _localizedText(context, zh: '最近模型', en: 'Last Model'),
    'compression_checkpoint' => _localizedText(
      context,
      zh: '压缩检查点',
      en: 'Compression Checkpoint',
    ),
    'latest_compression_at' => _localizedText(
      context,
      zh: '最近压缩时间',
      en: 'Latest Compression At',
    ),
    'total_input_characters' => _localizedText(
      context,
      zh: '输入字符总数',
      en: 'Total Input Characters',
    ),
    'total_output_characters' => _localizedText(
      context,
      zh: '输出字符总数',
      en: 'Total Output Characters',
    ),
    'total_prompt_characters' => _localizedText(
      context,
      zh: 'Prompt 字符总数',
      en: 'Total Prompt Characters',
    ),
    'last_prompt_system_message_count' => _localizedText(
      context,
      zh: '上次 Prompt 系统消息数',
      en: 'Last Prompt System Message Count',
    ),
    'last_prompt_history_message_count' => _localizedText(
      context,
      zh: '上次 Prompt 历史消息数',
      en: 'Last Prompt History Message Count',
    ),
    'locale_tag' => _localizedText(context, zh: '语言区域', en: 'Locale Tag'),
    'platform' => _localizedText(context, zh: '平台', en: 'Platform'),
    'app_version' => _localizedText(context, zh: '应用版本', en: 'App Version'),
    'compression_threshold_chars' => _localizedText(
      context,
      zh: '压缩阈值字符数',
      en: 'Compression Threshold Characters',
    ),
    'application_directory' => _localizedText(
      context,
      zh: '应用目录',
      en: 'Application Directory',
    ),
    'home_directory' => _localizedText(
      context,
      zh: '主目录',
      en: 'Home Directory',
    ),
    'settings_file' => _localizedText(context, zh: '设置文件', en: 'Settings File'),
    'skills_storage' => _localizedText(
      context,
      zh: '技能目录',
      en: 'Skills Storage',
    ),
    'mcp_servers_file' => _localizedText(
      context,
      zh: 'MCP 文件',
      en: 'MCP Servers File',
    ),
    'user_memory_file' => _localizedText(
      context,
      zh: '记忆文件',
      en: 'User Memory File',
    ),
    'sessions_directory' => _localizedText(
      context,
      zh: '会话目录',
      en: 'Sessions Directory',
    ),
    _ => field,
  };
}
