import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/tools/web_reverse_cdp_first_guard.dart';

void main() {
  group('WebReverseCdpFirstGuard', () {
    test('blocks same-origin WebFetch with prompt runtime metadata', () {
      final decision = WebReverseCdpFirstGuard.evaluateUrl(
        requestedUri: Uri.parse('https://linux.do/t/topic/2401043.json'),
        metadata: <String, Object?>{
          'web_reverse_runtime': <String, Object?>{
            'cdp_first_required': true,
            'config': <String, Object?>{
              'target_url': 'https://linux.do/t/topic/2401043/5',
            },
            'cdp_runtime': <String, Object?>{
              'browser_alive': true,
              'cdp_port': 9223,
            },
            'cdp_mcp_tool_availability': <String, Object?>{
              'browser_runtime_live': true,
              'current_turn_callable': true,
              'current_turn_callable_names': <String>[
                'mcp__web_reverse_cdp__evaluate_script',
              ],
            },
          },
        },
      );

      expect(decision, isNotNull);
      expect(decision!.targetOrigin, 'https://linux.do');
      expect(decision.requestedOrigin, 'https://linux.do');
      expect(decision.requiresToolSearch, isFalse);
    });

    test('falls back to legacy live CDP session metadata', () {
      final decision = WebReverseCdpFirstGuard.evaluateUrl(
        requestedUri: Uri.parse('https://linux.do/t/topic/2401043.json'),
        metadata: <String, Object?>{
          'web_reverse_config': <String, Object?>{
            'target_url': 'https://linux.do/t/topic/2401043/5',
          },
          'web_reverse_cdp_runtime': <String, Object?>{
            'browser_alive': true,
            'cdp_port': 9223,
          },
        },
      );

      expect(decision, isNotNull);
      expect(decision!.routeKind, 'runtime_live_without_callable_cdp_tools');
    });

    test('allows unrelated external URLs', () {
      final decision = WebReverseCdpFirstGuard.evaluateUrl(
        requestedUri: Uri.parse('https://docs.flutter.dev/'),
        metadata: <String, Object?>{
          'web_reverse_config': <String, Object?>{
            'target_url': 'https://linux.do/t/topic/2401043/5',
          },
          'web_reverse_cdp_runtime': <String, Object?>{
            'browser_alive': true,
            'cdp_port': 9223,
          },
        },
      );

      expect(decision, isNull);
    });
  });
}
