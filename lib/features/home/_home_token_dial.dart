part of 'openhand_home_page.dart';

class _TokenDial extends StatefulWidget {
  const _TokenDial({
    required this.statistics,
    this.activeProfile,
    this.claudeStyle = true,
  });

  final AiSessionStatistics statistics;
  final AiModelProfile? activeProfile;
  final bool claudeStyle;

  int get totalTokens => statistics.totalTokens ?? 0;
  int? get cacheReadTokens => statistics.cacheReadTokens;
  int? get cacheCreationTokens => statistics.cacheCreationTokens;

  /// 当前会话的 cache 命中率（cache_read / (prompt + cache_read)），范围 0..1。
  /// 当 prompt + cache_read = 0 时返回 0。
  double get cacheHitRatio {
    final read = cacheReadTokens ?? 0;
    final prompt = statistics.totalPromptTokens ?? 0;
    final denom = prompt + read;
    if (denom == 0) return 0.0;
    return read / denom;
  }

  @override
  State<_TokenDial> createState() => _TokenDialState();
}

class _TokenDialState extends State<_TokenDial>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portalController = OverlayPortalController();
  final LayerLink _link = LayerLink();
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _showPopup() {
    _hideTimer?.cancel();
    if (!_portalController.isShowing) {
      _portalController.show();
    }
    _fadeController.forward();
  }

  void _schedulePopupHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 60), () async {
      if (!mounted) return;
      await _fadeController.reverse();
      if (!mounted) return;
      if (_portalController.isShowing) {
        _portalController.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final numberStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: colorScheme.onSurface,
    );
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: colorScheme.onSurfaceVariant,
    );
    final hasCache = (widget.cacheReadTokens ?? 0) > 0;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portalController,
        overlayChildBuilder: (context) {
          return Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 8),
              child: MouseRegion(
                onEnter: (_) => _showPopup(),
                onExit: (_) => _schedulePopupHide(),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    alignment: Alignment.topRight,
                    child: _TokenDialPopup(
                      statistics: widget.statistics,
                      activeProfile: widget.activeProfile,
                      claudeStyle: widget.claudeStyle,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        child: MouseRegion(
          onEnter: (_) => _showPopup(),
          onExit: (_) => _schedulePopupHide(),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hasCache
                  ? Colors.green.withValues(alpha: 0.08)
                  : colorScheme.surfaceContainerHighest,
              borderRadius: _borderRadius999,
              border: Border.all(
                color: hasCache
                    ? Colors.green.withValues(alpha: 0.4)
                    : colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasCache
                      ? Icons.bolt_rounded
                      : Icons.confirmation_number_rounded,
                  size: 14,
                  color: hasCache
                      ? Colors.green.shade600
                      : colorScheme.primary,
                ),
                const SizedBox(width: 6),
                if (hasCache) ...[
                  _CacheSavingsBadge(percent: widget.cacheHitRatio),
                  Container(
                    width: 1,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: colorScheme.outlineVariant,
                  ),
                ],
                _RollingNumber(
                  value: widget.totalTokens,
                  style: numberStyle ?? const TextStyle(),
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context)!.tokenDialUnit,
                  style: labelStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 悬浮在 `_TokenDial` 下方的结构化 token 详情浮窗。
///
/// 内容分组：
/// - 输入侧：Prompt / Cache Read / Cache Write
/// - 输出侧：Completion
/// - 总计：Total
/// - 会话累计 (消息数 / prompt 字符 / 构建次数)
class _TokenDialPopup extends StatelessWidget {
  const _TokenDialPopup({
    required this.statistics,
    this.activeProfile,
    this.claudeStyle = true,
  });

  final AiSessionStatistics statistics;
  final AiModelProfile? activeProfile;
  final bool claudeStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final headStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: colorScheme.onSurfaceVariant,
      letterSpacing: 0.4,
    );
    final keyStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final cacheValueStyle = valueStyle?.copyWith(color: Colors.green.shade700);
    final reasoningValueStyle =
        valueStyle?.copyWith(color: Colors.purple.shade400);
    final promptTokens = statistics.totalPromptTokens ?? 0;
    final completionTokens = statistics.totalCompletionTokens ?? 0;
    final cacheRead = statistics.cacheReadTokens ?? 0;
    final cacheWrite = statistics.cacheCreationTokens ?? 0;
    final reasoning = statistics.reasoningTokens ?? 0;
    final total = statistics.totalTokens ?? 0;
    final cacheDenominator = promptTokens + cacheRead;
    final cacheHitRatio =
        cacheDenominator == 0 ? 0.0 : cacheRead / cacheDenominator;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 320),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context)!.tokenPopupInputHeading.toUpperCase(),
              style: headStyle,
            ),
            const SizedBox(height: 6),
            _PopupRow(
              label: AppLocalizations.of(context)!.tokenPopupPrompt,
              value: promptTokens,
              keyStyle: keyStyle,
              valueStyle: valueStyle,
            ),
            _PopupRow(
              label: AppLocalizations.of(context)!.tokenPopupCacheRead,
              value: cacheRead,
              keyStyle: keyStyle,
              valueStyle: cacheValueStyle,
              accent: Colors.green,
            ),
            _PopupRow(
              label: AppLocalizations.of(context)!.tokenPopupCacheWrite,
              value: cacheWrite,
              keyStyle: keyStyle,
              valueStyle: cacheValueStyle,
              accent: Colors.green,
            ),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context)!.tokenPopupOutputHeading.toUpperCase(),
              style: headStyle,
            ),
            const SizedBox(height: 6),
            _PopupRow(
              label: AppLocalizations.of(context)!.tokenPopupCompletion,
              value: completionTokens,
              keyStyle: keyStyle,
              valueStyle: valueStyle,
            ),
            if (reasoning > 0)
              _PopupRow(
                label: AppLocalizations.of(context)!.tokenPopupReasoning,
                value: reasoning,
                keyStyle: keyStyle,
                valueStyle: reasoningValueStyle,
                accent: Colors.purple,
              ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            _PopupRow(
              label: AppLocalizations.of(context)!.tokenPopupGrandTotal,
              value: total,
              keyStyle: keyStyle?.copyWith(fontWeight: FontWeight.w700),
              valueStyle: valueStyle?.copyWith(
                color: colorScheme.primary,
                fontSize: (valueStyle.fontSize ?? 14) + 1,
              ),
            ),
            if (cacheRead > 0 || cacheWrite > 0) ...[
              const SizedBox(height: 6),
              _PopupRow(
                label: AppLocalizations.of(context)!.tokenPopupCacheHit,
                value: (cacheHitRatio * 100).round(),
                suffix: '%',
                keyStyle: keyStyle,
                valueStyle: cacheValueStyle,
                accent: Colors.green,
              ),
              const SizedBox(height: 6),
              _CacheHitBar(
                ratio: cacheHitRatio,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite,
                prompt: promptTokens,
              ),
            ],
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context)!.tokenPopupSessionHeading.toUpperCase(),
              style: headStyle,
            ),
            const SizedBox(height: 6),
            _PopupRow(
              label: AppLocalizations.of(context)!.tokenPopupMessages,
              value: statistics.totalMessageCount,
              keyStyle: keyStyle,
              valueStyle: valueStyle,
            ),
            _PopupRow(
              label: AppLocalizations.of(context)!.tokenPopupPromptBuilds,
              value: statistics.promptBuildCount,
              keyStyle: keyStyle,
              valueStyle: valueStyle,
            ),
            _PopupRow(
              label: AppLocalizations.of(context)!.tokenPopupPromptChars,
              value: statistics.totalPromptCharacters,
              keyStyle: keyStyle,
              valueStyle: valueStyle,
            ),
            ..._buildCostSection(
              context: context,
              headStyle: headStyle,
              keyStyle: keyStyle,
              valueStyle: valueStyle,
              colorScheme: colorScheme,
              promptTokens: promptTokens,
              completionTokens: completionTokens,
              cacheRead: cacheRead,
              cacheWrite: cacheWrite,
            ),
          ],
        ),
      ),
    );
  }

  /// 1C-B：在累计统计末尾追加成本拆解。当 [activeProfile] 为 null 或
  /// 没有任一价格字段时返回空 list — UI 不渲染该分区。
  List<Widget> _buildCostSection({
    required BuildContext context,
    required TextStyle? headStyle,
    required TextStyle? keyStyle,
    required TextStyle? valueStyle,
    required ColorScheme colorScheme,
    required int promptTokens,
    required int completionTokens,
    required int cacheRead,
    required int cacheWrite,
  }) {
    if (activeProfile == null) return const <Widget>[];
    final breakdown = AiCostBreakdown.compute(
      usage: AiTokenUsage(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        cacheReadTokens: cacheRead,
        cacheCreationTokens: cacheWrite,
      ),
      profile: activeProfile,
      claudeStyle: claudeStyle,
    );
    if (breakdown == null || breakdown.isEmpty) return const <Widget>[];

    final amberStyle = valueStyle?.copyWith(color: Colors.amber.shade700);
    final l10n = AppLocalizations.of(context)!;

    return <Widget>[
      Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        height: 1,
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
      Text(
        l10n.tokenPopupCostHeading.toUpperCase(),
        style: headStyle,
      ),
      const SizedBox(height: 6),
      if (breakdown.inputUsd != null)
        _CostPopupRow(
          label: l10n.tokenPopupCostInput,
          usd: breakdown.inputUsd!,
          keyStyle: keyStyle,
          valueStyle: valueStyle,
        ),
      if (breakdown.outputUsd != null)
        _CostPopupRow(
          label: l10n.tokenPopupCostOutput,
          usd: breakdown.outputUsd!,
          keyStyle: keyStyle,
          valueStyle: valueStyle,
        ),
      if (breakdown.cacheReadUsd != null)
        _CostPopupRow(
          label: l10n.tokenPopupCostCacheRead,
          usd: breakdown.cacheReadUsd!,
          keyStyle: keyStyle,
          valueStyle: amberStyle,
        ),
      if (breakdown.cacheWriteUsd != null)
        _CostPopupRow(
          label: l10n.tokenPopupCostCacheWrite,
          usd: breakdown.cacheWriteUsd!,
          keyStyle: keyStyle,
          valueStyle: amberStyle,
        ),
      if (breakdown.totalUsd != null) ...[
        const SizedBox(height: 4),
        _CostPopupRow(
          label: l10n.tokenPopupCostTotal,
          usd: breakdown.totalUsd!,
          keyStyle: keyStyle?.copyWith(fontWeight: FontWeight.w800),
          valueStyle: valueStyle?.copyWith(color: colorScheme.primary),
        ),
      ],
    ];
  }
}

