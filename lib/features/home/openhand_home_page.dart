import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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
import '../ai/service/ai_git_snapshot_service.dart';
import '../ai/service/ai_workspace_instruction_service.dart';
import '../memory/memory_controller.dart';
import '../memory/memory_view.dart';
import '../mcp/mcp_controller.dart';
import '../mcp/mcp_view.dart';
import '../settings/settings_view.dart';
import '../skills/skills_controller.dart';
import '../skills/skills_view.dart';
import 'slash_command_parser.dart';
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
const double _autoFollowAnimatedDistanceThreshold = 8;
const int _slowUiFrameThresholdMs = 24;
const int _slowUiLogThrottleMs = 800;

class OpenHandHomePage extends StatefulWidget {
  const OpenHandHomePage({super.key});

  @override
  State<OpenHandHomePage> createState() => _OpenHandHomePageState();
}

class _OpenHandHomePageState extends State<OpenHandHomePage> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();
  final AiWorkspaceInstructionService _workspaceInstructionService =
      AiWorkspaceInstructionService();
  final AiGitSnapshotService _gitSnapshotService = AiGitSnapshotService();

  AppSection _selectedSection = AppSection.workspace;
  double _composerHeight = _composerDefaultHeight;
  bool _composerCollapsed = false;
  bool _autoFollowEnabled = true;
  String? _submittingSessionId;
  bool _shouldAutoFollowMessages = true;
  bool _pendingForcedScrollToBottom = false;
  bool _queuedForcedScrollToBottom = false;
  bool _scrollToBottomCallbackQueued = false;
  bool _pendingAnimatedScrollToBottom = false;
  int _pendingScrollToBottomSettlePasses = 0;
  String? _lastAutoScrollSignature;
  DateTime? _lastSlowUiLogAt;

  AiSendPhase _displaySendPhaseForSession(
    AiSessionController sessionController,
    String? sessionId,
  ) {
    if (sessionId == null) {
      return AiSendPhase.idle;
    }
    final controllerPhase = sessionController.sendPhaseForSession(sessionId);
    if (controllerPhase != AiSendPhase.idle) {
      return controllerPhase;
    }
    return _submittingSessionId == sessionId
        ? AiSendPhase.sendingMessage
        : AiSendPhase.idle;
  }

  AiSendPhase _effectiveSendPhase(AiSessionController sessionController) {
    return _displaySendPhaseForSession(
      sessionController,
      sessionController.currentSessionId,
    );
  }

  Map<String, AiSendPhase> _navigationSendPhases(
    AiSessionController sessionController,
  ) {
    return <String, AiSendPhase>{
      for (final session in sessionController.sessions)
        session.id: _displaySendPhaseForSession(sessionController, session.id),
    };
  }

  @override
  void initState() {
    super.initState();
    _messageScrollController.addListener(_handleMessageScroll);
    SchedulerBinding.instance.addTimingsCallback(_handleFrameTimings);
  }

  @override
  void dispose() {
    _messageScrollController.removeListener(_handleMessageScroll);
    SchedulerBinding.instance.removeTimingsCallback(_handleFrameTimings);
    _composerController.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  void _handleFrameTimings(List<FrameTiming> timings) {
    if (!kDebugMode || !mounted || timings.isEmpty) {
      return;
    }
    final sessionController = context.read<AiSessionController>();
    final sessionId = sessionController.currentSessionId;
    if (sessionId == null ||
        _displaySendPhaseForSession(sessionController, sessionId) !=
            AiSendPhase.responding) {
      return;
    }
    final now = DateTime.now().toUtc();
    final lastLoggedAt = _lastSlowUiLogAt;
    if (lastLoggedAt != null &&
        now.difference(lastLoggedAt).inMilliseconds < _slowUiLogThrottleMs) {
      return;
    }
    for (final timing in timings) {
      final buildMs = timing.buildDuration.inMilliseconds;
      final rasterMs = timing.rasterDuration.inMilliseconds;
      if (buildMs < _slowUiFrameThresholdMs &&
          rasterMs < _slowUiFrameThresholdMs) {
        continue;
      }
      _lastSlowUiLogAt = now;
      final currentSession = _sessionForId(sessionController, sessionId);
      final messageCount = currentSession == null
          ? 0
          : _displayMessages(currentSession).length;
      final activePosition = _activeMessageScrollPosition();
      final distanceToBottom = activePosition == null
          ? 0
          : (activePosition.maxScrollExtent - activePosition.pixels).round();
      debugPrint(
        '[OpenHand][UI][$sessionId] slow_frame build_ms=$buildMs raster_ms=$rasterMs total_ms=${timing.totalSpan.inMilliseconds} messages=$messageCount auto_follow=$_shouldAutoFollowMessages enabled=$_autoFollowEnabled scroll_distance=$distanceToBottom queued=$_scrollToBottomCallbackQueued settle=$_pendingScrollToBottomSettlePasses',
      );
      break;
    }
  }

  void _clearPendingAutoFollowState() {
    _pendingForcedScrollToBottom = false;
    _queuedForcedScrollToBottom = false;
    _pendingAnimatedScrollToBottom = false;
    _pendingScrollToBottomSettlePasses = 0;
  }

  void _armAutoFollowToBottom() {
    _shouldAutoFollowMessages = true;
    _pendingForcedScrollToBottom = true;
  }

  bool _consumePendingAutoFollowRequest() {
    final shouldForce = _pendingForcedScrollToBottom;
    _pendingForcedScrollToBottom = false;
    return shouldForce;
  }

  bool _shouldScheduleAutoFollow({bool consumePendingRequest = false}) {
    final shouldForce = consumePendingRequest
        ? _consumePendingAutoFollowRequest()
        : _pendingForcedScrollToBottom;
    if (!_autoFollowEnabled && !shouldForce) {
      return false;
    }
    if (!_shouldAutoFollowMessages && !shouldForce) {
      return false;
    }
    return true;
  }

  void _scheduleAutoFollowIfNeeded({
    bool consumePendingRequest = false,
    bool animated = true,
  }) {
    if (!_shouldScheduleAutoFollow(
      consumePendingRequest: consumePendingRequest,
    )) {
      return;
    }
    _scheduleScrollToBottom(force: true, animated: animated);
  }

  void _handleMessageScroll() {
    final nextValue = _isNearBottom();
    if (!nextValue) {
      return;
    }
    if (!_shouldAutoFollowMessages) {
      _shouldAutoFollowMessages = true;
    }
    if (_pendingForcedScrollToBottom) {
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
    final userScrolledAwayFromBottom =
        !isNearBottom &&
        ((notification is ScrollStartNotification &&
                notification.dragDetails != null) ||
            (notification is ScrollUpdateNotification &&
                notification.dragDetails != null) ||
            (notification is OverscrollNotification &&
                notification.dragDetails != null) ||
            (notification is UserScrollNotification &&
                notification.direction != ScrollDirection.idle));
    if (userScrolledAwayFromBottom) {
      _shouldAutoFollowMessages = false;
      _clearPendingAutoFollowState();
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
        _clearPendingAutoFollowState();
      } else {
        _armAutoFollowToBottom();
      }
    });
    if (nextValue) {
      _scheduleScrollToBottom(force: true, animated: true);
    }
  }

  Future<String?> _showThreadTemplateDialog() async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final sessionController = dialogContext.read<AiSessionController>();
        return _ThreadTemplateDialog(templates: sessionController.templates);
      },
    );
  }

  Future<bool> _createSession({
    required String templateId,
    AiSessionRuntimeContext? runtimeContext,
  }) async {
    final sessionController = context.read<AiSessionController>();
    final resolvedRuntimeContext =
        runtimeContext ?? await _buildRuntimeContext();
    if (!mounted) {
      return false;
    }
    final created = await sessionController.createSession(
      templateId: templateId,
      runtimeContext: resolvedRuntimeContext,
    );
    if (!mounted) {
      return false;
    }
    if (!created) {
      final l10n = AppLocalizations.of(context)!;
      final errorMessage = sessionController.lastErrorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage ?? l10n.chatRequestFailed)),
      );
      return false;
    }
    setState(() {
      _selectedSection = AppSection.workspace;
      _armAutoFollowToBottom();
    });
    return true;
  }

  Future<bool> _createSessionFromDialog({
    AiSessionRuntimeContext? runtimeContext,
  }) async {
    final templateId = await _showThreadTemplateDialog();
    if (!mounted || templateId == null) {
      return false;
    }
    return _createSession(
      templateId: templateId,
      runtimeContext: runtimeContext,
    );
  }

  Future<AiSessionRuntimeContext> _buildRuntimeContext() async {
    final settingsController = context.read<SettingsController>();
    final memoryController = context.read<MemoryController>();
    final skillsController = context.read<SkillsController>();
    final mcpController = context.read<McpController>();
    final appInfo = context.read<AppInfo>();
    final workingDirectory = OpenHandPaths.applicationDirectoryPath();
    final gitSnapshot = await _gitSnapshotService.loadSnapshot(
      workingDirectory: workingDirectory,
    );
    final now = DateTime.now().toLocal();
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
      singleRoundToolCallLimit: settingsController.aiSingleRoundToolCallLimit,
      memoryEnabled: settingsController.memoryEnabled,
      writeCommandConfirmationEnabled:
          settingsController.aiWriteCommandConfirmationEnabled,
      platformName: Platform.operatingSystem,
      workingDirectory: workingDirectory,
      todayLocalDate:
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      timeZoneName: now.timeZoneName,
      repositorySnapshot: gitSnapshot,
      memoryEntries: settingsController.memoryEnabled
          ? memoryController.entries
          : const [],
      allowCommandRules: settingsController.aiAllowCommandRules,
      availableSkills: skillsController.skills,
      availableMcpServers: mcpController.servers,
      workspaceInstructionDocuments: _workspaceInstructionService.loadDocuments(
        startDirectory: OpenHandPaths.applicationDirectoryPath(),
        homeDirectory: OpenHandPaths.homeDirectoryPath(),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final l10n = AppLocalizations.of(context)!;
    final prompt = _composerController.text.trim();
    if (prompt.isEmpty) {
      return;
    }
    final slashCommand = parseOpenHandSlashCommand(prompt);
    if (slashCommand != null) {
      _replaceComposerText('');
      await _handleSlashCommand(slashCommand);
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
    AiSessionRuntimeContext? runtimeContext;
    if (sessionController.currentSession == null) {
      final templateId = await _showThreadTemplateDialog();
      if (!mounted || templateId == null) {
        return;
      }
      runtimeContext = await _buildRuntimeContext();
      if (!mounted) {
        return;
      }
      final created = await _createSession(
        templateId: templateId,
        runtimeContext: runtimeContext,
      );
      if (!mounted || !created || sessionController.currentSession == null) {
        return;
      }
    }
    final initialSession = sessionController.currentSession;
    final targetSessionId = sessionController.currentSessionId;
    if (targetSessionId == null || _submittingSessionId == targetSessionId) {
      return;
    }
    final initialUserMessageCount = _visibleUserMessageCount(initialSession);
    final editingMessageIdBeforeSend = sessionController.editingMessageId;

    _replaceComposerText('');
    setState(() {
      _submittingSessionId = targetSessionId;
      _armAutoFollowToBottom();
    });
    try {
      runtimeContext ??= await _buildRuntimeContext();
      if (!mounted) {
        return;
      }
      final sent = await sessionController.sendMessage(
        sessionId: targetSessionId,
        content: prompt,
        model: selectedModel,
        runtimeContext: runtimeContext,
        denyCommandRules: settingsController.aiDenyCommandRules,
        requireWriteCommandConfirmation:
            settingsController.aiWriteCommandConfirmationEnabled,
        confirmWriteCommand: _confirmWriteCommand,
      );
      if (!mounted) {
        return;
      }
      if (!sent) {
        if (_shouldRestoreSubmittedPrompt(
          sessionController: sessionController,
          sessionId: targetSessionId,
          prompt: prompt,
          initialUserMessageCount: initialUserMessageCount,
          editingMessageId: editingMessageIdBeforeSend,
        )) {
          _replaceComposerText(prompt);
        }
        final errorMessage = sessionController.lastErrorMessageForSession(
          targetSessionId,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage ?? l10n.chatRequestFailed)),
        );
        return;
      }
      await sessionController.completeEditingMessage();
      if (!mounted) {
        return;
      }
      if (sessionController.didCompressInLastSendForSession(targetSessionId)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.threadCompressionNotice)));
      }
      _scheduleScrollToBottom(force: true, animated: true);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'openhand_home_page',
          context: ErrorDescription('while sending a chat message'),
        ),
      );
      if (mounted &&
          _shouldRestoreSubmittedPrompt(
            sessionController: sessionController,
            sessionId: targetSessionId,
            prompt: prompt,
            initialUserMessageCount: initialUserMessageCount,
            editingMessageId: editingMessageIdBeforeSend,
          )) {
        _replaceComposerText(prompt);
      }
      if (mounted) {
        final errorMessage = '$error'.trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage.isEmpty ? l10n.chatRequestFailed : errorMessage,
            ),
          ),
        );
      }
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

  void _replaceComposerText(String value) {
    _composerController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
  }

  int _visibleUserMessageCount(AiSession? session) {
    if (session == null) {
      return 0;
    }
    return session.messages
        .where(
          (message) =>
              !message.isDeleted && message.kind == AiSessionMessageKind.user,
        )
        .length;
  }

  AiSession? _sessionForId(
    AiSessionController sessionController,
    String sessionId,
  ) {
    for (final session in sessionController.sessions) {
      if (session.id == sessionId) {
        return session;
      }
    }
    return null;
  }

  bool _shouldRestoreSubmittedPrompt({
    required AiSessionController sessionController,
    required String sessionId,
    required String prompt,
    required int initialUserMessageCount,
    required String? editingMessageId,
  }) {
    if (_composerController.text.trim().isNotEmpty) {
      return false;
    }
    final targetSession = _sessionForId(sessionController, sessionId);
    if (targetSession == null) {
      return false;
    }
    if (_visibleUserMessageCount(targetSession) > initialUserMessageCount) {
      return false;
    }
    if (editingMessageId != null) {
      for (final message in targetSession.messages) {
        if (message.id == editingMessageId &&
            !message.isDeleted &&
            message.content.trim() == prompt) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _stopResponding() async {
    final sessionController = context.read<AiSessionController>();
    final sessionId = sessionController.currentSessionId;
    if (sessionId == null) {
      return;
    }
    await sessionController.stopResponding(sessionId);
  }

  void _scheduleScrollToBottom({
    bool force = false,
    bool animated = false,
    bool allowSettlePasses = true,
  }) {
    if (!force && !_shouldAutoFollowMessages) {
      return;
    }
    if (force) {
      _shouldAutoFollowMessages = true;
      _queuedForcedScrollToBottom = true;
    }
    _pendingAnimatedScrollToBottom = _pendingAnimatedScrollToBottom || animated;
    if (allowSettlePasses) {
      _pendingScrollToBottomSettlePasses = math.max(
        _pendingScrollToBottomSettlePasses,
        animated ? 4 : 3,
      );
    }
    if (_scrollToBottomCallbackQueued) {
      return;
    }
    _scrollToBottomCallbackQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomCallbackQueued = false;
      if (!mounted) {
        _queuedForcedScrollToBottom = false;
        _pendingAnimatedScrollToBottom = false;
        _pendingScrollToBottomSettlePasses = 0;
        return;
      }
      final shouldForce = _queuedForcedScrollToBottom;
      final shouldAnimate = _pendingAnimatedScrollToBottom;
      _queuedForcedScrollToBottom = false;
      _pendingAnimatedScrollToBottom = false;
      if (!shouldForce && (!_autoFollowEnabled || !_shouldAutoFollowMessages)) {
        _pendingScrollToBottomSettlePasses = 0;
        return;
      }
      final activePosition = _activeMessageScrollPosition();
      if (activePosition == null) {
        _pendingScrollToBottomSettlePasses = 0;
        return;
      }
      final targetOffset = activePosition.maxScrollExtent
          .clamp(activePosition.minScrollExtent, activePosition.maxScrollExtent)
          .toDouble();
      final distance = (targetOffset - activePosition.pixels).abs();
      if (distance >= 1 &&
          shouldAnimate &&
          distance > _autoFollowAnimatedDistanceThreshold) {
        _messageScrollController.animateTo(
          targetOffset,
          duration: _scrollToBottomAnimationDuration(distance),
          curve: Curves.easeOutCubic,
        );
      } else if (distance >= 1) {
        _messageScrollController.jumpTo(targetOffset);
      }
      if (_pendingScrollToBottomSettlePasses <= 0) {
        return;
      }
      _pendingScrollToBottomSettlePasses -= 1;
      _scheduleScrollToBottom(force: false, allowSettlePasses: false);
    });
  }

  Duration _scrollToBottomAnimationDuration(double distance) {
    final clampedDistance = distance.clamp(24, 520).toDouble();
    final milliseconds = (110 + clampedDistance * 0.24).round().clamp(110, 280);
    return Duration(milliseconds: milliseconds);
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
    _scheduleAutoFollowIfNeeded(consumePendingRequest: true);
  }

  void _handleComposerLayoutChanged() {
    _scheduleAutoFollowIfNeeded();
  }

  void _handleTranscriptLayoutChanged() {
    _scheduleAutoFollowIfNeeded();
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
    final settingsController = context.read<SettingsController>();
    for (final rule in settingsController.aiAllowCommandRules) {
      if (rule.matches(request.command)) {
        return true;
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          _WriteCommandConfirmationDialog(request: request),
    );
    return confirmed == true;
  }

  Future<void> _handleSlashCommand(OpenHandSlashCommand command) async {
    switch (command.kind) {
      case OpenHandSlashCommandKind.help:
        setState(() {
          _selectedSection = AppSection.settings;
        });
        await _showSlashHelpDialog();
        return;
      case OpenHandSlashCommandKind.feedback:
        setState(() {
          _selectedSection = AppSection.settings;
        });
        await _showFeedbackDialog(command.argument);
        return;
      case OpenHandSlashCommandKind.newSession:
        await _createSessionFromDialog();
        return;
      case OpenHandSlashCommandKind.status:
        final session = context.read<AiSessionController>().currentSession;
        if (session == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _localizedText(
                  context,
                  zh: '当前没有活动会话。',
                  en: 'There is no active session.',
                ),
              ),
            ),
          );
          return;
        }
        await _showSessionMetadataDialog(context, session);
        return;
      case OpenHandSlashCommandKind.stop:
        final sessionController = context.read<AiSessionController>();
        final currentSessionId = sessionController.currentSessionId;
        final hasActiveResponse =
            currentSessionId != null &&
            sessionController.sendPhaseForSession(currentSessionId) !=
                AiSendPhase.idle;
        if (!hasActiveResponse) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _localizedText(
                  context,
                  zh: '当前没有正在进行的响应。',
                  en: 'There is no active response to stop.',
                ),
              ),
            ),
          );
          return;
        }
        await _stopResponding();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _localizedText(
                  context,
                  zh: '已请求当前会话停止继续响应。',
                  en: 'Requested the current session to stop responding.',
                ),
              ),
            ),
          );
        }
        return;
      case OpenHandSlashCommandKind.settings:
        _activateSlashCommandSection(AppSection.settings);
        return;
      case OpenHandSlashCommandKind.workspace:
        _activateSlashCommandSection(AppSection.workspace);
        return;
      case OpenHandSlashCommandKind.automations:
        _activateSlashCommandSection(AppSection.automations);
        return;
      case OpenHandSlashCommandKind.skills:
        _activateSlashCommandSection(AppSection.skills);
        return;
      case OpenHandSlashCommandKind.memory:
        _activateSlashCommandSection(AppSection.memory);
        return;
      case OpenHandSlashCommandKind.mcp:
        _activateSlashCommandSection(AppSection.mcp);
        return;
    }
  }

  void _activateSlashCommandSection(AppSection section) {
    setState(() {
      _selectedSection = section;
    });
    final label = switch (section) {
      AppSection.workspace => _localizedText(
        context,
        zh: '工作区',
        en: 'Workspace',
      ),
      AppSection.automations => _localizedText(
        context,
        zh: '自动化',
        en: 'Automations',
      ),
      AppSection.skills => _localizedText(context, zh: '技能', en: 'Skills'),
      AppSection.memory => _localizedText(context, zh: '记忆', en: 'Memory'),
      AppSection.mcp => _localizedText(context, zh: 'MCP', en: 'MCP'),
      AppSection.settings => _localizedText(context, zh: '设置', en: 'Settings'),
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localizedText(
            context,
            zh: '已切换到 $label。',
            en: 'Switched to $label.',
          ),
        ),
      ),
    );
  }

  Future<void> _showSlashHelpDialog() {
    final settingsController = context.read<SettingsController>();
    final sessionController = context.read<AiSessionController>();
    final closeLabel = _localizedText(context, zh: '关闭', en: 'Close');
    final allowRulePreview = settingsController.aiAllowCommandRules
        .take(4)
        .map((item) => '- ${item.pattern}')
        .join('\n');
    final commandList = <String>[
      '/help',
      '/commands',
      '/feedback [note]',
      '/new',
      '/status',
      '/stop',
      '/settings',
      '/config',
      '/workspace',
      '/sessions',
      '/chat',
      '/automations',
      '/skills',
      '/memory',
      '/mcp',
    ].join('\n');
    final detail = _localizedText(
      context,
      zh: '可用本地命令：\n$commandList\n\n`/help`、`/commands`、`/feedback`、`/new`、`/status`、`/stop` 不会发给模型，而是由 OpenHand 本地处理。\n\n写命令确认：${settingsController.aiWriteCommandConfirmationEnabled ? '开启' : '关闭'}\n允许命令规则：${settingsController.aiAllowCommandRules.length}${allowRulePreview.isEmpty ? '' : '\n$allowRulePreview'}\n\n设置文件：${settingsController.displaySettingsFilePath}\n会话目录：${OpenHandPaths.shortenHomePath(sessionController.sessionsDirectoryPath)}',
      en: 'Available local commands:\n$commandList\n\n`/help`, `/commands`, `/feedback`, `/new`, `/status`, and `/stop` are handled locally by OpenHand instead of being sent to the model.\n\nWrite command confirmation: ${settingsController.aiWriteCommandConfirmationEnabled ? 'enabled' : 'disabled'}\nAllow command rules: ${settingsController.aiAllowCommandRules.length}${allowRulePreview.isEmpty ? '' : '\n$allowRulePreview'}\n\nSettings file: ${settingsController.displaySettingsFilePath}\nSession directory: ${OpenHandPaths.shortenHomePath(sessionController.sessionsDirectoryPath)}',
    );
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _localizedText(context, zh: 'Slash Commands', en: 'Slash Commands'),
          ),
          content: SelectableText(detail),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: closeLabel,
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFeedbackDialog(String note) {
    final settingsController = context.read<SettingsController>();
    final sessionController = context.read<AiSessionController>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final closeLabel = _localizedText(context, zh: '关闭', en: 'Close');
    final copiedLabel = _localizedText(
      context,
      zh: '反馈模板已复制。',
      en: 'Feedback template copied.',
    );
    final trimmedNote = note.trim();
    final feedbackTemplate = _localizedText(
      context,
      zh: 'OpenHand 反馈\n备注：${trimmedNote.isEmpty ? '请在这里补充问题描述。' : trimmedNote}\n设置文件：${settingsController.settingsFilePath}\n会话目录：${sessionController.sessionsDirectoryPath}',
      en: 'OpenHand Feedback\nNote: ${trimmedNote.isEmpty ? 'Add your issue details here.' : trimmedNote}\nSettings file: ${settingsController.settingsFilePath}\nSession directory: ${sessionController.sessionsDirectoryPath}',
    );
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_localizedText(context, zh: '反馈信息', en: 'Feedback Info')),
          content: SelectableText(
            _localizedText(
              context,
              zh: '该命令不会发送给模型。你可以把下面这段信息复制出去提交反馈：\n\n$feedbackTemplate',
              en: 'This command is handled locally and is not sent to the model. You can copy the following report template for feedback:\n\n$feedbackTemplate',
            ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: closeLabel,
            ),
            OpenHandDialogActionButton.primary(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: feedbackTemplate));
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text(copiedLabel)),
                );
              },
              label: _localizedText(context, zh: '复制模板', en: 'Copy Template'),
            ),
          ],
        );
      },
    );
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
    _replaceComposerText(content);
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
              final sessionSendPhases = _navigationSendPhases(
                sessionController,
              );
              final navigationPane = _NavigationPane(
                selectedSection: _selectedSection,
                sessions: sessionController.sessions,
                sessionSendPhases: sessionSendPhases,
                currentSessionId: sessionController.currentSessionId,
                onCreateThreadRequested: _createSessionFromDialog,
                onSessionSelected: (sessionId) async {
                  await sessionController.selectSession(sessionId);
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _selectedSection = AppSection.workspace;
                    _armAutoFollowToBottom();
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
        onComposerLayoutChanged: _handleComposerLayoutChanged,
        onTranscriptLayoutChanged: _handleTranscriptLayoutChanged,
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
    required this.sessionSendPhases,
    required this.currentSessionId,
    required this.onCreateThreadRequested,
    required this.onSessionSelected,
    required this.onRenameSession,
    required this.onDeleteSession,
    required this.onSectionSelected,
  });

  final AppSection selectedSection;
  final List<AiSession> sessions;
  final Map<String, AiSendPhase> sessionSendPhases;
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
                          sendPhase:
                              sessionSendPhases[session.id] ?? AiSendPhase.idle,
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
    required this.onComposerLayoutChanged,
    required this.onTranscriptLayoutChanged,
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
  final VoidCallback onComposerLayoutChanged;
  final VoidCallback onTranscriptLayoutChanged;
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
                      onLayoutChanged: onTranscriptLayoutChanged,
                      onEditMessage: onEditMessage,
                      onCopyMessage: onCopyMessage,
                    ),
            ),
            const SizedBox(height: 16),
            NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (notification) {
                onComposerLayoutChanged();
                return false;
              },
              child: SizeChangedLayoutNotifier(
                child: _ComposerPanel(
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
              ),
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
    required this.onLayoutChanged,
    required this.onEditMessage,
    required this.onCopyMessage,
  });

  final ScrollController controller;
  final bool Function(ScrollNotification notification) onScrollNotification;
  final AiSession session;
  final AiSendPhase sendPhase;
  final VoidCallback onLayoutChanged;
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
    final session = widget.session;
    final displayMessagesStopwatch = Stopwatch()..start();
    final displayMessages = _displayMessages(session);
    displayMessagesStopwatch.stop();
    if (kDebugMode && displayMessagesStopwatch.elapsedMilliseconds >= 8) {
      final lastMessage = displayMessages.isEmpty ? null : displayMessages.last;
      debugPrint(
        '[OpenHand][UI][${session.id}] transcript_messages_slow elapsed_ms=${displayMessagesStopwatch.elapsedMilliseconds} total_messages=${session.messages.length} display_messages=${displayMessages.length} last_kind=${lastMessage?.kind.storageValue ?? 'none'}',
      );
    }
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
              key: const ValueKey<String>('session-transcript-list'),
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
                  onLayoutChanged: widget.onLayoutChanged,
                  isSelected: _selectedMessageId == message.id,
                  onSelect: () {
                    setState(() {
                      _selectedMessageId = message.id;
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
          _SessionErrorBanner(error: userVisibleError),
        ],
      ],
    );
  }
}

