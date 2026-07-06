import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';

void main() {
  group('AiBuiltinToolConfig', () {
    test('fromJson clamps retry policy bounds', () {
      final config = AiBuiltinToolConfig.fromJson(<String, Object?>{
        'kind': AiBuiltinToolKind.read.name,
        'retry_on_failure': true,
        'max_retries': 999,
        'retry_backoff_ms': -5,
      });

      expect(config.retryOnFailure, isTrue);
      expect(config.maxRetries, AiBuiltinToolConfig.maxRetriesUpperBound);
      expect(config.retryBackoffMs, 0);
      expect(
        config.effectiveMaxRetries,
        AiBuiltinToolConfig.maxRetriesUpperBound,
      );
      expect(config.effectiveRetryBackoffMs, 0);
      expect(config.retryBackoffFor(1), Duration.zero);
    });

    test('effective retries stay disabled when retry flag is false', () {
      const config = AiBuiltinToolConfig(
        kind: AiBuiltinToolKind.read,
        maxRetries: 5,
      );

      expect(config.maxRetries, 5);
      expect(config.effectiveMaxRetries, 0);
    });

    test('copyWith and toJson normalize retry policy values', () {
      const config = AiBuiltinToolConfig(
        kind: AiBuiltinToolKind.read,
        retryOnFailure: true,
        maxRetries: 999,
        retryBackoffMs: 999999,
      );
      final copied = config.copyWith();
      final json = config.toJson();

      expect(copied.maxRetries, AiBuiltinToolConfig.maxRetriesUpperBound);
      expect(copied.retryBackoffMs, AiBuiltinToolConfig.maxRetryBackoffMs);
      expect(json['max_retries'], AiBuiltinToolConfig.maxRetriesUpperBound);
      expect(json['retry_backoff_ms'], AiBuiltinToolConfig.maxRetryBackoffMs);
    });

    test('retryBackoffFor caps exponential backoff', () {
      const config = AiBuiltinToolConfig(
        kind: AiBuiltinToolKind.read,
        retryOnFailure: true,
        maxRetries: 5,
        retryBackoffMs: 20000,
      );

      expect(config.retryBackoffFor(0), Duration.zero);
      expect(config.retryBackoffFor(1), const Duration(milliseconds: 20000));
      expect(
        config.retryBackoffFor(2),
        const Duration(milliseconds: AiBuiltinToolConfig.maxRetryBackoffMs),
      );
      expect(
        config.retryBackoffFor(60),
        const Duration(milliseconds: AiBuiltinToolConfig.maxRetryBackoffMs),
      );
    });
  });
}
