import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/media_preview_dialog.dart';

void main() {
  final transparentPng = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
      'AAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    ),
  );

  Widget preview({bool tickerEnabled = true, bool disableAnimations = false}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(960, 720),
          disableAnimations: disableAnimations,
        ),
        child: TickerMode(
          enabled: tickerEnabled,
          child: MediaPreviewDialog.bytes(
            bytes: transparentPng,
            title: 'preview.png',
          ),
        ),
      ),
    );
  }

  Finder dialogSizeAnimation() {
    return find.descendant(
      of: find.byType(MediaPreviewDialog),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedSize && widget.curve == Curves.easeOutCubic,
      ),
    );
  }

  testWidgets('MediaPreviewDialog disables size motion with ticker off', (
    tester,
  ) async {
    await tester.pumpWidget(preview(tickerEnabled: false));

    final animatedSize = tester.widget<AnimatedSize>(dialogSizeAnimation());
    expect(animatedSize.duration, Duration.zero);
  });

  testWidgets(
    'MediaPreviewDialog disables size motion when animations are off',
    (tester) async {
      await tester.pumpWidget(preview(disableAnimations: true));

      final animatedSize = tester.widget<AnimatedSize>(dialogSizeAnimation());
      expect(animatedSize.duration, Duration.zero);
    },
  );
}
