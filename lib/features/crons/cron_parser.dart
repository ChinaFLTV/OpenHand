/// Minimal cron expression parser for 5-field (minute-level) expressions.
///
/// Supports: `*`, exact numbers, comma-separated lists, ranges (`1-5`),
/// and step values (`*/5`, `1-30/5`).
///
/// Does NOT support the seconds field — the UI freezes seconds at 0.
class CronParser {
  CronParser._();

  /// Returns the next occurrence after [after] for the given 5-field
  /// [expression], or null if the expression is invalid.
  ///
  /// Safety: bails out after scanning 366 days to prevent infinite loops.
  static DateTime? nextRun(String expression, {DateTime? after}) {
    final fields = expression.trim().split(RegExp(r'\s+'));
    if (fields.length != 5) return null;

    final minutes = _parseField(fields[0], 0, 59);
    final hours = _parseField(fields[1], 0, 23);
    final daysOfMonth = _parseField(fields[2], 1, 31);
    final months = _parseField(fields[3], 1, 12);
    final daysOfWeek = _parseField(fields[4], 0, 7); // 0 & 7 = Sunday

    if (minutes == null ||
        hours == null ||
        daysOfMonth == null ||
        months == null ||
        daysOfWeek == null) {
      return null;
    }

    // Normalize day-of-week: convert 7 → 0 (both mean Sunday).
    final normalizedDow = daysOfWeek.map((d) => d == 7 ? 0 : d).toSet();

    var candidate = (after ?? DateTime.now()).add(const Duration(minutes: 1));
    candidate = DateTime(
      candidate.year,
      candidate.month,
      candidate.day,
      candidate.hour,
      candidate.minute,
    );

    // Scan forward at most ~527,040 minutes (≈ 366 days).
    const maxIterations = 527040;
    for (var i = 0; i < maxIterations; i++) {
      if (months.contains(candidate.month) &&
          daysOfMonth.contains(candidate.day) &&
          normalizedDow.contains(candidate.weekday % 7) &&
          hours.contains(candidate.hour) &&
          minutes.contains(candidate.minute)) {
        return candidate;
      }
      candidate = candidate.add(const Duration(minutes: 1));
    }
    return null;
  }

  /// Validates a 5-field cron expression. Returns null if valid, or an
  /// English/Chinese error description if invalid.
  static String? validate(String expression, {bool isZh = false}) {
    final fields = expression.trim().split(RegExp(r'\s+'));
    if (fields.length != 5) {
      return isZh
          ? 'Cron 表达式需要恰好 5 个字段（分 时 日 月 周）'
          : 'Cron expression must have exactly 5 fields (min hour dom mon dow)';
    }
    const labels = ['minute', 'hour', 'day-of-month', 'month', 'day-of-week'];
    const zhLabels = ['分钟', '小时', '日', '月', '星期'];
    const ranges = [
      (0, 59),
      (0, 23),
      (1, 31),
      (1, 12),
      (0, 7),
    ];
    for (var i = 0; i < 5; i++) {
      final parsed = _parseField(fields[i], ranges[i].$1, ranges[i].$2);
      if (parsed == null) {
        return isZh
            ? '${zhLabels[i]}字段 "${fields[i]}" 无效'
            : 'Invalid ${labels[i]} field "${fields[i]}"';
      }
    }
    return null;
  }

  /// Parses a single cron field into a set of matching integer values.
  /// Returns null if the field is syntactically invalid.
  static Set<int>? _parseField(String field, int min, int max) {
    final result = <int>{};
    for (final part in field.split(',')) {
      if (part.isEmpty) return null;
      // Handle step: */n or range/n
      final stepParts = part.split('/');
      if (stepParts.length > 2) return null;
      final step = stepParts.length == 2
          ? int.tryParse(stepParts[1])
          : null;
      if (stepParts.length == 2 && (step == null || step <= 0)) return null;

      final rangePart = stepParts[0];

      int rangeStart;
      int rangeEnd;

      if (rangePart == '*') {
        rangeStart = min;
        rangeEnd = max;
      } else if (rangePart.contains('-')) {
        final bounds = rangePart.split('-');
        if (bounds.length != 2) return null;
        final a = int.tryParse(bounds[0]);
        final b = int.tryParse(bounds[1]);
        if (a == null || b == null) return null;
        if (a < min || b > max || a > b) return null;
        rangeStart = a;
        rangeEnd = b;
      } else {
        final val = int.tryParse(rangePart);
        if (val == null || val < min || val > max) return null;
        if (step == null) {
          result.add(val);
          continue;
        }
        rangeStart = val;
        rangeEnd = max;
      }

      final effectiveStep = step ?? 1;
      for (var v = rangeStart; v <= rangeEnd; v += effectiveStep) {
        result.add(v);
      }
    }
    return result.isEmpty ? null : result;
  }
}
