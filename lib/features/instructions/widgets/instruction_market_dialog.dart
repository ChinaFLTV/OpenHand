import 'package:flutter/material.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/collision_safe_animated_switcher.dart';
import '../../../shared/ui/micro_press_feedback.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_document_markdown_preview.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_inline_empty_state.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_table_pagination.dart';
import '../../../shared/util/localized_text.dart';
import '../data/instruction_market_catalog.dart';
import '../instructions_controller.dart';
import '../model/user_instruction_entry.dart';
import 'instruction_market_labels.dart';

const double _kInstructionMarketDialogMaxWidth = 1400;
const double _kInstructionMarketDialogMaxHeight = 920;
const double _kInstructionMarketListAvatarSize = 46;
const double _kInstructionMarketDetailAvatarSize = 64;
const double _kInstructionMarketHeaderIconSize = 52;
const double _kInstructionMarketSplitBreakpoint = 800;
const double _kInstructionMarketWideListWidth = 392;
const double _kInstructionMarketNarrowListWidth = 320;
const double _kInstructionMarketWideListBreakpoint = 980;
const List<int> _kInstructionMarketPageSizes = <int>[12, 24, 48, 96];

Future<void> showInstructionMarketDialog(
  BuildContext context, {
  required InstructionsController controller,
}) => showAnimatedDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _InstructionMarketDialog(controller: controller),
);

class _InstructionMarketDialog extends StatefulWidget {
  const _InstructionMarketDialog({required this.controller});
  final InstructionsController controller;
  @override
  State<_InstructionMarketDialog> createState() =>
      _InstructionMarketDialogState();
}

class _InstructionMarketDialogState extends State<_InstructionMarketDialog> {
  final _search = TextEditingController();
  final _listScroll = ScrollController();
  final _detailScroll = ScrollController();
  List<InstructionMarketEntry> _items = instructionMarketCatalog;
  InstructionMarketEntry? _selected = instructionMarketCatalog.first;
  String _category = '';
  int _page = 1, _pageSize = 24;

  List<InstructionMarketEntry> get _visibleItems =>
      OpenHandPageWindow.normalize(
        page: _page,
        pageSize: _pageSize,
        total: _items.length,
      ).slice(_items);
  bool _showDetail = false, _adding = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _listScroll.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  bool _installed(InstructionMarketEntry entry) =>
      widget.controller.entries.any(
        (saved) =>
            saved.keywords.contains(entry.sourceKey) ||
            saved.body == entry.body,
      );

  void _filter() {
    final items = instructionMarketCatalog
        .where(
          (e) =>
              (_category.isEmpty || e.category == _category) &&
              instructionMarketMatches(e, _search.text),
        )
        .toList(growable: false);
    setState(() {
      _items = items;
      _page = 1;
      if (!_visibleItems.contains(_selected)) {
        _selected = _visibleItems.firstOrNull;
      }
      _error = null;
    });
    if (_listScroll.hasClients) _listScroll.jumpTo(0);
    if (_detailScroll.hasClients) _detailScroll.jumpTo(0);
  }

  void _changePage(int page, {int? pageSize}) {
    final window = OpenHandPageWindow.normalize(
      page: page,
      pageSize: pageSize ?? _pageSize,
      total: _items.length,
    );
    setState(() {
      _page = window.page;
      _pageSize = window.pageSize;
      _selected = _visibleItems.firstOrNull;
      _error = null;
    });
    if (_listScroll.hasClients) _listScroll.jumpTo(0);
    if (_detailScroll.hasClients) _detailScroll.jumpTo(0);
  }

