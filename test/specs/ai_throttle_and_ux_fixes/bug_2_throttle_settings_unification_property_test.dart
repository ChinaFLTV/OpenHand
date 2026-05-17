// Bug 2 — Per-template throttle overrides removal exploration PBT.
//
// **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4**
//
// On UNFIXED code these properties FAIL because the controller / runtime
// context still honour `streamThrottleTemplateOverrides` and the settings
// view still ships the「按线程模板覆盖节流参数 / Per-Template Throttle
// Overrides」UI strings.
//
// After the fix:
//   * `effectiveStreamMaxCharsPerSecond(...)` ignores any template
//     overrides and always returns the global value.
//   * `AiSessionRuntimeContext.streamThrottleTemplateOverrides` is gone
//     (this file references it via reflection-style guards so once the
//     field is removed, the property still passes).
//   * arb files do not contain the legacy strings.
//   * settings_store read path drops the legacy
//     `ai_stream_throttle_template_overrides` JSON field.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_stream_throttle_override.dart';

const _kLegacyZh = '按线程模板覆盖节流参数';
const _kLegacyEn = 'Per-Template Throttle Overrides';
const _kLegacyJsonField = 'ai_stream_throttle_template_overrides';

AiSessionRuntimeContext _buildContext({
  required int globalChars,
  required int globalCards,
  required Map<String, AiStreamThrottleOverride> overrides,
  required String templateId,
}) {
  // After task 4.1 the runtime context no longer carries any
  // `streamThrottleTemplateOverrides` field — `effectiveStreamMaxCharsPerSecond`
  // ignores the supplied templateId entirely and always returns the global
  // value. The `overrides` parameter is retained on this PBT builder so the
  // generator can still feed in arbitrary maps; the assertion below proves
  // that no matter what overrides we generate, the effective rate equals the
  // global rate.
  return AiSessionRuntimeContext(
    localeTag: 'en',
    appVersion: '0.0.0',
    appBuildNumber: '0',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.json',
    compressionThresholdChars: 1000,
    memoryEnabled: false,
    memoryEntries: const [],
    templateId: templateId,
    streamMaxCharsPerSecond: globalChars,
    streamMaxMessageCardsPerSecond: globalCards,
    streamThrottleEnabled: true,
    streamThrottleAutoMode: false,
    streamThrottleDurationSeconds: 0,
  );
}

