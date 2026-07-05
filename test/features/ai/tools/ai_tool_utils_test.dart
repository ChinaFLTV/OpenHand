import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/tools/ai_tool_utils.dart';

void main() {
  group('AiToolUtils.readClampedInt', () {
    test('normalizes tool integer arguments with shared integral bounds', () {
      expect(
        AiToolUtils.readClampedInt('7.0', fallback: 3, min: 0, max: 10),
        7,
      );
      expect(AiToolUtils.readClampedInt(12, fallback: 3, min: 0, max: 10), 10);
      expect(AiToolUtils.readClampedInt(-2, fallback: 3, min: 10, max: 0), 0);
    });

    test('falls back for fractional and invalid values', () {
      expect(AiToolUtils.readClampedInt(7.5, fallback: 4, min: 0, max: 10), 4);
      expect(
        AiToolUtils.readClampedInt('bad', fallback: 12, min: 0, max: 10),
        10,
      );
    });
  });
}
