part of 'openhand_home_page.dart';

class _TokenDial extends StatefulWidget {
  const _TokenDial({
    required this.totalTokens,
    this.cacheReadTokens,
    this.cacheCreationTokens,
  });

  final int totalTokens;
  final int? cacheReadTokens;
  final int? cacheCreationTokens;

  @override
  State<_TokenDial> createState() => _TokenDialState();
}

class _TokenDialState extends State<_TokenDial> {
  late int _previousTokens;
  late int _previousCacheRead;

  @override
  void initState() {
    super.initState();
    _previousTokens = widget.totalTokens;
    _previousCacheRead = widget.cacheReadTokens ?? 0;
  }

  @override
  void didUpdateWidget(covariant _TokenDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.totalTokens != widget.totalTokens) {
      _previousTokens = oldWidget.totalTokens;
    }
    if (oldWidget.cacheReadTokens != widget.cacheReadTokens) {
      _previousCacheRead = oldWidget.cacheReadTokens ?? 0;
    }
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
    final cacheStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: Colors.green.shade600,
    );
    final hasCache = (widget.cacheReadTokens ?? 0) > 0;
    return Container(
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
            hasCache ? Icons.bolt_rounded : Icons.confirmation_number_rounded,
            size: 14,
            color: hasCache ? Colors.green.shade600 : colorScheme.primary,
          ),
          const SizedBox(width: 6),
          if (hasCache) ...[
            TweenAnimationBuilder<int>(
              tween: IntTween(
                begin: _previousCacheRead,
                end: widget.cacheReadTokens ?? 0,
              ),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Text('$value', style: cacheStyle);
              },
            ),
            const SizedBox(width: 4),
            Text('Cached', style: cacheStyle),
            Container(
              width: 1,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: colorScheme.outlineVariant,
            ),
          ],
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: _previousTokens, end: widget.totalTokens),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Text('$value', style: numberStyle);
            },
          ),
          const SizedBox(width: 6),
          Text(
            hasCache
                ? _localizedText(context, zh: '总计', en: 'Total')
                : _localizedText(context, zh: 'Token', en: 'Token'),
            style: labelStyle,
          ),
        ],
      ),
    );
  }
}

