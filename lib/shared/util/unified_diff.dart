import 'dart:convert';

import 'byte_size_format.dart';

const int kUnifiedDiffDefaultMaxBytes = 256 * kBytesPerKiB;
const int kUnifiedDiffDefaultMiniDiffBytes = 32 * kBytesPerKiB;
const int kUnifiedDiffDefaultContextLines = 3;
const int kUnifiedDiffMaxMyersLineTotal = 2000;

List<String> unifiedDiffLinesFromText(
  String before,
  String after, {
  int contextLines = kUnifiedDiffDefaultContextLines,
  int maxMyersLineTotal = kUnifiedDiffMaxMyersLineTotal,
}) {
  return unifiedDiffLines(
    _splitDiffLines(before),
    _splitDiffLines(after),
    contextLines: contextLines,
    maxMyersLineTotal: maxMyersLineTotal,
  );
}

({int addedLines, int removedLines}) unifiedDiffLineStatsFromText(
  String before,
  String after, {
  int maxMyersLineTotal = kUnifiedDiffMaxMyersLineTotal,
}) {
  return unifiedDiffLineStats(
    _splitDiffLines(before),
    _splitDiffLines(after),
    maxMyersLineTotal: maxMyersLineTotal,
  );
}

({int addedLines, int removedLines}) unifiedDiffLineStats(
  List<String> before,
  List<String> after, {
  int maxMyersLineTotal = kUnifiedDiffMaxMyersLineTotal,
}) {
  if (before.isEmpty && after.isEmpty) {
    return (addedLines: 0, removedLines: 0);
  }
  if (before.isEmpty) {
    return (addedLines: after.length, removedLines: 0);
  }
  if (after.isEmpty) {
    return (addedLines: 0, removedLines: before.length);
  }

  final safeLineLimit = maxMyersLineTotal < 1 ? 1 : maxMyersLineTotal;
  if (before.length + after.length > safeLineLimit) {
    return _fallbackLineStats(before, after);
  }
  final edits = _myersDiffEdits(before, after);
  var added = 0;
  var removed = 0;
  for (final edit in edits) {
    if (edit.type == '+') {
      added += 1;
    } else if (edit.type == '-') {
      removed += 1;
    }
  }
  return (addedLines: added, removedLines: removed);
}

List<String> unifiedDiffLines(
  List<String> before,
  List<String> after, {
  int contextLines = kUnifiedDiffDefaultContextLines,
  int maxMyersLineTotal = kUnifiedDiffMaxMyersLineTotal,
}) {
  if (before.isEmpty && after.isEmpty) return const <String>[];
  if (before.isEmpty) {
    return <String>[
      '--- /dev/null',
      '+++ b/file',
      '@@ -0,0 +1,${after.length} @@',
      ...after.map((line) => '+$line'),
    ];
  }
  if (after.isEmpty) {
    return <String>[
      '--- a/file',
      '+++ /dev/null',
      '@@ -1,${before.length} +0,0 @@',
      ...before.map((line) => '-$line'),
    ];
  }

  final safeLineLimit = maxMyersLineTotal < 1 ? 1 : maxMyersLineTotal;
  if (before.length + after.length > safeLineLimit) {
    return _fallbackDiff(before, after);
  }

  final edits = _myersDiffEdits(before, after);
  if (edits.every((edit) => edit.type == ' ')) return const <String>[];

  final safeContext = contextLines < 0 ? 0 : contextLines;
  final result = <String>['--- a/file', '+++ b/file'];
  for (final range in _hunkRanges(edits, safeContext)) {
    final (start, end) = range;
    var beforeLine = 0;
    var afterLine = 0;
    for (var i = 0; i < start; i++) {
      if (edits[i].type != '+') beforeLine++;
      if (edits[i].type != '-') afterLine++;
    }

    final hunkBeforeStart = beforeLine + 1;
    final hunkAfterStart = afterLine + 1;
    var hunkBeforeCount = 0;
    var hunkAfterCount = 0;
    final hunkLines = <String>[];
    for (var i = start; i < end; i++) {
      final edit = edits[i];
      hunkLines.add('${edit.type}${edit.text}');
      if (edit.type != '+') hunkBeforeCount++;
      if (edit.type != '-') hunkAfterCount++;
    }

    result.add(
      '@@ -$hunkBeforeStart,$hunkBeforeCount '
      '+$hunkAfterStart,$hunkAfterCount @@',
    );
    result.addAll(hunkLines);
  }
  return result;
}

