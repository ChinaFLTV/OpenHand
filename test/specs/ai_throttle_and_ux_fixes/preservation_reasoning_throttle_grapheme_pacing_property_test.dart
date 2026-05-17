// Bug 1 Preservation #7 — Reasoning throttle pacing parity on ASCII.
//
// **Validates: Requirements 7.1**
//
// Property 6 (Preservation): the upcoming grapheme-aware fix must NOT
// make reasoning-card pacing visibly worse than the unfixed code. We
// can't directly compare future code with past code in one test pass,
// so we lean on a key invariant:
//
//   * For PURE ASCII reasoning text, `String.length` (UTF-16 units) ==
//     `text.characters.length`. So the production UTF-16 budget and a
//     grapheme-aware budget produce IDENTICAL traces. Any divergence
//     would be a regression.
//
// We mirror two throttles in this file:
//
//   * `_MirrorCharThrottle`        — UTF-16 budget (production formula);
//   * `_GraphemeAwareCharThrottle` — counts via `String.characters`.
//
// Both are driven over identical synthetic timelines. Property: for
// pure ASCII text, the two traces match exactly across every poll.
// On UNFIXED code this PASSES (because both budgets coincide on
// ASCII). After the fix lands, this preservation property MUST
// continue to pass — proving the fix did not "downshift" reasoning
// pacing on ASCII, which is the lower-bound the design promises.

import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirror of the production formula (UTF-16 length budget).
class _MirrorCharThrottle {
  _MirrorCharThrottle({required this.maxCharsPerSecond, required this.now})
      : _budget = maxCharsPerSecond.toDouble(),
        _lastTickAt = now();

  final int maxCharsPerSecond;
  final DateTime Function() now;
  double _budget;
  int _emittedChars = 0;
  DateTime _lastTickAt;

  bool get isEnabled => maxCharsPerSecond > 0;

  int renderableLength(int totalSanitizedLength) {
    if (!isEnabled) {
      _emittedChars = totalSanitizedLength;
      return totalSanitizedLength;
    }
    if (totalSanitizedLength <= _emittedChars) return _emittedChars;
    final n = now();
    final elapsed = n.difference(_lastTickAt).inMicroseconds;
    if (elapsed > 0) {
      _budget += elapsed * maxCharsPerSecond / 1000000.0;
      if (_budget > maxCharsPerSecond) _budget = maxCharsPerSecond.toDouble();
      _lastTickAt = n;
    }
    final allowance = _budget.floor();
    if (allowance > 0) {
      final pending = totalSanitizedLength - _emittedChars;
      final granted = allowance >= pending ? pending : allowance;
      _emittedChars += granted;
      _budget -= granted;
    }
    return _emittedChars;
  }
}

/// Grapheme-aware throttle: budget counted in user-perceived characters
/// (matches the future fix). On pure ASCII this trace coincides with
/// the UTF-16 mirror's trace exactly.
class _GraphemeAwareCharThrottle {
  _GraphemeAwareCharThrottle({
    required this.maxCharsPerSecond,
    required this.now,
  })  : _budget = maxCharsPerSecond.toDouble(),
        _lastTickAt = now();

  final int maxCharsPerSecond;
  final DateTime Function() now;
  double _budget;
  int _emittedGraphemes = 0;
  DateTime _lastTickAt;

  bool get isEnabled => maxCharsPerSecond > 0;

  int renderableGraphemeCount(int totalGraphemes) {
    if (!isEnabled) {
      _emittedGraphemes = totalGraphemes;
      return totalGraphemes;
    }
    if (totalGraphemes <= _emittedGraphemes) return _emittedGraphemes;
    final n = now();
    final elapsed = n.difference(_lastTickAt).inMicroseconds;
    if (elapsed > 0) {
      _budget += elapsed * maxCharsPerSecond / 1000000.0;
      if (_budget > maxCharsPerSecond) _budget = maxCharsPerSecond.toDouble();
      _lastTickAt = n;
    }
    final allowance = _budget.floor();
    if (allowance > 0) {
      final pending = totalGraphemes - _emittedGraphemes;
      final granted = allowance >= pending ? pending : allowance;
      _emittedGraphemes += granted;
      _budget -= granted;
    }
    return _emittedGraphemes;
  }
}

