// Bug 1 — Assistant final-response throttle FIX verification PBT.
//
// **Validates: Requirements 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 2.4**
//
// History note: this file was originally authored as an *exploration*
// PBT against the unfixed UTF-16 budget formula and was therefore
// expected to fail. After tasks 3.1 / 3.2 / 3.3 the production
// `_StreamCharThrottle` (lib/features/ai/state/_ai_session_stream_throttle.dart)
// switched its budget to grapheme cluster counts (`package:characters`)
// and renamed the public hook to `renderableGraphemeCount`. The mirror
// below now reflects that production formula 1:1 so this file acts as
// the post-fix acceptance PBT (task 3.4): it MUST pass green on the
// fixed code.
//
// The class is library-private (`part of '../ai_session_controller.dart'`),
// which is why we keep an in-test mirror — same pattern used by the
// unit-test sibling at
//   test/features/ai/state/stream_char_throttle_grapheme_test.dart.
// The injected `now` callback lets the test advance time deterministically
// without relying on `package:fake_async`.

import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirror of the production `_StreamCharThrottle` formula post-task-3.1.
/// Operates on grapheme cluster counts: callers pass
/// `text.characters.length` and the throttle releases tokens in
/// graphemes/sec.
class _MirrorCharThrottle {
  _MirrorCharThrottle({required this.maxCharsPerSecond, required this.now})
      : _budget = maxCharsPerSecond.toDouble(),
        _lastTickAt = now();

  /// Grapheme tokens per second; <=0 disables the throttle.
  final int maxCharsPerSecond;
  final DateTime Function() now;
  double _budget;
  int _emittedGraphemes = 0;
  DateTime _lastTickAt;

  bool get isEnabled => maxCharsPerSecond > 0;

  /// Production-equivalent: takes the total sanitized text's grapheme
  /// count and returns the count of GRAPHEMES that may currently be
  /// displayed. Callers slice via `text.characters.take(visible)` so
  /// the visible substring always lands on a cluster boundary.
  int renderableGraphemeCount(int totalSanitizedGraphemeCount) {
    if (!isEnabled) {
      _emittedGraphemes = totalSanitizedGraphemeCount;
      return totalSanitizedGraphemeCount;
    }
    if (totalSanitizedGraphemeCount <= _emittedGraphemes) {
      return _emittedGraphemes;
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
      final pending = totalSanitizedGraphemeCount - _emittedGraphemes;
      final granted = allowance >= pending ? pending : allowance;
      _emittedGraphemes += granted;
      _budget -= granted;
    }
    return _emittedGraphemes;
  }

  /// Backwards-compatible wrapper kept so this PBT file can keep its
  /// previous structure: callers pass the grapheme total here too.
  /// Equivalent to [renderableGraphemeCount] (the production
  /// `renderableLength` is now an `@Deprecated` forwarder with the
  /// same semantics).
  int renderableLength(int totalSanitizedGraphemeCount) =>
      renderableGraphemeCount(totalSanitizedGraphemeCount);
}

/// One sample of the visible text at a given moment.
class _Sample {
  _Sample({required this.elapsedMs, required this.visibleText});
  final int elapsedMs;
  final String visibleText;

  int get visibleGraphemeCount => visibleText.characters.length;
}

