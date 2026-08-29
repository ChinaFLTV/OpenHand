import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../app/support/system_proxy.dart';
import '../../../shared/util/text_clip.dart';
import '../../ai/index.dart'
    show
        AiChatClient,
        AiChatCompletion,
        AiChatRole,
        AiChatService,
        AiChatTurn,
        AiModelConfig,
        AiPromptTemplateRepository,
        AiToolDefinition;
import '../../instructions/index.dart' show UserInstructionEntry;
import '../../knowledge_base/index.dart'
    show KnowledgeBaseController, KnowledgeRetrievalHit;
import '../../mcp/index.dart' show McpServer, McpTool;
import '../../memory/index.dart' show UserMemoryEntry;
import '../../skills/index.dart' show LocalSkill;
import '../model/workflow_definition.dart';

const int _maxWorkflowHttpResponseBytes = 4 * 1024 * 1024;
const int _maxWorkflowPromptCharacters = 256 * 1024;
const int _maxWorkflowResourceCharacters = 96 * 1024;
const int _maxWorkflowRetries = 10;
const int _maxWorkflowRetryIntervalMs = 60 * 1000;
const int _maxWorkflowMcpTools = 64;
const int _maxWorkflowToolRounds = 8;
const int _maxWorkflowToolCalls = 32;
const int _maxWorkflowToolOutputCharacters = 128 * 1024;

typedef WorkflowMcpToolInvoker =
    Future<WorkflowMcpToolInvocationResult> Function({
      required String serverName,
      required String toolName,
      required Map<String, Object?> arguments,
      required String toolCallId,
    });

class WorkflowMcpToolInvocationResult {
  const WorkflowMcpToolInvocationResult({
    required this.output,
    required this.isError,
  });

  final String output;
  final bool isError;
}

class WorkflowNodeExecutionException implements Exception {
  const WorkflowNodeExecutionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class WorkflowExecutionResources {
  const WorkflowExecutionResources({
    required this.models,
    required this.templateRepository,
    this.skills = const <LocalSkill>[],
    this.memories = const <UserMemoryEntry>[],
    this.instructions = const <UserInstructionEntry>[],
    this.knowledgeBaseController,
    this.mcpServers = const <McpServer>[],
    this.mcpTools = const <String, List<McpTool>>{},
    this.mcpToolInvoker,
  });

  final List<AiModelConfig> models;
  final AiPromptTemplateRepository templateRepository;
  final List<LocalSkill> skills;
  final List<UserMemoryEntry> memories;
  final List<UserInstructionEntry> instructions;
  final KnowledgeBaseController? knowledgeBaseController;
  final List<McpServer> mcpServers;
  final Map<String, List<McpTool>> mcpTools;
  final WorkflowMcpToolInvoker? mcpToolInvoker;
}

class WorkflowNodeExecutionResult {
  const WorkflowNodeExecutionResult({
    required this.output,
    required this.attempts,
    required this.duration,
    this.rawOutput = '',
  });

  final Object? output;
  final String rawOutput;
  final int attempts;
  final Duration duration;
}

class WorkflowNodeExecutor {
  WorkflowNodeExecutor({AiChatClient? chatClient})
    : _chatClient = chatClient ?? AiChatService(),
      _ownsChatClient = chatClient == null;

  final AiChatClient _chatClient;
  final bool _ownsChatClient;

  Future<WorkflowNodeExecutionResult> execute({
    required WorkflowNode node,
    required WorkflowExecutionResources resources,
    Map<String, Object?> variables = const <String, Object?>{},
  }) {
    return switch (node.kind) {
      WorkflowNodeKind.llm => _executeLlm(node, resources, variables),
      WorkflowNodeKind.httpRequest => _executeHttp(node, variables),
      WorkflowNodeKind.condition => _executeCondition(node, variables),
      WorkflowNodeKind.loop => _executeLoop(node),
      WorkflowNodeKind.iteration => _executeIteration(node, variables),
    };
  }

  void dispose() {
    if (_ownsChatClient) _chatClient.dispose();
  }

