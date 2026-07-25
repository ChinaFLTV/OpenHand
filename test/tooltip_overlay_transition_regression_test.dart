import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_tooltip_dismissal.dart';

void main() {
  testWidgets('切换页面前关闭工具提示不会遗留脱离锚点的Overlay', (tester) async {
    final harnessKey = GlobalKey<_TooltipTransitionHarnessState>();
    await tester.pumpWidget(_TooltipTransitionHarness(key: harnessKey));

    expect(harnessKey.currentState!.showTooltip(), isTrue);
    await tester.pump(const Duration(milliseconds: 200));

    harnessKey.currentState!.openThreadPage();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('线程会话'), findsOneWidget);
  });
}

class _TooltipTransitionHarness extends StatefulWidget {
  const _TooltipTransitionHarness({super.key});

  @override
  State<_TooltipTransitionHarness> createState() =>
      _TooltipTransitionHarnessState();
}

class _TooltipTransitionHarnessState extends State<_TooltipTransitionHarness> {
  final _tooltipKey = GlobalKey<TooltipState>();
  bool _threadPageVisible = false;

  bool showTooltip() {
    return _tooltipKey.currentState?.ensureTooltipVisible() ?? false;
  }

  void openThreadPage() {
    dismissOpenHandTooltipsSafely(debugLabel: '测试页面切换前收起工具提示');
    setState(() {
      _threadPageVisible = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final media = MediaQuery.of(
              context,
            ).copyWith(alwaysUse24HourFormat: _threadPageVisible);
            return MediaQuery(
              data: media,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return AnimatedSwitcher(
                      duration: Duration.zero,
                      child: _threadPageVisible
                          ? const Center(
                              key: ValueKey<String>('thread-page'),
                              child: Text('线程会话'),
                            )
                          : Center(
                              key: const ValueKey<String>('mcp-page'),
                              child: Tooltip(
                                key: _tooltipKey,
                                message: 'MCP Tool',
                                child: const Chip(label: Text('动态 Tool')),
                              ),
                            ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
