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
      '用法：dart run scripts/sync_openrouter_model_catalog.dart [--check]',
    );
    return;
  }
  final unknownArguments = arguments.where((value) => value != '--check');
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
  final baselineIds =
      RegExp(r'^  "([^"]+)": const AiModelProfile\(', multiLine: true)
          .allMatches(await baselineFile.readAsString())
          .map((match) => match.group(1)!)
          .toSet();

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.getUrl(Uri.parse(_modelsUrl));
    request.headers.set(HttpHeaders.userAgentHeader, 'OpenHand model catalog');
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      stderr.writeln('模型目录请求失败：HTTP ${response.statusCode}');
      exitCode = 1;
      return;
    }
    final body = await _readResponseBody(response);
    final payload = jsonDecode(body) as Map<String, Object?>;
    final models =
        (payload['data'] as List<Object?>)
            .whereType<Map<Object?, Object?>>()
            .map((value) => value.map((key, value) => MapEntry('$key', value)))
            .where((model) => !baselineIds.contains(model['id']))
            .toList()
          ..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    final preservedEntries = await _readGeneratedEntries(outputFile);
    final generated = await _formatDart(
      _renderCatalog(models, preservedEntries: preservedEntries),
    );

    if (arguments.contains('--check')) {
      if (!await outputFile.exists() ||
          await outputFile.readAsString() != generated) {
        stderr.writeln('OpenRouter 增量模型目录不是最新版本。');
        exitCode = 1;
      } else {
        stdout.writeln('OpenRouter 增量模型目录已是最新版本。');
      }
      return;
    }
    await outputFile.writeAsString(generated);
    stdout.writeln('已同步 ${models.length} 个 OpenRouter 增量模型。');
  } on TimeoutException {
    stderr.writeln('模型目录请求超时。');
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
}) {
  final buffer = StringBuffer()
    ..writeln('// ignore_for_file: prefer_const_constructors')
    ..writeln()
    ..writeln("import 'ai_model_config.dart';")
    ..writeln()
    ..writeln('/// 由 `scripts/sync_openrouter_model_catalog.dart` 增量生成。')
    ..writeln('///')
    ..writeln('/// 仅补充全量基线目录中缺失的当前在线模型，不删除历史型号。')
    ..writeln(
      'final Map<String, AiModelProfile> openRouterLatestModelProfiles =',
    )
    ..writeln('    <String, AiModelProfile>{');
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
  return (buffer..writeln('};')).toString();
}

Future<Map<String, String>> _readGeneratedEntries(File outputFile) async {
  if (!await outputFile.exists()) return <String, String>{};
  final source = await outputFile.readAsString();
  final matches = RegExp(
    r'^  "([^"]+)": AiModelProfile\([\s\S]*?(?=^  "[^"]+": AiModelProfile\(|^};)',
    multiLine: true,
  ).allMatches(source);
  return <String, String>{
    for (final match in matches) match.group(1)!: match.group(0)!,
  };
}

