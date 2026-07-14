import '../../../l10n/app_localizations.dart';
import '../../../shared/util/input_value_parsing.dart';

/// Minimal cron expression parser for 5-field (minute-level) expressions.
///
/// Supports: `*`, exact numbers, comma-separated lists, ranges (`1-5`),
/// and step values (`*/5`, `1-30/5`).
///
/// Does NOT support the seconds field — the UI freezes seconds at 0.
class CronParser {
  CronParser._();

  static final RegExp _fieldSeparatorPattern = RegExp(r'\s+');

  /// Returns the next occurrence after [after] for the given 5-field
  /// [expression], or null if the expression is invalid.
  ///
  /// Safety: bails out after scanning 366 days to prevent infinite loops.
  static DateTime? nextRun(String expression, {DateTime? after}) {
    final fields = expression.trim().split(_fieldSeparatorPattern);
    final parsed = _parseExpressionFields(fields);
    if (parsed == null) return null;
    final (minutes, hours, daysOfMonth, months, daysOfWeek) = parsed;

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

  static bool isValid(String expression) {
    return _parseExpressionFields(
          expression.trim().split(_fieldSeparatorPattern),
        ) !=
        null;
  }

  static (Set<int>, Set<int>, Set<int>, Set<int>, Set<int>)?
  _parseExpressionFields(List<String> fields) {
    if (fields.length != 5) return null;
    final minutes = _parseField(fields[0], 0, 59);
    final hours = _parseField(fields[1], 0, 23);
    final daysOfMonth = _parseField(fields[2], 1, 31);
    final months = _parseField(fields[3], 1, 12);
    final daysOfWeek = _parseField(fields[4], 0, 7);
    if (minutes == null ||
        hours == null ||
        daysOfMonth == null ||
        months == null ||
        daysOfWeek == null) {
      return null;
    }
    return (minutes, hours, daysOfMonth, months, daysOfWeek);
  }

  /// Validates a 5-field cron expression. Returns null if valid, or a
  /// localized error description if invalid.
  static String? validate(String expression, {required AppLocalizations l10n}) {
    final fields = expression.trim().split(_fieldSeparatorPattern);
    if (fields.length != 5) {
      return l10n.cronParserFieldCountError;
    }
    final labels = [
      l10n.cronParserFieldMinute,
      l10n.cronParserFieldHour,
      l10n.cronParserFieldDayOfMonth,
      l10n.cronParserFieldMonth,
      l10n.cronParserFieldDayOfWeek,
    ];
    const ranges = [(0, 59), (0, 23), (1, 31), (1, 12), (0, 7)];
    for (var i = 0; i < 5; i++) {
      final parsed = _parseField(fields[i], ranges[i].$1, ranges[i].$2);
      if (parsed == null) {
        return l10n.cronParserInvalidField(labels[i], fields[i]);
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
          ? optionalPositiveIntFromValue(stepParts[1])
          : null;
      if (stepParts.length == 2 && step == null) return null;

      final rangePart = stepParts[0];

      int rangeStart;
      int rangeEnd;

      if (rangePart == '*') {
        rangeStart = min;
        rangeEnd = max;
      } else if (rangePart.contains('-')) {
        final bounds = rangePart.split('-');
        if (bounds.length != 2) return null;
        final a = optionalIntFromValue(bounds[0]);
        final b = optionalIntFromValue(bounds[1]);
        if (a == null || b == null) return null;
        if (a < min || b > max || a > b) return null;
        rangeStart = a;
        rangeEnd = b;
      } else {
        final val = optionalIntFromValue(rangePart);
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
