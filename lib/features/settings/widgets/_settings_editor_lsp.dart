part of 'settings_view.dart';

const List<({String id, String labelZh, String labelEn})>
_editorLspLanguageOptions = [
  (id: 'dart', labelZh: 'Dart / Flutter', labelEn: 'Dart / Flutter'),
  (id: 'python', labelZh: 'Python', labelEn: 'Python'),
  (id: 'javascript', labelZh: 'JavaScript', labelEn: 'JavaScript'),
  (id: 'typescript', labelZh: 'TypeScript', labelEn: 'TypeScript'),
  (id: 'go', labelZh: 'Go', labelEn: 'Go'),
  (id: 'rust', labelZh: 'Rust', labelEn: 'Rust'),
  (id: 'java', labelZh: 'Java', labelEn: 'Java'),
  (id: 'kotlin', labelZh: 'Kotlin', labelEn: 'Kotlin'),
  (id: 'c', labelZh: 'C', labelEn: 'C'),
  (id: 'cpp', labelZh: 'C++', labelEn: 'C++'),
  (id: 'swift', labelZh: 'Swift', labelEn: 'Swift'),
  (id: 'csharp', labelZh: 'C#', labelEn: 'C#'),
  (id: 'fsharp', labelZh: 'F#', labelEn: 'F#'),
  (id: 'php', labelZh: 'PHP', labelEn: 'PHP'),
  (id: 'ruby', labelZh: 'Ruby', labelEn: 'Ruby'),
  (id: 'lua', labelZh: 'Lua', labelEn: 'Lua'),
  (id: 'elixir', labelZh: 'Elixir', labelEn: 'Elixir'),
  (id: 'erlang', labelZh: 'Erlang', labelEn: 'Erlang'),
  (id: 'haskell', labelZh: 'Haskell', labelEn: 'Haskell'),
  (id: 'scala', labelZh: 'Scala', labelEn: 'Scala'),
  (id: 'clojure', labelZh: 'Clojure', labelEn: 'Clojure'),
  (id: 'ocaml', labelZh: 'OCaml', labelEn: 'OCaml'),
  (id: 'zig', labelZh: 'Zig', labelEn: 'Zig'),
  (id: 'gleam', labelZh: 'Gleam', labelEn: 'Gleam'),
  (id: 'julia', labelZh: 'Julia', labelEn: 'Julia'),
  (id: 'r', labelZh: 'R', labelEn: 'R'),
  (id: 'perl', labelZh: 'Perl', labelEn: 'Perl'),
  (id: 'vue', labelZh: 'Vue', labelEn: 'Vue'),
  (id: 'svelte', labelZh: 'Svelte', labelEn: 'Svelte'),
  (id: 'astro', labelZh: 'Astro', labelEn: 'Astro'),
  (id: 'shell', labelZh: 'Shell / Bash', labelEn: 'Shell / Bash'),
  (id: 'terraform', labelZh: 'Terraform / HCL', labelEn: 'Terraform / HCL'),
  (id: 'typst', labelZh: 'Typst', labelEn: 'Typst'),
  (id: 'yaml', labelZh: 'YAML', labelEn: 'YAML'),
  (id: 'json', labelZh: 'JSON', labelEn: 'JSON'),
  (id: 'html', labelZh: 'HTML', labelEn: 'HTML'),
  (id: 'css', labelZh: 'CSS', labelEn: 'CSS'),
  (id: 'graphql', labelZh: 'GraphQL', labelEn: 'GraphQL'),
  (id: 'prisma', labelZh: 'Prisma', labelEn: 'Prisma'),
  (id: 'sql', labelZh: 'SQL', labelEn: 'SQL'),
  (id: 'toml', labelZh: 'TOML', labelEn: 'TOML'),
  (id: 'dockerfile', labelZh: 'Dockerfile', labelEn: 'Dockerfile'),
  (id: 'markdown', labelZh: 'Markdown', labelEn: 'Markdown'),
];

String _localizedText(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  final languageCode = Localizations.localeOf(context).languageCode;
  return languageCode.startsWith('zh') ? zh : en;
}

String _editorLspLanguageLabel(BuildContext context, String language) {
  final normalized = normalizeAiLspLanguage(language);
  for (final option in _editorLspLanguageOptions) {
    if (option.id == normalized) {
      return _localizedText(context, zh: option.labelZh, en: option.labelEn);
    }
  }
  return normalized.toUpperCase();
}

String _editorIndentSpacesLabel(BuildContext context, int spaces) {
  return _localizedText(
    context,
    zh: '$spaces 个空格',
    en: spaces == 1 ? '1 space' : '$spaces spaces',
  );
}

enum _EditorLspConfigAction { save, install, reset, uninstall }

class _EditorLspConfigDialogResult {
  const _EditorLspConfigDialogResult({
    required this.action,
    required this.backend,
    required this.settings,
  });

  final _EditorLspConfigAction action;
  final AiLspBackendDescriptor backend;
  final AiLspLanguageSettings settings;
}

