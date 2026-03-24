import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../app/support/openhand_paths.dart';
import '../model/ai_deny_command_rule.dart';

enum BashToolExecutionStatus {
  success('success'),
  failed('failed'),
  cancelled('cancelled'),
  denied('denied'),
  rejected('rejected'),
  timedOut('timed_out'),
  invalidArguments('invalid_arguments');

  const BashToolExecutionStatus(this.storageValue);

  final String storageValue;
}

enum BashToolExecutionPhase { running, completed }

class BashCommandApprovalRequest {
  const BashCommandApprovalRequest({
    required this.command,
    required this.workingDirectory,
    required this.isWriteCommand,
  });

  final String command;
  final String workingDirectory;
  final bool isWriteCommand;
}

class BashToolExecutionUpdate {
  const BashToolExecutionUpdate({
    required this.phase,
    required this.command,
    required this.workingDirectory,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    this.exitCode,
  });

  final BashToolExecutionPhase phase;
  final String command;
  final String workingDirectory;
  final String stdout;
  final String stderr;
  final int durationMs;
  final int? exitCode;
}

class BashToolExecutionResult {
  const BashToolExecutionResult({
    required this.status,
    required this.command,
    required this.workingDirectory,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    this.exitCode,
    this.matchedRuleId,
    this.matchedRulePattern,
    this.isWriteCommand = false,
    this.writeAnalysisReason = '',
  });

  final BashToolExecutionStatus status;
  final String command;
  final String workingDirectory;
  final String stdout;
  final String stderr;
  final int durationMs;
  final int? exitCode;
  final String? matchedRuleId;
  final String? matchedRulePattern;
  final bool isWriteCommand;
  final String writeAnalysisReason;

  String toToolOutput() {
    final buffer = StringBuffer()
      ..writeln('status: ${status.storageValue}')
      ..writeln('command: $command')
      ..writeln('working_directory: $workingDirectory')
      ..writeln('duration_ms: $durationMs');
    if (exitCode != null) {
      buffer.writeln('exit_code: $exitCode');
    }
    if (matchedRuleId != null && matchedRulePattern != null) {
      buffer
        ..writeln('matched_rule_id: $matchedRuleId')
        ..writeln('matched_rule_pattern: $matchedRulePattern');
    }
    if (stdout.trim().isNotEmpty) {
      buffer
        ..writeln('stdout:')
        ..writeln(stdout.trimRight());
    }
    if (stderr.trim().isNotEmpty) {
      buffer
        ..writeln('stderr:')
        ..writeln(stderr.trimRight());
    }
    return buffer.toString().trim();
  }
}

class _WriteConfirmationOutcome {
  const _WriteConfirmationOutcome._({
    required this.approved,
    required this.cancelled,
  });

  const _WriteConfirmationOutcome.approved()
    : this._(approved: true, cancelled: false);

  const _WriteConfirmationOutcome.rejected()
    : this._(approved: false, cancelled: false);

  const _WriteConfirmationOutcome.cancelled()
    : this._(approved: false, cancelled: true);

  final bool approved;
  final bool cancelled;
}

class AiBashToolService {
  static const int defaultTimeoutMs = 30000;
  static const int _writeConfirmationTimeoutMs = 300000;
  static const int _maxCapturedCharacters = 32000;
  static const int _fastPathWriteAnalysisThreshold = 512;

  Future<BashToolExecutionResult> execute({
    required String command,
    String? workingDirectory,
    required List<AiDenyCommandRule> denyRules,
    required bool requireWriteConfirmation,
    Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    void Function(BashToolExecutionUpdate update)? onUpdate,
    Future<void>? cancelSignal,
    int timeoutMs = defaultTimeoutMs,
  }) async {
    final normalizedCommand = command.trim();
    final normalizedWorkingDirectory = (workingDirectory ?? '').trim().isEmpty
        ? OpenHandPaths.applicationDirectoryPath()
        : OpenHandPaths.normalizePath(
            workingDirectory,
            defaultPath: OpenHandPaths.applicationDirectoryPath(),
          );
    if (normalizedCommand.isEmpty) {
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.invalidArguments,
        command: normalizedCommand,
        workingDirectory: normalizedWorkingDirectory,
        stdout: '',
        stderr: 'The bash tool requires a non-empty command.',
        durationMs: 0,
        writeAnalysisReason: 'empty command',
      );
    }

    final writeAnalysis = analyzeWriteCommand(normalizedCommand);

    for (final rule in denyRules) {
      if (rule.matches(normalizedCommand)) {
        return BashToolExecutionResult(
          status: BashToolExecutionStatus.denied,
          command: normalizedCommand,
          workingDirectory: normalizedWorkingDirectory,
          stdout: '',
          stderr:
              'The command was blocked because it matched a deny rule configured by the user.',
          durationMs: 0,
          matchedRuleId: rule.id,
          matchedRulePattern: rule.pattern,
          isWriteCommand: writeAnalysis.isWrite,
          writeAnalysisReason: writeAnalysis.reason,
        );
      }
    }
    final isWriteCommand = writeAnalysis.isWrite;
    if (requireWriteConfirmation && isWriteCommand) {
      late final _WriteConfirmationOutcome outcome;
      try {
        final approvalFuture =
            (confirmWriteCommand
                        ?.call(
                          BashCommandApprovalRequest(
                            command: normalizedCommand,
                            workingDirectory: normalizedWorkingDirectory,
                            isWriteCommand: true,
                          ),
                        )
                        .timeout(
                          const Duration(
                            milliseconds: _writeConfirmationTimeoutMs,
                          ),
                        ) ??
                    Future<bool>.value(false))
                .then<_WriteConfirmationOutcome>(
                  (approved) => approved
                      ? const _WriteConfirmationOutcome.approved()
                      : const _WriteConfirmationOutcome.rejected(),
                );
        if (cancelSignal == null) {
          outcome = await approvalFuture;
        } else {
          outcome = await Future.any<_WriteConfirmationOutcome>([
            approvalFuture,
            cancelSignal.then(
              (_) => const _WriteConfirmationOutcome.cancelled(),
            ),
          ]);
        }
      } on TimeoutException {
        return BashToolExecutionResult(
          status: BashToolExecutionStatus.rejected,
          command: normalizedCommand,
          workingDirectory: normalizedWorkingDirectory,
          stdout: '',
          stderr:
              'The command confirmation timed out before the user approved execution.',
          durationMs: 0,
          isWriteCommand: isWriteCommand,
          writeAnalysisReason: writeAnalysis.reason,
        );
      }
      if (outcome.cancelled) {
        return BashToolExecutionResult(
          status: BashToolExecutionStatus.cancelled,
          command: normalizedCommand,
          workingDirectory: normalizedWorkingDirectory,
          stdout: '',
          stderr:
              'The command execution was cancelled before confirmation completed.',
          durationMs: 0,
          isWriteCommand: isWriteCommand,
          writeAnalysisReason: writeAnalysis.reason,
        );
      }
      if (!outcome.approved) {
        return BashToolExecutionResult(
          status: BashToolExecutionStatus.rejected,
          command: normalizedCommand,
          workingDirectory: normalizedWorkingDirectory,
          stdout: '',
          stderr:
              'The command was rejected because write-command confirmation was not granted by the user.',
          durationMs: 0,
          isWriteCommand: isWriteCommand,
          writeAnalysisReason: writeAnalysis.reason,
        );
      }
    }

