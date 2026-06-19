import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('product code uses showAnimatedDialog instead of raw dialog routes', () {
    final violations = <String>[];
    final libDir = Directory('lib');
    final rawDialogPattern = RegExp(r'\bshow(?:General)?Dialog\s*(?:<|\()');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (entity.path == 'lib/shared/ui/animated_dialog.dart') {
        continue;
      }
      final content = entity.readAsStringSync();
      for (final match in rawDialogPattern.allMatches(content)) {
        final line =
            '\n'.allMatches(content.substring(0, match.start)).length + 1;
        violations.add('${entity.path}:$line');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Use showAnimatedDialog or an OpenHand dialog wrapper so entrance '
          'and exit animations honor global dialog animation settings.',
    );
  });
}
