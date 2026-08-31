const String kCsvLineEnding = '\r\n';

const Set<String> _spreadsheetFormulaPrefixes = <String>{
  '=',
  '+',
  '-',
  '@',
  '\t',
  '\r',
};

String encodeCsvCell(
  Object? value, {
  bool alwaysQuote = false,
  bool protectSpreadsheetFormulas = true,
}) {
  var text = value?.toString() ?? '';
  if (protectSpreadsheetFormulas && value is String) {
    final candidate = text.trimLeft();
    if (candidate.isNotEmpty &&
        _spreadsheetFormulaPrefixes.contains(candidate[0])) {
      text = "'$text";
    }
  }
  final needsQuote =
      alwaysQuote ||
      text.contains(',') ||
      text.contains('"') ||
      text.contains('\r') ||
      text.contains('\n');
  if (!needsQuote) return text;
  return '"${text.replaceAll('"', '""')}"';
}

String encodeCsvRow(
  Iterable<Object?> values, {
  bool alwaysQuote = false,
  bool protectSpreadsheetFormulas = true,
}) {
  return values
      .map(
        (value) => encodeCsvCell(
          value,
          alwaysQuote: alwaysQuote,
          protectSpreadsheetFormulas: protectSpreadsheetFormulas,
        ),
      )
      .join(',');
}

String encodeCsvRows(
  Iterable<Iterable<Object?>> rows, {
  bool alwaysQuote = false,
  bool protectSpreadsheetFormulas = true,
  String lineEnding = kCsvLineEnding,
}) {
  return rows
      .map(
        (row) => encodeCsvRow(
          row,
          alwaysQuote: alwaysQuote,
          protectSpreadsheetFormulas: protectSpreadsheetFormulas,
        ),
      )
      .join(lineEnding);
}
