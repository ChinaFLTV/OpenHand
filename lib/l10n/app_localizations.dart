import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('fr'),
    Locale('ja'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'OpenHand'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In zh_Hans, this message translates to:
  /// **'开放、稳定、可扩展的桌面工作台'**
  String get appTagline;

  /// No description provided for @newThread.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新线程'**
  String get newThread;

  /// No description provided for @automations.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动化'**
  String get automations;

  /// No description provided for @skills.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能'**
  String get skills;

  /// No description provided for @memory.
  ///
  /// In zh_Hans, this message translates to:
  /// **'记忆'**
  String get memory;

  /// No description provided for @mcp.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP'**
  String get mcp;

  /// No description provided for @settings.
  ///
  /// In zh_Hans, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @threads.
  ///
  /// In zh_Hans, this message translates to:
  /// **'线程'**
  String get threads;

  /// No description provided for @workspaceHeadline.
  ///
  /// In zh_Hans, this message translates to:
  /// **'开始构建'**
  String get workspaceHeadline;

  /// No description provided for @composerHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'询问 OpenHand 任何内容，使用 / 触发动作，使用 @ 引用上下文'**
  String get composerHint;

  /// No description provided for @composerSend.
  ///
  /// In zh_Hans, this message translates to:
  /// **'发送'**
  String get composerSend;

  /// No description provided for @chatSending.
  ///
  /// In zh_Hans, this message translates to:
  /// **'发送中'**
  String get chatSending;

  /// No description provided for @chatRequestFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模型请求失败，请检查模型配置、网络连通性或接口协议。'**
  String get chatRequestFailed;

  /// No description provided for @composerUnavailable.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前为基础骨架，暂未接入实际执行能力。'**
  String get composerUnavailable;

  /// No description provided for @workspaceReadyTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'基础骨架已就绪'**
  String get workspaceReadyTitle;

  /// No description provided for @workspaceReadyBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前已经完成桌面端主布局、主题切换、语言切换与设置页基础能力，后续模块可以在此逐步扩展。'**
  String get workspaceReadyBody;

  /// No description provided for @quickActionsTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'建议从这里开始'**
  String get quickActionsTitle;

  /// No description provided for @quickActionCreateShell.
  ///
  /// In zh_Hans, this message translates to:
  /// **'创建桌面应用骨架'**
  String get quickActionCreateShell;

  /// No description provided for @quickActionThemeLanguage.
  ///
  /// In zh_Hans, this message translates to:
  /// **'配置主题与语言'**
  String get quickActionThemeLanguage;

  /// No description provided for @quickActionPlanModules.
  ///
  /// In zh_Hans, this message translates to:
  /// **'规划功能模块'**
  String get quickActionPlanModules;

  /// No description provided for @automationHeadline.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动化模块骨架'**
  String get automationHeadline;

  /// No description provided for @automationBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'后续可在这里编排定时任务、工作流和工具链触发逻辑。'**
  String get automationBody;

  /// No description provided for @skillsHeadline.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能中心骨架'**
  String get skillsHeadline;

  /// No description provided for @skillsBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'后续可在这里管理能力插件、提示模板和开发辅助工具。'**
  String get skillsBody;

  /// No description provided for @placeholderComingSoon.
  ///
  /// In zh_Hans, this message translates to:
  /// **'后续功能模块将在这里逐步扩展。'**
  String get placeholderComingSoon;

  /// No description provided for @settingsTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'设置中心'**
  String get settingsTitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'在这里管理常规设置、AI 模型、MCP 服务、技能目录、记忆与应用信息。'**
  String get settingsSubtitle;

  /// No description provided for @settingsFilePathLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'设置文件'**
  String get settingsFilePathLabel;

  /// No description provided for @themeSectionTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'应用主题'**
  String get themeSectionTitle;

  /// No description provided for @themeSectionBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'选择适合当前工作环境的界面亮度风格。'**
  String get themeSectionBody;

  /// No description provided for @themeSystem.
  ///
  /// In zh_Hans, this message translates to:
  /// **'跟随系统'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In zh_Hans, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh_Hans, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @themePaletteSectionTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'主题配色'**
  String get themePaletteSectionTitle;

  /// No description provided for @themePaletteSectionBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'选择全局主题配色，系统会基于该配色生成 Material 3 Expressive 主题层次。'**
  String get themePaletteSectionBody;

  /// No description provided for @themePresetDarkNightPurple.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暗夜紫'**
  String get themePresetDarkNightPurple;

  /// No description provided for @themePresetDeepSeaBlue.
  ///
  /// In zh_Hans, this message translates to:
  /// **'深海蓝'**
  String get themePresetDeepSeaBlue;

  /// No description provided for @themePresetMistGray.
  ///
  /// In zh_Hans, this message translates to:
  /// **'雾霭灰'**
  String get themePresetMistGray;

  /// No description provided for @themePresetObsidianBlack.
  ///
  /// In zh_Hans, this message translates to:
  /// **'曜石黑'**
  String get themePresetObsidianBlack;

  /// No description provided for @themePresetPolarWhite.
  ///
  /// In zh_Hans, this message translates to:
  /// **'极昼白'**
  String get themePresetPolarWhite;

  /// No description provided for @themePresetFrostMorningBlue.
  ///
  /// In zh_Hans, this message translates to:
  /// **'霜晨蓝'**
  String get themePresetFrostMorningBlue;

  /// No description provided for @themePresetDuskMountainGreen.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暮山青'**
  String get themePresetDuskMountainGreen;

  /// No description provided for @themePresetNebulaPurple.
  ///
  /// In zh_Hans, this message translates to:
  /// **'星云紫'**
  String get themePresetNebulaPurple;

  /// No description provided for @themePresetEmberOrange.
  ///
  /// In zh_Hans, this message translates to:
  /// **'余烬橙'**
  String get themePresetEmberOrange;

  /// No description provided for @themePresetTundraGreen.
  ///
  /// In zh_Hans, this message translates to:
  /// **'苔原绿'**
  String get themePresetTundraGreen;

  /// No description provided for @themePresetMoonShadowSilver.
  ///
  /// In zh_Hans, this message translates to:
  /// **'月影银'**
  String get themePresetMoonShadowSilver;

  /// No description provided for @themePresetAmberGold.
  ///
  /// In zh_Hans, this message translates to:
  /// **'琥珀金'**
  String get themePresetAmberGold;

  /// No description provided for @themePresetRainyCyan.
  ///
  /// In zh_Hans, this message translates to:
  /// **'烟雨青'**
  String get themePresetRainyCyan;

  /// No description provided for @themePresetGraphiteGray.
  ///
  /// In zh_Hans, this message translates to:
  /// **'石墨灰'**
  String get themePresetGraphiteGray;

  /// No description provided for @themePresetGlacierBlue.
  ///
  /// In zh_Hans, this message translates to:
  /// **'冰川蓝'**
  String get themePresetGlacierBlue;

  /// No description provided for @themePresetBlazeRed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'赤焰红'**
  String get themePresetBlazeRed;

  /// No description provided for @themePresetNightfallBlue.
  ///
  /// In zh_Hans, this message translates to:
  /// **'夜幕蓝'**
  String get themePresetNightfallBlue;

  /// No description provided for @themePresetColdMoonWhite.
  ///
  /// In zh_Hans, this message translates to:
  /// **'冷月白'**
  String get themePresetColdMoonWhite;

  /// No description provided for @themePresetPineInk.
  ///
  /// In zh_Hans, this message translates to:
  /// **'松烟墨'**
  String get themePresetPineInk;

  /// No description provided for @themePresetSkyCyan.
  ///
  /// In zh_Hans, this message translates to:
  /// **'苍穹青'**
  String get themePresetSkyCyan;

  /// No description provided for @languageSectionTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'应用语言'**
  String get languageSectionTitle;

  /// No description provided for @languageSectionBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'切换界面显示语言，保存后立即生效。'**
  String get languageSectionBody;

  /// No description provided for @languageSimplifiedChinese.
  ///
  /// In zh_Hans, this message translates to:
  /// **'简体中文'**
  String get languageSimplifiedChinese;

  /// No description provided for @languageTraditionalChinese.
  ///
  /// In zh_Hans, this message translates to:
  /// **'繁體中文'**
  String get languageTraditionalChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In zh_Hans, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageFrench.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Français'**
  String get languageFrench;

  /// No description provided for @languageGerman.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Deutsch'**
  String get languageGerman;

  /// No description provided for @languageJapanese.
  ///
  /// In zh_Hans, this message translates to:
  /// **'日本語'**
  String get languageJapanese;

  /// No description provided for @aboutSectionTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关于应用'**
  String get aboutSectionTitle;

  /// No description provided for @aboutSectionBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'OpenHand 当前处于基础骨架阶段，重点提供稳定的桌面应用结构、视觉基线与可扩展能力。'**
  String get aboutSectionBody;

  /// No description provided for @aboutVersion.
  ///
  /// In zh_Hans, this message translates to:
  /// **'版本'**
  String get aboutVersion;

  /// No description provided for @aboutPackage.
  ///
  /// In zh_Hans, this message translates to:
  /// **'包名'**
  String get aboutPackage;

  /// No description provided for @aboutPlatforms.
  ///
  /// In zh_Hans, this message translates to:
  /// **'支持平台'**
  String get aboutPlatforms;

  /// No description provided for @aboutPlatformsValue.
  ///
  /// In zh_Hans, this message translates to:
  /// **'macOS 15+ / Windows 10+'**
  String get aboutPlatformsValue;

  /// No description provided for @aboutBuild.
  ///
  /// In zh_Hans, this message translates to:
  /// **'构建号'**
  String get aboutBuild;

  /// No description provided for @commonCancel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @commonDelete.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'编辑'**
  String get commonEdit;

  /// No description provided for @previewSectionTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'设计方向'**
  String get previewSectionTitle;

  /// No description provided for @previewSectionBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'遵循 Material 3 Expressive 设计理念，强调层次、留白、圆角、柔和光感与清晰的信息节奏。'**
  String get previewSectionBody;

  /// No description provided for @threadPrimary.
  ///
  /// In zh_Hans, this message translates to:
  /// **'OpenHand'**
  String get threadPrimary;

  /// No description provided for @threadShell.
  ///
  /// In zh_Hans, this message translates to:
  /// **'桌面应用骨架'**
  String get threadShell;

  /// No description provided for @threadSettings.
  ///
  /// In zh_Hans, this message translates to:
  /// **'设置与本地化'**
  String get threadSettings;

  /// No description provided for @threadRoadmap.
  ///
  /// In zh_Hans, this message translates to:
  /// **'后续模块规划'**
  String get threadRoadmap;

  /// No description provided for @switchToWorkspace.
  ///
  /// In zh_Hans, this message translates to:
  /// **'返回主工作台'**
  String get switchToWorkspace;

  /// No description provided for @modelLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'OpenHand Skeleton'**
  String get modelLabel;

  /// No description provided for @platformLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'桌面端'**
  String get platformLabel;

  /// No description provided for @permissionLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'完全访问权限'**
  String get permissionLabel;

  /// No description provided for @settingsCategoryGeneral.
  ///
  /// In zh_Hans, this message translates to:
  /// **'常规'**
  String get settingsCategoryGeneral;

  /// No description provided for @settingsCategoryAi.
  ///
  /// In zh_Hans, this message translates to:
  /// **'AI'**
  String get settingsCategoryAi;

  /// No description provided for @settingsCategorySkills.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能'**
  String get settingsCategorySkills;

  /// No description provided for @settingsCategoryMemory.
  ///
  /// In zh_Hans, this message translates to:
  /// **'记忆'**
  String get settingsCategoryMemory;

  /// No description provided for @mcpSectionTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 服务'**
  String get mcpSectionTitle;

  /// No description provided for @mcpSectionBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'管理全局 MCP 开关和服务配置文件位置。服务条目的新增、更新、删除与启用状态会同步写入 MCP JSON 文件。'**
  String get mcpSectionBody;

  /// No description provided for @mcpEnabledLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'启用 MCP 服务'**
  String get mcpEnabledLabel;

  /// No description provided for @mcpEnabledBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭后不会启用 MCP 服务能力，但仍然保留已保存的服务配置。'**
  String get mcpEnabledBody;

  /// No description provided for @mcpFilePathLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 配置文件'**
  String get mcpFilePathLabel;

  /// No description provided for @mcpOpenDirectory.
  ///
  /// In zh_Hans, this message translates to:
  /// **'打开目录'**
  String get mcpOpenDirectory;

  /// No description provided for @settingsGeneralTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'常规'**
  String get settingsGeneralTitle;

  /// No description provided for @settingsGeneralSubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'管理主题、语言与应用基础信息。'**
  String get settingsGeneralSubtitle;

  /// No description provided for @settingsAiSubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'管理聊天模型、鉴权方式与协议适配。'**
  String get settingsAiSubtitle;

  /// No description provided for @settingsSkillsTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能'**
  String get settingsSkillsTitle;

  /// No description provided for @settingsSkillsSubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'管理本地技能目录、模板创建与已安装技能展示。'**
  String get settingsSkillsSubtitle;

  /// No description provided for @settingsMemorySubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'管理用户记忆开关与持久化文件位置。'**
  String get settingsMemorySubtitle;

  /// No description provided for @settingsPersistenceRecoveredTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'设置文件已自动恢复'**
  String get settingsPersistenceRecoveredTitle;

  /// No description provided for @settingsPersistenceRecoveredBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'检测到设置文件内容损坏或被篡改，OpenHand 已备份异常文件并恢复为安全默认值。'**
  String get settingsPersistenceRecoveredBody;

  /// No description provided for @settingsPersistenceSanitizedTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'设置内容已自动修正'**
  String get settingsPersistenceSanitizedTitle;

  /// No description provided for @settingsPersistenceSanitizedBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'检测到部分设置内容无效，OpenHand 已忽略异常字段并重新写回有效配置。'**
  String get settingsPersistenceSanitizedBody;

  /// No description provided for @settingsPersistenceSaveFailedTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'设置保存失败'**
  String get settingsPersistenceSaveFailedTitle;

  /// No description provided for @settingsPersistenceSaveFailedBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'设置文件写入失败，界面已回滚到上一次有效配置，请检查文件权限或磁盘状态。'**
  String get settingsPersistenceSaveFailedBody;

  /// No description provided for @settingsPersistenceDismiss.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭提示'**
  String get settingsPersistenceDismiss;

  /// No description provided for @aiModelAdd.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增提供商'**
  String get aiModelAdd;

  /// No description provided for @aiModelsEmptyTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'还没有可用模型提供商'**
  String get aiModelsEmptyTitle;

  /// No description provided for @aiModelsEmptyBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'先添加至少一个模型提供商配置，后续线程聊天窗口会直接复用这里的模型列表。'**
  String get aiModelsEmptyBody;

  /// No description provided for @aiModelDialogCreateTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增模型提供商'**
  String get aiModelDialogCreateTitle;

  /// No description provided for @aiModelDialogEditTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'编辑模型提供商'**
  String get aiModelDialogEditTitle;

  /// No description provided for @aiModelBaseUrl.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Base URL'**
  String get aiModelBaseUrl;

  /// No description provided for @aiModelBaseUrlRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 Base URL'**
  String get aiModelBaseUrlRequired;

  /// No description provided for @aiModelBaseUrlInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效的 Base URL'**
  String get aiModelBaseUrlInvalid;

  /// No description provided for @aiModelAuthScheme.
  ///
  /// In zh_Hans, this message translates to:
  /// **'鉴权方式'**
  String get aiModelAuthScheme;

  /// No description provided for @aiModelToken.
  ///
  /// In zh_Hans, this message translates to:
  /// **'令牌'**
  String get aiModelToken;

  /// No description provided for @aiModelIdField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模型 ID'**
  String get aiModelIdField;

  /// No description provided for @aiModelIdRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入模型 ID'**
  String get aiModelIdRequired;

  /// No description provided for @aiModelProtocol.
  ///
  /// In zh_Hans, this message translates to:
  /// **'协议类型'**
  String get aiModelProtocol;

  /// No description provided for @aiModelSaveSuccess.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模型提供商配置已保存。'**
  String get aiModelSaveSuccess;

  /// No description provided for @aiModelDeleteConfirmTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除模型提供商'**
  String get aiModelDeleteConfirmTitle;

  /// No description provided for @aiModelDeleteConfirmBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'确认删除这条模型提供商配置吗？'**
  String get aiModelDeleteConfirmBody;

  /// No description provided for @aiModelDeleteSuccess.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模型提供商配置已删除。'**
  String get aiModelDeleteSuccess;

  /// No description provided for @aiModelMoveUp.
  ///
  /// In zh_Hans, this message translates to:
  /// **'上移'**
  String get aiModelMoveUp;

  /// No description provided for @aiModelMoveDown.
  ///
  /// In zh_Hans, this message translates to:
  /// **'下移'**
  String get aiModelMoveDown;

  /// No description provided for @aiModelSelected.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前活跃提供商'**
  String get aiModelSelected;

  /// No description provided for @aiModelNoToken.
  ///
  /// In zh_Hans, this message translates to:
  /// **'未配置令牌'**
  String get aiModelNoToken;

  /// No description provided for @aiModelTest.
  ///
  /// In zh_Hans, this message translates to:
  /// **'测试'**
  String get aiModelTest;

  /// No description provided for @aiModelTesting.
  ///
  /// In zh_Hans, this message translates to:
  /// **'测试中'**
  String get aiModelTesting;

  /// No description provided for @aiModelTestSuccess.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{modelName} 测试通过。'**
  String aiModelTestSuccess(Object modelName);

  /// No description provided for @aiModelTestFailure.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{modelName} 测试失败：{reason}'**
  String aiModelTestFailure(Object modelName, Object reason);

  /// No description provided for @aiModelSelectionRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请先在设置中添加并选择一个 AI 模型提供商。'**
  String get aiModelSelectionRequired;

  /// No description provided for @aiModelScanButton.
  ///
  /// In zh_Hans, this message translates to:
  /// **'扫描模型'**
  String get aiModelScanButton;

  /// No description provided for @aiModelScanning.
  ///
  /// In zh_Hans, this message translates to:
  /// **'正在扫描可用模型…'**
  String get aiModelScanning;

  /// No description provided for @aiModelScanSuccess.
  ///
  /// In zh_Hans, this message translates to:
  /// **'发现 {count} 个模型。'**
  String aiModelScanSuccess(Object count);

  /// No description provided for @aiModelScanFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'扫描失败：{reason}'**
  String aiModelScanFailed(Object reason);

  /// No description provided for @aiModelScanEmpty.
  ///
  /// In zh_Hans, this message translates to:
  /// **'未从该提供商扫描到模型。'**
  String get aiModelScanEmpty;

  /// No description provided for @aiModelAvailableModels.
  ///
  /// In zh_Hans, this message translates to:
  /// **'可用模型'**
  String get aiModelAvailableModels;

  /// No description provided for @aiModelManualIdHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'手动输入模型 ID'**
  String get aiModelManualIdHint;

  /// No description provided for @aiModelManualIdAdd.
  ///
  /// In zh_Hans, this message translates to:
  /// **'添加'**
  String get aiModelManualIdAdd;

  /// No description provided for @aiModelCount.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{count} 个模型'**
  String aiModelCount(Object count);

  /// No description provided for @chatModelButton.
  ///
  /// In zh_Hans, this message translates to:
  /// **'选择模型'**
  String get chatModelButton;

  /// No description provided for @aiAuthNone.
  ///
  /// In zh_Hans, this message translates to:
  /// **'无'**
  String get aiAuthNone;

  /// No description provided for @aiAuthBearer.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Bearer'**
  String get aiAuthBearer;

  /// No description provided for @aiAuthToken.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Token'**
  String get aiAuthToken;

  /// No description provided for @aiAuthApiKey.
  ///
  /// In zh_Hans, this message translates to:
  /// **'API Key'**
  String get aiAuthApiKey;

  /// No description provided for @aiProtocolOpenAi.
  ///
  /// In zh_Hans, this message translates to:
  /// **'OpenAI'**
  String get aiProtocolOpenAi;

  /// No description provided for @aiProtocolClaude.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Claude'**
  String get aiProtocolClaude;

  /// No description provided for @aiProtocolGemini.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Gemini'**
  String get aiProtocolGemini;

  /// No description provided for @aiProtocolDeepSeek.
  ///
  /// In zh_Hans, this message translates to:
  /// **'DeepSeek'**
  String get aiProtocolDeepSeek;

  /// No description provided for @aiProtocolKimi.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Kimi'**
  String get aiProtocolKimi;

  /// No description provided for @aiProtocolGlm.
  ///
  /// In zh_Hans, this message translates to:
  /// **'GLM'**
  String get aiProtocolGlm;

  /// No description provided for @aiProtocolGrok.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Grok'**
  String get aiProtocolGrok;

  /// No description provided for @aiProtocolOllama.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Ollama'**
  String get aiProtocolOllama;

  /// No description provided for @aiProtocolVllm.
  ///
  /// In zh_Hans, this message translates to:
  /// **'vLLM'**
  String get aiProtocolVllm;

  /// No description provided for @aiProtocolSglang.
  ///
  /// In zh_Hans, this message translates to:
  /// **'SGLang'**
  String get aiProtocolSglang;

  /// No description provided for @aiProtocolQwen.
  ///
  /// In zh_Hans, this message translates to:
  /// **'通义千问'**
  String get aiProtocolQwen;

  /// No description provided for @aiProtocolSeed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'豆包 (火山方舟)'**
  String get aiProtocolSeed;

  /// No description provided for @aiProtocolStepFun.
  ///
  /// In zh_Hans, this message translates to:
  /// **'阶跃星辰'**
  String get aiProtocolStepFun;

  /// No description provided for @aiProtocolMinimax.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MiniMax'**
  String get aiProtocolMinimax;

  /// No description provided for @aiProtocolLongCat.
  ///
  /// In zh_Hans, this message translates to:
  /// **'LongCat'**
  String get aiProtocolLongCat;

  /// No description provided for @aiProtocolJoyCode.
  ///
  /// In zh_Hans, this message translates to:
  /// **'JoyCode'**
  String get aiProtocolJoyCode;

  /// No description provided for @aiProtocolWenxin.
  ///
  /// In zh_Hans, this message translates to:
  /// **'文心一言 (ERNIE)'**
  String get aiProtocolWenxin;

  /// No description provided for @aiProtocolMeta.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Meta AI (Llama)'**
  String get aiProtocolMeta;

  /// No description provided for @aiProtocolMimo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MIMO (小米)'**
  String get aiProtocolMimo;

  /// No description provided for @aiProtocolHunyuan.
  ///
  /// In zh_Hans, this message translates to:
  /// **'混元 (腾讯)'**
  String get aiProtocolHunyuan;

  /// No description provided for @skillsPageTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能'**
  String get skillsPageTitle;

  /// No description provided for @skillsPageSubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'为 OpenHand 提供更强大的扩展能力，统一管理本地已安装技能与模板。'**
  String get skillsPageSubtitle;

  /// No description provided for @skillsInstalledSectionTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已安装'**
  String get skillsInstalledSectionTitle;

  /// No description provided for @skillsSearchHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'搜索技能'**
  String get skillsSearchHint;

  /// No description provided for @skillsRefresh.
  ///
  /// In zh_Hans, this message translates to:
  /// **'刷新'**
  String get skillsRefresh;

  /// No description provided for @skillsOpenDirectory.
  ///
  /// In zh_Hans, this message translates to:
  /// **'打开目录'**
  String get skillsOpenDirectory;

  /// No description provided for @skillsImport.
  ///
  /// In zh_Hans, this message translates to:
  /// **'导入技能'**
  String get skillsImport;

  /// No description provided for @skillsNewSkill.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新技能'**
  String get skillsNewSkill;

  /// No description provided for @skillsEmptyTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'还没有安装任何技能'**
  String get skillsEmptyTitle;

  /// No description provided for @skillsEmptyBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前技能目录中未发现任何 SKILL.md。你可以先创建模板，或切换到已有技能目录。'**
  String get skillsEmptyBody;

  /// No description provided for @skillsEmptyActionCreate.
  ///
  /// In zh_Hans, this message translates to:
  /// **'创建模板'**
  String get skillsEmptyActionCreate;

  /// No description provided for @skillsEmptyActionOpenDirectory.
  ///
  /// In zh_Hans, this message translates to:
  /// **'打开目录'**
  String get skillsEmptyActionOpenDirectory;

  /// No description provided for @skillsNoResultsTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'未找到匹配的技能'**
  String get skillsNoResultsTitle;

  /// No description provided for @skillsNoResultsBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'尝试修改搜索关键词，或清空搜索后重新查看全部技能。'**
  String get skillsNoResultsBody;

  /// No description provided for @skillsFolderLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'存放位置'**
  String get skillsFolderLabel;

  /// No description provided for @skillsCardOpen.
  ///
  /// In zh_Hans, this message translates to:
  /// **'打开技能目录'**
  String get skillsCardOpen;

  /// No description provided for @skillTemplateCreated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已创建新技能'**
  String get skillTemplateCreated;

  /// No description provided for @skillOperationFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能操作失败，请稍后重试。'**
  String get skillOperationFailed;

  /// No description provided for @skillsImportSuccess.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已导入技能'**
  String get skillsImportSuccess;

  /// No description provided for @skillsEdit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'编辑技能'**
  String get skillsEdit;

  /// No description provided for @skillsDelete.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除技能'**
  String get skillsDelete;

  /// No description provided for @skillsPreviewClose.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭'**
  String get skillsPreviewClose;

  /// No description provided for @skillsEditorLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'SKILL.md 内容'**
  String get skillsEditorLabel;

  /// No description provided for @skillsCreateDialogTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增技能'**
  String get skillsCreateDialogTitle;

  /// No description provided for @skillsCreateNameLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能名称'**
  String get skillsCreateNameLabel;

  /// No description provided for @skillsCreateNameRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入技能名称'**
  String get skillsCreateNameRequired;

  /// No description provided for @skillsCreateIconLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能图标'**
  String get skillsCreateIconLabel;

  /// No description provided for @skillsCreateIconHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请选择表情或本地图片'**
  String get skillsCreateIconHint;

  /// No description provided for @skillsCreateIconRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请选择技能图标'**
  String get skillsCreateIconRequired;

  /// No description provided for @skillsCreateIconChoose.
  ///
  /// In zh_Hans, this message translates to:
  /// **'选择表情'**
  String get skillsCreateIconChoose;

  /// No description provided for @skillsCreateIconChange.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重新选择'**
  String get skillsCreateIconChange;

  /// No description provided for @skillsCreateImageChoose.
  ///
  /// In zh_Hans, this message translates to:
  /// **'选择图片'**
  String get skillsCreateImageChoose;

  /// No description provided for @skillsCreateImageChange.
  ///
  /// In zh_Hans, this message translates to:
  /// **'更换图片'**
  String get skillsCreateImageChange;

  /// No description provided for @skillsCreateImageSelected.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已选择本地图片'**
  String get skillsCreateImageSelected;

  /// No description provided for @skillsCreateDescriptionLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能简介'**
  String get skillsCreateDescriptionLabel;

  /// No description provided for @skillsCreateDescriptionRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入技能简介'**
  String get skillsCreateDescriptionRequired;

  /// No description provided for @skillsCreateContentRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 SKILL.md 内容'**
  String get skillsCreateContentRequired;

  /// No description provided for @imageEditorTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'编辑图片'**
  String get imageEditorTitle;

  /// No description provided for @imageEditorCropHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'拖动方框调整裁剪区域，可继续缩放、旋转、翻转，展开下方面板可使用 HSL、色调分离、清晰度、颗粒、降噪、色散、扭曲、水印等高级调整（高级调整在保存时应用）。'**
  String get imageEditorCropHint;

  /// No description provided for @imageEditorZoomLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缩放'**
  String get imageEditorZoomLabel;

  /// No description provided for @imageEditorBrightnessLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'亮度'**
  String get imageEditorBrightnessLabel;

  /// No description provided for @imageEditorContrastLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'对比度'**
  String get imageEditorContrastLabel;

  /// No description provided for @imageEditorRotateLeft.
  ///
  /// In zh_Hans, this message translates to:
  /// **'左转'**
  String get imageEditorRotateLeft;

  /// No description provided for @imageEditorRotateRight.
  ///
  /// In zh_Hans, this message translates to:
  /// **'右转'**
  String get imageEditorRotateRight;

  /// No description provided for @imageEditorReset.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重置'**
  String get imageEditorReset;

  /// No description provided for @imageEditorLoadFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'无法加载所选图片'**
  String get imageEditorLoadFailed;

  /// No description provided for @imageEditorProcessFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'无法处理所选图片'**
  String get imageEditorProcessFailed;

  /// No description provided for @imageEditorSectionBasic.
  ///
  /// In zh_Hans, this message translates to:
  /// **'基础调整'**
  String get imageEditorSectionBasic;

  /// No description provided for @imageEditorSectionColor.
  ///
  /// In zh_Hans, this message translates to:
  /// **'色彩（色温 / 色调 / 伽马）'**
  String get imageEditorSectionColor;

  /// No description provided for @imageEditorSectionSplitToning.
  ///
  /// In zh_Hans, this message translates to:
  /// **'色调分离（HSL）'**
  String get imageEditorSectionSplitToning;

  /// No description provided for @imageEditorSectionDetail.
  ///
  /// In zh_Hans, this message translates to:
  /// **'细节（清晰度 / 锐度 / 降噪 / 颗粒）'**
  String get imageEditorSectionDetail;

  /// No description provided for @imageEditorSectionEffects.
  ///
  /// In zh_Hans, this message translates to:
  /// **'特效（色散 / 扭曲 / 晕影）'**
  String get imageEditorSectionEffects;

  /// No description provided for @imageEditorSectionWatermark.
  ///
  /// In zh_Hans, this message translates to:
  /// **'文字水印 / 标记'**
  String get imageEditorSectionWatermark;

  /// No description provided for @imageEditorTemperatureLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'色温'**
  String get imageEditorTemperatureLabel;

  /// No description provided for @imageEditorTintLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'色调偏移'**
  String get imageEditorTintLabel;

  /// No description provided for @imageEditorGammaLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'伽马（曲线）'**
  String get imageEditorGammaLabel;

  /// No description provided for @imageEditorShadowHueLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暗部色相'**
  String get imageEditorShadowHueLabel;

  /// No description provided for @imageEditorShadowStrengthLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暗部强度'**
  String get imageEditorShadowStrengthLabel;

  /// No description provided for @imageEditorHighlightHueLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'亮部色相'**
  String get imageEditorHighlightHueLabel;

  /// No description provided for @imageEditorHighlightStrengthLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'亮部强度'**
  String get imageEditorHighlightStrengthLabel;

  /// No description provided for @imageEditorClarityLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'清晰度'**
  String get imageEditorClarityLabel;

  /// No description provided for @imageEditorSharpnessLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'锐度'**
  String get imageEditorSharpnessLabel;

  /// No description provided for @imageEditorDenoiseLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'降噪'**
  String get imageEditorDenoiseLabel;

  /// No description provided for @imageEditorGrainLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'颗粒'**
  String get imageEditorGrainLabel;

  /// No description provided for @imageEditorDispersionLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'色散'**
  String get imageEditorDispersionLabel;

  /// No description provided for @imageEditorDistortLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'扭曲（正值凸出 / 负值拉伸）'**
  String get imageEditorDistortLabel;

  /// No description provided for @imageEditorWatermarkTextLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'水印文字'**
  String get imageEditorWatermarkTextLabel;

  /// No description provided for @imageEditorWatermarkTextHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输入要叠加的文字（留空则不添加）'**
  String get imageEditorWatermarkTextHint;

  /// No description provided for @imageEditorWatermarkSizeLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'文字大小'**
  String get imageEditorWatermarkSizeLabel;

  /// No description provided for @imageEditorWatermarkOpacityLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'不透明度'**
  String get imageEditorWatermarkOpacityLabel;

  /// No description provided for @imageEditorWatermarkPositionLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'位置'**
  String get imageEditorWatermarkPositionLabel;

  /// No description provided for @imageEditorWatermarkColorLight.
  ///
  /// In zh_Hans, this message translates to:
  /// **'浅色'**
  String get imageEditorWatermarkColorLight;

  /// No description provided for @imageEditorWatermarkColorDark.
  ///
  /// In zh_Hans, this message translates to:
  /// **'深色'**
  String get imageEditorWatermarkColorDark;

  /// No description provided for @imageEditorAdvancedApplyHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'展开面板中的调整会在“保存”时一次性应用到原图。'**
  String get imageEditorAdvancedApplyHint;

  /// No description provided for @skillsEditorSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get skillsEditorSave;

  /// No description provided for @skillsEditorCancel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'取消'**
  String get skillsEditorCancel;

  /// No description provided for @skillsEditSuccess.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能内容已保存'**
  String get skillsEditSuccess;

  /// No description provided for @skillsDeleteConfirmTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除技能'**
  String get skillsDeleteConfirmTitle;

  /// No description provided for @skillsDeleteConfirmBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除后将永久移除该技能目录及其 SKILL.md 内容。'**
  String get skillsDeleteConfirmBody;

  /// No description provided for @skillsDeleteConfirmAction.
  ///
  /// In zh_Hans, this message translates to:
  /// **'确认删除'**
  String get skillsDeleteConfirmAction;

  /// No description provided for @skillsDeleteSuccess.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能已删除'**
  String get skillsDeleteSuccess;

  /// No description provided for @skillsStorageSectionTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能存放位置'**
  String get skillsStorageSectionTitle;

  /// No description provided for @skillsStorageSectionBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'配置 OpenHand 扫描技能的本地目录。默认会使用 ~/.openhand/skills，并在需要时自动创建。'**
  String get skillsStorageSectionBody;

  /// No description provided for @skillsStorageDefaultPath.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认路径'**
  String get skillsStorageDefaultPath;

  /// No description provided for @skillsStorageCurrentPath.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前路径'**
  String get skillsStorageCurrentPath;

  /// No description provided for @skillsStorageSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存位置'**
  String get skillsStorageSave;

  /// No description provided for @skillsStorageBrowse.
  ///
  /// In zh_Hans, this message translates to:
  /// **'选择目录'**
  String get skillsStorageBrowse;

  /// No description provided for @skillsStorageReset.
  ///
  /// In zh_Hans, this message translates to:
  /// **'恢复默认'**
  String get skillsStorageReset;

  /// No description provided for @skillsStorageOpen.
  ///
  /// In zh_Hans, this message translates to:
  /// **'打开位置'**
  String get skillsStorageOpen;

  /// No description provided for @skillsStorageSummaryTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能摘要'**
  String get skillsStorageSummaryTitle;

  /// No description provided for @skillsStorageSummaryBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前技能目录、安装数量与扫描状态会在这里实时展示。'**
  String get skillsStorageSummaryBody;

  /// No description provided for @skillsStorageStatusReady.
  ///
  /// In zh_Hans, this message translates to:
  /// **'状态'**
  String get skillsStorageStatusReady;

  /// No description provided for @skillsStorageStatusLoading.
  ///
  /// In zh_Hans, this message translates to:
  /// **'扫描中'**
  String get skillsStorageStatusLoading;

  /// No description provided for @skillsStorageStatusError.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能目录读取失败'**
  String get skillsStorageStatusError;

  /// No description provided for @skillsPathSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能存放位置已更新'**
  String get skillsPathSaved;

  /// No description provided for @instructionPageTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'指令'**
  String get instructionPageTitle;

  /// No description provided for @instructionPageSubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'维护应用内的可复用提示词片段。启用的指令会按当前顺序注入到所有线程模板的 system prompt，并在会话输入框上方以胶囊形式列出，可在单次发送前临时取消或重新加入。'**
  String get instructionPageSubtitle;

  /// No description provided for @instructionRefresh.
  ///
  /// In zh_Hans, this message translates to:
  /// **'刷新'**
  String get instructionRefresh;

  /// No description provided for @instructionNewEntry.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新建指令'**
  String get instructionNewEntry;

  /// No description provided for @instructionEmptyTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'尚未创建指令'**
  String get instructionEmptyTitle;

  /// No description provided for @instructionEmptyBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新建第一条可复用指令后，OpenHand 会把它保存到本地指令库中。'**
  String get instructionEmptyBody;

  /// No description provided for @instructionLoadFailedTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'指令库读取失败'**
  String get instructionLoadFailedTitle;

  /// No description provided for @instructionDeleteConfirmTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除指令'**
  String get instructionDeleteConfirmTitle;

  /// No description provided for @instructionDeleteConfirmBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'确认删除这条指令吗？删除后无法恢复。'**
  String get instructionDeleteConfirmBody;

  /// No description provided for @instructionEnabledStatus.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已启用并注入'**
  String get instructionEnabledStatus;

  /// No description provided for @instructionDisabledStatus.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已停用'**
  String get instructionDisabledStatus;

  /// No description provided for @instructionApplyToChipLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'适用'**
  String get instructionApplyToChipLabel;

  /// No description provided for @instructionNotesChipLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'备注'**
  String get instructionNotesChipLabel;

  /// No description provided for @instructionDialogCreateTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新建指令'**
  String get instructionDialogCreateTitle;

  /// No description provided for @instructionDialogEditTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'编辑指令'**
  String get instructionDialogEditTitle;

  /// No description provided for @instructionEnabledLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'启用'**
  String get instructionEnabledLabel;

  /// No description provided for @instructionEnabledBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'将这条指令注入到当前提示链中。'**
  String get instructionEnabledBody;

  /// No description provided for @instructionNameField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'名称 *'**
  String get instructionNameField;

  /// No description provided for @instructionNameRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入名称。'**
  String get instructionNameRequired;

  /// No description provided for @instructionDescriptionField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'描述'**
  String get instructionDescriptionField;

  /// No description provided for @instructionVersionField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'版本'**
  String get instructionVersionField;

  /// No description provided for @instructionApplyToField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'适用范围（描述何时加载这条指令）'**
  String get instructionApplyToField;

  /// No description provided for @instructionTaskTypesField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'触发任务类型（逗号分隔）'**
  String get instructionTaskTypesField;

  /// No description provided for @instructionKeywordsField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'触发关键词（逗号分隔）'**
  String get instructionKeywordsField;

  /// No description provided for @instructionNotesField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'备注（每行一条）'**
  String get instructionNotesField;

  /// No description provided for @instructionBodyField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'指令正文 *（Markdown）'**
  String get instructionBodyField;

  /// No description provided for @instructionBodyRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入指令正文。'**
  String get instructionBodyRequired;

  /// No description provided for @instructionCreateAction.
  ///
  /// In zh_Hans, this message translates to:
  /// **'创建'**
  String get instructionCreateAction;

  /// No description provided for @instructionSaveFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存失败，请检查必填项是否为空。'**
  String get instructionSaveFailed;

  /// No description provided for @memoryPageTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'记忆'**
  String get memoryPageTitle;

  /// No description provided for @memoryPageSubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'统一维护用户可编辑记忆，所有条目会持久化到本地 JSON 文件。'**
  String get memoryPageSubtitle;

  /// No description provided for @memoryRefresh.
  ///
  /// In zh_Hans, this message translates to:
  /// **'刷新'**
  String get memoryRefresh;

  /// No description provided for @memoryNewEntry.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增记忆'**
  String get memoryNewEntry;

  /// No description provided for @memoryEmptyTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'还没有任何用户记忆'**
  String get memoryEmptyTitle;

  /// No description provided for @memoryEmptyBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增一条用户记忆后，它会持久化保存到当前配置的记忆文件中。'**
  String get memoryEmptyBody;

  /// No description provided for @memoryLoadFailedTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'记忆文件读取失败'**
  String get memoryLoadFailedTitle;

  /// No description provided for @memoryOperationFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'记忆操作失败，请稍后重试。'**
  String get memoryOperationFailed;

  /// No description provided for @memoryDialogCreateTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增用户记忆'**
  String get memoryDialogCreateTitle;

  /// No description provided for @memoryDialogEditTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'编辑用户记忆'**
  String get memoryDialogEditTitle;

  /// No description provided for @memoryContentField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'记忆内容'**
  String get memoryContentField;

  /// No description provided for @memoryContentRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入记忆内容'**
  String get memoryContentRequired;

  /// No description provided for @memoryTagsField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'标签'**
  String get memoryTagsField;

  /// No description provided for @memoryTagsHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输入一个标签后按回车添加'**
  String get memoryTagsHint;

  /// No description provided for @memoryDeleteConfirmTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除用户记忆'**
  String get memoryDeleteConfirmTitle;

  /// No description provided for @memoryDeleteConfirmBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'确认删除这条用户记忆吗？删除后无法恢复。'**
  String get memoryDeleteConfirmBody;

  /// No description provided for @memoryTypeUser.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户编辑'**
  String get memoryTypeUser;

  /// No description provided for @memoryEntryCreated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户记忆已创建'**
  String get memoryEntryCreated;

  /// No description provided for @memoryEntryUpdated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户记忆已更新'**
  String get memoryEntryUpdated;

  /// No description provided for @memoryEntryDeleted.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户记忆已删除'**
  String get memoryEntryDeleted;

  /// No description provided for @memoryEnabledLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'启用记忆能力'**
  String get memoryEnabledLabel;

  /// No description provided for @memoryEnabledBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭后不会在运行时使用用户记忆，但仍然保留已保存的记忆内容。'**
  String get memoryEnabledBody;

  /// No description provided for @userMemoryFileLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户记忆文件'**
  String get userMemoryFileLabel;

  /// No description provided for @memoryFileBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'配置用户记忆 JSON 文件位置。默认会使用当前程序目录下的 .openhand/memory/user-memory.json。'**
  String get memoryFileBody;

  /// No description provided for @memoryFileDefaultPath.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认文件'**
  String get memoryFileDefaultPath;

  /// No description provided for @memoryFileSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存路径'**
  String get memoryFileSave;

  /// No description provided for @memoryFileBrowse.
  ///
  /// In zh_Hans, this message translates to:
  /// **'选择文件'**
  String get memoryFileBrowse;

  /// No description provided for @memoryFileReset.
  ///
  /// In zh_Hans, this message translates to:
  /// **'恢复默认'**
  String get memoryFileReset;

  /// No description provided for @memoryOpenDirectory.
  ///
  /// In zh_Hans, this message translates to:
  /// **'打开目录'**
  String get memoryOpenDirectory;

  /// No description provided for @memoryPathSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户记忆文件路径已更新'**
  String get memoryPathSaved;

  /// No description provided for @memoryDisabledTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'记忆能力当前已关闭'**
  String get memoryDisabledTitle;

  /// No description provided for @memoryDisabledBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'你仍然可以在这里维护用户记忆内容；如需在运行时启用，请到设置页记忆板块打开记忆开关。'**
  String get memoryDisabledBody;

  /// No description provided for @memoryCreatedAtLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'创建时间'**
  String get memoryCreatedAtLabel;

  /// No description provided for @memoryPersistenceRecoveredTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'记忆文件已自动恢复'**
  String get memoryPersistenceRecoveredTitle;

  /// No description provided for @memoryPersistenceRecoveredBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'检测到记忆文件内容损坏或被篡改，OpenHand 已备份异常文件并恢复为空列表。'**
  String get memoryPersistenceRecoveredBody;

  /// No description provided for @memoryPersistenceSanitizedTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'记忆内容已自动修正'**
  String get memoryPersistenceSanitizedTitle;

  /// No description provided for @memoryPersistenceSanitizedBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'检测到部分记忆字段无效，OpenHand 已忽略异常条目并重新写回有效内容。'**
  String get memoryPersistenceSanitizedBody;

  /// No description provided for @memoryPersistenceSaveFailedTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'记忆文件保存失败'**
  String get memoryPersistenceSaveFailedTitle;

  /// No description provided for @memoryPersistenceSaveFailedBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'写入记忆文件失败，界面已回滚到上一次有效内容，请检查文件权限或磁盘状态。'**
  String get memoryPersistenceSaveFailedBody;

  /// No description provided for @mcpPageTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP'**
  String get mcpPageTitle;

  /// No description provided for @mcpPageSubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'参考 Cursor 的 MCP 服务管理结构，统一维护本地 MCP Server 配置。'**
  String get mcpPageSubtitle;

  /// No description provided for @mcpRefresh.
  ///
  /// In zh_Hans, this message translates to:
  /// **'刷新'**
  String get mcpRefresh;

  /// No description provided for @mcpNewServer.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增服务'**
  String get mcpNewServer;

  /// No description provided for @mcpEmptyTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'还没有配置任何 MCP 服务'**
  String get mcpEmptyTitle;

  /// No description provided for @mcpEmptyBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'先新增一个 MCP Server，OpenHand 会把它保存到 ~/.openhand/mcp/mcp_servers.json 中。'**
  String get mcpEmptyBody;

  /// No description provided for @mcpLoadFailedTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 配置读取失败'**
  String get mcpLoadFailedTitle;

  /// No description provided for @mcpOperationFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 操作失败，请稍后重试。'**
  String get mcpOperationFailed;

  /// No description provided for @mcpDialogCreateTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增 MCP 服务'**
  String get mcpDialogCreateTitle;

  /// No description provided for @mcpDialogEditTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'编辑 MCP 服务'**
  String get mcpDialogEditTitle;

  /// No description provided for @mcpNameField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'服务名称'**
  String get mcpNameField;

  /// No description provided for @mcpNameRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入服务名称'**
  String get mcpNameRequired;

  /// No description provided for @mcpNameDuplicate.
  ///
  /// In zh_Hans, this message translates to:
  /// **'服务名称已存在'**
  String get mcpNameDuplicate;

  /// No description provided for @mcpTypeField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'服务类型'**
  String get mcpTypeField;

  /// No description provided for @mcpUrlField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'服务 URL'**
  String get mcpUrlField;

  /// No description provided for @mcpUrlRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入服务 URL'**
  String get mcpUrlRequired;

  /// No description provided for @mcpUrlInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效的服务 URL'**
  String get mcpUrlInvalid;

  /// No description provided for @mcpCommandField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'启动命令'**
  String get mcpCommandField;

  /// No description provided for @mcpCommandRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入启动命令'**
  String get mcpCommandRequired;

  /// No description provided for @mcpArgsField.
  ///
  /// In zh_Hans, this message translates to:
  /// **'命令参数'**
  String get mcpArgsField;

  /// No description provided for @mcpArgsHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'每行一个参数'**
  String get mcpArgsHint;

  /// No description provided for @mcpServerEnabledLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'启用该服务'**
  String get mcpServerEnabledLabel;

  /// No description provided for @mcpServerEnabledBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭后会保留服务配置，但不会在运行时启用它。'**
  String get mcpServerEnabledBody;

  /// No description provided for @mcpServerStatusEnabled.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已启用'**
  String get mcpServerStatusEnabled;

  /// No description provided for @mcpServerStatusDisabled.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已禁用'**
  String get mcpServerStatusDisabled;

  /// No description provided for @mcpServerCreated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 服务已创建'**
  String get mcpServerCreated;

  /// No description provided for @mcpServerUpdated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 服务已更新'**
  String get mcpServerUpdated;

  /// No description provided for @mcpServerDeleted.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 服务已删除'**
  String get mcpServerDeleted;

  /// No description provided for @mcpDeleteConfirmTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除 MCP 服务'**
  String get mcpDeleteConfirmTitle;

  /// No description provided for @mcpDeleteConfirmBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'确认删除这条 MCP 服务配置吗？'**
  String get mcpDeleteConfirmBody;

  /// No description provided for @mcpDisabledTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 服务当前已关闭'**
  String get mcpDisabledTitle;

  /// No description provided for @mcpDisabledBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'你仍然可以在这里维护服务配置；如需在运行时启用，请到设置页 MCP 板块打开 MCP 开关。'**
  String get mcpDisabledBody;

  /// No description provided for @mcpTransportStreamableHttp.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Streamable HTTP'**
  String get mcpTransportStreamableHttp;

  /// No description provided for @mcpTransportSse.
  ///
  /// In zh_Hans, this message translates to:
  /// **'SSE'**
  String get mcpTransportSse;

  /// No description provided for @mcpTransportStdio.
  ///
  /// In zh_Hans, this message translates to:
  /// **'STDIO'**
  String get mcpTransportStdio;

  /// No description provided for @mcpPersistenceRecoveredTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 配置文件已自动恢复'**
  String get mcpPersistenceRecoveredTitle;

  /// No description provided for @mcpPersistenceRecoveredBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'检测到 MCP 配置文件内容损坏或被篡改，OpenHand 已备份异常文件并恢复为空配置。'**
  String get mcpPersistenceRecoveredBody;

  /// No description provided for @mcpPersistenceSanitizedTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 配置内容已自动修正'**
  String get mcpPersistenceSanitizedTitle;

  /// No description provided for @mcpPersistenceSanitizedBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'检测到部分 MCP 服务字段无效，OpenHand 已忽略异常条目并重新写回有效配置。'**
  String get mcpPersistenceSanitizedBody;

  /// No description provided for @mcpPersistenceSaveFailedTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 配置保存失败'**
  String get mcpPersistenceSaveFailedTitle;

  /// No description provided for @mcpPersistenceSaveFailedBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'写入 MCP 配置文件失败，界面已回滚到上一次有效配置，请检查文件权限或磁盘状态。'**
  String get mcpPersistenceSaveFailedBody;

  /// No description provided for @threadsEmptyBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前还没有任何对话线程，创建一个新线程即可开始。'**
  String get threadsEmptyBody;

  /// No description provided for @threadTemplateDialogTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'选择线程模板'**
  String get threadTemplateDialogTitle;

  /// No description provided for @threadTemplateDialogBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新建线程前，请先从下方内置能力模板中选择一个。'**
  String get threadTemplateDialogBody;

  /// No description provided for @threadCompressionNotice.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前线程中的较早消息已被压缩为摘要检查点，以便让活跃 Prompt 保持聚焦。'**
  String get threadCompressionNotice;

  /// No description provided for @threadCompressionCheckpointLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'摘要检查点'**
  String get threadCompressionCheckpointLabel;

  /// No description provided for @aiCompressionThresholdLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息压缩阈值'**
  String get aiCompressionThresholdLabel;

  /// No description provided for @aiCompressionThresholdBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当当前线程中未压缩的历史消息字符总数超过该阈值时，OpenHand 会将更早的一段消息压缩为摘要检查点，并保留最近的一段消息继续参与 Prompt 组装。'**
  String get aiCompressionThresholdBody;

  /// No description provided for @aiCompressionThresholdSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存阈值'**
  String get aiCompressionThresholdSave;

  /// No description provided for @aiCompressionThresholdSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'AI 消息压缩阈值已更新。'**
  String get aiCompressionThresholdSaved;

  /// No description provided for @aiCompressionThresholdInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效的正整数阈值。'**
  String get aiCompressionThresholdInvalid;

  /// No description provided for @aiToolResultCompressionThresholdLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具调用输出压缩阈值'**
  String get aiToolResultCompressionThresholdLabel;

  /// No description provided for @aiToolResultCompressionThresholdBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当某个工具调用返回的 raw 内容字符数超过该阈值时，OpenHand 会在拼装 conversation history 前将其压缩为“受影响路径+目的+首尾片段”的结构化摘要，释放 tokens。默认 1024。'**
  String get aiToolResultCompressionThresholdBody;

  /// No description provided for @aiToolResultCompressionThresholdSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存阈值'**
  String get aiToolResultCompressionThresholdSave;

  /// No description provided for @aiToolResultCompressionThresholdSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具调用输出压缩阈值已更新。'**
  String get aiToolResultCompressionThresholdSaved;

  /// No description provided for @aiToolResultCompressionThresholdInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效的正整数阈值。'**
  String get aiToolResultCompressionThresholdInvalid;

  /// No description provided for @aiToolResultCompressionEnabledLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'启用工具调用输出压缩'**
  String get aiToolResultCompressionEnabledLabel;

  /// No description provided for @aiToolResultCompressionEnabledBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'总开关。关闭后不论阈值多大都不压缩工具输出原文，适合需要调试完整输出的场景。'**
  String get aiToolResultCompressionEnabledBody;

  /// No description provided for @aiToolResultCompressionHeadTailWindowLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'压缩摘要首尾片段窗口'**
  String get aiToolResultCompressionHeadTailWindowLabel;

  /// No description provided for @aiToolResultCompressionHeadTailWindowBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'压缩后摘要中保留 raw 输出首尾各多少个字符。默认 256；0 表示不保留首尾片段；范围 0~8192。'**
  String get aiToolResultCompressionHeadTailWindowBody;

  /// No description provided for @aiToolResultCompressionHeadTailWindowSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存窗口长度'**
  String get aiToolResultCompressionHeadTailWindowSave;

  /// No description provided for @aiToolResultCompressionHeadTailWindowSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'首尾片段窗口已更新。'**
  String get aiToolResultCompressionHeadTailWindowSaved;

  /// No description provided for @aiToolResultCompressionHeadTailWindowInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 0~8192 之间的整数。'**
  String get aiToolResultCompressionHeadTailWindowInvalid;

  /// No description provided for @aiToolResultCompressionMaxPathHitsLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'压缩摘要提取路径上限'**
  String get aiToolResultCompressionMaxPathHitsLabel;

  /// No description provided for @aiToolResultCompressionMaxPathHitsBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'压缩后摘要中提取受影响文件路径的最大条数。默认 12；0 表示不提取；范围 0~200。'**
  String get aiToolResultCompressionMaxPathHitsBody;

  /// No description provided for @aiToolResultCompressionMaxPathHitsSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存上限'**
  String get aiToolResultCompressionMaxPathHitsSave;

  /// No description provided for @aiToolResultCompressionMaxPathHitsSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'路径提取上限已更新。'**
  String get aiToolResultCompressionMaxPathHitsSaved;

  /// No description provided for @aiToolResultCompressionMaxPathHitsInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 0~200 之间的整数。'**
  String get aiToolResultCompressionMaxPathHitsInvalid;

  /// No description provided for @aiWriteToolSummaryMaxCharsLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'写类工具摘要字符上限'**
  String get aiWriteToolSummaryMaxCharsLabel;

  /// No description provided for @aiWriteToolSummaryMaxCharsBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'写类工具（write/edit/multiedit/notebookedit/写型 bash）结果摘要中保留 result_text 原文的最大字符数。默认 280；0 表示不保留；范围 0~8192。'**
  String get aiWriteToolSummaryMaxCharsBody;

  /// No description provided for @aiWriteToolSummaryMaxCharsSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存上限'**
  String get aiWriteToolSummaryMaxCharsSave;

  /// No description provided for @aiWriteToolSummaryMaxCharsSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'写类工具摘要字符上限已更新。'**
  String get aiWriteToolSummaryMaxCharsSaved;

  /// No description provided for @aiWriteToolSummaryMaxCharsInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 0~8192 之间的整数。'**
  String get aiWriteToolSummaryMaxCharsInvalid;

  /// No description provided for @aiMaxRecentErrorsLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话错误记录保留上限'**
  String get aiMaxRecentErrorsLabel;

  /// No description provided for @aiMaxRecentErrorsBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'AI 会话状态中保留的最近错误记录条数。默认 15；范围 0~1000。'**
  String get aiMaxRecentErrorsBody;

  /// No description provided for @aiMaxRecentErrorsSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存上限'**
  String get aiMaxRecentErrorsSave;

  /// No description provided for @aiMaxRecentErrorsSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话错误记录保留上限已更新。'**
  String get aiMaxRecentErrorsSaved;

  /// No description provided for @aiMaxRecentErrorsInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 0~1000 之间的整数。'**
  String get aiMaxRecentErrorsInvalid;

  /// No description provided for @aiMaxPlanHistoryEntriesLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划历史保留上限'**
  String get aiMaxPlanHistoryEntriesLabel;

  /// No description provided for @aiMaxPlanHistoryEntriesBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Plan 模式下 plan_history 保留的最大条目数。默认 15；范围 0~1000。'**
  String get aiMaxPlanHistoryEntriesBody;

  /// No description provided for @aiMaxPlanHistoryEntriesSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存上限'**
  String get aiMaxPlanHistoryEntriesSave;

  /// No description provided for @aiMaxPlanHistoryEntriesSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划历史保留上限已更新。'**
  String get aiMaxPlanHistoryEntriesSaved;

  /// No description provided for @aiMaxPlanHistoryEntriesInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 0~1000 之间的整数。'**
  String get aiMaxPlanHistoryEntriesInvalid;

  /// No description provided for @aiMaxTruncationContinuationsLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动续接轮次上限'**
  String get aiMaxTruncationContinuationsLabel;

  /// No description provided for @aiMaxTruncationContinuationsBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模型输出被截断（finish_reason=length）后自动续接的最大次数。默认 5；范围 0~100。'**
  String get aiMaxTruncationContinuationsBody;

  /// No description provided for @aiMaxTruncationContinuationsSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存上限'**
  String get aiMaxTruncationContinuationsSave;

  /// No description provided for @aiMaxTruncationContinuationsSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动续接轮次上限已更新。'**
  String get aiMaxTruncationContinuationsSaved;

  /// No description provided for @aiMaxTruncationContinuationsInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 0~100 之间的整数。'**
  String get aiMaxTruncationContinuationsInvalid;

  /// No description provided for @aiEstimatedCharactersPerTokenLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Token 字符估算系数'**
  String get aiEstimatedCharactersPerTokenLabel;

  /// No description provided for @aiEstimatedCharactersPerTokenBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'每个 token 约等于多少个字符，用于上下文容量估算。默认 4；范围 1~32。'**
  String get aiEstimatedCharactersPerTokenBody;

  /// No description provided for @aiEstimatedCharactersPerTokenSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存系数'**
  String get aiEstimatedCharactersPerTokenSave;

  /// No description provided for @aiEstimatedCharactersPerTokenSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Token 字符估算系数已更新。'**
  String get aiEstimatedCharactersPerTokenSaved;

  /// No description provided for @aiEstimatedCharactersPerTokenInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 1~32 之间的整数。'**
  String get aiEstimatedCharactersPerTokenInvalid;

  /// No description provided for @aiMaxToolOutputCharsLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具单次输出字符上限'**
  String get aiMaxToolOutputCharsLabel;

  /// No description provided for @aiMaxToolOutputCharsBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 150000。单次工具调用结果若超过这个字符数会截断，避免 Context 溢出。'**
  String get aiMaxToolOutputCharsBody;

  /// No description provided for @aiMaxToolOutputCharsSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存上限'**
  String get aiMaxToolOutputCharsSave;

  /// No description provided for @aiMaxToolOutputCharsSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具输出字符上限已保存。'**
  String get aiMaxToolOutputCharsSaved;

  /// No description provided for @aiMaxToolOutputCharsInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 1000~10000000 之间的整数。'**
  String get aiMaxToolOutputCharsInvalid;

  /// No description provided for @aiWriteConfirmationTimeoutMsLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'写命令确认超时（毫秒）'**
  String get aiWriteConfirmationTimeoutMsLabel;

  /// No description provided for @aiWriteConfirmationTimeoutMsBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 300000（5 分钟）。等待用户审批写命令的最长时间。'**
  String get aiWriteConfirmationTimeoutMsBody;

  /// No description provided for @aiWriteConfirmationTimeoutMsSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存超时'**
  String get aiWriteConfirmationTimeoutMsSave;

  /// No description provided for @aiWriteConfirmationTimeoutMsSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'写命令确认超时已保存。'**
  String get aiWriteConfirmationTimeoutMsSaved;

  /// No description provided for @aiWriteConfirmationTimeoutMsInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 1000~3600000 之间的整数。'**
  String get aiWriteConfirmationTimeoutMsInvalid;

  /// No description provided for @aiFastPathWriteAnalysisThresholdLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Fast-path 写命令分析阈值'**
  String get aiFastPathWriteAnalysisThresholdLabel;

  /// No description provided for @aiFastPathWriteAnalysisThresholdBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 512 字符。命令长度超过此值会走快速路径粗判，避免昂贵的语法分析。'**
  String get aiFastPathWriteAnalysisThresholdBody;

  /// No description provided for @aiFastPathWriteAnalysisThresholdSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存阈值'**
  String get aiFastPathWriteAnalysisThresholdSave;

  /// No description provided for @aiFastPathWriteAnalysisThresholdSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Fast-path 阈值已保存。'**
  String get aiFastPathWriteAnalysisThresholdSaved;

  /// No description provided for @aiFastPathWriteAnalysisThresholdInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 0~100000 之间的整数。'**
  String get aiFastPathWriteAnalysisThresholdInvalid;

  /// No description provided for @aiMaxHookTextCharactersLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Hook 文本输出上限'**
  String get aiMaxHookTextCharactersLabel;

  /// No description provided for @aiMaxHookTextCharactersBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 4000。Claude Hook 在合并 stdout/stderr 文本时的总字符上限。'**
  String get aiMaxHookTextCharactersBody;

  /// No description provided for @aiMaxHookTextCharactersSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存上限'**
  String get aiMaxHookTextCharactersSave;

  /// No description provided for @aiMaxHookTextCharactersSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Hook 文本上限已保存。'**
  String get aiMaxHookTextCharactersSaved;

  /// No description provided for @aiMaxHookTextCharactersInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 100~1000000 之间的整数。'**
  String get aiMaxHookTextCharactersInvalid;

  /// No description provided for @aiWebFetchMaxResponseBytesLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'WebFetch 单次响应字节上限'**
  String get aiWebFetchMaxResponseBytesLabel;

  /// No description provided for @aiWebFetchMaxResponseBytesBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 1048576（1MB）。调整以适配你的网络与附件需求。'**
  String get aiWebFetchMaxResponseBytesBody;

  /// No description provided for @aiWebFetchMaxResponseBytesSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiWebFetchMaxResponseBytesSave;

  /// No description provided for @aiWebFetchMaxResponseBytesSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'WebFetch 单次响应字节上限已保存。'**
  String get aiWebFetchMaxResponseBytesSaved;

  /// No description provided for @aiWebFetchMaxResponseBytesInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiWebFetchMaxResponseBytesInvalid;

  /// No description provided for @aiWebFetchMaxRedirectsLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'WebFetch 最大重定向次数'**
  String get aiWebFetchMaxRedirectsLabel;

  /// No description provided for @aiWebFetchMaxRedirectsBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 5。调整以适配你的网络与附件需求。'**
  String get aiWebFetchMaxRedirectsBody;

  /// No description provided for @aiWebFetchMaxRedirectsSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiWebFetchMaxRedirectsSave;

  /// No description provided for @aiWebFetchMaxRedirectsSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'WebFetch 最大重定向次数已保存。'**
  String get aiWebFetchMaxRedirectsSaved;

  /// No description provided for @aiWebFetchMaxRedirectsInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiWebFetchMaxRedirectsInvalid;

  /// No description provided for @aiWebFetchMaxCacheEntriesLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'WebFetch 缓存条目上限'**
  String get aiWebFetchMaxCacheEntriesLabel;

  /// No description provided for @aiWebFetchMaxCacheEntriesBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 64。调整以适配你的网络与附件需求。'**
  String get aiWebFetchMaxCacheEntriesBody;

  /// No description provided for @aiWebFetchMaxCacheEntriesSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiWebFetchMaxCacheEntriesSave;

  /// No description provided for @aiWebFetchMaxCacheEntriesSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'WebFetch 缓存条目上限已保存。'**
  String get aiWebFetchMaxCacheEntriesSaved;

  /// No description provided for @aiWebFetchMaxCacheEntriesInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiWebFetchMaxCacheEntriesInvalid;

  /// No description provided for @aiAttachmentMaxInlineImageDimensionLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'附件图片最大边长（像素）'**
  String get aiAttachmentMaxInlineImageDimensionLabel;

  /// No description provided for @aiAttachmentMaxInlineImageDimensionBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 1568。调整以适配你的网络与附件需求。'**
  String get aiAttachmentMaxInlineImageDimensionBody;

  /// No description provided for @aiAttachmentMaxInlineImageDimensionSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiAttachmentMaxInlineImageDimensionSave;

  /// No description provided for @aiAttachmentMaxInlineImageDimensionSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'附件图片最大边长（像素）已保存。'**
  String get aiAttachmentMaxInlineImageDimensionSaved;

  /// No description provided for @aiAttachmentMaxInlineImageDimensionInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiAttachmentMaxInlineImageDimensionInvalid;

  /// No description provided for @aiAttachmentMaxTextRawBytesLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'附件文本读取上限（字节）'**
  String get aiAttachmentMaxTextRawBytesLabel;

  /// No description provided for @aiAttachmentMaxTextRawBytesBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 1597152（2MB）。调整以适配你的网络与附件需求。'**
  String get aiAttachmentMaxTextRawBytesBody;

  /// No description provided for @aiAttachmentMaxTextRawBytesSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiAttachmentMaxTextRawBytesSave;

  /// No description provided for @aiAttachmentMaxTextRawBytesSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'附件文本读取上限（字节）已保存。'**
  String get aiAttachmentMaxTextRawBytesSaved;

  /// No description provided for @aiAttachmentMaxTextRawBytesInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiAttachmentMaxTextRawBytesInvalid;

  /// No description provided for @aiAttachmentMaxPdfRawBytesLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'附件 PDF 读取上限（字节）'**
  String get aiAttachmentMaxPdfRawBytesLabel;

  /// No description provided for @aiAttachmentMaxPdfRawBytesBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 1597152（2MB）。调整以适配你的网络与附件需求。'**
  String get aiAttachmentMaxPdfRawBytesBody;

  /// No description provided for @aiAttachmentMaxPdfRawBytesSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiAttachmentMaxPdfRawBytesSave;

  /// No description provided for @aiAttachmentMaxPdfRawBytesSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'附件 PDF 读取上限（字节）已保存。'**
  String get aiAttachmentMaxPdfRawBytesSaved;

  /// No description provided for @aiAttachmentMaxPdfRawBytesInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiAttachmentMaxPdfRawBytesInvalid;

  /// No description provided for @aiAttachmentMaxImageRawBytesLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'附件图片读取上限（字节）'**
  String get aiAttachmentMaxImageRawBytesLabel;

  /// No description provided for @aiAttachmentMaxImageRawBytesBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 52428800（50MB）。调整以适配你的网络与附件需求。'**
  String get aiAttachmentMaxImageRawBytesBody;

  /// No description provided for @aiAttachmentMaxImageRawBytesSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiAttachmentMaxImageRawBytesSave;

  /// No description provided for @aiAttachmentMaxImageRawBytesSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'附件图片读取上限（字节）已保存。'**
  String get aiAttachmentMaxImageRawBytesSaved;

  /// No description provided for @aiAttachmentMaxImageRawBytesInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiAttachmentMaxImageRawBytesInvalid;

  /// No description provided for @aiChatMaxStreamLineBufferBytesLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Chat 流缓冲字节上限'**
  String get aiChatMaxStreamLineBufferBytesLabel;

  /// No description provided for @aiChatMaxStreamLineBufferBytesBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 4194304（4MB）。调整以适配你的网络与附件需求。'**
  String get aiChatMaxStreamLineBufferBytesBody;

  /// No description provided for @aiChatMaxStreamLineBufferBytesSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiChatMaxStreamLineBufferBytesSave;

  /// No description provided for @aiChatMaxStreamLineBufferBytesSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Chat 流缓冲字节上限已保存。'**
  String get aiChatMaxStreamLineBufferBytesSaved;

  /// No description provided for @aiChatMaxStreamLineBufferBytesInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiChatMaxStreamLineBufferBytesInvalid;

  /// No description provided for @aiFallbackTitleMaxCharactersLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'回退标题最大字符数'**
  String get aiFallbackTitleMaxCharactersLabel;

  /// No description provided for @aiFallbackTitleMaxCharactersBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 15。调整以匹配会话标题派生策略。'**
  String get aiFallbackTitleMaxCharactersBody;

  /// No description provided for @aiFallbackTitleMaxCharactersSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiFallbackTitleMaxCharactersSave;

  /// No description provided for @aiFallbackTitleMaxCharactersSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'回退标题最大字符数已保存。'**
  String get aiFallbackTitleMaxCharactersSaved;

  /// No description provided for @aiFallbackTitleMaxCharactersInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiFallbackTitleMaxCharactersInvalid;

  /// No description provided for @aiGeneratedTitleMaxCharactersLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动标题最大字符数'**
  String get aiGeneratedTitleMaxCharactersLabel;

  /// No description provided for @aiGeneratedTitleMaxCharactersBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 15。调整以匹配会话标题派生策略。'**
  String get aiGeneratedTitleMaxCharactersBody;

  /// No description provided for @aiGeneratedTitleMaxCharactersSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiGeneratedTitleMaxCharactersSave;

  /// No description provided for @aiGeneratedTitleMaxCharactersSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动标题最大字符数已保存。'**
  String get aiGeneratedTitleMaxCharactersSaved;

  /// No description provided for @aiGeneratedTitleMaxCharactersInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiGeneratedTitleMaxCharactersInvalid;

  /// No description provided for @aiMinimumMeaningfulTitleCharactersLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'中文有效标题最小字符数'**
  String get aiMinimumMeaningfulTitleCharactersLabel;

  /// No description provided for @aiMinimumMeaningfulTitleCharactersBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 4。调整以匹配会话标题派生策略。'**
  String get aiMinimumMeaningfulTitleCharactersBody;

  /// No description provided for @aiMinimumMeaningfulTitleCharactersSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiMinimumMeaningfulTitleCharactersSave;

  /// No description provided for @aiMinimumMeaningfulTitleCharactersSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'中文有效标题最小字符数已保存。'**
  String get aiMinimumMeaningfulTitleCharactersSaved;

  /// No description provided for @aiMinimumMeaningfulTitleCharactersInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiMinimumMeaningfulTitleCharactersInvalid;

  /// No description provided for @aiMinimumMeaningfulLatinTitleWordsLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'拉丁有效标题最小词数'**
  String get aiMinimumMeaningfulLatinTitleWordsLabel;

  /// No description provided for @aiMinimumMeaningfulLatinTitleWordsBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 2。调整以匹配会话标题派生策略。'**
  String get aiMinimumMeaningfulLatinTitleWordsBody;

  /// No description provided for @aiMinimumMeaningfulLatinTitleWordsSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiMinimumMeaningfulLatinTitleWordsSave;

  /// No description provided for @aiMinimumMeaningfulLatinTitleWordsSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'拉丁有效标题最小词数已保存。'**
  String get aiMinimumMeaningfulLatinTitleWordsSaved;

  /// No description provided for @aiMinimumMeaningfulLatinTitleWordsInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiMinimumMeaningfulLatinTitleWordsInvalid;

  /// No description provided for @aiMaxSkillContentLengthLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能文件内容字符上限'**
  String get aiMaxSkillContentLengthLabel;

  /// No description provided for @aiMaxSkillContentLengthBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 100000。调整以适配技能与工作区文档大小。'**
  String get aiMaxSkillContentLengthBody;

  /// No description provided for @aiMaxSkillContentLengthSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiMaxSkillContentLengthSave;

  /// No description provided for @aiMaxSkillContentLengthSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能文件内容字符上限已保存。'**
  String get aiMaxSkillContentLengthSaved;

  /// No description provided for @aiMaxSkillContentLengthInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiMaxSkillContentLengthInvalid;

  /// No description provided for @aiMaxWorkspaceDocumentCharactersLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工作区指令文档字符上限'**
  String get aiMaxWorkspaceDocumentCharactersLabel;

  /// No description provided for @aiMaxWorkspaceDocumentCharactersBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 16000。调整以适配技能与工作区文档大小。'**
  String get aiMaxWorkspaceDocumentCharactersBody;

  /// No description provided for @aiMaxWorkspaceDocumentCharactersSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get aiMaxWorkspaceDocumentCharactersSave;

  /// No description provided for @aiMaxWorkspaceDocumentCharactersSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工作区指令文档字符上限已保存。'**
  String get aiMaxWorkspaceDocumentCharactersSaved;

  /// No description provided for @aiMaxWorkspaceDocumentCharactersInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效整数。'**
  String get aiMaxWorkspaceDocumentCharactersInvalid;

  /// No description provided for @aiImageSizeLimitLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'图片大小上限'**
  String get aiImageSizeLimitLabel;

  /// No description provided for @aiImageSizeLimitBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当用户添加的图片附件超过该上限时，OpenHand 会自动按质量 + 尺寸两级压缩后再发送。支持小数 MB；范围 0.0625 MB（64 KB）至 64 MB。'**
  String get aiImageSizeLimitBody;

  /// No description provided for @aiImageSizeLimitFieldLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'上限 (MB)'**
  String get aiImageSizeLimitFieldLabel;

  /// No description provided for @aiImageSizeLimitSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存上限'**
  String get aiImageSizeLimitSave;

  /// No description provided for @aiImageSizeLimitSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'图片附件大小上限已更新。'**
  String get aiImageSizeLimitSaved;

  /// No description provided for @aiImageSizeLimitInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入有效的正数 MB 值。'**
  String get aiImageSizeLimitInvalid;

  /// No description provided for @imageEditorAspectFree.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自由'**
  String get imageEditorAspectFree;

  /// No description provided for @imageEditorAspectOriginal.
  ///
  /// In zh_Hans, this message translates to:
  /// **'原始'**
  String get imageEditorAspectOriginal;

  /// No description provided for @imageEditorAspectSquare.
  ///
  /// In zh_Hans, this message translates to:
  /// **'1:1'**
  String get imageEditorAspectSquare;

  /// No description provided for @imageEditorAspect4x3.
  ///
  /// In zh_Hans, this message translates to:
  /// **'4:3'**
  String get imageEditorAspect4x3;

  /// No description provided for @imageEditorAspect3x4.
  ///
  /// In zh_Hans, this message translates to:
  /// **'3:4'**
  String get imageEditorAspect3x4;

  /// No description provided for @imageEditorAspect16x9.
  ///
  /// In zh_Hans, this message translates to:
  /// **'16:9'**
  String get imageEditorAspect16x9;

  /// No description provided for @imageEditorAspect9x16.
  ///
  /// In zh_Hans, this message translates to:
  /// **'9:16'**
  String get imageEditorAspect9x16;

  /// No description provided for @imageEditorAspectCircle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'圆形'**
  String get imageEditorAspectCircle;

  /// No description provided for @imageEditorFlipHorizontal.
  ///
  /// In zh_Hans, this message translates to:
  /// **'水平翻转'**
  String get imageEditorFlipHorizontal;

  /// No description provided for @imageEditorFlipVertical.
  ///
  /// In zh_Hans, this message translates to:
  /// **'垂直翻转'**
  String get imageEditorFlipVertical;

  /// No description provided for @imageEditorSaturationLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'饱和度'**
  String get imageEditorSaturationLabel;

  /// No description provided for @imageEditorExposureLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'曝光'**
  String get imageEditorExposureLabel;

  /// No description provided for @imageEditorHueLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'色相'**
  String get imageEditorHueLabel;

  /// No description provided for @imageEditorVignetteLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暗角'**
  String get imageEditorVignetteLabel;

  /// No description provided for @imageEditorFineRotationLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'微调旋转 (°)'**
  String get imageEditorFineRotationLabel;

  /// No description provided for @imageEditorSaveToFile.
  ///
  /// In zh_Hans, this message translates to:
  /// **'另存到本地'**
  String get imageEditorSaveToFile;

  /// No description provided for @imageEditorCopyToClipboard.
  ///
  /// In zh_Hans, this message translates to:
  /// **'复制到剪贴板'**
  String get imageEditorCopyToClipboard;

  /// No description provided for @imageEditorSavedTo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已另存：{path}'**
  String imageEditorSavedTo(String path);

  /// No description provided for @imageEditorSaveFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'另存失败：{error}'**
  String imageEditorSaveFailed(String error);

  /// No description provided for @imageEditorClipboardCopiedBitmap.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已复制图片到剪贴板（文件路径同时复制为文本）。'**
  String get imageEditorClipboardCopiedBitmap;

  /// No description provided for @imageEditorClipboardCopiedPath.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已复制图片文件路径到剪贴板：{path}'**
  String imageEditorClipboardCopiedPath(String path);

  /// No description provided for @imageEditorClipboardFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'复制失败：{error}'**
  String imageEditorClipboardFailed(String error);

  /// No description provided for @imageEditorApplyButton.
  ///
  /// In zh_Hans, this message translates to:
  /// **'应用'**
  String get imageEditorApplyButton;

  /// No description provided for @imageEditorUndoButton.
  ///
  /// In zh_Hans, this message translates to:
  /// **'回退'**
  String get imageEditorUndoButton;

  /// No description provided for @imageEditorResetAllButton.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重置全部'**
  String get imageEditorResetAllButton;

  /// No description provided for @imageEditorCompareHold.
  ///
  /// In zh_Hans, this message translates to:
  /// **'按住对比'**
  String get imageEditorCompareHold;

  /// No description provided for @imageEditorCompareRelease.
  ///
  /// In zh_Hans, this message translates to:
  /// **'松开返回'**
  String get imageEditorCompareRelease;

  /// No description provided for @imageEditorCompareOriginal.
  ///
  /// In zh_Hans, this message translates to:
  /// **'原图'**
  String get imageEditorCompareOriginal;

  /// No description provided for @imageEditorWatermarkColorLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'文字颜色'**
  String get imageEditorWatermarkColorLabel;

  /// No description provided for @imageEditorWatermarkColorHue.
  ///
  /// In zh_Hans, this message translates to:
  /// **'颜色（Hue）'**
  String get imageEditorWatermarkColorHue;

  /// No description provided for @imageEditorWatermarkColorSaturation.
  ///
  /// In zh_Hans, this message translates to:
  /// **'饱和度'**
  String get imageEditorWatermarkColorSaturation;

  /// No description provided for @imageEditorWatermarkColorLightness.
  ///
  /// In zh_Hans, this message translates to:
  /// **'明度'**
  String get imageEditorWatermarkColorLightness;

  /// No description provided for @imageEditorApplySuccess.
  ///
  /// In zh_Hans, this message translates to:
  /// **'调整已应用'**
  String get imageEditorApplySuccess;

  /// No description provided for @imageEditorProcessing.
  ///
  /// In zh_Hans, this message translates to:
  /// **'处理中…'**
  String get imageEditorProcessing;

  /// No description provided for @builtinToolTimeoutLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'超时时间（秒）'**
  String get builtinToolTimeoutLabel;

  /// No description provided for @builtinToolTimeoutHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {seconds}s'**
  String builtinToolTimeoutHint(int seconds);

  /// No description provided for @builtinToolTimeoutHelper.
  ///
  /// In zh_Hans, this message translates to:
  /// **'留空则使用默认 {seconds}s'**
  String builtinToolTimeoutHelper(int seconds);

  /// No description provided for @builtinToolRetryLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'失败/超时自动重试'**
  String get builtinToolRetryLabel;

  /// No description provided for @builtinToolRetryBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认关闭。仅对真正失败 (failed/timed_out) 触发，不会重试参数错误或被拒绝的调用。'**
  String get builtinToolRetryBody;

  /// No description provided for @builtinToolMaxRetriesLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'最大重试次数 (0–{max})'**
  String builtinToolMaxRetriesLabel(int max);

  /// No description provided for @builtinToolMaxRetriesHelper.
  ///
  /// In zh_Hans, this message translates to:
  /// **'不含首次执行；上限 {max} 次'**
  String builtinToolMaxRetriesHelper(int max);

  /// No description provided for @builtinToolBackoffLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重试退避基线（毫秒）'**
  String get builtinToolBackoffLabel;

  /// No description provided for @builtinToolBackoffHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {ms}ms'**
  String builtinToolBackoffHint(int ms);

  /// No description provided for @builtinToolBackoffHelper.
  ///
  /// In zh_Hans, this message translates to:
  /// **'指数退避：第 N 次重试等待 base × 2^(N-1)ms，上限 {max}ms'**
  String builtinToolBackoffHelper(int max);

  /// No description provided for @selfLearningFlushIntervalLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'流式刷新间隔：{ms}ms'**
  String selfLearningFlushIntervalLabel(int ms);

  /// No description provided for @selfLearningFlushIntervalHelper.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自我学习卡片流式输出的持久化间隔（{min}–{max}ms）。调小=更实时但更多布局抖动；调大=更平滑但增量延迟更高。默认 600ms。'**
  String selfLearningFlushIntervalHelper(int min, int max);

  /// No description provided for @tsmRenameThreadTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重命名线程'**
  String get tsmRenameThreadTitle;

  /// No description provided for @tsmRenameHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输入线程标题'**
  String get tsmRenameHint;

  /// No description provided for @tsmRenameFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重命名失败'**
  String get tsmRenameFailed;

  /// No description provided for @tsmDeleteThreadTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除线程'**
  String get tsmDeleteThreadTitle;

  /// No description provided for @tsmDeleteSelectedTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除所选线程'**
  String get tsmDeleteSelectedTitle;

  /// No description provided for @tsmDeleteSelectedConfirm.
  ///
  /// In zh_Hans, this message translates to:
  /// **'将永久删除 {count} 个线程及其消息。此操作无法撤销。'**
  String tsmDeleteSelectedConfirm(Object count);

  /// No description provided for @tsmDeleteFailedCount.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{count} 个线程删除失败'**
  String tsmDeleteFailedCount(Object count);

  /// No description provided for @tsmSessionMissing.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话不存在或已被删除'**
  String get tsmSessionMissing;

  /// No description provided for @tsmExportSessionDataTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'导出会话数据'**
  String get tsmExportSessionDataTitle;

  /// No description provided for @tsmExportingSession.
  ///
  /// In zh_Hans, this message translates to:
  /// **'正在导出 “{title}”…'**
  String tsmExportingSession(Object title);

  /// No description provided for @tsmExportComplete.
  ///
  /// In zh_Hans, this message translates to:
  /// **'导出完成'**
  String get tsmExportComplete;

  /// No description provided for @tsmExportFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'导出失败'**
  String get tsmExportFailed;

  /// No description provided for @tsmChooseExportFolder.
  ///
  /// In zh_Hans, this message translates to:
  /// **'选择导出目录'**
  String get tsmChooseExportFolder;

  /// No description provided for @tsmBatchExportTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'批量导出'**
  String get tsmBatchExportTitle;

  /// No description provided for @tsmBatchExportSubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'即将导出 {count} 个线程…'**
  String tsmBatchExportSubtitle(Object count);

  /// No description provided for @tsmBatchExportDone.
  ///
  /// In zh_Hans, this message translates to:
  /// **'批量导出完成：成功 {ok} / 失败 {failed}'**
  String tsmBatchExportDone(Object ok, Object failed);

  /// No description provided for @tsmMenuPreview.
  ///
  /// In zh_Hans, this message translates to:
  /// **'预览'**
  String get tsmMenuPreview;

  /// No description provided for @tsmMenuRename.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重命名'**
  String get tsmMenuRename;

  /// No description provided for @tsmMenuExportSession.
  ///
  /// In zh_Hans, this message translates to:
  /// **'导出会话数据'**
  String get tsmMenuExportSession;

  /// No description provided for @tsmMenuPin.
  ///
  /// In zh_Hans, this message translates to:
  /// **'置顶'**
  String get tsmMenuPin;

  /// No description provided for @tsmMenuUnpin.
  ///
  /// In zh_Hans, this message translates to:
  /// **'取消置顶'**
  String get tsmMenuUnpin;

  /// No description provided for @tsmMenuArchive.
  ///
  /// In zh_Hans, this message translates to:
  /// **'归档'**
  String get tsmMenuArchive;

  /// No description provided for @tsmMenuUnarchive.
  ///
  /// In zh_Hans, this message translates to:
  /// **'取消归档'**
  String get tsmMenuUnarchive;

  /// No description provided for @tsmMenuDelete.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除'**
  String get tsmMenuDelete;

  /// No description provided for @tsmPinUpdateFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'置顶状态更新失败'**
  String get tsmPinUpdateFailed;

  /// No description provided for @tsmArchiveUpdateFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'归档状态更新失败'**
  String get tsmArchiveUpdateFailed;

  /// No description provided for @tsmUntitledThread.
  ///
  /// In zh_Hans, this message translates to:
  /// **'(未命名线程)'**
  String get tsmUntitledThread;

  /// No description provided for @tsmPreviewMessageCount.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{count} 条消息'**
  String tsmPreviewMessageCount(Object count);

  /// No description provided for @tsmClosePreview.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭预览'**
  String get tsmClosePreview;

  /// No description provided for @tsmNoMessages.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暂无消息'**
  String get tsmNoMessages;

  /// No description provided for @tsmEmptyMessage.
  ///
  /// In zh_Hans, this message translates to:
  /// **'(空消息)'**
  String get tsmEmptyMessage;

  /// No description provided for @tsmSearchHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'按标题或 ID 搜索'**
  String get tsmSearchHint;

  /// No description provided for @tsmDensityComfortable.
  ///
  /// In zh_Hans, this message translates to:
  /// **'舒适密度'**
  String get tsmDensityComfortable;

  /// No description provided for @tsmDensityCompact.
  ///
  /// In zh_Hans, this message translates to:
  /// **'紧凑密度'**
  String get tsmDensityCompact;

  /// No description provided for @tsmAllTemplates.
  ///
  /// In zh_Hans, this message translates to:
  /// **'全部模板'**
  String get tsmAllTemplates;

  /// No description provided for @tsmSortDisabledHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前为「{mode}」排序，拖拽手柄已禁用，切回「手动顺序」可继续调整。'**
  String tsmSortDisabledHint(Object mode);

  /// No description provided for @tsmSortManual.
  ///
  /// In zh_Hans, this message translates to:
  /// **'手动顺序'**
  String get tsmSortManual;

  /// No description provided for @tsmSortUpdated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'最近更新'**
  String get tsmSortUpdated;

  /// No description provided for @tsmSortCreated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'最近创建'**
  String get tsmSortCreated;

  /// No description provided for @tsmSortSize.
  ///
  /// In zh_Hans, this message translates to:
  /// **'占用大小'**
  String get tsmSortSize;

  /// No description provided for @tsmSortMessages.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息数量'**
  String get tsmSortMessages;

  /// No description provided for @tsmSortToken.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Token 数'**
  String get tsmSortToken;

  /// No description provided for @tsmHideArchived.
  ///
  /// In zh_Hans, this message translates to:
  /// **'隐藏归档'**
  String get tsmHideArchived;

  /// No description provided for @tsmShowArchived.
  ///
  /// In zh_Hans, this message translates to:
  /// **'显示归档'**
  String get tsmShowArchived;

  /// No description provided for @tsmExitSelection.
  ///
  /// In zh_Hans, this message translates to:
  /// **'退出多选'**
  String get tsmExitSelection;

  /// No description provided for @tsmEnterSelection.
  ///
  /// In zh_Hans, this message translates to:
  /// **'多选'**
  String get tsmEnterSelection;

  /// No description provided for @tsmClose.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭'**
  String get tsmClose;

  /// No description provided for @tsmTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'线程会话管理'**
  String get tsmTitle;

  /// No description provided for @tsmHeaderSubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'共 {count} 个线程 · 长按或拖拽手柄可调整顺序，双击/右键查看更多操作'**
  String tsmHeaderSubtitle(Object count);

  /// No description provided for @tsmSelectedCount.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已选 {count}'**
  String tsmSelectedCount(Object count);

  /// No description provided for @tsmBatchExportButton.
  ///
  /// In zh_Hans, this message translates to:
  /// **'批量导出'**
  String get tsmBatchExportButton;

  /// No description provided for @tsmDeleteSelectedButton.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除所选'**
  String get tsmDeleteSelectedButton;

  /// No description provided for @tsmEmptyState.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暂无线程会话'**
  String get tsmEmptyState;

  /// No description provided for @tsmCancel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'取消'**
  String get tsmCancel;

  /// No description provided for @settingsThreadSessionManagementTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'线程会话管理'**
  String get settingsThreadSessionManagementTitle;

  /// No description provided for @settingsThreadSessionManagementSubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'查看所有线程的标题、创建/更新时间、占用大小、消息构成和 token 统计。支持拖拽排序、多选删除、双击或右键打开重命名/导出/删除菜单。弹窗的进出场动画跟随全局设置中的弹窗动画配置。'**
  String get settingsThreadSessionManagementSubtitle;

  /// No description provided for @settingsThreadSessionManagementOpen.
  ///
  /// In zh_Hans, this message translates to:
  /// **'打开管理弹窗'**
  String get settingsThreadSessionManagementOpen;

  /// No description provided for @settingsMessageGatewayTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息网关'**
  String get settingsMessageGatewayTitle;

  /// No description provided for @settingsMessageGatewayDescription.
  ///
  /// In zh_Hans, this message translates to:
  /// **'管理消息网关的路由、转换与节流策略。具体配置项将在后续版本中开放，当前为预留入口。'**
  String get settingsMessageGatewayDescription;

  /// No description provided for @settingsMessageGatewayComingSoon.
  ///
  /// In zh_Hans, this message translates to:
  /// **'即将推出'**
  String get settingsMessageGatewayComingSoon;

  /// No description provided for @settingsMessageGatewayComingSoonSubtitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息网关详细配置将在下一个迭代中提供。'**
  String get settingsMessageGatewayComingSoonSubtitle;

  /// No description provided for @tsmRowUnknown.
  ///
  /// In zh_Hans, this message translates to:
  /// **'未知'**
  String get tsmRowUnknown;

  /// No description provided for @tsmRowCreated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'创建'**
  String get tsmRowCreated;

  /// No description provided for @tsmRowUpdated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'更新'**
  String get tsmRowUpdated;

  /// No description provided for @tsmRowSize.
  ///
  /// In zh_Hans, this message translates to:
  /// **'占用'**
  String get tsmRowSize;

  /// No description provided for @tsmRowMessages.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息'**
  String get tsmRowMessages;

  /// No description provided for @tsmRowToken.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Token'**
  String get tsmRowToken;

  /// No description provided for @tsmRowByKind.
  ///
  /// In zh_Hans, this message translates to:
  /// **'占比'**
  String get tsmRowByKind;

  /// No description provided for @proxySectionTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'系统'**
  String get proxySectionTitle;

  /// No description provided for @proxySectionBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'所有 OpenHand 内建 HTTP 客户端（WebSearch / WebFetch 等）将按此处代理设置选择路由。保存后即时生效，无需重启。'**
  String get proxySectionBody;

  /// No description provided for @proxyModeLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'代理模式'**
  String get proxyModeLabel;

  /// No description provided for @proxyModeBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'决定 OpenHand 内置 HTTP 客户端（WebSearch / WebFetch 等）如何选择代理。'**
  String get proxyModeBody;

  /// No description provided for @proxyModeDisabled.
  ///
  /// In zh_Hans, this message translates to:
  /// **'无代理'**
  String get proxyModeDisabled;

  /// No description provided for @proxyModeAutomatic.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动发现代理（默认）'**
  String get proxyModeAutomatic;

  /// No description provided for @proxyModeManual.
  ///
  /// In zh_Hans, this message translates to:
  /// **'手动配置代理'**
  String get proxyModeManual;

  /// No description provided for @proxyProtocolsLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'代理协议'**
  String get proxyProtocolsLabel;

  /// No description provided for @proxyProtocolsBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'可多选，至少保留一个；取消所有协议时会自动恢复 HTTP + HTTPS。'**
  String get proxyProtocolsBody;

  /// No description provided for @proxyHostLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'服务器（IP 或主机名）'**
  String get proxyHostLabel;

  /// No description provided for @proxyPortLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'端口号'**
  String get proxyPortLabel;

  /// No description provided for @proxyAuthLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'开启代理服务器鉴权'**
  String get proxyAuthLabel;

  /// No description provided for @proxyAuthBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'开启后下面的用户名 / 密码字段才会被使用（HTTP Basic）。'**
  String get proxyAuthBody;

  /// No description provided for @proxyUsernameLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户名'**
  String get proxyUsernameLabel;

  /// No description provided for @proxyPasswordLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'密码'**
  String get proxyPasswordLabel;

  /// No description provided for @proxyExceptionsLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'忽略这些主机与域的代理设置'**
  String get proxyExceptionsLabel;

  /// No description provided for @proxyExceptionsBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'每行一条。支持：IP 地址（127.0.0.1）、IPv4 CIDR（192.168.0.0/16）、域名（example.com 含子域）、glob（*.example.com）、正则（/^api\\d+\\.example\\.com\$/i）。localhost / 127.0.0.1 / ::1 始终走直连。'**
  String get proxyExceptionsBody;

  /// No description provided for @proxyExceptionsHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'示例：\n*.local\n10.0.0.0/8\n/^api\\d+\\.example\\.com\$/i'**
  String get proxyExceptionsHint;

  /// No description provided for @proxyTestButton.
  ///
  /// In zh_Hans, this message translates to:
  /// **'测试代理连通性'**
  String get proxyTestButton;

  /// No description provided for @proxyTesting.
  ///
  /// In zh_Hans, this message translates to:
  /// **'测试中…'**
  String get proxyTesting;

  /// No description provided for @proxyTestSuccess.
  ///
  /// In zh_Hans, this message translates to:
  /// **'连通成功（{latency} ms，via {via}）'**
  String proxyTestSuccess(Object latency, Object via);

  /// No description provided for @proxyTestFailure.
  ///
  /// In zh_Hans, this message translates to:
  /// **'连通失败：{reason}'**
  String proxyTestFailure(Object reason);

  /// No description provided for @proxyTestEndpointLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'测试 URL'**
  String get proxyTestEndpointLabel;

  /// No description provided for @proxyTestEndpointHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认：https://www.google.com/generate_204'**
  String get proxyTestEndpointHint;

  /// No description provided for @proxyTestVerdictDirect.
  ///
  /// In zh_Hans, this message translates to:
  /// **'直连'**
  String get proxyTestVerdictDirect;

  /// No description provided for @proxyTestVerdictProxy.
  ///
  /// In zh_Hans, this message translates to:
  /// **'代理 {endpoint}'**
  String proxyTestVerdictProxy(Object endpoint);

  /// No description provided for @proxyTestEndpointInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'测试 URL 无效（需以 http:// 或 https:// 开头）'**
  String get proxyTestEndpointInvalid;

  /// No description provided for @proxyTestConsoleTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'代理连通性诊断'**
  String get proxyTestConsoleTitle;

  /// No description provided for @proxyTestConsoleRunning.
  ///
  /// In zh_Hans, this message translates to:
  /// **'正在执行链路探测…'**
  String get proxyTestConsoleRunning;

  /// No description provided for @proxyTestConsoleSucceeded.
  ///
  /// In zh_Hans, this message translates to:
  /// **'诊断完成：链路畅通'**
  String get proxyTestConsoleSucceeded;

  /// No description provided for @proxyTestConsoleFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'诊断完成：发现问题'**
  String get proxyTestConsoleFailed;

  /// No description provided for @proxyTestConsoleCopy.
  ///
  /// In zh_Hans, this message translates to:
  /// **'复制日志'**
  String get proxyTestConsoleCopy;

  /// No description provided for @proxyTestConsoleCopied.
  ///
  /// In zh_Hans, this message translates to:
  /// **'日志已复制到剪贴板'**
  String get proxyTestConsoleCopied;

  /// No description provided for @proxyTestConsoleClose.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭'**
  String get proxyTestConsoleClose;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'fr', 'ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppLocalizationsZhHans();
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
