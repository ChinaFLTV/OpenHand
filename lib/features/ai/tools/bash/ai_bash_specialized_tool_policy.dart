import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool_utils.dart';

class AiBashSpecializedToolPolicy {
  const AiBashSpecializedToolPolicy._();

  static AiBashSpecializedToolDecision? evaluate({
    required String command,
    required AiResolvedToolCatalog catalog,
  }) {
    final normalized = command.trim();
    if (normalized.isEmpty) return null;

    final editTools = _toolNamesForKinds(catalog, const <AiBuiltinToolKind>[
      AiBuiltinToolKind.edit,
      AiBuiltinToolKind.multiEdit,
      AiBuiltinToolKind.applyFileDiffs,
      AiBuiltinToolKind.write,
    ]);
    if (editTools.isNotEmpty && _looksLikeShellFileEdit(normalized)) {
      return AiBashSpecializedToolDecision(
        intent: 'file_edit',
        suggestedToolNames: editTools,
        reason:
            'The command looks like a shell-based file edit. Use the dedicated file-editing tool so OpenHand can validate exact text, confirmations, and mutation history.',
      );
    }

    final grepTool = _toolNameForKind(catalog, AiBuiltinToolKind.grep);
    if (grepTool != null &&
        _containsShellCommand(normalized, _searchCommands)) {
      return AiBashSpecializedToolDecision(
        intent: 'file_search',
        suggestedToolNames: <String>[grepTool],
        reason:
            'The command looks like file/content search. Use the dedicated Grep tool instead of shell grep/rg.',
      );
    }

    final globTool = _toolNameForKind(catalog, AiBuiltinToolKind.glob);
    if (globTool != null && _containsShellCommand(normalized, _globCommands)) {
      return AiBashSpecializedToolDecision(
        intent: 'file_discovery',
        suggestedToolNames: <String>[globTool],
        reason:
            'The command looks like file discovery. Use the dedicated Glob tool instead of shell find/fd.',
      );
    }

    final lsTool = _toolNameForKind(catalog, AiBuiltinToolKind.ls);
    if (lsTool != null && _containsShellCommand(normalized, _listCommands)) {
      return AiBashSpecializedToolDecision(
        intent: 'directory_listing',
        suggestedToolNames: <String>[lsTool],
        reason:
            'The command looks like directory listing. Use the dedicated LS tool instead of shell ls/tree.',
      );
    }

    final readTool = _toolNameForKind(catalog, AiBuiltinToolKind.read);
    if (readTool != null && _containsShellCommand(normalized, _readCommands)) {
      return AiBashSpecializedToolDecision(
        intent: 'file_read',
        suggestedToolNames: <String>[readTool],
        reason:
            'The command looks like file reading. Use the dedicated Read tool instead of shell cat/sed/head/tail.',
      );
    }

    final gitTool = _toolNameForKind(catalog, AiBuiltinToolKind.git);
    if (gitTool != null && _looksLikeReadOnlyGit(normalized)) {
      return AiBashSpecializedToolDecision(
        intent: 'git_read',
        suggestedToolNames: <String>[gitTool],
        reason:
            'The command looks like a read-only git query. Use the dedicated Git tool when it is available.',
      );
    }

    return null;
  }

  static const Set<String> _searchCommands = <String>{
    'grep',
    'egrep',
    'fgrep',
    'rg',
    'ag',
    'ack',
  };

  static const Set<String> _globCommands = <String>{
    'find',
    'fd',
    'fdfind',
    'locate',
  };

  static const Set<String> _listCommands = <String>{'ls', 'tree'};

  static const Set<String> _readCommands = <String>{
    'cat',
    'sed',
    'head',
    'tail',
    'less',
    'more',
    'nl',
  };

  static const Set<String> _readOnlyGitSubcommands = <String>{
    'status',
    'diff',
    'log',
    'show',
    'blame',
    'branch',
  };

  static bool _looksLikeShellFileEdit(String command) {
    final hasSed = _containsShellCommand(command, const <String>{'sed'});
    if (hasSed &&
        RegExp(
          r'(^|\s)(-[A-Za-z]*i[A-Za-z]*|--in-place)\b',
        ).hasMatch(command)) {
      return true;
    }
    final hasPerl = _containsShellCommand(command, const <String>{'perl'});
    if (hasPerl &&
        RegExp(r'(^|\s)-[A-Za-z]*p[A-Za-z]*i[A-Za-z]*\b').hasMatch(command)) {
      return true;
    }
    if (_containsShellCommand(command, const <String>{'tee'}) &&
        !RegExp(r'(^|\s)/dev/null(\s|$)').hasMatch(command)) {
      return true;
    }
    if (_containsShellCommand(command, const <String>{'cat'}) &&
        RegExp(r'(^|[^<])>\s*(?!/dev/null\b)\S+').hasMatch(command)) {
      return true;
    }
    return false;
  }

  static bool _looksLikeReadOnlyGit(String command) {
    final match = RegExp(
      r'(^|[;&()\{\}\n]|\|\||&&|\bdo\b|\bthen\b)\s*git\s+([A-Za-z0-9_-]+)\b',
    ).firstMatch(command);
    if (match == null) return false;
    final subcommand = match.group(2)?.toLowerCase();
    return subcommand != null && _readOnlyGitSubcommands.contains(subcommand);
  }

  static bool _containsShellCommand(String command, Set<String> names) {
    if (names.isEmpty) return false;
    final alternatives = names.map(RegExp.escape).join('|');
    return RegExp(
      '(^|[;&(){}\\n]|\\|\\||&&|\\bdo\\b|\\bthen\\b)\\s*'
      '(?:command\\s+|builtin\\s+)?(?:$alternatives)\\b',
      caseSensitive: false,
    ).hasMatch(command);
  }

  static String? _toolNameForKind(
    AiResolvedToolCatalog catalog,
    AiBuiltinToolKind kind,
  ) {
    for (final tool in catalog.toolsByName.values) {
      if (tool.source == AiRuntimeToolSource.builtin &&
          tool.builtinKind == kind) {
        return tool.name;
      }
    }
    return null;
  }

  static List<String> _toolNamesForKinds(
    AiResolvedToolCatalog catalog,
    List<AiBuiltinToolKind> kinds,
  ) {
    final names = <String>[];
    for (final kind in kinds) {
      final name = _toolNameForKind(catalog, kind);
      if (name != null) names.add(name);
    }
    return names;
  }
}

class AiBashSpecializedToolDecision {
  const AiBashSpecializedToolDecision({
    required this.intent,
    required this.suggestedToolNames,
    required this.reason,
  });

  final String intent;
  final List<String> suggestedToolNames;
  final String reason;

  AiToolExecutionResult toResult({
    required String command,
    required String workingDirectory,
  }) {
    final suggestion = suggestedToolNames.join(' / ');
    final message =
        'Bash command blocked by specialized-tool policy: $reason '
        'Suggested tool(s): $suggestion. Re-issue the action with the dedicated tool; use Bash only for shell-only commands such as tests, builds, package managers, or project scripts.';
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.invalidArguments,
      command: command.isEmpty ? 'Bash' : command,
      workingDirectory: workingDirectory.isEmpty
          ? AiToolUtils.defaultWorkingDirectory()
          : AiToolUtils.resolvePath(workingDirectory),
      stdout: '',
      stderr: message,
      durationMs: 0,
      resultText: 'status: invalid_arguments\nerror: $message',
      metadata: <String, Object?>{
        'bash_specialized_tool_policy_blocked': true,
        'bash_specialized_tool_intent': intent,
        'bash_specialized_tool_suggestions': suggestedToolNames,
      },
    );
  }
}
