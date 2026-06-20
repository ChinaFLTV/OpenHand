import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/web_reverse_runtime_metadata.dart';

void main() {
  group('web reverse runtime metadata helpers', () {
    test('parse loose browser_alive truthy values', () {
      expect(webReverseRuntimeBoolTrue(true), isTrue);
      expect(webReverseRuntimeBoolTrue('true'), isTrue);
      expect(webReverseRuntimeBoolTrue(' YES '), isTrue);
      expect(webReverseRuntimeBoolTrue(1), isTrue);

      expect(webReverseRuntimeBoolTrue(false), isFalse);
      expect(webReverseRuntimeBoolTrue('false'), isFalse);
      expect(webReverseRuntimeBoolTrue(0), isFalse);
      expect(webReverseRuntimeBoolTrue(null), isFalse);
    });

    test('parse loose browser_alive falsey values', () {
      expect(webReverseRuntimeBoolFalse(false), isTrue);
      expect(webReverseRuntimeBoolFalse('false'), isTrue);
      expect(webReverseRuntimeBoolFalse(' NO '), isTrue);
      expect(webReverseRuntimeBoolFalse(0), isTrue);

      expect(webReverseRuntimeBoolFalse(true), isFalse);
      expect(webReverseRuntimeBoolFalse('true'), isFalse);
      expect(webReverseRuntimeBoolFalse(1), isFalse);
      expect(webReverseRuntimeBoolFalse(null), isFalse);
    });

    test('detects live CDP locators', () {
      expect(webReverseCdpRuntimeHasLiveLocator(<Object?, Object?>{}), isFalse);
      expect(
        webReverseCdpRuntimeHasLiveLocator(<Object?, Object?>{
          'cdp_port': 9223,
        }),
        isTrue,
      );
      expect(
        webReverseCdpRuntimeHasLiveLocator(<Object?, Object?>{
          'json_list_url': 'http://127.0.0.1:9223/json/list',
        }),
        isTrue,
      );
      expect(
        webReverseCdpRuntimeHasLiveLocator(<Object?, Object?>{
          'last_cdp_port': 9223,
        }),
        isFalse,
      );
    });

    test('normalizes runtime maps with non-string keys', () {
      final mapped = webReverseRuntimeObjectMap(<Object?, Object?>{
        1: 'one',
        'browser_alive': true,
      });

      expect(mapped, isNotNull);
      expect(mapped!['1'], 'one');
      expect(mapped['browser_alive'], isTrue);
    });

    test('requires browser_alive and a current locator for live CDP', () {
      expect(
        webReverseCdpRuntimeIsLive(<String, Object?>{'browser_alive': true}),
        isFalse,
      );
      expect(
        webReverseCdpRuntimeIsLive(<String, Object?>{
          'browser_alive': false,
          'cdp_port': 9223,
        }),
        isFalse,
      );
      expect(
        webReverseCdpRuntimeIsLive(<String, Object?>{
          'browser_alive': 'yes',
          'json_version_url': 'http://127.0.0.1:9223/json/version',
        }),
        isTrue,
      );
    });

    test('summarizes CDP MCP bridge runtime status', () {
      final status = WebReverseCdpMcpRuntimeStatus.fromRuntime(
        <String, Object?>{
          'browser_alive': true,
          'cdp_port': 9224,
          'cdp_mcp_bridge': <Object?, Object?>{
            'status': 'ready',
            'browser_alive': true,
            'live_actions_callable': true,
            'tool_count': '3',
            'cdp_port': 9223,
            'server_name': 'web_reverse_cdp_abcd',
            'message': ' ready ',
          },
        },
      );

      expect(status.ready, isTrue);
      expect(status.toolCount, 3);
      expect(status.port, 9223);
      expect(status.serverName, 'web_reverse_cdp_abcd');
      expect(status.message, 'ready');
    });

    test('does not mark stale callable bridge ready when CDP is offline', () {
      final status = WebReverseCdpMcpRuntimeStatus.fromRuntime(
        <String, Object?>{
          'browser_alive': false,
          'last_cdp_port': 9223,
          'cdp_mcp_bridge': <String, Object?>{
            'status': 'ready',
            'browser_alive': false,
            'live_actions_callable': true,
            'tool_count': 2,
          },
        },
      );

      expect(status.browserAlive, isFalse);
      expect(status.ready, isFalse);
      expect(status.port, isNull);
    });

    test('prefers current controller CDP runtime over prompt runtime', () {
      final runtime = webReverseCurrentCdpRuntimeMetadata(<Object?, Object?>{
        'web_reverse_runtime': <String, Object?>{
          'cdp_runtime': <String, Object?>{
            'browser_alive': true,
            'cdp_port': 9223,
          },
        },
        'web_reverse_cdp_runtime': <String, Object?>{
          'browser_alive': false,
          'last_cdp_port': 9223,
        },
      });

      expect(runtime, isA<Map>());
      expect((runtime as Map)['browser_alive'], isFalse);
      expect(runtime['last_cdp_port'], 9223);
    });

    test(
      'falls back to prompt CDP runtime when controller runtime is absent',
      () {
        final runtime = webReverseCurrentCdpRuntimeMetadata(<Object?, Object?>{
          'web_reverse_runtime': <String, Object?>{
            'cdp_runtime': <String, Object?>{
              'browser_alive': true,
              'cdp_port': 9223,
            },
          },
        });

        expect(runtime, isA<Map>());
        expect((runtime as Map)['browser_alive'], isTrue);
        expect(runtime['cdp_port'], 9223);
      },
    );
  });
}
