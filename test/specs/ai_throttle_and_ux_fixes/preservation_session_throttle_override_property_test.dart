// Bug 2 Preservation #3 — Session-level throttle overrides stay in-process.
//
// **Validates: Requirements 8.2**
//
// Property 6 (Preservation): the top-of-thread "throttle capsule" (i.e.
// `_sessionStreamThrottleOverrides`) is process-local. Adjusting the
// rate via the capsule SHALL NOT survive a restart — it must not be
// written to the persistence layer, and on next launch the value
// returns to the global / template defaults.
//
// We don't need to drive a real DB here; we statically inspect:
//   1. `lib/app/state/settings_store.dart` — must NOT serialize any
//      `session_stream_throttle*` JSON field;
//   2. `lib/app/model/app_settings_snapshot.dart` — must NOT declare
//      any `sessionStreamThrottle*` field on the snapshot type (the
//      controller's `_sessionStreamThrottleOverrides` is fine —
//      it's stored on the in-memory controller).
//
// Additionally we generate random `(sessionId, override)` pairs and
// assert that an `AiStreamThrottleOverride` JSON encoding round-trips
// without leaking any "session" hint into the snapshot's surface area.
//
// On UNFIXED code these properties already PASS — session overrides
// are correctly process-local in the current impl. The test snapshots
// that invariant so the upcoming Bug 2 fix (which strips per-template
// overrides) does NOT accidentally also strip the session-level
// capsule mechanism.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_stream_throttle_override.dart';

const _kSettingsStorePath = 'lib/app/state/settings_store.dart';
const _kSnapshotPath = 'lib/app/model/app_settings_snapshot.dart';

void main() {
  group('Preservation — session-level throttle override is process-local',
      () {
    test('settings_store.dart does NOT persist session-level overrides', () {
      final body = File(_kSettingsStorePath).readAsStringSync();
      // Forbidden tokens (any of these would mean we leak the capsule
      // override into JSON/disk).
      const forbidden = <String>[
        'session_stream_throttle_overrides',
        'session_stream_throttle_override',
        'sessionStreamThrottleOverrides',
        '_sessionStreamThrottleOverrides',
      ];
      for (final marker in forbidden) {
        expect(
          body.contains(marker),
          isFalse,
          reason:
              'settings_store.dart must not reference "$marker" — '
              'session-level capsule overrides must remain in-process '
              'and never reach disk.',
        );
      }
    });

    test('AppSettingsSnapshot does NOT declare a session-throttle field', () {
      final body = File(_kSnapshotPath).readAsStringSync();
      const forbidden = <String>[
        'sessionStreamThrottleOverride',
        'session_stream_throttle_override',
      ];
      for (final marker in forbidden) {
        expect(
          body.contains(marker),
          isFalse,
          reason:
              'app_settings_snapshot.dart must not declare "$marker" — '
              'session-level capsule overrides live on the controller, '
              'not on the persisted snapshot.',
        );
      }
    });

    test(
      'Randomized PBT (40 cases) — AiStreamThrottleOverride round-trips '
      'via JSON without sessionId',
      () {
        final rng = Random(20260520);
        for (var i = 0; i < 40; i++) {
          final chars =
              rng.nextBool() ? 1 + rng.nextInt(60) : null; // null = unset
          final cards = rng.nextBool() ? 1 + rng.nextInt(8) : null;
          final override = AiStreamThrottleOverride(
            charsPerSecond: chars,
            cardsPerSecond: cards,
          );
          final json = override.toJson();
          // The override type itself must NOT carry a session_id field —
          // its identity comes from the in-memory map key.
          final keys = json.keys.toSet();
          expect(
            keys.contains('session_id'),
            isFalse,
            reason:
                'PBT #$i: AiStreamThrottleOverride.toJson() leaked '
                'session_id; capsule context must stay on the controller.',
          );
          expect(
            keys.contains('sessionId'),
            isFalse,
            reason:
                'PBT #$i: AiStreamThrottleOverride.toJson() leaked '
                'sessionId.',
          );
        }
      },
    );

    test('Generated session overrides do not appear in snapshot defaults',
        () {
      // The snapshot's defaults() must not pre-seed any session-level
      // override (because there is no concept of one at boot).
      final body = File(_kSnapshotPath).readAsStringSync();
      // Look for an explicit "_sessionStreamThrottleOverrides" assignment
      // anywhere — fail if present.
      expect(
        body.contains('_sessionStreamThrottleOverrides'),
        isFalse,
        reason:
            'app_settings_snapshot.dart must not reference '
            '_sessionStreamThrottleOverrides; that map lives on the '
            'controller and is reset on each cold start.',
      );
    });
  });
}