  Future<WorkflowNodeExecutionResult> _executeLlm(
    WorkflowNode node,
    WorkflowExecutionResources resources,
    Map<String, Object?> variables,
  ) async {
    final modelId = node
        .stringSetting(WorkflowSettingKeys.modelConfigId)
        .trim();
    final model = resources.models
        .where((item) => item.id == modelId)
        .firstOrNull;
    if (model == null) {
      throw const WorkflowNodeExecutionException('请选择可用模型。');
    }
    final prompt = renderWorkflowTemplate(
      node.stringSetting(WorkflowSettingKeys.prompt),
      variables,
    ).trim();
    if (prompt.isEmpty) {
      throw const WorkflowNodeExecutionException('提示词不能为空。');
    }
    if (prompt.length > _maxWorkflowPromptCharacters) {
      throw const WorkflowNodeExecutionException('提示词超过长度上限。');
    }

    final templateId = node
        .stringSetting(WorkflowSettingKeys.templateId)
        .trim();
    final bundle = await resources.templateRepository.loadBundle(
      templateId.isEmpty ? 'default' : templateId,
    );
    final resourcePrompt = await _buildResourcePrompt(
      node: node,
      resources: resources,
      query: prompt,
    );
    final outputFields = node.outputFields();
    final structured = node.boolSetting(WorkflowSettingKeys.structuredOutput);
    if (structured) WorkflowStructuredOutputParser.validateFields(outputFields);
    final systemPrompt = <String>[
      bundle.systemInstructions.trim(),
      bundle.developerInstructions.trim(),
      resourcePrompt,
      if (structured) WorkflowStructuredOutputParser.schemaPrompt(outputFields),
    ].where((part) => part.isNotEmpty).join('\n\n');
    final mcpBindings = _resolveMcpBindings(node, resources);

    final retries = _boundedRetryCount(node);
    final interval = _boundedRetryInterval(node);
    final stopwatch = Stopwatch()..start();
    var attempts = 0;
    Object? lastError;
    while (attempts <= retries) {
      attempts += 1;
      try {
        final completion = await _sendLlmWithTools(
          model: model,
          systemPrompt: systemPrompt,
          prompt: prompt,
          bindings: mcpBindings,
          invoker: resources.mcpToolInvoker,
        );
        final raw = completion.reply.trim();
        if (raw.isEmpty) {
          throw const WorkflowNodeExecutionException('模型返回内容为空。');
        }
        final output = structured
            ? WorkflowStructuredOutputParser.parse(raw, outputFields)
            : raw;
        stopwatch.stop();
        return WorkflowNodeExecutionResult(
          output: output,
          rawOutput: raw,
          attempts: attempts,
          duration: stopwatch.elapsed,
        );
      } catch (error) {
        lastError = error;
        if (attempts > retries) break;
        await Future<void>.delayed(interval);
      }
    }
    stopwatch.stop();
    throw WorkflowNodeExecutionException(
      'LLM 节点执行失败：${_executionErrorText(lastError)}',
      cause: lastError,
    );
  }

