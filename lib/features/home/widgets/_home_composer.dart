part of '../openhand_home_page.dart';

const Set<String> _atMentionIgnoredEntryNames = <String>{
  'node_modules',
  'build',
  '.dart_tool',
  '__pycache__',
  '.git',
  '.idea',
  '.vscode',
  'target',
  'dist',
  '.gradle',
};
const int _atMentionShallowResultLimit = 50;
const int _atMentionDeepSearchSoftLimit = 20;
const int _atMentionDeepSearchResultLimit = 80;
const int _atMentionDeepSearchMaxDepth = 8;
const int _atMentionDirectoryEntryLimit = 5000;
const int _atMentionDeepSearchEntryLimit = 20000;
const double _composerActionControlGap = 10;
const double _composerActionControlHeight = 52;
const double _composerOverlayViewportMargin = 8;
const double _composerOverlayGap = 6;
final RegExp _composerTriggerWindowsDrivePattern = RegExp(r'^[A-Za-z]:');

String _inputCacheModelLockReason(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已锁定服务商、模型与推理强度以保证缓存命中（可在设置→AI→成本控制中关闭输入缓存后再切换）',
    en: 'Provider, model & reasoning effort locked to ensure cache hit (disable Input Cache under Settings → AI → Cost Control to switch)',
  );
}

enum _AtMentionOverlayMode { projectFiles, localFiles }

bool _isComposerPathLikeQuery(String query) {
  if (query.isEmpty) return false;
  if (query.startsWith('/') ||
      query.startsWith('\\') ||
      query.contains('/') ||
      query.contains('\\') ||
      query.startsWith('./') ||
      query.startsWith('../') ||
      query.startsWith('~/') ||
      query.startsWith('.\\') ||
      query.startsWith('..\\') ||
      query.startsWith('~\\')) {
    return true;
  }
  return _composerTriggerWindowsDrivePattern.hasMatch(query);
}

bool _shouldSuppressSlashSkillPickerQuery(String query) {
  return _isComposerPathLikeQuery(query) || query.startsWith('*');
}

bool _shouldSuppressAtMentionPickerQuery(String query) {
  return _isComposerPathLikeQuery(query);
}

bool _shouldSuppressDismissedComposerTrigger({
  required String dismissedQuery,
  required String currentQuery,
}) {
  final dismissed = dismissedQuery.toLowerCase();
  final current = currentQuery.toLowerCase();
  return current.length >= dismissed.length && current.startsWith(dismissed);
}

String? _readComposerTriggerQueryAtOffset({
  required String text,
  required int triggerOffset,
  required int triggerCodeUnit,
  required bool requireWhitespaceBefore,
}) {
  if (triggerOffset < 0 || triggerOffset >= text.length) return null;
  if (text.codeUnitAt(triggerOffset) != triggerCodeUnit) return null;
  if (requireWhitespaceBefore &&
      triggerOffset > 0 &&
      !isAsciiWhitespaceCodeUnit(text.codeUnitAt(triggerOffset - 1))) {
    return null;
  }
  var tokenEnd = text.length;
  for (var i = triggerOffset + 1; i < text.length; i++) {
    if (isAsciiWhitespaceCodeUnit(text.codeUnitAt(i))) {
      tokenEnd = i;
      break;
    }
  }
  return text.substring(triggerOffset + 1, tokenEnd);
}

class _ComposerTriggerDismissal {
  const _ComposerTriggerDismissal({required this.offset, required this.query});

  final int offset;
  final String query;
}

/// 一次 @ 提及检索的不变量，随浅层遍历与递归下钻整体透传。
///
/// 目录遍历是异步的，输入框随时可能变化；把这些值打包传递，可以在每个可能
/// 让出事件循环的位置用同一份基准判断结果是否已经过期。
class _AtMentionSearchScope {
  const _AtMentionSearchScope({
    required this.searchGeneration,
    required this.triggerOffset,
    required this.query,
    required this.currentDirectory,
    required this.rootPath,
  });

  final int searchGeneration;
  final int triggerOffset;
  final String query;
  final String currentDirectory;
  final String rootPath;
}

({bool available, String reason}) _composerVoiceAvailability(
  OfflineSpeechSettings settings,
) {
  for (final entry in <(OfflineSpeechKind, OfflineSpeechModelSettings)>[
    (OfflineSpeechKind.recognition, settings.recognition),
    (OfflineSpeechKind.synthesis, settings.synthesis),
  ]) {
    final modelId = entry.$2.enabledModelId;
    final model = modelId == null
        ? null
        : OfflineSpeechModelCatalog.byId(modelId);
    final label = entry.$1 == OfflineSpeechKind.recognition ? '语音识别' : '语音朗读';
    if (model == null || model.kind != entry.$1) {
      return (available: false, reason: '请先在设置中启用一个$label模型。');
    }
    final configuration = entry.$2.configuration(model);
    final service = OfflineSpeechModelService.instance;
    final availability = service.availabilityFor(model, configuration);
    if (!availability.available) {
      return (available: false, reason: '$label模型不可用：${availability.reason}');
    }
    if (!service.isInstalled(model) ||
        service.requiresDownloadForConfiguration(model, configuration)) {
      return (available: false, reason: '请先下载并准备好$label模型。');
    }
  }
  return (available: true, reason: '开始语音沟通');
}

class _ComposerPanel extends StatefulWidget {
  const _ComposerPanel({
    required this.currentSession,
    required this.liveRuntimeToolPreview,
    required this.controller,
    required this.selectedModel,
    required this.availableModels,
    required this.recentModelSelections,
    required this.onModelSelected,
    required this.focusNode,
    required this.composerHeight,
    required this.isCollapsed,
    required this.onCollapsedChanged,
    required this.autoFollowEnabled,
    required this.autoFollowPaused,
    required this.onToggleAutoFollow,
    required this.sendPhase,
    required this.canStopSending,
    required this.sessionMode,
    required this.onSessionModeChanged,
    required this.goalControls,
    required this.attachments,
    required this.onSend,
    required this.onStop,
    required this.voiceConversationService,
    required this.onStartVoiceConversation,
    required this.onStopVoiceConversation,
    required this.creationMode,
    required this.onCreationModeChanged,
    this.creationOptions = AiCreationOptions.empty,
    this.onCreationOptionsChanged,
    this.onEditOptionsRequested,
    required this.fullAccessPermission,
    required this.onToggleFullAccessPermission,
    required this.editingMessageId,
    required this.onCancelEditing,
    required this.queuedPanel,
    this.projectRoot,
    this.onStateCreated,
    this.onStateDisposed,
  });

  final AiSession? currentSession;
  final AiRuntimeToolPreview? liveRuntimeToolPreview;
  final TextEditingController controller;
  final AiModelConfig? selectedModel;
  final List<AiModelConfig> availableModels;
  final List<RecentModelSelection> recentModelSelections;
  final void Function(String providerConfigId, String modelId) onModelSelected;
  final FocusNode focusNode;
  final double composerHeight;
  final bool isCollapsed;
  final ValueChanged<bool> onCollapsedChanged;
  final bool autoFollowEnabled;
  // 自动跟随已启用但因用户离开底部而暂停；点击后恢复并跳到最新消息。
  final bool autoFollowPaused;
  final VoidCallback onToggleAutoFollow;
  final AiSendPhase sendPhase;
  final bool canStopSending;
  final AiSessionMode sessionMode;
  final ValueChanged<AiSessionMode> onSessionModeChanged;
  final _GoalControls goalControls;
  final _ComposerAttachments attachments;
  final Future<void> Function() onSend;
  final Future<void> Function() onStop;
  final AiVoiceConversationService voiceConversationService;
  final Future<void> Function() onStartVoiceConversation;
  final Future<void> Function() onStopVoiceConversation;
  final _CreationMode creationMode;
  final ValueChanged<_CreationMode> onCreationModeChanged;
  final AiCreationOptions creationOptions;
  final ValueChanged<AiCreationOptions>? onCreationOptionsChanged;
  final Future<void> Function()? onEditOptionsRequested;
  final bool fullAccessPermission;
  final ValueChanged<bool> onToggleFullAccessPermission;
  final String? editingMessageId;
  final Future<void> Function() onCancelEditing;
  final _QueuedMessagesPanel queuedPanel;
  final String? projectRoot;
  final ValueChanged<_ComposerPanelState>? onStateCreated;
  final ValueChanged<_ComposerPanelState>? onStateDisposed;

  @override
  State<_ComposerPanel> createState() => _ComposerPanelState();
}

class _ComposerPanelState extends State<_ComposerPanel> {
  final LayerLink _atMentionLayerLink = LayerLink();
  final LayerLink _skillPickerLayerLink = LayerLink();
  final GlobalKey _atMentionAnchorKey = GlobalKey();
  final GlobalKey _skillPickerAnchorKey = GlobalKey();
  final AnimatedOverlayEntryController _atMentionOverlay =
      AnimatedOverlayEntryController();
  final AnimatedOverlayEntryController _skillPickerOverlay =
      AnimatedOverlayEntryController();
  bool _composerFocusListenerAttached = false;
  List<_AtMentionItem> _atMentionResults = const [];
  int _atMentionSelectedIndex = 0;
  int _atMentionTriggerOffset = -1;
  String _atMentionCurrentDirectory = '';
  String? _atMentionRestoreSelectionRelativePath;
  // 目录下钻的面包屑路径。
  List<String> _atMentionBreadcrumbs = const [];
  bool _atMentionLoading = false;
  bool _atMentionSuppressListener = false;
  int _atMentionSearchGeneration = 0;
  _AtMentionOverlayMode _atMentionOverlayMode =
      _AtMentionOverlayMode.projectFiles;
  // 记住主动关闭的查询，避免继续输入时立即重开浮层。
  _ComposerTriggerDismissal? _atMentionDismissal;
  // 通过 @ 浮层选择的项目路径。
  List<_AtMentionItem> _projectFileReferences = [];

