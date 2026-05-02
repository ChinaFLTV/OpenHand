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
  String get aiProtocolMinimax => 'MiniMax';

  @override
  String get aiProtocolLongCat => 'LongCat';

  @override
  String get aiProtocolJoyCode => 'JoyCode';

  @override
  String get aiProtocolWenxin => '文心一言 (ERNIE)';

  @override
  String get aiProtocolMeta => 'Meta AI (Llama)';

  @override
  String get aiProtocolMimo => 'MIMO (小米)';

  @override
  String get aiProtocolHunyuan => '混元 (腾讯)';

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
  String get imageEditorCropHint =>
      '拖动方框调整裁剪区域，可继续缩放、旋转、翻转，展开下方面板可使用 HSL、色调分离、清晰度、颗粒、降噪、色散、扭曲、水印等高级调整（高级调整在保存时应用）。';

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
  String get imageEditorSectionBasic => '基础调整';

  @override
  String get imageEditorSectionColor => '色彩（色温 / 色调 / 伽马）';

  @override
  String get imageEditorSectionSplitToning => '色调分离（HSL）';

  @override
  String get imageEditorSectionDetail => '细节（清晰度 / 锐度 / 降噪 / 颗粒）';

  @override
  String get imageEditorSectionEffects => '特效（色散 / 扭曲 / 晕影）';

  @override
  String get imageEditorSectionWatermark => '文字水印 / 标记';

  @override
  String get imageEditorTemperatureLabel => '色温';

  @override
  String get imageEditorTintLabel => '色调偏移';

  @override
  String get imageEditorGammaLabel => '伽马（曲线）';

  @override
  String get imageEditorShadowHueLabel => '暗部色相';

  @override
  String get imageEditorShadowStrengthLabel => '暗部强度';

  @override
  String get imageEditorHighlightHueLabel => '亮部色相';

  @override
  String get imageEditorHighlightStrengthLabel => '亮部强度';

  @override
  String get imageEditorClarityLabel => '清晰度';

  @override
  String get imageEditorSharpnessLabel => '锐度';

  @override
  String get imageEditorDenoiseLabel => '降噪';

  @override
  String get imageEditorGrainLabel => '颗粒';

  @override
  String get imageEditorDispersionLabel => '色散';

  @override
  String get imageEditorDistortLabel => '扭曲（正值凸出 / 负值拉伸）';

  @override
  String get imageEditorWatermarkTextLabel => '水印文字';

  @override
  String get imageEditorWatermarkTextHint => '输入要叠加的文字（留空则不添加）';

  @override
  String get imageEditorWatermarkSizeLabel => '文字大小';

  @override
  String get imageEditorWatermarkOpacityLabel => '不透明度';

  @override
  String get imageEditorWatermarkPositionLabel => '位置';

  @override
  String get imageEditorWatermarkColorLight => '浅色';

  @override
  String get imageEditorWatermarkColorDark => '深色';

  @override
  String get imageEditorAdvancedApplyHint => '展开面板中的调整会在“保存”时一次性应用到原图。';

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
  String get instructionPageTitle => '指令';

  @override
  String get instructionPageSubtitle =>
      '维护应用内的可复用提示词片段。启用的指令会按当前顺序注入到所有线程模板的 system prompt，并在会话输入框上方以胶囊形式列出，可在单次发送前临时取消或重新加入。';

  @override
  String get instructionRefresh => '刷新';

  @override
  String get instructionNewEntry => '新建指令';

  @override
  String get instructionEmptyTitle => '尚未创建指令';

  @override
  String get instructionEmptyBody => '新建第一条可复用指令后，OpenHand 会把它保存到本地指令库中。';

  @override
  String get instructionLoadFailedTitle => '指令库读取失败';

  @override
  String get instructionDeleteConfirmTitle => '删除指令';

  @override
  String get instructionDeleteConfirmBody => '确认删除这条指令吗？删除后无法恢复。';

  @override
  String get instructionEnabledStatus => '已启用并注入';

  @override
  String get instructionDisabledStatus => '已停用';

  @override
  String get instructionApplyToChipLabel => '适用';

  @override
  String get instructionNotesChipLabel => '备注';

  @override
  String get instructionDialogCreateTitle => '新建指令';

  @override
  String get instructionDialogEditTitle => '编辑指令';

  @override
  String get instructionEnabledLabel => '启用';

  @override
  String get instructionEnabledBody => '将这条指令注入到当前提示链中。';

  @override
  String get instructionNameField => '名称 *';

  @override
  String get instructionNameRequired => '请输入名称。';

  @override
  String get instructionDescriptionField => '描述';

  @override
  String get instructionVersionField => '版本';

  @override
  String get instructionApplyToField => '适用范围（描述何时加载这条指令）';

  @override
  String get instructionTaskTypesField => '触发任务类型（逗号分隔）';

  @override
  String get instructionKeywordsField => '触发关键词（逗号分隔）';

  @override
  String get instructionNotesField => '备注（每行一条）';

  @override
  String get instructionBodyField => '指令正文 *（Markdown）';

  @override
  String get instructionBodyRequired => '请输入指令正文。';

  @override
  String get instructionCreateAction => '创建';

  @override
  String get instructionSaveFailed => '保存失败，请检查必填项是否为空。';

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

  @override
  String get aiToolResultCompressionThresholdLabel => '工具调用输出压缩阈值';

  @override
  String get aiToolResultCompressionThresholdBody =>
      '当某个工具调用返回的 raw 内容字符数超过该阈值时，OpenHand 会在拼装 conversation history 前将其压缩为“受影响路径+目的+首尾片段”的结构化摘要，释放 tokens。默认 1024。';

  @override
  String get aiToolResultCompressionThresholdSave => '保存阈值';

  @override
  String get aiToolResultCompressionThresholdSaved => '工具调用输出压缩阈值已更新。';

  @override
  String get aiToolResultCompressionThresholdInvalid => '请输入有效的正整数阈值。';

  @override
  String get aiToolResultCompressionEnabledLabel => '启用工具调用输出压缩';

  @override
  String get aiToolResultCompressionEnabledBody =>
      '总开关。关闭后不论阈值多大都不压缩工具输出原文，适合需要调试完整输出的场景。';

  @override
  String get aiToolResultCompressionHeadTailWindowLabel => '压缩摘要首尾片段窗口';

  @override
  String get aiToolResultCompressionHeadTailWindowBody =>
      '压缩后摘要中保留 raw 输出首尾各多少个字符。默认 256；0 表示不保留首尾片段；范围 0~8192。';

  @override
  String get aiToolResultCompressionHeadTailWindowSave => '保存窗口长度';

  @override
  String get aiToolResultCompressionHeadTailWindowSaved => '首尾片段窗口已更新。';

  @override
  String get aiToolResultCompressionHeadTailWindowInvalid =>
      '请输入 0~8192 之间的整数。';

  @override
  String get aiToolResultCompressionMaxPathHitsLabel => '压缩摘要提取路径上限';

  @override
  String get aiToolResultCompressionMaxPathHitsBody =>
      '压缩后摘要中提取受影响文件路径的最大条数。默认 12；0 表示不提取；范围 0~200。';

  @override
  String get aiToolResultCompressionMaxPathHitsSave => '保存上限';

  @override
  String get aiToolResultCompressionMaxPathHitsSaved => '路径提取上限已更新。';

  @override
  String get aiToolResultCompressionMaxPathHitsInvalid => '请输入 0~200 之间的整数。';

  @override
  String get aiWriteToolSummaryMaxCharsLabel => '写类工具摘要字符上限';

  @override
  String get aiWriteToolSummaryMaxCharsBody =>
      '写类工具（write/edit/multiedit/notebookedit/写型 bash）结果摘要中保留 result_text 原文的最大字符数。默认 280；0 表示不保留；范围 0~8192。';

  @override
  String get aiWriteToolSummaryMaxCharsSave => '保存上限';

  @override
  String get aiWriteToolSummaryMaxCharsSaved => '写类工具摘要字符上限已更新。';

  @override
  String get aiWriteToolSummaryMaxCharsInvalid => '请输入 0~8192 之间的整数。';

  @override
  String get aiMaxRecentErrorsLabel => '会话错误记录保留上限';

  @override
  String get aiMaxRecentErrorsBody => 'AI 会话状态中保留的最近错误记录条数。默认 15；范围 0~1000。';

  @override
  String get aiMaxRecentErrorsSave => '保存上限';

  @override
  String get aiMaxRecentErrorsSaved => '会话错误记录保留上限已更新。';

  @override
  String get aiMaxRecentErrorsInvalid => '请输入 0~1000 之间的整数。';

  @override
  String get aiMaxPlanHistoryEntriesLabel => '计划历史保留上限';

  @override
  String get aiMaxPlanHistoryEntriesBody =>
      'Plan 模式下 plan_history 保留的最大条目数。默认 15；范围 0~1000。';

  @override
  String get aiMaxPlanHistoryEntriesSave => '保存上限';

  @override
  String get aiMaxPlanHistoryEntriesSaved => '计划历史保留上限已更新。';

  @override
  String get aiMaxPlanHistoryEntriesInvalid => '请输入 0~1000 之间的整数。';

  @override
  String get aiMaxTruncationContinuationsLabel => '自动续接轮次上限';

  @override
  String get aiMaxTruncationContinuationsBody =>
      '模型输出被截断（finish_reason=length）后自动续接的最大次数。默认 5；范围 0~100。';

  @override
  String get aiMaxTruncationContinuationsSave => '保存上限';

  @override
  String get aiMaxTruncationContinuationsSaved => '自动续接轮次上限已更新。';

  @override
  String get aiMaxTruncationContinuationsInvalid => '请输入 0~100 之间的整数。';

  @override
  String get aiEstimatedCharactersPerTokenLabel => 'Token 字符估算系数';

  @override
  String get aiEstimatedCharactersPerTokenBody =>
      '每个 token 约等于多少个字符，用于上下文容量估算。默认 4；范围 1~32。';

  @override
  String get aiEstimatedCharactersPerTokenSave => '保存系数';

  @override
  String get aiEstimatedCharactersPerTokenSaved => 'Token 字符估算系数已更新。';

  @override
  String get aiEstimatedCharactersPerTokenInvalid => '请输入 1~32 之间的整数。';

  @override
  String get aiMaxToolOutputCharsLabel => '工具单次输出字符上限';

  @override
  String get aiMaxToolOutputCharsBody =>
      '默认 150000。单次工具调用结果若超过这个字符数会截断，避免 Context 溢出。';

  @override
  String get aiMaxToolOutputCharsSave => '保存上限';

  @override
  String get aiMaxToolOutputCharsSaved => '工具输出字符上限已保存。';

  @override
  String get aiMaxToolOutputCharsInvalid => '请输入 1000~10000000 之间的整数。';

  @override
  String get aiWriteConfirmationTimeoutMsLabel => '写命令确认超时（毫秒）';

  @override
  String get aiWriteConfirmationTimeoutMsBody =>
      '默认 300000（5 分钟）。等待用户审批写命令的最长时间。';

  @override
  String get aiWriteConfirmationTimeoutMsSave => '保存超时';

  @override
  String get aiWriteConfirmationTimeoutMsSaved => '写命令确认超时已保存。';

  @override
  String get aiWriteConfirmationTimeoutMsInvalid => '请输入 1000~3600000 之间的整数。';

  @override
  String get aiFastPathWriteAnalysisThresholdLabel => 'Fast-path 写命令分析阈值';

  @override
  String get aiFastPathWriteAnalysisThresholdBody =>
      '默认 512 字符。命令长度超过此值会走快速路径粗判，避免昂贵的语法分析。';

  @override
  String get aiFastPathWriteAnalysisThresholdSave => '保存阈值';

  @override
  String get aiFastPathWriteAnalysisThresholdSaved => 'Fast-path 阈值已保存。';

  @override
  String get aiFastPathWriteAnalysisThresholdInvalid => '请输入 0~100000 之间的整数。';

  @override
  String get aiMaxHookTextCharactersLabel => 'Hook 文本输出上限';

  @override
  String get aiMaxHookTextCharactersBody =>
      '默认 4000。Claude Hook 在合并 stdout/stderr 文本时的总字符上限。';

  @override
  String get aiMaxHookTextCharactersSave => '保存上限';

  @override
  String get aiMaxHookTextCharactersSaved => 'Hook 文本上限已保存。';

  @override
  String get aiMaxHookTextCharactersInvalid => '请输入 100~1000000 之间的整数。';

  @override
  String get aiWebFetchMaxResponseBytesLabel => 'WebFetch 单次响应字节上限';

  @override
  String get aiWebFetchMaxResponseBytesBody =>
      '默认 1048576（1MB）。调整以适配你的网络与附件需求。';

  @override
  String get aiWebFetchMaxResponseBytesSave => '保存';

  @override
  String get aiWebFetchMaxResponseBytesSaved => 'WebFetch 单次响应字节上限已保存。';

  @override
  String get aiWebFetchMaxResponseBytesInvalid => '请输入有效整数。';

  @override
  String get aiWebFetchMaxRedirectsLabel => 'WebFetch 最大重定向次数';

  @override
  String get aiWebFetchMaxRedirectsBody => '默认 5。调整以适配你的网络与附件需求。';

  @override
  String get aiWebFetchMaxRedirectsSave => '保存';

  @override
  String get aiWebFetchMaxRedirectsSaved => 'WebFetch 最大重定向次数已保存。';

  @override
  String get aiWebFetchMaxRedirectsInvalid => '请输入有效整数。';

  @override
  String get aiWebFetchMaxCacheEntriesLabel => 'WebFetch 缓存条目上限';

  @override
  String get aiWebFetchMaxCacheEntriesBody => '默认 64。调整以适配你的网络与附件需求。';

  @override
  String get aiWebFetchMaxCacheEntriesSave => '保存';

  @override
  String get aiWebFetchMaxCacheEntriesSaved => 'WebFetch 缓存条目上限已保存。';

  @override
  String get aiWebFetchMaxCacheEntriesInvalid => '请输入有效整数。';

  @override
  String get aiAttachmentMaxInlineImageDimensionLabel => '附件图片最大边长（像素）';

  @override
  String get aiAttachmentMaxInlineImageDimensionBody =>
      '默认 1568。调整以适配你的网络与附件需求。';

  @override
  String get aiAttachmentMaxInlineImageDimensionSave => '保存';

  @override
  String get aiAttachmentMaxInlineImageDimensionSaved => '附件图片最大边长（像素）已保存。';

  @override
  String get aiAttachmentMaxInlineImageDimensionInvalid => '请输入有效整数。';

  @override
  String get aiAttachmentMaxTextRawBytesLabel => '附件文本读取上限（字节）';

  @override
  String get aiAttachmentMaxTextRawBytesBody =>
      '默认 1597152（2MB）。调整以适配你的网络与附件需求。';

  @override
  String get aiAttachmentMaxTextRawBytesSave => '保存';

  @override
  String get aiAttachmentMaxTextRawBytesSaved => '附件文本读取上限（字节）已保存。';

  @override
  String get aiAttachmentMaxTextRawBytesInvalid => '请输入有效整数。';

  @override
  String get aiAttachmentMaxPdfRawBytesLabel => '附件 PDF 读取上限（字节）';

  @override
  String get aiAttachmentMaxPdfRawBytesBody =>
      '默认 1597152（2MB）。调整以适配你的网络与附件需求。';

  @override
  String get aiAttachmentMaxPdfRawBytesSave => '保存';

  @override
  String get aiAttachmentMaxPdfRawBytesSaved => '附件 PDF 读取上限（字节）已保存。';

  @override
  String get aiAttachmentMaxPdfRawBytesInvalid => '请输入有效整数。';

  @override
  String get aiAttachmentMaxImageRawBytesLabel => '附件图片读取上限（字节）';

  @override
  String get aiAttachmentMaxImageRawBytesBody =>
      '默认 52428800（50MB）。调整以适配你的网络与附件需求。';

  @override
  String get aiAttachmentMaxImageRawBytesSave => '保存';

  @override
  String get aiAttachmentMaxImageRawBytesSaved => '附件图片读取上限（字节）已保存。';

  @override
  String get aiAttachmentMaxImageRawBytesInvalid => '请输入有效整数。';

  @override
  String get aiChatMaxStreamLineBufferBytesLabel => 'Chat 流缓冲字节上限';

  @override
  String get aiChatMaxStreamLineBufferBytesBody =>
      '默认 4194304（4MB）。调整以适配你的网络与附件需求。';

  @override
  String get aiChatMaxStreamLineBufferBytesSave => '保存';

  @override
  String get aiChatMaxStreamLineBufferBytesSaved => 'Chat 流缓冲字节上限已保存。';

  @override
  String get aiChatMaxStreamLineBufferBytesInvalid => '请输入有效整数。';

  @override
  String get aiFallbackTitleMaxCharactersLabel => '回退标题最大字符数';

  @override
  String get aiFallbackTitleMaxCharactersBody => '默认 15。调整以匹配会话标题派生策略。';

  @override
  String get aiFallbackTitleMaxCharactersSave => '保存';

  @override
  String get aiFallbackTitleMaxCharactersSaved => '回退标题最大字符数已保存。';

  @override
  String get aiFallbackTitleMaxCharactersInvalid => '请输入有效整数。';

  @override
  String get aiGeneratedTitleMaxCharactersLabel => '自动标题最大字符数';

  @override
  String get aiGeneratedTitleMaxCharactersBody => '默认 15。调整以匹配会话标题派生策略。';

  @override
  String get aiGeneratedTitleMaxCharactersSave => '保存';

  @override
  String get aiGeneratedTitleMaxCharactersSaved => '自动标题最大字符数已保存。';

  @override
  String get aiGeneratedTitleMaxCharactersInvalid => '请输入有效整数。';

  @override
  String get aiMinimumMeaningfulTitleCharactersLabel => '中文有效标题最小字符数';

  @override
  String get aiMinimumMeaningfulTitleCharactersBody => '默认 4。调整以匹配会话标题派生策略。';

  @override
  String get aiMinimumMeaningfulTitleCharactersSave => '保存';

  @override
  String get aiMinimumMeaningfulTitleCharactersSaved => '中文有效标题最小字符数已保存。';

  @override
  String get aiMinimumMeaningfulTitleCharactersInvalid => '请输入有效整数。';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsLabel => '拉丁有效标题最小词数';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsBody => '默认 2。调整以匹配会话标题派生策略。';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsSave => '保存';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsSaved => '拉丁有效标题最小词数已保存。';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsInvalid => '请输入有效整数。';

  @override
  String get aiMaxSkillContentLengthLabel => '技能文件内容字符上限';

  @override
  String get aiMaxSkillContentLengthBody => '默认 100000。调整以适配技能与工作区文档大小。';

  @override
  String get aiMaxSkillContentLengthSave => '保存';

  @override
  String get aiMaxSkillContentLengthSaved => '技能文件内容字符上限已保存。';

  @override
  String get aiMaxSkillContentLengthInvalid => '请输入有效整数。';

  @override
  String get aiMaxWorkspaceDocumentCharactersLabel => '工作区指令文档字符上限';

  @override
  String get aiMaxWorkspaceDocumentCharactersBody =>
      '默认 16000。调整以适配技能与工作区文档大小。';

  @override
  String get aiMaxWorkspaceDocumentCharactersSave => '保存';

  @override
  String get aiMaxWorkspaceDocumentCharactersSaved => '工作区指令文档字符上限已保存。';

  @override
  String get aiMaxWorkspaceDocumentCharactersInvalid => '请输入有效整数。';

  @override
  String get aiImageSizeLimitLabel => '图片大小上限';

  @override
  String get aiImageSizeLimitBody =>
      '当用户添加的图片附件超过该上限时，OpenHand 会自动按质量 + 尺寸两级压缩后再发送。支持小数 MB；范围 0.0625 MB（64 KB）至 64 MB。';

  @override
  String get aiImageSizeLimitFieldLabel => '上限 (MB)';

  @override
  String get aiImageSizeLimitSave => '保存上限';

  @override
  String get aiImageSizeLimitSaved => '图片附件大小上限已更新。';

  @override
  String get aiImageSizeLimitInvalid => '请输入有效的正数 MB 值。';

  @override
  String get imageEditorAspectFree => '自由';

  @override
  String get imageEditorAspectOriginal => '原始';

  @override
  String get imageEditorAspectSquare => '1:1';

  @override
  String get imageEditorAspect4x3 => '4:3';

  @override
  String get imageEditorAspect3x4 => '3:4';

  @override
  String get imageEditorAspect16x9 => '16:9';

  @override
  String get imageEditorAspect9x16 => '9:16';

  @override
  String get imageEditorAspectCircle => '圆形';

  @override
  String get imageEditorFlipHorizontal => '水平翻转';

  @override
  String get imageEditorFlipVertical => '垂直翻转';

  @override
  String get imageEditorSaturationLabel => '饱和度';

  @override
  String get imageEditorExposureLabel => '曝光';

  @override
  String get imageEditorHueLabel => '色相';

  @override
  String get imageEditorVignetteLabel => '暗角';

  @override
  String get imageEditorFineRotationLabel => '微调旋转 (°)';

  @override
  String get imageEditorSaveToFile => '另存到本地';

  @override
  String get imageEditorCopyToClipboard => '复制到剪贴板';

  @override
  String imageEditorSavedTo(String path) {
    return '已另存：$path';
  }

  @override
  String imageEditorSaveFailed(String error) {
    return '另存失败：$error';
  }

  @override
  String get imageEditorClipboardCopiedBitmap => '已复制图片到剪贴板（文件路径同时复制为文本）。';

  @override
  String imageEditorClipboardCopiedPath(String path) {
    return '已复制图片文件路径到剪贴板：$path';
  }

  @override
  String imageEditorClipboardFailed(String error) {
    return '复制失败：$error';
  }

  @override
  String get imageEditorApplyButton => '应用';

  @override
  String get imageEditorUndoButton => '回退';

  @override
  String get imageEditorResetAllButton => '重置全部';

  @override
  String get imageEditorCompareHold => '按住对比';

  @override
  String get imageEditorCompareRelease => '松开返回';

  @override
  String get imageEditorCompareOriginal => '原图';

  @override
  String get imageEditorWatermarkColorLabel => '文字颜色';

  @override
  String get imageEditorWatermarkColorHue => '颜色（Hue）';

  @override
  String get imageEditorWatermarkColorSaturation => '饱和度';

  @override
  String get imageEditorWatermarkColorLightness => '明度';

  @override
  String get imageEditorApplySuccess => '调整已应用';

  @override
  String get imageEditorProcessing => '处理中…';

  @override
  String get builtinToolTimeoutLabel => '超时时间（秒）';

  @override
  String builtinToolTimeoutHint(int seconds) {
    return '默认 ${seconds}s';
  }

  @override
  String builtinToolTimeoutHelper(int seconds) {
    return '留空则使用默认 ${seconds}s';
  }

  @override
  String get builtinToolRetryLabel => '失败/超时自动重试';

  @override
  String get builtinToolRetryBody =>
      '默认关闭。仅对真正失败 (failed/timed_out) 触发，不会重试参数错误或被拒绝的调用。';

  @override
  String builtinToolMaxRetriesLabel(int max) {
    return '最大重试次数 (0–$max)';
  }

  @override
  String builtinToolMaxRetriesHelper(int max) {
    return '不含首次执行；上限 $max 次';
  }

  @override
  String get builtinToolBackoffLabel => '重试退避基线（毫秒）';

  @override
  String builtinToolBackoffHint(int ms) {
    return '默认 ${ms}ms';
  }

  @override
  String builtinToolBackoffHelper(int max) {
    return '指数退避：第 N 次重试等待 base × 2^(N-1)ms，上限 ${max}ms';
  }

  @override
  String selfLearningFlushIntervalLabel(int ms) {
    return '流式刷新间隔：${ms}ms';
  }

  @override
  String selfLearningFlushIntervalHelper(int min, int max) {
    return '自我学习卡片流式输出的持久化间隔（$min–${max}ms）。调小=更实时但更多布局抖动；调大=更平滑但增量延迟更高。默认 600ms。';
  }

  @override
  String get tsmRenameThreadTitle => '重命名线程';

  @override
  String get tsmRenameHint => '输入线程标题';

  @override
  String get tsmRenameFailed => '重命名失败';

  @override
  String get tsmDeleteThreadTitle => '删除线程';

  @override
  String get tsmDeleteSelectedTitle => '删除所选线程';

  @override
  String tsmDeleteSelectedConfirm(Object count) {
    return '将永久删除 $count 个线程及其消息。此操作无法撤销。';
  }

  @override
  String tsmDeleteFailedCount(Object count) {
    return '$count 个线程删除失败';
  }

  @override
  String get tsmSessionMissing => '会话不存在或已被删除';

  @override
  String get tsmExportSessionDataTitle => '导出会话数据';

  @override
  String tsmExportingSession(Object title) {
    return '正在导出 “$title”…';
  }

  @override
  String get tsmExportComplete => '导出完成';

  @override
  String get tsmExportFailed => '导出失败';

  @override
  String get tsmChooseExportFolder => '选择导出目录';

  @override
  String get tsmBatchExportTitle => '批量导出';

  @override
  String tsmBatchExportSubtitle(Object count) {
    return '即将导出 $count 个线程…';
  }

  @override
  String tsmBatchExportDone(Object ok, Object failed) {
    return '批量导出完成：成功 $ok / 失败 $failed';
  }

  @override
  String get tsmMenuPreview => '预览';

  @override
  String get tsmMenuRename => '重命名';

  @override
  String get tsmMenuExportSession => '导出会话数据';

  @override
  String get tsmMenuPin => '置顶';

  @override
  String get tsmMenuUnpin => '取消置顶';

  @override
  String get tsmMenuArchive => '归档';

  @override
  String get tsmMenuUnarchive => '取消归档';

  @override
  String get tsmMenuDelete => '删除';

  @override
  String get tsmPinUpdateFailed => '置顶状态更新失败';

  @override
  String get tsmArchiveUpdateFailed => '归档状态更新失败';

  @override
  String get tsmUntitledThread => '(未命名线程)';

  @override
  String tsmPreviewMessageCount(Object count) {
    return '$count 条消息';
  }

  @override
  String get tsmClosePreview => '关闭预览';

  @override
  String get tsmNoMessages => '暂无消息';

  @override
  String get tsmEmptyMessage => '(空消息)';

  @override
  String get tsmSearchHint => '按标题或 ID 搜索';

  @override
  String get tsmDensityComfortable => '舒适密度';

  @override
  String get tsmDensityCompact => '紧凑密度';

  @override
  String get tsmAllTemplates => '全部模板';

  @override
  String tsmSortDisabledHint(Object mode) {
    return '当前为「$mode」排序，拖拽手柄已禁用，切回「手动顺序」可继续调整。';
  }

  @override
  String get tsmSortManual => '手动顺序';

  @override
  String get tsmSortUpdated => '最近更新';

  @override
  String get tsmSortCreated => '最近创建';

  @override
  String get tsmSortSize => '占用大小';

  @override
  String get tsmSortMessages => '消息数量';

  @override
  String get tsmSortToken => 'Token 数';

  @override
  String get tsmHideArchived => '隐藏归档';

  @override
  String get tsmShowArchived => '显示归档';

  @override
  String get tsmExitSelection => '退出多选';

  @override
  String get tsmEnterSelection => '多选';

  @override
  String get tsmClose => '关闭';

  @override
  String get tsmTitle => '线程会话管理';

  @override
  String tsmHeaderSubtitle(Object count) {
    return '共 $count 个线程 · 长按或拖拽手柄可调整顺序，双击/右键查看更多操作';
  }

  @override
  String tsmSelectedCount(Object count) {
    return '已选 $count';
  }

  @override
  String get tsmBatchExportButton => '批量导出';

  @override
  String get tsmDeleteSelectedButton => '删除所选';

  @override
  String get tsmEmptyState => '暂无线程会话';

  @override
  String get tsmCancel => '取消';

  @override
  String get settingsThreadSessionManagementTitle => '线程会话管理';

  @override
  String get settingsThreadSessionManagementSubtitle =>
      '查看所有线程的标题、创建/更新时间、占用大小、消息构成和 token 统计。支持拖拽排序、多选删除、双击或右键打开重命名/导出/删除菜单。弹窗的进出场动画跟随全局设置中的弹窗动画配置。';

  @override
  String get settingsThreadSessionManagementOpen => '打开管理弹窗';

  @override
  String get settingsMessageGatewayTitle => '消息网关';

  @override
  String get settingsMessageGatewayDescription =>
      '管理消息网关的路由、转换与节流策略。具体配置项将在后续版本中开放，当前为预留入口。';

  @override
  String get settingsMessageGatewayComingSoon => '即将推出';

  @override
  String get settingsMessageGatewayComingSoonSubtitle => '消息网关详细配置将在下一个迭代中提供。';

  @override
  String get tsmRowUnknown => '未知';

  @override
  String get tsmRowCreated => '创建';

  @override
  String get tsmRowUpdated => '更新';

  @override
  String get tsmRowSize => '占用';

  @override
  String get tsmRowMessages => '消息';

  @override
  String get tsmRowToken => 'Token';

  @override
  String get tsmRowByKind => '占比';

  @override
  String get proxySectionTitle => '系统';

  @override
  String get proxySectionBody =>
      '所有 OpenHand 内建 HTTP 客户端（WebSearch / WebFetch 等）将按此处代理设置选择路由。保存后即时生效，无需重启。';

  @override
  String get proxyModeLabel => '代理模式';

  @override
  String get proxyModeBody =>
      '决定 OpenHand 内置 HTTP 客户端（WebSearch / WebFetch 等）如何选择代理。';

  @override
  String get proxyModeDisabled => '无代理';

  @override
  String get proxyModeAutomatic => '自动发现代理（默认）';

  @override
  String get proxyModeManual => '手动配置代理';

  @override
  String get proxyProtocolsLabel => '代理协议';

  @override
  String get proxyProtocolsBody => '可多选，至少保留一个；取消所有协议时会自动恢复 HTTP + HTTPS。';

  @override
  String get proxyHostLabel => '服务器（IP 或主机名）';

  @override
  String get proxyPortLabel => '端口号';

  @override
  String get proxyAuthLabel => '开启代理服务器鉴权';

  @override
  String get proxyAuthBody => '开启后下面的用户名 / 密码字段才会被使用（HTTP Basic）。';

  @override
  String get proxyUsernameLabel => '用户名';

  @override
  String get proxyPasswordLabel => '密码';

  @override
  String get proxyExceptionsLabel => '忽略这些主机与域的代理设置';

  @override
  String get proxyExceptionsBody =>
      '每行一条。支持：IP 地址（127.0.0.1）、IPv4 CIDR（192.168.0.0/16）、域名（example.com 含子域）、glob（*.example.com）、正则（/^api\\d+\\.example\\.com\$/i）。localhost / 127.0.0.1 / ::1 始终走直连。';

  @override
  String get proxyExceptionsHint =>
      '示例：\n*.local\n10.0.0.0/8\n/^api\\d+\\.example\\.com\$/i';

  @override
  String get proxyTestButton => '测试代理连通性';

  @override
  String get proxyTesting => '测试中…';

  @override
  String proxyTestSuccess(Object latency, Object via) {
    return '连通成功（$latency ms，via $via）';
  }

  @override
  String proxyTestFailure(Object reason) {
    return '连通失败：$reason';
  }

  @override
  String get proxyTestEndpointLabel => '测试 URL';

  @override
  String get proxyTestEndpointHint => '默认：https://www.google.com/generate_204';

  @override
  String get proxyTestVerdictDirect => '直连';

  @override
  String proxyTestVerdictProxy(Object endpoint) {
    return '代理 $endpoint';
  }

  @override
  String get proxyTestEndpointInvalid => '测试 URL 无效（需以 http:// 或 https:// 开头）';

  @override
  String get proxyTestConsoleTitle => '代理连通性诊断';

  @override
  String get proxyTestConsoleRunning => '正在执行链路探测…';

  @override
  String get proxyTestConsoleSucceeded => '诊断完成：链路畅通';

  @override
  String get proxyTestConsoleFailed => '诊断完成：发现问题';

  @override
  String get proxyTestConsoleCopy => '复制日志';

  @override
  String get proxyTestConsoleCopied => '日志已复制到剪贴板';

  @override
  String get proxyTestConsoleClose => '关闭';

  @override
  String get proxyTestConsoleRerun => '重新运行';

  @override
  String get proxyTestConsoleMaximize => '最大化';

  @override
  String get proxyTestConsoleRestore => '还原';

  @override
  String get proxyTestConsoleClear => '清空终端';

  @override
  String get tokenPopupCostHeading => '成本估算';

  @override
  String get tokenPopupCostInput => '输入';

  @override
  String get tokenPopupCostOutput => '输出';

  @override
  String get tokenPopupCostCacheRead => 'Cache 命中';

  @override
  String get tokenPopupCostCacheWrite => 'Cache 写入';

  @override
  String get tokenPopupCostTotal => '总计';

  @override
  String get tokenDialUnit => 'Token';

  @override
  String get tokenDialTotal => '总计';

  @override
  String get tokenPopupInputHeading => '输入';

  @override
  String get tokenPopupPrompt => 'Prompt';

  @override
  String get tokenPopupCacheRead => 'Cache 命中';

  @override
  String get tokenPopupCacheWrite => 'Cache 写入';

  @override
  String get tokenPopupOutputHeading => '输出';

  @override
  String get tokenPopupCompletion => 'Completion';

  @override
  String get tokenPopupGrandTotal => '总计';

  @override
  String get tokenPopupCacheHit => 'Cache 命中率';

  @override
  String get tokenPopupSessionHeading => '会话累计';

  @override
  String get tokenPopupMessages => '消息总数';

  @override
  String get tokenPopupPromptBuilds => 'Prompt 构建';

  @override
  String get tokenPopupPromptChars => 'Prompt 字符';

  @override
  String get toolbarSessionMetadata => '会话元数据';

  @override
  String get toolbarProviderModelLocked => '已锁定服务商与模型以保证缓存命中';

  @override
  String get toolbarModelLocked => '模型已锁定';

  @override
  String get toolbarSessionAudit => '会话审计';

  @override
  String get toolbarShowPlan => '展开计划';

  @override
  String get toolbarHidePlan => '收起计划';

  @override
  String get toolbarPlanAwaitingApproval => '计划待确认';

  @override
  String get toolbarPlanNeedsReview => '计划待复核';

  @override
  String get toolbarPlanNeedsAttention => '计划需要处理';

  @override
  String get toolbarPlanCompleted => '计划已完成';

  @override
  String get toolbarPlanInProgress => '计划推进中';

  @override
  String get toolbarPlanConfirmToBegin => '请确认后开始执行';

  @override
  String get toolbarPlanInspectBeforeResume => '继续前先检查已完成步骤、产物和 Todo';

  @override
  String get toolbarPlanStepFailed => '当前步骤执行失败，请检查后继续';

  @override
  String get toolbarPlanPending => '等待确认';

  @override
  String get toolbarPlanReview => '待复核';

  @override
  String get toolbarToolsProtocolUnsupported => '当前模型协议不支持工具调用';

  @override
  String get toolbarRuntimeNoSnapshot => '尚未生成运行时工具快照';

  @override
  String get toolbarToolsCatalogStale => '工具目录已过期，等待下一轮刷新';

  @override
  String get toolbarRuntimeCatalogSynced => '运行时工具目录已同步';

  @override
  String get toolbarPlanAwaitingNoExecTools => '计划待确认，当前轮不开放执行工具';

  @override
  String get toolbarPlanReviewBeforeResume => '需要先复核已有步骤、产物和 Todo';

  @override
  String get toolbarPlanApprovedExecOpen => '计划已获准执行，当前轮开放执行工具';

  @override
  String get toolbarPlanOnlyPlanningExitAllowed => '当前仅开放规划工具，可在准备好后提交执行计划';

  @override
  String get toolbarPlanOnlyPlanningOnly => '当前仅开放规划工具';

  @override
  String get toolbarModeJustSwitched => '模式刚切换，等待下一轮重新计算工具目录';

  @override
  String get toolbarChatModeNoTools => '聊天模式当前没有可用工具';

  @override
  String get toolbarChatModeAllTools => '聊天模式当前开放完整运行时工具目录';

  @override
  String get toolbarRuntimeNoSnapshotPrompt => '当前还没有运行时快照，请先发起一轮请求';

  @override
  String get toolbarGateNoReason => '暂无门控说明';

  @override
  String get toolbarGateProtocolUnsupportedSwitchPlan =>
      '当前模型协议不支持工具调用。点击切换到计划模式。';

  @override
  String get toolbarGateChatActiveSwitchPlan => '当前为聊天模式，点击切换到计划模式';

  @override
  String get toolbarGatePlanActiveSwitchChat => '当前为计划模式，点击切换到聊天模式';

  @override
  String get toolbarGateProtocolUnsupportedSwitchChat =>
      '当前模型协议不支持工具调用。计划模式仍可组织步骤，但不会开放工具执行。点击切换到聊天模式。';

  @override
  String get toolbarGatePlanJustSwitchedToChat =>
      '计划模式刚切换完成，运行时工具会在下一轮自动刷新。点击切换到聊天模式。';

  @override
  String get toolbarGatePlanAwaitingSwitchChat =>
      '计划待确认。当前轮不会暴露执行工具，请先确认计划。点击切换到聊天模式。';

  @override
  String get toolbarGatePlanReviewSwitchChat =>
      '计划待复核。继续执行前应先检查已完成步骤、产物与 Todo。点击切换到聊天模 式。';

  @override
  String get toolbarGatePlanExecutingSwitchChat =>
      '计划执行中。当前轮会按运行时目录暴露执行工具。点击切换到聊天模式。';

  @override
  String get toolbarGatePlanModeSwitchChat =>
      '当前为计划模式，会先规划，再在获得确认后执行。点击切换到聊天模式。';

  @override
  String get toolbarFilesShow => '项目文件';

  @override
  String get toolbarFilesHide => '收起项目';

  @override
  String get toolbarRuntimeModeChat => '聊天模式';

  @override
  String get toolbarRuntimeModeChatCompact => '聊天模式';

  @override
  String get toolbarRuntimeModePlan => '计划模式';

  @override
  String get toolbarRuntimeModePlanCompact => '计划模式';

  @override
  String get toolbarRuntimeModePlanAwaiting => '计划待确认';

  @override
  String get toolbarRuntimeModePlanAwaitingCompact => '计划待确认';

  @override
  String get toolbarRuntimeModePlanReview => '计划待复核';

  @override
  String get toolbarRuntimeModePlanReviewCompact => '计划待复核';

  @override
  String get toolbarRuntimeModePlanExecution => '执行计划';

  @override
  String get toolbarRuntimeModePlanExecutionCompact => '执行计划';

  @override
  String get toolbarRuntimeModePlanDrafting => '计划规划中';

  @override
  String get toolbarRuntimeModePlanDraftCompact => '计划规划中';

  @override
  String toolbarRuntimeNotices(int count) {
    return '$count 项运行时 Notice';
  }

  @override
  String toolbarPlanStepsCompleted(int completed, int total) {
    return '已完成 $completed/$total 项';
  }
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
  String get aiProtocolMinimax => 'MiniMax';

  @override
  String get aiProtocolLongCat => 'LongCat';

  @override
  String get aiProtocolJoyCode => 'JoyCode';

  @override
  String get aiProtocolWenxin => '文心一言 (ERNIE)';

  @override
  String get aiProtocolMeta => 'Meta AI (Llama)';

  @override
  String get aiProtocolMimo => 'MIMO (小米)';

  @override
  String get aiProtocolHunyuan => '混元 (腾讯)';

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
  String get imageEditorCropHint =>
      '拖动方框调整裁剪区域，可继续缩放、旋转、翻转，展开下方面板可使用 HSL、色调分离、清晰度、颗粒、降噪、色散、扭曲、水印等高级调整（高级调整在保存时应用）。';

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
  String get imageEditorSectionBasic => '基础调整';

  @override
  String get imageEditorSectionColor => '色彩（色温 / 色调 / 伽马）';

  @override
  String get imageEditorSectionSplitToning => '色调分离（HSL）';

  @override
  String get imageEditorSectionDetail => '细节（清晰度 / 锐度 / 降噪 / 颗粒）';

  @override
  String get imageEditorSectionEffects => '特效（色散 / 扭曲 / 晕影）';

  @override
  String get imageEditorSectionWatermark => '文字水印 / 标记';

  @override
  String get imageEditorTemperatureLabel => '色温';

  @override
  String get imageEditorTintLabel => '色调偏移';

  @override
  String get imageEditorGammaLabel => '伽马（曲线）';

  @override
  String get imageEditorShadowHueLabel => '暗部色相';

  @override
  String get imageEditorShadowStrengthLabel => '暗部强度';

  @override
  String get imageEditorHighlightHueLabel => '亮部色相';

  @override
  String get imageEditorHighlightStrengthLabel => '亮部强度';

  @override
  String get imageEditorClarityLabel => '清晰度';

  @override
  String get imageEditorSharpnessLabel => '锐度';

  @override
  String get imageEditorDenoiseLabel => '降噪';

  @override
  String get imageEditorGrainLabel => '颗粒';

  @override
  String get imageEditorDispersionLabel => '色散';

  @override
  String get imageEditorDistortLabel => '扭曲（正值凸出 / 负值拉伸）';

  @override
  String get imageEditorWatermarkTextLabel => '水印文字';

  @override
  String get imageEditorWatermarkTextHint => '输入要叠加的文字（留空则不添加）';

  @override
  String get imageEditorWatermarkSizeLabel => '文字大小';

  @override
  String get imageEditorWatermarkOpacityLabel => '不透明度';

  @override
  String get imageEditorWatermarkPositionLabel => '位置';

  @override
  String get imageEditorWatermarkColorLight => '浅色';

  @override
  String get imageEditorWatermarkColorDark => '深色';

  @override
  String get imageEditorAdvancedApplyHint => '展开面板中的调整会在“保存”时一次性应用到原图。';

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
  String get instructionPageTitle => '指令';

  @override
  String get instructionPageSubtitle =>
      '维护应用内的可复用提示词片段。启用的指令会按当前顺序注入到所有线程模板的 system prompt，并在会话输入框上方以胶囊形式列出，可在单次发送前临时取消或重新加入。';

  @override
  String get instructionRefresh => '刷新';

  @override
  String get instructionNewEntry => '新建指令';

  @override
  String get instructionEmptyTitle => '尚未创建指令';

  @override
  String get instructionEmptyBody => '新建第一条可复用指令后，OpenHand 会把它保存到本地指令库中。';

  @override
  String get instructionLoadFailedTitle => '指令库读取失败';

  @override
  String get instructionDeleteConfirmTitle => '删除指令';

  @override
  String get instructionDeleteConfirmBody => '确认删除这条指令吗？删除后无法恢复。';

  @override
  String get instructionEnabledStatus => '已启用并注入';

  @override
  String get instructionDisabledStatus => '已停用';

  @override
  String get instructionApplyToChipLabel => '适用';

  @override
  String get instructionNotesChipLabel => '备注';

  @override
  String get instructionDialogCreateTitle => '新建指令';

  @override
  String get instructionDialogEditTitle => '编辑指令';

  @override
  String get instructionEnabledLabel => '启用';

  @override
  String get instructionEnabledBody => '将这条指令注入到当前提示链中。';

  @override
  String get instructionNameField => '名称 *';

  @override
  String get instructionNameRequired => '请输入名称。';

  @override
  String get instructionDescriptionField => '描述';

  @override
  String get instructionVersionField => '版本';

  @override
  String get instructionApplyToField => '适用范围（描述何时加载这条指令）';

  @override
  String get instructionTaskTypesField => '触发任务类型（逗号分隔）';

  @override
  String get instructionKeywordsField => '触发关键词（逗号分隔）';

  @override
  String get instructionNotesField => '备注（每行一条）';

  @override
  String get instructionBodyField => '指令正文 *（Markdown）';

  @override
  String get instructionBodyRequired => '请输入指令正文。';

  @override
  String get instructionCreateAction => '创建';

  @override
  String get instructionSaveFailed => '保存失败，请检查必填项是否为空。';

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

  @override
  String get aiToolResultCompressionThresholdLabel => '工具调用输出压缩阈值';

  @override
  String get aiToolResultCompressionThresholdBody =>
      '当某个工具调用返回的 raw 内容字符数超过该阈值时，OpenHand 会在拼装 conversation history 前将其压缩为“受影响路径+目的+首尾片段”的结构化摘要，释放 tokens。默认 1024。';

  @override
  String get aiToolResultCompressionThresholdSave => '保存阈值';

  @override
  String get aiToolResultCompressionThresholdSaved => '工具调用输出压缩阈值已更新。';

  @override
  String get aiToolResultCompressionThresholdInvalid => '请输入有效的正整数阈值。';

  @override
  String get aiToolResultCompressionEnabledLabel => '启用工具调用输出压缩';

  @override
  String get aiToolResultCompressionEnabledBody =>
      '总开关。关闭后不论阈值多大都不压缩工具输出原文，适合需要调试完整输出的场景。';

  @override
  String get aiToolResultCompressionHeadTailWindowLabel => '压缩摘要首尾片段窗口';

  @override
  String get aiToolResultCompressionHeadTailWindowBody =>
      '压缩后摘要中保留 raw 输出首尾各多少个字符。默认 256；0 表示不保留首尾片段；范围 0~8192。';

  @override
  String get aiToolResultCompressionHeadTailWindowSave => '保存窗口长度';

  @override
  String get aiToolResultCompressionHeadTailWindowSaved => '首尾片段窗口已更新。';

  @override
  String get aiToolResultCompressionHeadTailWindowInvalid =>
      '请输入 0~8192 之间的整数。';

  @override
  String get aiToolResultCompressionMaxPathHitsLabel => '压缩摘要提取路径上限';

  @override
  String get aiToolResultCompressionMaxPathHitsBody =>
      '压缩后摘要中提取受影响文件路径的最大条数。默认 12；0 表示不提取；范围 0~200。';

  @override
  String get aiToolResultCompressionMaxPathHitsSave => '保存上限';

  @override
  String get aiToolResultCompressionMaxPathHitsSaved => '路径提取上限已更新。';

  @override
  String get aiToolResultCompressionMaxPathHitsInvalid => '请输入 0~200 之间的整数。';

  @override
  String get aiWriteToolSummaryMaxCharsLabel => '写类工具摘要字符上限';

  @override
  String get aiWriteToolSummaryMaxCharsBody =>
      '写类工具（write/edit/multiedit/notebookedit/写型 bash）结果摘要中保留 result_text 原文的最大字符数。默认 280；0 表示不保留；范围 0~8192。';

  @override
  String get aiWriteToolSummaryMaxCharsSave => '保存上限';

  @override
  String get aiWriteToolSummaryMaxCharsSaved => '写类工具摘要字符上限已更新。';

  @override
  String get aiWriteToolSummaryMaxCharsInvalid => '请输入 0~8192 之间的整数。';

  @override
  String get aiMaxRecentErrorsLabel => '会话错误记录保留上限';

  @override
  String get aiMaxRecentErrorsBody => 'AI 会话状态中保留的最近错误记录条数。默认 15；范围 0~1000。';

  @override
  String get aiMaxRecentErrorsSave => '保存上限';

  @override
  String get aiMaxRecentErrorsSaved => '会话错误记录保留上限已更新。';

  @override
  String get aiMaxRecentErrorsInvalid => '请输入 0~1000 之间的整数。';

  @override
  String get aiMaxPlanHistoryEntriesLabel => '计划历史保留上限';

  @override
  String get aiMaxPlanHistoryEntriesBody =>
      'Plan 模式下 plan_history 保留的最大条目数。默认 15；范围 0~1000。';

  @override
  String get aiMaxPlanHistoryEntriesSave => '保存上限';

  @override
  String get aiMaxPlanHistoryEntriesSaved => '计划历史保留上限已更新。';

  @override
  String get aiMaxPlanHistoryEntriesInvalid => '请输入 0~1000 之间的整数。';

  @override
  String get aiMaxTruncationContinuationsLabel => '自动续接轮次上限';

  @override
  String get aiMaxTruncationContinuationsBody =>
      '模型输出被截断（finish_reason=length）后自动续接的最大次数。默认 5；范围 0~100。';

  @override
  String get aiMaxTruncationContinuationsSave => '保存上限';

  @override
  String get aiMaxTruncationContinuationsSaved => '自动续接轮次上限已更新。';

  @override
  String get aiMaxTruncationContinuationsInvalid => '请输入 0~100 之间的整数。';

  @override
  String get aiEstimatedCharactersPerTokenLabel => 'Token 字符估算系数';

  @override
  String get aiEstimatedCharactersPerTokenBody =>
      '每个 token 约等于多少个字符，用于上下文容量估算。默认 4；范围 1~32。';

  @override
  String get aiEstimatedCharactersPerTokenSave => '保存系数';

  @override
  String get aiEstimatedCharactersPerTokenSaved => 'Token 字符估算系数已更新。';

  @override
  String get aiEstimatedCharactersPerTokenInvalid => '请输入 1~32 之间的整数。';

  @override
  String get aiMaxToolOutputCharsLabel => '工具单次输出字符上限';

  @override
  String get aiMaxToolOutputCharsBody =>
      '默认 150000。单次工具调用结果若超过这个字符数会截断，避免 Context 溢出。';

  @override
  String get aiMaxToolOutputCharsSave => '保存上限';

  @override
  String get aiMaxToolOutputCharsSaved => '工具输出字符上限已保存。';

  @override
  String get aiMaxToolOutputCharsInvalid => '请输入 1000~10000000 之间的整数。';

  @override
  String get aiWriteConfirmationTimeoutMsLabel => '写命令确认超时（毫秒）';

  @override
  String get aiWriteConfirmationTimeoutMsBody =>
      '默认 300000（5 分钟）。等待用户审批写命令的最长时间。';

  @override
  String get aiWriteConfirmationTimeoutMsSave => '保存超时';

  @override
  String get aiWriteConfirmationTimeoutMsSaved => '写命令确认超时已保存。';

  @override
  String get aiWriteConfirmationTimeoutMsInvalid => '请输入 1000~3600000 之间的整数。';

  @override
  String get aiFastPathWriteAnalysisThresholdLabel => 'Fast-path 写命令分析阈值';

  @override
  String get aiFastPathWriteAnalysisThresholdBody =>
      '默认 512 字符。命令长度超过此值会走快速路径粗判，避免昂贵的语法分析。';

  @override
  String get aiFastPathWriteAnalysisThresholdSave => '保存阈值';

  @override
  String get aiFastPathWriteAnalysisThresholdSaved => 'Fast-path 阈值已保存。';

  @override
  String get aiFastPathWriteAnalysisThresholdInvalid => '请输入 0~100000 之间的整数。';

  @override
  String get aiMaxHookTextCharactersLabel => 'Hook 文本输出上限';

  @override
  String get aiMaxHookTextCharactersBody =>
      '默认 4000。Claude Hook 在合并 stdout/stderr 文本时的总字符上限。';

  @override
  String get aiMaxHookTextCharactersSave => '保存上限';

  @override
  String get aiMaxHookTextCharactersSaved => 'Hook 文本上限已保存。';

  @override
  String get aiMaxHookTextCharactersInvalid => '请输入 100~1000000 之间的整数。';

  @override
  String get aiWebFetchMaxResponseBytesLabel => 'WebFetch 单次响应字节上限';

  @override
  String get aiWebFetchMaxResponseBytesBody =>
      '默认 1048576（1MB）。调整以适配你的网络与附件需求。';

  @override
  String get aiWebFetchMaxResponseBytesSave => '保存';

  @override
  String get aiWebFetchMaxResponseBytesSaved => 'WebFetch 单次响应字节上限已保存。';

  @override
  String get aiWebFetchMaxResponseBytesInvalid => '请输入有效整数。';

  @override
  String get aiWebFetchMaxRedirectsLabel => 'WebFetch 最大重定向次数';

  @override
  String get aiWebFetchMaxRedirectsBody => '默认 5。调整以适配你的网络与附件需求。';

  @override
  String get aiWebFetchMaxRedirectsSave => '保存';

  @override
  String get aiWebFetchMaxRedirectsSaved => 'WebFetch 最大重定向次数已保存。';

  @override
  String get aiWebFetchMaxRedirectsInvalid => '请输入有效整数。';

  @override
  String get aiWebFetchMaxCacheEntriesLabel => 'WebFetch 缓存条目上限';

  @override
  String get aiWebFetchMaxCacheEntriesBody => '默认 64。调整以适配你的网络与附件需求。';

  @override
  String get aiWebFetchMaxCacheEntriesSave => '保存';

  @override
  String get aiWebFetchMaxCacheEntriesSaved => 'WebFetch 缓存条目上限已保存。';

  @override
  String get aiWebFetchMaxCacheEntriesInvalid => '请输入有效整数。';

  @override
  String get aiAttachmentMaxInlineImageDimensionLabel => '附件图片最大边长（像素）';

  @override
  String get aiAttachmentMaxInlineImageDimensionBody =>
      '默认 1568。调整以适配你的网络与附件需求。';

  @override
  String get aiAttachmentMaxInlineImageDimensionSave => '保存';

  @override
  String get aiAttachmentMaxInlineImageDimensionSaved => '附件图片最大边长（像素）已保存。';

  @override
  String get aiAttachmentMaxInlineImageDimensionInvalid => '请输入有效整数。';

  @override
  String get aiAttachmentMaxTextRawBytesLabel => '附件文本读取上限（字节）';

  @override
  String get aiAttachmentMaxTextRawBytesBody =>
      '默认 1597152（2MB）。调整以适配你的网络与附件需求。';

  @override
  String get aiAttachmentMaxTextRawBytesSave => '保存';

  @override
  String get aiAttachmentMaxTextRawBytesSaved => '附件文本读取上限（字节）已保存。';

  @override
  String get aiAttachmentMaxTextRawBytesInvalid => '请输入有效整数。';

  @override
  String get aiAttachmentMaxPdfRawBytesLabel => '附件 PDF 读取上限（字节）';

  @override
  String get aiAttachmentMaxPdfRawBytesBody =>
      '默认 1597152（2MB）。调整以适配你的网络与附件需求。';

  @override
  String get aiAttachmentMaxPdfRawBytesSave => '保存';

  @override
  String get aiAttachmentMaxPdfRawBytesSaved => '附件 PDF 读取上限（字节）已保存。';

  @override
  String get aiAttachmentMaxPdfRawBytesInvalid => '请输入有效整数。';

  @override
  String get aiAttachmentMaxImageRawBytesLabel => '附件图片读取上限（字节）';

  @override
  String get aiAttachmentMaxImageRawBytesBody =>
      '默认 52428800（50MB）。调整以适配你的网络与附件需求。';

  @override
  String get aiAttachmentMaxImageRawBytesSave => '保存';

  @override
  String get aiAttachmentMaxImageRawBytesSaved => '附件图片读取上限（字节）已保存。';

  @override
  String get aiAttachmentMaxImageRawBytesInvalid => '请输入有效整数。';

  @override
  String get aiChatMaxStreamLineBufferBytesLabel => 'Chat 流缓冲字节上限';

  @override
  String get aiChatMaxStreamLineBufferBytesBody =>
      '默认 4194304（4MB）。调整以适配你的网络与附件需求。';

  @override
  String get aiChatMaxStreamLineBufferBytesSave => '保存';

  @override
  String get aiChatMaxStreamLineBufferBytesSaved => 'Chat 流缓冲字节上限已保存。';

  @override
  String get aiChatMaxStreamLineBufferBytesInvalid => '请输入有效整数。';

  @override
  String get aiFallbackTitleMaxCharactersLabel => '回退标题最大字符数';

  @override
  String get aiFallbackTitleMaxCharactersBody => '默认 15。调整以匹配会话标题派生策略。';

  @override
  String get aiFallbackTitleMaxCharactersSave => '保存';

  @override
  String get aiFallbackTitleMaxCharactersSaved => '回退标题最大字符数已保存。';

  @override
  String get aiFallbackTitleMaxCharactersInvalid => '请输入有效整数。';

  @override
  String get aiGeneratedTitleMaxCharactersLabel => '自动标题最大字符数';

  @override
  String get aiGeneratedTitleMaxCharactersBody => '默认 15。调整以匹配会话标题派生策略。';

  @override
  String get aiGeneratedTitleMaxCharactersSave => '保存';

  @override
  String get aiGeneratedTitleMaxCharactersSaved => '自动标题最大字符数已保存。';

  @override
  String get aiGeneratedTitleMaxCharactersInvalid => '请输入有效整数。';

  @override
  String get aiMinimumMeaningfulTitleCharactersLabel => '中文有效标题最小字符数';

  @override
  String get aiMinimumMeaningfulTitleCharactersBody => '默认 4。调整以匹配会话标题派生策略。';

  @override
  String get aiMinimumMeaningfulTitleCharactersSave => '保存';

  @override
  String get aiMinimumMeaningfulTitleCharactersSaved => '中文有效标题最小字符数已保存。';

  @override
  String get aiMinimumMeaningfulTitleCharactersInvalid => '请输入有效整数。';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsLabel => '拉丁有效标题最小词数';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsBody => '默认 2。调整以匹配会话标题派生策略。';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsSave => '保存';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsSaved => '拉丁有效标题最小词数已保存。';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsInvalid => '请输入有效整数。';

  @override
  String get aiMaxSkillContentLengthLabel => '技能文件内容字符上限';

  @override
  String get aiMaxSkillContentLengthBody => '默认 100000。调整以适配技能与工作区文档大小。';

  @override
  String get aiMaxSkillContentLengthSave => '保存';

  @override
  String get aiMaxSkillContentLengthSaved => '技能文件内容字符上限已保存。';

  @override
  String get aiMaxSkillContentLengthInvalid => '请输入有效整数。';

  @override
  String get aiMaxWorkspaceDocumentCharactersLabel => '工作区指令文档字符上限';

  @override
  String get aiMaxWorkspaceDocumentCharactersBody =>
      '默认 16000。调整以适配技能与工作区文档大小。';

  @override
  String get aiMaxWorkspaceDocumentCharactersSave => '保存';

  @override
  String get aiMaxWorkspaceDocumentCharactersSaved => '工作区指令文档字符上限已保存。';

  @override
  String get aiMaxWorkspaceDocumentCharactersInvalid => '请输入有效整数。';

  @override
  String get aiImageSizeLimitLabel => '图片大小上限';

  @override
  String get aiImageSizeLimitBody =>
      '当用户添加的图片附件超过该上限时，OpenHand 会自动按质量 + 尺寸两级压缩后再发送。支持小数 MB；范围 0.0625 MB（64 KB）至 64 MB。';

  @override
  String get aiImageSizeLimitFieldLabel => '上限 (MB)';

  @override
  String get aiImageSizeLimitSave => '保存上限';

  @override
  String get aiImageSizeLimitSaved => '图片附件大小上限已更新。';

  @override
  String get aiImageSizeLimitInvalid => '请输入有效的正数 MB 值。';

  @override
  String get imageEditorAspectFree => '自由';

  @override
  String get imageEditorAspectOriginal => '原始';

  @override
  String get imageEditorAspectSquare => '1:1';

  @override
  String get imageEditorAspect4x3 => '4:3';

  @override
  String get imageEditorAspect3x4 => '3:4';

  @override
  String get imageEditorAspect16x9 => '16:9';

  @override
  String get imageEditorAspect9x16 => '9:16';

  @override
  String get imageEditorAspectCircle => '圆形';

  @override
  String get imageEditorFlipHorizontal => '水平翻转';

  @override
  String get imageEditorFlipVertical => '垂直翻转';

  @override
  String get imageEditorSaturationLabel => '饱和度';

  @override
  String get imageEditorExposureLabel => '曝光';

  @override
  String get imageEditorHueLabel => '色相';

  @override
  String get imageEditorVignetteLabel => '暗角';

  @override
  String get imageEditorFineRotationLabel => '微调旋转 (°)';

  @override
  String get imageEditorSaveToFile => '另存到本地';

  @override
  String get imageEditorCopyToClipboard => '复制到剪贴板';

  @override
  String imageEditorSavedTo(String path) {
    return '已另存：$path';
  }

  @override
  String imageEditorSaveFailed(String error) {
    return '另存失败：$error';
  }

  @override
  String get imageEditorClipboardCopiedBitmap => '已复制图片到剪贴板（文件路径同时复制为文本）。';

  @override
  String imageEditorClipboardCopiedPath(String path) {
    return '已复制图片文件路径到剪贴板：$path';
  }

  @override
  String imageEditorClipboardFailed(String error) {
    return '复制失败：$error';
  }

  @override
  String get imageEditorApplyButton => '应用';

  @override
  String get imageEditorUndoButton => '回退';

  @override
  String get imageEditorResetAllButton => '重置全部';

  @override
  String get imageEditorCompareHold => '按住对比';

  @override
  String get imageEditorCompareRelease => '松开返回';

  @override
  String get imageEditorCompareOriginal => '原图';

  @override
  String get imageEditorWatermarkColorLabel => '文字颜色';

  @override
  String get imageEditorWatermarkColorHue => '颜色（Hue）';

  @override
  String get imageEditorWatermarkColorSaturation => '饱和度';

  @override
  String get imageEditorWatermarkColorLightness => '明度';

  @override
  String get imageEditorApplySuccess => '调整已应用';

  @override
  String get imageEditorProcessing => '处理中…';

  @override
  String get builtinToolTimeoutLabel => '超时时间（秒）';

  @override
  String builtinToolTimeoutHint(int seconds) {
    return '默认 ${seconds}s';
  }

  @override
  String builtinToolTimeoutHelper(int seconds) {
    return '留空则使用默认 ${seconds}s';
  }

  @override
  String get builtinToolRetryLabel => '失败/超时自动重试';

  @override
  String get builtinToolRetryBody =>
      '默认关闭。仅对真正失败 (failed/timed_out) 触发，不会重试参数错误或被拒绝的调用。';

  @override
  String builtinToolMaxRetriesLabel(int max) {
    return '最大重试次数 (0–$max)';
  }

  @override
  String builtinToolMaxRetriesHelper(int max) {
    return '不含首次执行；上限 $max 次';
  }

  @override
  String get builtinToolBackoffLabel => '重试退避基线（毫秒）';

  @override
  String builtinToolBackoffHint(int ms) {
    return '默认 ${ms}ms';
  }

  @override
  String builtinToolBackoffHelper(int max) {
    return '指数退避：第 N 次重试等待 base × 2^(N-1)ms，上限 ${max}ms';
  }

  @override
  String selfLearningFlushIntervalLabel(int ms) {
    return '流式刷新间隔：${ms}ms';
  }

  @override
  String selfLearningFlushIntervalHelper(int min, int max) {
    return '自我学习卡片流式输出的持久化间隔（$min–${max}ms）。调小=更实时但更多布局抖动；调大=更平滑但增量延迟更高。默认 600ms。';
  }

  @override
  String get tsmRenameThreadTitle => '重命名线程';

  @override
  String get tsmRenameHint => '输入线程标题';

  @override
  String get tsmRenameFailed => '重命名失败';

  @override
  String get tsmDeleteThreadTitle => '删除线程';

  @override
  String get tsmDeleteSelectedTitle => '删除所选线程';

  @override
  String tsmDeleteSelectedConfirm(Object count) {
    return '将永久删除 $count 个线程及其消息。此操作无法撤销。';
  }

  @override
  String tsmDeleteFailedCount(Object count) {
    return '$count 个线程删除失败';
  }

  @override
  String get tsmSessionMissing => '会话不存在或已被删除';

  @override
  String get tsmExportSessionDataTitle => '导出会话数据';

  @override
  String tsmExportingSession(Object title) {
    return '正在导出 “$title”…';
  }

  @override
  String get tsmExportComplete => '导出完成';

  @override
  String get tsmExportFailed => '导出失败';

  @override
  String get tsmChooseExportFolder => '选择导出目录';

  @override
  String get tsmBatchExportTitle => '批量导出';

  @override
  String tsmBatchExportSubtitle(Object count) {
    return '即将导出 $count 个线程…';
  }

  @override
  String tsmBatchExportDone(Object ok, Object failed) {
    return '批量导出完成：成功 $ok / 失败 $failed';
  }

  @override
  String get tsmMenuPreview => '预览';

  @override
  String get tsmMenuRename => '重命名';

  @override
  String get tsmMenuExportSession => '导出会话数据';

  @override
  String get tsmMenuPin => '置顶';

  @override
  String get tsmMenuUnpin => '取消置顶';

  @override
  String get tsmMenuArchive => '归档';

  @override
  String get tsmMenuUnarchive => '取消归档';

  @override
  String get tsmMenuDelete => '删除';

  @override
  String get tsmPinUpdateFailed => '置顶状态更新失败';

  @override
  String get tsmArchiveUpdateFailed => '归档状态更新失败';

  @override
  String get tsmUntitledThread => '(未命名线程)';

  @override
  String tsmPreviewMessageCount(Object count) {
    return '$count 条消息';
  }

  @override
  String get tsmClosePreview => '关闭预览';

  @override
  String get tsmNoMessages => '暂无消息';

  @override
  String get tsmEmptyMessage => '(空消息)';

  @override
  String get tsmSearchHint => '按标题或 ID 搜索';

  @override
  String get tsmDensityComfortable => '舒适密度';

  @override
  String get tsmDensityCompact => '紧凑密度';

  @override
  String get tsmAllTemplates => '全部模板';

  @override
  String tsmSortDisabledHint(Object mode) {
    return '当前为「$mode」排序，拖拽手柄已禁用，切回「手动顺序」可继续调整。';
  }

  @override
  String get tsmSortManual => '手动顺序';

  @override
  String get tsmSortUpdated => '最近更新';

  @override
  String get tsmSortCreated => '最近创建';

  @override
  String get tsmSortSize => '占用大小';

  @override
  String get tsmSortMessages => '消息数量';

  @override
  String get tsmSortToken => 'Token 数';

  @override
  String get tsmHideArchived => '隐藏归档';

  @override
  String get tsmShowArchived => '显示归档';

  @override
  String get tsmExitSelection => '退出多选';

  @override
  String get tsmEnterSelection => '多选';

  @override
  String get tsmClose => '关闭';

  @override
  String get tsmTitle => '线程会话管理';

  @override
  String tsmHeaderSubtitle(Object count) {
    return '共 $count 个线程 · 长按或拖拽手柄可调整顺序，双击/右键查看更多操作';
  }

  @override
  String tsmSelectedCount(Object count) {
    return '已选 $count';
  }

  @override
  String get tsmBatchExportButton => '批量导出';

  @override
  String get tsmDeleteSelectedButton => '删除所选';

  @override
  String get tsmEmptyState => '暂无线程会话';

  @override
  String get tsmCancel => '取消';

  @override
  String get settingsThreadSessionManagementTitle => '线程会话管理';

  @override
  String get settingsThreadSessionManagementSubtitle =>
      '查看所有线程的标题、创建/更新时间、占用大小、消息构成和 token 统计。支持拖拽排序、多选删除、双击或右键打开重命名/导出/删除菜单。弹窗的进出场动画跟随全局设置中的弹窗动画配置。';

  @override
  String get settingsThreadSessionManagementOpen => '打开管理弹窗';

  @override
  String get settingsMessageGatewayTitle => '消息网关';

  @override
  String get settingsMessageGatewayDescription =>
      '管理消息网关的路由、转换与节流策略。具体配置项将在后续版本中开放，当前为预留入口。';

  @override
  String get settingsMessageGatewayComingSoon => '即将推出';

  @override
  String get settingsMessageGatewayComingSoonSubtitle => '消息网关详细配置将在下一个迭代中提供。';

  @override
  String get tsmRowUnknown => '未知';

  @override
  String get tsmRowCreated => '创建';

  @override
  String get tsmRowUpdated => '更新';

  @override
  String get tsmRowSize => '占用';

  @override
  String get tsmRowMessages => '消息';

  @override
  String get tsmRowToken => 'Token';

  @override
  String get tsmRowByKind => '占比';

  @override
  String get proxySectionTitle => '系统';

  @override
  String get proxySectionBody =>
      '所有 OpenHand 内建 HTTP 客户端（WebSearch / WebFetch 等）将按此处代理设置选择路由。保存后即时生效，无需重启。';

  @override
  String get proxyModeLabel => '代理模式';

  @override
  String get proxyModeBody =>
      '决定 OpenHand 内置 HTTP 客户端（WebSearch / WebFetch 等）如何选择代理。';

  @override
  String get proxyModeDisabled => '无代理';

  @override
  String get proxyModeAutomatic => '自动发现代理（默认）';

  @override
  String get proxyModeManual => '手动配置代理';

  @override
  String get proxyProtocolsLabel => '代理协议';

  @override
  String get proxyProtocolsBody => '可多选，至少保留一个；取消所有协议时会自动恢复 HTTP + HTTPS。';

  @override
  String get proxyHostLabel => '服务器（IP 或主机名）';

  @override
  String get proxyPortLabel => '端口号';

  @override
  String get proxyAuthLabel => '开启代理服务器鉴权';

  @override
  String get proxyAuthBody => '开启后下面的用户名 / 密码字段才会被使用（HTTP Basic）。';

  @override
  String get proxyUsernameLabel => '用户名';

  @override
  String get proxyPasswordLabel => '密码';

  @override
  String get proxyExceptionsLabel => '忽略这些主机与域的代理设置';

  @override
  String get proxyExceptionsBody =>
      '每行一条。支持：IP 地址（127.0.0.1）、IPv4 CIDR（192.168.0.0/16）、域名（example.com 含子域）、glob（*.example.com）、正则（/^api\\d+\\.example\\.com\$/i）。localhost / 127.0.0.1 / ::1 始终走直连。';

  @override
  String get proxyExceptionsHint =>
      '示例：\n*.local\n10.0.0.0/8\n/^api\\d+\\.example\\.com\$/i';

  @override
  String get proxyTestButton => '测试代理连通性';

  @override
  String get proxyTesting => '测试中…';

  @override
  String proxyTestSuccess(Object latency, Object via) {
    return '连通成功（$latency ms，via $via）';
  }

  @override
  String proxyTestFailure(Object reason) {
    return '连通失败：$reason';
  }

  @override
  String get proxyTestEndpointLabel => '测试 URL';

  @override
  String get proxyTestEndpointHint => '默认：https://www.google.com/generate_204';

  @override
  String get proxyTestVerdictDirect => '直连';

  @override
  String proxyTestVerdictProxy(Object endpoint) {
    return '代理 $endpoint';
  }

  @override
  String get proxyTestEndpointInvalid => '测试 URL 无效（需以 http:// 或 https:// 开头）';

  @override
  String get proxyTestConsoleTitle => '代理连通性诊断';

  @override
  String get proxyTestConsoleRunning => '正在执行链路探测…';

  @override
  String get proxyTestConsoleSucceeded => '诊断完成：链路畅通';

  @override
  String get proxyTestConsoleFailed => '诊断完成：发现问题';

  @override
  String get proxyTestConsoleCopy => '复制日志';

  @override
  String get proxyTestConsoleCopied => '日志已复制到剪贴板';

  @override
  String get proxyTestConsoleClose => '关闭';

  @override
  String get proxyTestConsoleRerun => '重新运行';

  @override
  String get proxyTestConsoleMaximize => '最大化';

  @override
  String get proxyTestConsoleRestore => '还原';

  @override
  String get proxyTestConsoleClear => '清空终端';

  @override
  String get tokenPopupCostHeading => '成本估算';

  @override
  String get tokenPopupCostInput => '输入';

  @override
  String get tokenPopupCostOutput => '输出';

  @override
  String get tokenPopupCostCacheRead => 'Cache 命中';

  @override
  String get tokenPopupCostCacheWrite => 'Cache 写入';

  @override
  String get tokenPopupCostTotal => '总计';

  @override
  String get tokenDialUnit => 'Token';

  @override
  String get tokenDialTotal => '总计';

  @override
  String get tokenPopupInputHeading => '输入';

  @override
  String get tokenPopupPrompt => 'Prompt';

  @override
  String get tokenPopupCacheRead => 'Cache 命中';

  @override
  String get tokenPopupCacheWrite => 'Cache 写入';

  @override
  String get tokenPopupOutputHeading => '输出';

  @override
  String get tokenPopupCompletion => 'Completion';

  @override
  String get tokenPopupGrandTotal => '总计';

  @override
  String get tokenPopupCacheHit => 'Cache 命中率';

  @override
  String get tokenPopupSessionHeading => '会话累计';

  @override
  String get tokenPopupMessages => '消息总数';

  @override
  String get tokenPopupPromptBuilds => 'Prompt 构建';

  @override
  String get tokenPopupPromptChars => 'Prompt 字符';

  @override
  String get toolbarSessionMetadata => '会话元数据';

  @override
  String get toolbarProviderModelLocked => '已锁定服务商与模型以保证缓存命中';

  @override
  String get toolbarModelLocked => '模型已锁定';

  @override
  String get toolbarSessionAudit => '会话审计';

  @override
  String get toolbarShowPlan => '展开计划';

  @override
  String get toolbarHidePlan => '收起计划';

  @override
  String get toolbarPlanAwaitingApproval => '计划待确认';

  @override
  String get toolbarPlanNeedsReview => '计划待复核';

  @override
  String get toolbarPlanNeedsAttention => '计划需要处理';

  @override
  String get toolbarPlanCompleted => '计划已完成';

  @override
  String get toolbarPlanInProgress => '计划推进中';

  @override
  String get toolbarPlanConfirmToBegin => '请确认后开始执行';

  @override
  String get toolbarPlanInspectBeforeResume => '继续前先检查已完成步骤、产物和 Todo';

  @override
  String get toolbarPlanStepFailed => '当前步骤执行失败，请检查后继续';

  @override
  String get toolbarPlanPending => '等待确认';

  @override
  String get toolbarPlanReview => '待复核';

  @override
  String get toolbarToolsProtocolUnsupported => '当前模型协议不支持工具调用';

  @override
  String get toolbarRuntimeNoSnapshot => '尚未生成运行时工具快照';

  @override
  String get toolbarToolsCatalogStale => '工具目录已过期，等待下一轮刷新';

  @override
  String get toolbarRuntimeCatalogSynced => '运行时工具目录已同步';

  @override
  String get toolbarPlanAwaitingNoExecTools => '计划待确认，当前轮不开放执行工具';

  @override
  String get toolbarPlanReviewBeforeResume => '需要先复核已有步骤、产物和 Todo';

  @override
  String get toolbarPlanApprovedExecOpen => '计划已获准执行，当前轮开放执行工具';

  @override
  String get toolbarPlanOnlyPlanningExitAllowed => '当前仅开放规划工具，可在准备好后提交执行计划';

  @override
  String get toolbarPlanOnlyPlanningOnly => '当前仅开放规划工具';

  @override
  String get toolbarModeJustSwitched => '模式刚切换，等待下一轮重新计算工具目录';

  @override
  String get toolbarChatModeNoTools => '聊天模式当前没有可用工具';

  @override
  String get toolbarChatModeAllTools => '聊天模式当前开放完整运行时工具目录';

  @override
  String get toolbarRuntimeNoSnapshotPrompt => '当前还没有运行时快照，请先发起一轮请求';

  @override
  String get toolbarGateNoReason => '暂无门控说明';

  @override
  String get toolbarGateProtocolUnsupportedSwitchPlan =>
      '当前模型协议不支持工具调用。点击切换到计划模式。';

  @override
  String get toolbarGateChatActiveSwitchPlan => '当前为聊天模式，点击切换到计划模式';

  @override
  String get toolbarGatePlanActiveSwitchChat => '当前为计划模式，点击切换到聊天模式';

  @override
  String get toolbarGateProtocolUnsupportedSwitchChat =>
      '当前模型协议不支持工具调用。计划模式仍可组织步骤，但不会开放工具执行。点击切换到聊天模式。';

  @override
  String get toolbarGatePlanJustSwitchedToChat =>
      '计划模式刚切换完成，运行时工具会在下一轮自动刷新。点击切换到聊天模式。';

  @override
  String get toolbarGatePlanAwaitingSwitchChat =>
      '计划待确认。当前轮不会暴露执行工具，请先确认计划。点击切换到聊天模式。';

  @override
  String get toolbarGatePlanReviewSwitchChat =>
      '计划待复核。继续执行前应先检查已完成步骤、产物与 Todo。点击切换到聊天模 式。';

  @override
  String get toolbarGatePlanExecutingSwitchChat =>
      '计划执行中。当前轮会按运行时目录暴露执行工具。点击切换到聊天模式。';

  @override
  String get toolbarGatePlanModeSwitchChat =>
      '当前为计划模式，会先规划，再在获得确认后执行。点击切换到聊天模式。';

  @override
  String get toolbarFilesShow => '项目文件';

  @override
  String get toolbarFilesHide => '收起项目';

  @override
  String get toolbarRuntimeModeChat => '聊天模式';

  @override
  String get toolbarRuntimeModeChatCompact => '聊天模式';

  @override
  String get toolbarRuntimeModePlan => '计划模式';

  @override
  String get toolbarRuntimeModePlanCompact => '计划模式';

  @override
  String get toolbarRuntimeModePlanAwaiting => '计划待确认';

  @override
  String get toolbarRuntimeModePlanAwaitingCompact => '计划待确认';

  @override
  String get toolbarRuntimeModePlanReview => '计划待复核';

  @override
  String get toolbarRuntimeModePlanReviewCompact => '计划待复核';

  @override
  String get toolbarRuntimeModePlanExecution => '执行计划';

  @override
  String get toolbarRuntimeModePlanExecutionCompact => '执行计划';

  @override
  String get toolbarRuntimeModePlanDrafting => '计划规划中';

  @override
  String get toolbarRuntimeModePlanDraftCompact => '计划规划中';

  @override
  String toolbarRuntimeNotices(int count) {
    return '$count 项运行时 Notice';
  }

  @override
  String toolbarPlanStepsCompleted(int completed, int total) {
    return '已完成 $completed/$total 项';
  }
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
  String get memory => '記憶';

  @override
  String get mcp => 'MCP';

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
  String get chatSending => '傳送中';

  @override
  String get chatRequestFailed => '模型請求失敗，請檢查模型配置、網路連通性或介面協議。';

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
  String get settingsFilePathLabel => '設定檔案';

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
  String get themePaletteSectionTitle => '主題配色';

  @override
  String get themePaletteSectionBody =>
      '選擇全域主題配色，系統會基於該配色生成 Material 3 Expressive 主題層次。';

  @override
  String get themePresetDarkNightPurple => '暗夜紫';

  @override
  String get themePresetDeepSeaBlue => '深海藍';

  @override
  String get themePresetMistGray => '霧靄灰';

  @override
  String get themePresetObsidianBlack => '曜石黑';

  @override
  String get themePresetPolarWhite => '極晝白';

  @override
  String get themePresetFrostMorningBlue => '霜晨藍';

  @override
  String get themePresetDuskMountainGreen => '暮山青';

  @override
  String get themePresetNebulaPurple => '星雲紫';

  @override
  String get themePresetEmberOrange => '餘燼橙';

  @override
  String get themePresetTundraGreen => '苔原綠';

  @override
  String get themePresetMoonShadowSilver => '月影銀';

  @override
  String get themePresetAmberGold => '琥珀金';

  @override
  String get themePresetRainyCyan => '煙雨青';

  @override
  String get themePresetGraphiteGray => '石墨灰';

  @override
  String get themePresetGlacierBlue => '冰川藍';

  @override
  String get themePresetBlazeRed => '赤焰紅';

  @override
  String get themePresetNightfallBlue => '夜幕藍';

  @override
  String get themePresetColdMoonWhite => '冷月白';

  @override
  String get themePresetPineInk => '松煙墨';

  @override
  String get themePresetSkyCyan => '蒼穹青';

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
  String get commonCancel => '取消';

  @override
  String get commonSave => '儲存';

  @override
  String get commonDelete => '刪除';

  @override
  String get commonEdit => '編輯';

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
  String get settingsCategoryAi => 'AI';

  @override
  String get settingsCategorySkills => '技能';

  @override
  String get settingsCategoryMemory => '記憶';

  @override
  String get mcpSectionTitle => 'MCP 服務';

  @override
  String get mcpSectionBody =>
      '管理全域 MCP 開關和服務配置檔案位置。服務條目的新增、更新、刪除與啟用狀態會同步寫入 MCP JSON 檔案。';

  @override
  String get mcpEnabledLabel => '啟用 MCP 服務';

  @override
  String get mcpEnabledBody => '關閉後不會啟用 MCP 服務能力，但仍然保留已儲存的服務配置。';

  @override
  String get mcpFilePathLabel => 'MCP 配置檔案';

  @override
  String get mcpOpenDirectory => '打開目錄';

  @override
  String get settingsGeneralTitle => '常規';

  @override
  String get settingsGeneralSubtitle => '管理主題、語言與應用基礎資訊。';

  @override
  String get settingsAiSubtitle => '管理聊天模型、驗證方式與協議適配。';

  @override
  String get settingsSkillsTitle => '技能';

  @override
  String get settingsSkillsSubtitle => '管理本地技能目錄、模板建立與已安裝技能展示。';

  @override
  String get settingsMemorySubtitle => '管理用戶記憶開關與持久化檔案位置。';

  @override
  String get settingsPersistenceRecoveredTitle => '設定檔案已自動恢復';

  @override
  String get settingsPersistenceRecoveredBody =>
      '檢測到設定檔案內容損壞或被竄改，OpenHand 已備份異常檔案并恢復為安全預設值。';

  @override
  String get settingsPersistenceSanitizedTitle => '設定內容已自動修正';

  @override
  String get settingsPersistenceSanitizedBody =>
      '檢測到部分設定內容無效，OpenHand 已忽略異常欄位并重新寫回有效配置。';

  @override
  String get settingsPersistenceSaveFailedTitle => '設定儲存失敗';

  @override
  String get settingsPersistenceSaveFailedBody =>
      '設定檔案寫入失敗，界面已回復到上一次有效配置，請檢查檔案權限或磁碟狀態。';

  @override
  String get settingsPersistenceDismiss => '關閉提示';

  @override
  String get aiModelAdd => '新增提供者';

  @override
  String get aiModelsEmptyTitle => '還沒有可用模型提供者';

  @override
  String get aiModelsEmptyBody => '先添加至少一個模型提供者配置，後續執行緒聊天窗口會直接複用這裡的模型列表。';

  @override
  String get aiModelDialogCreateTitle => '新增模型提供者';

  @override
  String get aiModelDialogEditTitle => '編輯模型提供者';

  @override
  String get aiModelBaseUrl => 'Base URL';

  @override
  String get aiModelBaseUrlRequired => '請輸入 Base URL';

  @override
  String get aiModelBaseUrlInvalid => '請輸入有效的 Base URL';

  @override
  String get aiModelAuthScheme => '驗證方式';

  @override
  String get aiModelToken => '權杖';

  @override
  String get aiModelIdField => '模型 ID';

  @override
  String get aiModelIdRequired => '請輸入模型 ID';

  @override
  String get aiModelProtocol => '協議類型';

  @override
  String get aiModelSaveSuccess => '模型提供者配置已儲存。';

  @override
  String get aiModelDeleteConfirmTitle => '刪除模型提供者';

  @override
  String get aiModelDeleteConfirmBody => '確認刪除這條模型提供者配置嗎？';

  @override
  String get aiModelDeleteSuccess => '模型提供者配置已刪除。';

  @override
  String get aiModelMoveUp => '上移';

  @override
  String get aiModelMoveDown => '下移';

  @override
  String get aiModelSelected => '目前活躍提供者';

  @override
  String get aiModelNoToken => '未配置權杖';

  @override
  String get aiModelTest => '測試';

  @override
  String get aiModelTesting => '測試中';

  @override
  String aiModelTestSuccess(Object modelName) {
    return '$modelName 測試通過。';
  }

  @override
  String aiModelTestFailure(Object modelName, Object reason) {
    return '$modelName 測試失敗：$reason';
  }

  @override
  String get aiModelSelectionRequired => '請先在設定中添加并選擇一個 AI 模型提供者。';

  @override
  String get aiModelScanButton => '掃描模型';

  @override
  String get aiModelScanning => '正在掃描可用模型…';

  @override
  String aiModelScanSuccess(Object count) {
    return '發現 $count 個模型。';
  }

  @override
  String aiModelScanFailed(Object reason) {
    return '掃描失敗：$reason';
  }

  @override
  String get aiModelScanEmpty => '未從該提供者掃描到模型。';

  @override
  String get aiModelAvailableModels => '可用模型';

  @override
  String get aiModelManualIdHint => '手動輸入模型 ID';

  @override
  String get aiModelManualIdAdd => '添加';

  @override
  String aiModelCount(Object count) {
    return '$count 個模型';
  }

  @override
  String get chatModelButton => '選擇模型';

  @override
  String get aiAuthNone => '無';

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
  String get aiProtocolQwen => '通義千問';

  @override
  String get aiProtocolSeed => '豆包 (火山方舟)';

  @override
  String get aiProtocolStepFun => '階躍星辰';

  @override
  String get aiProtocolMinimax => 'MiniMax';

  @override
  String get aiProtocolLongCat => 'LongCat';

  @override
  String get aiProtocolJoyCode => 'JoyCode';

  @override
  String get aiProtocolWenxin => '文心一言 (ERNIE)';

  @override
  String get aiProtocolMeta => 'Meta AI (Llama)';

  @override
  String get aiProtocolMimo => 'MIMO (小米)';

  @override
  String get aiProtocolHunyuan => '混元 (騰訊)';

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
  String get skillsCreateDialogTitle => '新增技能';

  @override
  String get skillsCreateNameLabel => '技能名稱';

  @override
  String get skillsCreateNameRequired => '請輸入技能名稱';

  @override
  String get skillsCreateIconLabel => '技能圖示';

  @override
  String get skillsCreateIconHint => '請選擇表情或本機圖片';

  @override
  String get skillsCreateIconRequired => '請選擇技能圖示';

  @override
  String get skillsCreateIconChoose => '選擇表情';

  @override
  String get skillsCreateIconChange => '重新選擇';

  @override
  String get skillsCreateImageChoose => '選擇圖片';

  @override
  String get skillsCreateImageChange => '更換圖片';

  @override
  String get skillsCreateImageSelected => '已選擇本機圖片';

  @override
  String get skillsCreateDescriptionLabel => '技能簡介';

  @override
  String get skillsCreateDescriptionRequired => '請輸入技能簡介';

  @override
  String get skillsCreateContentRequired => '請輸入 SKILL.md 內容';

  @override
  String get imageEditorTitle => '編輯圖片';

  @override
  String get imageEditorCropHint =>
      '拖動方框調整裁剪區域，可繼續縮放、旋轉、翻轉，展開下方面板可使用 HSL、色調分離、清晰度、顆粒、降噪、色散、扭曲、浮水印等高級調整（高級調整在儲存時應用）。';

  @override
  String get imageEditorZoomLabel => '縮放';

  @override
  String get imageEditorBrightnessLabel => '亮度';

  @override
  String get imageEditorContrastLabel => '對比度';

  @override
  String get imageEditorRotateLeft => '左轉';

  @override
  String get imageEditorRotateRight => '右轉';

  @override
  String get imageEditorReset => '重置';

  @override
  String get imageEditorLoadFailed => '無法載入所選圖片';

  @override
  String get imageEditorProcessFailed => '無法處理所選圖片';

  @override
  String get imageEditorSectionBasic => '基礎調整';

  @override
  String get imageEditorSectionColor => '色彩（色溫 / 色調 / 伽瑪）';

  @override
  String get imageEditorSectionSplitToning => '色調分離（HSL）';

  @override
  String get imageEditorSectionDetail => '細節（清晰度 / 銳利度 / 降噪 / 顆粒）';

  @override
  String get imageEditorSectionEffects => '特效（色散 / 扭曲 / 暈影）';

  @override
  String get imageEditorSectionWatermark => '文字浮水印 / 標記';

  @override
  String get imageEditorTemperatureLabel => '色溫';

  @override
  String get imageEditorTintLabel => '色調偏移';

  @override
  String get imageEditorGammaLabel => '伽瑪（曲線）';

  @override
  String get imageEditorShadowHueLabel => '暗部色相';

  @override
  String get imageEditorShadowStrengthLabel => '暗部強度';

  @override
  String get imageEditorHighlightHueLabel => '亮部色相';

  @override
  String get imageEditorHighlightStrengthLabel => '亮部強度';

  @override
  String get imageEditorClarityLabel => '清晰度';

  @override
  String get imageEditorSharpnessLabel => '銳利度';

  @override
  String get imageEditorDenoiseLabel => '降噪';

  @override
  String get imageEditorGrainLabel => '顆粒';

  @override
  String get imageEditorDispersionLabel => '色散';

  @override
  String get imageEditorDistortLabel => '扭曲（正值凸出 / 負值拉伸）';

  @override
  String get imageEditorWatermarkTextLabel => '浮水印文字';

  @override
  String get imageEditorWatermarkTextHint => '輸入要疊加的文字（留空則不添加）';

  @override
  String get imageEditorWatermarkSizeLabel => '文字大小';

  @override
  String get imageEditorWatermarkOpacityLabel => '不透明度';

  @override
  String get imageEditorWatermarkPositionLabel => '位置';

  @override
  String get imageEditorWatermarkColorLight => '淺色';

  @override
  String get imageEditorWatermarkColorDark => '深色';

  @override
  String get imageEditorAdvancedApplyHint => '展開面板中的調整會在“儲存”時一次性套用到原圖。';

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
  String get instructionPageTitle => '指令';

  @override
  String get instructionPageSubtitle =>
      '維護應用內的可複用提示詞片段。啟用的指令會按目前順序注入到所有執行緒模板的 system prompt，並在會話輸入框上方以膠囊形式列出，可在單次送出前臨時取消或重新加入。';

  @override
  String get instructionRefresh => '重新整理';

  @override
  String get instructionNewEntry => '新增指令';

  @override
  String get instructionEmptyTitle => '尚未建立指令';

  @override
  String get instructionEmptyBody => '新增第一條可複用指令後，OpenHand 會把它保存到本機指令庫中。';

  @override
  String get instructionLoadFailedTitle => '指令庫讀取失敗';

  @override
  String get instructionDeleteConfirmTitle => '刪除指令';

  @override
  String get instructionDeleteConfirmBody => '確認刪除這條指令嗎？刪除後無法復原。';

  @override
  String get instructionEnabledStatus => '已啟用並注入';

  @override
  String get instructionDisabledStatus => '已停用';

  @override
  String get instructionApplyToChipLabel => '適用';

  @override
  String get instructionNotesChipLabel => '備註';

  @override
  String get instructionDialogCreateTitle => '新增指令';

  @override
  String get instructionDialogEditTitle => '編輯指令';

  @override
  String get instructionEnabledLabel => '啟用';

  @override
  String get instructionEnabledBody => '將這條指令注入到目前提示鏈中。';

  @override
  String get instructionNameField => '名稱 *';

  @override
  String get instructionNameRequired => '請輸入名稱。';

  @override
  String get instructionDescriptionField => '描述';

  @override
  String get instructionVersionField => '版本';

  @override
  String get instructionApplyToField => '適用範圍（描述何時載入這條指令）';

  @override
  String get instructionTaskTypesField => '觸發任務類型（逗號分隔）';

  @override
  String get instructionKeywordsField => '觸發關鍵字（逗號分隔）';

  @override
  String get instructionNotesField => '備註（每行一條）';

  @override
  String get instructionBodyField => '指令正文 *（Markdown）';

  @override
  String get instructionBodyRequired => '請輸入指令正文。';

  @override
  String get instructionCreateAction => '建立';

  @override
  String get instructionSaveFailed => '保存失敗，請檢查必填項是否為空。';

  @override
  String get memoryPageTitle => '記憶';

  @override
  String get memoryPageSubtitle => '統一維護用戶可編輯記憶，所有條目會持久化到本機 JSON 檔案。';

  @override
  String get memoryRefresh => '重新整理';

  @override
  String get memoryNewEntry => '新增記憶';

  @override
  String get memoryEmptyTitle => '還沒有任何用戶記憶';

  @override
  String get memoryEmptyBody => '新增一條用戶記憶後，它會持久化儲存到目前配置的記憶檔案中。';

  @override
  String get memoryLoadFailedTitle => '記憶檔案讀取失敗';

  @override
  String get memoryOperationFailed => '記憶操作失敗，請稍後重試。';

  @override
  String get memoryDialogCreateTitle => '新增用戶記憶';

  @override
  String get memoryDialogEditTitle => '編輯用戶記憶';

  @override
  String get memoryContentField => '記憶內容';

  @override
  String get memoryContentRequired => '請輸入記憶內容';

  @override
  String get memoryTagsField => '標簽';

  @override
  String get memoryTagsHint => '輸入一個標簽後按回車添加';

  @override
  String get memoryDeleteConfirmTitle => '刪除用戶記憶';

  @override
  String get memoryDeleteConfirmBody => '確認刪除這條用戶記憶嗎？刪除後無法恢復。';

  @override
  String get memoryTypeUser => '用戶編輯';

  @override
  String get memoryEntryCreated => '用戶記憶已建立';

  @override
  String get memoryEntryUpdated => '用戶記憶已更新';

  @override
  String get memoryEntryDeleted => '用戶記憶已刪除';

  @override
  String get memoryEnabledLabel => '啟用記憶能力';

  @override
  String get memoryEnabledBody => '關閉後不會在運行時使用用戶記憶，但仍然保留已儲存的記憶內容。';

  @override
  String get userMemoryFileLabel => '用戶記憶檔案';

  @override
  String get memoryFileBody =>
      '配置用戶記憶 JSON 檔案位置。預設會使用目前程序目錄下的 .openhand/memory/user-memory.json。';

  @override
  String get memoryFileDefaultPath => '預設檔案';

  @override
  String get memoryFileSave => '儲存路徑';

  @override
  String get memoryFileBrowse => '選擇檔案';

  @override
  String get memoryFileReset => '恢復預設';

  @override
  String get memoryOpenDirectory => '打開目錄';

  @override
  String get memoryPathSaved => '用戶記憶檔案路徑已更新';

  @override
  String get memoryDisabledTitle => '記憶能力目前已關閉';

  @override
  String get memoryDisabledBody => '你仍然可以在這裡維護用戶記憶內容；如需在運行時啟用，請到設定頁記憶板塊打開記憶開關。';

  @override
  String get memoryCreatedAtLabel => '建立時間';

  @override
  String get memoryPersistenceRecoveredTitle => '記憶檔案已自動恢復';

  @override
  String get memoryPersistenceRecoveredBody =>
      '檢測到記憶檔案內容損壞或被竄改，OpenHand 已備份異常檔案并恢復為空列表。';

  @override
  String get memoryPersistenceSanitizedTitle => '記憶內容已自動修正';

  @override
  String get memoryPersistenceSanitizedBody =>
      '檢測到部分記憶欄位無效，OpenHand 已忽略異常條目并重新寫回有效內容。';

  @override
  String get memoryPersistenceSaveFailedTitle => '記憶檔案儲存失敗';

  @override
  String get memoryPersistenceSaveFailedBody =>
      '寫入記憶檔案失敗，界面已回復到上一次有效內容，請檢查檔案權限或磁碟狀態。';

  @override
  String get mcpPageTitle => 'MCP';

  @override
  String get mcpPageSubtitle => '參考 Cursor 的 MCP 服務管理結構，統一維護本機 MCP Server 配置。';

  @override
  String get mcpRefresh => '重新整理';

  @override
  String get mcpNewServer => '新增服務';

  @override
  String get mcpEmptyTitle => '還沒有配置任何 MCP 服務';

  @override
  String get mcpEmptyBody =>
      '先新增一個 MCP Server，OpenHand 會把它儲存到 ~/.openhand/mcp/mcp_servers.json 中。';

  @override
  String get mcpLoadFailedTitle => 'MCP 配置讀取失敗';

  @override
  String get mcpOperationFailed => 'MCP 操作失敗，請稍後重試。';

  @override
  String get mcpDialogCreateTitle => '新增 MCP 服務';

  @override
  String get mcpDialogEditTitle => '編輯 MCP 服務';

  @override
  String get mcpNameField => '服務名稱';

  @override
  String get mcpNameRequired => '請輸入服務名稱';

  @override
  String get mcpNameDuplicate => '服務名稱已存在';

  @override
  String get mcpTypeField => '服務類型';

  @override
  String get mcpUrlField => '服務 URL';

  @override
  String get mcpUrlRequired => '請輸入服務 URL';

  @override
  String get mcpUrlInvalid => '請輸入有效的服務 URL';

  @override
  String get mcpCommandField => '啟動命令';

  @override
  String get mcpCommandRequired => '請輸入啟動命令';

  @override
  String get mcpArgsField => '命令參數';

  @override
  String get mcpArgsHint => '每行一個參數';

  @override
  String get mcpServerEnabledLabel => '啟用該服務';

  @override
  String get mcpServerEnabledBody => '關閉後會保留服務配置，但不會在運行時啟用它。';

  @override
  String get mcpServerStatusEnabled => '已啟用';

  @override
  String get mcpServerStatusDisabled => '已禁用';

  @override
  String get mcpServerCreated => 'MCP 服務已建立';

  @override
  String get mcpServerUpdated => 'MCP 服務已更新';

  @override
  String get mcpServerDeleted => 'MCP 服務已刪除';

  @override
  String get mcpDeleteConfirmTitle => '刪除 MCP 服務';

  @override
  String get mcpDeleteConfirmBody => '確認刪除這條 MCP 服務配置嗎？';

  @override
  String get mcpDisabledTitle => 'MCP 服務目前已關閉';

  @override
  String get mcpDisabledBody =>
      '你仍然可以在這裡維護服務配置；如需在運行時啟用，請到設定頁 MCP 板塊打開 MCP 開關。';

  @override
  String get mcpTransportStreamableHttp => 'Streamable HTTP';

  @override
  String get mcpTransportSse => 'SSE';

  @override
  String get mcpTransportStdio => 'STDIO';

  @override
  String get mcpPersistenceRecoveredTitle => 'MCP 配置檔案已自動恢復';

  @override
  String get mcpPersistenceRecoveredBody =>
      '檢測到 MCP 配置檔案內容損壞或被竄改，OpenHand 已備份異常檔案并恢復為空配置。';

  @override
  String get mcpPersistenceSanitizedTitle => 'MCP 配置內容已自動修正';

  @override
  String get mcpPersistenceSanitizedBody =>
      '檢測到部分 MCP 服務欄位無效，OpenHand 已忽略異常條目并重新寫回有效配置。';

  @override
  String get mcpPersistenceSaveFailedTitle => 'MCP 配置儲存失敗';

  @override
  String get mcpPersistenceSaveFailedBody =>
      '寫入 MCP 配置檔案失敗，界面已回復到上一次有效配置，請檢查檔案權限或磁碟狀態。';

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

  @override
  String get aiToolResultCompressionThresholdLabel => '工具呼叫輸出壓縮閾值';

  @override
  String get aiToolResultCompressionThresholdBody =>
      '當某個工具呼叫返回的 raw 內容字元數超過該閾值時，OpenHand 會在組裝 conversation history 前將其壓縮為「受影響路徑+目的+首尾片段」的結構化摘要，釋放 tokens。預設 1024。';

  @override
  String get aiToolResultCompressionThresholdSave => '儲存閾值';

  @override
  String get aiToolResultCompressionThresholdSaved => '工具呼叫輸出壓縮閾值已更新。';

  @override
  String get aiToolResultCompressionThresholdInvalid => '請輸入有效的正整數閾值。';

  @override
  String get aiToolResultCompressionEnabledLabel => '啟用工具呼叫輸出壓縮';

  @override
  String get aiToolResultCompressionEnabledBody =>
      '總開關。關閉後不管閾值多大都不壓縮工具輸出原文，適合需要調試完整輸出的場景。';

  @override
  String get aiToolResultCompressionHeadTailWindowLabel => '壓縮摘要首尾片段視窗';

  @override
  String get aiToolResultCompressionHeadTailWindowBody =>
      '壓縮後摘要中保留 raw 輸出首尾各多少個字元。預設 256；0 表示不保留首尾片段；範圍 0~8192。';

  @override
  String get aiToolResultCompressionHeadTailWindowSave => '儲存視窗長度';

  @override
  String get aiToolResultCompressionHeadTailWindowSaved => '首尾片段視窗已更新。';

  @override
  String get aiToolResultCompressionHeadTailWindowInvalid =>
      '請輸入 0~8192 之間的整數。';

  @override
  String get aiToolResultCompressionMaxPathHitsLabel => '壓縮摘要擷取路徑上限';

  @override
  String get aiToolResultCompressionMaxPathHitsBody =>
      '壓縮後摘要中擷取受影響檔案路徑的最大條數。預設 12；0 表示不擷取；範圍 0~200。';

  @override
  String get aiToolResultCompressionMaxPathHitsSave => '儲存上限';

  @override
  String get aiToolResultCompressionMaxPathHitsSaved => '路徑擷取上限已更新。';

  @override
  String get aiToolResultCompressionMaxPathHitsInvalid => '請輸入 0~200 之間的整數。';

  @override
  String get aiWriteToolSummaryMaxCharsLabel => '寫類工具摘要字元上限';

  @override
  String get aiWriteToolSummaryMaxCharsBody =>
      '寫類工具（write/edit/multiedit/notebookedit/寫型 bash）結果摘要中保留 result_text 原文的最大字元數。預設 280；0 表示不保留；範圍 0~8192。';

  @override
  String get aiWriteToolSummaryMaxCharsSave => '儲存上限';

  @override
  String get aiWriteToolSummaryMaxCharsSaved => '寫類工具摘要字元上限已更新。';

  @override
  String get aiWriteToolSummaryMaxCharsInvalid => '請輸入 0~8192 之間的整數。';

  @override
  String get aiMaxRecentErrorsLabel => '會話錯誤紀錄保留上限';

  @override
  String get aiMaxRecentErrorsBody => 'AI 會話狀態中保留的最近錯誤紀錄條數。預設 20；範圍 0~1000。';

  @override
  String get aiMaxRecentErrorsSave => '儲存上限';

  @override
  String get aiMaxRecentErrorsSaved => '會話錯誤紀錄保留上限已更新。';

  @override
  String get aiMaxRecentErrorsInvalid => '請輸入 0~1000 之間的整數。';

  @override
  String get aiMaxPlanHistoryEntriesLabel => '計畫歷史保留上限';

  @override
  String get aiMaxPlanHistoryEntriesBody =>
      'Plan 模式下 plan_history 保留的最大條目數。預設 20；範圍 0~1000。';

  @override
  String get aiMaxPlanHistoryEntriesSave => '儲存上限';

  @override
  String get aiMaxPlanHistoryEntriesSaved => '計畫歷史保留上限已更新。';

  @override
  String get aiMaxPlanHistoryEntriesInvalid => '請輸入 0~1000 之間的整數。';

  @override
  String get aiMaxTruncationContinuationsLabel => '自動接續輪次上限';

  @override
  String get aiMaxTruncationContinuationsBody =>
      '模型輸出被截斷（finish_reason=length）後自動接續的最大次數。預設 5；範圍 0~100。';

  @override
  String get aiMaxTruncationContinuationsSave => '儲存上限';

  @override
  String get aiMaxTruncationContinuationsSaved => '自動接續輪次上限已更新。';

  @override
  String get aiMaxTruncationContinuationsInvalid => '請輸入 0~100 之間的整數。';

  @override
  String get aiEstimatedCharactersPerTokenLabel => 'Token 字元估算係數';

  @override
  String get aiEstimatedCharactersPerTokenBody =>
      '每個 token 約等於多少個字元，用於上下文容量估算。預設 4；範圍 1~32。';

  @override
  String get aiEstimatedCharactersPerTokenSave => '儲存係數';

  @override
  String get aiEstimatedCharactersPerTokenSaved => 'Token 字元估算係數已更新。';

  @override
  String get aiEstimatedCharactersPerTokenInvalid => '請輸入 1~32 之間的整數。';

  @override
  String get aiMaxToolOutputCharsLabel => '工具單次輸出字元上限';

  @override
  String get aiMaxToolOutputCharsBody =>
      '預設 200000。單次工具呼叫結果若超過此字元數會截斷，避免 Context 溢出。';

  @override
  String get aiMaxToolOutputCharsSave => '儲存上限';

  @override
  String get aiMaxToolOutputCharsSaved => '工具輸出字元上限已儲存。';

  @override
  String get aiMaxToolOutputCharsInvalid => '請輸入 1000~10000000 之間的整數。';

  @override
  String get aiWriteConfirmationTimeoutMsLabel => '寫命令確認逾時（毫秒）';

  @override
  String get aiWriteConfirmationTimeoutMsBody =>
      '預設 300000（5 分鐘）。等待使用者審核寫命令的最長時間。';

  @override
  String get aiWriteConfirmationTimeoutMsSave => '儲存逾時';

  @override
  String get aiWriteConfirmationTimeoutMsSaved => '寫命令確認逾時已儲存。';

  @override
  String get aiWriteConfirmationTimeoutMsInvalid => '請輸入 1000~3600000 之間的整數。';

  @override
  String get aiFastPathWriteAnalysisThresholdLabel => 'Fast-path 寫命令分析閾值';

  @override
  String get aiFastPathWriteAnalysisThresholdBody =>
      '預設 512 字元。命令長度超過此值會走快速路徑粗判，避免昂貴的語法分析。';

  @override
  String get aiFastPathWriteAnalysisThresholdSave => '儲存閾值';

  @override
  String get aiFastPathWriteAnalysisThresholdSaved => 'Fast-path 閾值已儲存。';

  @override
  String get aiFastPathWriteAnalysisThresholdInvalid => '請輸入 0~100000 之間的整數。';

  @override
  String get aiMaxHookTextCharactersLabel => 'Hook 文字輸出上限';

  @override
  String get aiMaxHookTextCharactersBody =>
      '預設 4000。Claude Hook 在合併 stdout/stderr 文字時的總字元上限。';

  @override
  String get aiMaxHookTextCharactersSave => '儲存上限';

  @override
  String get aiMaxHookTextCharactersSaved => 'Hook 文字上限已儲存。';

  @override
  String get aiMaxHookTextCharactersInvalid => '請輸入 100~1000000 之間的整數。';

  @override
  String get aiWebFetchMaxResponseBytesLabel => 'WebFetch 單次回應位元組上限';

  @override
  String get aiWebFetchMaxResponseBytesBody =>
      '默认 1048576（1MB）。調整以適配你的網路與附件需求。';

  @override
  String get aiWebFetchMaxResponseBytesSave => '儲存';

  @override
  String get aiWebFetchMaxResponseBytesSaved => 'WebFetch 單次回應位元組上限已儲存。';

  @override
  String get aiWebFetchMaxResponseBytesInvalid => '請輸入有效整數。';

  @override
  String get aiWebFetchMaxRedirectsLabel => 'WebFetch 最大重新導向次數';

  @override
  String get aiWebFetchMaxRedirectsBody => '默认 5。調整以適配你的網路與附件需求。';

  @override
  String get aiWebFetchMaxRedirectsSave => '儲存';

  @override
  String get aiWebFetchMaxRedirectsSaved => 'WebFetch 最大重新導向次數已儲存。';

  @override
  String get aiWebFetchMaxRedirectsInvalid => '請輸入有效整數。';

  @override
  String get aiWebFetchMaxCacheEntriesLabel => 'WebFetch 快取條目上限';

  @override
  String get aiWebFetchMaxCacheEntriesBody => '默认 64。調整以適配你的網路與附件需求。';

  @override
  String get aiWebFetchMaxCacheEntriesSave => '儲存';

  @override
  String get aiWebFetchMaxCacheEntriesSaved => 'WebFetch 快取條目上限已儲存。';

  @override
  String get aiWebFetchMaxCacheEntriesInvalid => '請輸入有效整數。';

  @override
  String get aiAttachmentMaxInlineImageDimensionLabel => '附件圖片最大邊長（像素）';

  @override
  String get aiAttachmentMaxInlineImageDimensionBody =>
      '默认 1568。調整以適配你的網路與附件需求。';

  @override
  String get aiAttachmentMaxInlineImageDimensionSave => '儲存';

  @override
  String get aiAttachmentMaxInlineImageDimensionSaved => '附件圖片最大邊長（像素）已儲存。';

  @override
  String get aiAttachmentMaxInlineImageDimensionInvalid => '請輸入有效整數。';

  @override
  String get aiAttachmentMaxTextRawBytesLabel => '附件文字讀取上限（位元組）';

  @override
  String get aiAttachmentMaxTextRawBytesBody =>
      '默认 1597152（2MB）。調整以適配你的網路與附件需求。';

  @override
  String get aiAttachmentMaxTextRawBytesSave => '儲存';

  @override
  String get aiAttachmentMaxTextRawBytesSaved => '附件文字讀取上限（位元組）已儲存。';

  @override
  String get aiAttachmentMaxTextRawBytesInvalid => '請輸入有效整數。';

  @override
  String get aiAttachmentMaxPdfRawBytesLabel => '附件 PDF 讀取上限（位元組）';

  @override
  String get aiAttachmentMaxPdfRawBytesBody =>
      '默认 1597152（2MB）。調整以適配你的網路與附件需求。';

  @override
  String get aiAttachmentMaxPdfRawBytesSave => '儲存';

  @override
  String get aiAttachmentMaxPdfRawBytesSaved => '附件 PDF 讀取上限（位元組）已儲存。';

  @override
  String get aiAttachmentMaxPdfRawBytesInvalid => '請輸入有效整數。';

  @override
  String get aiAttachmentMaxImageRawBytesLabel => '附件圖片讀取上限（位元組）';

  @override
  String get aiAttachmentMaxImageRawBytesBody =>
      '默认 52428800（50MB）。調整以適配你的網路與附件需求。';

  @override
  String get aiAttachmentMaxImageRawBytesSave => '儲存';

  @override
  String get aiAttachmentMaxImageRawBytesSaved => '附件圖片讀取上限（位元組）已儲存。';

  @override
  String get aiAttachmentMaxImageRawBytesInvalid => '請輸入有效整數。';

  @override
  String get aiChatMaxStreamLineBufferBytesLabel => 'Chat 串流緩衝位元組上限';

  @override
  String get aiChatMaxStreamLineBufferBytesBody =>
      '默认 4194304（4MB）。調整以適配你的網路與附件需求。';

  @override
  String get aiChatMaxStreamLineBufferBytesSave => '儲存';

  @override
  String get aiChatMaxStreamLineBufferBytesSaved => 'Chat 串流緩衝位元組上限已儲存。';

  @override
  String get aiChatMaxStreamLineBufferBytesInvalid => '請輸入有效整數。';

  @override
  String get aiFallbackTitleMaxCharactersLabel => '回退標題最大字元數';

  @override
  String get aiFallbackTitleMaxCharactersBody => '默认 15。調整以符合會話標題派生策略。';

  @override
  String get aiFallbackTitleMaxCharactersSave => '儲存';

  @override
  String get aiFallbackTitleMaxCharactersSaved => '回退標題最大字元數已儲存。';

  @override
  String get aiFallbackTitleMaxCharactersInvalid => '請輸入有效整數。';

  @override
  String get aiGeneratedTitleMaxCharactersLabel => '自動標題最大字元數';

  @override
  String get aiGeneratedTitleMaxCharactersBody => '默认 15。調整以符合會話標題派生策略。';

  @override
  String get aiGeneratedTitleMaxCharactersSave => '儲存';

  @override
  String get aiGeneratedTitleMaxCharactersSaved => '自動標題最大字元數已儲存。';

  @override
  String get aiGeneratedTitleMaxCharactersInvalid => '請輸入有效整數。';

  @override
  String get aiMinimumMeaningfulTitleCharactersLabel => '中文有效標題最小字元數';

  @override
  String get aiMinimumMeaningfulTitleCharactersBody => '默认 4。調整以符合會話標題派生策略。';

  @override
  String get aiMinimumMeaningfulTitleCharactersSave => '儲存';

  @override
  String get aiMinimumMeaningfulTitleCharactersSaved => '中文有效標題最小字元數已儲存。';

  @override
  String get aiMinimumMeaningfulTitleCharactersInvalid => '請輸入有效整數。';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsLabel => '拉丁有效標題最小詞數';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsBody => '默认 2。調整以符合會話標題派生策略。';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsSave => '儲存';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsSaved => '拉丁有效標題最小詞數已儲存。';

  @override
  String get aiMinimumMeaningfulLatinTitleWordsInvalid => '請輸入有效整數。';

  @override
  String get aiMaxSkillContentLengthLabel => '技能檔案內容字元上限';

  @override
  String get aiMaxSkillContentLengthBody => '默认 100000。調整以符合技能與工作區文件大小。';

  @override
  String get aiMaxSkillContentLengthSave => '儲存';

  @override
  String get aiMaxSkillContentLengthSaved => '技能檔案內容字元上限已儲存。';

  @override
  String get aiMaxSkillContentLengthInvalid => '請輸入有效整數。';

  @override
  String get aiMaxWorkspaceDocumentCharactersLabel => '工作區指令文件字元上限';

  @override
  String get aiMaxWorkspaceDocumentCharactersBody =>
      '默认 16000。調整以符合技能與工作區文件大小。';

  @override
  String get aiMaxWorkspaceDocumentCharactersSave => '儲存';

  @override
  String get aiMaxWorkspaceDocumentCharactersSaved => '工作區指令文件字元上限已儲存。';

  @override
  String get aiMaxWorkspaceDocumentCharactersInvalid => '請輸入有效整數。';

  @override
  String get aiImageSizeLimitLabel => '圖片大小上限';

  @override
  String get aiImageSizeLimitBody =>
      '當用戶添加的圖片附件超過該上限時，OpenHand 會自動按質量 + 尺寸兩級壓縮後再傳送。支持小數 MB；範圍 0.0625 MB（64 KB）至 64 MB。';

  @override
  String get aiImageSizeLimitFieldLabel => '上限 (MB)';

  @override
  String get aiImageSizeLimitSave => '儲存上限';

  @override
  String get aiImageSizeLimitSaved => '圖片附件大小上限已更新。';

  @override
  String get aiImageSizeLimitInvalid => '請輸入有效的正數 MB 值。';

  @override
  String get imageEditorAspectFree => '自由';

  @override
  String get imageEditorAspectOriginal => '原始';

  @override
  String get imageEditorAspectSquare => '1:1';

  @override
  String get imageEditorAspect4x3 => '4:3';

  @override
  String get imageEditorAspect3x4 => '3:4';

  @override
  String get imageEditorAspect16x9 => '16:9';

  @override
  String get imageEditorAspect9x16 => '9:16';

  @override
  String get imageEditorAspectCircle => '圓形';

  @override
  String get imageEditorFlipHorizontal => '水平翻轉';

  @override
  String get imageEditorFlipVertical => '垂直翻轉';

  @override
  String get imageEditorSaturationLabel => '飽和度';

  @override
  String get imageEditorExposureLabel => '曝光';

  @override
  String get imageEditorHueLabel => '色相';

  @override
  String get imageEditorVignetteLabel => '暗角';

  @override
  String get imageEditorFineRotationLabel => '微調旋轉 (°)';

  @override
  String get imageEditorSaveToFile => '另存到本機';

  @override
  String get imageEditorCopyToClipboard => '複製到剪貼簿';

  @override
  String imageEditorSavedTo(String path) {
    return '已另存：$path';
  }

  @override
  String imageEditorSaveFailed(String error) {
    return '另存失敗：$error';
  }

  @override
  String get imageEditorClipboardCopiedBitmap => '已複製圖片到剪貼簿（檔案路徑同時複製為文字）。';

  @override
  String imageEditorClipboardCopiedPath(String path) {
    return '已複製圖片檔案路徑到剪貼簿：$path';
  }

  @override
  String imageEditorClipboardFailed(String error) {
    return '複製失敗：$error';
  }

  @override
  String get imageEditorApplyButton => '應用';

  @override
  String get imageEditorUndoButton => '復原';

  @override
  String get imageEditorResetAllButton => '重置全部';

  @override
  String get imageEditorCompareHold => '按住比較';

  @override
  String get imageEditorCompareRelease => '放開返回';

  @override
  String get imageEditorCompareOriginal => '原圖';

  @override
  String get imageEditorWatermarkColorLabel => '文字顏色';

  @override
  String get imageEditorWatermarkColorHue => '顏色（Hue）';

  @override
  String get imageEditorWatermarkColorSaturation => '飽和度';

  @override
  String get imageEditorWatermarkColorLightness => '明度';

  @override
  String get imageEditorApplySuccess => '調整已應用';

  @override
  String get imageEditorProcessing => '處理中…';

  @override
  String get builtinToolTimeoutLabel => '超時時間（秒）';

  @override
  String builtinToolTimeoutHint(int seconds) {
    return '預設 ${seconds}s';
  }

  @override
  String builtinToolTimeoutHelper(int seconds) {
    return '留空則使用預設 ${seconds}s';
  }

  @override
  String get builtinToolRetryLabel => '失敗/超時自動重試';

  @override
  String get builtinToolRetryBody =>
      '預設關閉。僅對真正失敗 (failed/timed_out) 觸發，不會重試參數錯誤或被拒絕的呼叫。';

  @override
  String builtinToolMaxRetriesLabel(int max) {
    return '最大重試次數 (0–$max)';
  }

  @override
  String builtinToolMaxRetriesHelper(int max) {
    return '不含首次執行；上限 $max 次';
  }

  @override
  String get builtinToolBackoffLabel => '重試退避基線（毫秒）';

  @override
  String builtinToolBackoffHint(int ms) {
    return '預設 ${ms}ms';
  }

  @override
  String builtinToolBackoffHelper(int max) {
    return '指數退避：第 N 次重試等待 base × 2^(N-1)ms，上限 ${max}ms';
  }

  @override
  String selfLearningFlushIntervalLabel(int ms) {
    return '串流刷新間隔：${ms}ms';
  }

  @override
  String selfLearningFlushIntervalHelper(int min, int max) {
    return '自我學習卡片串流輸出的持久化間隔（$min–${max}ms）。調小=更即時但更多布局抖動；調大=更平滑但增量延遲更高。預設 600ms。';
  }

  @override
  String get tsmRenameThreadTitle => '重新命名執行緒';

  @override
  String get tsmRenameHint => '輸入執行緒標題';

  @override
  String get tsmRenameFailed => '重新命名失敗';

  @override
  String get tsmDeleteThreadTitle => '刪除執行緒';

  @override
  String get tsmDeleteSelectedTitle => '刪除選取的執行緒';

  @override
  String tsmDeleteSelectedConfirm(Object count) {
    return '將永久刪除 $count 個執行緒及其訊息，此操作無法復原。';
  }

  @override
  String tsmDeleteFailedCount(Object count) {
    return '$count 個執行緒刪除失敗';
  }

  @override
  String get tsmSessionMissing => '工作階段不存在或已刪除';

  @override
  String get tsmExportSessionDataTitle => '匯出工作階段資料';

  @override
  String tsmExportingSession(Object title) {
    return '正在匯出「$title」…';
  }

  @override
  String get tsmExportComplete => '匯出完成';

  @override
  String get tsmExportFailed => '匯出失敗';

  @override
  String get tsmChooseExportFolder => '選擇匯出資料夾';

  @override
  String get tsmBatchExportTitle => '批次匯出';

  @override
  String tsmBatchExportSubtitle(Object count) {
    return '即將匯出 $count 個執行緒…';
  }

  @override
  String tsmBatchExportDone(Object ok, Object failed) {
    return '批次匯出完成：成功 $ok 件 / 失敗 $failed 件';
  }

  @override
  String get tsmMenuPreview => '預覽';

  @override
  String get tsmMenuRename => '重新命名';

  @override
  String get tsmMenuExportSession => '匯出工作階段';

  @override
  String get tsmMenuPin => '釘選';

  @override
  String get tsmMenuUnpin => '取消釘選';

  @override
  String get tsmMenuArchive => '封存';

  @override
  String get tsmMenuUnarchive => '取消封存';

  @override
  String get tsmMenuDelete => '刪除';

  @override
  String get tsmPinUpdateFailed => '更新釘選狀態失敗';

  @override
  String get tsmArchiveUpdateFailed => '更新封存狀態失敗';

  @override
  String get tsmUntitledThread => '（未命名執行緒）';

  @override
  String tsmPreviewMessageCount(Object count) {
    return '$count 則訊息';
  }

  @override
  String get tsmClosePreview => '關閉預覽';

  @override
  String get tsmNoMessages => '沒有訊息';

  @override
  String get tsmEmptyMessage => '（空）';

  @override
  String get tsmSearchHint => '依標題或 ID 搜尋';

  @override
  String get tsmDensityComfortable => '舒適';

  @override
  String get tsmDensityCompact => '精簡';

  @override
  String get tsmAllTemplates => '所有範本';

  @override
  String tsmSortDisabledHint(Object mode) {
    return '目前依「$mode」排序，拖曳控制點已停用；切回「手動排序」即可重新排列。';
  }

  @override
  String get tsmSortManual => '手動排序';

  @override
  String get tsmSortUpdated => '最近更新';

  @override
  String get tsmSortCreated => '最近建立';

  @override
  String get tsmSortSize => '依大小';

  @override
  String get tsmSortMessages => '依訊息數';

  @override
  String get tsmSortToken => '依 Token 數';

  @override
  String get tsmHideArchived => '隱藏已封存';

  @override
  String get tsmShowArchived => '顯示已封存';

  @override
  String get tsmExitSelection => '結束多選';

  @override
  String get tsmEnterSelection => '多選';

  @override
  String get tsmClose => '關閉';

  @override
  String get tsmTitle => '執行緒工作階段管理';

  @override
  String tsmHeaderSubtitle(Object count) {
    return '共 $count 個執行緒 · 長按或拖曳控制點可重新排序，按兩下或按右鍵可叫出更多選項';
  }

  @override
  String tsmSelectedCount(Object count) {
    return '已選取 $count 個';
  }

  @override
  String get tsmBatchExportButton => '批次匯出';

  @override
  String get tsmDeleteSelectedButton => '刪除選取項目';

  @override
  String get tsmEmptyState => '尚無執行緒工作階段';

  @override
  String get tsmCancel => '取消';

  @override
  String get settingsThreadSessionManagementTitle => '執行緒工作階段管理';

  @override
  String get settingsThreadSessionManagementSubtitle =>
      '檢視所有執行緒的標題、建立／更新時間、佔用大小、訊息構成與 Token 統計。支援拖曳排序、多選刪除，並可用按兩下或按右鍵叫出重新命名／匯出／刪除選單。對話框的進場與退場動畫會依全域設定的對話框動畫設定。';

  @override
  String get settingsThreadSessionManagementOpen => '開啟管理視窗';

  @override
  String get settingsMessageGatewayTitle => '訊息閘道';

  @override
  String get settingsMessageGatewayDescription =>
      '設定訊息閘道的路由、轉換與節流策略。具體選項將於後續版本中釋出，目前為預留入口。';

  @override
  String get settingsMessageGatewayComingSoon => '即將推出';

  @override
  String get settingsMessageGatewayComingSoonSubtitle => '訊息閘道的詳細設定將於下一個迭代提供。';

  @override
  String get tsmRowUnknown => '未知';

  @override
  String get tsmRowCreated => '建立';

  @override
  String get tsmRowUpdated => '更新';

  @override
  String get tsmRowSize => '佔用';

  @override
  String get tsmRowMessages => '訊息';

  @override
  String get tsmRowToken => 'Token';

  @override
  String get tsmRowByKind => '佔比';

  @override
  String get proxySectionTitle => '系統';

  @override
  String get proxySectionBody =>
      '所有 OpenHand 內建 HTTP 客戶端（WebSearch / WebFetch 等）將按此處代理設定選擇路由。儲存後即時生效，無需重啟。';

  @override
  String get proxyModeLabel => '代理模式';

  @override
  String get proxyModeBody =>
      '決定 OpenHand 內建 HTTP 客戶端（WebSearch / WebFetch 等）如何選擇代理。';

  @override
  String get proxyModeDisabled => '無代理';

  @override
  String get proxyModeAutomatic => '自動偵測代理（預設）';

  @override
  String get proxyModeManual => '手動設定代理';

  @override
  String get proxyProtocolsLabel => '代理協定';

  @override
  String get proxyProtocolsBody => '可多選，至少保留一個；取消所有協定時會自動還原 HTTP + HTTPS。';

  @override
  String get proxyHostLabel => '伺服器（IP 或主機名稱）';

  @override
  String get proxyPortLabel => '埠號';

  @override
  String get proxyAuthLabel => '啟用代理伺服器驗證';

  @override
  String get proxyAuthBody => '啟用後下面的使用者名稱 / 密碼欄位才會被使用（HTTP Basic）。';

  @override
  String get proxyUsernameLabel => '使用者名稱';

  @override
  String get proxyPasswordLabel => '密碼';

  @override
  String get proxyExceptionsLabel => '忽略這些主機與網域的代理設定';

  @override
  String get proxyExceptionsBody =>
      '每行一條。支援：IP 位址（127.0.0.1）、IPv4 CIDR（192.168.0.0/16）、網域（example.com 含子網域）、glob（*.example.com）、正則（/^api\\d+\\.example\\.com\$/i）。localhost / 127.0.0.1 / ::1 永遠直連。';

  @override
  String get proxyExceptionsHint =>
      '範例：\n*.local\n10.0.0.0/8\n/^api\\d+\\.example\\.com\$/i';

  @override
  String get proxyTestButton => '測試代理連通性';

  @override
  String get proxyTesting => '測試中…';

  @override
  String proxyTestSuccess(Object latency, Object via) {
    return '連通成功（$latency ms，via $via）';
  }

  @override
  String proxyTestFailure(Object reason) {
    return '連通失敗：$reason';
  }

  @override
  String get proxyTestEndpointLabel => '測試 URL';

  @override
  String get proxyTestEndpointHint => '預設：https://www.google.com/generate_204';

  @override
  String get proxyTestVerdictDirect => '直連';

  @override
  String proxyTestVerdictProxy(Object endpoint) {
    return '代理 $endpoint';
  }

  @override
  String get proxyTestEndpointInvalid => '測試 URL 無效（需以 http:// 或 https:// 開頭）';

  @override
  String get proxyTestConsoleTitle => '代理連通性診斷';

  @override
  String get proxyTestConsoleRunning => '正在執行鏈路探測…';

  @override
  String get proxyTestConsoleSucceeded => '診斷完成：鏈路暢通';

  @override
  String get proxyTestConsoleFailed => '診斷完成：發現問題';

  @override
  String get proxyTestConsoleCopy => '複製日誌';

  @override
  String get proxyTestConsoleCopied => '日誌已複製到剪貼簿';

  @override
  String get proxyTestConsoleClose => '關閉';

  @override
  String get proxyTestConsoleRerun => '重新執行';

  @override
  String get proxyTestConsoleMaximize => '最大化';

  @override
  String get proxyTestConsoleRestore => '還原';

  @override
  String get proxyTestConsoleClear => '清空終端';

  @override
  String get tokenPopupCostHeading => '成本估算';

  @override
  String get tokenPopupCostInput => '輸入';

  @override
  String get tokenPopupCostOutput => '輸出';

  @override
  String get tokenPopupCostCacheRead => 'Cache 命中';

  @override
  String get tokenPopupCostCacheWrite => 'Cache 寫入';

  @override
  String get tokenPopupCostTotal => '總計';

  @override
  String get tokenDialUnit => 'Token';

  @override
  String get tokenDialTotal => '總計';

  @override
  String get tokenPopupInputHeading => '輸入';

  @override
  String get tokenPopupPrompt => 'Prompt';

  @override
  String get tokenPopupCacheRead => 'Cache 命中';

  @override
  String get tokenPopupCacheWrite => 'Cache 寫入';

  @override
  String get tokenPopupOutputHeading => '輸出';

  @override
  String get tokenPopupCompletion => 'Completion';

  @override
  String get tokenPopupGrandTotal => '總計';

  @override
  String get tokenPopupCacheHit => 'Cache 命中率';

  @override
  String get tokenPopupSessionHeading => '會話累計';

  @override
  String get tokenPopupMessages => '訊息總數';

  @override
  String get tokenPopupPromptBuilds => 'Prompt 構建';

  @override
  String get tokenPopupPromptChars => 'Prompt 字元';

  @override
  String get toolbarSessionMetadata => '會話元數據';

  @override
  String get toolbarProviderModelLocked => '已鎖定服務商與模型以保證緩存命中';

  @override
  String get toolbarModelLocked => '模型已鎖定';

  @override
  String get toolbarSessionAudit => '會話審計';

  @override
  String get toolbarShowPlan => '展開計劃';

  @override
  String get toolbarHidePlan => '收起計劃';

  @override
  String get toolbarPlanAwaitingApproval => '計劃待確認';

  @override
  String get toolbarPlanNeedsReview => '計劃待覆核';

  @override
  String get toolbarPlanNeedsAttention => '計劃需要處理';

  @override
  String get toolbarPlanCompleted => '計劃已完成';

  @override
  String get toolbarPlanInProgress => '計劃推進中';

  @override
  String get toolbarPlanConfirmToBegin => '請確認後開始執行';

  @override
  String get toolbarPlanInspectBeforeResume => '繼續前先檢查已完成步驟、產物和 Todo';

  @override
  String get toolbarPlanStepFailed => '當前步驟執行失敗，請檢查後繼續';

  @override
  String get toolbarPlanPending => '等待確認';

  @override
  String get toolbarPlanReview => '待覆核';

  @override
  String get toolbarToolsProtocolUnsupported => '當前模型協議不支援工具調用';

  @override
  String get toolbarRuntimeNoSnapshot => '尚未生成運行時工具快照';

  @override
  String get toolbarToolsCatalogStale => '工具目錄已過期，等待下一輪刷新';

  @override
  String get toolbarRuntimeCatalogSynced => '運行時工具目錄已同步';

  @override
  String get toolbarPlanAwaitingNoExecTools => '計劃待確認，當前輪不開放執行工具';

  @override
  String get toolbarPlanReviewBeforeResume => '需要先覆核已有步驟、產物和 Todo';

  @override
  String get toolbarPlanApprovedExecOpen => '計劃已獲准執行，當前輪開放執行工具';

  @override
  String get toolbarPlanOnlyPlanningExitAllowed => '當前僅開放規劃工具，可在準備好後提交執行計劃';

  @override
  String get toolbarPlanOnlyPlanningOnly => '當前僅開放規劃工具';

  @override
  String get toolbarModeJustSwitched => '模式剛切換，等待下一輪重新計算工具目錄';

  @override
  String get toolbarChatModeNoTools => '聊天模式當前沒有可用工具';

  @override
  String get toolbarChatModeAllTools => '聊天模式當前開放完整運行時工具目錄';

  @override
  String get toolbarRuntimeNoSnapshotPrompt => '當前還沒有運行時快照，請先發起一輪請求';

  @override
  String get toolbarGateNoReason => '暫無門控說明';

  @override
  String get toolbarGateProtocolUnsupportedSwitchPlan =>
      '當前模型協議不支援工具調用。點擊切換到計劃模式。';

  @override
  String get toolbarGateChatActiveSwitchPlan => '當前為聊天模式，點擊切換到計劃模式';

  @override
  String get toolbarGatePlanActiveSwitchChat => '當前為計劃模式，點擊切換到聊天模式';

  @override
  String get toolbarGateProtocolUnsupportedSwitchChat =>
      '當前模型協議不支援工具調用。計劃模式仍可組織步驟，但不會開放工具執行。點擊切換到聊天模式。';

  @override
  String get toolbarGatePlanJustSwitchedToChat =>
      '計劃模式剛切換完成，運行時工具會在下一輪自動刷新。點擊切換到聊天模式。';

  @override
  String get toolbarGatePlanAwaitingSwitchChat =>
      '計劃待確認。當前輪不會暴露執行工具，請先確認計劃。點擊切換到聊天模式。';

  @override
  String get toolbarGatePlanReviewSwitchChat =>
      '計劃待覆核。繼續執行前應先檢查已完成步驟、產物與 Todo。點擊切換到聊天模式。';

  @override
  String get toolbarGatePlanExecutingSwitchChat =>
      '計劃執行中。當前輪會按運行時目錄暴露執行工具。點擊切換到聊天模式。';

  @override
  String get toolbarGatePlanModeSwitchChat =>
      '當前為計劃模式，會先規劃，再在獲得確認後執行。點擊切換到聊天模式。';

  @override
  String get toolbarFilesShow => '專案檔案';

  @override
  String get toolbarFilesHide => '收起專案';

  @override
  String get toolbarRuntimeModeChat => '聊天模式';

  @override
  String get toolbarRuntimeModeChatCompact => '聊天模式';

  @override
  String get toolbarRuntimeModePlan => '計劃模式';

  @override
  String get toolbarRuntimeModePlanCompact => '計劃模式';

  @override
  String get toolbarRuntimeModePlanAwaiting => '計劃待確認';

  @override
  String get toolbarRuntimeModePlanAwaitingCompact => '計劃待確認';

  @override
  String get toolbarRuntimeModePlanReview => '計劃待覆核';

  @override
  String get toolbarRuntimeModePlanReviewCompact => '計劃待覆核';

  @override
  String get toolbarRuntimeModePlanExecution => '執行計劃';

  @override
  String get toolbarRuntimeModePlanExecutionCompact => '執行計劃';

  @override
  String get toolbarRuntimeModePlanDrafting => '計劃規劃中';

  @override
  String get toolbarRuntimeModePlanDraftCompact => '計劃規劃中';

  @override
  String toolbarRuntimeNotices(int count) {
    return '$count 項運行時 Notice';
  }

  @override
  String toolbarPlanStepsCompleted(int completed, int total) {
    return '已完成 $completed/$total 項';
  }
}