  Future<AiChatCompletion> _sendLlmWithTools({
    required AiModelConfig model,
    required String systemPrompt,
    required String prompt,
    required List<_WorkflowMcpBinding> bindings,
    required WorkflowMcpToolInvoker? invoker,
  }) async {
    final messages = <AiChatTurn>[
      AiChatTurn(role: AiChatRole.system, content: systemPrompt),
      AiChatTurn(role: AiChatRole.user, content: prompt),
    ];
    final tools = bindings
        .map(
          (binding) => AiToolDefinition(
            name: binding.callName,
            description: binding.tool.description.trim().isEmpty
                ? '调用 ${binding.server.name} 的 ${binding.tool.name} 工具。'
                : binding.tool.description.trim(),
            parameters: binding.tool.inputSchema,
          ),
        )
        .toList(growable: false);
    final bindingsByName = <String, _WorkflowMcpBinding>{
      for (final binding in bindings) binding.callName: binding,
    };
    var totalToolCalls = 0;
    for (var round = 0; round <= _maxWorkflowToolRounds; round++) {
      final completion = await _chatClient.sendMessage(
        model: model,
        messages: messages,
        tools: tools,
        timeout: const Duration(seconds: 120),
      );
      if (completion.toolCalls.isEmpty) return completion;
      if (invoker == null || bindings.isEmpty) {
        throw const WorkflowNodeExecutionException('MCP 工具执行器不可用。');
      }
      if (round == _maxWorkflowToolRounds) {
        throw const WorkflowNodeExecutionException('MCP 工具调用超过轮次上限。');
      }
      totalToolCalls += completion.toolCalls.length;
      if (totalToolCalls > _maxWorkflowToolCalls) {
        throw const WorkflowNodeExecutionException('MCP 工具调用数量超过上限。');
      }
      messages.add(
        AiChatTurn(
          role: AiChatRole.assistant,
          content: completion.reply,
          toolCalls: completion.toolCalls,
          reasoningContent: completion.reasoningContent,
        ),
      );
      for (final call in completion.toolCalls) {
        final binding = bindingsByName[call.name];
        if (binding == null) {
          throw WorkflowNodeExecutionException('模型请求了未授权工具：${call.name}');
        }
        final arguments = _decodeToolArguments(call.arguments, call.name);
        final result =
            await invoker(
              serverName: binding.server.name,
              toolName: binding.tool.id,
              arguments: arguments,
              toolCallId: call.id,
            ).timeout(
              const Duration(seconds: 120),
              onTimeout: () => throw TimeoutException('MCP 工具调用超时。'),
            );
        final output = _boundedToolOutput(result.output);
        messages.add(
          AiChatTurn(
            role: AiChatRole.tool,
            toolCallId: call.id,
            content: result.isError ? '工具执行失败：$output' : output,
          ),
        );
      }
    }
    throw const WorkflowNodeExecutionException('LLM 工具调用未能完成。');
  }

  List<_WorkflowMcpBinding> _resolveMcpBindings(
    WorkflowNode node,
    WorkflowExecutionResources resources,
  ) {
    final selectedNames = node.stringSetSetting(
      WorkflowSettingKeys.mcpServerNames,
    );
    if (selectedNames.isEmpty) return const <_WorkflowMcpBinding>[];
    final bindings = <_WorkflowMcpBinding>[];
    final usedNames = <String>{};
    for (final server in resources.mcpServers) {
      if (!server.enabled || !selectedNames.contains(server.name)) continue;
      for (final tool in resources.mcpTools[server.name] ?? const <McpTool>[]) {
        if (bindings.length >= _maxWorkflowMcpTools) {
          return List<_WorkflowMcpBinding>.unmodifiable(bindings);
        }
        bindings.add(
          _WorkflowMcpBinding(
            callName: _workflowMcpToolName(server.name, tool.id, usedNames),
            server: server,
            tool: tool,
          ),
        );
      }
    }
    return List<_WorkflowMcpBinding>.unmodifiable(bindings);
  }

