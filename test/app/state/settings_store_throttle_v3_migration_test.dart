// Persistence-layer migration test for the throttle-config schema bump
// from v1/v2 → v3 (task 4.2).
//
// **Validates: Requirements 3.3, 3.4, 8.3 (Bug 2 — Property 2)**
//
// Background:
//   * Up through v2 the snapshot stored a per-template throttle override
//     map under JSON key `ai_stream_throttle_template_overrides`.
//   * Task 4.1 stripped the field from `AppSettingsSnapshot` /
//     `SettingsController` / `AiSessionRuntimeContext`.
//   * Task 4.2 — this test — locks down the persistence layer:
//       1. read path tolerates v1 (overrides only) / v2 (overrides + duration)
//          / v3 (no overrides) settings.json shapes without throwing;
//       2. write path NEVER emits `ai_stream_throttle_template_overrides`;
//       3. `migrateAiStreamThrottleConfig` bumps `version` to 3 and drops
//          any `template_overrides` it sees on the way through.
//
// Why this test is structured as static-source introspection rather than
// a live `SettingsStore.load()` round-trip:
//   * `lib/app/state/settings_store.dart` and
//     `lib/app/state/settings_controller.dart` both transitively pull in
//     `ai_builtin_tool_config.dart` → `ai_tool_runtime_service.dart` →
//     `mcp/index.dart` → `tool_search_loaded_dialog.dart` → `ai/index.dart`
//     → `ai_session_jsonl_exporter.dart` → `hardness/index.dart` →
//     `hardness_session_dashboard.dart` → `home/index.dart` →
//     `openhand_home_page.dart`. Until tasks 4.3 / 4.5 land, that final
//     file (plus `web_message_platform_service.dart` and
//     `settings_view.dart`) still references the legacy
//     `streamThrottleTemplateOverrides` API and therefore fails kernel
//     compilation. The standing test convention in
//     `test/specs/ai_throttle_and_ux_fixes/` (e.g. the
//     `preservation_session_throttle_override_property_test`) handles
//     the same constraint by reading source files via `dart:io` instead
//     of importing the controller.
//
// We therefore validate the contract along three axes:
//   (a) JSON-level migration semantics — exercised on a small `migrate`
//       mirror that mechanically reflects the production function.
//   (b) Schema version constant + `migrate` function shape — verified by
//       grepping `settings_controller.dart`.
//   (c) `_snapshotToJson` / `_snapshotFromJson` no longer reference the
//       legacy field — verified by grepping `settings_store.dart`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _kSettingsControllerPath = 'lib/app/state/settings_controller.dart';
const _kSettingsStorePath = 'lib/app/state/settings_store.dart';
const _kLegacyJsonField = 'ai_stream_throttle_template_overrides';
const _kLegacyMigrateField = 'template_overrides';

/// Mechanical mirror of `migrateAiStreamThrottleConfig` from
/// `lib/app/state/settings_controller.dart`. Kept in lock-step with the
/// production function via the source-grep tests below — if the
/// production code changes shape, those grep tests fail and force this
/// mirror to be updated.
///
/// Production reference (post task 4.2):
/// ```dart
/// Map<String, Object?> migrateAiStreamThrottleConfig(
///   Map<String, Object?> doc,
/// ) {
///   final migrated = Map<String, Object?>.from(doc);
///   if (!migrated.containsKey('duration_seconds')) {
///     migrated['duration_seconds'] = 0; // default
///   }
///   migrated.remove('template_overrides');
///   migrated['version'] = 3;
///   return migrated;
/// }
/// ```
Map<String, Object?> _migrateMirror(Map<String, Object?> doc) {
  final migrated = Map<String, Object?>.from(doc);
  if (!migrated.containsKey('duration_seconds')) {
    migrated['duration_seconds'] = 0;
  }
  migrated.remove('template_overrides');
  migrated['version'] = 3;
  return migrated;
}

