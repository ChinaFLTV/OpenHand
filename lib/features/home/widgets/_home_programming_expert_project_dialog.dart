part of '../openhand_home_page.dart';

/// 编程专家配置结果。
class _ProgrammingExpertConfig {
  const _ProgrammingExpertConfig({
    required this.projectRoot,
    required this.language,
    required this.sdkPath,
    required this.lspPath,
  });

  final String projectRoot;

  /// 项目语言标识，如 dart、python、mixed。
  final String language;
  final String sdkPath;
  final String lspPath;
}

class _ProgrammingExpertRecentPathCache {
  const _ProgrammingExpertRecentPathCache({
    required this.projectRoots,
    required this.configsByProjectRoot,
    required this.sdkPathsByLanguage,
    required this.lspPathsByLanguage,
  });

  final List<String> projectRoots;
  final Map<String, _ProgrammingExpertConfig> configsByProjectRoot;
  final Map<String, List<String>> sdkPathsByLanguage;
  final Map<String, List<String>> lspPathsByLanguage;
}

/// 支持的项目语言。
const List<({String id, String labelZh, String labelEn})>
_programmingLanguageOptions = [
  (id: 'dart', labelZh: 'Dart / Flutter', labelEn: 'Dart / Flutter'),
  (id: 'python', labelZh: 'Python', labelEn: 'Python'),
  (id: 'go', labelZh: 'Go', labelEn: 'Go'),
  (id: 'java', labelZh: 'Java', labelEn: 'Java'),
  (id: 'kotlin', labelZh: 'Kotlin', labelEn: 'Kotlin'),
  (id: 'javascript', labelZh: 'JavaScript', labelEn: 'JavaScript'),
  (id: 'typescript', labelZh: 'TypeScript', labelEn: 'TypeScript'),
  (id: 'rust', labelZh: 'Rust', labelEn: 'Rust'),
  (id: 'cpp', labelZh: 'C / C++', labelEn: 'C / C++'),
  (id: 'swift', labelZh: 'Swift', labelEn: 'Swift'),
  (id: 'csharp', labelZh: 'C#', labelEn: 'C#'),
  (id: 'fsharp', labelZh: 'F#', labelEn: 'F#'),
  (id: 'ruby', labelZh: 'Ruby', labelEn: 'Ruby'),
  (id: 'php', labelZh: 'PHP', labelEn: 'PHP'),
  (id: 'lua', labelZh: 'Lua', labelEn: 'Lua'),
  (id: 'elixir', labelZh: 'Elixir', labelEn: 'Elixir'),
  (id: 'scala', labelZh: 'Scala', labelEn: 'Scala'),
  (id: 'haskell', labelZh: 'Haskell', labelEn: 'Haskell'),
  (id: 'clojure', labelZh: 'Clojure', labelEn: 'Clojure'),
  (id: 'ocaml', labelZh: 'OCaml', labelEn: 'OCaml'),
  (id: 'zig', labelZh: 'Zig', labelEn: 'Zig'),
  (id: 'gleam', labelZh: 'Gleam', labelEn: 'Gleam'),
  (id: 'shell', labelZh: 'Shell / Bash', labelEn: 'Shell / Bash'),
  (id: 'vue', labelZh: 'Vue', labelEn: 'Vue'),
  (id: 'svelte', labelZh: 'Svelte', labelEn: 'Svelte'),
  (id: 'mixed', labelZh: '混合 (Monorepo)', labelEn: 'Mixed (Monorepo)'),
];

({String id, String labelZh, String labelEn})? _programmingLanguageOptionById(
  String languageId,
) {
  for (final option in _programmingLanguageOptions) {
    if (option.id == languageId) {
      return option;
    }
  }
  return null;
}

String _programmingLanguageLabel(BuildContext context, String languageId) {
  final option = _programmingLanguageOptionById(languageId);
  if (option != null) {
    return _programmingLanguageOptionLabel(context, option);
  }
  if (languageId.isEmpty) {
    return 'Plain Text';
  }
  return languageId[0].toUpperCase() + languageId.substring(1);
}

String _programmingLanguageOptionLabel(
  BuildContext context,
  ({String id, String labelZh, String labelEn}) option,
) {
  if (option.id != 'mixed') {
    return option.labelEn;
  }
  return openHandLocalizedText(
    context,
    zh: option.labelZh,
    zhHant: '混合 (Monorepo)',
    en: option.labelEn,
    fr: 'Mixte (Monorepo)',
    de: 'Gemischt (Monorepo)',
    ja: '混在 (Monorepo)',
  );
}

/// 编程专家项目配置弹窗。
class _ProgrammingExpertProjectDialog extends StatefulWidget {
  const _ProgrammingExpertProjectDialog({
    required this.settingsController,
    required this.recentPathCache,
    this.currentWorkspacePath = '',
  });

  final SettingsController settingsController;
  final _ProgrammingExpertRecentPathCache recentPathCache;
  final String currentWorkspacePath;

  @override
  State<_ProgrammingExpertProjectDialog> createState() =>
      _ProgrammingExpertProjectDialogState();
}

