import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';
import 'package:openhand/features/home/widgets/token_popup_cache_hit_trend_chart.dart';
import 'package:openhand/l10n/app_localizations.dart';

void main() {
  testWidgets('tapping a trend point selects its exact conversation turn', (
    tester,
  ) async {
    SessionCacheHitTurnPoint? selectedPoint;
    final points = <SessionCacheHitTurnPoint>[
      _point(turnIndex: 2, messageId: 'round-2', hitRatio: 0.5),
      _point(turnIndex: 3, messageId: 'round-3', hitRatio: 0.8),
    ];

    await tester.pumpWidget(
      _TestApp(
        child: TokenPopupCacheHitTrendChart(
          trend: SessionCacheHitTrend(
            points: points,
            averageHitRatio: 0.65,
            claudeStyle: true,
          ),
          height: 180,
          onPointSelected: (point) => selectedPoint = point,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final paints = find.descendant(
      of: find.byType(TokenPopupCacheHitTrendChart),
      matching: find.byType(CustomPaint),
    );
    expect(paints, findsNWidgets(2));
    final paintBox = tester.renderObject<RenderBox>(paints.first);
    const chartPadding = EdgeInsets.fromLTRB(30, 8, 8, 22);
    final chartHeight = paintBox.size.height - chartPadding.vertical;
    final pointPosition =
        tester.getTopLeft(paints.first) +
        Offset(
          chartPadding.left,
          chartPadding.top + chartHeight * (1 - points.first.hitRatio),
        );

    await tester.tapAt(pointPosition);
    await tester.pump();

    expect(selectedPoint?.starterMessageId, 'round-2');
    expect(selectedPoint?.turnIndex, 2);
    expect(find.text('Turn 2'), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: SizedBox(width: 420, child: child)),
      ),
    );
  }
}

SessionCacheHitTurnPoint _point({
  required int turnIndex,
  required String messageId,
  required double hitRatio,
}) {
  return SessionCacheHitTurnPoint(
    turnIndex: turnIndex,
    starterMessageId: messageId,
    starterMessageKind: 'user',
    starterOrigin: 'app',
    timestamp: DateTime.utc(2026, 7, 14, 12, turnIndex),
    hitRatio: hitRatio,
    averageHitRatio: hitRatio,
    promptTokens: 100,
    cacheReadTokens: (hitRatio * 100).round(),
    cacheWriteTokens: 0,
    idleGapSeconds: 30,
    ttlSuspected: false,
    prefixDriftSuspected: false,
    automaticProviderMissSuspected: false,
  );
}
