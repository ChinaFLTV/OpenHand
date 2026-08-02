import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/services_controller.dart';
import 'package:openhand/features/services/widgets/ai_exposure_dialogs.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('服务状态仪表盘适配宽窄视口', (tester) async {
    final controller = ServicesController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.shutdown();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    await tester.pumpWidget(
      ChangeNotifierProvider<ServicesController>.value(
        value: controller,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showAiExposureStatusDialog(context),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('服务状态'), findsOneWidget);
    expect(find.text('持久化与完整性'), findsOneWidget);
    expect(find.text('运行依赖矩阵'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(480, 760));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