  Future<void> _add() async {
    final entry = _selected;
    if (_adding || entry == null || _installed(entry)) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      final saved = await widget.controller.createEntry(
        name: instructionMarketEntryName(context, entry),
        description: instructionMarketEntryDescription(context, entry),
        body: entry.body,
        keywords: [entry.sourceKey],
        enabled: false,
      );
      if (mounted && !saved) {
        setState(
          () => _error =
              widget.controller.errorMessage ??
              instructionMarketAddFailed(context),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final small = MediaQuery.sizeOf(context).width < 668;
      final entry = _selected;
      final installed = entry != null && _installed(entry);
      return PopScope(
        canPop: !_adding,
        child: buildOpenHandResponsiveDialogShell(
          context: context,
          maxWidth: _kInstructionMarketDialogMaxWidth,
          maxHeight: _kInstructionMarketDialogMaxHeight,
          minAvailableWidth: 320,
          minAvailableHeight: 420,
          horizontalMargin: small ? 24 : 48,
          verticalMargin: 24,
          safeAreaMinimum: const EdgeInsets.all(12),
          expandToMax: true,
          child: Padding(
            padding: EdgeInsets.all(small ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(kOpenHandRadius18),
                      ),
                      child: SizedBox(
                        width: _kInstructionMarketHeaderIconSize,
                        height: _kInstructionMarketHeaderIconSize,
                        child: Icon(
                          Icons.storefront_rounded,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                    kOpenHandHGap14,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            openHandInstructionMarketLabel(context),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          kOpenHandGap4,
                          Text(
                            instructionMarketSubtitle(context),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                kOpenHandGap18,
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final list = _listPane();
                      final detail = _detailPane();
                      if (constraints.maxWidth >=
                          _kInstructionMarketSplitBreakpoint) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width:
                                  constraints.maxWidth <
                                      _kInstructionMarketWideListBreakpoint
                                  ? _kInstructionMarketNarrowListWidth
                                  : _kInstructionMarketWideListWidth,
                              child: list,
                            ),
                            kOpenHandHGap16,
                            Expanded(child: detail),
                          ],
                        );
                      }
                      final duration = openHandMotionDuration(
                        context,
                        kOpenHandMotion180,
                      );
                      final browseLabel = instructionMarketBrowseTab(context);
                      final detailLabel = instructionMarketDetailTab(context);
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OpenHandChoicePill(
                                  label: browseLabel,
                                  selected: !_showDetail,
                                  onSelected: () =>
                                      setState(() => _showDetail = false),
                                ),
                              ),
                              kOpenHandHGap12,
                              Expanded(
                                child: OpenHandChoicePill(
                                  label: detailLabel,
                                  selected: _showDetail,
                                  onSelected: () =>
                                      setState(() => _showDetail = true),
                                ),
                              ),
                            ],
                          ),
                          kOpenHandGap12,
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                IgnorePointer(
                                  ignoring: _showDetail,
                                  child: ExcludeFocus(
                                    excluding: _showDetail,
                                    child: ExcludeSemantics(
                                      excluding: _showDetail,
                                      child: AnimatedOpacity(
                                        opacity: _showDetail ? 0 : 1,
                                        duration: duration,
                                        child: list,
                                      ),
                                    ),
                                  ),
                                ),
                                IgnorePointer(
                                  ignoring: !_showDetail,
                                  child: ExcludeFocus(
                                    excluding: !_showDetail,
                                    child: ExcludeSemantics(
                                      excluding: !_showDetail,
                                      child: AnimatedOpacity(
                                        opacity: _showDetail ? 1 : 0,
                                        duration: duration,
                                        child: detail,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                OpenHandDialogErrorText(
                  message:
                      _error ??
                      (widget.controller.entries.length >=
                              UserInstructionEntry.maxEntries
                          ? instructionMarketLimitReached(context)
                          : null),
                ),
                OpenHandDialogBusyBar(busy: _adding),
                kOpenHandGap12,
                LayoutBuilder(
                  builder: (context, constraints) {
                    final hint = Text(
                      instructionMarketFooter(
                        context,
                        instructionMarketCatalog.length,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    );
                    final width = ((constraints.maxWidth - 12) / 2).clamp(
                      0.0,
                      kOpenHandDialogActionButtonWidth,
                    );
                    final buttons = Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: width,
                          child: OpenHandDialogActionButton.secondary(
                            onPressed: _adding
                                ? null
                                : () => Navigator.of(context).pop(),
                            label: openHandCloseLabel(context),
                          ),
                        ),
                        kOpenHandHGap12,
                        SizedBox(
                          width: width,
                          child: OpenHandDialogActionButton.primary(
                            onPressed:
                                _adding ||
                                    widget.controller.isLoading ||
                                    installed ||
                                    entry == null ||
                                    widget.controller.entries.length >=
                                        UserInstructionEntry.maxEntries
                                ? null
                                : _add,
                            icon: installed
                                ? Icons.check_rounded
                                : Icons.add_rounded,
                            label: installed
                                ? openHandAddedLabel(context)
                                : instructionMarketAddAction(context),
                          ),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 640) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          hint,
                          kOpenHandGap12,
                          Align(
                            alignment: Alignment.centerRight,
                            child: buttons,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: hint),
                        kOpenHandHGap16,
                        buttons,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _pane(Widget child) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(kOpenHandRadius22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            colors.tertiary.withValues(alpha: 0.045),
            Color.alphaBlend(
              colors.primary.withValues(alpha: 0.035),
              colors.surfaceContainerLow,
            ),
          ),
          borderRadius: BorderRadius.circular(kOpenHandRadius22),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: .72),
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _listPane() {
    final visibleItems = _visibleItems;
    return _pane(
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            SearchBar(
              enabled: !_adding,
              controller: _search,
              hintText: instructionMarketSearchHint(context),
              leading: const Icon(Icons.search_rounded),
              elevation: const WidgetStatePropertyAll(0),
              shadowColor: const WidgetStatePropertyAll(Colors.transparent),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              onChanged: (_) => _filter(),
              trailing: [
                if (_search.text.isNotEmpty) ...[
                  IconButton(
                    tooltip: openHandClearSearchLabel(context),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      _filter();
                    },
                  ),
                  kOpenHandHGap8,
                ],
                IconButton(
                  tooltip: instructionMarketRefreshTooltip(context),
                  onPressed: _adding ? null : _filter,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            kOpenHandGap12,
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final category in [
                    '',
                    ...kInstructionMarketCategoryOrder,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OpenHandChoicePill(
                        label: category.isEmpty
                            ? openHandAllLabel(context)
                            : '${instructionMarketCategoryLabel(context, category)} · ${instructionMarketCatalog.where((entry) => entry.category == category).length}',
                        selected: _category == category,
                        onSelected: _adding
                            ? null
                            : () {
                                _category = category;
                                _filter();
                              },
                      ),
                    ),
                ],
              ),
            ),
            kOpenHandGap12,
            Expanded(
              child: OpenHandSafeScrollbar(
                controller: _listScroll,
                child: _items.isEmpty
                    ? Center(
                        child: OpenHandInlineEmptyState(
                          icon: Icons.search_off_rounded,
                          message: instructionMarketEmptySearch(context),
                        ),
                      )
                    : ListView.separated(
                        controller: _listScroll,
                        itemCount: visibleItems.length,
                        separatorBuilder: (_, _) => kOpenHandGap8,
                        itemBuilder: (context, index) {
                          final item = visibleItems[index];
                          return _InstructionMarketTile(
                            item: item,
                            selected: _selected == item,
                            installed: _installed(item),
                            onTap: _adding
                                ? null
                                : () {
                                    setState(() {
                                      _selected = item;
                                      _showDetail = true;
                                      _error = null;
                                    });
                                    if (_detailScroll.hasClients) {
                                      _detailScroll.jumpTo(0);
                                    }
                                  },
                          );
                        },
                      ),
              ),
            ),
            kOpenHandGap8,
            OpenHandTablePagination(
              total: _items.length,
              page: _page,
              pageSize: _pageSize,
              pageSizes: _kInstructionMarketPageSizes,
              enabled: !_adding,
              onPageChanged: _changePage,
              onPageSizeChanged: (size) => _changePage(1, pageSize: size),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailPane() {
    final entry = _selected;
    final colors = Theme.of(context).colorScheme;
    final accent = entry == null ? colors.primary : Color(entry.accent);
    final duration = openHandMotionDuration(context, kOpenHandMotion180);
    return _pane(
      OpenHandSafeScrollbar(
        controller: _detailScroll,
        child: SingleChildScrollView(
          controller: _detailScroll,
          padding: const EdgeInsets.all(16),
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: kOpenHandSwitchInCurve,
            switchOutCurve: kOpenHandSwitchOutCurve,
            layoutBuilder: (current, previous) =>
                buildCollisionSafeAnimatedSwitcherLayout(
                  current,
                  previous,
                  alignment: Alignment.topCenter,
                  sizeToCurrentChild: true,
                ),
            child: entry == null
                ? Padding(
                    key: const ValueKey('empty'),
                    padding: const EdgeInsets.all(24),
                    child: OpenHandInlineEmptyState(
                      icon: Icons.auto_awesome_rounded,
                      message: instructionMarketEmptyDetail(context),
                    ),
                  )
                : Column(
                    key: ValueKey(entry.id),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OpenHandTintedPanel(
                        accent: accent,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      kOpenHandRadius16,
                                    ),
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.42),
                                      width: 2,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: _InstructionMarketAvatar(
                                      item: entry,
                                      size: _kInstructionMarketDetailAvatarSize,
                                    ),
                                  ),
                                ),
                                kOpenHandHGap14,
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        instructionMarketEntryName(
                                          context,
                                          entry,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      kOpenHandGap10,
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          OpenHandFactChip(
                                            icon: Icons.library_books_outlined,
                                            label: instructionMarketSourceLabel(
                                              context,
                                            ),
                                            color: OpenHandStatusColors.info,
                                          ),
                                          OpenHandFactChip(
                                            icon: Icons.auto_awesome_rounded,
                                            label: instructionMarketSoulLabel(
                                              context,
                                            ),
                                            color: colors.tertiary,
                                          ),
                                          OpenHandFactChip(
                                            icon: Icons.category_outlined,
                                            label:
                                                instructionMarketCategoryLabel(
                                                  context,
                                                  entry.category,
                                                ),
                                            color: accent,
                                          ),
                                          if (_installed(entry))
                                            OpenHandStatusPill(
                                              icon: Icons.check_circle_rounded,
                                              label: openHandAddedLabel(
                                                context,
                                              ),
                                              color:
                                                  OpenHandStatusColors.success,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            kOpenHandGap14,
                            SelectionArea(
                              child: Text(
                                instructionMarketEntryDescription(
                                  context,
                                  entry,
                                ),
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      height: 1.45,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      kOpenHandGap14,
                      OpenHandTintedPanel(
                        accent: accent,
                        icon: Icons.auto_awesome_rounded,
                        title: instructionMarketRoleReadingTitle(context),
                        child: OpenHandDocumentMarkdownPreview(
                          data: instructionMarketEntryInterpretation(
                            context,
                            entry,
                          ),
                        ),
                      ),
                      kOpenHandGap14,
                      OpenHandTintedPanel(
                        accent: colors.primary,
                        icon: Icons.menu_book_rounded,
                        title: instructionMarketPromptTitle(context),
                        child: OpenHandDocumentMarkdownPreview(
                          data: '```yaml\n${entry.body}\n```',
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

class _InstructionMarketTile extends StatelessWidget {
  const _InstructionMarketTile({
    required this.item,
    required this.selected,
    required this.installed,
    required this.onTap,
  });

  final InstructionMarketEntry item;
  final bool selected;
  final bool installed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = Color(item.accent);
    final radius = BorderRadius.circular(kOpenHandRadius18);
    return MicroPressFeedback(
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: Colors.transparent,
          splashColor: accent.withValues(alpha: 0.10),
          highlightColor: accent.withValues(alpha: 0.06),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: AnimatedContainer(
            duration: openHandMotionDuration(context, kOpenHandMotion180),
            curve: kOpenHandSwitchInCurve,
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(
                      accent.withValues(alpha: 0.16),
                      colors.surface,
                    )
                  : colors.surface,
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? accent
                    : colors.outlineVariant.withValues(alpha: 0.78),
              ),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: kOpenHandAccentBarWidth,
                    child: ColoredBox(color: accent),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InstructionMarketAvatar(
                          item: item,
                          size: _kInstructionMarketListAvatarSize,
                        ),
                        kOpenHandHGap12,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                instructionMarketEntryName(context, item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              kOpenHandGap8,
                              Text(
                                instructionMarketEntryDescription(
                                  context,
                                  item,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                              kOpenHandGap10,
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  OpenHandFactChip(
                                    icon: Icons.auto_awesome_rounded,
                                    label: instructionMarketSoulLabel(context),
                                    color: colors.tertiary,
                                  ),
                                  OpenHandFactChip(
                                    icon: Icons.category_outlined,
                                    label: instructionMarketCategoryLabel(
                                      context,
                                      item.category,
                                    ),
                                    color: accent,
                                  ),
                                  if (installed)
                                    OpenHandStatusPill(
                                      icon: Icons.check_circle_rounded,
                                      label: openHandAddedLabel(context),
                                      color: OpenHandStatusColors.success,
                                    ),
                                ],
                              ),
                            ],
                          ),
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
    );
  }
}

class _InstructionMarketAvatar extends StatelessWidget {
  const _InstructionMarketAvatar({required this.item, required this.size});

  final InstructionMarketEntry item;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kOpenHandRadius14),
      child: Image.network(
        item.avatarUrl,
        key: ValueKey(item.avatarUrl),
        width: size,
        height: size,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ColoredBox(
          color: Color(item.accent).withValues(alpha: .15),
          child: SizedBox(
            width: size,
            height: size,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.id,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
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
