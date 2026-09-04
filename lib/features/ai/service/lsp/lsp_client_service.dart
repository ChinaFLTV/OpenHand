import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../../../app/support/safe_subprocess.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_file_io.dart';
import '../../../../shared/util/bounded_json_conversion.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/message_frame_scan.dart';
import '../../../../shared/util/timer_safety.dart';
import '../../../../shared/util/workspace_root_resolver.dart';
import '../../model/ai_lsp_backend_catalog.dart';
import '../../model/ai_lsp_language_settings.dart';

enum AiLspBackendAvailability {
  available,
  unsupportedLanguage,
  executableNotFound,
}

const int _maxLspDocumentBytes = 16 * kBytesPerMiB;
const int _maxLspSessions = 8;
const int _maxConcurrentLspSessionStarts = 4;
const Duration _lspProcessStartTimeout = Duration(seconds: 10);
const Duration _lspSessionStartupTimeout = Duration(seconds: 30);

/// 将 LSP 文件 URI 转为平台路径，非文件 URI 保持原值。
String aiLspUriToPath(String value) {
  final uri = Uri.tryParse(value);
  if (uri?.scheme != 'file') return value;
  try {
    return uri!.toFilePath();
  } catch (error, stack) {
    silentLog('lsp_client_service', '转换文件 URI', error, stack);
    return value;
  }
}

int _validateLspDocumentText(String filePath, String text) {
  var bytes = 0;
  final units = text.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final unit = units[index];
    if (unit <= 0x7F) {
      bytes += 1;
    } else if (unit <= 0x7FF) {
      bytes += 2;
    } else if (unit >= 0xD800 &&
        unit <= 0xDBFF &&
        index + 1 < units.length &&
        units[index + 1] >= 0xDC00 &&
        units[index + 1] <= 0xDFFF) {
      bytes += 4;
      index++;
    } else {
      bytes += 3;
    }
    if (bytes > _maxLspDocumentBytes) {
      throw BoundedFileReadException(
        filePath: filePath,
        maxBytes: _maxLspDocumentBytes,
        failure: BoundedFileReadFailure.tooLarge,
      );
    }
  }
  return bytes;
}

class AiLspBackendResolution {
  const AiLspBackendResolution({
    required this.availability,
    required this.language,
    required this.rootPath,
    this.backendId,
    this.displayName,
    this.executable,
    this.executablePath,
    this.configuredInstallRoot,
    this.configuredVersion,
    this.configuredSdkPath,
    this.arguments = const <String>[],
  });

  final AiLspBackendAvailability availability;
  final String language;
  final String rootPath;
  final String? backendId;
  final String? displayName;
  final String? executable;
  final String? executablePath;
  final String? configuredInstallRoot;
  final String? configuredVersion;
  final String? configuredSdkPath;
  final List<String> arguments;

  bool get isAvailable => availability == AiLspBackendAvailability.available;

  String get cacheKey =>
      '$rootPath::$language::${backendId ?? 'unavailable'}::${executablePath ?? executable ?? ''}';
}

class AiLspPosition {
  const AiLspPosition({required this.line, required this.character});

  final int line;
  final int character;
}

class AiLspRange {
  const AiLspRange({required this.start, required this.end});

  final AiLspPosition start;
  final AiLspPosition end;
}

class AiLspLocation {
  const AiLspLocation({required this.filePath, required this.range});

  final String filePath;
  final AiLspRange range;

  int get line => range.start.line;
  int get character => range.start.character;
}

class AiLspWorkspaceSymbol {
  const AiLspWorkspaceSymbol({
    required this.name,
    required this.kind,
    required this.location,
    this.containerName,
    this.detail,
  });

  final String name;
  final int kind;
  final AiLspLocation location;
  final String? containerName;
  final String? detail;
}

class AiLspHoverResult {
  const AiLspHoverResult({required this.plainText, this.markdown, this.range});

  final String plainText;
  final String? markdown;
  final AiLspRange? range;

  String get renderedText =>
      markdown?.trim().isNotEmpty == true ? markdown! : plainText;
}

class AiLspParameterInformation {
  const AiLspParameterInformation({
    required this.label,
    this.labelStart,
    this.labelEnd,
    this.documentationPlainText = '',
    this.documentationMarkdown,
  });

  final String label;
  final int? labelStart;
  final int? labelEnd;
  final String documentationPlainText;
  final String? documentationMarkdown;

  bool get hasExplicitOffsets =>
      labelStart != null && labelEnd != null && labelEnd! > labelStart!;
}

class AiLspSignatureInformation {
  const AiLspSignatureInformation({
    required this.label,
    this.documentationPlainText = '',
    this.documentationMarkdown,
    this.parameters = const <AiLspParameterInformation>[],
  });

  final String label;
  final String documentationPlainText;
  final String? documentationMarkdown;
  final List<AiLspParameterInformation> parameters;
}

class AiLspSignatureHelp {
  const AiLspSignatureHelp({
    this.signatures = const <AiLspSignatureInformation>[],
    this.activeSignature = 0,
    this.activeParameter = 0,
  });

  final List<AiLspSignatureInformation> signatures;
  final int activeSignature;
  final int activeParameter;

  bool get isEmpty => signatures.isEmpty;

  AiLspSignatureInformation? get selectedSignature {
    if (signatures.isEmpty) {
      return null;
    }
    final index = activeSignature.clamp(0, signatures.length - 1);
    return signatures[index];
  }

  AiLspParameterInformation? get selectedParameter {
    final signature = selectedSignature;
    if (signature == null || signature.parameters.isEmpty) {
      return null;
    }
    final index = activeParameter.clamp(0, signature.parameters.length - 1);
    return signature.parameters[index];
  }
}

class AiLspDocumentSymbol {
  const AiLspDocumentSymbol({
    required this.name,
    required this.kind,
    required this.range,
    this.detail,
    this.children = const <AiLspDocumentSymbol>[],
  });

  final String name;
  final int kind;
  final AiLspRange range;
  final String? detail;
  final List<AiLspDocumentSymbol> children;
}

class AiLspDiagnostic {
  const AiLspDiagnostic({
    required this.range,
    required this.message,
    this.code,
    this.severity,
    this.source,
  });

  final AiLspRange range;
  final String message;
  final String? code;
  final int? severity;
  final String? source;
}

class AiLspTextEdit {
  const AiLspTextEdit({required this.range, required this.newText});

  final AiLspRange range;
  final String newText;
}

class AiLspWorkspaceFileEdit {
  const AiLspWorkspaceFileEdit({required this.filePath, required this.edits});

  final String filePath;
  final List<AiLspTextEdit> edits;
}

class AiLspWorkspaceEdit {
  const AiLspWorkspaceEdit({
    this.fileEdits = const <AiLspWorkspaceFileEdit>[],
    this.unsupportedOperationsCount = 0,
  });

  final List<AiLspWorkspaceFileEdit> fileEdits;
  final int unsupportedOperationsCount;

  bool get isEmpty => fileEdits.isEmpty;
  bool get hasUnsupportedOperations => unsupportedOperationsCount > 0;

  int get fileCount => fileEdits.length;

  int get editCount =>
      fileEdits.fold<int>(0, (total, item) => total + item.edits.length);
}

class AiLspCommand {
  const AiLspCommand({
    required this.title,
    required this.command,
    this.arguments = const <Object?>[],
  });

  final String title;
  final String command;
  final List<Object?> arguments;
}

class AiLspCodeAction {
  const AiLspCodeAction({
    required this.title,
    this.kind,
    this.isPreferred = false,
    this.disabledReason,
    this.edit,
    this.command,
    this.raw,
  });

  final String title;
  final String? kind;
  final bool isPreferred;
  final String? disabledReason;
  final AiLspWorkspaceEdit? edit;
  final AiLspCommand? command;
  final Map<String, Object?>? raw;

  bool get isDisabled => disabledReason?.trim().isNotEmpty == true;
  bool get canResolve => raw != null;
}

class AiLspPrepareRenameResult {
  const AiLspPrepareRenameResult({this.range, this.placeholder});

  final AiLspRange? range;
  final String? placeholder;
}

/// LSP 服务端返回的单个补全项。
class AiLspCompletionItem {
  const AiLspCompletionItem({
    required this.label,
    this.kind,
    this.detail,
    this.insertText,
    this.filterText,
    this.sortText,
  });

  final String label;

  /// CompletionItemKind 枚举值（1=Text, 2=Method, 3=Function, 4=Constructor,
  /// 5=Field, 6=Variable, 7=Class, 8=Interface, 9=Module, 10=Property,
  /// 11=Unit, 12=Value, 13=Enum, 14=Keyword, 15=Snippet, 16=Color,
  /// 17=File, 18=Reference, 19=Folder, 20=EnumMember, 21=Constant,
  /// 22=Struct, 23=Event, 24=Operator, 25=TypeParameter)
  final int? kind;
  final String? detail;
  final String? insertText;
  final String? filterText;
  final String? sortText;

  /// 选中后实际插入的文本。
  String get effectiveInsertText => insertText ?? label;

  /// 用于匹配输入前缀的过滤文本。
  String get effectiveFilterText => filterText ?? label;
}

typedef AiLspProcessLauncher =
    Future<Process> Function({
      required AiLspBackendResolution backend,
      Map<String, String>? environment,
    });

Future<Process> _launchAiLspProcess({
  required AiLspBackendResolution backend,
  Map<String, String>? environment,
}) {
  return startTrackedProcessBounded(
    backend.executablePath!,
    backend.arguments,
    timeout: _lspProcessStartTimeout,
    tag: 'lsp_client_service',
    startInNewProcessGroup: true,
    workingDirectory: backend.rootPath,
    environment: environment,
  );
}

class AiLspClientService {
  AiLspClientService._()
    : _processLauncher = _launchAiLspProcess,
      _requestTimeout = _defaultRequestTimeout,
      _initializationSettleDelay = _defaultInitializationSettleDelay,
      _shutdownRequestDelay = _defaultShutdownRequestDelay,
      _shutdownExitDelay = _defaultShutdownExitDelay,
      _startupDisposeWait = _defaultStartupDisposeWait,
      _sessionStartupTimeout = _lspSessionStartupTimeout;

  static final AiLspClientService instance = AiLspClientService._();
  static final RegExp _markdownFenceStartPattern = RegExp(r'^```[\w-]*\n');
  static final RegExp _markdownFenceEndPattern = RegExp(r'\n```$');

  static const Duration _defaultRequestTimeout = Duration(seconds: 15);
  static const Duration _defaultInitializationSettleDelay = Duration(
    milliseconds: 350,
  );
  static const Duration _defaultShutdownRequestDelay = Duration(
    milliseconds: 180,
  );
  static const Duration _defaultShutdownExitDelay = Duration(milliseconds: 80);
  static const Duration _defaultStartupDisposeWait = Duration(seconds: 3);
  static const Duration _commandPathLookupTimeout = Duration(seconds: 3);
  static const Duration _configuredRootProbeIdleTimeout = Duration(
    milliseconds: 500,
  );
  static const Duration _configuredRootProbeTotalTimeout = Duration(seconds: 3);
  static const int _commandPathMaxStdoutBytes = 64 * kBytesPerKiB;
  static const int _commandPathMaxStderrBytes = 16 * kBytesPerKiB;
  static const int _commandPathCacheLimit = 128;

  final Map<String, _AiLspSession> _sessions = <String, _AiLspSession>{};
  final Map<String, _AiLspSessionStart> _sessionStarts =
      <String, _AiLspSessionStart>{};
  final Set<_AiLspSession> _trackedSessions = HashSet<_AiLspSession>.identity();
  final Set<_AiLspSession> _startingSessions =
      HashSet<_AiLspSession>.identity();
  final Stopwatch _commandPathCacheStopwatch = Stopwatch()..start();
  final Map<String, ({String? path, Duration resolvedAt})> _commandPathCache =
      <String, ({String? path, Duration resolvedAt})>{};