  // 输入以 `/` 开头时展示技能选择器，发送时通过隐藏提醒注入技能清单。
  LocalSkill? _selectedSkill;
  String? _selectedSkillManifest;
  int _slashTriggerOffset = -1;
  _ComposerTriggerDismissal? _slashDismissal;
  List<LocalSkill> _skillPickerResults = const <LocalSkill>[];
  int _skillPickerSelectedIndex = 0;
  bool _skillPickerLoading = false;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated?.call(this);
    widget.controller.addListener(_handleTextChangedForAtMention);
    widget.controller.addListener(_handleTextChangedForSlashSkill);
    widget.voiceConversationService.addListener(
      _handleVoiceConversationChanged,
    );
    OfflineSpeechModelService.instance.addListener(
      _handleVoiceConversationChanged,
    );
    _attachComposerFocusListener(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant _ComposerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChangedForAtMention);
      oldWidget.controller.removeListener(_handleTextChangedForSlashSkill);
      widget.controller.addListener(_handleTextChangedForAtMention);
      widget.controller.addListener(_handleTextChangedForSlashSkill);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _detachComposerFocusListener(oldWidget.focusNode);
      _attachComposerFocusListener(widget.focusNode);
    }
    if (oldWidget.voiceConversationService != widget.voiceConversationService) {
      oldWidget.voiceConversationService.removeListener(
        _handleVoiceConversationChanged,
      );
      widget.voiceConversationService.addListener(
        _handleVoiceConversationChanged,
      );
    }
  }

  @override
  void dispose() {
    widget.onStateDisposed?.call(this);
    widget.controller.removeListener(_handleTextChangedForAtMention);
    widget.controller.removeListener(_handleTextChangedForSlashSkill);
    widget.voiceConversationService.removeListener(
      _handleVoiceConversationChanged,
    );
    OfflineSpeechModelService.instance.removeListener(
      _handleVoiceConversationChanged,
    );
    _detachComposerFocusListener(widget.focusNode);
    _atMentionOverlay.dispose();
    _skillPickerOverlay.dispose();
    super.dispose();
  }

  void _handleVoiceConversationChanged() {
    if (mounted) setState(() {});
  }

  void _attachComposerFocusListener(FocusNode focusNode) {
    if (_composerFocusListenerAttached) return;
    focusNode.addListener(_handleComposerFocusChanged);
    _composerFocusListenerAttached = true;
  }

  void _detachComposerFocusListener(FocusNode focusNode) {
    if (!_composerFocusListenerAttached) return;
    focusNode.removeListener(_handleComposerFocusChanged);
    _composerFocusListenerAttached = false;
  }

  void _handleComposerFocusChanged() {
    if (!mounted || widget.focusNode.hasFocus) return;
    if (_atMentionOverlay.hasEntry) {
      _userDismissAtMentionOverlay();
    }
    if (_skillPickerOverlay.hasEntry) {
      _userDismissSkillPickerOverlay();
    }
  }

  // @ 提及检测。

  ({int triggerOffset, int tokenEnd, String query})?
  _computeAtMentionTrigger() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final cursor = selection.baseOffset.clamp(0, text.length);
    int atIndex = -1;
    for (var i = cursor - 1; i >= 0; i--) {
      final ch = text.codeUnitAt(i);
      if (ch == 0x40 /* @ */ ) {
        atIndex = i;
        break;
      }
      if (isAsciiWhitespaceCodeUnit(ch)) {
        break;
      }
    }
    if (atIndex < 0) return null;
    if (atIndex > 0 &&
        !isAsciiWhitespaceCodeUnit(text.codeUnitAt(atIndex - 1))) {
      return null;
    }
    var tokenEnd = text.length;
    for (var i = atIndex + 1; i < text.length; i++) {
      if (isAsciiWhitespaceCodeUnit(text.codeUnitAt(i))) {
        tokenEnd = i;
        break;
      }
    }
    if (cursor > tokenEnd) return null;
    final query = text.substring(atIndex + 1, tokenEnd);
    if (_shouldSuppressAtMentionPickerQuery(query)) {
      return null;
    }
    return (triggerOffset: atIndex, tokenEnd: tokenEnd, query: query);
  }

  void _invalidateAtMentionSearch() {
    _atMentionSearchGeneration += 1;
    _atMentionLoading = false;
  }

  /// 一次 @ 提及检索的身份：目录遍历与递归下钻都靠它判断结果是否仍该采纳。
  ///
  /// 输入框内容、当前目录或触发位置一变，本次检索的结果就已过期，必须整体丢弃。
  bool _isAtMentionSearchStale(_AtMentionSearchScope scope) {
    if (!mounted) return true;
    if (scope.searchGeneration != _atMentionSearchGeneration) return true;
    if (widget.projectRoot != scope.rootPath) return true;
    if (_atMentionCurrentDirectory != scope.currentDirectory) return true;
    if (_atMentionTriggerOffset != scope.triggerOffset) return true;
    final trigger = _computeAtMentionTrigger();
    return trigger == null ||
        trigger.triggerOffset != scope.triggerOffset ||
        trigger.query != scope.query;
  }

  void _pruneAtMentionDismissal() {
    final dismissal = _atMentionDismissal;
    if (dismissal == null) return;
    final currentQuery = _readComposerTriggerQueryAtOffset(
      text: widget.controller.text,
      triggerOffset: dismissal.offset,
      triggerCodeUnit: 0x40,
      requireWhitespaceBefore: true,
    );
    if (currentQuery == null ||
        !_shouldSuppressDismissedComposerTrigger(
          dismissedQuery: dismissal.query,
          currentQuery: currentQuery,
        )) {
      _atMentionDismissal = null;
    }
  }

  void _pruneSlashDismissal() {
    final dismissal = _slashDismissal;
    if (dismissal == null) return;
    final currentQuery = _readComposerTriggerQueryAtOffset(
      text: widget.controller.text,
      triggerOffset: dismissal.offset,
      triggerCodeUnit: 0x2F,
      requireWhitespaceBefore: false,
    );
    if (currentQuery == null ||
        !_shouldSuppressDismissedComposerTrigger(
          dismissedQuery: dismissal.query,
          currentQuery: currentQuery,
        )) {
      _slashDismissal = null;
    }
  }

  _ComposerTriggerDismissal? _readAtMentionDismissalAtOffset(int offset) {
    final query = _readComposerTriggerQueryAtOffset(
      text: widget.controller.text,
      triggerOffset: offset,
      triggerCodeUnit: 0x40,
      requireWhitespaceBefore: true,
    );
    return query == null
        ? null
        : _ComposerTriggerDismissal(offset: offset, query: query);
  }

  _ComposerTriggerDismissal? _readSlashDismissalAtOffset(int offset) {
    final query = _readComposerTriggerQueryAtOffset(
      text: widget.controller.text,
      triggerOffset: offset,
      triggerCodeUnit: 0x2F,
      requireWhitespaceBefore: false,
    );
    return query == null
        ? null
        : _ComposerTriggerDismissal(offset: offset, query: query);
  }

  bool _atMentionDismissalSuppresses(int triggerOffset) {
    _pruneAtMentionDismissal();
    final dismissal = _atMentionDismissal;
    if (dismissal == null || dismissal.offset != triggerOffset) return false;
    final current = _readAtMentionDismissalAtOffset(triggerOffset);
    return current != null &&
        _shouldSuppressDismissedComposerTrigger(
          dismissedQuery: dismissal.query,
          currentQuery: current.query,
        );
  }

  bool _slashDismissalSuppresses(int triggerOffset) {
    _pruneSlashDismissal();
    final dismissal = _slashDismissal;
    if (dismissal == null || dismissal.offset != triggerOffset) return false;
    final current = _readSlashDismissalAtOffset(triggerOffset);
    return current != null &&
        _shouldSuppressDismissedComposerTrigger(
          dismissedQuery: dismissal.query,
          currentQuery: current.query,
        );
  }

  void _handleTextChangedForAtMention() {
    if (_atMentionSuppressListener) return;
    final trigger = _computeAtMentionTrigger();
    if (trigger == null) {
      if (_atMentionTriggerOffset >= 0) {
        _atMentionDismissal =
            _readAtMentionDismissalAtOffset(_atMentionTriggerOffset) ??
            _atMentionDismissal;
      }
      _pruneAtMentionDismissal();
      _dismissAtMentionOverlay();
      return;
    }
    final root = widget.projectRoot;
    if (_atMentionDismissalSuppresses(trigger.triggerOffset)) {
      _dismissAtMentionOverlay();
      return;
    }
    if (_atMentionTriggerOffset != trigger.triggerOffset) {
      _atMentionCurrentDirectory = '';
      _atMentionBreadcrumbs = const [];
    }
    _atMentionDismissal = null;
    _atMentionTriggerOffset = trigger.triggerOffset;
    if (root == null || root.isEmpty) {
      _showAtMentionLocalFileOverlay();
      return;
    }
    _performAtMentionSearch(root, trigger.query);
  }

  void _showAtMentionLocalFileOverlay() {
    _invalidateAtMentionSearch();
    setState(() {
      _atMentionOverlayMode = _AtMentionOverlayMode.localFiles;
      _atMentionCurrentDirectory = '';
      _atMentionBreadcrumbs = const [];
      _atMentionResults = widget.attachments.enabled
          ? const <_AtMentionItem>[_AtMentionItem.localFileAction()]
          : const <_AtMentionItem>[];
      _atMentionSelectedIndex = 0;
      _atMentionLoading = false;
    });
    _showAtMentionOverlay();
  }

  Future<void> _performAtMentionSearch(String rootPath, String query) async {
    if (!mounted) return;
    final currentDirectory = _atMentionCurrentDirectory;
    final scope = _AtMentionSearchScope(
      searchGeneration: ++_atMentionSearchGeneration,
      triggerOffset: _atMentionTriggerOffset,
      query: query,
      currentDirectory: currentDirectory,
      rootPath: rootPath,
    );
    final restoreSelectionRelativePath = _atMentionRestoreSelectionRelativePath;
    setState(() => _atMentionLoading = true);
    _atMentionOverlayMode = _AtMentionOverlayMode.projectFiles;
    final basePath = currentDirectory.isEmpty
        ? rootPath
        : p.join(rootPath, currentDirectory);
    final trimmedQuery = query.trim().toLowerCase();
    final results = <_AtMentionItem>[];
    try {
      final dir = Directory(basePath);
      if (!await isDirectoryPath(dir.path, followLinks: true)) {
        if (_isAtMentionSearchStale(scope)) {
          return;
        }
        setState(() {
          _atMentionResults = const [];
          _atMentionSelectedIndex = 0;
          _atMentionLoading = false;
        });
        _showAtMentionOverlay();
        return;
      }
      final entries = (await listDirectoryBounded(
        dir,
        maxEntries: _atMentionDirectoryEntryLimit,
      )).entries.toList(growable: false);
      if (_isAtMentionSearchStale(scope)) {
        return;
      }
      entries.sort(_compareFileSystemEntitiesDirectoryFirst);
      for (final entry in entries) {
        if (_isAtMentionSearchStale(scope)) {
          return;
        }
        if (results.length >= _atMentionShallowResultLimit) break;
        final name = p.basename(entry.path);
        if (name.startsWith('.')) continue;
        if (_atMentionIgnoredEntryNames.contains(name)) continue;
        if (trimmedQuery.isEmpty || name.toLowerCase().contains(trimmedQuery)) {
          final relativePath = p.relative(entry.path, from: rootPath);
          results.add(
            _AtMentionItem(
              name: name,
              path: entry.path,
              relativePath: relativePath,
              isDirectory: entry is Directory,
            ),
          );
        }
      }
      // 浅层结果不足时递归搜索深层路径，总数最多 80。
      if (trimmedQuery.isNotEmpty &&
          results.length < _atMentionDeepSearchSoftLimit) {
        await _deepSearchAtMention(
          Directory(rootPath),
          trimmedQuery,
          results,
          0,
          scope: scope,
          budget: _DirectoryScanBudget(_atMentionDeepSearchEntryLimit),
        );
      }
    } catch (error, stack) {
      silentLog('composer', '@ 提及浅层搜索', error, stack);
    }
    if (_isAtMentionSearchStale(scope)) {
      return;
    }
    setState(() {
      _atMentionResults = results;
      _atMentionSelectedIndex = restoreSelectionRelativePath == null
          ? 0
          : math.max(
              0,
              results.indexWhere(
                (item) => item.relativePath == restoreSelectionRelativePath,
              ),
            );
      _atMentionLoading = false;
    });
    if (_atMentionRestoreSelectionRelativePath ==
        restoreSelectionRelativePath) {
      _atMentionRestoreSelectionRelativePath = null;
    }
    _showAtMentionOverlay();
  }

  Future<void> _deepSearchAtMention(
    Directory dir,
    String query,
    List<_AtMentionItem> results,
    int depth, {
    required _AtMentionSearchScope scope,
    required _DirectoryScanBudget budget,
  }) async {
    if (depth > _atMentionDeepSearchMaxDepth ||
        results.length >= _atMentionDeepSearchResultLimit ||
        budget.remaining <= 0) {
      return;
    }
    if (_isAtMentionSearchStale(scope)) {
      return;
    }
    try {
      final entries = (await listDirectoryBounded(
        dir,
        maxEntries: math.min(_atMentionDirectoryEntryLimit, budget.remaining),
      )).entries;
      if (_isAtMentionSearchStale(scope)) {
        return;
      }
      for (final entry in entries) {
        if (!budget.consume()) return;
        if (_isAtMentionSearchStale(scope)) {
          return;
        }
        if (results.length >= _atMentionDeepSearchResultLimit) return;
        final name = p.basename(entry.path);
        if (name.startsWith('.')) continue;
        if (_atMentionIgnoredEntryNames.contains(name)) continue;
        final relativePath = p.relative(entry.path, from: scope.rootPath);
        // 去除浅层列表已有项。
        if (name.toLowerCase().contains(query) &&
            !results.any((r) => r.path == entry.path)) {
          results.add(
            _AtMentionItem(
              name: name,
              path: entry.path,
              relativePath: relativePath,
              isDirectory: entry is Directory,
            ),
          );
        }
        if (entry is Directory) {
          await _deepSearchAtMention(
            entry,
            query,
            results,
            depth + 1,
            scope: scope,
            budget: budget,
          );
        }
      }
    } catch (error, stack) {
      silentLog('composer', '@ 提及深层搜索', error, stack);
    }
  }

  DialogAnimationSettings _resolveMenuAnimationSettings() {
    return openHandMotionSettingsOf(context, OpenHandMotionSettingsScope.menu);
  }

  void _showAtMentionOverlay() {
    final animationSettings = _resolveMenuAnimationSettings();
    _atMentionOverlay.show(
      overlay: Overlay.of(context, rootOverlay: true),
      builder: (context, visibility, onExitCompleted) {
        return _AtMentionOverlayPanel(
          link: _atMentionLayerLink,
          anchorKey: _atMentionAnchorKey,
          items: _atMentionResults,
          selectedIndex: _atMentionSelectedIndex,
          loading: _atMentionLoading,
          breadcrumbs: _atMentionBreadcrumbs,
          mode: _atMentionOverlayMode,
          attachmentsEnabled: widget.attachments.enabled,
          onSelect: _handleAtMentionSelect,
          onDrillDown: _handleAtMentionDrillDown,
          onBreadcrumbTap: _handleAtMentionBreadcrumbTap,
          onDismiss: _userDismissAtMentionOverlay,
          visible: visibility,
          animationSettings: animationSettings,
          onExitComplete: onExitCompleted,
        );
      },
    );
  }

  /// 用户主动关闭后记住 @ 偏移，避免同一位置立即再次弹出。
  void _userDismissAtMentionOverlay() {
    final trigger = _computeAtMentionTrigger();
    if (trigger != null) {
      _atMentionDismissal =
          _readAtMentionDismissalAtOffset(trigger.triggerOffset) ??
          _ComposerTriggerDismissal(
            offset: trigger.triggerOffset,
            query: trigger.query,
          );
    } else if (_atMentionTriggerOffset >= 0) {
      _atMentionDismissal =
          _readAtMentionDismissalAtOffset(_atMentionTriggerOffset) ??
          _atMentionDismissal;
    }
    _dismissAtMentionOverlay();
  }

  void _dismissAtMentionOverlay() {
    _atMentionOverlay.close(immediately: !mounted);
    _invalidateAtMentionSearch();
    _atMentionResults = const [];
    _atMentionSelectedIndex = 0;
    if (_atMentionTriggerOffset >= 0) {
      _atMentionTriggerOffset = -1;
      _atMentionCurrentDirectory = '';
      _atMentionBreadcrumbs = const [];
    }
  }

  void _handleAtMentionSelect(_AtMentionItem item) {
    if (item.isLocalFileAction) {
      unawaited(_handleAtMentionLocalFileSelect());
      return;
    }
    // 添加为项目路径胶囊。
    if (_projectFileReferences.any((r) => r.path == item.path)) {
      // 已引用时直接关闭。
      _atMentionDismissal = null;
      _dismissAtMentionOverlay();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.focusNode.requestFocus();
      });
      return;
    }
    _removeAtMentionTriggerText();
    setState(() {
      _projectFileReferences = [..._projectFileReferences, item];
    });
    _atMentionDismissal = null;
    _dismissAtMentionOverlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.focusNode.requestFocus();
    });
  }

  Future<void> _handleAtMentionLocalFileSelect() async {
    _removeAtMentionTriggerText();
    _atMentionDismissal = null;
    _dismissAtMentionOverlay();
    if (widget.attachments.enabled) {
      await widget.attachments.onPick();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.focusNode.requestFocus();
    });
  }

  void _removeAtMentionTriggerText() {
    if (_atMentionTriggerOffset < 0 ||
        _atMentionTriggerOffset > widget.controller.text.length) {
      return;
    }
    final cursor = widget.controller.selection.baseOffset.clamp(
      0,
      widget.controller.text.length,
    );
    if (cursor < _atMentionTriggerOffset) return;
    final trigger = _computeAtMentionTrigger();
    final removeEnd = trigger?.tokenEnd ?? cursor;
    _atMentionSuppressListener = true;
    try {
      final nextText = widget.controller.text.replaceRange(
        _atMentionTriggerOffset,
        removeEnd,
        '',
      );
      widget.controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: _atMentionTriggerOffset),
      );
    } finally {
      _atMentionSuppressListener = false;
    }
  }

  void _handleAtMentionDrillDown(_AtMentionItem item) {
    if (!item.isDirectory) return;
    final root = widget.projectRoot;
    if (root == null) return;
    setState(() {
      _atMentionRestoreSelectionRelativePath = null;
      _atMentionCurrentDirectory = p.relative(item.path, from: root);
      _atMentionBreadcrumbs = p
          .split(_atMentionCurrentDirectory)
          .where((s) => s.isNotEmpty)
          .toList();
    });
    // 将 @ 后的查询文本还原为空。
    final textLen = widget.controller.text.length;
    if (_atMentionTriggerOffset >= 0 && _atMentionTriggerOffset < textLen) {
      final cursor = widget.controller.selection.baseOffset.clamp(0, textLen);
      final start = _atMentionTriggerOffset + 1;
      if (start <= cursor) {
        final trigger = _computeAtMentionTrigger();
        final replaceEnd = trigger?.tokenEnd ?? cursor;
        // 同样合并为单次 value 写入。
        _atMentionSuppressListener = true;
        try {
          widget.controller.value = TextEditingValue(
            text: widget.controller.text.replaceRange(start, replaceEnd, ''),
            selection: TextSelection.collapsed(offset: start),
          );
        } finally {
          _atMentionSuppressListener = false;
        }
      }
    }
    _performAtMentionSearch(root, '');
  }

  void _handleAtMentionBreadcrumbTap(int depth) {
    final root = widget.projectRoot;
    if (root == null) return;
    final previousDirectory = _atMentionCurrentDirectory;
    if (depth < 0) {
      // 返回项目根目录。
      setState(() {
        _atMentionRestoreSelectionRelativePath = previousDirectory.isEmpty
            ? null
            : previousDirectory;
        _atMentionCurrentDirectory = '';
        _atMentionBreadcrumbs = const [];
      });
    } else {
      final newBreadcrumbs = _atMentionBreadcrumbs.sublist(0, depth + 1);
      setState(() {
        _atMentionRestoreSelectionRelativePath = previousDirectory.isEmpty
            ? null
            : previousDirectory;
        _atMentionCurrentDirectory = p.joinAll(newBreadcrumbs);
        _atMentionBreadcrumbs = newBreadcrumbs;
      });
    }
    _performAtMentionSearch(root, '');
  }

  // 斜杠技能选择器。

  /// 解析光标位于首个 `/token` 内的斜杠触发器。
  ({int triggerOffset, int tokenEnd, String query})? _computeSlashTrigger() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    if (text.isEmpty || text.codeUnitAt(0) != 0x2F /* '/' */ ) return null;
    var tokenEnd = text.length;
    for (var i = 0; i < text.length; i++) {
      final ch = text.codeUnitAt(i);
      if (isAsciiWhitespaceCodeUnit(ch)) {
        tokenEnd = i;
        break;
      }
    }
    final cursor = selection.baseOffset.clamp(0, text.length);
    if (cursor > tokenEnd) return null;
    final query = text.substring(1, tokenEnd);
    if (_shouldSuppressSlashSkillPickerQuery(query)) {
      return null;
    }
    return (triggerOffset: 0, tokenEnd: tokenEnd, query: query);
  }

  void _handleTextChangedForSlashSkill() {
    if (_atMentionSuppressListener) return;
    if (_selectedSkill != null) {
      _dismissSkillPickerOverlay(remember: false);
      return;
    }
    final trigger = _computeSlashTrigger();
    if (trigger == null) {
      if (_slashTriggerOffset >= 0) {
        _slashDismissal =
            _readSlashDismissalAtOffset(_slashTriggerOffset) ?? _slashDismissal;
      }
      _dismissSkillPickerOverlay(remember: false);
      _pruneSlashDismissal();
      return;
    }
    if (_slashDismissalSuppresses(trigger.triggerOffset)) {
      _dismissSkillPickerOverlay(remember: false);
      return;
    }
    _slashDismissal = null;
    _slashTriggerOffset = trigger.triggerOffset;
    _performSkillPickerSearch(trigger.query);
  }

  void _performSkillPickerSearch(String query) {
    if (!mounted) return;
    final skills = _readSkillsListSafe();
    final trimmed = query.trim().toLowerCase();
    final matches = trimmed.isEmpty
        ? skills
        : skills.where((skill) {
            final haystack = '${skill.name} ${skill.description}'.toLowerCase();
            return haystack.contains(trimmed);
          }).toList();
    setState(() {
      _skillPickerResults = matches;
      _skillPickerSelectedIndex = 0;
      _skillPickerLoading = false;
    });
    _showSkillPickerOverlay();
  }

  List<LocalSkill> _readSkillsListSafe() {
    try {
      final controller = Provider.of<SkillsController>(context, listen: false);
      return controller.skills;
    } catch (_) {
      return const <LocalSkill>[];
    }
  }

  void _showSkillPickerOverlay() {
    final animationSettings = _resolveMenuAnimationSettings();
    _skillPickerOverlay.show(
      overlay: Overlay.of(context, rootOverlay: true),
      builder: (context, visibility, onExitCompleted) {
        return _SkillPickerOverlayPanel(
          link: _skillPickerLayerLink,
          anchorKey: _skillPickerAnchorKey,
          items: _skillPickerResults,
          selectedIndex: _skillPickerSelectedIndex,
          loading: _skillPickerLoading,
          onSelect: _handleSkillPickerSelect,
          onDismiss: _userDismissSkillPickerOverlay,
          visible: visibility,
          animationSettings: animationSettings,
          onExitComplete: onExitCompleted,
        );
      },
    );
  }

  void _userDismissSkillPickerOverlay() {
    _dismissSkillPickerOverlay(remember: true);
  }

  void _dismissSkillPickerOverlay({required bool remember}) {
    if (remember) {
      final trigger = _computeSlashTrigger();
      if (trigger != null) {
        _slashDismissal =
            _readSlashDismissalAtOffset(trigger.triggerOffset) ??
            _ComposerTriggerDismissal(
              offset: trigger.triggerOffset,
              query: trigger.query,
            );
      } else if (_slashTriggerOffset >= 0) {
        _slashDismissal =
            _readSlashDismissalAtOffset(_slashTriggerOffset) ?? _slashDismissal;
      }
    }
    _skillPickerOverlay.close(immediately: !mounted);
    _skillPickerResults = const <LocalSkill>[];
    _skillPickerSelectedIndex = 0;
    _skillPickerLoading = false;
    _slashTriggerOffset = -1;
  }

  Future<void> _handleSkillPickerSelect(LocalSkill skill) async {
    final trigger = _computeSlashTrigger();
    if (trigger != null) {
      _atMentionSuppressListener = true;
      try {
        final text = widget.controller.text;
        final remainderStart =
            trigger.tokenEnd < text.length &&
                (text.codeUnitAt(trigger.tokenEnd) == 0x20 ||
                    text.codeUnitAt(trigger.tokenEnd) == 0x09)
            ? trigger.tokenEnd + 1
            : trigger.tokenEnd;
        final newText = text.substring(remainderStart);
        // 合并为单次 value 写入，避免与 IME 之间产生
        // selection 越界。
        widget.controller.value = TextEditingValue(
          text: newText,
          selection: const TextSelection.collapsed(offset: 0),
        );
      } finally {
        _atMentionSuppressListener = false;
      }
    }
    _dismissSkillPickerOverlay(remember: false);
    _slashDismissal = null;
    String? manifestContent;
    try {
      final controller = Provider.of<SkillsController>(context, listen: false);
      manifestContent = await controller.readSkillManifest(skill);
    } catch (_) {
      manifestContent = null;
    }
    if (!mounted) return;
    setState(() {
      _selectedSkill = skill;
      _selectedSkillManifest = manifestContent;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.focusNode.requestFocus();
    });
  }

  void _clearSelectedSkill() {
    if (_selectedSkill == null && _selectedSkillManifest == null) return;
    setState(() {
      _selectedSkill = null;
      _selectedSkillManifest = null;
    });
  }

  void _moveAtMentionSelection(int delta) {
    if (!_atMentionOverlay.hasEntry) return;
    final total = _atMentionResults.length;
    if (total == 0) return;
    final next = (_atMentionSelectedIndex + delta) % total;
    setState(() {
      _atMentionSelectedIndex = next < 0 ? next + total : next;
    });
    _atMentionOverlay.markNeedsBuild();
  }

  bool _commitAtMentionSelection() {
    if (!_atMentionOverlay.hasEntry) return false;
    if (_atMentionLoading) return false;
    if (_atMentionResults.isEmpty) return false;
    final index = _atMentionSelectedIndex;
    if (index < 0 || index >= _atMentionResults.length) return false;
    _handleAtMentionSelect(_atMentionResults[index]);
    return true;
  }

  bool _openSelectedAtMentionDirectory() {
    if (!_atMentionOverlay.hasEntry) return false;
    if (_atMentionLoading) return false;
    if (_atMentionResults.isEmpty) return false;
    final index = _atMentionSelectedIndex;
    if (index < 0 || index >= _atMentionResults.length) return false;
    final item = _atMentionResults[index];
    if (!item.isDirectory) return false;
    _handleAtMentionDrillDown(item);
    return true;
  }

  bool _navigateAtMentionToParentDirectory() {
    if (!_atMentionOverlay.hasEntry) return false;
    if (_atMentionLoading) return false;
    if (_atMentionCurrentDirectory.isEmpty) return false;
    _handleAtMentionBreadcrumbTap(_atMentionBreadcrumbs.length - 2);
    return true;
  }

  /// 循环移动技能选择器高亮项。
  void _moveSkillPickerSelection(int delta) {
    if (!_skillPickerOverlay.hasEntry) return;
    final total = _skillPickerResults.length;
    if (total == 0) return;
    final next = (_skillPickerSelectedIndex + delta) % total;
    setState(() {
      _skillPickerSelectedIndex = next < 0 ? next + total : next;
    });
    _skillPickerOverlay.markNeedsBuild();
  }

  /// 提交当前高亮技能，成功时返回 true 以消费按键事件。
  bool _commitSkillPickerSelection() {
    if (!_skillPickerOverlay.hasEntry) return false;
    if (_skillPickerLoading) return false;
    if (_skillPickerResults.isEmpty) return false;
    final index = _skillPickerSelectedIndex;
    if (index < 0 || index >= _skillPickerResults.length) return false;
    final skill = _skillPickerResults[index];
    // 选择处理器自行更新状态并加载技能说明。
    unawaited(_handleSkillPickerSelect(skill));
    return true;
  }

  /// 返回待发送技能的展示元数据，必须在消费技能提醒前读取。
  Map<String, Object?>? peekPendingSkillMetadata() {
    final skill = _selectedSkill;
    if (skill == null) return null;
    return <String, Object?>{
      'name': skill.name,
      'path': skill.manifestPath,
      'resource_id': skill.relativeDirectoryPath,
      if (skill.hasEmojiIcon) 'emoji': skill.emojiIcon,
      if (skill.hasIcon) 'icon_path': skill.iconPath,
      if (skill.hasIcon && skill.iconKind != null)
        'icon_kind': switch (skill.iconKind!) {
          LocalSkillIconKind.svg => 'svg',
          LocalSkillIconKind.raster => 'raster',
        },
    };
  }

  Future<void> restoreSelectedSkillFromMetadata(
    Map<String, Object?>? metadata,
  ) async {
    final skill = _skillFromSelectionMetadata(metadata);
    if (skill == null) {
      _clearSelectedSkill();
      return;
    }
    String? manifestContent;
    try {
      final controller = Provider.of<SkillsController>(context, listen: false);
      manifestContent = await controller.readSkillManifest(skill);
    } catch (_) {
      manifestContent = null;
    }
    if (!mounted) return;
    setState(() {
      _selectedSkill = skill;
      _selectedSkillManifest = manifestContent;
    });
  }

  LocalSkill? _skillFromSelectionMetadata(Map<String, Object?>? metadata) {
    if (metadata == null || metadata.isEmpty) return null;
    final name = '${metadata['name'] ?? ''}'.trim();
    final path = '${metadata['path'] ?? metadata['manifest_path'] ?? ''}'
        .trim();
    final relativePath =
        '${metadata['relative_directory_path'] ?? metadata['relative_path'] ?? ''}'
            .trim();
    final normalizedPath = path.isEmpty ? '' : p.normalize(path);
    final normalizedRelativePath = relativePath.isEmpty
        ? ''
        : p.normalize(relativePath);
    final skills = _readSkillsListSafe();
    for (final skill in skills) {
      if (normalizedPath.isNotEmpty &&
          (p.normalize(skill.manifestPath) == normalizedPath ||
              p.normalize(skill.directoryPath) == normalizedPath)) {
        return skill;
      }
      if (normalizedRelativePath.isNotEmpty &&
          p.normalize(skill.relativeDirectoryPath) == normalizedRelativePath) {
        return skill;
      }
      if (name.isNotEmpty && skill.name == name) {
        return skill;
      }
    }
    if (name.isEmpty) return null;
    final manifestPath = normalizedPath.endsWith('SKILL.md')
        ? normalizedPath
        : '';
    final directoryPath = manifestPath.isNotEmpty
        ? p.dirname(manifestPath)
        : normalizedPath;
    return LocalSkill(
      name: name,
      description: '',
      directoryPath: directoryPath,
      manifestPath: manifestPath,
      relativeDirectoryPath: normalizedRelativePath,
      emojiIcon: '${metadata['emoji'] ?? ''}'.trim().isEmpty
          ? null
          : '${metadata['emoji']}'.trim(),
    );
  }

  /// 消费当前技能并生成本轮隐藏提醒，不修改输入框与会话展示文本。
  String? consumePendingSkillReminder() {
    final skill = _selectedSkill;
    if (skill == null) return null;
    final reminder = buildLocalSkillSystemReminder(
      skill,
      manifestContent: _selectedSkillManifest,
    );
    _clearSelectedSkill();
    return reminder;
  }

  bool get hasPendingProjectFileReferences => _projectFileReferences.isNotEmpty;

  /// 将项目文件引用写入输入框并清空胶囊列表。
  void _injectReferencesIntoText() {
    if (_projectFileReferences.isEmpty) return;
    final refs = _projectFileReferences
        .map((r) {
          final suffix = r.isDirectory ? '/' : '';
          return '@${r.relativePath}$suffix';
        })
        .join(' ');
    _atMentionSuppressListener = true;
    try {
      final currentText = widget.controller.text;
      final merged = currentText.trim().isEmpty ? refs : '$refs\n$currentText';
      // 合并为单次 value 写入，避免与 IME 之间产生
      // selection 越界。
      widget.controller.value = TextEditingValue(
        text: merged,
        selection: TextSelection.collapsed(offset: merged.length),
      );
    } finally {
      _atMentionSuppressListener = false;
    }
    setState(() {
      _projectFileReferences = [];
    });
  }

  /// 将项目路径以 @path 注入文本，清空胶囊后发送。
  Future<void> _sendWithReferences() async {
    _injectReferencesIntoText();
    await widget.onSend();
  }

  bool _isModelSelectionLocked(SettingsController settings) {
    final session = widget.currentSession;
    return session != null &&
        widget.selectedModel != null &&
        isInputCacheModelSelectionLockedForSession(
          inputCacheEnabled: settings.aiInputCacheEnabled,
          session: session,
        );
  }

  void _showModelMenu(BuildContext btnContext) {
    final settings = context.read<SettingsController>();
    if (_isModelSelectionLocked(settings)) {
      showOpenHandInfoSnack(context, _inputCacheModelLockReason(context));
      return;
    }
    // 实时从 SettingsController 获取最新模型列表，确保增删模型后立即同步
    final settingsController = Provider.of<SettingsController?>(
      btnContext,
      listen: false,
    );
    final latestModels = settingsController?.aiModels ?? widget.availableModels;
    final latestRecent =
        settingsController?.recentModelSelections ??
        widget.recentModelSelections;
    showModelSearchSelector(
      context: btnContext,
      models: latestModels,
      recentSelections: latestRecent,
      selectedConfigId: widget.selectedModel?.id,
      selectedModelId: widget.selectedModel?.modelId,
    ).then((value) {
      if (!mounted || value == null) return;
      widget.onModelSelected(value.$1, value.$2);
    });
  }

  /// 使用当前提供商配置打开共享模型编辑弹窗。
  Future<void> _openSelectedModelEditor(BuildContext btnContext) async {
    final selected = widget.selectedModel;
    if (selected == null) {
      return;
    }
    await showAiModelEditorDialog(btnContext, initialModel: selected);
  }

  Future<void> _selectReasoningEffort(BuildContext btnContext) async {
    final settings = context.read<SettingsController>();
    if (_isModelSelectionLocked(settings)) {
      showOpenHandInfoSnack(context, _inputCacheModelLockReason(context));
      return;
    }
    final selected = widget.selectedModel;
    if (selected == null || !selected.resolvedReasoningEffortControlEnabled) {
      return;
    }
    final options = selected.resolvedReasoningEffortOptions
        .where((option) => option.isSelectable)
        .toList(growable: false);
    if (options.isEmpty) return;
    await showReasoningEffortSelector(
      context: context,
      anchorContext: btnContext,
      options: options,
      currentValue: selected.resolvedReasoningEffort,
      onChanged: (effort) async {
        if (!mounted) return false;
        final latestSettings = context.read<SettingsController>();
        if (_isModelSelectionLocked(latestSettings)) {
          showOpenHandInfoSnack(context, _inputCacheModelLockReason(context));
          return false;
        }
        var saved = false;
        try {
          saved = await context
              .read<SettingsController>()
              .updateAiModelReasoningEffort(
                selected.id,
                selected.modelId,
                effort,
              );
        } catch (_) {
          // 展示稳定错误，并让选择器回滚到已持久化值。
        }
        if (!mounted) return false;
        if (saved) return true;
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '推理强度保存失败，请检查当前模型配置。',
            en: 'Could not save the reasoning effort. Check this model configuration.',
          ),
        );
        return false;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final voiceSnapshot = widget.voiceConversationService.snapshot;
    final voiceActive = voiceSnapshot.active;
    final effectiveCollapsed = widget.isCollapsed && !voiceActive;
    final persistedModelId = widget.currentSession?.lastUsedModelLabel?.trim();
    final selectedModelUnavailable =
        widget.selectedModel == null && persistedModelId?.isNotEmpty == true;
    final selectedModelLabel =
        widget.selectedModel?.displayName ??
        (selectedModelUnavailable ? persistedModelId! : l10n.chatModelButton);
    final selectedModelReasoningEffortLabel = widget.selectedModel
        ?.reasoningEffortLabelForLocaleName(
          Localizations.localeOf(context).toLanguageTag(),
        );
    final selectedModelReasoningSupported =
        widget.selectedModel?.resolvedReasoningEffortControlEnabled == true &&
        (widget.selectedModel?.resolvedReasoningEffortOptions.any(
              (option) => option.isSelectable,
            ) ??
            false);
    final selectedModelHasReasoningOptions =
        widget.selectedModel?.resolvedReasoningEffortOptions.any(
          (option) => option.isSelectable,
        ) ??
        false;
    final selectedModelReasoningButtonLabel = widget.selectedModel == null
        ? openHandLocalizedText(
            context,
            zh: '推理不可用',
            en: 'Reasoning unavailable',
          )
        : selectedModelReasoningSupported
        ? (selectedModelReasoningEffortLabel ??
              openHandLocalizedText(context, zh: '推理强度', en: 'Reasoning'))
        : selectedModelHasReasoningOptions
        ? openHandLocalizedText(context, zh: '推理未启用', en: 'Reasoning disabled')
        : openHandLocalizedText(
            context,
            zh: '不支持推理',
            en: 'No reasoning control',
          );
    final isCompressing = widget.sendPhase == AiSendPhase.compressing;
    final isSendingMessage = widget.sendPhase == AiSendPhase.sendingMessage;
    final isResponding = widget.sendPhase == AiSendPhase.responding;
    final isBusy = widget.sendPhase != AiSendPhase.idle;
    final settings = context.watch<SettingsController>();
    final voiceAvailability = _composerVoiceAvailability(
      settings.offlineSpeechSettings,
    );
    final voiceModeAvailable =
        widget.currentSession != null && voiceAvailability.available;
    final modelSelectionLocked = _isModelSelectionLocked(settings);
    final modelLockReason = _inputCacheModelLockReason(context);
    final canStopSending = widget.canStopSending;
    final activeGoal = widget.currentSession?.activeGoal;
    final hasActiveGoal = activeGoal?.isActive == true;
    final voiceModeActionEnabled =
        voiceModeAvailable && !isBusy && !hasActiveGoal;
    final voiceModeUnavailableReason = widget.currentSession == null
        ? openHandLocalizedText(
            context,
            zh: '请先创建或打开一个会话。',
            en: 'Create or open a conversation first.',
          )
        : !voiceAvailability.available
        ? voiceAvailability.reason
        : hasActiveGoal
        ? openHandLocalizedText(
            context,
            zh: '请先暂停或结束当前目标。',
            en: 'Pause or finish the active goal first.',
          )
        : openHandLocalizedText(
            context,
            zh: '请等待当前回复完成。',
            en: 'Wait for the current response to finish.',
          );
    final showGoalControls =
        hasActiveGoal && !widget.goalControls.suppressedForQueue;
    final manualSendLockedByGoal = hasActiveGoal && !canStopSending;
    final modeToggleEnabled =
        widget.sendPhase == AiSendPhase.idle && !hasActiveGoal;
    final runtimeStatus = widget.currentSession == null
        ? null
        : _runtimeToolCatalogStatus(
            widget.currentSession!,
            livePreview: widget.liveRuntimeToolPreview,
          );
    final sendButtonLabel = canStopSending
        ? _homeComposerStopResponseLabel(context)
        : switch (widget.sendPhase) {
            AiSendPhase.compressing => openHandLocalizedText(
              context,
              zh: '消息压缩中',
              en: 'Compressing Messages',
            ),
            AiSendPhase.sendingMessage => l10n.chatSending,
            AiSendPhase.responding => _homeComposerStopResponseLabel(context),
            AiSendPhase.awaitingApproval => _homeAwaitingApprovalLabel(context),
            AiSendPhase.idle => l10n.composerSend,
          };

    final chipAnim = context
        .select<SettingsController, DialogAnimationSettings>(
          (c) => c.chipAnimationSettings,
        );
    final expandedContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedSkill != null) ...[
          AnimatedRemovableChip(
            key: ValueKey('skill:${_selectedSkill!.manifestPath}'),
            settings: chipAnim,
            collapseAxis: Axis.vertical,
            onRemove: _clearSelectedSkill,
            builder: (ctx, requestRemove) => _SelectedSkillChip(
              skill: _selectedSkill!,
              onRemoved: requestRemove,
            ),
          ),
          kOpenHandGap10,
        ],
        if (widget.editingMessageId != null) ...[
          AnimatedRemovableChip(
            key: ValueKey<String>('editing:${widget.editingMessageId}'),
            settings: chipAnim,
            collapseAxis: Axis.vertical,
            onRemove: () {
              widget.onCancelEditing();
            },
            builder: (ctx, requestRemove) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: kOpenHandPillBorderRadius,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: colorScheme.onSecondaryContainer,
                  ),
                  kOpenHandHGap8,
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '正在编辑历史消息',
                      en: 'Editing Previous Message',
                    ),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  kOpenHandHGap8,
                  InkWell(
                    onTap: requestRemove,
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          kOpenHandGap10,
        ],
        if (widget.queuedPanel.messages.isNotEmpty) ...[
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.queuedPanel.messages.length,
            itemBuilder: (context, index) {
              final msg = widget.queuedPanel.messages[index];
              final isFirst = index == 0;
              final isLast = index == widget.queuedPanel.messages.length - 1;
              final queueActionsLocked = widget.queuedPanel.guidanceInProgress;
              final actionBaseColor = Theme.of(
                context,
              ).colorScheme.onSurfaceVariant;
              Color actionColor(bool enabled) => enabled
                  ? actionBaseColor
                  : actionBaseColor.withValues(alpha: 0.3);
              return AnimatedRemovableChip(
                key: ValueKey<String>('queued:${msg.id}'),
                settings: chipAnim,
                collapseAxis: Axis.vertical,
                onRemove: () => widget.queuedPanel.onRemove(index),
                builder: (ctx, requestRemove) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: kOpenHandBorderRadius8,
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
                        kOpenHandHGap8,
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
                          kOpenHandHGap8,
                          Icon(
                            Icons.attach_file_rounded,
                            size: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          kOpenHandHGap2,
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
                        kOpenHandHGap4,
                        // 工具栏按钮使用统一按压反馈并遵循减少动效设置。
                        MicroPressFeedback(
                          enabled: !isFirst && !queueActionsLocked,
                          child: IconButton(
                            onPressed: isFirst || queueActionsLocked
                                ? null
                                : () => widget.queuedPanel.onMove(
                                    index,
                                    index - 1,
                                  ),
                            icon: Icon(
                              Icons.arrow_upward_rounded,
                              size: 14,
                              color: actionColor(
                                !isFirst && !queueActionsLocked,
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: openHandLocalizedText(
                              context,
                              zh: '上移',
                              en: 'Move up',
                            ),
                          ),
                        ),
                        kOpenHandHGap4,
                        MicroPressFeedback(
                          enabled: !isLast && !queueActionsLocked,
                          child: IconButton(
                            onPressed: isLast || queueActionsLocked
                                ? null
                                : () => widget.queuedPanel.onMove(
                                    index,
                                    index + 1,
                                  ),
                            icon: Icon(
                              Icons.arrow_downward_rounded,
                              size: 14,
                              color: actionColor(
                                !isLast && !queueActionsLocked,
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: openHandLocalizedText(
                              context,
                              zh: '下移',
                              en: 'Move down',
                            ),
                          ),
                        ),
                        kOpenHandHGap4,
                        MicroPressFeedback(
                          enabled: !queueActionsLocked,
                          child: IconButton(
                            onPressed: queueActionsLocked
                                ? null
                                : () async {
                                    final edited =
                                        await _showEditQueuedMessageDialog(
                                          context,
                                          msg.text,
                                        );
                                    if (edited != null &&
                                        edited.trim().isNotEmpty) {
                                      widget.queuedPanel.onEdit(index, edited);
                                    }
                                  },
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: actionColor(!queueActionsLocked),
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: openHandLocalizedText(
                              context,
                              zh: '编辑此等待消息',
                              en: 'Edit this queued message',
                            ),
                          ),
                        ),
                        kOpenHandHGap4,
                        MicroPressFeedback(
                          enabled: !queueActionsLocked,
                          child: IconButton(
                            onPressed: queueActionsLocked
                                ? null
                                : () => widget.queuedPanel.onGuide(index),
                            icon: Icon(
                              Icons.lightbulb_outline_rounded,
                              size: 14,
                              color: actionColor(!queueActionsLocked),
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: openHandLocalizedText(
                              context,
                              zh: '指导发送此等待消息',
                              en: 'Send this queued message as guidance',
                            ),
                          ),
                        ),
                        kOpenHandHGap4,
                        MicroPressFeedback(
                          enabled: !queueActionsLocked,
                          child: IconButton(
                            onPressed: queueActionsLocked
                                ? null
                                : requestRemove,
                            icon: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: actionColor(!queueActionsLocked),
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: openHandLocalizedText(
                              context,
                              zh: '删除此等待消息',
                              en: 'Remove this queued message',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          kOpenHandGap8,
        ],
        if (_projectFileReferences.isNotEmpty) ...[
          _ReorderableProjectReferenceWrap(
            references: _projectFileReferences,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                final list = List<_AtMentionItem>.from(_projectFileReferences);
                final item = list.removeAt(oldIndex);
                list.insert(
                  newIndex > oldIndex ? newIndex - 1 : newIndex,
                  item,
                );
                _projectFileReferences = list;
              });
            },
            onRemove: (path) {
              setState(() {
                _projectFileReferences = _projectFileReferences
                    .where((r) => r.path != path)
                    .toList();
              });
            },
          ),
          kOpenHandGap8,
        ],
        if (widget.attachments.drafts.isNotEmpty) ...[
          _ReorderableAttachmentWrap(
            attachments: widget.attachments.drafts,
            onReorder: widget.attachments.onReorder,
            onRemove: (filePath) => widget.attachments.onRemove(filePath),
            onTap: (draft) => _openComposerAttachment(context, draft),
          ),
          kOpenHandGap12,
        ],
        AnimatedSize(
          duration: openHandMotionDuration(context, kOpenHandMotion260),
          curve: kOpenHandEmphasizedCurve,
          child: AnimatedSwitcher(
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            reverseDuration: openHandMotionDuration(
              context,
              kOpenHandMotion180,
            ),
            switchInCurve: kOpenHandEntranceCurve,
            switchOutCurve: kOpenHandSwitchOutCurve,
            layoutBuilder: buildCollisionSafeAnimatedSwitcherLayout,
            child: voiceActive
                ? const SizedBox(
                    key: ValueKey<String>('voice-composer-input-hidden'),
                  )
                : SizedBox(
                    key: const ValueKey<String>('voice-composer-input'),
                    height: widget.composerHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CompositedTransformTarget(
                          key: _atMentionAnchorKey,
                          link: _atMentionLayerLink,
                          child: const SizedBox.expand(),
                        ),
                        CompositedTransformTarget(
                          key: _skillPickerAnchorKey,
                          link: _skillPickerLayerLink,
                          child: const SizedBox.expand(),
                        ),
                        // 在输入框层拦截全局快捷键，避免 macOS 文本编辑快捷键抢占 Ctrl+P。
                        _ComposerShortcutsHost(
                          bindings: context
                              .watch<SettingsController>()
                              .shortcutBindings,
                          child: TextField(
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            expands: true,
                            maxLines: null,
                            textInputAction: TextInputAction.newline,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: InputDecoration(
                              hintText: l10n.composerHint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );

    final voiceControls = AnimatedSwitcher(
      duration: openHandMotionDuration(context, kOpenHandMotion240),
      reverseDuration: openHandMotionDuration(context, kOpenHandMotion180),
      switchInCurve: kOpenHandEntranceCurve,
      switchOutCurve: kOpenHandSwitchOutCurve,
      layoutBuilder: buildCollisionSafeAnimatedSwitcherLayout,
      child: voiceActive
          ? Row(
              key: const ValueKey<String>('voice-controls-active'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _VoiceModeActionButton(
                  tooltip: voiceSnapshot.speakerMuted
                      ? openHandLocalizedText(
                          context,
                          zh: '恢复语音朗读',
                          en: 'Unmute spoken replies',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '静音语音朗读',
                          en: 'Mute spoken replies',
                        ),
                  icon: voiceSnapshot.speakerMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  active: !voiceSnapshot.speakerMuted,
                  onPressed: () => widget.voiceConversationService
                      .setSpeakerMuted(!voiceSnapshot.speakerMuted),
                ),
                kOpenHandHGap10,
                _VoiceModeActionButton(
                  tooltip: voiceSnapshot.microphoneEnabled
                      ? openHandLocalizedText(
                          context,
                          zh: '关闭麦克风',
                          en: 'Turn off microphone',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '开启麦克风',
                          en: 'Turn on microphone',
                        ),
                  icon: voiceSnapshot.microphoneEnabled
                      ? Icons.mic_rounded
                      : Icons.mic_off_rounded,
                  active: voiceSnapshot.microphoneEnabled,
                  onPressed: () => widget.voiceConversationService
                      .setMicrophoneEnabled(!voiceSnapshot.microphoneEnabled),
                ),
              ],
            )
          : _VoiceModeActionButton(
              key: const ValueKey<String>('voice-controls-inactive'),
              tooltip: voiceModeActionEnabled
                  ? openHandLocalizedText(
                      context,
                      zh: '开始语音沟通',
                      en: 'Start voice mode',
                    )
                  : voiceModeUnavailableReason,
              icon: Icons.graphic_eq_rounded,
              active: true,
              onPressed: voiceModeActionEnabled
                  ? widget.onStartVoiceConversation
                  : null,
            ),
    );

    final actionRow = Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Builder(
                  builder: (btnContext) {
                    final hasSelection = widget.selectedModel != null;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: modelSelectionLocked
                              ? modelLockReason
                              : selectedModelUnavailable
                              ? openHandLocalizedText(
                                  context,
                                  zh: '线程固定模型配置已不可用，请重新选择模型',
                                  en: 'The model fixed to this thread is unavailable. Select another model.',
                                )
                              : selectedModelLabel,
                          child: OutlinedButton(
                            onPressed:
                                widget.availableModels.isEmpty ||
                                    modelSelectionLocked
                                ? null
                                : () => _showModelMenu(btnContext),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 52),
                              padding: const EdgeInsetsDirectional.only(
                                start: 16,
                                end: 12,
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadiusDirectional.horizontal(
                                      start: Radius.circular(26),
                                    ),
                              ),
                            ),
                            child: Text(
                              selectedModelLabel,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Tooltip(
                          message: modelSelectionLocked
                              ? modelLockReason
                              : selectedModelReasoningSupported
                              ? openHandLocalizedText(
                                  context,
                                  zh: '调整当前模型的推理强度',
                                  en: 'Adjust reasoning effort for this model',
                                )
                              : openHandLocalizedText(
                                  context,
                                  zh: '当前模型未启用或不支持推理强度控制',
                                  en: 'Reasoning effort control is disabled or unsupported',
                                ),
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed:
                                  selectedModelReasoningSupported &&
                                      !modelSelectionLocked
                                  ? () => unawaited(
                                      _selectReasoningEffort(btnContext),
                                    )
                                  : null,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 52),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                shape: const RoundedRectangleBorder(),
                              ),
                              child: AnimatedSwitcher(
                                duration: openHandMotionDuration(
                                  context,
                                  kOpenHandMotion220,
                                ),
                                switchInCurve: kOpenHandEntranceCurve,
                                switchOutCurve: kOpenHandSwitchOutCurve,
                                layoutBuilder:
                                    buildCollisionSafeAnimatedSwitcherLayout,
                                child: Text(
                                  selectedModelReasoningButtonLabel,
                                  key: ValueKey<String>(
                                    selectedModelReasoningButtonLabel,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 快速编辑当前模型，复用设置页的模型编辑弹窗。
                        Tooltip(
                          message: openHandLocalizedText(
                            context,
                            zh: '编辑当前模型配置',
                            en: 'Edit selected model configuration',
                          ),
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton(
                              onPressed: hasSelection
                                  ? () => unawaited(
                                      _openSelectedModelEditor(btnContext),
                                    )
                                  : null,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(40, 52),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                shape: const RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadiusDirectional.horizontal(
                                        end: Radius.circular(26),
                                      ),
                                ),
                              ),
                              child: const Icon(Icons.tune_rounded, size: 18),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(width: _composerActionControlGap),
                _ComposerFullAccessModeButton(
                  fullAccess: widget.fullAccessPermission,
                  enabled: true,
                  onChanged: (bool value) {
                    if (value != widget.fullAccessPermission) {
                      widget.onToggleFullAccessPermission(value);
                    }
                  },
                ),
                const SizedBox(width: _composerActionControlGap),
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
                    availableModes: <AiSessionMode>[
                      AiSessionMode.chat,
                      AiSessionMode.plan,
                      if (widget.goalControls.available) AiSessionMode.goal,
                    ],
                    onChanged: widget.onSessionModeChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: _composerActionControlGap),
        // 紧凑附件选择按钮，与右侧创作模式按钮形成对称。
        Tooltip(
          message: widget.attachments.enabled
              ? openHandLocalizedText(
                  context,
                  zh: '添加附件（最多 $aiMessageAttachmentLimit 个，单文件 ≤10MB；支持图片、文本、代码、表格和 PDF）',
                  en: 'Add attachments (up to $aiMessageAttachmentLimit, ≤10MB each; images, text, code, spreadsheets, PDF)',
                )
              : openHandLocalizedText(
                  context,
                  zh: '当前模型不支持附件',
                  zhHant: '目前模型不支援附件',
                  en: 'The selected model does not support attachments',
                  fr: 'Le modèle sélectionné ne prend pas en charge les pièces jointes',
                  de: 'Das ausgewählte Modell unterstützt keine Anhänge',
                  ja: '選択中のモデルは添付ファイルに対応していません',
                ),
          child: SizedBox(
            width: _composerActionControlHeight,
            height: _composerActionControlHeight,
            child: FilledButton(
              onPressed: widget.attachments.enabled
                  ? () => unawaited(widget.attachments.onPick())
                  : null,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(
                  _composerActionControlHeight,
                  _composerActionControlHeight,
                ),
                backgroundColor: widget.attachments.enabled
                    ? colorScheme.surfaceContainerHighest
                    : colorScheme.surfaceContainerHigh,
                foregroundColor: widget.attachments.enabled
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: const Icon(Icons.add_rounded),
            ),
          ),
        ),
        kOpenHandHGap10,
        Tooltip(
          message: openHandLocalizedText(
            context,
            zh: voiceActive
                ? '语音沟通期间保持展开'
                : widget.isCollapsed
                ? '展开输入框'
                : '折叠输入框',
            en: voiceActive
                ? 'Composer stays expanded in voice mode'
                : widget.isCollapsed
                ? 'Expand Composer'
                : 'Collapse Composer',
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: FilledButton(
              onPressed: voiceActive
                  ? null
                  : () => widget.onCollapsedChanged(!widget.isCollapsed),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(52, 52),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: AnimatedRotation(
                turns: widget.isCollapsed ? 0.5 : 0,
                duration: openHandMotionDuration(context, kOpenHandMotion220),
                curve: kOpenHandSwitchInCurve,
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
          ),
        ),
        kOpenHandHGap10,
        Tooltip(
          message: openHandLocalizedText(
            context,
            zh: !widget.autoFollowEnabled
                ? '开启自动滚动'
                : (widget.autoFollowPaused
                      ? '自动滚动已暂停（已上滑）· 点击恢复并跳至最新'
                      : '关闭自动滚动'),
            en: !widget.autoFollowEnabled
                ? 'Enable Auto Follow'
                : (widget.autoFollowPaused
                      ? 'Auto Follow paused (scrolled up) · tap to resume & jump to latest'
                      : 'Disable Auto Follow'),
          ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: FilledButton(
              onPressed: widget.onToggleAutoFollow,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(52, 52),
                backgroundColor: !widget.autoFollowEnabled
                    ? colorScheme.surfaceContainerHighest
                    : (widget.autoFollowPaused
                          ? colorScheme.primaryContainer
                          : colorScheme.primary),
                foregroundColor: !widget.autoFollowEnabled
                    ? colorScheme.onSurfaceVariant
                    : (widget.autoFollowPaused
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onPrimary),
                side: !widget.autoFollowEnabled
                    ? BorderSide(color: colorScheme.outlineVariant)
                    : (widget.autoFollowPaused
                          ? BorderSide(color: colorScheme.primary)
                          : null),
              ),
              child: Icon(
                !widget.autoFollowEnabled
                    ? Icons.vertical_align_bottom_outlined
                    : (widget.autoFollowPaused
                          ? Icons.arrow_downward_rounded
                          : Icons.vertical_align_bottom_rounded),
              ),
            ),
          ),
        ),
        kOpenHandHGap10,
        _ComposerCreationModeButton(
          creationMode: widget.creationMode,
          onCreationModeChanged: widget.onCreationModeChanged,
        ),
        // LayoutBuilder 内仅使用绘制层淡入淡出，避免逐帧重建触发布局断言。
        AnimatedSwitcher(
          duration: openHandMotionDuration(context, kOpenHandMotion240),
          child:
              widget.creationMode != _CreationMode.none &&
                  widget.onEditOptionsRequested != null
              ? Padding(
                  key: ValueKey<String>(
                    'creation-options-${widget.creationMode.name}',
                  ),
                  padding: const EdgeInsets.only(left: 6),
                  child: _ComposerCreationOptionsChip(
                    mode: widget.creationMode,
                    options: widget.creationOptions,
                    onTap: widget.onEditOptionsRequested!,
                  ),
                )
              : const SizedBox(key: ValueKey<String>('creation-options-off')),
        ),
        if (!showGoalControls) ...[kOpenHandHGap10, voiceControls],
        kOpenHandHGap10,
        if (showGoalControls)
          SizedBox(
            height: 52,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: activeGoal?.isPaused == true
                      ? () => unawaited(widget.goalControls.onResume())
                      : () => unawaited(widget.goalControls.onPause()),
                  icon: Icon(
                    activeGoal?.isPaused == true
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                  label: Text(
                    activeGoal?.isPaused == true
                        ? openHandLocalizedText(
                            context,
                            zh: '继续目标',
                            en: 'Resume Goal',
                          )
                        : openHandLocalizedText(
                            context,
                            zh: '暂停目标',
                            en: 'Pause Goal',
                          ),
                  ),
                ),
                kOpenHandHGap8,
                FilledButton.icon(
                  onPressed: () => unawaited(widget.goalControls.onTerminate()),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                  ),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '终止目标',
                      en: 'Terminate Goal',
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (voiceActive)
          Tooltip(
            message: openHandLocalizedText(
              context,
              zh: '结束语音沟通',
              en: 'End voice mode',
            ),
            child: SizedBox(
              width: 52,
              height: 52,
              child: FilledButton(
                onPressed: widget.onStopVoiceConversation,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(52, 52),
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
                child: const Icon(Icons.stop_rounded),
              ),
            ),
          )
        else
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: widget.controller,
            builder: (context, textValue, _) {
              final hasUserTextOrAttachments =
                  textValue.text.trim().isNotEmpty ||
                  widget.attachments.drafts.isNotEmpty ||
                  _projectFileReferences.isNotEmpty;
              final isQueueingAction = isBusy && hasUserTextOrAttachments;

              return SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: isQueueingAction
                      ? () => _sendWithReferences()
                      : canStopSending && !hasUserTextOrAttachments
                      ? () => widget.onStop()
                      : isBusy || manualSendLockedByGoal
                      ? null
                      : () => _sendWithReferences(),
                  icon: isQueueingAction
                      ? const Icon(Icons.queue_play_next_rounded)
                      : canStopSending && !hasUserTextOrAttachments
                      ? const Icon(Icons.stop_rounded)
                      : OpenHandBusyStatusIcon(
                          busy: isCompressing || isSendingMessage,
                          icon: isResponding
                              ? Icons.stop_rounded
                              : Icons.arrow_upward_rounded,
                          strokeWidth: 2.4,
                        ),
                  label: Text(
                    isQueueingAction
                        ? openHandLocalizedText(
                            context,
                            zh: '提前发送',
                            en: 'Queue Message',
                          )
                        : canStopSending && !hasUserTextOrAttachments
                        ? openHandLocalizedText(
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
        duration: openHandMotionDuration(context, kOpenHandMotion260),
        curve: kOpenHandEmphasizedCurve,
        padding: EdgeInsets.fromLTRB(18, 14, 18, effectiveCollapsed ? 10 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OpenHandCollapsibleFade(
              collapsed: effectiveCollapsed,
              child: expandedContent,
            ),
            AnimatedContainer(
              duration: openHandMotionDuration(context, kOpenHandMotion260),
              curve: kOpenHandEmphasizedCurve,
              height: effectiveCollapsed ? 0 : 14,
            ),
            actionRow,
          ],
        ),
      ),
    );
  }
}

class _VoiceTeleprompter extends StatelessWidget {
  const _VoiceTeleprompter({required this.snapshot, required this.onForceSend});

  final AiVoiceConversationSnapshot snapshot;
  final Future<void> Function() onForceSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final current = snapshot.currentTranscript.trim();
    final previous = snapshot.previousTranscript.trim();
    final status = switch (snapshot.phase) {
      AiVoiceConversationPhase.starting => openHandLocalizedText(
        context,
        zh: '正在启动本地语音服务…',
        en: 'Starting local voice services…',
      ),
      AiVoiceConversationPhase.recognizing => openHandLocalizedText(
        context,
        zh: '正在识别…',
        en: 'Recognizing…',
      ),
      AiVoiceConversationPhase.polishing => openHandLocalizedText(
        context,
        zh: '正在润色…',
        en: 'Polishing…',
      ),
      AiVoiceConversationPhase.speaking => openHandLocalizedText(
        context,
        zh: '正在朗读回复',
        en: 'Speaking reply',
      ),
      AiVoiceConversationPhase.failed => openHandLocalizedText(
        context,
        zh: '语音沟通异常',
        en: 'Voice mode error',
      ),
      AiVoiceConversationPhase.idle || AiVoiceConversationPhase.listening =>
        snapshot.microphoneEnabled
            ? openHandLocalizedText(context, zh: '正在聆听', en: 'Listening')
            : openHandLocalizedText(
                context,
                zh: '麦克风已关闭',
                en: 'Microphone off',
              ),
    };

    return AnimatedSize(
      duration: openHandMotionDuration(context, kOpenHandMotion260),
      curve: kOpenHandEmphasizedCurve,
      child: AnimatedSwitcher(
        duration: openHandMotionDuration(context, kOpenHandMotion220),
        reverseDuration: openHandMotionDuration(context, kOpenHandMotion180),
        switchInCurve: kOpenHandEntranceCurve,
        switchOutCurve: kOpenHandSwitchOutCurve,
        layoutBuilder: buildCollisionSafeAnimatedSwitcherLayout,
        child: !snapshot.active
            ? const SizedBox(key: ValueKey<String>('voice-teleprompter-hidden'))
            : Semantics(
                key: const ValueKey<String>('voice-teleprompter-visible'),
                liveRegion: true,
                label: '$status $current',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: kOpenHandBorderRadius16,
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.72),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          height: 34,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: snapshot.microphoneEnabled
                                    ? (snapshot.inputLevel * 14).clamp(0.06, 1)
                                    : 0,
                                strokeWidth: 3,
                                color:
                                    snapshot.phase ==
                                        AiVoiceConversationPhase.failed
                                    ? colors.error
                                    : colors.primary,
                                backgroundColor: colors.surfaceContainerHigh,
                              ),
                              Icon(
                                snapshot.microphoneEnabled
                                    ? Icons.mic_rounded
                                    : Icons.mic_off_rounded,
                                size: 17,
                                color: colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                        kOpenHandHGap12,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    status,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: colors.primary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  if (snapshot.message case final message?) ...[
                                    kOpenHandHGap8,
                                    Expanded(
                                      child: Text(
                                        message,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (previous.isNotEmpty) ...[
                                kOpenHandGap4,
                                Text(
                                  previous,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant.withValues(
                                      alpha: 0.48,
                                    ),
                                    shadows: <Shadow>[
                                      Shadow(
                                        color: colors.shadow.withValues(
                                          alpha: 0.12,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              kOpenHandGap4,
                              AnimatedSwitcher(
                                duration: openHandMotionDuration(
                                  context,
                                  kOpenHandMotion180,
                                ),
                                layoutBuilder:
                                    buildCollisionSafeAnimatedSwitcherLayout,
                                child: Text(
                                  current.isEmpty
                                      ? openHandLocalizedText(
                                          context,
                                          zh: '请开始说话…',
                                          en: 'Start speaking…',
                                        )
                                      : current,
                                  key: ValueKey<String>(current),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: current.isEmpty
                                        ? colors.onSurfaceVariant
                                        : colors.onSurface,
                                    fontWeight: current.isEmpty
                                        ? FontWeight.w500
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        kOpenHandHGap8,
                        AnimatedSwitcher(
                          duration: openHandMotionDuration(
                            context,
                            kOpenHandMotion180,
                          ),
                          child: current.isEmpty
                              ? const SizedBox(
                                  key: ValueKey<String>(
                                    'voice-force-send-hidden',
                                  ),
                                )
                              : Tooltip(
                                  key: const ValueKey<String>(
                                    'voice-force-send-visible',
                                  ),
                                  message: openHandLocalizedText(
                                    context,
                                    zh: '立即发送识别文本',
                                    en: 'Send recognized text now',
                                  ),
                                  child: IconButton.filled(
                                    onPressed: () => unawaited(onForceSend()),
                                    icon: const Icon(
                                      Icons.arrow_upward_rounded,
                                      size: 18,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _VoiceModeActionButton extends StatelessWidget {
  const _VoiceModeActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function()? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 52,
        height: 52,
        child: FilledButton(
          onPressed: enabled ? () => unawaited(onPressed!()) : null,
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(52, 52),
            backgroundColor: active
                ? colors.primary
                : colors.surfaceContainerHighest,
            foregroundColor: active
                ? colors.onPrimary
                : colors.onSurfaceVariant,
            side: active ? null : BorderSide(color: colors.outlineVariant),
          ),
          child: Icon(icon),
        ),
      ),
    );
  }
}

class _ComposerFullAccessModeButton extends StatefulWidget {
  const _ComposerFullAccessModeButton({
    required this.fullAccess,
    required this.enabled,
    required this.onChanged,
  });

  final bool fullAccess;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  State<_ComposerFullAccessModeButton> createState() =>
      _ComposerFullAccessModeButtonState();
}

class _ComposerFullAccessModeButtonState
    extends State<_ComposerFullAccessModeButton> {
  void _showAccessMenu() {
    showAnimatedAnchoredPopupMenu<bool>(
      context: context,
      items: [
        PopupMenuItem<bool>(
          value: false,
          child: Row(
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 20),
              kOpenHandHGap12,
              Expanded(child: Text(_homeComposerDefaultAccessLabel(context))),
              if (!widget.fullAccess)
                const Icon(Icons.check_rounded, size: 20)
              else
                kOpenHandHGap20,
            ],
          ),
        ),
        PopupMenuItem<bool>(
          value: true,
          child: Row(
            children: [
              const Icon(Icons.gpp_maybe_outlined, size: 20),
              kOpenHandHGap12,
              Expanded(child: Text(_homeComposerFullAccessLabel(context))),
              if (widget.fullAccess)
                const Icon(Icons.check_rounded, size: 20)
              else
                kOpenHandHGap20,
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!mounted || value == null) return;
      widget.onChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final modeLabel = widget.fullAccess
        ? _homeComposerFullAccessLabel(context)
        : _homeComposerDefaultAccessLabel(context);
    final backgroundColor = !widget.enabled
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.78)
        : widget.fullAccess
        ? OpenHandConsolePalette.warning.withValues(alpha: 0.15)
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = !widget.enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : widget.fullAccess
        ? OpenHandStatusColors.warning
        : colorScheme.onSurfaceVariant;
    final borderColor = !widget.enabled
        ? colorScheme.outlineVariant.withValues(alpha: 0.48)
        : widget.fullAccess
        ? OpenHandStatusColors.warning.withValues(alpha: 0.5)
        : colorScheme.outlineVariant;

    return OutlinedButton(
      onPressed: widget.enabled ? _showAccessMenu : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        side: BorderSide(color: borderColor),
        shape: const RoundedRectangleBorder(
          borderRadius: kOpenHandBorderRadius16,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.fullAccess
                ? Icons.gpp_maybe_outlined
                : Icons.admin_panel_settings_outlined,
            size: 18,
            color: foregroundColor,
          ),
          kOpenHandHGap8,
          Text(
            modeLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          kOpenHandHGap4,
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: foregroundColor,
          ),
        ],
      ),
    );
  }
}

class _ComposerModeButton extends StatefulWidget {
  const _ComposerModeButton({
    required this.mode,
    required this.runtimeStatus,
    required this.enabled,
    required this.availableModes,
    required this.onChanged,
  });

  final AiSessionMode mode;
  final _RuntimeToolCatalogStatus? runtimeStatus;
  final bool enabled;
  final List<AiSessionMode> availableModes;
  final ValueChanged<AiSessionMode> onChanged;

  @override
  State<_ComposerModeButton> createState() => _ComposerModeButtonState();
}

class _ComposerModeButtonState extends State<_ComposerModeButton> {
  void _showModeMenu() {
    final modes = widget.availableModes.isEmpty
        ? <AiSessionMode>[AiSessionMode.chat]
        : widget.availableModes;

    showAnimatedAnchoredPopupMenu<AiSessionMode>(
      context: context,
      items: [
        for (final mode in modes)
          PopupMenuItem<AiSessionMode>(
            value: mode,
            child: Row(
              children: [
                Icon(
                  _runtimeModeIcon(widget.runtimeStatus, explicitMode: mode),
                  size: 20,
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Text(
                    _runtimeModeLabel(
                      context,
                      widget.runtimeStatus,
                      compact: true,
                      explicitMode: mode,
                    ),
                  ),
                ),
                if (mode == widget.mode)
                  const Icon(Icons.check_rounded, size: 20)
                else
                  kOpenHandHGap20,
              ],
            ),
          ),
      ],
    ).then((value) {
      if (!mounted || value == null || value == widget.mode) return;
      widget.onChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final modeIcon = _runtimeModeIcon(
      widget.runtimeStatus,
      explicitMode: widget.mode,
    );
    final modeLabel = _runtimeModeLabel(
      context,
      widget.runtimeStatus,
      compact: true,
      explicitMode: widget.mode,
    );
    final backgroundColor = !widget.enabled
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.78)
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = !widget.enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : colorScheme.onSurface;
    final accentColor = !widget.enabled
        ? colorScheme.onSurface.withValues(alpha: 0.28)
        : colorScheme.primary.withValues(alpha: 0.9);
    final borderColor = !widget.enabled
        ? colorScheme.outlineVariant.withValues(alpha: 0.48)
        : colorScheme.outlineVariant;
    return OutlinedButton(
      onPressed: widget.enabled ? _showModeMenu : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        side: BorderSide(color: borderColor),
        shape: const RoundedRectangleBorder(
          borderRadius: kOpenHandBorderRadius16,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            curve: kOpenHandSwitchInCurve,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.10),
              borderRadius: kOpenHandBorderRadius10,
            ),
            alignment: Alignment.center,
            // LayoutBuilder 内仅使用不会触发布局回调断言的淡入淡出。
            child: AnimatedSwitcher(
              duration: openHandMotionDuration(context, kOpenHandMotion180),
              child: Icon(
                modeIcon,
                key: ValueKey<String>('${widget.mode.storageValue}-$modeIcon'),
                size: 16,
                color: accentColor,
              ),
            ),
          ),
          kOpenHandHGap10,
          // LayoutBuilder 内不使用会逐帧改写布局的滑动过渡。
          AnimatedSwitcher(
            duration: openHandMotionDuration(context, kOpenHandMotion180),
            child: Text(
              modeLabel,
              key: ValueKey<String>('${widget.mode.storageValue}-$modeLabel'),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          kOpenHandHGap4,
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: foregroundColor,
          ),
        ],
      ),
    );
  }
}

enum _CreationMode { none, image, video, audio, deepResearch }

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
    _CreationMode.none => Icons.tune_rounded,
    _CreationMode.image => Icons.image_outlined,
    _CreationMode.video => Icons.videocam_outlined,
    _CreationMode.audio => Icons.audiotrack_outlined,
    _CreationMode.deepResearch => Icons.travel_explore_rounded,
  };

  /// 当前帧结束后通知模式变化，避免 MouseTracker 更新期间修改组件树。
  void _deferModeChange(_CreationMode mode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCreationModeChanged(mode);
    });
  }

  void _selectMode(_CreationMode mode) {
    if (mode == widget.creationMode) {
      _deferModeChange(_CreationMode.none);
      return;
    }
    if (mode == _CreationMode.deepResearch) {
      final label = switch (mode) {
        _CreationMode.deepResearch => openHandLocalizedText(
          context,
          zh: '深度研究功能暂不支持，敬请期待',
          en: 'Deep Research is not yet supported',
        ),
        _ => '',
      };
      if (label.isNotEmpty) {
        flashOpenHandSnack(
          context,
          label,
          duration: kOpenHandSnackBarBriefDuration,
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
    return Tooltip(
      message: openHandModeLabel(context),
      child: SizedBox(
        width: 52,
        height: 52,
        child: AnimatedContainer(
          duration: openHandMotionDuration(context, kOpenHandMotion340),
          curve: kOpenHandEmphasizedCurve,
          child: FilledButton(
            onPressed: () {
              if (isActive) {
                _deferModeChange(_CreationMode.none);
                return;
              }
              _showCreationMenu();
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
            // LayoutBuilder 子树仅使用安全的淡入淡出过渡。
            child: AnimatedSwitcher(
              duration: openHandMotionDuration(context, kOpenHandMotion220),
              child: Icon(
                _iconForMode(widget.creationMode),
                key: ValueKey<_CreationMode>(widget.creationMode),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCreationMenu() {
    final colorScheme = Theme.of(context).colorScheme;
    showAnimatedAnchoredPopupMenu<_CreationMode>(
      context: context,
      items: [
        PopupMenuItem<_CreationMode>(
          value: _CreationMode.image,
          child: Row(
            children: [
              Icon(
                Icons.image_outlined,
                size: 20,
                color: widget.creationMode == _CreationMode.image
                    ? colorScheme.primary
                    : null,
              ),
              kOpenHandHGap12,
              Expanded(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '创建图片',
                    en: 'Create Image',
                  ),
                ),
              ),
              if (widget.creationMode == _CreationMode.image)
                Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
            ],
          ),
        ),
        PopupMenuItem<_CreationMode>(
          value: _CreationMode.video,
          child: Row(
            children: [
              Icon(
                Icons.videocam_outlined,
                size: 20,
                color: widget.creationMode == _CreationMode.video
                    ? colorScheme.primary
                    : null,
              ),
              kOpenHandHGap12,
              Expanded(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '视频生成',
                    en: 'Generate Video',
                  ),
                ),
              ),
              if (widget.creationMode == _CreationMode.video)
                Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
            ],
          ),
        ),
        PopupMenuItem<_CreationMode>(
          value: _CreationMode.audio,
          child: Row(
            children: [
              Icon(
                Icons.audiotrack_outlined,
                size: 20,
                color: widget.creationMode == _CreationMode.audio
                    ? colorScheme.primary
                    : null,
              ),
              kOpenHandHGap12,
              Expanded(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '音频生成',
                    en: 'Generate Audio',
                  ),
                ),
              ),
              if (widget.creationMode == _CreationMode.audio)
                Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
            ],
          ),
        ),
        PopupMenuItem<_CreationMode>(
          value: _CreationMode.deepResearch,
          child: Row(
            children: [
              const Icon(Icons.travel_explore_rounded, size: 20),
              kOpenHandHGap12,
              Expanded(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '深度研究',
                    en: 'Deep Research',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!mounted || value == null) return;
      _selectMode(value);
    });
  }
}

/// 拖拽重排胶囊构建器。[interactive] 为假时用于拖拽影像与占位，不接交互。
typedef _ReorderableChipBuilder<T> =
    Widget Function(
      T item, {
      required VoidCallback onRemove,
      required bool interactive,
    });

/// 可拖拽重排的胶囊流式布局。
///
/// 附件胶囊与项目引用胶囊共用同一套拖拽接受、悬停高亮与移除动效；此前两处各写
/// 一份，差异只在圆角与光晕半径，收敛为下面几个尺寸参数。
class _ReorderableChipWrap<T> extends StatefulWidget {
  const _ReorderableChipWrap({
    required this.items,
    required this.spacing,
    required this.itemKey,
    required this.chipBuilder,
    required this.onRemoveItem,
    required this.onReorder,
    required this.feedbackRadius,
    required this.hoverRadius,
    required this.hoverGlowBlur,
  });

  final List<T> items;
  final double spacing;

  /// 胶囊的稳定标识，用于移除动效的 key。
  final String Function(T item) itemKey;
  final _ReorderableChipBuilder<T> chipBuilder;

  /// 移除动效播完后真正删除条目。
  final void Function(T item) onRemoveItem;
  final void Function(int oldIndex, int newIndex) onReorder;
  final double feedbackRadius;
  final double hoverRadius;
  final double hoverGlowBlur;

  @override
  State<_ReorderableChipWrap<T>> createState() =>
      _ReorderableChipWrapState<T>();
}

class _ReorderableChipWrapState<T> extends State<_ReorderableChipWrap<T>> {
  int? _dragIndex;
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    final chipAnim = context
        .select<SettingsController, DialogAnimationSettings>(
          (c) => c.chipAnimationSettings,
        );
    return Wrap(
      spacing: widget.spacing,
      runSpacing: widget.spacing,
      children: List.generate(widget.items.length, (index) {
        final item = widget.items[index];
        final isDragging = _dragIndex == index;
        final isHovering = _hoverIndex == index;
        Widget staticChip() =>
            widget.chipBuilder(item, onRemove: () {}, interactive: false);
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
                borderRadius: BorderRadius.circular(widget.feedbackRadius),
                child: Opacity(opacity: 0.85, child: staticChip()),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: staticChip()),
              child: AnimatedRemovableChip(
                key: ValueKey(widget.itemKey(item)),
                settings: chipAnim,
                onRemove: () => widget.onRemoveItem(item),
                builder: (context, requestRemove) {
                  // hover 反馈保持 1.02 scale + primary 柔和光晕与描边，点明
                  // “此处会被插入”；过渡统一 240ms easeOutCubic，reduceMotion
                  // 时由 shared motion preference 归零。
                  final cs = Theme.of(context).colorScheme;
                  return AnimatedContainer(
                    duration: openHandMotionDuration(
                      context,
                      kOpenHandMotion240,
                    ),
                    curve: kOpenHandSwitchInCurve,
                    transform: isHovering
                        ? (Matrix4.identity()
                            ..scaleByDouble(1.02, 1.02, 1.0, 1.0))
                        : Matrix4.identity(),
                    transformAlignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.hoverRadius),
                      border: Border.all(
                        width: isHovering ? 1.4 : 0,
                        color: isHovering
                            ? cs.primary.withValues(alpha: 0.55)
                            : Colors.transparent,
                      ),
                      boxShadow: isHovering
                          ? [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.18),
                                blurRadius: widget.hoverGlowBlur,
                                spreadRadius: 1,
                              ),
                            ]
                          : const [],
                    ),
                    child: Opacity(
                      opacity: isDragging ? 0.3 : 1.0,
                      child: widget.chipBuilder(
                        item,
                        onRemove: requestRemove,
                        interactive: true,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      }),
    );
  }
}

class _ReorderableAttachmentWrap extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return _ReorderableChipWrap<_ComposerAttachmentDraft>(
      items: attachments,
      spacing: 8,
      feedbackRadius: 16,
      hoverRadius: 18,
      hoverGlowBlur: 12,
      itemKey: (item) => 'attachment:${item.filePath}',
      onRemoveItem: (item) => onRemove(item.filePath),
      onReorder: onReorder,
      chipBuilder: (item, {required onRemove, required interactive}) =>
          _ComposerAttachmentChip(
            attachment: item,
            onRemove: onRemove,
            onTap: interactive ? () => onTap(item) : null,
          ),
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
    if (attachment.kind == AiAttachmentKind.image) {
      return _ComposerImageThumbChip(
        attachment: attachment,
        onTap: onTap,
        onRemove: onRemove,
      );
    }
    return OpenHandTapRegion(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: kOpenHandBorderRadius16,
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
            kOpenHandHGap8,
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                '${attachment.name} · ${formatByteSize(attachment.sizeBytes)}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            kOpenHandHGap8,
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
    );
  }
}

/// 图片附件方形缩略图胶囊，点击后复用消息气泡的图片预览。
class _ComposerImageThumbChip extends StatelessWidget {
  const _ComposerImageThumbChip({
    required this.attachment,
    required this.onTap,
    required this.onRemove,
  });

  final _ComposerAttachmentDraft attachment;
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const double size = 64;
    return Tooltip(
      message: '${attachment.name} · ${formatByteSize(attachment.sizeBytes)}',
      waitDuration: kOpenHandTooltipWait,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: OpenHandTapRegion(
                onTap: onTap,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: kOpenHandBorderRadius12,
                    border: Border.all(color: colorScheme.outlineVariant),
                    color: colorScheme.surfaceContainerHighest,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(
                    File(attachment.filePath),
                    fit: BoxFit.cover,
                    cacheWidth: 192,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 24,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: OpenHandTapRegion(
                onTap: onRemove,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: colorScheme.onSurface,
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

// 可排序、可移除的项目路径胶囊。

class _ReorderableProjectReferenceWrap extends StatelessWidget {
  const _ReorderableProjectReferenceWrap({
    required this.references,
    required this.onReorder,
    required this.onRemove,
  });

  final List<_AtMentionItem> references;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return _ReorderableChipWrap<_AtMentionItem>(
      items: references,
      spacing: 6,
      feedbackRadius: 14,
      hoverRadius: 16,
      hoverGlowBlur: 10,
      itemKey: (item) => 'projref:${item.path}',
      onRemoveItem: (item) => onRemove(item.path),
      onReorder: onReorder,
      chipBuilder: (item, {required onRemove, required interactive}) =>
          _ProjectReferenceChip(item: item, onRemove: onRemove),
    );
  }
}

class _ProjectReferenceChip extends StatelessWidget {
  const _ProjectReferenceChip({required this.item, required this.onRemove});

  final _AtMentionItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.isDirectory
                ? Icons.folder_rounded
                : _AtMentionOverlayPanelState._atMentionIcon(item),
            size: 14,
            color: colorScheme.primary,
          ),
          kOpenHandHGap5,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              item.isDirectory ? '${item.relativePath}/' : item.relativePath,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          kOpenHandHGap4,
          OpenHandTapRegion(
            onTap: onRemove,
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// @ 提及文件补全浮层。

class _AtMentionItem {
  const _AtMentionItem({
    required this.name,
    required this.path,
    required this.relativePath,
    required this.isDirectory,
  }) : kind = _AtMentionItemKind.projectEntry;

  const _AtMentionItem.localFileAction()
    : name = '选择本地文件',
      path = '__openhand_local_file_action__',
      relativePath = '',
      isDirectory = false,
      kind = _AtMentionItemKind.localFileAction;

  final String name;
  final String path;
  final String relativePath;
  final bool isDirectory;
  final _AtMentionItemKind kind;

  bool get isLocalFileAction => kind == _AtMentionItemKind.localFileAction;
}

enum _AtMentionItemKind { projectEntry, localFileAction }

class _ComposerOverlayLayout {
  const _ComposerOverlayLayout({
    required this.targetAnchor,
    required this.followerAnchor,
    required this.offset,
    required this.maxWidth,
    required this.maxHeight,
  });

  final Alignment targetAnchor;
  final Alignment followerAnchor;
  final Offset offset;
  final double maxWidth;
  final double maxHeight;
}

_ComposerOverlayLayout _resolveComposerOverlayLayout(
  BuildContext context,
  GlobalKey anchorKey, {
  required double preferredWidth,
  required double preferredHeight,
}) {
  final overlayBox = Overlay.maybeOf(
    context,
    rootOverlay: true,
  )?.context.findRenderObject();
  final anchorBox = anchorKey.currentContext?.findRenderObject();
  final fallbackSize = MediaQuery.sizeOf(context);
  final overlaySize = overlayBox is RenderBox && overlayBox.hasSize
      ? overlayBox.size
      : fallbackSize;
  final availableWidth = math.max(
    1.0,
    overlaySize.width - _composerOverlayViewportMargin * 2,
  );
  final fallbackWidth = math.min(preferredWidth, availableWidth);
  if (overlayBox is! RenderBox ||
      anchorBox is! RenderBox ||
      !overlayBox.hasSize ||
      !anchorBox.hasSize ||
      !anchorBox.attached) {
    return _ComposerOverlayLayout(
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      offset: const Offset(0, -_composerOverlayGap),
      maxWidth: fallbackWidth,
      maxHeight: math.max(
        1.0,
        math.min(
          preferredHeight,
          overlaySize.height - _composerOverlayViewportMargin * 2,
        ),
      ),
    );
  }

  final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  final anchorRect = topLeft & anchorBox.size;
  final maxWidth = math.min(preferredWidth, availableWidth);
  final spaceAbove = math.max(
    0.0,
    anchorRect.top - _composerOverlayGap - _composerOverlayViewportMargin,
  );
  final spaceBelow = math.max(
    0.0,
    overlaySize.height -
        anchorRect.bottom -
        _composerOverlayGap -
        _composerOverlayViewportMargin,
  );
  final preferredAboveThreshold = math.min(preferredHeight, 160.0);
  final placeAbove =
      spaceAbove >= preferredAboveThreshold || spaceAbove >= spaceBelow;
  final maxHeight = math.max(
    1.0,
    math.min(preferredHeight, placeAbove ? spaceAbove : spaceBelow),
  );
  final fitsFromLeft =
      anchorRect.left + maxWidth <=
      overlaySize.width - _composerOverlayViewportMargin;
  final fitsFromRight =
      anchorRect.right - maxWidth >= _composerOverlayViewportMargin;
  final alignRight =
      !fitsFromLeft &&
      (fitsFromRight || anchorRect.center.dx >= overlaySize.width / 2);
  const minLeft = _composerOverlayViewportMargin;
  final maxLeft = math.max(
    minLeft,
    overlaySize.width - _composerOverlayViewportMargin - maxWidth,
  );
  final horizontalOffset = alignRight
      ? anchorRect.right
                .clamp(minLeft + maxWidth, maxLeft + maxWidth)
                .toDouble() -
            anchorRect.right
      : anchorRect.left.clamp(minLeft, maxLeft).toDouble() - anchorRect.left;

  return _ComposerOverlayLayout(
    targetAnchor: placeAbove
        ? (alignRight ? Alignment.topRight : Alignment.topLeft)
        : (alignRight ? Alignment.bottomRight : Alignment.bottomLeft),
    followerAnchor: placeAbove
        ? (alignRight ? Alignment.bottomRight : Alignment.bottomLeft)
        : (alignRight ? Alignment.topRight : Alignment.topLeft),
    offset: Offset(
      horizontalOffset,
      placeAbove ? -_composerOverlayGap : _composerOverlayGap,
    ),
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );
}

void _scrollComposerOverlaySelectionIntoView({
  required ScrollController controller,
  required int selectedIndex,
  required double itemExtent,
}) {
  if (!controller.hasClients || selectedIndex < 0 || itemExtent <= 0) return;
  final position = controller.position;
  final target = selectedIndex * itemExtent;
  final viewportStart = controller.offset;
  final viewportEnd = viewportStart + position.viewportDimension;
  if (target < viewportStart) {
    controller.animateTo(
      target.clamp(0.0, position.maxScrollExtent),
      duration: kOpenHandMotion120,
      curve: kOpenHandSwitchInCurve,
    );
    return;
  }
  if (target + itemExtent <= viewportEnd) return;
  controller.animateTo(
    (target + itemExtent - position.viewportDimension).clamp(
      0.0,
      position.maxScrollExtent,
    ),
    duration: kOpenHandMotion120,
    curve: kOpenHandSwitchInCurve,
  );
}

class _AtMentionOverlayPanel extends StatefulWidget {
  const _AtMentionOverlayPanel({
    required this.link,
    required this.anchorKey,
    required this.items,
    required this.selectedIndex,
    required this.loading,
    required this.breadcrumbs,
    required this.mode,
    required this.attachmentsEnabled,
    required this.onSelect,
    required this.onDrillDown,
    required this.onBreadcrumbTap,
    required this.onDismiss,
    required this.visible,
    required this.animationSettings,
    required this.onExitComplete,
  });

  final LayerLink link;
  final GlobalKey anchorKey;
  final List<_AtMentionItem> items;
  final int selectedIndex;
  final bool loading;
  final List<String> breadcrumbs;
  final _AtMentionOverlayMode mode;
  final bool attachmentsEnabled;
  final void Function(_AtMentionItem item) onSelect;
  final void Function(_AtMentionItem item) onDrillDown;
  final void Function(int depth) onBreadcrumbTap;
  final VoidCallback onDismiss;
  final ValueListenable<bool> visible;
  final DialogAnimationSettings animationSettings;
  final VoidCallback onExitComplete;

  @override
  State<_AtMentionOverlayPanel> createState() => _AtMentionOverlayPanelState();
}

class _AtMentionOverlayPanelState extends State<_AtMentionOverlayPanel> {
  final ScrollController _listController = ScrollController();
  static const double _estimatedItemExtent = 50.0;

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AtMentionOverlayPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _scrollComposerOverlaySelectionIntoView(
        controller: _listController,
        selectedIndex: widget.selectedIndex,
        itemExtent: _estimatedItemExtent,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isLocalFileMode = widget.mode == _AtMentionOverlayMode.localFiles;
    final titleLabel = isLocalFileMode
        ? openHandLocalizedText(
            context,
            zh: '选择文件',
            zhHant: '選擇檔案',
            en: 'Select Files',
            fr: 'Sélectionner des fichiers',
            de: 'Dateien auswählen',
            ja: 'ファイルを選択',
          )
        : openHandLocalizedText(
            context,
            zh: '选择项目文件',
            zhHant: '選擇專案檔案',
            en: 'Select Project Files',
            fr: 'Sélectionner des fichiers du projet',
            de: 'Projektdateien auswählen',
            ja: 'プロジェクトファイルを選択',
          );

    final layout = _resolveComposerOverlayLayout(
      context,
      widget.anchorKey,
      preferredWidth: 460,
      preferredHeight: 340,
    );
    return OpenHandAnchoredAnimatedOverlay(
      link: widget.link,
      targetAnchor: layout.targetAnchor,
      followerAnchor: layout.followerAnchor,
      offset: layout.offset,
      constraints: BoxConstraints(
        maxWidth: layout.maxWidth,
        maxHeight: layout.maxHeight,
      ),
      onDismiss: widget.onDismiss,
      customSettings: widget.animationSettings,
      visibility: widget.visible,
      onExitCompleted: widget.onExitComplete,
      child: Material(
        elevation: 8,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.25),
        borderRadius: kOpenHandBorderRadius16,
        color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  Icon(
                    isLocalFileMode
                        ? Icons.attach_file_rounded
                        : Icons.folder_open_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  kOpenHandHGap8,
                  Text(
                    titleLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (!isLocalFileMode && widget.breadcrumbs.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AtMentionBreadcrumbChip(
                        label: openHandLocalizedText(
                          context,
                          zh: '项目根目录',
                          zhHant: '專案根目錄',
                          en: 'Project Root',
                          fr: 'Racine du projet',
                          de: 'Projektwurzel',
                          ja: 'プロジェクトルート',
                        ),
                        icon: Icons.home_rounded,
                        onTap: () => widget.onBreadcrumbTap(-1),
                      ),
                      for (var i = 0; i < widget.breadcrumbs.length; i++) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 14,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        _AtMentionBreadcrumbChip(
                          label: widget.breadcrumbs[i],
                          icon: Icons.folder_rounded,
                          onTap: () => widget.onBreadcrumbTap(i),
                          isLast: i == widget.breadcrumbs.length - 1,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (widget.loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (widget.items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: OpenHandInlineEmptyState(
                  message: isLocalFileMode && !widget.attachmentsEnabled
                      ? openHandLocalizedText(
                          context,
                          zh: '当前模型不支持附件',
                          zhHant: '目前模型不支援附件',
                          en: 'The selected model does not support attachments',
                          fr: 'Le modèle sélectionné ne prend pas en charge les pièces jointes',
                          de: 'Das ausgewählte Modell unterstützt keine Anhänge',
                          ja: '選択中のモデルは添付ファイルに対応していません',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '未找到匹配文件或目录',
                          zhHant: '找不到相符的檔案或目錄',
                          en: 'No matching files or directories',
                          fr: 'Aucun fichier ou dossier correspondant',
                          de: 'Keine passenden Dateien oder Ordner gefunden',
                          ja: '一致するファイルまたはディレクトリがありません',
                        ),
                  dense: true,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  controller: _listController,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: widget.items.length,
                  itemBuilder: (ctx, index) {
                    final item = widget.items[index];
                    final isSelected = index == widget.selectedIndex;
                    return Material(
                      color: isSelected
                          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onSelect(item),
                        borderRadius: kOpenHandBorderRadius8,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _atMentionIcon(item),
                                size: 18,
                                color: item.isDirectory
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                              kOpenHandHGap10,
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.isLocalFileAction
                                          ? openHandLocalizedText(
                                              context,
                                              zh: '选择本地文件',
                                              zhHant: '選擇本機檔案',
                                              en: 'Choose Local Files',
                                              fr: 'Choisir des fichiers locaux',
                                              de: 'Lokale Dateien auswählen',
                                              ja: 'ローカルファイルを選択',
                                            )
                                          : item.name,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      item.isLocalFileAction
                                          ? openHandLocalizedText(
                                              context,
                                              zh: '添加图片、文本、代码、表格或 PDF 附件',
                                              zhHant: '新增圖片、文字、程式碼、試算表或 PDF 附件',
                                              en: 'Add images, text, code, spreadsheets, or PDFs',
                                              fr: 'Ajouter des images, du texte, du code, des feuilles de calcul ou des PDF',
                                              de: 'Bilder, Text, Code, Tabellen oder PDFs anhängen',
                                              ja: '画像、テキスト、コード、表計算、PDF を添付',
                                            )
                                          : item.relativePath,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.55),
                                            fontSize: 10,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (item.isDirectory) ...[
                                kOpenHandHGap4,
                                Semantics(
                                  button: true,
                                  label: openHandLocalizedText(
                                    context,
                                    zh: '进入目录',
                                    zhHant: '進入目錄',
                                    en: 'Open directory',
                                    fr: 'Ouvrir le dossier',
                                    de: 'Ordner öffnen',
                                    ja: 'ディレクトリを開く',
                                  ),
                                  child: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => widget.onDrillDown(item),
                                      icon: Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _atMentionIcon(_AtMentionItem item) {
    if (item.isLocalFileAction) return Icons.attach_file_rounded;
    if (item.isDirectory) return Icons.folder_rounded;
    return openHandFileNameIcon(item.name);
  }
}

class _AtMentionBreadcrumbChip extends StatelessWidget {
  const _AtMentionBreadcrumbChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isLast = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isLast
          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: kOpenHandBorderRadius8,
      child: InkWell(
        onTap: onTap,
        borderRadius: kOpenHandBorderRadius8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: colorScheme.primary),
              kOpenHandHGap4,
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isLast
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  fontWeight: isLast ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 斜杠技能选择浮层。

class _SkillPickerOverlayPanel extends StatefulWidget {
  const _SkillPickerOverlayPanel({
    required this.link,
    required this.anchorKey,
    required this.items,
    required this.selectedIndex,
    required this.loading,
    required this.onSelect,
    required this.onDismiss,
    required this.visible,
    required this.animationSettings,
    required this.onExitComplete,
  });

  final LayerLink link;
  final GlobalKey anchorKey;
  final List<LocalSkill> items;
  final int selectedIndex;
  final bool loading;
  final ValueChanged<LocalSkill> onSelect;
  final VoidCallback onDismiss;
  final ValueListenable<bool> visible;
  final DialogAnimationSettings animationSettings;
  final VoidCallback onExitComplete;

  @override
  State<_SkillPickerOverlayPanel> createState() =>
      _SkillPickerOverlayPanelState();
}

class _SkillPickerOverlayPanelState extends State<_SkillPickerOverlayPanel> {
  final ScrollController _listController = ScrollController();
  // 单项估算高度需与列表项内边距同步，用于键盘选中项自动滚入视口。
  static const double _estimatedItemExtent = 54.0;

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SkillPickerOverlayPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _scrollComposerOverlaySelectionIntoView(
        controller: _listController,
        selectedIndex: widget.selectedIndex,
        itemExtent: _estimatedItemExtent,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final layout = _resolveComposerOverlayLayout(
      context,
      widget.anchorKey,
      preferredWidth: 480,
      preferredHeight: 360,
    );

    final panel = Material(
      elevation: 8,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.25),
      borderRadius: kOpenHandBorderRadius16,
      color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                Icon(
                  Icons.extension_rounded,
                  size: 14,
                  color: colorScheme.primary,
                ),
                kOpenHandHGap6,
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '选择一个技能',
                    zhHant: '選擇一個技能',
                    en: 'Select a skill',
                    fr: 'Sélectionner une compétence',
                    de: 'Skill auswählen',
                    ja: 'スキルを選択',
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          if (widget.loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (widget.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OpenHandInlineEmptyState(
                message: openHandLocalizedText(
                  context,
                  zh: '未找到匹配技能',
                  zhHant: '找不到相符技能',
                  en: 'No matching skills',
                  fr: 'Aucune compétence correspondante',
                  de: 'Keine passenden Skills',
                  ja: '一致するスキルがありません',
                ),
                dense: true,
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                controller: _listController,
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: widget.items.length,
                itemBuilder: (ctx, index) {
                  final item = widget.items[index];
                  final isSelected = index == widget.selectedIndex;
                  return Material(
                    color: isSelected
                        ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                        : Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onSelect(item),
                      borderRadius: kOpenHandBorderRadius8,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            _SkillPickerLeading(skill: item),
                            kOpenHandHGap10,
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (item.description.trim().isNotEmpty)
                                    Text(
                                      item.description,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.7),
                                            fontSize: 10,
                                          ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );

    return OpenHandAnchoredAnimatedOverlay(
      link: widget.link,
      targetAnchor: layout.targetAnchor,
      followerAnchor: layout.followerAnchor,
      offset: layout.offset,
      constraints: BoxConstraints(
        maxWidth: layout.maxWidth,
        maxHeight: layout.maxHeight,
      ),
      onDismiss: widget.onDismiss,
      customSettings: widget.animationSettings,
      visibility: widget.visible,
      onExitCompleted: widget.onExitComplete,
      child: panel,
    );
  }
}

class _SkillPickerLeading extends StatelessWidget {
  const _SkillPickerLeading({required this.skill});

  final LocalSkill skill;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (skill.hasEmojiIcon) {
      return SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: Text(skill.emojiIcon!, style: const TextStyle(fontSize: 18)),
        ),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: kOpenHandBorderRadius8,
      ),
      alignment: Alignment.center,
      child: Text(
        skill.initials,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// 用户通过斜杠选择技能后显示的可移除胶囊。
class _SelectedSkillChip extends StatelessWidget {
  const _SelectedSkillChip({required this.skill, required this.onRemoved});

  final LocalSkill skill;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: kOpenHandPillBorderRadius,
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (skill.hasEmojiIcon)
              Text(skill.emojiIcon!, style: const TextStyle(fontSize: 14))
            else
              Icon(
                Icons.extension_rounded,
                size: 14,
                color: colorScheme.onPrimaryContainer,
              ),
            kOpenHandHGap6,
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                skill.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            kOpenHandHGap6,
            Tooltip(
              message: openHandLocalizedText(
                context,
                zh: '移除此技能',
                zhHant: '移除此技能',
                en: 'Remove skill',
                fr: 'Retirer cette compétence',
                de: 'Skill entfernen',
                ja: 'このスキルを削除',
              ),
              child: InkWell(
                onTap: onRemoved,
                borderRadius: kOpenHandPillBorderRadius,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: colorScheme.onPrimaryContainer,
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
    final stat = await file.stat().timeout(defaultBoundedFileReadIdleTimeout);
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('附件路径不是普通文件。', path);
    }
    return _ComposerAttachmentDraft(
      filePath: path,
      name: p.basename(path),
      kind: aiAttachmentKindForPath(path),
      sizeBytes: stat.size,
    );
  }
}

class _AppendComposerAttachmentsResult {
  const _AppendComposerAttachmentsResult({
    this.added = 0,
    this.oversized = 0,
    this.unsupported = 0,
    this.unreadable = 0,
    this.limitSkipped = 0,
  });

  final int added;
  final int oversized;
  final int unsupported;
  final int unreadable;
  final int limitSkipped;

  bool get hasNotices =>
      oversized > 0 || unsupported > 0 || unreadable > 0 || limitSkipped > 0;
}

IconData _iconForAttachmentKind(AiAttachmentKind kind) {
  return switch (kind) {
    AiAttachmentKind.image => Icons.image_outlined,
    AiAttachmentKind.video => Icons.videocam_outlined,
    AiAttachmentKind.audio => Icons.audiotrack_outlined,
    AiAttachmentKind.text => Icons.description_outlined,
    AiAttachmentKind.spreadsheet => Icons.table_chart_outlined,
    AiAttachmentKind.pdf => Icons.picture_as_pdf_outlined,
    AiAttachmentKind.binary => Icons.insert_drive_file_outlined,
  };
}

/// 展示当前生成选项，点击可恢复纯文本模式。
class _ComposerCreationOptionsChip extends StatelessWidget {
  const _ComposerCreationOptionsChip({
    required this.mode,
    required this.options,
    required this.onTap,
  });

  final _CreationMode mode;
  final AiCreationOptions options;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratio = options.aspectRatio?.trim();
    final label = switch (mode) {
      _CreationMode.image =>
        ratio != null && ratio.isNotEmpty
            ? ratio
            : openHandLocalizedText(context, zh: '图像', en: 'IMG'),
      _CreationMode.video =>
        ratio != null && ratio.isNotEmpty
            ? ratio
            : openHandLocalizedText(context, zh: '视频', en: 'VID'),
      _CreationMode.audio =>
        options.durationSeconds != null
            ? '${options.durationSeconds}s'
            : openHandLocalizedText(context, zh: '音频', en: 'AUD'),
      _CreationMode.deepResearch => openHandLocalizedText(
        context,
        zh: '研究',
        en: 'R',
      ),
      _CreationMode.none => openHandLocalizedText(context, zh: '开', en: 'ON'),
    };
    return Tooltip(
      message: openHandLocalizedText(
        context,
        zh: '取消创建模式并恢复文本发送',
        en: 'Cancel creation mode and return to text',
      ),
      child: SizedBox(
        width: 52,
        height: 52,
        child: AnimatedContainer(
          duration: openHandMotionDuration(context, kOpenHandMotion320),
          curve: kOpenHandEmphasizedCurve,
          child: FilledButton(
            onPressed: () => unawaited(onTap()),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(52, 52),
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
            // LayoutBuilder 内仅使用默认淡入淡出，避免动画逐帧重建触发布局断言。
            child: AnimatedSwitcher(
              duration: openHandMotionDuration(context, kOpenHandMotion200),
              child: Text(
                label,
                key: ValueKey<String>('creation-options-label-$label'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 输入框快捷键拦截层，优先于系统文本编辑快捷键处理发送与折叠操作。

class _ComposerSendIntent extends Intent {
  const _ComposerSendIntent();
}

class _ComposerToggleCollapsedIntent extends Intent {
  const _ComposerToggleCollapsedIntent();
}

class _ComposerShortcutsHost extends StatelessWidget {
  const _ComposerShortcutsHost({required this.bindings, required this.child});

  final Map<OpenHandShortcutAction, List<int>> bindings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shortcutMap = <ShortcutActivator, Intent>{};
    final sendActivators = _activatorsForBinding(
      bindings[OpenHandShortcutAction.sendMessage],
      includeRepeats: false,
    );
    for (final activator in sendActivators) {
      shortcutMap[activator] = const _ComposerSendIntent();
    }
    final toggleActivators = _activatorsForBinding(
      bindings[OpenHandShortcutAction.toggleComposer],
      includeRepeats: false,
    );
    for (final activator in toggleActivators) {
      shortcutMap[activator] = const _ComposerToggleCollapsedIntent();
    }
    if (shortcutMap.isEmpty) {
      return child;
    }
    return Shortcuts(
      shortcuts: shortcutMap,
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ComposerSendIntent: CallbackAction<_ComposerSendIntent>(
            onInvoke: (_) => null,
          ),
          _ComposerToggleCollapsedIntent:
              CallbackAction<_ComposerToggleCollapsedIntent>(
                onInvoke: (_) => null,
              ),
        },
        child: child,
      ),
    );
  }

  // 将已规范化的用户快捷键转换为 SingleActivator。
  static List<ShortcutActivator> _activatorsForBinding(
    List<int>? keyIds, {
    bool includeRepeats = true,
  }) {
    if (keyIds == null || keyIds.isEmpty) {
      return const <ShortcutActivator>[];
    }
    var control = false;
    var shift = false;
    var alt = false;
    var meta = false;
    LogicalKeyboardKey? trigger;
    for (final keyId in keyIds) {
      final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
      if (key == null) continue;
      if (key == LogicalKeyboardKey.control) {
        control = true;
      } else if (key == LogicalKeyboardKey.shift) {
        shift = true;
      } else if (key == LogicalKeyboardKey.alt) {
        alt = true;
      } else if (key == LogicalKeyboardKey.meta) {
        meta = true;
      } else {
        trigger ??= key;
      }
    }
    if (trigger == null) {
      return const <ShortcutActivator>[];
    }
    return <ShortcutActivator>[
      SingleActivator(
        trigger,
        control: control,
        shift: shift,
        alt: alt,
        meta: meta,
        includeRepeats: includeRepeats,
      ),
    ];
  }
}

String _homeComposerDefaultAccessLabel(BuildContext context) {
  return openHandDefaultAccessLabel(context);
}

String _homeComposerFullAccessLabel(BuildContext context) {
  return openHandFullAccessLabel(context);
}

String _homeComposerStopResponseLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '停止回答', en: 'Stop Response');
}
