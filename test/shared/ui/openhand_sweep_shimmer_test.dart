import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_sweep_shimmer.dart';

void main() {
  testWidgets('骨架扫光仅覆盖子组件像素', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OpenHandSweepShimmer(
          sweepColor: Colors.white24,
          maskToChildAlpha: true,
          child: SizedBox(width: 120, height: 12),
        ),
      ),
    );

    final shimmer = find.byType(OpenHandSweepShimmer);
    expect(
      find.descendant(of: shimmer, matching: find.byType(ShaderMask)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: shimmer, matching: find.byType(Stack)),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('普通扫光保持覆盖整个容器', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OpenHandSweepShimmer(
          sweepColor: Colors.white24,
          child: SizedBox(width: 120, height: 12),
        ),
      ),
    );

    final shimmer = find.byType(OpenHandSweepShimmer);
    expect(
      find.descendant(of: shimmer, matching: find.byType(Stack)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: shimmer, matching: find.byType(ShaderMask)),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