String unifiedDiffLineSummary(
  String before,
  String after, {
  int maxBytes = kUnifiedDiffDefaultMaxBytes,
  int miniDiffMaxBytes = kUnifiedDiffDefaultMiniDiffBytes,
  String? beforeSha,
  String? afterSha,
}) {
  final beforeBytes = _utf8ByteLength(before);
  final afterBytes = _utf8ByteLength(after);
  if (beforeBytes > maxBytes || afterBytes > maxBytes) {
    return '<file too large for inline diff; '
        'before=${beforeBytes}B${_shortShaTag(beforeSha)}, '
        'after=${afterBytes}B${_shortShaTag(afterSha)}>';
  }

  final beforeLines = _splitDiffLines(before);
  final afterLines = _splitDiffLines(after);
  final maxLen = beforeLines.length > afterLines.length
      ? beforeLines.length
      : afterLines.length;
  final compact =
      miniDiffMaxBytes > 0 &&
      (beforeBytes > miniDiffMaxBytes || afterBytes > miniDiffMaxBytes);
  final out = StringBuffer();
  var emitted = 0;

  for (var i = 0; i < maxLen; i++) {
    final lhs = i < beforeLines.length ? beforeLines[i] : null;
    final rhs = i < afterLines.length ? afterLines[i] : null;
    if (lhs == rhs) {
      if (!compact) out.writeln(' ${lhs ?? ''}');
      continue;
    }
    if (lhs != null) {
      out.writeln('-$lhs');
      emitted++;
    }
    if (rhs != null) {
      out.writeln('+$rhs');
      emitted++;
    }
  }

  if (compact && emitted == 0) return '';
  return out.toString().trimRight();
}

List<String> _splitDiffLines(String value) {
  if (value.isEmpty) return const <String>[];
  return const LineSplitter().convert(value);
}

String _shortShaTag(String? sha) {
  if (sha == null || sha.isEmpty) return '';
  return ' sha=${sha.length >= 12 ? sha.substring(0, 12) : sha}';
}

int _utf8ByteLength(String value) => utf8.encode(value).length;

List<({String type, String text})> _myersDiffEdits(
  List<String> before,
  List<String> after,
) {
  final n = before.length;
  final m = after.length;
  final max = n + m;
  final offset = max;
  final v = List<int>.filled(2 * max + 1, 0);
  final traces = <List<int>>[];

  var found = false;
  for (var d = 0; d <= max && !found; d++) {
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])) {
        x = v[k + 1 + offset];
      } else {
        x = v[k - 1 + offset] + 1;
      }
      var y = x - k;
      while (x < n && y < m && before[x] == after[y]) {
        x++;
        y++;
      }
      v[k + offset] = x;
      if (x >= n && y >= m) {
        found = true;
        break;
      }
    }
    traces.add(List<int>.from(v));
  }

  final editScript = <({String type, String text})>[];
  var bx = n;
  var by = m;
  for (var d = traces.length - 1; d > 0; d--) {
    final vPrev = traces[d - 1];
    final k = bx - by;
    final prevK =
        k == -d || (k != d && vPrev[k - 1 + offset] < vPrev[k + 1 + offset])
        ? k + 1
        : k - 1;
    final prevX = vPrev[prevK + offset];
    final prevY = prevX - prevK;

    while (bx > prevX && by > prevY) {
      bx--;
      by--;
      editScript.add((type: ' ', text: before[bx]));
    }
    if (bx == prevX && by > prevY) {
      by--;
      editScript.add((type: '+', text: after[by]));
    } else if (by == prevY && bx > prevX) {
      bx--;
      editScript.add((type: '-', text: before[bx]));
    }
  }

  while (bx > 0 && by > 0) {
    bx--;
    by--;
    editScript.add((type: ' ', text: before[bx]));
  }
  while (bx > 0) {
    bx--;
    editScript.add((type: '-', text: before[bx]));
  }
  while (by > 0) {
    by--;
    editScript.add((type: '+', text: after[by]));
  }

  return editScript.reversed.toList(growable: false);
}

