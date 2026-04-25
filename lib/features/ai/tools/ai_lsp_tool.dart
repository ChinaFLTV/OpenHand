import 'dart:async';

import 'package:path/path.dart' as p;

import '../../../app/support/silent_log.dart';
import '../service/ai_bash_tool_service.dart';
import '../service/ai_tool_runtime_service.dart';
import '../service/lsp_client_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

/// Multi-language LSP code intelligence tool backed by [AiLspClientService].
class AiLspTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.lsp;

  @override
  List<String> get aliases => const <String>['Lsp'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();

    final operation = '${args['operation'] ?? ''}'.trim();
    final filePath = '${args['file_path'] ?? ''}'.trim();

    if (operation.isEmpty || filePath.isEmpty) {
      return AiToolUtils.invalidResult(
        'Lsp',
        'operation and file_path are required.',
      );
    }

    final resolvedPath = AiToolUtils.resolvePath(filePath);
    final line = AiToolUtils.readInt(args['line']) ?? 1;
    final character = AiToolUtils.readInt(args['character']) ?? 1;
    final language = context.metadata['language']?.toString();

    try {
      final rawResult = await AiLspClientService.instance.request(
        operation: operation,
        filePath: resolvedPath,
        line: line,
        character: character,
        language: language,
      );
      final rendered = _renderOperationResult(operation, rawResult);
      return AiToolUtils.simpleSuccessResult(
        command: 'Lsp $operation',
        output: rendered,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: p.dirname(resolvedPath),
      );
    } catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'Lsp $operation',
        workingDirectory: p.dirname(resolvedPath),
        stdout: '',
        stderr: '$error',
        durationMs: startedAt.elapsedMilliseconds,
        resultText:
            'status: failed\nerror: LSP operation "$operation" failed: $error\n'
            'Fallback: use Grep/Glob/Read for code intelligence.',
      );
    }
  }

  static Future<void> disposeAll() => AiLspClientService.instance.disposeAll();

  String _renderOperationResult(String operation, Object? result) {
    switch (operation) {
      case 'goToDefinition':
        return _formatLocationResult(
          AiLspClientService.parseLocations(result),
          'Definition',
        );
      case 'findReferences':
        return _formatLocationResult(
          AiLspClientService.parseLocations(result),
          'References',
        );
      case 'hover':
        return _formatHoverResult(AiLspClientService.parseHover(result));
      case 'documentSymbol':
        return _formatSymbolResult(
          AiLspClientService.parseDocumentSymbols(result),
          'Document Symbols',
        );
      case 'workspaceSymbol':
        return _formatRawSymbolResult(result, 'Workspace Symbols');
      case 'goToImplementation':
        return _formatLocationResult(
          AiLspClientService.parseLocations(result),
          'Implementation',
        );
      case 'prepareCallHierarchy':
        return _formatCallHierarchyItems(result);
      case 'incomingCalls':
        return _formatCallResults(result, 'Incoming Calls');
      case 'outgoingCalls':
        return _formatCallResults(result, 'Outgoing Calls');
      default:
        return '$result';
    }
  }

  String _formatLocationResult(List<AiLspLocation> locations, String label) {
    if (locations.isEmpty) {
      return '($label: no results)';
    }
    final buffer = StringBuffer('$label (${locations.length} result(s)):\n');
    for (final location in locations) {
      buffer.writeln(
        '  ${location.filePath}:${location.line}:${location.character}',
      );
    }
    return buffer.toString().trimRight();
  }

  String _formatHoverResult(AiLspHoverResult? hover) {
    if (hover == null) {
      return '(hover: no information at this position)';
    }
    return hover.renderedText.trim().isEmpty
        ? '(hover: no content)'
        : hover.renderedText;
  }

  String _formatSymbolResult(List<AiLspDocumentSymbol> symbols, String label) {
    if (symbols.isEmpty) {
      return '($label: no results)';
    }
    final buffer = StringBuffer('$label (${symbols.length} symbol(s)):\n');
    for (final symbol in symbols) {
      _writeSymbol(buffer, symbol, 1);
    }
    return buffer.toString().trimRight();
  }

  void _writeSymbol(
    StringBuffer buffer,
    AiLspDocumentSymbol symbol,
    int depth,
  ) {
    final indent = '  ' * depth;
    final detail = symbol.detail?.trim().isNotEmpty == true
        ? ' — ${symbol.detail!.trim()}'
        : '';
    buffer.writeln(
      '$indent[${_symbolKindName(symbol.kind)}] ${symbol.name}$detail '
      '(line ${symbol.range.start.line})',
    );
    for (final child in symbol.children) {
      _writeSymbol(buffer, child, depth + 1);
    }
  }

  String _formatRawSymbolResult(Object? result, String label) {
    if (result is! List || result.isEmpty) {
      return '($label: no results)';
    }
    final buffer = StringBuffer('$label (${result.length} symbol(s)):\n');
    for (final item in result) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final name = item['name'] ?? '?';
      final kind = _symbolKindName(item['kind'] as int? ?? 0);
      final detail = '${item['detail'] ?? ''}'.trim();
      final location = item['location'] as Map<String, Object?>?;
      final range = location?['range'] as Map<String, Object?>?;
      final start = range?['start'] as Map<String, Object?>?;
      final uri = location?['uri'] as String? ?? '';
      final line = ((start?['line'] as int?) ?? 0) + 1;
      final detailLabel = detail.isEmpty ? '' : ' — $detail';
      final pathLabel = uri.isEmpty ? 'line $line' : '${_uriToPath(uri)}:$line';
      buffer.writeln('  [$kind] $name$detailLabel ($pathLabel)');
    }
    return buffer.toString().trimRight();
  }

  String _formatCallHierarchyItems(Object? result) {
    if (result is! List || result.isEmpty) {
      return '(no call hierarchy item found at this position)';
    }
    final buffer = StringBuffer('Call Hierarchy Items:\n');
    for (final item in result) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final name = item['name'] ?? '?';
      final kind = _symbolKindName(item['kind'] as int? ?? 0);
      final uri = item['uri'] as String? ?? '';
      final range = item['range'] as Map<String, Object?>?;
      final start = range?['start'] as Map<String, Object?>?;
      final line = ((start?['line'] as int?) ?? 0) + 1;
      buffer.writeln('  [$kind] $name (${_uriToPath(uri)}:$line)');
    }
    return buffer.toString().trimRight();
  }

  String _formatCallResults(Object? result, String label) {
    if (result is! List || result.isEmpty) {
      return '($label: none)';
    }
    final buffer = StringBuffer('$label (${result.length}):\n');
    for (final item in result) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      final target =
          item['from'] as Map<String, Object?>? ??
          item['to'] as Map<String, Object?>?;
      if (target == null) {
        continue;
      }
      final name = target['name'] ?? '?';
      final kind = _symbolKindName(target['kind'] as int? ?? 0);
      final uri = target['uri'] as String? ?? '';
      final range = target['range'] as Map<String, Object?>?;
      final start = range?['start'] as Map<String, Object?>?;
      final line = ((start?['line'] as int?) ?? 0) + 1;
      buffer.writeln('  [$kind] $name (${_uriToPath(uri)}:$line)');
    }
    return buffer.toString().trimRight();
  }

  String _uriToPath(String uri) {
    try {
      final parsed = Uri.parse(uri);
      if (parsed.scheme == 'file') {
        return parsed.toFilePath();
      }
    } catch (error, stack) {
      silentLog('ai_lsp_tool', 'parse file uri', error, stack);
    }
    return uri;
  }

  String _symbolKindName(int kind) {
    const names = <int, String>{
      1: 'File',
      2: 'Module',
      3: 'Namespace',
      4: 'Package',
      5: 'Class',
      6: 'Method',
      7: 'Property',
      8: 'Field',
      9: 'Constructor',
      10: 'Enum',
      11: 'Interface',
      12: 'Function',
      13: 'Variable',
      14: 'Constant',
      22: 'EnumMember',
      23: 'Struct',
      25: 'Operator',
      26: 'TypeParameter',
    };
    return names[kind] ?? 'Symbol($kind)';
  }
}
