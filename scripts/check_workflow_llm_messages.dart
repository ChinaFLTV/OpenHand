import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final executor = File(
    '${root.path}/lib/features/workflows/service/workflow_node_executor.dart',
  );
  final source = (await executor.readAsString()).replaceAllMapped(
    RegExp("import '([^']+)'"),
    (match) {
      final uri = Uri.parse(match[1]!);
      final resolved = uri.hasScheme
          ? uri.toString()
          : executor.uri.resolveUri(uri).toString();
      return "import '${resolved.replaceFirst('${root.uri}lib/', 'package:openhand/')}'";
    },
  );
  await runFlutterWidgetCheck(
    root: root,
    name: 'workflow_llm_messages',
    source:
        "import 'package:flutter_test/flutter_test.dart';\n"
        "import 'package:openhand/features/ai/service/operations/ai_responses_service.dart';\n"
        "import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';\n"
        "import 'package:openhand/features/ai/model/ai_model_config.dart';\n"
        "import 'package:http/testing.dart';\n"
        "import 'package:http/http.dart' as http;\n$source\n$_checks",
  );
}

const _checks = '''
void main() {
  Map<String, Object?> message(String text, [String? phase]) => {
    'type': 'message', 'role': 'assistant', if (phase != null) 'phase': phase,
    'content': [{'type': 'output_text', 'text': text}],
  };
  test('过程响应与正式输出分离，保留多个过程卡片及思考消息', () async {
    final payload = {
      'status': 'completed',
      'output_text': '正在定位数据\\n正在读取文件\\n{"结论":"完成"}',
      'output': [
        {'type': 'reasoning', 'summary': [{'type': 'summary_text', 'text': '推理内容'}]},
        message('正在定位数据', 'commentary'),
        message('正在读取文件', 'commentary'),
        message('{"结论":"完成"}', 'final_answer'),
      ],
    };
    final service = AiResponsesService(client: MockClient((_) async => http.Response(jsonEncode(payload), 200, headers: {'content-type': 'application/json; charset=utf-8'})));
    addTearDown(service.dispose);
    final result = await service.createResponseFromRequest(request: const AiResponsesRequestBlueprint(
      url: 'https://example.invalid/responses', method: 'POST', headers: {}, body: {},
    ));
    expect(result.text, '{"结论":"完成"}');
    expect(result.processMessages, ['正在定位数据', '正在读取文件']);
    final chatClient = MockClient((_) async => http.Response(jsonEncode(payload), 200,
      headers: {'content-type': 'application/json; charset=utf-8'}));
    final chat = AiChatService(client: chatClient);
    addTearDown(chat.dispose);
    addTearDown(chatClient.close);
    final completion = await chat.sendMessage(
      model: const AiModelConfig(id: '测试模型', baseUrl: 'https://example.invalid/v1',
        authScheme: AiAuthScheme.bearer, token: '测试凭据', modelId: '测试模型',
        protocolType: AiProtocolType.openai),
      messages: const [AiChatTurn(role: AiChatRole.user, content: '测试')],
    );
    expect(completion.processMessages, result.processMessages);
    expect(completion.reply, result.text);
    final executor = WorkflowNodeExecutor();
    addTearDown(executor.dispose);
    final messages = <WorkflowLlmConversationMessage>[];
    executor._appendLlmCompletionMessages(messages, completion, WorkflowLlmReasoningFormat.separated);
    expect(messages.map((message) => message.kind), [WorkflowLlmMessageKind.reasoning,
      WorkflowLlmMessageKind.process, WorkflowLlmMessageKind.process, WorkflowLlmMessageKind.assistant]);
    expect(messages.last.content, '{"结论":"完成"}');
    expect(messages.map((message) => message.id).toSet().length, messages.length);
  });

  test('缺少正式响应时不回填过程文字，无阶段协议保持兼容', () async {
    final service = AiResponsesService();
    addTearDown(service.dispose);
    final processOnly = await service.parseResponsePayload({
      'output_text': '准备执行', 'output': [message('准备执行', 'commentary')],
    });
    expect(processOnly.text, isEmpty);
    expect(processOnly.processMessages, ['准备执行']);
    final legacy = await service.parseResponsePayload({'output': [message('我先说明步骤，然后给出答案。')]});
    expect(legacy.text, '我先说明步骤，然后给出答案。');
    expect(legacy.processMessages, isEmpty);
    final direct = await service.parseResponsePayload({'output_text': '普通正文'});
    expect(direct.text, '普通正文');
  });

  test('工具调用轮次的正文属于过程响应，最终轮次仍为助手回复', () {
    final executor = WorkflowNodeExecutor();
    addTearDown(executor.dispose);
    final messages = <WorkflowLlmConversationMessage>[];
    executor._appendLlmCompletionMessages(messages, const AiChatCompletion(
      reply: '读取数据中', toolCalls: [AiToolCall(id: '调用', name: 'read', arguments: '{}')],
    ), WorkflowLlmReasoningFormat.separated);
    executor._appendLlmCompletionMessages(messages, const AiChatCompletion(reply: '最终答案'),
      WorkflowLlmReasoningFormat.separated);
    expect(messages.map((message) => message.kind), [WorkflowLlmMessageKind.process,
      WorkflowLlmMessageKind.toolCall, WorkflowLlmMessageKind.assistant]);
  });
}
''';