  /// 「未找到」的负缓存有效期。命中路径可以长期缓存（可执行文件不会自己消失），
  /// 但未找到必须过期：用户很可能刚在内置终端里 `npm i -g pyright`，或刚走完
  /// 托管安装流程，永久负缓存会让他必须重启应用才能用上。
  static const Duration _negativeCommandPathTtl = Duration(minutes: 2);
  final AiLspProcessLauncher _processLauncher;
  final Duration _requestTimeout;
  final Duration _initializationSettleDelay;
  final Duration _shutdownRequestDelay;
  final Duration _shutdownExitDelay;
  final Duration _startupDisposeWait;
  final Duration _sessionStartupTimeout;
  int _sessionGeneration = 0;
  Map<String, AiLspLanguageSettings> _baseLanguageSettings =
      const <String, AiLspLanguageSettings>{};
  Map<String, AiLspLanguageSettings> _projectLanguageSettingsOverride =
      const <String, AiLspLanguageSettings>{};
  Map<String, AiLspLanguageSettings> _effectiveLanguageSettings =
      const <String, AiLspLanguageSettings>{};
  Future<bool> Function(AiLspWorkspaceEdit edit)? _workspaceEditHandler;

  /// LSP 服务端推送文件诊断时触发；编辑器通过它实时更新，无需轮询。
  void Function(String filePath, List<AiLspDiagnostic> diagnostics)?
  _diagnosticsPushCallback;

  set diagnosticsPushCallback(
    void Function(String filePath, List<AiLspDiagnostic> diagnostics)? cb,
  ) {
    _diagnosticsPushCallback = cb;
  }

  static const Duration _diagnosticsWait = Duration(milliseconds: 400);

  set workspaceEditHandler(
    Future<bool> Function(AiLspWorkspaceEdit edit)? handler,
  ) {
    _workspaceEditHandler = handler;
  }

  void updateLanguageSettings(Map<String, AiLspLanguageSettings> settings) {
    final normalized = normalizeAiLspLanguageSettingsMap(settings);
    if (_sameLanguageSettings(_baseLanguageSettings, normalized)) {
      return;
    }
    _baseLanguageSettings = normalized;
    _refreshEffectiveLanguageSettings();
  }

  void updateProjectLanguageSettingsOverride(
    Map<String, AiLspLanguageSettings>? settings,
  ) {
    final normalized = normalizeAiLspLanguageSettingsMap(
      settings ?? const <String, AiLspLanguageSettings>{},
    );
    if (_sameLanguageSettings(_projectLanguageSettingsOverride, normalized)) {
      return;
    }
    _projectLanguageSettingsOverride = normalized;
    _refreshEffectiveLanguageSettings();
  }

  void _refreshEffectiveLanguageSettings() {
    final merged = <String, AiLspLanguageSettings>{
      for (final entry in _baseLanguageSettings.entries) entry.key: entry.value,
    };
    for (final entry in _projectLanguageSettingsOverride.entries) {
      final base = merged[entry.key] ?? const AiLspLanguageSettings();
      final effective = _mergeLanguageSettings(base, entry.value);
      if (effective.isEmpty) {
        merged.remove(entry.key);
      } else {
        merged[entry.key] = effective;
      }
    }
    final normalizedMerged = normalizeAiLspLanguageSettingsMap(merged);
    if (_sameLanguageSettings(_effectiveLanguageSettings, normalizedMerged)) {
      return;
    }
    _effectiveLanguageSettings = normalizedMerged;
    _commandPathCache.clear();
    unawaited(disposeAll());
  }

  Future<AiLspBackendResolution> resolveBackendForFile({
    required String filePath,
    String? language,
  }) async {
    final resolvedLanguage = normalizeAiLspLanguage(
      language ?? _languageFromPath(filePath),
    );
    final rootPath = await standardWorkspaceRootResolver.resolve(filePath);
    final configuredSettings = _effectiveLanguageSettings[resolvedLanguage];
    final candidate = _candidateForLanguage(
      resolvedLanguage,
      preferredBackendId: configuredSettings?.backendId,
    );
    if (candidate == null) {
      return AiLspBackendResolution(
        availability: AiLspBackendAvailability.unsupportedLanguage,
        language: resolvedLanguage,
        rootPath: rootPath,
      );
    }
    final configuredRoot = nullIfBlank(configuredSettings?.rootPath);
    final configuredSdk = nullIfBlank(configuredSettings?.sdkPath);
    final configuredVersion = nullIfBlank(configuredSettings?.version);
    if (configuredRoot != null) {
      final configuredExecutablePath =
          await _resolveExecutablePathFromConfiguredRoot(
            executable: candidate.executable,
            configuredRoot: configuredRoot,
          );
      if (configuredExecutablePath != null) {
        return AiLspBackendResolution(
          availability: AiLspBackendAvailability.available,
          language: resolvedLanguage,
          rootPath: rootPath,
          backendId: candidate.id,
          displayName: candidate.displayName,
          executable: candidate.executable,
          executablePath: configuredExecutablePath,
          configuredInstallRoot: configuredRoot,
          configuredVersion: configuredVersion,
          configuredSdkPath: configuredSdk,
          arguments: candidate.arguments,
        );
      }
      return AiLspBackendResolution(
        availability: AiLspBackendAvailability.executableNotFound,
        language: resolvedLanguage,
        rootPath: rootPath,
        backendId: candidate.id,
        displayName: candidate.displayName,
        executable: candidate.executable,
        configuredInstallRoot: configuredRoot,
        configuredVersion: configuredVersion,
        configuredSdkPath: configuredSdk,
        arguments: candidate.arguments,
      );
    }
    final executablePath = await _resolveCommandPath(candidate.executable);
    if (executablePath == null) {
      return AiLspBackendResolution(
        availability: AiLspBackendAvailability.executableNotFound,
        language: resolvedLanguage,
        rootPath: rootPath,
        backendId: candidate.id,
        displayName: candidate.displayName,
        executable: candidate.executable,
        configuredVersion: configuredVersion,
        configuredSdkPath: configuredSdk,
        arguments: candidate.arguments,
      );
    }
    return AiLspBackendResolution(
      availability: AiLspBackendAvailability.available,
      language: resolvedLanguage,
      rootPath: rootPath,
      backendId: candidate.id,
      displayName: candidate.displayName,
      executable: candidate.executable,
      executablePath: executablePath,
      configuredInstallRoot: configuredRoot,
      configuredVersion: configuredVersion,
      configuredSdkPath: configuredSdk,
      arguments: candidate.arguments,
    );
  }

  Future<({AiLspBackendResolution backend, _AiLspSession? session})>
  _resolveSyncedSessionForFile({
    required String filePath,
    required String? documentText,
    String? language,
  }) async {
    if (documentText != null) {
      _validateLspDocumentText(filePath, documentText);
    }
    final backend = await resolveBackendForFile(
      filePath: filePath,
      language: language,
    );
    if (!backend.isAvailable) return (backend: backend, session: null);
    final session = await _getOrCreateSession(backend);
    await session.ensureDocumentSynced(
      filePath: filePath,
      language: backend.language,
      text: documentText,
    );
    return (backend: backend, session: session);
  }

  /// 解析后端并同步文档，随后在会话上执行 [run]。
  ///
  /// 后端不可用时：未提供 [whenUnavailable] 则抛 [StateError]（编辑类能力必须
  /// 让调用方看见失败）；提供了则返回其结果，让补全、代码动作、格式化这类
  /// 查询能力静默降级为空结果，不打断编辑流。
  Future<T> _onSyncedSession<T>({
    required String filePath,
    required String? language,
    required String? documentText,
    required Future<T> Function(_AiLspSession session) run,
    T Function()? whenUnavailable,
  }) async {
    final resolved = await _resolveSyncedSessionForFile(
      filePath: filePath,
      language: language,
      documentText: documentText,
    );
    final session = resolved.session;
    if (session == null) {
      final fallback = whenUnavailable;
      if (fallback == null) {
        throw StateError(_resolutionErrorMessage(resolved.backend));
      }
      return fallback();
    }
    return run(session);
  }

  Future<Object?> request({
    required String operation,
    required String filePath,
    required int line,
    required int character,
    String? language,
    String? documentText,
  }) {
    return _onSyncedSession(
      filePath: filePath,
      language: language,
      documentText: documentText,
      run: (session) => session.request(
        operation: operation,
        filePath: filePath,
        line: line,
        character: character,
      ),
    );
  }

