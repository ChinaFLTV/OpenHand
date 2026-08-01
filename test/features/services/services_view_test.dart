import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/features/services/services_controller.dart';
import 'package:openhand/features/services/widgets/services_view.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

void main() {
  testWidgets('服务卡适配桌面与移动尺寸并保持智能体卡视觉结构', (tester) async {
    final services = ServicesController();
    final settings = await SettingsController.create(
      store: _MemorySettingsStore(),
    );
    addTearDown(services.shutdown);
    addTearDown(settings.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in const <Size>[Size(1280, 900), Size(390, 844)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MultiProvider(
          providers: <SingleChildWidget>[
            ChangeNotifierProvider<ServicesController>.value(value: services),
            ChangeNotifierProvider<SettingsController>.value(value: settings),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(
              cardTheme: const CardThemeData(margin: EdgeInsets.zero),
            ),
            home: const Scaffold(body: ServicesView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cardFinder = find.byKey(
        const ValueKey<String>('ai-infrastructure-exposure-service-card'),
      );
      expect(cardFinder, findsOneWidget);
      expect(find.text('AI 基础设施暴露面扫描'), findsOneWidget);
      expect(
        find.descendant(of: cardFinder, matching: find.byType(IconButton)),
        findsNWidgets(10),
      );
      final lastAction = find
          .descendant(of: cardFinder, matching: find.byType(IconButton))
          .last;
      expect(
        tester.getRect(cardFinder).right - tester.getRect(lastAction).right,
        closeTo(18, 0.01),
      );
      final card = tester.widget<Card>(cardFinder);
      final shape = card.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(22));
      expect(tester.takeException(), isNull);
    }
  });
}

class _MemorySettingsStore extends SettingsStore {
  @override
  Future<SettingsLoadResult> load() async => SettingsLoadResult(
    snapshot: AppSettingsSnapshot.defaults(),
    canPersist: false,
  );

  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {}
}
