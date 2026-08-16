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

String _editorLspLanguageLabel(BuildContext context, String language) {
  final normalized = normalizeAiLspLanguage(language);
  for (final option in _editorLspLanguageOptions) {
    if (option.id == normalized) {
      return openHandLocalizedText(
        context,
        zh: option.labelZh,
        en: option.labelEn,
      );
    }
  }
  return normalized.toUpperCase();
}

String _editorIndentSpacesLabel(BuildContext context, int spaces) {
  return openHandLocalizedText(
    context,
    zh: '$spaces 个空格',
    en: spaces == 1 ? '1 space' : '$spaces spaces',
  );
}

String _editorCodeThemeLabel(
  BuildContext context,
  EditorCodeTheme theme,
  bool darkSurface,
) {
  return switch (theme) {
    EditorCodeTheme.materialYou => openHandLocalizedText(
      context,
      zh: 'Material You（默认）',
      zhHant: 'Material You（預設）',
      en: 'Material You (Default)',
      fr: 'Material You (par défaut)',
      de: 'Material You (Standard)',
      ja: 'Material You（既定）',
    ),
    _ => theme.labelEn(darkSurface),
  };
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
        _SettingsSubsectionCard(
          title: openHandLocalizedText(context, zh: '文本布局', en: 'Text Layout'),
          description: openHandLocalizedText(
            context,
            zh: '控制编辑器中代码文本的布局方式，例如是否自动换行。',
            en: 'Controls how code text is laid out in the editor, such as word wrapping.',
          ),
          child: _ResponsiveSettingRow(
            title: openHandLocalizedText(context, zh: '自动换行', en: 'Word Wrap'),
            subtitle: openHandLocalizedText(
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
        kOpenHandGap16,
        _SettingsSubsectionCard(
          title: openHandLocalizedText(context, zh: '缩进', en: 'Indentation'),
          description: openHandLocalizedText(
            context,
            zh: '控制编辑器在按下 Tab 时使用的空格数量。默认是 4 个空格；Shift+Tab 会按同样的宽度反向减少缩进。',
            en: 'Controls how many spaces the editor uses when Tab is pressed. The default is 4 spaces; Shift+Tab removes indentation by the same width.',
          ),
          child: _ResponsiveSettingRow(
            title: openHandLocalizedText(
              context,
              zh: 'Tab 等效空格数',
              en: 'Tab Size',
            ),
            subtitle: openHandLocalizedText(
              context,
              zh: '代码编辑器会把 Tab 转换为空格，并按这个宽度进行整行缩进或反向缩进。',
              en: 'The code editor converts Tab into spaces and uses this width for both indentation and outdent operations.',
            ),
            control: AnimatedDropdownButton<int>(
              value: settingsController.editorIndentSpaces,
              underline: const SizedBox.shrink(),
              borderRadius: kOpenHandBorderRadius12,
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
        kOpenHandGap16,
        _SettingsSubsectionCard(
          title: openHandLocalizedText(context, zh: '代码主题', en: 'Code Theme'),
          description: openHandLocalizedText(
            context,
            zh: '选择编辑器中代码的配色方案。',
            en: 'Choose a color scheme for code in the editor.',
          ),
          child: _ResponsiveSettingRow(
            title: openHandLocalizedText(
              context,
              zh: '配色方案',
              en: 'Color Scheme',
            ),
            subtitle: openHandLocalizedText(
              context,
              zh: '切换代码编辑器的语法高亮配色主题。',
              en: 'Switch the syntax highlighting color theme of the code editor.',
            ),
            control: AnimatedDropdownButton<EditorCodeTheme>(
              value: settingsController.editorCodeTheme,
              underline: const SizedBox.shrink(),
              borderRadius: kOpenHandBorderRadius12,
              items: EditorCodeTheme.values
                  .map((theme) {
                    final darkSurface =
                        Theme.of(context).brightness == Brightness.dark;
                    final label = _editorCodeThemeLabel(
                      context,
                      theme,
                      darkSurface,
                    );
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
        kOpenHandGap16,
        _buildEditorShortcutBindingsSection(context, settingsController),
        kOpenHandGap16,
        _SettingsSubsectionCard(
          title: openHandLocalizedText(
            context,
            zh: '语言服务器映射',
            en: 'Language Server Mappings',
          ),
          description: openHandLocalizedText(
            context,
            zh: '为每种语言指定首选 LSP、SDK 目录、LSP 根路径以及下载入口。列表高度已限制，点击条目会以弹窗方式配置。',
            en: 'Choose a preferred LSP, SDK directory, LSP root path, and install entry for each language. The list is height-limited and each row opens a configuration dialog.',
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: PrimaryScrollController.none(
              child: OpenHandSafeScrollbar(
                controller: _editorLspListScrollController,
                child: ListView.separated(
                  controller: _editorLspListScrollController,
                  primary: false,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: supportedLanguages.length,
                  separatorBuilder: (context, index) =>
                      kOpenHandGap10,
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
      title: openHandLocalizedText(
        context,
        zh: '编辑器快捷键',
        en: 'Editor Shortcuts',
      ),
      description: openHandLocalizedText(
        context,
        zh: '这些绑定仅在代码编辑器获得焦点时生效，用于补全、签名提示、导航和常见符号操作。再次按下同一个面板类快捷键会关闭对应工具面板。',
        en: 'These bindings apply only while the code editor is focused. They control completion, signature help, navigation, and common symbol actions. Pressing the same panel shortcut again closes the corresponding tool panel.',
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: PrimaryScrollController.none(
          child: OpenHandSafeScrollbar(
            controller: _editorShortcutListScrollController,
            child: ListView.separated(
              controller: _editorShortcutListScrollController,
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: actions.length,
              separatorBuilder: (context, index) => kOpenHandGap12,
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
    final managedInstallManifest = _editorLspManagedManifest(normalizedRoot);

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
    final managedInstallManifest = _editorLspManagedManifest(normalizedRoot);

    if (settings.isEmpty) {
      return openHandLocalizedText(
        context,
        zh: '当前使用默认自动探测、系统 SDK 与 PATH 解析。',
        en: 'Currently using default auto-detection, system SDKs, and PATH resolution.',
      );
    }

    final segments = <String>[
      backend?.displayName ??
          openHandLocalizedText(context, zh: '未指定后端', en: 'No backend'),
      if (settings.sdkPath.trim().isNotEmpty)
        openHandLocalizedText(
          context,
          zh: 'SDK：${OpenHandPaths.shortenHomePath(settings.sdkPath)}',
          en: 'SDK: ${OpenHandPaths.shortenHomePath(settings.sdkPath)}',
        ),
      if (settings.rootPath.trim().isNotEmpty)
        openHandLocalizedText(
          context,
          zh: 'LSP：${OpenHandPaths.shortenHomePath(settings.rootPath)}',
          en: 'LSP: ${OpenHandPaths.shortenHomePath(settings.rootPath)}',
        ),
      if (settings.version.trim().isNotEmpty) 'v${settings.version.trim()}',
      if (managedInstallManifest != null)
        openHandLocalizedText(
          context,
          zh: 'OpenHand 托管安装',
          en: 'Managed by OpenHand',
        ),
    ];
    return segments.join('  •  ');
  }

  AiLspManagedInstallManifest? _editorLspManagedManifest(String rootPath) {
    if (rootPath.isEmpty) return null;
    unawaited(_ensureEditorLspManifestLoaded(rootPath));
    return AiLspManagedInstallService.peekManifest(rootPath);
  }

  Future<void> _ensureEditorLspManifestLoaded(String rootPath) {
    return _editorLspManifestRefreshes.run(rootPath, () async {
      final before = AiLspManagedInstallService.peekManifest(rootPath);
      final manifest = await AiLspManagedInstallService.readManifest(rootPath);
      if (!identical(before, manifest)) _refreshEditorLspManifestState();
    });
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
      case _EditorLspConfigAction.uninstall:
        await _uninstallEditorLsp(
          context,
          language,
          targetRoot: result.settings.rootPath,
        );
      case _EditorLspConfigAction.save:
        await _saveEditorLspConfig(context, language, result.settings);
      case _EditorLspConfigAction.install:
        await _saveEditorLspConfig(
          context,
          language,
          result.settings,
          installBackend: result.backend,
          startInstall: true,
        );
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
        flashOpenHandSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '当前后端信息无效，无法开始安装。',
            en: 'The selected backend is invalid, so installation cannot start.',
          ),
          kind: OpenHandSnackKind.error,
        );
        return;
      }
      final validationMessage =
          await AiLspManagedInstallService.validateInstallRoot(
            backend: installBackend,
            settings: settings,
          );
      if (!context.mounted) {
        return;
      }
      if (validationMessage != null) {
        flashOpenHandSnack(
          context,
          openHandLocalizedText(
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
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
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
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
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
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
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
      } catch (error, stack) {
        silentLog('settings_editor_lsp', '写入 LSP 卸载元数据', error, stack);
        if (!context.mounted) {
          return;
        }
        final detail = userFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '无法写入卸载元数据。',
            en: 'Unable to record cleanup metadata.',
          ),
        );
        flashOpenHandSnack(
          context,
          openHandLocalizedText(
            context,
            zh: 'LSP 已安装，但写入卸载元数据失败：$detail',
            en: 'Installed the LSP, but failed to record cleanup metadata: $detail',
          ),
          kind: OpenHandSnackKind.error,
        );
        return;
      }
      if (!context.mounted) {
        return;
      }
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '${installBackend.displayName} 已安装到 ${OpenHandPaths.shortenHomePath(installPlan.installRootPath)}。',
          en: 'Installed ${installBackend.displayName} into ${OpenHandPaths.shortenHomePath(installPlan.installRootPath)}.',
        ),
        kind: OpenHandSnackKind.success,
      );
      return;
    }

    flashOpenHandSnack(
      context,
      openHandLocalizedText(
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

    flashOpenHandSnack(
      context,
      openHandLocalizedText(
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
    final manifest = await AiLspManagedInstallService.readManifest(
      normalizedRoot,
      forceRefresh: true,
    );
    if (!context.mounted) return;
    if (manifest == null) {
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '当前路径不是 OpenHand 托管安装目录，无法执行自动清理。',
          en: 'The current path is not an OpenHand-managed install root, so automatic cleanup is unavailable.',
        ),
        kind: OpenHandSnackKind.error,
      );
      return;
    }

    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '卸载 ${manifest.backendId}',
        en: 'Uninstall ${manifest.backendId}',
      ),
      message: openHandLocalizedText(
        context,
        zh: '将删除 ${OpenHandPaths.shortenHomePath(normalizedRoot)} 下的托管安装文件。若当前语言正在使用该路径，还会同步清空已保存的 LSP 路径与版本。这个操作不可撤销。',
        en: 'This deletes the managed install under ${OpenHandPaths.shortenHomePath(normalizedRoot)}. If the current language is using that folder, the saved LSP path and version are cleared as well. This cannot be undone.',
      ),
      cancelLabel: AppLocalizations.of(context)!.commonCancel,
      confirmLabel: openHandLocalizedText(
        context,
        zh: '确认卸载',
        en: 'Confirm Uninstall',
      ),
      destructive: true,
    );
    if (!context.mounted || !confirmed) {
      return;
    }

    try {
      await AiLspManagedInstallService.deleteManagedInstall(normalizedRoot);
    } catch (error, stack) {
      silentLog('settings_editor_lsp', '卸载托管 LSP', error, stack);
      if (!context.mounted) {
        return;
      }
      final detail = userFailureMessage(error, fallback: '无法卸载托管 LSP。');
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '卸载失败：$detail',
          en: 'Uninstall failed: $detail',
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

    flashOpenHandSnack(
      context,
      openHandLocalizedText(
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
    final motionEnabled = _settingsMotionEnabled(context);
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
            borderRadius: kOpenHandBorderRadius18,
            onTap: widget.onTap,
            child: Ink(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: kOpenHandBorderRadius18,
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
                        borderRadius: kOpenHandBorderRadius12,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.terminal_rounded,
                        size: 20,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    kOpenHandHGap12,
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
                                    borderRadius: kOpenHandPillBorderRadius,
                                  ),
                                  child: Text(
                                    openHandLocalizedText(
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
                          kOpenHandGap6,
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
                            kOpenHandGap8,
                            Text(
                              openHandLocalizedText(
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
                    kOpenHandHGap12,
                    AnimatedSlide(
                      offset: Offset(_hovered && motionEnabled ? 0.18 : 0, 0),
                      duration: openHandMotionDuration(context, kOpenHandMotion180),
                      curve: kOpenHandSwitchInCurve,
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
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          kOpenHandHGap8,
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

const Duration _sdkExecutableProbeIdleTimeout = Duration(milliseconds: 500);
const Duration _sdkExecutableProbeTotalTimeout = Duration(seconds: 3);

Future<String?> _resolveSdkExecutable(
  String sdkPath,
  List<List<String>> candidateRelativePaths,
) async {
  final stopwatch = Stopwatch()..start();
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
      final remaining = _sdkExecutableProbeTotalTimeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) return null;
      final timeout = remaining < _sdkExecutableProbeIdleTimeout
          ? remaining
          : _sdkExecutableProbeIdleTimeout;
      if (await isRegularFilePath(
        candidatePath,
        timeout: timeout,
        followLinks: true,
      )) {
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
  final executablePath = await _resolveSdkExecutable(
    sdkPath,
    candidateRelativePaths,
  );
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
  final flutterExecutable = await _resolveSdkExecutable(
    sdkPath,
    const <List<String>>[
      <String>['bin', 'flutter'],
      <String>['flutter'],
    ],
  );
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
      silentLog('settings_editor_lsp', '检测 Flutter SDK 版本', error, stack);
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
  if (normalizedSdkPath.isEmpty ||
      !await isDirectoryPath(normalizedSdkPath, followLinks: true)) {
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
  Timer? _installRootValidationTimer;
  int _installRootValidationGeneration = 0;
  bool _installRootValidationPending = true;
  String? _installRootValidationMessage;
  String _managedInstallManifestRoot = '';
  AiLspManagedInstallManifest? _managedInstallManifest;
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
    _pathController.addListener(_handleInstallRootChanged);
    _sdkController.addListener(_handleControllerChanged);
    _sdkController.addListener(_handleSdkPathChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scheduleInstallRootValidation(immediate: true);
        if (_sdkController.text.trim().isNotEmpty) {
          _scheduleSdkVersionDetection(immediate: true);
        }
      }
    });
  }

  @override
  void dispose() {
    _sdkVersionDetectionTimer?.cancel();
    _installRootValidationTimer?.cancel();
    _installRootValidationGeneration += 1;
    _versionController.removeListener(_handleControllerChanged);
    _versionController.removeListener(_handleVersionControllerChanged);
    _pathController.removeListener(_handleInstallRootChanged);
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

  void _handleInstallRootChanged() {
    _scheduleInstallRootValidation();
  }

  void _scheduleInstallRootValidation({bool immediate = false}) {
    if (!mounted) {
      return;
    }
    _installRootValidationTimer?.cancel();
    final generation = ++_installRootValidationGeneration;
    setState(() {
      _installRootValidationPending = true;
      _installRootValidationMessage = null;
    });
    if (immediate) {
      unawaited(_refreshInstallRootValidation(generation));
      return;
    }
    _installRootValidationTimer = startSafeTimer(
      kOpenHandMotion220,
      () => _refreshInstallRootValidation(generation),
    );
  }

  Future<void> _refreshInstallRootValidation(int generation) async {
    final normalizedEnteredRoot = OpenHandPaths.normalizeOptionalPath(
      _pathController.text,
    );
    final backend = aiLspBackendById(_selectedBackendId);
    String? message;
    var validationFailed = false;
    AiLspManagedInstallManifest? managedInstallManifest;
    try {
      if (backend != null &&
          AiLspManagedInstallService.supportsManagedInstall(backend)) {
        final rootPath = _pathController.text.trim().isEmpty
            ? widget.defaultInstallRoot
            : _pathController.text;
        message = await AiLspManagedInstallService.validateInstallRoot(
          backend: backend,
          settings: AiLspLanguageSettings(
            backendId: _selectedBackendId,
            rootPath: rootPath,
            sdkPath: _sdkController.text.trim(),
            version: _versionController.text.trim(),
          ),
        );
        managedInstallManifest = AiLspManagedInstallService.peekManifest(
          normalizedEnteredRoot,
        );
      } else if (normalizedEnteredRoot.isNotEmpty) {
        managedInstallManifest = await AiLspManagedInstallService.readManifest(
          normalizedEnteredRoot,
        );
      }
    } catch (error, stack) {
      silentLog('settings_editor_lsp', '校验 LSP 安装目录', error, stack);
      validationFailed = true;
    }
    if (!mounted || generation != _installRootValidationGeneration) {
      return;
    }
    if (validationFailed) {
      message = openHandLocalizedText(
        context,
        zh: '无法校验安装目录，请检查权限后重试。',
        zhHant: '無法驗證安裝目錄，請檢查權限後重試。',
        en: 'The install root could not be validated. Check its permissions and retry.',
        fr: 'Impossible de valider le dossier d’installation. Vérifiez ses autorisations et réessayez.',
        de: 'Das Installationsverzeichnis konnte nicht geprüft werden. Prüfen Sie die Berechtigungen und versuchen Sie es erneut.',
        ja: 'インストール先を検証できません。権限を確認して再試行してください。',
      );
    }
    setState(() {
      _installRootValidationPending = false;
      _installRootValidationMessage = message;
      _managedInstallManifestRoot = normalizedEnteredRoot;
      _managedInstallManifest = managedInstallManifest;
    });
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
    _sdkVersionDetectionTimer = startSafeTimer(
      kOpenHandMotion220,
      () => _refreshSdkVersionDetection(normalizedSdkPath),
    );
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
    _DetectedSdkVersion? detected;
    try {
      detected = await _detectSdkVersionForLanguage(
        language: widget.language,
        sdkPath: requestPath,
      );
    } catch (error, stack) {
      silentLog('settings_editor_lsp', '检测 SDK 版本', error, stack);
    }
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
    final appliedToVersionField =
        detected != null &&
        _maybeMirrorDetectedSdkVersionIntoVersionField(
          detected: detected,
          backend: backend,
        );
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
    final languageLabel = _editorLspLanguageLabel(context, widget.language);
    final defaultRootLabel = OpenHandPaths.defaultLspDirectoryLabelForLanguage(
      widget.language,
    );
    final supportsManagedInstall =
        backend != null &&
        AiLspManagedInstallService.supportsManagedInstall(backend);
    final normalizedRoot = OpenHandPaths.normalizeOptionalPath(
      _pathController.text,
    );
    final normalizedSdkPath = OpenHandPaths.normalizeOptionalPath(
      _sdkController.text,
    );
    final managedInstallManifest = _managedInstallManifestRoot == normalizedRoot
        ? _managedInstallManifest
        : null;
    final effectiveInstallRoot = normalizedRoot.isEmpty
        ? widget.defaultInstallRoot
        : normalizedRoot;
    final installValidationMessage = supportsManagedInstall
        ? _installRootValidationMessage
        : null;
    final installValidationPending =
        supportsManagedInstall && _installRootValidationPending;
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
        sdkVersionNoticeText = openHandLocalizedText(
          context,
          zh: '正在根据当前 SDK 目录解析工具链版本…',
          zhHant: '正在根據目前 SDK 目錄解析工具鏈版本…',
          en: 'Resolving the toolchain version from the current SDK directory…',
          fr: 'Résolution de la version de la chaîne d’outils depuis le dossier SDK actuel…',
          de: 'Toolchain-Version wird aus dem aktuellen SDK-Ordner ermittelt…',
          ja: '現在の SDK ディレクトリからツールチェーンのバージョンを解析しています…',
        );
        sdkVersionNoticeColor = colorScheme.primary;
        sdkVersionNoticeIcon = Icons.sync_rounded;
      } else if (_detectedSdkVersion != null) {
        sdkVersionNoticeColor = canMirrorDetectedSdkVersion
            ? colorScheme.primary
            : colorScheme.tertiary;
        sdkVersionNoticeIcon = Icons.verified_rounded;
        if (canMirrorDetectedSdkVersion) {
          sdkVersionNoticeText = _sdkVersionAppliedToLspVersion
              ? openHandLocalizedText(
                  context,
                  zh: '已自动解析 SDK 版本：${_detectedSdkVersion!.display}，并同步填入下方的 LSP 版本字段。',
                  zhHant:
                      '已自動解析 SDK 版本：${_detectedSdkVersion!.display}，並同步填入下方的 LSP 版本欄位。',
                  en: 'Auto-detected SDK version: ${_detectedSdkVersion!.display}, and mirrored it into the LSP version field below.',
                  fr: 'Version du SDK détectée automatiquement : ${_detectedSdkVersion!.display}. Elle a été recopiée dans le champ de version LSP ci-dessous.',
                  de: 'SDK-Version automatisch erkannt: ${_detectedSdkVersion!.display}. Sie wurde in das LSP-Versionsfeld unten übernommen.',
                  ja: 'SDK バージョン ${_detectedSdkVersion!.display} を自動検出し、下の LSP バージョン欄に同期しました。',
                )
              : openHandLocalizedText(
                  context,
                  zh: '已自动解析 SDK 版本：${_detectedSdkVersion!.display}。当前 LSP 版本字段已由你手动接管，因此本次没有自动覆盖。',
                  zhHant:
                      '已自動解析 SDK 版本：${_detectedSdkVersion!.display}。目前 LSP 版本欄位已由你手動接管，因此本次沒有自動覆蓋。',
                  en: 'Auto-detected SDK version: ${_detectedSdkVersion!.display}. The LSP version field is currently under manual control, so it was not overwritten.',
                  fr: 'Version du SDK détectée automatiquement : ${_detectedSdkVersion!.display}. Le champ de version LSP est sous contrôle manuel, il n’a donc pas été remplacé.',
                  de: 'SDK-Version automatisch erkannt: ${_detectedSdkVersion!.display}. Das LSP-Versionsfeld wird manuell verwaltet und wurde daher nicht überschrieben.',
                  ja: 'SDK バージョン ${_detectedSdkVersion!.display} を自動検出しました。LSP バージョン欄は手動管理中のため上書きしていません。',
                );
        } else {
          sdkVersionNoticeText = openHandLocalizedText(
            context,
            zh: '已自动解析 SDK 版本：${_detectedSdkVersion!.display}。为避免把托管安装装到错误的 LSP 版本，下方的 LSP 版本字段保持独立。',
            zhHant:
                '已自動解析 SDK 版本：${_detectedSdkVersion!.display}。為避免托管安裝裝到錯誤的 LSP 版本，下方的 LSP 版本欄位會保持獨立。',
            en: 'Auto-detected SDK version: ${_detectedSdkVersion!.display}. The LSP version field stays independent so managed installs do not target the wrong release.',
            fr: 'Version du SDK détectée automatiquement : ${_detectedSdkVersion!.display}. Le champ de version LSP reste indépendant afin d’éviter une mauvaise cible d’installation.',
            de: 'SDK-Version automatisch erkannt: ${_detectedSdkVersion!.display}. Das LSP-Versionsfeld bleibt unabhängig, damit verwaltete Installationen nicht die falsche Version wählen.',
            ja: 'SDK バージョン ${_detectedSdkVersion!.display} を自動検出しました。管理インストールが誤った LSP リリースを選ばないよう、LSP バージョン欄は独立させます。',
          );
        }
      } else if (_sdkVersionDetectionFailed) {
        sdkVersionNoticeText = openHandLocalizedText(
          context,
          zh: '当前 SDK 目录还没有解析出版本，请确认它指向真实的工具链根目录。',
          zhHant: '目前 SDK 目錄尚未解析出版本，請確認它指向真實的工具鏈根目錄。',
          en: 'The current SDK directory did not resolve to a version yet. Confirm that it points to a real toolchain root.',
          fr: 'Le dossier SDK actuel n’a pas encore fourni de version. Vérifiez qu’il pointe vers une vraie racine de chaîne d’outils.',
          de: 'Aus dem aktuellen SDK-Ordner konnte noch keine Version ermittelt werden. Prüfen Sie, ob er auf eine echte Toolchain-Wurzel zeigt.',
          ja: '現在の SDK ディレクトリからバージョンを解析できません。実際のツールチェーンのルートを指しているか確認してください。',
        );
        sdkVersionNoticeColor = colorScheme.error;
        sdkVersionNoticeIcon = Icons.info_outline_rounded;
      }
    }

    return buildOpenHandAlertDialog(
      title: Text(
        openHandLocalizedText(
          context,
          zh: '配置 $languageLabel 的工具链',
          zhHant: '設定 $languageLabel 的工具鏈',
          en: 'Configure $languageLabel Toolchain',
          fr: 'Configurer la chaîne d’outils $languageLabel',
          de: '$languageLabel-Toolchain konfigurieren',
          ja: '$languageLabel のツールチェーンを設定',
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
                openHandLocalizedText(
                  context,
                  zh: '在这里为当前语言统一管理 LSP 后端、SDK 目录、LSP 根路径与安装方式。保存后立即生效；如后端支持托管安装，也可以直接在当前弹窗中下载并安装。',
                  zhHant:
                      '在這裡統一管理目前語言的 LSP 後端、SDK 目錄、LSP 根路徑與安裝方式。儲存後立即生效；若後端支援托管安裝，也可以直接在目前彈窗中下載並安裝。',
                  en: 'Manage the LSP backend, SDK directory, LSP root path, and install workflow for this language here. Saving takes effect immediately, and supported backends can be downloaded directly from this dialog.',
                  fr: 'Gérez ici le backend LSP, le dossier SDK, la racine LSP et le flux d’installation pour ce langage. L’enregistrement prend effet immédiatement, et les backends compatibles peuvent être téléchargés depuis cette fenêtre.',
                  de: 'Verwalten Sie hier LSP-Backend, SDK-Ordner, LSP-Wurzelpfad und Installation für diese Sprache. Speichern wirkt sofort; unterstützte Backends können direkt aus diesem Dialog heruntergeladen werden.',
                  ja: 'この言語の LSP バックエンド、SDK ディレクトリ、LSP ルートパス、インストール方法をまとめて管理します。保存後すぐに反映され、対応バックエンドはこのダイアログから直接ダウンロードできます。',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              kOpenHandGap16,
              AnimatedDropdownButtonFormField<String>(
                initialValue: _selectedBackendId,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: 'LSP 后端',
                    zhHant: 'LSP 後端',
                    en: 'LSP Backend',
                    fr: 'Backend LSP',
                    de: 'LSP-Backend',
                    ja: 'LSP バックエンド',
                  ),
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
                    _sdkVersionAppliedToLspVersion =
                        _detectedSdkVersion != null &&
                        _maybeMirrorDetectedSdkVersionIntoVersionField(
                          detected: _detectedSdkVersion!,
                          backend: aiLspBackendById(value),
                        );
                  });
                  _scheduleInstallRootValidation();
                },
              ),
              kOpenHandGap14,
              OpenHandDirectoryField(
                controller: _sdkController,
                label: openHandLocalizedText(
                  context,
                  zh: 'SDK 目录',
                  zhHant: 'SDK 目錄',
                  en: 'SDK Directory',
                  fr: 'Dossier SDK',
                  de: 'SDK-Ordner',
                  ja: 'SDK ディレクトリ',
                ),
                hintText: openHandLocalizedText(
                  context,
                  zh: '可选，不配置则沿用系统默认',
                  zhHant: '可選，不設定則沿用系統預設',
                  en: 'Optional, use the system default when empty',
                  fr: 'Facultatif, utilise la valeur système par défaut si vide',
                  de: 'Optional, leer bedeutet Systemstandard',
                  ja: '任意。空の場合はシステム既定を使用',
                ),
                helperText: openHandLocalizedText(
                  context,
                  zh: '用于记录当前语言 SDK 的位置，并作为项目级配置的默认值。',
                  zhHant: '用於記錄目前語言 SDK 的位置，並作為專案級設定的預設值。',
                  en: 'Records where this language SDK lives and seeds project-level defaults.',
                  fr: 'Enregistre l’emplacement du SDK de ce langage et l’utilise comme valeur par défaut du projet.',
                  de: 'Speichert den Ort des SDKs dieser Sprache und nutzt ihn als Projektstandard.',
                  ja: 'この言語の SDK の場所を記録し、プロジェクト単位の既定値として使います。',
                ),
                browseTooltip: _settingsEditorBrowseFolderLabel(context),
                onBrowse: _browseSdkDirectory,
              ),
              if (sdkVersionNoticeText != null) ...[
                kOpenHandGap10,
                _EditorLspInlineNotice(
                  icon: sdkVersionNoticeIcon,
                  color: sdkVersionNoticeColor,
                  text: sdkVersionNoticeText,
                ),
              ],
              kOpenHandGap14,
              TextField(
                controller: _versionController,
                decoration: InputDecoration(
                  labelText: openHandLocalizedText(
                    context,
                    zh: 'LSP 版本',
                    zhHant: 'LSP 版本',
                    en: 'LSP Version',
                    fr: 'Version LSP',
                    de: 'LSP-Version',
                    ja: 'LSP バージョン',
                  ),
                  hintText: 'latest',
                  helperText: openHandLocalizedText(
                    context,
                    zh: '这是 LSP / 安装版本，不一定等同于 SDK 版本；留空或填写 latest 表示使用最新版本。',
                    zhHant:
                        '這是 LSP / 安裝版本，不一定等同於 SDK 版本；留空或填寫 latest 表示使用最新版本。',
                    en: 'This is the LSP / install version and may differ from the SDK version. Leave blank or use latest to install the newest release.',
                    fr: 'Version LSP / installation, pas forcément identique à la version SDK. Laissez vide ou saisissez latest pour la dernière version.',
                    de: 'Dies ist die LSP-/Installationsversion und kann von der SDK-Version abweichen. Leer oder latest installiert die neueste Version.',
                    ja: 'LSP / インストール用のバージョンです。SDK バージョンと同じとは限りません。空欄または latest で最新リリースを使います。',
                  ),
                ),
              ),
              kOpenHandGap14,
              OpenHandDirectoryField(
                controller: _pathController,
                label: openHandLocalizedText(
                  context,
                  zh: 'LSP 根路径',
                  zhHant: 'LSP 根路徑',
                  en: 'LSP Root Path',
                  fr: 'Racine LSP',
                  de: 'LSP-Wurzelpfad',
                  ja: 'LSP ルートパス',
                ),
                hintText: defaultRootLabel,
                helperText: openHandLocalizedText(
                  context,
                  zh: '为空时继续从 PATH 自动探测；点击“下载并安装”时会自动回落到默认安装目录。',
                  zhHant: '留空時繼續從 PATH 自動偵測；點擊「下載並安裝」時會自動回落到預設安裝目錄。',
                  en: 'Leave empty to keep PATH-based auto detection. Download & Install falls back to the default install root automatically.',
                  fr: 'Laissez vide pour conserver la détection via PATH. Télécharger et installer utilise automatiquement la racine par défaut.',
                  de: 'Leer lassen, um die PATH-Erkennung beizubehalten. Herunterladen und installieren nutzt automatisch die Standardwurzel.',
                  ja: '空欄にすると PATH ベースの自動検出を続けます。「ダウンロードしてインストール」は既定のインストール先に自動で戻ります。',
                ),
                browseTooltip: _settingsEditorBrowseFolderLabel(context),
                onBrowse: _browseLspDirectory,
              ),
              kOpenHandGap8,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (showDefaultRootShortcut)
                    ActionChip(
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '使用默认目录 $defaultRootLabel',
                          zhHant: '使用預設目錄 $defaultRootLabel',
                          en: 'Use default root $defaultRootLabel',
                          fr: 'Utiliser la racine par défaut $defaultRootLabel',
                          de: 'Standardwurzel $defaultRootLabel verwenden',
                          ja: '既定のルート $defaultRootLabel を使用',
                        ),
                      ),
                      onPressed: () {
                        _pathController.text = widget.defaultInstallRoot;
                      },
                    ),
                  if (showClearRootShortcut)
                    ActionChip(
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '清空并回退到 PATH',
                          zhHant: '清空並回退到 PATH',
                          en: 'Clear and fall back to PATH',
                          fr: 'Vider et revenir à PATH',
                          de: 'Leeren und auf PATH zurückfallen',
                          ja: 'クリアして PATH に戻す',
                        ),
                      ),
                      onPressed: () {
                        _pathController.clear();
                      },
                    ),
                  if (showLatestVersionShortcut)
                    ActionChip(
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '版本设为 latest',
                          zhHant: '版本設為 latest',
                          en: 'Set version to latest',
                          fr: 'Définir la version sur latest',
                          de: 'Version auf latest setzen',
                          ja: 'バージョンを latest に設定',
                        ),
                      ),
                      onPressed: () {
                        _versionController.clear();
                      },
                    ),
                ],
              ),
              kOpenHandGap12,
              if (installValidationPending)
                _EditorLspInlineNotice(
                  icon: Icons.sync_rounded,
                  color: colorScheme.primary,
                  text: openHandLocalizedText(
                    context,
                    zh: '正在检查托管安装目录边界…',
                    zhHant: '正在檢查托管安裝目錄邊界…',
                    en: 'Checking the managed-install directory boundary…',
                    fr: 'Vérification des limites du dossier d’installation gérée…',
                    de: 'Das Verzeichnis für die verwaltete Installation wird geprüft…',
                    ja: '管理インストール先のディレクトリ境界を確認しています…',
                  ),
                )
              else if (installValidationMessage != null)
                _EditorLspInlineNotice(
                  icon: Icons.warning_amber_rounded,
                  color: colorScheme.error,
                  text: openHandLocalizedText(
                    context,
                    zh: '当前安装目录边界检查未通过：$installValidationMessage\n如仅保存配置而不做托管安装，可以改为清空路径并继续使用 PATH 自动探测。',
                    zhHant:
                        '目前安裝目錄邊界檢查未通過：$installValidationMessage\n若只想儲存設定而不做托管安裝，可以清空路徑並繼續使用 PATH 自動偵測。',
                    en: 'The current install root did not pass validation: $installValidationMessage\nIf you only want to save the mapping without a managed install, clear the path and keep PATH-based auto detection instead.',
                    fr: 'La racine d’installation actuelle n’a pas passé la validation : $installValidationMessage\nPour enregistrer seulement la correspondance sans installation gérée, videz le chemin et gardez la détection via PATH.',
                    de: 'Die aktuelle Installationswurzel hat die Prüfung nicht bestanden: $installValidationMessage\nWenn Sie nur die Zuordnung speichern möchten, leeren Sie den Pfad und behalten Sie die PATH-Erkennung bei.',
                    ja: '現在のインストールルートは検証に失敗しました: $installValidationMessage\n管理インストールなしで設定だけ保存する場合は、パスを空にして PATH 自動検出を使ってください。',
                  ),
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
                            ? openHandLocalizedText(
                                context,
                                zh: '当前未显式填写 LSP 根路径。点击“下载并安装”时会自动使用默认目录 $defaultRootLabel；若只保存配置，则继续沿用 PATH 自动探测。',
                                zhHant:
                                    '目前未明確填寫 LSP 根路徑。點擊「下載並安裝」時會自動使用預設目錄 $defaultRootLabel；若只儲存設定，則繼續沿用 PATH 自動偵測。',
                                en: 'No explicit LSP root is set yet. Download & Install will automatically use the default directory $defaultRootLabel, while Save Only continues to rely on PATH auto detection.',
                                fr: 'Aucune racine LSP explicite n’est définie. Télécharger et installer utilisera automatiquement le dossier par défaut $defaultRootLabel, tandis que Enregistrer seulement gardera la détection via PATH.',
                                de: 'Es ist noch keine LSP-Wurzel gesetzt. Herunterladen und installieren nutzt automatisch $defaultRootLabel; Nur speichern verwendet weiter die PATH-Erkennung.',
                                ja: '明示的な LSP ルートは未設定です。「ダウンロードしてインストール」は既定ディレクトリ $defaultRootLabel を使い、「保存のみ」は PATH 自動検出を続けます。',
                              )
                            : openHandLocalizedText(
                                context,
                                zh: '当前目录通过了托管安装边界检查。后续下载会写入 ${OpenHandPaths.shortenHomePath(effectiveInstallRoot)}，并保留对应卸载元数据。',
                                zhHant:
                                    '目前目錄已通過托管安裝邊界檢查。後續下載會寫入 ${OpenHandPaths.shortenHomePath(effectiveInstallRoot)}，並保留對應卸載元資料。',
                                en: 'The current directory passed the managed-install safety check. Future downloads will write into ${OpenHandPaths.shortenHomePath(effectiveInstallRoot)} and keep uninstall metadata there.',
                                fr: 'Le dossier actuel a passé le contrôle d’installation gérée. Les prochains téléchargements écriront dans ${OpenHandPaths.shortenHomePath(effectiveInstallRoot)} et y conserveront les métadonnées de désinstallation.',
                                de: 'Der aktuelle Ordner hat die Prüfung für verwaltete Installationen bestanden. Künftige Downloads schreiben nach ${OpenHandPaths.shortenHomePath(effectiveInstallRoot)} und behalten dort Deinstallationsmetadaten.',
                                ja: '現在のディレクトリは管理インストールの安全チェックに合格しました。今後のダウンロードは ${OpenHandPaths.shortenHomePath(effectiveInstallRoot)} に書き込み、アンインストール用メタデータを保持します。',
                              ))
                      : (normalizedRoot.isEmpty
                            ? openHandLocalizedText(
                                context,
                                zh: '当前不会为这个语言保存自定义 LSP 根路径，编辑器会继续从 PATH 自动解析后端命令。',
                                zhHant:
                                    '目前不會為這個語言儲存自訂 LSP 根路徑，編輯器會繼續從 PATH 自動解析後端命令。',
                                en: 'No custom LSP root will be stored for this language, so the editor will continue resolving the backend from PATH.',
                                fr: 'Aucune racine LSP personnalisée ne sera enregistrée pour ce langage ; l’éditeur continuera à résoudre le backend via PATH.',
                                de: 'Für diese Sprache wird keine benutzerdefinierte LSP-Wurzel gespeichert; der Editor löst das Backend weiter über PATH auf.',
                                ja: 'この言語にはカスタム LSP ルートを保存しません。エディタは引き続き PATH からバックエンドを解決します。',
                              )
                            : openHandLocalizedText(
                                context,
                                zh: '当前仅保存一个现成的本地 LSP 根路径，不会触发托管下载。',
                                zhHant: '目前只會儲存既有的本機 LSP 根路徑，不會觸發托管下載。',
                                en: 'This will only save an existing local LSP root and will not trigger a managed download.',
                                fr: 'Cela enregistre seulement une racine LSP locale existante et ne déclenche pas de téléchargement géré.',
                                de: 'Dies speichert nur eine vorhandene lokale LSP-Wurzel und startet keinen verwalteten Download.',
                                ja: '既存のローカル LSP ルートだけを保存し、管理ダウンロードは開始しません。',
                              )),
                ),
              if (managedInstallManifest != null) ...[
                kOpenHandGap14,
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
                        openHandLocalizedText(
                          context,
                          zh: '当前目录已检测到托管安装',
                          zhHant: '目前目錄已偵測到托管安裝',
                          en: 'Managed install detected',
                          fr: 'Installation gérée détectée',
                          de: 'Verwaltete Installation erkannt',
                          ja: '管理インストールを検出',
                        ),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      kOpenHandGap6,
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '后端：${managedInstallManifest.backendId}\n目录：${OpenHandPaths.shortenHomePath(managedInstallManifest.installRootPath)}\n版本：${managedInstallManifest.version}',
                          zhHant:
                              '後端：${managedInstallManifest.backendId}\n目錄：${OpenHandPaths.shortenHomePath(managedInstallManifest.installRootPath)}\n版本：${managedInstallManifest.version}',
                          en: 'Backend: ${managedInstallManifest.backendId}\nRoot: ${OpenHandPaths.shortenHomePath(managedInstallManifest.installRootPath)}\nVersion: ${managedInstallManifest.version}',
                          fr: 'Backend : ${managedInstallManifest.backendId}\nRacine : ${OpenHandPaths.shortenHomePath(managedInstallManifest.installRootPath)}\nVersion : ${managedInstallManifest.version}',
                          de: 'Backend: ${managedInstallManifest.backendId}\nWurzel: ${OpenHandPaths.shortenHomePath(managedInstallManifest.installRootPath)}\nVersion: ${managedInstallManifest.version}',
                          ja: 'バックエンド: ${managedInstallManifest.backendId}\nルート: ${OpenHandPaths.shortenHomePath(managedInstallManifest.installRootPath)}\nバージョン: ${managedInstallManifest.version}',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              kOpenHandGap12,
              Text(
                supportsManagedInstall
                    ? openHandLocalizedText(
                        context,
                        zh: '当前后端支持托管安装。开始安装前会校验目录安全性，避免覆盖非 OpenHand 管理的现有文件。',
                        zhHant:
                            '目前後端支援托管安裝。開始安裝前會校驗目錄安全性，避免覆蓋非 OpenHand 管理的現有檔案。',
                        en: 'This backend supports managed installation. The chosen folder is validated first so the app does not overwrite unrelated existing files.',
                        fr: 'Ce backend prend en charge l’installation gérée. Le dossier choisi est validé d’abord afin de ne pas écraser des fichiers non gérés par OpenHand.',
                        de: 'Dieses Backend unterstützt verwaltete Installation. Der gewählte Ordner wird zuerst geprüft, damit OpenHand keine fremden Dateien überschreibt.',
                        ja: 'このバックエンドは管理インストールに対応しています。開始前にフォルダの安全性を検証し、OpenHand 管理外の既存ファイルを上書きしないようにします。',
                      )
                    : openHandLocalizedText(
                        context,
                        zh: '当前后端在当前平台下暂不提供可托管安装包。你仍然可以仅保存一个已经存在的本地 LSP 路径。',
                        zhHant: '目前後端在目前平台下暫不提供可托管安裝包。你仍然可以只儲存既有的本機 LSP 路徑。',
                        en: 'This backend does not currently expose a managed install package on the current platform. You can still save an already installed local LSP root.',
                        fr: 'Ce backend ne fournit pas encore de paquet d’installation gérée sur cette plateforme. Vous pouvez tout de même enregistrer une racine LSP locale existante.',
                        de: 'Dieses Backend bietet auf der aktuellen Plattform noch kein Paket für verwaltete Installation. Sie können dennoch eine vorhandene lokale LSP-Wurzel speichern.',
                        ja: 'このバックエンドは現在のプラットフォームで管理インストール用パッケージを提供していません。既存のローカル LSP ルートだけ保存できます。',
                      ),
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
            label: openHandLocalizedText(
              context,
              zh: '卸载并清理',
              zhHant: '解除安裝並清理',
              en: 'Uninstall & Clean',
              fr: 'Désinstaller et nettoyer',
              de: 'Deinstallieren und bereinigen',
              ja: 'アンインストールしてクリーンアップ',
            ),
          ),
        OpenHandDialogActionButton.secondary(
          onPressed: () => _submit(_EditorLspConfigAction.reset),
          label: openHandLocalizedText(
            context,
            zh: '恢复自动探测',
            zhHant: '恢復自動偵測',
            en: 'Reset to Auto',
            fr: 'Réinitialiser en auto',
            de: 'Auf Auto zurücksetzen',
            ja: '自動検出に戻す',
          ),
        ),
        OpenHandDialogActionButton.secondary(
          onPressed: () => _submit(_EditorLspConfigAction.save),
          label: openHandLocalizedText(
            context,
            zh: '仅保存',
            zhHant: '僅儲存',
            en: 'Save Only',
            fr: 'Enregistrer seulement',
            de: 'Nur speichern',
            ja: '保存のみ',
          ),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: supportsManagedInstall
              ? () => _submit(_EditorLspConfigAction.install)
              : null,
          label: openHandLocalizedText(
            context,
            zh: '下载并安装',
            zhHant: '下載並安裝',
            en: 'Download & Install',
            fr: 'Télécharger et installer',
            de: 'Herunterladen und installieren',
            ja: 'ダウンロードしてインストール',
          ),
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
    extends State<_EditorLspInstallRunnerDialog>
    with BufferedConsoleLogHost<_EditorLspInstallRunnerDialog> {
  @override
  String get consoleLogTag => 'settings_editor_lsp';

  static const Duration _installTimeout = Duration(minutes: 10);
  static const Duration _processStartTimeout = Duration(seconds: 10);
  final TrackedProcessSlot _processSlot = TrackedProcessSlot(
    logTag: 'settings_editor_lsp',
  );
  bool _disposed = false;
  bool _running = true;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed) _startInstall();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _processSlot.abort('释放安装进程');
    super.dispose();
  }

  void _appendLine(String value) {
    if (_disposed) return;
    appendConsoleLine(value);
  }

  bool _isRunActive(int generation) {
    return mounted && !_disposed && _processSlot.isCurrent(generation);
  }

  Future<void> _startInstall() async {
    final generation = _processSlot.beginRun();
    Process? startedProcess;
    try {
      await createDirectoryBounded(Directory(widget.plan.installRootPath));
      if (!mounted || !_isRunActive(generation)) return;
      _appendLine('\$ ${widget.plan.previewCommand}');
      _appendLine('');

      final launch = _buildInstallLaunch(widget.plan.shellCommand);
      final result = await runTrackedProcessWithLineLogging(
        launch.executable,
        launch.arguments,
        timeout: _installTimeout,
        processStartTimeout: _processStartTimeout,
        tag: 'settings_editor_lsp',
        runInShell: launch.runInShell,
        environment: <String, String>{
          'FORCE_COLOR': '1',
          ...SystemProxyResolver.instance.resolveSubprocessEnvironment(),
        },
        onStdoutLine: _appendLine,
        onStderrLine: _appendLine,
        onProcessStarted: (process) {
          startedProcess = process;
          _processSlot.claim(process, generation, staleAction: '终止延迟到达的安装进程');
        },
      );
      if (!mounted || !_isRunActive(generation)) return;
      setState(() {
        _running = false;
        _success = !result.timedOut && result.exitCode == 0;
      });
      _appendLine('');
      if (result.timedOut) {
        _appendLine(
          openHandLocalizedText(
            context,
            zh: '✗ 安装超时（超过 ${_installTimeout.inMinutes} 分钟）',
            en: '✗ Installation timed out after ${_installTimeout.inMinutes} minutes',
          ),
        );
      } else if (_success) {
        _appendLine(
          openHandLocalizedText(
            context,
            zh: '✓ 安装完成',
            en: '✓ Installation completed',
          ),
        );
      } else {
        _appendLine(
          openHandLocalizedText(
            context,
            zh: '✗ 安装失败（退出码：${result.exitCode}）',
            en: '✗ Installation failed (exit code: ${result.exitCode})',
          ),
        );
      }
    } catch (error, stack) {
      silentLog('settings_editor_lsp', '运行 LSP 安装命令', error, stack);
      if (!_isRunActive(generation)) return;
      setState(() {
        _running = false;
        _success = false;
      });
      _appendLine('');
      _appendLine('✗ ${userFailureMessage(error, fallback: 'LSP 安装命令执行失败。')}');
    } finally {
      _processSlot.release(startedProcess);
    }
  }

  ({String executable, List<String> arguments, bool runInShell})
  _buildInstallLaunch(String shellCommand) {
    if (Platform.isWindows) {
      return (
        executable: 'cmd',
        arguments: <String>['/c', shellCommand],
        runInShell: true,
      );
    }
    return (
      executable: resolveHarnessCliShellExecutable(),
      arguments: buildHarnessCliShellArgs(shellCommand),
      runInShell: false,
    );
  }

  void _cancelAndClose() {
    _processSlot.abort('取消安装进程');
    Navigator.of(context).pop(false);
  }

  Color _terminalLineColor(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('\$')) {
      return OpenHandConsolePalette.githubCommand;
    }
    if (trimmed.startsWith('✓')) {
      return OpenHandConsolePalette.githubSuccess;
    }
    if (trimmed.startsWith('✗')) {
      return OpenHandConsolePalette.githubError;
    }
    if (trimmed.startsWith('OpenHand:')) {
      return OpenHandConsolePalette.githubNotice;
    }
    return OpenHandConsolePalette.githubText;
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
    final languageLabel = _editorLspLanguageLabel(context, widget.language);
    final installRoot = OpenHandPaths.shortenHomePath(
      widget.plan.installRootPath,
    );
    const terminalBackground = OpenHandConsolePalette.deepSurface;
    const terminalChrome = OpenHandConsolePalette.githubSurface;
    const terminalBorder = OpenHandConsolePalette.githubBorder;
    const terminalMuted = OpenHandConsolePalette.githubMuted;

    return buildOpenHandAlertDialog(
      title: Text(
        openHandLocalizedText(
          context,
          zh: '安装 ${widget.backend.displayName}',
          zhHant: '安裝 ${widget.backend.displayName}',
          en: 'Install ${widget.backend.displayName}',
          fr: 'Installer ${widget.backend.displayName}',
          de: '${widget.backend.displayName} installieren',
          ja: '${widget.backend.displayName} をインストール',
        ),
      ),
      content: SizedBox(
        width: 700,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              openHandLocalizedText(
                context,
                zh: '语言：$languageLabel\n安装目录：$installRoot',
                zhHant: '語言：$languageLabel\n安裝目錄：$installRoot',
                en: 'Language: $languageLabel\nInstall root: $installRoot',
                fr: 'Langage : $languageLabel\nRacine d’installation : $installRoot',
                de: 'Sprache: $languageLabel\nInstallationswurzel: $installRoot',
                ja: '言語: $languageLabel\nインストール先: $installRoot',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            kOpenHandGap14,
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: terminalBackground,
                  borderRadius: kOpenHandBorderRadius12,
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
                          top: Radius.circular(kOpenHandRadius12),
                        ),
                      ),
                      child: Row(
                        children: [
                          _terminalDot(const Color(0xFFFF5F57)),
                          kOpenHandHGap6,
                          _terminalDot(const Color(0xFFFEBB2E)),
                          kOpenHandHGap6,
                          _terminalDot(const Color(0xFF28C840)),
                          kOpenHandHGap12,
                          Expanded(
                            child: Text(
                              OpenHandPaths.shortenHomePath(
                                widget.plan.installRootPath,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: terminalMuted,
                                fontFamily: kOpenHandMonospaceFontFamily,
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
                        onNotification: logScrollGuard.handleNotification,
                        child: ListView.builder(
                          controller: logScrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: logLines.length,
                          itemBuilder: (context, index) {
                            final line = logLines[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: SelectableText(
                                line.isEmpty ? ' ' : line,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: kOpenHandMonospaceFontFamily,
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
            onPressed: _cancelAndClose,
            label: AppLocalizations.of(context)!.commonCancel,
          )
        else
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(context).pop(_success),
            label: AppLocalizations.of(context)!.commonClose,
          ),
      ],
    );
  }
}

// ── 本文件内复用的文案 ──
// 同一标签在本文件里出现两次以上；抽成函数后措辞只有一个改动点。

String _settingsEditorBrowseFolderLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '浏览文件夹',
    zhHant: '瀏覽資料夾',
    en: 'Browse folder',
    fr: 'Parcourir le dossier',
    de: 'Ordner auswählen',
    ja: 'フォルダを参照',
  );
}
