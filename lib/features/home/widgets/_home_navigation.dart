part of '../openhand_home_page.dart';

@immutable
class _NavigationSessionSnapshot {
  const _NavigationSessionSnapshot({
    required this.sessions,
    required this.sendPhases,
    required this.currentSessionId,
    required this.totalSessionCount,
    required this.harnessInsertionIndex,
  });

  final List<AiSession> sessions;
  final Map<String, AiSendPhase> sendPhases;
  final String? currentSessionId;
  final int totalSessionCount;
  final int harnessInsertionIndex;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _NavigationSessionSnapshot ||
        currentSessionId != other.currentSessionId ||
        totalSessionCount != other.totalSessionCount ||
        harnessInsertionIndex != other.harnessInsertionIndex ||
        sessions.length != other.sessions.length) {
      return false;
    }
    for (var index = 0; index < sessions.length; index++) {
      final session = sessions[index];
      final otherSession = other.sessions[index];
      if (session.id != otherSession.id ||
          session.title != otherSession.title ||
          session.templateIconName != otherSession.templateIconName ||
          sendPhases[session.id] != other.sendPhases[otherSession.id]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    currentSessionId,
    totalSessionCount,
    harnessInsertionIndex,
    Object.hashAll(
      sessions.map(
        (session) => Object.hash(
          session.id,
          session.title,
          session.templateIconName,
          sendPhases[session.id],
        ),
      ),
    ),
  );
}

class _NavigationPane extends StatefulWidget {
  const _NavigationPane({
    required this.selectedSection,
    required this.sessions,
    required this.sessionLimit,
    required this.totalSessionCount,
    required this.hasMoreSessions,
    required this.sessionSendPhases,
    required this.currentSessionId,
    required this.onLoadMoreSessions,
    required this.onCreateThreadRequested,
    required this.onSessionSelected,
    required this.onRenameSession,
    required this.onDeleteSession,
    required this.onExportSession,
    this.onGenerateTitleForSession,
    required this.onShowTrajectoryForSession,
    required this.onSectionSelected,
    this.activeHarnessOrchestrator,
    this.harnessSessionRecord,
    this.onHarnessSessionSelected,
    this.onRenameHarnessSession,
    this.onDeleteHarnessSession,
    this.onExportHarnessSession,
  });

  final AppSection selectedSection;
  final List<AiSession> sessions;
  final int sessionLimit;
  final int totalSessionCount;
  final bool hasMoreSessions;
  final Map<String, AiSendPhase> sessionSendPhases;
  final String? currentSessionId;
  final VoidCallback onLoadMoreSessions;
  final Future<void> Function() onCreateThreadRequested;
  final Future<void> Function(String sessionId) onSessionSelected;
  final Future<void> Function(AiSession session) onRenameSession;
  final Future<void> Function(AiSession session) onDeleteSession;
  final Future<void> Function(AiSession session) onExportSession;
  final void Function(AiSession session)? onGenerateTitleForSession;
  final void Function(AiSession session) onShowTrajectoryForSession;
  final ValueChanged<AppSection> onSectionSelected;
  final HarnessOrchestrator? activeHarnessOrchestrator;
  final HarnessSessionRecord? harnessSessionRecord;
  final VoidCallback? onHarnessSessionSelected;
  final VoidCallback? onRenameHarnessSession;
  final VoidCallback? onDeleteHarnessSession;
  final VoidCallback? onExportHarnessSession;

  @override
  State<_NavigationPane> createState() => _NavigationPaneState();
}

class _NavigationPaneState extends State<_NavigationPane> {
  final Map<String, _ThreadTileCacheEntry> _threadTileCache =
      <String, _ThreadTileCacheEntry>{};
  _HarnessTileCacheEntry? _harnessTileCache;
  final AppearTracker _threadAppear = AppearTracker();
  final ScrollController _featureScrollController = ScrollController();
  final ScrollController _threadScrollController = ScrollController();
  bool _creatingThread = false;