    final stopwatch = Stopwatch()..start();
    late final Process process;
    try {
      process = await _startProcess(
        normalizedCommand,
        normalizedWorkingDirectory,
      );
    } on ProcessException catch (error) {
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: normalizedCommand,
        workingDirectory: normalizedWorkingDirectory,
        stdout: '',
        stderr: error.message,
        durationMs: stopwatch.elapsedMilliseconds,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysis.reason,
      );
    }

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    var lastRunningEmitMs = -1;

    void emitUpdate({
      required BashToolExecutionPhase phase,
      bool force = false,
      int? exitCode,
    }) {
      if (onUpdate == null) {
        return;
      }
      final durationMs = stopwatch.elapsedMilliseconds;
      if (phase == BashToolExecutionPhase.running &&
          !force &&
          lastRunningEmitMs != -1 &&
          durationMs - lastRunningEmitMs < 160) {
        return;
      }
      if (phase == BashToolExecutionPhase.running) {
        lastRunningEmitMs = durationMs;
      }
      onUpdate(
        BashToolExecutionUpdate(
          phase: phase,
          command: normalizedCommand,
          workingDirectory: normalizedWorkingDirectory,
          stdout: stdoutBuffer.toString(),
          stderr: stderrBuffer.toString(),
          durationMs: durationMs,
          exitCode: exitCode,
        ),
      );
    }

    emitUpdate(phase: BashToolExecutionPhase.running, force: true);
    final progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      emitUpdate(phase: BashToolExecutionPhase.running, force: true);
    });
    final stdoutSubscription = process.stdout.transform(utf8.decoder).listen((
      chunk,
    ) {
      _appendChunk(stdoutBuffer, chunk);
      emitUpdate(phase: BashToolExecutionPhase.running);
    });
    final stderrSubscription = process.stderr.transform(utf8.decoder).listen((
      chunk,
    ) {
      _appendChunk(stderrBuffer, chunk);
      emitUpdate(phase: BashToolExecutionPhase.running);
    });

    int? exitCode;
    var cancelled = false;
    var timedOut = false;
    try {
      final waitForExit = process.exitCode.timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () async {
          timedOut = true;
          process.kill(ProcessSignal.sigkill);
          try {
            await process.exitCode.timeout(const Duration(seconds: 2));
          } catch (_) {
            // Ignore cleanup failures after forcing termination.
          }
          return -1;
        },
      );
      if (cancelSignal != null) {
        exitCode = await Future.any<int>([
          waitForExit,
          cancelSignal.then((_) async {
            cancelled = true;
            process.kill(ProcessSignal.sigkill);
            try {
              await process.exitCode.timeout(const Duration(seconds: 2));
            } catch (_) {
              // Ignore cleanup failures after forcing termination.
            }
            return -2;
          }),
        ]);
      } else {
        exitCode = await waitForExit;
      }
    } finally {
      progressTimer.cancel();
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      stopwatch.stop();
    }

    if (cancelled) {
      emitUpdate(
        phase: BashToolExecutionPhase.completed,
        force: true,
        exitCode: exitCode,
      );
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.cancelled,
        command: normalizedCommand,
        workingDirectory: normalizedWorkingDirectory,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString().isEmpty
            ? 'The command was cancelled by the user.'
            : stderrBuffer.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
        exitCode: exitCode,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysis.reason,
      );
    }

    if (timedOut) {
      emitUpdate(
        phase: BashToolExecutionPhase.completed,
        force: true,
        exitCode: exitCode,
      );
      return BashToolExecutionResult(
        status: BashToolExecutionStatus.timedOut,
        command: normalizedCommand,
        workingDirectory: normalizedWorkingDirectory,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString().isEmpty
            ? 'The command timed out before completion.'
            : stderrBuffer.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
        exitCode: exitCode,
        isWriteCommand: isWriteCommand,
        writeAnalysisReason: writeAnalysis.reason,
      );
    }

    emitUpdate(
      phase: BashToolExecutionPhase.completed,
      force: true,
      exitCode: exitCode,
    );
    return BashToolExecutionResult(
      status: exitCode == 0
          ? BashToolExecutionStatus.success
          : BashToolExecutionStatus.failed,
      command: normalizedCommand,
      workingDirectory: normalizedWorkingDirectory,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
      durationMs: stopwatch.elapsedMilliseconds,
      exitCode: exitCode,
      isWriteCommand: isWriteCommand,
      writeAnalysisReason: writeAnalysis.reason,
    );
  }

  Future<Process> _startProcess(String command, String workingDirectory) {
    if (Platform.isWindows) {
      return Process.start(
        'cmd',
        <String>['/c', command],
        workingDirectory: workingDirectory,
        runInShell: false,
      );
    }
    final shellExecutable = _resolveShellExecutable();
    return Process.start(
      shellExecutable,
      <String>['-lc', command],
      workingDirectory: workingDirectory,
      runInShell: false,
    );
  }

  String _resolveShellExecutable() {
    final environmentShell = Platform.environment['SHELL']?.trim() ?? '';
    if (environmentShell.isNotEmpty) {
      return environmentShell;
    }
    const shellCandidates = <String>['/bin/zsh', '/bin/bash', '/bin/sh'];
    for (final candidate in shellCandidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return '/bin/sh';
  }

  void _appendChunk(StringBuffer buffer, String chunk) {
    if (buffer.length >= _maxCapturedCharacters) {
      return;
    }
    final allowed = _maxCapturedCharacters - buffer.length;
    if (chunk.length <= allowed) {
      buffer.write(chunk);
      return;
    }
    buffer
      ..write(chunk.substring(0, allowed))
      ..write('\n...[output truncated]');
  }

  BashWriteAnalysis analyzeWriteCommand(String command) {
    final normalized = command.trim();
    if (normalized.isEmpty) {
      return const BashWriteAnalysis.readOnly('empty command');
    }
    final fastPath = _fastPathWriteAnalysis(normalized);
    if (fastPath != null) {
      return fastPath;
    }
    if (Platform.isWindows) {
      return _CmdWriteCommandAnalyzer(normalized).analyze();
    }
    return _ShellWriteCommandAnalyzer(normalized).analyze();
  }

  bool isLikelyWriteCommand(String command) {
    return analyzeWriteCommand(command).isWrite;
  }

  BashWriteAnalysis? _fastPathWriteAnalysis(String command) {
    if (command.length < _fastPathWriteAnalysisThreshold) {
      return null;
    }
    if (command.contains('<<')) {
      return const BashWriteAnalysis.write(
        'fast-path redirection or heredoc command',
      );
    }
    if (_containsPotentiallySafeRedirectionTarget(command)) {
      return null;
    }
    if (RegExp(r'(^|[;&|]\s*|\s)\d*(>|>>|>\||<>)\s+\S').hasMatch(command)) {
      return const BashWriteAnalysis.write(
        'fast-path redirection or heredoc command',
      );
    }
    return null;
  }

  bool _containsPotentiallySafeRedirectionTarget(String command) {
    return command.contains('/dev/null') ||
        command.contains('/dev/stdout') ||
        command.contains('/dev/stderr') ||
        command.contains('/dev/fd/') ||
        command.contains('/proc/self/fd/') ||
        command.contains('>&');
  }
}

