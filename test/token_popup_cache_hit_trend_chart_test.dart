import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';
import 'package:openhand/features/home/widgets/token_popup_cache_hit_trend_chart.dart';
import 'package:openhand/l10n/app_localizations.dart';

void main() {
  testWidgets('hover content remains mounted until its exit completes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(trend: _trend(<double>[0.12, 0.37, 0.81])),
    );
    final gesture = await _hoverChartCenter(tester);
    await tester.pumpAndSettle();
    expect(find.text('37%'), findsOneWidget);

    await gesture.moveTo(const Offset(1, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('37%'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('37%'), findsNothing);
    await gesture.removePointer();
  });

  testWidgets(
    'metric refresh preserves hover but identity replacement clears it',
    (tester) async {
      late StateSetter update;
      var trend = _trend(<double>[0.12, 0.37, 0.81]);
      await tester.pumpWidget(
        _testApp(
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return TokenPopupCacheHitTrendChart(
                trend: trend,
                displayMode: SessionCacheHitDisplayMode.includeExpiredMisses,
              );
            },
          ),
        ),
      );
      final gesture = await _hoverChartCenter(tester);
      await tester.pumpAndSettle();
      expect(find.text('37%'), findsOneWidget);

      update(() => trend = _trend(<double>[0.12, 0.63, 0.81]));
      await tester.pump();

      expect(find.text('37%'), findsNothing);
      expect(find.text('63%'), findsOneWidget);

      update(
        () => trend = _trend(<double>[
          0.12,
          0.63,
          0.81,
        ], messageIdPrefix: 'replacement'),
      );
      await tester.pump();

      expect(find.text('63%'), findsNothing);
      await gesture.removePointer();
    },
  );

  testWidgets('display mode change clears relative-index hover state', (
    tester,
  ) async {
    late StateSetter update;
    var mode = SessionCacheHitDisplayMode.includeExpiredMisses;
    final trend = _trend(<double>[0.12, 0.37, 0.81]);
    await tester.pumpWidget(
      _testApp(
        child: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return TokenPopupCacheHitTrendChart(
              trend: trend,
              displayMode: mode,
            );
          },
        ),
      ),
    );
    final gesture = await _hoverChartCenter(tester);
    await tester.pumpAndSettle();
    expect(find.text('37%'), findsOneWidget);

    update(() => mode = SessionCacheHitDisplayMode.excludeExpiredMisses);
    await tester.pump();

    expect(find.text('37%'), findsNothing);
    await gesture.removePointer();
  });

  testWidgets('reduced motion finishes an active exit without stale cleanup', (
    tester,
  ) async {
    late StateSetter update;
    var disableAnimations = false;
    final trend = _trend(<double>[0.12, 0.37, 0.81]);
    await tester.pumpWidget(
      _testApp(
        child: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: disableAnimations),
              child: TokenPopupCacheHitTrendChart(
                trend: trend,
                displayMode: SessionCacheHitDisplayMode.includeExpiredMisses,
              ),
            );
          },
        ),
      ),
    );
    final gesture = await _hoverChartCenter(tester);
    await tester.pumpAndSettle();
    expect(find.text('37%'), findsOneWidget);

    await gesture.moveTo(const Offset(1, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('37%'), findsOneWidget);

    update(() => disableAnimations = true);
    await tester.pump();
    expect(find.text('37%'), findsNothing);

    // The cleanup callback still converges the retained exit state without
    // briefly rebuilding the now-disabled exit transition at full opacity.
    await tester.pump();
    expect(find.text('37%'), findsNothing);

    await gesture.moveTo(tester.getRect(_chartInteractionRegion()).center);
    await tester.pump();
    expect(find.text('37%'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('37%'), findsOneWidget);
    await gesture.removePointer();
  });

  testWidgets('tiny chart height keeps tooltip positioning bounds valid', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        child: TokenPopupCacheHitTrendChart(
          trend: _trend(<double>[0.12, 0.37, 0.81]),
          height: 20,
          displayMode: SessionCacheHitDisplayMode.includeExpiredMisses,
        ),
      ),
    );

    final gesture = await _hoverChartCenter(tester);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('37%'), findsOneWidget);
    await gesture.removePointer();
  });

  testWidgets('zoom persists in the filtered display viewport', (tester) async {
    await tester.pumpWidget(
      _testApp(
        trend: _trend(List<double>.generate(11, (index) => 0.2 + index * 0.05)),
        displayMode: SessionCacheHitDisplayMode.excludeExpiredMisses,
      ),
    );

    expect(find.text('Reset'), findsNothing);
    await tester.tap(find.text('Zoom'));
    await tester.pump();

    expect(find.text('Reset'), findsOneWidget);
  });

  testWidgets('trackpad cumulative scale is applied incrementally', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        trend: _trend(List<double>.generate(11, (index) => 0.2 + index * 0.05)),
      ),
    );
    final interactionRegion = _chartInteractionRegion();
    final center = tester.getRect(interactionRegion).center;
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );

    await gesture.panZoomStart(center);
    await gesture.panZoomUpdate(center, scale: 1.2);
    await tester.pump();
    await gesture.panZoomUpdate(center, scale: 1.4);
    await tester.pump();
    await gesture.panZoomEnd();
    await tester.pump();

    // A cumulative 1.4x gesture leaves turns 2...10 visible. Treating both
    // updates as fresh multipliers would over-zoom to turns 3...9.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
  });
}

Widget _testApp({
  SessionCacheHitTrend? trend,
  SessionCacheHitDisplayMode displayMode =
      SessionCacheHitDisplayMode.includeExpiredMisses,
  Widget? child,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(48),
        child:
            child ??
            TokenPopupCacheHitTrendChart(
              trend: trend!,
              displayMode: displayMode,
            ),
      ),
    ),
  );
}

Future<TestGesture> _hoverChartCenter(WidgetTester tester) async {
  final hoverRegion = _chartInteractionRegion();
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(1, 1));
  await gesture.moveTo(tester.getRect(hoverRegion).center);
  return gesture;
}

Finder _chartInteractionRegion() {
  final hoverRegion = find.byWidgetPredicate(
    (widget) =>
        widget is MouseRegion &&
        widget.onHover != null &&
        widget.onExit != null,
  );
  expect(hoverRegion, findsOneWidget);
  return hoverRegion;
}

SessionCacheHitTrend _trend(
  List<double> ratios, {
  String messageIdPrefix = 'message',
}) {
  final timestamp = DateTime.utc(2026);
  final points = <SessionCacheHitTurnPoint>[
    for (var index = 0; index < ratios.length; index += 1)
      SessionCacheHitTurnPoint(
        turnIndex: index + 1,
        starterMessageId: '$messageIdPrefix-${index + 1}',
        starterMessageKind: 'user',
        starterOrigin: 'user',
        timestamp: timestamp.add(Duration(minutes: index)),
        hitRatio: ratios[index],
        averageHitRatio: ratios[index],
        promptTokens: 100,
        cacheReadTokens: (ratios[index] * 100).round(),
        cacheWriteTokens: 0,
        idleGapSeconds: index == 0 ? null : 60,
        ttlSuspected: false,
        prefixDriftSuspected: false,
        automaticProviderMissSuspected: false,
      ),
  ];
  return SessionCacheHitTrend(
    points: points,
    averageHitRatio: ratios.isEmpty
        ? 0
        : ratios.reduce((left, right) => left + right) / ratios.length,
    claudeStyle: false,
  );
}
