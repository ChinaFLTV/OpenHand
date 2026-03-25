import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/model/ai_attachment.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session.dart';
import 'package:openhand/features/ai/model/ai_session_message.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/model/ai_thread_template.dart';
import 'package:openhand/features/ai/service/ai_prompt_builder.dart';
import 'package:openhand/features/ai/service/ai_prompt_template_repository.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';

void main() {
  test(
    'AiPromptBuilder falls back to text-only image context when the local attachment file is missing',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand-ai-prompt-builder-',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final missingImagePath = '${tempDirectory.path}/missing-image.png';
      final attachment = AiMessageAttachment(
        id: 'attachment-1',
        name: 'missing-image.png',
        storagePath: missingImagePath,
        kind: AiAttachmentKind.image,
        mimeType: 'image/png',
        sizeBytes: 128,
        promptText: 'Image attachment: missing-image.png (128 B, 4x3).',
        summaryText: 'Image attachment: missing-image.png (128 B, 4x3).',
        width: 4,
        height: 3,
      );
      final userMessage =
          AiSessionMessage.user(
            id: 'user-1',
            content: 'Describe the attachment.',
            createdAt: DateTime.utc(2026, 3, 25, 12),
            metadata: <String, Object?>{
              aiSessionMessageAttachmentsMetadataKey: <Map<String, Object?>>[
                attachment.toJson(),
              ],
            },
          ).copyWith(
            characterCount:
                AiSessionMessage.countCharacters('Describe the attachment.') +
                attachment.promptText.length,
          );
      final session = AiSession(
        id: 'session-1',
        title: 'Attachment Session',
        templateId: 'default',
        templateName: 'Default Assistant',
        templateIconName: 'auto_awesome_rounded',
        templateInternalVersion: '1.0.0',
        createdAt: DateTime.utc(2026, 3, 25, 12),
        updatedAt: DateTime.utc(2026, 3, 25, 12),
        messages: <AiSessionMessage>[userMessage],
        environment: const AiSessionEnvironment(
          localeTag: 'en',
          platform: 'macos',
          appVersion: '1.0.0',
          appBuildNumber: '1',
          applicationDirectory: '/tmp/openhand',
          homeDirectory: '/tmp',
          settingsFilePath: '/tmp/settings.toml',
          skillsStoragePath: '/tmp/skills',
          mcpServersFilePath: '/tmp/mcp.json',
          userMemoryFilePath: '/tmp/memory.json',
          sessionsDirectoryPath: '/tmp/sessions',
          compressionThresholdChars: 5000,
        ),
        statistics: const AiSessionStatistics.initial(),
        recentErrors: const <AiSessionErrorRecord>[],
      );
      const template = AiThreadTemplate(
        id: 'default',
        name: 'Default Assistant',
        iconName: 'auto_awesome_rounded',
        description: 'Default template.',
        internalVersion: '1.0.0',
        promptAssetDirectory: 'assets/prompts/default',
      );
      const bundle = AiPromptTemplateBundle(
        template: template,
        systemInstructions: 'System',
        developerInstructions: 'Developer',
        compressionSummaryInstructions: 'Compress',
      );
      const runtimeContext = AiSessionRuntimeContext(
        localeTag: 'en',
        appVersion: '1.0.0',
        appBuildNumber: '1',
        settingsFilePath: '/tmp/settings.toml',
        skillsStoragePath: '/tmp/skills',
        mcpServersFilePath: '/tmp/mcp.json',
        userMemoryFilePath: '/tmp/memory.json',
        compressionThresholdChars: 5000,
        memoryEnabled: false,
        memoryEntries: <Never>[],
        platformName: 'macOS',
        workingDirectory: '/tmp/openhand',
        todayLocalDate: '2026-03-25',
        timeZoneName: 'Asia/Shanghai',
      );
      const model = AiModelConfig(
        id: 'model-image',
        baseUrl: 'https://api.example.com',
        authScheme: AiAuthScheme.none,
        token: '',
        modelId: 'gpt-4o-mini',
        protocolType: AiProtocolType.openai,
      );

      final prompt = const AiPromptBuilder().buildSessionPrompt(
        templateBundle: bundle,
        session: session,
        model: model,
        runtimeContext: runtimeContext,
        memoryEntries: const <Never>[],
        sessionMessages: session.messages,
        latestUserMessageId: userMessage.id,
      );
      final body = await AiProtocolRegistry.adapterFor(
        model.protocolType,
      ).buildBody(model, prompt.messages);

      final messages = body['messages'] as List<dynamic>;
      final lastMessage = messages.last as Map<String, Object?>;

      expect(lastMessage['role'], 'user');
      expect('${lastMessage['content']}', contains('Describe the attachment.'));
      expect(
        '${lastMessage['content']}',
        contains('Image attachment: missing-image.png (128 B, 4x3).'),
      );
      expect('${lastMessage['content']}', isNot(contains('data:image/png')));
    },
  );
}