class BashWriteAnalysis {
  const BashWriteAnalysis._({required this.isWrite, required this.reason});

  const BashWriteAnalysis.readOnly(String reason)
    : this._(isWrite: false, reason: reason);

  const BashWriteAnalysis.write(String reason)
    : this._(isWrite: true, reason: reason);

  final bool isWrite;
  final String reason;
}

enum _ShellTokenKind { word, separator, redirection }

class _ShellToken {
  const _ShellToken.word(
    this.text, {
    this.nestedCommands = const <String>[],
    this.hasDynamicExpansion = false,
  }) : kind = _ShellTokenKind.word;

  const _ShellToken.separator(this.text)
    : kind = _ShellTokenKind.separator,
      nestedCommands = const <String>[],
      hasDynamicExpansion = false;

  const _ShellToken.redirection(this.text)
    : kind = _ShellTokenKind.redirection,
      nestedCommands = const <String>[],
      hasDynamicExpansion = false;

  final _ShellTokenKind kind;
  final String text;
  final List<String> nestedCommands;
  final bool hasDynamicExpansion;
}

class _TokenReadResult {
  const _TokenReadResult({required this.token, required this.nextIndex});

  final _ShellToken token;
  final int nextIndex;
}

class _ShellWriteCommandAnalyzer {
  _ShellWriteCommandAnalyzer(this.source);

  static const Set<String> _outputRedirections = <String>{
    '>',
    '>>',
    '>|',
    '>&',
    '<>',
  };

  static const Set<String> _controlKeywords = <String>{
    '!',
    'if',
    'then',
    'elif',
    'else',
    'do',
    'done',
    'fi',
    'esac',
    'in',
  };

  static const Set<String> _nonCommandKeywords = <String>{
    'for',
    'function',
    'case',
    'select',
  };

  static const Set<String> _readOnlyCommands = <String>{
    'pwd',
    'ls',
    'cat',
    'head',
    'tail',
    'less',
    'more',
    'grep',
    'egrep',
    'fgrep',
    'rg',
    'ag',
    'fd',
    'readlink',
    'realpath',
    'stat',
    'file',
    'du',
    'df',
    'uname',
    'whoami',
    'id',
    'printenv',
    'date',
    'which',
    'whereis',
    'basename',
    'dirname',
    'sort',
    'uniq',
    'cut',
    'tr',
    'wc',
    'comm',
    'join',
    'column',
    'printf',
    'echo',
    'true',
    'false',
    'sleep',
    'history',
  };

  static const Set<String> _alwaysWriteCommands = <String>{
    'rm',
    'mv',
    'cp',
    'touch',
    'mkdir',
    'rmdir',
    'chmod',
    'chown',
    'chgrp',
    'truncate',
    'install',
    'ln',
    'dd',
    'patch',
    'apply_patch',
    'rsync',
    'scp',
    'sftp',
    'wget',
    'kubectl',
    'helm',
    'terraform',
    'ansible-playbook',
    'docker',
    'podman',
    'make',
    'cmake',
    'ninja',
    'gradle',
    'mvn',
    'npm',
    'pnpm',
    'yarn',
    'bun',
    'cargo',
    'go',
    'flutter',
    'dart',
    'pip',
    'pip3',
    'uv',
    'poetry',
    'composer',
  };

  static const Set<String> _wrapperCommands = <String>{
    'sudo',
    'env',
    'command',
    'builtin',
    'noglob',
    'stdbuf',
    'chronic',
    'nice',
    'nohup',
    'time',
    'timeout',
  };

  static const Set<String> _shellCommands = <String>{
    'bash',
    'sh',
    'zsh',
    'ksh',
    'fish',
  };

  static const Set<String> _interpreterCommands = <String>{
    'python',
    'python3',
    'node',
    'ruby',
    'perl',
    'lua',
    'php',
    'deno',
    'awk',
  };

  final String source;

  BashWriteAnalysis analyze() {
    final tokens = _tokenize(source);
    if (tokens.isEmpty) {
      return const BashWriteAnalysis.readOnly('empty command');
    }

    for (final token in tokens) {
      for (final nestedCommand in token.nestedCommands) {
        final nestedAnalysis = _ShellWriteCommandAnalyzer(
          nestedCommand,
        ).analyze();
        if (nestedAnalysis.isWrite) {
          return BashWriteAnalysis.write(
            'nested shell expansion: ${nestedAnalysis.reason}',
          );
        }
      }
    }

    final segments = _splitSegments(tokens);
    for (final segment in segments) {
      final analysis = _analyzeSegment(segment);
      if (analysis.isWrite) {
        return analysis;
      }
    }

    return const BashWriteAnalysis.readOnly(
      'all parsed shell commands are read-only',
    );
  }

