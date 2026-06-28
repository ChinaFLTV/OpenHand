import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  group('web reverse runtime metadata parsing', () {
    test('guards boolean and integer parsing against non-finite values', () {
      expect(webReverseRuntimeBoolTrue('on'), isTrue);
      expect(webReverseRuntimeBoolTrue(double.nan), isFalse);
      expect(webReverseRuntimeBoolFalse('off'), isTrue);
      expect(webReverseRuntimeBoolFalse(double.infinity), isFalse);
      expect(webReverseRuntimeInt('9222'), 9222);
      expect(webReverseRuntimeInt(double.infinity), isNull);
    });

    test('requires a positive CDP port or a non-empty endpoint locator', () {
      expect(
        webReverseCdpRuntimeHasLiveLocator(<String, Object?>{
          'cdp_port': double.infinity,
        }),
        isFalse,
      );
      expect(
        webReverseCdpRuntimeHasLiveLocator(<String, Object?>{
          'cdp_port': '9222',
        }),
        isTrue,
      );
      expect(
        webReverseCdpRuntimeHasLiveLocator(<String, Object?>{
          'json_version_url': ' http://127.0.0.1:9222/json/version ',
        }),
        isTrue,
      );
      expect(
        webReverseCdpRuntimeIsLive(<String, Object?>{
          'browser_alive': 'yes',
          'cdp_port': '0',
        }),
        isFalse,
      );
    });

    test('runtime status prefers valid ports and clamps tool count', () {
      final fallbackRuntimePort = WebReverseCdpMcpRuntimeStatus.fromRuntime(
        <String, Object?>{
          'browser_alive': 'true',
          'cdp_port': '9223',
          'cdp_mcp_bridge': <String, Object?>{
            'status': 'ready',
            'cdp_port': double.nan,
            'tool_count': '-4',
            'live_actions_callable': 'yes',
          },
        },
        controllerPort: -1,
      );

      expect(fallbackRuntimePort.port, 9223);
      expect(fallbackRuntimePort.toolCount, 0);
      expect(fallbackRuntimePort.browserAlive, isTrue);
      expect(fallbackRuntimePort.liveActionsCallable, isTrue);
      expect(fallbackRuntimePort.ready, isFalse);

      final readyBridge = WebReverseCdpMcpRuntimeStatus.fromRuntime(
        <String, Object?>{
          'cdp_port': '9223',
          'cdp_mcp_bridge': <String, Object?>{
            'status': 'ready',
            'browser_alive': true,
            'cdp_port': '9333',
            'tool_count': '2',
            'live_actions_callable': '1',
          },
        },
      );

      expect(readyBridge.port, 9333);
      expect(readyBridge.toolCount, 2);
      expect(readyBridge.ready, isTrue);
    });

    test('controller offline state overrides live bridge metadata', () {
      final status = WebReverseCdpMcpRuntimeStatus.fromRuntime(
        <String, Object?>{
          'browser_alive': 'true',
          'cdp_port': '9223',
          'cdp_mcp_bridge': <String, Object?>{
            'status': 'ready',
            'cdp_port': '9333',
            'tool_count': 3,
            'live_actions_callable': true,
          },
        },
        controllerBrowserAlive: false,
        controllerPort: 9444,
      );

      expect(status.port, isNull);
      expect(status.browserAlive, isFalse);
      expect(status.liveActionsCallable, isFalse);
      expect(status.ready, isFalse);
    });
  });
}