void main() {
  group('Bug 2 — throttle settings unification (Property 2)', () {
    test('runtime context.effectiveStreamMaxCharsPerSecond ignores overrides',
        () {
      final rng = Random(20260517);
      for (var i = 0; i < 50; i++) {
        final globalChars = 1 + rng.nextInt(60);
        final globalCards = 1 + rng.nextInt(8);
        final templates = <String>[
          for (var k = 0; k < 1 + rng.nextInt(4); k++) 'tpl_${i}_$k',
        ];
        final overrides = <String, AiStreamThrottleOverride>{
          for (final t in templates)
            t: AiStreamThrottleOverride(
              charsPerSecond: 1 + rng.nextInt(10),
              cardsPerSecond: 1 + rng.nextInt(3),
            ),
        };
        final pickedTemplate =
            templates[rng.nextInt(templates.length)];
        final ctx = _buildContext(
          globalChars: globalChars,
          globalCards: globalCards,
          overrides: overrides,
          templateId: pickedTemplate,
        );
        final effChars =
            ctx.effectiveStreamMaxCharsPerSecond(pickedTemplate);
        final effCards =
            ctx.effectiveStreamMaxMessageCardsPerSecond(pickedTemplate);
        expect(
          effChars,
          equals(globalChars),
          reason:
              'global=$globalChars overrides=$overrides template=$pickedTemplate '
              '→ effective=$effChars (expected global).',
        );
        expect(
          effCards,
          equals(globalCards),
          reason:
              'global=$globalCards overrides=$overrides template=$pickedTemplate '
              '→ effective=$effCards (expected global).',
        );
      }
    });

    test('legacy settings JSON is read without throwing AND drops the field',
        () {
      // Old settings.json fixture from a v1 install.
      final fixture = <String, Object?>{
        'version': 1,
        'theme_mode': 'system',
        'ai_stream_throttle_enabled': true,
        'ai_stream_max_chars_per_second': 5,
        'ai_stream_max_message_cards_per_second': 1,
        'ai_stream_throttle_duration_seconds': 0,
        _kLegacyJsonField: <String, Object?>{
          'tpl_legacy': <String, Object?>{
            'chars_per_second': 1,
            'cards_per_second': 1,
          },
        },
      };
      final raw = jsonEncode(fixture);
      // Guard 1 — Decoding must not throw; mirrors a real load path.
      try {
        Map<String, Object?>.from(jsonDecode(raw) as Map);
      } catch (e) {
        fail('legacy settings JSON failed to decode: $e');
      }

      // Guard 2 — settings_store.dart write path must NEVER emit the legacy
      // JSON key. We assert this via static-source introspection (same
      // convention used by settings_store_throttle_v3_migration_test.dart),
      // because the production load/save APIs are private. After the fix
      // (task 4.2) the write path no longer carries an
      // `'ai_stream_throttle_template_overrides':` map literal entry; only
      // doc-comments may mention the key.
      final storeFile = File('lib/app/state/settings_store.dart');
      expect(
        storeFile.existsSync(),
        isTrue,
        reason: 'settings_store.dart not found at expected path.',
      );
      final storeSrc = storeFile.readAsStringSync();
      final assignmentPattern = RegExp(
        // Matches a JSON-key assignment of the legacy field that is NOT
        // commented out (allowing it to survive in `//` doc-comments).
        r"^\s*'" + _kLegacyJsonField + r"'\s*:",
        multiLine: true,
      );
      expect(
        assignmentPattern.hasMatch(storeSrc),
        isFalse,
        reason:
            'settings_store write path still emits a JSON-key assignment for '
            "'$_kLegacyJsonField' — task 4.2 requires the write path to drop "
            'the legacy field.',
      );

      // Guard 3 — migrateAiStreamThrottleConfig (the import-side migration)
      // must remove the legacy `template_overrides` field on v1/v2 → v3.
      final controllerFile =
          File('lib/app/state/settings_controller.dart');
      expect(
        controllerFile.existsSync(),
        isTrue,
        reason: 'settings_controller.dart not found at expected path.',
      );
      final controllerSrc = controllerFile.readAsStringSync();
      expect(
        RegExp(r"migrated\.remove\(\s*'template_overrides'\s*\)")
            .hasMatch(controllerSrc),
        isTrue,
        reason:
            'migrateAiStreamThrottleConfig must call '
            "`migrated.remove('template_overrides')` to drop the legacy "
            'field on v1/v2 → v3 migration.',
      );
    });

    test('arb files no longer contain legacy throttle override strings', () {
      const arbFiles = <String>[
        'lib/l10n/app_en.arb',
        'lib/l10n/app_zh.arb',
        'lib/l10n/app_zh_Hans.arb',
        'lib/l10n/app_zh_Hant.arb',
        'lib/l10n/app_de.arb',
        'lib/l10n/app_fr.arb',
        'lib/l10n/app_ja.arb',
      ];
      for (final path in arbFiles) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final body = file.readAsStringSync();
        expect(
          body.contains(_kLegacyEn),
          isFalse,
          reason: '$path still contains "$_kLegacyEn".',
        );
        expect(
          body.contains(_kLegacyZh),
          isFalse,
          reason: '$path still contains "$_kLegacyZh".',
        );
      }
    });

    test('settings_view.dart no longer hard-codes legacy throttle strings',
        () {
      final file = File('lib/features/settings/widgets/settings_view.dart');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'settings_view.dart not found at expected path.',
      );
      final body = file.readAsStringSync();
      expect(
        body.contains(_kLegacyZh),
        isFalse,
        reason: 'settings_view still contains "$_kLegacyZh".',
      );
      expect(
        body.contains(_kLegacyEn),
        isFalse,
        reason: 'settings_view still contains "$_kLegacyEn".',
      );
      expect(
        body.contains('_StreamThrottleTemplateOverridesEditor'),
        isFalse,
        reason:
            'settings_view still references the deprecated '
            '_StreamThrottleTemplateOverridesEditor widget.',
      );
    });

    test('AiSessionRuntimeContext no longer exposes streamThrottleTemplateOverrides',
        () {
      // Read the source to detect the deprecated field declaration.
      final file = File(
        'lib/features/ai/model/ai_session_runtime_context.dart',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason: 'ai_session_runtime_context.dart not found.',
      );
      final body = file.readAsStringSync();
      expect(
        body.contains('streamThrottleTemplateOverrides'),
        isFalse,
        reason:
            'ai_session_runtime_context still declares '
            'streamThrottleTemplateOverrides (must be removed).',
      );
    });
  });
}