  List<_ShellToken> _tokenize(String input) {
    final tokens = <_ShellToken>[];
    var index = 0;
    while (index < input.length) {
      final char = input[index];
      if (_isWhitespace(char)) {
        if (char == '\n') {
          tokens.add(const _ShellToken.separator('\n'));
        }
        index++;
        continue;
      }
      if (char == '#') {
        index = _skipComment(input, index);
        continue;
      }
      final processSubstitution = _readProcessSubstitution(input, index);
      if (processSubstitution != null) {
        tokens.add(processSubstitution.token);
        index = processSubstitution.nextIndex;
        continue;
      }
      final separator = _readSeparator(input, index);
      if (separator != null) {
        tokens.add(separator.token);
        index = separator.nextIndex;
        continue;
      }
      final redirection = _readRedirection(input, index);
      if (redirection != null) {
        tokens.add(redirection.token);
        index = redirection.nextIndex;
        continue;
      }
      final word = _readWord(input, index);
      tokens.add(word.token);
      index = word.nextIndex;
    }
    return tokens;
  }

  List<List<_ShellToken>> _splitSegments(List<_ShellToken> tokens) {
    final segments = <List<_ShellToken>>[];
    var current = <_ShellToken>[];
    for (final token in tokens) {
      if (token.kind == _ShellTokenKind.separator) {
        if (current.isNotEmpty) {
          segments.add(current);
          current = <_ShellToken>[];
        }
        continue;
      }
      current.add(token);
    }
    if (current.isNotEmpty) {
      segments.add(current);
    }
    return segments;
  }

  BashWriteAnalysis _analyzeSegment(List<_ShellToken> segment) {
    final words = <_ShellToken>[];
    var skipRedirectionTarget = false;
    for (var index = 0; index < segment.length; index++) {
      final token = segment[index];
      if (token.kind == _ShellTokenKind.redirection) {
        skipRedirectionTarget = true;
        final target =
            index + 1 < segment.length &&
                segment[index + 1].kind == _ShellTokenKind.word
            ? segment[index + 1]
            : null;
        final redirectionAnalysis = _analyzeRedirection(token, target);
        if (redirectionAnalysis != null) {
          return redirectionAnalysis;
        }
        continue;
      }
      if (token.kind != _ShellTokenKind.word) {
        continue;
      }
      if (skipRedirectionTarget) {
        skipRedirectionTarget = false;
        continue;
      }
      words.add(token);
    }
    return _analyzeWords(words);
  }

  BashWriteAnalysis? _analyzeRedirection(
    _ShellToken operatorToken,
    _ShellToken? target,
  ) {
    final normalizedOperator = _normalizeRedirection(operatorToken.text);
    if (!_outputRedirections.contains(normalizedOperator)) {
      return null;
    }
    if (_isNonPersistentOutputTarget(target)) {
      return null;
    }
    if (normalizedOperator == '>&' && _isFileDescriptorTarget(target)) {
      return null;
    }
    return BashWriteAnalysis.write(
      'output redirection operator ${operatorToken.text}',
    );
  }

  BashWriteAnalysis _analyzeWords(List<_ShellToken> words) {
    if (words.isEmpty) {
      return const BashWriteAnalysis.readOnly(
        'segment without executable words',
      );
    }
    if (_nonCommandKeywords.contains(words.first.text)) {
      return BashWriteAnalysis.readOnly(
        'shell control keyword ${words.first.text}',
      );
    }

    var start = 0;
    while (start < words.length &&
        _controlKeywords.contains(words[start].text)) {
      start++;
    }
    while (start < words.length && _looksLikeAssignment(words[start].text)) {
      start++;
    }
    if (start >= words.length) {
      return const BashWriteAnalysis.readOnly(
        'only shell control tokens or assignments',
      );
    }

    final invocation = words.sublist(start);
    if (invocation.first.hasDynamicExpansion) {
      return BashWriteAnalysis.write(
        'dynamic command name ${invocation.first.text}',
      );
    }
    final commandName = _basename(invocation.first.text);

    if (_wrapperCommands.contains(commandName)) {
      return _analyzeWrapperCommand(commandName, invocation);
    }
    if (_shellCommands.contains(commandName)) {
      return _analyzeShellInvocation(commandName, invocation);
    }
    if (_interpreterCommands.contains(commandName)) {
      return _analyzeInterpreterInvocation(commandName, invocation);
    }
    if (_alwaysWriteCommands.contains(commandName)) {
      return BashWriteAnalysis.write('mutating command $commandName');
    }
    if (commandName == 'git') {
      return _analyzeGitInvocation(invocation);
    }
    if (commandName == 'find') {
      return _analyzeFindInvocation(invocation);
    }
    if (commandName == 'xargs') {
      return _analyzeXargsInvocation(invocation);
    }
    if (commandName == 'sed') {
      return _analyzeSedInvocation(invocation);
    }
    if (commandName == 'tar') {
      return _analyzeTarInvocation(invocation);
    }
    if (commandName == 'tee') {
      return _analyzeTeeInvocation(invocation);
    }
    if (commandName == 'curl') {
      return _analyzeCurlInvocation(invocation);
    }
    if (_readOnlyCommands.contains(commandName)) {
      return BashWriteAnalysis.readOnly('read-only command $commandName');
    }
    if (_looksLikeScriptPath(invocation.first.text)) {
      return BashWriteAnalysis.write(
        'script or executable path ${invocation.first.text}',
      );
    }
    return BashWriteAnalysis.write(
      'unclassified external command $commandName',
    );
  }

  BashWriteAnalysis _analyzeWrapperCommand(
    String commandName,
    List<_ShellToken> invocation,
  ) {
    final innerWords = switch (commandName) {
      'env' => _unwrapEnv(invocation),
      'timeout' => _unwrapTimeout(invocation),
      'sudo' => _unwrapSudo(invocation),
      _ => _unwrapGenericWrapper(invocation),
    };
    if (innerWords.isEmpty) {
      return BashWriteAnalysis.readOnly('$commandName without inner command');
    }
    return _analyzeWords(innerWords);
  }

