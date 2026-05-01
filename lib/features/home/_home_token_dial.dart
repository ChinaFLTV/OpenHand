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
            _RollingNumber(
              value: widget.cacheReadTokens ?? 0,
              style: cacheStyle ?? const TextStyle(),
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
          _RollingNumber(
            value: widget.totalTokens,
            style: numberStyle ?? const TextStyle(),
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
      duration: const Duration(milliseconds: 360),
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