extension on _SettingsViewState {
  Widget _buildEditorSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final supportedLanguages = _editorLspLanguageOptions
        .where((option) => aiLspBackendsForLanguage(option.id).isNotEmpty)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Word Wrap Toggle
        _SettingsSubsectionCard(
          title: _localizedText(context, zh: '文本布局', en: 'Text Layout'),
          description: _localizedText(
            context,
            zh: '控制编辑器中代码文本的布局方式，例如是否自动换行。',
            en: 'Controls how code text is laid out in the editor, such as word wrapping.',
          ),
          child: _ResponsiveSettingRow(
            title: _localizedText(context, zh: '自动换行', en: 'Word Wrap'),
            subtitle: _localizedText(
              context,
              zh: '启用时，超出编辑器宽度的代码行将自动折行显示；禁用时，需要水平滚动查看长代码行。',
              en: 'When enabled, lines exceeding editor width wrap automatically; when disabled, horizontal scrolling is needed for long lines.',
            ),
            control: Switch(
              value: settingsController.editorWordWrap,
              onChanged: (value) async {
                await settingsController.updateEditorWordWrap(value);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSubsectionCard(
          title: _localizedText(context, zh: '缩进', en: 'Indentation'),
          description: _localizedText(
            context,
            zh: '控制编辑器在按下 Tab 时使用的空格数量。默认是 4 个空格；Shift+Tab 会按同样的宽度反向减少缩进。',
            en: 'Controls how many spaces the editor uses when Tab is pressed. The default is 4 spaces; Shift+Tab removes indentation by the same width.',
          ),
          child: _ResponsiveSettingRow(
            title: _localizedText(context, zh: 'Tab 等效空格数', en: 'Tab Size'),
            subtitle: _localizedText(
              context,
              zh: '代码编辑器会把 Tab 转换为空格，并按这个宽度进行整行缩进或反向缩进。',
              en: 'The code editor converts Tab into spaces and uses this width for both indentation and outdent operations.',
            ),
            control: DropdownButton<int>(
              value: settingsController.editorIndentSpaces,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(12),
              items: editorIndentSpaceOptions
                  .map(
                    (spaces) => DropdownMenuItem<int>(
                      value: spaces,
                      child: Text(_editorIndentSpacesLabel(context, spaces)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) async {
                if (value != null) {
                  await settingsController.updateEditorIndentSpaces(value);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Code Theme
        _SettingsSubsectionCard(
          title: _localizedText(context, zh: '代码主题', en: 'Code Theme'),
          description: _localizedText(
            context,
            zh: '选择编辑器中代码的配色方案。',
            en: 'Choose a color scheme for code in the editor.',
          ),
          child: _ResponsiveSettingRow(
            title: _localizedText(context, zh: '配色方案', en: 'Color Scheme'),
            subtitle: _localizedText(
              context,
              zh: '切换代码编辑器的语法高亮配色主题。',
              en: 'Switch the syntax highlighting color theme of the code editor.',
            ),
            control: DropdownButton<EditorCodeTheme>(
              value: settingsController.editorCodeTheme,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(12),
              items: EditorCodeTheme.values
                  .map((theme) {
                    final languageCode = Localizations.localeOf(
                      context,
                    ).languageCode;
                    final darkSurface =
                        Theme.of(context).brightness == Brightness.dark;
                    final label = languageCode.startsWith('zh')
                        ? theme.labelZh(darkSurface)
                        : theme.labelEn(darkSurface);
                    return DropdownMenuItem<EditorCodeTheme>(
                      value: theme,
                      child: Text(label),
                    );
                  })
                  .toList(growable: false),
              onChanged: (value) async {
                if (value != null) {
                  await settingsController.updateEditorCodeTheme(value);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildEditorShortcutBindingsSection(context, settingsController),
        const SizedBox(height: 16),
        // Language Server Mappings
        _SettingsSubsectionCard(
          title: _localizedText(
            context,
            zh: '语言服务器映射',
            en: 'Language Server Mappings',
          ),
          description: _localizedText(
            context,
            zh: '为每种语言指定首选 LSP、SDK 目录、LSP 根路径以及下载入口。列表高度已限制，点击条目会以弹窗方式配置。',
            en: 'Choose a preferred LSP, SDK directory, LSP root path, and install entry for each language. The list is height-limited and each row opens a configuration dialog.',
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: PrimaryScrollController.none(
              child: OpenHandSafeScrollbar(
                controller: _editorLspListScrollController,
                thumbVisibility: supportedLanguages.length > 6,
                child: ListView.separated(
                  controller: _editorLspListScrollController,
                  primary: false,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: supportedLanguages.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _buildEditorLspLanguageRow(
                      context,
                      settingsController,
                      supportedLanguages[index].id,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditorShortcutBindingsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final bindings = settingsController.editorShortcutBindings;
    const actions = EditorShortcutAction.values;
    return _SettingsSubsectionCard(
      title: _localizedText(context, zh: '编辑器快捷键', en: 'Editor Shortcuts'),
      description: _localizedText(
        context,
        zh: '这些绑定仅在代码编辑器获得焦点时生效，用于补全、签名提示、导航和常见符号操作。再次按下同一个面板类快捷键会关闭对应工具面板。',
        en: 'These bindings apply only while the code editor is focused. They control completion, signature help, navigation, and common symbol actions. Pressing the same panel shortcut again closes the corresponding tool panel.',
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: PrimaryScrollController.none(
          child: OpenHandSafeScrollbar(
            controller: _editorShortcutListScrollController,
            thumbVisibility: true,
            child: ListView.separated(
              controller: _editorShortcutListScrollController,
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: actions.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final action = actions[index];
                return _ShortcutBindingTile(
                  actionStorageKey: editorShortcutActionStorageKey(action),
                  title: _editorShortcutActionTitle(context, action),
                  subtitle: _editorShortcutActionSubtitle(context, action),
                  value: formatShortcutLabel(bindings[action] ?? const <int>[]),
                  onRecord: () =>
                      _showEditorShortcutRecorderDialog(context, action),
                  onReset: () async {
                    final saved = await settingsController
                        .resetEditorShortcutBinding(action);
                    if (!context.mounted || saved) {
                      return;
                    }
                    _showPersistenceFailureSnackBar(context);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorLspLanguageRow(
    BuildContext context,
    SettingsController settingsController,
    String language,
  ) {
    final settings = settingsController.editorLspSettingsForLanguage(language);
    final effectiveBackend = settings.backendId.trim().isNotEmpty
        ? aiLspBackendById(settings.backendId.trim())
        : aiLspBackendsForLanguage(language).firstOrNull;
    final normalizedRoot = OpenHandPaths.normalizeOptionalPath(
      settings.rootPath,
    );
    final managedInstallManifest = normalizedRoot.isEmpty
        ? null
        : AiLspManagedInstallService.readManifest(normalizedRoot);

    return _EditorLspLanguageRow(
      key: ValueKey<String>('editor-lsp-row-$language'),
      language: language,
      languageLabel: _editorLspLanguageLabel(context, language),
      summary: _editorLspSummary(context, settingsController, language),
      hasManagedInstallManifest: managedInstallManifest != null,
      supportsManagedInstall:
          effectiveBackend != null &&
          AiLspManagedInstallService.supportsManagedInstall(effectiveBackend),
      onTap: () => _openEditorLspConfigDialog(context, language),
    );
  }

  String _editorLspSummary(
    BuildContext context,
    SettingsController settingsController,
    String language,
  ) {
    final settings = settingsController.editorLspSettingsForLanguage(language);
    final backend = settings.backendId.trim().isNotEmpty
        ? aiLspBackendById(settings.backendId.trim())
        : aiLspBackendsForLanguage(language).firstOrNull;
    final normalizedRoot = OpenHandPaths.normalizeOptionalPath(
      settings.rootPath,
    );
    final managedInstallManifest = normalizedRoot.isEmpty
        ? null
        : AiLspManagedInstallService.readManifest(normalizedRoot);

    if (settings.isEmpty) {
      return _localizedText(
        context,
        zh: '当前使用默认自动探测、系统 SDK 与 PATH 解析。',
        en: 'Currently using default auto-detection, system SDKs, and PATH resolution.',
      );
    }

    final segments = <String>[
      backend?.displayName ??
          _localizedText(context, zh: '未指定后端', en: 'No backend'),
      if (settings.sdkPath.trim().isNotEmpty)
        _localizedText(
          context,
          zh: 'SDK：${OpenHandPaths.shortenHomePath(settings.sdkPath)}',
          en: 'SDK: ${OpenHandPaths.shortenHomePath(settings.sdkPath)}',
        ),
      if (settings.rootPath.trim().isNotEmpty)
        _localizedText(
          context,
          zh: 'LSP：${OpenHandPaths.shortenHomePath(settings.rootPath)}',
          en: 'LSP: ${OpenHandPaths.shortenHomePath(settings.rootPath)}',
        ),
      if (settings.version.trim().isNotEmpty) 'v${settings.version.trim()}',
      if (managedInstallManifest != null)
        _localizedText(context, zh: 'OpenHand 托管安装', en: 'Managed by OpenHand'),
    ];
    return segments.join('  •  ');
  }

  Future<void> _openEditorLspConfigDialog(
    BuildContext context,
    String language,
  ) async {
    final settingsController = context.read<SettingsController>();
    final result = await showAnimatedDialog<_EditorLspConfigDialogResult>(
      context: context,
      builder: (dialogContext) => _EditorLspConfigDialog(
        language: language,
        initialSettings: settingsController.editorLspSettingsForLanguage(
          language,
        ),
        defaultInstallRoot: settingsController.defaultEditorLspRootPath(
          language,
        ),
      ),
    );
    if (!context.mounted || result == null) {
      return;
    }

    switch (result.action) {
      case _EditorLspConfigAction.reset:
        await _resetEditorLspSettings(context, language);
        break;
      case _EditorLspConfigAction.uninstall:
        await _uninstallEditorLsp(
          context,
          language,
          targetRoot: result.settings.rootPath,
        );
        break;
      case _EditorLspConfigAction.save:
        await _saveEditorLspConfig(context, language, result.settings);
        break;
      case _EditorLspConfigAction.install:
        await _saveEditorLspConfig(
          context,
          language,
          result.settings,
          installBackend: result.backend,
          startInstall: true,
        );
        break;
    }
  }

  Future<void> _saveEditorLspConfig(
    BuildContext context,
    String language,
    AiLspLanguageSettings settings, {
    AiLspBackendDescriptor? installBackend,
    bool startInstall = false,
  }) async {
    final settingsController = context.read<SettingsController>();

    if (startInstall) {
      if (installBackend == null) {
        _showSnackBar(
          context,
          _localizedText(
            context,
            zh: '当前后端信息无效，无法开始安装。',
            en: 'The selected backend is invalid, so installation cannot start.',
          ),
          kind: OpenHandSnackKind.error,
        );
        return;
      }
      final validationMessage = AiLspManagedInstallService.validateInstallRoot(
        language: language,
        backend: installBackend,
        settings: settings,
      );
      if (validationMessage != null) {
        _showSnackBar(
          context,
          _localizedText(
            context,
            zh: '无法开始安装：$validationMessage',
            en: validationMessage,
          ),
          kind: OpenHandSnackKind.error,
        );
        return;
      }
    }

    final saved = await settingsController.updateEditorLspSettings(
      language,
      settings,
    );
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }

    if (!startInstall) {
      _showSnackBar(
        context,
        _localizedText(
          context,
          zh: '${_editorLspLanguageLabel(context, language)} 的编辑器工具链配置已保存。',
          en: 'Saved the editor toolchain settings for ${_editorLspLanguageLabel(context, language)}.',
        ),
        kind: OpenHandSnackKind.success,
      );
      return;
    }

    if (installBackend == null ||
        !AiLspManagedInstallService.supportsManagedInstall(installBackend)) {
      _showSnackBar(
        context,
        _localizedText(
          context,
          zh: '当前后端在本平台下暂不支持托管安装。',
          en: 'This backend does not support managed installation on the current platform yet.',
        ),
      );
      return;
    }

    final installPlan = AiLspManagedInstallService.buildInstallPlan(
      installBackend,
      settings,
    );
    if (installPlan == null) {
      _showSnackBar(
        context,
        _localizedText(
          context,
          zh: '当前 LSP 暂不支持自动安装。',
          en: 'Automatic installation is not available for this LSP yet.',
        ),
      );
      return;
    }

    final installed = await showAnimatedDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _EditorLspInstallRunnerDialog(
        language: language,
        backend: installBackend,
        plan: installPlan,
      ),
    );
    if (!context.mounted) {
      return;
    }
    if (installed == true) {
      try {
        await AiLspManagedInstallService.writeManifest(
          rootPath: installPlan.installRootPath,
          language: language,
          backend: installBackend,
          version: settings.normalizedVersion,
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        _showSnackBar(
          context,
          _localizedText(
            context,
            zh: 'LSP 已安装，但写入卸载元数据失败：$error',
            en: 'Installed the LSP, but failed to record cleanup metadata: $error',
          ),
          kind: OpenHandSnackKind.error,
        );
        return;
      }
      if (!context.mounted) {
        return;
      }
      _showSnackBar(
        context,
        _localizedText(
          context,
          zh: '${installBackend.displayName} 已安装到 ${OpenHandPaths.shortenHomePath(installPlan.installRootPath)}。',
          en: 'Installed ${installBackend.displayName} into ${OpenHandPaths.shortenHomePath(installPlan.installRootPath)}.',
        ),
        kind: OpenHandSnackKind.success,
      );
      return;
    }

    _showSnackBar(
      context,
      _localizedText(
        context,
        zh: 'LSP 安装未完成，请检查日志输出。',
        en: 'The LSP installation did not finish successfully. Check the log output.',
      ),
      kind: OpenHandSnackKind.error,
    );
  }

  Future<void> _resetEditorLspSettings(
    BuildContext context,
    String language,
  ) async {
    final saved = await context
        .read<SettingsController>()
        .updateEditorLspSettings(language, const AiLspLanguageSettings());
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }

    _showSnackBar(
      context,
      _localizedText(
        context,
        zh: '${_editorLspLanguageLabel(context, language)} 已恢复为自动探测。',
        en: '${_editorLspLanguageLabel(context, language)} has been reset to auto detection.',
      ),
      kind: OpenHandSnackKind.success,
    );
  }

  Future<void> _uninstallEditorLsp(
    BuildContext context,
    String language, {
    String? targetRoot,
  }) async {
    final settingsController = context.read<SettingsController>();
    final current = settingsController.editorLspSettingsForLanguage(language);
    final normalizedRoot = OpenHandPaths.normalizeOptionalPath(
      targetRoot ?? current.rootPath,
    );
    final manifest = AiLspManagedInstallService.readManifest(normalizedRoot);
    if (manifest == null) {
      _showSnackBar(
        context,
        _localizedText(
          context,
          zh: '当前路径不是 OpenHand 托管安装目录，无法执行自动清理。',
          en: 'The current path is not an OpenHand-managed install root, so automatic cleanup is unavailable.',
        ),
        kind: OpenHandSnackKind.error,
      );
      return;
    }

    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowAlignment: OverflowBarAlignment.center,
        title: Text(
          _localizedText(
            dialogContext,
            zh: '卸载 ${manifest.backendId}',
            en: 'Uninstall ${manifest.backendId}',
          ),
        ),
        content: Text(
          _localizedText(
            dialogContext,
            zh: '将删除 ${OpenHandPaths.shortenHomePath(normalizedRoot)} 下的托管安装文件。若当前语言正在使用该路径，还会同步清空已保存的 LSP 路径与版本。这个操作不可撤销。',
            en: 'This deletes the managed install under ${OpenHandPaths.shortenHomePath(normalizedRoot)}. If the current language is using that folder, the saved LSP path and version are cleared as well. This cannot be undone.',
          ),
        ),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: AppLocalizations.of(dialogContext)!.commonCancel,
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: _localizedText(
              dialogContext,
              zh: '确认卸载',
              en: 'Confirm Uninstall',
            ),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) {
      return;
    }

    try {
      await AiLspManagedInstallService.deleteManagedInstall(normalizedRoot);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(
        context,
        _localizedText(
          context,
          zh: '卸载失败：$error',
          en: 'Uninstall failed: $error',
        ),
        kind: OpenHandSnackKind.error,
      );
      return;
    }

    final currentRoot = OpenHandPaths.normalizeOptionalPath(current.rootPath);
    if (currentRoot == normalizedRoot) {
      final saved = await settingsController.updateEditorLspSettings(
        language,
        current.copyWith(clearRootPath: true, clearVersion: true),
      );
      if (!context.mounted) {
        return;
      }
      if (!saved) {
        _showPersistenceFailureSnackBar(context);
        return;
      }
    }

    if (!context.mounted) {
      return;
    }

    _showSnackBar(
      context,
      _localizedText(
        context,
        zh: '${_editorLspLanguageLabel(context, language)} 的托管安装已卸载并清理。',
        en: 'Removed the managed install for ${_editorLspLanguageLabel(context, language)}.',
      ),
      kind: OpenHandSnackKind.success,
    );
  }
}

class _EditorLspLanguageRow extends StatefulWidget {
  const _EditorLspLanguageRow({
    super.key,
    required this.language,
    required this.languageLabel,
    required this.summary,
    required this.hasManagedInstallManifest,
    required this.supportsManagedInstall,
    required this.onTap,
  });

  final String language;
  final String languageLabel;
  final String summary;
  final bool hasManagedInstallManifest;
  final bool supportsManagedInstall;
  final VoidCallback onTap;

  @override
  State<_EditorLspLanguageRow> createState() => _EditorLspLanguageRowState();
}

class _EditorLspLanguageRowState extends State<_EditorLspLanguageRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) {
        if (_hovered) return;
        _hovered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      onExit: (_) {
        if (!_hovered) return;
        _hovered = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      child: MicroPressFeedback(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            child: Ink(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.terminal_rounded,
                        size: 20,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.languageLabel,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (widget.hasManagedInstallManifest)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _localizedText(
                                      context,
                                      zh: '托管安装',
                                      en: 'Managed',
                                    ),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.summary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                          if (widget.supportsManagedInstall) ...[
                            const SizedBox(height: 8),
                            Text(
                              _localizedText(
                                context,
                                zh: '支持托管下载，路径可在弹窗中保存、重置或卸载。',
                                en: 'Managed download is available. Save, reset, or uninstall from the dialog.',
                              ),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedSlide(
                      offset: Offset(_hovered && !reduceMotion ? 0.18 : 0, 0),
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorLspDirectoryField extends StatelessWidget {
  const _EditorLspDirectoryField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.browseTooltip,
    required this.onBrowse,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String browseTooltip;
  final String? helperText;
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
              hintText: hint,
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

class _EditorLspInlineNotice extends StatelessWidget {
  const _EditorLspInlineNotice({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectedSdkVersion {
  const _DetectedSdkVersion({required this.version, required this.display});

  final String version;
  final String display;
}

String? _resolveSdkExecutable(
  String sdkPath,
  List<List<String>> candidateRelativePaths,
) {
  for (final segments in candidateRelativePaths) {
    if (segments.isEmpty) {
      continue;
    }
    final executableBaseName = segments.last;
    final parentSegments = segments.take(segments.length - 1).toList();
    final executableNames =
        !Platform.isWindows || executableBaseName.contains('.')
        ? <String>[executableBaseName]
        : <String>[
            executableBaseName,
            '$executableBaseName.exe',
            '$executableBaseName.cmd',
            '$executableBaseName.bat',
          ];
    for (final executableName in executableNames) {
      final candidatePath = p.normalize(
        p.joinAll(<String>[sdkPath, ...parentSegments, executableName]),
      );
      if (File(candidatePath).existsSync()) {
        return candidatePath;
      }
    }
  }
  return null;
}

Future<_DetectedSdkVersion?> _detectCommandSdkVersion({
  required String sdkPath,
  required List<List<String>> candidateRelativePaths,
  required List<String> arguments,
  required RegExp versionPattern,
  required String Function(String version, String output) displayBuilder,
}) async {
  final executablePath = _resolveSdkExecutable(sdkPath, candidateRelativePaths);
  if (executablePath == null) {
    return null;
  }
  try {
    final result = await runProcessWithTimeout(
      executablePath,
      arguments,
      tag: 'settings_editor_lsp',
    );
    if (result == null) {
      return null;
    }
    final output = '${result.stdout}\n${result.stderr}'.trim();
    if (output.isEmpty) {
      return null;
    }
    final match = versionPattern.firstMatch(output);
    if (match == null) {
      return null;
    }
    final version =
        (match.groupCount >= 1 ? match.group(1) : match.group(0))?.trim() ?? '';
    if (version.isEmpty) {
      return null;
    }
    return _DetectedSdkVersion(
      version: version,
      display: displayBuilder(version, output),
    );
  } catch (_) {
    return null;
  }
}

Future<_DetectedSdkVersion?> _detectDartSdkVersion(String sdkPath) async {
  final flutterExecutable = _resolveSdkExecutable(sdkPath, const <List<String>>[
    <String>['bin', 'flutter'],
    <String>['flutter'],
  ]);
  if (flutterExecutable != null) {
    try {
      final result = await runProcessWithTimeout(
        flutterExecutable,
        const <String>['--version', '--machine'],
        tag: 'settings_editor_lsp',
      );
      if (result != null) {
        final rawOutput = '${result.stdout}${result.stderr}'.trim();
        if (result.exitCode == 0 && rawOutput.isNotEmpty) {
          final decoded = jsonDecode(rawOutput);
          if (decoded is Map<String, Object?>) {
            final frameworkVersion = '${decoded['frameworkVersion'] ?? ''}'
                .trim();
            if (frameworkVersion.isNotEmpty) {
              return _DetectedSdkVersion(
                version: frameworkVersion,
                display: 'Flutter $frameworkVersion',
              );
            }
          }
        }
      }
    } catch (error, stack) {
      silentLog(
        'settings_editor_lsp',
        'detect Flutter SDK version',
        error,
        stack,
      );
    }
  }
  return _detectCommandSdkVersion(
    sdkPath: sdkPath,
    candidateRelativePaths: const <List<String>>[
      <String>['bin', 'dart'],
      <String>['dart'],
    ],
    arguments: const <String>['--version'],
    versionPattern: RegExp(r'Dart SDK version:\s*([^\s]+)'),
    displayBuilder: (version, _) => 'Dart $version',
  );
}

Future<_DetectedSdkVersion?> _detectNativeToolchainVersion(
  String sdkPath,
) async {
  final clangVersion = await _detectCommandSdkVersion(
    sdkPath: sdkPath,
    candidateRelativePaths: const <List<String>>[
      <String>['bin', 'clang'],
      <String>['clang'],
    ],
    arguments: const <String>['--version'],
    versionPattern: RegExp(r'clang version\s+([^\s]+)', caseSensitive: false),
    displayBuilder: (version, _) => 'Clang $version',
  );
  if (clangVersion != null) {
    return clangVersion;
  }
  return _detectCommandSdkVersion(
    sdkPath: sdkPath,
    candidateRelativePaths: const <List<String>>[
      <String>['bin', 'gcc'],
      <String>['gcc'],
      <String>['bin', 'g++'],
      <String>['g++'],
    ],
    arguments: const <String>['--version'],
    versionPattern: RegExp(
      r'(?:gcc|g\+\+)[^\n]*\s([0-9][^\s]*)',
      caseSensitive: false,
    ),
    displayBuilder: (version, output) {
      final lower = output.toLowerCase();
      final label = lower.contains('g++') ? 'G++' : 'GCC';
      return '$label $version';
    },
  );
}

Future<_DetectedSdkVersion?> _detectSdkVersionForLanguage({
  required String language,
  required String sdkPath,
}) async {
  final normalizedLanguage = normalizeAiLspLanguage(language);
  final normalizedSdkPath = OpenHandPaths.normalizeOptionalPath(sdkPath);
  if (normalizedSdkPath.isEmpty || !Directory(normalizedSdkPath).existsSync()) {
    return null;
  }

  switch (normalizedLanguage) {
    case 'dart':
      return _detectDartSdkVersion(normalizedSdkPath);
    case 'python':
      return _detectCommandSdkVersion(
        sdkPath: normalizedSdkPath,
        candidateRelativePaths: const <List<String>>[
          <String>['bin', 'python3'],
          <String>['bin', 'python'],
          <String>['python3'],
          <String>['python'],
        ],
        arguments: const <String>['--version'],
        versionPattern: RegExp(r'Python\s+([^\s]+)', caseSensitive: false),
        displayBuilder: (version, _) => 'Python $version',
      );
    case 'javascript':
    case 'typescript':
      return _detectCommandSdkVersion(
        sdkPath: normalizedSdkPath,
        candidateRelativePaths: const <List<String>>[
          <String>['bin', 'node'],
          <String>['node'],
        ],
        arguments: const <String>['--version'],
        versionPattern: RegExp(r'v?([0-9][^\s]*)'),
        displayBuilder: (version, _) => 'Node $version',
      );
    case 'go':
      return _detectCommandSdkVersion(
        sdkPath: normalizedSdkPath,
        candidateRelativePaths: const <List<String>>[
          <String>['bin', 'go'],
          <String>['go'],
        ],
        arguments: const <String>['version'],
        versionPattern: RegExp(r'go version go([^\s]+)', caseSensitive: false),
        displayBuilder: (version, _) => 'Go $version',
      );
    case 'rust':
      return _detectCommandSdkVersion(
        sdkPath: normalizedSdkPath,
        candidateRelativePaths: const <List<String>>[
          <String>['bin', 'rustc'],
          <String>['rustc'],
        ],
        arguments: const <String>['--version'],
        versionPattern: RegExp(r'rustc\s+([^\s]+)', caseSensitive: false),
        displayBuilder: (version, _) => 'Rust $version',
      );
    case 'java':
      return _detectCommandSdkVersion(
        sdkPath: normalizedSdkPath,
        candidateRelativePaths: const <List<String>>[
          <String>['bin', 'java'],
          <String>['java'],
        ],
        arguments: const <String>['--version'],
        versionPattern: RegExp(
          r'(?:openjdk|java)\s+(?:version\s+)?"?([^\s\"]+)',
          caseSensitive: false,
        ),
        displayBuilder: (version, _) => 'Java $version',
      );
    case 'kotlin':
      return _detectCommandSdkVersion(
        sdkPath: normalizedSdkPath,
        candidateRelativePaths: const <List<String>>[
          <String>['bin', 'kotlin'],
          <String>['bin', 'kotlinc'],
          <String>['kotlin'],
          <String>['kotlinc'],
        ],
        arguments: const <String>['-version'],
        versionPattern: RegExp(
          r'(?:Kotlin version|kotlinc(?:-jvm)?)(?:\s+version)?\s+([^\s]+)',
          caseSensitive: false,
        ),
        displayBuilder: (version, _) => 'Kotlin $version',
      );
    case 'c':
    case 'cpp':
      return _detectNativeToolchainVersion(normalizedSdkPath);
    case 'swift':
      return _detectCommandSdkVersion(
        sdkPath: normalizedSdkPath,
        candidateRelativePaths: const <List<String>>[
          <String>['usr', 'bin', 'swift'],
          <String>['bin', 'swift'],
          <String>['swift'],
        ],
        arguments: const <String>['--version'],
        versionPattern: RegExp(
          r'Swift version\s+([^\s]+)',
          caseSensitive: false,
        ),
        displayBuilder: (version, _) => 'Swift $version',
      );
    case 'csharp':
      return _detectCommandSdkVersion(
        sdkPath: normalizedSdkPath,
        candidateRelativePaths: const <List<String>>[
          <String>['dotnet'],
          <String>['bin', 'dotnet'],
        ],
        arguments: const <String>['--version'],
        versionPattern: RegExp(r'^([0-9][^\s]*)', multiLine: true),
        displayBuilder: (version, _) => 'dotnet $version',
      );
    case 'php':
      return _detectCommandSdkVersion(
        sdkPath: normalizedSdkPath,
        candidateRelativePaths: const <List<String>>[
          <String>['bin', 'php'],
          <String>['php'],
        ],
        arguments: const <String>['-v'],
        versionPattern: RegExp(r'PHP\s+([^\s]+)', caseSensitive: false),
        displayBuilder: (version, _) => 'PHP $version',
      );
    case 'ruby':
      return _detectCommandSdkVersion(
        sdkPath: normalizedSdkPath,
        candidateRelativePaths: const <List<String>>[
          <String>['bin', 'ruby'],
          <String>['ruby'],
        ],
        arguments: const <String>['-v'],
        versionPattern: RegExp(r'ruby\s+([^\s]+)', caseSensitive: false),
        displayBuilder: (version, _) => 'Ruby $version',
      );
    default:
      return null;
  }
}

class _EditorLspConfigDialog extends StatefulWidget {
  const _EditorLspConfigDialog({
    required this.language,
    required this.initialSettings,
    required this.defaultInstallRoot,
  });

  final String language;
  final AiLspLanguageSettings initialSettings;
  final String defaultInstallRoot;

  @override
  State<_EditorLspConfigDialog> createState() => _EditorLspConfigDialogState();
}

class _EditorLspConfigDialogState extends State<_EditorLspConfigDialog> {
  late final TextEditingController _versionController;
  late final TextEditingController _pathController;
  late final TextEditingController _sdkController;
  late String _selectedBackendId;
  Timer? _sdkVersionDetectionTimer;
  bool _sdkVersionDetecting = false;
  bool _sdkVersionDetectionFailed = false;
  bool _sdkVersionAppliedToLspVersion = false;
  bool _suppressVersionControllerListener = false;
  String? _lastAutoAppliedLspVersion;
  _DetectedSdkVersion? _detectedSdkVersion;

  @override
  void initState() {
    super.initState();
    final candidates = aiLspBackendsForLanguage(widget.language);
    _selectedBackendId = widget.initialSettings.backendId.trim().isNotEmpty
        ? widget.initialSettings.backendId.trim()
        : candidates.first.id;
    _versionController = TextEditingController(
      text: widget.initialSettings.version.trim(),
    );
    _pathController = TextEditingController(
      text: widget.initialSettings.rootPath.trim(),
    );
    _sdkController = TextEditingController(
      text: widget.initialSettings.sdkPath.trim(),
    );
    _versionController.addListener(_handleControllerChanged);
    _versionController.addListener(_handleVersionControllerChanged);
    _pathController.addListener(_handleControllerChanged);
    _sdkController.addListener(_handleControllerChanged);
    _sdkController.addListener(_handleSdkPathChanged);
    if (_sdkController.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scheduleSdkVersionDetection(immediate: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _sdkVersionDetectionTimer?.cancel();
    _versionController.removeListener(_handleControllerChanged);
    _versionController.removeListener(_handleVersionControllerChanged);
    _pathController.removeListener(_handleControllerChanged);
    _sdkController.removeListener(_handleControllerChanged);
    _sdkController.removeListener(_handleSdkPathChanged);
    _versionController.dispose();
    _pathController.dispose();
    _sdkController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _handleSdkPathChanged() {
    _scheduleSdkVersionDetection();
  }

  void _handleVersionControllerChanged() {
    if (_suppressVersionControllerListener) {
      return;
    }
    final currentVersion = _versionController.text.trim();
    if (_lastAutoAppliedLspVersion != null &&
        currentVersion != _lastAutoAppliedLspVersion) {
      if (!mounted) {
        _lastAutoAppliedLspVersion = null;
        _sdkVersionAppliedToLspVersion = false;
        return;
      }
      setState(() {
        _lastAutoAppliedLspVersion = null;
        _sdkVersionAppliedToLspVersion = false;
      });
    }
  }

  void _setVersionControllerText(String value) {
    _suppressVersionControllerListener = true;
    try {
      _versionController.text = value;
    } finally {
      _suppressVersionControllerListener = false;
    }
  }

  void _clearAutoAppliedLspVersionIfNeeded() {
    if (_lastAutoAppliedLspVersion != null &&
        _versionController.text.trim() == _lastAutoAppliedLspVersion) {
      _setVersionControllerText('');
    }
    _lastAutoAppliedLspVersion = null;
    _sdkVersionAppliedToLspVersion = false;
  }

  bool _canMirrorDetectedSdkVersion(AiLspBackendDescriptor? backend) {
    if (backend == null) {
      return false;
    }
    return backend.id == 'dart-analysis-server' ||
        backend.install.kind == AiLspManagedInstallKind.none;
  }

  bool _maybeMirrorDetectedSdkVersionIntoVersionField({
    required _DetectedSdkVersion detected,
    required AiLspBackendDescriptor? backend,
  }) {
    if (!_canMirrorDetectedSdkVersion(backend)) {
      _clearAutoAppliedLspVersionIfNeeded();
      return false;
    }
    final currentVersion = _versionController.text.trim();
    final canOverwrite =
        currentVersion.isEmpty ||
        (_lastAutoAppliedLspVersion != null &&
            currentVersion == _lastAutoAppliedLspVersion);
    if (!canOverwrite) {
      _lastAutoAppliedLspVersion = null;
      _sdkVersionAppliedToLspVersion = false;
      return false;
    }
    _setVersionControllerText(detected.version);
    _lastAutoAppliedLspVersion = detected.version;
    _sdkVersionAppliedToLspVersion = true;
    return true;
  }

  void _scheduleSdkVersionDetection({bool immediate = false}) {
    _sdkVersionDetectionTimer?.cancel();
    final normalizedSdkPath = OpenHandPaths.normalizeOptionalPath(
      _sdkController.text,
    );
    if (normalizedSdkPath.isEmpty) {
      _clearAutoAppliedLspVersionIfNeeded();
      if (!mounted) {
        return;
      }
      setState(() {
        _sdkVersionDetecting = false;
        _sdkVersionDetectionFailed = false;
        _detectedSdkVersion = null;
      });
      return;
    }
    if (immediate) {
      unawaited(_refreshSdkVersionDetection(normalizedSdkPath));
      return;
    }
    _sdkVersionDetectionTimer = Timer(const Duration(milliseconds: 220), () {
      unawaited(_refreshSdkVersionDetection(normalizedSdkPath));
    });
  }

  Future<void> _refreshSdkVersionDetection(String sdkPath) async {
    final requestPath = OpenHandPaths.normalizeOptionalPath(sdkPath);
    if (requestPath.isEmpty) {
      return;
    }
    if (mounted) {
      setState(() {
        _sdkVersionDetecting = true;
        _sdkVersionDetectionFailed = false;
      });
    }
    final detected = await _detectSdkVersionForLanguage(
      language: widget.language,
      sdkPath: requestPath,
    );
    if (!mounted) {
      return;
    }
    final currentSdkPath = OpenHandPaths.normalizeOptionalPath(
      _sdkController.text,
    );
    if (currentSdkPath != requestPath) {
      return;
    }
    final backend = aiLspBackendById(_selectedBackendId);
    final appliedToVersionField = detected != null
        ? _maybeMirrorDetectedSdkVersionIntoVersionField(
            detected: detected,
            backend: backend,
          )
        : false;
    if (detected == null) {
      _clearAutoAppliedLspVersionIfNeeded();
    }
    setState(() {
      _sdkVersionDetecting = false;
      _sdkVersionDetectionFailed = detected == null;
      _detectedSdkVersion = detected;
      _sdkVersionAppliedToLspVersion =
          detected != null && appliedToVersionField;
    });
  }

  Future<void> _browseLspDirectory() async {
    final selectedPath = await getDirectoryPath(
      initialDirectory: _pathController.text.trim().isEmpty
          ? widget.defaultInstallRoot
          : _pathController.text.trim(),
    );
    if (selectedPath == null || !mounted) {
      return;
    }
    _pathController.text = selectedPath;
  }

  Future<void> _browseSdkDirectory() async {
    final selectedPath = await getDirectoryPath(
      initialDirectory: _sdkController.text.trim().isEmpty
          ? null
          : _sdkController.text.trim(),
    );
    if (selectedPath == null || !mounted) {
      return;
    }
    _sdkController.text = selectedPath;
    _scheduleSdkVersionDetection(immediate: true);
  }

  void _submit(_EditorLspConfigAction action) {
    final backend = aiLspBackendById(_selectedBackendId);
    if (backend == null) {
      return;
    }
    final lspRoot =
        _pathController.text.trim().isEmpty &&
            action == _EditorLspConfigAction.install
        ? widget.defaultInstallRoot
        : _pathController.text.trim();
    Navigator.of(context).pop(
      _EditorLspConfigDialogResult(
        action: action,
        backend: backend,
        settings: AiLspLanguageSettings(
          backendId: _selectedBackendId,
          rootPath: lspRoot,
          sdkPath: _sdkController.text.trim(),
          version: _versionController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final candidates = aiLspBackendsForLanguage(widget.language);
    final backend = aiLspBackendById(_selectedBackendId);
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final supportsManagedInstall =
        backend != null &&
        AiLspManagedInstallService.supportsManagedInstall(backend);
    final normalizedRoot = OpenHandPaths.normalizeOptionalPath(
      _pathController.text,
    );
    final normalizedSdkPath = OpenHandPaths.normalizeOptionalPath(
      _sdkController.text,
    );
    final managedInstallManifest = normalizedRoot.isEmpty
        ? null
        : AiLspManagedInstallService.readManifest(normalizedRoot);
    final effectiveInstallRoot = normalizedRoot.isEmpty
        ? widget.defaultInstallRoot
        : normalizedRoot;
    final draftSettings = AiLspLanguageSettings(
      backendId: _selectedBackendId,
      rootPath: effectiveInstallRoot,
      sdkPath: normalizedSdkPath,
      version: _versionController.text.trim(),
    );
    final installValidationMessage = backend != null && supportsManagedInstall
        ? AiLspManagedInstallService.validateInstallRoot(
            language: widget.language,
            backend: backend,
            settings: draftSettings,
          )
        : null;
    final showDefaultRootShortcut =
        effectiveInstallRoot != widget.defaultInstallRoot ||
        normalizedRoot.isEmpty;
    final showClearRootShortcut = _pathController.text.trim().isNotEmpty;
    final showLatestVersionShortcut = _versionController.text.trim().isNotEmpty;
    final canMirrorDetectedSdkVersion = _canMirrorDetectedSdkVersion(backend);
    String? sdkVersionNoticeText;
    var sdkVersionNoticeColor = colorScheme.onSurfaceVariant;
    var sdkVersionNoticeIcon = Icons.info_outline_rounded;
    if (normalizedSdkPath.isNotEmpty) {
      if (_sdkVersionDetecting) {
        sdkVersionNoticeText = isZh
            ? '正在根据当前 SDK 目录解析工具链版本…'
            : 'Resolving the toolchain version from the current SDK directory…';
        sdkVersionNoticeColor = colorScheme.primary;
        sdkVersionNoticeIcon = Icons.sync_rounded;
      } else if (_detectedSdkVersion != null) {
        sdkVersionNoticeColor = canMirrorDetectedSdkVersion
            ? colorScheme.primary
            : colorScheme.tertiary;
        sdkVersionNoticeIcon = Icons.verified_rounded;
        if (canMirrorDetectedSdkVersion) {
          sdkVersionNoticeText = _sdkVersionAppliedToLspVersion
              ? (isZh
                    ? '已自动解析 SDK 版本：${_detectedSdkVersion!.display}，并同步填入下方的 LSP 版本字段。'
                    : 'Auto-detected SDK version: ${_detectedSdkVersion!.display}, and mirrored it into the LSP version field below.')
              : (isZh
                    ? '已自动解析 SDK 版本：${_detectedSdkVersion!.display}。当前 LSP 版本字段已由你手动接管，因此本次没有自动覆盖。'
                    : 'Auto-detected SDK version: ${_detectedSdkVersion!.display}. The LSP version field is currently under manual control, so it was not overwritten.');
        } else {
          sdkVersionNoticeText = isZh
              ? '已自动解析 SDK 版本：${_detectedSdkVersion!.display}。为避免把托管安装装到错误的 LSP 版本，下方的 LSP 版本字段保持独立。'
              : 'Auto-detected SDK version: ${_detectedSdkVersion!.display}. The LSP version field stays independent so managed installs do not target the wrong release.';
        }
      } else if (_sdkVersionDetectionFailed) {
        sdkVersionNoticeText = isZh
            ? '当前 SDK 目录还没有解析出版本，请确认它指向真实的工具链根目录。'
            : 'The current SDK directory did not resolve to a version yet. Confirm that it points to a real toolchain root.';
        sdkVersionNoticeColor = colorScheme.error;
        sdkVersionNoticeIcon = Icons.info_outline_rounded;
      }
    }

    return AlertDialog(
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowAlignment: OverflowBarAlignment.center,
      title: Text(
        isZh
            ? '配置 ${_editorLspLanguageLabel(context, widget.language)} 的工具链'
            : 'Configure ${_editorLspLanguageLabel(context, widget.language)} Toolchain',
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isZh
                    ? '在这里为当前语言统一管理 LSP 后端、SDK 目录、LSP 根路径与安装方式。保存后立即生效；如后端支持托管安装，也可以直接在当前弹窗中下载并安装。'
                    : 'Manage the LSP backend, SDK directory, LSP root path, and install workflow for this language here. Saving takes effect immediately, and supported backends can be downloaded directly from this dialog.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedBackendId,
                decoration: InputDecoration(
                  labelText: isZh ? 'LSP 后端' : 'LSP Backend',
                ),
                items: candidates
                    .map(
                      (candidate) => DropdownMenuItem<String>(
                        value: candidate.id,
                        child: Text(candidate.displayName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _selectedBackendId = value;
                    _sdkVersionAppliedToLspVersion = _detectedSdkVersion != null
                        ? _maybeMirrorDetectedSdkVersionIntoVersionField(
                            detected: _detectedSdkVersion!,
                            backend: aiLspBackendById(value),
                          )
                        : false;
                  });
                },
              ),
              const SizedBox(height: 14),
              _EditorLspDirectoryField(
                controller: _sdkController,
                label: isZh ? 'SDK 目录' : 'SDK Directory',
                hint: isZh
                    ? '可选，不配置则沿用系统默认'
                    : 'Optional, use the system default when empty',
                helperText: isZh
                    ? '用于记录当前语言 SDK 的位置，并作为项目级配置的默认值。'
                    : 'Records where this language SDK lives and seeds project-level defaults.',
                browseTooltip: isZh ? '浏览文件夹' : 'Browse folder',
                onBrowse: _browseSdkDirectory,
              ),
              if (sdkVersionNoticeText != null) ...[
                const SizedBox(height: 10),
                _EditorLspInlineNotice(
                  icon: sdkVersionNoticeIcon,
                  color: sdkVersionNoticeColor,
                  text: sdkVersionNoticeText,
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _versionController,
                decoration: InputDecoration(
                  labelText: isZh ? 'LSP 版本' : 'LSP Version',
                  hintText: 'latest',
                  helperText: isZh
                      ? '这是 LSP / 安装版本，不一定等同于 SDK 版本；留空或填写 latest 表示使用最新版本。'
                      : 'This is the LSP / install version and may differ from the SDK version. Leave blank or use latest to install the newest release.',
                ),
              ),
              const SizedBox(height: 14),
              _EditorLspDirectoryField(
                controller: _pathController,
                label: isZh ? 'LSP 根路径' : 'LSP Root Path',
                hint: OpenHandPaths.defaultLspDirectoryLabelForLanguage(
                  widget.language,
                ),
                helperText: isZh
                    ? '为空时继续从 PATH 自动探测；点击“下载并安装”时会自动回落到默认安装目录。'
                    : 'Leave empty to keep PATH-based auto detection. Download & Install falls back to the default install root automatically.',
                browseTooltip: isZh ? '浏览文件夹' : 'Browse folder',
                onBrowse: _browseLspDirectory,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (showDefaultRootShortcut)
                    ActionChip(
                      label: Text(
                        isZh
                            ? '使用默认目录 ${OpenHandPaths.defaultLspDirectoryLabelForLanguage(widget.language)}'
                            : 'Use default root ${OpenHandPaths.defaultLspDirectoryLabelForLanguage(widget.language)}',
                      ),
                      onPressed: () {
                        _pathController.text = widget.defaultInstallRoot;
                      },
                    ),
                  if (showClearRootShortcut)
                    ActionChip(
                      label: Text(
                        isZh ? '清空并回退到 PATH' : 'Clear and fall back to PATH',
                      ),
                      onPressed: () {
                        _pathController.clear();
                      },
                    ),
                  if (showLatestVersionShortcut)
                    ActionChip(
                      label: Text(
                        isZh ? '版本设为 latest' : 'Set version to latest',
                      ),
                      onPressed: () {
                        _versionController.clear();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (installValidationMessage != null)
                _EditorLspInlineNotice(
                  icon: Icons.warning_amber_rounded,
                  color: colorScheme.error,
                  text: isZh
                      ? '当前安装目录边界检查未通过：$installValidationMessage\n如仅保存配置而不做托管安装，可以改为清空路径并继续使用 PATH 自动探测。'
                      : 'The current install root did not pass validation: $installValidationMessage\nIf you only want to save the mapping without a managed install, clear the path and keep PATH-based auto detection instead.',
                )
              else
                _EditorLspInlineNotice(
                  icon: supportsManagedInstall
                      ? Icons.download_done_rounded
                      : Icons.info_outline_rounded,
                  color: supportsManagedInstall
                      ? colorScheme.primary
                      : colorScheme.tertiary,
                  text: supportsManagedInstall
                      ? (normalizedRoot.isEmpty
                            ? (isZh
                                  ? '当前未显式填写 LSP 根路径。点击“下载并安装”时会自动使用默认目录 ${OpenHandPaths.defaultLspDirectoryLabelForLanguage(widget.language)}；若只保存配置，则继续沿用 PATH 自动探测。'
                                  : 'No explicit LSP root is set yet. Download & Install will automatically use the default directory ${OpenHandPaths.defaultLspDirectoryLabelForLanguage(widget.language)}, while Save Only continues to rely on PATH auto detection.')
                            : (isZh
                                  ? '当前目录通过了托管安装边界检查。后续下载会写入 ${OpenHandPaths.shortenHomePath(effectiveInstallRoot)}，并保留对应卸载元数据。'
                                  : 'The current directory passed the managed-install safety check. Future downloads will write into ${OpenHandPaths.shortenHomePath(effectiveInstallRoot)} and keep uninstall metadata there.'))
                      : (normalizedRoot.isEmpty
                            ? (isZh
                                  ? '当前不会为这个语言保存自定义 LSP 根路径，编辑器会继续从 PATH 自动解析后端命令。'
                                  : 'No custom LSP root will be stored for this language, so the editor will continue resolving the backend from PATH.')
                            : (isZh
                                  ? '当前仅保存一个现成的本地 LSP 根路径，不会触发托管下载。'
                                  : 'This will only save an existing local LSP root and will not trigger a managed download.')),
                ),
              if (managedInstallManifest != null) ...[
                const SizedBox(height: 14),
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
                        isZh ? '当前目录已检测到托管安装' : 'Managed install detected',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isZh
                            ? '后端：${managedInstallManifest.backendId}\n目录：${OpenHandPaths.shortenHomePath(managedInstallManifest.installRootPath)}\n版本：${managedInstallManifest.version}'
                            : 'Backend: ${managedInstallManifest.backendId}\nRoot: ${OpenHandPaths.shortenHomePath(managedInstallManifest.installRootPath)}\nVersion: ${managedInstallManifest.version}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                supportsManagedInstall
                    ? (isZh
                          ? '当前后端支持托管安装。开始安装前会校验目录安全性，避免覆盖非 OpenHand 管理的现有文件。'
                          : 'This backend supports managed installation. The chosen folder is validated first so the app does not overwrite unrelated existing files.')
                    : (isZh
                          ? '当前后端在当前平台下暂不提供可托管安装包。你仍然可以仅保存一个已经存在的本地 LSP 路径。'
                          : 'This backend does not currently expose a managed install package on the current platform. You can still save an already installed local LSP root.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: AppLocalizations.of(context)!.commonCancel,
        ),
        if (managedInstallManifest != null)
          OpenHandDialogActionButton.secondary(
            onPressed: () => _submit(_EditorLspConfigAction.uninstall),
            label: isZh ? '卸载并清理' : 'Uninstall & Clean',
          ),
        OpenHandDialogActionButton.secondary(
          onPressed: () => _submit(_EditorLspConfigAction.reset),
          label: isZh ? '恢复自动探测' : 'Reset to Auto',
        ),
        OpenHandDialogActionButton.secondary(
          onPressed: () => _submit(_EditorLspConfigAction.save),
          label: isZh ? '仅保存' : 'Save Only',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: supportsManagedInstall
              ? () => _submit(_EditorLspConfigAction.install)
              : null,
          label: isZh ? '下载并安装' : 'Download & Install',
        ),
      ],
    );
  }
}

class _EditorLspInstallRunnerDialog extends StatefulWidget {
  const _EditorLspInstallRunnerDialog({
    required this.language,
    required this.backend,
    required this.plan,
  });

  final String language;
  final AiLspBackendDescriptor backend;
  final AiLspManagedInstallPlan plan;

  @override
  State<_EditorLspInstallRunnerDialog> createState() =>
      _EditorLspInstallRunnerDialogState();
}

class _EditorLspInstallRunnerDialogState
    extends State<_EditorLspInstallRunnerDialog> {
  final List<String> _logLines = <String>[];
  final ScrollController _scrollController = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  Process? _process;
  bool _running = true;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startInstall());
  }

  @override
  void dispose() {
    try {
      _process?.kill();
    } catch (error, stack) {
      silentLog(
        'settings_editor_lsp',
        'kill install process on dispose',
        error,
        stack,
      );
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _appendLine(String value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _logLines.add(value);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollGuard.followToBottom(
        _scrollController,
        animated: true,
        animationDuration: const Duration(milliseconds: 120),
      );
    });
  }

  Future<void> _startInstall() async {
    await Directory(widget.plan.installRootPath).create(recursive: true);
    _appendLine('\$ ${widget.plan.previewCommand}');
    _appendLine('');
    try {
      final process = await _spawnProcess(widget.plan.shellCommand);
      _process = process;
      final stdoutDone = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_appendLine)
          .asFuture<void>();
      final stderrDone = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_appendLine)
          .asFuture<void>();
      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      if (!mounted) {
        return;
      }
      setState(() {
        _running = false;
        _success = exitCode == 0;
      });
      _appendLine('');
      _appendLine(
        _success
            ? '✓ Install completed'
            : '✗ Install failed (exit code: $exitCode)',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _running = false;
        _success = false;
      });
      _appendLine('');
      _appendLine('✗ $error');
    }
  }

  Future<Process> _spawnProcess(String shellCommand) {
    if (Platform.isWindows) {
      return startTrackedProcess('cmd', ['/c', shellCommand], runInShell: true);
    }
    return startTrackedProcess(
      resolveHardnessCliShellExecutable(),
      buildHardnessCliShellArgs(shellCommand),
      environment: const <String, String>{'FORCE_COLOR': '1'},
    );
  }

  Color _terminalLineColor(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('\$')) {
      return const Color(0xFF79C0FF);
    }
    if (trimmed.startsWith('✓')) {
      return const Color(0xFF3FB950);
    }
    if (trimmed.startsWith('✗')) {
      return const Color(0xFFF85149);
    }
    if (trimmed.startsWith('OpenHand:')) {
      return const Color(0xFFD29922);
    }
    return const Color(0xFFC9D1D9);
  }

  Widget _terminalDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    const terminalBackground = Color(0xFF0D1117);
    const terminalChrome = Color(0xFF161B22);
    const terminalBorder = Color(0xFF30363D);
    const terminalMuted = Color(0xFF8B949E);

    return AlertDialog(
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowAlignment: OverflowBarAlignment.center,
      title: Text(
        isZh
            ? '安装 ${widget.backend.displayName}'
            : 'Install ${widget.backend.displayName}',
      ),
      content: SizedBox(
        width: 700,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isZh
                  ? '语言：${_editorLspLanguageLabel(context, widget.language)}\n安装目录：${OpenHandPaths.shortenHomePath(widget.plan.installRootPath)}'
                  : 'Language: ${_editorLspLanguageLabel(context, widget.language)}\nInstall root: ${OpenHandPaths.shortenHomePath(widget.plan.installRootPath)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: terminalBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: terminalBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: const BoxDecoration(
                        color: terminalChrome,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          _terminalDot(const Color(0xFFFF5F57)),
                          const SizedBox(width: 6),
                          _terminalDot(const Color(0xFFFEBB2E)),
                          const SizedBox(width: 6),
                          _terminalDot(const Color(0xFF28C840)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              OpenHandPaths.shortenHomePath(
                                widget.plan.installRootPath,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: terminalMuted,
                                fontFamily: 'SF Mono, Menlo, monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: terminalBorder,
                    ),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _scrollGuard.handleNotification,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _logLines.length,
                          itemBuilder: (context, index) {
                            final line = _logLines[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: SelectableText(
                                line.isEmpty ? ' ' : line,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'SF Mono, Menlo, monospace',
                                  color: _terminalLineColor(line),
                                  height: 1.45,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_running)
          OpenHandDialogActionButton.secondary(
            onPressed: () {
              try {
                _process?.kill();
              } catch (error, stack) {
                silentLog(
                  'settings_editor_lsp',
                  'kill install process on cancel',
                  error,
                  stack,
                );
              }
              Navigator.of(context).pop(false);
            },
            label: isZh ? '取消' : 'Cancel',
          )
        else
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(context).pop(_success),
            label: isZh ? '关闭' : 'Close',
          ),
      ],
    );
  }
}
