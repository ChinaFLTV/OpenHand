import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/tools/web_reverse_cdp_first_guard.dart';

void main() {
  group('WebReverseCdpFirstGuard', () {
    test('uses shared runtime boolean parsing for CDP-first metadata', () {
      final metadata = <String, Object?>{
        'web_reverse_runtime': <String, Object?>{
          'cdp_first_required': 'enabled',
          'config': <String, Object?>{
            'target_url': 'https://www.example.com/dashboard',
          },
          'cdp_runtime': <String, Object?>{
            'browser_alive': '1.0',
            'cdp_port': '9222',
          },
          'cdp_mcp_tool_availability': <String, Object?>{
            'browser_runtime_live': 'on',
            'current_turn_callable': 'enabled',
            'current_turn_callable_count': '2',
            'current_turn_callable_names': <String>['cdp_click'],
          },
        },
      };

      final decision = WebReverseCdpFirstGuard.evaluateUrl(
        requestedUri: Uri.parse('https://example.com/settings'),
        metadata: metadata,
      );

      expect(WebReverseCdpFirstGuard.isRequired(metadata: metadata), isTrue);
      expect(decision, isNotNull);
      expect(decision!.routeKind, 'current_turn_callable');
      expect(decision.requiresToolSearch, isFalse);
      expect(decision.toolPreview, <String>['cdp_click']);
    });

    test('keeps explicit disabled CDP-first metadata disabled', () {
      final metadata = <String, Object?>{
        'web_reverse_runtime': <String, Object?>{'cdp_first_required': 'off'},
      };

      final decision = WebReverseCdpFirstGuard.evaluateUrl(
        requestedUri: Uri.parse('https://example.com/settings'),
        metadata: metadata,
      );

      expect(WebReverseCdpFirstGuard.isRequired(metadata: metadata), isFalse);
      expect(decision, isNull);
    });
  });
}