  @override
  void dispose() {
    _featureScrollController.dispose();
    _threadScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _NavigationPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionLimit > oldWidget.sessionLimit) {
      for (final session in widget.sessions) {
        _threadAppear.markSeen('ai-${session.id}');
      }
    }
  }

  AiSession? _visibleSession(String sessionId) {
    for (final session in widget.sessions) {
      if (session.id == sessionId) return session;
    }
    return null;
  }

  Future<void> _requestCreateThread() async {
    if (_creatingThread) return;
    setState(() => _creatingThread = true);
    try {
      await widget.onCreateThreadRequested();
    } finally {
      if (mounted) setState(() => _creatingThread = false);
    }
  }

  /// 按更新时间将可选 Harness 会话合并插入已排序的 AI 会话列表。
  List<Widget> _buildMergedThreadTiles({
    required HarnessSessionRecord? heRecord,
    required HarnessOrchestratorStatus? heStatus,
    required bool heAwaitingApproval,
  }) {
    final tiles = <Widget>[];
    bool heInserted = false;
    final activeSessionIds = <String>{};

    Widget buildHeTile() {
      final record = heRecord;
      final status = heStatus;
      if (record == null || status == null) {
        return const SizedBox.shrink();
      }
      final isSelected = widget.selectedSection == AppSection.harnessSession;
      final cached = _harnessTileCache;
      if (cached != null &&
          cached.recordId == record.id &&
          cached.title == record.title &&
          cached.updatedAtMs == record.updatedAt.millisecondsSinceEpoch &&
          cached.status == status &&
          cached.awaitingApproval == heAwaitingApproval &&
          cached.isSelected == isSelected) {
        return cached.widget;
      }
      final built = Padding(
        key: ValueKey<String>('he-thread-${record.id}'),
        padding: const EdgeInsets.only(bottom: _kThreadTileGap),
        child: RepaintBoundary(
          child: _HarnessSessionTile(
            title: record.title,
            status: status,
            awaitingApproval: heAwaitingApproval,
            isSelected: isSelected,
            onTap: widget.onHarnessSessionSelected ?? () {},
            onRename: widget.onRenameHarnessSession ?? () {},
            onDelete: widget.onDeleteHarnessSession ?? () {},
            onExport: widget.onExportHarnessSession ?? () {},
          ),
        ),
      );
      // 新 Harness 记录按标识播放一次入场动画，后续缓存复用直接返回子组件。
      final heKey = 'he-${record.id}';
      final heIsNew = _threadAppear.shouldAnimate(heKey);
      _threadAppear.markSeen(heKey);
      final heDisplayed = heIsNew
          ? SettingsAwareAppearOnce(
              key: ValueKey<String>('he-thread-appear-${record.id}'),
              child: built,
            )
          : built;
      _harnessTileCache = _HarnessTileCacheEntry(
        recordId: record.id,
        title: record.title,
        updatedAtMs: record.updatedAt.millisecondsSinceEpoch,
        status: status,
        awaitingApproval: heAwaitingApproval,
        isSelected: isSelected,
        widget: heDisplayed,
      );
      return heDisplayed;
    }

    for (final session in widget.sessions) {
      // Harness 更新时间不早于当前 AI 会话时插入。
      if (!heInserted &&
          heRecord != null &&
          !session.updatedAt.isAfter(heRecord.updatedAt)) {
        tiles.add(buildHeTile());
        heInserted = true;
      }
      activeSessionIds.add(session.id);
      final sendPhase =
          widget.sessionSendPhases[session.id] ?? AiSendPhase.idle;
      final isSelected =
          widget.selectedSection == AppSection.workspace &&
          widget.currentSessionId == session.id;
      final cached = _threadTileCache[session.id];
      if (cached != null &&
          cached.title == session.title &&
          cached.templateIconName == session.templateIconName &&
          cached.sendPhase == sendPhase &&
          cached.isSelected == isSelected) {
        tiles.add(cached.widget);
        continue;
      }
      final sessionId = session.id;
      final built = Padding(
        key: ValueKey<String>('ai-thread-$sessionId'),
        padding: const EdgeInsets.only(bottom: _kThreadTileGap),
        child: RepaintBoundary(
          child: _ThreadTile(
            session: session,
            sendPhase: sendPhase,
            isSelected: isSelected,
            onTap: () => widget.onSessionSelected(sessionId),
            onRename: () {
              final latest = _visibleSession(sessionId);
              if (latest != null) widget.onRenameSession(latest);
            },
            onDelete: () {
              final latest = _visibleSession(sessionId);
              if (latest != null) widget.onDeleteSession(latest);
            },
            onExport: () {
              final latest = _visibleSession(sessionId);
              if (latest != null) widget.onExportSession(latest);
            },
            onGenerateTitle: () {
              final latest = _visibleSession(sessionId);
              if (latest != null) {
                widget.onGenerateTitleForSession?.call(latest);
              }
            },
            onTrajectory: () {
              final latest = _visibleSession(sessionId);
              if (latest != null) {
                widget.onShowTrajectoryForSession(latest);
              }
            },
          ),
        ),
      );
      // 仅首帧后新增的会话播放入场动画，避免启动时整个侧栏同时动画。
      final aiKey = 'ai-$sessionId';
      final aiIsNew = _threadAppear.shouldAnimate(aiKey);
      _threadAppear.markSeen(aiKey);
      final aiDisplayed = aiIsNew
          ? SettingsAwareAppearOnce(
              key: ValueKey<String>('ai-thread-appear-$sessionId'),
              child: built,
            )
          : built;
      _threadTileCache[sessionId] = _ThreadTileCacheEntry(
        title: session.title,
        templateIconName: session.templateIconName,
        sendPhase: sendPhase,
        isSelected: isSelected,
        widget: aiDisplayed,
      );
      tiles.add(aiDisplayed);
    }

    // Harness 会话最旧或没有 AI 会话时追加到末尾。
    if (!heInserted && heRecord != null) {
      tiles.add(buildHeTile());
    }

    // 移除已不存在会话的缓存项。
    if (_threadTileCache.length != activeSessionIds.length) {
      _threadTileCache.removeWhere(
        (sessionId, _) => !activeSessionIds.contains(sessionId),
      );
    }
    _threadAppear.retainOnly(<String>{
      for (final sessionId in activeSessionIds) 'ai-$sessionId',
      if (heRecord != null) 'he-${heRecord.id}',
    });
    _threadAppear.markInitialBuildDone();

    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // Harness 运行时优先使用实时状态，空闲时回退到持久化状态。
    final liveHeStatus = widget.activeHarnessOrchestrator?.status;
    final heAwaitingApprovalForTile =
        widget.activeHarnessOrchestrator?.awaitingApprovalPhase != null;
    final heStatusForTile = widget.harnessSessionRecord == null
        ? null
        : (liveHeStatus != null &&
              liveHeStatus != HarnessOrchestratorStatus.idle)
        ? liveHeStatus
        : widget.harnessSessionRecord!.status;

    final threadCount =
        widget.totalSessionCount +
        (widget.harnessSessionRecord == null ? 0 : 1);
    final hasThreads = threadCount > 0;
    final colorScheme = theme.colorScheme;
    final threadTiles = _buildMergedThreadTiles(
      heRecord: widget.harnessSessionRecord,
      heStatus: heStatusForTile,
      heAwaitingApproval: heAwaitingApprovalForTile,
    );
    final threadTileIndexByKey = <Key, int>{
      for (var index = 0; index < threadTiles.length; index++)
        if (threadTiles[index].key case final key?) key: index,
    };

    return Column(
      children: [
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: OpenHandSafeScrollbar(
              controller: _featureScrollController,
              child: CustomScrollView(
                controller: _featureScrollController,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate.fixed([
                        for (final destination
                            in _kSystemNavigationDestinations)
                          _AdaptiveNavigationDestination(
                            key: ValueKey<AppSection>(destination.section),
                            destination: destination,
                            isSelected:
                                widget.selectedSection == destination.section,
                            onSelected: widget.onSectionSelected,
                          ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: _contentPaneGap),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                l10n.threads,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            if (hasThreads) ...[
                              kOpenHandHGap8,
                              Container(
                                constraints: const BoxConstraints(minWidth: 22),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.72),
                                  borderRadius: kOpenHandPillBorderRadius,
                                ),
                                child: Text(
                                  '$threadCount',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      kOpenHandHGap8,
                      MicroPressFeedback(
                        scale: 0.94,
                        enabled: !_creatingThread,
                        child: IconButton(
                          tooltip: l10n.newThread,
                          onPressed: _creatingThread
                              ? null
                              : _requestCreateThread,
                          style: IconButton.styleFrom(
                            minimumSize: const Size.square(
                              _kCreateThreadButtonSize,
                            ),
                            maximumSize: const Size.square(
                              _kCreateThreadButtonSize,
                            ),
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.transparent,
                            foregroundColor: colorScheme.onSurfaceVariant,
                            disabledBackgroundColor: Colors.transparent,
                            disabledForegroundColor: colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.48),
                            hoverColor: colorScheme.onSurface.withValues(
                              alpha: 0.05,
                            ),
                            focusColor: colorScheme.onSurface.withValues(
                              alpha: 0.07,
                            ),
                            highlightColor: colorScheme.onSurface.withValues(
                              alpha: 0.09,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                kOpenHandRadius11,
                              ),
                            ),
                          ),
                          icon: AnimatedSwitcher(
                            duration: openHandMotionDuration(
                              context,
                              _kHomeSidebarTileMotionDuration,
                            ),
                            child: _creatingThread
                                ? SizedBox.square(
                                    key: const ValueKey<String>(
                                      'creating-thread-progress',
                                    ),
                                    dimension: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                : const Icon(
                                    Icons.edit_outlined,
                                    key: ValueKey<String>('create-thread-icon'),
                                    size: 18,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.48),
                  ),
                ),
                kOpenHandGap8,
                Expanded(
                  child: OpenHandSafeScrollbar(
                    controller: _threadScrollController,
                    child: CustomScrollView(
                      controller: _threadScrollController,
                      slivers: [
                        if (!hasThreads)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerLowest
                                      .withValues(alpha: 0.55),
                                  borderRadius: kOpenHandBorderRadius18,
                                  border: Border.all(
                                    color: colorScheme.outlineVariant
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Text(
                                    l10n.threadsEmptyBody,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (hasThreads)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (_, index) => threadTiles[index],
                                childCount: threadTiles.length,
                                addAutomaticKeepAlives: false,
                                addRepaintBoundaries: false,
                                findChildIndexCallback: (key) =>
                                    threadTileIndexByKey[key],
                              ),
                            ),
                          ),
                        if (widget.hasMoreSessions)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: MicroPressFeedback(
                                child: SizedBox(
                                  width: double.infinity,
                                  child: TextButton.icon(
                                    onPressed: widget.onLoadMoreSessions,
                                    icon: const Icon(Icons.expand_more_rounded),
                                    label: Text(l10n.threadsLoadMore),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

const double _kThreadTileGap = 4;
const double _kCreateThreadButtonSize = 32;
const EdgeInsets _kSidebarTileOuterPadding = EdgeInsets.fromLTRB(
  12,
  0,
  12,
  _kThreadTileGap,
);
const EdgeInsets _kSidebarTileContentPadding = EdgeInsets.symmetric(
  horizontal: 14,
  vertical: 11,
);
const double _kSidebarTileIconSize = 16;
const double _kSidebarTileIconGap = 10;

const List<_NavigationDestinationSpec> _kSystemNavigationDestinations =
    <_NavigationDestinationSpec>[
      _NavigationDestinationSpec(
        section: AppSection.skills,
        icon: Icons.extension_outlined,
        selectedIcon: Icons.extension_rounded,
      ),
      _NavigationDestinationSpec(
        section: AppSection.memory,
        icon: Icons.psychology_alt_outlined,
        selectedIcon: Icons.psychology_alt_rounded,
      ),
      _NavigationDestinationSpec(
        section: AppSection.mcp,
        icon: Icons.hub_outlined,
        selectedIcon: Icons.hub_rounded,
      ),
      _NavigationDestinationSpec(
        section: AppSection.hooks,
        icon: Icons.webhook_outlined,
        selectedIcon: Icons.webhook_rounded,
      ),
      _NavigationDestinationSpec(
        section: AppSection.crons,
        icon: Icons.schedule_outlined,
        selectedIcon: Icons.schedule_rounded,
      ),
      _NavigationDestinationSpec(
        section: AppSection.instructions,
        icon: Icons.rule_folder_outlined,
        selectedIcon: Icons.rule_folder_rounded,
      ),
      _NavigationDestinationSpec(
        section: AppSection.messageGateway,
        icon: Icons.alt_route_outlined,
        selectedIcon: Icons.alt_route_rounded,
      ),
      _NavigationDestinationSpec(
        section: AppSection.pluginService,
        icon: Icons.power_outlined,
        selectedIcon: Icons.power_rounded,
      ),
      _NavigationDestinationSpec(
        section: AppSection.knowledgeBase,
        icon: Icons.library_books_outlined,
        selectedIcon: Icons.library_books_rounded,
      ),
      _NavigationDestinationSpec(
        section: AppSection.services,
        icon: Icons.auto_awesome_mosaic_outlined,
        selectedIcon: Icons.auto_awesome_mosaic_rounded,
      ),
      _NavigationDestinationSpec(
        section: AppSection.settings,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
      ),
    ];

class _NavigationDestinationSpec {
  const _NavigationDestinationSpec({
    required this.section,
    required this.icon,
    required this.selectedIcon,
  });

  final AppSection section;
  final IconData icon;
  final IconData selectedIcon;
}

class _AdaptiveNavigationDestination extends StatelessWidget {
  const _AdaptiveNavigationDestination({
    super.key,
    required this.destination,
    required this.isSelected,
    required this.onSelected,
  });

  final _NavigationDestinationSpec destination;
  final bool isSelected;
  final ValueChanged<AppSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = _navigationDestinationLabel(context, destination.section);
    final configuredMotionSettings = context
        .select<SettingsController, DialogAnimationSettings>(
          (controller) => controller.listItemAnimationSettings,
        );
    final motionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.listItem,
      override: configuredMotionSettings,
    );
    final duration = openHandMotionDuration(context, motionSettings.duration);
    final curve = motionSettings.curve.curve;
    final backgroundColor = isSelected
        ? colorScheme.primaryContainer
        : Colors.transparent;
    final foregroundColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final iconColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final textStyle = theme.textTheme.titleSmall?.copyWith(
      color: foregroundColor,
      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
      height: 1.25,
    );

    return Padding(
      padding: _kSidebarTileOuterPadding,
      child: Semantics(
        button: true,
        selected: isSelected,
        child: MicroPressFeedback(
          scale: 0.985,
          child: AnimatedContainer(
            width: double.infinity,
            duration: duration,
            curve: curve,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: kOpenHandPillBorderRadius,
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: kOpenHandPillBorderRadius,
                onTap: () {
                  if (!isSelected) {
                    onSelected(destination.section);
                  }
                },
                child: Padding(
                  padding: _kSidebarTileContentPadding,
                  child: Row(
                    children: [
                      TweenAnimationBuilder<Color?>(
                        tween: ColorTween(end: iconColor),
                        duration: duration,
                        curve: curve,
                        builder: (context, animatedColor, _) {
                          return AnimatedSwitcher(
                            duration: duration,
                            switchInCurve: curve,
                            switchOutCurve: curve.flipped,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.92,
                                    end: 1,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: Icon(
                              isSelected
                                  ? destination.selectedIcon
                                  : destination.icon,
                              key: ValueKey<IconData>(
                                isSelected
                                    ? destination.selectedIcon
                                    : destination.icon,
                              ),
                              size: _kSidebarTileIconSize,
                              color: animatedColor ?? iconColor,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: _kSidebarTileIconGap),
                      Expanded(
                        child: Text(
                          label,
                          style: textStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

String _navigationDestinationLabel(BuildContext context, AppSection section) {
  final l10n = AppLocalizations.of(context)!;
  return switch (section) {
    AppSection.skills => l10n.skills,
    AppSection.memory => l10n.memory,
    AppSection.mcp => l10n.mcp,
    AppSection.hooks => _homeHooksLabel(context),
    AppSection.crons => 'Crons',
    AppSection.instructions => openHandInstructionsLabel(context),
    AppSection.messageGateway => l10n.settingsMessageGatewayTitle,
    AppSection.pluginService => _homePluginsLabel(context),
    AppSection.knowledgeBase => openHandKnowledgeBaseLabel(context),
    AppSection.services => l10n.servicesTitle,
    AppSection.settings => l10n.settings,
    AppSection.workspace || AppSection.harnessSession => '',
  };
}

class _ContentPane extends StatelessWidget {
  const _ContentPane({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 为切换器两侧页面提供独立合成层，避免重型页面在淡入淡出时相互触发重绘。
    return RepaintBoundary(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.all(24), child: child),
      ),
    );
  }
}

/// 缓存导航项及其签名，避免视觉状态未变时重建。
class _ThreadTileCacheEntry {
  const _ThreadTileCacheEntry({
    required this.title,
    required this.templateIconName,
    required this.sendPhase,
    required this.isSelected,
    required this.widget,
  });

  final String title;
  final String templateIconName;
  final AiSendPhase sendPhase;
  final bool isSelected;
  final Widget widget;
}

class _HarnessTileCacheEntry {
  const _HarnessTileCacheEntry({
    required this.recordId,
    required this.title,
    required this.updatedAtMs,
    required this.status,
    required this.awaitingApproval,
    required this.isSelected,
    required this.widget,
  });

  final String recordId;
  final String title;
  final int updatedAtMs;
  final HarnessOrchestratorStatus status;
  final bool awaitingApproval;
  final bool isSelected;
  final Widget widget;
}