  Future<String> _buildResourcePrompt({
    required WorkflowNode node,
    required WorkflowExecutionResources resources,
    required String query,
  }) async {
    final sections = <String>[];
    final skillNames = node.stringSetSetting(WorkflowSettingKeys.skillNames);
    final skills = resources.skills.where(
      (item) => skillNames.contains(item.name),
    );
    if (skills.isNotEmpty) {
      sections.add(
        '<WorkflowSkills>\n${skills.map((skill) {
          final guidance = skill.defaultPrompt?.trim();
          return '- ${skill.name}: ${guidance?.isNotEmpty == true ? guidance : skill.description.trim()}';
        }).join('\n')}\n</WorkflowSkills>',
      );
    }

    final memoryIds = node.stringSetSetting(WorkflowSettingKeys.memoryIds);
    final memories = resources.memories.where(
      (item) => memoryIds.contains(item.id),
    );
    if (memories.isNotEmpty) {
      sections.add(
        '<WorkflowMemory>\n${memories.map((item) => item.content.trim()).join('\n\n')}\n</WorkflowMemory>',
      );
    }

    final instructionIds = node.stringSetSetting(
      WorkflowSettingKeys.instructionIds,
    );
    final instructions = resources.instructions.where(
      (item) => item.enabled && instructionIds.contains(item.id),
    );
    if (instructions.isNotEmpty) {
      sections.add(
        '<WorkflowInstructions>\n${instructions.map((item) => item.body.trim()).join('\n\n')}\n</WorkflowInstructions>',
      );
    }

    final mcpNames = node.stringSetSetting(WorkflowSettingKeys.mcpServerNames);
    final mcpServers = resources.mcpServers.where(
      (item) => item.enabled && mcpNames.contains(item.name),
    );
    if (mcpServers.isNotEmpty) {
      sections.add(
        '<WorkflowMcpScope>\n${mcpServers.map((server) {
          final tools = resources.mcpTools[server.name] ?? const <McpTool>[];
          final suffix = tools.isEmpty ? '' : '；工具：${tools.take(24).map((tool) => tool.name).join('、')}';
          return '- ${server.name}（${server.type.transportValue}）$suffix';
        }).join('\n')}\n</WorkflowMcpScope>',
      );
    }

    final capabilityNames = node.stringSetSetting(
      WorkflowSettingKeys.multimodalCapabilities,
    );
    if (capabilityNames.isNotEmpty) {
      sections.add(
        '<WorkflowMultimodalCapabilities>${capabilityNames.join(', ')}</WorkflowMultimodalCapabilities>',
      );
    }

    final knowledgeIds = node.stringSetSetting(
      WorkflowSettingKeys.knowledgeSourceIds,
    );
    final knowledge = resources.knowledgeBaseController;
    if (knowledge != null && knowledgeIds.isNotEmpty) {
      try {
        final retrieved = await knowledge.retrieveForTool(
          query: query,
          topK: 20,
          models: resources.models,
        );
        if (retrieved != null) {
          final hits = retrieved.result.hits
              .where((hit) => knowledgeIds.contains(hit.source.id))
              .take(12)
              .toList(growable: false);
          final context = _knowledgePrompt(hits);
          if (context.isNotEmpty) sections.add(context);
        }
      } catch (_) {
        throw const WorkflowNodeExecutionException('检索所选知识库失败。');
      }
    }
    final joined = sections.join('\n\n');
    if (joined.length <= _maxWorkflowResourceCharacters) return joined;
    return joined.substring(0, _maxWorkflowResourceCharacters);
  }

  String _knowledgePrompt(List<KnowledgeRetrievalHit> hits) {
    if (hits.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('<WorkflowKnowledge>')
      ..writeln('仅在相关时使用以下本地知识，不得虚构引用。');
    for (var index = 0; index < hits.length; index++) {
      final hit = hits[index];
      buffer
        ..writeln('[KB-${index + 1}] ${hit.source.title}')
        ..writeln(hit.chunk.content.trim())
        ..writeln();
    }
    buffer.write('</WorkflowKnowledge>');
    return buffer.toString();
  }

  Future<WorkflowNodeExecutionResult> _executeHttp(
    WorkflowNode node,
    Map<String, Object?> variables,
  ) async {
    final rawUrl = renderWorkflowTemplate(
      node.stringSetting(WorkflowSettingKeys.url),
      variables,
    ).trim();
    final parsedUrl = Uri.tryParse(rawUrl);
    if (parsedUrl == null ||
        !parsedUrl.hasScheme ||
        !const <String>{'http', 'https'}.contains(parsedUrl.scheme) ||
        parsedUrl.host.isEmpty) {
      throw const WorkflowNodeExecutionException('请输入有效的 HTTP 或 HTTPS 地址。');
    }
    final params = <String, String>{...parsedUrl.queryParameters};
    for (final item in node.keyValueSetting(
      WorkflowSettingKeys.queryParameters,
    )) {
      final key = renderWorkflowTemplate(item.key, variables).trim();
      if (!item.enabled || key.isEmpty) continue;
      params[key] = renderWorkflowTemplate(item.value, variables);
    }
    final uri = parsedUrl.replace(
      queryParameters: params.isEmpty ? null : params,
    );
    final method = node
        .stringSetting(WorkflowSettingKeys.method, 'GET')
        .trim()
        .toUpperCase();
    if (!const <String>{
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
      'HEAD',
    }.contains(method)) {
      throw const WorkflowNodeExecutionException('HTTP 请求方式无效。');
    }
    final retries = _boundedRetryCount(node);
    final interval = _boundedRetryInterval(node);
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    var attempts = 0;
    while (attempts <= retries) {
      attempts += 1;
      try {
        final response = await _sendHttpRequest(
          node: node,
          method: method,
          uri: uri,
          variables: variables,
        );
        final structured = node.boolSetting(
          WorkflowSettingKeys.structuredOutput,
        );
        final fields = node.outputFields();
        final output = structured
            ? WorkflowStructuredOutputParser.parse(response.body, fields)
            : <String, Object?>{
                'status_code': response.statusCode,
                'headers': response.headers,
                'body': response.body,
              };
        stopwatch.stop();
        return WorkflowNodeExecutionResult(
          output: output,
          rawOutput: response.body,
          attempts: attempts,
          duration: stopwatch.elapsed,
        );
      } catch (error) {
        lastError = error;
        if (attempts > retries) break;
        await Future<void>.delayed(interval);
      }
    }
    stopwatch.stop();
    throw WorkflowNodeExecutionException(
      'HTTP 节点执行失败：${_executionErrorText(lastError)}',
      cause: lastError,
    );
  }

  Future<_WorkflowHttpResponse> _sendHttpRequest({
    required WorkflowNode node,
    required String method,
    required Uri uri,
    required Map<String, Object?> variables,
  }) async {
    final connectSeconds = node
        .intSetting(WorkflowSettingKeys.connectTimeoutSeconds, 15)
        .clamp(1, 120);
    final responseSeconds = node
        .intSetting(WorkflowSettingKeys.responseTimeoutSeconds, 60)
        .clamp(1, 600);
    final client = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: Duration(seconds: connectSeconds),
      userAgent: 'OpenHand-Workflow/1.0',
    );
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(
            Duration(seconds: connectSeconds),
            onTimeout: () => throw TimeoutException('HTTP 连接超时。'),
          );
      for (final item in node.keyValueSetting(WorkflowSettingKeys.headers)) {
        final key = renderWorkflowTemplate(item.key, variables).trim();
        if (!item.enabled || key.isEmpty) continue;
        request.headers.set(key, renderWorkflowTemplate(item.value, variables));
      }
      if (!const <String>{'GET', 'HEAD'}.contains(method)) {
        _writeHttpBody(request, node, variables);
      }
      final response = await request.close().timeout(
        Duration(seconds: responseSeconds),
        onTimeout: () {
          request.abort(TimeoutException('HTTP 响应超时。'));
          throw TimeoutException('HTTP 响应超时。');
        },
      );
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(
        Duration(seconds: responseSeconds),
      )) {
        if (bytes.length + chunk.length > _maxWorkflowHttpResponseBytes) {
          throw const WorkflowNodeExecutionException('HTTP 响应超过 4 MiB 上限。');
        }
        bytes.add(chunk);
      }
      final body = utf8.decode(bytes.takeBytes(), allowMalformed: true);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final preview = body.length > 500 ? '${body.substring(0, 500)}…' : body;
        throw WorkflowNodeExecutionException(
          'HTTP ${response.statusCode}${preview.trim().isEmpty ? '' : '：$preview'}',
        );
      }
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });
      return _WorkflowHttpResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }

  void _writeHttpBody(
    HttpClientRequest request,
    WorkflowNode node,
    Map<String, Object?> variables,
  ) {
    final format = WorkflowHttpBodyFormat.fromStorage(
      node.settings[WorkflowSettingKeys.bodyFormat],
    );
    final body = renderWorkflowTemplate(
      node.stringSetting(WorkflowSettingKeys.body),
      variables,
    );
    switch (format) {
      case WorkflowHttpBodyFormat.none:
        return;
      case WorkflowHttpBodyFormat.json:
        try {
          request.add(utf8.encode(jsonEncode(jsonDecode(body))));
        } on FormatException {
          throw const WorkflowNodeExecutionException('请求体不是有效 JSON。');
        }
        request.headers.contentType = ContentType.json;
        return;
      case WorkflowHttpBodyFormat.text:
        request.headers.contentType = ContentType.text;
        request.add(utf8.encode(body));
        return;
      case WorkflowHttpBodyFormat.formUrlEncoded:
        final values = _bodyEntries(node, variables);
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.add(utf8.encode(Uri(queryParameters: values).query));
        return;
      case WorkflowHttpBodyFormat.formData:
        final boundary = 'openhand-${DateTime.now().microsecondsSinceEpoch}';
        request.headers.contentType = ContentType(
          'multipart',
          'form-data',
          parameters: <String, String>{'boundary': boundary},
        );
        final buffer = StringBuffer();
        for (final entry in _bodyEntries(node, variables).entries) {
          buffer
            ..writeln('--$boundary')
            ..writeln(
              'Content-Disposition: form-data; name="${_escapeMultipartName(entry.key)}"',
            )
            ..writeln()
            ..writeln(entry.value);
        }
        buffer.write('--$boundary--\r\n');
        request.add(utf8.encode(buffer.toString().replaceAll('\n', '\r\n')));
        return;
    }
  }

  Map<String, String> _bodyEntries(
    WorkflowNode node,
    Map<String, Object?> variables,
  ) {
    final values = <String, String>{};
    for (final item in node.keyValueSetting(WorkflowSettingKeys.bodyEntries)) {
      final key = renderWorkflowTemplate(item.key, variables).trim();
      if (item.enabled && key.isNotEmpty) {
        values[key] = renderWorkflowTemplate(item.value, variables);
      }
    }
    return values;
  }

  String _escapeMultipartName(String value) =>
      value.replaceAll(RegExp(r'["\r\n]'), '_');

  Future<WorkflowNodeExecutionResult> _executeCondition(
    WorkflowNode node,
    Map<String, Object?> variables,
  ) async {
    final expression = renderWorkflowTemplate(
      node.stringSetting(WorkflowSettingKeys.expression),
      variables,
    ).trim();
    if (expression.isEmpty) {
      throw const WorkflowNodeExecutionException('条件表达式不能为空。');
    }
    final match = RegExp(
      r'^(.+?)\s*(==|!=|>=|<=|>|<|contains)\s*(.+)$',
    ).firstMatch(expression);
    if (match == null) {
      throw const WorkflowNodeExecutionException('条件表达式格式无效。');
    }
    final left = _literalValue(match.group(1)!.trim());
    final right = _literalValue(match.group(3)!.trim());
    final operator = match.group(2)!;
    final result = switch (operator) {
      '==' => left == right || '$left' == '$right',
      '!=' => left != right && '$left' != '$right',
      'contains' => '$left'.contains('$right'),
      '>' => _number(left) > _number(right),
      '<' => _number(left) < _number(right),
      '>=' => _number(left) >= _number(right),
      '<=' => _number(left) <= _number(right),
      _ => false,
    };
    return WorkflowNodeExecutionResult(
      output: result,
      rawOutput: '$result',
      attempts: 1,
      duration: Duration.zero,
    );
  }

  Future<WorkflowNodeExecutionResult> _executeLoop(WorkflowNode node) async {
    final count = node
        .intSetting(WorkflowSettingKeys.maxIterations, 10)
        .clamp(1, 1000);
    return WorkflowNodeExecutionResult(
      output: <String, Object?>{'max_iterations': count},
      rawOutput: '$count',
      attempts: 1,
      duration: Duration.zero,
    );
  }

  Future<WorkflowNodeExecutionResult> _executeIteration(
    WorkflowNode node,
    Map<String, Object?> variables,
  ) async {
    final key = node.stringSetting(WorkflowSettingKeys.iterationInput).trim();
    final raw = variables[key];
    final items = raw is List
        ? raw
        : raw is String
        ? _tryDecodeList(raw)
        : const <Object?>[];
    if (items.isEmpty) {
      throw const WorkflowNodeExecutionException('迭代输入必须是非空数组。');
    }
    return WorkflowNodeExecutionResult(
      output: List<Object?>.unmodifiable(items.take(1000)),
      rawOutput: jsonEncode(items.take(1000).toList(growable: false)),
      attempts: 1,
      duration: Duration.zero,
    );
  }

  int _boundedRetryCount(WorkflowNode node) => node
      .intSetting(WorkflowSettingKeys.retryCount, 0)
      .clamp(0, _maxWorkflowRetries);

  Duration _boundedRetryInterval(WorkflowNode node) => Duration(
    milliseconds: node
        .intSetting(WorkflowSettingKeys.retryIntervalMs, 1000)
        .clamp(0, _maxWorkflowRetryIntervalMs),
  );
}

