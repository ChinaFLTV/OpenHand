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

  /// Application brand name. Keep as "OpenHand" untranslated.
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

  /// Model Context Protocol acronym. Keep as "MCP" untranslated.
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

  /// Default conversation thread title; same as the application brand "OpenHand".
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

  /// No description provided for @mcpLazyLoadingModeLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 工具懒加载'**
  String get mcpLazyLoadingModeLabel;

  /// No description provided for @mcpLazyLoadingModeBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'控制是否在系统提示中折叠 MCP 工具描述：关闭时全部展开；开启时全部折叠为 ToolSearch 可按需取回；自动模式下当总 token 估算超过阈值才折叠。'**
  String get mcpLazyLoadingModeBody;

  /// No description provided for @mcpLazyLoadingModeDisabled.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭'**
  String get mcpLazyLoadingModeDisabled;

  /// No description provided for @mcpLazyLoadingModeAuto.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动'**
  String get mcpLazyLoadingModeAuto;

  /// No description provided for @mcpLazyLoadingModeEnabled.
  ///
  /// In zh_Hans, this message translates to:
  /// **'开启'**
  String get mcpLazyLoadingModeEnabled;

  /// No description provided for @mcpLazyLoadingThresholdLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 工具压缩阈值'**
  String get mcpLazyLoadingThresholdLabel;

  /// No description provided for @mcpLazyLoadingThresholdBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动模式下 MCP 工具描述总 token 估算超过该值时启用懒加载。'**
  String get mcpLazyLoadingThresholdBody;

  /// No description provided for @mcpLazyLoadingThresholdSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存阈值'**
  String get mcpLazyLoadingThresholdSave;

  /// No description provided for @mcpLazyLoadingThresholdSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 工具懒加载阈值已保存。'**
  String get mcpLazyLoadingThresholdSaved;

  /// No description provided for @mcpLazyLoadingThresholdInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请填写 1000 ~ 1000000 之间的整数。'**
  String get mcpLazyLoadingThresholdInvalid;

  /// No description provided for @mcpLazyLoadingHowItWorks.
  ///
  /// In zh_Hans, this message translates to:
  /// **'懒加载启用时：MCP 工具描述被折叠为名称索引，模型通过内置 ToolSearch 工具按需取回完整 JSON Schema。支持三种查询：\n• select:NAME（直接选取，可空格分隔多个）\n• 关键字（按 name/description 评分匹配）\n• +KEYWORD（必含词，用于过滤噪声）\n命中工具会写入当前会话已加载列表，下一轮即可直接调用，无需再次查询。'**
  String get mcpLazyLoadingHowItWorks;

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
  String aiModelTestSuccess(String modelName);

  /// No description provided for @aiModelTestFailure.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{modelName} 测试失败：{reason}'**
  String aiModelTestFailure(String modelName, String reason);

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
  String aiModelScanSuccess(int count);

  /// No description provided for @aiModelScanFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'扫描失败：{reason}'**
  String aiModelScanFailed(String reason);

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
  String aiModelCount(int count);

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

  /// AI provider brand: OpenAI. Brand name; transliterate only when natural (e.g. ja: オープンAI).
  ///
  /// In zh_Hans, this message translates to:
  /// **'OpenAI'**
  String get aiProtocolOpenAi;

  /// AI provider brand: Anthropic Claude. Brand name; transliterate only when natural (e.g. ja: クロード).
  ///
  /// In zh_Hans, this message translates to:
  /// **'Claude'**
  String get aiProtocolClaude;

  /// AI provider brand: Google Gemini. Brand name; transliterate only when natural (e.g. ja: ジェミニ).
  ///
  /// In zh_Hans, this message translates to:
  /// **'Gemini'**
  String get aiProtocolGemini;

  /// AI provider brand: DeepSeek. Brand name; transliterate only when natural (e.g. ja: ディープシーク).
  ///
  /// In zh_Hans, this message translates to:
  /// **'DeepSeek'**
  String get aiProtocolDeepSeek;

  /// AI provider brand: Moonshot Kimi. Brand name; transliterate only when natural (e.g. ja: キミ).
  ///
  /// In zh_Hans, this message translates to:
  /// **'Kimi'**
  String get aiProtocolKimi;

  /// AI provider brand: Zhipu GLM. Acronym; keep as "GLM" untranslated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'GLM'**
  String get aiProtocolGlm;

  /// AI provider brand: xAI Grok. Brand name; transliterate only when natural (e.g. ja: グロック).
  ///
  /// In zh_Hans, this message translates to:
  /// **'Grok'**
  String get aiProtocolGrok;

  /// Local-runtime brand: Ollama. Brand name; transliterate only when natural (e.g. ja: オラマ).
  ///
  /// In zh_Hans, this message translates to:
  /// **'Ollama'**
  String get aiProtocolOllama;

  /// Local-runtime brand: vLLM. Acronym; keep as "vLLM" untranslated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'vLLM'**
  String get aiProtocolVllm;

  /// Local-runtime brand: SGLang. Keep as "SGLang" untranslated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'SGLang'**
  String get aiProtocolSglang;

  /// AI provider brand: Alibaba Qwen / 通义千问. Brand name; transliterate when natural (ja: クウェン).
  ///
  /// In zh_Hans, this message translates to:
  /// **'通义千问'**
  String get aiProtocolQwen;

  /// AI provider brand: ByteDance Seed / Doubao 豆包. Brand name; preserve "(Doubao)" parenthetical.
  ///
  /// In zh_Hans, this message translates to:
  /// **'豆包 (火山方舟)'**
  String get aiProtocolSeed;

  /// AI provider brand: StepFun 阶跃星辰. Brand name; transliterate when natural (ja: ステップファン).
  ///
  /// In zh_Hans, this message translates to:
  /// **'阶跃星辰'**
  String get aiProtocolStepFun;

  /// AI provider brand: MiniMax. Brand name; transliterate when natural (ja: ミニマックス).
  ///
  /// In zh_Hans, this message translates to:
  /// **'MiniMax'**
  String get aiProtocolMinimax;

  /// AI provider brand: Meituan LongCat. Brand name; transliterate when natural (ja: ロングキャット).
  ///
  /// In zh_Hans, this message translates to:
  /// **'LongCat'**
  String get aiProtocolLongCat;

  /// AI provider brand: JD JoyCode. Brand name; transliterate when natural (ja: ジョイコード).
  ///
  /// In zh_Hans, this message translates to:
  /// **'JoyCode'**
  String get aiProtocolJoyCode;

  /// AI provider brand: Baidu Wenxin / ERNIE 文心一言. Preserve "/ ERNIE" pairing.
  ///
  /// In zh_Hans, this message translates to:
  /// **'文心一言 (ERNIE)'**
  String get aiProtocolWenxin;

  /// AI provider brand: Meta AI / Llama family. Preserve "Meta AI / " prefix.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Meta AI (Llama)'**
  String get aiProtocolMeta;

  /// AI provider brand: Xiaomi MIMO. Acronym; keep as "MIMO" untranslated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MIMO (小米)'**
  String get aiProtocolMimo;

  /// AI provider brand: Tencent Hunyuan 混元. Brand name; Chinese form preferred for ja/zh.
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

  /// MCP settings page title. Acronym; keep as "MCP" untranslated.
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

  /// MCP transport mode label. Technical term; keep "HTTP" portion untranslated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Streamable HTTP'**
  String get mcpTransportStreamableHttp;

  /// MCP Server-Sent Events transport. Acronym; keep as "SSE" untranslated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'SSE'**
  String get mcpTransportSse;

  /// MCP standard I/O transport. Acronym; keep as "STDIO" untranslated.
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
  String tsmDeleteSelectedConfirm(int count);

  /// No description provided for @tsmDeleteFailedCount.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{count} 个线程删除失败'**
  String tsmDeleteFailedCount(int count);

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
  String tsmExportingSession(String title);

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
  String tsmBatchExportSubtitle(int count);

  /// No description provided for @tsmBatchExportDone.
  ///
  /// In zh_Hans, this message translates to:
  /// **'批量导出完成：成功 {ok} / 失败 {failed}'**
  String tsmBatchExportDone(int ok, int failed);

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
  String tsmPreviewMessageCount(int count);

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
  String tsmSortDisabledHint(String mode);

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
  String tsmHeaderSubtitle(int count);

  /// No description provided for @tsmSelectedCount.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已选 {count}'**
  String tsmSelectedCount(int count);

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
  String proxyTestSuccess(int latency, String via);

  /// No description provided for @proxyTestFailure.
  ///
  /// In zh_Hans, this message translates to:
  /// **'连通失败：{reason}'**
  String proxyTestFailure(String reason);

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
  String proxyTestVerdictProxy(String endpoint);

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

  /// No description provided for @proxyTestConsoleRerun.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重新运行'**
  String get proxyTestConsoleRerun;

  /// No description provided for @proxyTestConsoleMaximize.
  ///
  /// In zh_Hans, this message translates to:
  /// **'最大化'**
  String get proxyTestConsoleMaximize;

  /// No description provided for @proxyTestConsoleRestore.
  ///
  /// In zh_Hans, this message translates to:
  /// **'还原'**
  String get proxyTestConsoleRestore;

  /// No description provided for @proxyTestConsoleClear.
  ///
  /// In zh_Hans, this message translates to:
  /// **'清空终端'**
  String get proxyTestConsoleClear;

  /// No description provided for @tokenPopupCostHeading.
  ///
  /// In zh_Hans, this message translates to:
  /// **'成本估算'**
  String get tokenPopupCostHeading;

  /// No description provided for @tokenPopupCostInput.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输入'**
  String get tokenPopupCostInput;

  /// No description provided for @tokenPopupCostOutput.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输出'**
  String get tokenPopupCostOutput;

  /// No description provided for @tokenPopupCostCacheRead.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Cache 命中'**
  String get tokenPopupCostCacheRead;

  /// No description provided for @tokenPopupCostCacheWrite.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Cache 写入'**
  String get tokenPopupCostCacheWrite;

  /// No description provided for @tokenPopupCostTotal.
  ///
  /// In zh_Hans, this message translates to:
  /// **'总计'**
  String get tokenPopupCostTotal;

  /// No description provided for @tokenDialUnit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Token'**
  String get tokenDialUnit;

  /// No description provided for @tokenDialTotal.
  ///
  /// In zh_Hans, this message translates to:
  /// **'总计'**
  String get tokenDialTotal;

  /// No description provided for @tokenPopupInputHeading.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输入'**
  String get tokenPopupInputHeading;

  /// No description provided for @tokenPopupPrompt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Prompt'**
  String get tokenPopupPrompt;

  /// No description provided for @tokenPopupCacheRead.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Cache 命中'**
  String get tokenPopupCacheRead;

  /// No description provided for @tokenPopupCacheWrite.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Cache 写入'**
  String get tokenPopupCacheWrite;

  /// No description provided for @tokenPopupOutputHeading.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输出'**
  String get tokenPopupOutputHeading;

  /// No description provided for @tokenPopupCompletion.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Completion'**
  String get tokenPopupCompletion;

  /// No description provided for @tokenPopupGrandTotal.
  ///
  /// In zh_Hans, this message translates to:
  /// **'总计'**
  String get tokenPopupGrandTotal;

  /// No description provided for @tokenPopupCacheHit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Cache 命中率'**
  String get tokenPopupCacheHit;

  /// No description provided for @tokenPopupSessionHeading.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话累计'**
  String get tokenPopupSessionHeading;

  /// No description provided for @tokenPopupMessages.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息总数'**
  String get tokenPopupMessages;

  /// No description provided for @tokenPopupPromptBuilds.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Prompt 构建'**
  String get tokenPopupPromptBuilds;

  /// No description provided for @tokenPopupPromptChars.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Prompt 字符'**
  String get tokenPopupPromptChars;

  /// No description provided for @toolbarSessionMetadata.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话元数据'**
  String get toolbarSessionMetadata;

  /// No description provided for @toolbarProviderModelLocked.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已锁定服务商与模型以保证缓存命中'**
  String get toolbarProviderModelLocked;

  /// No description provided for @toolbarModelLocked.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模型已锁定'**
  String get toolbarModelLocked;

  /// No description provided for @toolbarSessionAudit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话审计'**
  String get toolbarSessionAudit;

  /// No description provided for @toolbarShowPlan.
  ///
  /// In zh_Hans, this message translates to:
  /// **'展开计划'**
  String get toolbarShowPlan;

  /// No description provided for @toolbarHidePlan.
  ///
  /// In zh_Hans, this message translates to:
  /// **'收起计划'**
  String get toolbarHidePlan;

  /// No description provided for @toolbarPlanAwaitingApproval.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划待确认'**
  String get toolbarPlanAwaitingApproval;

  /// No description provided for @toolbarPlanNeedsReview.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划待复核'**
  String get toolbarPlanNeedsReview;

  /// No description provided for @toolbarPlanNeedsAttention.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划需要处理'**
  String get toolbarPlanNeedsAttention;

  /// No description provided for @toolbarPlanCompleted.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划已完成'**
  String get toolbarPlanCompleted;

  /// No description provided for @toolbarPlanInProgress.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划推进中'**
  String get toolbarPlanInProgress;

  /// No description provided for @toolbarPlanConfirmToBegin.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请确认后开始执行'**
  String get toolbarPlanConfirmToBegin;

  /// No description provided for @toolbarPlanInspectBeforeResume.
  ///
  /// In zh_Hans, this message translates to:
  /// **'继续前先检查已完成步骤、产物和 Todo'**
  String get toolbarPlanInspectBeforeResume;

  /// No description provided for @toolbarPlanStepFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前步骤执行失败，请检查后继续'**
  String get toolbarPlanStepFailed;

  /// No description provided for @toolbarPlanPending.
  ///
  /// In zh_Hans, this message translates to:
  /// **'等待确认'**
  String get toolbarPlanPending;

  /// No description provided for @toolbarPlanReview.
  ///
  /// In zh_Hans, this message translates to:
  /// **'待复核'**
  String get toolbarPlanReview;

  /// No description provided for @toolbarToolsProtocolUnsupported.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前模型协议不支持工具调用'**
  String get toolbarToolsProtocolUnsupported;

  /// No description provided for @toolbarRuntimeNoSnapshot.
  ///
  /// In zh_Hans, this message translates to:
  /// **'尚未生成运行时工具快照'**
  String get toolbarRuntimeNoSnapshot;

  /// No description provided for @toolbarToolsCatalogStale.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具目录已过期，等待下一轮刷新'**
  String get toolbarToolsCatalogStale;

  /// No description provided for @toolbarRuntimeCatalogSynced.
  ///
  /// In zh_Hans, this message translates to:
  /// **'运行时工具目录已同步'**
  String get toolbarRuntimeCatalogSynced;

  /// No description provided for @toolbarPlanAwaitingNoExecTools.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划待确认，当前轮不开放执行工具'**
  String get toolbarPlanAwaitingNoExecTools;

  /// No description provided for @toolbarPlanReviewBeforeResume.
  ///
  /// In zh_Hans, this message translates to:
  /// **'需要先复核已有步骤、产物和 Todo'**
  String get toolbarPlanReviewBeforeResume;

  /// No description provided for @toolbarPlanApprovedExecOpen.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划已获准执行，当前轮开放执行工具'**
  String get toolbarPlanApprovedExecOpen;

  /// No description provided for @toolbarPlanOnlyPlanningExitAllowed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前仅开放规划工具，可在准备好后提交执行计划'**
  String get toolbarPlanOnlyPlanningExitAllowed;

  /// No description provided for @toolbarPlanOnlyPlanningOnly.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前仅开放规划工具'**
  String get toolbarPlanOnlyPlanningOnly;

  /// No description provided for @toolbarModeJustSwitched.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模式刚切换，等待下一轮重新计算工具目录'**
  String get toolbarModeJustSwitched;

  /// No description provided for @toolbarChatModeNoTools.
  ///
  /// In zh_Hans, this message translates to:
  /// **'聊天模式当前没有可用工具'**
  String get toolbarChatModeNoTools;

  /// No description provided for @toolbarChatModeAllTools.
  ///
  /// In zh_Hans, this message translates to:
  /// **'聊天模式当前开放完整运行时工具目录'**
  String get toolbarChatModeAllTools;

  /// No description provided for @toolbarRuntimeNoSnapshotPrompt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前还没有运行时快照，请先发起一轮请求'**
  String get toolbarRuntimeNoSnapshotPrompt;

  /// No description provided for @toolbarGateNoReason.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暂无门控说明'**
  String get toolbarGateNoReason;

  /// No description provided for @toolbarGateProtocolUnsupportedSwitchPlan.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前模型协议不支持工具调用。点击切换到计划模式。'**
  String get toolbarGateProtocolUnsupportedSwitchPlan;

  /// No description provided for @toolbarGateChatActiveSwitchPlan.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前为聊天模式，点击切换到计划模式'**
  String get toolbarGateChatActiveSwitchPlan;

  /// No description provided for @toolbarGatePlanActiveSwitchChat.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前为计划模式，点击切换到聊天模式'**
  String get toolbarGatePlanActiveSwitchChat;

  /// No description provided for @toolbarGateProtocolUnsupportedSwitchChat.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前模型协议不支持工具调用。计划模式仍可组织步骤，但不会开放工具执行。点击切换到聊天模式。'**
  String get toolbarGateProtocolUnsupportedSwitchChat;

  /// No description provided for @toolbarGatePlanJustSwitchedToChat.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划模式刚切换完成，运行时工具会在下一轮自动刷新。点击切换到聊天模式。'**
  String get toolbarGatePlanJustSwitchedToChat;

  /// No description provided for @toolbarGatePlanAwaitingSwitchChat.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划待确认。当前轮不会暴露执行工具，请先确认计划。点击切换到聊天模式。'**
  String get toolbarGatePlanAwaitingSwitchChat;

  /// No description provided for @toolbarGatePlanReviewSwitchChat.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划待复核。继续执行前应先检查已完成步骤、产物与 Todo。点击切换到聊天模 式。'**
  String get toolbarGatePlanReviewSwitchChat;

  /// No description provided for @toolbarGatePlanExecutingSwitchChat.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划执行中。当前轮会按运行时目录暴露执行工具。点击切换到聊天模式。'**
  String get toolbarGatePlanExecutingSwitchChat;

  /// No description provided for @toolbarGatePlanModeSwitchChat.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前为计划模式，会先规划，再在获得确认后执行。点击切换到聊天模式。'**
  String get toolbarGatePlanModeSwitchChat;

  /// No description provided for @toolbarFilesShow.
  ///
  /// In zh_Hans, this message translates to:
  /// **'项目文件'**
  String get toolbarFilesShow;

  /// No description provided for @toolbarFilesHide.
  ///
  /// In zh_Hans, this message translates to:
  /// **'收起项目'**
  String get toolbarFilesHide;

  /// No description provided for @toolbarRuntimeModeChat.
  ///
  /// In zh_Hans, this message translates to:
  /// **'聊天模式'**
  String get toolbarRuntimeModeChat;

  /// No description provided for @toolbarRuntimeModeChatCompact.
  ///
  /// In zh_Hans, this message translates to:
  /// **'聊天模式'**
  String get toolbarRuntimeModeChatCompact;

  /// No description provided for @toolbarRuntimeModePlan.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划模式'**
  String get toolbarRuntimeModePlan;

  /// No description provided for @toolbarRuntimeModePlanCompact.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划模式'**
  String get toolbarRuntimeModePlanCompact;

  /// No description provided for @toolbarRuntimeModePlanAwaiting.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划待确认'**
  String get toolbarRuntimeModePlanAwaiting;

  /// No description provided for @toolbarRuntimeModePlanAwaitingCompact.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划待确认'**
  String get toolbarRuntimeModePlanAwaitingCompact;

  /// No description provided for @toolbarRuntimeModePlanReview.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划待复核'**
  String get toolbarRuntimeModePlanReview;

  /// No description provided for @toolbarRuntimeModePlanReviewCompact.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划待复核'**
  String get toolbarRuntimeModePlanReviewCompact;

  /// No description provided for @toolbarRuntimeModePlanExecution.
  ///
  /// In zh_Hans, this message translates to:
  /// **'执行计划'**
  String get toolbarRuntimeModePlanExecution;

  /// No description provided for @toolbarRuntimeModePlanExecutionCompact.
  ///
  /// In zh_Hans, this message translates to:
  /// **'执行计划'**
  String get toolbarRuntimeModePlanExecutionCompact;

  /// No description provided for @toolbarRuntimeModePlanDrafting.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划规划中'**
  String get toolbarRuntimeModePlanDrafting;

  /// No description provided for @toolbarRuntimeModePlanDraftCompact.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划规划中'**
  String get toolbarRuntimeModePlanDraftCompact;

  /// No description provided for @toolbarRuntimeNotices.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{count} 项运行时 Notice'**
  String toolbarRuntimeNotices(int count);

  /// No description provided for @toolbarMcpLazyLoading.
  ///
  /// In zh_Hans, this message translates to:
  /// **'MCP 已载 {loaded}/{total}'**
  String toolbarMcpLazyLoading(int loaded, int total);

  /// No description provided for @snackToolSearchLoaded.
  ///
  /// In zh_Hans, this message translates to:
  /// **'ToolSearch 已加载 {loaded}/{total} 个 MCP 工具'**
  String snackToolSearchLoaded(int loaded, int total);

  /// No description provided for @snackToolSearchLoadedAction.
  ///
  /// In zh_Hans, this message translates to:
  /// **'查看列表'**
  String get snackToolSearchLoadedAction;

  /// No description provided for @snackToolSearchLoadedDialogTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'ToolSearch 已加载的 MCP 工具'**
  String get snackToolSearchLoadedDialogTitle;

  /// No description provided for @snackToolSearchLoadedDialogClose.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭'**
  String get snackToolSearchLoadedDialogClose;

  /// No description provided for @snackToolSearchLoadedCopyAction.
  ///
  /// In zh_Hans, this message translates to:
  /// **'复制 select:'**
  String get snackToolSearchLoadedCopyAction;

  /// No description provided for @snackToolSearchLoadedCopiedToast.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已复制'**
  String get snackToolSearchLoadedCopiedToast;

  /// No description provided for @snackToolSearchLoadedClearAction.
  ///
  /// In zh_Hans, this message translates to:
  /// **'清空已加载列表'**
  String get snackToolSearchLoadedClearAction;

  /// No description provided for @snackToolSearchLoadedClearedToast.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已清空已加载列表'**
  String get snackToolSearchLoadedClearedToast;

  /// No description provided for @snackToolSearchLoadedGroupOther.
  ///
  /// In zh_Hans, this message translates to:
  /// **'其他（未识别 server）'**
  String get snackToolSearchLoadedGroupOther;

  /// No description provided for @snackToolSearchLoadedCopyGroupAction.
  ///
  /// In zh_Hans, this message translates to:
  /// **'复制本组全部 select:'**
  String get snackToolSearchLoadedCopyGroupAction;

  /// No description provided for @snackToolSearchLoadedTabLoaded.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已加载'**
  String get snackToolSearchLoadedTabLoaded;

  /// No description provided for @snackToolSearchLoadedTabHistory.
  ///
  /// In zh_Hans, this message translates to:
  /// **'加载历史'**
  String get snackToolSearchLoadedTabHistory;

  /// No description provided for @snackToolSearchLoadedHistoryEmpty.
  ///
  /// In zh_Hans, this message translates to:
  /// **'本会话还没有 ToolSearch 加载记录'**
  String get snackToolSearchLoadedHistoryEmpty;

  /// No description provided for @snackToolSearchLoadedHistoryQueryPrefix.
  ///
  /// In zh_Hans, this message translates to:
  /// **'加载查询：'**
  String get snackToolSearchLoadedHistoryQueryPrefix;

  /// No description provided for @snackToolSearchLoadedFilterHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'按名字过滤…'**
  String get snackToolSearchLoadedFilterHint;

  /// No description provided for @snackToolSearchLoadedHistoryFilterHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'按名字或查询过滤…'**
  String get snackToolSearchLoadedHistoryFilterHint;

  /// No description provided for @snackToolSearchLoadedSourceAi.
  ///
  /// In zh_Hans, this message translates to:
  /// **'AI 会话'**
  String get snackToolSearchLoadedSourceAi;

  /// No description provided for @snackToolSearchLoadedSourceHardness.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Hardness 阶段'**
  String get snackToolSearchLoadedSourceHardness;

  /// No description provided for @snackToolSearchLoadedHistoryReplayAction.
  ///
  /// In zh_Hans, this message translates to:
  /// **'把本次复制为 select:…'**
  String get snackToolSearchLoadedHistoryReplayAction;

  /// No description provided for @snackToolSearchLoadedHistoryClearAction.
  ///
  /// In zh_Hans, this message translates to:
  /// **'清空历史'**
  String get snackToolSearchLoadedHistoryClearAction;

  /// No description provided for @snackToolSearchLoadedHistoryClearedToast.
  ///
  /// In zh_Hans, this message translates to:
  /// **'加载历史已清空'**
  String get snackToolSearchLoadedHistoryClearedToast;

  /// No description provided for @mcpLazyLoadingViewLoadedAction.
  ///
  /// In zh_Hans, this message translates to:
  /// **'查看本会话已加载列表'**
  String get mcpLazyLoadingViewLoadedAction;

  /// No description provided for @mcpLazyLoadingNoActiveSession.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前没有正在活动的会话'**
  String get mcpLazyLoadingNoActiveSession;

  /// No description provided for @toolbarPlanStepsCompleted.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已完成 {completed}/{total} 项'**
  String toolbarPlanStepsCompleted(int completed, int total);

  /// No description provided for @mdlEdEnterAValidBaseUrlFirst.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请先输入有效的 Base URL'**
  String get mdlEdEnterAValidBaseUrlFirst;

  /// No description provided for @mdlEdNoModelsFoundFromThisProvider.
  ///
  /// In zh_Hans, this message translates to:
  /// **'未从该提供商扫描到模型。'**
  String get mdlEdNoModelsFoundFromThisProvider;

  /// No description provided for @mdlEdProviderName.
  ///
  /// In zh_Hans, this message translates to:
  /// **'提供商名称'**
  String get mdlEdProviderName;

  /// No description provided for @mdlEdOptionalEGDeepseekLocalOllama.
  ///
  /// In zh_Hans, this message translates to:
  /// **'可选，如 DeepSeek、本地 Ollama'**
  String get mdlEdOptionalEGDeepseekLocalOllama;

  /// No description provided for @mdlEdCurrentlyActiveModel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前活跃模型'**
  String get mdlEdCurrentlyActiveModel;

  /// No description provided for @mdlEdClickToSetAsActiveModel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'点击切换为活跃模型'**
  String get mdlEdClickToSetAsActiveModel;

  /// No description provided for @mdlEdTapScanModelsToDiscoverModels.
  ///
  /// In zh_Hans, this message translates to:
  /// **'点击「扫描模型」按钮自动发现可用模型，或手动添加。'**
  String get mdlEdTapScanModelsToDiscoverModels;

  /// No description provided for @mdlEdActiveModelId.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前活跃模型 ID'**
  String get mdlEdActiveModelId;

  /// No description provided for @mdlEdTheModelUsedForConversationsSelect.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前用于对话的模型。可从上方列表选择或直接输入。'**
  String get mdlEdTheModelUsedForConversationsSelect;

  /// No description provided for @mdlEdMaxContextTokens.
  ///
  /// In zh_Hans, this message translates to:
  /// **'最大上下文 Token 上限'**
  String get mdlEdMaxContextTokens;

  /// No description provided for @mdlEdOptionalLimitsTheHistorySliceUsed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'可选。用于在压缩时限制历史切片大小。'**
  String get mdlEdOptionalLimitsTheHistorySliceUsed;

  /// No description provided for @mdlEdEnterAWholeNumberGreaterThan.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入大于 0 的整数'**
  String get mdlEdEnterAWholeNumberGreaterThan;

  /// No description provided for @mdlEdRequestMethod.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请求方式'**
  String get mdlEdRequestMethod;

  /// No description provided for @mdlEdOutputMode.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输出模式'**
  String get mdlEdOutputMode;

  /// No description provided for @mdlEdStreaming.
  ///
  /// In zh_Hans, this message translates to:
  /// **'流式输出'**
  String get mdlEdStreaming;

  /// No description provided for @mdlEdNonStreaming.
  ///
  /// In zh_Hans, this message translates to:
  /// **'非流式输出'**
  String get mdlEdNonStreaming;

  /// No description provided for @mdlEdMaxOutputTokens.
  ///
  /// In zh_Hans, this message translates to:
  /// **'最大输出 Token 数'**
  String get mdlEdMaxOutputTokens;

  /// No description provided for @mdlEdOptionalUsesAdapterDefaultIfUnset.
  ///
  /// In zh_Hans, this message translates to:
  /// **'可选。不指定则使用适配器默认值。'**
  String get mdlEdOptionalUsesAdapterDefaultIfUnset;

  /// No description provided for @mdlEdTemperature.
  ///
  /// In zh_Hans, this message translates to:
  /// **'温度'**
  String get mdlEdTemperature;

  /// No description provided for @mdlEd0020Default0.
  ///
  /// In zh_Hans, this message translates to:
  /// **'0.0 ~ 2.0，默认 0.7'**
  String get mdlEd0020Default0;

  /// No description provided for @mdlEdEnterANumberBetween00.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 0.0 到 2.0 之间的数值'**
  String get mdlEdEnterANumberBetween00;

  /// No description provided for @mdlEdCustomHeaders.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自定义请求头'**
  String get mdlEdCustomHeaders;

  /// No description provided for @mdlEdAdd.
  ///
  /// In zh_Hans, this message translates to:
  /// **'添加'**
  String get mdlEdAdd;

  /// No description provided for @mdlEdNoCustomHeadersTapAddTo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暂无自定义请求头。点击「添加」按钮来添加。'**
  String get mdlEdNoCustomHeadersTapAddTo;

  /// No description provided for @mdlEdHeaderName.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Header 名称'**
  String get mdlEdHeaderName;

  /// No description provided for @mdlEdHeaderValue.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Header 值'**
  String get mdlEdHeaderValue;

  /// No description provided for @mdlEdEditModelProfile.
  ///
  /// In zh_Hans, this message translates to:
  /// **'编辑模型配置'**
  String get mdlEdEditModelProfile;

  /// No description provided for @mdlEdDisplayName.
  ///
  /// In zh_Hans, this message translates to:
  /// **'显示名称'**
  String get mdlEdDisplayName;

  /// No description provided for @mdlEdOptionalShownInTheUi.
  ///
  /// In zh_Hans, this message translates to:
  /// **'可选，用于界面展示'**
  String get mdlEdOptionalShownInTheUi;

  /// No description provided for @mdlEdDescription.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模型描述'**
  String get mdlEdDescription;

  /// No description provided for @mdlEdMultimodalSupport.
  ///
  /// In zh_Hans, this message translates to:
  /// **'多模态支持'**
  String get mdlEdMultimodalSupport;

  /// No description provided for @mdlEdAutoDetect.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动检测'**
  String get mdlEdAutoDetect;

  /// No description provided for @mdlEdYes.
  ///
  /// In zh_Hans, this message translates to:
  /// **'是'**
  String get mdlEdYes;

  /// No description provided for @mdlEdNo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'否'**
  String get mdlEdNo;

  /// No description provided for @mdlEdSupportsAttachments.
  ///
  /// In zh_Hans, this message translates to:
  /// **'支持附件'**
  String get mdlEdSupportsAttachments;

  /// No description provided for @mdlEdSupportedModalities.
  ///
  /// In zh_Hans, this message translates to:
  /// **'支持的模态'**
  String get mdlEdSupportedModalities;

  /// No description provided for @mdlEdText.
  ///
  /// In zh_Hans, this message translates to:
  /// **'文本'**
  String get mdlEdText;

  /// No description provided for @mdlEdImage.
  ///
  /// In zh_Hans, this message translates to:
  /// **'图片生成'**
  String get mdlEdImage;

  /// No description provided for @mdlEdVideo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'视频生成'**
  String get mdlEdVideo;

  /// No description provided for @mdlEdAudio.
  ///
  /// In zh_Hans, this message translates to:
  /// **'音频生成'**
  String get mdlEdAudio;

  /// No description provided for @mdlEdGenerationCapabilities.
  ///
  /// In zh_Hans, this message translates to:
  /// **'生成能力'**
  String get mdlEdGenerationCapabilities;

  /// No description provided for @mdlEdPdf.
  ///
  /// In zh_Hans, this message translates to:
  /// **'PDF 生成'**
  String get mdlEdPdf;

  /// No description provided for @mdlEdPpt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'PPT 生成'**
  String get mdlEdPpt;

  /// No description provided for @mdlEdTokenLimits.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Token 限制'**
  String get mdlEdTokenLimits;

  /// No description provided for @mdlEdContextLength.
  ///
  /// In zh_Hans, this message translates to:
  /// **'上下文长度'**
  String get mdlEdContextLength;

  /// No description provided for @mdlEdSummaryLength.
  ///
  /// In zh_Hans, this message translates to:
  /// **'摘要长度'**
  String get mdlEdSummaryLength;

  /// No description provided for @mdlEdOutputLength.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输出长度'**
  String get mdlEdOutputLength;

  /// No description provided for @mdlEdThinkingLength.
  ///
  /// In zh_Hans, this message translates to:
  /// **'思考长度'**
  String get mdlEdThinkingLength;

  /// No description provided for @mdlEdTokenPricingUsd1mTokensLeave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Token 单价（USD / 1M tokens，留空表示未配置）'**
  String get mdlEdTokenPricingUsd1mTokensLeave;

  /// No description provided for @mdlEdInput.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输入价'**
  String get mdlEdInput;

  /// No description provided for @mdlEdOutput.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输出价'**
  String get mdlEdOutput;

  /// No description provided for @mdlEdCacheRead.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缓存读取价'**
  String get mdlEdCacheRead;

  /// No description provided for @mdlEdCacheWrite.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缓存写入价'**
  String get mdlEdCacheWrite;

  /// No description provided for @mdlEdReset.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重置'**
  String get mdlEdReset;

  /// No description provided for @mdlEdCancel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'取消'**
  String get mdlEdCancel;

  /// No description provided for @mdlEdOk.
  ///
  /// In zh_Hans, this message translates to:
  /// **'确定'**
  String get mdlEdOk;

  /// No description provided for @tlCallDir.
  ///
  /// In zh_Hans, this message translates to:
  /// **'目录'**
  String get tlCallDir;

  /// No description provided for @tlCallElapsed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'耗时'**
  String get tlCallElapsed;

  /// No description provided for @tlCallExit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'退出码'**
  String get tlCallExit;

  /// No description provided for @tlCallToolInput.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具入参'**
  String get tlCallToolInput;

  /// No description provided for @tlCallCommand.
  ///
  /// In zh_Hans, this message translates to:
  /// **'命令'**
  String get tlCallCommand;

  /// No description provided for @tlCallArguments.
  ///
  /// In zh_Hans, this message translates to:
  /// **'入参'**
  String get tlCallArguments;

  /// No description provided for @tlCallToolOutput.
  ///
  /// In zh_Hans, this message translates to:
  /// **'结果输出'**
  String get tlCallToolOutput;

  /// No description provided for @tlCallNoOutputYet.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暂无输出'**
  String get tlCallNoOutputYet;

  /// No description provided for @tlCallResult.
  ///
  /// In zh_Hans, this message translates to:
  /// **'结果'**
  String get tlCallResult;

  /// No description provided for @tlCallStdout.
  ///
  /// In zh_Hans, this message translates to:
  /// **'标准输出'**
  String get tlCallStdout;

  /// No description provided for @tlCallStderr.
  ///
  /// In zh_Hans, this message translates to:
  /// **'标准错误'**
  String get tlCallStderr;

  /// No description provided for @tlCallArgumentsConstructing.
  ///
  /// In zh_Hans, this message translates to:
  /// **'参数构造中…'**
  String get tlCallArgumentsConstructing;

  /// No description provided for @tlCallArgumentsConstructingHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'正在跟随模型输出实时拼装入参，参数构造完成后会自动切回正常状态。'**
  String get tlCallArgumentsConstructingHint;

  /// No description provided for @tlCallCollectedParameters.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已采集参数'**
  String get tlCallCollectedParameters;

  /// No description provided for @tlCallNoParametersYet.
  ///
  /// In zh_Hans, this message translates to:
  /// **'尚未解析到入参'**
  String get tlCallNoParametersYet;

  /// No description provided for @tlCallSubmitting.
  ///
  /// In zh_Hans, this message translates to:
  /// **'提交中…'**
  String get tlCallSubmitting;

  /// No description provided for @tlCallSubmittingHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已采集参数完毕，正在交给执行器'**
  String get tlCallSubmittingHint;

  /// No description provided for @tlCallThereIsNoToolOutputYet.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前还没有工具输出。'**
  String get tlCallThereIsNoToolOutputYet;

  /// No description provided for @tlCallViewInDialog.
  ///
  /// In zh_Hans, this message translates to:
  /// **'在弹窗里查看完整内容'**
  String get tlCallViewInDialog;

  /// No description provided for @tlCallEmptyContent.
  ///
  /// In zh_Hans, this message translates to:
  /// **'内容为空'**
  String get tlCallEmptyContent;

  /// No description provided for @tlCallWrite.
  ///
  /// In zh_Hans, this message translates to:
  /// **'写入'**
  String get tlCallWrite;

  /// No description provided for @tlCallEdit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'编辑'**
  String get tlCallEdit;

  /// No description provided for @tlCallMultiEdit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'多处编辑'**
  String get tlCallMultiEdit;

  /// No description provided for @tlCallNotebookEdit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Notebook 编辑'**
  String get tlCallNotebookEdit;

  /// No description provided for @tlCallBashWrite.
  ///
  /// In zh_Hans, this message translates to:
  /// **'命令写入'**
  String get tlCallBashWrite;

  /// No description provided for @tlCallFileChanged.
  ///
  /// In zh_Hans, this message translates to:
  /// **'文件变更'**
  String get tlCallFileChanged;

  /// No description provided for @tlCallChangedFile.
  ///
  /// In zh_Hans, this message translates to:
  /// **'文件变动'**
  String get tlCallChangedFile;

  /// No description provided for @tlCallTool.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具'**
  String get tlCallTool;

  /// No description provided for @tlCallSkill.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能'**
  String get tlCallSkill;

  /// No description provided for @tlCallStopped.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已停止'**
  String get tlCallStopped;

  /// No description provided for @tlCallBlocked.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已拦截'**
  String get tlCallBlocked;

  /// No description provided for @tlCallRejected.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户拒绝'**
  String get tlCallRejected;

  /// No description provided for @tlCallInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'参数无效'**
  String get tlCallInvalid;

  /// No description provided for @tlCallToolCall.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具调用'**
  String get tlCallToolCall;

  /// No description provided for @tlCallRunning.
  ///
  /// In zh_Hans, this message translates to:
  /// **'运行中'**
  String get tlCallRunning;

  /// No description provided for @tlCallSucceeded.
  ///
  /// In zh_Hans, this message translates to:
  /// **'执行成功'**
  String get tlCallSucceeded;

  /// No description provided for @tlCallDenied.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已被禁止'**
  String get tlCallDenied;

  /// No description provided for @tlCallTimedOut.
  ///
  /// In zh_Hans, this message translates to:
  /// **'执行超时'**
  String get tlCallTimedOut;

  /// No description provided for @tlCallFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'执行失败'**
  String get tlCallFailed;

  /// No description provided for @tlCallToolIsRunningWaitingForOutput.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具运行中，等待新的输出...'**
  String get tlCallToolIsRunningWaitingForOutput;

  /// No description provided for @tlCallExpandToInspectToolOutput.
  ///
  /// In zh_Hans, this message translates to:
  /// **'点击展开查看工具输出'**
  String get tlCallExpandToInspectToolOutput;

  /// No description provided for @tlCallType.
  ///
  /// In zh_Hans, this message translates to:
  /// **'类型'**
  String get tlCallType;

  /// No description provided for @tlCallSize.
  ///
  /// In zh_Hans, this message translates to:
  /// **'大小'**
  String get tlCallSize;

  /// No description provided for @tlCallModified.
  ///
  /// In zh_Hans, this message translates to:
  /// **'修改于'**
  String get tlCallModified;

  /// No description provided for @tlCallSelfLearning.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自我学习'**
  String get tlCallSelfLearning;

  /// No description provided for @tlCallNudgeRecovered.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已纠正\"光说不做\"'**
  String get tlCallNudgeRecovered;

  /// No description provided for @tlCallProfileChanges.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户画像变更'**
  String get tlCallProfileChanges;

  /// No description provided for @tlCallMemoryChanges.
  ///
  /// In zh_Hans, this message translates to:
  /// **'记忆变更'**
  String get tlCallMemoryChanges;

  /// No description provided for @tlCallSkillChanges.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能变更'**
  String get tlCallSkillChanges;

  /// No description provided for @tlCallProfileDiff.
  ///
  /// In zh_Hans, this message translates to:
  /// **'画像差异摘要'**
  String get tlCallProfileDiff;

  /// No description provided for @tlCallNoChanges.
  ///
  /// In zh_Hans, this message translates to:
  /// **'无变更'**
  String get tlCallNoChanges;

  /// No description provided for @tlCallUnnamed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'(未命名)'**
  String get tlCallUnnamed;

  /// No description provided for @tlCallJustNow.
  ///
  /// In zh_Hans, this message translates to:
  /// **'刚刚'**
  String get tlCallJustNow;

  /// No description provided for @sessMetaMessages.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息总数'**
  String get sessMetaMessages;

  /// No description provided for @sessMetaPromptBuilds.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Prompt 构建'**
  String get sessMetaPromptBuilds;

  /// No description provided for @sessMetaCompressions.
  ///
  /// In zh_Hans, this message translates to:
  /// **'压缩次数'**
  String get sessMetaCompressions;

  /// No description provided for @sessMetaTotalTokens.
  ///
  /// In zh_Hans, this message translates to:
  /// **'总 Token'**
  String get sessMetaTotalTokens;

  /// No description provided for @sessMetaMode.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前模式'**
  String get sessMetaMode;

  /// No description provided for @sessMetaRuntimeTools.
  ///
  /// In zh_Hans, this message translates to:
  /// **'运行工具'**
  String get sessMetaRuntimeTools;

  /// No description provided for @sessMetaPending.
  ///
  /// In zh_Hans, this message translates to:
  /// **'未展示'**
  String get sessMetaPending;

  /// No description provided for @sessMetaCurrentSessionMetadata.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前会话元数据'**
  String get sessMetaCurrentSessionMetadata;

  /// No description provided for @sessMetaSessionOverview.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话概览'**
  String get sessMetaSessionOverview;

  /// No description provided for @sessMetaExtendedMetadata.
  ///
  /// In zh_Hans, this message translates to:
  /// **'扩展元数据'**
  String get sessMetaExtendedMetadata;

  /// No description provided for @sessMetaStatistics.
  ///
  /// In zh_Hans, this message translates to:
  /// **'统计信息'**
  String get sessMetaStatistics;

  /// No description provided for @sessMetaUser.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户'**
  String get sessMetaUser;

  /// No description provided for @sessMetaAssistant.
  ///
  /// In zh_Hans, this message translates to:
  /// **'助手'**
  String get sessMetaAssistant;

  /// No description provided for @sessMetaTool.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具'**
  String get sessMetaTool;

  /// No description provided for @sessMetaSkill.
  ///
  /// In zh_Hans, this message translates to:
  /// **'技能'**
  String get sessMetaSkill;

  /// No description provided for @sessMetaCompression.
  ///
  /// In zh_Hans, this message translates to:
  /// **'压缩'**
  String get sessMetaCompression;

  /// No description provided for @sessMetaEnvironment.
  ///
  /// In zh_Hans, this message translates to:
  /// **'运行环境'**
  String get sessMetaEnvironment;

  /// No description provided for @sessMetaCommandPolicy.
  ///
  /// In zh_Hans, this message translates to:
  /// **'命令策略'**
  String get sessMetaCommandPolicy;

  /// No description provided for @sessMetaPromptMetadataIsNotAvailableYet.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前还没有可展示的 prompt 元数据。'**
  String get sessMetaPromptMetadataIsNotAvailableYet;

  /// No description provided for @sessMetaWriteConfirmation.
  ///
  /// In zh_Hans, this message translates to:
  /// **'写命令确认'**
  String get sessMetaWriteConfirmation;

  /// No description provided for @sessMetaRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'需要确认'**
  String get sessMetaRequired;

  /// No description provided for @sessMetaNotRequired.
  ///
  /// In zh_Hans, this message translates to:
  /// **'无需确认'**
  String get sessMetaNotRequired;

  /// No description provided for @sessMetaAllowRules.
  ///
  /// In zh_Hans, this message translates to:
  /// **'允许规则数'**
  String get sessMetaAllowRules;

  /// No description provided for @sessMetaThereAreNoSurfacedAllowCommand.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前没有已上屏的允许命令规则。'**
  String get sessMetaThereAreNoSurfacedAllowCommand;

  /// No description provided for @sessMetaRuntimeOrchestration.
  ///
  /// In zh_Hans, this message translates to:
  /// **'运行时编排'**
  String get sessMetaRuntimeOrchestration;

  /// No description provided for @sessMetaStateSource.
  ///
  /// In zh_Hans, this message translates to:
  /// **'状态来源'**
  String get sessMetaStateSource;

  /// No description provided for @sessMetaGeneratedFromTheCurrentModelMcp.
  ///
  /// In zh_Hans, this message translates to:
  /// **'根据当前模型、MCP/Skills 与 Plan 状态即时生成'**
  String get sessMetaGeneratedFromTheCurrentModelMcp;

  /// No description provided for @sessMetaTheLastPersistedRuntimeSnapshot.
  ///
  /// In zh_Hans, this message translates to:
  /// **'上一轮已落盘的运行时快照'**
  String get sessMetaTheLastPersistedRuntimeSnapshot;

  /// No description provided for @sessMetaToolCatalogState.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具目录状态'**
  String get sessMetaToolCatalogState;

  /// No description provided for @sessMetaGateReason.
  ///
  /// In zh_Hans, this message translates to:
  /// **'门控原因'**
  String get sessMetaGateReason;

  /// No description provided for @sessMetaRuntimeToolCount.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前运行时工具数'**
  String get sessMetaRuntimeToolCount;

  /// No description provided for @sessMetaRefreshesNextRound.
  ///
  /// In zh_Hans, this message translates to:
  /// **'等待下一轮刷新'**
  String get sessMetaRefreshesNextRound;

  /// No description provided for @sessMetaRuntimeNotices.
  ///
  /// In zh_Hans, this message translates to:
  /// **'运行时 Notices'**
  String get sessMetaRuntimeNotices;

  /// No description provided for @sessMetaCurrentRuntimeTools.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前运行时工具'**
  String get sessMetaCurrentRuntimeTools;

  /// No description provided for @sessMetaTaskTracking.
  ///
  /// In zh_Hans, this message translates to:
  /// **'任务跟踪'**
  String get sessMetaTaskTracking;

  /// No description provided for @sessMetaCurrentTodos.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前 Todo 数量'**
  String get sessMetaCurrentTodos;

  /// No description provided for @sessMetaPlanRecords.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划记录数量'**
  String get sessMetaPlanRecords;

  /// No description provided for @sessMetaTodowriteReminder.
  ///
  /// In zh_Hans, this message translates to:
  /// **'TodoWrite 强提醒'**
  String get sessMetaTodowriteReminder;

  /// No description provided for @sessMetaTriggered.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已触发'**
  String get sessMetaTriggered;

  /// No description provided for @sessMetaNotTriggered.
  ///
  /// In zh_Hans, this message translates to:
  /// **'未触发'**
  String get sessMetaNotTriggered;

  /// No description provided for @sessMetaUnavailable.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暂无数据'**
  String get sessMetaUnavailable;

  /// No description provided for @sessMetaReminderReason.
  ///
  /// In zh_Hans, this message translates to:
  /// **'提醒原因'**
  String get sessMetaReminderReason;

  /// No description provided for @sessMetaPlanHistory.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划历史'**
  String get sessMetaPlanHistory;

  /// No description provided for @sessMetaRecentErrors.
  ///
  /// In zh_Hans, this message translates to:
  /// **'最近异常'**
  String get sessMetaRecentErrors;

  /// No description provided for @sessMetaThereAreNoSessionErrorsTo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前没有需要关注的会话异常。'**
  String get sessMetaThereAreNoSessionErrorsTo;

  /// No description provided for @sessMetaLastPromptMetadata.
  ///
  /// In zh_Hans, this message translates to:
  /// **'最后一次 Prompt 元数据'**
  String get sessMetaLastPromptMetadata;

  /// No description provided for @sessMetaClose.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭'**
  String get sessMetaClose;

  /// No description provided for @sessMetaPendingApproval.
  ///
  /// In zh_Hans, this message translates to:
  /// **'待确认'**
  String get sessMetaPendingApproval;

  /// No description provided for @sessMetaInProgress.
  ///
  /// In zh_Hans, this message translates to:
  /// **'进行中'**
  String get sessMetaInProgress;

  /// No description provided for @sessMetaCompleted.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已完成'**
  String get sessMetaCompleted;

  /// No description provided for @sessMetaFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'失败'**
  String get sessMetaFailed;

  /// No description provided for @sessMetaCancelled.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已取消'**
  String get sessMetaCancelled;

  /// No description provided for @sessMetaCreated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'创建'**
  String get sessMetaCreated;

  /// No description provided for @sessMetaUpdated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'更新'**
  String get sessMetaUpdated;

  /// No description provided for @sessMetaErrorDetail.
  ///
  /// In zh_Hans, this message translates to:
  /// **'错误细节'**
  String get sessMetaErrorDetail;

  /// No description provided for @sessMetaPresented.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已展示'**
  String get sessMetaPresented;

  /// No description provided for @sessMetaThisSessionEndedEarlyRetryThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前会话已提前结束。请重试或继续发送更具体的指令。'**
  String get sessMetaThisSessionEndedEarlyRetryThe;

  /// No description provided for @sessMetaToolCallsStoppedForSafety.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具调用已安全停止'**
  String get sessMetaToolCallsStoppedForSafety;

  /// No description provided for @sessMetaOpenhandStoppedThisSessionForSafety.
  ///
  /// In zh_Hans, this message translates to:
  /// **'本次会话连续触发了过多轮工具调用，OpenHand 已为安全起见提前停止。这次停止发生在会话控制层，并不是某个具体工具真的执行失败。你可以让助手先总结当前进展，或给出更具体的下一步指令。'**
  String get sessMetaOpenhandStoppedThisSessionForSafety;

  /// No description provided for @sessMetaResponseInterrupted.
  ///
  /// In zh_Hans, this message translates to:
  /// **'回答已中断'**
  String get sessMetaResponseInterrupted;

  /// No description provided for @sessMetaTheResponseWasInterruptedWhileStreaming.
  ///
  /// In zh_Hans, this message translates to:
  /// **'本次回答在流式接收过程中异常中断，当前会话已停止。你可以直接重试，或继续发送下一条消息。'**
  String get sessMetaTheResponseWasInterruptedWhileStreaming;

  /// No description provided for @sessMetaRequestFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请求发送失败'**
  String get sessMetaRequestFailed;

  /// No description provided for @sessMetaTheRequestFailedBeforeTheAssistant.
  ///
  /// In zh_Hans, this message translates to:
  /// **'本次请求在发送阶段失败，当前会话未继续执行。你可以检查配置后重试，或继续发送新的消息。'**
  String get sessMetaTheRequestFailedBeforeTheAssistant;

  /// No description provided for @sessMetaContinuationFailed.
  ///
  /// In zh_Hans, this message translates to:
  /// **'后续请求失败'**
  String get sessMetaContinuationFailed;

  /// No description provided for @sessMetaTheSessionFailedWhileRequestingThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'本次会话在继续执行后续步骤时，请求下一轮模型响应失败。已完成的步骤与工具结果都已保留，你可以直接回复继续/重试，或检查配置后再试。'**
  String get sessMetaTheSessionFailedWhileRequestingThe;

  /// No description provided for @sessMetaSafetyStop.
  ///
  /// In zh_Hans, this message translates to:
  /// **'安全停止'**
  String get sessMetaSafetyStop;

  /// No description provided for @sessMetaStreamError.
  ///
  /// In zh_Hans, this message translates to:
  /// **'响应中断'**
  String get sessMetaStreamError;

  /// No description provided for @sessMetaRequestError.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请求失败'**
  String get sessMetaRequestError;

  /// No description provided for @sessMetaContinuationError.
  ///
  /// In zh_Hans, this message translates to:
  /// **'后续请求失败'**
  String get sessMetaContinuationError;

  /// No description provided for @sessMetaToolExecutionError.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具执行失败'**
  String get sessMetaToolExecutionError;

  /// No description provided for @sessMetaCompressionError.
  ///
  /// In zh_Hans, this message translates to:
  /// **'历史压缩失败'**
  String get sessMetaCompressionError;

  /// No description provided for @sessMetaPromptBlocked.
  ///
  /// In zh_Hans, this message translates to:
  /// **'提示词被拦截'**
  String get sessMetaPromptBlocked;

  /// No description provided for @sessMetaTitleGenerationError.
  ///
  /// In zh_Hans, this message translates to:
  /// **'标题生成失败'**
  String get sessMetaTitleGenerationError;

  /// No description provided for @sessMetaSessionError.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话异常'**
  String get sessMetaSessionError;

  /// No description provided for @auditNoData.
  ///
  /// In zh_Hans, this message translates to:
  /// **'无数据'**
  String get auditNoData;

  /// No description provided for @auditCopyJson.
  ///
  /// In zh_Hans, this message translates to:
  /// **'复制 JSON'**
  String get auditCopyJson;

  /// No description provided for @auditCopiedToClipboard.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已复制到剪贴板'**
  String get auditCopiedToClipboard;

  /// No description provided for @auditMessageAudit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息审计'**
  String get auditMessageAudit;

  /// No description provided for @auditClose.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭'**
  String get auditClose;

  /// No description provided for @auditOverview.
  ///
  /// In zh_Hans, this message translates to:
  /// **'基本信息'**
  String get auditOverview;

  /// No description provided for @auditMessageId.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息 ID'**
  String get auditMessageId;

  /// No description provided for @auditSessionId.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话 ID'**
  String get auditSessionId;

  /// No description provided for @auditRole.
  ///
  /// In zh_Hans, this message translates to:
  /// **'角色'**
  String get auditRole;

  /// No description provided for @auditKind.
  ///
  /// In zh_Hans, this message translates to:
  /// **'类型'**
  String get auditKind;

  /// No description provided for @auditCharacterCount.
  ///
  /// In zh_Hans, this message translates to:
  /// **'字符数'**
  String get auditCharacterCount;

  /// No description provided for @auditStreaming.
  ///
  /// In zh_Hans, this message translates to:
  /// **'是否流式'**
  String get auditStreaming;

  /// No description provided for @auditDeleted.
  ///
  /// In zh_Hans, this message translates to:
  /// **'是否已删除'**
  String get auditDeleted;

  /// No description provided for @auditHasError.
  ///
  /// In zh_Hans, this message translates to:
  /// **'是否报错'**
  String get auditHasError;

  /// No description provided for @auditTiming.
  ///
  /// In zh_Hans, this message translates to:
  /// **'时间与耗时'**
  String get auditTiming;

  /// No description provided for @auditStartedCreated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'开始/创建时间'**
  String get auditStartedCreated;

  /// No description provided for @auditEnded.
  ///
  /// In zh_Hans, this message translates to:
  /// **'结束时间'**
  String get auditEnded;

  /// No description provided for @auditDurationMs.
  ///
  /// In zh_Hans, this message translates to:
  /// **'耗时 (ms)'**
  String get auditDurationMs;

  /// No description provided for @auditModelTokens.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模型与 Token'**
  String get auditModelTokens;

  /// No description provided for @auditModelId.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模型 ID'**
  String get auditModelId;

  /// No description provided for @auditModelLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模型标签'**
  String get auditModelLabel;

  /// No description provided for @auditTotalTokens.
  ///
  /// In zh_Hans, this message translates to:
  /// **'总 Token'**
  String get auditTotalTokens;

  /// No description provided for @auditPromptTokens.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输入 Token'**
  String get auditPromptTokens;

  /// No description provided for @auditCompletionTokens.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输出 Token'**
  String get auditCompletionTokens;

  /// No description provided for @auditTokenBreakdown.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Token 明细'**
  String get auditTokenBreakdown;

  /// No description provided for @auditError.
  ///
  /// In zh_Hans, this message translates to:
  /// **'错误信息'**
  String get auditError;

  /// No description provided for @auditContent.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息内容'**
  String get auditContent;

  /// No description provided for @auditFullComposedPromptThatWasActually.
  ///
  /// In zh_Hans, this message translates to:
  /// **'以下为该轮用户消息触发时，程序自动拼装后最终发送给 AI 的 prompt 完全体（含系统指令 / 工具目录 / 用户记忆 / 历史上下文 / 用户输入等）。'**
  String get auditFullComposedPromptThatWasActually;

  /// No description provided for @auditWaitingForComposedPromptInjectionAuto.
  ///
  /// In zh_Hans, this message translates to:
  /// **'正在等待本轮最终组合 Prompt 注入（发送中会自动刷新）'**
  String get auditWaitingForComposedPromptInjectionAuto;

  /// No description provided for @auditUserRawInput.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户原始输入'**
  String get auditUserRawInput;

  /// No description provided for @auditStructuredPromptTurns.
  ///
  /// In zh_Hans, this message translates to:
  /// **'结构化 Prompt Turns'**
  String get auditStructuredPromptTurns;

  /// No description provided for @auditNone.
  ///
  /// In zh_Hans, this message translates to:
  /// **'无'**
  String get auditNone;

  /// No description provided for @auditPromptMetadata.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Prompt Metadata'**
  String get auditPromptMetadata;

  /// No description provided for @auditRequest.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请求参数'**
  String get auditRequest;

  /// No description provided for @auditMethod.
  ///
  /// In zh_Hans, this message translates to:
  /// **'方法'**
  String get auditMethod;

  /// No description provided for @auditHeaders.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请求头'**
  String get auditHeaders;

  /// No description provided for @auditNotCapturedEnableSettingsAiTelemetry.
  ///
  /// In zh_Hans, this message translates to:
  /// **'未捕获（请在设置 → AI → 遥测 中开启调试）'**
  String get auditNotCapturedEnableSettingsAiTelemetry;

  /// No description provided for @auditBodyQueryPath.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请求体 / Query / Path'**
  String get auditBodyQueryPath;

  /// No description provided for @auditRawAiResponse.
  ///
  /// In zh_Hans, this message translates to:
  /// **'原始 AI 响应'**
  String get auditRawAiResponse;

  /// No description provided for @auditExpandRawResponse.
  ///
  /// In zh_Hans, this message translates to:
  /// **'展开查看原始响应'**
  String get auditExpandRawResponse;

  /// No description provided for @auditNotCapturedDebugDisabledOrResponse.
  ///
  /// In zh_Hans, this message translates to:
  /// **'未捕获：调试未开启或模型未提供原始响应'**
  String get auditNotCapturedDebugDisabledOrResponse;

  /// No description provided for @auditAttachments.
  ///
  /// In zh_Hans, this message translates to:
  /// **'附件'**
  String get auditAttachments;

  /// No description provided for @auditAttachmentList.
  ///
  /// In zh_Hans, this message translates to:
  /// **'附件列表'**
  String get auditAttachmentList;

  /// No description provided for @auditNoAttachments.
  ///
  /// In zh_Hans, this message translates to:
  /// **'无附件'**
  String get auditNoAttachments;

  /// No description provided for @auditFullMetadata.
  ///
  /// In zh_Hans, this message translates to:
  /// **'完整元数据 (metadata)'**
  String get auditFullMetadata;

  /// No description provided for @auditMessageMetadata.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息元数据'**
  String get auditMessageMetadata;

  /// No description provided for @auditSessionEnvironment.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话环境'**
  String get auditSessionEnvironment;

  /// No description provided for @auditEnvironmentSnapshot.
  ///
  /// In zh_Hans, this message translates to:
  /// **'环境快照'**
  String get auditEnvironmentSnapshot;

  /// No description provided for @auditAuditSnapshotCopied.
  ///
  /// In zh_Hans, this message translates to:
  /// **'审计快照已复制'**
  String get auditAuditSnapshotCopied;

  /// No description provided for @auditCopyAuditSnapshot.
  ///
  /// In zh_Hans, this message translates to:
  /// **'复制审计快照'**
  String get auditCopyAuditSnapshot;

  /// No description provided for @auditSessionMetadataSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话元数据已更新'**
  String get auditSessionMetadataSaved;

  /// No description provided for @auditSessionAudit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话审计'**
  String get auditSessionAudit;

  /// No description provided for @auditTemplate.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模板'**
  String get auditTemplate;

  /// No description provided for @auditCreatedAt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'创建时间'**
  String get auditCreatedAt;

  /// No description provided for @auditUpdatedAt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'更新时间'**
  String get auditUpdatedAt;

  /// No description provided for @auditMessages.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息数'**
  String get auditMessages;

  /// No description provided for @auditLastModel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'最近模型'**
  String get auditLastModel;

  /// No description provided for @auditTitleEditable.
  ///
  /// In zh_Hans, this message translates to:
  /// **'标题编辑'**
  String get auditTitleEditable;

  /// No description provided for @auditSessionTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话标题'**
  String get auditSessionTitle;

  /// No description provided for @auditSaveTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存标题'**
  String get auditSaveTitle;

  /// No description provided for @auditSessionMetadataEditableJson.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话元数据 (可编辑 JSON)'**
  String get auditSessionMetadataEditableJson;

  /// No description provided for @auditSaveWritesBackThroughTheSession.
  ///
  /// In zh_Hans, this message translates to:
  /// **'修改后点击保存将通过会话控制器写回数据库并实时刷新 UI。删除的 key 会被清除。'**
  String get auditSaveWritesBackThroughTheSession;

  /// No description provided for @auditSaveMetadata.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存元数据'**
  String get auditSaveMetadata;

  /// No description provided for @auditRuntimePromptMetadataReadOnly.
  ///
  /// In zh_Hans, this message translates to:
  /// **'运行时 Prompt 元数据 (只读)'**
  String get auditRuntimePromptMetadataReadOnly;

  /// No description provided for @auditUsefulForPromptConstructionTroubleshooti.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用于排查本轮消息拼装上下文；自动由系统写入。'**
  String get auditUsefulForPromptConstructionTroubleshooti;

  /// No description provided for @auditLastPromptMetadata.
  ///
  /// In zh_Hans, this message translates to:
  /// **'last_prompt_metadata'**
  String get auditLastPromptMetadata;

  /// No description provided for @auditNoRuntimePromptMetadataYet.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暂无运行时 Prompt 元数据'**
  String get auditNoRuntimePromptMetadataYet;

  /// No description provided for @auditEnvironment.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话环境'**
  String get auditEnvironment;

  /// No description provided for @auditErrorList.
  ///
  /// In zh_Hans, this message translates to:
  /// **'错误列表'**
  String get auditErrorList;

  /// No description provided for @auditNoErrorsRecorded.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暂无错误'**
  String get auditNoErrorsRecorded;

  /// No description provided for @auditTapARowToInspectA.
  ///
  /// In zh_Hans, this message translates to:
  /// **'点击单条可打开消息审计弹窗；支持删除单条消息。'**
  String get auditTapARowToInspectA;

  /// No description provided for @auditNoMessages.
  ///
  /// In zh_Hans, this message translates to:
  /// **'暂无消息'**
  String get auditNoMessages;

  /// No description provided for @auditAudit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'审计'**
  String get auditAudit;

  /// No description provided for @auditDelete.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除'**
  String get auditDelete;

  /// No description provided for @progExpFESelectOpenedFile.
  ///
  /// In zh_Hans, this message translates to:
  /// **'定位到已打开文件'**
  String get progExpFESelectOpenedFile;

  /// No description provided for @progExpFEExpandSelected.
  ///
  /// In zh_Hans, this message translates to:
  /// **'展开选中目录'**
  String get progExpFEExpandSelected;

  /// No description provided for @progExpFECollapseAll.
  ///
  /// In zh_Hans, this message translates to:
  /// **'全部折叠'**
  String get progExpFECollapseAll;

  /// No description provided for @progExpFETypeASymbolNameToSearch.
  ///
  /// In zh_Hans, this message translates to:
  /// **'输入符号名后即可在当前工作区内跨文件搜索。'**
  String get progExpFETypeASymbolNameToSearch;

  /// No description provided for @progExpFENoWorkspaceSymbolBackendIsAvailable.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前文件没有可用的工作区符号后端。'**
  String get progExpFENoWorkspaceSymbolBackendIsAvailable;

  /// No description provided for @progExpFENoMatchingWorkspaceSymbolsWereFound.
  ///
  /// In zh_Hans, this message translates to:
  /// **'没有找到匹配的工作区符号。'**
  String get progExpFENoMatchingWorkspaceSymbolsWereFound;

  /// No description provided for @progExpFEFetchingWorkspaceSymbolsFailedConfirmTha.
  ///
  /// In zh_Hans, this message translates to:
  /// **'读取工作区符号失败，请确认对应语言服务器支持 workspace/symbol。'**
  String get progExpFEFetchingWorkspaceSymbolsFailedConfirmTha;

  /// No description provided for @progExpFEThisFileIsStillInLarge.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前文件仍处于大文件预览模式，符号栏暂使用本地提取以保持响应速度。'**
  String get progExpFEThisFileIsStillInLarge;

  /// No description provided for @progExpFENoLspSymbolBackendIsAvailable.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前文件没有可用的 LSP 符号后端，已回退到本地符号提取。'**
  String get progExpFENoLspSymbolBackendIsAvailable;

  /// No description provided for @progExpFETheLspServerReturnedAnEmpty.
  ///
  /// In zh_Hans, this message translates to:
  /// **'LSP 已返回空符号列表。'**
  String get progExpFETheLspServerReturnedAnEmpty;

  /// No description provided for @progExpFEFetchingLspSymbolsFailedSoThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'读取 LSP 符号失败，已回退到本地符号提取。'**
  String get progExpFEFetchingLspSymbolsFailedSoThe;

  /// No description provided for @progExpFERenameSymbol.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重命名符号'**
  String get progExpFERenameSymbol;

  /// No description provided for @progExpFEReviewTheDiffForThisRename.
  ///
  /// In zh_Hans, this message translates to:
  /// **'先查看这次重命名将影响的差异，再决定是否应用。'**
  String get progExpFEReviewTheDiffForThisRename;

  /// No description provided for @progExpFETheRenameWasCancelledAndNo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已取消本次重命名，未写入任何修改。'**
  String get progExpFETheRenameWasCancelledAndNo;

  /// No description provided for @progExpFETheSymbolAtTheCurrentCursor.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前光标位置不支持重命名。'**
  String get progExpFETheSymbolAtTheCurrentCursor;

  /// No description provided for @progExpFETheLanguageServerDidNotReturn.
  ///
  /// In zh_Hans, this message translates to:
  /// **'语言服务器没有返回需要应用的修改。'**
  String get progExpFETheLanguageServerDidNotReturn;

  /// No description provided for @progExpFECodeActions.
  ///
  /// In zh_Hans, this message translates to:
  /// **'代码操作'**
  String get progExpFECodeActions;

  /// No description provided for @progExpFENoCodeActionsAreAvailableAt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前光标位置没有可用的代码操作。'**
  String get progExpFENoCodeActionsAreAvailableAt;

  /// No description provided for @progExpFEReviewTheDiffFromThisCode.
  ///
  /// In zh_Hans, this message translates to:
  /// **'先预览该代码操作将要写入的差异，再决定是否应用。'**
  String get progExpFEReviewTheDiffFromThisCode;

  /// No description provided for @progExpFEIfTheLanguageServerCommandRequests.
  ///
  /// In zh_Hans, this message translates to:
  /// **'如果语言服务器命令在执行过程中请求写入修改，也会先展示差异预览。'**
  String get progExpFEIfTheLanguageServerCommandRequests;

  /// No description provided for @progExpFETheCodeActionWasCancelledAnd.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已取消本次代码操作，未写入任何修改。'**
  String get progExpFETheCodeActionWasCancelledAnd;

  /// No description provided for @progExpFEExecutedTheLanguageServerCommand.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已执行语言服务器命令。'**
  String get progExpFEExecutedTheLanguageServerCommand;

  /// No description provided for @progExpFESomeLanguageServerRequestedEditsWere.
  ///
  /// In zh_Hans, this message translates to:
  /// **'有语言服务器请求的修改被跳过。'**
  String get progExpFESomeLanguageServerRequestedEditsWere;

  /// No description provided for @progExpFEThisCodeActionDidNotReturn.
  ///
  /// In zh_Hans, this message translates to:
  /// **'该代码操作没有返回可应用的编辑。'**
  String get progExpFEThisCodeActionDidNotReturn;

  /// No description provided for @progExpFEQuickFix.
  ///
  /// In zh_Hans, this message translates to:
  /// **'快速修复'**
  String get progExpFEQuickFix;

  /// No description provided for @progExpFENoQuickFixesAreAvailableFor.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前诊断位置没有可用的快速修复。'**
  String get progExpFENoQuickFixesAreAvailableFor;

  /// No description provided for @progExpFENoCodeActionsAreAvailableFor.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前诊断位置没有可用的代码操作。'**
  String get progExpFENoCodeActionsAreAvailableFor;

  /// No description provided for @progExpFENoQuickFixesAreAvailableFor2.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前诊断行没有可用的快速修复。'**
  String get progExpFENoQuickFixesAreAvailableFor2;

  /// No description provided for @progExpFETheCurrentFileIsStillLoading.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前文件尚未完成加载，暂时无法执行 LSP 操作。'**
  String get progExpFETheCurrentFileIsStillLoading;

  /// No description provided for @progExpFEThisFileIsStillInLarge2.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前文件仍处于大文件预览模式，请先切换到完整编辑器后再执行 LSP 跳转。'**
  String get progExpFEThisFileIsStillInLarge2;

  /// No description provided for @progExpFETheCurrentFileIsStillLoading2.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前文件尚未完成加载，暂时无法执行文档级编辑操作。'**
  String get progExpFETheCurrentFileIsStillLoading2;

  /// No description provided for @progExpFEThisFileIsStillInLarge3.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前文件仍处于大文件预览模式，请先切换到完整编辑器后再执行格式化。'**
  String get progExpFEThisFileIsStillInLarge3;

  /// No description provided for @progExpFEFormatDocument.
  ///
  /// In zh_Hans, this message translates to:
  /// **'格式化文档'**
  String get progExpFEFormatDocument;

  /// No description provided for @progExpFETheCurrentFileIsNotReady.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前文件尚未准备好，稍后再试。'**
  String get progExpFETheCurrentFileIsNotReady;

  /// No description provided for @progExpFETheFormatterDidNotReturnAny.
  ///
  /// In zh_Hans, this message translates to:
  /// **'格式化器没有返回可应用的修改。'**
  String get progExpFETheFormatterDidNotReturnAny;

  /// No description provided for @progExpFEFormattingProducedTheSameContentSo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'格式化结果与当前内容一致，没有产生新的文本变更。'**
  String get progExpFEFormattingProducedTheSameContentSo;

  /// No description provided for @progExpFEGoToDefinition.
  ///
  /// In zh_Hans, this message translates to:
  /// **'定义跳转'**
  String get progExpFEGoToDefinition;

  /// No description provided for @progExpFENoDefinitionWasFoundAtThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前光标位置没有找到定义。'**
  String get progExpFENoDefinitionWasFoundAtThe;

  /// No description provided for @progExpFEMultipleDefinitionsWereFoundChooseA.
  ///
  /// In zh_Hans, this message translates to:
  /// **'找到多个定义结果，请选择要跳转的位置。'**
  String get progExpFEMultipleDefinitionsWereFoundChooseA;

  /// No description provided for @progExpFEFindReferences.
  ///
  /// In zh_Hans, this message translates to:
  /// **'引用查找'**
  String get progExpFEFindReferences;

  /// No description provided for @progExpFENoReferencesWereFoundAtThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前光标位置没有找到引用。'**
  String get progExpFENoReferencesWereFoundAtThe;

  /// No description provided for @progExpFEHoverInfo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'悬浮信息'**
  String get progExpFEHoverInfo;

  /// No description provided for @progExpFEThereIsNoHoverInformationAt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前光标位置没有可显示的悬浮信息。'**
  String get progExpFEThereIsNoHoverInformationAt;

  /// No description provided for @progExpFELspBackend.
  ///
  /// In zh_Hans, this message translates to:
  /// **'LSP 后端'**
  String get progExpFELspBackend;

  /// No description provided for @progExpFEReResolveTheBackendForThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重新解析当前文件后端'**
  String get progExpFEReResolveTheBackendForThe;

  /// No description provided for @progExpFEInspectBackendDetails.
  ///
  /// In zh_Hans, this message translates to:
  /// **'查看后端详情'**
  String get progExpFEInspectBackendDetails;

  /// No description provided for @progExpFECloseEsc.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭 (Esc)'**
  String get progExpFECloseEsc;

  /// No description provided for @progExpFEToggleComment.
  ///
  /// In zh_Hans, this message translates to:
  /// **'切换注释'**
  String get progExpFEToggleComment;

  /// No description provided for @progExpFEThisLanguageDoesNotHaveA.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前语言暂未配置注释策略，无法执行注释切换。'**
  String get progExpFEThisLanguageDoesNotHaveA;

  /// No description provided for @progExpFEGoToImplementation.
  ///
  /// In zh_Hans, this message translates to:
  /// **'跳转到实现'**
  String get progExpFEGoToImplementation;

  /// No description provided for @progExpFESignatureHelp.
  ///
  /// In zh_Hans, this message translates to:
  /// **'参数信息'**
  String get progExpFESignatureHelp;

  /// No description provided for @progExpFEThereIsNoSignatureHelpAvailable.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前光标位置没有可显示的参数签名信息。'**
  String get progExpFEThereIsNoSignatureHelpAvailable;

  /// No description provided for @progExpFEPreviousMatch.
  ///
  /// In zh_Hans, this message translates to:
  /// **'上一个结果'**
  String get progExpFEPreviousMatch;

  /// No description provided for @progExpFENextMatch.
  ///
  /// In zh_Hans, this message translates to:
  /// **'下一个结果'**
  String get progExpFENextMatch;

  /// No description provided for @progExpFEMatchCase.
  ///
  /// In zh_Hans, this message translates to:
  /// **'区分大小写'**
  String get progExpFEMatchCase;

  /// No description provided for @progExpFEShowReplace.
  ///
  /// In zh_Hans, this message translates to:
  /// **'显示替换'**
  String get progExpFEShowReplace;

  /// No description provided for @progExpFEReplaceCurrent.
  ///
  /// In zh_Hans, this message translates to:
  /// **'替换当前结果'**
  String get progExpFEReplaceCurrent;

  /// No description provided for @progExpFEReplaceAll.
  ///
  /// In zh_Hans, this message translates to:
  /// **'全部替换'**
  String get progExpFEReplaceAll;

  /// No description provided for @progExpFECurrentFileSymbols.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前文件符号'**
  String get progExpFECurrentFileSymbols;

  /// No description provided for @progExpFEWorkspaceSymbols.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工作区符号'**
  String get progExpFEWorkspaceSymbols;

  /// No description provided for @progExpFERefreshDiagnostics.
  ///
  /// In zh_Hans, this message translates to:
  /// **'刷新诊断'**
  String get progExpFERefreshDiagnostics;

  /// No description provided for @progExpFESymbols.
  ///
  /// In zh_Hans, this message translates to:
  /// **'符号'**
  String get progExpFESymbols;

  /// No description provided for @progExpFESymbolNavigationShiftCmdCtrlO.
  ///
  /// In zh_Hans, this message translates to:
  /// **'符号导航 (Shift+Cmd/Ctrl+O)'**
  String get progExpFESymbolNavigationShiftCmdCtrlO;

  /// No description provided for @progExpFEWorkspace.
  ///
  /// In zh_Hans, this message translates to:
  /// **'全局符号'**
  String get progExpFEWorkspace;

  /// No description provided for @progExpFEWorkspaceSymbolSearchCmdCtrlT.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工作区符号搜索 (Cmd/Ctrl+T)'**
  String get progExpFEWorkspaceSymbolSearchCmdCtrlT;

  /// No description provided for @progExpFEShowDiagnosticsForTheCurrentFile.
  ///
  /// In zh_Hans, this message translates to:
  /// **'显示当前文件诊断'**
  String get progExpFEShowDiagnosticsForTheCurrentFile;

  /// No description provided for @progExpFEInspectTheLspBackendBoundTo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'查看当前文件绑定的 LSP 后端'**
  String get progExpFEInspectTheLspBackendBoundTo;

  /// No description provided for @progExpFEDef.
  ///
  /// In zh_Hans, this message translates to:
  /// **'定义'**
  String get progExpFEDef;

  /// No description provided for @progExpFEGoToDefinitionF12CmdCtrl.
  ///
  /// In zh_Hans, this message translates to:
  /// **'定义跳转 (F12 / Cmd/Ctrl+B)'**
  String get progExpFEGoToDefinitionF12CmdCtrl;

  /// No description provided for @progExpFERefs.
  ///
  /// In zh_Hans, this message translates to:
  /// **'引用'**
  String get progExpFERefs;

  /// No description provided for @progExpFEFindReferencesShiftF12CmdCtrl.
  ///
  /// In zh_Hans, this message translates to:
  /// **'引用查找 (Shift+F12 / Cmd/Ctrl+Shift+B)'**
  String get progExpFEFindReferencesShiftF12CmdCtrl;

  /// No description provided for @progExpFEHover.
  ///
  /// In zh_Hans, this message translates to:
  /// **'悬浮'**
  String get progExpFEHover;

  /// No description provided for @progExpFEHoverInfoCmdCtrlI.
  ///
  /// In zh_Hans, this message translates to:
  /// **'悬浮信息 (Cmd/Ctrl+I)'**
  String get progExpFEHoverInfoCmdCtrlI;

  /// No description provided for @progExpFERename.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重命名'**
  String get progExpFERename;

  /// No description provided for @progExpFERenameSymbolF2.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重命名符号 (F2)'**
  String get progExpFERenameSymbolF2;

  /// No description provided for @progExpFEActions.
  ///
  /// In zh_Hans, this message translates to:
  /// **'操作'**
  String get progExpFEActions;

  /// No description provided for @progExpFECodeActionsCmdCtrl.
  ///
  /// In zh_Hans, this message translates to:
  /// **'代码操作 (Cmd/Ctrl+.)'**
  String get progExpFECodeActionsCmdCtrl;

  /// No description provided for @progExpFEFormat.
  ///
  /// In zh_Hans, this message translates to:
  /// **'格式化'**
  String get progExpFEFormat;

  /// No description provided for @progExpFENoImplementationWasFoundAtThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前光标位置没有找到实现。'**
  String get progExpFENoImplementationWasFoundAtThe;

  /// No description provided for @progExpFEMultipleImplementationsFoundChooseATarge.
  ///
  /// In zh_Hans, this message translates to:
  /// **'找到多个实现，请选择要跳转的位置。'**
  String get progExpFEMultipleImplementationsFoundChooseATarge;

  /// No description provided for @progExpFERefactor.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重构'**
  String get progExpFERefactor;

  /// No description provided for @progExpFEReviewTheChangesBeforeApplying.
  ///
  /// In zh_Hans, this message translates to:
  /// **'查看此次重构将影响的差异，再决定是否应用。'**
  String get progExpFEReviewTheChangesBeforeApplying;

  /// No description provided for @progExpFESaveFile.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存文件'**
  String get progExpFESaveFile;

  /// No description provided for @progExpFECloseEditorReturnToSession.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭编辑器，返回会话'**
  String get progExpFECloseEditorReturnToSession;

  /// No description provided for @progExpFEShowQuickFixesForThisDiagnostic.
  ///
  /// In zh_Hans, this message translates to:
  /// **'显示该诊断行的快速修复'**
  String get progExpFEShowQuickFixesForThisDiagnostic;

  /// No description provided for @progExpFELargeFilePerformanceModeIsActive.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已启用大文件性能模式：使用虚拟化只读预览，避免整篇文本布局导致卡顿。'**
  String get progExpFELargeFilePerformanceModeIsActive;

  /// No description provided for @progExpFEOpenFullEditorAnyway.
  ///
  /// In zh_Hans, this message translates to:
  /// **'仍然打开完整编辑器'**
  String get progExpFEOpenFullEditorAnyway;

  /// No description provided for @settingsShortcuts.
  ///
  /// In zh_Hans, this message translates to:
  /// **'快捷键'**
  String get settingsShortcuts;

  /// No description provided for @settingsConfigureKeyCombinationsForCommonActions.
  ///
  /// In zh_Hans, this message translates to:
  /// **'为常用操作配置组合键。当前最多支持同时按下 4 个按键。'**
  String get settingsConfigureKeyCombinationsForCommonActions;

  /// No description provided for @settingsBuiltInTools.
  ///
  /// In zh_Hans, this message translates to:
  /// **'内建工具'**
  String get settingsBuiltInTools;

  /// No description provided for @settingsCrons.
  ///
  /// In zh_Hans, this message translates to:
  /// **'定时任务'**
  String get settingsCrons;

  /// No description provided for @settingsControlsRetentionAndColdStartCleanup.
  ///
  /// In zh_Hans, this message translates to:
  /// **'控制定时任务执行历史的保留与冷启动清理。清理 worker 仅在冷启动后异步运行一次，导致有超时兑底、独享运行锁、异常全部 silentLog，避免资源泄露与无限重试。'**
  String get settingsControlsRetentionAndColdStartCleanup;

  /// Internal feature brand name: Hermes Talker. Brand-style; transliterate only when natural.
  ///
  /// In zh_Hans, this message translates to:
  /// **'Hermes Talker'**
  String get settingsHermesTalker;

  /// No description provided for @settingsConfigureHermesTalkerSelfLearningEvery.
  ///
  /// In zh_Hans, this message translates to:
  /// **'配置 Hermes Talker 线程模板的自主学习：每 5 分钟扫描最近 7 天的会话，在后台派发受限子 Agent 更新记忆与技能。'**
  String get settingsConfigureHermesTalkerSelfLearningEvery;

  /// No description provided for @settingsEditor.
  ///
  /// In zh_Hans, this message translates to:
  /// **'编辑器'**
  String get settingsEditor;

  /// No description provided for @settingsManagePerLanguageLspBackendsInstall.
  ///
  /// In zh_Hans, this message translates to:
  /// **'管理各编程语言的 LSP 后端、安装根路径与下载辅助配置。保存后的配置会直接用于文件编辑器内的跳转、诊断、重命名和代码操作。'**
  String get settingsManagePerLanguageLspBackendsInstall;

  /// No description provided for @settingsAppData.
  ///
  /// In zh_Hans, this message translates to:
  /// **'应用数据'**
  String get settingsAppData;

  /// No description provided for @settingsPerResponseToolCallLimit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'单轮工具调用上限'**
  String get settingsPerResponseToolCallLimit;

  /// No description provided for @settingsSaveLimit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存上限'**
  String get settingsSaveLimit;

  /// No description provided for @settingsSequentialToolRoundLimit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'连续工具轮次上限'**
  String get settingsSequentialToolRoundLimit;

  /// No description provided for @settingsSessionSettings.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话设置'**
  String get settingsSessionSettings;

  /// No description provided for @settingsConfigureDefaultBehaviourForNewSessions.
  ///
  /// In zh_Hans, this message translates to:
  /// **'配置新会话的默认行为，包括超时时间、自动标题、默认模式与权限。'**
  String get settingsConfigureDefaultBehaviourForNewSessions;

  /// No description provided for @settingsSendTimeoutS.
  ///
  /// In zh_Hans, this message translates to:
  /// **'发送超时（秒）'**
  String get settingsSendTimeoutS;

  /// No description provided for @settingsMaximumWaitTimeToEstablishThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'建立 HTTP 连接并完成请求发送的最大等待时间，默认 60 秒。'**
  String get settingsMaximumWaitTimeToEstablishThe;

  /// No description provided for @settingsSaveTimeout.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存超时'**
  String get settingsSaveTimeout;

  /// No description provided for @settingsResponseTimeoutS.
  ///
  /// In zh_Hans, this message translates to:
  /// **'响应超时（秒）'**
  String get settingsResponseTimeoutS;

  /// No description provided for @settingsMaximumWaitForACompleteResponse.
  ///
  /// In zh_Hans, this message translates to:
  /// **'非流式请求等待完整响应的最大时间，默认 120 秒。'**
  String get settingsMaximumWaitForACompleteResponse;

  /// No description provided for @settingsStreamIdleTimeoutS.
  ///
  /// In zh_Hans, this message translates to:
  /// **'等待超时（秒）'**
  String get settingsStreamIdleTimeoutS;

  /// No description provided for @settingsMaximumIdleWaitBetweenStreamChunks.
  ///
  /// In zh_Hans, this message translates to:
  /// **'流式响应中两次数据块之间的最大空闲等待时间，超时将中断请求并显示\"Request timed out.\"，默认 120 秒。'**
  String get settingsMaximumIdleWaitBetweenStreamChunks;

  /// No description provided for @settingsAutoTitle.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动标题'**
  String get settingsAutoTitle;

  /// No description provided for @settingsWhenEnabledATitleIsAutomatically.
  ///
  /// In zh_Hans, this message translates to:
  /// **'开启后，新会话发送首条消息时将自动生成会话标题。'**
  String get settingsWhenEnabledATitleIsAutomatically;

  /// No description provided for @settingsDefaultSessionMode.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认会话模式'**
  String get settingsDefaultSessionMode;

  /// No description provided for @settingsDefaultInteractionModeForNewSessions.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新会话的默认交互模式：对话（Chat）或规划（Plan）。'**
  String get settingsDefaultInteractionModeForNewSessions;

  /// No description provided for @settingsChat.
  ///
  /// In zh_Hans, this message translates to:
  /// **'对话'**
  String get settingsChat;

  /// No description provided for @settingsPlan.
  ///
  /// In zh_Hans, this message translates to:
  /// **'规划'**
  String get settingsPlan;

  /// No description provided for @settingsDefaultFullAccess.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认全访问权限'**
  String get settingsDefaultFullAccess;

  /// No description provided for @settingsWhenEnabledNewSessionsStartIn.
  ///
  /// In zh_Hans, this message translates to:
  /// **'开启后，新会话将默认使用全访问权限模式，允许 AI 直接执行文件与命令操作而无需逐一确认。'**
  String get settingsWhenEnabledNewSessionsStartIn;

  /// No description provided for @settingsUserProfile.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户画像'**
  String get settingsUserProfile;

  /// No description provided for @settingsMaintainAGlobalUserProfileLanguage.
  ///
  /// In zh_Hans, this message translates to:
  /// **'维护用于全局会话的用户画像（语言风格、关注领域、交流偏好等）。设置非空时，所有线程模板的内建系统提示词都会自动携带画像上下文，使 AI 回复更贴近你的习惯；自我学习也会增量更新这份画像。'**
  String get settingsMaintainAGlobalUserProfileLanguage;

  /// No description provided for @settingsModelProviderManagement.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模型提供商管理'**
  String get settingsModelProviderManagement;

  /// No description provided for @settingsAddSelectTestAndMaintainModel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增、选择、测试并维护当前可用的模型提供商配置。每个提供商可包含多个模型。'**
  String get settingsAddSelectTestAndMaintainModel;

  /// No description provided for @settingsCompressionTrigger.
  ///
  /// In zh_Hans, this message translates to:
  /// **'压缩触发阈值'**
  String get settingsCompressionTrigger;

  /// No description provided for @settingsOnceTheUncompressedHistoryInA.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当线程中尚未被压缩的历史消息字符总数超过这个值时，系统会生成新的摘要检查点。'**
  String get settingsOnceTheUncompressedHistoryInA;

  /// No description provided for @settingsToolCallOutputCompressionThreshold.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具调用输出压缩阈值'**
  String get settingsToolCallOutputCompressionThreshold;

  /// No description provided for @settingsWhenAToolCallReturnsMore.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当某个工具调用返回的 raw 内容字符数超过该阈值时，OpenHand 会在拼装 conversation history 前将其压缩为「受影响路径+目的+首尾片段」的结构化摘要，释放 tokens。默认 1024。'**
  String get settingsWhenAToolCallReturnsMore;

  /// No description provided for @settingsDefaultsTo40IfOneAssistant.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 40 次。一次人机对话响应过程中，如果工具调用总次数超过这个阈值，系统会追加警告消息并安全终止本轮响应。'**
  String get settingsDefaultsTo40IfOneAssistant;

  /// No description provided for @settingsDefaultsTo24RoundsIfThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 24 轮。一次会话中，如果助手在工具执行后又连续请求下一轮工具，达到这个轮次数时系统会安全停止，避免陷入无限工具回环。'**
  String get settingsDefaultsTo24RoundsIfThe;

  /// No description provided for @settingsImageSizeLimit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'图片大小上限'**
  String get settingsImageSizeLimit;

  /// No description provided for @settingsDefaultsTo1mbImageAttachmentsLarger.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 1MB。用户附加的图片若超过这个大小，会在弹出图片编辑器之前先按比例自动压缩，并最终落盘到该上限以内，避免会话与提示词膨胀。'**
  String get settingsDefaultsTo1mbImageAttachmentsLarger;

  /// No description provided for @settingsCostControl.
  ///
  /// In zh_Hans, this message translates to:
  /// **'成本控制'**
  String get settingsCostControl;

  /// No description provided for @settingsReduceTokenCostsByFreezingThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'通过冻结 prompt 静态前缀与协议层缓存断点来降低 token 成本。开启后：新会话创建时会冻结当前的内建工具/技能/MCP/指令/记忆作为不可变前缀；用户发出首条消息后会锁定服务商与模型；Anthropic 协议会自动注入 cache_control 断点。'**
  String get settingsReduceTokenCostsByFreezingThe;

  /// No description provided for @settingsEnableInputCache.
  ///
  /// In zh_Hans, this message translates to:
  /// **'启用输入缓存'**
  String get settingsEnableInputCache;

  /// No description provided for @settingsDisabledByDefaultWhenEnabledEvery.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认关闭。开启后，对所有线程模板、所有模型，新会话创建时即冻结其 prompt 静态前缀（系统提示/工具定义/技能列表/MCP/指令/记忆）。会话创建之后再修改技能、MCP、记忆等不会影响已存在的会话——只对此后新建的会话生效，以保证最大不可变性，最大化输入缓存命中。'**
  String get settingsDisabledByDefaultWhenEnabledEvery;

  /// No description provided for @settingsCacheBreakpointUpdateMode.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缓存断点更新模式'**
  String get settingsCacheBreakpointUpdateMode;

  /// No description provided for @settingsChooseTheSlidingUnitForThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'决定动态缓存断点的滑动单位：按全部消息条数（user+assistant）/ 仅按用户消息条数 / 按累计 tokens 阈值。后两者更适合配合较小的更新间隔，前者更直观。'**
  String get settingsChooseTheSlidingUnitForThe;

  /// No description provided for @settingsByMessageCountUserAssistant.
  ///
  /// In zh_Hans, this message translates to:
  /// **'按消息条数 (user+assistant)'**
  String get settingsByMessageCountUserAssistant;

  /// No description provided for @settingsByUserMessageCountOnly.
  ///
  /// In zh_Hans, this message translates to:
  /// **'按用户消息条数'**
  String get settingsByUserMessageCountOnly;

  /// No description provided for @settingsByAccumulatedTokens.
  ///
  /// In zh_Hans, this message translates to:
  /// **'按累计 tokens'**
  String get settingsByAccumulatedTokens;

  /// No description provided for @settingsCacheBreakpointUpdateInterval.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缓存断点更新间隔'**
  String get settingsCacheBreakpointUpdateInterval;

  /// No description provided for @settingsDefault10MeaningDependsOnThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 10。含义随上方模式变化：消息条数 (1-50 推荐) / 用户消息条数 (1-30 推荐) / tokens 阈值 (建议 ≥1000)。'**
  String get settingsDefault10MeaningDependsOnThe;

  /// No description provided for @settingsSave.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存'**
  String get settingsSave;

  /// No description provided for @settingsCacheBreakpointCount.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缓存断点数量'**
  String get settingsCacheBreakpointCount;

  /// No description provided for @settingsDefault4Range14Anthropic.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 4，范围 1-4。Anthropic 协议每个请求最多支持 4 个 cache_control 断点。前 N-1 个用于静态前缀切片（系统提示/工具/技能/MCP/指令/记忆），第 N 个跟随上面的更新间隔在消息流中滑动。'**
  String get settingsDefault4Range14Anthropic;

  /// No description provided for @settingsCommandSafety.
  ///
  /// In zh_Hans, this message translates to:
  /// **'命令安全'**
  String get settingsCommandSafety;

  /// No description provided for @settingsControlWriteCommandConfirmationForBash.
  ///
  /// In zh_Hans, this message translates to:
  /// **'控制 bash 工具是否需要写命令确认，并集中管理禁止命令规则。'**
  String get settingsControlWriteCommandConfirmationForBash;

  /// No description provided for @settingsWriteCommandConfirmation.
  ///
  /// In zh_Hans, this message translates to:
  /// **'写命令确认'**
  String get settingsWriteCommandConfirmation;

  /// No description provided for @settingsEnabledByDefaultWhenTheAi.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认开启。AI 调用 bash 工具执行可能修改文件或系统状态的命令时，会先弹窗等待你确认。'**
  String get settingsEnabledByDefaultWhenTheAi;

  /// No description provided for @settingsAllowCommandList.
  ///
  /// In zh_Hans, this message translates to:
  /// **'允许命令列表'**
  String get settingsAllowCommandList;

  /// No description provided for @settingsMatchingWriteLikeBashCommandsSkip.
  ///
  /// In zh_Hans, this message translates to:
  /// **'匹配到的写类 bash 命令会跳过确认弹窗直接执行。只适合长期明确放行的稳定命令模式。'**
  String get settingsMatchingWriteLikeBashCommandsSkip;

  /// No description provided for @settingsAddAllowRule.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增允许规则'**
  String get settingsAddAllowRule;

  /// No description provided for @settingsNoAllowRulesConfigured.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前没有允许命令规则'**
  String get settingsNoAllowRulesConfigured;

  /// No description provided for @settingsAddARuleToLetMatching.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增规则后，匹配到的写命令将跳过确认弹窗。'**
  String get settingsAddARuleToLetMatching;

  /// No description provided for @settingsDenyCommandList.
  ///
  /// In zh_Hans, this message translates to:
  /// **'禁止命令列表'**
  String get settingsDenyCommandList;

  /// No description provided for @settingsMatchingBashCommandsAreBlockedBefore.
  ///
  /// In zh_Hans, this message translates to:
  /// **'匹配到的 bash 命令将不会真正执行，而是把“被用户禁止”这一结果直接返回给模型。支持正则和简单通配写法，例如 `rm *`。'**
  String get settingsMatchingBashCommandsAreBlockedBefore;

  /// No description provided for @settingsAddRule.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增规则'**
  String get settingsAddRule;

  /// No description provided for @settingsNoDenyRulesConfigured.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前没有禁止命令规则'**
  String get settingsNoDenyRulesConfigured;

  /// No description provided for @settingsAddARuleToBlockMatching.
  ///
  /// In zh_Hans, this message translates to:
  /// **'新增规则后，匹配到的 bash 命令会被直接拦截。'**
  String get settingsAddARuleToBlockMatching;

  /// No description provided for @settingsTelemetry.
  ///
  /// In zh_Hans, this message translates to:
  /// **'遥测'**
  String get settingsTelemetry;

  /// No description provided for @settingsWhenEnabledOpenhandCapturesRawAi.
  ///
  /// In zh_Hans, this message translates to:
  /// **'开启后会捕获每条 AI 消息的原始响应、请求参数、耗时、错误等调试数据，方便在消息/会话审计弹窗中排查问题。'**
  String get settingsWhenEnabledOpenhandCapturesRawAi;

  /// No description provided for @settingsDebugMode.
  ///
  /// In zh_Hans, this message translates to:
  /// **'开启调试'**
  String get settingsDebugMode;

  /// No description provided for @settingsOffByDefaultWhenEnabledEvery.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认关闭。开启后，在所有线程模板的消息卡片上鼠标悬停/聚焦时会显示【审计】按钮，会话顶部也会新增会话审计入口。'**
  String get settingsOffByDefaultWhenEnabledEvery;

  /// No description provided for @settingsCaptureRawPayload.
  ///
  /// In zh_Hans, this message translates to:
  /// **'捕获原始响应'**
  String get settingsCaptureRawPayload;

  /// No description provided for @settingsEnabledByDefaultOnlyActiveWhen.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认开启。仅当调试开启时生效，将 AI 响应的原始 JSON/SSE 片段一并写入消息元数据，便于审计。'**
  String get settingsEnabledByDefaultOnlyActiveWhen;

  /// No description provided for @settingsCaptureEnvironment.
  ///
  /// In zh_Hans, this message translates to:
  /// **'捕获环境数据'**
  String get settingsCaptureEnvironment;

  /// No description provided for @settingsOffByDefaultOnlyActiveWhen.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认关闭。仅当调试开启时生效。将工作目录、平台信息、进程环境变量（可能含敏感令牌）等写入消息元数据，便于深度排查，请谨慎开启。'**
  String get settingsOffByDefaultOnlyActiveWhen;

  /// No description provided for @settingsShortcutBindings.
  ///
  /// In zh_Hans, this message translates to:
  /// **'快捷键绑定'**
  String get settingsShortcutBindings;

  /// No description provided for @settingsClickRecordThenPressTheNew.
  ///
  /// In zh_Hans, this message translates to:
  /// **'点击录制后，按下新的组合键即可更新绑定。模型切换和会话切换会自动绕圈循环。'**
  String get settingsClickRecordThenPressTheNew;

  /// No description provided for @settingsAutoCleanupExecutionHistory.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动清理执行历史'**
  String get settingsAutoCleanupExecutionHistory;

  /// No description provided for @settingsOnEveryColdStartAnAsync.
  ///
  /// In zh_Hans, this message translates to:
  /// **'应用每次冷启动后，会异步启动一次清理 worker，删除超过保留天数的历史记录。worker 自带 single-flight、超时兜底与异常 silentLog，绝不无限重试或阻塞 UI。'**
  String get settingsOnEveryColdStartAnAsync;

  /// No description provided for @settingsEnableSelfLearning.
  ///
  /// In zh_Hans, this message translates to:
  /// **'启用自主学习'**
  String get settingsEnableSelfLearning;

  /// No description provided for @settingsWhenOffTheSchedulerSkipsEvery.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭后，后台调度器跳过所有 Hermes Talker 会话；系统 Cron 条目会保留但不再派发子 Agent。'**
  String get settingsWhenOffTheSchedulerSkipsEvery;

  /// No description provided for @settingsShowSelfLearningMessages.
  ///
  /// In zh_Hans, this message translates to:
  /// **'显示自我学习消息'**
  String get settingsShowSelfLearningMessages;

  /// No description provided for @settingsWhenOffSelfLearningCardsAre.
  ///
  /// In zh_Hans, this message translates to:
  /// **'关闭后，对话中不再展示\"自我学习\"卡片（后台学习仍会运行）。默认开启。'**
  String get settingsWhenOffSelfLearningCardsAre;

  /// No description provided for @settingsToolCatalogOverview.
  ///
  /// In zh_Hans, this message translates to:
  /// **'工具目录总览'**
  String get settingsToolCatalogOverview;

  /// No description provided for @settingsResetAll.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重置全部'**
  String get settingsResetAll;

  /// No description provided for @settingsEnableAll.
  ///
  /// In zh_Hans, this message translates to:
  /// **'全部启用'**
  String get settingsEnableAll;

  /// No description provided for @settingsDisableAll.
  ///
  /// In zh_Hans, this message translates to:
  /// **'全部禁用'**
  String get settingsDisableAll;

  /// No description provided for @settingsNoBuiltInToolConfigurations.
  ///
  /// In zh_Hans, this message translates to:
  /// **'没有内建工具配置'**
  String get settingsNoBuiltInToolConfigurations;

  /// No description provided for @settingsClickResetAllToRestoreThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'点击\"重置全部\"恢复默认工具列表。'**
  String get settingsClickResetAllToRestoreThe;

  /// No description provided for @settingsResetBuiltInToolConfigs.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重置内建工具配置'**
  String get settingsResetBuiltInToolConfigs;

  /// No description provided for @settingsCancel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'取消'**
  String get settingsCancel;

  /// No description provided for @settingsReset.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重置'**
  String get settingsReset;

  /// No description provided for @settingsDeleteCustomTool.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除自定义工具'**
  String get settingsDeleteCustomTool;

  /// No description provided for @settingsDelete.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除'**
  String get settingsDelete;

  /// No description provided for @settingsSendTimeoutSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'发送超时时间已保存。'**
  String get settingsSendTimeoutSaved;

  /// No description provided for @settingsResponseTimeoutSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'响应超时时间已保存。'**
  String get settingsResponseTimeoutSaved;

  /// No description provided for @settingsStreamIdleTimeoutSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'等待超时时间已保存。'**
  String get settingsStreamIdleTimeoutSaved;

  /// No description provided for @settingsCacheBreakpointUpdateIntervalSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缓存断点更新间隔已保存'**
  String get settingsCacheBreakpointUpdateIntervalSaved;

  /// No description provided for @settingsCacheBreakpointCountSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缓存断点数量已保存'**
  String get settingsCacheBreakpointCountSaved;

  /// No description provided for @settingsCacheBreakpointPositions.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缓存断点位置'**
  String get settingsCacheBreakpointPositions;

  /// No description provided for @settingsCacheBreakpointPositionsSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缓存断点位置已保存'**
  String get settingsCacheBreakpointPositionsSaved;

  /// No description provided for @cacheBarTopDescription.
  ///
  /// In zh_Hans, this message translates to:
  /// **'彩色段对应实际 prompt 各部分。拖动 P 插桩定位静态缓存断点；最右侧虚线插桩为动态断点（跟随更新间隔自动落点）。各段宽度仅作示意，并非真实 token 占比。'**
  String get cacheBarTopDescription;

  /// No description provided for @cacheBarSectionSysLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'[0] 系统指令'**
  String get cacheBarSectionSysLabel;

  /// No description provided for @cacheBarSectionDevLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'[1] 开发者指令'**
  String get cacheBarSectionDevLabel;

  /// No description provided for @cacheBarSectionToolsLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'[2] 工具目录'**
  String get cacheBarSectionToolsLabel;

  /// No description provided for @cacheBarSectionStateLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'[3] 会话状态'**
  String get cacheBarSectionStateLabel;

  /// No description provided for @cacheBarSectionMemoryLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'[4] 用户记忆'**
  String get cacheBarSectionMemoryLabel;

  /// No description provided for @cacheBarSectionUserInstLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'[4.5] 用户指令'**
  String get cacheBarSectionUserInstLabel;

  /// No description provided for @cacheBarSectionSummaryLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'[5] 会话摘要'**
  String get cacheBarSectionSummaryLabel;

  /// No description provided for @cacheBarSectionHistoryLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'历史消息'**
  String get cacheBarSectionHistoryLabel;

  /// No description provided for @cacheBarSectionLatestLabel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'[6] 最新消息'**
  String get cacheBarSectionLatestLabel;

  /// No description provided for @cacheBarSectionSysSummary.
  ///
  /// In zh_Hans, this message translates to:
  /// **'模板系统指令、工作区指令与运行时环境快照（OS / cwd / 仓库摘要）。'**
  String get cacheBarSectionSysSummary;

  /// No description provided for @cacheBarSectionSysCacheHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缓存友好：跨轮极稳定，最适合作为第一个断点。'**
  String get cacheBarSectionSysCacheHint;

  /// No description provided for @cacheBarSectionDevSummary.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前提示词模板的开发者指令（行为规则与输出格式约束）。'**
  String get cacheBarSectionDevSummary;

  /// No description provided for @cacheBarSectionDevCacheHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缓存友好：会话内极少变动。'**
  String get cacheBarSectionDevCacheHint;

  /// No description provided for @cacheBarSectionToolsSummary.
  ///
  /// In zh_Hans, this message translates to:
  /// **'内置工具目录、MCP 能力与 Skill 加载器（含 DSML 调用约束）。'**
  String get cacheBarSectionToolsSummary;

  /// No description provided for @cacheBarSectionToolsCacheHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'较稳定：除非工具注册表变化，否则可放心命中缓存。'**
  String get cacheBarSectionToolsCacheHint;

  /// No description provided for @cacheBarSectionStateSummary.
  ///
  /// In zh_Hans, this message translates to:
  /// **'会话元数据 JSON：计数器、Todo、计划标记、附件等。'**
  String get cacheBarSectionStateSummary;

  /// No description provided for @cacheBarSectionStateCacheHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'易变：每轮计数器都会更新，断点放此处易失效。'**
  String get cacheBarSectionStateCacheHint;

  /// No description provided for @cacheBarSectionMemorySummary.
  ///
  /// In zh_Hans, this message translates to:
  /// **'长期用户记忆事实，作为已掌握的常识自然融入。'**
  String get cacheBarSectionMemorySummary;

  /// No description provided for @cacheBarSectionMemoryCacheHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'相对稳定：仅在记忆条目变更时才会失效。'**
  String get cacheBarSectionMemoryCacheHint;

  /// No description provided for @cacheBarSectionUserInstSummary.
  ///
  /// In zh_Hans, this message translates to:
  /// **'用户预设的可复用指令片段（项目级权威指引）。'**
  String get cacheBarSectionUserInstSummary;

  /// No description provided for @cacheBarSectionUserInstCacheHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'稳定：极少修改，断点落在它后面较稳妥。'**
  String get cacheBarSectionUserInstCacheHint;

  /// No description provided for @cacheBarSectionSummarySummary.
  ///
  /// In zh_Hans, this message translates to:
  /// **'较早会话的压缩摘要 + 最近聊天纪要。'**
  String get cacheBarSectionSummarySummary;

  /// No description provided for @cacheBarSectionSummaryCacheHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'缓慢演化：仅在压缩重生成时刷新。'**
  String get cacheBarSectionSummaryCacheHint;

  /// No description provided for @cacheBarSectionHistorySummary.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前会话中的历史消息（用户 / 助手 / 工具结果）。'**
  String get cacheBarSectionHistorySummary;

  /// No description provided for @cacheBarSectionHistoryCacheHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'仅追加：放在历史中段的断点能跨多轮命中尾部新增内容。'**
  String get cacheBarSectionHistoryCacheHint;

  /// No description provided for @cacheBarSectionLatestSummary.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前正在回答的用户消息（含附件元数据）。'**
  String get cacheBarSectionLatestSummary;

  /// No description provided for @cacheBarSectionLatestCacheHint.
  ///
  /// In zh_Hans, this message translates to:
  /// **'每轮变化：动态断点正是为命中此段而设。'**
  String get cacheBarSectionLatestCacheHint;

  /// No description provided for @cacheBarDynamicTooltip.
  ///
  /// In zh_Hans, this message translates to:
  /// **'动态断点：跟随缓存更新间隔自动落点。'**
  String get cacheBarDynamicTooltip;

  /// No description provided for @cacheBarDynamicSuffix.
  ///
  /// In zh_Hans, this message translates to:
  /// **'（动态）'**
  String get cacheBarDynamicSuffix;

  /// No description provided for @cacheBarResetEven.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重置为均匀分布'**
  String get cacheBarResetEven;

  /// No description provided for @settingsAiBudgetUsdPerSession.
  ///
  /// In zh_Hans, this message translates to:
  /// **'单会话预算（USD）'**
  String get settingsAiBudgetUsdPerSession;

  /// No description provided for @settingsAiBudgetUsdPerSessionBody.
  ///
  /// In zh_Hans, this message translates to:
  /// **'0 表示关闭。当某个会话累计估算成本超过该上限时，会话元数据对话框中会以警示色提示，仅作软提醒，不会中断对话或限制发送。'**
  String get settingsAiBudgetUsdPerSessionBody;

  /// No description provided for @settingsAiBudgetUsdPerSessionInvalid.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 0 到 100000 之间的非负数。'**
  String get settingsAiBudgetUsdPerSessionInvalid;

  /// No description provided for @settingsAiBudgetUsdPerSessionSaved.
  ///
  /// In zh_Hans, this message translates to:
  /// **'单会话预算已保存'**
  String get settingsAiBudgetUsdPerSessionSaved;

  /// No description provided for @sessionMetadataOverBudgetNotice.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前会话估算成本 {total} 已超出预算 {budget}。仅作提醒，不影响发送。'**
  String sessionMetadataOverBudgetNotice(String total, String budget);

  /// No description provided for @settingsEnterAToolCallLimitGreater.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入大于 0 的工具调用上限。'**
  String get settingsEnterAToolCallLimitGreater;

  /// No description provided for @settingsThePerResponseToolCallLimit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'单轮工具调用上限已保存。'**
  String get settingsThePerResponseToolCallLimit;

  /// No description provided for @settingsEnterASequentialToolRoundLimit.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入大于 0 的连续工具轮次上限。'**
  String get settingsEnterASequentialToolRoundLimit;

  /// No description provided for @settingsTheSequentialToolRoundLimitHas.
  ///
  /// In zh_Hans, this message translates to:
  /// **'连续工具轮次上限已保存。'**
  String get settingsTheSequentialToolRoundLimitHas;

  /// No description provided for @settingsDeleteDenyRule.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除禁止命令规则'**
  String get settingsDeleteDenyRule;

  /// No description provided for @settingsTheDenyCommandRuleHasBeen.
  ///
  /// In zh_Hans, this message translates to:
  /// **'禁止命令规则已删除。'**
  String get settingsTheDenyCommandRuleHasBeen;

  /// No description provided for @settingsDeleteAllowRule.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除允许命令规则'**
  String get settingsDeleteAllowRule;

  /// No description provided for @settingsTheAllowCommandRuleHasBeen.
  ///
  /// In zh_Hans, this message translates to:
  /// **'允许命令规则已删除。'**
  String get settingsTheAllowCommandRuleHasBeen;

  /// No description provided for @settingsTheShortcutHasBeenUpdated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'快捷键已更新。'**
  String get settingsTheShortcutHasBeenUpdated;

  /// No description provided for @settingsTheEditorShortcutHasBeenUpdated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'编辑器快捷键已更新。'**
  String get settingsTheEditorShortcutHasBeenUpdated;

  /// No description provided for @settingsSendMessage.
  ///
  /// In zh_Hans, this message translates to:
  /// **'发送消息'**
  String get settingsSendMessage;

  /// No description provided for @settingsCollapseOrExpandComposer.
  ///
  /// In zh_Hans, this message translates to:
  /// **'折叠或展开输入框'**
  String get settingsCollapseOrExpandComposer;

  /// No description provided for @settingsPreviousModel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'上一个模型'**
  String get settingsPreviousModel;

  /// No description provided for @settingsNextModel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'下一个模型'**
  String get settingsNextModel;

  /// No description provided for @settingsToggleAutoFollow.
  ///
  /// In zh_Hans, this message translates to:
  /// **'开关自动滚动'**
  String get settingsToggleAutoFollow;

  /// No description provided for @settingsPreviousSession.
  ///
  /// In zh_Hans, this message translates to:
  /// **'上一个会话'**
  String get settingsPreviousSession;

  /// No description provided for @settingsNextSession.
  ///
  /// In zh_Hans, this message translates to:
  /// **'下一个会话'**
  String get settingsNextSession;

  /// No description provided for @settingsSaveFile.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存文件'**
  String get settingsSaveFile;

  /// No description provided for @settingsTriggerCompletion.
  ///
  /// In zh_Hans, this message translates to:
  /// **'触发智能补全'**
  String get settingsTriggerCompletion;

  /// No description provided for @settingsShowSignatureHelp.
  ///
  /// In zh_Hans, this message translates to:
  /// **'显示签名帮助'**
  String get settingsShowSignatureHelp;

  /// No description provided for @settingsFind.
  ///
  /// In zh_Hans, this message translates to:
  /// **'查找'**
  String get settingsFind;

  /// No description provided for @settingsFindAndReplace.
  ///
  /// In zh_Hans, this message translates to:
  /// **'查找替换'**
  String get settingsFindAndReplace;

  /// No description provided for @settingsGoToLine.
  ///
  /// In zh_Hans, this message translates to:
  /// **'跳转到行'**
  String get settingsGoToLine;

  /// No description provided for @settingsDocumentSymbols.
  ///
  /// In zh_Hans, this message translates to:
  /// **'文档符号'**
  String get settingsDocumentSymbols;

  /// No description provided for @settingsWorkspaceSymbols.
  ///
  /// In zh_Hans, this message translates to:
  /// **'全局符号'**
  String get settingsWorkspaceSymbols;

  /// No description provided for @settingsGoToDefinition.
  ///
  /// In zh_Hans, this message translates to:
  /// **'跳转到定义'**
  String get settingsGoToDefinition;

  /// No description provided for @settingsFindReferences.
  ///
  /// In zh_Hans, this message translates to:
  /// **'查找引用'**
  String get settingsFindReferences;

  /// No description provided for @settingsGoToImplementation.
  ///
  /// In zh_Hans, this message translates to:
  /// **'跳转到实现'**
  String get settingsGoToImplementation;

  /// No description provided for @settingsShowHoverInfo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'显示悬浮信息'**
  String get settingsShowHoverInfo;

  /// No description provided for @settingsRenameSymbol.
  ///
  /// In zh_Hans, this message translates to:
  /// **'重命名符号'**
  String get settingsRenameSymbol;

  /// No description provided for @settingsCodeActions.
  ///
  /// In zh_Hans, this message translates to:
  /// **'代码操作'**
  String get settingsCodeActions;

  /// No description provided for @settingsFormatDocument.
  ///
  /// In zh_Hans, this message translates to:
  /// **'格式化文档'**
  String get settingsFormatDocument;

  /// No description provided for @settingsDefaultsToCtrlEnterAndTriggers.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 Ctrl + Enter，仅在聊天输入框准备好时触发发送按钮。'**
  String get settingsDefaultsToCtrlEnterAndTriggers;

  /// No description provided for @settingsDefaultsToCtrlPForQuickly.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 Ctrl + P，用于快速折叠或展开输入框。'**
  String get settingsDefaultsToCtrlPForQuickly;

  /// No description provided for @settingsDefaultsToCtrlLeftAndWraps.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 Ctrl + ←，向前切换模型，切到头后自动绕回末尾。'**
  String get settingsDefaultsToCtrlLeftAndWraps;

  /// No description provided for @settingsDefaultsToCtrlRightAndWraps.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 Ctrl + →，向后切换模型，切到末尾后自动绕回开头。'**
  String get settingsDefaultsToCtrlRightAndWraps;

  /// No description provided for @settingsDefaultsToCtrlSForToggling.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 Ctrl + S，开关自动滚动模式。'**
  String get settingsDefaultsToCtrlSForToggling;

  /// No description provided for @settingsDefaultsToCtrlUpAndWraps.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 Ctrl + ↑，切换到上一个会话并支持绕圈。'**
  String get settingsDefaultsToCtrlUpAndWraps;

  /// No description provided for @settingsDefaultsToCtrlDownAndWraps.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 Ctrl + ↓，切换到下一个会话并支持绕圈。'**
  String get settingsDefaultsToCtrlDownAndWraps;

  /// No description provided for @auditDeleteMessage.
  ///
  /// In zh_Hans, this message translates to:
  /// **'删除消息'**
  String get auditDeleteMessage;

  /// No description provided for @auditDeleteThisMessageThisCannotBe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'确认删除该消息？此操作不可撤销。'**
  String get auditDeleteThisMessageThisCannotBe;

  /// No description provided for @auditCancel.
  ///
  /// In zh_Hans, this message translates to:
  /// **'取消'**
  String get auditCancel;

  /// No description provided for @settingsManageTheBuiltInAiTools.
  ///
  /// In zh_Hans, this message translates to:
  /// **'管理应用内置的 AI 内建工具。可调整每个工具的启用状态、名称、描述、Schema、优先级、排序、加载策略和其他参数。'**
  String get settingsManageTheBuiltInAiTools;

  /// No description provided for @settingsManageTheLocalFilesAndDatabase.
  ///
  /// In zh_Hans, this message translates to:
  /// **'管理 OpenHand 在本地占用的文件与数据库体积。所有清理动作都在后台 worker 中运行，不会阻塞主线程；每个分类均需二次确认后才会真正删除。'**
  String get settingsManageTheLocalFilesAndDatabase;

  /// No description provided for @settingsThisWillRestoreAllBuiltIn.
  ///
  /// In zh_Hans, this message translates to:
  /// **'这将把所有内建工具配置恢复为出厂默认值，包括名称、描述、Schema 覆盖、优先级、排序和加载策略。此操作不可撤销。'**
  String get settingsThisWillRestoreAllBuiltIn;

  /// No description provided for @tlCallUnwrap.
  ///
  /// In zh_Hans, this message translates to:
  /// **'取消换行'**
  String get tlCallUnwrap;

  /// No description provided for @tlCallWrapLines.
  ///
  /// In zh_Hans, this message translates to:
  /// **'自动换行'**
  String get tlCallWrapLines;

  /// No description provided for @tlCallViewCompressedContent.
  ///
  /// In zh_Hans, this message translates to:
  /// **'查看压缩内容'**
  String get tlCallViewCompressedContent;

  /// No description provided for @tlCallViewFullContent.
  ///
  /// In zh_Hans, this message translates to:
  /// **'查看完整内容'**
  String get tlCallViewFullContent;

  /// No description provided for @tlCallMultiEditEditcount.
  ///
  /// In zh_Hans, this message translates to:
  /// **'多处编辑 ×{editCount}'**
  String tlCallMultiEditEditcount(Object editCount);

  /// No description provided for @tlCallPreparing.
  ///
  /// In zh_Hans, this message translates to:
  /// **'准备执行'**
  String get tlCallPreparing;

  /// No description provided for @tlCallPreparingAlt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'准备调用'**
  String get tlCallPreparingAlt;

  /// No description provided for @tlCallRunningAlt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'调用中'**
  String get tlCallRunningAlt;

  /// No description provided for @tlCallCompleted.
  ///
  /// In zh_Hans, this message translates to:
  /// **'执行完成'**
  String get tlCallCompleted;

  /// No description provided for @tlCallCompletedAlt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'调用完成'**
  String get tlCallCompletedAlt;

  /// No description provided for @tlCallTimedOutAlt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'调用超时'**
  String get tlCallTimedOutAlt;

  /// No description provided for @tlCallFailedAlt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'调用失败'**
  String get tlCallFailedAlt;

  /// No description provided for @tlCallFailedToOpenFileLocationError.
  ///
  /// In zh_Hans, this message translates to:
  /// **'打开文件位置失败：{error}'**
  String tlCallFailedToOpenFileLocationError(Object error);

  /// No description provided for @tlCallMemoryitemsLengthMemoriesUpdated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{memoryItems_length} 条记忆已更新'**
  String tlCallMemoryitemsLengthMemoriesUpdated(Object memoryItems_length);

  /// No description provided for @tlCallProfileitemsLengthProfileChanges.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{profileItems_length} 项画像已更新'**
  String tlCallProfileitemsLengthProfileChanges(Object profileItems_length);

  /// No description provided for @tlCallSkillitemsLengthSkillsUpdated.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{skillItems_length} 个技能已更新'**
  String tlCallSkillitemsLengthSkillsUpdated(Object skillItems_length);

  /// No description provided for @tlCallAiThinkingStreaming.
  ///
  /// In zh_Hans, this message translates to:
  /// **'AI 思考（生成中）'**
  String get tlCallAiThinkingStreaming;

  /// No description provided for @tlCallAiThinking.
  ///
  /// In zh_Hans, this message translates to:
  /// **'AI 思考'**
  String get tlCallAiThinking;

  /// No description provided for @tlCallAiResponseStreaming.
  ///
  /// In zh_Hans, this message translates to:
  /// **'AI 响应（生成中）'**
  String get tlCallAiResponseStreaming;

  /// No description provided for @tlCallAiResponse.
  ///
  /// In zh_Hans, this message translates to:
  /// **'AI 响应'**
  String get tlCallAiResponse;

  /// No description provided for @tlCallAndItemsLength3More.
  ///
  /// In zh_Hans, this message translates to:
  /// **' 等 {items_length} 项'**
  String tlCallAndItemsLength3More(Object items_length_3, Object items_length);

  /// No description provided for @tlCallSecondsSAgo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{seconds}秒前'**
  String tlCallSecondsSAgo(Object seconds);

  /// No description provided for @tlCallMinutesMAgo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{minutes}分钟前'**
  String tlCallMinutesMAgo(Object minutes);

  /// No description provided for @tlCallHoursHAgo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{hours}小时前'**
  String tlCallHoursHAgo(Object hours);

  /// No description provided for @tlCallDaysDAgo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'{days}天前'**
  String tlCallDaysDAgo(Object days);

  /// No description provided for @sessMetaPlanPlanindex.
  ///
  /// In zh_Hans, this message translates to:
  /// **'计划 #{planIndex}'**
  String sessMetaPlanPlanindex(Object planIndex);

  /// No description provided for @sessMetaTheCurrentSequentialToolRoundLimit.
  ///
  /// In zh_Hans, this message translates to:
  /// **' 当前连续工具轮次上限为 {configuredLimit}。'**
  String sessMetaTheCurrentSequentialToolRoundLimit(Object configuredLimit);

  /// No description provided for @auditInvalidJsonErrorMessage.
  ///
  /// In zh_Hans, this message translates to:
  /// **'JSON 解析失败：{error_message}'**
  String auditInvalidJsonErrorMessage(Object error_message);

  /// No description provided for @auditSaveFailedError.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保存失败：{error}'**
  String auditSaveFailedError(Object error);

  /// No description provided for @auditRecentErrorsSessionRecenterrorsLength.
  ///
  /// In zh_Hans, this message translates to:
  /// **'最近错误 ({session_recentErrors_length})'**
  String auditRecentErrorsSessionRecenterrorsLength(
    Object session_recentErrors_length,
  );

  /// No description provided for @auditMessagesSessionMessagesLength.
  ///
  /// In zh_Hans, this message translates to:
  /// **'消息列表 ({session_messages_length})'**
  String auditMessagesSessionMessagesLength(Object session_messages_length);

  /// No description provided for @progExpFEAppliedEditsLengthFormattingEdits.
  ///
  /// In zh_Hans, this message translates to:
  /// **'已应用 {edits_length} 处格式化修改。'**
  String progExpFEAppliedEditsLengthFormattingEdits(Object edits_length);

  /// No description provided for @progExpFEFormatTheCurrentFileFormatshortcut.
  ///
  /// In zh_Hans, this message translates to:
  /// **'格式化当前文件 ({formatShortcut})'**
  String progExpFEFormatTheCurrentFileFormatshortcut(Object formatShortcut);

  /// No description provided for @progExpFENoCodeactionkindRefactoringIsAvailableAt.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前位置没有可用的\"{codeActionKind}\"重构操作。'**
  String progExpFENoCodeactionkindRefactoringIsAvailableAt(
    Object codeActionKind,
  );

  /// No description provided for @progExpFEHideFileBrowser.
  ///
  /// In zh_Hans, this message translates to:
  /// **'隐藏文件浏览器'**
  String get progExpFEHideFileBrowser;

  /// No description provided for @progExpFEShowFileBrowser.
  ///
  /// In zh_Hans, this message translates to:
  /// **'显示文件浏览器'**
  String get progExpFEShowFileBrowser;

  /// No description provided for @settingsRetentionWindowRetentionDayS.
  ///
  /// In zh_Hans, this message translates to:
  /// **'保留天数：{retention} 天'**
  String settingsRetentionWindowRetentionDayS(Object retention);

  /// No description provided for @settingsRangeMinrMaxrDaysDefault7.
  ///
  /// In zh_Hans, this message translates to:
  /// **'范围 {minR}–{maxR} 天，默认 7 天。下次冷启动时生效。'**
  String settingsRangeMinrMaxrDaysDefault7(Object minR, Object maxR);

  /// No description provided for @settingsConcurrentWorkersConcurrency.
  ///
  /// In zh_Hans, this message translates to:
  /// **'并发 Worker 数：{concurrency}'**
  String settingsConcurrentWorkersConcurrency(Object concurrency);

  /// No description provided for @settingsCapsHowManySessionsCanBe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'限制单轮 tick 同时派发的会话数 ({minC}–{maxC})。默认 5。'**
  String settingsCapsHowManySessionsCanBe(Object minC, Object maxC);

  /// No description provided for @settingsSortedLengthBuiltInToolsEnabledcount.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前共 {sorted_length} 个内建工具，已启用 {enabledCount} 个。可调整每个工具的名称、描述、Schema、优先级、排序和加载策略等。'**
  String settingsSortedLengthBuiltInToolsEnabledcount(
    Object sorted_length,
    Object enabledCount,
  );

  /// No description provided for @settingsAreYouSureYouWantTo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'确定要删除 \"{config_effectiveName}\" 吗？此操作不可撤销。'**
  String settingsAreYouSureYouWantTo(Object config_effectiveName);

  /// No description provided for @settingsEnterAValueBetweenMinAnd.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 {min}–{max} 之间的秒数。'**
  String settingsEnterAValueBetweenMinAnd(Object min, Object max);

  /// No description provided for @settingsPleaseEnterAnIntegerBetweenAppsettingssn.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 {AppSettingsSnapshot_minAiInputCacheUpdateInterval} 到 {AppSettingsSnapshot_maxAiInputCacheUpdateInterval} 之间的整数'**
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn(
    Object AppSettingsSnapshot_minAiInputCacheUpdateInterval,
    Object AppSettingsSnapshot_maxAiInputCacheUpdateInterval,
  );

  /// No description provided for @settingsPleaseEnterAnIntegerBetweenAppsettingssn2.
  ///
  /// In zh_Hans, this message translates to:
  /// **'请输入 {AppSettingsSnapshot_minAiInputCacheBreakpointCount} 到 {AppSettingsSnapshot_maxAiInputCacheBreakpointCount} 之间的整数'**
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn2(
    Object AppSettingsSnapshot_minAiInputCacheBreakpointCount,
    Object AppSettingsSnapshot_maxAiInputCacheBreakpointCount,
  );

  /// No description provided for @settingsDragTheThumbcountThumbsToPosition.
  ///
  /// In zh_Hans, this message translates to:
  /// **'拖动 {thumbCount} 个圆点自定义前 N-1 个静态断点在消息流中的位置（百分比 0%-100%）。最后一个断点固定在末尾消息（带锁图标的圆点），不可拖动。点击「重置」恢复均匀分布。'**
  String settingsDragTheThumbcountThumbsToPosition(Object thumbCount);

  /// No description provided for @settingsTheDenyCommandRuleHasBeen2.
  ///
  /// In zh_Hans, this message translates to:
  /// **'禁止命令规则已更新。'**
  String get settingsTheDenyCommandRuleHasBeen2;

  /// No description provided for @settingsTheAllowCommandRuleHasBeen2.
  ///
  /// In zh_Hans, this message translates to:
  /// **'允许命令规则已更新。'**
  String get settingsTheAllowCommandRuleHasBeen2;

  /// No description provided for @settingsDefaultsToDefaultlabelAndSavesThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，保存当前正在编辑的文件。'**
  String settingsDefaultsToDefaultlabelAndSavesThe(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndOpensThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，主动弹出智能补全候选列表。'**
  String settingsDefaultsToDefaultlabelAndOpensThe(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndShowsMethod.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，显示当前调用位置的方法签名、参数解释和文档摘要。'**
  String settingsDefaultsToDefaultlabelAndShowsMethod(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndTogglesThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，打开或关闭查找面板。'**
  String settingsDefaultsToDefaultlabelAndTogglesThe(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndTogglesThe2.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，打开或关闭替换面板。'**
  String settingsDefaultsToDefaultlabelAndTogglesThe2(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndTogglesThe3.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，打开或关闭跳转到行面板。'**
  String settingsDefaultsToDefaultlabelAndTogglesThe3(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndTogglesThe4.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，打开或关闭当前文件的符号列表。'**
  String settingsDefaultsToDefaultlabelAndTogglesThe4(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndTogglesThe5.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，打开或关闭全局符号检索面板。'**
  String settingsDefaultsToDefaultlabelAndTogglesThe5(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndJumpsTo.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，跳转到当前符号定义。'**
  String settingsDefaultsToDefaultlabelAndJumpsTo(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndFindsReferences.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，查找当前符号的引用位置。'**
  String settingsDefaultsToDefaultlabelAndFindsReferences(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndJumpsTo2.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，跳转到当前符号的实现位置。'**
  String settingsDefaultsToDefaultlabelAndJumpsTo2(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndShowsType.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，显示当前位置的类型或文档信息。'**
  String settingsDefaultsToDefaultlabelAndShowsType(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndStartsRename.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，发起当前符号重命名。'**
  String settingsDefaultsToDefaultlabelAndStartsRename(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndShowsAvailable.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，显示可用的代码操作列表。'**
  String settingsDefaultsToDefaultlabelAndShowsAvailable(Object defaultLabel);

  /// No description provided for @settingsDefaultsToDefaultlabelAndFormatsThe.
  ///
  /// In zh_Hans, this message translates to:
  /// **'默认 {defaultLabel}，格式化当前编程文件；当选中多行时，Shift+Tab 仍优先执行反向缩进。'**
  String settingsDefaultsToDefaultlabelAndFormatsThe(Object defaultLabel);

  /// No description provided for @progExpFEResolvedLspBackendForCurrentFile.
  ///
  /// In zh_Hans, this message translates to:
  /// **'当前文件已解析到 {lspName}。\n项目语言：{projLang}\n当前文件语言：{fileLang}\n{modeLine}\n{sdkSourceLine}\n{lspSourceLine}\n工作区：{rootPath}\n命令：{command}'**
  String progExpFEResolvedLspBackendForCurrentFile(
    Object lspName,
    Object projLang,
    Object fileLang,
    Object modeLine,
    Object sdkSourceLine,
    Object lspSourceLine,
    Object rootPath,
    Object command,
  );

  /// Settings → General: label for the global reduce-motion switch.
  ///
  /// In zh_Hans, this message translates to:
  /// **'减少动画'**
  String get settingsReduceMotionLabel;

  /// Settings → General: subtitle for the reduce-motion switch.
  ///
  /// In zh_Hans, this message translates to:
  /// **'开启后，自研动画与 Flutter 内建动画的时长全部归零。与系统层「减少动画」辅助功能并联生效。'**
  String get settingsReduceMotionBody;
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
