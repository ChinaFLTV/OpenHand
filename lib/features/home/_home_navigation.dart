part of 'openhand_home_page.dart';

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
    required this.onSectionSelected,
    this.activeHardnessOrchestrator,
    this.hardnessSessionRecord,
    this.onHardnessSessionSelected,
    this.onRenameHardnessSession,
    this.onDeleteHardnessSession,
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
  final HardnessOrchestrator? activeHardnessOrchestrator;
  final HardnessSessionRecord? hardnessSessionRecord;
  final VoidCallback? onHardnessSessionSelected;
  final VoidCallback? onRenameHardnessSession;
  final VoidCallback? onDeleteHardnessSession;

  @override
  State<_NavigationPane> createState() => _NavigationPaneState();
}

class _NavigationPaneState extends State<_NavigationPane> {
  ThemeData? _cachedDrawerTheme;
  int? _cachedThemeSignature;

  // Per-tile widget cache keyed by session id.  When none of the fields
  // contributing to the tile's visual state (title / updatedAt / sendPhase /
  // isSelected) change, we reuse the exact Widget instance so Flutter's
  // Element.update short-circuits and skips rebuilding 60+ unrelated tiles
  // whenever the user opens a different thread or a single session's send
  // phase ticks during streaming.
  final Map<String, _ThreadTileCacheEntry> _threadTileCache =
      <String, _ThreadTileCacheEntry>{};
  _HardnessTileCacheEntry? _hardnessTileCache;

  ThemeData _ensureDrawerTheme(ThemeData theme) {
    final signature = Object.hashAll(<Object?>[
      theme.colorScheme.primary.toARGB32(),
      theme.colorScheme.primaryContainer.toARGB32(),
      theme.brightness.index,
      theme.textTheme.titleMedium?.fontSize,
    ]);
    if (_cachedDrawerTheme != null && _cachedThemeSignature == signature) {
      return _cachedDrawerTheme!;
    }
    final colorScheme = theme.colorScheme;
    _cachedDrawerTheme = theme.copyWith(
      navigationDrawerTheme: theme.navigationDrawerTheme.copyWith(
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return theme.textTheme.titleMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
            size: 22,
          );
        }),
      ),
    );
    _cachedThemeSignature = signature;
    return _cachedDrawerTheme!;
  }

  /// Builds an interleaved list of AI thread tiles and the optional HE session
  /// tile, sorted by [updatedAt] descending.  The incoming [widget.sessions]
  /// are already sorted by the store; we simply merge-insert the HE record at
  /// the correct position.
  List<Widget> _buildMergedThreadTiles({
    required HardnessSessionRecord? heRecord,
    required HardnessOrchestratorStatus? heStatus,
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
      final isSelected = widget.selectedSection == AppSection.hardnessSession;
      final cached = _hardnessTileCache;
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
        padding: const EdgeInsets.only(bottom: 10),
        child: RepaintBoundary(
          child: _HardnessSessionTile(
            title: record.title,
            status: status,
            awaitingApproval: heAwaitingApproval,
            isSelected: isSelected,
            onTap: widget.onHardnessSessionSelected ?? () {},
            onRename: widget.onRenameHardnessSession ?? () {},
            onDelete: widget.onDeleteHardnessSession ?? () {},
          ),
        ),
      );
      _hardnessTileCache = _HardnessTileCacheEntry(
        recordId: record.id,
        title: record.title,
        updatedAtMs: record.updatedAt.millisecondsSinceEpoch,
        status: status,
        awaitingApproval: heAwaitingApproval,
        isSelected: isSelected,
        widget: built,
      );
      return built;
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
      final isSelected = widget.selectedSection == AppSection.workspace &&
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
        padding: const EdgeInsets.only(bottom: 10),
        child: RepaintBoundary(
          child: _ThreadTile(
            session: session,
            sendPhase: sendPhase,
            isSelected: isSelected,
            onTap: () => widget.onSessionSelected(sessionId),
            onRename: () => widget.onRenameSession(session),
            onDelete: () => widget.onDeleteSession(session),
          ),
        ),
      );
      _threadTileCache[sessionId] = _ThreadTileCacheEntry(
        title: session.title,
        updatedAtMs: session.updatedAt.millisecondsSinceEpoch,
        sendPhase: sendPhase,
        isSelected: isSelected,
        widget: built,
      );
      tiles.add(built);
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

    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final drawerTheme = _ensureDrawerTheme(theme);

    // HE tile status: prefer the live orchestrator status when it is actually
    // running/completed/failed/cancelled; fall back to the persisted record
    // status when the live orchestrator is idle (e.g. an orchestrator that
    // was reconstructed from a persisted record on app restart).
    final liveHeStatus = widget.activeHardnessOrchestrator?.status;
    final heAwaitingApprovalForTile =
        widget.activeHardnessOrchestrator?.awaitingApprovalPhase != null;
    final heStatusForTile = widget.hardnessSessionRecord == null
        ? null
        : (liveHeStatus != null &&
              liveHeStatus != HardnessOrchestratorStatus.idle)
        ? liveHeStatus
        : widget.hardnessSessionRecord!.status;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: drawerTheme,
        // Use a ValueKey to ensure full rebuild when selectedIndex changes,
        // forcing the internal _SelectableAnimatedBuilder widgets to recreate
        // their animation controllers and avoid stale selection state.
        child: NavigationDrawer(
          key: ValueKey<int>(widget.selectedSection.drawerIndex),
          selectedIndex: widget.selectedSection.drawerIndex,
          onDestinationSelected: (index) {
            widget.onSectionSelected(_sectionFromDrawerIndex(index));
          },
          children: [
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: widget.onCreateThreadRequested,
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
              icon: const Icon(Icons.webhook_outlined),
              selectedIcon: const Icon(Icons.webhook_rounded),
              label: Text(_localizedText(context, zh: 'Hooks', en: 'Hooks')),
            ),
            const NavigationDrawerDestination(
              icon: Icon(Icons.schedule_outlined),
              selectedIcon: Icon(Icons.schedule_rounded),
              label: Text('Crons'),
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
            // Unified thread list: merge AI sessions and HE session,
            // sorted by updatedAt descending (most recently updated first).
            if (widget.sessions.isEmpty && widget.hardnessSessionRecord == null)
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
                  children: _buildMergedThreadTiles(
                    heRecord: widget.hardnessSessionRecord,
                    heStatus: heStatusForTile,
                    heAwaitingApproval: heAwaitingApprovalForTile,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ContentPane extends StatelessWidget {
  const _ContentPane({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(24), child: child),
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

class _HardnessTileCacheEntry {
  const _HardnessTileCacheEntry({
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
  final HardnessOrchestratorStatus status;
  final bool awaitingApproval;
  final bool isSelected;
  final Widget widget;
}

