part of '../openhand_home_page.dart';

class _NavigationPane extends StatefulWidget {
  const _NavigationPane({
    required this.selectedSection,
    required this.sessions,
    required this.sessionSendPhases,
    required this.currentSessionId,
    required this.onCreateThreadRequested,
    required this.onSessionSelected,
    required this.onRenameSession,
    required this.onDeleteSession,
    required this.onExportSession,
    this.onGenerateTitleForSession,
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
  final Map<String, AiSendPhase> sessionSendPhases;
  final String? currentSessionId;
  final Future<void> Function() onCreateThreadRequested;
  final Future<void> Function(String sessionId) onSessionSelected;
  final Future<void> Function(AiSession session) onRenameSession;
  final Future<void> Function(AiSession session) onDeleteSession;
  final Future<void> Function(AiSession session) onExportSession;
  final void Function(AiSession session)? onGenerateTitleForSession;
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
  // Per-tile widget cache keyed by session id.  When none of the fields
  // contributing to the tile's visual state (title / updatedAt / sendPhase /
  // isSelected) change, we reuse the exact Widget instance so Flutter's
  // Element.update short-circuits and skips rebuilding 60+ unrelated tiles
  // whenever the user opens a different thread or a single session's send
  // phase ticks during streaming.
  final Map<String, _ThreadTileCacheEntry> _threadTileCache =
      <String, _ThreadTileCacheEntry>{};
  _HarnessTileCacheEntry? _harnessTileCache;

  // Tracks which thread ids have already appeared in the sidebar at
  // least once. Newly appended sessions (or a freshly created HE record)
  // get an AppearOnce entrance the first time they show up; the existing
  // list does NOT animate on initial mount.
  final AppearTracker _threadAppear = AppearTracker();

  /// Builds an interleaved list of AI thread tiles and the optional HE session
  /// tile, sorted by [updatedAt] descending.  The incoming [widget.sessions]
  /// are already sorted by the store; we simply merge-insert the HE record at
  /// the correct position.
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
      // Wrap brand-new HE records with an entrance animation. The wrapper
      // is keyed off the record id so it's preserved across cache misses
      // (e.g. title edit) — once its internal animation completes the
      // wrapper short-circuits to its child, so reuse is free.
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
      // Insert HE tile when its updatedAt >= the current AI session's.
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
      // Note: we intentionally do NOT identity-check the callbacks. Method
      // tear-offs (e.g. `_activateSession`) are not guaranteed to be
      // `identical` across rebuilds in Dart — every parent rebuild was
      // busting the cache and forcing all 60+ tiles to re-render. The
      // cached closure captures `widget.onSessionSelected` lazily via
      // the State's `widget` getter, so even if the parent swaps the
      // callback the next tap will still reach the current one.
      if (cached != null &&
          cached.title == session.title &&
          cached.updatedAtMs == session.updatedAt.millisecondsSinceEpoch &&
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
            onRename: () => widget.onRenameSession(session),
            onDelete: () => widget.onDeleteSession(session),
            onExport: () => widget.onExportSession(session),
            onGenerateTitle: () =>
                widget.onGenerateTitleForSession?.call(session),
          ),
        ),
      );
      // Only sessions that appear AFTER the first build (i.e. user just
      // created a new thread) get the AppearOnce entrance — we don't
      // want the entire sidebar to animate on app launch. The wrapped
      // widget is what we cache so subsequent cache-hits keep the
      // wrapper alive until its 220ms animation completes; afterwards
      // AppearOnce short-circuits to the child.
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
        updatedAtMs: session.updatedAt.millisecondsSinceEpoch,
        sendPhase: sendPhase,
        isSelected: isSelected,
        widget: aiDisplayed,
      );
      tiles.add(aiDisplayed);
    }

    // HE session is the oldest, or there are no AI sessions — append at end.
    if (!heInserted && heRecord != null) {
      tiles.add(buildHeTile());
    }

    // Evict cache entries for sessions that no longer exist to bound memory.
    if (_threadTileCache.length != activeSessionIds.length) {
      _threadTileCache.removeWhere(
        (sessionId, _) => !activeSessionIds.contains(sessionId),
      );
    }
    // Drop seen-id markers so a future re-creation of a deleted thread
    // (or, in tests, a freshly-restored snapshot) is treated as new and
    // re-animates. Build the union of all currently-rendered ids first.
    final liveKeys = <String>{
      for (final id in activeSessionIds) 'ai-$id',
      if (heRecord != null) 'he-${heRecord.id}',
    };
    _threadAppear.retainOnly(liveKeys);

    _threadAppear.markInitialBuildDone();

    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // HE tile status: prefer the live orchestrator status when it is actually
    // running/completed/failed/cancelled; fall back to the persisted record
    // status when the live orchestrator is idle (e.g. an orchestrator that
    // was reconstructed from a persisted record on app restart).
    final liveHeStatus = widget.activeHarnessOrchestrator?.status;
    final heAwaitingApprovalForTile =
        widget.activeHarnessOrchestrator?.awaitingApprovalPhase != null;
    final heStatusForTile = widget.harnessSessionRecord == null
        ? null
        : (liveHeStatus != null &&
              liveHeStatus != HarnessOrchestratorStatus.idle)
        ? liveHeStatus
        : widget.harnessSessionRecord!.status;

    final threadCount = widget.sessions.length +
        (widget.harnessSessionRecord == null ? 0 : 1);
    final hasThreads = threadCount > 0;
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: MicroPressFeedback(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.onCreateThreadRequested,
                  icon: const Icon(Icons.add_comment_rounded),
                  label: Text(l10n.newThread),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final destination in _kSystemNavigationDestinations)
            _AdaptiveNavigationDestination(
              destination: destination,
              isSelected: widget.selectedSection == destination.section,
              onSelected: widget.onSectionSelected,
            ),
          // 系统导航与线程列表的分区：细分割 + 轻量区头，避免「大标题压卡片堆」的土气感。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: 15,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.88),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.threads,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (hasThreads)
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.72),
                      borderRadius: _borderRadius999,
                    ),
                    child: Text(
                      '$threadCount',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Unified thread list: merge AI sessions and HE session,
          // sorted by updatedAt descending (most recently updated first).
          if (!hasThreads)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest
                      .withValues(alpha: 0.55),
                  borderRadius: _borderRadius18,
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.threadsEmptyBody,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildMergedThreadTiles(
                  heRecord: widget.harnessSessionRecord,
                  heStatus: heStatusForTile,
                  heAwaitingApproval: heAwaitingApprovalForTile,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 线程列表项纵向间距：与系统导航胶囊节奏对齐，避免卡片式厚重堆叠。
const double _kThreadTileGap = 4;

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
        section: AppSection.agents,
        icon: Icons.smart_toy_outlined,
        selectedIcon: Icons.smart_toy_rounded,
      ),
      _NavigationDestinationSpec(
        section: AppSection.settings,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
      ),
    ];

