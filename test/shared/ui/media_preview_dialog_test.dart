import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/l10n/app_localizations.dart';
import 'package:openhand/shared/ui/media_preview_dialog.dart';

void main() {
  testWidgets('媒体预览可以渲染本地 SVG 文件', (tester) async {
    late final Directory directory;
    late final File file;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'openhand-media-preview-test-',
      );
      file = File('${directory.path}/图标.svg');
      await file.writeAsString('''
<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80">
  <rect width="120" height="80" rx="12" fill="#5b7cfa"/>
  <circle cx="60" cy="40" r="20" fill="#ffffff"/>
</svg>
''');
    });
    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaPreviewDialog.file(
            filePath: file.path,
            title: file.path,
            mimeType: 'image/svg+xml',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      await tester.runAsync(() => directory.delete(recursive: true));
    }
  });
}