  BashWriteAnalysis _analyzeShellInvocation(
    String commandName,
    List<_ShellToken> invocation,
  ) {
    final scriptToken = _findInlineScriptToken(invocation, const <String>{
      '-c',
    });
    if (scriptToken != null) {
      if (scriptToken.hasDynamicExpansion) {
        return BashWriteAnalysis.write(
          'dynamic inline shell script for $commandName',
        );
      }
      final nested = _ShellWriteCommandAnalyzer(scriptToken.text).analyze();
      if (nested.isWrite) {
        return BashWriteAnalysis.write(
          'inline shell script for $commandName: ${nested.reason}',
        );
      }
      return BashWriteAnalysis.readOnly(
        'inline shell script for $commandName is read-only',
      );
    }
    final scriptPath = _firstNonOption(invocation.sublist(1));
    if (scriptPath != null) {
      return BashWriteAnalysis.write(
        'shell script execution ${scriptPath.text}',
      );
    }
    return BashWriteAnalysis.write('interactive shell invocation $commandName');
  }

  BashWriteAnalysis _analyzeInterpreterInvocation(
    String commandName,
    List<_ShellToken> invocation,
  ) {
    if (commandName == 'awk') {
      return BashWriteAnalysis.write('awk programs can write files and state');
    }
    final inlineScriptToken = _findInlineScriptToken(invocation, const <String>{
      '-c',
      '-e',
      '--eval',
    });
    if (inlineScriptToken != null) {
      return BashWriteAnalysis.write(
        'inline interpreter code for $commandName',
      );
    }
    if (_firstNonOption(invocation.sublist(1)) != null) {
      return BashWriteAnalysis.write(
        'interpreter or script execution via $commandName',
      );
    }
    return BashWriteAnalysis.readOnly('$commandName without program input');
  }

  BashWriteAnalysis _analyzeGitInvocation(List<_ShellToken> invocation) {
    final subcommandIndex = _findGitSubcommandIndex(invocation);
    if (subcommandIndex == -1) {
      return const BashWriteAnalysis.readOnly('git without subcommand');
    }
    final subcommand = invocation[subcommandIndex].text;
    final args = invocation.sublist(subcommandIndex + 1);
    switch (subcommand) {
      case 'status':
      case 'diff':
      case 'log':
      case 'show':
      case 'grep':
      case 'rev-parse':
      case 'describe':
      case 'blame':
        return BashWriteAnalysis.readOnly('git $subcommand is read-only');
      case 'branch':
        if (_gitBranchIsReadOnly(args)) {
          return const BashWriteAnalysis.readOnly('git branch listing');
        }
        return const BashWriteAnalysis.write('git branch mutation');
      case 'tag':
        if (_gitTagIsReadOnly(args)) {
          return const BashWriteAnalysis.readOnly('git tag listing');
        }
        return const BashWriteAnalysis.write('git tag mutation');
      case 'stash':
        if (_gitStashIsReadOnly(args)) {
          return const BashWriteAnalysis.readOnly('git stash listing');
        }
        return const BashWriteAnalysis.write('git stash mutation');
      default:
        return BashWriteAnalysis.write(
          'git $subcommand mutates repository state',
        );
    }
  }

  BashWriteAnalysis _analyzeFindInvocation(List<_ShellToken> invocation) {
    final args = invocation.sublist(1);
    for (var index = 0; index < args.length; index++) {
      final value = args[index].text;
      if (value == '-delete' ||
          value == '-fprint' ||
          value == '-fprintf' ||
          value == '-fls') {
        return BashWriteAnalysis.write('find action $value');
      }
      if (value == '-exec' ||
          value == '-execdir' ||
          value == '-ok' ||
          value == '-okdir') {
        final nestedWords = <_ShellToken>[];
        for (
          var nestedIndex = index + 1;
          nestedIndex < args.length;
          nestedIndex++
        ) {
          final nestedValue = args[nestedIndex].text;
          if (nestedValue == ';' ||
              nestedValue == '+' ||
              nestedValue == r'\;') {
            break;
          }
          nestedWords.add(args[nestedIndex]);
        }
        if (nestedWords.isEmpty) {
          return BashWriteAnalysis.write(
            'find $value without explicit command',
          );
        }
        final nestedAnalysis = _analyzeWords(nestedWords);
        if (nestedAnalysis.isWrite) {
          return BashWriteAnalysis.write(
            'find $value launches mutating command: ${nestedAnalysis.reason}',
          );
        }
      }
    }
    return const BashWriteAnalysis.readOnly('find predicate scan only');
  }

  BashWriteAnalysis _analyzeXargsInvocation(List<_ShellToken> invocation) {
    var index = 1;
    while (index < invocation.length &&
        _looksLikeOption(invocation[index].text)) {
      final option = invocation[index].text;
      index++;
      if (option == '-I' ||
          option == '-i' ||
          option == '-L' ||
          option == '-l' ||
          option == '-n' ||
          option == '-P' ||
          option == '-s' ||
          option == '-E' ||
          option == '--replace' ||
          option == '--max-lines' ||
          option == '--max-args' ||
          option == '--max-procs' ||
          option == '--delimiter' ||
          option == '--eof') {
        if (index < invocation.length) {
          index++;
        }
      }
    }
    if (index >= invocation.length) {
      return const BashWriteAnalysis.readOnly(
        'xargs without explicit command defaults to echo',
      );
    }
    return _analyzeWords(invocation.sublist(index));
  }

  BashWriteAnalysis _analyzeSedInvocation(List<_ShellToken> invocation) {
    for (final token in invocation.skip(1)) {
      final value = token.text;
      if (value == '-i' || value.startsWith('-i') || value == '--in-place') {
        return const BashWriteAnalysis.write('sed in-place edit');
      }
    }
    return const BashWriteAnalysis.readOnly('sed stream transform only');
  }

