import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';

import '../../support/test_directory.dart';

void main() {
  late Directory temporaryDirectory;

  AiModelConfig model(String modelId) {
    return AiModelConfig(
      id: 'mimo-test',
      baseUrl: 'https://example.com',
      authScheme: AiAuthScheme.none,
      token: '',
      modelId: modelId,
      protocolType: AiProtocolType.mimo,
      modelProfiles: <String, AiModelProfile>{
        modelId: const AiModelProfile(supportsAttachments: true),
      },
    );
  }

  AiChatTurn imageTurn(String path) {
    return AiChatTurn(
      role: AiChatRole.user,
      content: '',
      parts: <AiChatContentPart>[
        AiChatContentPart.imageFile(filePath: path, mimeType: 'image/png'),
      ],
    );
  }

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-mimo-validation-',
    );
  });

  tearDown(() => deleteTestDirectory(temporaryDirectory));

  test('accepts a regular non-empty Responses image', () async {
    final image = File('${temporaryDirectory.path}/image.png');
    await image.writeAsBytes(<int>[1, 2, 3]);

    await expectLater(
      validateMimoContentParts(model('mimo-v2.5'), <AiChatTurn>[
        imageTurn(image.path),
      ], surface: AiMimoMediaSurface.responses),
      completes,
    );
  });

  test('rejects an empty Responses image', () async {
    final image = File('${temporaryDirectory.path}/empty.png');
    await image.create();

    await expectLater(
      validateMimoContentParts(model('mimo-v2.5'), <AiChatTurn>[
        imageTurn(image.path),
      ], surface: AiMimoMediaSurface.responses),
      throwsA(
        isA<ArgumentError>().having(
          (error) => '${error.message}',
          'message',
          contains('cannot be empty'),
        ),
      ),
    );
  });

  test('Anthropic surface rejects ASR audio input', () async {
    final audio = File('${temporaryDirectory.path}/speech.mp3');
    await audio.writeAsBytes(<int>[1]);
    final turn = AiChatTurn(
      role: AiChatRole.user,
      content: '',
      parts: <AiChatContentPart>[
        AiChatContentPart.audioFile(
          filePath: audio.path,
          mimeType: 'audio/mpeg',
        ),
      ],
    );

    await expectLater(
      validateMimoContentParts(model('mimo-v2.5-asr'), <AiChatTurn>[
        turn,
      ], surface: AiMimoMediaSurface.anthropic),
      throwsA(
        isA<ArgumentError>().having(
          (error) => '${error.message}',
          'message',
          contains('only supports JPEG'),
        ),
      ),
    );
  });

  test('Responses images use the image limit for an ASR model id', () async {
    final image = File('${temporaryDirectory.path}/asr-image.png');
    final output = await image.open(mode: FileMode.write);
    try {
      await output.truncate(8 * 1024 * 1024);
    } finally {
      await output.close();
    }

    await expectLater(
      validateMimoContentParts(model('mimo-v2.5-asr'), <AiChatTurn>[
        imageTurn(image.path),
      ], surface: AiMimoMediaSurface.responses),
      completes,
    );
  });

  test('rejects a symbolic-link media input', () async {
    final target = File('${temporaryDirectory.path}/target.png');
    await target.writeAsBytes(<int>[1]);
    final link = Link('${temporaryDirectory.path}/linked.png');
    await link.create(target.path);

    await expectLater(
      validateMimoContentParts(model('mimo-v2.5'), <AiChatTurn>[
        imageTurn(link.path),
      ]),
      throwsA(
        isA<ArgumentError>().having(
          (error) => '${error.message}',
          'message',
          contains('regular file'),
        ),
      ),
    );
  });

  test(
    'rejects media whose Base64 payload exceeds the provider limit',
    () async {
      final image = File('${temporaryDirectory.path}/oversized.png');
      final output = await image.open(mode: FileMode.write);
      try {
        await output.truncate(aiMimoUnderstandingMaxRawBytes + 1);
      } finally {
        await output.close();
      }

      await expectLater(
        validateMimoContentParts(model('mimo-v2.5'), <AiChatTurn>[
          imageTurn(image.path),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '${error.message}',
            'message',
            contains('exceeds 50 MB'),
          ),
        ),
      );
    },
  );
}