abstract final class WorkflowStructuredOutputParser {
  static void validateFields(List<WorkflowOutputField> fields) {
    if (fields.isEmpty) {
      throw const WorkflowNodeExecutionException('结构化输出至少需要一个参数。');
    }
    final names = <String>{};
    for (final field in fields) {
      final name = field.name.trim();
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$').hasMatch(name)) {
        throw WorkflowNodeExecutionException('输出参数名称无效：${field.name}');
      }
      if (!names.add(name)) {
        throw WorkflowNodeExecutionException('输出参数名称重复：$name');
      }
      if (field.defaultValue.trim().isNotEmpty) {
        _coerce(field.defaultValue, field.type, fieldName: name);
      }
    }
  }

  static Map<String, Object?> parse(
    String raw,
    List<WorkflowOutputField> fields,
  ) {
    validateFields(fields);
    final decoded = _decodeObject(raw);
    if (decoded == null) {
      throw const WorkflowNodeExecutionException('无法从响应中解析结构化 JSON 对象。');
    }
    final result = <String, Object?>{};
    for (final field in fields) {
      final name = field.name.trim();
      final hasValue = decoded.containsKey(name) && decoded[name] != null;
      if (!hasValue) {
        if (field.defaultValue.trim().isNotEmpty) {
          result[name] = _coerce(
            field.defaultValue,
            field.type,
            fieldName: name,
          );
          continue;
        }
        if (field.required) {
          throw WorkflowNodeExecutionException('响应缺少必需参数：$name');
        }
        result[name] = null;
        continue;
      }
      result[name] = _coerce(decoded[name], field.type, fieldName: name);
    }
    return Map<String, Object?>.unmodifiable(result);
  }

  static Map<String, Object?> jsonSchema(List<WorkflowOutputField> fields) {
    validateFields(fields);
    return <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'properties': <String, Object?>{
        for (final field in fields)
          field.name.trim(): <String, Object?>{
            'type': field.type.storageValue,
            if (field.description.trim().isNotEmpty)
              'description': field.description.trim(),
            if (field.defaultValue.trim().isNotEmpty)
              'default': _coerce(
                field.defaultValue,
                field.type,
                fieldName: field.name.trim(),
              ),
          },
      },
      'required': fields
          .where((field) => field.required)
          .map((field) => field.name.trim())
          .toList(growable: false),
    };
  }

  static String schemaPrompt(List<WorkflowOutputField> fields) {
    final schema = const JsonEncoder.withIndent(
      '  ',
    ).convert(jsonSchema(fields));
    return '''# 响应格式
仅返回一个符合下列 JSON Schema 的 JSON 对象，不要添加 Markdown、解释或额外字段。

$schema''';
  }

  static Map<String, Object?>? _decodeObject(String raw) {
    final candidates = <String>[raw.trim()];
    final fencePattern = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    candidates.addAll(
      fencePattern.allMatches(raw).map((match) => match.group(1)?.trim() ?? ''),
    );
    final balanced = _firstBalancedObject(raw);
    if (balanced != null) candidates.add(balanced);
    for (final candidate in candidates.where((item) => item.isNotEmpty)) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) {
          return <String, Object?>{
            for (final entry in decoded.entries) '${entry.key}': entry.value,
          };
        }
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  static String? _firstBalancedObject(String raw) {
    var start = -1;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = 0; index < raw.length; index++) {
      final char = raw[index];
      if (start < 0) {
        if (char == '{') {
          start = index;
          depth = 1;
        }
        continue;
      }
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\' && inString) {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (char == '{') depth += 1;
      if (char == '}') depth -= 1;
      if (depth == 0) return raw.substring(start, index + 1);
    }
    return null;
  }

  static Object? _coerce(
    Object? value,
    WorkflowOutputType type, {
    required String fieldName,
  }) {
    try {
      return switch (type) {
        WorkflowOutputType.string =>
          value is String ? value : jsonEncode(value),
        WorkflowOutputType.integer =>
          value is int
              ? value
              : value is num && value == value.roundToDouble()
              ? value.toInt()
              : int.parse('$value'.trim()),
        WorkflowOutputType.number =>
          value is num ? value : num.parse('$value'.trim()),
        WorkflowOutputType.boolean => _boolValue(value),
        WorkflowOutputType.object => _objectValue(value),
        WorkflowOutputType.array => _arrayValue(value),
      };
    } catch (_) {
      throw WorkflowNodeExecutionException(
        '参数 $fieldName 无法转换为 ${type.storageValue}。',
      );
    }
  }

  static bool _boolValue(Object? value) {
    if (value is bool) return value;
    final normalized = '$value'.trim().toLowerCase();
    if (const <String>{'true', '1', 'yes', '是'}.contains(normalized)) {
      return true;
    }
    if (const <String>{'false', '0', 'no', '否'}.contains(normalized)) {
      return false;
    }
    throw const FormatException();
  }

  static Map<String, Object?> _objectValue(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! Map) throw const FormatException();
    return <String, Object?>{
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    };
  }

  static List<Object?> _arrayValue(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! List) throw const FormatException();
    return List<Object?>.unmodifiable(decoded);
  }
}