  bool _sameLanguageSettings(
    Map<String, AiLspLanguageSettings> left,
    Map<String, AiLspLanguageSettings> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  AiLspLanguageSettings _mergeLanguageSettings(
    AiLspLanguageSettings base,
    AiLspLanguageSettings override,
  ) {
    return AiLspLanguageSettings(
      backendId: nullIfBlank(override.backendId) ?? base.backendId,
      rootPath: nullIfBlank(override.rootPath) ?? base.rootPath,
      sdkPath: nullIfBlank(override.sdkPath) ?? base.sdkPath,
      version: nullIfBlank(override.version) ?? base.version,
    );
  }

  Future<List<AiLspLocation>> goToDefinition({
    required String filePath,
    required int line,
    required int character,
    String? language,
    String? documentText,
  }) async {
    final result = await request(
      operation: 'goToDefinition',
      filePath: filePath,
      line: line,
      character: character,
      language: language,
      documentText: documentText,
    );
    return parseLocations(result);
  }

  Future<List<AiLspLocation>> findReferences({
    required String filePath,
    required int line,
    required int character,
    String? language,
    String? documentText,
  }) async {
    final result = await request(
      operation: 'findReferences',
      filePath: filePath,
      line: line,
      character: character,
      language: language,
      documentText: documentText,
    );
    return parseLocations(result);
  }

  Future<AiLspPrepareRenameResult?> prepareRename({
    required String filePath,
    required int line,
    required int character,
    String? language,
    String? documentText,
  }) {
    return _onSyncedSession(
      filePath: filePath,
      language: language,
      documentText: documentText,
      run: (session) async => parsePrepareRename(
        await session.prepareRename(
          filePath: filePath,
          line: line,
          character: character,
        ),
      ),
    );
  }

  Future<AiLspWorkspaceEdit> renameSymbol({
    required String filePath,
    required int line,
    required int character,
    required String newName,
    String? language,
    String? documentText,
  }) {
    return _onSyncedSession(
      filePath: filePath,
      language: language,
      documentText: documentText,
      run: (session) async => parseWorkspaceEdit(
        await session.rename(
          filePath: filePath,
          line: line,
          character: character,
          newName: newName,
        ),
      ),
    );
  }

  Future<AiLspHoverResult?> hover({
    required String filePath,
    required int line,
    required int character,
    String? language,
    String? documentText,
  }) async {
    final result = await request(
      operation: 'hover',
      filePath: filePath,
      line: line,
      character: character,
      language: language,
      documentText: documentText,
    );
    return parseHover(result);
  }

  Future<List<AiLspCompletionItem>> completion({
    required String filePath,
    required int line,
    required int character,
    String? language,
    String? documentText,
    String? triggerCharacter,
    bool isRetrigger = false,
  }) {
    return _onSyncedSession(
      filePath: filePath,
      language: language,
      documentText: documentText,
      whenUnavailable: () => const <AiLspCompletionItem>[],
      run: (session) async => parseCompletionItems(
        await session.completion(
          filePath: filePath,
          line: line,
          character: character,
          triggerCharacter: triggerCharacter,
          isRetrigger: isRetrigger,
        ),
      ),
    );
  }

  Future<AiLspSignatureHelp?> signatureHelp({
    required String filePath,
    required int line,
    required int character,
    String? language,
    String? documentText,
    String? triggerCharacter,
    bool isRetrigger = false,
  }) {
    return _onSyncedSession(
      filePath: filePath,
      language: language,
      documentText: documentText,
      whenUnavailable: () => null,
      run: (session) async => parseSignatureHelp(
        await session.signatureHelp(
          filePath: filePath,
          line: line,
          character: character,
          triggerCharacter: triggerCharacter,
          isRetrigger: isRetrigger,
        ),
      ),
    );
  }

  Future<List<AiLspDocumentSymbol>> documentSymbols({
    required String filePath,
    String? language,
    String? documentText,
  }) async {
    final result = await request(
      operation: 'documentSymbol',
      filePath: filePath,
      line: 1,
      character: 1,
      language: language,
      documentText: documentText,
    );
    return parseDocumentSymbols(result);
  }

  Future<List<AiLspCodeAction>> codeActions({
    required String filePath,
    required AiLspRange range,
    List<AiLspDiagnostic> diagnostics = const <AiLspDiagnostic>[],
    String? language,
    String? documentText,
  }) {
    return _onSyncedSession(
      filePath: filePath,
      language: language,
      documentText: documentText,
      whenUnavailable: () => const <AiLspCodeAction>[],
      run: (session) async => parseCodeActions(
        await session.codeActions(
          filePath: filePath,
          range: range,
          diagnostics: diagnostics,
        ),
      ),
    );
  }

  Future<List<AiLspTextEdit>> formatDocument({
    required String filePath,
    required int tabSize,
    String? language,
    String? documentText,
    bool insertSpaces = true,
  }) {
    return _onSyncedSession(
      filePath: filePath,
      language: language,
      documentText: documentText,
      whenUnavailable: () => const <AiLspTextEdit>[],
      run: (session) async => _parseTextEdits(
        await session.formatDocument(
          filePath: filePath,
          tabSize: tabSize,
          insertSpaces: insertSpaces,
        ),
      ),
    );
  }

  Future<AiLspCodeAction> resolveCodeAction({
    required String filePath,
    required AiLspCodeAction action,
    String? language,
  }) async {
    final raw = action.raw;
    if (raw == null) {
      return action;
    }
    final backend = await resolveBackendForFile(
      filePath: filePath,
      language: language,
    );
    if (!backend.isAvailable) {
      throw StateError(_resolutionErrorMessage(backend));
    }
    final session = await _getOrCreateSession(backend);
    final result = await session.resolveCodeAction(raw);
    return _parseCodeAction(result) ?? action;
  }

  Future<List<AiLspWorkspaceSymbol>> workspaceSymbols({
    required String filePath,
    required String query,
    String? language,
  }) async {
    final trimmedQuery = nullIfBlank(query);
    if (trimmedQuery == null) {
      return const <AiLspWorkspaceSymbol>[];
    }
    final backend = await resolveBackendForFile(
      filePath: filePath,
      language: language,
    );
    if (!backend.isAvailable) {
      return const <AiLspWorkspaceSymbol>[];
    }
    final session = await _getOrCreateSession(backend);
    final result = await session.workspaceSymbols(query: trimmedQuery);
    return parseWorkspaceSymbols(result);
  }

  Future<Object?> executeCommand({
    required String filePath,
    required AiLspCommand command,
    String? language,
  }) async {
    final backend = await resolveBackendForFile(
      filePath: filePath,
      language: language,
    );
    if (!backend.isAvailable) {
      throw StateError(_resolutionErrorMessage(backend));
    }
    final session = await _getOrCreateSession(backend);
    return session.executeCommand(command);
  }

  Future<void> syncDocument({
    required String filePath,
    required String documentText,
    String? language,
  }) async {
    await _resolveSyncedSessionForFile(
      filePath: filePath,
      language: language,
      documentText: documentText,
    );
  }

  Future<List<AiLspDiagnostic>> diagnosticsForFile({
    required String filePath,
    String? language,
    String? documentText,
    bool waitForPublish = true,
  }) async {
    if (documentText != null) {
      _validateLspDocumentText(filePath, documentText);
    }
    final backend = await resolveBackendForFile(
      filePath: filePath,
      language: language,
    );
    if (!backend.isAvailable) {
      return const <AiLspDiagnostic>[];
    }
    final session = await _getOrCreateSession(backend);

    // 先同步文档，以确定内容是否实际变化。
    final didChange = await session.ensureDocumentSynced(
      filePath: filePath,
      language: backend.language,
      text: documentText,
    );

    if (!waitForPublish) {
      return session.diagnosticsForFile(filePath);
    }

    // 内容未变化时直接返回缓存诊断，无需等待服务端。
    if (!didChange) {
      return session.diagnosticsForFile(filePath);
    }

    // 内容变化后等待服务端发布最新诊断。
    return session.waitForDiagnostics(filePath, timeout: _diagnosticsWait);
  }

  Future<void> closeDocument({
    required String filePath,
    String? language,
  }) async {
    final backend = await resolveBackendForFile(
      filePath: filePath,
      language: language,
    );
    if (!backend.isAvailable) {
      return;
    }
    final session = _sessions[backend.cacheKey];
    if (session == null) {
      return;
    }
    await session.closeDocument(filePath);
  }

  Future<void> disposeAll() async {
    _sessionGeneration += 1;
    final sessions = <_AiLspSession>{..._trackedSessions, ..._startingSessions};
    final starts = List<_AiLspSessionStart>.of(_sessionStarts.values);
    _sessions.clear();
    _sessionStarts.clear();

    // 启动 Future 可能仍未完成，因此先请求关闭；会话会记住取消状态并清理迟到进程。
    final shutdowns = sessions
        .map((session) => session.shutdown())
        .toList(growable: false);
    await Future.wait<void>(<Future<void>>[
      ...shutdowns,
      ...starts.map((start) async {
        try {
          final session = await start.future.timeout(_startupDisposeWait);
          await session.shutdown();
        } on TimeoutException {
          // Process.start 无法主动取消；会话已标记关闭，initialize 会终止迟到进程，
          // 当前释放流程只做有界等待。
        } catch (_) {
          // 初始化异常交给原调用方；释放流程只保证相关资源得到清理。
        }
      }),
    ]);
  }

  Future<_AiLspSession> _getOrCreateSession(
    AiLspBackendResolution backend,
  ) async {
    final cacheKey = backend.cacheKey;
    final existing = _sessions[cacheKey];
    if (existing != null && existing.isAlive) {
      existing.touch();
      return existing;
    }
    if (existing != null) {
      _sessions.remove(cacheKey);
      unawaited(existing.shutdown());
    }

    final inFlight = _sessionStarts[cacheKey];
    if (inFlight != null) {
      return inFlight.future;
    }
    if (_startingSessions.any(
      (session) => session.backend.cacheKey == cacheKey,
    )) {
      throw StateError('该工作区的上一个 LSP 会话仍在关闭。');
    }
    if (_startingSessions.length >= _maxConcurrentLspSessionStarts) {
      throw StateError('LSP 会话启动数已达到上限：$_maxConcurrentLspSessionStarts。');
    }
    final reservedSessions = HashSet<_AiLspSession>.identity()
      ..addAll(_trackedSessions)
      ..addAll(_startingSessions);
    if (reservedSessions.length >= _maxLspSessions) {
      throw StateError('LSP 会话数已达到上限：$_maxLspSessions。');
    }

    final generation = _sessionGeneration;
    late final _AiLspSession session;
    session = _AiLspSession(
      backend: backend,
      processLauncher: _processLauncher,
      requestTimeout: _requestTimeout,
      initializationSettleDelay: _initializationSettleDelay,
      shutdownRequestDelay: _shutdownRequestDelay,
      shutdownExitDelay: _shutdownExitDelay,
      workspaceEditHandlerProvider: () => _workspaceEditHandler,
      diagnosticsPushCallbackProvider: () => _diagnosticsPushCallback,
      onTerminated: () {
        _trackedSessions.remove(session);
        if (identical(_sessions[cacheKey], session)) {
          _sessions.remove(cacheKey);
        }
      },
    );
    _trackedSessions.add(session);
    _startingSessions.add(session);
    final rawFuture = _initializeSession(
      cacheKey: cacheKey,
      generation: generation,
      session: session,
    );
    final future = rawFuture.timeout(
      _sessionStartupTimeout,
      onTimeout: () {
        unawaited(session.shutdown());
        throw TimeoutException('LSP 会话启动超时。', _sessionStartupTimeout);
      },
    );
    final start = _AiLspSessionStart(session: session, future: future);
    _sessionStarts[cacheKey] = start;
    return future;
  }

  Future<_AiLspSession> _initializeSession({
    required String cacheKey,
    required int generation,
    required _AiLspSession session,
  }) async {
    try {
      await session.initialize();
      if (generation != _sessionGeneration) {
        throw StateError('LSP 会话在启动期间已被释放。');
      }
      if (!session.isAlive) {
        throw StateError('LSP 进程在会话启动期间已退出。');
      }

      // 仅当前代次可登记已初始化会话，释放后迟到的启动结果不能覆盖同键新会话。
      _sessions[cacheKey] = session;
      return session;
    } catch (_) {
      await session.shutdown();
      rethrow;
    } finally {
      _startingSessions.remove(session);
      final start = _sessionStarts[cacheKey];
      if (start != null && identical(start.session, session)) {
        _sessionStarts.remove(cacheKey);
      }
    }
  }

  Future<String?> _resolveCommandPath(String executable) async {
    final normalizedExecutable = executable.trim();
    if (normalizedExecutable.isEmpty) return null;
    final cached = _commandPathCache[normalizedExecutable];
    if (cached != null) {
      if (cached.path != null) return cached.path;
      if (_commandPathCacheStopwatch.elapsed - cached.resolvedAt <
          _negativeCommandPathTtl) {
        return null;
      }
      _commandPathCache.remove(normalizedExecutable);
    }
    // PATH 查询受时限约束；超时不缓存以便重试，未找到则缓存空值避免重复拉起进程。
    var timedOut = false;
    final result = await runProcessWithTimeout(
      Platform.isWindows ? 'where' : 'which',
      <String>[normalizedExecutable],
      timeout: _commandPathLookupTimeout,
      tag: 'lsp_client_service.path_lookup',
      maxStdoutBytes: _commandPathMaxStdoutBytes,
      maxStderrBytes: _commandPathMaxStderrBytes,
      timeoutResultBuilder: (pid, stdout, stderr) {
        timedOut = true;
        return ProcessResult(pid, -1, stdout, stderr);
      },
    );
    if (timedOut) {
      silentLog(
        'lsp_client_service',
        '查询 LSP 命令路径超时',
        '可执行文件=$normalizedExecutable',
      );
      return null;
    }
    if (result?.exitCode == 0) {
      final trimmed = '${result!.stdout}'.trim();
      if (trimmed.isNotEmpty) {
        final path = const LineSplitter().convert(trimmed).first.trim();
        _rememberCommandPath(normalizedExecutable, path);
        return path;
      }
    }
    _rememberCommandPath(normalizedExecutable, null);
    return null;
  }

  void _rememberCommandPath(String executable, String? path) {
    if (_commandPathCache.length >= _commandPathCacheLimit) {
      _commandPathCache.remove(_commandPathCache.keys.first);
    }
    _commandPathCache[executable] = (
      path: path,
      resolvedAt: _commandPathCacheStopwatch.elapsed,
    );
  }

  static String? _languageFromPath(String filePath) {
    final basename = p.basename(filePath).toLowerCase();
    // 处理没有标准扩展名的特殊文件名。
    if (basename == 'dockerfile' || basename.startsWith('dockerfile.')) {
      return 'dockerfile';
    }
    final ext = p.extension(filePath).toLowerCase();
    return switch (ext) {
      '.dart' => 'dart',
      '.py' || '.pyi' => 'python',
      '.js' || '.mjs' || '.cjs' => 'javascript',
      '.jsx' => 'javascript',
      '.ts' || '.mts' || '.cts' => 'typescript',
      '.tsx' => 'typescript',
      '.go' => 'go',
      '.rs' => 'rust',
      '.java' => 'java',
      '.kt' || '.kts' => 'kotlin',
      '.swift' => 'swift',
      '.c' => 'c',
      '.cc' || '.cpp' || '.cxx' || '.c++' => 'cpp',
      '.h' || '.hpp' || '.hh' || '.hxx' || '.h++' => 'cpp',
      '.m' => 'objectivec',
      '.mm' => 'objectivecpp',
      '.cs' => 'csharp',
      '.fs' || '.fsi' || '.fsx' || '.fsscript' => 'fsharp',
      '.php' => 'php',
      '.rb' || '.rake' || '.gemspec' || '.ru' => 'ruby',
      '.sh' || '.bash' || '.zsh' || '.ksh' => 'shell',
      '.html' || '.htm' => 'html',
      '.css' => 'css',
      '.scss' || '.less' => 'css',
      '.json' || '.jsonc' => 'json',
      '.yaml' || '.yml' => 'yaml',
      '.vue' => 'vue',
      '.svelte' => 'svelte',
      '.astro' => 'astro',
      '.lua' => 'lua',
      '.zig' || '.zon' => 'zig',
      '.ex' || '.exs' => 'elixir',
      '.erl' || '.hrl' => 'erlang',
      '.tf' || '.tfvars' => 'terraform',
      '.typ' || '.typc' => 'typst',
      '.clj' || '.cljs' || '.cljc' || '.edn' => 'clojure',
      '.hs' || '.lhs' => 'haskell',
      '.ml' || '.mli' => 'ocaml',
      '.gleam' => 'gleam',
      '.jl' => 'julia',
      '.r' || '.R' => 'r',
      '.scala' || '.sc' => 'scala',
      '.pl' || '.pm' => 'perl',
      '.toml' => 'toml',
      '.graphql' || '.gql' => 'graphql',
      '.prisma' => 'prisma',
      '.sql' => 'sql',
      '.md' || '.markdown' => 'markdown',
      _ => null,
    };
  }

  static String _documentLanguageId(String language) {
    return switch (normalizeAiLspLanguage(language)) {
      'shell' => 'shellscript',
      'plaintext' => 'plaintext',
      final normalized => normalized,
    };
  }

  static AiLspBackendDescriptor? _candidateForLanguage(
    String language, {
    String? preferredBackendId,
  }) {
    final normalized = normalizeAiLspLanguage(language);
    final trimmedPreferredBackendId = nullIfBlank(preferredBackendId);
    if (trimmedPreferredBackendId != null) {
      final preferred = aiLspBackendById(trimmedPreferredBackendId);
      if (preferred != null && preferred.languages.contains(normalized)) {
        return preferred;
      }
    }
    final candidates = aiLspBackendsForLanguage(normalized);
    if (candidates.isNotEmpty) {
      return candidates.first;
    }
    return null;
  }

  static Future<String?> _resolveExecutablePathFromConfiguredRoot({
    required String executable,
    required String configuredRoot,
  }) async {
    final trimmedRoot = nullIfBlank(configuredRoot);
    if (trimmedRoot == null) {
      return null;
    }
    final stopwatch = Stopwatch()..start();
    Future<FileSystemEntityType> probeType(String path) async {
      final remaining = _configuredRootProbeTotalTimeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        return FileSystemEntityType.notFound;
      }
      final timeout = remaining < _configuredRootProbeIdleTimeout
          ? remaining
          : _configuredRootProbeIdleTimeout;
      try {
        return await FileSystemEntity.type(path).timeout(timeout);
      } on FileSystemException {
        return FileSystemEntityType.notFound;
      } on TimeoutException {
        return FileSystemEntityType.notFound;
      }
    }

    final rootType = await probeType(trimmedRoot);
    if (rootType == FileSystemEntityType.file) {
      return p.normalize(trimmedRoot);
    }
    if (rootType != FileSystemEntityType.directory) {
      return null;
    }

    final executableNames = <String>{
      executable,
      if (Platform.isWindows) ...<String>[
        '$executable.exe',
        '$executable.cmd',
        '$executable.bat',
      ],
    };
    final candidateDirectories = <String>[
      trimmedRoot,
      p.join(trimmedRoot, 'bin'),
      p.join(trimmedRoot, 'Scripts'),
      p.join(trimmedRoot, 'node_modules', '.bin'),
    ];

    for (final directoryPath in candidateDirectories) {
      for (final executableName in executableNames) {
        final candidatePath = p.join(directoryPath, executableName);
        if (await probeType(candidatePath) == FileSystemEntityType.file) {
          return p.normalize(candidatePath);
        }
      }
    }
    return null;
  }

