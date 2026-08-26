import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/startup_failure_view.dart';

void main() {
  testWidgets('启动失败页完整展示结构化信息', (tester) async {
    await tester.pumpWidget(
      const OpenHandStartupFailureApp(
        title: '数据库初始化失败',
        reason: '目录不可写',
        suggestionsTitle: '建议处理',
        suggestions: <String>['检查目录权限', '确认磁盘空间'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OpenHand'), findsOneWidget);
    expect(find.text('数据库初始化失败'), findsOneWidget);
    expect(find.text('目录不可写'), findsOneWidget);
    expect(find.text('检查目录权限'), findsOneWidget);
    expect(find.text('确认磁盘空间'), findsOneWidget);
  });

  testWidgets('紧凑窗口下长文本不发生布局溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const OpenHandStartupFailureApp(
        title: '应用数据库初始化失败，请检查当前运行环境',
        reason: '数据库目录当前不可写，应用无法完成必要的启动数据迁移和运行状态恢复。',
        suggestionsTitle: '建议处理',
        suggestions: <String>[
          '检查 Application Support 目录权限以及其他 OpenHand 实例的占用状态。',
          '确认磁盘剩余空间充足后重新启动应用。',
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