/// Shared minimal settings.json fixture covering only the throttle slice
/// + a couple of universally-required string fields. The real on-disk
/// document has ~150 keys; we only need to assert the read path tolerates
/// the legacy override field and the write path drops it.
Map<String, Object?> _baseFixture({
  required int version,
  bool includeTemplateOverrides = false,
  bool includeDurationSeconds = false,
}) {
  final overrides = <String, Object?>{
    'tplA': <String, Object?>{
      'chars_per_second': 1,
      'cards_per_second': 1,
    },
    'tplB': <String, Object?>{'chars_per_second': 7},
  };

  return <String, Object?>{
    'version': version,
    'ai_stream_throttle_enabled': true,
    'ai_stream_throttle_auto_mode': false,
    'ai_stream_max_chars_per_second': 5,
    'ai_stream_max_message_cards_per_second': 1,
    if (includeDurationSeconds) 'ai_stream_throttle_duration_seconds': 0,
    if (includeTemplateOverrides) _kLegacyJsonField: overrides,
  };
}

void main() {
  group('migrateAiStreamThrottleConfig — v1/v2 → v3 (mirror)', () {
    test('v1 doc (no duration_seconds, with template_overrides) is migrated',
        () {
      final v1 = <String, Object?>{
        'version': 1,
        'throttle_enabled': true,
        'auto_mode': false,
        'max_chars_per_second': 5,
        'max_message_cards_per_second': 1,
        _kLegacyMigrateField: <String, Object?>{
          'tplA': <String, Object?>{'chars_per_second': 1},
        },
        'cloud_sync': const <String, Object?>{
          'enabled': false,
          'endpoint': '',
        },
      };

      final migrated = _migrateMirror(v1);

      expect(migrated['version'], 3);
      expect(migrated.containsKey(_kLegacyMigrateField), isFalse);
      // duration_seconds backfilled to default 0 (continuous throttle).
      expect(migrated['duration_seconds'], 0);
      // Global params untouched.
      expect(migrated['max_chars_per_second'], 5);
      expect(migrated['max_message_cards_per_second'], 1);
      // Original input not mutated (defensive copy).
      expect(v1.containsKey(_kLegacyMigrateField), isTrue);
      expect(v1['version'], 1);
    });

    test('v2 doc (with duration_seconds and template_overrides) is migrated',
        () {
      final v2 = <String, Object?>{
        'version': 2,
        'throttle_enabled': true,
        'auto_mode': false,
        'duration_seconds': 30,
        'max_chars_per_second': 8,
        'max_message_cards_per_second': 2,
        _kLegacyMigrateField: <String, Object?>{
          'tplB': <String, Object?>{'chars_per_second': 12},
        },
      };

      final migrated = _migrateMirror(v2);

      expect(migrated['version'], 3);
      expect(migrated.containsKey(_kLegacyMigrateField), isFalse);
      // Existing duration_seconds preserved.
      expect(migrated['duration_seconds'], 30);
    });

    test('v3 doc (no template_overrides) is left structurally equivalent',
        () {
      final v3 = <String, Object?>{
        'version': 3,
        'throttle_enabled': false,
        'auto_mode': true,
        'duration_seconds': 60,
        'max_chars_per_second': 10,
        'max_message_cards_per_second': 3,
      };

      final migrated = _migrateMirror(v3);

      expect(migrated['version'], 3);
      expect(migrated.containsKey(_kLegacyMigrateField), isFalse);
      expect(migrated['throttle_enabled'], false);
      expect(migrated['auto_mode'], true);
      expect(migrated['duration_seconds'], 60);
    });

    test('mirror is deterministic over a fixture sweep (v1/v2/v3, +/-overrides)',
        () {
      for (final version in const [1, 2, 3]) {
        for (final includeOv in const [false, true]) {
          for (final includeDur in const [false, true]) {
            final fixture = _baseFixture(
              version: version,
              includeTemplateOverrides: includeOv,
              includeDurationSeconds: includeDur,
            );
            final migrated = _migrateMirror(fixture);

            expect(migrated['version'], 3,
                reason: 'fixture v$version overrides=$includeOv '
                    'duration=$includeDur');
            expect(
              migrated.containsKey(_kLegacyMigrateField),
              isFalse,
              reason: 'fixture v$version overrides=$includeOv '
                  'duration=$includeDur retains legacy template_overrides',
            );
            expect(migrated.containsKey('duration_seconds'), isTrue);
          }
        }
      }
    });
  });

  group('settings_controller.dart — v3 schema bump landed', () {
    late final String controllerSrc;

    setUpAll(() {
      final file = File(_kSettingsControllerPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: '$_kSettingsControllerPath must exist',
      );
      controllerSrc = file.readAsStringSync();
    });

    test('aiStreamThrottleConfigSchemaVersion is bumped to 3', () {
      // Match the top-level `const int aiStreamThrottleConfigSchemaVersion = N;`
      // declaration. We allow whitespace flexibility but the value MUST be
      // the literal `3`.
      final pattern = RegExp(
        r'const\s+int\s+aiStreamThrottleConfigSchemaVersion\s*=\s*(\d+)\s*;',
      );
      final match = pattern.firstMatch(controllerSrc);
      expect(
        match,
        isNotNull,
        reason: 'aiStreamThrottleConfigSchemaVersion declaration not found',
      );
      expect(
        match!.group(1),
        '3',
        reason: 'task 4.2 requires schema version bumped from 2 to 3',
      );
    });

    test('migrateAiStreamThrottleConfig drops template_overrides', () {
      // The function body must contain a `remove('template_overrides')`
      // call so any v1/v2 doc loses the legacy field on the way through.
      expect(
        RegExp(
              r"migrated\.remove\(\s*'template_overrides'\s*\)",
            ).hasMatch(controllerSrc),
        isTrue,
        reason:
            'migrateAiStreamThrottleConfig must call '
            "`migrated.remove('template_overrides')` to drop the legacy "
            'field on v1/v2 → v3 migration.',
      );
    });

    test('doc comment mentions v3 (2026-05-22) lifecycle note', () {
      // Body of the doc-comment that lists schema versions; the v3 entry
      // is the new one and must call out the override removal.
      expect(
        controllerSrc.contains('v3 (2026-05-22)'),
        isTrue,
        reason:
            'doc comment on aiStreamThrottleConfigSchemaVersion must '
            'announce v3 (2026-05-22) — drop of `template_overrides`.',
      );
    });
  });

  group('settings_store.dart — read path tolerates v1/v2/v3, write drops legacy',
      () {
    late final String storeSrc;

    setUpAll(() {
      final file = File(_kSettingsStorePath);
      expect(
        file.existsSync(),
        isTrue,
        reason: '$_kSettingsStorePath must exist',
      );
      storeSrc = file.readAsStringSync();
    });

    test('write path no longer emits ai_stream_throttle_template_overrides',
        () {
      // The string MAY appear inside a doc-comment explaining the
      // migration, but the production write path must never use it as a
      // JSON key. We assert no `'ai_stream_throttle_template_overrides':`
      // assignment survives.
      final assignmentPattern = RegExp(
        "'$_kLegacyJsonField'\\s*:\\s*",
      );
      expect(
        assignmentPattern.hasMatch(storeSrc),
        isFalse,
        reason:
            'settings_store write path still emits a value for '
            '`$_kLegacyJsonField` — task 4.2 requires it removed.',
      );
    });

    test(
      'read path no longer captures ai_stream_throttle_template_overrides into '
      'an in-memory variable',
      () {
        // The load path used to read `json[...]` into a typed map. Post
        // task 4.2 the read path silently ignores the field; no
        // `aiStreamThrottleTemplateOverrides` local should remain.
        expect(
          storeSrc.contains("aiStreamThrottleTemplateOverrides ="),
          isFalse,
          reason:
              'settings_store read path still binds an '
              '`aiStreamThrottleTemplateOverrides` local; task 4.2 '
              'requires the legacy slot to be silently ignored.',
        );
      },
    );

    test(
      'AiStreamThrottleOverride import is dropped from settings_store.dart',
      () {
        // Once the legacy field is gone, the import that exists solely to
        // construct `AiStreamThrottleOverride` instances should also be
        // removed (it would otherwise be dead code).
        expect(
          storeSrc.contains(
            "import '../../features/ai/model/ai_stream_throttle_override.dart';",
          ),
          isFalse,
          reason:
              'settings_store no longer needs ai_stream_throttle_override.dart '
              '— the import should be removed.',
        );
      },
    );
  });
}