  static String _resolutionErrorMessage(AiLspBackendResolution resolution) {
    return switch (resolution.availability) {
      AiLspBackendAvailability.unsupportedLanguage =>
        '语言“${resolution.language}”没有对应的 LSP 后端。',
      AiLspBackendAvailability.executableNotFound =>
        '未在 PATH 中找到 LSP 后端“${resolution.displayName ?? resolution.backendId}”。',
      AiLspBackendAvailability.available => 'LSP 后端可用。',
    };
  }

  static List<AiLspLocation> parseLocations(Object? result) {
    if (result == null) {
      return const <AiLspLocation>[];
    }
    final items = <Map<String, Object?>>[];
    if (result is List) {
      for (final item in result) {
        if (item is Map<String, Object?>) {
          items.add(item);
        }
      }
    } else if (result is Map<String, Object?>) {
      items.add(result);
    }
    final locations = <AiLspLocation>[];
    for (final item in items) {
      final uri = item['uri'] as String? ?? item['targetUri'] as String?;
      final range = _parseRange(
        item['range'] as Map<String, Object?>? ??
            item['targetSelectionRange'] as Map<String, Object?>? ??
            item['targetRange'] as Map<String, Object?>?,
      );
      if (uri == null || range == null) {
        continue;
      }
      locations.add(AiLspLocation(filePath: aiLspUriToPath(uri), range: range));
    }
    return List<AiLspLocation>.unmodifiable(locations);
  }

  static AiLspHoverResult? parseHover(Object? result) {
    if (result is! Map<String, Object?>) {
      return null;
    }
    final contents = result['contents'];
    if (contents == null) {
      return null;
    }
    final parts = _flattenHoverContents(contents);
    if (parts.isEmpty) {
      return null;
    }
    final markdownParts = trimmedNonEmptyStrings(
      parts.map((part) => part.markdown),
    );
    final plainParts = trimmedNonEmptyStrings(
      parts.map((part) => part.plainText),
    );
    return AiLspHoverResult(
      plainText: plainParts.join('\n\n').trim(),
      markdown: markdownParts.isEmpty
          ? null
          : markdownParts.join('\n\n').trim(),
      range: _parseRange(result['range'] as Map<String, Object?>?),
    );
  }

  static List<AiLspDocumentSymbol> parseDocumentSymbols(Object? result) {
    if (result is! List) {
      return const <AiLspDocumentSymbol>[];
    }
    final symbols = result
        .whereType<Map<String, Object?>>()
        .map(_parseDocumentSymbol)
        .whereType<AiLspDocumentSymbol>()
        .toList(growable: false);
    return List<AiLspDocumentSymbol>.unmodifiable(symbols);
  }

  static AiLspPrepareRenameResult? parsePrepareRename(Object? result) {
    if (result == null) {
      return null;
    }
    if (result is Map<String, Object?>) {
      final range = _parseRange(result['range'] as Map<String, Object?>?);
      final placeholder = result['placeholder']?.toString();
      final defaultBehavior = result['defaultBehavior'] == true;
      if (range == null && !defaultBehavior) {
        return null;
      }
      return AiLspPrepareRenameResult(range: range, placeholder: placeholder);
    }
    return null;
  }

  static AiLspWorkspaceEdit parseWorkspaceEdit(Object? result) {
    if (result is! Map<String, Object?>) {
      return const AiLspWorkspaceEdit();
    }
    final fileEdits = <AiLspWorkspaceFileEdit>[];
    var unsupportedOperations = 0;

    final changes = result['changes'] as Map<String, Object?>?;
    if (changes != null) {
      for (final entry in changes.entries) {
        final edits = _parseTextEdits(entry.value);
        if (edits.isEmpty) {
          continue;
        }
        fileEdits.add(
          AiLspWorkspaceFileEdit(
            filePath: aiLspUriToPath(entry.key),
            edits: edits,
          ),
        );
      }
    }

    final documentChanges = result['documentChanges'] as List?;
    if (documentChanges != null) {
      for (final item in documentChanges.whereType<Map<String, Object?>>()) {
        final textDocument = item['textDocument'] as Map<String, Object?>?;
        final uri = textDocument?['uri'] as String?;
        if (uri == null) {
          unsupportedOperations += 1;
          continue;
        }
        final edits = _parseTextEdits(item['edits']);
        if (edits.isEmpty) {
          unsupportedOperations += 1;
          continue;
        }
        fileEdits.add(
          AiLspWorkspaceFileEdit(filePath: aiLspUriToPath(uri), edits: edits),
        );
      }
    }

    return AiLspWorkspaceEdit(
      fileEdits: List<AiLspWorkspaceFileEdit>.unmodifiable(fileEdits),
      unsupportedOperationsCount: unsupportedOperations,
    );
  }

  static AiLspSignatureHelp? parseSignatureHelp(Object? result) {
    if (result is! Map<String, Object?>) {
      return null;
    }
    final rawSignatures = result['signatures'];
    if (rawSignatures is! List) {
      return null;
    }
    final signatures = rawSignatures
        .whereType<Map<String, Object?>>()
        .map(_parseSignatureInformation)
        .whereType<AiLspSignatureInformation>()
        .toList(growable: false);
    if (signatures.isEmpty) {
      return null;
    }
    final maxSignatureIndex = signatures.length - 1;
    final activeSignature = ((result['activeSignature'] as int?) ?? 0).clamp(
      0,
      maxSignatureIndex,
    );
    final selectedSignature = signatures[activeSignature];
    final maxParameterIndex = math.max(
      0,
      selectedSignature.parameters.length - 1,
    );
    final activeParameter = ((result['activeParameter'] as int?) ?? 0).clamp(
      0,
      maxParameterIndex,
    );
    return AiLspSignatureHelp(
      signatures: List<AiLspSignatureInformation>.unmodifiable(signatures),
      activeSignature: activeSignature,
      activeParameter: activeParameter,
    );
  }

  static List<AiLspCodeAction> parseCodeActions(Object? result) {
    if (result is! List) {
      return const <AiLspCodeAction>[];
    }
    final actions = result
        .whereType<Object?>()
        .map(_parseCodeAction)
        .whereType<AiLspCodeAction>()
        .toList(growable: false);
    return List<AiLspCodeAction>.unmodifiable(actions);
  }

  static List<AiLspWorkspaceSymbol> parseWorkspaceSymbols(Object? result) {
    if (result is! List) {
      return const <AiLspWorkspaceSymbol>[];
    }
    final symbols = result
        .whereType<Map<String, Object?>>()
        .map(_parseWorkspaceSymbol)
        .whereType<AiLspWorkspaceSymbol>()
        .toList(growable: false);
    return List<AiLspWorkspaceSymbol>.unmodifiable(symbols);
  }

