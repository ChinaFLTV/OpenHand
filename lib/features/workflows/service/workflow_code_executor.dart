import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/util/bounded_delete.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/text_clip.dart';
import '../model/workflow_definition.dart';

const int maxWorkflowCodeBytes = 512 * 1024;
const int maxWorkflowCodeInputBytes = 1024 * 1024;
const int maxWorkflowCodeOutputBytes = 1024 * 1024;
const int maxWorkflowCodeLogBytes = 1024 * 1024;
const int minWorkflowCodeTimeoutSeconds = 1;
const int maxWorkflowCodeTimeoutSeconds = 120;
const int defaultWorkflowCodeTimeoutSeconds = 30;
const Duration workflowValueExpressionTimeout = Duration(seconds: 10);
const Duration _workflowCodeFileIoTimeout = Duration(seconds: 3);

class WorkflowCodeRuntime {
  const WorkflowCodeRuntime({
    required this.language,
    this.executable,
    this.version,
    this.unavailableReason,
  });

  final WorkflowCodeLanguage language;
  final String? executable;
  final String? version;
  final String? unavailableReason;

  bool get isAvailable => executable?.trim().isNotEmpty == true;
}

WorkflowCodeRuntime workflowSystemCodeRuntime(WorkflowCodeLanguage language) {
  final isPowerShell = language == WorkflowCodeLanguage.windowsPowerShell;
  final supported = isPowerShell == Platform.isWindows;
  return WorkflowCodeRuntime(
    language: language,
    executable: supported
        ? (isPowerShell ? 'powershell.exe' : '/bin/sh')
        : null,
    version: supported ? '系统运行时' : null,
    unavailableReason: supported ? null : '${language.label} 仅支持当前平台对应的系统环境。',
  );
}

Map<WorkflowCodeLanguage, WorkflowCodeRuntime> workflowSystemCodeRuntimes() {
  final language = Platform.isWindows
      ? WorkflowCodeLanguage.windowsPowerShell
      : WorkflowCodeLanguage.linuxShell;
  return <WorkflowCodeLanguage, WorkflowCodeRuntime>{
    WorkflowCodeLanguage.python3: WorkflowCodeRuntime(
      language: WorkflowCodeLanguage.python3,
      executable: Platform.isWindows ? 'python.exe' : 'python3',
      version: '系统 PATH',
    ),
    WorkflowCodeLanguage.javascript: WorkflowCodeRuntime(
      language: WorkflowCodeLanguage.javascript,
      executable: Platform.isWindows ? 'node.exe' : 'node',
      version: '系统 PATH',
    ),
    language: workflowSystemCodeRuntime(language),
  };
}

class WorkflowCodeExecutionResult {
  const WorkflowCodeExecutionResult({
    required this.output,
    required this.stdout,
    required this.stderr,
    required this.duration,
  });

  final Map<String, Object?> output;
  final String stdout;
  final String stderr;
  final Duration duration;
}

