import 'dart:convert';

String parseBashToolCommandFromArguments(String rawArguments) {
  return _readToolArgumentValue(
    rawArguments,
    preferredKeys: const <String>['cmd', 'command'],
  );
}

String parseBashToolWorkingDirectoryFromArguments(String rawArguments) {
  return _readToolArgumentValue(
    rawArguments,
    preferredKeys: const <String>['working_directory', 'cwd'],
  );
}

String _readToolArgumentValue(
  String rawArguments, {
  required List<String> preferredKeys,
}) {
  final trimmed = rawArguments.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      final argumentsMap = Map<String, Object?>.from(decoded);
      for (final key in preferredKeys) {
        final value = argumentsMap[key];
        final normalized = '${value ?? ''}'.trim();
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    }
  } catch (_) {}
  return _readPartialJsonStringField(trimmed, preferredKeys);
}

String _readPartialJsonStringField(String source, List<String> preferredKeys) {
  for (final key in preferredKeys) {
    final value = _readSinglePartialJsonStringField(source, key);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _readSinglePartialJsonStringField(String source, String key) {
  final quotedKey = '"$key"';
  final keyIndex = source.indexOf(quotedKey);
  if (keyIndex == -1) {
    return '';
  }
  var cursor = keyIndex + quotedKey.length;
  while (cursor < source.length &&
      _isAsciiWhitespace(source.codeUnitAt(cursor))) {
    cursor += 1;
  }
  if (cursor >= source.length || source.codeUnitAt(cursor) != 0x3A) {
    return '';
  }
  cursor += 1;
  while (cursor < source.length &&
      _isAsciiWhitespace(source.codeUnitAt(cursor))) {
    cursor += 1;
  }
  if (cursor >= source.length || source.codeUnitAt(cursor) != 0x22) {
    return '';
  }
  cursor += 1;

  final buffer = StringBuffer();
  while (cursor < source.length) {
    final codeUnit = source.codeUnitAt(cursor);
    if (codeUnit == 0x22) {
      return buffer.toString().trim();
    }
    if (codeUnit == 0x5C) {
      cursor += 1;
      if (cursor >= source.length) {
        buffer.write(r'\');
        break;
      }
      final escapedCodeUnit = source.codeUnitAt(cursor);
      switch (escapedCodeUnit) {
        case 0x22:
          buffer.write('"');
        case 0x5C:
          buffer.write(r'\');
        case 0x2F:
          buffer.write('/');
        case 0x62:
          buffer.write('\b');
        case 0x66:
          buffer.write('\f');
        case 0x6E:
          buffer.write('\n');
        case 0x72:
          buffer.write('\r');
        case 0x74:
          buffer.write('\t');
        case 0x75:
          if (cursor + 4 < source.length) {
            final hex = source.substring(cursor + 1, cursor + 5);
            final parsed = int.tryParse(hex, radix: 16);
            if (parsed != null) {
              buffer.write(String.fromCharCode(parsed));
              cursor += 4;
              break;
            }
          }
          buffer.write(r'\u');
        default:
          buffer.writeCharCode(escapedCodeUnit);
      }
      cursor += 1;
      continue;
    }
    buffer.writeCharCode(codeUnit);
    cursor += 1;
  }
  return buffer.toString().trim();
}

bool _isAsciiWhitespace(int codeUnit) {
  return codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D;
}