  static List<AiLspCompletionItem> parseCompletionItems(Object? result) {
    List<Object?> items;
    if (result is List) {
      items = result;
    } else if (result is Map<String, Object?>) {
      final innerItems = result['items'];
      if (innerItems is List) {
        items = innerItems;
      } else {
        return const <AiLspCompletionItem>[];
      }
    } else {
      return const <AiLspCompletionItem>[];
    }
    final completions = <AiLspCompletionItem>[];
    for (final raw in items) {
      if (raw is! Map<String, Object?>) continue;
      final label = raw['label'];
      if (label == null) continue;
      completions.add(
        AiLspCompletionItem(
          label: '$label',
          kind: raw['kind'] is int ? raw['kind'] as int : null,
          detail: raw['detail']?.toString(),
          insertText: raw['insertText']?.toString(),
          filterText: raw['filterText']?.toString(),
          sortText: raw['sortText']?.toString(),
        ),
      );
    }
    return List<AiLspCompletionItem>.unmodifiable(completions);
  }

  static AiLspSignatureInformation? _parseSignatureInformation(
    Map<String, Object?> raw,
  ) {
    final label = '${raw['label'] ?? ''}'.trim();
    if (label.isEmpty) {
      return null;
    }
    final documentation = _parseRichTextDocumentation(raw['documentation']);
    final parameters =
        (raw['parameters'] as List?)
            ?.whereType<Map<String, Object?>>()
            .map(_parseParameterInformation)
            .whereType<AiLspParameterInformation>()
            .toList(growable: false) ??
        const <AiLspParameterInformation>[];
    return AiLspSignatureInformation(
      label: label,
      documentationPlainText: documentation.plainText,
      documentationMarkdown: documentation.markdown,
      parameters: List<AiLspParameterInformation>.unmodifiable(parameters),
    );
  }

  static AiLspParameterInformation? _parseParameterInformation(
    Map<String, Object?> raw,
  ) {
    final labelValue = raw['label'];
    String label = '';
    int? labelStart;
    int? labelEnd;
    if (labelValue is String) {
      label = labelValue.trim();
    } else if (labelValue is List && labelValue.length >= 2) {
      final start = labelValue.first;
      final end = labelValue[1];
      if (start is num && end is num) {
        labelStart = start.toInt();
        labelEnd = end.toInt();
      }
    }
    final documentation = _parseRichTextDocumentation(raw['documentation']);
    if (label.isEmpty &&
        labelStart == null &&
        documentation.plainText.isEmpty) {
      return null;
    }
    return AiLspParameterInformation(
      label: label,
      labelStart: labelStart,
      labelEnd: labelEnd,
      documentationPlainText: documentation.plainText,
      documentationMarkdown: documentation.markdown,
    );
  }

  static List<AiLspTextEdit> _parseTextEdits(Object? result) {
    if (result is! List) {
      return const <AiLspTextEdit>[];
    }
    final edits = result
        .whereType<Map<String, Object?>>()
        .map((raw) {
          final range = _parseRange(raw['range'] as Map<String, Object?>?);
          if (range == null) {
            return null;
          }
          return AiLspTextEdit(
            range: range,
            newText: raw['newText']?.toString() ?? '',
          );
        })
        .whereType<AiLspTextEdit>()
        .toList(growable: false);
    return List<AiLspTextEdit>.unmodifiable(edits);
  }

  static AiLspCommand? _parseCommand(Object? raw, {String? fallbackTitle}) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final command = nullIfBlank(raw['command']?.toString());
    if (command == null) {
      return null;
    }
    final title =
        nullIfBlank(raw['title']?.toString()) ??
        nullIfBlank(fallbackTitle) ??
        command;
    final arguments = raw['arguments'] is List
        ? List<Object?>.unmodifiable(raw['arguments'] as List)
        : const <Object?>[];
    return AiLspCommand(title: title, command: command, arguments: arguments);
  }

  static AiLspCodeAction? _parseCodeAction(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final title = nullIfBlank(raw['title']?.toString());
    final directCommand = _parseCommand(raw, fallbackTitle: title);
    if (title == null) {
      return directCommand == null
          ? null
          : AiLspCodeAction(title: directCommand.title, command: directCommand);
    }
    final parsedEdit = parseWorkspaceEdit(raw['edit']);
    final edit = parsedEdit.isEmpty && !parsedEdit.hasUnsupportedOperations
        ? null
        : parsedEdit;
    final command = _parseCommand(raw['command'], fallbackTitle: title);
    final disabled = raw['disabled'] as Map<String, Object?>?;
    return AiLspCodeAction(
      title: title,
      kind: raw['kind']?.toString(),
      isPreferred: raw['isPreferred'] == true,
      disabledReason: disabled?['reason']?.toString(),
      edit: edit,
      command: command,
      raw: Map<String, Object?>.unmodifiable(raw),
    );
  }

  static AiLspDiagnostic _parseDiagnostic(Map<String, Object?> raw) {
    return AiLspDiagnostic(
      range:
          _parseRange(raw['range'] as Map<String, Object?>?) ??
          const AiLspRange(
            start: AiLspPosition(line: 1, character: 1),
            end: AiLspPosition(line: 1, character: 1),
          ),
      message: '${raw['message'] ?? ''}'.trim(),
      code: raw['code']?.toString(),
      severity: raw['severity'] as int?,
      source: raw['source']?.toString(),
    );
  }

  static AiLspDocumentSymbol? _parseDocumentSymbol(Map<String, Object?> raw) {
    final range = _parseRange(raw['range'] as Map<String, Object?>?);
    if (range == null) {
      final location = raw['location'] as Map<String, Object?>?;
      final locationRange = _parseRange(
        location?['range'] as Map<String, Object?>?,
      );
      if (locationRange == null) {
        return null;
      }
      return AiLspDocumentSymbol(
        name: '${raw['name'] ?? ''}'.trim(),
        kind: raw['kind'] as int? ?? 0,
        range: locationRange,
        detail: raw['detail']?.toString(),
      );
    }
    final children =
        (raw['children'] as List?)
            ?.whereType<Map<String, Object?>>()
            .map(_parseDocumentSymbol)
            .whereType<AiLspDocumentSymbol>()
            .toList(growable: false) ??
        const <AiLspDocumentSymbol>[];
    return AiLspDocumentSymbol(
      name: '${raw['name'] ?? ''}'.trim(),
      kind: raw['kind'] as int? ?? 0,
      range: range,
      detail: raw['detail']?.toString(),
      children: children,
    );
  }

  static AiLspWorkspaceSymbol? _parseWorkspaceSymbol(Map<String, Object?> raw) {
    final name = '${raw['name'] ?? ''}'.trim();
    if (name.isEmpty) {
      return null;
    }
    final locationRaw = raw['location'] as Map<String, Object?>?;
    final uri = locationRaw?['uri'] as String?;
    final range =
        _parseRange(locationRaw?['range'] as Map<String, Object?>?) ??
        _parseRange(raw['range'] as Map<String, Object?>?);
    if (uri == null || range == null) {
      return null;
    }
    return AiLspWorkspaceSymbol(
      name: name,
      kind: raw['kind'] as int? ?? 0,
      location: AiLspLocation(filePath: aiLspUriToPath(uri), range: range),
      containerName: raw['containerName']?.toString(),
      detail: raw['detail']?.toString(),
    );
  }

  static AiLspRange? _parseRange(Map<String, Object?>? raw) {
    if (raw == null) {
      return null;
    }
    final start = raw['start'] as Map<String, Object?>?;
    final end = raw['end'] as Map<String, Object?>?;
    if (start == null || end == null) {
      return null;
    }
    return AiLspRange(
      start: AiLspPosition(
        line: ((start['line'] as int?) ?? 0) + 1,
        character: ((start['character'] as int?) ?? 0) + 1,
      ),
      end: AiLspPosition(
        line: ((end['line'] as int?) ?? 0) + 1,
        character: ((end['character'] as int?) ?? 0) + 1,
      ),
    );
  }

  static List<_AiLspHoverPart> _flattenHoverContents(Object? contents) {
    if (contents == null) {
      return const <_AiLspHoverPart>[];
    }
    if (contents is String) {
      return <_AiLspHoverPart>[
        _AiLspHoverPart(markdown: contents, plainText: contents),
      ];
    }
    if (contents is Map<String, Object?>) {
      final kind = lowercaseStringFromValue(contents['kind']);
      if (contents.containsKey('value')) {
        final value = '${contents['value'] ?? ''}'.trim();
        final markdown = kind == 'markdown' ? value : value;
        final plain = _stripMarkdownFences(value);
        return <_AiLspHoverPart>[
          _AiLspHoverPart(markdown: markdown, plainText: plain),
        ];
      }
      if (contents.containsKey('language') && contents.containsKey('value')) {
        final language = '${contents['language'] ?? ''}'.trim();
        final value = '${contents['value'] ?? ''}'.trim();
        return <_AiLspHoverPart>[
          _AiLspHoverPart(
            markdown: '```$language\n$value\n```',
            plainText: value,
          ),
        ];
      }
      return <_AiLspHoverPart>[
        _AiLspHoverPart(markdown: '$contents', plainText: '$contents'),
      ];
    }
    if (contents is List) {
      final parts = <_AiLspHoverPart>[];
      for (final item in contents) {
        parts.addAll(_flattenHoverContents(item));
      }
      return parts;
    }
    return <_AiLspHoverPart>[
      _AiLspHoverPart(markdown: '$contents', plainText: '$contents'),
    ];
  }

  static ({String plainText, String? markdown}) _parseRichTextDocumentation(
    Object? contents,
  ) {
    final parts = _flattenHoverContents(contents);
    if (parts.isEmpty) {
      return (plainText: '', markdown: null);
    }
    final markdownParts = trimmedNonEmptyStrings(
      parts.map((part) => part.markdown),
    );
    final plainParts = trimmedNonEmptyStrings(
      parts.map((part) => part.plainText),
    );
    return (
      plainText: plainParts.join('\n\n').trim(),
      markdown: markdownParts.isEmpty
          ? null
          : markdownParts.join('\n\n').trim(),
    );
  }

  static String _stripMarkdownFences(String value) {
    return value
        .replaceAll(_markdownFenceStartPattern, '')
        .replaceAll(_markdownFenceEndPattern, '')
        .trim();
  }
}

class _AiLspHoverPart {
  const _AiLspHoverPart({required this.markdown, required this.plainText});

  final String markdown;
  final String plainText;
}

class _AiLspSessionStart {
  const _AiLspSessionStart({required this.session, required this.future});

  final _AiLspSession session;
  final Future<_AiLspSession> future;
}

class _AiLspSession {
  _AiLspSession({
    required this.backend,
    required this._processLauncher,
    required this._requestTimeout,
    required this._initializationSettleDelay,
    required this._shutdownRequestDelay,
    required this._shutdownExitDelay,
    required this._workspaceEditHandlerProvider,
    required this._diagnosticsPushCallbackProvider,
    required this._onTerminated,
  });

