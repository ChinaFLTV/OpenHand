import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';

void main() {
  test('knowledge tools are enabled and force-loaded by default', () {
    final configs = {
      for (final config in AiBuiltinToolConfig.defaults()) config.kind: config,
    };
    for (final kind in <AiBuiltinToolKind>[
      AiBuiltinToolKind.knowledgeSearch,
      AiBuiltinToolKind.knowledgeRead,
    ]) {
      final config = configs[kind];
      expect(config, isNotNull);
      expect(config!.enabled, isTrue);
      expect(config.loadStrategy, AiBuiltinToolLoadStrategy.eager);
      expect(config.forceLoad, isTrue);
      expect(AiBuiltinToolConfig.defaultForceLoadForKind(kind), isTrue);
    }
  });

  test('fromJson normalizes loose scalar values and JSON text lists', () {
    final config = AiBuiltinToolConfig.fromJson(<Object?, Object?>{
      'kind': AiBuiltinToolKind.webFetch.name,
      'enabled': 'off',
      'display_name': 123,
      'schema_override': <Object?, Object?>{1: 'one', 'two': 2},
      'force_load': 'yes',
      'tags': '[" alpha ", 42, "", "beta"]',
      'require_confirmation': '1',
      'retry_on_failure': 'enabled',
      'max_retries': '99',
      'retry_backoff_ms': '999999',
      'is_custom': 1,
      'custom_tool_name': ' fetcher ',
    });

    expect(config.kind, AiBuiltinToolKind.webFetch);
    expect(config.enabled, isFalse);
    expect(config.displayName, '123');
    expect(config.schemaOverride, <String, Object?>{'1': 'one', 'two': 2});
    expect(config.forceLoad, isTrue);
    expect(config.tags, <String>['alpha', '42', 'beta']);
    expect(config.requireConfirmation, isTrue);
    expect(config.retryOnFailure, isTrue);
    expect(config.maxRetries, AiBuiltinToolConfig.maxRetriesUpperBound);
    expect(config.retryBackoffMs, AiBuiltinToolConfig.maxRetryBackoffMs);
    expect(config.isCustom, isTrue);
    expect(config.customToolName, 'fetcher');
  });

  test('fromJson accepts JSON object text', () {
    final config = AiBuiltinToolConfig.fromJson('''
      {
        "kind": "grep",
        "enabled": "true",
        "tags": "search, code",
        "load_strategy": "lazy"
      }
    ''');

    expect(config.kind, AiBuiltinToolKind.grep);
    expect(config.enabled, isTrue);
    expect(config.tags, <String>['search', 'code']);
    expect(config.loadStrategy, AiBuiltinToolLoadStrategy.lazy);
  });
}