class _SessionErrorBanner extends StatelessWidget {
  const _SessionErrorBanner({required this.error});

  final AiSessionErrorRecord error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presentation = _presentSessionError(context, error);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presentation.title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  presentation.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

int _metadataInt(Object? rawValue) {
  if (rawValue is int) {
    return rawValue;
  }
  return int.tryParse('${rawValue ?? ''}'.trim()) ?? 0;
}

List<Map<String, Object?>> _metadataObjectList(Object? rawValue) {
  if (rawValue is! List) {
    return const <Map<String, Object?>>[];
  }
  return rawValue
      .whereType<Map>()
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);
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
    final lastPromptMetadata = session.lastPromptMetadata;
    final hasPromptMetadata = lastPromptMetadata.isNotEmpty;
    final writeCommandConfirmationEnabled =
        lastPromptMetadata['write_command_confirmation_enabled'] == true;
    final allowCommandRuleCount = _metadataInt(
      lastPromptMetadata['allow_command_rule_count'],
    );
    final allowCommandRules = _metadataObjectList(
      lastPromptMetadata['allow_command_rules'],
    );
    final todoWriteRecommended =
        lastPromptMetadata['todo_write_recommended'] == true;
    final todoWriteReason = '${lastPromptMetadata['todo_write_reason'] ?? ''}'
        .trim();
    final currentTodos = session.todoItems
        .map((item) => item.toJson())
        .toList(growable: false);
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
                          zh: '命令策略',
                          en: 'Command Policy',
                        ),
                        children: !hasPromptMetadata
                            ? [
                                Text(
                                  _localizedText(
                                    context,
                                    zh: '当前还没有可展示的 prompt 元数据。',
                                    en: 'Prompt metadata is not available yet.',
                                  ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ]
                            : [
                                _MetadataEntryRow(
                                  label: _localizedText(
                                    context,
                                    zh: '写命令确认',
                                    en: 'Write Confirmation',
                                  ),
                                  value: writeCommandConfirmationEnabled
                                      ? _localizedText(
                                          context,
                                          zh: '需要确认',
                                          en: 'Required',
                                        )
                                      : _localizedText(
                                          context,
                                          zh: '无需确认',
                                          en: 'Not required',
                                        ),
                                ),
                                _MetadataEntryRow(
                                  label: _localizedText(
                                    context,
                                    zh: '允许规则数',
                                    en: 'Allow Rules',
                                  ),
                                  value: '$allowCommandRuleCount',
                                ),
                                if (allowCommandRules.isEmpty)
                                  Text(
                                    _localizedText(
                                      context,
                                      zh: '当前没有已上屏的允许命令规则。',
                                      en: 'There are no surfaced allow command rules.',
                                    ),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: allowCommandRules
                                        .map((rule) {
                                          final pattern =
                                              '${rule['pattern'] ?? ''}'.trim();
                                          final matchMode =
                                              '${rule['match_mode'] ?? ''}'
                                                  .trim();
                                          if (pattern.isEmpty) {
                                            return null;
                                          }
                                          final prefix = matchMode.isEmpty
                                              ? ''
                                              : '$matchMode: ';
                                          return _MetadataChip(
                                            label: '$prefix$pattern',
                                          );
                                        })
                                        .whereType<Widget>()
                                        .toList(growable: false),
                                  ),
                              ],
                      ),
                      const SizedBox(height: 16),
                      _MetadataSection(
                        title: _localizedText(
                          context,
                          zh: '任务跟踪',
                          en: 'Task Tracking',
                        ),
                        children: [
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: '当前 Todo 数量',
                              en: 'Current Todos',
                            ),
                            value: '${currentTodos.length}',
                          ),
                          _MetadataEntryRow(
                            label: _localizedText(
                              context,
                              zh: 'TodoWrite 强提醒',
                              en: 'TodoWrite Reminder',
                            ),
                            value: hasPromptMetadata
                                ? (todoWriteRecommended
                                      ? _localizedText(
                                          context,
                                          zh: '已触发',
                                          en: 'Triggered',
                                        )
                                      : _localizedText(
                                          context,
                                          zh: '未触发',
                                          en: 'Not triggered',
                                        ))
                                : _localizedText(
                                    context,
                                    zh: '暂无数据',
                                    en: 'Unavailable',
                                  ),
                          ),
                          if (todoWriteReason.isNotEmpty)
                            _MetadataEntryRow(
                              label: _localizedText(
                                context,
                                zh: '提醒原因',
                                en: 'Reminder Reason',
                              ),
                              value: todoWriteReason,
                            ),
                          if (currentTodos.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: currentTodos
                                  .map((todo) {
                                    final id = '${todo['id'] ?? ''}'.trim();
                                    final content = '${todo['content'] ?? ''}'
                                        .trim();
                                    final status = '${todo['status'] ?? ''}'
                                        .trim();
                                    if (content.isEmpty) {
                                      return null;
                                    }
                                    final prefix = status.isEmpty
                                        ? ''
                                        : '[$status] ';
                                    final idPrefix = id.isEmpty ? '' : '$id: ';
                                    return _MetadataChip(
                                      label: '$prefix$idPrefix$content',
                                    );
                                  })
                                  .whereType<Widget>()
                                  .toList(growable: false),
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
    final presentation = _presentSessionError(context, error);
    final detail = (error.detail ?? '').trim();
    final rawMessage = error.message.trim();
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
            presentation.title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onErrorContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            presentation.message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onErrorContainer,
              height: 1.4,
            ),
          ),
          if (detail.isNotEmpty && detail != rawMessage) ...[
            const SizedBox(height: 8),
            Text(
              _localizedText(context, zh: '错误细节', en: 'Error Detail'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onErrorContainer.withValues(alpha: 0.9),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${_sessionErrorStageLabel(context, error.stage)} · ${_formatDateTime(error.createdAt)} · ${error.hasBeenPresented ? _localizedText(context, zh: '已展示', en: 'Presented') : _localizedText(context, zh: '未展示', en: 'Pending')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onErrorContainer.withValues(alpha: 0.84),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionErrorPresentation {
  const _SessionErrorPresentation({required this.title, required this.message});

  final String title;
  final String message;
}

_SessionErrorPresentation _presentSessionError(
  BuildContext context,
  AiSessionErrorRecord error,
) {
  final fallbackTitle = _sessionErrorStageLabel(context, error.stage);
  final rawMessage = error.message.trim();
  final fallbackMessage = rawMessage.isNotEmpty
      ? rawMessage
      : _localizedText(
          context,
          zh: '当前会话已提前结束。请重试或继续发送更具体的指令。',
          en: 'This session ended early. Retry the request or continue with a more specific instruction.',
        );
  return switch (error.stage) {
    'tool_loop' => _SessionErrorPresentation(
      title: _localizedText(
        context,
        zh: '工具调用已安全停止',
        en: 'Tool Calls Stopped for Safety',
      ),
      message: _localizedText(
        context,
        zh: '本次会话连续触发了过多轮工具调用，OpenHand 已为安全起见提前停止。你可以继续让助手先总结当前进展，或给出更具体的下一步指令。',
        en: 'OpenHand stopped this session for safety after too many sequential tool rounds. Ask the assistant to summarize the current progress or give a more specific next step.',
      ),
    ),
    'chat_stream' => _SessionErrorPresentation(
      title: _localizedText(context, zh: '回答已中断', en: 'Response Interrupted'),
      message: _localizedText(
        context,
        zh: '本次回答在流式接收过程中异常中断，当前会话已停止。你可以直接重试，或继续发送下一条消息。',
        en: 'The response was interrupted while streaming and this session has stopped. Retry the request or continue with a new message.',
      ),
    ),
    'chat_request' => _SessionErrorPresentation(
      title: _localizedText(context, zh: '请求发送失败', en: 'Request Failed'),
      message: _localizedText(
        context,
        zh: '本次请求在发送阶段失败，当前会话未继续执行。你可以检查配置后重试，或继续发送新的消息。',
        en: 'The request failed before the assistant could continue. Check the configuration and retry, or send a new message.',
      ),
    ),
    _ => _SessionErrorPresentation(
      title: fallbackTitle,
      message: fallbackMessage,
    ),
  };
}

String _sessionErrorStageLabel(BuildContext context, String stage) {
  return switch (stage) {
    'tool_loop' => _localizedText(context, zh: '安全停止', en: 'Safety Stop'),
    'chat_stream' => _localizedText(context, zh: '响应中断', en: 'Stream Error'),
    'chat_request' => _localizedText(context, zh: '请求失败', en: 'Request Error'),
    'tool_execution' => _localizedText(
      context,
      zh: '工具执行失败',
      en: 'Tool Execution Error',
    ),
    'history_compression' => _localizedText(
      context,
      zh: '历史压缩失败',
      en: 'Compression Error',
    ),
    'user_prompt_hook' => _localizedText(
      context,
      zh: '提示词被拦截',
      en: 'Prompt Blocked',
    ),
    'title_generation' => _localizedText(
      context,
      zh: '标题生成失败',
      en: 'Title Generation Error',
    ),
    _ => _localizedText(context, zh: '会话异常', en: 'Session Error'),
  };
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
    required this.onLayoutChanged,
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
  final VoidCallback onLayoutChanged;
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
  bool? _reasoningExpandedOverride;

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _compressionExpanded = false;
      _reasoningExpandedOverride = null;
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
    final isStreamingReasoning = _isStreamingReasoningMessage(message);
    final isToolCall = message.kind == AiSessionMessageKind.toolCall;
    final isToolResult =
        message.kind == AiSessionMessageKind.tool ||
        message.kind == AiSessionMessageKind.mcp ||
        message.kind == AiSessionMessageKind.skill;
    final isStatus = message.kind == AiSessionMessageKind.status;
    final reasoningExpanded =
        _reasoningExpandedOverride ?? _shouldDefaultExpandReasoning(message);

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

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onSelect(),
      child: TapRegion(
        enabled: widget.isSelected,
        onTapOutside: (_) => widget.onDeselect(),
        child: Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (notification) {
                widget.onLayoutChanged();
                return false;
              },
              child: SizeChangedLayoutNotifier(
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
                            ? Border.all(
                                color: colorScheme.secondary,
                                width: 1.2,
                              )
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
                                expanded: reasoningExpanded,
                                onTap: () {
                                  final nextExpanded = !reasoningExpanded;
                                  setState(() {
                                    _reasoningExpandedOverride = nextExpanded;
                                  });
                                },
                              )
                            else if (isToolCall)
                              _ToolCallMetaRow(
                                message: message,
                                color: textColor,
                              )
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
                                    _compressionExpanded =
                                        !_compressionExpanded;
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
                                expanded: reasoningExpanded,
                                streaming: isStreamingReasoning,
                                textColor: textColor,
                                fadeColor: backgroundColor,
                                styleSheet: markdownStyleSheet,
                                builders: markdownBuilders,
                                inlineSyntaxes: inlineSyntaxes,
                                parseKey: filePathParseKey,
                              )
                            else if (isToolCall)
                              _ToolCallBody(message: message)
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
                              label: _localizedText(
                                context,
                                zh: '复制',
                                en: 'Copy',
                              ),
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
    required this.streaming,
    required this.textColor,
    required this.fadeColor,
    required this.styleSheet,
    required this.builders,
    required this.inlineSyntaxes,
    required this.parseKey,
  });

  final String content;
  final bool expanded;
  final bool streaming;
  final Color textColor;
  final Color fadeColor;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final List<md.InlineSyntax> inlineSyntaxes;
  final String parseKey;

  @override
  Widget build(BuildContext context) {
    if (streaming) {
      return _StreamingReasoningBody(
        content: content,
        expanded: expanded,
        textStyle: styleSheet.p?.copyWith(color: textColor),
        fadeColor: fadeColor,
      );
    }
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

class _StreamingReasoningBody extends StatelessWidget {
  const _StreamingReasoningBody({
    required this.content,
    required this.expanded,
    required this.textStyle,
    required this.fadeColor,
  });

  final String content;
  final bool expanded;
  final TextStyle? textStyle;
  final Color fadeColor;

  @override
  Widget build(BuildContext context) {
    final effectiveContent = content.isEmpty ? ' ' : content;
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: expanded
            ? SelectableText(effectiveContent, style: textStyle)
            : Stack(
                children: [
                  Text(
                    effectiveContent,
                    maxLines: 6,
                    overflow: TextOverflow.fade,
                    softWrap: true,
                    style: textStyle,
                  ),
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
                              fadeColor.withValues(alpha: 0),
                              fadeColor.withValues(alpha: 0.96),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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

class _ToolCallBody extends StatefulWidget {
  const _ToolCallBody({required this.message});

  final AiSessionMessage message;

  @override
  State<_ToolCallBody> createState() => _ToolCallBodyState();
}

class _ToolCallBodyState extends State<_ToolCallBody> {
  bool? _argumentsExpandedOverride;
  bool? _resultExpandedOverride;

  @override
  void didUpdateWidget(covariant _ToolCallBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _argumentsExpandedOverride = null;
      _resultExpandedOverride = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.message;
    final toolCall = _ToolCallViewData.from(context, message);
    final argumentsExpanded =
        _argumentsExpandedOverride ?? toolCall.defaultExpanded;
    final resultExpanded = _resultExpandedOverride ?? toolCall.defaultExpanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ToolExecutionChip(
              icon: toolCall.presentation.icon,
              label: toolCall.primaryChipLabel,
            ),
            if (toolCall.workingDirectory.isNotEmpty)
              _ToolExecutionChip(
                icon: Icons.folder_outlined,
                label:
                    '${_localizedText(context, zh: '目录', en: 'Dir')}: ${toolCall.workingDirectory}',
              ),
            if (toolCall.status.isNotEmpty)
              _ToolExecutionChip(
                icon: toolCall.statusIcon,
                label: toolCall.outcomeLabel,
              ),
            if (toolCall.durationMs > 0 || toolCall.status == 'running')
              _ToolExecutionChip(
                icon: Icons.timer_outlined,
                label:
                    '${_localizedText(context, zh: '耗时', en: 'Elapsed')}: ${_formatToolExecutionDuration(toolCall.durationMs)}',
              ),
            if (toolCall.exitCode != null)
              _ToolExecutionChip(
                icon: Icons.flag_outlined,
                label:
                    '${_localizedText(context, zh: '退出码', en: 'Exit')}: ${toolCall.exitCode}',
              ),
          ],
        ),
        const SizedBox(height: 10),
        _ExpandableToolSection(
          title: _localizedText(context, zh: '工具入参', en: 'Tool Input'),
          preview: toolCall.argumentsPreview,
          expanded: argumentsExpanded,
          onToggle: () {
            setState(() {
              _argumentsExpandedOverride = !argumentsExpanded;
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (toolCall.command.isNotEmpty)
                _ToolOutputPanel(
                  label: _localizedText(context, zh: 'command', en: 'command'),
                  content: '\$ ${toolCall.command}',
                  theme: theme,
                ),
              if (toolCall.command.isNotEmpty) const SizedBox(height: 10),
              _ToolOutputPanel(
                label: _localizedText(
                  context,
                  zh: 'arguments',
                  en: 'arguments',
                ),
                content: toolCall.prettyArguments,
                theme: theme,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _ExpandableToolSection(
          title: _localizedText(context, zh: '结果输出', en: 'Tool Output'),
          preview: toolCall.hasResultContent
              ? toolCall.resultPreview
              : _localizedText(context, zh: '暂无输出', en: 'No output yet'),
          expanded: resultExpanded,
          onToggle: () {
            setState(() {
              _resultExpandedOverride = !resultExpanded;
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (toolCall.stdout.isNotEmpty)
                _ToolOutputPanel(
                  label: 'stdout',
                  content: toolCall.stdout,
                  theme: theme,
                ),
              if (toolCall.stderr.isNotEmpty) ...[
                if (toolCall.stdout.isNotEmpty) const SizedBox(height: 10),
                _ToolOutputPanel(
                  label: 'stderr',
                  content: toolCall.stderr,
                  theme: theme,
                  isError: true,
                ),
              ],
              if (toolCall.showResultText) ...[
                if (toolCall.stdout.isNotEmpty || toolCall.stderr.isNotEmpty)
                  const SizedBox(height: 10),
                _ToolOutputPanel(
                  label: _localizedText(context, zh: 'result', en: 'result'),
                  content: toolCall.resultText,
                  theme: theme,
                ),
              ],
              if (toolCall.stdout.isEmpty &&
                  toolCall.stderr.isEmpty &&
                  !toolCall.showResultText)
                Text(
                  _localizedText(
                    context,
                    zh: '当前还没有工具输出。',
                    en: 'There is no tool output yet.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
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

class _ToolCallPresentation {
  const _ToolCallPresentation({
    required this.categoryLabel,
    required this.displayName,
    required this.icon,
    this.isCommandLike = false,
  });

  final String categoryLabel;
  final String displayName;
  final IconData icon;
  final bool isCommandLike;
}

class _ToolCallViewData {
  const _ToolCallViewData({
    required this.presentation,
    required this.status,
    required this.command,
    required this.workingDirectory,
    required this.stdout,
    required this.stderr,
    required this.resultText,
    required this.exitCode,
    required this.durationMs,
    required this.argumentsPreview,
    required this.prettyArguments,
    required this.defaultExpanded,
    required this.showResultText,
    required this.hasResultContent,
    required this.shouldSweepBadge,
    required this.statusIcon,
    required this.primaryChipLabel,
    required this.statusLabel,
    required this.outcomeLabel,
    required this.resultPreview,
  });

  factory _ToolCallViewData.from(
    BuildContext context,
    AiSessionMessage message,
  ) {
    final stopwatch = Stopwatch()..start();
    final presentation = _toolCallPresentation(context, message);
    final status = _toolExecutionStatus(message);
    final command = _toolExecutionCommand(message);
    final workingDirectory = _toolExecutionWorkingDirectory(message);
    final stdout = _toolExecutionStdout(message).trimRight();
    final stderr = _toolExecutionStderr(message).trimRight();
    final resultText = _toolExecutionResult(message).trimRight();
    final exitCode = _toolExecutionExitCode(message);
    final durationMs = _toolExecutionDurationMs(message);
    final argumentsPreview = _toolArgumentsPreview(message);
    final prettyArguments = _prettyToolArgumentsForDisplay(
      '${message.metadata['tool_arguments'] ?? ''}',
    );
    final showResultText =
        resultText.isNotEmpty &&
        resultText != stdout.trim() &&
        resultText != stderr.trim();
    final hasResultContent =
        stdout.isNotEmpty ||
        stderr.isNotEmpty ||
        resultText.isNotEmpty ||
        exitCode != null ||
        status.isNotEmpty;
    final viewData = _ToolCallViewData(
      presentation: presentation,
      status: status,
      command: command,
      workingDirectory: workingDirectory,
      stdout: stdout,
      stderr: stderr,
      resultText: resultText,
      exitCode: exitCode,
      durationMs: durationMs,
      argumentsPreview: argumentsPreview,
      prettyArguments: prettyArguments,
      defaultExpanded: _shouldDefaultExpandToolStatus(status),
      showResultText: showResultText,
      hasResultContent: hasResultContent,
      shouldSweepBadge: _shouldSweepToolStatus(status),
      statusIcon: _toolExecutionStatusIcon(status),
      primaryChipLabel: presentation.displayName == presentation.categoryLabel
          ? presentation.categoryLabel
          : '${presentation.categoryLabel}: ${presentation.displayName}',
      statusLabel: _toolCallStatusLabelForData(
        context,
        presentation,
        status,
        durationMs,
      ),
      outcomeLabel: _toolExecutionOutcomeLabel(context, status),
      resultPreview: _toolExecutionPreviewText(
        context,
        status: status,
        stdout: stdout,
        stderr: stderr,
        resultText: resultText,
      ),
    );
    stopwatch.stop();
    if (kDebugMode && stopwatch.elapsedMilliseconds >= 8) {
      debugPrint(
        '[OpenHand][UI][${message.id}] tool_viewdata_slow elapsed_ms=${stopwatch.elapsedMilliseconds} tool=${presentation.displayName} status=$status arg_chars=${'${message.metadata['tool_arguments'] ?? ''}'.length} stdout_chars=${stdout.length} stderr_chars=${stderr.length}',
      );
    }
    return viewData;
  }

  final _ToolCallPresentation presentation;
  final String status;
  final String command;
  final String workingDirectory;
  final String stdout;
  final String stderr;
  final String resultText;
  final int? exitCode;
  final int durationMs;
  final String argumentsPreview;
  final String prettyArguments;
  final bool defaultExpanded;
  final bool showResultText;
  final bool hasResultContent;
  final bool shouldSweepBadge;
  final IconData statusIcon;
  final String primaryChipLabel;
  final String statusLabel;
  final String outcomeLabel;
  final String resultPreview;
}

String _toolCallName(AiSessionMessage message) =>
    '${message.metadata['tool_name'] ?? ''}'.trim();

String _toolExecutionStatus(AiSessionMessage message) =>
    '${message.metadata['tool_execution_status'] ?? ''}'.trim();

bool _shouldSweepToolStatus(String status) {
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

String _toolExecutionResult(AiSessionMessage message) =>
    '${message.metadata['tool_execution_result'] ?? ''}';

bool _isStreamingReasoningMessage(AiSessionMessage message) {
  return message.kind == AiSessionMessageKind.reasoning &&
      message.metadata[aiSessionMessageMetadataStreamingKey] == true;
}

bool _shouldDefaultExpandReasoning(AiSessionMessage message) {
  return _isStreamingReasoningMessage(message);
}

bool _shouldDefaultExpandToolStatus(String status) {
  return status.isEmpty || status == 'running';
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

IconData _toolExecutionStatusIcon(String status) {
  return switch (status) {
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

_ToolCallPresentation _toolCallPresentation(
  BuildContext context,
  AiSessionMessage message,
) {
  final rawToolName = _toolCallName(message);
  final normalizedToolName = rawToolName.trim().toLowerCase();
  final toolSource = '${message.metadata['tool_source'] ?? ''}'
      .trim()
      .toLowerCase();
  if (toolSource == 'skill' || normalizedToolName.startsWith('skill__')) {
    final skillName = '${message.metadata['skill_name'] ?? ''}'.trim();
    return _ToolCallPresentation(
      categoryLabel: _localizedText(context, zh: '技能', en: 'Skill'),
      displayName: skillName.isEmpty ? rawToolName : skillName,
      icon: Icons.extension_rounded,
    );
  }
  if (toolSource == 'mcp' || normalizedToolName.startsWith('mcp__')) {
    final serverName = '${message.metadata['mcp_server_name'] ?? ''}'.trim();
    final toolName = '${message.metadata['mcp_tool_name'] ?? ''}'.trim();
    final toolId = '${message.metadata['mcp_tool_id'] ?? ''}'.trim();
    final displayName = <String>[
      if (serverName.isNotEmpty) serverName,
      if (toolName.isNotEmpty) toolName else if (toolId.isNotEmpty) toolId,
    ].join(' / ');
    return _ToolCallPresentation(
      categoryLabel: 'MCP',
      displayName: displayName.isEmpty ? rawToolName : displayName,
      icon: Icons.account_tree_outlined,
    );
  }
  return switch (normalizedToolName) {
    'bash' => const _ToolCallPresentation(
      categoryLabel: 'Bash',
      displayName: 'Bash',
      icon: Icons.terminal_rounded,
      isCommandLike: true,
    ),
    'grep' => const _ToolCallPresentation(
      categoryLabel: 'Grep',
      displayName: 'Grep',
      icon: Icons.manage_search_rounded,
    ),
    'ls' => const _ToolCallPresentation(
      categoryLabel: 'LS',
      displayName: 'LS',
      icon: Icons.folder_open_rounded,
    ),
    'read' => const _ToolCallPresentation(
      categoryLabel: 'Read',
      displayName: 'Read',
      icon: Icons.article_outlined,
    ),
    'write' => const _ToolCallPresentation(
      categoryLabel: 'Write',
      displayName: 'Write',
      icon: Icons.edit_note_rounded,
    ),
    'edit' => const _ToolCallPresentation(
      categoryLabel: 'Edit',
      displayName: 'Edit',
      icon: Icons.edit_outlined,
    ),
    'multiedit' => const _ToolCallPresentation(
      categoryLabel: 'MultiEdit',
      displayName: 'MultiEdit',
      icon: Icons.edit_note_outlined,
    ),
    'notebookedit' => const _ToolCallPresentation(
      categoryLabel: 'NotebookEdit',
      displayName: 'NotebookEdit',
      icon: Icons.menu_book_outlined,
    ),
    'webfetch' => const _ToolCallPresentation(
      categoryLabel: 'WebFetch',
      displayName: 'WebFetch',
      icon: Icons.language_rounded,
    ),
    'websearch' => const _ToolCallPresentation(
      categoryLabel: 'WebSearch',
      displayName: 'WebSearch',
      icon: Icons.travel_explore_rounded,
    ),
    'todowrite' => const _ToolCallPresentation(
      categoryLabel: 'TodoWrite',
      displayName: 'TodoWrite',
      icon: Icons.checklist_rounded,
    ),
    'task' => const _ToolCallPresentation(
      categoryLabel: 'Task',
      displayName: 'Task',
      icon: Icons.hub_outlined,
    ),
    'glob' => const _ToolCallPresentation(
      categoryLabel: 'Glob',
      displayName: 'Glob',
      icon: Icons.filter_alt_outlined,
    ),
    'exitplanmode' => const _ToolCallPresentation(
      categoryLabel: 'ExitPlanMode',
      displayName: 'ExitPlanMode',
      icon: Icons.assignment_turned_in_outlined,
    ),
    _ => _ToolCallPresentation(
      categoryLabel: _localizedText(context, zh: '工具', en: 'Tool'),
      displayName: rawToolName.isEmpty
          ? _localizedText(context, zh: '工具', en: 'Tool')
          : rawToolName,
      icon: Icons.build_circle_outlined,
    ),
  };
}

String _prettyToolArgumentsForDisplay(String rawArguments) {
  final trimmed = rawArguments.trim();
  if (trimmed.isEmpty) {
    return '{}';
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(trimmed));
  } catch (_) {
    return trimmed;
  }
}

String _toolArgumentsPreview(AiSessionMessage message) {
  final command = _toolExecutionCommand(message);
  if (command.isNotEmpty) {
    return '\$ $command';
  }
  final rawArguments = '${message.metadata['tool_arguments'] ?? ''}'.trim();
  if (rawArguments.isNotEmpty) {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map) {
        final entries = Map<String, Object?>.from(decoded).entries.take(2);
        final summary = entries
            .map((entry) => '${entry.key}: ${entry.value}')
            .join(', ');
        if (summary.isNotEmpty) {
          return summary;
        }
      }
      if (decoded is List) {
        return '[${decoded.length} items]';
      }
    } catch (_) {
      // Fallback to the prettified text preview below.
    }
  }
  final preview = _prettyToolArgumentsForDisplay(rawArguments);
  final firstLine = const LineSplitter()
      .convert(preview)
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '{}');
  return firstLine;
}

String _toolCallStatusLabelForData(
  BuildContext context,
  _ToolCallPresentation presentation,
  String status,
  int durationMs,
) {
  final suffix = durationMs <= 0
      ? ''
      : ' (${_formatToolExecutionDuration(durationMs)})';
  final toolLabel = presentation.displayName.trim().isEmpty
      ? presentation.categoryLabel
      : presentation.displayName.trim();
  final statusLabel = _toolCallStatusActionLabel(
    context,
    status,
    isCommandLike: presentation.isCommandLike,
  );
  return suffix.isEmpty
      ? '$toolLabel · $statusLabel'
      : '$toolLabel · $statusLabel$suffix';
}

String _toolCallStatusActionLabel(
  BuildContext context,
  String status, {
  required bool isCommandLike,
}) {
  return switch (status) {
    '' => _localizedText(
      context,
      zh: isCommandLike ? '准备执行' : '准备调用',
      en: 'Preparing',
    ),
    'running' => _localizedText(
      context,
      zh: isCommandLike ? '执行中' : '调用中',
      en: 'Running',
    ),
    'cancelled' => _localizedText(context, zh: '已停止', en: 'Stopped'),
    'success' => _localizedText(
      context,
      zh: isCommandLike ? '执行完成' : '调用完成',
      en: 'Completed',
    ),
    'denied' => _localizedText(context, zh: '已拦截', en: 'Blocked'),
    'rejected' => _localizedText(context, zh: '已拒绝', en: 'Rejected'),
    'timed_out' => _localizedText(
      context,
      zh: isCommandLike ? '执行超时' : '调用超时',
      en: 'Timed Out',
    ),
    'failed' => _localizedText(
      context,
      zh: isCommandLike ? '执行失败' : '调用失败',
      en: 'Failed',
    ),
    'invalid_arguments' => _localizedText(context, zh: '参数无效', en: 'Invalid'),
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

String _toolExecutionPreviewText(
  BuildContext context, {
  required String status,
  required String stdout,
  required String stderr,
  required String resultText,
}) {
  final stderrLine = _lastNonEmptyToolOutputLine(stderr);
  if (stderrLine.isNotEmpty) {
    return 'stderr · $stderrLine';
  }
  final stdoutLine = _lastNonEmptyToolOutputLine(stdout);
  if (stdoutLine.isNotEmpty) {
    return 'stdout · $stdoutLine';
  }
  final resultLine = _lastNonEmptyToolOutputLine(resultText);
  if (resultLine.isNotEmpty) {
    return 'result · $resultLine';
  }
  if (_shouldSweepToolStatus(status)) {
    return _localizedText(
      context,
      zh: '工具运行中，等待新的输出...',
      en: 'Tool is running. Waiting for output...',
    );
  }
  return _localizedText(
    context,
    zh: '点击展开查看工具输出',
    en: 'Expand to inspect tool output',
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
    required this.sendPhase,
    required this.isSelected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final AiSession session;
  final AiSendPhase sendPhase;
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
    final isActive = sendPhase != AiSendPhase.idle;
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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: titleColor,
                    ),
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 12),
                  _ActiveThreadBadge(
                    key: ValueKey<String>('thread-active-${session.id}'),
                    sendPhase: sendPhase,
                    isSelected: isSelected,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveThreadBadge extends StatelessWidget {
  const _ActiveThreadBadge({
    super.key,
    required this.sendPhase,
    required this.isSelected,
  });

  final AiSendPhase sendPhase;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foregroundColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.primary;
    final backgroundColor = isSelected
        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.14)
        : colorScheme.primary.withValues(alpha: 0.12);
    final label = switch (sendPhase) {
      AiSendPhase.compressing => _localizedText(
        context,
        zh: '压缩中',
        en: 'Compressing',
      ),
      AiSendPhase.sendingMessage => _localizedText(
        context,
        zh: '发送中',
        en: 'Sending',
      ),
      AiSendPhase.responding => _localizedText(
        context,
        zh: '进行中',
        en: 'Active',
      ),
      AiSendPhase.idle => '',
    };
    return _SweepBadge(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      backgroundColor: backgroundColor,
      borderColor: foregroundColor.withValues(alpha: 0.22),
      sweepColor: foregroundColor.withValues(alpha: 0.18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: foregroundColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
    final toolCall = _ToolCallViewData.from(context, message);
    final showSweep = toolCall.shouldSweepBadge;
    final effectiveColor = showSweep
        ? theme.colorScheme.onSurfaceVariant
        : color;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(toolCall.statusIcon, size: 18, color: effectiveColor),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            toolCall.statusLabel,
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
        if (message.kind != AiSessionMessageKind.tool &&
            message.kind != AiSessionMessageKind.mcp &&
            message.kind != AiSessionMessageKind.skill) {
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