  final AiLspBackendResolution backend;
  final AiLspProcessLauncher _processLauncher;
  final Duration _requestTimeout;
  final Duration _initializationSettleDelay;
  final Duration _shutdownRequestDelay;
  final Duration _shutdownExitDelay;
  final Future<bool> Function(AiLspWorkspaceEdit edit)? Function()
  _workspaceEditHandlerProvider;
  final void Function(String filePath, List<AiLspDiagnostic> diagnostics)?
  Function()
  _diagnosticsPushCallbackProvider;
  final void Function() _onTerminated;
  Process? _process;
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  int _nextId = 1;
  final Map<int, Completer<Object?>> _pendingRequests =
      <int, Completer<Object?>>{};
  final List<int> _responseBuffer = <int>[];
  final Map<String, _AiLspOpenDocument> _openDocuments =
      <String, _AiLspOpenDocument>{};
  int _openDocumentBytes = 0;
  final Map<String, List<AiLspDiagnostic>> _diagnosticsByUri =
      <String, List<AiLspDiagnostic>>{};
  final Map<String, _AiLspDiagnosticsWaitGroup> _pendingDiagnostics =
      <String, _AiLspDiagnosticsWaitGroup>{};
  final ListQueue<Map<String, Object?>> _serverRequestQueue =
      ListQueue<Map<String, Object?>>();
  bool _serverRequestActive = false;
  Timer? _idleTimer;
  Future<void>? _shutdownFuture;
  bool _shutdownRequested = false;
  bool _terminationNotified = false;
  bool _bufferDrainScheduled = false;

  static const Duration _idleTimeout = Duration(seconds: 30);
  static const Duration _transportCancelTimeout = Duration(seconds: 1);
  static const Duration _processCleanupTimeout = Duration(seconds: 3);
  // 限制异常 LSP 服务端造成的请求堆积；单次请求最长 15 秒，正常负载不会触及上限。
  static const int _maxPendingRequests = 256;
  static const int _maxOpenDocuments = 64;
  static const int _maxOpenDocumentBytes = 32 * kBytesPerMiB;
  static const int _maxLspFrameBytes = 8 * kBytesPerMiB;
  static const int _maxLspHeaderBytes = 64 * kBytesPerKiB;
  static const BoundedJsonConversionConfig _lspJsonConversionConfig =
      kOpenHandProtocolJsonConversionConfig;
  static const int _maxMessagesPerDrain = 64;
  static const int _maxQueuedServerRequests = 32;
  static const Duration _serverRequestResponseTimeout = Duration(seconds: 15);
  static final int _maxContentLengthDigits = _maxLspFrameBytes
      .toString()
      .length;

  bool get isAlive => _process != null && !_shutdownRequested;

  void touch() {
    if (_shutdownRequested) {
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = startSafeTimer(_idleTimeout, shutdown);
  }

  Future<void> initialize() async {
    try {
      await _initializeOnce();
    } catch (_) {
      await shutdown();
      rethrow;
    }
  }

  Future<void> _initializeOnce() async {
    if (_shutdownRequested) {
      throw StateError('LSP 会话在启动前已被释放。');
    }
    final sdkPath = backend.configuredSdkPath;
    Map<String, String>? environment;
    if (sdkPath != null && sdkPath.isNotEmpty) {
      final sdkBin = p.join(sdkPath, 'bin');
      final currentPath = Platform.environment['PATH'] ?? '';
      final pathSeparator = Platform.isWindows ? ';' : ':';
      environment = <String, String>{
        'PATH': currentPath.isEmpty
            ? sdkBin
            : '$sdkBin$pathSeparator$currentPath',
      };
      if (backend.language == 'go') {
        environment['GOROOT'] = sdkPath;
      }
    }
    final process = await _processLauncher(
      backend: backend,
      environment: environment,
    );
    _process = process;
    if (_shutdownRequested) {
      await shutdown();
      throw StateError('LSP 会话在启动期间已被释放。');
    }
    unawaited(
      process.stdin.done.then<void>(
        (_) {
          _handleTransportFailure(
            process,
            StateError('LSP 标准输入流意外关闭。'),
            StackTrace.current,
          );
        },
        onError: (Object error, StackTrace stack) {
          _handleTransportFailure(process, error, stack);
        },
      ),
    );

    // 保存订阅供 shutdown 取消，避免进程终止后回调继续访问已清空的会话状态。
    _stdoutSubscription = process.stdout.listen(
      _onData,
      onError: (Object error, StackTrace stack) {
        silentLog('lsp_client_service', '读取 LSP 标准输出', error, stack);
        _handleTransportFailure(process, error, stack);
      },
      onDone: () {
        _handleTransportFailure(
          process,
          StateError('LSP 标准输出流意外关闭。'),
          StackTrace.current,
        );
      },
      cancelOnError: true,
    );
    unawaited(_watchProcessExit(process));
    // 持续排空 stderr，避免服务端写阻塞；同时保留订阅以便关闭时释放继承管道。
    _stderrSubscription = process.stderr.listen(
      (_) {},
      onError: (Object error, StackTrace stack) {
        silentLog(
          'lsp_client_service',
          '排空标准错误流（${backend.language}）',
          error,
          stack,
        );
      },
      cancelOnError: true,
    );

    final initResult = await _sendRequest('initialize', <String, Object?>{
      'processId': pid,
      'rootUri': Uri.directory(backend.rootPath).toString(),
      'workspaceFolders': <Map<String, Object?>>[
        <String, Object?>{
          'uri': Uri.directory(backend.rootPath).toString(),
          'name': p.basename(backend.rootPath),
        },
      ],
      'capabilities': <String, Object?>{
        'textDocument': <String, Object?>{
          'hover': <String, Object?>{
            'contentFormat': <String>['markdown', 'plaintext'],
          },
          'definition': <String, Object?>{'linkSupport': true},
          'references': <String, Object?>{},
          'implementation': <String, Object?>{},
          'completion': <String, Object?>{
            'completionItem': <String, Object?>{
              'snippetSupport': false,
              'deprecatedSupport': false,
              'insertReplaceSupport': false,
            },
            'contextSupport': true,
          },
          'signatureHelp': <String, Object?>{
            'contextSupport': true,
            'signatureInformation': <String, Object?>{
              'documentationFormat': <String>['markdown', 'plaintext'],
              'parameterInformation': <String, Object?>{
                'labelOffsetSupport': true,
              },
            },
          },
          'rename': <String, Object?>{'prepareSupport': true},
          'codeAction': <String, Object?>{
            'dynamicRegistration': false,
            'codeActionLiteralSupport': <String, Object?>{
              'codeActionKind': <String, Object?>{
                'valueSet': <String>[
                  '',
                  'quickfix',
                  'refactor',
                  'refactor.extract',
                  'refactor.inline',
                  'refactor.rewrite',
                  'source',
                  'source.fixAll',
                ],
              },
            },
            'resolveSupport': <String, Object?>{
              'properties': <String>['edit', 'command'],
            },
          },
          'documentSymbol': <String, Object?>{
            'hierarchicalDocumentSymbolSupport': true,
            'symbolKind': <String, Object?>{
              'valueSet': List<int>.generate(26, (index) => index + 1),
            },
          },
          'publishDiagnostics': <String, Object?>{},
          'synchronization': <String, Object?>{
            'didSave': true,
            'dynamicRegistration': false,
          },
        },
        'workspace': <String, Object?>{
          'applyEdit': true,
          'executeCommand': <String, Object?>{},
          'symbol': <String, Object?>{},
          'workspaceFolders': true,
        },
      },
    });
    if (initResult == null) {
      throw StateError('LSP 初始化返回了空结果。');
    }

    _sendNotification('initialized', <String, Object?>{});
    touch();
    final stillActive = await delayWhileContinuing(
      _initializationSettleDelay,
      () => !_shutdownRequested,
    );
    if (!stillActive) {
      throw StateError('LSP 会话在启动期间已被释放。');
    }
  }

  /// 向 LSP 服务端同步文档。发送 didOpen 或 didChange 时返回 `true`；
  /// 文本未变化且无需通知时返回 `false`。
  Future<bool> ensureDocumentSynced({
    required String filePath,
    required String language,
    String? text,
  }) async {
    if (text != null) {
      _validateLspDocumentText(filePath, text);
    }
    _ensureActive();
    final uri = Uri.file(filePath).toString();
    final currentText =
        text ??
        await readBoundedFileString(
          File(filePath),
          maxBytes: _maxLspDocumentBytes,
        );
    final currentBytes = _validateLspDocumentText(filePath, currentText);
    _ensureActive();
    final existing = _openDocuments[uri];
    if (existing == null) {
      _ensureOpenDocumentCapacity(
        uri: uri,
        requiredBytes: currentBytes,
        addsDocument: true,
      );
      _openDocuments[uri] = _AiLspOpenDocument(
        uri: uri,
        language: language,
        text: currentText,
        byteLength: currentBytes,
        version: 1,
      );
      _openDocumentBytes += currentBytes;
      _sendNotification('textDocument/didOpen', <String, Object?>{
        'textDocument': <String, Object?>{
          'uri': uri,
          'languageId': AiLspClientService._documentLanguageId(language),
          'version': 1,
          'text': currentText,
        },
      });
      // 清除旧诊断，等待服务端发布新结果。
      _diagnosticsByUri.remove(uri);
      touch();
      return true;
    }
    if (existing.text == currentText) {
      _touchOpenDocument(uri, existing);
      touch();
      return false;
    }
    _ensureOpenDocumentCapacity(
      uri: uri,
      requiredBytes: currentBytes,
      addsDocument: false,
    );
    _openDocumentBytes += currentBytes - existing.byteLength;
    existing
      ..text = currentText
      ..byteLength = currentBytes
      ..version += 1;
    _touchOpenDocument(uri, existing);
    _sendNotification('textDocument/didChange', <String, Object?>{
      'textDocument': <String, Object?>{
        'uri': uri,
        'version': existing.version,
      },
      'contentChanges': <Map<String, Object?>>[
        <String, Object?>{'text': currentText},
      ],
    });
    // 清除旧诊断，确保下一次 waitForDiagnostics 等待新结果。
    _diagnosticsByUri.remove(uri);
    touch();
    return true;
  }

  void _ensureOpenDocumentCapacity({
    required String uri,
    required int requiredBytes,
    required bool addsDocument,
  }) {
    final replacedBytes = _openDocuments[uri]?.byteLength ?? 0;
    while ((addsDocument && _openDocuments.length >= _maxOpenDocuments) ||
        _openDocumentBytes - replacedBytes + requiredBytes >
            _maxOpenDocumentBytes) {
      final candidate = _openDocuments.keys.firstWhere(
        (key) => key != uri,
        orElse: () => '',
      );
      if (candidate.isEmpty) {
        throw StateError('LSP 已打开文档容量耗尽。');
      }
      _removeOpenDocument(candidate, notifyServer: true);
    }
  }

  void _touchOpenDocument(String uri, _AiLspOpenDocument document) {
    _openDocuments.remove(uri);
    _openDocuments[uri] = document;
  }

  void _removeOpenDocument(String uri, {required bool notifyServer}) {
    final removed = _openDocuments.remove(uri);
    if (removed == null) return;
    _openDocumentBytes = math.max(0, _openDocumentBytes - removed.byteLength);
    _diagnosticsByUri.remove(uri);
    final pendingDiagnostics = _pendingDiagnostics.remove(uri)?.completer;
    if (pendingDiagnostics != null && !pendingDiagnostics.isCompleted) {
      pendingDiagnostics.complete(const <AiLspDiagnostic>[]);
    }
    if (notifyServer && isAlive) {
      _sendNotification('textDocument/didClose', <String, Object?>{
        'textDocument': <String, Object?>{'uri': uri},
      });
    }
  }

  Future<void> closeDocument(String filePath) async {
    if (!isAlive) {
      return;
    }
    final uri = Uri.file(filePath).toString();
    if (!_openDocuments.containsKey(uri)) {
      return;
    }
    _removeOpenDocument(uri, notifyServer: true);
    touch();
  }

  Future<Object?> workspaceSymbols({required String query}) async {
    touch();
    return _sendRequest('workspace/symbol', <String, Object?>{'query': query});
  }

  Future<Object?> completion({
    required String filePath,
    required int line,
    required int character,
    String? triggerCharacter,
    bool isRetrigger = false,
  }) async {
    touch();
    final trimmedTriggerCharacter = nullIfBlank(triggerCharacter);
    return _sendRequest('textDocument/completion', <String, Object?>{
      'textDocument': <String, Object?>{'uri': Uri.file(filePath).toString()},
      'position': <String, Object?>{
        'line': line - 1,
        'character': character - 1,
      },
      'context': <String, Object?>{
        'triggerKind': trimmedTriggerCharacter == null
            ? 1
            : (isRetrigger ? 3 : 2),
        if (trimmedTriggerCharacter != null)
          'triggerCharacter': trimmedTriggerCharacter,
      },
    });
  }

  Future<Object?> signatureHelp({
    required String filePath,
    required int line,
    required int character,
    String? triggerCharacter,
    bool isRetrigger = false,
  }) async {
    touch();
    final trimmedTriggerCharacter = nullIfBlank(triggerCharacter);
    return _sendRequest('textDocument/signatureHelp', <String, Object?>{
      'textDocument': <String, Object?>{'uri': Uri.file(filePath).toString()},
      'position': <String, Object?>{
        'line': line - 1,
        'character': character - 1,
      },
      'context': <String, Object?>{
        'triggerKind': trimmedTriggerCharacter == null
            ? 1
            : (isRetrigger ? 3 : 2),
        if (trimmedTriggerCharacter != null)
          'triggerCharacter': trimmedTriggerCharacter,
        'isRetrigger': isRetrigger,
      },
    });
  }

  Future<Object?> prepareRename({
    required String filePath,
    required int line,
    required int character,
  }) async {
    touch();
    return _sendRequest('textDocument/prepareRename', <String, Object?>{
      'textDocument': <String, Object?>{'uri': Uri.file(filePath).toString()},
      'position': <String, Object?>{
        'line': line - 1,
        'character': character - 1,
      },
    });
  }

  Future<Object?> rename({
    required String filePath,
    required int line,
    required int character,
    required String newName,
  }) async {
    touch();
    return _sendRequest('textDocument/rename', <String, Object?>{
      'textDocument': <String, Object?>{'uri': Uri.file(filePath).toString()},
      'position': <String, Object?>{
        'line': line - 1,
        'character': character - 1,
      },
      'newName': newName,
    });
  }

  Future<Object?> codeActions({
    required String filePath,
    required AiLspRange range,
    required List<AiLspDiagnostic> diagnostics,
  }) async {
    touch();
    return _sendRequest('textDocument/codeAction', <String, Object?>{
      'textDocument': <String, Object?>{'uri': Uri.file(filePath).toString()},
      'range': <String, Object?>{
        'start': <String, Object?>{
          'line': range.start.line - 1,
          'character': range.start.character - 1,
        },
        'end': <String, Object?>{
          'line': range.end.line - 1,
          'character': range.end.character - 1,
        },
      },
      'context': <String, Object?>{
        'diagnostics': diagnostics
            .map(
              (item) => <String, Object?>{
                'range': <String, Object?>{
                  'start': <String, Object?>{
                    'line': item.range.start.line - 1,
                    'character': item.range.start.character - 1,
                  },
                  'end': <String, Object?>{
                    'line': item.range.end.line - 1,
                    'character': item.range.end.character - 1,
                  },
                },
                'message': item.message,
                if (item.code != null) 'code': item.code,
                if (item.severity != null) 'severity': item.severity,
                if (item.source != null) 'source': item.source,
              },
            )
            .toList(growable: false),
      },
    });
  }

  Future<Object?> formatDocument({
    required String filePath,
    required int tabSize,
    required bool insertSpaces,
  }) async {
    touch();
    return _sendRequest('textDocument/formatting', <String, Object?>{
      'textDocument': <String, Object?>{'uri': Uri.file(filePath).toString()},
      'options': <String, Object?>{
        'tabSize': tabSize,
        'insertSpaces': insertSpaces,
      },
    });
  }

  Future<Object?> resolveCodeAction(Map<String, Object?> action) async {
    touch();
    return _sendRequest('codeAction/resolve', action);
  }

  Future<Object?> executeCommand(AiLspCommand command) async {
    touch();
    return _sendRequest('workspace/executeCommand', <String, Object?>{
      'command': command.command,
      if (command.arguments.isNotEmpty) 'arguments': command.arguments,
    });
  }

  Future<Object?> request({
    required String operation,
    required String filePath,
    required int line,
    required int character,
  }) async {
    final fileUri = Uri.file(filePath).toString();
    final position = <String, Object?>{
      'line': line - 1,
      'character': character - 1,
    };
    final textDocIdent = <String, Object?>{'uri': fileUri};

    touch();

    switch (operation) {
      case 'goToDefinition':
        return _sendRequest('textDocument/definition', <String, Object?>{
          'textDocument': textDocIdent,
          'position': position,
        });
      case 'findReferences':
        return _sendRequest('textDocument/references', <String, Object?>{
          'textDocument': textDocIdent,
          'position': position,
          'context': <String, Object?>{'includeDeclaration': true},
        });
      case 'hover':
        return _sendRequest('textDocument/hover', <String, Object?>{
          'textDocument': textDocIdent,
          'position': position,
        });
      case 'documentSymbol':
        return _sendRequest('textDocument/documentSymbol', <String, Object?>{
          'textDocument': textDocIdent,
        });
      case 'workspaceSymbol':
        return workspaceSymbols(query: p.basename(filePath));
      case 'goToImplementation':
        return _sendRequest('textDocument/implementation', <String, Object?>{
          'textDocument': textDocIdent,
          'position': position,
        });
      case 'prepareCallHierarchy':
        return _sendRequest(
          'textDocument/prepareCallHierarchy',
          <String, Object?>{'textDocument': textDocIdent, 'position': position},
        );
      case 'incomingCalls':
        final prepareIncoming = await _sendRequest(
          'textDocument/prepareCallHierarchy',
          <String, Object?>{'textDocument': textDocIdent, 'position': position},
        );
        final incomingItems = _parseCallHierarchyItems(prepareIncoming);
        if (incomingItems.isEmpty) {
          return const <Object?>[];
        }
        return _sendRequest('callHierarchy/incomingCalls', <String, Object?>{
          'item': incomingItems.first,
        });
      case 'outgoingCalls':
        final prepareOutgoing = await _sendRequest(
          'textDocument/prepareCallHierarchy',
          <String, Object?>{'textDocument': textDocIdent, 'position': position},
        );
        final outgoingItems = _parseCallHierarchyItems(prepareOutgoing);
        if (outgoingItems.isEmpty) {
          return const <Object?>[];
        }
        return _sendRequest('callHierarchy/outgoingCalls', <String, Object?>{
          'item': outgoingItems.first,
        });
      default:
        throw UnsupportedError('未知 LSP 操作：$operation。');
    }
  }

  Future<List<AiLspDiagnostic>> waitForDiagnostics(
    String filePath, {
    required Duration timeout,
  }) async {
    final uri = Uri.file(filePath).toString();
    if (_diagnosticsByUri.containsKey(uri)) {
      return diagnosticsForFile(filePath);
    }
    final existingWaitGroup = _pendingDiagnostics[uri];
    if (existingWaitGroup == null &&
        _pendingDiagnostics.length >= _maxOpenDocuments) {
      return diagnosticsForFile(filePath);
    }
    final waitGroup = existingWaitGroup ?? _AiLspDiagnosticsWaitGroup();
    _pendingDiagnostics[uri] = waitGroup;
    waitGroup.waiterCount += 1;
    try {
      return await waitGroup.completer.future.timeout(
        timeout,
        onTimeout: () => diagnosticsForFile(filePath),
      );
    } finally {
      waitGroup.waiterCount -= 1;
      if (waitGroup.waiterCount == 0 &&
          identical(_pendingDiagnostics[uri], waitGroup)) {
        _pendingDiagnostics.remove(uri);
      }
    }
  }

  List<AiLspDiagnostic> diagnosticsForFile(String filePath) {
    final uri = Uri.file(filePath).toString();
    return List<AiLspDiagnostic>.unmodifiable(
      _diagnosticsByUri[uri] ?? const <AiLspDiagnostic>[],
    );
  }

  Future<Object?> _sendRequest(
    String method,
    Map<String, Object?> params,
  ) async {
    _ensureActive();
    if (_pendingRequests.length >= _maxPendingRequests) {
      throw StateError(
        'LSP“${backend.language}”待处理请求过多'
        '（${_pendingRequests.length} 个），服务端可能无响应。',
      );
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pendingRequests[id] = completer;
    try {
      _writeMessage(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      });
    } catch (_) {
      _pendingRequests.remove(id);
      rethrow;
    }
    return completer.future.timeout(
      _requestTimeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException(
          'LSP 请求“$method”在 ${_requestTimeout.inMilliseconds} 毫秒后超时。',
        );
      },
    );
  }

