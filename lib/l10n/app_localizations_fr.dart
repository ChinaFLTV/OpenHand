// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'OpenHand';

  @override
  String get appTagline =>
      'Un espace de travail de bureau ouvert, stable et extensible';

  @override
  String get newThread => 'Nouveau fil';

  @override
  String get automations => 'Automatisations';

  @override
  String get skills => 'Compétences';

  @override
  String get memory => '记忆';

  @override
  String get mcp => 'MCP';

  @override
  String get settings => 'Paramètres';

  @override
  String get threads => 'Fils';

  @override
  String get workspaceHeadline => 'Commencer à créer';

  @override
  String get composerHint =>
      'Demandez n\'importe quoi à OpenHand, utilisez / pour les actions et @ pour le contexte';

  @override
  String get composerSend => 'Envoyer';

  @override
  String get chatSending => '发送中';

  @override
  String get chatRequestFailed => '模型请求失败，请检查模型配置、网络连通性或接口协议。';

  @override
  String get composerUnavailable =>
      'Il s\'agit de l\'ossature de base. Les capacités d\'exécution ne sont pas encore connectées.';

  @override
  String get workspaceReadyTitle => 'La base est prête';

  @override
  String get workspaceReadyBody =>
      'La disposition bureau, le changement de thème, le changement de langue et l\'infrastructure des paramètres sont en place. Les modules futurs peuvent maintenant s\'y ajouter.';

  @override
  String get quickActionsTitle => 'Points de départ suggérés';

  @override
  String get quickActionCreateShell => 'Créer l\'ossature de l\'application';

  @override
  String get quickActionThemeLanguage => 'Configurer le thème et la langue';

  @override
  String get quickActionPlanModules => 'Planifier les modules futurs';

  @override
  String get automationHeadline => 'Ossature du module d\'automatisation';

  @override
  String get automationBody =>
      'Cette zone est réservée aux tâches planifiées, aux flux de travail et aux déclencheurs d\'outils.';

  @override
  String get skillsHeadline => 'Ossature du centre de compétences';

  @override
  String get skillsBody =>
      'Cette zone est réservée aux plugins de capacité, aux modèles d\'invite et aux assistants de développement.';

  @override
  String get placeholderComingSoon =>
      'Des modules supplémentaires seront ajoutés ici progressivement.';

  @override
  String get settingsTitle => 'Centre des paramètres';

  @override
  String get settingsSubtitle =>
      'Gérez ici le thème, la langue et les informations de l\'application.';

  @override
  String get settingsFilePathLabel => '设置文件';

  @override
  String get themeSectionTitle => 'Thème de l\'application';

  @override
  String get themeSectionBody =>
      'Choisissez le style de luminosité adapté à votre espace de travail actuel.';

  @override
  String get themeSystem => 'Système';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

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
  String get languageSectionTitle => 'Langue de l\'application';

  @override
  String get languageSectionBody =>
      'Changez la langue de l\'interface et appliquez-la immédiatement.';

  @override
  String get languageSimplifiedChinese => 'Chinois simplifié';

  @override
  String get languageTraditionalChinese => 'Chinois traditionnel';

  @override
  String get languageEnglish => 'Anglais';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageGerman => 'Allemand';

  @override
  String get languageJapanese => 'Japonais';

  @override
  String get aboutSectionTitle => 'À propos';

  @override
  String get aboutSectionBody =>
      'OpenHand est actuellement à l\'étape de fondation, avec un accent sur une structure de bureau stable, une base visuelle et une architecture extensible.';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutPackage => 'Package';

  @override
  String get aboutPlatforms => 'Plateformes';

  @override
  String get aboutPlatformsValue => 'macOS 15+ / Windows 10+';

  @override
  String get aboutBuild => 'Build';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '删除';

  @override
  String get commonEdit => '编辑';

  @override
  String get previewSectionTitle => 'Direction du design';

  @override
  String get previewSectionBody =>
      'Conçu autour de Material 3 Expressive, avec des surfaces superposées, de larges espacements, des formes arrondies, une lumière douce et un rythme d\'information clair.';

  @override
  String get threadPrimary => 'OpenHand';

  @override
  String get threadShell => 'Ossature de l\'application bureau';

  @override
  String get threadSettings => 'Paramètres et localisation';

  @override
  String get threadRoadmap => 'Planification des futurs modules';

  @override
  String get switchToWorkspace => 'Retour à l\'espace de travail';

  @override
  String get modelLabel => 'OpenHand Skeleton';

  @override
  String get platformLabel => 'Bureau';

  @override
  String get permissionLabel => 'Accès complet';

  @override
  String get settingsCategoryGeneral => 'Général';

  @override
  String get settingsCategoryAi => 'AI';

  @override
  String get settingsCategorySkills => 'Compétences';

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
  String get settingsGeneralTitle => 'Général';

  @override
  String get settingsGeneralSubtitle =>
      'Gérez le thème, la langue et les informations principales de l\'application.';

  @override
  String get settingsAiSubtitle => '管理聊天模型、鉴权方式与协议适配。';

  @override
  String get settingsSkillsTitle => 'Compétences';

  @override
  String get settingsSkillsSubtitle =>
      'Gérez le dossier local des compétences, la création de modèles et les compétences installées.';

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
  String get aiModelAdd => '新增模型';

  @override
  String get aiModelsEmptyTitle => '还没有可用模型';

  @override
  String get aiModelsEmptyBody => '先添加至少一个模型配置，后续线程聊天窗口会直接复用这里的模型列表。';

  @override
  String get aiModelDialogCreateTitle => '新增模型配置';

  @override
  String get aiModelDialogEditTitle => '编辑模型配置';

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
  String get aiModelSaveSuccess => '模型配置已保存。';

  @override
  String get aiModelDeleteConfirmTitle => '删除模型配置';

  @override
  String get aiModelDeleteConfirmBody => '确认删除这条模型配置吗？';

  @override
  String get aiModelDeleteSuccess => '模型配置已删除。';

  @override
  String get aiModelMoveUp => '上移';

  @override
  String get aiModelMoveDown => '下移';

  @override
  String get aiModelSelected => '当前会话模型';

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
  String get aiModelSelectionRequired => '请先在设置中添加并选择一个 AI 模型。';

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
  String get skillsPageTitle => 'Compétences';

  @override
  String get skillsPageSubtitle =>
      'Donnez à OpenHand une plus grande extensibilité grâce à une vue unifiée des compétences locales installées et des modèles.';

  @override
  String get skillsInstalledSectionTitle => 'Installées';

  @override
  String get skillsSearchHint => 'Rechercher des compétences';

  @override
  String get skillsRefresh => 'Actualiser';

  @override
  String get skillsOpenDirectory => 'Ouvrir le dossier';

  @override
  String get skillsImport => 'Importer une compétence';

  @override
  String get skillsNewSkill => 'Nouvelle compétence';

  @override
  String get skillsEmptyTitle => 'Aucune compétence installée';

  @override
  String get skillsEmptyBody =>
      'Aucun fichier SKILL.md n\'a été trouvé dans le dossier actuel. Créez un modèle ou basculez vers un dossier existant.';

  @override
  String get skillsEmptyActionCreate => 'Créer un modèle';

  @override
  String get skillsEmptyActionOpenDirectory => 'Ouvrir le dossier';

  @override
  String get skillsNoResultsTitle => 'Aucune compétence correspondante';

  @override
  String get skillsNoResultsBody =>
      'Essayez un autre mot-clé ou effacez la recherche pour revoir toutes les compétences.';

  @override
  String get skillsFolderLabel => 'Emplacement';

  @override
  String get skillsCardOpen => 'Ouvrir le dossier de la compétence';

  @override
  String get skillTemplateCreated => 'Nouveau modèle de compétence créé';

  @override
  String get skillOperationFailed =>
      'L\'action sur la compétence a échoué. Veuillez réessayer.';

  @override
  String get skillsImportSuccess => 'Compétence importée';

  @override
  String get skillsEdit => 'Modifier la compétence';

  @override
  String get skillsDelete => 'Supprimer la compétence';

  @override
  String get skillsPreviewClose => 'Fermer';

  @override
  String get skillsEditorLabel => 'Contenu de SKILL.md';

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
  String get skillsEditorSave => 'Enregistrer';

  @override
  String get skillsEditorCancel => 'Annuler';

  @override
  String get skillsEditSuccess =>
      'Le contenu de la compétence a été enregistré';

  @override
  String get skillsDeleteConfirmTitle => 'Supprimer la compétence';

  @override
  String get skillsDeleteConfirmBody =>
      'La suppression retirera définitivement le dossier de la compétence et son contenu SKILL.md.';

  @override
  String get skillsDeleteConfirmAction => 'Supprimer';

  @override
  String get skillsDeleteSuccess => 'Compétence supprimée';

  @override
  String get skillsStorageSectionTitle => 'Emplacement des compétences';

  @override
  String get skillsStorageSectionBody =>
      'Configurez le dossier local analysé par OpenHand pour les compétences. Par défaut, ~/.openhand/skills est utilisé et créé si nécessaire.';

  @override
  String get skillsStorageDefaultPath => 'Chemin par défaut';

  @override
  String get skillsStorageCurrentPath => 'Chemin actuel';

  @override
  String get skillsStorageSave => 'Enregistrer l\'emplacement';

  @override
  String get skillsStorageBrowse => 'Choisir un dossier';

  @override
  String get skillsStorageReset => 'Réinitialiser';

  @override
  String get skillsStorageOpen => 'Ouvrir l\'emplacement';

  @override
  String get skillsStorageSummaryTitle => 'Résumé des compétences';

  @override
  String get skillsStorageSummaryBody =>
      'Le dossier actuel, le nombre installé et l\'état d\'analyse sont affichés ici en temps réel.';

  @override
  String get skillsStorageStatusReady => 'État';

  @override
  String get skillsStorageStatusLoading => 'Analyse en cours';

  @override
  String get skillsStorageStatusError =>
      'Impossible de lire le dossier des compétences';

  @override
  String get skillsPathSaved =>
      'L\'emplacement des compétences a été mis à jour';

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
}
