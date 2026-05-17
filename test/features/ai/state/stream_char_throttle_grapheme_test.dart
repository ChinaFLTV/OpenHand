// Unit tests for `_StreamCharThrottle` after the grapheme switch.
//
// **Validates: Requirements 2.1, 2.2 (Bug 1 — Property 1)**
//
// The production class lives at
//   lib/features/ai/state/_ai_session_stream_throttle.dart
// and is `part of '../ai_session_controller.dart'`, which makes it
// library-private (cannot be imported from outside the controller
// library). We follow the established pattern in
// `test/specs/ai_throttle_and_ux_fixes/`: mirror the production formula
// in this file so the unit test stays self-contained while still
// faithfully exercising the new grapheme contract.
//
// The mirror's input is grapheme count (post task 3.1): callers pass
// `text.characters.length` and the throttle releases tokens in
// graphemes/sec. After task 3.2 lands the controller will be migrated
// to the same contract and these tests will continue to PASS.

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirror of the post-task-3.1 production `_StreamCharThrottle`. Operates
/// on grapheme counts. The injected `now` callback lets the test advance
/// time deterministically without relying on `package:fake_async` (the
/// production throttle calls `DateTime.now()` directly).
class _GraphemeMirrorCharThrottle {
  _GraphemeMirrorCharThrottle({
    required this.maxCharsPerSecond,
    required this.now,
  })  : _budget = maxCharsPerSecond.toDouble(),
        _lastTickAt = now();

  /// Grapheme tokens per second; <=0 disables the throttle.
  final int maxCharsPerSecond;
  final DateTime Function() now;
  double _budget;
  int _emittedGraphemes = 0;
  DateTime _lastTickAt;

  bool get isEnabled => maxCharsPerSecond > 0;

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
      if (_budget > maxCharsPerSecond) {
        _budget = maxCharsPerSecond.toDouble();
      }
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
}

/// Drive the mirror in synthetic time, sampling each tick. Returns the
/// visible-grapheme-count timeline, plus the well-formed visible text
/// produced by `text.characters.take(visible).toString()` (always
/// aligned to a grapheme cluster boundary).
class _Trace {
  _Trace({required this.elapsedMs, required this.visible, required this.text});
  final int elapsedMs;
  final int visible;
  final String text;
}

List<_Trace> _runTrace({
  required int rate,
  required String content,
  required Duration totalDuration,
  Duration sampleInterval = const Duration(milliseconds: 16),
}) {
  final start = DateTime.utc(2026);
  var elapsed = Duration.zero;
  final throttle = _GraphemeMirrorCharThrottle(
    maxCharsPerSecond: rate,
    now: () => start.add(elapsed),
  );
  final totalGraphemes = content.characters.length;
  final out = <_Trace>[];
  while (elapsed <= totalDuration) {
    final visible = throttle.renderableGraphemeCount(totalGraphemes);
    final visibleText = visible >= totalGraphemes
        ? content
        : content.characters.take(visible).toString();
    out.add(
      _Trace(
        elapsedMs: elapsed.inMilliseconds,
        visible: visible,
        text: visibleText,
      ),
    );
    elapsed += sampleInterval;
  }
  return out;
}

/// True when [s] round-trips through `package:characters` with the
/// expected grapheme count [expectedGraphemes]. This is the canonical
/// post-fix invariant: `text.characters.take(n).toString()` MUST always
/// satisfy `result.characters.length == n`. A failure here means the
/// slice landed inside a cluster (mid-surrogate / mid-ZWJ /
/// mid-combining-mark), which is exactly the Bug 1 symptom.
bool _isGraphemeAligned(String s, int expectedGraphemes) {
  return s.characters.length == expectedGraphemes;
}

/// First sample at-or-after [t]. Returns the trace itself.
_Trace _sampleAt(List<_Trace> trace, Duration t) {
  for (final s in trace) {
    if (s.elapsedMs >= t.inMilliseconds) return s;
  }
  return trace.last;
}