  void _sendNotification(String method, Map<String, Object?> params) {
    _ensureActive();
    _writeMessage(<String, Object?>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  void _writeMessage(Map<String, Object?> message) {
    final process = _process;
    if (process == null) {
      throw StateError('LSP 会话没有正在运行的进程。');
    }
    final body = utf8.encode(jsonEncode(message));
    process.stdin.add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
    process.stdin.add(body);
  }

  void _onData(List<int> chunk) {
    if (_shutdownRequested || chunk.isEmpty) return;
    _responseBuffer.addAll(chunk);
    if (_bufferDrainScheduled) return;
    _processBuffer();
  }

  void _processBuffer() {
    var processedMessages = 0;
    while (!_shutdownRequested && _responseBuffer.isNotEmpty) {
      final frame = findMessageFrameHeaderEnd(
        _responseBuffer,
        acceptBareLf: false,
      );
      if (frame == null) {
        if (_responseBuffer.length > _maxLspHeaderBytes) {
          _failProtocol(
            const FormatException('LSP 消息头超过 $_maxLspHeaderBytes 字节。'),
          );
        }
        return;
      }
      final headerEnd = frame.headerEnd;
      if (headerEnd > _maxLspHeaderBytes) {
        _failProtocol(
          const FormatException('LSP 消息头超过 $_maxLspHeaderBytes 字节。'),
        );
        return;
      }

      final header = latin1.decode(_responseBuffer.sublist(0, headerEnd));
      final parsedContentLength = parseHttpContentLengthHeader(
        header,
        maxDigits: _maxContentLengthDigits,
      );
      final contentLength = parsedContentLength.value;
      if (!parsedContentLength.found ||
          contentLength == null ||
          contentLength <= 0 ||
          contentLength > _maxLspFrameBytes) {
        _failProtocol(const FormatException('Content-Length 消息头无效。'));
        return;
      }
      final bodyStart = frame.bodyStart;
      final bodyEnd = bodyStart + contentLength;
      if (bodyEnd > _responseBuffer.length) return;
      final body = _responseBuffer.sublist(bodyStart, bodyEnd);
      _responseBuffer.removeRange(0, bodyEnd);

      try {
        final decoded = decodeJsonTextUsingConfig(
          utf8.decode(body),
          maxTextCodeUnits: _maxLspFrameBytes,
          config: _lspJsonConversionConfig,
        );
        if (decoded is! Map) {
          _failProtocol(const FormatException('LSP JSON-RPC 载荷必须为对象。'));
          return;
        }
        final message = stringKeyedMapFromValue(decoded);
        if (message.containsKey('id') && message.containsKey('method')) {
          _enqueueServerRequest(message);
        } else if (message.containsKey('id')) {
          _handleResponse(message);
        } else {
          _handleNotification(message);
        }
      } catch (error, stack) {
        _failProtocol(error, stack: stack);
        return;
      }

      processedMessages += 1;
      if (processedMessages >= _maxMessagesPerDrain) {
        _bufferDrainScheduled = true;
        startSafeTimer(Duration.zero, () {
          _bufferDrainScheduled = false;
          if (!_shutdownRequested) _processBuffer();
        }, onError: (error, stack) => _failProtocol(error, stack: stack));
        return;
      }
    }
  }

  void _failProtocol(Object error, {StackTrace? stack}) {
    final process = _process;
    if (process == null || _shutdownRequested) return;
    final effectiveStack = stack ?? StackTrace.current;
    silentLog(
      'lsp_client_service',
      '处理 LSP 协议（${backend.language}）',
      error,
      effectiveStack,
    );
    _handleTransportFailure(process, error, effectiveStack);
  }

  void _handleResponse(Map<String, Object?> message) {
    if (_shutdownRequested) {
      return;
    }
    final id = message['id'];
    if (id is! int || !_pendingRequests.containsKey(id)) {
      return;
    }
    final completer = _pendingRequests.remove(id)!;
    if (message.containsKey('error')) {
      final error = message['error'];
      completer.completeError(
        Exception('LSP 错误：${error is Map ? error['message'] : error}'),
      );
      return;
    }
    completer.complete(message['result']);
  }

  void _enqueueServerRequest(Map<String, Object?> message) {
    if (_shutdownRequested) return;
    final outstanding =
        _serverRequestQueue.length + (_serverRequestActive ? 1 : 0);
    if (outstanding >= _maxQueuedServerRequests) {
      _sendServerRequestError(
        message['id'],
        code: -32000,
        message: 'LSP 客户端请求队列已满。',
      );
      return;
    }
    _serverRequestQueue.addLast(message);
    _drainServerRequestQueue();
  }

  void _drainServerRequestQueue() {
    if (_shutdownRequested ||
        _serverRequestActive ||
        _serverRequestQueue.isEmpty) {
      return;
    }
    final message = _serverRequestQueue.removeFirst();
    _serverRequestActive = true;
    unawaited(
      _handleServerRequestSafely(message).whenComplete(() {
        _serverRequestActive = false;
        _drainServerRequestQueue();
      }),
    );
  }

  Future<void> _handleServerRequestSafely(Map<String, Object?> message) async {
    if (_shutdownRequested) return;
    try {
      await _handleServerRequest(message);
    } catch (error, stack) {
      silentLog(
        'lsp_client_service',
        '处理 LSP 服务端请求（${backend.language}）',
        error,
        stack,
      );
      if (!_shutdownRequested) {
        _sendServerRequestError(
          message['id'],
          code: -32603,
          message: 'LSP 客户端请求失败。',
        );
      }
    }
  }

  void _sendServerRequestError(
    Object? id, {
    required int code,
    required String message,
  }) {
    final process = _process;
    if (_shutdownRequested || id == null || process == null) return;
    try {
      _writeMessage(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': code, 'message': message},
      });
    } catch (error, stack) {
      _handleTransportFailure(process, error, stack);
    }
  }

  Future<void> _handleServerRequest(Map<String, Object?> message) async {
    if (_shutdownRequested) {
      return;
    }
    touch();
    final method = '${message['method'] ?? ''}'.trim();
    final id = message['id'];
    if (id == null) {
      return;
    }
    switch (method) {
      case 'workspace/applyEdit':
        final params = message['params'] as Map<String, Object?>?;
        final edit = AiLspClientService.parseWorkspaceEdit(params?['edit']);
        var applied = false;
        final handler = _workspaceEditHandlerProvider();
        if (!edit.isEmpty && handler != null) {
          final outcomeCompleter = Completer<Object?>();
          unawaited(
            handler(edit).then<void>(
              (result) {
                if (!outcomeCompleter.isCompleted) {
                  outcomeCompleter.complete(result);
                }
              },
              onError: (Object _, StackTrace _) {
                if (!outcomeCompleter.isCompleted) {
                  outcomeCompleter.complete(false);
                }
              },
            ),
          );
          final timeoutTimer = startSafeTimer(
            _serverRequestResponseTimeout,
            () {
              if (!outcomeCompleter.isCompleted) {
                outcomeCompleter.complete(const _ServerRequestTimeoutToken());
              }
            },
          );
          final outcome = await outcomeCompleter.future;
          timeoutTimer.cancel();
          if (outcome is _ServerRequestTimeoutToken) {
            if (!_shutdownRequested && _process != null) {
              _writeMessage(<String, Object?>{
                'jsonrpc': '2.0',
                'id': id,
                'result': <String, Object?>{
                  'applied': false,
                  'failureReason': '工作区编辑处理超时。',
                },
              });
            }
            _serverRequestQueue.clear();
            unawaited(shutdown());
            return;
          }
          applied = outcome == true;
        }
        if (_shutdownRequested || _process == null) {
          return;
        }
        _writeMessage(<String, Object?>{
          'jsonrpc': '2.0',
          'id': id,
          'result': <String, Object?>{'applied': applied},
        });
        return;
      default:
        _sendServerRequestError(
          id,
          code: -32601,
          message: '不支持的客户端请求：$method。',
        );
        return;
    }
  }

  void _handleNotification(Map<String, Object?> message) {
    if (_shutdownRequested) {
      return;
    }
    final method = '${message['method'] ?? ''}'.trim();
    if (method != 'textDocument/publishDiagnostics') {
      return;
    }
    final params = message['params'] as Map<String, Object?>?;
    final uri = params?['uri'] as String?;
    if (uri == null || !_openDocuments.containsKey(uri)) return;
    final diagnostics =
        (params?['diagnostics'] as List?)
            ?.whereType<Map<String, Object?>>()
            .map(AiLspClientService._parseDiagnostic)
            .toList(growable: false) ??
        const <AiLspDiagnostic>[];
    _diagnosticsByUri[uri] = diagnostics;
    final completer = _pendingDiagnostics.remove(uri)?.completer;
    if (completer != null && !completer.isCompleted) {
      completer.complete(List<AiLspDiagnostic>.unmodifiable(diagnostics));
    }

    // 已注册监听器时向编辑器推送实时诊断。
    final pushCb = _diagnosticsPushCallbackProvider();
    if (pushCb != null) {
      // 转回编辑器使用的文件路径。
      final parsed = Uri.tryParse(uri);
      if (parsed != null && parsed.scheme == 'file') {
        pushCb(parsed.toFilePath(), diagnostics);
      }
    }
  }

  void _handleTransportFailure(
    Process process,
    Object error,
    StackTrace stack,
  ) {
    if (_shutdownRequested || !identical(_process, process)) return;
    _failPendingRequests(error, stack);
    unawaited(shutdown());
  }

  Future<void> _watchProcessExit(Process process) async {
    late final int exitCode;
    try {
      exitCode = await process.exitCode;
    } catch (error, stack) {
      if (identical(_process, process)) {
        _handleTransportFailure(process, error, stack);
      }
      return;
    }
    if (!identical(_process, process)) return;

    final wasUnexpected = !_shutdownRequested;
    _shutdownRequested = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    _process = null;
    if (wasUnexpected) {
      _failPendingRequests(
        StateError('LSP 进程意外退出，退出码：$exitCode。'),
        StackTrace.current,
      );
      await runAsyncCleanupBounded(
        () => terminateTrackedProcessTree(
          process,
          gracefulTimeout: Duration.zero,
        ),
        timeout: _processCleanupTimeout,
        onError: (error, stack) =>
            silentLog('lsp_client_service', '清理意外退出的 LSP 进程', error, stack),
      );
    }
    await _cancelTransportSubscriptions('进程退出');
    _clearSessionState();
    _notifyTerminated();
  }

  Future<void> shutdown() {
    _shutdownRequested = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    final activeShutdown = _shutdownFuture;
    if (activeShutdown != null) {
      return activeShutdown;
    }
    final process = _process;
    if (process == null) {
      _clearSessionState();
      _notifyTerminated();
      return Future<void>.value();
    }

    late final Future<void> shutdownFuture;
    shutdownFuture = _performShutdown(process).whenComplete(() {
      if (identical(_shutdownFuture, shutdownFuture)) {
        _shutdownFuture = null;
      }
    });
    _shutdownFuture = shutdownFuture;
    return shutdownFuture;
  }

  Future<void> _performShutdown(Process process) async {
    try {
      _writeMessage(<String, Object?>{
        'jsonrpc': '2.0',
        'id': _nextId++,
        'method': 'shutdown',
        'params': null,
      });
      await Future<void>.delayed(_shutdownRequestDelay);
      _writeMessage(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'exit',
        'params': <String, Object?>{},
      });
      await Future<void>.delayed(_shutdownExitDelay);
    } catch (error, stack) {
      silentLog('lsp_client_service', '执行 LSP 优雅关闭握手', error, stack);
    }
    if (identical(_process, process)) {
      _process = null;
    }
    await runAsyncCleanupBounded(
      () => terminateTrackedProcessTree(process),
      timeout: _processCleanupTimeout,
      onError: (error, stack) =>
          silentLog('lsp_client_service', '终止 LSP 进程', error, stack),
    );
    await _cancelTransportSubscriptions('关闭');
    _clearSessionState();
    _notifyTerminated();
  }

