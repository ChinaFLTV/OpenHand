import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_attachment.dart';
import 'package:openhand/features/ai/model/ai_attachment_context.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/fs/ai_attachment_service.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/prompt/ai_prompt_template_repository.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('openhand-attachments-');
  });
  tearDown(() async => directory.delete(recursive: true));

  AiMessageAttachment attachment(String id, AiAttachmentKind kind) =>
      AiMessageAttachment(
        id: id,
        name: '同名资源',
        storagePath: '${directory.path}/session/attachments/$id',
        kind: kind,
        mimeType: switch (kind) {
          AiAttachmentKind.image => 'image/png',
          AiAttachmentKind.audio => 'audio/wav',
          _ => 'text/plain',
        },
        sizeBytes: 4,
        promptText: '附件正文$id',
      );
  AiSessionMessage message(
    String id,
    List<AiMessageAttachment> attachments, {
    List<AiMessageAttachment>? snapshot,
  }) => AiSessionMessage.user(
    id: id,
    content: '消息$id',
    createdAt: DateTime.utc(2026),
    metadata: {
      aiSessionMessageAttachmentsMetadataKey:
          AiMessageAttachment.listToMetadata(attachments),
      if (snapshot != null)
        aiHistoricalAttachmentsMetadataKey: AiMessageAttachment.listToMetadata(
          snapshot,
        ),
    },
  );

  test('历史图片与资源各保留最近五个，最新二十个附件独立保留', () {
    final history = [
      for (var i = 0; i < 8; i++)
        message('m$i', [
          attachment('image$i', AiAttachmentKind.image),
          attachment('audio$i', AiAttachmentKind.audio),
        ]),
    ];
    final latest = message('latest', [
      for (var i = 0; i < 20; i++)
        attachment('current$i', AiAttachmentKind.image),
    ]);
    final selected = selectAiSessionAttachments([...history, latest], latest);
    expect(selected['latest'], hasLength(20));
    final old = selected.values
        .expand((a) => a)
        .where((a) => a.isHistorical)
        .toList();
    expect(old, hasLength(10));
    expect(old.map((a) => a.attachment.id), [
      for (var i = 3; i < 8; i++) ...['image$i', 'audio$i'],
    ]);
    expect(old.first.label, contains('历史附件'));
    expect(old.first.label, contains('m3'));
    expect(selected['latest']!.first.label, contains('当前附件'));
  });

  test('普通文件与语音共用资源配额，删除和重复资源不占位', () {
    final duplicate = attachment('duplicate', AiAttachmentKind.audio);
    final history = [
      for (var i = 0; i < 7; i++)
        message('m$i', [
          attachment(
            'file$i',
            i.isEven ? AiAttachmentKind.text : AiAttachmentKind.audio,
          ),
        ]),
      message('deleted', [
        attachment('deleted', AiAttachmentKind.text),
      ]).copyWith(isDeleted: true),
      message('old-copy', [duplicate]),
    ];
    final latest = message('latest', [duplicate]);
    final selected = selectAiSessionAttachments(
      history,
      latest,
    ).values.expand((a) => a).toList();
    expect(selected.where((a) => a.isHistorical).map((a) => a.attachment.id), [
      'file2',
      'file3',
      'file4',
      'file5',
      'file6',
    ]);
    expect(selected.where((a) => a.attachment.id == 'duplicate'), hasLength(1));
  });

  test('网关历史快照为空时，不从旧会话复活已排除的附件', () {
    final old = message('old', [
      attachment('recalled', AiAttachmentKind.audio),
    ]);
    final latest = message('latest', [], snapshot: []);
    expect(
      selectAiSessionAttachments([old], latest).values.expand((a) => a),
      isEmpty,
    );
  });

  test('网关导入二十个当前附件和十个历史附件，保留原名与消息来源', () async {
    final service = AiAttachmentService(
      attachmentsDirectoryPath: '${directory.path}/legacy',
      perSessionAttachmentsDirectoryPath: (id) =>
          '${directory.path}/$id/attachments',
    );
    final file = await File(
      '${directory.path}/cache.txt',
    ).writeAsString('资源内容');
    var counter = 0;
    final imported = await service.importContextAttachments(
      sessionId: 'session',
      messageId: 'turn',
      idGenerator: () => 'a${counter++}',
      context: AiAttachmentContextInput(
        current: [
          for (var i = 0; i < 20; i++)
            AiAttachmentSource(
              path: file.path,
              name: '当前$i.txt',
              messageId: 'current',
            ),
        ],
        history: [
          for (var i = 0; i < 10; i++)
            AiAttachmentSource(
              path: file.path,
              name: '历史$i.txt',
              messageId: 'old$i',
            ),
        ],
      ),
    );
    expect(imported.current, hasLength(20));
    expect(imported.history, hasLength(10));
    expect(imported.history.last.name, '历史9.txt');
    expect(imported.history.last.sourceMessageId, 'old9');
    expect(imported.history.last.originalSourcePath, file.path);
    expect(
      await File(imported.history.last.storagePath).readAsString(),
      '资源内容',
    );
  });

  test('历史资源复用已导入文件，丢失缓存重新导入', () async {
    final service = AiAttachmentService(
      attachmentsDirectoryPath: '${directory.path}/legacy',
      perSessionAttachmentsDirectoryPath: (id) =>
          '${directory.path}/$id/attachments',
    );
    final file = await File(
      '${directory.path}/cache.txt',
    ).writeAsString('文件正文');
    final source = AiAttachmentSource(
      path: file.path,
      name: '原始文件.txt',
      messageId: 'source',
    );
    var counter = 0;
    final first = await service.importContextAttachments(
      sessionId: 'session',
      messageId: 'first',
      context: AiAttachmentContextInput(current: [source], history: []),
      idGenerator: () => 'a${counter++}',
    );
    final second = await service.importContextAttachments(
      sessionId: 'session',
      messageId: 'second',
      context: AiAttachmentContextInput(current: [], history: [source]),
      idGenerator: () => 'a${counter++}',
      reusableAttachments: first.current,
    );
    expect(counter, 1);
    expect(second.history.single.storagePath, first.current.single.storagePath);
    expect(second.history.single.promptText, contains('原始文件.txt'));
    await File(first.current.single.storagePath).delete();
    final third = await service.importContextAttachments(
      sessionId: 'session',
      messageId: 'third',
      context: AiAttachmentContextInput(current: [], history: [source]),
      idGenerator: () => 'a${counter++}',
      reusableAttachments: first.current,
    );
    expect(counter, 2);
    expect(await File(third.history.single.storagePath).readAsString(), '文件正文');
  });

  test('历史附件导入失败时回滚本轮已创建的文件', () async {
    final service = AiAttachmentService(
      attachmentsDirectoryPath: '${directory.path}/legacy',
      perSessionAttachmentsDirectoryPath: (id) =>
          '${directory.path}/$id/attachments',
    );
    final file = await File('${directory.path}/exists.txt').writeAsString('内容');
    await expectLater(
      service.importContextAttachments(
        sessionId: 'session',
        messageId: 'turn',
        idGenerator: () => 'a',
        context: AiAttachmentContextInput(
          current: [
            AiAttachmentSource(
              path: file.path,
              name: '当前',
              messageId: 'current',
            ),
          ],
          history: [
            AiAttachmentSource(
              path: '${directory.path}/missing',
              name: '丢失',
              messageId: 'old',
            ),
          ],
        ),
      ),
      throwsA(isA<AiAttachmentException>()),
    );
    expect(
      await Directory('${directory.path}/session/attachments').exists(),
      isFalse,
    );
  });

  test('实际提示词携带历史图像与音频，续写不改变附件选择，失效文件不内联', () async {
    final history = [
      for (var i = 0; i < 7; i++)
        message('m$i', [
          attachment('image$i', AiAttachmentKind.image),
          attachment('audio$i', AiAttachmentKind.audio),
        ]),
    ];
    final latest = message('latest', [
      attachment('current', AiAttachmentKind.image),
      attachment('missing', AiAttachmentKind.audio),
    ]);
    for (final m in [...history, latest]) {
      for (final a in AiMessageAttachment.listFromMetadata(
        m.metadata[aiSessionMessageAttachmentsMetadataKey],
      )) {
        if (a.id == 'missing') continue;
        await File(a.storagePath).create(recursive: true);
      }
    }
    final session = AiSession.fromJson({
      'session': {'id': 'session', 'template_id': 'default'},
      'messages': [],
      'environment': {'sessions_directory_path': directory.path},
      'statistics': {},
    });
    final repository = AiPromptTemplateRepository(loader: (_) async => '');
    final bundle = await repository.loadBundle('default');
    final runtime = AiSessionRuntimeContext(
      localeTag: 'zh-CN',
      appVersion: '1',
      appBuildNumber: '1',
      settingsFilePath: '',
      skillsStoragePath: '',
      mcpServersFilePath: '',
      userMemoryFilePath: '',
      compressionThresholdChars: 1000000,
      memoryEnabled: false,
      memoryEntries: [],
    );
    final model = AiModelConfig.fromJson({
      'model_id': 'gpt-4o',
      'model_profiles': {
        'gpt-4o': {
          'supports_attachments': true,
          'is_multimodal': true,
          'supported_modalities': ['image', 'audio'],
        },
      },
    });
    Future<AiPromptBuildResult> build(
      List<AiSessionMessage> messages, {
      AiSession? fullSession,
      AiModelConfig? selectedModel,
    }) => const AiPromptBuilder().buildSessionPrompt(
      templateBundle: bundle,
      session: fullSession ?? session,
      model: selectedModel ?? model,
      runtimeContext: runtime,
      memoryEntries: [],
      sessionMessages: messages,
      latestUserMessageId: latest.id,
    );
    final first = await build([...history, latest]);
    final continued = await build([
      ...history,
      latest,
      AiSessionMessage.assistant(
        id: 'reply',
        content: '继续分析',
        createdAt: DateTime.utc(2026),
      ),
    ]);
    List<AiChatContentPart> media(AiPromptBuildResult result) => result.messages
        .expand((turn) => turn.effectiveParts)
        .where((p) => p.kind != AiChatContentPartKind.text)
        .toList();
    expect(
      media(first).where((p) => p.kind == AiChatContentPartKind.imageFile),
      hasLength(6),
    );
    expect(
      media(first).where((p) => p.kind == AiChatContentPartKind.audioFile),
      hasLength(5),
    );
    expect(
      media(continued).map((p) => p.filePath),
      media(first).map((p) => p.filePath),
    );
    final text = first.messages
        .expand((t) => t.effectiveParts)
        .map((p) => p.text)
        .join('\n');
    expect(text, contains('missing'));
    expect(text, contains('unavailable'));
    expect(text, isNot(contains('附件正文image0')));
    final compressed = session.copyWith(
      messages: [
        ...history,
        AiSessionMessage.compressionPoint(
          id: 'compact',
          content: '历史摘要',
          createdAt: DateTime.utc(2026),
          metadata: {},
        ),
        latest,
      ],
    );
    final afterCompression = await build([latest], fullSession: compressed);
    expect(
      media(afterCompression).map((p) => p.filePath),
      unorderedEquals(media(first).map((p) => p.filePath)),
    );
    final textOnly = AiModelConfig.fromJson({
      'model_id': 'text-only',
      'model_profiles': {
        'text-only': {'supports_attachments': false, 'is_multimodal': false},
      },
    });
    final unsupported = await build([
      ...history,
      latest,
    ], selectedModel: textOnly);
    expect(media(unsupported), isEmpty);
    expect(
      unsupported.messages
          .expand((t) => t.effectiveParts)
          .map((p) => p.text)
          .join(),
      contains('audio6'),
    );
  });
}
