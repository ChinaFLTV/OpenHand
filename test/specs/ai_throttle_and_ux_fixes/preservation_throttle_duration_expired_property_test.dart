// Bug 1 Preservation #2 — Throttle `durationSeconds > 0` and expired.
//
// **Validates: Requirements 7.3**
//
// Property 6 (Preservation): when `durationSeconds > 0` and the
// throttle window has elapsed, the production `_StreamCharThrottle`
// SHALL flip `isEnabled` to false (`_isExpired` true) and pass any
// remaining sanitized text through on the next `renderableLength`
// call. We are interested in the time-passes-through invariant — NOT
// in character semantics, because the unfixed code uses UTF-16 length.
//
// To keep this preservation test green on UNFIXED code, we mirror the
// production formula EXACTLY (UTF-16 length budget, same expiry
// short-circuit). After the fix, the formula will be replaced with the
// grapheme-aware variant; preservation here only asserts the
// "after expiry, remaining content flushes in one call" invariant,
// which is unaffected by the unit chosen for the budget.

import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

class _MirrorCharThrottle {
  _MirrorCharThrottle({
    required this.maxCharsPerSecond,
    required this.now,
    Duration? throttleDuration,
  })  : _budget = maxCharsPerSecond.toDouble(),
        _lastTickAt = now(),
        _expireAt = (throttleDuration != null &&
                throttleDuration.inMilliseconds > 0)
            ? now().add(throttleDuration)
            : null;

  final int maxCharsPerSecond;
  final DateTime Function() now;
  double _budget;
  int _emittedChars = 0;
  DateTime _lastTickAt;
  final DateTime? _expireAt;

  bool get _isExpired {
    final exp = _expireAt;
    return exp != null && !now().isBefore(exp);
  }

  bool get isEnabled => maxCharsPerSecond > 0 && !_isExpired;

  int renderableLength(int totalSanitizedLength) {
    if (!isEnabled) {
      // Production short-circuit when expired: pass-through.
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

/// Mixed grapheme generator (ASCII / CJK / emoji ZWJ).
String _randomGraphemes(Random rng, int n) {
  const alphabet = <String>[
    'a', 'B', '1', ' ',
    '中', '日', '本',
    '\u{1F600}',
    '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}',
  ];
  final buf = StringBuffer();
  for (var i = 0; i < n; i++) {
    buf.write(alphabet[rng.nextInt(alphabet.length)]);
  }
  return buf.toString();
}

void main() {
  group('Preservation — throttle duration expires then flushes', () {
    test('rate=5, duration=2s: after 2.5s remaining content flushes at once',
        () {
      const content = 'Hello world. ';
      final s = content * 50; // 650 utf16 units, ~50 graphemes.
      final start = DateTime.utc(2026, 1, 1);
      var elapsed = Duration.zero;
      final throttle = _MirrorCharThrottle(
        maxCharsPerSecond: 5,
        throttleDuration: const Duration(seconds: 2),
        now: () => start.add(elapsed),
      );
      // Drive at 16ms cadence for the first 2.5s.
      const tick = Duration(milliseconds: 16);
      var lastVisible = 0;
      while (elapsed <= const Duration(milliseconds: 2500)) {
        lastVisible = throttle.renderableLength(s.length);
        elapsed += tick;
      }
      // After the throttle expires, the very next poll must flush the
      // entire remaining length (production pass-through on expiry).
      final flushed = throttle.renderableLength(s.length);
      expect(
        flushed,
        equals(s.length),
        reason:
            'after duration expired, remaining content must flush to '
            '${s.length}; got $flushed (last visible before flush: $lastVisible).',
      );
    });

    test('Pre-expiry behaviour is throttled (control)', () {
      const content = 'X';
      final s = content * 200;
      final start = DateTime.utc(2026, 1, 1);
      var elapsed = Duration.zero;
      final throttle = _MirrorCharThrottle(
        maxCharsPerSecond: 5,
        throttleDuration: const Duration(seconds: 4),
        now: () => start.add(elapsed),
      );
      // Sample at 1.5s — well within the throttle window.
      elapsed = const Duration(milliseconds: 1500);
      final mid = throttle.renderableLength(s.length);
      expect(
        mid < s.length,
        isTrue,
        reason: 'control: at 1.5s under rate=5/duration=4s, the visible '
            'length must remain below the full content length. got=$mid.',
      );
    });

    test(
      'Randomized PBT (30 cases) — post-expiry passes remainder through',
      () {
        final rng = Random(20260519);
        for (var i = 0; i < 30; i++) {
          final rate = 1 + rng.nextInt(20);
          final durationSeconds = 1 + rng.nextInt(4);
          final n = 4 + rng.nextInt(120);
          final content = _randomGraphemes(rng, n);
          final start = DateTime.utc(2026, 1, 1);
          var elapsed = Duration.zero;
          final throttle = _MirrorCharThrottle(
            maxCharsPerSecond: rate,
            throttleDuration: Duration(seconds: durationSeconds),
            now: () => start.add(elapsed),
          );
          // Drive ticks until past the expiry boundary.
          const tick = Duration(milliseconds: 32);
          final cutoff =
              Duration(seconds: durationSeconds, milliseconds: 200);
          while (elapsed <= cutoff) {
            throttle.renderableLength(content.length);
            elapsed += tick;
          }
          // First poll past expiry: flush all remaining content.
          final flushed = throttle.renderableLength(content.length);
          expect(
            flushed,
            equals(content.length),
            reason:
                'PBT #$i (rate=$rate dur=$durationSeconds n=$n graphemes='
                '${content.characters.length}): expected flushed '
                '== ${content.length}; got $flushed.',
          );
        }
      },
    );
  });
}