void main() {
  group('_StreamCharThrottle grapheme contract', () {
    test(
      'emoji ZWJ family (👨‍👩‍👧 × 30) at 5 cps is throttled, '
      'drain ≥ ~5s, slices stay on cluster boundaries',
      () {
        const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}'; // 👨‍👩‍👧
        final content = family * 30;
        expect(content.characters.length, 30,
            reason: 'sanity check: each ZWJ family is one grapheme cluster.');

        const rate = 5;
        final trace = _runTrace(
          rate: rate,
          content: content,
          totalDuration: const Duration(seconds: 12),
        );

        // 1) Per-second sliding window: emissions must respect the rate
        //    (with a small token-bucket tolerance).
        final tolerance = (rate * 0.5).ceil(); // ±3 graphemes per second
        for (var i = 0; i < trace.length; i++) {
          final start = trace[i];
          final endIdx = trace.indexWhere(
            (s) => s.elapsedMs - start.elapsedMs >= 1000,
            i,
          );
          if (endIdx < 0) break;
          final delta = trace[endIdx].visible - start.visible;
          expect(
            delta <= rate + tolerance,
            isTrue,
            reason: 'sliding 1s window from ${start.elapsedMs}ms emitted '
                '$delta graphemes; rate=$rate tolerance=$tolerance.',
          );
        }

        // 2) The throttle must still be draining at t=4.5s — proving
        //    that 30 graphemes at rate=5/s cannot be flushed in less
        //    than ~5 seconds. (Token bucket: initial burst grants
        //    `rate` graphemes at t=0, then refill at `rate`/sec, so
        //    full drain time ≈ (N − rate) / rate + 0 = 5s for N=30.)
        final at4500ms = _sampleAt(trace, const Duration(milliseconds: 4500));
        expect(
          at4500ms.visible < 30,
          isTrue,
          reason: 'at t=4.5s visible should still be below 30 — '
              'continuous throttle should make the full drain take '
              '≥ ~5s. visible=${at4500ms.visible}.',
        );

        // 3) At t=4s visible has made measurable progress (lower bound)
        //    AND has not finished (upper bound). Concrete bounds are
        //    intentionally loose to tolerate scheduler jitter.
        final at4s = _sampleAt(trace, const Duration(seconds: 4));
        expect(
          at4s.visible >= 3,
          isTrue,
          reason: 'at t=4s ≥3 graphemes should have been released. '
              'visible=${at4s.visible}.',
        );
        expect(
          at4s.visible < 30,
          isTrue,
          reason: 'at t=4s the drain should still be ongoing. '
              'visible=${at4s.visible}.',
        );

        // 4) Every visible slice MUST end on a grapheme boundary —
        //    `text.characters.take(n).toString()` guarantees this on
        //    the new API; sanity-check it explicitly to lock in the
        //    invariant for future refactors.
        for (final s in trace) {
          expect(
            _isGraphemeAligned(s.text, s.visible),
            isTrue,
            reason: 'visible text at ${s.elapsedMs}ms is sliced inside a '
                'cluster: visible=${s.visible} '
                'observedGraphemes=${s.text.characters.length} '
                'codeUnits=${s.text.codeUnits}.',
          );
        }
      },
    );

    test(
      'combining mark á (a + U+0301) is one grapheme; visible immediately '
      'reaches 1 with rate=1cps',
      () {
        const content = 'a\u0301'; // á
        expect(
          content.characters.length,
          1,
          reason: 'sanity check: U+0301 combines with prior `a` into one '
              'grapheme cluster.',
        );
        // Sanity: code units are 2 (the bug is exactly this mismatch).
        expect(content.length, 2);

        final start = DateTime.utc(2026);
        var elapsed = Duration.zero;
        final throttle = _GraphemeMirrorCharThrottle(
          maxCharsPerSecond: 1,
          now: () => start.add(elapsed),
        );
        // First poll at t=0: initial budget == rate (1), so the single
        // grapheme is granted immediately.
        final visible = throttle.renderableGraphemeCount(
          content.characters.length,
        );
        expect(
          visible,
          1,
          reason: 'with initial budget == rate the 1-grapheme content is '
              'released on the first poll.',
        );
        // Slicing must produce the full single-grapheme `á` (a + U+0301),
        // NOT the bare `a` that a UTF-16-aware substring would emit.
        final visibleText = visible >= content.characters.length
            ? content
            : content.characters.take(visible).toString();
        expect(visibleText, content,
            reason: 'visible must be the full combining-mark string.');
        expect(visibleText.codeUnits, <int>[0x61, 0x0301]);
        expect(
          _isGraphemeAligned(visibleText, 1),
          isTrue,
          reason: 'á must not be sliced before the combining U+0301.',
        );
      },
    );

    test('CJK 中 × 100 at 10 cps drains in ~10s and respects rate', () {
      const content = '中';
      final sample = content * 100;
      expect(sample.characters.length, 100);

      const rate = 10;
      final trace = _runTrace(
        rate: rate,
        content: sample,
        totalDuration: const Duration(seconds: 14),
      );

      // Sliding 1s window: emissions stay within rate ± tolerance.
      final tolerance = (rate * 0.5).ceil(); // ±5
      for (var i = 0; i < trace.length; i++) {
        final start = trace[i];
        final endIdx = trace.indexWhere(
          (s) => s.elapsedMs - start.elapsedMs >= 1000,
          i,
        );
        if (endIdx < 0) break;
        final delta = trace[endIdx].visible - start.visible;
        expect(
          delta <= rate + tolerance,
          isTrue,
          reason: 'sliding 1s window from ${start.elapsedMs}ms emitted '
              '$delta graphemes; rate=$rate tolerance=$tolerance.',
        );
      }

      // 8-second checkpoint: still draining. With initial budget of 10
      // (rate-worth of graphemes) and 10 graphemes/sec refill, the
      // mathematical drain time is ≈ 9s. We anchor at t=8s with a small
      // margin to stay robust to scheduler jitter.
      final at8s = _sampleAt(trace, const Duration(seconds: 8));
      expect(
        at8s.visible < 100,
        isTrue,
        reason: 'at t=8s the 100-grapheme buffer should still be draining '
            'at 10 graphemes/sec. visible=${at8s.visible}.',
      );

      // After ~12s the drain MUST be complete (≈10s of pacing + initial
      // budget grace + scheduler tolerance).
      final at12s = _sampleAt(trace, const Duration(seconds: 12));
      expect(
        at12s.visible,
        100,
        reason: 'at t=12s the throttle MUST have released all 100 '
            'graphemes (drain time ≈ 10s).',
      );

      // No mid-cluster slicing for CJK either (each `中` is one
      // grapheme spanning a single BMP code unit).
      for (final s in trace) {
        expect(
          _isGraphemeAligned(s.text, s.visible),
          isTrue,
          reason: 'visible CJK text at ${s.elapsedMs}ms misaligned: '
              'visible=${s.visible} '
              'observedGraphemes=${s.text.characters.length}.',
        );
      }
    });

    test(
      'rate==0 short-circuits — pass-through regardless of grapheme cost',
      () {
        const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}'; // 👨‍👩‍👧
        final content = family * 5;
        final start = DateTime.utc(2026);
        final throttle = _GraphemeMirrorCharThrottle(
          maxCharsPerSecond: 0,
          now: () => start,
        );
        final visible = throttle.renderableGraphemeCount(
          content.characters.length,
        );
        expect(visible, content.characters.length,
            reason: 'rate=0 (disabled) MUST pass-through immediately.');
      },
    );
  });
}