  BashWriteAnalysis _analyzeTarInvocation(List<_ShellToken> invocation) {
    final args = invocation
        .skip(1)
        .map((token) => token.text)
        .toList(growable: false);
    final flags = StringBuffer();
    for (final arg in args) {
      if (arg.startsWith('--')) {
        if (arg == '--list') {
          continue;
        }
        if (arg == '--extract' ||
            arg == '--create' ||
            arg == '--append' ||
            arg == '--update' ||
            arg == '--delete' ||
            arg == '--concatenate') {
          return BashWriteAnalysis.write('tar option $arg');
        }
        continue;
      }
      if (arg.startsWith('-')) {
        flags.write(arg.substring(1));
        continue;
      }
      if (!arg.startsWith('-') && RegExp(r'^[ctxruA]').hasMatch(arg)) {
        flags.write(arg);
      }
    }
    final normalizedFlags = flags.toString();
    if (normalizedFlags.contains('x') ||
        normalizedFlags.contains('c') ||
        normalizedFlags.contains('r') ||
        normalizedFlags.contains('u') ||
        normalizedFlags.contains('A')) {
      return BashWriteAnalysis.write('tar flags $normalizedFlags');
    }
    return const BashWriteAnalysis.readOnly('tar listing or inspection');
  }

  BashWriteAnalysis _analyzeTeeInvocation(List<_ShellToken> invocation) {
    final hasFileTarget = invocation
        .skip(1)
        .any((token) => !_looksLikeOption(token.text));
    if (hasFileTarget) {
      return const BashWriteAnalysis.write('tee writes to file targets');
    }
    return const BashWriteAnalysis.readOnly('tee without file targets');
  }

  BashWriteAnalysis _analyzeCurlInvocation(List<_ShellToken> invocation) {
    for (var index = 1; index < invocation.length; index++) {
      final value = invocation[index].text;
      if (value == '-o' ||
          value == '-O' ||
          value == '-T' ||
          value == '--output' ||
          value == '--remote-name' ||
          value == '--upload-file' ||
          value == '--output-dir') {
        return BashWriteAnalysis.write('curl option $value');
      }
      if (value.startsWith('--output=') || value.startsWith('--upload-file=')) {
        return BashWriteAnalysis.write('curl option ${value.split('=').first}');
      }
    }
    return const BashWriteAnalysis.readOnly('curl without local output target');
  }

  List<_ShellToken> _unwrapEnv(List<_ShellToken> invocation) {
    var index = 1;
    while (index < invocation.length) {
      final value = invocation[index].text;
      if (value == '--') {
        index++;
        break;
      }
      if (_looksLikeOption(value)) {
        index++;
        if (value == '-u' || value == '--unset') {
          index++;
        }
        continue;
      }
      if (_looksLikeAssignment(value)) {
        index++;
        continue;
      }
      break;
    }
    return invocation.sublist(index);
  }

  List<_ShellToken> _unwrapTimeout(List<_ShellToken> invocation) {
    var index = 1;
    while (index < invocation.length &&
        _looksLikeOption(invocation[index].text)) {
      final option = invocation[index].text;
      index++;
      if (option == '-k' ||
          option == '--kill-after' ||
          option == '-s' ||
          option == '--signal') {
        if (index < invocation.length) {
          index++;
        }
      }
    }
    if (index < invocation.length) {
      index++;
    }
    return invocation.sublist(index);
  }

  List<_ShellToken> _unwrapSudo(List<_ShellToken> invocation) {
    var index = 1;
    while (index < invocation.length &&
        _looksLikeOption(invocation[index].text)) {
      final option = invocation[index].text;
      index++;
      if (option == '-u' ||
          option == '-g' ||
          option == '-h' ||
          option == '-p' ||
          option == '-C' ||
          option == '-T' ||
          option == '-r' ||
          option == '-t') {
        if (index < invocation.length) {
          index++;
        }
      }
    }
    return invocation.sublist(index);
  }

  List<_ShellToken> _unwrapGenericWrapper(List<_ShellToken> invocation) {
    var index = 1;
    while (index < invocation.length &&
        _looksLikeOption(invocation[index].text)) {
      index++;
    }
    return invocation.sublist(index);
  }

  _ShellToken? _findInlineScriptToken(
    List<_ShellToken> invocation,
    Set<String> supportedFlags,
  ) {
    for (var index = 1; index < invocation.length; index++) {
      final value = invocation[index].text;
      if (value == '--') {
        break;
      }
      if (supportedFlags.contains(value) && index + 1 < invocation.length) {
        return invocation[index + 1];
      }
      if (value.startsWith('-') &&
          !value.startsWith('--') &&
          value.length > 2 &&
          supportedFlags.any((flag) => value.contains(flag.substring(1)))) {
        if (index + 1 < invocation.length) {
          return invocation[index + 1];
        }
      }
    }
    return null;
  }

  _ShellToken? _firstNonOption(List<_ShellToken> tokens) {
    for (final token in tokens) {
      if (!_looksLikeOption(token.text)) {
        return token;
      }
    }
    return null;
  }

  int _findGitSubcommandIndex(List<_ShellToken> invocation) {
    var index = 1;
    while (index < invocation.length) {
      final value = invocation[index].text;
      if (value == '--') {
        return index + 1 < invocation.length ? index + 1 : -1;
      }
      if (!_looksLikeOption(value)) {
        return index;
      }
      index++;
      if (value == '-C' ||
          value == '--git-dir' ||
          value == '--work-tree' ||
          value == '--namespace' ||
          value == '-c' ||
          value == '--config-env') {
        index++;
      }
    }
    return -1;
  }

  bool _gitBranchIsReadOnly(List<_ShellToken> args) {
    if (args.isEmpty) {
      return true;
    }
    for (final arg in args) {
      final value = arg.text;
      if (value == '-d' ||
          value == '-D' ||
          value == '-m' ||
          value == '-M' ||
          value == '-c' ||
          value == '-C' ||
          value == '--delete' ||
          value == '--move' ||
          value == '--copy' ||
          value == '--set-upstream-to' ||
          value == '--unset-upstream') {
        return false;
      }
      if (!_looksLikeOption(value)) {
        return false;
      }
    }
    return true;
  }

  bool _gitTagIsReadOnly(List<_ShellToken> args) {
    if (args.isEmpty) {
      return true;
    }
    for (final arg in args) {
      final value = arg.text;
      if (value == '-d' ||
          value == '--delete' ||
          value == '-m' ||
          value == '-F') {
        return false;
      }
      if (!_looksLikeOption(value)) {
        return false;
      }
    }
    return true;
  }

  bool _gitStashIsReadOnly(List<_ShellToken> args) {
    if (args.isEmpty) {
      return false;
    }
    final subcommand = args.first.text;
    return subcommand == 'list' || subcommand == 'show';
  }

