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
  });
}
