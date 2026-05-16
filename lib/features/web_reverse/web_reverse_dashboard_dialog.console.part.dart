part of 'web_reverse_dashboard_dialog.dart';

class _ConsoleBody extends StatelessWidget {
  const _ConsoleBody({
    required this.controller,
    required this.filter,
    required this.isZh,
    required this.reduceMotion,
  });

  final WebReverseSessionController controller;
  final String filter;
  final bool isZh;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final all = controller.consoleMessages;
    final filtered = filter.isEmpty
        ? all
        : all
            .where((e) => e.text.toLowerCase().contains(filter.toLowerCase()))
            .toList(growable: false);
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            isZh ? '暂无控制台输出。' : 'No console output yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      itemBuilder: (_, idx) {
        final e = filtered[filtered.length - 1 - idx];
        final color = switch (e.level) {
          'error' => cs.errorContainer,
          'warning' => cs.tertiaryContainer,
          _ => cs.surfaceContainerHigh,
        };
        final onColor = switch (e.level) {
          'error' => cs.onErrorContainer,
          'warning' => cs.onTertiaryContainer,
          _ => cs.onSurface,
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _AnimatedAppearOnce(
            duration: reduceMotion ? Duration.zero : _kSwitchDuration,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      e.level.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        color: onColor.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      e.text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: onColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