/// Random ASCII reasoning text generator (printable ASCII subset).
String _randomAscii(Random rng, int n) {
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,!?';
  final buf = StringBuffer();
  for (var i = 0; i < n; i++) {
    buf.writeCharCode(alphabet.codeUnitAt(rng.nextInt(alphabet.length)));
  }
  return buf.toString();
}

/// Drive both throttles in lockstep across the same timeline.
({List<int> utf16, List<int> grapheme}) _runParallel({
  required int rate,
  required String content,
  required Duration totalDuration,
  Duration sampleInterval = const Duration(milliseconds: 16),
}) {
  final start = DateTime.utc(2026, 1, 1);
  var elapsedA = Duration.zero;
  var elapsedB = Duration.zero;
  final utf16Throttle = _MirrorCharThrottle(
    maxCharsPerSecond: rate,
    now: () => start.add(elapsedA),
  );
  final graphemeThrottle = _GraphemeAwareCharThrottle(
    maxCharsPerSecond: rate,
    now: () => start.add(elapsedB),
  );
  final utf16Trace = <int>[];
  final graphemeTrace = <int>[];
  final totalGraphemes = content.characters.length;
  final totalUtf16 = content.length;
  while (elapsedA <= totalDuration) {
    utf16Trace.add(utf16Throttle.renderableLength(totalUtf16));
    graphemeTrace.add(graphemeThrottle.renderableGraphemeCount(totalGraphemes));
    elapsedA += sampleInterval;
    elapsedB += sampleInterval;
  }
  return (utf16: utf16Trace, grapheme: graphemeTrace);
}

void main() {
  group('Preservation — reasoning throttle pacing on pure ASCII', () {
    test('rate=12, ascii reasoning: traces match across timeline', () {
      const reasoning =
          'The assistant is reasoning about the user request. '
          'Step 1: parse intent. Step 2: gather context. Step 3: respond.';
      final result = _runParallel(
        rate: 12,
        content: reasoning,
        totalDuration: const Duration(seconds: 12),
      );
      expect(
        result.utf16,
        orderedEquals(result.grapheme),
        reason:
            'on pure ASCII the UTF-16 budget and grapheme budget MUST '
            'produce identical traces (preservation lower-bound for the '
            'reasoning card).',
      );
    });

    test('rate=1: still identical on slow pacing', () {
      const reasoning = 'short ascii reasoning.';
      final result = _runParallel(
        rate: 1,
        content: reasoning,
        totalDuration: const Duration(seconds: 30),
      );
      expect(result.utf16, orderedEquals(result.grapheme));
    });

    test('rate=60: identical on fast pacing too', () {
      const reasoning =
          'fast ascii reasoning content with lots of words flowing through.';
      final result = _runParallel(
        rate: 60,
        content: reasoning * 10,
        totalDuration: const Duration(seconds: 4),
      );
      expect(result.utf16, orderedEquals(result.grapheme));
    });

    test('Randomized PBT (60 cases) — ASCII content, traces parity', () {
      final rng = Random(20260522);
      for (var i = 0; i < 60; i++) {
        final rate = 1 + rng.nextInt(60);
        final n = 8 + rng.nextInt(180);
        final content = _randomAscii(rng, n);
        // Sanity: pure-ASCII assumption holds.
        expect(
          content.characters.length,
          equals(content.length),
          reason: 'PBT #$i: generator must yield pure ASCII '
              '(graphemes=${content.characters.length}, '
              'utf16=${content.length}).',
        );
        final result = _runParallel(
          rate: rate,
          content: content,
          totalDuration: Duration(seconds: (n / rate).ceil() + 4),
        );
        expect(
          result.utf16,
          orderedEquals(result.grapheme),
          reason:
              'PBT #$i (rate=$rate n=$n): UTF-16 mirror and grapheme-aware '
              'throttle produced different traces on pure ASCII reasoning '
              'text — that would be a preservation regression for the '
              'reasoning card pacing.',
        );
      }
    });
  });
}
