import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_inline_notice.dart';

void main() {
  Widget notice() {
    return const OpenHandInlineNotice(
      icon: Icons.info_outline,
      color: Colors.blue,
      foregroundColor: Colors.white,
      message: 'notice',
      showCopyAction: false,
      showCloseAction: false,
    );
  }

  Finder noticeDescendant(Type type) {
    return find.descendant(
      of: find.byType(OpenHandInlineNotice),
      matching: find.byType(type),
    );
  }

  Finder slotDescendant(Type type) {
    return find.descendant(
      of: find.byType(OpenHandInlineNoticeSlot),
      matching: find.byType(type),
    );
  }

  testWidgets('OpenHandInlineNotice renders directly when ticker is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: TickerMode(enabled: false, child: notice())),
    );

    expect(find.text('notice'), findsOneWidget);
    expect(noticeDescendant(AnimatedSwitcher), findsNothing);
    expect(noticeDescendant(SizeTransition), findsNothing);
  });

  testWidgets(
    'OpenHandInlineNotice renders directly when animations disabled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: notice(),
          ),
        ),
      );

      expect(find.text('notice'), findsOneWidget);
      expect(noticeDescendant(AnimatedSwitcher), findsNothing);
      expect(noticeDescendant(SizeTransition), findsNothing);
    },
  );

  testWidgets('OpenHandInlineNoticeSlot renders directly without motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TickerMode(
          enabled: false,
          child: OpenHandInlineNoticeSlot(child: Text('slot')),
        ),
      ),
    );

    expect(find.text('slot'), findsOneWidget);
    expect(slotDescendant(AnimatedSwitcher), findsNothing);
    expect(slotDescendant(SizeTransition), findsNothing);
    expect(slotDescendant(SlideTransition), findsNothing);
  });

  testWidgets(
    'OpenHandInlineNoticeSlot renders empty directly without motion',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TickerMode(
            enabled: false,
            child: OpenHandInlineNoticeSlot(child: null),
          ),
        ),
      );

      expect(slotDescendant(AnimatedSwitcher), findsNothing);
      expect(slotDescendant(SizeTransition), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    },
  );
}