  void _ensureActive() {
    if (_shutdownRequested || _process == null) {
      throw StateError('LSP 会话已关闭。');
    }
  }

  void _clearSessionState() {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('LSP 会话已关闭。'));
      }
    }
    for (final waitGroup in _pendingDiagnostics.values) {
      final completer = waitGroup.completer;
      if (!completer.isCompleted) {
        completer.complete(const <AiLspDiagnostic>[]);
      }
    }
    _pendingRequests.clear();
    _pendingDiagnostics.clear();
    _serverRequestQueue.clear();
    _openDocuments.clear();
    _openDocumentBytes = 0;
    _diagnosticsByUri.clear();
    _responseBuffer.clear();
    _bufferDrainScheduled = false;
  }

  void _failPendingRequests(Object error, StackTrace stack) {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    }
  }

  Future<void> _cancelTransportSubscriptions(String reason) async {
    final stdoutSubscription = _stdoutSubscription;
    final stderrSubscription = _stderrSubscription;
    _stdoutSubscription = null;
    _stderrSubscription = null;

    Future<void> cancel(
      StreamSubscription<dynamic>? subscription,
      String streamName,
    ) async {
      await cancelStreamSubscriptionBounded<dynamic>(
        subscription,
        timeout: _transportCancelTimeout,
        onError: (error, stack) => silentLog(
          'lsp_client_service',
          '取消 LSP $streamName 流订阅（$reason）',
          error,
          stack,
        ),
      );
    }

    await Future.wait<void>(<Future<void>>[
      cancel(stdoutSubscription, '标准输出'),
      cancel(stderrSubscription, '标准错误'),
    ]);
  }

  void _notifyTerminated() {
    if (_terminationNotified) return;
    _terminationNotified = true;
    _onTerminated();
  }

  static List<Map<String, Object?>> _parseCallHierarchyItems(Object? result) {
    if (result is! List) {
      return const <Map<String, Object?>>[];
    }
    return result.whereType<Map<String, Object?>>().toList(growable: false);
  }
}

class _AiLspOpenDocument {
  _AiLspOpenDocument({
    required this.uri,
    required this.language,
    required this.text,
    required this.byteLength,
    required this.version,
  });

  final String uri;
  final String language;
  String text;
  int byteLength;
  int version;
}

class _AiLspDiagnosticsWaitGroup {
  final Completer<List<AiLspDiagnostic>> completer =
      Completer<List<AiLspDiagnostic>>();
  int waiterCount = 0;
}

class _ServerRequestTimeoutToken {
  const _ServerRequestTimeoutToken();
}
