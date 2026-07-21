import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';

void main() {
  group('McpServer 模板可见性', () {
    test('null 配置对所有模板可见', () {
      const server = McpServer(
        name: 'custom',
        type: McpServerType.streamableHttp,
        enabled: true,
        url: 'https://example.com/mcp',
      );

      expect(server.isVisibleToTemplate('default'), isTrue);
      expect(server.isVisibleToTemplate('web_reverse_expert'), isTrue);
    });

    test('显式配置仅对命中的模板可见', () {
      const server = McpServer(
        name: 'web',
        type: McpServerType.stdio,
        enabled: true,
        command: 'npx',
        visibleTemplateIds: <String>{'web_reverse_expert'},
      );

      expect(server.isVisibleToTemplate('web_reverse_expert'), isTrue);
      expect(server.isVisibleToTemplate('default'), isFalse);
      expect(server.isVisibleToTemplate(' web_reverse_expert '), isTrue);
    });

    test('copyWith 可保留、替换或清除显式配置', () {
      const server = McpServer(
        name: 'web',
        type: McpServerType.stdio,
        enabled: true,
        command: 'npx',
        visibleTemplateIds: <String>{'web_reverse_expert'},
      );

      expect(server.copyWith().visibleTemplateIds, <String>{
        'web_reverse_expert',
      });
      expect(
        server
            .copyWith(visibleTemplateIds: const <String>{'default'})
            .visibleTemplateIds,
        <String>{'default'},
      );
      expect(
        server.copyWith(visibleTemplateIds: null).visibleTemplateIds,
        isNull,
      );
    });

    test('补充模板可见性时保留原集合且不修改原对象', () {
      const server = McpServer(
        name: 'web',
        type: McpServerType.stdio,
        enabled: true,
        command: 'npx',
        visibleTemplateIds: <String>{'web_reverse_expert'},
      );

      final updated = server.withVisibleTemplate('default');

      expect(server.visibleTemplateIds, <String>{'web_reverse_expert'});
      expect(updated.visibleTemplateIds, <String>{
        'default',
        'web_reverse_expert',
      });
      expect(updated.withVisibleTemplate('default'), same(updated));
      expect(
        server
            .copyWith(visibleTemplateIds: null)
            .withVisibleTemplate('default'),
        isA<McpServer>().having(
          (value) => value.visibleTemplateIds,
          '全部可见',
          isNull,
        ),
      );
    });

    test('内置服务默认映射严格区分服务名称', () {
      expect(
        McpServer.defaultVisibleTemplateIdsForName('Web Reverse CDP MCP'),
        <String>{'web_reverse_expert'},
      );
      expect(
        McpServer.defaultVisibleTemplateIdsForName('Android Frida MCP'),
        <String>{'android_reverse_expert'},
      );
      expect(
        McpServer.defaultVisibleTemplateIdsForName('web reverse cdp mcp'),
        isNull,
      );
      expect(McpServer.defaultVisibleTemplateIdsForName('Custom MCP'), isNull);
    });
  });
}
