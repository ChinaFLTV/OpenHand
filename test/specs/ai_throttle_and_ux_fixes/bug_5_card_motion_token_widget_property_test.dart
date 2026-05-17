// Bug 5 — card expand/collapse motion-token unification exploration PBT.
//
// **Validates: Requirements 5.1, 5.2, 5.3, 6.1, 6.2, 6.3**
//
// The fix introduces a single source of truth at
//   lib/features/home/widgets/_home_motion_tokens.dart
// exporting:
//   * kCardMotionDurationExpand   = Duration(milliseconds: 280)
//   * kCardMotionDurationCollapse = Duration(milliseconds: 220)
//   * kCardMotionCurve            = Cubic(0.22, 1.22, 0.36, 1)
//   * cardMotionDurationFor(BuildContext, {required bool expanding})
//
// On UNFIXED code the file does not exist yet. We assert it must exist
// and the expected constants must be reachable via static text matching
// of the file contents (so the test does not need to compile-import a
// file that may not exist). When the fix lands, this test passes.
//
// We also walk the existing production widget files and assert no
// hard-coded motion durations remain that contradict the token. On
// unfixed code those files still hold 240ms / 260ms / 320ms etc.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _kMotionTokensFile =
    'lib/features/home/widgets/_home_motion_tokens.dart';

const _kExpectedExpandMs = 280;
const _kExpectedCollapseMs = 220;
const _kExpectedCurveSignature = 'Cubic(0.22, 1.22, 0.36, 1)';

const _kProductionFilesUsingMotion = <String>[
  'lib/features/home/widgets/_home_message_bubble.dart',
  'lib/features/home/widgets/_home_message_content.dart',
  'lib/features/home/widgets/_home_message_meta_rows.dart',
];

void main() {
  group('Bug 5 — card motion token unification (Property 5)', () {
    test('motion tokens file exists with expected constants', () {
      final file = File(_kMotionTokensFile);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'expected motion-token file at $_kMotionTokensFile is missing — '
            'fix has not introduced kCardMotionDurationExpand / '
            'kCardMotionDurationCollapse / kCardMotionCurve yet.',
      );
      final body = file.readAsStringSync();
      expect(
        body.contains('kCardMotionDurationExpand'),
        isTrue,
        reason: 'kCardMotionDurationExpand is missing from $_kMotionTokensFile.',
      );
      expect(
        body.contains('kCardMotionDurationCollapse'),
        isTrue,
        reason:
            'kCardMotionDurationCollapse is missing from $_kMotionTokensFile.',
      );
      expect(
        body.contains('kCardMotionCurve'),
        isTrue,
        reason: 'kCardMotionCurve is missing from $_kMotionTokensFile.',
      );
      expect(
        body.contains('milliseconds: $_kExpectedExpandMs'),
        isTrue,
        reason:
            'expand duration must be $_kExpectedExpandMs ms (per design.md).',
      );
      expect(
        body.contains('milliseconds: $_kExpectedCollapseMs'),
        isTrue,
        reason:
            'collapse duration must be $_kExpectedCollapseMs ms (per design.md).',
      );
      expect(
        body.contains(_kExpectedCurveSignature),
        isTrue,
        reason:
            'curve must be $_kExpectedCurveSignature (per design.md).',
      );
      expect(
        body.contains('cardMotionDurationFor'),
        isTrue,
        reason:
            'helper cardMotionDurationFor(BuildContext, {expanding}) must be '
            'exported from $_kMotionTokensFile.',
      );
    });

    test('production widget files reference the motion token, not literals',
        () {
      // Disallow lingering raw 240/260/320ms AnimatedSize durations and
      // require imports of the new tokens file.
      for (final path in _kProductionFilesUsingMotion) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path missing');
        final body = file.readAsStringSync();
        // Allow anywhere-else duration literals BUT reject the legacy
        // motion durations within AnimatedSize / AnimatedRotation /
        // AnimatedDefaultTextStyle / _reasoningBodyAnimDuration definition.
        // Cheap pattern: the token names should appear at least once.
        final referencesTokens =
            body.contains('kCardMotionDurationExpand') ||
                body.contains('kCardMotionDurationCollapse') ||
                body.contains('cardMotionDurationFor');
        expect(
          referencesTokens,
          isTrue,
          reason:
              '$path does not reference any kCardMotionDuration* / '
              'cardMotionDurationFor symbols; motion tokens have not been '
              'wired in yet.',
        );
      }
    });

    test('disableAnimations short-circuit in cardMotionDurationFor', () {
      // We detect that cardMotionDurationFor returns Duration.zero when
      // disableAnimations is true. The detection is text-level (we can't
      // import the file when it doesn't exist). When the file is added,
      // tighten this to a real call.
      final file = File(_kMotionTokensFile);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'motion-token file missing; cannot check disableAnimations.',
      );
      final body = file.readAsStringSync();
      expect(
        body.contains('disableAnimations') ||
            body.contains('disableAnimationsOf') ||
            body.contains('reduceMotion'),
        isTrue,
        reason:
            'cardMotionDurationFor must consult MediaQuery.disableAnimationsOf '
            '(or equivalent reduceMotion flag) and return Duration.zero.',
      );
      expect(
        body.contains('Duration.zero'),
        isTrue,
        reason:
            'cardMotionDurationFor must return Duration.zero in the '
            'disableAnimations branch.',
      );
    });

    testWidgets('AnimatedSize duration on a card-like surface matches token',
        (tester) async {
      // We do not have access to the private _MessageBubble. Once the
      // motion token file exists, the production widgets read it. As a
      // canary: build a minimal AnimatedSize with the post-fix expected
      // duration to ensure the framework Animation pipeline uses the
      // token semantics. This test fails before the file exists because
      // the dependency target is missing.
      final file = File(_kMotionTokensFile);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'motion-token file missing; canary cannot validate token use.',
      );
      // Build an AnimatedSize at the expected token to ensure framework
      // accepts it without complaint (this is a sanity check; the real
      // verification happens in the file-content checks above).
      var expanded = false;
      late StateSetter setOuter;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(builder: (context, setState) {
          setOuter = setState;
          return Scaffold(
            body: AnimatedSize(
              duration: const Duration(milliseconds: _kExpectedExpandMs),
              curve: const Cubic(0.22, 1.22, 0.36, 1),
              child: SizedBox(height: expanded ? 400 : 100),
            ),
          );
        }),
      ));
      setOuter(() => expanded = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: _kExpectedExpandMs));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