String renderWorkflowTemplate(String template, Map<String, Object?> variables) {
  if (template.isEmpty || variables.isEmpty) return template;
  return template.replaceAllMapped(
    RegExp(r'\{\{\s*([A-Za-z_][A-Za-z0-9_.-]*)\s*\}\}'),
    (match) {
      Object? value = variables;
      for (final segment in match.group(1)!.split('.')) {
        if (value is Map && value.containsKey(segment)) {
          value = value[segment];
        } else {
          return match.group(0)!;
        }
      }
      return value is String ? value : jsonEncode(value);
    },
  );
}

class _WorkflowMcpBinding {
  const _WorkflowMcpBinding({
    required this.callName,
    required this.server,
    required this.tool,
  });

  final String callName;
  final McpServer server;
  final McpTool tool;
}

String _workflowMcpToolName(
  String serverName,
  String toolName,
  Set<String> usedNames,
) {
  var base = 'mcp_${serverName}_$toolName'
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (base.isEmpty) base = 'mcp_tool';
  if (RegExp(r'^[0-9]').hasMatch(base)) base = 'mcp_$base';
  base = clipTextByCodeUnits(base, 56, suffix: '');
  var candidate = base;
  var suffix = 2;
  while (!usedNames.add(candidate)) {
    candidate = '${clipTextByCodeUnits(base, 52, suffix: '')}_${suffix++}';
  }
  return candidate;
}

