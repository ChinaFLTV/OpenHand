import 'package:flutter/material.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/collision_safe_animated_switcher.dart';
import '../../../shared/ui/micro_press_feedback.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_document_markdown_preview.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_table_pagination.dart';
import '../data/instruction_market_catalog.dart';
import '../instructions_controller.dart';
import '../model/user_instruction_entry.dart';

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
  static final _categories = instructionMarketCatalog
      .map((e) => e.category)
      .toSet()
      .toList(growable: false);
  List<InstructionMarketEntry> _items = instructionMarketCatalog;
  InstructionMarketEntry? _selected = instructionMarketCatalog.first;
  String _category = '';
  static const _pageSizes = [12, 24, 48, 96];
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
              e.matches(_search.text),
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
        name: entry.name,
        description: entry.description,
        body: entry.body,
        keywords: [entry.sourceKey],
        enabled: false,
      );
      if (mounted && !saved) {
        setState(
          () => _error = widget.controller.errorMessage ?? '添加失败，请稍后重试。',
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
          maxWidth: 1400,
          maxHeight: 920,
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
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(kOpenHandRadius18),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    kOpenHandHGap14,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '指令市场',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '发现适合你的 AI 搭子，预览后添加到指令。',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
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
                      if (constraints.maxWidth >= 800) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: constraints.maxWidth < 980 ? 320 : 392,
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
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OpenHandChoicePill(
                                  label: '浏览指令',
                                  selected: !_showDetail,
                                  onSelected: () =>
                                      setState(() => _showDetail = false),
                                ),
                              ),
                              kOpenHandHGap12,
                              Expanded(
                                child: OpenHandChoicePill(
                                  label: '指令详情',
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
                          ? '指令数量已达上限，请先移除不再使用的指令。'
                          : null),
                ),
                OpenHandDialogBusyBar(busy: _adding),
                kOpenHandGap12,
                LayoutBuilder(
                  builder: (context, constraints) {
                    final hint = Text(
                      '本地内置 · ${instructionMarketCatalog.length} 个角色',
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
                            label: '关闭',
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
                            label: installed ? '已添加' : '添加指令',
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
            colors.primary.withValues(alpha: .025),
            colors.surfaceContainerLow,
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
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SearchBar(
              enabled: !_adding,
              controller: _search,
              hintText: '搜索指令',
              leading: const Icon(Icons.search_rounded),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (_) => _filter(),
              trailing: [
                if (_search.text.isNotEmpty) ...[
                  IconButton(
                    tooltip: '清空搜索',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      _filter();
                    },
                  ),
                  kOpenHandHGap8,
                ],
                IconButton(
                  tooltip: '刷新市场',
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
                  for (final category in ['', ..._categories])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OpenHandChoicePill(
                        label: category.isEmpty
                            ? '全部'
                            : '$category · ${instructionMarketCatalog.where((entry) => entry.category == category).length}',
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
                    ? const Center(
                        child: Text(
                          '没有匹配的指令，试试其他关键词。',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        controller: _listScroll,
                        itemCount: visibleItems.length,
                        separatorBuilder: (_, _) => kOpenHandGap8,
                        itemBuilder: (context, index) {
                          final item = visibleItems[index];
                          final colors = Theme.of(context).colorScheme;
                          final selected = _selected == item;
                          final accent = Color(item.accent);
                          final radius = BorderRadius.circular(
                            kOpenHandRadius18,
                          );
                          return MicroPressFeedback(
                            child: Material(
                              color: selected
                                  ? Color.alphaBlend(
                                      accent.withValues(alpha: .13),
                                      colors.surface,
                                    )
                                  : colors.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: radius,
                                side: BorderSide(
                                  color: selected
                                      ? accent
                                      : colors.outlineVariant,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
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
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: accent,
                                        width: kOpenHandAccentBarWidth,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      12,
                                      12,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _avatar(item),
                                        kOpenHandHGap12,
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                'SkillHub',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: colors
                                                          .onSurfaceVariant,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              kOpenHandGap8,
                                              Text(
                                                item.description,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              kOpenHandGap8,
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: [
                                                  OpenHandFactChip(
                                                    icon: Icons
                                                        .description_outlined,
                                                    label: 'SOUL',
                                                    color: colors.secondary,
                                                  ),
                                                  if (_installed(item))
                                                    OpenHandFactChip(
                                                      icon: Icons.check_rounded,
                                                      label: '已添加',
                                                      color: colors.primary,
                                                    ),
                                                  OpenHandFactChip(
                                                    icon:
                                                        Icons.category_outlined,
                                                    label: item.category,
                                                    color: accent,
                                                  ),
                                                ],
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
                        },
                      ),
              ),
            ),
            kOpenHandGap8,
            OpenHandTablePagination(
              total: _items.length,
              page: _page,
              pageSize: _pageSize,
              pageSizes: _pageSizes,
              enabled: !_adding,
              onPageChanged: _changePage,
              onPageSizeChanged: (size) => _changePage(1, pageSize: size),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(InstructionMarketEntry item, {double size = 44}) => ClipRRect(
    borderRadius: BorderRadius.circular(kOpenHandRadius14),
    child: Image.network(
      item.avatarUrl,
      key: ValueKey(item.avatarUrl),
      width: size,
      height: size,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(6),
        color: Color(item.accent).withValues(alpha: .15),
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
  );

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
                ? const Padding(
                    key: ValueKey('empty'),
                    padding: EdgeInsets.all(24),
                    child: Text('选择左侧指令，查看角色解读与提示词。'),
                  )
                : Column(
                    key: ValueKey(entry.id),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OpenHandTintedPanel(
                        accent: accent,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final portraitSize = constraints.maxWidth < 460
                                ? 88.0
                                : 120.0;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        kOpenHandRadius14,
                                      ),
                                      child: SizedBox.square(
                                        dimension: portraitSize,
                                        child: Image.network(
                                          entry.backgroundUrl,
                                          key: ValueKey(entry.backgroundUrl),
                                          cacheWidth:
                                              (portraitSize *
                                                      MediaQuery.devicePixelRatioOf(
                                                        context,
                                                      ))
                                                  .ceil(),
                                          fit: BoxFit.cover,
                                          alignment: Alignment.topCenter,
                                          errorBuilder: (_, _, _) => _avatar(
                                            entry,
                                            size: portraitSize,
                                          ),
                                          frameBuilder:
                                              (
                                                context,
                                                child,
                                                frame,
                                                synchronous,
                                              ) => AnimatedOpacity(
                                                opacity:
                                                    synchronous || frame != null
                                                    ? 1
                                                    : 0,
                                                duration: duration,
                                                curve: Curves.easeOut,
                                                child: child,
                                              ),
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
                                            entry.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                          kOpenHandGap8,
                                          Text(
                                            'SkillHub',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                          ),
                                          kOpenHandGap8,
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              OpenHandFactChip(
                                                icon: Icons.category_outlined,
                                                label: entry.category,
                                                color: accent,
                                              ),
                                              OpenHandFactChip(
                                                icon:
                                                    Icons.description_outlined,
                                                label: 'SOUL',
                                                color: colors.secondary,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                kOpenHandGap14,
                                SelectionArea(child: Text(entry.description)),
                              ],
                            );
                          },
                        ),
                      ),
                      kOpenHandGap14,
                      OpenHandTintedPanel(
                        accent: accent,
                        icon: Icons.auto_awesome_rounded,
                        title: '角色解读',
                        child: OpenHandDocumentMarkdownPreview(
                          data: entry.interpretation,
                        ),
                      ),
                      kOpenHandGap14,
                      OpenHandTintedPanel(
                        accent: colors.primary,
                        icon: Icons.menu_book_rounded,
                        title: '指令内容',
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
