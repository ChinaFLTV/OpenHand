import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';
import 'package:openhand/features/home/widgets/token_popup_cache_hit_trend_chart.dart';
import 'package:openhand/l10n/app_localizations.dart';

void main() {
  testWidgets('toggle switches between filtered and full cache-hit summaries', (
    tester,
  ) async {
    final trend = SessionCacheHitTrend(
      averageHitRatio: 60 / 260,
      claudeStyle: true,
      points: <SessionCacheHitTurnPoint>[
        SessionCacheHitTurnPoint(
          turnIndex: 1,
          timestamp: DateTime.utc(2026),
          hitRatio: 0,
          averageHitRatio: 0,
          promptTokens: 100,
          cacheReadTokens: 0,
          cacheWriteTokens: 0,
          idleGapSeconds: null,
          ttlSuspected: false,
          prefixDriftSuspected: false,
        ),
        SessionCacheHitTurnPoint(
          turnIndex: 2,
          timestamp: DateTime.utc(2026, 1, 1, 0, 0, 1),
          hitRatio: 60 / 160,
          averageHitRatio: 60 / 160,
          promptTokens: 100,
          cacheReadTokens: 60,
          cacheWriteTokens: 0,
          idleGapSeconds: 30,
          ttlSuspected: false,
          prefixDriftSuspected: false,
        ),
        SessionCacheHitTurnPoint(
          turnIndex: 3,
          timestamp: DateTime.utc(2026, 1, 1, 0, 0, 2),
          hitRatio: 0,
          averageHitRatio: 60 / 260,
          promptTokens: 100,
          cacheReadTokens: 0,
          cacheWriteTokens: 0,
          idleGapSeconds: 7201,
          ttlSuspected: true,
          prefixDriftSuspected: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'Hans'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: TokenPopupCacheHitTrendChart(trend: trend),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('平均: 38%'), findsOneWidget);
    expect(find.text('排除极端值'), findsOneWidget);
    expect(find.text('包括全部'), findsOneWidget);

    await tester.tap(find.text('包括全部'));
    await tester.pumpAndSettle();

    expect(find.text('排除极端值'), findsOneWidget);
    expect(find.text('包括全部'), findsOneWidget);
  });
}
