import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/tools/ai_tool_utils.dart';

void main() {
  test('tool integer parsing accepts finite integral values only', () {
    expect(AiToolUtils.readInt(12), 12);
    expect(AiToolUtils.readInt(12.0), 12);
    expect(AiToolUtils.readInt('12'), 12);
    expect(AiToolUtils.readInt('12.0'), 12);
    expect(AiToolUtils.readInt(12.5), isNull);
    expect(AiToolUtils.readInt('12.5'), isNull);
    expect(AiToolUtils.readInt(double.infinity), isNull);
    expect(AiToolUtils.readInt(double.nan), isNull);
    expect(AiToolUtils.readInt('bad'), isNull);
  });

  test('tool integer parsing clamps valid values and safe fallback', () {
    expect(AiToolUtils.readClampedInt('12', fallback: 6, min: 1, max: 20), 12);
    expect(AiToolUtils.readClampedInt(99, fallback: 6, min: 1, max: 20), 20);
    expect(AiToolUtils.readClampedInt(-5, fallback: 6, min: 1, max: 20), 1);
    expect(
      AiToolUtils.readClampedInt('bad', fallback: 99, min: 1, max: 20),
      20,
    );
    expect(AiToolUtils.readClampedInt('12', fallback: 6, min: 20, max: 1), 12);
  });
}
