import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/resizable_splitter.dart';

void main() {
  testWidgets('ResizableSplitter normalizes invalid sizing parameters', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 160,
          child: ResizableSplitter(
            initialLeftFraction: double.nan,
            minLeft: -100,
            minRight: double.infinity,
            handleWidth: -8,
            left: Center(child: Text('left')),
            right: Center(child: Text('right')),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('left'), findsOneWidget);
    expect(find.text('right'), findsOneWidget);
  });
}
