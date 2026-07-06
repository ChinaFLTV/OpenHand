import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  group('AiOneMillionContextPolicy', () {
    test('normalizes model ID suffix once', () {
      expect(
        AiOneMillionContextPolicy.normalizeModelId(' gpt-5.4 '),
        'gpt-5.4[1M]',
      );
      expect(
        AiOneMillionContextPolicy.normalizeModelId('gpt-5.4[1M][1m]'),
        'gpt-5.4[1M]',
      );
    });

    test('restores model ID by snapshot or by stripping current suffix', () {
      expect(
        AiOneMillionContextPolicy.restoreModelId(
          currentModelId: 'gpt-5.4[1M]',
          snapshotModelId: 'gpt-5.4',
        ),
        'gpt-5.4',
      );
      expect(
        AiOneMillionContextPolicy.restoreModelId(
          currentModelId: 'custom-model[1M]',
          snapshotModelId: 'gpt-5.4',
        ),
        'custom-model',
      );
    });

    test('restores context length without leaving the 1M lock behind', () {
      expect(
        AiOneMillionContextPolicy.restoreContextLength(
          currentMaxContextLength: '1000000',
          snapshotMaxContextLength: '400000',
          fallbackMaxContextLength: '128000',
        ),
        '400000',
      );
      expect(
        AiOneMillionContextPolicy.restoreContextLength(
          currentMaxContextLength: '1000000',
          fallbackMaxContextLength: '128000',
        ),
        '128000',
      );
      expect(
        AiOneMillionContextPolicy.restoreContextLength(
          currentMaxContextLength: '64000',
          snapshotMaxContextLength: '400000',
          fallbackMaxContextLength: '128000',
        ),
        '64000',
      );
    });

    test('copy keeps the policy suffix at the end only', () {
      expect(
        AiOneMillionContextPolicy.copyModelId('gpt-5.4[1M]', 2),
        'gpt-5.4-Copy-2[1M]',
      );
      expect(
        AiOneMillionContextPolicy.copyModelId('gpt-5.4', 2),
        'gpt-5.4-Copy-2',
      );
    });
  });
}
