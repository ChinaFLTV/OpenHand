import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_safe_scrollbar.dart';

void main() {
  testWidgets('控制器挂载后保持滚动子树稳定', (tester) async {
    final controller = ScrollController();
    final listKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 160,
            child: LayoutBuilder(
              builder: (_, _) => OpenHandSafeScrollbar(
                controller: controller,
                thumbVisibility: true,
                interactive: true,
                child: ListView.builder(
                  key: listKey,
                  controller: controller,
                  itemCount: 30,
                  itemBuilder: (_, index) => Tooltip(
                    message: '操作 $index',
                    child: SizedBox(height: 32, child: Text('条目 $index')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.ancestor(of: find.byKey(listKey), matching: find.byType(Scrollbar)),
      findsOneWidget,
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.ancestor(of: find.byKey(listKey), matching: find.byType(Scrollbar)),
      findsOneWidget,
    );
    expect(listKey.currentContext, isNotNull);
    expect(controller.hasClients, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
