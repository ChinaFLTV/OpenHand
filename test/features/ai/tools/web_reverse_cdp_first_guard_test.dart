import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/tools/web_reverse_cdp_first_guard.dart';

void main() {
  group('WebReverseCdpFirstGuard', () {
    test('blocks same-origin WebFetch with prompt runtime metadata', () {
      final decision = WebReverseCdpFirstGuard.evaluateUrl(
        requestedUri: Uri.parse('https://linux.do/t/topic/2401043.json'),
        metadata: _liveRuntimeMetadata(),
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

    test(
      'blocks legacy target-origin URL with only historical CDP locator',
      () {
        final decision = WebReverseCdpFirstGuard.evaluateUrl(
          requestedUri: Uri.parse('https://linux.do/t/topic/2401043.json'),
          metadata: <String, Object?>{
            'web_reverse_config': <String, Object?>{
              'target_url': 'https://linux.do/t/topic/2401043/5',
            },
            'web_reverse_cdp_runtime': <String, Object?>{
              'browser_alive': true,
              'last_cdp_port': 9223,
            },
          },
        );

        expect(decision, isNotNull);
        expect(decision!.routeKind, 'runtime_unavailable_without_live_cdp');
      },
    );

    test(
      'blocks target-origin URL when runtime explicitly says CDP is offline',
      () {
        final decision = WebReverseCdpFirstGuard.evaluateUrl(
          requestedUri: Uri.parse('https://linux.do/t/topic/2401043.json'),
          metadata: <String, Object?>{
            'web_reverse_runtime': <String, Object?>{
              'cdp_first_required': true,
              'config': <String, Object?>{
                'target_url': 'https://linux.do/t/topic/2401043/5',
              },
              'cdp_runtime': <String, Object?>{
                'browser_alive': false,
                'last_cdp_port': 9223,
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
        expect(decision!.routeKind, 'runtime_unavailable_without_live_cdp');
        expect(
          decision.nextAction,
          contains('Live CDP is unavailable for this Web Reverse target'),
        );
      },
    );

    test('blocks target-origin URL when runtime lacks live CDP locator', () {
      final decision = WebReverseCdpFirstGuard.evaluateUrl(
        requestedUri: Uri.parse('https://linux.do/t/topic/2401043.json'),
        metadata: <String, Object?>{
          'web_reverse_runtime': <String, Object?>{
            'cdp_first_required': true,
            'config': <String, Object?>{
              'target_url': 'https://linux.do/t/topic/2401043/5',
            },
            'cdp_runtime': <String, Object?>{'browser_alive': true},
            'cdp_mcp_tool_availability': <String, Object?>{
              'browser_runtime_live': false,
              'current_turn_callable': true,
              'current_turn_callable_names': <String>[
                'mcp__web_reverse_cdp__evaluate_script',
              ],
            },
          },
        },
      );

      expect(decision, isNotNull);
      expect(decision!.routeKind, 'runtime_unavailable_without_live_cdp');
    });

    test(
      'uses current offline session CDP runtime over stale prompt runtime',
      () {
        final metadata = _liveRuntimeMetadata();
        metadata['web_reverse_cdp_runtime'] = <String, Object?>{
          'browser_alive': false,
          'last_cdp_port': 9223,
        };

        final decision = WebReverseCdpFirstGuard.evaluateUrl(
          requestedUri: Uri.parse('https://linux.do/t/topic/2401043.json'),
          metadata: metadata,
        );

        expect(decision, isNotNull);
        expect(decision!.routeKind, 'runtime_unavailable_without_live_cdp');
      },
    );

    test('allows unrelated external URLs', () {
      final decision = WebReverseCdpFirstGuard.evaluateUrl(
        requestedUri: Uri.parse('https://docs.flutter.dev/'),
        metadata: _legacyLiveMetadata(),
      );

      expect(decision, isNull);
    });

    test('blocks same target host over alternate HTTP scheme', () {
      final decision = WebReverseCdpFirstGuard.evaluateUrl(
        requestedUri: Uri.parse('http://linux.do/t/topic/2401043.json'),
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNotNull);
      expect(decision!.targetOrigin, 'https://linux.do');
      expect(decision.requestedOrigin, 'http://linux.do');
    });

    test('blocks same target host over alternate port', () {
      final decision = WebReverseCdpFirstGuard.evaluateUrl(
        requestedUri: Uri.parse('https://linux.do:8443/t/topic/2401043.json'),
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNotNull);
      expect(decision!.requestedOrigin, 'https://linux.do:8443');
    });

    test('blocks plain text target URL reference', () {
      final decision = WebReverseCdpFirstGuard.evaluateTextReference(
        text: 'site:https://linux.do/t/topic/2401043',
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNotNull);
      expect(decision!.requestedOrigin, 'https://linux.do');
    });

    test('blocks plain text target host reference', () {
      final decision = WebReverseCdpFirstGuard.evaluateTextReference(
        text: 'site:linux.do topic 2401043',
        metadata: _legacyLiveMetadata(),
      );

      expect(decision, isNotNull);
      expect(decision!.targetOrigin, 'https://linux.do');
    });

    test('blocks command URL with Chinese punctuation', () {
      final decision = WebReverseCdpFirstGuard.evaluateCommand(
        command: 'curl https://linux.do/t/topic/2401043.json。',
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNotNull);
      expect(
        decision!.requestedUri.toString(),
        'https://linux.do/t/topic/2401043.json',
      );
    });

    test('blocks quoted curl URL', () {
      final decision = WebReverseCdpFirstGuard.evaluateCommand(
        command: "curl 'https://linux.do/t/topic/2401043.json'",
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNotNull);
      expect(decision!.requestedOrigin, 'https://linux.do');
    });

    test('blocks script embedded requests call', () {
      final decision = WebReverseCdpFirstGuard.evaluateCommand(
        command:
            'python -c "import requests; requests.get('
            "'https://linux.do/t/topic/2401043.json')"
            '"',
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNotNull);
      expect(decision!.requestedOrigin, 'https://linux.do');
    });

    test('blocks script URL with escaped forward slashes', () {
      final decision = WebReverseCdpFirstGuard.evaluateCommand(
        command:
            r'''node -e "fetch('https:\/\/linux.do\/t\/topic\/2401043.json')"''',
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNotNull);
      expect(
        decision!.requestedUri.toString(),
        'https://linux.do/t/topic/2401043.json',
      );
    });

    test('blocks browser automation outside CDP', () {
      final decision = WebReverseCdpFirstGuard.evaluateCommand(
        command:
            'osascript -e \'tell application "Google Chrome" to open location '
            '"https://linux.do/t/topic/2401043/5"\'',
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNotNull);
      expect(decision!.requestedOrigin, 'https://linux.do');
    });

    test('blocks compiled runtime command with target URL', () {
      final decision = WebReverseCdpFirstGuard.evaluateCommand(
        command: 'go run ./cmd/scrape https://linux.do/t/topic/2401043.json',
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNotNull);
      expect(decision!.requestedOrigin, 'https://linux.do');
    });

    test('blocks JVM command with target URL', () {
      final decision = WebReverseCdpFirstGuard.evaluateCommand(
        command: 'java -jar fetcher.jar "https://linux.do/t/topic/2401043/5"',
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNotNull);
      expect(decision!.requestedOrigin, 'https://linux.do');
    });

    test('blocks runtime command with target host reference', () {
      final decision = WebReverseCdpFirstGuard.evaluateCommand(
        command: 'dotnet run --project tools/Scraper --host linux.do',
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNotNull);
      expect(decision!.targetOrigin, 'https://linux.do');
    });

    test('allows non-network command that only prints target URL', () {
      final decision = WebReverseCdpFirstGuard.evaluateCommand(
        command: 'echo https://linux.do/t/topic/2401043/5',
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNull);
    });

    test(
      'blocks HTTPie https command without treating URL scheme as command',
      () {
        final decision = WebReverseCdpFirstGuard.evaluateCommand(
          command: 'https GET https://linux.do/t/topic/2401043.json',
          metadata: _liveRuntimeMetadata(),
        );

        expect(decision, isNotNull);
        expect(decision!.requestedOrigin, 'https://linux.do');
      },
    );

    test('allows command against unrelated external URLs', () {
      final decision = WebReverseCdpFirstGuard.evaluateCommand(
        command: 'curl https://docs.flutter.dev/',
        metadata: _liveRuntimeMetadata(),
      );

      expect(decision, isNull);
    });
  });
}

Map<String, Object?> _liveRuntimeMetadata() {
  return <String, Object?>{
    'web_reverse_runtime': <String, Object?>{
      'cdp_first_required': true,
      'config': <String, Object?>{
        'target_url': 'https://linux.do/t/topic/2401043/5',
      },
      'cdp_runtime': <String, Object?>{'browser_alive': true, 'cdp_port': 9223},
      'cdp_mcp_tool_availability': <String, Object?>{
        'browser_runtime_live': true,
        'current_turn_callable': true,
        'current_turn_callable_names': <String>[
          'mcp__web_reverse_cdp__evaluate_script',
        ],
      },
    },
  };
}

Map<String, Object?> _legacyLiveMetadata() {
  return <String, Object?>{
    'web_reverse_config': <String, Object?>{
      'target_url': 'https://linux.do/t/topic/2401043/5',
    },
    'web_reverse_cdp_runtime': <String, Object?>{
      'browser_alive': true,
      'cdp_port': 9223,
    },
  };
}