class _ProgrammingExpertProjectDialogState
    extends State<_ProgrammingExpertProjectDialog> {
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _sdkController = TextEditingController();
  final TextEditingController _lspController = TextEditingController();
  final Map<String, String> _sdkDraftByLanguage = <String, String>{};
  final Map<String, String> _lspDraftByLanguage = <String, String>{};
  late final OpenHandDebouncer _projectRootDraftDebouncer = OpenHandDebouncer(
    delay: _projectRootDraftDebounce,
  );
  static const Duration _projectRootDraftDebounce = Duration(milliseconds: 220);
  static const int _projectLanguageProbeMaxEntriesPerDirectory = 256;
  static const Duration _projectLanguageProbeTimeout = Duration(seconds: 3);
  static const Duration _projectLanguageProbeIdleTimeout = Duration(
    milliseconds: 500,
  );
  bool _suspendProjectRootDraftListener = false;
  bool _suspendToolchainDraftListener = false;
  int _projectLanguageProbeGeneration = 0;
  String _detectedProjectRoot = '';
  String _detectedProjectLanguage = 'mixed';
  String? _autoSelectedLanguage;
  String _autoSelectedSdkPath = '';
  String _autoSelectedLspPath = '';
  String _selectedLanguage = 'mixed';
  String _validatedProjectRoot = '';
  bool _projectRootExists = false;
  String _validatedCurrentWorkspacePath = '';
  bool _currentWorkspaceExists = false;

  @override
  void initState() {
    super.initState();
    _pathController.addListener(_handleProjectRootTextChanged);
    _sdkController.addListener(_handleToolchainDraftChanged);
    _lspController.addListener(_handleToolchainDraftChanged);
    unawaited(_refreshCurrentWorkspaceExists());
  }

  @override
  void didUpdateWidget(covariant _ProgrammingExpertProjectDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentWorkspacePath != widget.currentWorkspacePath) {
      unawaited(_refreshCurrentWorkspaceExists());
    }
  }

  @override
  void dispose() {
    _projectLanguageProbeGeneration += 1;
    _projectRootDraftDebouncer.dispose();
    _pathController.removeListener(_handleProjectRootTextChanged);
    _sdkController.removeListener(_handleToolchainDraftChanged);
    _lspController.removeListener(_handleToolchainDraftChanged);
    _pathController.dispose();
    _sdkController.dispose();
    _lspController.dispose();
    super.dispose();
  }

  void _handleProjectRootTextChanged() {
    if (_suspendProjectRootDraftListener) {
      return;
    }
    _projectRootDraftDebouncer.schedule(() {
      unawaited(_syncProjectRootDraftState());
    });
  }

  void _handleToolchainDraftChanged() {
    if (_suspendToolchainDraftListener) {
      return;
    }
    _projectLanguageProbeGeneration += 1;
    if (_autoSelectedLanguage != null && !_isFollowingAutomaticSelection) {
      setState(_clearAutomaticSelectionState);
      return;
    }
    setState(() {});
  }

  void _setProjectRootText(String value) {
    _suspendProjectRootDraftListener = true;
    try {
      _pathController.text = value;
    } finally {
      _suspendProjectRootDraftListener = false;
    }
  }

  bool get _isFollowingAutomaticSelection {
    final autoLanguage = _autoSelectedLanguage;
    if (autoLanguage == null) {
      return false;
    }
    return _selectedLanguage == autoLanguage &&
        _sdkController.text.trim() == _autoSelectedSdkPath &&
        _lspController.text.trim() == _autoSelectedLspPath;
  }

  void _clearAutomaticSelectionState() {
    _autoSelectedLanguage = null;
    _autoSelectedSdkPath = '';
    _autoSelectedLspPath = '';
  }

  void _rememberAutomaticSelection({
    required String language,
    required String sdkPath,
    required String lspPath,
  }) {
    _autoSelectedLanguage = normalizeAiLspLanguage(language);
    _autoSelectedSdkPath = sdkPath.trim();
    _autoSelectedLspPath = lspPath.trim();
  }

  Future<void> _syncProjectRootDraftState() async {
    if (!mounted || _suspendProjectRootDraftListener) {
      return;
    }
    final normalized = OpenHandPaths.normalizeOptionalPath(
      _pathController.text,
    );
    if (normalized.isEmpty) {
      _invalidateProjectLanguageProbe();
      _validatedProjectRoot = '';
      _projectRootExists = false;
      setState(() {});
      return;
    }
    final detectedLanguage = await _probeCurrentProjectLanguage(normalized);
    if (detectedLanguage == null) return;
    if (!_projectRootExists) {
      setState(() {});
      return;
    }
    final recentConfig = _recentConfigForProjectRoot(normalized);
    if (_canAutoBackfillProjectDefaults && recentConfig != null) {
      _invalidateProjectLanguageProbe();
      _applyProjectConfig(recentConfig, syncProjectRoot: false);
      return;
    }
    if (_canAutoBackfillProjectDefaults && detectedLanguage != 'mixed') {
      _applyAutomaticLanguageSelection(language: detectedLanguage);
      return;
    }
    if (_canAutoBackfillProjectDefaults && _autoSelectedLanguage != null) {
      _applyAutomaticLanguageSelection(language: 'mixed');
      return;
    }
    setState(() {});
  }

  Future<void> _refreshCurrentWorkspaceExists() async {
    final normalized = OpenHandPaths.normalizeOptionalPath(
      widget.currentWorkspacePath,
    );
    if (normalized.isEmpty) {
      _validatedCurrentWorkspacePath = '';
      _currentWorkspaceExists = false;
      return;
    }
    final exists = await isDirectoryPath(normalized);
    if (!mounted ||
        OpenHandPaths.normalizeOptionalPath(widget.currentWorkspacePath) !=
            normalized) {
      return;
    }
    setState(() {
      _validatedCurrentWorkspacePath = normalized;
      _currentWorkspaceExists = exists;
    });
  }

  Future<void> _pickProjectDirectory() async {
    final current = _pathController.text.trim();
    final result = await getDirectoryPath(
      initialDirectory: current.isNotEmpty ? current : null,
    );
    if (result != null && mounted) {
      await _applyProjectRootSelection(result);
    }
  }

  Future<void> _pickSdkDirectory() async {
    final current = _sdkController.text.trim();
    final result = await getDirectoryPath(
      initialDirectory: current.isNotEmpty ? current : null,
    );
    if (result != null && mounted) {
      _sdkController.text = result;
    }
  }

  Future<void> _pickLspDirectory() async {
    final current = _lspController.text.trim();
    final result = await getDirectoryPath(
      initialDirectory: current.isNotEmpty ? current : null,
    );
    if (result != null && mounted) {
      _lspController.text = result;
    }
  }

  String _defaultSdkPathForLanguage(String language) {
    if (language == 'mixed') {
      return '';
    }
    final globalValue = widget.settingsController
        .editorLspSettingsForLanguage(language)
        .sdkPath
        .trim();
    if (globalValue.isNotEmpty) {
      return globalValue;
    }
    return widget.recentPathCache.sdkPathsByLanguage[language]?.firstOrNull ??
        '';
  }

  String _defaultLspPathForLanguage(String language) {
    if (language == 'mixed') {
      return '';
    }
    final globalValue = widget.settingsController
        .editorLspSettingsForLanguage(language)
        .rootPath
        .trim();
    if (globalValue.isNotEmpty) {
      return globalValue;
    }
    return widget.recentPathCache.lspPathsByLanguage[language]?.firstOrNull ??
        '';
  }

  _ProgrammingExpertConfig? _recentConfigForProjectRoot(String projectRoot) {
    final normalized = OpenHandPaths.normalizeOptionalPath(projectRoot);
    if (normalized.isEmpty) {
      return null;
    }
    return widget.recentPathCache.configsByProjectRoot[normalized];
  }

  bool get _canAutoBackfillProjectDefaults {
    final autoLanguage = _autoSelectedLanguage;
    if (autoLanguage != null) {
      return _selectedLanguage == autoLanguage &&
          _sdkController.text.trim() == _autoSelectedSdkPath &&
          _lspController.text.trim() == _autoSelectedLspPath;
    }
    return _selectedLanguage == 'mixed' &&
        _sdkController.text.trim().isEmpty &&
        _lspController.text.trim().isEmpty;
  }

  void _invalidateProjectLanguageProbe() {
    _projectLanguageProbeGeneration += 1;
    _detectedProjectRoot = '';
    _detectedProjectLanguage = 'mixed';
  }

  Future<String?> _probeCurrentProjectLanguage(String projectRoot) async {
    final normalized = OpenHandPaths.normalizeOptionalPath(projectRoot);
    final generation = ++_projectLanguageProbeGeneration;
    final exists = await isDirectoryPath(normalized);
    if (!mounted ||
        generation != _projectLanguageProbeGeneration ||
        OpenHandPaths.normalizeOptionalPath(_pathController.text) !=
            normalized) {
      return null;
    }
    _validatedProjectRoot = normalized;
    _projectRootExists = exists;
    if (!exists) {
      _detectedProjectRoot = normalized;
      _detectedProjectLanguage = 'mixed';
      return 'mixed';
    }
    final detected = await _detectProjectLanguage(normalized);
    if (!mounted ||
        generation != _projectLanguageProbeGeneration ||
        OpenHandPaths.normalizeOptionalPath(_pathController.text) !=
            normalized) {
      return null;
    }
    _detectedProjectRoot = normalized;
    _detectedProjectLanguage = detected;
    return detected;
  }

  Future<String> _detectProjectLanguage(String projectRoot) async {
    final normalized = OpenHandPaths.normalizeOptionalPath(projectRoot);
    if (normalized.isEmpty) {
      return 'mixed';
    }
    final stopwatch = Stopwatch()..start();

    Duration remainingProbeTime() =>
        _projectLanguageProbeTimeout - stopwatch.elapsed;

    Future<FileSystemEntityType> entryType(String relativePath) async {
      final remaining = remainingProbeTime();
      if (remaining <= Duration.zero) {
        return FileSystemEntityType.notFound;
      }
      final operationTimeout = remaining < _projectLanguageProbeIdleTimeout
          ? remaining
          : _projectLanguageProbeIdleTimeout;
      try {
        return await FileSystemEntity.type(
          relativePath.isEmpty ? normalized : p.join(normalized, relativePath),
          followLinks: false,
        ).timeout(operationTimeout);
      } on TimeoutException {
        return FileSystemEntityType.notFound;
      } on FileSystemException {
        return FileSystemEntityType.notFound;
      }
    }

    Future<bool> hasEntry(String relativePath) async =>
        await entryType(relativePath) != FileSystemEntityType.notFound;

    Set<String>? extensionCache;
    Future<Set<String>> projectExtensions() async {
      final cached = extensionCache;
      if (cached != null) {
        return cached;
      }
      final extensions = <String>{};
      const candidateDirs = <String>['', 'lib', 'src', 'app', 'bin', 'test'];
      for (final relativeDir in candidateDirs) {
        final remaining = remainingProbeTime();
        if (remaining <= Duration.zero) {
          break;
        }
        final directoryPath = relativeDir.isEmpty
            ? normalized
            : p.join(normalized, relativeDir);
        if (await entryType(relativeDir) != FileSystemEntityType.directory) {
          continue;
        }
        try {
          final listingBudget = remainingProbeTime();
          if (listingBudget <= Duration.zero) {
            break;
          }
          final idleTimeout = listingBudget < _projectLanguageProbeIdleTimeout
              ? listingBudget
              : _projectLanguageProbeIdleTimeout;
          final listing = await listDirectoryBounded(
            Directory(directoryPath),
            maxEntries: _projectLanguageProbeMaxEntriesPerDirectory,
            idleTimeout: idleTimeout,
            totalTimeout: listingBudget,
          );
          for (final entry in listing.entries.whereType<File>()) {
            extensions.add(p.extension(entry.path).toLowerCase());
          }
        } on FileSystemException catch (error, stack) {
          silentLog('project_dialog', '遍历目录探测语言', error, stack);
        }
      }
      extensionCache = extensions;
      return extensions;
    }

    bool containsAny(Set<String> extensions, Set<String> candidates) =>
        extensions.any(candidates.contains);

    if (await entryType('') != FileSystemEntityType.directory) {
      return 'mixed';
    }
    if (await hasEntry('pubspec.yaml')) {
      return 'dart';
    }
    if (await hasEntry('go.mod')) {
      return 'go';
    }
    if (await hasEntry('Cargo.toml')) {
      return 'rust';
    }
    if (await hasEntry('Package.swift')) {
      return 'swift';
    }
    if (await hasEntry('composer.json')) {
      return 'php';
    }
    if (await hasEntry('Gemfile')) {
      return 'ruby';
    }
    if (await hasEntry('tsconfig.json')) {
      return 'typescript';
    }
    if (await hasEntry('package.json')) {
      final extensions = await projectExtensions();
      return containsAny(extensions, const <String>{'.ts', '.tsx'})
          ? 'typescript'
          : 'javascript';
    }
    if (await hasEntry('pom.xml') ||
        await hasEntry('build.gradle') ||
        await hasEntry('build.gradle.kts') ||
        await hasEntry('settings.gradle') ||
        await hasEntry('settings.gradle.kts')) {
      if (await hasEntry('src/main/kotlin') ||
          await hasEntry('app/src/main/kotlin')) {
        return 'kotlin';
      }
      return 'java';
    }
    final extensions = await projectExtensions();
    if (containsAny(extensions, const <String>{'.csproj', '.sln', '.cs'})) {
      return 'csharp';
    }
    if (containsAny(extensions, const <String>{'.kt', '.kts'})) {
      return 'kotlin';
    }
    if (extensions.contains('.dart')) {
      return 'dart';
    }
    if (extensions.contains('.py')) {
      return 'python';
    }
    if (extensions.contains('.java')) {
      return 'java';
    }
    if (extensions.contains('.go')) {
      return 'go';
    }
    if (extensions.contains('.rs')) {
      return 'rust';
    }
    if (containsAny(extensions, const <String>{
      '.cpp',
      '.cc',
      '.cxx',
      '.hpp',
      '.h',
    })) {
      return 'cpp';
    }
    if (containsAny(extensions, const <String>{'.js', '.jsx'})) {
      return 'javascript';
    }
    if (containsAny(extensions, const <String>{'.sh', '.bash', '.zsh'})) {
      return 'shell';
    }
    return 'mixed';
  }

  String _sdkDefaultSourceLabel(BuildContext context, String language) {
    final globalValue = widget.settingsController
        .editorLspSettingsForLanguage(language)
        .sdkPath
        .trim();
    if (globalValue.isNotEmpty) {
      return _homeProgramminGlobalSettingsLabel(context);
    }
    if ((widget.recentPathCache.sdkPathsByLanguage[language] ??
            const <String>[])
        .isNotEmpty) {
      return _homeProgramminRecentHistoryLabel(context);
    }
    return openHandLocalizedText(
      context,
      zh: '系统默认',
      zhHant: '系統預設',
      en: 'system default',
      fr: 'valeur système par défaut',
      de: 'Systemstandard',
      ja: 'システム既定値',
    );
  }

  String _lspDefaultSourceLabel(BuildContext context, String language) {
    final globalValue = widget.settingsController
        .editorLspSettingsForLanguage(language)
        .rootPath
        .trim();
    if (globalValue.isNotEmpty) {
      return _homeProgramminGlobalSettingsLabel(context);
    }
    if ((widget.recentPathCache.lspPathsByLanguage[language] ??
            const <String>[])
        .isNotEmpty) {
      return _homeProgramminRecentHistoryLabel(context);
    }
    return openHandLocalizedText(
      context,
      zh: 'PATH / 自动探测',
      zhHant: 'PATH / 自動偵測',
      en: 'PATH / auto-detect',
      fr: 'PATH / détection automatique',
      de: 'PATH / automatische Erkennung',
      ja: 'PATH / 自動検出',
    );
  }

  void _applyLanguageSelection({
    required String language,
    String? sdkDraft,
    String? lspDraft,
  }) {
    final normalizedLanguage = normalizeAiLspLanguage(language);
    if (_selectedLanguage != 'mixed') {
      _sdkDraftByLanguage[_selectedLanguage] = _sdkController.text.trim();
      _lspDraftByLanguage[_selectedLanguage] = _lspController.text.trim();
    }

    final nextSdk = normalizedLanguage == 'mixed'
        ? ''
        : (sdkDraft ?? _defaultSdkPathForLanguage(normalizedLanguage));
    final nextLsp = normalizedLanguage == 'mixed'
        ? ''
        : (lspDraft ?? _defaultLspPathForLanguage(normalizedLanguage));

    if (normalizedLanguage != 'mixed') {
      _sdkDraftByLanguage[normalizedLanguage] = nextSdk;
      _lspDraftByLanguage[normalizedLanguage] = nextLsp;
    }

    setState(() {
      _selectedLanguage = normalizedLanguage;
      _suspendToolchainDraftListener = true;
      try {
        _sdkController.text = nextSdk;
        _lspController.text = nextLsp;
      } finally {
        _suspendToolchainDraftListener = false;
      }
    });
  }

  void _applyAutomaticLanguageSelection({
    required String language,
    String? sdkDraft,
    String? lspDraft,
  }) {
    final normalizedLanguage = normalizeAiLspLanguage(language);
    final nextSdk = normalizedLanguage == 'mixed'
        ? ''
        : (sdkDraft ?? _defaultSdkPathForLanguage(normalizedLanguage));
    final nextLsp = normalizedLanguage == 'mixed'
        ? ''
        : (lspDraft ?? _defaultLspPathForLanguage(normalizedLanguage));
    _rememberAutomaticSelection(
      language: normalizedLanguage,
      sdkPath: nextSdk,
      lspPath: nextLsp,
    );
    _applyLanguageSelection(
      language: normalizedLanguage,
      sdkDraft: nextSdk,
      lspDraft: nextLsp,
    );
  }

  void _applyProjectConfig(
    _ProgrammingExpertConfig config, {
    bool syncProjectRoot = true,
  }) {
    if (syncProjectRoot) {
      _setProjectRootText(config.projectRoot);
    }
    _applyAutomaticLanguageSelection(
      language: config.language,
      sdkDraft: config.sdkPath,
      lspDraft: config.lspPath,
    );
  }

  void _restoreRecommendedDefaultsForSelectedLanguage() {
    if (_selectedLanguage == 'mixed') {
      return;
    }
    _clearAutomaticSelectionState();
    _applyLanguageSelection(
      language: _selectedLanguage,
      sdkDraft: _defaultSdkPathForLanguage(_selectedLanguage),
      lspDraft: _defaultLspPathForLanguage(_selectedLanguage),
    );
  }

  void _clearProjectOverridesForSelectedLanguage() {
    if (_selectedLanguage == 'mixed') {
      return;
    }
    _clearAutomaticSelectionState();
    _applyLanguageSelection(
      language: _selectedLanguage,
      sdkDraft: '',
      lspDraft: '',
    );
  }

  Future<void> _applyDetectedLanguageForProjectRoot(String projectRoot) async {
    final detectedLanguage = await _probeCurrentProjectLanguage(projectRoot);
    if (detectedLanguage == null) {
      return;
    }
    if (detectedLanguage == 'mixed') {
      setState(() {});
      return;
    }
    _applyAutomaticLanguageSelection(language: detectedLanguage);
  }

  Future<void> _applyProjectRootSelection(String projectRoot) async {
    final normalized = OpenHandPaths.normalizeOptionalPath(projectRoot);
    if (normalized.isEmpty) {
      return;
    }
    _setProjectRootText(normalized);
    final detectedLanguage = await _probeCurrentProjectLanguage(normalized);
    if (detectedLanguage == null || !_projectRootExists) {
      if (mounted) setState(() {});
      return;
    }
    final recentConfig = _recentConfigForProjectRoot(normalized);
    if (_canAutoBackfillProjectDefaults && recentConfig != null) {
      _invalidateProjectLanguageProbe();
      _applyProjectConfig(recentConfig);
      return;
    }
    if (_canAutoBackfillProjectDefaults && detectedLanguage != 'mixed') {
      _applyAutomaticLanguageSelection(language: detectedLanguage);
      return;
    }
    if (_canAutoBackfillProjectDefaults && _autoSelectedLanguage != null) {
      _applyAutomaticLanguageSelection(language: 'mixed');
      return;
    }
    setState(() {});
  }

  void _setSelectedLanguage(String language) {
    if (_selectedLanguage == language) {
      return;
    }
    _projectLanguageProbeGeneration += 1;
    _clearAutomaticSelectionState();
    _applyLanguageSelection(
      language: language,
      sdkDraft: _sdkDraftByLanguage[language],
      lspDraft: _lspDraftByLanguage[language],
    );
  }

  Future<void> _submit() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      return;
    }
    final normalizedProjectRoot = OpenHandPaths.normalizeOptionalPath(path);
    if (normalizedProjectRoot.isEmpty ||
        !await isDirectoryPath(normalizedProjectRoot)) {
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      _ProgrammingExpertConfig(
        projectRoot: normalizedProjectRoot,
        language: _selectedLanguage,
        sdkPath: _selectedLanguage == 'mixed'
            ? ''
            : OpenHandPaths.normalizeOptionalPath(_sdkController.text),
        lspPath: _selectedLanguage == 'mixed'
            ? ''
            : OpenHandPaths.normalizeOptionalPath(_lspController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final text = openHandTextResolver(context);

    final recentProjectRoots = widget.recentPathCache.projectRoots;
    final recentSdkPaths =
        widget.recentPathCache.sdkPathsByLanguage[_selectedLanguage] ??
        const <String>[];
    final recentLspPaths =
        widget.recentPathCache.lspPathsByLanguage[_selectedLanguage] ??
        const <String>[];
    final currentWorkspacePath = OpenHandPaths.normalizeOptionalPath(
      widget.currentWorkspacePath,
    );
    final normalizedProjectRoot = OpenHandPaths.normalizeOptionalPath(
      _pathController.text,
    );
    final projectRootExists =
        normalizedProjectRoot.isEmpty ||
        (_validatedProjectRoot == normalizedProjectRoot && _projectRootExists);
    final currentWorkspaceExists =
        currentWorkspacePath.isNotEmpty &&
        _validatedCurrentWorkspacePath == currentWorkspacePath &&
        _currentWorkspaceExists;
    final currentWorkspaceMatchesProjectRoot =
        currentWorkspacePath.isNotEmpty &&
        currentWorkspacePath == normalizedProjectRoot;
    final recentProjectConfig = _recentConfigForProjectRoot(
      normalizedProjectRoot,
    );
    final detectedProjectLanguage =
        recentProjectConfig?.language ??
        (_detectedProjectRoot == normalizedProjectRoot
            ? _detectedProjectLanguage
            : 'mixed');
    final isFollowingRecentProjectConfig =
        recentProjectConfig != null &&
        _selectedLanguage ==
            normalizeAiLspLanguage(recentProjectConfig.language) &&
        _sdkController.text.trim() == recentProjectConfig.sdkPath &&
        _lspController.text.trim() == recentProjectConfig.lspPath;
    final isFollowingDetectedRecommendation =
        recentProjectConfig == null &&
        detectedProjectLanguage != 'mixed' &&
        _isFollowingAutomaticSelection &&
        _selectedLanguage == normalizeAiLspLanguage(detectedProjectLanguage);
    final recommendedSdkPath = _selectedLanguage == 'mixed'
        ? ''
        : _defaultSdkPathForLanguage(_selectedLanguage);
    final recommendedLspPath = _selectedLanguage == 'mixed'
        ? ''
        : _defaultLspPathForLanguage(_selectedLanguage);
    final canRestoreRecommendedDefaults =
        _selectedLanguage != 'mixed' &&
        (_sdkController.text.trim() != recommendedSdkPath ||
            _lspController.text.trim() != recommendedLspPath);
    final canClearProjectOverrides =
        _selectedLanguage != 'mixed' &&
        (_sdkController.text.trim().isNotEmpty ||
            _lspController.text.trim().isNotEmpty);
    final recentProjectLanguageLabel = recentProjectConfig == null
        ? ''
        : _programmingLanguageLabel(context, recentProjectConfig.language);
    final detectedProjectLanguageLabel = detectedProjectLanguage == 'mixed'
        ? ''
        : _programmingLanguageLabel(context, detectedProjectLanguage);
    final projectLanguageHint = recentProjectConfig != null
        ? (isFollowingRecentProjectConfig
              ? text(
                  zh: '这个目录最近一次使用的是 $recentProjectLanguageLabel 配置，当前已经即时回填对应语言、SDK 路径和 LSP 路径。后续只要你还没有手动改动，这些默认值会继续跟随目录切换。',
                  zhHant:
                      '這個目錄最近一次使用的是 $recentProjectLanguageLabel 設定，目前已即時回填對應語言、SDK 路徑和 LSP 路徑。後續只要你尚未手動修改，這些預設值會繼續跟隨目錄切換。',
                  en: 'This directory was most recently opened as $recentProjectLanguageLabel, and that language, SDK path, and LSP path have already been refilled. As long as you do not manually override them, the defaults continue following the directory change.',
                  fr: 'Ce dossier a récemment été ouvert en $recentProjectLanguageLabel ; le langage, le SDK et le LSP ont déjà été renseignés. Sans modification manuelle, ces valeurs suivront les changements de dossier.',
                  de: 'Dieser Ordner wurde zuletzt als $recentProjectLanguageLabel geöffnet. Sprache, SDK- und LSP-Pfad wurden bereits gefüllt und folgen weiter dem Ordner, solange du sie nicht manuell änderst.',
                  ja: 'このディレクトリは最近 $recentProjectLanguageLabel として開かれており、言語、SDK パス、LSP パスを即時入力しました。手動変更しない限り、既定値はディレクトリ切り替えに追従します。',
                )
              : text(
                  zh: '这个目录最近一次使用的是 $recentProjectLanguageLabel 配置。可以一键回填当时的语言、SDK 路径和 LSP 路径。',
                  zhHant:
                      '這個目錄最近一次使用的是 $recentProjectLanguageLabel 設定。可以一鍵回填當時的語言、SDK 路徑和 LSP 路徑。',
                  en: 'This directory was recently opened as $recentProjectLanguageLabel. You can refill that language, SDK path, and LSP path in one step.',
                  fr: 'Ce dossier a récemment été ouvert en $recentProjectLanguageLabel. Vous pouvez rétablir le langage, le SDK et le LSP en une action.',
                  de: 'Dieser Ordner wurde kürzlich als $recentProjectLanguageLabel geöffnet. Du kannst Sprache, SDK- und LSP-Pfad mit einem Klick übernehmen.',
                  ja: 'このディレクトリは最近 $recentProjectLanguageLabel として開かれました。当時の言語、SDK パス、LSP パスを一括入力できます。',
                ))
        : (isFollowingDetectedRecommendation
              ? text(
                  zh: '从当前目录结构看，它更像是 $detectedProjectLanguageLabel 项目，当前已经即时预选该语言，并跟随该语言的默认 SDK / LSP。你仍然可以手动切换。',
                  zhHant:
                      '從目前目錄結構看，它更像是 $detectedProjectLanguageLabel 專案，目前已即時預選該語言，並跟隨該語言的預設 SDK / LSP。你仍可隨時手動切換。',
                  en: 'The current directory looks like a $detectedProjectLanguageLabel project, so that language has already been preselected together with its default SDK / LSP. You can still switch manually at any time.',
                  fr: 'Le dossier ressemble à un projet $detectedProjectLanguageLabel ; ce langage et ses valeurs SDK / LSP par défaut sont déjà sélectionnés. Vous pouvez encore changer manuellement.',
                  de: 'Der Ordner wirkt wie ein $detectedProjectLanguageLabel-Projekt. Sprache sowie Standard-SDK/LSP sind vorausgewählt, du kannst aber jederzeit manuell wechseln.',
                  ja: '現在のディレクトリは $detectedProjectLanguageLabel プロジェクトに見えるため、その言語と既定の SDK / LSP を事前選択しました。いつでも手動で切り替えられます。',
                )
              : (!_canAutoBackfillProjectDefaults
                    ? text(
                        zh: '从当前目录结构看，它更像是 $detectedProjectLanguageLabel 项目；但你已经手动调整过语言或工具链路径，所以本次不会自动覆盖。需要时可点下面的按钮恢复自动预选。',
                        zhHant:
                            '從目前目錄結構看，它更像是 $detectedProjectLanguageLabel 專案；但你已手動調整過語言或工具鏈路徑，因此本次不會自動覆寫。需要時可點下方按鈕恢復自動預選。',
                        en: 'The current directory looks like a $detectedProjectLanguageLabel project, but you have already adjusted the language or toolchain paths manually, so this dialog will not overwrite them automatically. Use the action below to resume auto-preselection if needed.',
                        fr: 'Le dossier ressemble à un projet $detectedProjectLanguageLabel, mais vous avez déjà modifié le langage ou les chemins d’outils. Rien ne sera écrasé automatiquement ; utilisez l’action ci-dessous pour reprendre la présélection.',
                        de: 'Der Ordner wirkt wie ein $detectedProjectLanguageLabel-Projekt, aber du hast Sprache oder Toolchain-Pfade bereits manuell geändert. Es wird nichts automatisch überschrieben; nutze unten die Aktion zum Fortsetzen.',
                        ja: '現在のディレクトリは $detectedProjectLanguageLabel プロジェクトに見えますが、言語またはツールチェーンパスが手動調整済みのため自動上書きしません。必要なら下の操作で自動事前選択を再開できます。',
                      )
                    : text(
                        zh: '从当前目录结构看，它更像是 $detectedProjectLanguageLabel 项目。会在你尚未手动接管时即时预选推荐语言，并回填该语言的默认 SDK / LSP。',
                        zhHant:
                            '從目前目錄結構看，它更像是 $detectedProjectLanguageLabel 專案。當你尚未手動接管時，會即時預選建議語言，並回填該語言的預設 SDK / LSP。',
                        en: 'The current directory looks like a $detectedProjectLanguageLabel project. While you have not taken over manually, the dialog immediately preselects the recommended language and refills its default SDK / LSP.',
                        fr: 'Le dossier ressemble à un projet $detectedProjectLanguageLabel. Tant que vous ne reprenez pas la main, le langage recommandé et ses valeurs SDK / LSP sont présélectionnés.',
                        de: 'Der Ordner wirkt wie ein $detectedProjectLanguageLabel-Projekt. Solange du nicht manuell übernimmst, werden Sprache und Standard-SDK/LSP vorausgewählt.',
                        ja: '現在のディレクトリは $detectedProjectLanguageLabel プロジェクトに見えます。手動で変更していない間は、推奨言語と既定の SDK / LSP を即時入力します。',
                      )));
    final recommendedSdkSourceLabel = _selectedLanguage == 'mixed'
        ? ''
        : _sdkDefaultSourceLabel(context, _selectedLanguage);
    final recommendedLspSourceLabel = _selectedLanguage == 'mixed'
        ? ''
        : _lspDefaultSourceLabel(context, _selectedLanguage);

    return buildOpenHandAlertDialog(
      title: Text(
        text(
          zh: '编程专家配置',
          zhHant: '程式專家設定',
          en: 'Programming Expert Configuration',
          fr: 'Configuration de l’expert programmation',
          de: 'Programmierexperte konfigurieren',
          ja: 'プログラミングエキスパート設定',
        ),
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text(
                  zh: '请配置项目根目录、项目语言，以及可选的 SDK / LSP 路径覆盖。具体语言的默认值会优先跟随全局设置，并结合你最近使用过的该语言路径。',
                  zhHant:
                      '請設定專案根目錄、專案語言，以及可選的 SDK / LSP 路徑覆寫。各語言預設值會優先跟隨全域設定，再使用你最近用過的該語言路徑。',
                  en: 'Configure the project root, primary language, and optional SDK / LSP path overrides. Language-specific defaults follow global settings first and then fall back to your recent paths for that language.',
                  fr: 'Configurez la racine du projet, le langage principal et les chemins SDK / LSP optionnels. Les valeurs par défaut suivent d’abord les paramètres globaux, puis vos chemins récents pour ce langage.',
                  de: 'Konfiguriere Projektwurzel, Hauptsprache und optionale SDK-/LSP-Pfade. Sprachspezifische Standardwerte folgen zuerst den globalen Einstellungen und dann deinen letzten Pfaden.',
                  ja: 'プロジェクトルート、主言語、任意の SDK / LSP パス上書きを設定します。言語ごとの既定値はグローバル設定を優先し、その後最近使ったパスを使います。',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              kOpenHandGap18,
              OpenHandDirectoryField(
                controller: _pathController,
                label: text(
                  zh: '项目根目录',
                  zhHant: '專案根目錄',
                  en: 'Project Root',
                  fr: 'Racine du projet',
                  de: 'Projektwurzel',
                  ja: 'プロジェクトルート',
                ),
                hintText: text(
                  zh: '输入或选择项目根目录路径',
                  zhHant: '輸入或選擇專案根目錄路徑',
                  en: 'Enter or browse project root path',
                  fr: 'Saisir ou choisir la racine du projet',
                  de: 'Projektwurzel eingeben oder auswählen',
                  ja: 'プロジェクトルートのパスを入力または選択',
                ),
                helperText: text(
                  zh: '该目录会作为编程专家的工作空间。',
                  zhHant: '此目錄會作為程式專家的工作區。',
                  en: 'This directory becomes the Programming Expert workspace.',
                  fr: 'Ce dossier devient l’espace de travail de l’expert programmation.',
                  de: 'Dieser Ordner wird der Arbeitsbereich des Programmierexperten.',
                  ja: 'このディレクトリがプログラミングエキスパートのワークスペースになります。',
                ),
                browseTooltip: text(
                  zh: '浏览文件夹',
                  zhHant: '瀏覽資料夾',
                  en: 'Browse folder',
                  fr: 'Parcourir les dossiers',
                  de: 'Ordner durchsuchen',
                  ja: 'フォルダーを参照',
                ),
                onBrowse: _pickProjectDirectory,
              ),
              if (normalizedProjectRoot.isNotEmpty && !projectRootExists) ...[
                kOpenHandGap10,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: colorScheme.error,
                    ),
                    kOpenHandHGap6,
                    Expanded(
                      child: Text(
                        text(
                          zh: '当前路径对应的目录不存在，确认按钮会保持禁用，直到你选择一个有效目录。',
                          zhHant: '目前路徑對應的目錄不存在，確認按鈕會保持停用，直到你選擇有效目錄。',
                          en: 'The current path does not exist, so confirm stays disabled until you choose a valid directory.',
                          fr: 'Le chemin actuel n’existe pas ; la confirmation reste désactivée jusqu’au choix d’un dossier valide.',
                          de: 'Der aktuelle Pfad existiert nicht. Bestätigen bleibt deaktiviert, bis du einen gültigen Ordner auswählst.',
                          ja: '現在のパスに対応するディレクトリは存在しません。有効なディレクトリを選ぶまで確認は無効です。',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (currentWorkspacePath.isNotEmpty) ...[
                kOpenHandGap10,
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary.withValues(alpha: 0.08),
                    borderRadius: kOpenHandBorderRadius12,
                    border: Border.all(
                      color: colorScheme.tertiary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.work_outline_rounded,
                        size: 18,
                        color: colorScheme.tertiary,
                      ),
                      kOpenHandHGap10,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              text(
                                zh: '当前工作区',
                                zhHant: '目前工作區',
                                en: 'Current Workspace',
                                fr: 'Espace de travail actuel',
                                de: 'Aktueller Arbeitsbereich',
                                ja: '現在のワークスペース',
                              ),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.tertiary,
                              ),
                            ),
                            kOpenHandGap4,
                            Text(
                              OpenHandPaths.shortenHomePath(
                                currentWorkspacePath,
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                            kOpenHandGap6,
                            Text(
                              currentWorkspaceExists
                                  ? text(
                                      zh: '可一键填充为项目根目录，并立即触发语言识别与默认值预选。',
                                      zhHant: '可一鍵填入為專案根目錄，並立即觸發語言識別與預設值預選。',
                                      en: 'Use it as the project root in one click and immediately trigger language detection and default prefilling.',
                                      fr: 'Utilisez-le comme racine du projet en un clic et lancez aussitôt la détection du langage et le préremplissage.',
                                      de: 'Nutze ihn mit einem Klick als Projektwurzel und starte sofort Spracherkennung und Vorausfüllung.',
                                      ja: 'ワンクリックでプロジェクトルートにし、言語検出と既定値の事前入力をすぐ実行できます。',
                                    )
                                  : text(
                                      zh: '这个工作区路径当前不可访问，请先确认目录是否仍然存在。',
                                      zhHant: '這個工作區路徑目前無法存取，請先確認目錄是否仍然存在。',
                                      en: 'This workspace path is not accessible right now. Check whether the directory still exists.',
                                      fr: 'Ce chemin d’espace de travail est inaccessible. Vérifiez que le dossier existe toujours.',
                                      de: 'Dieser Arbeitsbereichspfad ist derzeit nicht erreichbar. Prüfe, ob der Ordner noch existiert.',
                                      ja: 'このワークスペースパスには現在アクセスできません。ディレクトリがまだ存在するか確認してください。',
                                    ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      kOpenHandHGap10,
                      if (currentWorkspaceMatchesProjectRoot)
                        Chip(
                          label: Text(
                            text(
                              zh: '已使用',
                              zhHant: '使用中',
                              en: 'In Use',
                              fr: 'Utilisé',
                              de: 'In Verwendung',
                              ja: '使用中',
                            ),
                          ),
                          avatar: const Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                          ),
                          visualDensity: VisualDensity.compact,
                        )
                      else
                        FilledButton.tonalIcon(
                          onPressed: currentWorkspaceExists
                              ? () {
                                  unawaited(
                                    _applyProjectRootSelection(
                                      currentWorkspacePath,
                                    ),
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.my_location_rounded, size: 18),
                          label: Text(
                            text(
                              zh: '填充当前工作区',
                              zhHant: '填入目前工作區',
                              en: 'Use Current Workspace',
                              fr: 'Utiliser l’espace actuel',
                              de: 'Aktuellen Arbeitsbereich nutzen',
                              ja: '現在のワークスペースを使用',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (normalizedProjectRoot.isNotEmpty &&
                  (recentProjectConfig != null ||
                      detectedProjectLanguage != 'mixed')) ...[
                kOpenHandGap10,
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: kOpenHandBorderRadius12,
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recentProjectConfig != null
                            ? (isFollowingRecentProjectConfig
                                  ? text(
                                      zh: '已即时应用最近项目配置',
                                      zhHant: '已即時套用最近專案設定',
                                      en: 'Recent project config applied immediately',
                                      fr: 'Configuration récente appliquée immédiatement',
                                      de: 'Letzte Projektkonfiguration sofort angewendet',
                                      ja: '最近のプロジェクト設定を即時適用しました',
                                    )
                                  : text(
                                      zh: '已命中最近项目配置',
                                      zhHant: '已命中最近專案設定',
                                      en: 'Matched recent project config',
                                      fr: 'Configuration récente du projet trouvée',
                                      de: 'Letzte Projektkonfiguration gefunden',
                                      ja: '最近のプロジェクト設定に一致',
                                    ))
                            : (isFollowingDetectedRecommendation
                                  ? text(
                                      zh: '已即时预选项目语言',
                                      zhHant: '已即時預選專案語言',
                                      en: 'Detected project language preselected',
                                      fr: 'Langage du projet détecté et présélectionné',
                                      de: 'Erkannte Projektsprache vorausgewählt',
                                      ja: '検出したプロジェクト言語を事前選択しました',
                                    )
                                  : text(
                                      zh: '项目语言建议',
                                      zhHant: '專案語言建議',
                                      en: 'Project language suggestion',
                                      fr: 'Suggestion de langage',
                                      de: 'Vorschlag für Projektsprache',
                                      ja: 'プロジェクト言語の候補',
                                    )),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary,
                        ),
                      ),
                      kOpenHandGap6,
                      Text(
                        projectLanguageHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                      kOpenHandGap8,
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (recentProjectConfig != null)
                            ActionChip(
                              label: Text(
                                isFollowingRecentProjectConfig
                                    ? text(
                                        zh: '重新应用最近配置',
                                        zhHant: '重新套用最近設定',
                                        en: 'Reapply Recent Config',
                                        fr: 'Réappliquer la config récente',
                                        de: 'Letzte Konfiguration erneut anwenden',
                                        ja: '最近の設定を再適用',
                                      )
                                    : text(
                                        zh: '回填最近配置',
                                        zhHant: '回填最近設定',
                                        en: 'Refill Recent Config',
                                        fr: 'Renseigner la config récente',
                                        de: 'Letzte Konfiguration übernehmen',
                                        ja: '最近の設定を入力',
                                      ),
                              ),
                              onPressed: () {
                                _applyProjectConfig(recentProjectConfig);
                              },
                            ),
                          if (recentProjectConfig == null &&
                              detectedProjectLanguage != 'mixed' &&
                              !isFollowingDetectedRecommendation)
                            ActionChip(
                              label: Text(
                                detectedProjectLanguage == _selectedLanguage
                                    ? text(
                                        zh: '恢复自动预选',
                                        zhHant: '恢復自動預選',
                                        en: 'Resume Auto-Preselect',
                                        fr: 'Reprendre la présélection',
                                        de: 'Automatische Vorauswahl fortsetzen',
                                        ja: '自動事前選択を再開',
                                      )
                                    : text(
                                        zh: '立即预选推荐语言',
                                        zhHant: '立即預選建議語言',
                                        en: 'Preselect Suggested Language',
                                        fr: 'Présélectionner le langage suggéré',
                                        de: 'Vorgeschlagene Sprache auswählen',
                                        ja: '推奨言語を事前選択',
                                      ),
                              ),
                              onPressed: () {
                                unawaited(
                                  _applyDetectedLanguageForProjectRoot(
                                    normalizedProjectRoot,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              kOpenHandGap18,
              Text(
                text(
                  zh: '项目编程语言',
                  zhHant: '專案程式語言',
                  en: 'Project Language',
                  fr: 'Langage du projet',
                  de: 'Projektsprache',
                  ja: 'プロジェクト言語',
                ),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              kOpenHandGap8,
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _programmingLanguageOptions
                    .map((opt) {
                      final selected = _selectedLanguage == opt.id;
                      return ChoiceChip(
                        label: Text(
                          _programmingLanguageOptionLabel(context, opt),
                        ),
                        selected: selected,
                        onSelected: (_) => _setSelectedLanguage(opt.id),
                        selectedColor: colorScheme.primaryContainer,
                        labelStyle: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: kOpenHandBorderRadius20,
                          side: BorderSide(
                            color: selected
                                ? colorScheme.primary.withValues(alpha: 0.4)
                                : colorScheme.outline.withValues(alpha: 0.3),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
              if (_selectedLanguage == 'mixed') ...[
                kOpenHandGap10,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    kOpenHandHGap6,
                    Expanded(
                      child: Text(
                        text(
                          zh: '混合模式会按文件后缀自动识别语言，并继续使用全局的按语言 SDK / LSP 映射；因此这里不会设置单一项目级覆盖。',
                          zhHant:
                              '混合模式會依檔案副檔名自動識別語言，並繼續使用全域的各語言 SDK / LSP 對應；因此這裡不會設定單一專案級覆寫。',
                          en: 'Mixed mode auto-detects the language per file and continues using the global per-language SDK / LSP mappings, so no single project-level override is applied here.',
                          fr: 'Le mode mixte détecte le langage par fichier et utilise les correspondances SDK / LSP globales ; aucun remplacement unique au niveau du projet n’est appliqué ici.',
                          de: 'Der gemischte Modus erkennt die Sprache pro Datei und nutzt die globalen SDK-/LSP-Zuordnungen. Daher wird hier keine einzelne Projektüberschreibung gesetzt.',
                          ja: '混在モードではファイル拡張子ごとに言語を自動検出し、グローバルな言語別 SDK / LSP マッピングを使うため、単一のプロジェクト上書きは設定しません。',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.8,
                          ),
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                kOpenHandGap18,
                OpenHandDirectoryField(
                  controller: _sdkController,
                  label: text(
                    zh: 'SDK 路径',
                    zhHant: 'SDK 路徑',
                    en: 'SDK Path',
                    fr: 'Chemin SDK',
                    de: 'SDK-Pfad',
                    ja: 'SDK パス',
                  ),
                  hintText: text(
                    zh: '留空则沿用全局配置或系统默认',
                    zhHant: '留空則沿用全域設定或系統預設',
                    en: 'Leave empty to use the global setting or system default',
                    fr: 'Laisser vide pour utiliser le paramètre global ou la valeur système',
                    de: 'Leer lassen, um globale Einstellung oder Systemstandard zu verwenden',
                    ja: '空のままならグローバル設定またはシステム既定値を使用',
                  ),
                  helperText: text(
                    zh: '默认优先使用全局设置中的该语言 SDK 路径。',
                    zhHant: '預設優先使用全域設定中的該語言 SDK 路徑。',
                    en: 'Defaults to the global SDK path configured for this language.',
                    fr: 'Utilise par défaut le chemin SDK global configuré pour ce langage.',
                    de: 'Verwendet standardmäßig den globalen SDK-Pfad für diese Sprache.',
                    ja: '既定ではこの言語のグローバル SDK パスを優先します。',
                  ),
                  browseTooltip: text(
                    zh: '浏览文件夹',
                    zhHant: '瀏覽資料夾',
                    en: 'Browse folder',
                    fr: 'Parcourir les dossiers',
                    de: 'Ordner durchsuchen',
                    ja: 'フォルダーを参照',
                  ),
                  onBrowse: _pickSdkDirectory,
                ),
                if (recentSdkPaths.isNotEmpty) ...[
                  kOpenHandGap8,
                  _ProgrammingExpertRecentPathChips(
                    title: text(
                      zh: '最近 SDK 路径',
                      zhHant: '最近 SDK 路徑',
                      en: 'Recent SDK Paths',
                      fr: 'Chemins SDK récents',
                      de: 'Letzte SDK-Pfade',
                      ja: '最近の SDK パス',
                    ),
                    paths: recentSdkPaths,
                    onSelected: (value) {
                      _sdkController.text = value;
                    },
                  ),
                ],
                kOpenHandGap18,
                OpenHandDirectoryField(
                  controller: _lspController,
                  label: text(
                    zh: 'LSP 路径',
                    zhHant: 'LSP 路徑',
                    en: 'LSP Path',
                    fr: 'Chemin LSP',
                    de: 'LSP-Pfad',
                    ja: 'LSP パス',
                  ),
                  hintText: text(
                    zh: '留空则沿用全局映射或 PATH 自动探测',
                    zhHant: '留空則沿用全域對應或 PATH 自動偵測',
                    en: 'Leave empty to use the global mapping or PATH resolution',
                    fr: 'Laisser vide pour utiliser la correspondance globale ou la résolution PATH',
                    de: 'Leer lassen, um globale Zuordnung oder PATH-Auflösung zu verwenden',
                    ja: '空のままならグローバルマッピングまたは PATH 解決を使用',
                  ),
                  helperText: text(
                    zh: '默认优先使用全局设置中的该语言 LSP 根路径。',
                    zhHant: '預設優先使用全域設定中的該語言 LSP 根路徑。',
                    en: 'Defaults to the global LSP root configured for this language.',
                    fr: 'Utilise par défaut la racine LSP globale configurée pour ce langage.',
                    de: 'Verwendet standardmäßig den globalen LSP-Stammpfad für diese Sprache.',
                    ja: '既定ではこの言語のグローバル LSP ルートを優先します。',
                  ),
                  browseTooltip: text(
                    zh: '浏览文件夹',
                    zhHant: '瀏覽資料夾',
                    en: 'Browse folder',
                    fr: 'Parcourir les dossiers',
                    de: 'Ordner durchsuchen',
                    ja: 'フォルダーを参照',
                  ),
                  onBrowse: _pickLspDirectory,
                ),
                if (recentLspPaths.isNotEmpty) ...[
                  kOpenHandGap8,
                  _ProgrammingExpertRecentPathChips(
                    title: text(
                      zh: '最近 LSP 路径',
                      zhHant: '最近 LSP 路徑',
                      en: 'Recent LSP Paths',
                      fr: 'Chemins LSP récents',
                      de: 'Letzte LSP-Pfade',
                      ja: '最近の LSP パス',
                    ),
                    paths: recentLspPaths,
                    onSelected: (value) {
                      _lspController.text = value;
                    },
                  ),
                ],
                kOpenHandGap12,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    kOpenHandHGap6,
                    Expanded(
                      child: Text(
                        text(
                          zh: '当前语言的推荐默认值：SDK 来自 $recommendedSdkSourceLabel，LSP 来自 $recommendedLspSourceLabel。',
                          zhHant:
                              '目前語言的建議預設值：SDK 來自 $recommendedSdkSourceLabel，LSP 來自 $recommendedLspSourceLabel。',
                          en: 'Recommended defaults for this language: SDK comes from $recommendedSdkSourceLabel and LSP comes from $recommendedLspSourceLabel.',
                          fr: 'Valeurs recommandées pour ce langage : SDK depuis $recommendedSdkSourceLabel, LSP depuis $recommendedLspSourceLabel.',
                          de: 'Empfohlene Standardwerte für diese Sprache: SDK aus $recommendedSdkSourceLabel, LSP aus $recommendedLspSourceLabel.',
                          ja: 'この言語の推奨既定値: SDK は $recommendedSdkSourceLabel、LSP は $recommendedLspSourceLabel から取得します。',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
                kOpenHandGap8,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canRestoreRecommendedDefaults)
                      ActionChip(
                        label: Text(
                          text(
                            zh: '回填推荐默认值',
                            zhHant: '回填建議預設值',
                            en: 'Restore Recommended Defaults',
                            fr: 'Rétablir les valeurs recommandées',
                            de: 'Empfohlene Standardwerte wiederherstellen',
                            ja: '推奨既定値を復元',
                          ),
                        ),
                        onPressed:
                            _restoreRecommendedDefaultsForSelectedLanguage,
                      ),
                    if (canClearProjectOverrides)
                      ActionChip(
                        label: Text(
                          text(
                            zh: '清空项目级覆盖',
                            zhHant: '清空專案級覆寫',
                            en: 'Clear Project Overrides',
                            fr: 'Effacer les remplacements du projet',
                            de: 'Projektüberschreibungen löschen',
                            ja: 'プロジェクト上書きをクリア',
                          ),
                        ),
                        onPressed: _clearProjectOverridesForSelectedLanguage,
                      ),
                  ],
                ),
              ],
              if (recentProjectRoots.isNotEmpty) ...[
                kOpenHandGap18,
                Text(
                  text(
                    zh: '最近项目',
                    zhHant: '最近專案',
                    en: 'Recent Projects',
                    fr: 'Projets récents',
                    de: 'Letzte Projekte',
                    ja: '最近のプロジェクト',
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                kOpenHandGap8,
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: recentProjectRoots
                          .map((path) {
                            final dirName = p.basename(path);
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: kOpenHandBorderRadius8,
                                onTap: () {
                                  unawaited(_applyProjectRootSelection(path));
                                },
                                onDoubleTap: () async {
                                  await _applyProjectRootSelection(path);
                                  if (!mounted) {
                                    return;
                                  }
                                  _submit();
                                },
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.folder_rounded,
                                        size: 18,
                                        color: colorScheme.primary,
                                      ),
                                      kOpenHandHGap10,
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              dirName,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              path,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: openHandCancelLabel(context),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _pathController,
          builder: (context, value, _) {
            final normalizedPath = OpenHandPaths.normalizeOptionalPath(
              value.text,
            );
            final hasValue =
                normalizedPath.isNotEmpty &&
                _validatedProjectRoot == normalizedPath &&
                _projectRootExists;
            return OpenHandDialogActionButton.primary(
              onPressed: hasValue ? () => unawaited(_submit()) : null,
              label: text(
                zh: '确定',
                zhHant: '確定',
                en: 'Confirm',
                fr: 'Confirmer',
                de: 'Bestätigen',
                ja: '確定',
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ProgrammingExpertRecentPathChips extends StatelessWidget {
  const _ProgrammingExpertRecentPathChips({
    required this.title,
    required this.paths,
    required this.onSelected,
  });

  final String title;
  final List<String> paths;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap6,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: paths
              .map((path) {
                return Tooltip(
                  message: path,
                  child: ActionChip(
                    label: Text(OpenHandPaths.shortenHomePath(path)),
                    onPressed: () => onSelected(path),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }
}

_ProgrammingExpertRecentPathCache _collectProgrammingExpertRecentPaths(
  List<AiSession> sessions,
) {
  final seenProjectRoots = <String>{};
  final projectRoots = <String>[];
  final configsByProjectRoot = <String, _ProgrammingExpertConfig>{};
  final sdkSeenByLanguage = <String, Set<String>>{};
  final sdkPathsByLanguage = <String, List<String>>{};
  final lspSeenByLanguage = <String, Set<String>>{};
  final lspPathsByLanguage = <String, List<String>>{};

  for (final session in sessions) {
    if (session.templateId != 'programming_expert') {
      continue;
    }
    final config = session.metadata['programming_expert_config'];
    if (config is! Map) {
      continue;
    }

    final rawProjectRoot = config['project_root'];
    final projectRoot = OpenHandPaths.normalizeOptionalPath(
      '${rawProjectRoot ?? ''}',
    );
    if (projectRoot.isNotEmpty) {
      if (seenProjectRoots.add(projectRoot)) {
        projectRoots.add(projectRoot);
      }
    }

    final language = normalizeAiLspLanguage('${config['language'] ?? 'mixed'}');
    final sdkPath = OpenHandPaths.normalizeOptionalPath(
      '${config['sdk_path'] ?? ''}',
    );
    final lspPath = OpenHandPaths.normalizeOptionalPath(
      '${config['lsp_path'] ?? ''}',
    );
    if (projectRoot.isNotEmpty) {
      configsByProjectRoot.putIfAbsent(
        projectRoot,
        () => _ProgrammingExpertConfig(
          projectRoot: projectRoot,
          language: language,
          sdkPath: sdkPath,
          lspPath: lspPath,
        ),
      );
    }
    if (language == 'mixed' || language == 'plaintext') {
      continue;
    }

    if (sdkPath.isNotEmpty) {
      _appendRecentProgrammingExpertPath(
        language: language,
        path: sdkPath,
        target: sdkPathsByLanguage,
        seen: sdkSeenByLanguage,
      );
    }

    if (lspPath.isNotEmpty) {
      _appendRecentProgrammingExpertPath(
        language: language,
        path: lspPath,
        target: lspPathsByLanguage,
        seen: lspSeenByLanguage,
      );
    }
  }

  return _ProgrammingExpertRecentPathCache(
    projectRoots: projectRoots.take(10).toList(growable: false),
    configsByProjectRoot: Map<String, _ProgrammingExpertConfig>.unmodifiable(
      configsByProjectRoot,
    ),
    sdkPathsByLanguage: <String, List<String>>{
      for (final entry in sdkPathsByLanguage.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    },
    lspPathsByLanguage: <String, List<String>>{
      for (final entry in lspPathsByLanguage.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    },
  );
}

void _appendRecentProgrammingExpertPath({
  required String language,
  required String path,
  required Map<String, List<String>> target,
  required Map<String, Set<String>> seen,
}) {
  final seenForLanguage = seen.putIfAbsent(language, () => <String>{});
  if (!seenForLanguage.add(path)) {
    return;
  }
  final paths = target.putIfAbsent(language, () => <String>[]);
  if (paths.length < 6) {
    paths.add(path);
  }
}

String _homeProgramminGlobalSettingsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '全局设置',
    zhHant: '全域設定',
    en: 'global settings',
    fr: 'paramètres globaux',
    de: 'globale Einstellungen',
    ja: 'グローバル設定',
  );
}

String _homeProgramminRecentHistoryLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '最近记录',
    zhHant: '最近記錄',
    en: 'recent history',
    fr: 'historique récent',
    de: 'letzter Verlauf',
    ja: '最近の履歴',
  );
}
