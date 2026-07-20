import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_attachment.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String attachmentPath;
  late List<AiSessionMessage> messages;
  late AiSession session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('openhand_prompt_test_');
    attachmentPath = p.join(root.path, _sessionId, 'attachments', 'ticket.jpg');
    await Directory(p.dirname(attachmentPath)).create(recursive: true);
    await File(
      attachmentPath,
    ).writeAsBytes(const <int>[0xff, 0xd8, 0xff, 0xd9]);
    messages = _conversationMessages(attachmentPath: attachmentPath);
    session = _session(sessionsDirectoryPath: root.path, messages: messages);
  });

  tearDown(() => root.delete(recursive: true));

  test('工具续写轮继续内联本轮图片附件', () async {
    final result = await const AiPromptBuilder().buildSessionPrompt(
      templateBundle: _templateBundle,
      session: session,
      model: _model,
      runtimeContext: _runtimeContext,
      memoryEntries: const [],
      sessionMessages: messages,
      latestUserMessageId: _userMessageId,
      runtimeContextAnchorMessageId: 'tool-result-id',
    );

    final imageParts = result.messages
        .expand((turn) => turn.parts)
        .where((part) => part.kind == AiChatContentPartKind.imageFile)
        .toList(growable: false);
    expect(imageParts, hasLength(1));
    expect(imageParts.single.filePath, attachmentPath);
  });

  test('已结束的历史轮次仅保留图片占位信息', () async {
    final result = await const AiPromptBuilder().buildSessionPrompt(
      templateBundle: _templateBundle,
      session: session,
      model: _model,
      runtimeContext: _runtimeContext,
      memoryEntries: const [],
      sessionMessages: messages,
      runtimeContextAnchorMessageId: 'tool-result-id',
    );

    expect(
      result.messages.expand((turn) => turn.parts),
      isNot(
        contains(
          predicate<AiChatContentPart>(
            (part) => part.kind == AiChatContentPartKind.imageFile,
          ),
        ),
      ),
    );
    expect(
      result.messages
          .expand((turn) => turn.effectiveParts)
          .map((part) => part.text ?? '')
          .join('\n'),
      contains('[图片附件；图片元数据：{id=attachment-id'),
    );
  });
}

const _sessionId = 'session-id';
const _userMessageId = 'user-id';

const _templateBundle = AiPromptTemplateBundle(
  template: AiThreadTemplate(
    id: 'default',
    name: '默认助手',
    iconName: AiThreadTemplateIcons.forumRounded,
    description: '',
    internalVersion: '1',
    promptAssetDirectory: '',
  ),
  systemInstructions: '系统指令',
  developerInstructions: '开发者指令',
  compressionSummaryInstructions: '压缩指令',
);

const _model = AiModelConfig(
  id: 'model-id',
  baseUrl: 'https://example.com',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'vision-model',
  protocolType: AiProtocolType.openai,
  modelProfiles: <String, AiModelProfile>{
    'vision-model': AiModelProfile(
      isMultimodal: true,
      supportedModalities: <AiModelModality>{AiModelModality.image},
      supportsAttachments: true,
    ),
  },
);

final _runtimeContext = AiSessionRuntimeContext(
  localeTag: 'zh-CN',
  appVersion: '1.0.0',
  appBuildNumber: '1',
  settingsFilePath: '',
  skillsStoragePath: '',
  mcpServersFilePath: '',
  userMemoryFilePath: '',
  compressionThresholdChars: 100000,
  memoryEnabled: false,
  memoryEntries: const [],
);

List<AiSessionMessage> _conversationMessages({required String attachmentPath}) {
  final createdAt = DateTime.utc(2026, 7, 20);
  final attachment = AiMessageAttachment(
    id: 'attachment-id',
    name: 'ticket.jpg',
    storagePath: attachmentPath,
    kind: AiAttachmentKind.image,
    mimeType: 'image/jpeg',
    sizeBytes: 4,
    promptText: 'Image attachment: ticket.jpg.',
  );
  return <AiSessionMessage>[
    AiSessionMessage.user(
      id: _userMessageId,
      content: '请分析图片',
      createdAt: createdAt,
      metadata: <String, Object?>{
        aiSessionMessageAttachmentsMetadataKey:
            AiMessageAttachment.listToMetadata(<AiMessageAttachment>[
              attachment,
            ]),
      },
    ),
    AiSessionMessage.assistant(
      id: 'assistant-id',
      content: '先查询资料。',
      createdAt: createdAt.add(const Duration(seconds: 1)),
    ),
    AiSessionMessage.toolCall(
      id: 'tool-call-message-id',
      content: 'Tool call: WebSearch',
      createdAt: createdAt.add(const Duration(seconds: 2)),
      metadata: const <String, Object?>{
        'tool_call_id': 'tool-call-id',
        'tool_name': 'WebSearch',
        'tool_arguments': '{}',
        'tool_calls': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'tool-call-id',
            'name': 'WebSearch',
            'arguments': '{}',
          },
        ],
      },
    ),
    AiSessionMessage.toolResult(
      id: 'tool-result-id',
      content: '查询完成。',
      createdAt: createdAt.add(const Duration(seconds: 3)),
      metadata: const <String, Object?>{
        'tool_call_id': 'tool-call-id',
        'tool_name': 'WebSearch',
        'status': 'success',
      },
    ),
  ];
}

AiSession _session({
  required String sessionsDirectoryPath,
  required List<AiSessionMessage> messages,
}) {
  final createdAt = DateTime.utc(2026, 7, 20);
  return AiSession(
    id: _sessionId,
    title: '测试会话',
    templateId: 'default',
    templateName: '默认助手',
    templateIconName: AiThreadTemplateIcons.forumRounded,
    templateInternalVersion: '1',
    createdAt: createdAt,
    updatedAt: createdAt,
    messages: messages,
    environment: AiSessionEnvironment(
      localeTag: 'zh-CN',
      platform: 'macos',
      appVersion: '1.0.0',
      appBuildNumber: '1',
      applicationDirectory: '',
      homeDirectory: '',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      sessionsDirectoryPath: sessionsDirectoryPath,
      compressionThresholdChars: 100000,
    ),
    statistics: const AiSessionStatistics.initial(),
    recentErrors: const [],
  );
}