void _renderModel(StringBuffer buffer, Map<String, Object?> model) {
  final id = _string(model['id'])!;
  final architecture = _map(model['architecture']);
  final inputModalities = _strings(architecture['input_modalities']);
  final outputModalities = _strings(architecture['output_modalities']);
  final modalities = <String>{...inputModalities, ...outputModalities}.toList()
    ..sort();
  final capabilities = outputModalities
      .where((value) => value != 'text' && value != 'file')
      .map((value) => '${value}Generation')
      .toList();
  final supportedParameters = _strings(model['supported_parameters']);
  final reasoning = _map(model['reasoning']);
  final supportedEfforts = id == 'x-ai/grok-4.5'
      ? <String>['high', 'medium', 'low', 'xhigh']
      : _strings(reasoning['supported_efforts']);
  final topProvider = _map(model['top_provider']);
  final pricing = _map(model['pricing']);
  final links = _map(model['links']);
  final defaultParameters = _map(model['default_parameters']);
  final hasReasoning =
      reasoning.isNotEmpty ||
      supportedParameters.contains('reasoning') ||
      supportedParameters.contains('include_reasoning');
  final isMultimodal = modalities.any((value) => value != 'text');
  final supportsAttachments = inputModalities.any((value) => value != 'text');

  buffer
    ..writeln('  ${_dartString(id)}: AiModelProfile(')
    ..writeln('    displayName: ${_dartString(_displayName(model))},');
  _writeString(buffer, 'description', _string(model['description']));
  if (isMultimodal) buffer.writeln('    isMultimodal: true,');
  if (supportsAttachments) buffer.writeln('    supportsAttachments: true,');
  if (modalities.isNotEmpty) {
    buffer.writeln('    supportedModalities: <AiModelModality>{');
    for (final modality in modalities) {
      buffer.writeln('      AiModelModality.$modality,');
    }
    buffer.writeln('    },');
  }
  _writeInt(buffer, 'maxContextLength', model['context_length']);
  _writeInt(buffer, 'maxOutputLength', topProvider['max_completion_tokens']);
  if (hasReasoning && topProvider['max_completion_tokens'] is num) {
    _writeInt(
      buffer,
      'maxThinkingLength',
      topProvider['max_completion_tokens'],
    );
  }
  if (reasoning['mandatory'] == true || reasoning['default_enabled'] == true) {
    buffer.writeln('    thinkingEnabled: true,');
  }
  if (supportedEfforts.isNotEmpty) {
    buffer
      ..writeln('    reasoningEffortControlEnabled: true,')
      ..writeln(
        '    reasoningEffort: ${_dartString(_string(reasoning['default_effort']) ?? supportedEfforts.first)},',
      )
      ..writeln(
        '    reasoningEffortOptions: AiReasoningEffortOption.standardValues(',
      )
      ..writeln('      const <String>${_dartValue(supportedEfforts)},')
      ..writeln('    ),');
  }
  if (capabilities.isNotEmpty) {
    buffer.writeln('    capabilities: <AiModelCapability>{');
    for (final capability in capabilities) {
      buffer.writeln('      AiModelCapability.$capability,');
    }
    buffer.writeln('    },');
  }
  _writePrice(buffer, 'inputUsdPer1M', pricing['prompt']);
  _writePrice(buffer, 'outputUsdPer1M', pricing['completion']);
  _writePrice(buffer, 'cacheReadUsdPer1M', pricing['input_cache_read']);
  _writePrice(buffer, 'cacheWriteUsdPer1M', pricing['input_cache_write']);
  _writeString(buffer, 'canonicalSlug', _string(model['canonical_slug']));
  _writeString(buffer, 'huggingFaceId', _string(model['hugging_face_id']));
  _writeInt(buffer, 'created', model['created']);
  if (architecture.isNotEmpty) {
    buffer.writeln('    architecture: AiModelArchitectureMetadata(');
    _writeString(
      buffer,
      'modality',
      _string(architecture['modality']),
      indent: 6,
    );
    _writeStringList(buffer, 'inputModalities', inputModalities, indent: 6);
    _writeStringList(buffer, 'outputModalities', outputModalities, indent: 6);
    _writeString(
      buffer,
      'tokenizer',
      _string(architecture['tokenizer']),
      indent: 6,
    );
    _writeString(
      buffer,
      'instructType',
      _string(architecture['instruct_type']),
      indent: 6,
    );
    buffer.writeln('    ),');
  }
  _writeStringList(buffer, 'supportedParameters', supportedParameters);
  if (defaultParameters.isNotEmpty) {
    buffer.writeln('    defaultParameters: ${_dartValue(defaultParameters)},');
  }
  _writeStringList(
    buffer,
    'supportedVoices',
    _strings(model['supported_voices']),
  );
  _writeString(buffer, 'knowledgeCutoff', _string(model['knowledge_cutoff']));
  _writeString(buffer, 'expirationDate', _string(model['expiration_date']));
  if (links.isNotEmpty) {
    buffer.writeln('    links: AiModelLinksMetadata(');
    _writeString(buffer, 'details', _string(links['details']), indent: 6);
    buffer.writeln('    ),');
  }
  buffer.writeln('  ),');
}

String _displayName(Map<String, Object?> model) {
  final name = _string(model['name']) ?? _string(model['id'])!;
  final separator = name.indexOf(': ');
  return separator < 0 ? name : name.substring(separator + 2);
}

Future<String> _formatDart(String source) async {
  final tempDirectory = await Directory.systemTemp.createTemp(
    'openhand_model_catalog_',
  );
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

void _writeString(
  StringBuffer buffer,
  String name,
  String? value, {
  int indent = 4,
}) {
  if (value == null || value.isEmpty) return;
  buffer.writeln('${' ' * indent}$name: ${_dartString(value)},');
}

void _writeInt(StringBuffer buffer, String name, Object? value) {
  if (value is num && value > 0) buffer.writeln('    $name: ${value.toInt()},');
}

void _writePrice(StringBuffer buffer, String name, Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null || parsed < 0) return;
  buffer.writeln('    $name: ${_number(parsed * 1000000)},');
}

void _writeStringList(
  StringBuffer buffer,
  String name,
  List<String> values, {
  int indent = 4,
}) {
  if (values.isEmpty) return;
  buffer.writeln('${' ' * indent}$name: <String>${_dartValue(values)},');
}

String _dartValue(Object? value) {
  if (value == null) return 'null';
  if (value is String) return _dartString(value);
  if (value is bool) return '$value';
  if (value is num) return _number(value.toDouble());
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

String _number(double value) => value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(10).replaceFirst(RegExp(r'0+$'), '');

String? _string(Object? value) => value is String ? value : null;

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : <String>[];

Map<String, Object?> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry('$key', value))
    : <String, Object?>{};
