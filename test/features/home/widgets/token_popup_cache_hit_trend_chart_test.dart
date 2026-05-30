import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/home/model/session_cache_hit_trend.dart';
import 'package:openhand/features/home/widgets/token_popup_cache_hit_trend_chart.dart';
import 'package:openhand/l10n/app_localizations.dart';

void main() {
  testWidgets('renders axes, title and reset affordance after zoom', (
    tester,
  ) async {
    final trend = SessionCacheHitTrend(
      averageHitRatio: 0.36,
      points: List<SessionCacheHitTurnPoint>.generate(
        8,
        (index) => SessionCacheHitTurnPoint(
          turnIndex: index + 1,
          timestamp: DateTime.utc(2026, 1, 1, 0, 0, index),
          hitRatio: (index + 1) / 10,
          averageHitRatio: 0.36,
          promptTokens: 100,
          cacheReadTokens: 20,
          idleGapSeconds: null,
          ttlSuspected: false,
          prefixDriftSuspected: false,
        ),
      ),
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
              width: 360,
              child: TokenPopupCacheHitTrendChart(trend: trend),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('缓存命中率趋势'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.textContaining('平均'), findsWidgets);
    expect(find.text('重置'), findsNothing);

    await tester.tap(find.text('缩放'));
    await tester.pump();

    expect(find.text('重置'), findsOneWidget);
  });
}
