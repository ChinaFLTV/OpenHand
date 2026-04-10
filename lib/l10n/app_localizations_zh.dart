// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'OpenHand';

  @override
  String get appTagline => '开放、稳定、可扩展的桌面工作台';

  @override
  String get newThread => '新线程';

  @override
  String get automations => '自动化';

  @override
  String get skills => '技能';

  @override
  String get memory => '记忆';

  @override
  String get mcp => 'MCP';

  @override
  String get settings => '设置';

  @override
  String get threads => '线程';

  @override
  String get workspaceHeadline => '开始构建';

  @override
  String get composerHint => '询问 OpenHand 任何内容，使用 / 触发动作，使用 @ 引用上下文';

  @override
  String get composerSend => '发送';

  @override
  String get chatSending => '发送中';

  @override
  String get chatRequestFailed => '模型请求失败，请检查模型配置、网络连通性或接口协议。';

  @override
  String get composerUnavailable => '当前为基础骨架，暂未接入实际执行能力。';

  @override
  String get workspaceReadyTitle => '基础骨架已就绪';

  @override
  String get workspaceReadyBody =>
      '当前已经完成桌面端主布局、主题切换、语言切换与设置页基础能力，后续模块可以在此逐步扩展。';

  @override
  String get quickActionsTitle => '建议从这里开始';

  @override
  String get quickActionCreateShell => '创建桌面应用骨架';

  @override
  String get quickActionThemeLanguage => '配置主题与语言';

  @override
  String get quickActionPlanModules => '规划功能模块';

  @override
  String get automationHeadline => '自动化模块骨架';

  @override
  String get automationBody => '后续可在这里编排定时任务、工作流和工具链触发逻辑。';

  @override
  String get skillsHeadline => '技能中心骨架';

  @override
  String get skillsBody => '后续可在这里管理能力插件、提示模板和开发辅助工具。';

  @override
  String get placeholderComingSoon => '后续功能模块将在这里逐步扩展。';

  @override
  String get settingsTitle => '设置中心';

  @override
  String get settingsSubtitle => '在这里管理主题、语言与应用信息。';

  @override
  String get settingsFilePathLabel => '设置文件';

  @override
  String get themeSectionTitle => '应用主题';

  @override
  String get themeSectionBody => '选择适合当前工作环境的界面亮度风格。';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get themePaletteSectionTitle => '主题配色';

  @override
  String get themePaletteSectionBody =>
      '选择全局主题配色，系统会基于该配色生成 Material 3 Expressive 主题层次。';

  @override
  String get themePresetDarkNightPurple => '暗夜紫';

  @override
  String get themePresetDeepSeaBlue => '深海蓝';

  @override
  String get themePresetMistGray => '雾霭灰';

  @override
  String get themePresetObsidianBlack => '曜石黑';

  @override
  String get themePresetPolarWhite => '极昼白';

  @override
  String get themePresetFrostMorningBlue => '霜晨蓝';

  @override
  String get themePresetDuskMountainGreen => '暮山青';

  @override
  String get themePresetNebulaPurple => '星云紫';

  @override
  String get themePresetEmberOrange => '余烬橙';

  @override
  String get themePresetTundraGreen => '苔原绿';

  @override
  String get themePresetMoonShadowSilver => '月影银';

  @override
  String get themePresetAmberGold => '琥珀金';

  @override
  String get themePresetRainyCyan => '烟雨青';

  @override
  String get themePresetGraphiteGray => '石墨灰';

  @override
  String get themePresetGlacierBlue => '冰川蓝';

  @override
  String get themePresetBlazeRed => '赤焰红';

  @override
  String get themePresetNightfallBlue => '夜幕蓝';

  @override
  String get themePresetColdMoonWhite => '冷月白';

  @override
  String get themePresetPineInk => '松烟墨';

  @override
  String get themePresetSkyCyan => '苍穹青';

  @override
  String get languageSectionTitle => '应用语言';

  @override
  String get languageSectionBody => '切换界面显示语言，保存后立即生效。';

  @override
  String get languageSimplifiedChinese => '简体中文';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get languageJapanese => '日本語';

  @override
  String get aboutSectionTitle => '关于应用';

  @override
  String get aboutSectionBody =>
      'OpenHand 当前处于基础骨架阶段，重点提供稳定的桌面应用结构、视觉基线与可扩展能力。';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutPackage => '包名';

  @override
  String get aboutPlatforms => '支持平台';

  @override
  String get aboutPlatformsValue => 'macOS 15+ / Windows 10+';

  @override
  String get aboutBuild => '构建号';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '删除';

  @override
  String get commonEdit => '编辑';

  @override
  String get previewSectionTitle => '设计方向';

  @override
  String get previewSectionBody =>
      '遵循 Material 3 Expressive 设计理念，强调层次、留白、圆角、柔和光感与清晰的信息节奏。';

  @override
  String get threadPrimary => 'OpenHand';

  @override
  String get threadShell => '桌面应用骨架';

  @override
  String get threadSettings => '设置与本地化';

  @override
  String get threadRoadmap => '后续模块规划';

  @override
  String get switchToWorkspace => '返回主工作台';

  @override
  String get modelLabel => 'OpenHand Skeleton';

  @override
  String get platformLabel => '桌面端';

  @override
  String get permissionLabel => '完全访问权限';

  @override
  String get settingsCategoryGeneral => '常规';

  @override
  String get settingsCategoryAi => 'AI';

  @override
  String get settingsCategorySkills => '技能';

  @override
  String get settingsCategoryMemory => '记忆';

  @override
  String get mcpSectionTitle => 'MCP 服务';

  @override
  String get mcpSectionBody =>
      '管理全局 MCP 开关和服务配置文件位置。服务条目的新增、更新、删除与启用状态会同步写入 MCP JSON 文件。';

  @override
  String get mcpEnabledLabel => '启用 MCP 服务';

  @override
  String get mcpEnabledBody => '关闭后不会启用 MCP 服务能力，但仍然保留已保存的服务配置。';

  @override
  String get mcpFilePathLabel => 'MCP 配置文件';

  @override
  String get mcpOpenDirectory => '打开目录';

  @override
  String get settingsGeneralTitle => '常规';

  @override
  String get settingsGeneralSubtitle => '管理主题、语言与应用基础信息。';

  @override
  String get settingsAiSubtitle => '管理聊天模型、鉴权方式与协议适配。';

  @override
  String get settingsSkillsTitle => '技能';

  @override
  String get settingsSkillsSubtitle => '管理本地技能目录、模板创建与已安装技能展示。';

  @override
  String get settingsMemorySubtitle => '管理用户记忆开关与持久化文件位置。';

  @override
  String get settingsPersistenceRecoveredTitle => '设置文件已自动恢复';

  @override
  String get settingsPersistenceRecoveredBody =>
      '检测到设置文件内容损坏或被篡改，OpenHand 已备份异常文件并恢复为安全默认值。';

  @override
  String get settingsPersistenceSanitizedTitle => '设置内容已自动修正';

  @override
  String get settingsPersistenceSanitizedBody =>
      '检测到部分设置内容无效，OpenHand 已忽略异常字段并重新写回有效配置。';

  @override
  String get settingsPersistenceSaveFailedTitle => '设置保存失败';

  @override
  String get settingsPersistenceSaveFailedBody =>
      '设置文件写入失败，界面已回滚到上一次有效配置，请检查文件权限或磁盘状态。';

  @override
  String get settingsPersistenceDismiss => '关闭提示';

  @override
  String get aiModelAdd => '新增提供商';

  @override
  String get aiModelsEmptyTitle => '还没有可用模型提供商';

  @override
  String get aiModelsEmptyBody => '先添加至少一个模型提供商配置，后续线程聊天窗口会直接复用这里的模型列表。';

  @override
  String get aiModelDialogCreateTitle => '新增模型提供商';

  @override
  String get aiModelDialogEditTitle => '编辑模型提供商';

  @override
  String get aiModelBaseUrl => 'Base URL';

  @override
  String get aiModelBaseUrlRequired => '请输入 Base URL';

  @override
  String get aiModelBaseUrlInvalid => '请输入有效的 Base URL';

  @override
  String get aiModelAuthScheme => '鉴权方式';

  @override
  String get aiModelToken => '令牌';

  @override
  String get aiModelIdField => '模型 ID';

  @override
  String get aiModelIdRequired => '请输入模型 ID';

  @override
  String get aiModelProtocol => '协议类型';

  @override
  String get aiModelSaveSuccess => '模型提供商配置已保存。';

  @override
  String get aiModelDeleteConfirmTitle => '删除模型提供商';

  @override
  String get aiModelDeleteConfirmBody => '确认删除这条模型提供商配置吗？';

  @override
  String get aiModelDeleteSuccess => '模型提供商配置已删除。';

  @override
  String get aiModelMoveUp => '上移';

  @override
  String get aiModelMoveDown => '下移';

  @override
  String get aiModelSelected => '当前活跃提供商';

  @override
  String get aiModelNoToken => '未配置令牌';

  @override
  String get aiModelTest => '测试';

  @override
  String get aiModelTesting => '测试中';

  @override
  String aiModelTestSuccess(Object modelName) {
    return '$modelName 测试通过。';
  }

  @override
  String aiModelTestFailure(Object modelName, Object reason) {
    return '$modelName 测试失败：$reason';
  }

  @override
  String get aiModelSelectionRequired => '请先在设置中添加并选择一个 AI 模型提供商。';

  @override
  String get aiModelScanButton => '扫描模型';

  @override
  String get aiModelScanning => '正在扫描可用模型…';

  @override
  String aiModelScanSuccess(Object count) {
    return '发现 $count 个模型。';
  }

  @override
  String aiModelScanFailed(Object reason) {
    return '扫描失败：$reason';
  }

  @override
  String get aiModelScanEmpty => '未从该提供商扫描到模型。';

  @override
  String get aiModelAvailableModels => '可用模型';

  @override
  String get aiModelManualIdHint => '手动输入模型 ID';

  @override
  String get aiModelManualIdAdd => '添加';

  @override
  String aiModelCount(Object count) {
    return '$count 个模型';
  }

  @override
  String get chatModelButton => '选择模型';

  @override
  String get aiAuthNone => '无';

  @override
  String get aiAuthBearer => 'Bearer';

  @override
  String get aiAuthToken => 'Token';

  @override
  String get aiAuthApiKey => 'API Key';

  @override
  String get aiProtocolOpenAi => 'OpenAI';

  @override
  String get aiProtocolClaude => 'Claude';

  @override
  String get aiProtocolGemini => 'Gemini';

  @override
  String get aiProtocolDeepSeek => 'DeepSeek';

  @override
  String get aiProtocolKimi => 'Kimi';

  @override
  String get aiProtocolGlm => 'GLM';

  @override
  String get aiProtocolGrok => 'Grok';

  @override
  String get aiProtocolOllama => 'Ollama';

  @override
  String get aiProtocolVllm => 'vLLM';

  @override
  String get aiProtocolSglang => 'SGLang';

  @override
  String get aiProtocolQwen => '通义千问';

  @override
  String get aiProtocolSeed => '豆包 (火山方舟)';

  @override
  String get aiProtocolStepFun => '阶跃星辰';

  @override
  String get aiProtocolMimo => 'MIMO (小米)';

  @override
  String get skillsPageTitle => '技能';

  @override
  String get skillsPageSubtitle => '为 OpenHand 提供更强大的扩展能力，统一管理本地已安装技能与模板。';

  @override
  String get skillsInstalledSectionTitle => '已安装';

  @override
  String get skillsSearchHint => '搜索技能';

  @override
  String get skillsRefresh => '刷新';

  @override
  String get skillsOpenDirectory => '打开目录';

  @override
  String get skillsImport => '导入技能';

  @override
  String get skillsNewSkill => '新技能';

  @override
  String get skillsEmptyTitle => '还没有安装任何技能';

  @override
  String get skillsEmptyBody => '当前技能目录中未发现任何 SKILL.md。你可以先创建模板，或切换到已有技能目录。';

  @override
  String get skillsEmptyActionCreate => '创建模板';

  @override
  String get skillsEmptyActionOpenDirectory => '打开目录';

  @override
  String get skillsNoResultsTitle => '未找到匹配的技能';

  @override
  String get skillsNoResultsBody => '尝试修改搜索关键词，或清空搜索后重新查看全部技能。';

  @override
  String get skillsFolderLabel => '存放位置';

  @override
  String get skillsCardOpen => '打开技能目录';

  @override
  String get skillTemplateCreated => '已创建新技能模板';

  @override
  String get skillOperationFailed => '技能操作失败，请稍后重试。';

  @override
  String get skillsImportSuccess => '已导入技能';

  @override
  String get skillsEdit => '编辑技能';

  @override
  String get skillsDelete => '删除技能';

  @override
  String get skillsPreviewClose => '关闭';

  @override
  String get skillsEditorLabel => 'SKILL.md 内容';

  @override
  String get skillsCreateDialogTitle => '新增技能';

  @override
  String get skillsCreateNameLabel => '技能名称';

  @override
  String get skillsCreateNameRequired => '请输入技能名称';

  @override
  String get skillsCreateIconLabel => '技能图标';

  @override
  String get skillsCreateIconHint => '请选择表情或本地图片';

  @override
  String get skillsCreateIconRequired => '请选择技能图标';

  @override
  String get skillsCreateIconChoose => '选择表情';

  @override
  String get skillsCreateIconChange => '重新选择';

  @override
  String get skillsCreateImageChoose => '选择图片';

  @override
  String get skillsCreateImageChange => '更换图片';

  @override
  String get skillsCreateImageSelected => '已选择本地图片';

  @override
  String get skillsCreateDescriptionLabel => '技能简介';

  @override
  String get skillsCreateDescriptionRequired => '请输入技能简介';

  @override
  String get skillsCreateContentRequired => '请输入 SKILL.md 内容';

  @override
  String get imageEditorTitle => '编辑图片';

  @override
  String get imageEditorCropHint => '拖动图片调整方形裁剪区域，并可继续缩放、旋转、调节亮度与对比度。';

  @override
  String get imageEditorZoomLabel => '缩放';

  @override
  String get imageEditorBrightnessLabel => '亮度';

  @override
  String get imageEditorContrastLabel => '对比度';

  @override
  String get imageEditorRotateLeft => '左转';

  @override
  String get imageEditorRotateRight => '右转';

  @override
  String get imageEditorReset => '重置';

  @override
  String get imageEditorLoadFailed => '无法加载所选图片';

  @override
  String get imageEditorProcessFailed => '无法处理所选图片';

  @override
  String get skillsEditorSave => '保存';

  @override
  String get skillsEditorCancel => '取消';

  @override
  String get skillsEditSuccess => '技能内容已保存';

  @override
  String get skillsDeleteConfirmTitle => '删除技能';

  @override
  String get skillsDeleteConfirmBody => '删除后将永久移除该技能目录及其 SKILL.md 内容。';

  @override
  String get skillsDeleteConfirmAction => '确认删除';

  @override
  String get skillsDeleteSuccess => '技能已删除';

  @override
  String get skillsStorageSectionTitle => '技能存放位置';

  @override
  String get skillsStorageSectionBody =>
      '配置 OpenHand 扫描技能的本地目录。默认会使用 ~/.openhand/skills，并在需要时自动创建。';

  @override
  String get skillsStorageDefaultPath => '默认路径';

  @override
  String get skillsStorageCurrentPath => '当前路径';

  @override
  String get skillsStorageSave => '保存位置';

  @override
  String get skillsStorageBrowse => '选择目录';

  @override
  String get skillsStorageReset => '恢复默认';

  @override
  String get skillsStorageOpen => '打开位置';

  @override
  String get skillsStorageSummaryTitle => '技能摘要';

  @override
  String get skillsStorageSummaryBody => '当前技能目录、安装数量与扫描状态会在这里实时展示。';

  @override
  String get skillsStorageStatusReady => '状态';

  @override
  String get skillsStorageStatusLoading => '扫描中';

  @override
  String get skillsStorageStatusError => '技能目录读取失败';

  @override
  String get skillsPathSaved => '技能存放位置已更新';

  @override
  String get memoryPageTitle => '记忆';

  @override
  String get memoryPageSubtitle => '统一维护用户可编辑记忆，所有条目会持久化到本地 JSON 文件。';

  @override
  String get memoryRefresh => '刷新';

  @override
  String get memoryNewEntry => '新增记忆';

  @override
  String get memoryEmptyTitle => '还没有任何用户记忆';

  @override
  String get memoryEmptyBody => '新增一条用户记忆后，它会持久化保存到当前配置的记忆文件中。';

  @override
  String get memoryLoadFailedTitle => '记忆文件读取失败';

  @override
  String get memoryOperationFailed => '记忆操作失败，请稍后重试。';

  @override
  String get memoryDialogCreateTitle => '新增用户记忆';

  @override
  String get memoryDialogEditTitle => '编辑用户记忆';

  @override
  String get memoryContentField => '记忆内容';

  @override
  String get memoryContentRequired => '请输入记忆内容';

  @override
  String get memoryTagsField => '标签';

  @override
  String get memoryTagsHint => '输入一个标签后按回车添加';

  @override
  String get memoryDeleteConfirmTitle => '删除用户记忆';

  @override
  String get memoryDeleteConfirmBody => '确认删除这条用户记忆吗？删除后无法恢复。';

  @override
  String get memoryTypeUser => '用户编辑';

  @override
  String get memoryEntryCreated => '用户记忆已创建';

  @override
  String get memoryEntryUpdated => '用户记忆已更新';

  @override
  String get memoryEntryDeleted => '用户记忆已删除';

  @override
  String get memoryEnabledLabel => '启用记忆能力';

  @override
  String get memoryEnabledBody => '关闭后不会在运行时使用用户记忆，但仍然保留已保存的记忆内容。';

  @override
  String get userMemoryFileLabel => '用户记忆文件';

  @override
  String get memoryFileBody =>
      '配置用户记忆 JSON 文件位置。默认会使用当前程序目录下的 .openhand/memory/user-memory.json。';

  @override
  String get memoryFileDefaultPath => '默认文件';

  @override
  String get memoryFileSave => '保存路径';

  @override
  String get memoryFileBrowse => '选择文件';

  @override
  String get memoryFileReset => '恢复默认';

  @override
  String get memoryOpenDirectory => '打开目录';

  @override
  String get memoryPathSaved => '用户记忆文件路径已更新';

  @override
  String get memoryDisabledTitle => '记忆能力当前已关闭';

  @override
  String get memoryDisabledBody => '你仍然可以在这里维护用户记忆内容；如需在运行时启用，请到设置页记忆板块打开记忆开关。';

  @override
  String get memoryCreatedAtLabel => '创建时间';

  @override
  String get memoryPersistenceRecoveredTitle => '记忆文件已自动恢复';

  @override
  String get memoryPersistenceRecoveredBody =>
      '检测到记忆文件内容损坏或被篡改，OpenHand 已备份异常文件并恢复为空列表。';

  @override
  String get memoryPersistenceSanitizedTitle => '记忆内容已自动修正';

  @override
  String get memoryPersistenceSanitizedBody =>
      '检测到部分记忆字段无效，OpenHand 已忽略异常条目并重新写回有效内容。';

  @override
  String get memoryPersistenceSaveFailedTitle => '记忆文件保存失败';

  @override
  String get memoryPersistenceSaveFailedBody =>
      '写入记忆文件失败，界面已回滚到上一次有效内容，请检查文件权限或磁盘状态。';

  @override
  String get mcpPageTitle => 'MCP';

  @override
  String get mcpPageSubtitle => '参考 Cursor 的 MCP 服务管理结构，统一维护本地 MCP Server 配置。';

  @override
  String get mcpRefresh => '刷新';

  @override
  String get mcpNewServer => '新增服务';

  @override
  String get mcpEmptyTitle => '还没有配置任何 MCP 服务';

  @override
  String get mcpEmptyBody =>
      '先新增一个 MCP Server，OpenHand 会把它保存到 ~/.openhand/mcp/mcp_servers.json 中。';

  @override
  String get mcpLoadFailedTitle => 'MCP 配置读取失败';

  @override
  String get mcpOperationFailed => 'MCP 操作失败，请稍后重试。';

  @override
  String get mcpDialogCreateTitle => '新增 MCP 服务';

  @override
  String get mcpDialogEditTitle => '编辑 MCP 服务';

  @override
  String get mcpNameField => '服务名称';

  @override
  String get mcpNameRequired => '请输入服务名称';

  @override
  String get mcpNameDuplicate => '服务名称已存在';

  @override
  String get mcpTypeField => '服务类型';

  @override
  String get mcpUrlField => '服务 URL';

  @override
  String get mcpUrlRequired => '请输入服务 URL';

  @override
  String get mcpUrlInvalid => '请输入有效的服务 URL';

  @override
  String get mcpCommandField => '启动命令';

  @override
  String get mcpCommandRequired => '请输入启动命令';

  @override
  String get mcpArgsField => '命令参数';

  @override
  String get mcpArgsHint => '每行一个参数';

  @override
  String get mcpServerEnabledLabel => '启用该服务';

  @override
  String get mcpServerEnabledBody => '关闭后会保留服务配置，但不会在运行时启用它。';

  @override
  String get mcpServerStatusEnabled => '已启用';

  @override
  String get mcpServerStatusDisabled => '已禁用';

  @override
  String get mcpServerCreated => 'MCP 服务已创建';

  @override
  String get mcpServerUpdated => 'MCP 服务已更新';

  @override
  String get mcpServerDeleted => 'MCP 服务已删除';

  @override
  String get mcpDeleteConfirmTitle => '删除 MCP 服务';

  @override
  String get mcpDeleteConfirmBody => '确认删除这条 MCP 服务配置吗？';

  @override
  String get mcpDisabledTitle => 'MCP 服务当前已关闭';

  @override
  String get mcpDisabledBody =>
      '你仍然可以在这里维护服务配置；如需在运行时启用，请到设置页 MCP 板块打开 MCP 开关。';

  @override
  String get mcpTransportStreamableHttp => 'Streamable HTTP';

  @override
  String get mcpTransportSse => 'SSE';

  @override
  String get mcpTransportStdio => 'STDIO';

  @override
  String get mcpPersistenceRecoveredTitle => 'MCP 配置文件已自动恢复';

  @override
  String get mcpPersistenceRecoveredBody =>
      '检测到 MCP 配置文件内容损坏或被篡改，OpenHand 已备份异常文件并恢复为空配置。';

  @override
  String get mcpPersistenceSanitizedTitle => 'MCP 配置内容已自动修正';

  @override
  String get mcpPersistenceSanitizedBody =>
      '检测到部分 MCP 服务字段无效，OpenHand 已忽略异常条目并重新写回有效配置。';

  @override
  String get mcpPersistenceSaveFailedTitle => 'MCP 配置保存失败';

  @override
  String get mcpPersistenceSaveFailedBody =>
      '写入 MCP 配置文件失败，界面已回滚到上一次有效配置，请检查文件权限或磁盘状态。';

  @override
  String get threadsEmptyBody => '当前还没有任何对话线程，创建一个新线程即可开始。';

  @override
  String get threadTemplateDialogTitle => '选择线程模板';

  @override
  String get threadTemplateDialogBody => '新建线程前，请先从下方内置能力模板中选择一个。';

  @override
  String get threadCompressionNotice =>
      '当前线程中的较早消息已被压缩为摘要检查点，以便让活跃 Prompt 保持聚焦。';

  @override
  String get threadCompressionCheckpointLabel => '摘要检查点';

  @override
  String get aiCompressionThresholdLabel => '消息压缩阈值';

  @override
  String get aiCompressionThresholdBody =>
      '当当前线程中未压缩的历史消息字符总数超过该阈值时，OpenHand 会将更早的一段消息压缩为摘要检查点，并保留最近的一段消息继续参与 Prompt 组装。';

  @override
  String get aiCompressionThresholdSave => '保存阈值';

  @override
  String get aiCompressionThresholdSaved => 'AI 消息压缩阈值已更新。';

  @override
  String get aiCompressionThresholdInvalid => '请输入有效的正整数阈值。';
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans() : super('zh_Hans');

  @override
  String get appTitle => 'OpenHand';

  @override
  String get appTagline => '开放、稳定、可扩展的桌面工作台';

  @override
  String get newThread => '新线程';

  @override
  String get automations => '自动化';

  @override
  String get skills => '技能';

  @override
  String get memory => '记忆';

  @override
  String get mcp => 'MCP';

  @override
  String get settings => '设置';

  @override
  String get threads => '线程';

  @override
  String get workspaceHeadline => '开始构建';

  @override
  String get composerHint => '询问 OpenHand 任何内容，使用 / 触发动作，使用 @ 引用上下文';

  @override
  String get composerSend => '发送';

  @override
  String get chatSending => '发送中';

  @override
  String get chatRequestFailed => '模型请求失败，请检查模型配置、网络连通性或接口协议。';

  @override
  String get composerUnavailable => '当前为基础骨架，暂未接入实际执行能力。';

  @override
  String get workspaceReadyTitle => '基础骨架已就绪';

  @override
  String get workspaceReadyBody =>
      '当前已经完成桌面端主布局、主题切换、语言切换与设置页基础能力，后续模块可以在此逐步扩展。';

  @override
  String get quickActionsTitle => '建议从这里开始';

  @override
  String get quickActionCreateShell => '创建桌面应用骨架';

  @override
  String get quickActionThemeLanguage => '配置主题与语言';

  @override
  String get quickActionPlanModules => '规划功能模块';

  @override
  String get automationHeadline => '自动化模块骨架';

  @override
  String get automationBody => '后续可在这里编排定时任务、工作流和工具链触发逻辑。';

  @override
  String get skillsHeadline => '技能中心骨架';

  @override
  String get skillsBody => '后续可在这里管理能力插件、提示模板和开发辅助工具。';

  @override
  String get placeholderComingSoon => '后续功能模块将在这里逐步扩展。';

  @override
  String get settingsTitle => '设置中心';

  @override
  String get settingsSubtitle => '在这里管理常规设置、AI 模型、MCP 服务、技能目录、记忆与应用信息。';

  @override
  String get settingsFilePathLabel => '设置文件';

  @override
  String get themeSectionTitle => '应用主题';

  @override
  String get themeSectionBody => '选择适合当前工作环境的界面亮度风格。';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get themePaletteSectionTitle => '主题配色';

  @override
  String get themePaletteSectionBody =>
      '选择全局主题配色，系统会基于该配色生成 Material 3 Expressive 主题层次。';

  @override
  String get themePresetDarkNightPurple => '暗夜紫';

  @override
  String get themePresetDeepSeaBlue => '深海蓝';

  @override
  String get themePresetMistGray => '雾霭灰';

  @override
  String get themePresetObsidianBlack => '曜石黑';

  @override
  String get themePresetPolarWhite => '极昼白';

  @override
  String get themePresetFrostMorningBlue => '霜晨蓝';

  @override
  String get themePresetDuskMountainGreen => '暮山青';

  @override
  String get themePresetNebulaPurple => '星云紫';

  @override
  String get themePresetEmberOrange => '余烬橙';

  @override
  String get themePresetTundraGreen => '苔原绿';

  @override
  String get themePresetMoonShadowSilver => '月影银';

  @override
  String get themePresetAmberGold => '琥珀金';

  @override
  String get themePresetRainyCyan => '烟雨青';

  @override
  String get themePresetGraphiteGray => '石墨灰';

  @override
  String get themePresetGlacierBlue => '冰川蓝';

  @override
  String get themePresetBlazeRed => '赤焰红';

  @override
  String get themePresetNightfallBlue => '夜幕蓝';

  @override
  String get themePresetColdMoonWhite => '冷月白';

  @override
  String get themePresetPineInk => '松烟墨';

  @override
  String get themePresetSkyCyan => '苍穹青';

  @override
  String get languageSectionTitle => '应用语言';

  @override
  String get languageSectionBody => '切换界面显示语言，保存后立即生效。';

  @override
  String get languageSimplifiedChinese => '简体中文';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get languageJapanese => '日本語';

  @override
  String get aboutSectionTitle => '关于应用';

  @override
  String get aboutSectionBody =>
      'OpenHand 当前处于基础骨架阶段，重点提供稳定的桌面应用结构、视觉基线与可扩展能力。';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutPackage => '包名';

  @override
  String get aboutPlatforms => '支持平台';

  @override
  String get aboutPlatformsValue => 'macOS 15+ / Windows 10+';

  @override
  String get aboutBuild => '构建号';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '删除';

  @override
  String get commonEdit => '编辑';

  @override
  String get previewSectionTitle => '设计方向';

  @override
  String get previewSectionBody =>
      '遵循 Material 3 Expressive 设计理念，强调层次、留白、圆角、柔和光感与清晰的信息节奏。';

  @override
  String get threadPrimary => 'OpenHand';

  @override
  String get threadShell => '桌面应用骨架';

  @override
  String get threadSettings => '设置与本地化';

  @override
  String get threadRoadmap => '后续模块规划';

  @override
  String get switchToWorkspace => '返回主工作台';

  @override
  String get modelLabel => 'OpenHand Skeleton';

  @override
  String get platformLabel => '桌面端';

  @override
  String get permissionLabel => '完全访问权限';

  @override
  String get settingsCategoryGeneral => '常规';

  @override
  String get settingsCategoryAi => 'AI';

  @override
  String get settingsCategorySkills => '技能';

  @override
  String get settingsCategoryMemory => '记忆';

  @override
  String get mcpSectionTitle => 'MCP 服务';

  @override
  String get mcpSectionBody =>
      '管理全局 MCP 开关和服务配置文件位置。服务条目的新增、更新、删除与启用状态会同步写入 MCP JSON 文件。';

  @override
  String get mcpEnabledLabel => '启用 MCP 服务';

  @override
  String get mcpEnabledBody => '关闭后不会启用 MCP 服务能力，但仍然保留已保存的服务配置。';

  @override
  String get mcpFilePathLabel => 'MCP 配置文件';

  @override
  String get mcpOpenDirectory => '打开目录';

  @override
  String get settingsGeneralTitle => '常规';

  @override
  String get settingsGeneralSubtitle => '管理主题、语言与应用基础信息。';

  @override
  String get settingsAiSubtitle => '管理聊天模型、鉴权方式与协议适配。';

  @override
  String get settingsSkillsTitle => '技能';

  @override
  String get settingsSkillsSubtitle => '管理本地技能目录、模板创建与已安装技能展示。';

  @override
  String get settingsMemorySubtitle => '管理用户记忆开关与持久化文件位置。';

  @override
  String get settingsPersistenceRecoveredTitle => '设置文件已自动恢复';

  @override
  String get settingsPersistenceRecoveredBody =>
      '检测到设置文件内容损坏或被篡改，OpenHand 已备份异常文件并恢复为安全默认值。';

  @override
  String get settingsPersistenceSanitizedTitle => '设置内容已自动修正';

  @override
  String get settingsPersistenceSanitizedBody =>
      '检测到部分设置内容无效，OpenHand 已忽略异常字段并重新写回有效配置。';

  @override
  String get settingsPersistenceSaveFailedTitle => '设置保存失败';

  @override
  String get settingsPersistenceSaveFailedBody =>
      '设置文件写入失败，界面已回滚到上一次有效配置，请检查文件权限或磁盘状态。';

  @override
  String get settingsPersistenceDismiss => '关闭提示';

  @override
  String get aiModelAdd => '新增提供商';

  @override
  String get aiModelsEmptyTitle => '还没有可用模型提供商';

  @override
  String get aiModelsEmptyBody => '先添加至少一个模型提供商配置，后续线程聊天窗口会直接复用这里的模型列表。';

  @override
  String get aiModelDialogCreateTitle => '新增模型提供商';

  @override
  String get aiModelDialogEditTitle => '编辑模型提供商';

  @override
  String get aiModelBaseUrl => 'Base URL';

  @override
  String get aiModelBaseUrlRequired => '请输入 Base URL';

  @override
  String get aiModelBaseUrlInvalid => '请输入有效的 Base URL';

  @override
  String get aiModelAuthScheme => '鉴权方式';

  @override
  String get aiModelToken => '令牌';

  @override
  String get aiModelIdField => '模型 ID';

  @override
  String get aiModelIdRequired => '请输入模型 ID';

  @override
  String get aiModelProtocol => '协议类型';

  @override
  String get aiModelSaveSuccess => '模型提供商配置已保存。';

  @override
  String get aiModelDeleteConfirmTitle => '删除模型提供商';

  @override
  String get aiModelDeleteConfirmBody => '确认删除这条模型提供商配置吗？';

  @override
  String get aiModelDeleteSuccess => '模型提供商配置已删除。';

  @override
  String get aiModelMoveUp => '上移';

  @override
  String get aiModelMoveDown => '下移';

  @override
  String get aiModelSelected => '当前活跃提供商';

  @override
  String get aiModelNoToken => '未配置令牌';

  @override
  String get aiModelTest => '测试';

  @override
  String get aiModelTesting => '测试中';

  @override
  String aiModelTestSuccess(Object modelName) {
    return '$modelName 测试通过。';
  }

  @override
  String aiModelTestFailure(Object modelName, Object reason) {
    return '$modelName 测试失败：$reason';
  }

  @override
  String get aiModelSelectionRequired => '请先在设置中添加并选择一个 AI 模型提供商。';

  @override
  String get aiModelScanButton => '扫描模型';

  @override
  String get aiModelScanning => '正在扫描可用模型…';

  @override
  String aiModelScanSuccess(Object count) {
    return '发现 $count 个模型。';
  }

  @override
  String aiModelScanFailed(Object reason) {
    return '扫描失败：$reason';
  }

  @override
  String get aiModelScanEmpty => '未从该提供商扫描到模型。';

  @override
  String get aiModelAvailableModels => '可用模型';

  @override
  String get aiModelManualIdHint => '手动输入模型 ID';

  @override
  String get aiModelManualIdAdd => '添加';

  @override
  String aiModelCount(Object count) {
    return '$count 个模型';
  }

  @override
  String get chatModelButton => '选择模型';

  @override
  String get aiAuthNone => '无';

  @override
  String get aiAuthBearer => 'Bearer';

  @override
  String get aiAuthToken => 'Token';

  @override
  String get aiAuthApiKey => 'API Key';

  @override
  String get aiProtocolOpenAi => 'OpenAI';

  @override
  String get aiProtocolClaude => 'Claude';

  @override
  String get aiProtocolGemini => 'Gemini';

  @override
  String get aiProtocolDeepSeek => 'DeepSeek';

  @override
  String get aiProtocolKimi => 'Kimi';

  @override
  String get aiProtocolGlm => 'GLM';

  @override
  String get aiProtocolGrok => 'Grok';

  @override
  String get aiProtocolOllama => 'Ollama';

  @override
  String get aiProtocolVllm => 'vLLM';

  @override
  String get aiProtocolSglang => 'SGLang';

  @override
  String get aiProtocolQwen => '通义千问';

  @override
  String get aiProtocolSeed => '豆包 (火山方舟)';

  @override
  String get aiProtocolStepFun => '阶跃星辰';

  @override
  String get aiProtocolMimo => 'MIMO (小米)';

  @override
  String get skillsPageTitle => '技能';

  @override
  String get skillsPageSubtitle => '为 OpenHand 提供更强大的扩展能力，统一管理本地已安装技能与模板。';

  @override
  String get skillsInstalledSectionTitle => '已安装';

  @override
  String get skillsSearchHint => '搜索技能';

  @override
  String get skillsRefresh => '刷新';

  @override
  String get skillsOpenDirectory => '打开目录';

  @override
  String get skillsImport => '导入技能';

  @override
  String get skillsNewSkill => '新技能';

  @override
  String get skillsEmptyTitle => '还没有安装任何技能';

  @override
  String get skillsEmptyBody => '当前技能目录中未发现任何 SKILL.md。你可以先创建模板，或切换到已有技能目录。';

  @override
  String get skillsEmptyActionCreate => '创建模板';

  @override
  String get skillsEmptyActionOpenDirectory => '打开目录';

  @override
  String get skillsNoResultsTitle => '未找到匹配的技能';

  @override
  String get skillsNoResultsBody => '尝试修改搜索关键词，或清空搜索后重新查看全部技能。';

  @override
  String get skillsFolderLabel => '存放位置';

  @override
  String get skillsCardOpen => '打开技能目录';

  @override
  String get skillTemplateCreated => '已创建新技能';

  @override
  String get skillOperationFailed => '技能操作失败，请稍后重试。';

  @override
  String get skillsImportSuccess => '已导入技能';

  @override
  String get skillsEdit => '编辑技能';

  @override
  String get skillsDelete => '删除技能';

  @override
  String get skillsPreviewClose => '关闭';

  @override
  String get skillsEditorLabel => 'SKILL.md 内容';

  @override
  String get skillsCreateDialogTitle => '新增技能';

  @override
  String get skillsCreateNameLabel => '技能名称';

  @override
  String get skillsCreateNameRequired => '请输入技能名称';

  @override
  String get skillsCreateIconLabel => '技能图标';

  @override
  String get skillsCreateIconHint => '请选择表情或本地图片';

  @override
  String get skillsCreateIconRequired => '请选择技能图标';

  @override
  String get skillsCreateIconChoose => '选择表情';

  @override
  String get skillsCreateIconChange => '重新选择';

  @override
  String get skillsCreateImageChoose => '选择图片';

  @override
  String get skillsCreateImageChange => '更换图片';

  @override
  String get skillsCreateImageSelected => '已选择本地图片';

  @override
  String get skillsCreateDescriptionLabel => '技能简介';

  @override
  String get skillsCreateDescriptionRequired => '请输入技能简介';

  @override
  String get skillsCreateContentRequired => '请输入 SKILL.md 内容';

  @override
  String get imageEditorTitle => '编辑图片';

  @override
  String get imageEditorCropHint => '拖动图片调整方形裁剪区域，并可继续缩放、旋转、调节亮度与对比度。';

  @override
  String get imageEditorZoomLabel => '缩放';

  @override
  String get imageEditorBrightnessLabel => '亮度';

  @override
  String get imageEditorContrastLabel => '对比度';

  @override
  String get imageEditorRotateLeft => '左转';

  @override
  String get imageEditorRotateRight => '右转';

  @override
  String get imageEditorReset => '重置';

  @override
  String get imageEditorLoadFailed => '无法加载所选图片';

  @override
  String get imageEditorProcessFailed => '无法处理所选图片';

  @override
  String get skillsEditorSave => '保存';

  @override
  String get skillsEditorCancel => '取消';

  @override
  String get skillsEditSuccess => '技能内容已保存';

  @override
  String get skillsDeleteConfirmTitle => '删除技能';

  @override
  String get skillsDeleteConfirmBody => '删除后将永久移除该技能目录及其 SKILL.md 内容。';

  @override
  String get skillsDeleteConfirmAction => '确认删除';

  @override
  String get skillsDeleteSuccess => '技能已删除';

  @override
  String get skillsStorageSectionTitle => '技能存放位置';

  @override
  String get skillsStorageSectionBody =>
      '配置 OpenHand 扫描技能的本地目录。默认会使用 ~/.openhand/skills，并在需要时自动创建。';

  @override
  String get skillsStorageDefaultPath => '默认路径';

  @override
  String get skillsStorageCurrentPath => '当前路径';

  @override
  String get skillsStorageSave => '保存位置';

  @override
  String get skillsStorageBrowse => '选择目录';

  @override
  String get skillsStorageReset => '恢复默认';

  @override
  String get skillsStorageOpen => '打开位置';

  @override
  String get skillsStorageSummaryTitle => '技能摘要';

  @override
  String get skillsStorageSummaryBody => '当前技能目录、安装数量与扫描状态会在这里实时展示。';

  @override
  String get skillsStorageStatusReady => '状态';

  @override
  String get skillsStorageStatusLoading => '扫描中';

  @override
  String get skillsStorageStatusError => '技能目录读取失败';

  @override
  String get skillsPathSaved => '技能存放位置已更新';

  @override
  String get memoryPageTitle => '记忆';

  @override
  String get memoryPageSubtitle => '统一维护用户可编辑记忆，所有条目会持久化到本地 JSON 文件。';

  @override
  String get memoryRefresh => '刷新';

  @override
  String get memoryNewEntry => '新增记忆';

  @override
  String get memoryEmptyTitle => '还没有任何用户记忆';

  @override
  String get memoryEmptyBody => '新增一条用户记忆后，它会持久化保存到当前配置的记忆文件中。';

  @override
  String get memoryLoadFailedTitle => '记忆文件读取失败';

  @override
  String get memoryOperationFailed => '记忆操作失败，请稍后重试。';

  @override
  String get memoryDialogCreateTitle => '新增用户记忆';

  @override
  String get memoryDialogEditTitle => '编辑用户记忆';

  @override
  String get memoryContentField => '记忆内容';

  @override
  String get memoryContentRequired => '请输入记忆内容';

  @override
  String get memoryTagsField => '标签';

  @override
  String get memoryTagsHint => '输入一个标签后按回车添加';

  @override
  String get memoryDeleteConfirmTitle => '删除用户记忆';

  @override
  String get memoryDeleteConfirmBody => '确认删除这条用户记忆吗？删除后无法恢复。';

  @override
  String get memoryTypeUser => '用户编辑';

  @override
  String get memoryEntryCreated => '用户记忆已创建';

  @override
  String get memoryEntryUpdated => '用户记忆已更新';

  @override
  String get memoryEntryDeleted => '用户记忆已删除';

  @override
  String get memoryEnabledLabel => '启用记忆能力';

  @override
  String get memoryEnabledBody => '关闭后不会在运行时使用用户记忆，但仍然保留已保存的记忆内容。';

  @override
  String get userMemoryFileLabel => '用户记忆文件';

  @override
  String get memoryFileBody =>
      '配置用户记忆 JSON 文件位置。默认会使用当前程序目录下的 .openhand/memory/user-memory.json。';

  @override
  String get memoryFileDefaultPath => '默认文件';

  @override
  String get memoryFileSave => '保存路径';

  @override
  String get memoryFileBrowse => '选择文件';

  @override
  String get memoryFileReset => '恢复默认';

  @override
  String get memoryOpenDirectory => '打开目录';

  @override
  String get memoryPathSaved => '用户记忆文件路径已更新';

  @override
  String get memoryDisabledTitle => '记忆能力当前已关闭';

  @override
  String get memoryDisabledBody => '你仍然可以在这里维护用户记忆内容；如需在运行时启用，请到设置页记忆板块打开记忆开关。';

  @override
  String get memoryCreatedAtLabel => '创建时间';

  @override
  String get memoryPersistenceRecoveredTitle => '记忆文件已自动恢复';

  @override
  String get memoryPersistenceRecoveredBody =>
      '检测到记忆文件内容损坏或被篡改，OpenHand 已备份异常文件并恢复为空列表。';

  @override
  String get memoryPersistenceSanitizedTitle => '记忆内容已自动修正';

  @override
  String get memoryPersistenceSanitizedBody =>
      '检测到部分记忆字段无效，OpenHand 已忽略异常条目并重新写回有效内容。';

  @override
  String get memoryPersistenceSaveFailedTitle => '记忆文件保存失败';

  @override
  String get memoryPersistenceSaveFailedBody =>
      '写入记忆文件失败，界面已回滚到上一次有效内容，请检查文件权限或磁盘状态。';

  @override
  String get mcpPageTitle => 'MCP';

  @override
  String get mcpPageSubtitle => '参考 Cursor 的 MCP 服务管理结构，统一维护本地 MCP Server 配置。';

  @override
  String get mcpRefresh => '刷新';

  @override
  String get mcpNewServer => '新增服务';

  @override
  String get mcpEmptyTitle => '还没有配置任何 MCP 服务';

  @override
  String get mcpEmptyBody =>
      '先新增一个 MCP Server，OpenHand 会把它保存到 ~/.openhand/mcp/mcp_servers.json 中。';

  @override
  String get mcpLoadFailedTitle => 'MCP 配置读取失败';

  @override
  String get mcpOperationFailed => 'MCP 操作失败，请稍后重试。';

  @override
  String get mcpDialogCreateTitle => '新增 MCP 服务';

  @override
  String get mcpDialogEditTitle => '编辑 MCP 服务';

  @override
  String get mcpNameField => '服务名称';

  @override
  String get mcpNameRequired => '请输入服务名称';

  @override
  String get mcpNameDuplicate => '服务名称已存在';

  @override
  String get mcpTypeField => '服务类型';

  @override
  String get mcpUrlField => '服务 URL';

  @override
  String get mcpUrlRequired => '请输入服务 URL';

  @override
  String get mcpUrlInvalid => '请输入有效的服务 URL';

  @override
  String get mcpCommandField => '启动命令';

  @override
  String get mcpCommandRequired => '请输入启动命令';

  @override
  String get mcpArgsField => '命令参数';

  @override
  String get mcpArgsHint => '每行一个参数';

  @override
  String get mcpServerEnabledLabel => '启用该服务';

  @override
  String get mcpServerEnabledBody => '关闭后会保留服务配置，但不会在运行时启用它。';

  @override
  String get mcpServerStatusEnabled => '已启用';

  @override
  String get mcpServerStatusDisabled => '已禁用';

  @override
  String get mcpServerCreated => 'MCP 服务已创建';

  @override
  String get mcpServerUpdated => 'MCP 服务已更新';

  @override
  String get mcpServerDeleted => 'MCP 服务已删除';

  @override
  String get mcpDeleteConfirmTitle => '删除 MCP 服务';

  @override
  String get mcpDeleteConfirmBody => '确认删除这条 MCP 服务配置吗？';

  @override
  String get mcpDisabledTitle => 'MCP 服务当前已关闭';

  @override
  String get mcpDisabledBody =>
      '你仍然可以在这里维护服务配置；如需在运行时启用，请到设置页 MCP 板块打开 MCP 开关。';

  @override
  String get mcpTransportStreamableHttp => 'Streamable HTTP';

  @override
  String get mcpTransportSse => 'SSE';

  @override
  String get mcpTransportStdio => 'STDIO';

  @override
  String get mcpPersistenceRecoveredTitle => 'MCP 配置文件已自动恢复';

  @override
  String get mcpPersistenceRecoveredBody =>
      '检测到 MCP 配置文件内容损坏或被篡改，OpenHand 已备份异常文件并恢复为空配置。';

  @override
  String get mcpPersistenceSanitizedTitle => 'MCP 配置内容已自动修正';

  @override
  String get mcpPersistenceSanitizedBody =>
      '检测到部分 MCP 服务字段无效，OpenHand 已忽略异常条目并重新写回有效配置。';

  @override
  String get mcpPersistenceSaveFailedTitle => 'MCP 配置保存失败';

  @override
  String get mcpPersistenceSaveFailedBody =>
      '写入 MCP 配置文件失败，界面已回滚到上一次有效配置，请检查文件权限或磁盘状态。';

  @override
  String get threadsEmptyBody => '当前还没有任何对话线程，创建一个新线程即可开始。';

  @override
  String get threadTemplateDialogTitle => '选择线程模板';

  @override
  String get threadTemplateDialogBody => '新建线程前，请先从下方内置能力模板中选择一个。';

  @override
  String get threadCompressionNotice =>
      '当前线程中的较早消息已被压缩为摘要检查点，以便让活跃 Prompt 保持聚焦。';

  @override
  String get threadCompressionCheckpointLabel => '摘要检查点';

  @override
  String get aiCompressionThresholdLabel => '消息压缩阈值';

  @override
  String get aiCompressionThresholdBody =>
      '当当前线程中未压缩的历史消息字符总数超过该阈值时，OpenHand 会将更早的一段消息压缩为摘要检查点，并保留最近的一段消息继续参与 Prompt 组装。';

  @override
  String get aiCompressionThresholdSave => '保存阈值';

  @override
  String get aiCompressionThresholdSaved => 'AI 消息压缩阈值已更新。';

  @override
  String get aiCompressionThresholdInvalid => '请输入有效的正整数阈值。';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get appTitle => 'OpenHand';

  @override
  String get appTagline => '開放、穩定、可擴展的桌面工作台';

  @override
  String get newThread => '新執行緒';

  @override
  String get automations => '自動化';

  @override
  String get skills => '技能';

  @override
  String get settings => '設定';

  @override
  String get threads => '執行緒';

  @override
  String get workspaceHeadline => '開始構建';

  @override
  String get composerHint => '詢問 OpenHand 任何內容，使用 / 觸發動作，使用 @ 引用上下文';

  @override
  String get composerSend => '送出';

  @override
  String get composerUnavailable => '目前為基礎骨架，尚未接入實際執行能力。';

  @override
  String get workspaceReadyTitle => '基礎骨架已就緒';

  @override
  String get workspaceReadyBody => '目前已完成桌面端主佈局、主題切換、語言切換與設定頁基礎能力，後續模組可在此逐步擴展。';

  @override
  String get quickActionsTitle => '建議從這裡開始';

  @override
  String get quickActionCreateShell => '建立桌面應用骨架';

  @override
  String get quickActionThemeLanguage => '配置主題與語言';

  @override
  String get quickActionPlanModules => '規劃功能模組';

  @override
  String get automationHeadline => '自動化模組骨架';

  @override
  String get automationBody => '後續可在這裡編排定時任務、工作流與工具鏈觸發邏輯。';

  @override
  String get skillsHeadline => '技能中心骨架';

  @override
  String get skillsBody => '後續可在這裡管理能力外掛、提示模板與開發輔助工具。';

  @override
  String get placeholderComingSoon => '後續功能模組將在這裡逐步擴展。';

  @override
  String get settingsTitle => '設定中心';

  @override
  String get settingsSubtitle => '在這裡管理主題、語言與應用資訊。';

  @override
  String get themeSectionTitle => '應用主題';

  @override
  String get themeSectionBody => '選擇適合目前工作環境的介面亮度風格。';

  @override
  String get themeSystem => '跟隨系統';

  @override
  String get themeLight => '淺色';

  @override
  String get themeDark => '深色';

  @override
  String get languageSectionTitle => '應用語言';

  @override
  String get languageSectionBody => '切換介面顯示語言，儲存後立即生效。';

  @override
  String get languageSimplifiedChinese => '簡體中文';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get languageJapanese => '日本語';

  @override
  String get aboutSectionTitle => '關於應用';

  @override
  String get aboutSectionBody =>
      'OpenHand 目前處於基礎骨架階段，重點提供穩定的桌面應用結構、視覺基線與可擴展能力。';

  @override
  String get aboutVersion => '版本';

  @override
  String get aboutPackage => '套件名稱';

  @override
  String get aboutPlatforms => '支援平台';

  @override
  String get aboutPlatformsValue => 'macOS 15+ / Windows 10+';

  @override
  String get aboutBuild => '建置號';

  @override
  String get previewSectionTitle => '設計方向';

  @override
  String get previewSectionBody =>
      '遵循 Material 3 Expressive 設計理念，強調層次、留白、圓角、柔和光感與清晰的資訊節奏。';

  @override
  String get threadPrimary => 'OpenHand';

  @override
  String get threadShell => '桌面應用骨架';

  @override
  String get threadSettings => '設定與在地化';

  @override
  String get threadRoadmap => '後續模組規劃';

  @override
  String get switchToWorkspace => '返回主工作台';

  @override
  String get modelLabel => 'OpenHand Skeleton';

  @override
  String get platformLabel => '桌面端';

  @override
  String get permissionLabel => '完全訪問權限';

  @override
  String get settingsCategoryGeneral => '常規';

  @override
  String get settingsCategorySkills => '技能';

  @override
  String get settingsGeneralTitle => '常規';

  @override
  String get settingsGeneralSubtitle => '管理主題、語言與應用基礎資訊。';

  @override
  String get settingsSkillsTitle => '技能';

  @override
  String get settingsSkillsSubtitle => '管理本地技能目錄、模板建立與已安裝技能展示。';

  @override
  String get skillsPageTitle => '技能';

  @override
  String get skillsPageSubtitle => '為 OpenHand 提供更強大的擴展能力，統一管理本地已安裝技能與模板。';

  @override
  String get skillsInstalledSectionTitle => '已安裝';

  @override
  String get skillsSearchHint => '搜尋技能';

  @override
  String get skillsRefresh => '重新整理';

  @override
  String get skillsOpenDirectory => '打開目錄';

  @override
  String get skillsImport => '匯入技能';

  @override
  String get skillsNewSkill => '新技能';

  @override
  String get skillsEmptyTitle => '尚未安裝任何技能';

  @override
  String get skillsEmptyBody => '目前技能目錄中未發現任何 SKILL.md。你可以先建立模板，或切換到既有技能目錄。';

  @override
  String get skillsEmptyActionCreate => '建立模板';

  @override
  String get skillsEmptyActionOpenDirectory => '打開目錄';

  @override
  String get skillsNoResultsTitle => '找不到符合條件的技能';

  @override
  String get skillsNoResultsBody => '請嘗試修改搜尋關鍵字，或清除搜尋後重新查看全部技能。';

  @override
  String get skillsFolderLabel => '存放位置';

  @override
  String get skillsCardOpen => '打開技能目錄';

  @override
  String get skillTemplateCreated => '已建立新的技能模板';

  @override
  String get skillOperationFailed => '技能操作失敗，請稍後再試。';

  @override
  String get skillsImportSuccess => '已匯入技能';

  @override
  String get skillsEdit => '編輯技能';

  @override
  String get skillsDelete => '刪除技能';

  @override
  String get skillsPreviewClose => '關閉';

  @override
  String get skillsEditorLabel => 'SKILL.md 內容';

  @override
  String get skillsEditorSave => '儲存';

  @override
  String get skillsEditorCancel => '取消';

  @override
  String get skillsEditSuccess => '技能內容已儲存';

  @override
  String get skillsDeleteConfirmTitle => '刪除技能';

  @override
  String get skillsDeleteConfirmBody => '刪除後將永久移除該技能目錄及其 SKILL.md 內容。';

  @override
  String get skillsDeleteConfirmAction => '確認刪除';

  @override
  String get skillsDeleteSuccess => '技能已刪除';

  @override
  String get skillsStorageSectionTitle => '技能存放位置';

  @override
  String get skillsStorageSectionBody =>
      '設定 OpenHand 掃描技能的本地目錄。預設會使用 ~/.openhand/skills，並在需要時自動建立。';

  @override
  String get skillsStorageDefaultPath => '預設路徑';

  @override
  String get skillsStorageCurrentPath => '目前路徑';

  @override
  String get skillsStorageSave => '儲存位置';

  @override
  String get skillsStorageBrowse => '選擇目錄';

  @override
  String get skillsStorageReset => '恢復預設';

  @override
  String get skillsStorageOpen => '打開位置';

  @override
  String get skillsStorageSummaryTitle => '技能摘要';

  @override
  String get skillsStorageSummaryBody => '目前技能目錄、安裝數量與掃描狀態會在這裡即時顯示。';

  @override
  String get skillsStorageStatusReady => '狀態';

  @override
  String get skillsStorageStatusLoading => '掃描中';

  @override
  String get skillsStorageStatusError => '技能目錄讀取失敗';

  @override
  String get skillsPathSaved => '技能存放位置已更新';

  @override
  String get threadsEmptyBody => '目前還沒有任何對話執行緒，建立一個新執行緒即可開始。';

  @override
  String get threadTemplateDialogTitle => '選擇執行緒模板';

  @override
  String get threadTemplateDialogBody => '建立新執行緒前，請先從下方內建能力模板中選擇一個。';

  @override
  String get threadCompressionNotice =>
      '目前執行緒中較早的訊息已被壓縮為摘要檢查點，讓活躍 Prompt 保持聚焦。';

  @override
  String get threadCompressionCheckpointLabel => '摘要檢查點';

  @override
  String get aiCompressionThresholdLabel => '訊息壓縮閾值';

  @override
  String get aiCompressionThresholdBody =>
      '當目前執行緒中未壓縮的歷史訊息字元總數超過此閾值時，OpenHand 會將更早的一段訊息壓縮為摘要檢查點，並保留最近的一段訊息繼續參與 Prompt 組裝。';

  @override
  String get aiCompressionThresholdSave => '儲存閾值';

  @override
  String get aiCompressionThresholdSaved => 'AI 訊息壓縮閾值已更新。';

  @override
  String get aiCompressionThresholdInvalid => '請輸入有效的正整數閾值。';
}
