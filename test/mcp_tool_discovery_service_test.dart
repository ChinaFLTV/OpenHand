import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

void main() {
  test(
    'DefaultMcpToolDiscoveryService ignores malformed SSE events before the matching JSON-RPC message',
    () async {
      final service = DefaultMcpToolDiscoveryService(
        client: _QueuedHttpClient(<_QueuedHttpResponse>[
          _QueuedHttpResponse(
            statusCode: 200,
            headers: <String, String>{
              'content-type': 'application/json',
              'mcp-session-id': 'session-1',
            },
            body: jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 1,
              'result': <String, Object?>{'protocolVersion': '2025-11-25'},
            }),
          ),
          const _QueuedHttpResponse(
            statusCode: 202,
            headers: <String, String>{'content-type': 'application/json'},
            body: '',
          ),
          _QueuedHttpResponse(
            statusCode: 200,
            headers: <String, String>{
              'content-type': 'text/event-stream',
              'mcp-session-id': 'session-1',
            },
            body: [
              'event: message',
              'data: not-json',
              '',
              'event: message',
              'data: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"tail_logs","title":"Tail Logs","description":"Inspect service logs.","inputSchema":{"type":"object"}}]}}',
              '',
            ].join('\n'),
          ),
        ]),
      );
      addTearDown(service.dispose);

      final catalog = await service.discoverTools(
        const McpServer(
          name: 'local-http',
          type: McpServerType.streamableHttp,
          enabled: true,
          url: 'https://mcp.example/tools',
        ),
      );

      expect(catalog.status, McpToolCatalogStatus.ready);
      expect(catalog.tools, hasLength(1));
      expect(catalog.tools.single.id, 'tail_logs');
      expect(catalog.tools.single.name, 'Tail Logs');
    },
  );

  test(
    'DefaultMcpToolDiscoveryService reports healthy when initialize succeeds',
    () async {
      final service = DefaultMcpToolDiscoveryService(
        client: _QueuedHttpClient(<_QueuedHttpResponse>[
          _QueuedHttpResponse(
            statusCode: 200,
            headers: <String, String>{
              'content-type': 'application/json',
              'mcp-session-id': 'session-health',
            },
            body: jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 1,
              'result': <String, Object?>{'protocolVersion': '2025-11-25'},
            }),
          ),
          const _QueuedHttpResponse(
            statusCode: 202,
            headers: <String, String>{'content-type': 'application/json'},
            body: '',
          ),
        ]),
      );
      addTearDown(service.dispose);

      final health = await service.checkHealth(
        const McpServer(
          name: 'local-http',
          type: McpServerType.streamableHttp,
          enabled: true,
          url: 'https://mcp.example/tools',
        ),
      );

      expect(health.status, McpServerHealthStatus.healthy);
      expect(health.errorMessage, isNull);
      expect(health.lastCheckedAt, isNotNull);
    },
  );

  test(
    'DefaultMcpToolDiscoveryService sends custom headers on streamable HTTP requests',
    () async {
      final client = _QueuedHttpClient(<_QueuedHttpResponse>[
        _QueuedHttpResponse(
          statusCode: 200,
          headers: <String, String>{
            'content-type': 'application/json',
            'mcp-session-id': 'session-custom-headers',
          },
          body: jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'result': <String, Object?>{'protocolVersion': '2025-03-26'},
          }),
        ),
        const _QueuedHttpResponse(
          statusCode: 202,
          headers: <String, String>{'content-type': 'application/json'},
          body: '',
        ),
        _QueuedHttpResponse(
          statusCode: 200,
          headers: <String, String>{
            'content-type': 'application/json',
            'mcp-session-id': 'session-custom-headers',
          },
          body: jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 2,
            'result': <String, Object?>{
              'tools': <Object?>[
                <String, Object?>{
                  'name': 'tail_logs',
                  'description': 'Inspect service logs.',
                  'inputSchema': <String, Object?>{'type': 'object'},
                },
              ],
            },
          }),
        ),
      ]);
      final service = DefaultMcpToolDiscoveryService(client: client);
      addTearDown(service.dispose);

      final catalog = await service.discoverTools(
        const McpServer(
          name: 'local-http',
          type: McpServerType.streamableHttp,
          enabled: true,
          url: 'https://mcp.example/tools',
          headers: <String, String>{
            'Authorization': 'Bearer secret-token',
            'X-Workspace': 'openhand',
          },
        ),
      );

      expect(catalog.status, McpToolCatalogStatus.ready);
      expect(client.requests, hasLength(3));
      for (final request in client.requests) {
        expect(
          _readRequestHeader(request, 'authorization'),
          'Bearer secret-token',
        );
        expect(_readRequestHeader(request, 'x-workspace'), 'openhand');
      }
    },
  );

  test(
    'DefaultMcpToolDiscoveryService follows POST redirects for streamable HTTP servers',
    () async {
      final client = _QueuedHttpClient(<_QueuedHttpResponse>[
        const _QueuedHttpResponse(
          statusCode: 307,
          headers: <String, String>{
            'content-type': 'application/json',
            'location': '/mcp/v1/',
          },
          body: '',
        ),
        _QueuedHttpResponse(
          statusCode: 200,
          headers: <String, String>{
            'content-type': 'application/json',
            'mcp-session-id': 'session-redirect',
          },
          body: jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'result': <String, Object?>{'protocolVersion': '2025-03-26'},
          }),
        ),
        const _QueuedHttpResponse(
          statusCode: 202,
          headers: <String, String>{'content-type': 'application/json'},
          body: '',
        ),
        _QueuedHttpResponse(
          statusCode: 200,
          headers: <String, String>{
            'content-type': 'application/json',
            'mcp-session-id': 'session-redirect',
          },
          body: jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 2,
            'result': <String, Object?>{
              'tools': <Object?>[
                <String, Object?>{
                  'name': 'tail_logs',
                  'description': 'Inspect service logs.',
                  'inputSchema': <String, Object?>{'type': 'object'},
                },
              ],
            },
          }),
        ),
      ]);
      final service = DefaultMcpToolDiscoveryService(client: client);
      addTearDown(service.dispose);

      final catalog = await service.discoverTools(
        const McpServer(
          name: 'redirect-http',
          type: McpServerType.streamableHttp,
          enabled: true,
          url: 'https://mcp.example/mcp/v1',
        ),
      );

      expect(catalog.status, McpToolCatalogStatus.ready);
      expect(catalog.tools.single.id, 'tail_logs');
      expect(client.requests, hasLength(4));
      expect(client.requests.first.method, 'POST');
      expect(client.requests.first.url.path, '/mcp/v1');
      expect(client.requests[1].method, 'POST');
      expect(client.requests[2].method, 'POST');
      expect(client.requests[3].method, 'POST');
    },
  );

  test(
    'DefaultMcpToolDiscoveryService strips session headers on cross-origin redirects',
    () async {
      final client = _QueuedHttpClient(<_QueuedHttpResponse>[
        _QueuedHttpResponse(
          statusCode: 200,
          headers: <String, String>{
            'content-type': 'application/json',
            'mcp-session-id': 'session-cross-origin',
          },
          body: jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'result': <String, Object?>{'protocolVersion': '2025-03-26'},
          }),
        ),
        const _QueuedHttpResponse(
          statusCode: 202,
          headers: <String, String>{'content-type': 'application/json'},
          body: '',
        ),
        const _QueuedHttpResponse(
          statusCode: 307,
          headers: <String, String>{
            'content-type': 'application/json',
            'location': 'https://redirect.example/mcp/v1/',
          },
          body: '',
        ),
        _QueuedHttpResponse(
          statusCode: 200,
          headers: <String, String>{
            'content-type': 'application/json',
            'mcp-session-id': 'session-cross-origin',
          },
          body: jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 2,
            'result': <String, Object?>{
              'tools': <Object?>[
                <String, Object?>{
                  'name': 'tail_logs',
                  'description': 'Inspect service logs.',
                  'inputSchema': <String, Object?>{'type': 'object'},
                },
              ],
            },
          }),
        ),
      ]);
      final service = DefaultMcpToolDiscoveryService(client: client);
      addTearDown(service.dispose);

      final catalog = await service.discoverTools(
        const McpServer(
          name: 'cross-origin-http',
          type: McpServerType.streamableHttp,
          enabled: true,
          url: 'https://mcp.example/mcp/v1/',
          headers: <String, String>{
            'Authorization': 'Bearer secret-token',
            'X-Workspace': 'openhand',
          },
        ),
      );

      expect(catalog.status, McpToolCatalogStatus.ready);
      expect(client.requests, hasLength(4));
      expect(
        _readRequestHeader(client.requests[2], 'authorization'),
        'Bearer secret-token',
      );
      expect(_readRequestHeader(client.requests[2], 'x-workspace'), 'openhand');
      expect(
        client.requests[2].headers['mcp-session-id'],
        'session-cross-origin',
      );
      expect(client.requests[3].url.host, 'redirect.example');
      expect(client.requests[3].headers.containsKey('mcp-session-id'), isFalse);
      expect(_readRequestHeader(client.requests[3], 'authorization'), isNull);
      expect(_readRequestHeader(client.requests[3], 'x-workspace'), isNull);
    },
  );

  test(
    'DefaultMcpToolDiscoveryService reports unhealthy when initialize fails',
    () async {
      final service = DefaultMcpToolDiscoveryService(
        client: _QueuedHttpClient(<_QueuedHttpResponse>[
          const _QueuedHttpResponse(
            statusCode: 307,
            headers: <String, String>{'content-type': 'application/json'},
            body: '',
          ),
        ]),
      );
      addTearDown(service.dispose);

      final health = await service.checkHealth(
        const McpServer(
          name: 'local-http',
          type: McpServerType.streamableHttp,
          enabled: true,
          url: 'https://mcp.example/tools',
        ),
      );

      expect(health.status, McpServerHealthStatus.unhealthy);
      expect(health.errorMessage, contains('HTTP 307'));
      expect(health.lastCheckedAt, isNotNull);
    },
  );

  test(
    'DefaultMcpToolDiscoveryService falls back from SSE to streamable HTTP when the server does not expose a legacy endpoint',
    () async {
      final client = _QueuedHttpClient(<_QueuedHttpResponse>[
        const _QueuedHttpResponse(
          statusCode: 200,
          headers: <String, String>{'content-type': 'text/event-stream'},
          body: '',
        ),
        _QueuedHttpResponse(
          statusCode: 200,
          headers: <String, String>{
            'content-type': 'application/json',
            'mcp-session-id': 'session-fallback',
          },
          body: jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'result': <String, Object?>{'protocolVersion': '2025-03-26'},
          }),
        ),
        const _QueuedHttpResponse(
          statusCode: 202,
          headers: <String, String>{'content-type': 'application/json'},
          body: '',
        ),
        _QueuedHttpResponse(
          statusCode: 200,
          headers: <String, String>{
            'content-type': 'application/json',
            'mcp-session-id': 'session-fallback',
          },
          body: jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 2,
            'result': <String, Object?>{
              'tools': <Object?>[
                <String, Object?>{
                  'name': 'send_dingtalk_msg_tool',
                  'description': 'Send DingTalk message.',
                  'inputSchema': <String, Object?>{'type': 'object'},
                },
              ],
            },
          }),
        ),
      ]);
      final service = DefaultMcpToolDiscoveryService(client: client);
      addTearDown(service.dispose);

      final catalog = await service.discoverTools(
        const McpServer(
          name: 'fallback-sse',
          type: McpServerType.sse,
          enabled: true,
          url: 'https://mcp.example/mcp/v1/',
        ),
      );

      expect(catalog.status, McpToolCatalogStatus.ready);
      expect(catalog.tools.single.id, 'send_dingtalk_msg_tool');
      expect(client.requests, hasLength(4));
      expect(client.requests.first.method, 'GET');
      expect(client.requests[1].method, 'POST');
    },
  );

  test(
    'DefaultMcpToolDiscoveryService falls back from SSE to streamable HTTP when the server does not return an event stream',
    () async {
      final client = _QueuedHttpClient(<_QueuedHttpResponse>[
        const _QueuedHttpResponse(
          statusCode: 200,
          headers: <String, String>{'content-type': 'application/json'},
          body: '{}',
        ),
        _QueuedHttpResponse(
          statusCode: 200,
          headers: <String, String>{
            'content-type': 'application/json',
            'mcp-session-id': 'session-fallback',
          },
          body: jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'result': <String, Object?>{'protocolVersion': '2025-03-26'},
          }),
        ),
        const _QueuedHttpResponse(
          statusCode: 202,
          headers: <String, String>{'content-type': 'application/json'},
          body: '',
        ),
        _QueuedHttpResponse(
          statusCode: 200,
          headers: <String, String>{
            'content-type': 'application/json',
            'mcp-session-id': 'session-fallback',
          },
          body: jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 2,
            'result': <String, Object?>{
              'tools': <Object?>[
                <String, Object?>{
                  'name': 'send_dingtalk_msg_tool',
                  'description': 'Send DingTalk message.',
                  'inputSchema': <String, Object?>{'type': 'object'},
                },
              ],
            },
          }),
        ),
      ]);
      final service = DefaultMcpToolDiscoveryService(client: client);
      addTearDown(service.dispose);

      final catalog = await service.discoverTools(
        const McpServer(
          name: 'fallback-sse',
          type: McpServerType.sse,
          enabled: true,
          url: 'https://mcp.example/mcp/v1/',
        ),
      );

      expect(catalog.status, McpToolCatalogStatus.ready);
      expect(catalog.tools.single.id, 'send_dingtalk_msg_tool');
      expect(client.requests, hasLength(4));
      expect(client.requests.first.method, 'GET');
      expect(client.requests[1].method, 'POST');
    },
  );

  test(
    'DefaultMcpToolDiscoveryService preserves raw metadata for non-standard tool schemas',
    () async {
      final service = DefaultMcpToolDiscoveryService(
        client: _QueuedHttpClient(<_QueuedHttpResponse>[
          _QueuedHttpResponse(
            statusCode: 200,
            headers: <String, String>{
              'content-type': 'application/json',
              'mcp-session-id': 'session-2',
            },
            body: jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 1,
              'result': <String, Object?>{'protocolVersion': '2025-11-25'},
            }),
          ),
          const _QueuedHttpResponse(
            statusCode: 202,
            headers: <String, String>{'content-type': 'application/json'},
            body: '',
          ),
          _QueuedHttpResponse(
            statusCode: 200,
            headers: <String, String>{
              'content-type': 'application/json',
              'mcp-session-id': 'session-2',
            },
            body: jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 2,
              'result': <String, Object?>{
                'tools': <Object?>[
                  <String, Object?>{
                    'name': 'deploy_release',
                    'title': 'Deploy Release',
                    'description': 'Deploy a tagged release.',
                    'inputSchema': <Object?>[
                      <String, Object?>{
                        'name': 'environment',
                        'type': 'string',
                        'description': 'Target environment.',
                        'required': true,
                      },
                    ],
                    'outputSchema': 'plain-text',
                  },
                ],
              },
            }),
          ),
        ]),
      );
      addTearDown(service.dispose);

      final catalog = await service.discoverTools(
        const McpServer(
          name: 'local-http',
          type: McpServerType.streamableHttp,
          enabled: true,
          url: 'https://mcp.example/tools',
        ),
      );

      expect(catalog.status, McpToolCatalogStatus.ready);
      expect(catalog.tools, hasLength(1));
      final tool = catalog.tools.single;
      expect(
        tool.metadataWarning,
        contains('Input schema is not a structured object'),
      );
      expect(
        tool.metadataWarning,
        contains('Output schema is not a structured object'),
      );
      expect(tool.inputSchema, <String, Object?>{'type': 'object'});
      expect(tool.rawInputSchema, isA<List<Object?>>());
      expect(tool.rawOutputSchema, 'plain-text');
      expect(tool.rawMetadata['outputSchema'], 'plain-text');
    },
  );
}

class _QueuedHttpClient extends http.BaseClient {
  _QueuedHttpClient(this._responses);

  final List<_QueuedHttpResponse> _responses;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = _responses.removeAt(0);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[utf8.encode(response.body)]),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

class _QueuedHttpResponse {
  const _QueuedHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}

String? _readRequestHeader(http.BaseRequest request, String name) {
  final target = name.toLowerCase();
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == target) {
      return entry.value;
    }
  }
  return null;
}