const EdgeInsets _kNavigationDestinationOuterPadding = EdgeInsets.symmetric(
  horizontal: 12,
);
const EdgeInsets _kNavigationDestinationContentPadding = EdgeInsets.symmetric(
  horizontal: 16,
);
const double _kNavigationDestinationFallbackHeight = 58;
const double _kNavigationDestinationIconSize = 22;
const double _kNavigationDestinationIconGap = 12;

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
    final tileHeight =
        theme.navigationDrawerTheme.tileHeight ??
        _kNavigationDestinationFallbackHeight;
    final backgroundColor = isSelected
        ? colorScheme.primaryContainer
        : Colors.transparent;
    final foregroundColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final iconColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final textStyle = theme.textTheme.titleMedium?.copyWith(
      color: foregroundColor,
      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
    );

    return Padding(
      padding: _kNavigationDestinationOuterPadding,
      child: Semantics(
        button: true,
        selected: isSelected,
        child: MicroPressFeedback(
          scale: 0.985,
          child: AnimatedContainer(
            width: double.infinity,
            height: tileHeight,
            duration: duration,
            curve: curve,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: _borderRadius999,
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: _borderRadius999,
                onTap: () {
                  if (!isSelected) {
                    onSelected(destination.section);
                  }
                },
                child: Padding(
                  padding: _kNavigationDestinationContentPadding,
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
                              size: _kNavigationDestinationIconSize,
                              color: animatedColor ?? iconColor,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: _kNavigationDestinationIconGap),
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: duration,
                          curve: curve,
                          style: textStyle ?? const TextStyle(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          child: Text(label),
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
    AppSection.hooks => openHandLocalizedText(
      context,
      zh: 'Hooks',
      en: 'Hooks',
    ),
    AppSection.crons => 'Crons',
    AppSection.instructions => openHandLocalizedText(
      context,
      zh: '指令',
      en: 'Instructions',
    ),
    AppSection.messageGateway => l10n.settingsMessageGatewayTitle,
    AppSection.pluginService => openHandLocalizedText(
      context,
      zh: '插件',
      en: 'Plugins',
    ),
    AppSection.knowledgeBase => openHandLocalizedText(
      context,
      zh: '知识库',
      en: 'Knowledge Base',
    ),
    AppSection.agents => openHandLocalizedText(
      context,
      zh: '智能体',
      en: 'Agents',
    ),
    AppSection.settings => l10n.settings,
    AppSection.workspace || AppSection.harnessSession => '',
  };
}

class _ContentPane extends StatelessWidget {
  const _ContentPane({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The right-pane content is cross-faded inside an `AnimatedSwitcher`
    // that stacks the outgoing and incoming sections during the
    // transition. A `RepaintBoundary` here gives each pane its own
    // compositor layer so the heavy widget tree of one section (large
    // transcripts, MCP tool catalogues, memory entry markdown) does not
    // dirty / repaint the other on every frame of the fade.
    return RepaintBoundary(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.all(24), child: child),
      ),
    );
  }
}

/// Cached tile instance + signature used by [_NavigationPaneState] to avoid
/// rebuilding sidebar tiles whose visual state did not change.
class _ThreadTileCacheEntry {
  const _ThreadTileCacheEntry({
    required this.title,
    required this.updatedAtMs,
    required this.sendPhase,
    required this.isSelected,
    required this.widget,
  });

  final String title;
  final int updatedAtMs;
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
