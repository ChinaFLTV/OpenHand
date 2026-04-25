import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../app/support/silent_log.dart';
import '../service/ai_bash_tool_service.dart';
import '../service/ai_file_history_service.dart';
import '../service/ai_file_tracker_service.dart';
import '../service/ai_tool_runtime_service.dart';

class AiToolUtils {
  AiToolUtils._();

  static const int maxFileCharacters = 64000;
  static const int maxReadBytes = maxFileCharacters * 4;
  static const int maxSearchOutputCharacters = 24000;
  static const int maxWebContentCharacters = 20000;
  static const int maxReadLineLength = 2000;
  static const int defaultReadLimit = 2000;
  static const int maxBinaryPreviewBytes = 32;

  static String defaultWorkingDirectory() {
    return p.normalize(Directory.current.path);
  }

  static String resolvePath(String rawPath) {
    final normalizedInput = rawPath.trim();
    if (normalizedInput.isEmpty) return defaultWorkingDirectory();
    if (p.isAbsolute(normalizedInput)) return p.normalize(normalizedInput);
    return p.normalize(p.join(defaultWorkingDirectory(), normalizedInput));
  }

  static Map<String, Object?> decodeArguments(String rawArguments) {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map<String, Object?>) return decoded;
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (error, stack) {
      silentLog('ai_tool_utils', 'decode tool arguments JSON', error, stack);
    }
    return const <String, Object?>{};
  }

  static String? requireAbsoluteFilePath(String rawPath) {
    final normalizedInput = rawPath.trim();
    if (normalizedInput.isEmpty || !p.isAbsolute(normalizedInput)) return null;
    return p.normalize(normalizedInput);
  }

  static String? requireAbsoluteDirectoryPath(String rawPath) {
    final normalizedInput = rawPath.trim();
    if (normalizedInput.isEmpty || !p.isAbsolute(normalizedInput)) return null;
    return p.normalize(normalizedInput);
  }

  static int? readInt(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value'.trim());
  }

  static List<String> normalizeStringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => '$item'.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String truncateContent(String content, int maxCharacters) {
    if (content.length <= maxCharacters) return content;
    return '${content.substring(0, maxCharacters)}...';
  }

  static String htmlToText(String html) {
    final withoutScripts = html
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
          ' ',
        );
    final withoutTags = withoutScripts.replaceAll(RegExp(r'<[^>]+>'), ' ');
    final withoutEntities = withoutTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return withoutEntities.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool globMatches(String value, String pattern) {
    final normalizedValue = value.replaceAll('\\', '/');
    final normalizedPattern = pattern.replaceAll('\\', '/');
    final regex = _globToRegExp(normalizedPattern);
    return regex.hasMatch(normalizedValue) ||
        regex.hasMatch('/$normalizedValue');
  }

  static bool matchesAnyGlob(String value, List<String> patterns) {
    for (final pattern in patterns) {
      if (globMatches(value, pattern)) return true;
    }
    return false;
  }

  static RegExp _globToRegExp(String pattern) {
    final buffer = StringBuffer('^');
    for (var index = 0; index < pattern.length; index++) {
      final char = pattern[index];
      if (char == '*') {
        final isDoubleStar =
            index + 1 < pattern.length && pattern[index + 1] == '*';
        if (isDoubleStar) {
          buffer.write('.*');
          index += 1;
        } else {
          buffer.write('[^/]*');
        }
        continue;
      }
      if (char == '?') {
        buffer.write('.');
        continue;
      }
      if (r'\\.^$+()[]{}|'.contains(char)) {
        buffer.write('\\$char');
        continue;
      }
      buffer.write(char);
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  static ReplacementResult replaceOnceOrAll({
    required String content,
    required String oldString,
    required String newString,
    required bool replaceAll,
  }) {
    if (oldString.isEmpty) {
      return const ReplacementResult.failure('old_string must not be empty.');
    }
    final matchCount = RegExp(
      RegExp.escape(oldString),
    ).allMatches(content).length;
    if (matchCount == 0) {
      return const ReplacementResult.failure(
        'old_string was not found in the file.',
      );
    }
    if (!replaceAll && matchCount > 1) {
      return const ReplacementResult.failure(
        'old_string matched multiple locations. Provide more context or set replace_all.',
      );
    }
    return ReplacementResult.success(
      replaceAll
          ? content.replaceAll(oldString, newString)
          : content.replaceFirst(oldString, newString),
    );
  }

  static AiToolExecutionResult invalidResult(String command, String message) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.invalidArguments,
      command: command,
      workingDirectory: defaultWorkingDirectory(),
      stdout: '',
      stderr: message,
      durationMs: 0,
      resultText: 'status: invalid_arguments\nerror: $message',
    );
  }

  static AiToolExecutionResult simpleSuccessResult({
    required String command,
    required String output,
    required int durationMs,
    String? workingDirectory,
    bool isWriteCommand = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: command,
      workingDirectory: workingDirectory ?? defaultWorkingDirectory(),
      stdout: output,
      stderr: '',
      durationMs: durationMs,
      resultText: output.trim(),
      isWriteCommand: isWriteCommand,
      writeAnalysisReason: isWriteCommand ? 'builtin file mutation tool' : '',
      metadata: metadata,
    );
  }

  static AiToolExecutionResult cancelledResult({
    required String command,
    required int durationMs,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    const detail = 'The tool execution was cancelled by the user.';
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.cancelled,
      command: command,
      workingDirectory: defaultWorkingDirectory(),
      stdout: '',
      stderr: detail,
      durationMs: durationMs,
      resultText: 'status: cancelled\ndetail: $detail',
      metadata: metadata,
    );
  }

  static Future<AiToolExecutionResult?> validateReadBeforeMutation({
    required String toolName,
    required String filePath,
    required Set<String> previouslyReadFiles,
    bool requireExistingFileRead = true,
    AiFileTrackerService? fileTracker,
  }) async {
    if (!requireExistingFileRead) return null;
    final file = File(filePath);
    if (!await file.exists()) return null;
    if (!previouslyReadFiles.contains(filePath)) {
      return invalidResult(
        toolName,
        '$toolName requires reading the file with Read before mutating it: $filePath',
      );
    }

    // 2026-04-12: 脏写检测 - 检查文件是否在读取后被外部修改
    if (fileTracker != null) {
      final dirtyWriteError = await fileTracker.validateSafeToWrite(filePath);
      if (dirtyWriteError != null) {
        return invalidResult(toolName, dirtyWriteError);
      }
    }

    return null;
  }

  /// 在文件修改前保存历史版本
  ///
  /// 2026-04-12: 实现 OpenCode 历史版本机制
  static Future<String?> saveFileVersionBeforeMutation({
    required String filePath,
    required String sessionId,
    String? toolCallId,
    AiFileHistoryService? fileHistory,
  }) async {
    if (fileHistory == null) return null;
    return fileHistory.saveVersion(
      filePath: filePath,
      sessionId: sessionId,
      toolCallId: toolCallId,
    );
  }

  /// 在文件修改后更新追踪器
  ///
  /// 2026-04-12: 写入成功后更新 lastReadTime
  static Future<void> updateTrackerAfterMutation({
    required String filePath,
    AiFileTrackerService? fileTracker,
  }) async {
    if (fileTracker == null) return;
    await fileTracker.updateAfterWrite(filePath);
  }

  static Future<void> writeTextFileSafely(File file, String content) async {
    final entityType = await FileSystemEntity.type(
      file.path,
      followLinks: false,
    );
    await file.parent.create(recursive: true);
    if (entityType == FileSystemEntityType.link) {
      await file.writeAsString(content, flush: true);
      return;
    }
    final tempFile = File(
      p.join(
        file.parent.path,
        '.${p.basename(file.path)}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    final backupFile = File('${file.path}.bak');
    if (await tempFile.exists()) await tempFile.delete();
    await tempFile.writeAsString(content, flush: true);
    if (await file.exists()) await _copyExistingFileMode(file, tempFile);
    var movedExistingFile = false;
    try {
      if (await backupFile.exists()) await backupFile.delete();
      if (await file.exists()) {
        await file.rename(backupFile.path);
        movedExistingFile = true;
      }
      await tempFile.rename(file.path);
      if (await backupFile.exists()) await backupFile.delete();
    } catch (_) {
      if (await tempFile.exists()) await tempFile.delete();
      if (movedExistingFile && await backupFile.exists()) {
        if (await file.exists()) await file.delete();
        await backupFile.rename(file.path);
      }
      rethrow;
    }
  }

  static Future<void> _copyExistingFileMode(
    File sourceFile,
    File targetFile,
  ) async {
    if (Platform.isWindows) return;
    final sourceStat = await FileStat.stat(sourceFile.path);
    if (sourceStat.type == FileSystemEntityType.notFound) return;
    final permissionBits = sourceStat.mode & 0x1FF;
    final chmodResult = await Process.run('chmod', <String>[
      permissionBits.toRadixString(8),
      targetFile.path,
    ]);
    if (chmodResult.exitCode == 0) return;
    final message = '${chmodResult.stderr}'.trim();
    throw FileSystemException(
      message.isEmpty
          ? 'Unable to preserve existing file permissions.'
          : message,
      targetFile.path,
    );
  }

  static Future<List<int>> readFilePrefix(File file, int fileLength) async {
    final byteLimit = fileLength < maxReadBytes ? fileLength : maxReadBytes;
    if (byteLimit <= 0) return const <int>[];
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, byteLimit)) {
      builder.add(chunk);
      if (builder.length >= byteLimit) break;
    }
    return builder.takeBytes();
  }

  static String decodeTextBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  static bool looksBinary(List<int> bytes) {
    final preview = bytes.take(2048);
    var suspiciousCount = 0;
    var inspected = 0;
    for (final value in preview) {
      inspected += 1;
      if (value == 0) return true;
      final isControl = value < 32 && value != 9 && value != 10 && value != 13;
      if (isControl) suspiciousCount += 1;
    }
    if (inspected == 0) return false;
    return suspiciousCount / inspected > 0.12;
  }

  static bool isRasterImageExtension(String extension) {
    return const <String>{
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.ico',
      '.tga',
    }.contains(extension);
  }

  static bool isKnownTextExtension(String extension) {
    if (extension.isEmpty) return false;
    return const <String>{
      '.txt',
      '.md',
      '.markdown',
      '.json',
      '.yaml',
      '.yml',
      '.toml',
      '.xml',
      '.html',
      '.htm',
      '.css',
      '.scss',
      '.sass',
      '.js',
      '.jsx',
      '.ts',
      '.tsx',
      '.dart',
      '.go',
      '.py',
      '.java',
      '.kt',
      '.kts',
      '.rb',
      '.rs',
      '.c',
      '.cc',
      '.cpp',
      '.h',
      '.hpp',
      '.sh',
      '.zsh',
      '.bash',
      '.fish',
      '.sql',
      '.csv',
      '.tsv',
      '.env',
      '.ini',
      '.cfg',
      '.conf',
      '.log',
      '.svg',
      '.vue',
    }.contains(extension);
  }

  static bool looksLikeTimeoutMessage(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized.contains('timed out') || normalized.contains('timeout');
  }

  static Future<T?> awaitWithCancellation<T>(
    Future<T> future, {
    Future<void>? cancelSignal,
  }) async {
    if (cancelSignal == null) return future;
    final sentinel = Object();
    final firstResult = await Future.any(
      <Future<Object?>?>[
        future,
        cancelSignal.then<Object?>((_) => sentinel),
      ].whereType<Future<Object?>>().toList(),
    );
    if (identical(firstResult, sentinel)) {
      future.then<void>((_) {}, onError: (Object e, StackTrace st) {});
      return null;
    }
    return firstResult as T;
  }

  // ────────────────────────────────────────────────────────────
  // 2026-04-13: ripgrep (rg) 命令路径解析
  // 优先使用应用内嵌入的 rg，确保用户无需预装 ripgrep
  // ────────────────────────────────────────────────────────────

  /// 缓存的 rg 可执行文件路径。首次调用时初始化。
  static String? _cachedRgPath;

  /// 获取当前平台的 ripgrep 子目录名称。
  ///
  /// 返回格式：`{arch}-{os}`，例如 `arm64-darwin`、`x64-win32`。
  static String _getRipgrepPlatformDir() {
    final String os;
    if (Platform.isMacOS) {
      os = 'darwin';
    } else if (Platform.isWindows) {
      os = 'win32';
    } else if (Platform.isLinux) {
      os = 'linux';
    } else {
      os = 'unknown';
    }

    // 检测 CPU 架构
    // Dart 没有直接的 API，通过 Platform.version 或环境变量推断
    final String arch;
    final version = Platform.version.toLowerCase();
    final executable = Platform.resolvedExecutable.toLowerCase();

    if (Platform.isMacOS) {
      // macOS: 通过可执行文件路径或 uname 推断
      // Apple Silicon 通常在 arm64 目录，Intel 在 x86_64
      // 简化判断：如果路径包含 arm64 或 M1/M2/M3 系列，使用 arm64
      if (executable.contains('arm64') || _isAppleSilicon()) {
        arch = 'arm64';
      } else {
        arch = 'x64';
      }
    } else if (Platform.isWindows) {
      // Windows: 检查环境变量
      final processorArch =
          Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
      if (processorArch.contains('ARM64')) {
        arch = 'arm64';
      } else {
        arch = 'x64';
      }
    } else {
      // Linux: 通过 uname -m 或环境变量
      if (version.contains('arm64') || version.contains('aarch64')) {
        arch = 'arm64';
      } else {
        arch = 'x64';
      }
    }

    return '$arch-$os';
  }

  /// 检测是否为 Apple Silicon Mac。
  static bool _isAppleSilicon() {
    // 环境变量:运行在 Rosetta 下的 x86_64 二进制,宿主为 Apple Silicon
    final sysctl = Platform.environment['SYSCTL_PROC_TRANSLATED'];
    if (sysctl == '1') return true;

    // 首选:同步执行 `uname -m` 读取内核架构
    try {
      final result = Process.runSync('uname', <String>['-m']);
      if (result.exitCode == 0) {
        final machine = '${result.stdout}'.trim().toLowerCase();
        if (machine == 'arm64' || machine == 'aarch64') return true;
        if (machine == 'x86_64' || machine == 'i386') return false;
      }
    } catch (_) {
      // uname 不可用时回退到路径探测
    }

    // 回退:Homebrew 在 Apple Silicon 上默认安装到 /opt/homebrew
    return Directory('/opt/homebrew/bin').existsSync();
  }

  /// 获取应用内嵌入的 ripgrep 路径。
  ///
  /// 查找优先级：
  /// 1. 开发模式：项目根目录的 vendor/ripgrep
  /// 2. macOS 打包：应用包内的 Resources/vendor/ripgrep
  /// 3. Windows 打包：可执行文件同级的 vendor/ripgrep
  static Future<String?> _getEmbeddedRipgrepPath() async {
    final platformDir = _getRipgrepPlatformDir();
    final rgName = Platform.isWindows ? 'rg.exe' : 'rg';

    // 候选路径列表
    final candidates = <String>[];

    final executablePath = Platform.resolvedExecutable;
    final executableDir = p.dirname(executablePath);

    if (Platform.isMacOS) {
      // macOS 打包后：MyApp.app/Contents/MacOS/MyApp
      // vendor 应该在：MyApp.app/Contents/Resources/vendor
      final appBundle = p.dirname(executableDir); // Contents
      final resourcesDir = p.join(
        appBundle,
        'Resources',
        'vendor',
        'ripgrep',
        platformDir,
        rgName,
      );
      candidates.add(resourcesDir);

      // 开发模式：直接使用项目目录
      // 项目结构：OpenHand/vendor/ripgrep/...
      // 可执行文件在：OpenHand/build/macos/Build/Products/Debug/openhand.app/...
      final projectRoot = _findProjectRoot(executableDir);
      if (projectRoot != null) {
        candidates.add(
          p.join(projectRoot, 'vendor', 'ripgrep', platformDir, rgName),
        );
      }
    } else if (Platform.isWindows) {
      // Windows 打包后：安装目录/MyApp.exe
      // vendor 应该在：安装目录/vendor/ripgrep
      candidates.add(
        p.join(executableDir, 'vendor', 'ripgrep', platformDir, rgName),
      );

      // 开发模式
      final projectRoot = _findProjectRoot(executableDir);
      if (projectRoot != null) {
        candidates.add(
          p.join(projectRoot, 'vendor', 'ripgrep', platformDir, rgName),
        );
      }
    } else if (Platform.isLinux) {
      // Linux 类似 Windows
      candidates.add(
        p.join(executableDir, 'vendor', 'ripgrep', platformDir, rgName),
      );

      final projectRoot = _findProjectRoot(executableDir);
      if (projectRoot != null) {
        candidates.add(
          p.join(projectRoot, 'vendor', 'ripgrep', platformDir, rgName),
        );
      }
    }

    // 添加当前工作目录作为最后备选（开发模式）
    candidates.add(
      p.join(Directory.current.path, 'vendor', 'ripgrep', platformDir, rgName),
    );

    // 检查每个候选路径
    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) {
        // 确保有执行权限（非 Windows）
        if (!Platform.isWindows) {
          try {
            final stat = await file.stat();
            // 检查是否有执行权限 (mode & 0x49 = owner/group/other execute)
            if (stat.mode & 0x49 == 0) {
              // 尝试添加执行权限
              await Process.run('chmod', <String>['+x', candidate]);
            }
          } catch (_) {
            // 忽略权限检查失败
          }
        }
        return candidate;
      }
    }

    return null;
  }

  /// 查找项目根目录（通过向上查找 pubspec.yaml）。
  static String? _findProjectRoot(String startDir) {
    var current = startDir;
    for (var i = 0; i < 10; i++) {
      final pubspec = File(p.join(current, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        return current;
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
    return null;
  }

  /// rg 系统安装常见路径（macOS/Linux）。
  static const List<String> _rgSystemPaths = <String>[
    '/opt/homebrew/bin/rg', // macOS Apple Silicon (Homebrew)
    '/usr/local/bin/rg', // macOS Intel (Homebrew) / Linux
    '/usr/bin/rg', // Linux system install
    '/home/linuxbrew/.linuxbrew/bin/rg', // Linux Homebrew
  ];

  /// 解析 rg (ripgrep) 可执行文件路径。
  ///
  /// 查找优先级：
  /// 1. **应用内嵌入的 rg**（确保无需用户预装）
  /// 2. PATH 环境变量（通过 which 命令）
  /// 3. 常见系统安装路径
  /// 4. macOS 登录 shell 环境
  ///
  /// 返回 null 表示未找到 ripgrep。
  static Future<String?> resolveRipgrepPath() async {
    if (_cachedRgPath != null) return _cachedRgPath;

    // 1. 优先使用应用内嵌入的 rg
    final embeddedPath = await _getEmbeddedRipgrepPath();
    if (embeddedPath != null) {
      _cachedRgPath = embeddedPath;
      return _cachedRgPath;
    }

    // 2. 尝试从 PATH 环境变量查找（通过 which/where 命令）
    try {
      final whichCmd = Platform.isWindows ? 'where' : 'which';
      final whichResult = await Process.run(whichCmd, <String>['rg']);
      if (whichResult.exitCode == 0) {
        final foundPath = whichResult.stdout
            .toString()
            .trim()
            .split('\n')
            .first;
        if (foundPath.isNotEmpty && await File(foundPath).exists()) {
          _cachedRgPath = foundPath;
          return _cachedRgPath;
        }
      }
    } catch (_) {
      // which/where 命令失败，继续尝试其他方式
    }

    // 3. 直接检查常见系统安装路径（非 Windows）
    if (!Platform.isWindows) {
      for (final candidatePath in _rgSystemPaths) {
        if (await File(candidatePath).exists()) {
          _cachedRgPath = candidatePath;
          return _cachedRgPath;
        }
      }
    }

    // 4. 尝试从登录 shell 获取环境变量（macOS）
    if (Platform.isMacOS) {
      try {
        final shellResult = await Process.run(
          '/bin/zsh',
          <String>['-l', '-c', 'which rg'],
          environment: <String, String>{
            'HOME': Platform.environment['HOME'] ?? '',
          },
        );
        if (shellResult.exitCode == 0) {
          final foundPath = shellResult.stdout.toString().trim();
          if (foundPath.isNotEmpty && await File(foundPath).exists()) {
            _cachedRgPath = foundPath;
            return _cachedRgPath;
          }
        }
      } catch (_) {
        // 登录 shell 查找失败
      }
    }

    return null;
  }

  /// 检查 ripgrep 是否可用。
  static Future<bool> isRipgrepAvailable() async {
    return await resolveRipgrepPath() != null;
  }

  /// 清除缓存的 ripgrep 路径（供测试使用）。
  static void clearRipgrepPathCache() {
    _cachedRgPath = null;
  }

  /// 执行进程，正确处理异常并返回统一的 ProcessResult。
  ///
  /// [workingDirectory]：工作目录。如果为空，使用当前目录。
  /// [inheritEnvironment]：是否继承父进程的环境变量。默认 true。
  static Future<ProcessResult> runProcessSafely(
    String executable,
    List<String> args, {
    String? workingDirectory,
    bool inheritEnvironment = true,
  }) async {
    try {
      return await Process.run(
        executable,
        args,
        workingDirectory: workingDirectory,
        environment: inheritEnvironment ? Platform.environment : null,
      );
    } on ProcessException catch (error) {
      return ProcessResult(
        0,
        127,
        '',
        'Process execution failed: ${error.message}',
      );
    } on FileSystemException catch (error) {
      return ProcessResult(0, 126, '', 'File system error: ${error.message}');
    } catch (error) {
      return ProcessResult(0, 1, '', 'Unexpected error: $error');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 2026-04-13 写操作权限确认支持
  // ══════════════════════════════════════════════════════════════════════════

  /// 写操作权限确认超时时间（5分钟）。
  static const int _writeConfirmationTimeoutMs = 300000;

  /// 请求用户确认写操作。
  ///
  /// 当 [requireWriteConfirmation] 为 true 且 [confirmWriteCommand] 回调存在时，
  /// 会向用户请求写操作审批。
  ///
  /// 如果用户批准或不需要确认，返回 null。
  /// 如果用户拒绝、超时或取消，返回相应的错误结果。
  static Future<AiToolExecutionResult?> requestWriteConfirmation({
    required String toolName,
    required String operationDescription,
    required String targetPath,
    required bool requireWriteConfirmation,
    required Future<bool> Function(BashCommandApprovalRequest request)?
    confirmWriteCommand,
    Future<void>? cancelSignal,
  }) async {
    // 如果不需要写确认，直接通过
    if (!requireWriteConfirmation) {
      return null;
    }

    // 如果需要确认但没有确认回调，这是一个配置错误，拒绝执行
    if (confirmWriteCommand == null) {
      return rejectedWriteResult(
        toolName: toolName,
        targetPath: targetPath,
        reason: '需要写操作确认但未提供确认回调，操作已拒绝执行。',
      );
    }

    final workingDirectory = p.dirname(targetPath);
    final request = BashCommandApprovalRequest(
      command: '$toolName $targetPath\n$operationDescription',
      workingDirectory: workingDirectory,
      isWriteCommand: true,
    );

    late final _WriteConfirmationOutcome outcome;
    try {
      final approvalFuture = confirmWriteCommand(request)
          .timeout(const Duration(milliseconds: _writeConfirmationTimeoutMs))
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
          cancelSignal.then((_) => const _WriteConfirmationOutcome.cancelled()),
        ]);
      }
    } on TimeoutException {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.rejected,
        command: '$toolName $targetPath',
        workingDirectory: workingDirectory,
        stdout: '',
        stderr: '写操作确认超时，用户未在规定时间内批准执行。',
        durationMs: 0,
        resultText: 'status: rejected\nreason: Write confirmation timed out.',
        isWriteCommand: true,
      );
    }

    if (outcome.cancelled) {
      return cancelledResult(
        command: '$toolName $targetPath',
        durationMs: 0,
        metadata: <String, Object?>{'write_confirmation_cancelled': true},
      );
    }

    if (!outcome.approved) {
      return rejectedWriteResult(
        toolName: toolName,
        targetPath: targetPath,
        reason: '用户拒绝了写操作确认请求。',
      );
    }

    // 用户已批准
    return null;
  }

  /// 生成写操作被拒绝的结果。
  static AiToolExecutionResult rejectedWriteResult({
    required String toolName,
    required String targetPath,
    required String reason,
  }) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.rejected,
      command: '$toolName $targetPath',
      workingDirectory: p.dirname(targetPath),
      stdout: '',
      stderr: reason,
      durationMs: 0,
      resultText: 'status: rejected\nreason: $reason',
      isWriteCommand: true,
      writeAnalysisReason: 'builtin file mutation tool requires confirmation',
    );
  }
}

/// 2026-04-13 写确认结果内部类型。
class _WriteConfirmationOutcome {
  const _WriteConfirmationOutcome.approved()
    : approved = true,
      cancelled = false;
  const _WriteConfirmationOutcome.rejected()
    : approved = false,
      cancelled = false;
  const _WriteConfirmationOutcome.cancelled()
    : approved = false,
      cancelled = true;

  final bool approved;
  final bool cancelled;
}

class ReplacementResult {
  const ReplacementResult.success(this.content)
    : success = true,
      errorMessage = '';
  const ReplacementResult.failure(this.errorMessage)
    : success = false,
      content = '';

  final bool success;
  final String content;
  final String errorMessage;
}