  _TokenReadResult? _readProcessSubstitution(String input, int index) {
    if (index + 1 >= input.length) {
      return null;
    }
    final leader = input[index];
    if ((leader != '<' && leader != '>') || input[index + 1] != '(') {
      return null;
    }
    final balanced = _readBalancedCommand(input, index + 2);
    return _TokenReadResult(
      token: _ShellToken.word(
        input.substring(index, balanced.nextIndex),
        nestedCommands: <String>[balanced.content],
      ),
      nextIndex: balanced.nextIndex,
    );
  }

  _TokenReadResult? _readSeparator(String input, int index) {
    for (final candidate in <String>[
      '&&',
      '||',
      ';',
      '|',
      '&',
      '(',
      ')',
      '{',
      '}',
    ]) {
      if (input.startsWith(candidate, index)) {
        return _TokenReadResult(
          token: _ShellToken.separator(candidate),
          nextIndex: index + candidate.length,
        );
      }
    }
    return null;
  }

  _TokenReadResult? _readRedirection(String input, int index) {
    final start = index;
    var cursor = index;
    while (cursor < input.length && _isDigit(input[cursor])) {
      cursor++;
    }
    for (final operator in <String>[
      '<<-',
      '<<<',
      '>>',
      '<<',
      '>|',
      '<>',
      '>&',
      '<&',
      '>',
      '<',
    ]) {
      if (input.startsWith(operator, cursor)) {
        return _TokenReadResult(
          token: _ShellToken.redirection(
            input.substring(start, cursor + operator.length),
          ),
          nextIndex: cursor + operator.length,
        );
      }
    }
    return null;
  }

  _TokenReadResult _readWord(String input, int index) {
    final buffer = StringBuffer();
    final nestedCommands = <String>[];
    var hasDynamicExpansion = false;
    var cursor = index;

    while (cursor < input.length) {
      final char = input[cursor];
      if (_isWhitespace(char) ||
          _readSeparator(input, cursor) != null ||
          _readRedirection(input, cursor) != null) {
        break;
      }
      final processSubstitution = _readProcessSubstitution(input, cursor);
      if (processSubstitution != null) {
        buffer.write(processSubstitution.token.text);
        nestedCommands.addAll(processSubstitution.token.nestedCommands);
        cursor = processSubstitution.nextIndex;
        continue;
      }
      if (char == '\'') {
        final closing = input.indexOf('\'', cursor + 1);
        if (closing == -1) {
          buffer.write(input.substring(cursor + 1));
          cursor = input.length;
        } else {
          buffer.write(input.substring(cursor + 1, closing));
          cursor = closing + 1;
        }
        continue;
      }
      if (char == '"') {
        final quoted = _readDoubleQuoted(input, cursor);
        buffer.write(quoted.text);
        nestedCommands.addAll(quoted.nestedCommands);
        hasDynamicExpansion = hasDynamicExpansion || quoted.hasDynamicExpansion;
        cursor = quoted.nextIndex;
        continue;
      }
      if (char == '`') {
        final nested = _readBacktickCommand(input, cursor);
        buffer.write('`${nested.content}`');
        nestedCommands.add(nested.content);
        hasDynamicExpansion = true;
        cursor = nested.nextIndex;
        continue;
      }
      if (char == r'$') {
        if (cursor + 1 < input.length && input[cursor + 1] == '(') {
          final nested = _readBalancedCommand(input, cursor + 2);
          buffer.write(r'$(${nested.content})');
          nestedCommands.add(nested.content);
          hasDynamicExpansion = true;
          cursor = nested.nextIndex;
          continue;
        }
        if (cursor + 1 < input.length && input[cursor + 1] == '{') {
          final closing = input.indexOf('}', cursor + 2);
          if (closing == -1) {
            buffer.write(input.substring(cursor));
            hasDynamicExpansion = true;
            cursor = input.length;
          } else {
            buffer.write(input.substring(cursor, closing + 1));
            hasDynamicExpansion = true;
            cursor = closing + 1;
          }
          continue;
        }
        final variableMatch = RegExp(
          r'^\$[A-Za-z_][A-Za-z0-9_]*',
        ).matchAsPrefix(input.substring(cursor));
        if (variableMatch != null) {
          buffer.write(variableMatch.group(0));
          hasDynamicExpansion = true;
          cursor += variableMatch.group(0)!.length;
          continue;
        }
      }
      if (char == r'\') {
        if (cursor + 1 < input.length) {
          buffer.write(input[cursor + 1]);
          cursor += 2;
          continue;
        }
        cursor++;
        break;
      }
      buffer.write(char);
      cursor++;
    }

    return _TokenReadResult(
      token: _ShellToken.word(
        buffer.toString(),
        nestedCommands: nestedCommands,
        hasDynamicExpansion: hasDynamicExpansion,
      ),
      nextIndex: cursor,
    );
  }

  _QuotedReadResult _readDoubleQuoted(String input, int index) {
    final buffer = StringBuffer();
    final nestedCommands = <String>[];
    var hasDynamicExpansion = false;
    var cursor = index + 1;
    while (cursor < input.length) {
      final char = input[cursor];
      if (char == '"') {
        return _QuotedReadResult(
          text: buffer.toString(),
          nextIndex: cursor + 1,
          nestedCommands: nestedCommands,
          hasDynamicExpansion: hasDynamicExpansion,
        );
      }
      if (char == r'\') {
        if (cursor + 1 < input.length) {
          buffer.write(input[cursor + 1]);
          cursor += 2;
          continue;
        }
        cursor++;
        break;
      }
      if (char == '`') {
        final nested = _readBacktickCommand(input, cursor);
        buffer.write('`${nested.content}`');
        nestedCommands.add(nested.content);
        hasDynamicExpansion = true;
        cursor = nested.nextIndex;
        continue;
      }
      if (char == r'$') {
        if (cursor + 1 < input.length && input[cursor + 1] == '(') {
          final nested = _readBalancedCommand(input, cursor + 2);
          buffer.write(r'$(${nested.content})');
          nestedCommands.add(nested.content);
          hasDynamicExpansion = true;
          cursor = nested.nextIndex;
          continue;
        }
        if (cursor + 1 < input.length && input[cursor + 1] == '{') {
          final closing = input.indexOf('}', cursor + 2);
          if (closing == -1) {
            buffer.write(input.substring(cursor));
            hasDynamicExpansion = true;
            cursor = input.length;
          } else {
            buffer.write(input.substring(cursor, closing + 1));
            hasDynamicExpansion = true;
            cursor = closing + 1;
          }
          continue;
        }
        final variableMatch = RegExp(
          r'^\$[A-Za-z_][A-Za-z0-9_]*',
        ).matchAsPrefix(input.substring(cursor));
        if (variableMatch != null) {
          buffer.write(variableMatch.group(0));
          hasDynamicExpansion = true;
          cursor += variableMatch.group(0)!.length;
          continue;
        }
      }
      buffer.write(char);
      cursor++;
    }
    return _QuotedReadResult(
      text: buffer.toString(),
      nextIndex: cursor,
      nestedCommands: nestedCommands,
      hasDynamicExpansion: hasDynamicExpansion,
    );
  }

