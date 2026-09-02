import 'dart:async';

import 'package:path/path.dart' as p;

import '../../model/ai_builtin_tool_contracts.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/lsp/lsp_client_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// 由 [AiLspClientService] 提供的多语言 LSP 代码分析工具。
class AiLspTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.lsp;

  @override
  List<String> get aliases => const <String>['LSP', 'Lsp'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();

    final operation = AiToolUtils.readString(args['operation']);
    final filePath = AiToolUtils.readFirstString(args, const <String>[
      'filePath',
      'file_path',
    ]);

    if (operation.isEmpty || filePath.isEmpty) {
      return AiToolUtils.invalidResult(
        'LSP',
        'operation and filePath (or file_path) are required.',
      );
    }
    if (!aiLspToolOperations.contains(operation)) {
      return AiToolUtils.invalidResult(
        'LSP',
        'Unsupported LSP operation "$operation".',
      );
    }

    final resolvedPath = AiToolUtils.resolvePathForContext(context, filePath);
    final boundaryError = await AiToolUtils.validatePathWithinWorkingDirectory(
      context: context,
      toolName: 'LSP',
      path: resolvedPath,
    );
    if (boundaryError != null) return boundaryError;
    final line = AiToolUtils.readInt(args['line']);
    final character = AiToolUtils.readInt(args['character']);
    if (line == null || line <= 0 || character == null || character <= 0) {
      return AiToolUtils.invalidResult(
        'LSP',
        'line and character must be positive 1-based integers.',
      );
    }
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
        command: 'LSP $operation',
        output: rendered,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: p.dirname(resolvedPath),
      );
    } catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'LSP $operation',
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
      final pathLabel = uri.isEmpty
          ? 'line $line'
          : '${aiLspUriToPath(uri)}:$line';
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
      final location = _callHierarchyLocation(item);
      buffer.writeln(
        '  [${location.kind}] ${location.name} '
        '(${location.path}:${location.line})',
      );
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
      final location = _callHierarchyLocation(target);
      buffer.writeln(
        '  [${location.kind}] ${location.name} '
        '(${location.path}:${location.line})',
      );
    }
    return buffer.toString().trimRight();
  }

  ({Object name, String kind, String path, int line}) _callHierarchyLocation(
    Map<String, Object?> item,
  ) {
    final range = item['range'] as Map<String, Object?>?;
    final start = range?['start'] as Map<String, Object?>?;
    return (
      name: item['name'] ?? '?',
      kind: _symbolKindName(item['kind'] as int? ?? 0),
      path: aiLspUriToPath(item['uri'] as String? ?? ''),
      line: ((start?['line'] as int?) ?? 0) + 1,
    );
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