Map<String, Object?> _decodeToolArguments(String raw, String toolName) {
  if (raw.length > 256 * 1024) {
    throw WorkflowNodeExecutionException('工具 $toolName 的参数超过长度上限。');
  }
  try {
    final decoded = jsonDecode(raw.trim().isEmpty ? '{}' : raw);
    if (decoded is! Map) throw const FormatException();
    return <String, Object?>{
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    };
  } on FormatException {
    throw WorkflowNodeExecutionException('工具 $toolName 的参数不是有效 JSON 对象。');
  }
}

String _boundedToolOutput(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return '工具未返回内容。';
  return clipTextByCodeUnits(
    normalized,
    _maxWorkflowToolOutputCharacters,
    suffix: '\n…（工具输出已截断）',
  );
}

class _WorkflowHttpResponse {
  const _WorkflowHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}

String _executionErrorText(Object? error) {
  if (error is WorkflowNodeExecutionException) return error.message;
  if (error is TimeoutException) return error.message ?? '请求超时。';
  final text = '$error'.trim();
  return text.isEmpty ? '未知错误。' : text;
}

Object? _literalValue(String value) {
  final normalized = value.trim();
  if ((normalized.startsWith('"') && normalized.endsWith('"')) ||
      (normalized.startsWith("'") && normalized.endsWith("'"))) {
    return normalized.substring(1, normalized.length - 1);
  }
  if (normalized == 'true') return true;
  if (normalized == 'false') return false;
  return num.tryParse(normalized) ?? normalized;
}

num _number(Object? value) {
  if (value is num) return value;
  return num.parse('$value'.trim());
}

List<Object?> _tryDecodeList(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is List ? decoded : const <Object?>[];
  } on FormatException {
    return const <Object?>[];
  }
}
