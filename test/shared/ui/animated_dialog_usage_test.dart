import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const Set<String> _legacyWebReverseRawDialogFiles = {
  'lib/features/web_reverse/web_reverse_account_snapshots_dialog.dart',
  'lib/features/web_reverse/web_reverse_ai_crypto_dialog.dart',
  'lib/features/web_reverse/web_reverse_animations_dialog.dart',
  'lib/features/web_reverse/web_reverse_callgraph_dialog.dart',
  'lib/features/web_reverse/web_reverse_collection_export_dialog.dart',
  'lib/features/web_reverse/web_reverse_cookie_editor_dialog.dart',
  'lib/features/web_reverse/web_reverse_cors_preflight_dialog.dart',
  'lib/features/web_reverse/web_reverse_dashboard_dialog.advanced.part.dart',
  'lib/features/web_reverse/web_reverse_dashboard_dialog.dart',
  'lib/features/web_reverse/web_reverse_dashboard_dialog.panels.part.dart',
  'lib/features/web_reverse/web_reverse_dashboard_dialog.sources.part.dart',
  'lib/features/web_reverse/web_reverse_device_emulation_dialog.dart',
  'lib/features/web_reverse/web_reverse_dom_mutation_dialog.dart',
  'lib/features/web_reverse/web_reverse_geo_override_dialog.dart',
  'lib/features/web_reverse/web_reverse_har_persistence_dialog.dart',
  'lib/features/web_reverse/web_reverse_headless_batch_dialog.dart',
  'lib/features/web_reverse/web_reverse_heap_snapshot_dialog.dart',
  'lib/features/web_reverse/web_reverse_input_sim_dialog.dart',
  'lib/features/web_reverse/web_reverse_issues_dialog.dart',
  'lib/features/web_reverse/web_reverse_jwt_refresh_dialog.dart',
  'lib/features/web_reverse/web_reverse_mock_rules_dialog.dart',
  'lib/features/web_reverse/web_reverse_perf_trace_dialog.dart',
  'lib/features/web_reverse/web_reverse_postmessage_dialog.dart',
  'lib/features/web_reverse/web_reverse_rendering_dialog.dart',
  'lib/features/web_reverse/web_reverse_resend_request_dialog.dart',
  'lib/features/web_reverse/web_reverse_screenshot_markup.dart',
  'lib/features/web_reverse/web_reverse_signature_diff_dialog.dart',
  'lib/features/web_reverse/web_reverse_sourcemap_dialog.dart',
  'lib/features/web_reverse/web_reverse_storage_dialog.dart',
  'lib/features/web_reverse/web_reverse_sw_debug_dialog.dart',
  'lib/features/web_reverse/web_reverse_throttle_dialog.dart',
  'lib/features/web_reverse/web_reverse_watch_dialog.dart',
  'lib/features/web_reverse/web_reverse_waterfall_dialog.dart',
  'lib/features/web_reverse/web_reverse_webauthn_dialog.dart',
  'lib/features/web_reverse/web_reverse_websocket_dialog.dart',
  'lib/features/web_reverse/web_reverse_ws_inject_dialog.dart',
};

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

  test('web reverse code does not add new raw Dialog shells', () {
    final violations = <String>[];
    final webReverseDir = Directory('lib/features/web_reverse');
    final rawDialogPattern = RegExp(r'\bDialog\s*\(');

    for (final entity in webReverseDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final content = entity.readAsStringSync();
      if (!rawDialogPattern.hasMatch(content)) {
        continue;
      }
      if (_legacyWebReverseRawDialogFiles.contains(entity.path)) {
        continue;
      }
      violations.add(entity.path);
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Use buildOpenHandToolDialogShell/buildOpenHandResponsiveDialogShell '
          'with showAnimatedDialog for new Web Reverse dialogs.',
    );
  });
}
