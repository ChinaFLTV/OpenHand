import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/interactive_image_preview.dart';

void main() {
  bool isIdentity(Matrix4 matrix) {
    final identity = Matrix4.identity().storage;
    final storage = matrix.storage;
    for (var i = 0; i < storage.length; i += 1) {
      if ((storage[i] - identity[i]).abs() > 0.0001) {
        return false;
      }
    }
    return true;
  }

  TransformationController previewController(WidgetTester tester) {
    return tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
  }

  Future<void> pumpPreview(
    WidgetTester tester, {
    bool tickerEnabled = true,
    bool disableAnimations = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: TickerMode(
            enabled: tickerEnabled,
            child: const Center(
              child: OpenHandInteractiveImagePreview(
                child: SizedBox.square(dimension: 120),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('resets immediately when ticker is disabled', (tester) async {
    await pumpPreview(tester, tickerEnabled: false);
    final controller = previewController(tester);
    controller.value = Matrix4.translationValues(24, 18, 0);

    await tester.tap(find.byType(OpenHandInteractiveImagePreview));
    await tester.pump(kDoubleTapTimeout ~/ 2);
    await tester.tap(find.byType(OpenHandInteractiveImagePreview));
    await tester.pump();

    expect(isIdentity(controller.value), isTrue);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('resets immediately when animations are disabled', (
    tester,
  ) async {
    await pumpPreview(tester, disableAnimations: true);
    final controller = previewController(tester);
    controller.value = Matrix4.translationValues(24, 18, 0);

    await tester.tap(find.byType(OpenHandInteractiveImagePreview));
    await tester.pump(kDoubleTapTimeout ~/ 2);
    await tester.tap(find.byType(OpenHandInteractiveImagePreview));
    await tester.pump();

    expect(isIdentity(controller.value), isTrue);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('settles reset animation when motion is disabled mid-flight', (
    tester,
  ) async {
    await pumpPreview(tester);
    final controller = previewController(tester);
    controller.value = Matrix4.translationValues(24, 18, 0);

    await tester.tap(find.byType(OpenHandInteractiveImagePreview));
    await tester.pump(kDoubleTapTimeout ~/ 2);
    await tester.tap(find.byType(OpenHandInteractiveImagePreview));
    await tester.pump(const Duration(milliseconds: 40));

    await pumpPreview(tester, disableAnimations: true);

    expect(isIdentity(controller.value), isTrue);
    await tester.pump(kDoubleTapTimeout);
  });
}
