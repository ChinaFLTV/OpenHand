import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

void main() {
  group('mcpStdoutDrainHasBudget', () {
    test('allows takes below max including empty-frame accounting', () {
      // Simulate empty frames consuming budget the same as real messages.
      var takes = 0;
      const maxTakes = 4;
      var emptyProcessed = 0;
      while (mcpStdoutDrainHasBudget(takes: takes, maxTakes: maxTakes)) {
        takes += 1;
        emptyProcessed += 1;
      }
      expect(takes, maxTakes);
      expect(emptyProcessed, maxTakes);
      expect(mcpStdoutDrainHasBudget(takes: takes, maxTakes: maxTakes), isFalse);
    });

    test('clamps non-positive maxTakes to 1', () {
      expect(mcpStdoutDrainHasBudget(takes: 0, maxTakes: 0), isTrue);
      expect(mcpStdoutDrainHasBudget(takes: 1, maxTakes: 0), isFalse);
      expect(mcpStdoutDrainHasBudget(takes: 0, maxTakes: -5), isTrue);
      expect(mcpStdoutDrainHasBudget(takes: 1, maxTakes: -5), isFalse);
    });
  });
}
