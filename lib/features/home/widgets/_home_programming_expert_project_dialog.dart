part of '../openhand_home_page.dart';

/// Result returned by the programming expert configuration dialog.
class _ProgrammingExpertConfig {
  const _ProgrammingExpertConfig({
    required this.projectRoot,
    required this.language,
    required this.sdkPath,
    required this.lspPath,
  });

  final String projectRoot;

  /// Language identifier: 'dart', 'python', 'go', 'java', 'javascript',
  /// 'typescript', 'rust', 'cpp', 'swift', 'kotlin', 'mixed', etc.
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

/// Supported project language options.
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
    final isZh = openHandIsChineseLocale(context);
    return isZh ? option.labelZh : option.labelEn;
  }
  if (languageId.isEmpty) {
    return 'Plain Text';
  }
  return languageId[0].toUpperCase() + languageId.substring(1);
}

/// Dialog shown after selecting the "编程专家" template.
/// Lets the user configure project root path, primary language, SDK path,
/// and project-level LSP path overrides.
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
  bool _suspendProjectRootDraftListener = false;
  bool _suspendToolchainDraftListener = false;
  String? _autoSelectedLanguage;
  String _autoSelectedSdkPath = '';
  String _autoSelectedLspPath = '';
  String _selectedLanguage = 'mixed';

  @override
  void initState() {
    super.initState();
    _pathController.addListener(_handleProjectRootTextChanged);
    _sdkController.addListener(_handleToolchainDraftChanged);
    _lspController.addListener(_handleToolchainDraftChanged);
  }

  @override
  void dispose() {
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
    _projectRootDraftDebouncer.schedule(_syncProjectRootDraftState);
  }

  void _handleToolchainDraftChanged() {
    if (_suspendToolchainDraftListener) {
      return;
    }
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

  void _syncProjectRootDraftState() {
    if (!mounted || _suspendProjectRootDraftListener) {
      return;
    }
    final normalized = OpenHandPaths.normalizeOptionalPath(
      _pathController.text,
    );
    if (normalized.isEmpty) {
      setState(() {});
      return;
    }
    final recentConfig = _recentConfigForProjectRoot(normalized);
    if (_canAutoBackfillProjectDefaults && recentConfig != null) {
      _applyProjectConfig(recentConfig, syncProjectRoot: false);
      return;
    }
    final detectedLanguage = _detectProjectLanguage(normalized);
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

  Future<void> _pickProjectDirectory() async {
    final current = _pathController.text.trim();
    final result = await getDirectoryPath(
      initialDirectory: current.isNotEmpty ? current : null,
    );
    if (result != null && mounted) {
      _applyProjectRootSelection(result);
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

  String _detectProjectLanguage(String projectRoot) {
    final normalized = OpenHandPaths.normalizeOptionalPath(projectRoot);
    if (normalized.isEmpty) {
      return 'mixed';
    }
    final root = Directory(normalized);
    if (!root.existsSync()) {
      return 'mixed';
    }

    bool hasEntry(String relativePath) {
      final file = File(p.join(normalized, relativePath));
      if (file.existsSync()) {
        return true;
      }
      return Directory(p.join(normalized, relativePath)).existsSync();
    }

    bool hasExtension(List<String> extensions) {
      const candidateDirs = <String>['', 'lib', 'src', 'app', 'bin', 'test'];
      for (final relativeDir in candidateDirs) {
        final dir = Directory(
          relativeDir.isEmpty ? normalized : p.join(normalized, relativeDir),
        );
        if (!dir.existsSync()) {
          continue;
        }
        try {
          for (final entry in dir.listSync(followLinks: false)) {
            if (entry is! File) {
              continue;
            }
            if (extensions.contains(p.extension(entry.path).toLowerCase())) {
              return true;
            }
          }
        } catch (error, stack) {
          silentLog(
            'project_dialog',
            'list directory for language probe',
            error,
            stack,
          );
        }
      }
      return false;
    }

    if (hasEntry('pubspec.yaml')) {
      return 'dart';
    }
    if (hasEntry('go.mod')) {
      return 'go';
    }
    if (hasEntry('Cargo.toml')) {
      return 'rust';
    }
    if (hasEntry('Package.swift')) {
      return 'swift';
    }
    if (hasEntry('composer.json')) {
      return 'php';
    }
    if (hasEntry('Gemfile')) {
      return 'ruby';
    }
    if (hasEntry('tsconfig.json')) {
      return 'typescript';
    }
    if (hasEntry('package.json')) {
      return hasExtension(const <String>['.ts', '.tsx'])
          ? 'typescript'
          : 'javascript';
    }
    if (hasEntry('pom.xml') ||
        hasEntry('build.gradle') ||
        hasEntry('build.gradle.kts') ||
        hasEntry('settings.gradle') ||
        hasEntry('settings.gradle.kts')) {
      if (hasEntry('src/main/kotlin') || hasEntry('app/src/main/kotlin')) {
        return 'kotlin';
      }
      return 'java';
    }
    if (hasExtension(const <String>['.csproj', '.sln', '.cs'])) {
      return 'csharp';
    }
    if (hasExtension(const <String>['.kt', '.kts'])) {
      return 'kotlin';
    }
    if (hasExtension(const <String>['.dart'])) {
      return 'dart';
    }
    if (hasExtension(const <String>['.py'])) {
      return 'python';
    }
    if (hasExtension(const <String>['.java'])) {
      return 'java';
    }
    if (hasExtension(const <String>['.go'])) {
      return 'go';
    }
    if (hasExtension(const <String>['.rs'])) {
      return 'rust';
    }
    if (hasExtension(const <String>['.cpp', '.cc', '.cxx', '.hpp', '.h'])) {
      return 'cpp';
    }
    if (hasExtension(const <String>['.js', '.jsx'])) {
      return 'javascript';
    }
    if (hasExtension(const <String>['.sh', '.bash', '.zsh'])) {
      return 'shell';
    }
    return 'mixed';
  }

  String _sdkDefaultSourceLabel(String language, {required bool isZh}) {
    final globalValue = widget.settingsController
        .editorLspSettingsForLanguage(language)
        .sdkPath
        .trim();
    if (globalValue.isNotEmpty) {
      return isZh ? '全局设置' : 'global settings';
    }
    if ((widget.recentPathCache.sdkPathsByLanguage[language] ??
            const <String>[])
        .isNotEmpty) {
      return isZh ? '最近记录' : 'recent history';
    }
    return isZh ? '系统默认' : 'system default';
  }

  String _lspDefaultSourceLabel(String language, {required bool isZh}) {
    final globalValue = widget.settingsController
        .editorLspSettingsForLanguage(language)
        .rootPath
        .trim();
    if (globalValue.isNotEmpty) {
      return isZh ? '全局设置' : 'global settings';
    }
    if ((widget.recentPathCache.lspPathsByLanguage[language] ??
            const <String>[])
        .isNotEmpty) {
      return isZh ? '最近记录' : 'recent history';
    }
    return isZh ? 'PATH / 自动探测' : 'PATH / auto-detect';
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

  void _applyDetectedLanguageForProjectRoot(String projectRoot) {
    final detectedLanguage = _detectProjectLanguage(projectRoot);
    if (detectedLanguage == 'mixed') {
      return;
    }
    _applyAutomaticLanguageSelection(language: detectedLanguage);
  }

  void _applyProjectRootSelection(String projectRoot) {
    final normalized = OpenHandPaths.normalizeOptionalPath(projectRoot);
    if (normalized.isEmpty) {
      return;
    }
    _setProjectRootText(normalized);
    final recentConfig = _recentConfigForProjectRoot(normalized);
    if (_canAutoBackfillProjectDefaults && recentConfig != null) {
      _applyProjectConfig(recentConfig);
      return;
    }
    final detectedLanguage = _detectProjectLanguage(normalized);
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
    _clearAutomaticSelectionState();
    _applyLanguageSelection(
      language: language,
      sdkDraft: _sdkDraftByLanguage[language],
      lspDraft: _lspDraftByLanguage[language],
    );
  }

  void _submit() {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      return;
    }
    final normalizedProjectRoot = OpenHandPaths.normalizeOptionalPath(path);
    if (normalizedProjectRoot.isEmpty ||
        !Directory(normalizedProjectRoot).existsSync()) {
      return;
    }
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
    final isZh = openHandIsChineseLocale(context);
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
        Directory(normalizedProjectRoot).existsSync();
    final currentWorkspaceExists =
        currentWorkspacePath.isNotEmpty &&
        Directory(currentWorkspacePath).existsSync();
    final currentWorkspaceMatchesProjectRoot =
        currentWorkspacePath.isNotEmpty &&
        currentWorkspacePath == normalizedProjectRoot;
    final recentProjectConfig = _recentConfigForProjectRoot(
      normalizedProjectRoot,
    );
    final detectedProjectLanguage =
        recentProjectConfig?.language ??
        _detectProjectLanguage(normalizedProjectRoot);
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

    return buildOpenHandAlertDialog(
      title: Text(isZh ? '编程专家配置' : 'Programming Expert Configuration'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isZh
                    ? '请配置项目根目录、项目语言，以及可选的 SDK / LSP 路径覆盖。具体语言的默认值会优先跟随全局设置，并结合你最近使用过的该语言路径。'
                    : 'Configure the project root, primary language, and optional SDK / LSP path overrides. Language-specific defaults follow global settings first and then fall back to your recent paths for that language.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              _ProgrammingExpertDirectoryField(
                controller: _pathController,
                label: isZh ? '项目根目录' : 'Project Root',
                hintText: isZh
                    ? '输入或选择项目根目录路径'
                    : 'Enter or browse project root path',
                helperText: isZh
                    ? '该目录会作为编程专家的工作空间。'
                    : 'This directory becomes the Programming Expert workspace.',
                browseTooltip: isZh ? '浏览文件夹' : 'Browse folder',
                onBrowse: _pickProjectDirectory,
              ),
              if (normalizedProjectRoot.isNotEmpty && !projectRootExists) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isZh
                            ? '当前路径对应的目录不存在，确认按钮会保持禁用，直到你选择一个有效目录。'
                            : 'The current path does not exist, so confirm stays disabled until you choose a valid directory.',
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
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isZh ? '当前工作区' : 'Current Workspace',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.tertiary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              OpenHandPaths.shortenHomePath(
                                currentWorkspacePath,
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              currentWorkspaceExists
                                  ? (isZh
                                        ? '可一键填充为项目根目录，并立即触发语言识别与默认值预选。'
                                        : 'Use it as the project root in one click and immediately trigger language detection and default prefilling.')
                                  : (isZh
                                        ? '这个工作区路径当前不可访问，请先确认目录是否仍然存在。'
                                        : 'This workspace path is not accessible right now. Check whether the directory still exists.'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (currentWorkspaceMatchesProjectRoot)
                        Chip(
                          label: Text(isZh ? '已使用' : 'In Use'),
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
                                  _applyProjectRootSelection(
                                    currentWorkspacePath,
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.my_location_rounded, size: 18),
                          label: Text(
                            isZh ? '填充当前工作区' : 'Use Current Workspace',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (normalizedProjectRoot.isNotEmpty &&
                  (recentProjectConfig != null ||
                      detectedProjectLanguage != 'mixed')) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
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
                                  ? (isZh
                                        ? '已即时应用最近项目配置'
                                        : 'Recent project config applied immediately')
                                  : (isZh
                                        ? '已命中最近项目配置'
                                        : 'Matched recent project config'))
                            : (isFollowingDetectedRecommendation
                                  ? (isZh
                                        ? '已即时预选项目语言'
                                        : 'Detected project language preselected')
                                  : (isZh
                                        ? '项目语言建议'
                                        : 'Project language suggestion')),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        recentProjectConfig != null
                            ? (isFollowingRecentProjectConfig
                                  ? (isZh
                                        ? '这个目录最近一次使用的是 ${_programmingLanguageLabel(context, recentProjectConfig.language)} 配置，当前已经即时回填对应语言、SDK 路径和 LSP 路径。后续只要你还没有手动改动，这些默认值会继续跟随目录切换。'
                                        : 'This directory was most recently opened as ${_programmingLanguageLabel(context, recentProjectConfig.language)}, and that language, SDK path, and LSP path have already been refilled. As long as you do not manually override them, the defaults continue following the directory change.')
                                  : (isZh
                                        ? '这个目录最近一次使用的是 ${_programmingLanguageLabel(context, recentProjectConfig.language)} 配置。可以一键回填当时的语言、SDK 路径和 LSP 路径。'
                                        : 'This directory was recently opened as ${_programmingLanguageLabel(context, recentProjectConfig.language)}. You can refill that language, SDK path, and LSP path in one step.'))
                            : (isFollowingDetectedRecommendation
                                  ? (isZh
                                        ? '从当前目录结构看，它更像是 ${_programmingLanguageLabel(context, detectedProjectLanguage)} 项目，当前已经即时预选该语言，并跟随该语言的默认 SDK / LSP。你仍然可以手动切换。'
                                        : 'The current directory looks like a ${_programmingLanguageLabel(context, detectedProjectLanguage)} project, so that language has already been preselected together with its default SDK / LSP. You can still switch manually at any time.')
                                  : (!_canAutoBackfillProjectDefaults
                                        ? (isZh
                                              ? '从当前目录结构看，它更像是 ${_programmingLanguageLabel(context, detectedProjectLanguage)} 项目；但你已经手动调整过语言或工具链路径，所以本次不会自动覆盖。需要时可点下面的按钮恢复自动预选。'
                                              : 'The current directory looks like a ${_programmingLanguageLabel(context, detectedProjectLanguage)} project, but you have already adjusted the language or toolchain paths manually, so this dialog will not overwrite them automatically. Use the action below to resume auto-preselection if needed.')
                                        : (isZh
                                              ? '从当前目录结构看，它更像是 ${_programmingLanguageLabel(context, detectedProjectLanguage)} 项目。会在你尚未手动接管时即时预选推荐语言，并回填该语言的默认 SDK / LSP。'
                                              : 'The current directory looks like a ${_programmingLanguageLabel(context, detectedProjectLanguage)} project. While you have not taken over manually, the dialog immediately preselects the recommended language and refills its default SDK / LSP.'))),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (recentProjectConfig != null)
                            ActionChip(
                              label: Text(
                                isFollowingRecentProjectConfig
                                    ? (isZh
                                          ? '重新应用最近配置'
                                          : 'Reapply Recent Config')
                                    : (isZh
                                          ? '回填最近配置'
                                          : 'Refill Recent Config'),
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
                                    ? (isZh
                                          ? '恢复自动预选'
                                          : 'Resume Auto-Preselect')
                                    : (isZh
                                          ? '立即预选推荐语言'
                                          : 'Preselect Suggested Language'),
                              ),
                              onPressed: () {
                                _applyDetectedLanguageForProjectRoot(
                                  normalizedProjectRoot,
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                isZh ? '项目编程语言' : 'Project Language',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _programmingLanguageOptions
                    .map((opt) {
                      final selected = _selectedLanguage == opt.id;
                      return ChoiceChip(
                        label: Text(isZh ? opt.labelZh : opt.labelEn),
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
                          borderRadius: BorderRadius.circular(20),
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
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isZh
                            ? '混合模式会按文件后缀自动识别语言，并继续使用全局的按语言 SDK / LSP 映射；因此这里不会设置单一项目级覆盖。'
                            : 'Mixed mode auto-detects the language per file and continues using the global per-language SDK / LSP mappings, so no single project-level override is applied here.',
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
                const SizedBox(height: 18),
                _ProgrammingExpertDirectoryField(
                  controller: _sdkController,
                  label: isZh ? 'SDK 路径' : 'SDK Path',
                  hintText: isZh
                      ? '留空则沿用全局配置或系统默认'
                      : 'Leave empty to use the global setting or system default',
                  helperText: isZh
                      ? '默认优先使用全局设置中的该语言 SDK 路径。'
                      : 'Defaults to the global SDK path configured for this language.',
                  browseTooltip: isZh ? '浏览文件夹' : 'Browse folder',
                  onBrowse: _pickSdkDirectory,
                ),
                if (recentSdkPaths.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _ProgrammingExpertRecentPathChips(
                    title: isZh ? '最近 SDK 路径' : 'Recent SDK Paths',
                    paths: recentSdkPaths,
                    onSelected: (value) {
                      _sdkController.text = value;
                    },
                  ),
                ],
                const SizedBox(height: 18),
                _ProgrammingExpertDirectoryField(
                  controller: _lspController,
                  label: isZh ? 'LSP 路径' : 'LSP Path',
                  hintText: isZh
                      ? '留空则沿用全局映射或 PATH 自动探测'
                      : 'Leave empty to use the global mapping or PATH resolution',
                  helperText: isZh
                      ? '默认优先使用全局设置中的该语言 LSP 根路径。'
                      : 'Defaults to the global LSP root configured for this language.',
                  browseTooltip: isZh ? '浏览文件夹' : 'Browse folder',
                  onBrowse: _pickLspDirectory,
                ),
                if (recentLspPaths.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _ProgrammingExpertRecentPathChips(
                    title: isZh ? '最近 LSP 路径' : 'Recent LSP Paths',
                    paths: recentLspPaths,
                    onSelected: (value) {
                      _lspController.text = value;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isZh
                            ? '当前语言的推荐默认值：SDK 来自 ${_sdkDefaultSourceLabel(_selectedLanguage, isZh: true)}，LSP 来自 ${_lspDefaultSourceLabel(_selectedLanguage, isZh: true)}。'
                            : 'Recommended defaults for this language: SDK comes from ${_sdkDefaultSourceLabel(_selectedLanguage, isZh: false)} and LSP comes from ${_lspDefaultSourceLabel(_selectedLanguage, isZh: false)}.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canRestoreRecommendedDefaults)
                      ActionChip(
                        label: Text(
                          isZh ? '回填推荐默认值' : 'Restore Recommended Defaults',
                        ),
                        onPressed:
                            _restoreRecommendedDefaultsForSelectedLanguage,
                      ),
                    if (canClearProjectOverrides)
                      ActionChip(
                        label: Text(
                          isZh ? '清空项目级覆盖' : 'Clear Project Overrides',
                        ),
                        onPressed: _clearProjectOverridesForSelectedLanguage,
                      ),
                  ],
                ),
              ],
              if (recentProjectRoots.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  isZh ? '最近项目' : 'Recent Projects',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
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
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  _applyProjectRootSelection(path);
                                },
                                onDoubleTap: () {
                                  _applyProjectRootSelection(path);
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
                                      const SizedBox(width: 10),
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
          label: isZh ? '取消' : 'Cancel',
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _pathController,
          builder: (context, value, _) {
            final normalizedPath = OpenHandPaths.normalizeOptionalPath(
              value.text,
            );
            final hasValue =
                normalizedPath.isNotEmpty &&
                Directory(normalizedPath).existsSync();
            return OpenHandDialogActionButton.primary(
              onPressed: hasValue ? _submit : null,
              label: isZh ? '确定' : 'Confirm',
            );
          },
        ),
      ],
    );
  }
}

class _ProgrammingExpertDirectoryField extends StatelessWidget {
  const _ProgrammingExpertDirectoryField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.helperText,
    required this.browseTooltip,
    required this.onBrowse,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final String helperText;
  final String browseTooltip;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hintText,
              helperText: helperText,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: browseTooltip,
          child: SizedBox(
            height: 52,
            width: 44,
            child: OutlinedButton(
              onPressed: onBrowse,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.6),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
              child: const Icon(Icons.folder_open_rounded, size: 18),
            ),
          ),
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
        const SizedBox(height: 6),
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