class WorkflowCodeExecutionException implements Exception {
  const WorkflowCodeExecutionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class WorkflowCodeExecutor {
  const WorkflowCodeExecutor();

  static const BoundedDeletePolicy _cleanupPolicy = BoundedDeletePolicy(
    maxEntries: 8,
    maxDepth: 2,
    operationTimeout: Duration(seconds: 2),
    totalTimeout: Duration(seconds: 5),
  );

  Future<Map<String, Object?>> evaluateExpressions({
    required WorkflowCodeRuntime runtime,
    required Map<String, String> expressions,
    required Map<String, Object?> variables,
    Future<void>? cancelSignal,
  }) async {
    if (expressions.isEmpty) return const <String, Object?>{};
    final result = await execute(
      runtime: runtime,
      code: _expressionCode(runtime.language, expressions),
      inputs: variables,
      timeout: workflowValueExpressionTimeout,
      cancelSignal: cancelSignal,
    );
    return result.output;
  }

  Future<WorkflowCodeExecutionResult> execute({
    required WorkflowCodeRuntime runtime,
    required String code,
    required Map<String, Object?> inputs,
    required Duration timeout,
    Future<void>? cancelSignal,
  }) async {
    final executable = runtime.executable?.trim() ?? '';
    if (executable.isEmpty) {
      throw WorkflowCodeExecutionException(
        runtime.unavailableReason ?? '${runtime.language.label} 运行时不可用。',
      );
    }
    final sourceBytes = utf8.encode(code);
    if (sourceBytes.isEmpty) {
      throw const WorkflowCodeExecutionException('代码不能为空。');
    }
    if (sourceBytes.length > maxWorkflowCodeBytes) {
      throw const WorkflowCodeExecutionException('代码大小不能超过 512 KiB。');
    }
    late final List<int> inputBytes;
    try {
      inputBytes = utf8.encode(jsonEncode(inputs));
    } on JsonUnsupportedObjectError catch (error) {
      throw WorkflowCodeExecutionException('代码输入包含无法序列化的值。', cause: error);
    }
    if (inputBytes.length > maxWorkflowCodeInputBytes) {
      throw const WorkflowCodeExecutionException('代码输入不能超过 1 MiB。');
    }

    final boundedTimeout = Duration(
      seconds: timeout.inSeconds.clamp(
        minWorkflowCodeTimeoutSeconds,
        maxWorkflowCodeTimeoutSeconds,
      ),
    );
    final stopwatch = Stopwatch()..start();
    Directory? temporaryDirectory;
    try {
      temporaryDirectory = await createTemporaryDirectoryBounded(
        prefix: 'openhand-workflow-code-',
        timeout: _workflowCodeFileIoTimeout,
      );
      final resultFile = File(p.join(temporaryDirectory.path, 'result.json'));
      final scriptFile = File(
        p.join(
          temporaryDirectory.path,
          'main.${runtime.language.fileExtension}',
        ),
      );
      await writeTemporaryFileTextBounded(
        scriptFile,
        _wrappedCode(runtime.language, code),
        timeout: _workflowCodeFileIoTimeout,
      );
      Object? launchFailure;
      final processResult = await runProcessWithTimeout(
        executable,
        _arguments(runtime.language, scriptFile.path, resultFile.path),
        stdinBytes: inputBytes,
        environment: _inputEnvironment(inputs),
        timeout: boundedTimeout,
        cancelSignal: cancelSignal,
        workingDirectory: temporaryDirectory.path,
        maxStderrBytes: maxWorkflowCodeLogBytes,
        tag: 'workflow.code_execution',
        onFailure: (error, _) => launchFailure = error,
        timeoutResultBuilder: (pid, stdout, stderr) =>
            ProcessResult(pid, -408, stdout, stderr),
      );
      final stdout = '${processResult?.stdout ?? ''}';
      final stderr = '${processResult?.stderr ?? ''}';
      if (processResult == null) {
        throw WorkflowCodeExecutionException(
          '无法启动 ${runtime.language.label} 运行时。',
          cause: launchFailure,
        );
      }
      if (processResult.exitCode == -408) {
        throw WorkflowCodeExecutionException(
          '代码执行超过 ${boundedTimeout.inSeconds} 秒，已终止进程。',
        );
      }
      if (processResult.exitCode != 0) {
        final detail = clipText(
          stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim(),
          4000,
        );
        throw WorkflowCodeExecutionException(
          detail.isEmpty
              ? '代码执行失败，退出码 ${processResult.exitCode}。'
              : '代码执行失败：$detail',
        );
      }
      if (!await regularFileExistsBounded(resultFile, followLinks: false)) {
        throw const WorkflowCodeExecutionException('代码未返回有效结果。');
      }
      late final String rawResult;
      try {
        rawResult = await readBoundedFileString(
          resultFile,
          maxBytes: maxWorkflowCodeOutputBytes,
        );
      } on BoundedFileReadException catch (error) {
        throw WorkflowCodeExecutionException('代码输出不能超过 1 MiB。', cause: error);
      }
      final payload = _decodePayload(rawResult);
      if (payload['ok'] != true) {
        final message = '${payload['error'] ?? ''}'.trim();
        throw WorkflowCodeExecutionException(
          message.isEmpty ? '代码执行失败。' : '代码执行失败：$message',
        );
      }
      final value = payload['result'];
      if (value is! Map) {
        throw const WorkflowCodeExecutionException('main 函数必须返回 JSON 对象。');
      }
      return WorkflowCodeExecutionResult(
        output: Map<String, Object?>.unmodifiable(<String, Object?>{
          for (final entry in value.entries) '${entry.key}': entry.value,
        }),
        stdout: stdout,
        stderr: stderr,
        duration: stopwatch.elapsed,
      );
    } finally {
      stopwatch.stop();
      final directory = temporaryDirectory;
      if (directory != null) {
        try {
          await deletePathBounded(
            p.absolute(directory.path),
            policy: _cleanupPolicy,
            allowedRoot: p.absolute(Directory.systemTemp.path),
          );
        } catch (error, stack) {
          silentLog('workflow_code_executor', '清理代码执行临时目录', error, stack);
        }
      }
    }
  }

  Map<String, String> _inputEnvironment(Map<String, Object?> inputs) {
    final environment = <String, String>{};
    for (final entry in inputs.entries) {
      final name = entry.key.trim();
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) continue;
      try {
        environment[name] = jsonEncode(entry.value);
      } catch (_) {
        environment[name] = '${entry.value ?? ''}';
      }
    }
    return environment;
  }

