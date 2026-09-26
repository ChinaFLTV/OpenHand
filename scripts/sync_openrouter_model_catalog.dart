import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _modelsUrl = 'https://openrouter.ai/api/v1/models';
const _responseMaxBytes = 32 * 1024 * 1024;
const _responseIdleTimeout = Duration(seconds: 30);
const _responseTotalTimeout = Duration(minutes: 2);

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(
      '用法：dart run scripts/sync_openrouter_model_catalog.dart [--check] [--input=本地快照.json]',
    );
    return;
  }
  final unknownArguments = arguments.where(
    (value) => value != '--check' && !value.startsWith('--input='),
  );
  if (unknownArguments.isNotEmpty) {
    stderr.writeln('不支持的参数：${unknownArguments.join(' ')}');
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final baselineFile = File(
    '${root.path}/lib/features/ai/model/openrouter_exact_model_catalog.dart',
  );
  final outputFile = File(
    '${root.path}/lib/features/ai/model/openrouter_latest_model_catalog.dart',
  );
  final baselineEntries = await _readGeneratedEntries(baselineFile);
  final latestEntries = await _readGeneratedEntries(outputFile);

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final inputs = arguments
        .where((value) => value.startsWith('--input='))
        .toList();
    if (inputs.length > 1) {
      throw const FormatException('只能指定一个本地快照。');
    }
    final String body;
    if (inputs.isNotEmpty) {
      final file = File(inputs.single.substring('--input='.length));
      if (await file.length() > _responseMaxBytes) {
        throw const FormatException('本地快照超过 32 MiB 上限。');
      }
      body = await file.readAsString();
    } else {
      final request = await client.getUrl(Uri.parse(_modelsUrl));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'OpenHand model catalog',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        stderr.writeln('模型目录请求失败：HTTP ${response.statusCode}');
        exitCode = 1;
        return;
      }
      body = await _readResponseBody(response);
    }
    final payload = jsonDecode(body);
    if (payload is! Map || payload['data'] is! List) {
      throw const FormatException('模型目录缺少 data 数组。');
    }
    final models =
        (payload['data'] as List<Object?>)
            .whereType<Map<Object?, Object?>>()
            .map((value) => value.map((key, value) => MapEntry('$key', value)))
            .toList()
          ..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    if (models.length != (payload['data'] as List).length ||
        models.isEmpty ||
        models.any((model) => _string(model['id']) == null)) {
      throw const FormatException('模型目录为空或缺少模型标识。');
    }
    final ids = models.map((model) => model['id']).toSet();
    if (ids.length != models.length) {
      throw const FormatException('模型目录包含重复标识。');
    }
    final generated = <File, String>{};
    for (final entry in <(File, String, Map<String, String>, bool)>[
      (baselineFile, 'openRouterExactModelProfiles', baselineEntries, true),
      (outputFile, 'openRouterLatestModelProfiles', latestEntries, false),
    ]) {
      generated[entry.$1] = await _formatDart(
        _renderCatalog(
          models
              .where(
                (model) => baselineEntries.containsKey(model['id']) == entry.$4,
              )
              .toList(),
          preservedEntries: entry.$3,
          variableName: entry.$2,
        ),
        root: root,
      );
    }
    if (arguments.contains('--check')) {
      for (final entry in generated.entries) {
        if (!await entry.key.exists() ||
            await entry.key.readAsString() != entry.value) {
          stderr.writeln('OpenRouter 模型目录不是最新版本：${entry.key.path}');
          exitCode = 1;
        }
      }
      if (exitCode == 0) stdout.writeln('OpenRouter 模型目录已是最新版本。');
      return;
    }
    for (final entry in generated.entries) {
      await entry.key.writeAsString(entry.value);
    }
    stdout.writeln('已更新 ${models.length} 个在线模型，并保留历史型号。');
  } on TimeoutException {
    stderr.writeln('模型目录请求超时。');
    exitCode = 1;
  } on IOException catch (error) {
    stderr.writeln('模型目录读取失败：$error');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('模型目录数据格式错误：$error');
    exitCode = 1;
  } finally {
    client.close(force: true);
  }
}

