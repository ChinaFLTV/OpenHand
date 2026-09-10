import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_builtin_tool_lazy_loading_applier.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/bash/ai_bash_specialized_tool_policy.dart';

void main() {
  group('AiBashSpecializedToolPolicy 定时任务路由', () {
    test('懒加载 Cron 工具可拦截原生调度器命令', () {
      final catalog = _catalogWithDeferredCronTools();
      expect(catalog.find('CronCreate'), isNull);
      expect(catalog.findDeferredTool('CronCreate'), isNotNull);
      final commands = <String>[
        'crontab -l',
        'printf \'%s\\n\' \'0 21 * * * date\' | crontab -',
        'sudo /usr/bin/crontab -r',
        'schtasks /create /tn demo /sc daily /tr date',
        'systemctl enable demo.timer',
        'systemctl list-timers',
        'systemd-run --on-calendar=daily date',
        'Register-ScheduledTask -TaskName demo',
        'launchctl load demo.plist # StartCalendarInterval',
      ];

      for (final command in commands) {
        final decision = AiBashSpecializedToolPolicy.evaluate(
          command: command,
          catalog: catalog,
        );
        expect(decision, isNotNull, reason: command);
        expect(decision!.intent, 'scheduled_task', reason: command);
        expect(decision.searchGatewayName, 'ToolSearch', reason: command);
        expect(decision.searchQuery, '定时任务', reason: command);
        expect(decision.suggestedToolNames, contains('CronCreate'));
      }
    });

    test('拦截结果携带可执行的 ToolSearch 路由', () {
      final decision = AiBashSpecializedToolPolicy.evaluate(
        command: 'crontab -l',
        catalog: _catalogWithDeferredCronTools(),
      );
      final result = decision!.toResult(
        command: 'crontab -l',
        workingDirectory: '/tmp',
      );

      expect(result.metadata['bash_specialized_tool_policy_blocked'], isTrue);
      expect(result.metadata['bash_specialized_tool_intent'], 'scheduled_task');
      expect(result.metadata['bash_specialized_tool_gateway'], 'ToolSearch');
      expect(result.metadata['bash_specialized_tool_search_query'], '定时任务');
      expect(result.stderr, contains('CronCreate'));
      expect(result.stderr, contains('ToolSearch'));
    });

    test('未提供 Cron 工具时不改变 Bash 行为', () {
      const emptyCatalog = AiResolvedToolCatalog(
        definitions: <AiToolDefinition>[],
        toolsByName: <String, AiResolvedTool>{},
      );

      expect(
        AiBashSpecializedToolPolicy.evaluate(
          command: 'crontab -l',
          catalog: emptyCatalog,
        ),
        isNull,
      );
      expect(
        AiBashSpecializedToolPolicy.evaluate(
          command: 'flutter analyze',
          catalog: _catalogWithDeferredCronTools(),
        ),
        isNull,
      );
    });
  });
}

AiResolvedToolCatalog _catalogWithDeferredCronTools() {
  final cronTools = <String, AiResolvedTool>{
    for (final entry in const <(AiBuiltinToolKind, String)>[
      (AiBuiltinToolKind.cronCreate, 'CronCreate'),
      (AiBuiltinToolKind.cronEdit, 'CronEdit'),
      (AiBuiltinToolKind.cronDelete, 'CronDelete'),
      (AiBuiltinToolKind.cronEnable, 'CronEnable'),
      (AiBuiltinToolKind.cronDisable, 'CronDisable'),
    ])
      entry.$2: _resolvedTool(entry.$1, entry.$2),
  };
  final toolSearch = AiResolvedTool(
    name: 'ToolSearch',
    definition: _definition('ToolSearch'),
    source: AiRuntimeToolSource.builtin,
    builtinKind: AiBuiltinToolKind.toolSearch,
  );
  final sourceCatalog = AiResolvedToolCatalog(
    definitions: <AiToolDefinition>[
      toolSearch.definition,
      ...cronTools.values.map((tool) => tool.definition),
    ],
    toolsByName: <String, AiResolvedTool>{
      'ToolSearch': toolSearch,
      ...cronTools,
    },
  );
  return AiBuiltinToolLazyLoadingApplier.apply(
    catalog: sourceCatalog,
    sourceCatalog: sourceCatalog,
    mode: AiBuiltinToolLazyLoadingMode.enabled,
    thresholdTokens: 1000,
    charsPerToken: 4,
  );
}

AiResolvedTool _resolvedTool(AiBuiltinToolKind kind, String name) {
  return AiResolvedTool(
    name: name,
    definition: _definition(name),
    source: AiRuntimeToolSource.builtin,
    builtinKind: kind,
  );
}

AiToolDefinition _definition(String name) {
  return AiToolDefinition(
    name: name,
    description: name,
    parameters: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  );
}
