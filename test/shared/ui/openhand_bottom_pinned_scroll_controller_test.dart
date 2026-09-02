import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_bottom_pinned_scroll_controller.dart';

void main() {
  testWidgets('仅在用户到达底部后跟随内容高度变化', (tester) async {
    final controller = OpenHandBottomPinnedScrollController();
    final contentKey = GlobalKey<_DynamicListState>();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 300,
          child: _DynamicList(key: contentKey, controller: controller),
        ),
      ),
    );

    contentKey.currentState!.setTrailingHeight(240);
    await tester.pump();
    expect(controller.offset, 0);

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(
      controller.offset,
      closeTo(controller.position.maxScrollExtent, 0.5),
    );

    contentKey.currentState!.setTrailingHeight(480);
    await tester.pump();
    expect(
      controller.offset,
      closeTo(controller.position.maxScrollExtent, 0.5),
    );

    contentKey.currentState!.setTrailingHeight(360);
    await tester.pump();
    expect(
      controller.offset,
      closeTo(controller.position.maxScrollExtent, 0.5),
    );

    await tester.drag(find.byType(ListView), const Offset(0, 160));
    await tester.pumpAndSettle();
    final offsetBeforeGrowth = controller.offset;
    expect(controller.position.extentAfter, greaterThan(2));

    contentKey.currentState!.setTrailingHeight(720);
    await tester.pump();
    expect(controller.offset, closeTo(offsetBeforeGrowth, 0.5));
    expect(controller.offset, lessThan(controller.position.maxScrollExtent));
  });
}

class _DynamicList extends StatefulWidget {
  const _DynamicList({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<_DynamicList> createState() => _DynamicListState();
}

class _DynamicListState extends State<_DynamicList> {
  double _trailingHeight = 0;

  void setTrailingHeight(double value) {
    setState(() => _trailingHeight = value);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.controller,
      physics: const ClampingScrollPhysics(),
      children: [
        for (var index = 0; index < 8; index++)
          SizedBox(height: 100, child: Text('条目 $index')),
        SizedBox(height: _trailingHeight),
      ],
    );
  }
}