/// 单价行专用：USD 格式化展示（最高精度 4 位小数；总计/小数据时切到更密）。
class _CostPopupRow extends StatefulWidget {
  const _CostPopupRow({
    required this.label,
    required this.usd,
    this.keyStyle,
    this.valueStyle,
  });

  final String label;
  final double usd;
  final TextStyle? keyStyle;
  final TextStyle? valueStyle;

  @override
  State<_CostPopupRow> createState() => _CostPopupRowState();
}

class _CostPopupRowState extends State<_CostPopupRow> {
  bool _hovered = false;

  String _format(double v) {
    if (v == 0) return r'$0.0000';
    if (v >= 1) return '\$${v.toStringAsFixed(2)}';
    if (v >= 0.01) return '\$${v.toStringAsFixed(4)}';
    return '\$${v.toStringAsFixed(6)}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final highlight = _hovered
        ? accent.withValues(alpha: 0.10)
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: highlight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label, style: widget.keyStyle),
            Text(_format(widget.usd), style: widget.valueStyle),
          ],
        ),
      ),
    );
  }
}

/// TopBar Token 胶囊里的常驻「缓存收益」徽标：闪电图标 + 百分比 + 流体进度条。
/// 比例越高背景越绿、越饱和，给用户一眼可读的「省了多少」反馈。
class _CacheSavingsBadge extends StatelessWidget {
  const _CacheSavingsBadge({required this.percent});

