import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/ai/model/ai_attachment.dart';
import 'package:openhand/features/ai/service/ai_attachment_service.dart';

void main() {
  test(
    'AiAttachmentService keeps total prompt text within the message budget',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_ai_attachment_service_budget_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final sourceDirectory = Directory('${tempDirectory.path}/source');
      await sourceDirectory.create(recursive: true);
      final filePaths = <String>[];
      for (var index = 0; index < aiMessageAttachmentLimit; index++) {
        final file = File('${sourceDirectory.path}/attachment_$index.txt');
        await file.writeAsString(
          'Attachment $index\n${'A' * 6000}',
          flush: true,
        );
        filePaths.add(file.path);
      }
      final service = AiAttachmentService(
        attachmentsDirectoryPath: '${tempDirectory.path}/attachments',
      );
      var nextAttachmentId = 0;

      final attachments = await service.importAttachments(
        sessionId: 'session-1',
        messageId: 'message-1',
        filePaths: filePaths,
        idGenerator: () => 'attachment-id-${nextAttachmentId++}',
      );

      final totalPromptCharacters = attachments.fold<int>(
        0,
        (sum, item) => sum + item.promptText.length,
      );
      expect(attachments, hasLength(aiMessageAttachmentLimit));
      expect(
        totalPromptCharacters,
        lessThanOrEqualTo(
          AiAttachmentService.maxAttachmentPromptCharactersPerMessage,
        ),
      );
    },
  );

  test(
    'attachment picker extensions stay aligned with supported text and spreadsheet formats',
    () {
      final extensions = aiAttachmentPickerExtensions();

      expect(
        extensions,
        containsAll(<String>['md', 'toml', 'dart', 'go', 'py', 'xlsx', 'pdf']),
      );
    },
  );

  test(
    'AiAttachmentService rolls back imported files when import fails',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_ai_attachment_service_rollback_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final sourceDirectory = Directory('${tempDirectory.path}/source');
      await sourceDirectory.create(recursive: true);
      final validFile = File('${sourceDirectory.path}/valid.txt');
      await validFile.writeAsString('valid', flush: true);
      final service = AiAttachmentService(
        attachmentsDirectoryPath: '${tempDirectory.path}/attachments',
      );

      await expectLater(
        () => service.importAttachments(
          sessionId: 'session-rollback',
          messageId: 'message-rollback',
          filePaths: <String>[
            validFile.path,
            '${sourceDirectory.path}/missing.txt',
          ],
          idGenerator: () => 'attachment-id',
        ),
        throwsA(isA<AiAttachmentException>()),
      );

      expect(
        Directory(
          '${tempDirectory.path}/attachments/session-rollback/message-rollback',
        ).existsSync(),
        isFalse,
      );
    },
  );
}