  _BalancedReadResult _readBacktickCommand(String input, int index) {
    final buffer = StringBuffer();
    var cursor = index + 1;
    while (cursor < input.length) {
      final char = input[cursor];
      if (char == '`') {
        return _BalancedReadResult(
          content: buffer.toString(),
          nextIndex: cursor + 1,
        );
      }
      if (char == r'\' && cursor + 1 < input.length) {
        buffer.write(input[cursor + 1]);
        cursor += 2;
        continue;
      }
      buffer.write(char);
      cursor++;
    }
    return _BalancedReadResult(content: buffer.toString(), nextIndex: cursor);
  }

  _BalancedReadResult _readBalancedCommand(String input, int index) {
    final buffer = StringBuffer();
    var cursor = index;
    var depth = 1;
    while (cursor < input.length) {
      final char = input[cursor];
      if (char == '\'' || char == '"') {
        final quoted = char == '\''
            ? _readSingleQuotedSegment(input, cursor)
            : _readDoubleQuoted(input, cursor);
        buffer.write(input.substring(cursor, quoted.nextIndex));
        cursor = quoted.nextIndex;
        continue;
      }
      if (char == '`') {
        final nested = _readBacktickCommand(input, cursor);
        buffer.write('`${nested.content}`');
        cursor = nested.nextIndex;
        continue;
      }
      if (char == r'\' && cursor + 1 < input.length) {
        buffer.write(input.substring(cursor, cursor + 2));
        cursor += 2;
        continue;
      }
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          return _BalancedReadResult(
            content: buffer.toString(),
            nextIndex: cursor + 1,
          );
        }
      }
      buffer.write(char);
      cursor++;
    }
    return _BalancedReadResult(content: buffer.toString(), nextIndex: cursor);
  }

  _QuotedReadResult _readSingleQuotedSegment(String input, int index) {
    final closing = input.indexOf('\'', index + 1);
    if (closing == -1) {
      return _QuotedReadResult(
        text: input.substring(index + 1),
        nextIndex: input.length,
        nestedCommands: const <String>[],
        hasDynamicExpansion: false,
      );
    }
    return _QuotedReadResult(
      text: input.substring(index + 1, closing),
      nextIndex: closing + 1,
      nestedCommands: const <String>[],
      hasDynamicExpansion: false,
    );
  }

  int _skipComment(String input, int index) {
    var cursor = index;
    while (cursor < input.length && input[cursor] != '\n') {
      cursor++;
    }
    return cursor;
  }

  String _normalizeRedirection(String token) {
    final body = token.replaceFirst(RegExp(r'^\d+'), '');
    return body;
  }

  bool _looksLikeAssignment(String value) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(value);
  }

  bool _looksLikeOption(String value) {
    return value.startsWith('-') && value != '-';
  }

  bool _looksLikeScriptPath(String value) {
    if (value.contains('/')) {
      return true;
    }
    return RegExp(
      r'\.(sh|bash|zsh|ksh|py|rb|pl|php|lua|js|ts)$',
    ).hasMatch(value);
  }

  String _basename(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return normalized;
    }
    final parts = normalized.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? normalized : parts.last;
  }

  bool _isWhitespace(String value) {
    return value == ' ' || value == '\t' || value == '\n' || value == '\r';
  }

  bool _isDigit(String value) {
    return value.codeUnitAt(0) >= 48 && value.codeUnitAt(0) <= 57;
  }

  bool _isFileDescriptorTarget(_ShellToken? target) {
    if (target == null || target.hasDynamicExpansion) {
      return false;
    }
    final normalized = target.text.trim();
    return normalized == '-' || RegExp(r'^\d+$').hasMatch(normalized);
  }

  bool _isNonPersistentOutputTarget(_ShellToken? target) {
    if (target == null || target.hasDynamicExpansion) {
      return false;
    }
    final normalized = target.text.trim();
    return normalized == '/dev/null' ||
        normalized == '/dev/stdout' ||
        normalized == '/dev/stderr' ||
        RegExp(r'^/dev/fd/\d+$').hasMatch(normalized) ||
        RegExp(r'^/proc/self/fd/\d+$').hasMatch(normalized);
  }
}

class _CmdWriteCommandAnalyzer {
  const _CmdWriteCommandAnalyzer(this.source);

  final String source;

  BashWriteAnalysis analyze() {
    final normalized = source.trim();
    if (normalized.isEmpty) {
      return const BashWriteAnalysis.readOnly('empty command');
    }
    if (RegExp(r'(^|[^<])>>?|>|>>').hasMatch(normalized)) {
      return const BashWriteAnalysis.write('cmd output redirection');
    }
    if (RegExp(
      r'(^|\s)(del|erase|move|copy|ren|rename|mkdir|rmdir|md|rd|attrib|type\s+.+>|powershell|pwsh|python|node)\b',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return const BashWriteAnalysis.write('cmd mutating command');
    }
    return const BashWriteAnalysis.readOnly('cmd command appears read-only');
  }
}

class _QuotedReadResult {
  const _QuotedReadResult({
    required this.text,
    required this.nextIndex,
    required this.nestedCommands,
    required this.hasDynamicExpansion,
  });

  final String text;
  final int nextIndex;
  final List<String> nestedCommands;
  final bool hasDynamicExpansion;
}

class _BalancedReadResult {
  const _BalancedReadResult({required this.content, required this.nextIndex});

  final String content;
  final int nextIndex;
}
