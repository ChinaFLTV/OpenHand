import '../model/workflow_definition.dart';

class WorkflowCurlEntry {
  const WorkflowCurlEntry({required this.key, required this.value});

  final String key;
  final String value;
}

class WorkflowCurlImport {
  const WorkflowCurlImport({
    required this.method,
    required this.url,
    required this.headers,
    required this.queryParameters,
    required this.bodyFormat,
    required this.body,
    required this.bodyEntries,
    required this.verifySsl,
  });

  final String method;
  final String url;
  final List<WorkflowCurlEntry> headers;
  final List<WorkflowCurlEntry> queryParameters;
  final WorkflowHttpBodyFormat bodyFormat;
  final String body;
  final List<WorkflowCurlEntry> bodyEntries;
  final bool verifySsl;
}

WorkflowCurlImport parseWorkflowCurl(String command) {
  final arguments = _tokenizeCurl(command.trim());
  final executable = arguments.isEmpty
      ? ''
      : arguments.first.toLowerCase().split('/').last;
  if (executable != 'curl' && executable != 'curl.exe') {
    throw const FormatException('请输入以 curl 开头的完整命令。');
  }

  var method = '';
  var url = '';
  var bodyFormat = WorkflowHttpBodyFormat.none;
  var body = '';
  var hasRequestBody = false;
  var dataInQuery = false;
  var verifySsl = true;
  final headers = <WorkflowCurlEntry>[];
  final bodyEntries = <WorkflowCurlEntry>[];

  String nextValue(int index, String option) {
    if (index + 1 >= arguments.length) {
      throw FormatException('$option 缺少参数值。');
    }
    return arguments[index + 1];
  }

  for (var index = 1; index < arguments.length; index++) {
    final argument = arguments[index];
    final longOption = argument.startsWith('--') && argument.contains('=')
        ? argument.substring(0, argument.indexOf('='))
        : argument;
    final inlineValue = argument.startsWith('--') && argument.contains('=')
        ? argument.substring(argument.indexOf('=') + 1)
        : null;

    if (longOption == '--request' || argument == '-X') {
      method = (inlineValue ?? nextValue(index, argument)).toUpperCase();
      if (inlineValue == null) index += 1;
      continue;
    }
    if (argument.startsWith('-X') && argument.length > 2) {
      method = argument.substring(2).toUpperCase();
      continue;
    }
    if (longOption == '--header' || argument == '-H') {
      final value = inlineValue ?? nextValue(index, argument);
      if (inlineValue == null) index += 1;
      _addHeader(headers, value);
      continue;
    }
    if (argument.startsWith('-H') && argument.length > 2) {
      _addHeader(headers, argument.substring(2));
      continue;
    }
    if (longOption == '--url') {
      url = inlineValue ?? nextValue(index, argument);
      if (inlineValue == null) index += 1;
      continue;
    }
    if (const <String>{
          '--data',
          '--data-raw',
          '--data-binary',
        }.contains(longOption) ||
        argument == '-d') {
      final value = inlineValue ?? nextValue(index, argument);
      if (inlineValue == null) index += 1;
      body = body.isEmpty ? value : '$body&$value';
      bodyFormat = WorkflowHttpBodyFormat.text;
      hasRequestBody = true;
      continue;
    }
    if (argument.startsWith('-d') && argument.length > 2) {
      final value = argument.substring(2);
      body = body.isEmpty ? value : '$body&$value';
      bodyFormat = WorkflowHttpBodyFormat.text;
      hasRequestBody = true;
      continue;
    }
    if (longOption == '--json') {
      body = inlineValue ?? nextValue(index, argument);
      if (inlineValue == null) index += 1;
      bodyFormat = WorkflowHttpBodyFormat.json;
      hasRequestBody = true;
      _addHeaderIfMissing(headers, 'Content-Type', 'application/json');
      _addHeaderIfMissing(headers, 'Accept', 'application/json');
      continue;
    }
    if (longOption == '--form' || argument == '-F') {
      final value = inlineValue ?? nextValue(index, argument);
      if (inlineValue == null) index += 1;
      bodyEntries.add(_parsePair(value, option: argument));
      bodyFormat = WorkflowHttpBodyFormat.formData;
      hasRequestBody = true;
      continue;
    }
    if (argument.startsWith('-F') && argument.length > 2) {
      bodyEntries.add(
        _parsePair(argument.substring(2), option: argument.substring(0, 2)),
      );
      bodyFormat = WorkflowHttpBodyFormat.formData;
      hasRequestBody = true;
      continue;
    }
    if (longOption == '--data-urlencode') {
      final value = inlineValue ?? nextValue(index, argument);
      if (inlineValue == null) index += 1;
      bodyEntries.add(_parsePair(value, option: longOption));
      bodyFormat = WorkflowHttpBodyFormat.formUrlEncoded;
      hasRequestBody = true;
      continue;
    }
    if (argument == '-G' || argument == '--get') {
      method = 'GET';
      dataInQuery = true;
      continue;
    }
    if (argument == '-k' || argument == '--insecure') {
      verifySsl = false;
      continue;
    }
    if (argument == '-I' || argument == '--head') {
      method = 'HEAD';
      continue;
    }
    if (!argument.startsWith('-') &&
        (argument.startsWith('http://') || argument.startsWith('https://'))) {
      url = argument;
    }
  }

  final parsedUrl = Uri.tryParse(url);
  if (parsedUrl == null ||
      !const <String>{'http', 'https'}.contains(parsedUrl.scheme) ||
      parsedUrl.host.isEmpty) {
    throw const FormatException('cURL 命令缺少有效的 HTTP 或 HTTPS 地址。');
  }
  method = method.isEmpty ? (hasRequestBody ? 'POST' : 'GET') : method;
  if (!const <String>{
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
    'HEAD',
  }.contains(method)) {
    throw FormatException('暂不支持 $method 请求方式。');
  }
  if (method == 'HEAD' || method == 'GET' && !dataInQuery) {
    bodyFormat = WorkflowHttpBodyFormat.none;
    body = '';
    bodyEntries.clear();
  } else if (bodyFormat == WorkflowHttpBodyFormat.text &&
      headers.any(
        (entry) =>
            entry.key.toLowerCase() == 'content-type' &&
            entry.value.toLowerCase().contains('application/json'),
      )) {
    bodyFormat = WorkflowHttpBodyFormat.json;
  }

  final queryParameters = <WorkflowCurlEntry>[
    for (final entry in parsedUrl.queryParametersAll.entries)
      WorkflowCurlEntry(key: entry.key, value: entry.value.join(',')),
    if (dataInQuery) ..._queryEntries(body, bodyEntries),
  ];
  if (dataInQuery) {
    bodyFormat = WorkflowHttpBodyFormat.none;
    body = '';
    bodyEntries.clear();
  }
  final cleanUrl = parsedUrl
      .replace(queryParameters: const <String, String>{})
      .toString();
  return WorkflowCurlImport(
    method: method,
    url: cleanUrl,
    headers: List<WorkflowCurlEntry>.unmodifiable(headers),
    queryParameters: List<WorkflowCurlEntry>.unmodifiable(queryParameters),
    bodyFormat: bodyFormat,
    body: body,
    bodyEntries: List<WorkflowCurlEntry>.unmodifiable(bodyEntries),
    verifySsl: verifySsl,
  );
}