/// Drive the mirrored throttle in synthetic time and collect per-tick
/// samples of what the UI would actually see (using production's
/// grapheme-aligned `Characters.take(n).toString()` slicing).
List<_Sample> _runScenario({
  required int rateCharsPerSecond,
  required String content,
  required Duration totalDuration,
  Duration sampleInterval = const Duration(milliseconds: 16),
}) {
  final start = DateTime.utc(2026);
  var elapsed = Duration.zero;
  final throttle = _MirrorCharThrottle(
    maxCharsPerSecond: rateCharsPerSecond,
    now: () => start.add(elapsed),
  );
  final totalGraphemes = content.characters.length;
  final samples = <_Sample>[];
  while (elapsed <= totalDuration) {
    // Production passes `fullSanitized.characters.length` (grapheme count).
    final visible = throttle.renderableGraphemeCount(totalGraphemes);
    // Production slices via `content.characters.take(visible).toString()`
    // — this always lands on a grapheme cluster boundary.
    final clamped = visible.clamp(0, totalGraphemes);
    final visibleText = clamped >= totalGraphemes
        ? content
        : content.characters.take(clamped).toString();
    samples.add(
      _Sample(elapsedMs: elapsed.inMilliseconds, visibleText: visibleText),
    );
    elapsed += sampleInterval;
  }
  return samples;
}

/// True when the UTF-16 form of [s] contains no lone surrogates, no
/// trailing ZWJ, and no trailing combining mark — i.e. the slice ended
/// at a real grapheme cluster boundary.
bool _isWellFormedGraphemeAligned(String s) {
  if (s.isEmpty) return true;
  final cu = s.codeUnits;
  for (var i = 0; i < cu.length; i++) {
    final c = cu[i];
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 >= cu.length) return false;
      final next = cu[i + 1];
      if (next < 0xDC00 || next > 0xDFFF) return false;
      i++;
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      // lone low surrogate.
      return false;
    }
  }
  // ZWJ at the tail means the next emoji of the joiner sequence is
  // missing → orphaned cluster.
  if (cu.last == 0x200D) return false;
  // Combining marks (very partial range coverage) at the tail are also
  // a sign of mid-cluster slicing; we cover the most common ones here.
  if (cu.last >= 0x0300 && cu.last <= 0x036F) return false;
  return true;
}

void _assertOneSecondWindowGraphemeRate({
  required List<_Sample> samples,
  required int rateGraphemesPerSecond,
}) {
  // tolerance per design.md: ±ceil(rate × 0.5) graphemes.
  final tolerance = (rateGraphemesPerSecond * 0.5).ceil();
  for (var i = 0; i < samples.length; i++) {
    final start = samples[i];
    // find the sample at +1s.
    final endIdx = samples.indexWhere(
      (s) => s.elapsedMs - start.elapsedMs >= 1000,
      i,
    );
    if (endIdx < 0) break;
    final end = samples[endIdx];
    final delta = end.visibleGraphemeCount - start.visibleGraphemeCount;
    expect(
      delta <= rateGraphemesPerSecond + tolerance,
      isTrue,
      reason:
          'sliding 1s window starting at ${start.elapsedMs}ms emitted '
          '$delta graphemes, exceeds rate $rateGraphemesPerSecond + tol $tolerance.',
    );
  }
}

/// After [secondsToCheck] seconds of elapsed time on a content with at
/// least `secondsToCheck × rate` graphemes, the visible grapheme count
/// MUST be at least `secondsToCheck × rate − tolerance`. With the
/// grapheme-aware budget this lower bound holds even on emoji ZWJ
/// content (which used to advance at ≪1 grapheme/sec under the
/// UTF-16 formula).
void _assertOneSecondWindowGraphemeLowerBound({
  required List<_Sample> samples,
  required int rateGraphemesPerSecond,
  required int totalGraphemes,
  int secondsToCheck = 5,
}) {
  if (totalGraphemes < rateGraphemesPerSecond * secondsToCheck) return;
  final tolerance = max(2, (rateGraphemesPerSecond * 0.5).ceil());
  for (final sample in samples) {
    if (sample.elapsedMs < secondsToCheck * 1000) continue;
    final expectedAtLeast =
        ((sample.elapsedMs / 1000) * rateGraphemesPerSecond - tolerance)
            .floor();
    if (expectedAtLeast <= 0) continue;
    expect(
      sample.visibleGraphemeCount >= expectedAtLeast,
      isTrue,
      reason:
          'at ${sample.elapsedMs}ms only ${sample.visibleGraphemeCount} '
          'graphemes have been emitted; expected ≥ $expectedAtLeast '
          '(rate $rateGraphemesPerSecond/s, tolerance $tolerance).',
    );
    // Only the earliest qualifying sample is checked — saves CPU and
    // gives a precise counterexample.
    return;
  }
}

