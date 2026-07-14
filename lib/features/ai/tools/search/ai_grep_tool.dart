import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiGrepTool extends AiTool {
  static const int _defaultHeadLimit = 250;
  static const int _maxColumns = 500;
  static const List<String> _vcsDirectoriesToExclude = <String>[
    '.git',
    '.svn',
    '.hg',
    '.bzr',
    '.jj',
    '.sl',
  ];

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.grep;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();

    // 参数解析
    final pattern = AiToolUtils.readString(args['pattern']);
    if (pattern.isEmpty) {
      return AiToolUtils.invalidResult('Grep', 'Grep requires pattern.');
    }

    // 路径解析和验证
    final rawPath = AiToolUtils.readString(args['path']);
    final path = rawPath.isEmpty
        ? AiToolUtils.defaultWorkingDirectory()
        : (p.isAbsolute(rawPath)
              ? p.normalize(rawPath)
              : p.normalize(
                  p.join(AiToolUtils.defaultWorkingDirectory(), rawPath),
                ));

    // 验证路径存在性
    final pathType = await probeFileSystemEntityType(path, followLinks: true);
    if (pathType == FileSystemEntityType.notFound) {
      return AiToolUtils.invalidResult('Grep', 'Path does not exist: $path');
    }

    final glob = AiToolUtils.readString(args['glob']);
    final outputMode = AiToolUtils.readString(
      args['output_mode'],
      fallback: 'files_with_matches',
    );
    if (!_supportedOutputModes.contains(outputMode)) {
      return AiToolUtils.invalidResult(
        'Grep',
        'Grep output_mode must be content, files_with_matches, or count.',
      );
    }
    final before = AiToolUtils.readInt(args['-B']);
    final after = AiToolUtils.readInt(args['-A']);
    final contextLines =
        AiToolUtils.readInt(args['-C']) ?? AiToolUtils.readInt(args['context']);
    if (_hasNegativeContextLineOption(before, after, contextLines)) {
      return AiToolUtils.invalidResult(
        'Grep',
        'Grep context line options (-B, -A, -C/context) must be non-negative integers.',
      );
    }
    final showLineNumbers = AiToolUtils.readBool(args['-n']) ?? true;
    final caseInsensitive = AiToolUtils.readBool(args['-i']) == true;
    final type = AiToolUtils.readString(args['type']);
    final headLimit = AiToolUtils.readInt(args['head_limit']);
    if (headLimit != null && headLimit < 0) {
      return AiToolUtils.invalidResult(
        'Grep',
        'Grep head_limit must be a non-negative integer.',
      );
    }
    final offset = AiToolUtils.readInt(args['offset']) ?? 0;
    if (offset < 0) {
      return AiToolUtils.invalidResult(
        'Grep',
        'Grep offset must be a non-negative integer.',
      );
    }
    final multiline = AiToolUtils.readBool(args['multiline']) == true;

    // 查找 rg 可执行文件（优先使用应用内嵌入的 vendor/ripgrep；
    // 仅当应用打包损坏导致内嵌二进制丢失时才会回退到系统 PATH）。
    final rgPath = await AiToolUtils.resolveRipgrepPath();
    if (rgPath == null) {
      const message =
          'ripgrep (rg) binary unavailable. The application bundles rg under '
          'vendor/ripgrep/{arch}-{os}/rg, so this normally never happens — '
          'reinstall the app or ensure the vendor directory was shipped. '
          'As a last resort install ripgrep system-wide (e.g. `brew install '
          'ripgrep` on macOS).';
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'Grep $pattern',
        workingDirectory: path,
        stdout: '',
        stderr: message,
        durationMs: startedAt.elapsedMilliseconds,
        exitCode: 127,
        resultText:
            'status: failed\nexit_code: 127\nstdout:\n\nstderr:\n$message',
      );
    }

    // 构建 rg 参数列表
    final rgArgs = <String>[
      '--hidden',
      '--max-columns',
      '$_maxColumns',
      for (final dir in _vcsDirectoriesToExclude) ...<String>[
        '--glob',
        '!$dir',
      ],
    ];
    switch (outputMode) {
      case 'content':
        break;
      case 'count':
        rgArgs.add('--count');
      case 'files_with_matches':
        rgArgs.add('--files-with-matches');
      default:
        rgArgs.add('--files-with-matches');
    }
    if (outputMode == 'content' && before != null) {
      rgArgs
        ..add('-B')
        ..add('$before');
    }
    if (outputMode == 'content' && after != null) {
      rgArgs
        ..add('-A')
        ..add('$after');
    }
    if (outputMode == 'content' && contextLines != null) {
      rgArgs
        ..add('-C')
        ..add('$contextLines');
    }
    if (outputMode == 'content' && showLineNumbers) {
      rgArgs.add('-n');
    }
    if (caseInsensitive) {
      rgArgs.add('-i');
    }
    if (type.isNotEmpty) {
      rgArgs
        ..add('--type')
        ..add(type);
    }
    for (final globPattern in _splitGlobPatterns(glob)) {
      rgArgs
        ..add('--glob')
        ..add(globPattern);
    }
    if (multiline) {
      rgArgs
        ..add('-U')
        ..add('--multiline-dotall');
    }

    // 确定搜索目标和工作目录
    final String workingDir;
    final String searchTarget;
    if (pathType == FileSystemEntityType.directory) {
      // 目录：设置为工作目录，搜索 '.'
      workingDir = path;
      searchTarget = '.';
    } else {
      // 文件：父目录为工作目录，搜索文件名
      workingDir = p.dirname(path);
      searchTarget = p.basename(path);
    }
    if (pattern.startsWith('-')) {
      rgArgs
        ..add('-e')
        ..add(pattern);
    } else {
      rgArgs.add(pattern);
    }
    rgArgs.add(searchTarget);

    // 执行 rg 命令（使用共享工具方法）
    final rgResult = await AiToolUtils.runProcessSafely(
      rgPath,
      rgArgs,
      workingDirectory: workingDir,
    );
    if (rgResult.exitCode == 0 ||
        (rgResult.exitCode == 1 && rgResult.stdout.trim().isEmpty)) {
      var output = rgResult.stdout.trimRight();
      var pagination = _GrepPaginationResult(
        output: output,
        appliedLimit: null,
      );
      if (output.isEmpty) {
        output = outputMode == 'count' ? '(zero matches)' : '(no matches)';
      } else {
        pagination = _applyPagination(
          output,
          headLimit: headLimit,
          offset: offset,
        );
        output = pagination.output;
        if (output.isEmpty) {
          output = '(no matches after offset)';
        }
        final paginationInfo = _formatPaginationInfo(
          appliedLimit: pagination.appliedLimit,
          offset: offset,
        );
        if (paginationInfo.isNotEmpty) {
          output =
              '$output\n\n[Showing results with pagination = $paginationInfo]';
        }
      }
      output = AiToolUtils.truncateContent(
        output,
        AiToolUtils.maxSearchOutputCharacters,
      );
      return AiToolUtils.simpleSuccessResult(
        command: 'Grep $pattern',
        output: output,
        durationMs: startedAt.elapsedMilliseconds,
        workingDirectory: path,
        metadata: <String, Object?>{
          'grep_output_mode': outputMode,
          'grep_head_limit': headLimit ?? _defaultHeadLimit,
          'grep_head_limit_defaulted': headLimit == null,
          'grep_offset': offset,
          if (pagination.appliedLimit != null)
            'grep_applied_limit': pagination.appliedLimit,
        },
      );
    }

    // 处理执行失败
    final stderrText = rgResult.stderr.trimRight();
    final stdoutText = rgResult.stdout.trimRight();
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: 'Grep $pattern',
      workingDirectory: path,
      stdout: stdoutText,
      stderr: stderrText,
      durationMs: startedAt.elapsedMilliseconds,
      exitCode: rgResult.exitCode,
      resultText: _buildFailureResultText(
        exitCode: rgResult.exitCode,
        stdout: stdoutText,
        stderr: stderrText,
      ),
    );
  }

  static const Set<String> _supportedOutputModes = <String>{
    'content',
    'files_with_matches',
    'count',
  };

  List<String> _splitGlobPatterns(String glob) {
    if (glob.isEmpty) return const <String>[];
    final patterns = <String>[];
    for (final rawPattern in glob.split(RegExp(r'\s+'))) {
      if (rawPattern.isEmpty) {
        continue;
      }
      if (rawPattern.contains('{') && rawPattern.contains('}')) {
        patterns.add(rawPattern);
      } else {
        patterns.addAll(splitTrimmedNonEmpty(rawPattern));
      }
    }
    return patterns;
  }

  bool _hasNegativeContextLineOption(
    int? before,
    int? after,
    int? contextLines,
  ) {
    return (before ?? 0) < 0 || (after ?? 0) < 0 || (contextLines ?? 0) < 0;
  }

  _GrepPaginationResult _applyPagination(
    String output, {
    required int? headLimit,
    required int offset,
  }) {
    final lines = output.split('\n');
    final safeOffset = offset < lines.length ? offset : lines.length;
    if (headLimit == 0) {
      return _GrepPaginationResult(
        output: lines.skip(safeOffset).join('\n'),
        appliedLimit: null,
      );
    }
    final effectiveLimit = headLimit ?? _defaultHeadLimit;
    final visibleLines = lines.skip(safeOffset).take(effectiveLimit).toList();
    final wasTruncated = lines.length - safeOffset > effectiveLimit;
    return _GrepPaginationResult(
      output: visibleLines.join('\n'),
      appliedLimit: wasTruncated ? effectiveLimit : null,
    );
  }

  String _formatPaginationInfo({
    required int? appliedLimit,
    required int offset,
  }) {
    final parts = <String>[];
    if (appliedLimit != null) {
      parts.add('limit: $appliedLimit');
    }
    if (offset > 0) {
      parts.add('offset: $offset');
    }
    return parts.join(', ');
  }

  /// 构建失败结果文本，提供更清晰的错误信息。
  String _buildFailureResultText({
    required int exitCode,
    required String stdout,
    required String stderr,
  }) {
    final buffer = StringBuffer('status: failed\nexit_code: $exitCode');
    if (stdout.isNotEmpty) {
      buffer
        ..writeln()
        ..write('stdout:\n')
        ..write(stdout);
    }
    if (stderr.isNotEmpty) {
      buffer
        ..writeln()
        ..write('stderr:\n')
        ..write(stderr);
    }
    // 为常见错误码添加提示
    if (exitCode == 2) {
      buffer
        ..writeln()
        ..write(
          'hint: Exit code 2 typically indicates a syntax error in the regex pattern.',
        );
    }
    return buffer.toString().trim();
  }
}

class _GrepPaginationResult {
  const _GrepPaginationResult({
    required this.output,
    required this.appliedLimit,
  });

  final String output;
  final int? appliedLimit;
}