List<WorkflowCurlEntry> _queryEntries(
  String body,
  List<WorkflowCurlEntry> bodyEntries,
) {
  final entries = <WorkflowCurlEntry>[...bodyEntries];
  if (body.isEmpty) return entries;
  for (final pair in body.split('&')) {
    if (pair.isEmpty) continue;
    final separator = pair.indexOf('=');
    final rawKey = separator < 0 ? pair : pair.substring(0, separator);
    final rawValue = separator < 0 ? '' : pair.substring(separator + 1);
    if (rawKey.isEmpty) continue;
    entries.add(
      WorkflowCurlEntry(
        key: Uri.decodeQueryComponent(rawKey),
        value: Uri.decodeQueryComponent(rawValue),
      ),
    );
  }
  return entries;
}

List<String> _tokenizeCurl(String command) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  String? quote;
  var escaped = false;

  void flush() {
    if (buffer.isEmpty) return;
    tokens.add(buffer.toString());
    buffer.clear();
  }

  for (var index = 0; index < command.length; index++) {
    final character = command[index];
    if (escaped) {
      if (character != '\n' && character != '\r') buffer.write(character);
      escaped = false;
      continue;
    }
    if (character == r'\' && quote != "'") {
      escaped = true;
      continue;
    }
    if (quote != null) {
      if (character == quote) {
        quote = null;
      } else {
        buffer.write(character);
      }
      continue;
    }
    if (character == "'" || character == '"') {
      quote = character;
      continue;
    }
    if (RegExp(r'\s').hasMatch(character)) {
      flush();
      continue;
    }
    buffer.write(character);
  }
  if (quote != null) throw const FormatException('cURL 命令包含未闭合的引号。');
  if (escaped) buffer.write(r'\');
  flush();
  return tokens;
}

void _addHeader(List<WorkflowCurlEntry> headers, String source) {
  final separator = source.indexOf(':');
  if (separator <= 0) throw const FormatException('cURL 请求头格式无效。');
  final key = source.substring(0, separator).trim();
  final value = source.substring(separator + 1).trim();
  if (key.isEmpty) throw const FormatException('cURL 请求头名称不能为空。');
  final existingIndex = headers.indexWhere(
    (entry) => entry.key.toLowerCase() == key.toLowerCase(),
  );
  final entry = WorkflowCurlEntry(key: key, value: value);
  if (existingIndex < 0) {
    headers.add(entry);
  } else {
    headers[existingIndex] = entry;
  }
}

void _addHeaderIfMissing(
  List<WorkflowCurlEntry> headers,
  String key,
  String value,
) {
  if (headers.any((entry) => entry.key.toLowerCase() == key.toLowerCase())) {
    return;
  }
  headers.add(WorkflowCurlEntry(key: key, value: value));
}

WorkflowCurlEntry _parsePair(String source, {required String option}) {
  final separator = source.indexOf('=');
  if (separator <= 0) throw FormatException('$option 的键值格式无效。');
  return WorkflowCurlEntry(
    key: source.substring(0, separator).trim(),
    value: source.substring(separator + 1),
  );
}