({int addedLines, int removedLines}) _fallbackLineStats(
  List<String> before,
  List<String> after,
) {
  final window = _fallbackWindow(before, after);
  var added = 0;
  var removed = 0;
  final beforeCount = window.beforeEnd - window.beforeStart;
  final afterCount = window.afterEnd - window.afterStart;
  final maxLen = beforeCount > afterCount ? beforeCount : afterCount;
  for (var i = 0; i < maxLen; i++) {
    final beforeLine = i < beforeCount ? before[window.beforeStart + i] : null;
    final afterLine = i < afterCount ? after[window.afterStart + i] : null;
    if (beforeLine == afterLine) continue;
    if (beforeLine != null) removed += 1;
    if (afterLine != null) added += 1;
  }
  return (addedLines: added, removedLines: removed);
}

List<(int, int)> _hunkRanges(
  List<({String type, String text})> edits,
  int contextLines,
) {
  final changeIndices = <int>[];
  for (var i = 0; i < edits.length; i++) {
    if (edits[i].type != ' ') changeIndices.add(i);
  }
  if (changeIndices.isEmpty) return const <(int, int)>[];

  final ranges = <(int, int)>[];
  var hunkStart = (changeIndices.first - contextLines).clamp(0, edits.length);
  var hunkEnd = (changeIndices.first + contextLines + 1).clamp(0, edits.length);

  for (var ci = 1; ci < changeIndices.length; ci++) {
    final start = (changeIndices[ci] - contextLines).clamp(0, edits.length);
    final end = (changeIndices[ci] + contextLines + 1).clamp(0, edits.length);
    if (start <= hunkEnd) {
      hunkEnd = end;
    } else {
      ranges.add((hunkStart, hunkEnd));
      hunkStart = start;
      hunkEnd = end;
    }
  }
  ranges.add((hunkStart, hunkEnd));
  return ranges;
}

List<String> _fallbackDiff(List<String> before, List<String> after) {
  final result = <String>['--- a/file', '+++ b/file'];
  final window = _fallbackWindow(before, after);
  final beforeCount = window.beforeEnd - window.beforeStart;
  final afterCount = window.afterEnd - window.afterStart;
  final maxLen = beforeCount > afterCount ? beforeCount : afterCount;
  var diffStart = -1;
  final hunkLines = <String>[];

  void flush() {
    if (hunkLines.isEmpty) return;
    final beforeStart = window.beforeStart + diffStart;
    final afterStart = window.afterStart + diffStart;
    var beforeLineCount = 0;
    var afterLineCount = 0;
    for (final line in hunkLines) {
      if (!line.startsWith('+')) beforeLineCount += 1;
      if (!line.startsWith('-')) afterLineCount += 1;
    }
    result.add(
      '@@ -${beforeStart + 1},$beforeLineCount '
      '+${afterStart + 1},$afterLineCount @@',
    );
    result.addAll(hunkLines);
    hunkLines.clear();
    diffStart = -1;
  }

  for (var i = 0; i < maxLen; i++) {
    final beforeLine = i < beforeCount ? before[window.beforeStart + i] : null;
    final afterLine = i < afterCount ? after[window.afterStart + i] : null;
    if (beforeLine == afterLine) {
      flush();
      continue;
    }
    if (diffStart < 0) diffStart = i;
    if (beforeLine != null) hunkLines.add('-$beforeLine');
    if (afterLine != null) hunkLines.add('+$afterLine');
  }
  flush();
  return result.length == 2 ? const <String>[] : result;
}

({int beforeStart, int beforeEnd, int afterStart, int afterEnd})
_fallbackWindow(List<String> before, List<String> after) {
  var prefix = 0;
  while (prefix < before.length &&
      prefix < after.length &&
      before[prefix] == after[prefix]) {
    prefix += 1;
  }

  var suffix = 0;
  while (suffix < before.length - prefix &&
      suffix < after.length - prefix &&
      before[before.length - 1 - suffix] == after[after.length - 1 - suffix]) {
    suffix += 1;
  }

  return (
    beforeStart: prefix,
    beforeEnd: before.length - suffix,
    afterStart: prefix,
    afterEnd: after.length - suffix,
  );
}