  /// 0..1 之间的命中率。
  final double percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 0 命中时弱化显示；命中越高饱和度越强。
    final clamped = percent.isFinite ? percent.clamp(0.0, 1.0) : 0.0;
    final intensity = (0.5 + clamped * 0.5).clamp(0.5, 1.0);
    final fg = Color.lerp(
      Colors.green.shade400,
      Colors.green.shade700,
      clamped,
    )!;
    final bg = Colors.green.withValues(alpha: 0.12 + clamped * 0.18);
    final percentInt = (clamped * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.savings_rounded, size: 11, color: fg),
          const SizedBox(width: 3),
          _RollingNumber(
            value: percentInt,
            style: theme.textTheme.labelSmall!.copyWith(
              fontWeight: FontWeight.w800,
              color: fg.withValues(alpha: intensity),
            ),
          ),
          Text(
            '%',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: fg.withValues(alpha: intensity),
            ),
          ),
        ],
      ),
    );
  }
}

/// 缓存命中比例可视化条：左侧绿色 = cache_read（命中），中间金色 =
/// cache_creation（写入），右侧灰色 = 未缓存的 prompt。Hover 时整体亮度提升，
/// 让用户一眼看出当前 session 的缓存收益。
class _CacheHitBar extends StatefulWidget {
  const _CacheHitBar({
    required this.ratio,
    required this.cacheRead,
    required this.cacheWrite,
    required this.prompt,
  });