void _assertWellFormed(List<_Sample> samples) {
  for (final sample in samples) {
    expect(
      _isWellFormedGraphemeAligned(sample.visibleText),
      isTrue,
      reason:
          'visible text at ${sample.elapsedMs}ms is sliced inside a '
          'surrogate pair / ZWJ sequence: codeUnits=${sample.visibleText.codeUnits}.',
    );
  }
}

void main() {
  group('Bug 1 — assistant final-response throttle (Property 1)', () {
    test('CJK 200 chars at 5 cps respects 1s sliding-window grapheme rate', () {
      const content = '中';
      final sample = content * 200;
      final samples = _runScenario(
        rateCharsPerSecond: 5,
        content: sample,
        totalDuration: const Duration(seconds: 60),
      );
      _assertOneSecondWindowGraphemeRate(
        samples: samples,
        rateGraphemesPerSecond: 5,
      );
      _assertOneSecondWindowGraphemeLowerBound(
        samples: samples,
        rateGraphemesPerSecond: 5,
        totalGraphemes: sample.characters.length,
      );
      _assertWellFormed(samples);
    });

    test(
      'Emoji ZWJ family x30 at 5 cps respects grapheme rate AND boundary',
      () {
        const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}'; // 👨‍👩‍👧
        final sample = family * 30;
        final samples = _runScenario(
          rateCharsPerSecond: 5,
          content: sample,
          totalDuration: const Duration(seconds: 12),
        );
        _assertOneSecondWindowGraphemeRate(
          samples: samples,
          rateGraphemesPerSecond: 5,
        );
        _assertOneSecondWindowGraphemeLowerBound(
          samples: samples,
          rateGraphemesPerSecond: 5,
          totalGraphemes: sample.characters.length,
          secondsToCheck: 4,
        );
        _assertWellFormed(samples);
      },
    );

    test('Mixed CJK + Latin + emoji at 8 cps respects grapheme contract', () {
      const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
      const piece = 'Hello 你好 $family';
      final sample = piece * 50;
      final samples = _runScenario(
        rateCharsPerSecond: 8,
        content: sample,
        totalDuration: const Duration(seconds: 30),
      );
      _assertOneSecondWindowGraphemeRate(
        samples: samples,
        rateGraphemesPerSecond: 8,
      );
      _assertOneSecondWindowGraphemeLowerBound(
        samples: samples,
        rateGraphemesPerSecond: 8,
        totalGraphemes: sample.characters.length,
      );
      _assertWellFormed(samples);
    });

    test('Randomized PBT (50 cases) respects grapheme contract', () {
      // Scoped reproducible seed; counterexamples reported via fail message.
      final rng = Random(424242);
      const alphabet = <String>[
        '中', '日', '本',
        'a', 'B', '1',
        '\u{1F600}', // 😀
        '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}', // 👨‍👩‍👧
      ];
      for (var i = 0; i < 50; i++) {
        final rate = 1 + rng.nextInt(20);
        final n = 8 + rng.nextInt(40);
        final buf = StringBuffer();
        for (var k = 0; k < n; k++) {
          buf.write(alphabet[rng.nextInt(alphabet.length)]);
        }
        final content = buf.toString();
        final samples = _runScenario(
          rateCharsPerSecond: rate,
          content: content,
          totalDuration: Duration(seconds: (n / rate).ceil() + 5),
        );
        _assertOneSecondWindowGraphemeRate(
          samples: samples,
          rateGraphemesPerSecond: rate,
        );
        _assertWellFormed(samples);
      }
    });
  });
}