  List<String> _arguments(
    WorkflowCodeLanguage language,
    String scriptPath,
    String resultPath,
  ) => switch (language) {
    WorkflowCodeLanguage.python3 => <String>['-I', scriptPath, resultPath],
    WorkflowCodeLanguage.javascript => <String>[
      '--max-old-space-size=256',
      '--unhandled-rejections=strict',
      scriptPath,
      resultPath,
    ],
    WorkflowCodeLanguage.linuxShell => <String>['-eu', scriptPath, resultPath],
    WorkflowCodeLanguage.windowsPowerShell => <String>[
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      scriptPath,
      resultPath,
    ],
  };

  Map<String, Object?> _decodePayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, Object?>{
          for (final entry in decoded.entries) '${entry.key}': entry.value,
        };
      }
    } on FormatException {
      // 下方统一返回面向用户的错误。
    }
    throw const WorkflowCodeExecutionException('代码返回结果不是有效 JSON。');
  }

  String _expressionCode(
    WorkflowCodeLanguage language,
    Map<String, String> expressions,
  ) => switch (language) {
    WorkflowCodeLanguage.python3 =>
      '''def main(**__openhand_variables):
    __openhand_scope = {
        "len": len,
        "min": min,
        "max": max,
        "sum": sum,
        "round": round,
        "abs": abs,
        "sorted": sorted,
        "str": str,
        "int": int,
        "float": float,
        "bool": bool,
    }
    __openhand_scope.update(__openhand_variables)
    return {
${expressions.entries.map((entry) => '        ${jsonEncode(entry.key)}: eval(${jsonEncode(entry.value)}, {"__builtins__": {}}, __openhand_scope),').join('\n')}
    }''',
    WorkflowCodeLanguage.javascript =>
      '''function main(__openhandVariables) {
  const evaluate = expression => Function("__openhandScope", `with (__openhandScope) { return (\${expression}); }`)(__openhandVariables);
  return {
${expressions.entries.map((entry) => '    ${jsonEncode(entry.key)}: evaluate(${jsonEncode(entry.value)}),').join('\n')}
  };
}''',
    WorkflowCodeLanguage.linuxShell => _linuxShellExpressionCode(expressions),
    WorkflowCodeLanguage.windowsPowerShell => _powerShellExpressionCode(
      expressions,
    ),
  };

  String _linuxShellExpressionCode(Map<String, String> expressions) {
    final buffer = StringBuffer()
      ..writeln('#!/bin/sh')
      ..writeln('set -eu')
      ..writeln('__openhand_result_path="\${2}"')
      ..writeln('__openhand_input="\$(cat)"')
      ..writeln('export OPENHAND_INPUT_JSON="\$__openhand_input"')
      ..writeln("printf '{'");
    var index = 0;
    for (final entry in expressions.entries) {
      if (index > 0) buffer.writeln("printf ','");
      buffer.writeln(
        'printf \'${jsonEncode(entry.key)}:%s\' "\$(eval ${_shellQuote(entry.value)})"',
      );
      index += 1;
    }
    buffer
      ..writeln("printf '}' > \"\$__openhand_result_path\"")
      ..write('');
    return buffer.toString();
  }

  String _powerShellExpressionCode(Map<String, String> expressions) {
    final buffer = StringBuffer()
      ..writeln('param([string]\$ResultPath)')
      ..writeln('\$inputJson = [Console]::In.ReadToEnd()')
      ..writeln('\$inputObject = \$inputJson | ConvertFrom-Json')
      ..writeln(
        'if (\$inputObject -is [pscustomobject]) { \$inputObject.psobject.Properties | ForEach-Object { Set-Variable -Name \$_.Name -Value \$_.Value } }',
      )
      ..writeln('\$env:OPENHAND_INPUT_JSON = \$inputJson')
      ..writeln('\$result = [ordered]@{}');
    for (final entry in expressions.entries) {
      buffer.writeln(
        '\$result[${jsonEncode(entry.key)}] = & { ${entry.value} }',
      );
    }
    buffer.writeln(
      '\$result | ConvertTo-Json -Compress -Depth 32 | Set-Content -Encoding utf8 \$ResultPath',
    );
    return buffer.toString();
  }

  String _shellQuote(String value) {
    final escaped = value.replaceAll("'", "'\"'\"'");
    return "'$escaped'";
  }

  String _wrappedCode(WorkflowCodeLanguage language, String code) =>
      switch (language) {
        WorkflowCodeLanguage.python3 =>
          '''$code

import asyncio as __openhand_asyncio
import inspect as __openhand_inspect
import json as __openhand_json
import sys as __openhand_sys
import traceback as __openhand_traceback

def __openhand_write(payload):
    encoded = __openhand_json.dumps(payload, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")
    if len(encoded) > $maxWorkflowCodeOutputBytes:
        encoded = __openhand_json.dumps({"ok": False, "error": "代码输出不能超过 1 MiB。"}, ensure_ascii=False).encode("utf-8")
    with open(__openhand_sys.argv[1], "wb") as __openhand_file:
        __openhand_file.write(encoded)

try:
    __openhand_payload = __openhand_json.loads(__openhand_sys.stdin.read() or "{}")
    if not isinstance(__openhand_payload, dict):
        raise TypeError("代码输入必须是 JSON 对象。")
    if "main" not in globals() or not callable(main):
        raise TypeError("请定义 main 函数。")
    __openhand_result = main(**__openhand_payload)
    if __openhand_inspect.isawaitable(__openhand_result):
        __openhand_result = __openhand_asyncio.run(__openhand_result)
    if not isinstance(__openhand_result, dict):
        raise TypeError("main 函数必须返回 JSON 对象。")
    __openhand_write({"ok": True, "result": __openhand_result})
except BaseException as __openhand_error:
    __openhand_traceback.print_exc(file=__openhand_sys.stderr)
    __openhand_write({"ok": False, "error": str(__openhand_error)[:32768]})
''',
        WorkflowCodeLanguage.javascript =>
          '''$code

const __openhandFs = require('fs');
const __openhandResultPath = process.argv[2];

function __openhandWrite(payload) {
  let encoded = JSON.stringify(payload);
  if (Buffer.byteLength(encoded, 'utf8') > $maxWorkflowCodeOutputBytes) {
    encoded = JSON.stringify({ ok: false, error: '代码输出不能超过 1 MiB。' });
  }
  __openhandFs.writeFileSync(__openhandResultPath, encoded, 'utf8');
}

(async () => {
  try {
    const chunks = [];
    for await (const chunk of process.stdin) chunks.push(chunk);
    const payload = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
    if (!payload || Array.isArray(payload) || typeof payload !== 'object') {
      throw new TypeError('代码输入必须是 JSON 对象。');
    }
    if (typeof main !== 'function') throw new TypeError('请定义 main 函数。');
    const result = await main(payload);
    if (!result || Array.isArray(result) || typeof result !== 'object') {
      throw new TypeError('main 函数必须返回 JSON 对象。');
    }
    __openhandWrite({ ok: true, result });
  } catch (error) {
    console.error(error && error.stack ? error.stack : String(error));
    __openhandWrite({ ok: false, error: String(error && error.message ? error.message : error).slice(0, 32768) });
  }
})();
''',
        WorkflowCodeLanguage.linuxShell =>
          '''#!/bin/sh
set -eu
__openhand_result_path="\${2}"
__openhand_input="\$(cat)"
export OPENHAND_INPUT_JSON="\$__openhand_input"
__openhand_stdout="\$(
$code
)"
if [ -z "\$__openhand_stdout" ]; then __openhand_stdout='{}'; fi
printf '{"ok":true,"result":%s}' "\$__openhand_stdout" > "\$__openhand_result_path"
''',
        WorkflowCodeLanguage.windowsPowerShell =>
          '''param([string]\$ResultPath)
\$inputJson = [Console]::In.ReadToEnd()
\$inputObject = \$inputJson | ConvertFrom-Json
if (\$inputObject -is [pscustomobject]) { \$inputObject.psobject.Properties | ForEach-Object { Set-Variable -Name \$_.Name -Value \$_.Value } }
\$env:OPENHAND_INPUT_JSON = \$inputJson
try {
$code
  if (\$null -eq \$result) { \$result = @{} }
  @{ ok = \$true; result = \$result } | ConvertTo-Json -Compress -Depth 32 | Set-Content -Encoding utf8 \$ResultPath
} catch {
  @{ ok = \$false; error = \$_.Exception.Message } | ConvertTo-Json -Compress | Set-Content -Encoding utf8 \$ResultPath
  exit 1
}
''',
      };
}