  final double ratio;
  final int cacheRead;
  final int cacheWrite;
  final int prompt;

  @override
  State<_CacheHitBar> createState() => _CacheHitBarState();
}

class _CacheHitBarState extends State<_CacheHitBar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 分母：cache_read + cache_write + 未缓存 prompt（promptTokens 已扣除
    // cache_read，与 read/write 不重叠）。
    final total = widget.cacheRead + widget.cacheWrite + widget.prompt;
    final readWeight = total == 0 ? 0.0 : widget.cacheRead / total;
    final writeWeight = total == 0 ? 0.0 : widget.cacheWrite / total;
    final promptWeight = total == 0
        ? 0.0
        : (widget.prompt / total).clamp(0.0, 1.0);
    final intensify = _hovered ? 1.10 : 1.0;
    final readColor = Colors.green.shade500;
    final writeColor = Colors.amber.shade600;
    final missColor = colorScheme.surfaceContainerHighest;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 8,
        decoration: BoxDecoration(
          color: missColor.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
          boxShadow: _hovered
              ? <BoxShadow>[
                  BoxShadow(
                    color: readColor.withValues(alpha: 0.18),
                    blurRadius: 4,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            if (readWeight > 0)
              Expanded(
                flex: (readWeight * 1000).round(),
                child: Container(
                  color: readColor.withValues(
                    alpha: (0.85 * intensify).clamp(0.0, 1.0),
                  ),
                ),
              ),
            if (writeWeight > 0)
              Expanded(
                flex: (writeWeight * 1000).round(),
                child: Container(
                  color: writeColor.withValues(
                    alpha: (0.78 * intensify).clamp(0.0, 1.0),
                  ),
                ),
              ),
            if (promptWeight > 0)
              Expanded(
                flex: (promptWeight * 1000).round(),
                child: const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}

class _PopupRow extends StatefulWidget {
  const _PopupRow({
    required this.label,
    required this.value,
    this.suffix,
    this.keyStyle,
    this.valueStyle,
    this.accent,
  });

  final String label;
  final int value;
  final String? suffix;
  final TextStyle? keyStyle;
  final TextStyle? valueStyle;

  /// Tinted hover highlight (defaults to theme primary when null).
  final Color? accent;

  @override
  State<_PopupRow> createState() => _PopupRowState();
}

class _PopupRowState extends State<_PopupRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? Theme.of(context).colorScheme.primary;
    final highlight = _hovered
        ? accent.withValues(alpha: 0.10)
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: highlight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label, style: widget.keyStyle),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RollingNumber(
                  value: widget.value,
                  style: widget.valueStyle ?? const TextStyle(),
                ),
                if (widget.suffix != null) ...[
                  const SizedBox(width: 2),
                  Text(widget.suffix!, style: widget.valueStyle),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Odometer-style rolling number: each digit slot slides vertically when
/// it changes, giving a Q-elastic 数字滚轮 feel without rebuilding the
/// surrounding capsule. Comma thousand-separators are inserted between
/// digit slots and remain static. Whole-number transitions feel snappier
/// than rebuilding the entire `Text` with a fade because each slot's
/// motion is independent and bounded to a single character cell.
class _RollingNumber extends StatelessWidget {
  const _RollingNumber({required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final formatted = _formatWithSeparators(value);
    final children = <Widget>[];
    for (var i = 0; i < formatted.length; i += 1) {
      final ch = formatted[i];
      if (ch == ',') {
        children.add(Text(ch, style: style));
      } else {
        children.add(_RollingDigit(digit: ch, style: style));
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  static String _formatWithSeparators(int value) {
    final raw = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i += 1) {
      final remaining = raw.length - i;
      if (i != 0 && remaining % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(raw[i]);
    }
    return value < 0 ? '-${buffer.toString()}' : buffer.toString();
  }
}

class _RollingDigit extends StatelessWidget {
  const _RollingDigit({required this.digit, required this.style});

  final String digit;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // Reserve a fixed cell width using a tabular '0' to prevent layout
    // jitter as the digit changes (some font glyphs are slightly narrower).
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final outgoing = animation.status == AnimationStatus.reverse;
        final slide = Tween<Offset>(
          begin: Offset(0, outgoing ? -0.6 : 0.6),
          end: Offset.zero,
        ).animate(animation);
        return ClipRect(
          child: SlideTransition(
            position: slide,
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: Text(
        digit,
        key: ValueKey<String>(digit),
        style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}
