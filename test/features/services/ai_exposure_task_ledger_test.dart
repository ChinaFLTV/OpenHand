import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/widgets/ai_exposure_monitoring_dialogs.dart';

void main() {
  testWidgets('任务账本来源筛选框与相邻筛选框底边对齐', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AiExposureTaskLedger(tasks: [])),
      ),
    );

    Finder fieldFinder(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(InputDecorator),
    );
    Rect fieldRect(String label) => tester.getRect(fieldFinder(label));

    final status = fieldRect('状态');
    final source = fieldRect('来源');
    final time = fieldRect('时间');
    expect(source.height, status.height);
    expect(source.height, time.height);
    expect(source.bottom, status.bottom);
    expect(source.bottom, time.bottom);
    final sourceDecorator = tester.widget<InputDecorator>(fieldFinder('来源'));
    expect(
      sourceDecorator.decoration.contentPadding,
      const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
    );
  });

  testWidgets('任务账本桌面筛选栏铺满横向空间', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in [800.0, 900.0, 1400.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AiExposureTaskLedger(tasks: [])),
        ),
      );

      final ledger = tester.getRect(find.byType(AiExposureTaskLedger));
      final search = tester.getRect(find.byType(TextField));
      final sort = tester.getRect(
        find.ancestor(
          of: find.text('排序'),
          matching: find.byType(InputDecorator),
        ),
      );
      final horizontalInset = search.left - ledger.left;
      expect(
        sort.right,
        closeTo(ledger.right - horizontalInset, 0.01),
        reason: '$width 宽度下筛选栏未铺满',
      );
      expect(tester.takeException(), isNull);
    }
  });
}
