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

    Widget buildHeTile() {
      final record = heRecord;
      final status = heStatus;
      if (record == null || status == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        key: ValueKey<String>('he-thread-${record.id}'),
        padding: const EdgeInsets.only(bottom: 10),
        child: _HardnessSessionTile(
          title: record.title,
          status: status,
          awaitingApproval: heAwaitingApproval,
          isSelected: widget.selectedSection == AppSection.hardnessSession,
          onTap: widget.onHardnessSessionSelected ?? () {},
          onRename: widget.onRenameHardnessSession ?? () {},
          onDelete: widget.onDeleteHardnessSession ?? () {},
        ),
      );
    }

    for (final session in widget.sessions) {
      // Insert HE tile when its updatedAt >= the current AI session's.
      if (!heInserted &&
          heRecord != null &&
          !session.updatedAt.isAfter(heRecord.updatedAt)) {
        tiles.add(buildHeTile());
        heInserted = true;
      }
      tiles.add(
        Padding(
          key: ValueKey<String>('ai-thread-${session.id}'),
          padding: const EdgeInsets.only(bottom: 10),
          child: _ThreadTile(
            session: session,
            sendPhase: widget.sessionSendPhases[session.id] ?? AiSendPhase.idle,
            isSelected:
                widget.selectedSection == AppSection.workspace &&
                widget.currentSessionId == session.id,
            onTap: () => widget.onSessionSelected(session.id),
            onRename: () => widget.onRenameSession(session),
            onDelete: () => widget.onDeleteSession(session),
          ),
        ),
      );
    }

    // HE session is the oldest, or there are no AI sessions — append at end.
    if (!heInserted && heRecord != null) {
      tiles.add(buildHeTile());
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