Future<String> _readResponseBody(HttpClientResponse response) async {
  if (response.contentLength > _responseMaxBytes) {
    throw const FormatException('模型目录响应超过 32 MiB 上限。');
  }
  return _collectResponseBody(response).timeout(_responseTotalTimeout);
}

Future<String> _collectResponseBody(HttpClientResponse response) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in response.timeout(_responseIdleTimeout)) {
    if (chunk.length > _responseMaxBytes - bytes.length) {
      throw const FormatException('模型目录响应超过 32 MiB 上限。');
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}

String _renderCatalog(
  List<Map<String, Object?>> models, {
  required Map<String, String> preservedEntries,
  required String variableName,
}) {
  final buffer = StringBuffer()
    ..writeln("import 'ai_model_config.dart';")
    ..writeln("import 'openrouter_model_profile_mapper.dart';")
    ..writeln()
    ..writeln('/// 由 `scripts/sync_openrouter_model_catalog.dart` 生成。')
    ..writeln('///')
    ..writeln('/// 更新在线型号，保留历史型号；原始字段通过统一映射器转换，价格仅适用于 OpenRouter。')
    ..writeln('final Map<String, AiModelProfile> $variableName =')
    ..writeln('    OpenRouterModelProfiles(<String, Object>{');
  final entries = <String, String>{...preservedEntries};
  for (final model in models) {
    final entry = StringBuffer();
    _renderModel(entry, model);
    entries[_string(model['id'])!] = entry.toString();
  }
  final ids = entries.keys.toList()..sort();
  for (final id in ids) {
    buffer.write(entries[id]);
  }
  return (buffer..writeln('});')).toString();
}

Future<Map<String, String>> _readGeneratedEntries(File outputFile) async {
  if (!await outputFile.exists()) return <String, String>{};
  final source = await outputFile.readAsString();
  final matches = RegExp(
    r'^  "([^"]+)":\s[\s\S]*?(?=^  "[^"]+":\s|^}\)?;)',
    multiLine: true,
  ).allMatches(source);
  return <String, String>{
    for (final match in matches) match.group(1)!: match.group(0)!,
  };
}

void _renderModel(StringBuffer buffer, Map<String, Object?> model) {
  buffer.writeln(
    '  ${_dartString(_string(model['id'])!)}: const ${_dartValue(model)},',
  );
}

Future<String> _formatDart(String source, {required Directory root}) async {
  // 在项目内格式化，沿用 pubspec 的语言版本与格式规则。
  final tempDirectory = await Directory(
    '${root.path}/.dart_tool',
  ).createTemp('openhand_model_catalog_');
  final tempFile = File('${tempDirectory.path}/catalog.dart');
  try {
    await tempFile.writeAsString(source);
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'format',
      tempFile.path,
    ]);
    if (result.exitCode != 0) {
      throw FormatException('目录格式化失败：${result.stderr}');
    }
    return await tempFile.readAsString();
  } finally {
    await tempDirectory.delete(recursive: true);
  }
}

String _dartValue(Object? value) {
  if (value == null) return 'null';
  if (value is String) return _dartString(value);
  if (value is bool) return '$value';
  if (value is num) return value.toString();
  if (value is List) return '[${value.map(_dartValue).join(', ')}]';
  if (value is Map) {
    final entries = value.entries
        .map(
          (entry) =>
              '${_dartString('${entry.key}')}: ${_dartValue(entry.value)}',
        )
        .join(', ');
    return '<String, Object?>{$entries}';
  }
  throw FormatException('不支持的字段类型：${value.runtimeType}');
}

String _dartString(String value) => jsonEncode(value).replaceAll(r'$', r'\$');

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
