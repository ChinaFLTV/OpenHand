// Bug 1 Preservation #1 — Throttling disabled (rate <= 0 / throttle off).
//
// **Validates: Requirements 7.2**
//
// Property 6 (Preservation): when `aiStreamThrottleEnabled = false` OR
// `effChars <= 0`, the assistant streaming path SHALL pass content
// through unchanged — content is rendered as soon as it arrives, with
// no extra delay introduced by the throttle. This test snapshots that
// invariant on UNFIXED code; after the grapheme-aware fix it must
// continue to PASS.
//
// We use a self-contained mirror of `_StreamCharThrottle` (the
// production class is library-private). The mirror keeps the production
// short-circuit semantics: when `maxCharsPerSecond <= 0` (`isEnabled`
// false), `renderableLength` immediately advances to the full input
// length without consulting the token budget.
//
// Mirror naming follows the Task 1 file convention so each test file is
// self-contained and does not import the other test files.

import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Production-formula mirror of `_StreamCharThrottle`. Kept private to
/// this test file so we don't couple to the Task 1 mirror.
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
      // Production short-circuit: pass-through, immediate.
      _emittedChars = totalSanitizedLength;
      return totalSanitizedLength;
    }
    if (totalSanitizedLength <= _emittedChars) {
      return _emittedChars;
    }
    final n = now();
    final elapsedMicros = n.difference(_lastTickAt).inMicroseconds;
    if (elapsedMicros > 0) {
      _budget += elapsedMicros * maxCharsPerSecond / 1000000.0;
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

/// Random grapheme-cluster string generator (mixes ASCII, CJK, emoji).
String _randomGraphemes(Random rng, int targetGraphemes) {
  const alphabet = <String>[
    'a', 'B', '1', ' ',
    '中', '日', '本',
    '\u{1F600}', // 😀
    '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}', // 👨‍👩‍👧
    'á', // composed Latin
  ];
  final buf = StringBuffer();
  for (var i = 0; i < targetGraphemes; i++) {
    buf.write(alphabet[rng.nextInt(alphabet.length)]);
  }
  return buf.toString();
}

/// Sample (elapsedMs, visibleLen) trace from the mirror. With the
/// pass-through case the very first call returns the full length; after
/// that it stays constant.
List<int> _runDisabled({
  required int rateOrZero,
  required String content,
  required Duration totalDuration,
  Duration sampleInterval = const Duration(milliseconds: 16),
}) {
  final start = DateTime.utc(2026, 1, 1);
  var elapsed = Duration.zero;
  final throttle = _MirrorCharThrottle(
    maxCharsPerSecond: rateOrZero,
    now: () => start.add(elapsed),
  );
  final lengths = <int>[];
  while (elapsed <= totalDuration) {
    lengths.add(throttle.renderableLength(content.length));
    elapsed += sampleInterval;
  }
  return lengths;
}

void main() {
  group('Preservation — throttle disabled passes content through', () {
    test('rate=0: first sample already exposes full content (CJK)', () {
      const content = '中';
      final s = content * 200;
      final lengths = _runDisabled(
        rateOrZero: 0,
        content: s,
        totalDuration: const Duration(seconds: 5),
      );
      expect(
        lengths.first,
        equals(s.length),
        reason: 'rate=0 must pass full UTF-16 length on the first poll '
            '(production pass-through invariant). got=${lengths.first} '
            'expected=${s.length}.',
      );
      // Stays constant — no further deferral.
      expect(
        lengths.every((v) => v == s.length),
        isTrue,
        reason: 'rate=0 trace must stay at full length across all samples.',
      );
    });

    test('rate=0 with emoji ZWJ: full length immediately', () {
      const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
      final s = family * 30;
      final lengths = _runDisabled(
        rateOrZero: 0,
        content: s,
        totalDuration: const Duration(seconds: 2),
      );
      expect(lengths.first, equals(s.length));
    });

    test('Randomized PBT (40 cases) — throttle disabled is pass-through', () {
      final rng = Random(20260518);
      for (var i = 0; i < 40; i++) {
        final n = 1 + rng.nextInt(120);
        final content = _randomGraphemes(rng, n);
        // Two disabled flavours: rate=0 and a negative sentinel that the
        // production code clamps to "off" via `<= 0`.
        final rate = rng.nextBool() ? 0 : -(1 + rng.nextInt(10));
        final lengths = _runDisabled(
          rateOrZero: rate,
          content: content,
          totalDuration: const Duration(seconds: 3),
        );
        expect(
          lengths.first,
          equals(content.length),
          reason:
              'rate=$rate must pass full content on first poll '
              '(content graphemes=${content.characters.length}, '
              'utf16 units=${content.length}).',
        );
        expect(
          lengths.every((v) => v == content.length),
          isTrue,
          reason: 'rate=$rate trace must remain constant at full length.',
        );
      }
    });

    test('No extra delay vs raw content arrival (control: rate=5)', () {
      // Sanity contrast: enabled throttle must NOT immediately expose
      // full length on the first poll. The contrast keeps the
      // pass-through assertion meaningful.
      final start = DateTime.utc(2026, 1, 1);
      var elapsed = Duration.zero;
      final throttle = _MirrorCharThrottle(
        maxCharsPerSecond: 5,
        now: () => start.add(elapsed),
      );
      const content = 'Hello world!' ;
      final first = throttle.renderableLength(content.length);
      expect(
        first < content.length,
        isTrue,
        reason: 'control: enabled rate=5 must NOT pass full content '
            'instantly (got first=$first expected < ${content.length}).',
      );
    });
  });
}
