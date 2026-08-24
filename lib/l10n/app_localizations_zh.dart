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
  String get threadsLoadMore => '加载更多线程';

  @override
  String get composerHint => '询问 OpenHand 任何内容，使用 / 触发动作，使用 @ 引用上下文';

  @override
  String get composerSend => '发送';

  @override
  String get chatSending => '发送中';

  @override
  String get chatRequestFailed => '模型请求失败，请检查模型配置、网络连通性或接口协议。';

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
  String get exportProgressCancelling => '正在取消…';

  @override
  String get readerFileTypeText => '纯文本';

  @override
  String get readerFileTypeCode => '代码';

  @override
  String knowledgeReaderNoModelForType(Object type) {
    return '没有可读取 $type 的 reader 模型。';
  }

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
  String get mcpStdioCacheResetAction => '重置 stdio 包缓存';

  @override
  String get mcpStdioCacheResetConfirmTitle => '重置 stdio 隔离包缓存？';

  @override
  String get mcpStdioCacheResetConfirmBody =>
      '将删除 ~/.openhand/mcp/package-cache 下的 npm/uv/pip 等隔离缓存。下次启动 stdio MCP 服务会重新下载依赖。不影响全局 ~/.npm 。';

  @override
  String get mcpStdioCacheResetConfirm => '重置';

  @override
  String get mcpStdioCacheResetCancel => '取消';

  @override
  String get mcpStdioCacheResetDone => '隔离缓存已重置。';

  @override
  String get mcpStdioCacheResetFailed =>
      '重置失败，请手动删除 ~/.openhand/mcp/package-cache。';

  @override
  String get pluginServiceTitle => '插件';

  @override
  String get pluginServiceSubtitle =>
      '管理可选插件的安装、更新与卸载。插件为 OpenHand 提供额外的运行时能力。';

  @override
  String get pluginServiceRescan => '重新扫描';

  @override
  String get pluginServiceScanning => '正在扫描本机插件环境…';

  @override
  String get pluginServiceScanFailed => '插件扫描失败';

  @override
  String get pluginServiceActionInstall => '安装';

  @override
  String get pluginServiceActionUpdate => '更新';

  @override
  String get pluginServiceActionUninstall => '卸载';

  @override
  String get pluginServiceActionEnable => '启用';

  @override
  String get pluginServiceActionDisable => '禁用';

  @override
  String get pluginServiceStatusInstalled => '已安装';

  @override
  String get pluginServiceStatusNotInstalled => '未安装';

  @override
  String get pluginServiceStatusInstalling => '安装中…';

  @override
  String get pluginServiceStatusUpdating => '更新中…';

  @override
  String get pluginServiceStatusUninstalling => '卸载中…';

  @override
  String get pluginServiceStatusError => '错误';

  @override
  String get pluginServiceCheckUpdates => '检查更新';

  @override
  String get pluginServiceMcpService => 'MCP 服务';

  @override
  String pluginServiceInstallDependencyRequired(Object dependency) {
    return '需要先安装 $dependency';
  }

  @override
  String pluginServiceInstallConfirmTitle(Object plugin) {
    return '安装 $plugin？';
  }

  @override
  String pluginServiceInstallConfirmMessage(Object plugin) {
    return '将在本机安装 $plugin，可能需要下载依赖文件。';
  }

  @override
  String pluginServiceInstallSuccess(Object plugin) {
    return '$plugin 安装成功';
  }

  @override
  String pluginServiceInstallFailure(Object plugin) {
    return '$plugin 安装失败';
  }

  @override
  String pluginServiceUpdateConfirmTitle(Object plugin) {
    return '更新 $plugin？';
  }

  @override
  String pluginServiceUpdateConfirmMessage(
    Object plugin,
    Object currentVersion,
    Object latestVersion,
  ) {
    return '将 $plugin 从 $currentVersion 更新到 $latestVersion。';
  }

  @override
  String pluginServiceUpdateSuccess(Object plugin) {
    return '$plugin 更新成功';
  }

  @override
  String pluginServiceUpdateFailure(Object plugin) {
    return '$plugin 更新失败';
  }

  @override
  String get pluginServiceCheckUpdateFailed => '检查更新失败';

  @override
  String pluginServiceNewVersionAvailable(Object version) {
    return '发现新版本：$version';
  }

  @override
  String get pluginServiceNoUpdatesAvailable => '未发现新版本';

  @override
  String pluginServiceUninstallBlocked(Object dependent, Object plugin) {
    return '$dependent 依赖 $plugin，请先卸载 $dependent';
  }

  @override
  String pluginServiceUninstallConfirmTitle(Object plugin) {
    return '卸载 $plugin？';
  }

  @override
  String pluginServiceUninstallConfirmMessage(Object plugin) {
    return '将从本机卸载 $plugin，此操作不可撤销。';
  }

  @override
  String pluginServiceUninstallSuccess(Object plugin) {
    return '$plugin 已卸载';
  }

  @override
  String pluginServiceUninstallFailure(Object plugin) {
    return '$plugin 卸载失败';
  }

  @override
  String pluginServiceOperationTitle(Object action, Object plugin) {
    return '$action $plugin';
  }

  @override
  String get pluginServiceRuntimePid => 'PID';

  @override
  String get pluginServiceRuntimeOs => 'OS';

  @override
  String get pluginServiceRuntimeArch => '架构';

  @override
  String pluginServiceLogLineCount(Object count) {
    return '日志：$count 行';
  }

  @override
  String get pluginServiceWaitingForOutput => '等待输出…';

  @override
  String get pluginServiceExecuting => '正在执行…';

  @override
  String get pluginServiceCompleted => '操作完成';

  @override
  String get pluginServiceVersion => '版本';

  @override
  String get pluginServiceUpdateAvailable => '可更新到';

  @override
  String get pluginServiceDependsOn => '依赖';

  @override
  String get pluginServiceRequiredBy => '被依赖';

  @override
  String get pluginServiceNone => '无';

  @override
  String pluginServiceDetailTitle(Object plugin) {
    return '$plugin 详情';
  }

  @override
  String get pluginServiceDetailBasicInfo => '基本信息';

  @override
  String get pluginServiceDetailName => '名称';

  @override
  String get pluginServiceDetailDescription => '描述';

  @override
  String get pluginServiceDetailStatus => '状态';

  @override
  String get pluginServiceDetailEnvironment => '环境信息';

  @override
  String get pluginServiceDetailFileSystem => '文件系统';

  @override
  String get pluginServiceDetailDependencies => '依赖关系';

  @override
  String get pluginServiceThreadTemplates => '线程模板关联';

  @override
  String get pluginServiceTemplates => '关联模板';

  @override
  String get pluginServiceMcpPackage => 'MCP 包';

  @override
  String get pluginServiceMcpBrowserDescription => '提供浏览器自动化能力的 MCP 服务';

  @override
  String get pluginServiceDetailProcessors => '处理器数';

  @override
  String get pluginServiceDetailInstallPath => '安装路径';

  @override
  String get pluginServiceDetailInstallationTarget => '安装目标';

  @override
  String get pluginServiceDetailInstallMethod => '安装方式';

  @override
  String get pluginServiceDetailTargetOs => '目标操作系统';

  @override
  String get pluginServiceDetailSupportedPlatforms => '支持平台';

  @override
  String get pluginServiceDetailPackageName => '包名称';

  @override
  String get pluginServiceDetailBinaryName => '命令名称';

  @override
  String get pluginServiceDetailRepository => '代码仓库';

  @override
  String get pluginServiceDetailDocumentation => '官方文档';

  @override
  String get pluginServiceDetailInstallCommand => '安装命令';

  @override
  String get pluginServiceDetailUpgradeCommand => '升级命令';

  @override
  String get pluginServiceDetailUninstallCommand => '卸载命令';

  @override
  String get pluginServiceDetailExecutablePath => '可执行入口';

  @override
  String get pluginServiceDetailCacheDirectory => '缓存目录';

  @override
  String get pluginServiceDetailNpmGlobalRoot => 'npm 全局目录';

  @override
  String get pluginServiceDetailCurrentVersion => '当前版本';

  @override
  String get pluginServiceDetailLatestVersion => '最新版本';

  @override
  String get pluginServiceDetailBoundPython => '绑定解释器';

  @override
  String get pluginServiceDetailDesktopAppDetected => '检测到桌面应用';

  @override
  String get pluginServiceDetailDaemonRunning => 'Daemon 运行中';

  @override
  String get pluginServiceDetailCliAvailable => 'CLI 可用';

  @override
  String get pluginServiceDetailDockerContext => 'Docker 上下文';

  @override
  String get pluginServiceDetailServerVersion => '服务端版本';

  @override
  String get pluginServiceDetailDockerOs => 'Docker OS';

  @override
  String get pluginServiceDetailDockerRootDir => 'Docker 根目录';

  @override
  String get pluginServiceDetailDaemonName => 'Daemon 名称';

  @override
  String get pluginServiceDetailOsType => 'OS 类型';

  @override
  String get pluginServiceDetailArchitecture => '架构';

  @override
  String get pluginServiceDetailComposeVersion => 'Compose 版本';

  @override
  String get pluginServiceDetailDockerDaemonRunning => 'Docker daemon 运行中';

  @override
  String get pluginServiceDetailOpenHandManaged => 'OpenHand 管理';

  @override
  String get pluginServiceDetailContainerId => '容器 ID';

  @override
  String get pluginServiceDetailContainerName => '容器名称';

  @override
  String get pluginServiceDetailContainerStatus => '容器状态';

  @override
  String get pluginServiceDetailRunning => '运行中';

  @override
  String get pluginServiceDetailStartedAt => '启动时间';

  @override
  String get pluginServiceDetailFinishedAt => '结束时间';

  @override
  String get pluginServiceDetailRestartCount => '重启次数';

  @override
  String get pluginServiceDetailExitCode => '退出码';

  @override
  String get pluginServiceDetailImage => '镜像';

  @override
  String get pluginServiceDetailImageId => '镜像 ID';

  @override
  String get pluginServiceDetailPorts => '端口';

  @override
  String get pluginServiceDetailRestartPolicy => '重启策略';

  @override
  String get pluginServiceDetailRestEndpoint => 'REST 端点';

  @override
  String get pluginServiceDetailGrpcEndpoint => 'gRPC 端点';

  @override
  String get pluginServiceDetailDataDirectory => '数据目录';

  @override
  String get pluginServiceDetailHealthResponse => '健康响应';

  @override
  String get pluginServiceDetailHealthTitle => '健康标题';

  @override
  String get pluginServiceDetailCollectionCount => '集合数量';

  @override
  String get pluginServiceDetailRuntimeCapabilities => '运行能力';

  @override
  String get pluginServiceDetailApplicationPath => '应用目录';

  @override
  String get pluginServiceDetailReleaseChannel => '发布通道';

  @override
  String get pluginServiceDetailVersionSource => '版本来源';

  @override
  String get pluginServiceDetailVersionApi => '版本 API';

  @override
  String get pluginServiceDetailBrowserKind => '浏览器类型';

  @override
  String get pluginServiceDetailCdpTransport => 'CDP 传输';

  @override
  String get pluginServiceDetailCdpEndpoint => 'CDP 端点';

  @override
  String get pluginServiceDetailProfileStrategy => '配置策略';

  @override
  String get pluginServiceDetailCaptureScope => '采集范围';

  @override
  String get pluginServiceDetailCredentialPolicy => '凭据保护';

  @override
  String get pluginServiceDetailSessionCleanup => '会话清理';

  @override
  String get pluginServiceDetailUpdatePolicy => '更新策略';

  @override
  String get pluginServiceDetailUninstallPolicy => '卸载策略';

  @override
  String get pluginServiceDetailOfficialSite => '官方网站';

  @override
  String pluginServiceMcpInstalledVersion(Object version) {
    return '已安装 v$version';
  }

  @override
  String get pluginServiceMcpOperationTimeout => '[timeout] 操作超时，已终止进程';

  @override
  String pluginServiceMcpOperationCompleted(Object action, Object exitCode) {
    return '✓ $action 完成 (exit code: $exitCode)';
  }

  @override
  String pluginServiceMcpOperationFailed(Object action, Object exitCode) {
    return '✗ $action 失败 (exit code: $exitCode)';
  }

  @override
  String pluginServiceMcpOperationError(Object error) {
    return '✗ 异常：$error';
  }

  @override
  String get pluginServiceMcpVerificationFailed => 'MCP 操作后的状态校验失败';

  @override
  String get pluginServiceDescriptionNodejs =>
      'JavaScript 运行时环境，用于执行 JS/TS 脚本与工具链';

  @override
  String get pluginServiceDescriptionPlaywright =>
      '浏览器自动化测试框架，支持 Chromium / Firefox / WebKit';

  @override
  String get pluginServiceDescriptionHermesAgent =>
      'Hermes Agent 运行时，用于智能体编排、自我学习与技能沉淀';

  @override
  String get pluginServiceDescriptionPython =>
      'Python 运行时环境，用于执行 Python 脚本、库与扩展能力';

  @override
  String get pluginServiceDescriptionPip => 'Python 包管理工具，用于安装、升级与管理 Python 库';

  @override
  String get pluginServiceDescriptionJava =>
      'JDK 运行时，用于 apktool / jadx 等 Android 静态分析工具';

  @override
  String get pluginServiceDescriptionFrida => '动态插桩与 Hook 工具链，用于 Android 运行时验证';

  @override
  String get pluginServiceDescriptionMitmproxy =>
      'HTTP(S) 代理抓包工具，用于 Web / Android 流量取证';

  @override
  String get pluginServiceDescriptionApktool => 'APK 解包与 smali 分析工具';

  @override
  String get pluginServiceDescriptionJadx => 'DEX / APK Java 反编译工具';

  @override
  String get pluginServiceDescriptionRadare2 => '二进制静态分析与 ELF / native so 逆向工具';

  @override
  String get pluginServiceDescriptionBlutter =>
      'Flutter Dart AOT 快速还原工具，用于 libapp.so 分析';

  @override
  String get pluginServiceDescriptionDoldrums =>
      'Flutter snapshot / ELF 辅助分析工具';

  @override
  String get pluginServiceDescriptionAnythingAnalyzer =>
      '协议分析与 MCP Server 工具，用于抓包、分析和 Agent 联动';

  @override
  String get pluginServiceDescriptionDocker => '容器运行环境，用于运行 Qdrant 本地向量数据库服务';

  @override
  String get pluginServiceDescriptionQdrant =>
      '本地向量数据库，用于知识库 embedding 向量索引与检索';

  @override
  String get pluginServiceDescriptionPostgresql =>
      '关系型数据库服务，供 AI 暴露面扫描保存任务与审计数据';

  @override
  String get pluginServiceDescriptionRedis => '内存数据存储服务，供 AI 暴露面扫描执行缓存与任务队列';

  @override
  String get pluginServiceDescriptionDingtalkWorkspaceCli =>
      '钉钉工作区命令行工具，为 AI Agent 提供钉钉工作流能力';

  @override
  String get pluginServiceDescriptionGoogleChrome =>
      '本机 Chrome 运行时，为论坛狩猎提供原生 CDP 页面与网络采集';

  @override
  String get pluginServiceDetailExternalService => '外部服务';

  @override
  String get pluginServiceDetailServiceRunning => '服务运行中';

  @override
  String get pluginServiceDetailEndpoint => '服务端点';

  @override
  String get pluginServiceTemplateWebReverseExpert => 'Web 逆向专家';

  @override
  String get pluginServiceTemplateAndroidReverseExpert => 'Android 逆向专家';

  @override
  String get pluginServiceTemplateHermesTalker => 'Hermes Talker';

  @override
  String get mcpStdioMirrorModeLabel => '镜像源模式';

  @override
  String get mcpStdioMirrorModeBody =>
      'stdio MCP 服务首启时，是否注入国内镜像源（npmmirror / 清华 PyPI）。auto = 按系统语言自判；强制开启 / 关闭 = 无视 locale。环变 OPENHAND_MCP_MIRROR=on/off 能运行时再覆盖一次。';

  @override
  String get mcpStdioMirrorModeAuto => '跟随语言';

  @override
  String get mcpStdioMirrorModeForceOn => '强制开启';

  @override
  String get mcpStdioMirrorModeForceOff => '强制关闭';

  @override
  String get mcpStdioMirrorModeStatusInjected => '当前生效：将注入 npmmirror / 清华 PyPI';

  @override
  String get mcpStdioMirrorModeStatusBypassed => '当前生效：不注入镜像源，走官方 registry';

  @override
  String mcpStdioMirrorModeStatusReason(Object reason) {
    return '依据：$reason';
  }

  @override
  String get mcpStdioMirrorModeReasonEnv => '环变 OPENHAND_MCP_MIRROR';

  @override
  String get mcpStdioMirrorModeReasonSetting => '设置项强制';

  @override
  String mcpStdioMirrorModeReasonLocale(Object locale) {
    return '跟随语言 ($locale)';
  }

  @override
  String get mcpStdioMirrorModeReconnectAction => '按新设置重拉已启用的 server';

  @override
  String get mcpStdioMirrorModeReconnectDone => '已触发重拉，下一次调用会用新镜像源重新启动进程。';

  @override
  String mcpStdioDialogLogsTitle(Object name) {
    return '$name 日志';
  }

  @override
  String mcpStdioDialogRuntimeDetailsTitle(Object name) {
    return '$name 运行时详情';
  }

  @override
  String mcpStdioDialogRunningPid(Object pid) {
    return '运行中 · PID $pid';
  }

  @override
  String get mcpStdioDialogStopped => '已停止';

  @override
  String get mcpStdioDialogAutoScroll => '自动滚动';

  @override
  String get mcpStdioDialogCopyLogs => '复制日志';

  @override
  String get mcpStdioDialogClearLogs => '清除日志';

  @override
  String get mcpStdioDialogCopiedToClipboard => '已复制到剪贴板';

  @override
  String get mcpStdioDialogNoLogOutput => '暂无日志输出';

  @override
  String mcpStdioDialogLineCount(int count) {
    return '$count 行';
  }

  @override
  String mcpStdioDialogUptime(Object uptime) {
    return '运行 $uptime';
  }

  @override
  String get mcpStdioDialogRefresh => '刷新';

  @override
  String get settingsScraplingRuntimeActionInstall => '安装';

  @override
  String get settingsScraplingRuntimeActionUninstall => '卸载';

  @override
  String settingsScraplingRuntimeCommand(Object action) {
    return '$action Scrapling 运行时';
  }

  @override
  String get settingsScraplingRuntimeInstallTitle => '安装 Scrapling 运行时';

  @override
  String get settingsScraplingRuntimeUninstallTitle => '卸载 Scrapling 运行时';

  @override
  String get settingsScraplingRuntimeInstalling => '安装中…';

  @override
  String get settingsScraplingRuntimeUninstalling => '卸载中…';

  @override
  String get settingsScraplingRuntimeInstalled => '安装完成';

  @override
  String get settingsScraplingRuntimeUninstalled => '卸载完成';

  @override
  String get settingsScraplingRuntimeFailed => '执行失败';

  @override
  String get settingsScraplingRuntimeCertificateDiagnosis =>
      '诊断：当前环境的 Python / pip 无法验证 PyPI 证书链。请检查系统 CA 证书、代理拦截证书，或为 Python 配置可用的证书文件。';

  @override
  String get settingsScraplingRuntimeCopiedAllLogs => '已复制全部日志';

  @override
  String get settingsScraplingRuntimeCopyLogs => '复制日志';

  @override
  String get mcpStdioDialogProcessStatus => '进程状态';

  @override
  String get mcpStdioDialogServiceConfig => '服务配置';

  @override
  String get mcpStdioDialogType => '类型';

  @override
  String get mcpStdioDialogCommand => '命令';

  @override
  String get mcpStdioDialogArgs => '参数';

  @override
  String get mcpStdioDialogEnabled => '已启用';

  @override
  String get mcpStdioDialogYes => '是';

  @override
  String get mcpStdioDialogNo => '否';

  @override
  String get mcpStdioDialogEnvironment => '环境信息';

  @override
  String get mcpStdioDialogError => '错误信息';

  @override
  String get mcpStdioDialogDepsTitle => '依赖管理';

  @override
  String get mcpStdioDialogNoDepsToManage => '此服务非包管理器类型（npx / uvx），无需管理依赖。';

  @override
  String mcpStdioDialogInstalledVersion(Object version) {
    return '已安装 v$version';
  }

  @override
  String get mcpStdioDialogUnknownVersion => '?';

  @override
  String get mcpStdioDialogNotGloballyInstalled => '未全局安装';

  @override
  String get mcpStdioDialogInstall => '安装';

  @override
  String get mcpStdioDialogUpdate => '更新';

  @override
  String get mcpStdioDialogUninstall => '卸载';

  @override
  String mcpStdioDialogLatestVersion(Object version) {
    return '最新版本: $version';
  }

  @override
  String get mcpStdioDialogUpdateAvailableSuffix => '（可更新）';

  @override
  String get mcpStdioDialogOperationTimeout => '[timeout] 操作超时，已终止进程';

  @override
  String mcpStdioDialogOperationCompleted(
    Object time,
    Object action,
    int exitCode,
  ) {
    return '[$time] ✓ $action 完成 (exit code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationFailed(
    Object time,
    Object action,
    int exitCode,
  ) {
    return '[$time] ✗ $action 失败 (exit code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationFailedPlain(Object action, int exitCode) {
    return '$action 失败 (exit code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationException(Object time, Object error) {
    return '[$time] ✗ 异常: $error';
  }

  @override
  String mcpStdioDialogWarmCache(Object time) {
    return '[$time] 预热隔离缓存…';
  }

  @override
  String mcpStdioDialogWarmCacheDone(Object time) {
    return '[$time] ✓ 缓存预热完成';
  }

  @override
  String mcpStdioDialogWarmCacheSkipped(Object time, Object error) {
    return '[$time] 缓存预热跳过: $error';
  }

  @override
  String get mcpAutoProbeConcurrencyLabel => 'MCP 检查/拉取并发数';

  @override
  String get mcpAutoProbeConcurrencyBody =>
      '同时执行 MCP 健康检查或 Tools 拉取的服务数量上限。默认 5；调低可减少资源占用，调高可加速大量服务的批量刷新。';

  @override
  String get mcpAutoProbeConcurrencySave => '保存并发数';

  @override
  String get mcpAutoProbeConcurrencySaved => 'MCP 检查/拉取并发数已保存。';

  @override
  String get mcpAutoProbeConcurrencyInvalid => '请输入 1 到 32 之间的整数。';

  @override
  String get mcpProbeDetailsTitle => 'MCP 探测详情';

  @override
  String get mcpProbePoolActive => '探测池运行中';

  @override
  String get mcpProbePoolIdle => '探测池空闲';

  @override
  String get mcpProbePoolStatusTitle => '探测池状态';

  @override
  String mcpProbeSlots(int active, int total) {
    return '槽位 $active/$total';
  }

  @override
  String mcpProbeQueued(int count) {
    return '排队 $count';
  }

  @override
  String get mcpProbeStateRunning => '运行中';

  @override
  String get mcpProbeStateIdle => '空闲';

  @override
  String mcpProbeToolsStatus(Object status) {
    return '工具 $status';
  }

  @override
  String mcpProbeHealthStatus(Object status) {
    return '健康 $status';
  }

  @override
  String mcpProbeLastRun(Object time) {
    return '上次 $time';
  }

  @override
  String mcpProbeNextRun(Object time) {
    return '下次 $time';
  }

  @override
  String get mcpProbeControlsTitle => '探测控制';

  @override
  String get mcpProbeForceProbe => '强制触发探测';

  @override
  String get mcpProbeStopProbing => '中断当前探测';

  @override
  String get mcpProbeReloadServers => '重载服务列表';

  @override
  String mcpProbeServerStatusTitle(int count) {
    return '服务探测状态 ($count 个服务)';
  }

  @override
  String get mcpProbeNoServers => '暂无服务';

  @override
  String get mcpProbeHealthHealthy => '健康';

  @override
  String get mcpProbeHealthUnhealthy => '异常';

  @override
  String get mcpProbeHealthChecking => '检测中';

  @override
  String get mcpProbeHealthIdle => '待检测';

  @override
  String get mcpProbeDisableServerTooltip => '点击禁用此服务探测';

  @override
  String get mcpProbeEnableServerTooltip => '点击启用此服务探测';

  @override
  String get mcpProbeNoProbe => '不探测';

  @override
  String mcpProbeToolCount(int count) {
    return '$count 个工具';
  }

  @override
  String get mcpProbeThisServer => '探测此服务';

  @override
  String get mcpRelativeJustNow => '刚刚';

  @override
  String mcpRelativeSecondsAgo(int seconds) {
    return '$seconds 秒前';
  }

  @override
  String mcpRelativeMinutesAgo(int minutes) {
    return '$minutes 分钟前';
  }

  @override
  String mcpRelativeHoursAgo(int hours) {
    return '$hours 小时前';
  }

  @override
  String mcpRelativeDaysAgo(int days) {
    return '$days 天前';
  }

  @override
  String get mcpRelativeImminent => '即将开始';

  @override
  String mcpRelativeInSeconds(int seconds) {
    return '约 $seconds 秒后';
  }

  @override
  String mcpRelativeInMinutes(int minutes) {
    return '约 $minutes 分钟后';
  }

  @override
  String mcpRelativeInHours(int hours) {
    return '约 $hours 小时后';
  }

  @override
  String mcpRelativeInDays(int days) {
    return '约 $days 天后';
  }

  @override
  String get mcpKeywordIndexUpdateModeLabel => '更新关键词映射模式';

  @override
  String get mcpKeywordIndexUpdateModeBody =>
      '控制 MCP 工具关键词倒排索引的重建节奏。冷启动模式仅在启动时加载磁盘缓存，需要手动点击「构建关键词映射」；定时间隔模式按设定的「值 + 单位」周期重建并整体覆盖磁盘缓存；每日定点模式在指定时刻自动重建一次。后两者复用同一条系统 cron 任务，避免任务碎片化。';

  @override
  String get mcpKeywordIndexUpdateModeColdStart => '冷启动';

  @override
  String get mcpKeywordIndexUpdateModeInterval => '定时间隔';

  @override
  String get mcpKeywordIndexUpdateModeScheduled => '每日定点';

  @override
  String get mcpKeywordIndexUpdateModeColdStartHint =>
      '冷启动模式：仅在 App 启动时加载磁盘上的关键词索引；如需刷新请手动点击「构建关键词映射」。系统 cron 任务保持禁用。';

  @override
  String get mcpKeywordIndexIntervalValueLabel => '间隔';

  @override
  String get mcpKeywordIndexIntervalUnitLabel => '单位';

  @override
  String get mcpKeywordIndexIntervalUnitMinute => '分钟';

  @override
  String get mcpKeywordIndexIntervalUnitHour => '小时';

  @override
  String get mcpKeywordIndexIntervalUnitDay => '天';

  @override
  String mcpKeywordIndexScheduledLabel(String time) {
    return '每日 $time 自动重建';
  }

  @override
  String get mcpKeywordIndexScheduledPickAction => '选择时间';

  @override
  String get commonClose => '关闭';

  @override
  String get commonRunInBackground => '后台运行';

  @override
  String get mcpBuildKeywordIndex => '构建关键词映射';

  @override
  String get mcpKeywordIndexBuildTitle => '构建关键词倒排索引';

  @override
  String get mcpKeywordIndexBuildStarting => '正在准备…';

  @override
  String mcpKeywordIndexBuildProgress(
    int idx,
    int count,
    Object server,
    int tools,
  ) {
    return '$idx/$count：$server（已扫 $tools 个工具）';
  }

  @override
  String mcpKeywordIndexBuildSummary(
    int servers,
    int tools,
    int keys,
    Object sec,
  ) {
    return '已索引 $servers 个服务、$tools 个工具，关键词 $keys 个，用时 ${sec}s';
  }

  @override
  String mcpKeywordIndexBuildSkipped(int n) {
    return '跳过 $n 个未就绪服务';
  }

  @override
  String get mcpKeywordIndexBuildFailed => '构建失败：';

  @override
  String get mcpLazyLoadingModeLabel => 'MCP 工具懒加载';

  @override
  String get mcpLazyLoadingModeBody =>
      '控制是否在系统提示中折叠 MCP 工具描述：关闭时全部展开；开启时全部折叠为 ToolSearch 可按需取回；自动模式下当总 token 估算超过阈值才折叠。';

  @override
  String get mcpLazyLoadingModeDisabled => '关闭';

  @override
  String get mcpLazyLoadingModeAuto => '自动';

  @override
  String get mcpLazyLoadingModeEnabled => '开启';

  @override
  String get mcpLazyLoadingThresholdLabel => 'MCP 工具压缩阈值';

  @override
  String get mcpLazyLoadingThresholdBody =>
      '自动模式下 MCP 工具描述总 token 估算超过该值时启用懒加载。';

  @override
  String get mcpLazyLoadingThresholdSave => '保存阈值';

  @override
  String get mcpLazyLoadingThresholdSaved => 'MCP 工具懒加载阈值已保存。';

  @override
  String get mcpLazyLoadingThresholdInvalid => '请填写 1000 ~ 1000000 之间的整数。';

  @override
  String get settingsHarnessToolSearchHistoryCapLabel =>
      'Harness ToolSearch 历史保留上限';

  @override
  String get settingsHarnessToolSearchHistoryCapBody =>
      'ToolSearch 已加载列表对话框保留的 Harness phase 最大个数，超出后以 LRU 淘汰。';

  @override
  String settingsHarnessToolSearchHistoryCapValue(int cap) {
    return '当前保留最近 $cap 个 phase';
  }

  @override
  String settingsHarnessToolSearchHistoryCapRange(int min, int max) {
    return '范围：$min–$max（默认 8）';
  }

  @override
  String settingsHarnessToolSearchHistoryCapResetTooltip(int defaultCap) {
    return '重置为默认值（$defaultCap）';
  }

  @override
  String get harnessCliLoginNoOutputHint =>
      '[提示] CLI 尚未产生输出。可能正在初始化，或需要在外部浏览器中完成授权。\n';

  @override
  String harnessCliLoginTimedOut(int minutes) {
    return '登录等待超过 $minutes 分钟，已自动停止进程。';
  }

  @override
  String get harnessCliLoginTtyRequiredHint =>
      '[提示] 该 CLI 可能需要真实终端 (TTY) 才能完成交互式登录。\n请点击下方“在终端中打开”按钮，在系统终端中完成登录流程。\n';

  @override
  String harnessCliLoginStreamError(Object error) {
    return '[流错误：$error]';
  }

  @override
  String harnessCliLoginFailedToStartProcess(Object message) {
    return '无法启动进程：$message';
  }

  @override
  String harnessCliLoginOpenTerminalError(Object error) {
    return '[无法打开终端：$error]';
  }

  @override
  String get harnessCliLoginStatusFailed => '启动失败';

  @override
  String get harnessCliLoginStatusStarting => '正在启动登录流程...';

  @override
  String get harnessCliLoginStatusFinished => '流程已结束';

  @override
  String harnessCliLoginStatusFinishedWithExit(int exitCode) {
    return '流程已结束 · 退出码 $exitCode';
  }

  @override
  String get harnessCliLoginStatusWaiting => '等待 CLI 交互...';

  @override
  String harnessCliLoginTitle(Object name) {
    return '$name 登录';
  }

  @override
  String get harnessCliLoginDescription =>
      '该弹窗会在应用内启动交互式 CLI 登录流程。过程中 CLI 可能会自动打开外部浏览器，请根据提示完成授权。';

  @override
  String get harnessCliLoginCopyCommandTooltip => '复制命令';

  @override
  String get harnessCliLoginEmptyOutput => '等待 CLI 输出...';

  @override
  String get harnessCliLoginInputLabel => '发送输入';

  @override
  String get harnessCliLoginInputHint => '输入内容后回车；留空可直接发送回车';

  @override
  String get harnessCliLoginSend => '发送';

  @override
  String get harnessCliLoginSendEsc => '发送 Esc';

  @override
  String get harnessCliLoginOpenInTerminal => '在终端中打开';

  @override
  String get harnessCliInstallLogSuccess => '✓ 安装成功';

  @override
  String harnessCliInstallLogSuccessWithPath(Object path) {
    return '✓ 安装成功（路径：$path）';
  }

  @override
  String harnessCliInstallLogFailureExitCode(int exitCode) {
    return '✗ 安装失败（退出码：$exitCode）';
  }

  @override
  String harnessCliInstallLogStartProcessFailed(Object message) {
    return '✗ 无法启动安装进程：$message';
  }

  @override
  String harnessCliInstallLogGenericError(Object error) {
    return '✗ 发生错误：$error';
  }

  @override
  String get harnessCliInstallHintInstallNode =>
      '  → 请先安装 Node.js：https://nodejs.org';

  @override
  String get harnessCliInstallHintRetryAdminButton => '  → 点击下方“以管理员权限重试”按钮';

  @override
  String harnessCliInstallHintTrySudo(Object command) {
    return '  → 尝试：sudo $command';
  }

  @override
  String get harnessCliInstallHintCheckNetworkDocs => '  → 请检查网络连接或查阅官方文档';

  @override
  String get harnessCliInstallHintInstallPipx =>
      '  → 请先安装 pipx：https://pipx.pypa.io/stable/installation/';

  @override
  String get harnessCliInstallHintUsePipInstallUserAider =>
      '    或使用：pip install --user aider-chat';

  @override
  String get harnessCliInstallHintHomebrewNoSudo =>
      '  → Homebrew 通常不应以 sudo 安装，请检查目录权限';

  @override
  String get harnessCliInstallHintHomebrewFix =>
      '  → 修复建议：https://docs.brew.sh/FAQ#why-does-homebrew-say-sudo-is-not-allowed';

  @override
  String get harnessCliInstallHintInstallPython =>
      '  → 请先安装 Python：https://www.python.org';

  @override
  String harnessCliInstallHintPipInstallUser(Object packageName) {
    return '  → 尝试：pip install --user $packageName';
  }

  @override
  String harnessCliInstallHintOfficialDocs(Object url) {
    return '  → 官方文档：$url';
  }

  @override
  String get harnessCliInstallLogCancelled => '⚠ 安装已被取消';

  @override
  String get harnessCliInstallWindowsAdminManual =>
      '请在管理员权限的 PowerShell 中手动执行：';

  @override
  String harnessCliInstallAdminCommand(Object command) {
    return '> [管理员] $command';
  }

  @override
  String get harnessCliInstallAdminTimeout =>
      '✗ 管理员授权对话框超时或启动失败，已强制结束 osascript 子进程';

  @override
  String get harnessCliInstallUserCancelledAuth => '⚠ 用户已取消授权';

  @override
  String get harnessCliInstallAdminPermissionFailed => '✗ 无法获取管理员权限';

  @override
  String harnessCliInstallPathMissingWarning(Object executable) {
    return '⚠ 安装完成，但未在当前 PATH 中检测到 $executable';
  }

  @override
  String get harnessCliInstallRestartPathHint =>
      '  → 请尝试重新启动 OpenHand 或从终端启动以加载新 PATH';

  @override
  String get harnessCliInstallTimeoutManual => '✗ 安装超时（超过 5 分钟），请手动运行：';

  @override
  String harnessCliInstallOsascriptStartFailed(Object message) {
    return '✗ 无法启动 osascript：$message';
  }

  @override
  String get harnessCliInstallLinuxSudoManual => '请在终端手动执行（需要 root 权限）：';

  @override
  String get harnessCliInstallStatusInstalling => '安装中...';

  @override
  String get harnessCliInstallStatusSuccess => '安装成功';

  @override
  String get harnessCliInstallStatusCancelled => '已取消';

  @override
  String get harnessCliInstallStatusFailed => '安装失败';

  @override
  String harnessCliInstallTitle(Object name) {
    return '安装 $name';
  }

  @override
  String get harnessCliInstallCopyDocUrl => '复制文档链接';

  @override
  String get harnessCliInstallCancel => '取消安装';

  @override
  String get harnessCliInstallRetryAdmin => '以管理员权限重试';

  @override
  String get harnessCliInstallDoneContinue => '完成，继续';

  @override
  String get settingsToolSearchReplayCancelWindowLabel => '重放反悔窗口';

  @override
  String get settingsToolSearchReplayCancelWindowBody =>
      'snackbar 在发送前等待的秒数；期间点取消即可撤销。';

  @override
  String settingsToolSearchReplayCancelWindowValue(int seconds) {
    return '窗口：$seconds 秒';
  }

  @override
  String settingsToolSearchReplayCancelWindowRange(int min, int max) {
    return '范围：$min–$max 秒（默认 3）';
  }

  @override
  String settingsToolSearchReplayCancelWindowResetTooltip(int defaultSeconds) {
    return '重置为默认值（$defaultSeconds 秒）';
  }

  @override
  String get mcpLazyLoadingHowItWorks =>
      '懒加载启用时：MCP 工具描述被折叠为名称索引，模型通过内置 ToolSearch 工具按需取回完整 JSON Schema。支持三种查询：\n• select:NAME（直接选取，可空格分隔多个）\n• 关键字（按 name/description 评分匹配）\n• +KEYWORD（必含词，用于过滤噪声）\n命中后继续通过 ToolSearch 提交精确 tool_name 和符合 Schema 的 arguments。原生工具目录保持固定，避免破坏提示词缓存。';

  @override
  String get settingsGeneralSubtitle => '管理主题、语言与应用基础信息。';

  @override
  String get settingsAiSubtitle => '管理聊天模型、鉴权方式与协议适配。';

  @override
  String get settingsActiveToolCallsTitle => '运行中的工具调用';

  @override
  String get settingsActiveToolCallsBody =>
      '实时展示当前所有派发中的工具，包括 PID、类别、所属会话与已运行时长，单击 Stop 可立即终止该调用。';

  @override
  String get settingsActiveToolCallsEmpty => '目前没有正在运行的工具调用。';

  @override
  String get settingsActiveToolCallsCancel => '停止';

  @override
  String get settingsActiveToolKindBuiltin => '内建';

  @override
  String get settingsActiveToolKindMcp => 'MCP';

  @override
  String get settingsActiveToolKindSkill => '技能';

  @override
  String get settingsActiveToolSessionLabel => '会话';

  @override
  String get settingsToolHardeningTitle => '工具加固参数';

  @override
  String get settingsToolHardeningBody =>
      '子进程 graceful shutdown 时长、bash 输出上限、并发工具调用上限。';

  @override
  String get settingsSubprocessGracefulShutdownLabel =>
      '子进程 graceful shutdown（毫秒）';

  @override
  String get settingsSubprocessGracefulShutdownBody =>
      'SIGTERM 之后等多久才升级到 SIGKILL。越大越仁慈，但 UI 取消反馈也越慢。范围 100–5000。';

  @override
  String get settingsBashOutputMaxBytesLabel => 'Bash 捕获上限（字符）';

  @override
  String get settingsBashOutputMaxBytesBody =>
      '单次 bash 调用合并捕获 stdout+stderr 的上限。超过会从中段截断保留头尾。范围 16000–4000000。';

  @override
  String get settingsMaxConcurrentToolsLabel => '并发工具调用上限';

  @override
  String get settingsMaxConcurrentToolsBody => '同会话内同时派发的工具调用最大数量。范围 1–64。';

  @override
  String get settingsToolHardeningInvalid => '请输入范围内的整数';

  @override
  String get settingsSkillsSubtitle => '管理本地技能目录、模板创建与已安装技能展示。';

  @override
  String get settingsMemorySubtitle => '管理用户记忆开关与持久化文件位置。';

  @override
  String get settingsPersistenceInvalidTitle => '设置数据损坏';

  @override
  String get settingsPersistenceInvalidBody => '数据库记录无法解析。当前仅展示安全默认值，不会覆盖原始数据。';

  @override
  String get settingsPersistenceLoadFailedTitle => '设置读取失败';

  @override
  String get settingsPersistenceLoadFailedBody =>
      '无法读取本地数据库。当前临时展示默认值并暂停保存，以保护已有数据。';

  @override
  String get settingsPersistenceSaveFailedTitle => '设置保存失败';

  @override
  String get settingsPersistenceSaveFailedBody =>
      '设置数据库写入失败，界面已回滚到上一次有效配置，请检查数据库访问权限或磁盘状态。';

  @override
  String get settingsPersistenceDismiss => '关闭提示';

  @override
  String get settingsAnimationRestoreDefaultsTitle => '恢复默认动画';

  @override
  String get settingsAnimationRestoreDefaultsSubtitle =>
      '一键将弹窗、菜单、页面 / 模块、工作区面板、胶囊、列表项这六组动画的进场 / 退场风格、时长、速率曲线全部重置为 OpenHand 推荐的默认值。';

  @override
  String get settingsAnimationRestoreDefaultsButton => '恢复默认';

  @override
  String get settingsAnimationRestoreConfirmTitle => '恢复默认动画？';

  @override
  String get settingsAnimationRestoreConfirmMessage =>
      '将把弹窗、菜单、页面 / 模块、工作区面板、胶囊、列表项六组动画全部重置为默认值，已自定义的设置会被覆盖，此操作不可撤销。';

  @override
  String get settingsAnimationRestoreConfirm => '恢复';

  @override
  String get settingsAnimationRestoreSuccess => '已恢复默认动画设置';

  @override
  String get settingsDialogAnimationTitle => '弹窗动画';

  @override
  String get settingsDialogAnimationSubtitle => '配置全局弹窗的进场动画、退场动画、时长和速率曲线。';

  @override
  String get settingsMenuAnimationTitle => '菜单动画';

  @override
  String get settingsMenuAnimationSubtitle =>
      '配置弹出菜单、右键菜单和下拉菜单的进场动画、退场动画、时长和速率曲线。';

  @override
  String get settingsPanelAnimationTitle => '工作区面板动画';

  @override
  String get settingsPanelAnimationSubtitle =>
      '配置工作区左右面板切换的进场动画、退场动画、时长和速率曲线，例如左侧导航与文件浏览器切换、右侧会话与代码编辑器切换。Settings、MCP、记忆等右侧模块页面切换由“页面动画”控制。';

  @override
  String get settingsPageAnimationTitle => '页面 / 模块动画';

  @override
  String get settingsPageAnimationSubtitle =>
      '配置右侧主内容模块切换的进场动画、退场动画、时长和速率曲线，包括会话、设置、MCP、记忆、Hooks、Crons、技能、自动化等页面之间的切换。';

  @override
  String get settingsChipAnimationTitle => '胶囊动画';

  @override
  String get settingsChipAnimationSubtitle =>
      '配置技能、附件、项目引用、队列消息、编辑提示等所有可关闭胶囊（chip）的进场 / 退场动画样式、时长和速率曲线。点击叉号关闭时会先播放退场动效再从布局中移除。';

  @override
  String get settingsListItemAnimationTitle => '列表项动画';

  @override
  String get settingsListItemAnimationSubtitle =>
      '配置 MCP 服务器、记忆条目、指令卡片、左侧导航会话、工具调用卡片等列表项的进场动画样式与时长。设置为「无」则禁用列表项进场动画。';

  @override
  String get settingsAnimationEnter => '进场';

  @override
  String get settingsAnimationExit => '退场';

  @override
  String get settingsAnimationDuration => '时长';

  @override
  String get settingsAnimationCurve => '曲线';

  @override
  String get dialogAnimationStyleNone => '无动画';

  @override
  String get dialogAnimationStyleFade => '淡入淡出';

  @override
  String get dialogAnimationStyleFadeScale => '渐显缩放';

  @override
  String get dialogAnimationStyleSlideUp => '底部上滑';

  @override
  String get dialogAnimationStyleSlideDown => '顶部下滑';

  @override
  String get dialogAnimationStyleSlideLeft => '左侧滑入';

  @override
  String get dialogAnimationStyleSlideRight => '右侧滑入';

  @override
  String get dialogAnimationStyleExpand => '中心展开';

  @override
  String get dialogAnimationStyleRotateScale => '旋转缩放';

  @override
  String get dialogAnimationStyleElastic => '弹性动画';

  @override
  String get dialogAnimationStyleSpringScale => '弹簧缩放';

  @override
  String get dialogAnimationStyleFlipX => 'X 轴翻转';

  @override
  String get dialogAnimationCurveEaseInOut => '缓入缓出';

  @override
  String get dialogAnimationCurveEaseOut => '缓出';

  @override
  String get dialogAnimationCurveEaseOutCubic => '缓出三次';

  @override
  String get dialogAnimationCurveEaseInOutCubicEmphasized => '三次加强';

  @override
  String get dialogAnimationCurveElasticOut => '弹性缓出';

  @override
  String get dialogAnimationCurveBounceOut => '弹跳';

  @override
  String get dialogAnimationCurveDecelerate => '减速';

  @override
  String get commonOptional => '可选';

  @override
  String get cronScriptTypeCommand => '命令';

  @override
  String get cronScriptTypeScript => '脚本';

  @override
  String get cronScriptTypeAgent => 'Agent';

  @override
  String get cronJobStatusRunning => '运行中';

  @override
  String get cronJobStatusPaused => '已暂停';

  @override
  String get cronJobStatusFailed => '失败';

  @override
  String get cronJobStatusError => '异常';

  @override
  String get cronJobStatusIdle => '空闲';

  @override
  String get cronNotifyTypeNone => '无';

  @override
  String get cronNotifyTypeLog => '仅日志';

  @override
  String get cronNotifyTypeSystem => '系统通知';

  @override
  String get cronNotifyTypeAppNotification => '应用内通知';

  @override
  String get cronNotifySeverityInfo => '信息';

  @override
  String get cronNotifySeveritySuccess => '成功';

  @override
  String get cronNotifySeverityWarning => '警告';

  @override
  String get cronNotifySeverityError => '错误';

  @override
  String get cronNotifySeverityCritical => '严重';

  @override
  String get cronParserFieldCountError => 'Cron 表达式需要恰好 5 个字段（分 时 日 月 周）';

  @override
  String get cronParserFieldMinute => '分钟';

  @override
  String get cronParserFieldHour => '小时';

  @override
  String get cronParserFieldDayOfMonth => '日';

  @override
  String get cronParserFieldDayOfMonthShort => '日';

  @override
  String get cronParserFieldMonth => '月';

  @override
  String get cronParserFieldDayOfWeek => '星期';

  @override
  String get cronParserFieldDayOfWeekShort => '周';

  @override
  String cronParserInvalidField(String field, String value) {
    return '$field字段 \"$value\" 无效';
  }

  @override
  String get cronsViewDescription =>
      '配置和管理定时任务。支持 Cron 表达式调度、超时控制、自动重试和执行历史查看。';

  @override
  String get cronsNewCronJob => '新增定时任务';

  @override
  String get cronsEditCronJob => '编辑定时任务';

  @override
  String get cronsDeleteCronJobTitle => '删除定时任务';

  @override
  String cronsDeleteCronJobMessage(String name) {
    return '确定删除 \"$name\" 吗？此操作不可撤销，执行历史也将一并删除。';
  }

  @override
  String get cronsEmptyTitle => '暂无定时任务';

  @override
  String get cronsEmptyBody => '点击右上角「新增定时任务」按钮开始配置。';

  @override
  String get cronsCronExpressionTooltip => 'Cron 表达式';

  @override
  String get cronsTimeoutTooltip => '超时时间';

  @override
  String get cronsRetryCountTooltip => '重试次数';

  @override
  String get cronsMcpKeywordIndexLockedTooltip =>
      '由「全局设置 -> MCP -> 更新关键词映射模式」控制，不可手动开关';

  @override
  String get cronsRunOnceNow => '立即执行一次';

  @override
  String get cronsHistory => '执行历史';

  @override
  String cronsLastRunAt(String time) {
    return '上次: $time';
  }

  @override
  String get cronsFieldName => '任务名称';

  @override
  String get cronsFieldNameHint => '例如: 每日备份';

  @override
  String get cronsFieldDescription => '简介';

  @override
  String get cronsFieldType => '类型';

  @override
  String get cronsFieldScriptFilePath => '脚本文件路径';

  @override
  String get cronsFieldScriptFilePathHint => '选择 .sh / .ps1 / .bat 文件';

  @override
  String get cronsBrowse => '浏览';

  @override
  String get cronsFieldCommand => '命令内容';

  @override
  String get cronsFieldCommandHintWindows => '输入 PowerShell / BAT 命令';

  @override
  String get cronsFieldCommandHintShell => '输入 Shell 命令';

  @override
  String get cronsCronSchedule => 'Cron 时间表达式';

  @override
  String get cronsCronScheduleHelper => '秒字段已冻结为 0，最小粒度为分钟。格式: 分 时 日 月 周';

  @override
  String get cronsTimeoutSeconds => '超时（秒）';

  @override
  String get cronsRetries => '重试次数';

  @override
  String get cronsMaxRetryDelaySeconds => '重试间隔上限（秒）';

  @override
  String get cronsRunAsUser => '执行用户';

  @override
  String get cronsDefaultCurrentUser => '默认（当前用户）';

  @override
  String get cronsDefault => '默认';

  @override
  String get cronsTagsCommaSeparated => '标签（逗号分隔）';

  @override
  String get cronsTagsHint => '例如: 备份, 清理';

  @override
  String get cronsWorkingDirectory => '工作目录';

  @override
  String get cronsWorkingDirectoryHint => '可选，默认为应用目录';

  @override
  String get cronsEnvironmentVariables => '环境变量';

  @override
  String get cronsEnvironmentVariablesHint => '每行一个，格式: KEY=VALUE';

  @override
  String get cronsExecutionContextCollection => '执行上下文采集';

  @override
  String get cronsCollectAppMetadata => '采集应用信息';

  @override
  String get cronsCollectAppMetadataSubtitle => '记录应用版本、PID、可执行文件路径等信息';

  @override
  String get cronsCollectHostMetadata => '采集主机信息';

  @override
  String get cronsCollectHostMetadataSubtitle => '记录系统版本、主机名、CPU 核心数等信息';

  @override
  String get cronsCollectEnvironmentSnapshot => '采集环境快照';

  @override
  String get cronsCollectEnvironmentSnapshotSubtitle =>
      '记录执行时有效环境变量快照（可能包含敏感信息）';

  @override
  String get cronsSensitive => '敏感';

  @override
  String get cronsNotificationSettings => '通知配置';

  @override
  String get cronsTestNotification => '测试通知';

  @override
  String get cronsTestSuccessNotification => '测试成功通知';

  @override
  String get cronsTestFailureNotification => '测试失败通知';

  @override
  String get cronsTestTimeoutNotification => '测试超时通知';

  @override
  String get cronsTestAllNotifications => '测试全部（顺序）';

  @override
  String get cronsNotificationSettingsHelper => '每个事件可分别配置通知渠道、严重程度、声音和震动。';

  @override
  String get cronsOnSuccess => '执行成功';

  @override
  String get cronsOnFailure => '执行失败';

  @override
  String get cronsOnTimeout => '执行超时';

  @override
  String get cronsEnabled => '启用';

  @override
  String get cronsCustomNotificationMessageHint => '自定义通知内容（可选）';

  @override
  String get cronsVibrationUnsupportedHint => '当前平台不支持震动，开启后会自动忽略。';

  @override
  String get cronsValidationNameRequired => '请填写任务名称。';

  @override
  String get cronsValidationScriptRequired => '请选择脚本文件。';

  @override
  String get cronsValidationCommandRequired => '请填写命令内容。';

  @override
  String cronsValidationInvalidEnvironment(String lines) {
    return '环境变量格式错误，请检查第 $lines 行。格式应为 KEY=VALUE。';
  }

  @override
  String get cronsNotificationSequentialStartTitle => '开始顺序测试';

  @override
  String get cronsNotificationSequentialStartBody => '将按顺序测试成功、失败、超时通知。';

  @override
  String get cronsNotificationVibrationIgnoredTitle => '震动已忽略';

  @override
  String get cronsNotificationSequentialVibrationIgnoredBody =>
      '当前平台不支持震动，顺序测试中已自动忽略震动设置。';

  @override
  String get cronsNotificationSequentialCompletedTitle => '顺序测试完成';

  @override
  String get cronsNotificationSequentialCompletedBody => '已完成成功、失败、超时三种通知测试。';

  @override
  String get cronsNotificationScenarioSuccess => '成功';

  @override
  String get cronsNotificationScenarioFailure => '失败';

  @override
  String get cronsNotificationScenarioTimeout => '超时';

  @override
  String get cronsNotificationScenarioAll => '全部';

  @override
  String cronsNotificationTestTitle(String label) {
    return '定时任务通知测试 · $label';
  }

  @override
  String get cronsNotificationTestDefaultBodySuccess => '成功场景通知测试消息。';

  @override
  String get cronsNotificationTestDefaultBodyFailure => '失败场景通知测试消息。';

  @override
  String get cronsNotificationTestDefaultBodyTimeout => '超时场景通知测试消息。';

  @override
  String get cronsNotificationNoEmitBody => '当前配置为“无”或“仅日志”，不会触发通知。';

  @override
  String get cronsSystemNotificationUnavailableTitle => '系统通知不可用';

  @override
  String get cronsSystemNotificationFallbackBody => '系统通知发送失败，已回退为应用内通知。';

  @override
  String get cronsNotificationVibrationIgnoredBody => '当前平台不支持震动，已自动忽略该配置。';

  @override
  String get cronsUnknownPlatform => '未知平台';

  @override
  String get cronsToggleOn => '已开启';

  @override
  String get cronsToggleOff => '已关闭';

  @override
  String get cronsSupportBestEffortSystemSound => '支持（尽力触发系统声音）';

  @override
  String get cronsSupportSupported => '支持';

  @override
  String get cronsSupportNotSupportedOnPlatform => '当前平台不支持';

  @override
  String get cronsSupportNotSupportedWillBeIgnored => '不支持（开启后将自动忽略）';

  @override
  String get cronsSoundLabel => '声音';

  @override
  String get cronsVibrationLabel => '震动';

  @override
  String get cronsPlatformLabel => '平台';

  @override
  String get cronsSupportLabel => '状态';

  @override
  String get cronsExecutionHistoryTitle => '定时任务执行历史';

  @override
  String get cronsClearAllExecutionHistory => '清空全部执行历史';

  @override
  String get cronsNoExecutionRecords => '暂无执行记录';

  @override
  String get cronsClearExecutionHistoryTitle => '清空执行历史';

  @override
  String cronsClearExecutionHistoryMessage(String name) {
    return '确定清空「$name」的全部执行历史吗？此操作不可撤销。';
  }

  @override
  String get cronsClear => '清空';

  @override
  String get cronsDeleteExecutionRecordTitle => '删除执行记录';

  @override
  String get cronsDeleteExecutionRecordMessage => '确定删除这条执行记录吗？';

  @override
  String get cronsExecutionStatusSuccess => '成功';

  @override
  String get cronsExecutionStatusFailed => '失败';

  @override
  String get cronsExecutionStatusTimedOut => '超时';

  @override
  String get cronsExecutionStatusRunning => '运行中';

  @override
  String get cronsExecutionStatusKilled => '已终止';

  @override
  String get cronsTriggerManual => '手动';

  @override
  String get cronsTriggerScheduled => '调度';

  @override
  String get cronsDeleteThisRecord => '删除此条记录';

  @override
  String get cronsRetryAttempt => '重试次数';

  @override
  String get cronsRunAs => '执行用户';

  @override
  String get cronsWorkingDir => '工作目录';

  @override
  String get cronsScriptEnvironmentOverrides => '脚本环境覆盖:';

  @override
  String get cronsEnvironmentSnapshot => '环境快照:';

  @override
  String get cronsErrorReason => '错误原因:';

  @override
  String get cronsStdout => '标准输出 (stdout):';

  @override
  String get cronsStderr => '标准错误 (stderr):';

  @override
  String get cronsExecutionContext => '执行上下文:';

  @override
  String get cronsHermesTalkerReportTitle => 'Hermes Talker 自我学习报告';

  @override
  String get cronsHermesNoEligibleSessions => '本轮无符合条件的会话被实际学习。';

  @override
  String cronsHermesAffectedSessions(int count) {
    return '受影响的会话 ($count)';
  }

  @override
  String cronsHermesStatsLine(
    int scanned,
    int triggered,
    int skipped,
    int errors,
  ) {
    return '扫描 $scanned · 触发 $triggered · 跳过 $skipped · 异常 $errors';
  }

  @override
  String get cronsHermesUntitledSession => '(未命名会话)';

  @override
  String cronsHermesMemoryUpdates(int count) {
    return '记忆 +$count';
  }

  @override
  String cronsHermesMemoryErrors(int count) {
    return '记忆错误 $count';
  }

  @override
  String cronsHermesSkillUpdates(int count) {
    return '技能 +$count';
  }

  @override
  String cronsHermesSkillErrors(int count) {
    return '技能错误 $count';
  }

  @override
  String cronsHermesProfileChanges(int count) {
    return '用户轮廓 $count';
  }

  @override
  String cronsHermesToolRounds(int count) {
    return '工具轮次 $count';
  }

  @override
  String get cronsHermesModelLabel => '模型';

  @override
  String get cronsHermesProviderLabel => '渠道';

  @override
  String get cronsHermesTerminatedLabel => '结束原因';

  @override
  String get cronsHermesUserProfileChanges => '用户轮廓变动';

  @override
  String get cronsHermesMemoryChanges => '记忆变动';

  @override
  String get cronsHermesSkillChanges => '技能变动';

  @override
  String get cronsHermesAiReasoningOnScene => '当时现场的 AI 思考';

  @override
  String get cronsHermesAiResponseOnScene => '当时现场的 AI 响应';

  @override
  String get cronsHermesNoFurtherDetails => '本会话无更多详情。';

  @override
  String get cronsHermesStatusError => '失败';

  @override
  String get cronsHermesStatusSkipped => '跳过';

  @override
  String get cronsHermesStatusOk => '完成';

  @override
  String get cronsHermesChangeBefore => '变更前';

  @override
  String get cronsHermesChangeAfter => '变更后';

  @override
  String get cronsHermesChangeValue => '值';

  @override
  String get cronsHermesChangeSource => '来源';

  @override
  String get cronsHermesChangeReason => '原因';

  @override
  String get cronsHermesChangeMetadata => '元数据';

  @override
  String get cronsHermesChangeError => '错误';

  @override
  String get cronsCollapse => '折叠';

  @override
  String get cronsExpand => '展开';

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
  String get aiModelOfficialWebsiteUrl => '官网地址（可选）';

  @override
  String get aiModelOfficialWebsiteUrlHint => 'https://example.com';

  @override
  String get aiModelOfficialWebsiteUrlInvalid => '请输入有效的官网地址';

  @override
  String get aiModelOpenWebsiteFailure => '无法打开官网地址。';

  @override
  String get aiModelOpenWebsiteTooltip => '打开官网地址';

  @override
  String get aiModelAuthScheme => '鉴权方式';

  @override
  String get aiModelToken => '令牌';

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
  String aiModelTestSuccess(String modelName) {
    return '$modelName 测试通过。';
  }

  @override
  String aiModelTestFailure(String modelName, String reason) {
    return '$modelName 测试失败：$reason';
  }

  @override
  String get aiModelSelectionRequired => '请先在设置中添加并选择一个 AI 模型提供商。';

  @override
  String get aiModelScanButton => '扫描模型';

  @override
  String get aiModelScanning => '正在扫描可用模型…';

  @override
  String get aiModelAvailableModels => '可用模型';

  @override
  String get aiModelManualIdHint => '手动输入模型 ID';

  @override
  String get aiModelManualIdAdd => '添加';

  @override
  String aiModelCount(int count) {
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
  String get aiProtocolDots => 'Dots (小红书)';

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
  String get aiProtocolAgnes => 'Agnes';

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
  String get skillsNoResultsTitle => '未找到匹配的技能';

  @override
  String get skillsNoResultsBody => '尝试修改搜索关键词，或清空搜索后重新查看全部技能。';

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
  String get memoryPageSubtitle => '统一维护存储在本地数据库中的用户记忆。';

  @override
  String get memoryRefresh => '刷新';

  @override
  String get memoryNewEntry => '新增记忆';

  @override
  String get memoryEmptyTitle => '还没有任何用户记忆';

  @override
  String get memoryEmptyBody => '新增用户记忆后，它会持久化保存到本地数据库。';

  @override
  String get memoryLoadFailedTitle => '记忆数据读取失败';

  @override
  String get memoryLoadFailedBody => '记忆数据无效或暂不可用，请修复或清空存储后重试。';

  @override
  String get memoryQuotaRecoveryTitle => '记忆存储已超出配额';

  @override
  String get memoryQuotaRecoveryBody => '当前仅展示受限快照。请删除条目或缩减内容直至恢复限额；期间禁止新增条目。';

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
  String get memoryTagLimitExceeded => '每条记忆最多可添加 32 个标签。';

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
  String get userMemoryFileLabel => '记忆数据库';

  @override
  String get memoryFileBody => '用户记忆统一存储在 OpenHand 本地 SQLite 数据库中。';

  @override
  String get memoryFileDefaultPath => '数据库位置';

  @override
  String get memoryOpenDirectory => '打开数据库目录';

  @override
  String get memoryDisabledTitle => '记忆能力当前已关闭';

  @override
  String get memoryDisabledBody => '你仍然可以在这里维护用户记忆内容；如需在运行时启用，请到设置页记忆板块打开记忆开关。';

  @override
  String get memoryCreatedAtLabel => '创建时间';

  @override
  String get memoryPersistenceSaveFailedTitle => '记忆数据保存失败';

  @override
  String get memoryPersistenceSaveFailedBody =>
      '记忆数据库写入失败，未提交的变更未被应用，请检查数据库访问权限或磁盘状态。';

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
  String mcpDeleteAlsoUninstallPackage(String packageName) {
    return '同时卸载底层包（$packageName）';
  }

  @override
  String get mcpDeleteAlsoUninstallPackageBody => '将卸载全局包并清理隔离缓存。';

  @override
  String mcpDependencyCleanedUp(String packageName) {
    return '$packageName 依赖已清理';
  }

  @override
  String mcpDependencyCleanupFailed(String packageName, String error) {
    return '$packageName 清理失败：$error';
  }

  @override
  String mcpDependencyCleanupError(String packageName, String error) {
    return '$packageName 清理异常：$error';
  }

  @override
  String get mcpTemplateSessionManaged => '会话托管';

  @override
  String mcpTemplateSessionOn(String status) {
    return '会话启用 · $status';
  }

  @override
  String mcpTemplateSessionOff(String status) {
    return '会话关闭 · $status';
  }

  @override
  String get mcpTemplateNotRegistered => '未注册';

  @override
  String mcpTemplateRuntimeEnabledCount(int count) {
    return '会话启用 $count';
  }

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
  String get aiToolResultCompressionThresholdSave => '保存阈值';

  @override
  String get aiToolResultCompressionThresholdSaved => '工具调用输出压缩阈值已更新。';

  @override
  String get aiToolResultCompressionThresholdInvalid => '请输入有效的正整数阈值。';

  @override
  String get aiToolResultCompressionEnabledLabel => '启用工具调用输出压缩';

  @override
  String get aiToolResultCompressionEnabledBody =>
      '控制生成压缩检查点时是否摘要过长工具输出。普通对话始终向模型交付完整结果；关闭后检查点也保留原文，可能增加压缩成本。';

  @override
  String get aiMicroCompressionEnabledLabel => '微压缩';

  @override
  String get aiMicroCompressionEnabledBody =>
      '开启后，仅在生成摘要检查点时将更早的已消费工具结果压成紧凑恢复线索，降低摘要成本；正常对话历史保持稳定，以保护输入缓存命中。关闭后仍会按上方阈值做结构化摘要。';

  @override
  String get aiMessageContentSectionLabel => '消息内容';

  @override
  String get aiMessageContentFormatLabel => '内容格式';

  @override
  String get aiMessageContentFormatBody =>
      '控制 AI 助手消息的展示方式。Markdown 为默认；纯文本性能最优；HTML 由第三方库渲染，token 消耗略高，渲染失败时按下方回退策略降级。';

  @override
  String get aiMessageContentFormatMarkdown => 'Markdown';

  @override
  String get aiMessageContentFormatPlainText => '纯文本';

  @override
  String get aiMessageContentFormatHtml => 'HTML';

  @override
  String get aiMessageContentFormatHtmlTokenWarning =>
      'HTML 模式会向每轮 Prompt 注入额外约束，token 消耗略高。';

  @override
  String get aiHtmlRenderFallbackLabel => 'HTML 渲染失败回退';

  @override
  String get aiHtmlRenderFallbackBody =>
      '当 HTML 解析或渲染异常时，按此策略降级；Markdown 会尝试以 Markdown 解析，PlainText 则直接以纯文本展示。';

  @override
  String get aiHtmlRenderFallbackMarkdown => 'Markdown';

  @override
  String get aiHtmlRenderFallbackPlainText => '纯文本';

  @override
  String get aiHtmlContentRichnessLabel => 'HTML 内容丰富度';

  @override
  String get aiHtmlContentRichnessBody =>
      '控制 HTML 模式下注入给模型的视觉风格强度。适中为默认（克制黑白灰）；丰富放开色彩与卡片；多彩推到极致渐变、玻璃拟态与封面块，token 成本最高。';

  @override
  String get aiHtmlContentRichnessBalanced => '适中';

  @override
  String get aiHtmlContentRichnessRich => '丰富';

  @override
  String get aiHtmlContentRichnessVivid => '多彩';

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
    return '留空则默认 ${seconds}s。仅作无副作用工具的运行时护栏；Task/Bash/写工具使用自身限制。';
  }

  @override
  String get builtinToolRetryLabel => '失败/超时自动重试';

  @override
  String get builtinToolRetryBody =>
      '默认关闭。仅对无副作用工具的真正失败 (failed/timed_out) 自动重试；不会重试参数错误、被拒绝调用、Task、写命令、文件编辑、后台进程、技能变更或记忆写入。';

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
  String tsmDeleteSelectedConfirm(int count) {
    return '将永久删除 $count 个线程及其消息。此操作无法撤销。';
  }

  @override
  String tsmDeleteFailedCount(int count) {
    return '$count 个线程删除失败';
  }

  @override
  String get tsmSessionMissing => '会话不存在或已被删除';

  @override
  String get tsmExportSessionDataTitle => '导出会话数据';

  @override
  String tsmExportingSession(String title) {
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
  String tsmBatchExportSubtitle(int count) {
    return '即将导出 $count 个线程…';
  }

  @override
  String tsmBatchExportDone(int ok, int failed) {
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
  String tsmPreviewMessageCount(int count) {
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
  String tsmSortDisabledHint(String mode) {
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
  String tsmHeaderSubtitle(int count) {
    return '共 $count 个线程 · 长按或拖拽手柄可调整顺序，双击/右键查看更多操作';
  }

  @override
  String tsmSelectedCount(int count) {
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
      '管理内建 Web通用消息平台的监听、鉴权、会话、Web 聊天、健康检查、日志与运维能力。';

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
  String get inputRepairTitle => '输入修复';

  @override
  String get inputRepairBody =>
      '回收遗留的子进程（osascript、LSP、MCP 等），并重置 macOS 输入法上下文，修复全局文本框无法输入、复制、粘贴或 ESC 失效的问题';

  @override
  String get inputRepairButton => '修复输入';

  @override
  String get inputRepairDone => '已重置输入上下文';

  @override
  String inputRepairDoneDetail(int count) {
    return '已重置输入上下文，回收 $count 个后台子进程';
  }

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
  String proxyTestSuccess(int latency, String via) {
    return '连通成功（$latency ms，via $via）';
  }

  @override
  String proxyTestFailure(String reason) {
    return '连通失败：$reason';
  }

  @override
  String get proxyTestEndpointLabel => '测试 URL';

  @override
  String get proxyTestEndpointHint => '默认：https://www.google.com/generate_204';

  @override
  String get proxyTestVerdictDirect => '直连';

  @override
  String proxyTestVerdictProxy(String endpoint) {
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
  String get tokenPopupCostCacheRead => '缓存命中';

  @override
  String get tokenPopupCostCacheWrite => '缓存写入';

  @override
  String get tokenPopupCostTotal => '总计';

  @override
  String get tokenDialUnit => 'Token';

  @override
  String get tokenPopupInputHeading => '输入';

  @override
  String get tokenPopupPrompt => '提示词';

  @override
  String get tokenPopupAudioInput => '音频输入';

  @override
  String get tokenPopupImageInput => '图片输入';

  @override
  String get tokenPopupVideoInput => '视频输入';

  @override
  String get tokenPopupCacheRead => '缓存命中';

  @override
  String get tokenPopupCacheWrite => '缓存写入';

  @override
  String get tokenPopupOutputHeading => '输出';

  @override
  String get tokenPopupCompletion => '回复';

  @override
  String get tokenPopupReasoning => '推理';

  @override
  String get tokenPopupWebSearchHeading => '联网搜索';

  @override
  String get tokenPopupWebSearchCalls => '调用次数';

  @override
  String get tokenPopupWebSearchPages => '返回页面';

  @override
  String get tokenPopupGrandTotal => '总计';

  @override
  String get tokenPopupContextOverview => '上下文数据概览';

  @override
  String get tokenPopupContextMeasured => '总量实测 · 分类折算';

  @override
  String get tokenPopupContextEstimated => '按请求内容估算';

  @override
  String get tokenPopupContextEmpty => '发送下一条消息后生成概览';

  @override
  String get tokenPopupContextSystemPrompt => '系统 Prompt';

  @override
  String get tokenPopupContextBuiltinTools => '内建 Tool';

  @override
  String get tokenPopupContextMcp => 'MCP';

  @override
  String get tokenPopupContextInstructions => '指令';

  @override
  String get tokenPopupContextMemory => '记忆';

  @override
  String get tokenPopupContextSkills => '技能';

  @override
  String get tokenPopupContextHooks => 'Hooks';

  @override
  String get tokenPopupContextConversation => '会话';

  @override
  String get tokenPopupContextRuntime => '运行时';

  @override
  String get tokenPopupContextWindow => '上下文窗口';

  @override
  String get tokenPopupCompactNow => '主动压缩';

  @override
  String get tokenPopupCompacting => '正在压缩…';

  @override
  String get tokenPopupSessionHeading => '会话累计';

  @override
  String get tokenPopupMessages => '消息总数';

  @override
  String get tokenPopupPromptBuilds => '提示词构建';

  @override
  String get tokenPopupPromptChars => '提示词字符';

  @override
  String get tokenPopupCacheHitModeExcludeExpired => '不含过期异常';

  @override
  String get tokenPopupCacheHitModeIncludeExpired => '含过期异常';

  @override
  String tokenPopupExcludedRounds(int count) {
    return '已排除 $count 轮';
  }

  @override
  String get tokenPopupPrefixReuse => '前缀复用';

  @override
  String tokenPopupTooltipFreshReuse(String fresh, int reuse) {
    return '新增 $fresh · 复用 $reuse%';
  }

  @override
  String get tokenPopupFirstRequestShort => '首轮不计';

  @override
  String get tokenPopupFirstRequestNotAveraged => '不参与平均';

  @override
  String get tokenPopupTrendNoData => '尚无缓存命中率数据，发送消息后将在此展示走势。';

  @override
  String get tokenPopupTrendOnlyFirstIgnored => '首轮请求不参与平均，下一轮正常请求后展示趋势。';

  @override
  String get tokenPopupTrendFirstReferenceOnly => '首轮仅作参考，不参与平均缓存命中率。';

  @override
  String get tokenPopupUncached => '未缓存';

  @override
  String get toolbarSessionMetadata => '会话元数据';

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
  String toolbarMcpLazyLoading(int loaded, int total) {
    return 'MCP 已载 $loaded/$total';
  }

  @override
  String snackToolSearchLoaded(int loaded, int total) {
    return 'ToolSearch 已加载 $loaded/$total 个 MCP 工具';
  }

  @override
  String get snackToolSearchLoadedAction => '查看列表';

  @override
  String get snackToolSearchLoadedDialogTitle => 'ToolSearch 已加载的 MCP 工具';

  @override
  String get snackToolSearchLoadedDialogClose => '关闭';

  @override
  String get snackToolSearchLoadedCopyAction => '复制 select:';

  @override
  String get snackToolSearchLoadedCopiedToast => '已复制';

  @override
  String get snackToolSearchLoadedClearAction => '清空已加载列表';

  @override
  String get snackToolSearchLoadedClearedToast => '已清空已加载列表';

  @override
  String get snackToolSearchLoadedGroupOther => '其他（未识别 server）';

  @override
  String get snackToolSearchLoadedCopyGroupAction => '复制本组全部';

  @override
  String get snackToolSearchLoadedTabLoaded => '已加载';

  @override
  String get snackToolSearchLoadedTabHistory => '加载历史';

  @override
  String get snackToolSearchLoadedHistoryEmpty => '本会话还没有 ToolSearch 加载记录';

  @override
  String get snackToolSearchLoadedHistoryQueryPrefix => '加载查询：';

  @override
  String get snackToolSearchLoadedFilterHint => '按名字过滤…';

  @override
  String get snackToolSearchLoadedHistoryFilterHint => '按名字或查询过滤…';

  @override
  String get snackToolSearchLoadedSourceAi => 'AI 会话';

  @override
  String get snackToolSearchLoadedSourceHarness => 'Harness 阶段';

  @override
  String get snackToolSearchLoadedReplayedToast => '已重新发起 ToolSearch';

  @override
  String get snackToolSearchLoadedReplayPendingToast => '即将发起，3 秒内可点击「撤销」';

  @override
  String get snackToolSearchLoadedReplayCancelAction => '撤销';

  @override
  String get snackToolSearchLoadedReplayCancelledToast => '已撤销 — composer 已清空';

  @override
  String get snackToolSearchLoadedSourceFilterAll => '全部';

  @override
  String get snackToolSearchLoadedSourceFilterAi => '仅 AI';

  @override
  String get snackToolSearchLoadedSourceFilterHarness => '仅 Harness';

  @override
  String snackToolSearchLoadedSummary(int queries, int tools) {
    return '本会话已从 $queries 个查询中加载 $tools 个 MCP 工具';
  }

  @override
  String get snackToolSearchLoadedHistoryReplayAction => '把本次复制为 select:…';

  @override
  String get snackToolSearchLoadedHistoryClearAction => '清空历史';

  @override
  String get snackToolSearchLoadedHistoryExportTooltip => '导出历史';

  @override
  String get snackToolSearchLoadedHistoryExportCsv => '复制为 CSV';

  @override
  String get snackToolSearchLoadedHistoryExportMarkdown => '复制为 Markdown';

  @override
  String get snackToolSearchLoadedHistoryExportJson => '复制为 JSON';

  @override
  String get snackToolSearchLoadedHistoryExportSaveCsv => '保存为 CSV…';

  @override
  String get snackToolSearchLoadedHistoryExportSaveMarkdown => '保存为 Markdown…';

  @override
  String get snackToolSearchLoadedHistoryExportSaveJson => '保存为 JSON…';

  @override
  String get snackToolSearchLoadedHistoryExportCsvHint => '适合表格软件；一条 query 一行。';

  @override
  String get snackToolSearchLoadedHistoryExportMarkdownHint =>
      'GitHub 风格表格；贴 Issue / 文档好看。';

  @override
  String get snackToolSearchLoadedHistoryExportJsonHint =>
      '结构化数据；可被 OpenHand 重新导入。';

  @override
  String get toolSearchLoadedHistoryImportTooltip => '导入 JSON 转储';

  @override
  String get toolSearchLoadedHistoryImportDialogTitle => 'ToolSearch 历史导入预览';

  @override
  String toolSearchLoadedHistoryImportDialogCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条记录',
      zero: '无条目',
    );
    return '$_temp0';
  }

  @override
  String get toolSearchLoadedHistoryImportDialogEmpty => '文件中未发现任何条目。';

  @override
  String get toolSearchLoadedHistoryImportDialogClose => '关闭';

  @override
  String snackToolSearchLoadedHistoryExportSavedToast(int count, String path) {
    return '已保存 $count 条到 $path';
  }

  @override
  String snackToolSearchLoadedHistoryExportSaveFailedToast(String error) {
    return '保存失败：$error';
  }

  @override
  String get snackToolSearchLoadedHistoryExportRevealAction => '在访谈器中显示';

  @override
  String get snackToolSearchLoadedHistoryExportEmptyToast => '过滤后历史为空，无可导出。';

  @override
  String snackToolSearchLoadedHistoryExportedToast(int count) {
    return '已复制 $count 条历史到剪贴板。';
  }

  @override
  String get snackToolSearchLoadedHistoryClearedToast => '加载历史已清空';

  @override
  String get mcpLazyLoadingViewLoadedAction => '查看本会话已加载列表';

  @override
  String get mcpToolSearchExportLastDirResetAction => '清除记忆的导出目录';

  @override
  String get mcpToolSearchExportLastDirResetToast => '已清除导出目录记忆';

  @override
  String get mcpLazyLoadingNoActiveSession => '当前没有正在活动的会话';

  @override
  String toolbarPlanStepsCompleted(int completed, int total) {
    return '已完成 $completed/$total 项';
  }

  @override
  String get mdlEdEnterAValidBaseUrlFirst => '请先输入有效的 Base URL';

  @override
  String get mdlEdNoModelsFoundFromThisProvider => '未从该提供商扫描到模型。';

  @override
  String get mdlEdProviderName => '提供商名称';

  @override
  String get mdlEdOptionalEGDeepseekLocalOllama => '可选，如 DeepSeek、本地 Ollama';

  @override
  String get mdlEdCurrentlyActiveModel => '当前活跃模型';

  @override
  String get mdlEdClickToSetAsActiveModel => '点击切换为活跃模型';

  @override
  String get mdlEdTapScanModelsToDiscoverModels => '点击「扫描模型」按钮自动发现可用模型，或手动添加。';

  @override
  String get mdlEdActiveModelId => '当前活跃模型 ID';

  @override
  String get mdlEdTheModelUsedForConversationsSelect =>
      '当前用于对话的模型。可从上方列表选择或直接输入。';

  @override
  String get mdlEdMaxContextTokens => '最大上下文 Token 上限';

  @override
  String get mdlEdOptionalLimitsTheHistorySliceUsed => '可选。用于在压缩时限制历史切片大小。';

  @override
  String get mdlEdEnterAWholeNumberGreaterThan => '请输入大于 0 的整数';

  @override
  String get mdlEdRequestMethod => '请求方式';

  @override
  String get mdlEdOutputMode => '输出模式';

  @override
  String get mdlEdStreaming => '流式输出';

  @override
  String get mdlEdNonStreaming => '非流式输出';

  @override
  String get mdlEdMaxOutputTokens => '最大输出 Token 数';

  @override
  String get mdlEdOptionalUsesAdapterDefaultIfUnset => '可选。不指定则使用适配器默认值。';

  @override
  String get mdlEdTemperature => '温度';

  @override
  String get mdlEd0020Default0 => '0.0 ~ 2.0，默认 0.7';

  @override
  String get mdlEdEnterANumberBetween00 => '请输入 0.0 到 2.0 之间的数值';

  @override
  String get mdlEdCustomHeaders => '自定义请求头';

  @override
  String get mdlEdAdd => '添加';

  @override
  String get mdlEdNoCustomHeadersTapAddTo => '暂无自定义请求头。点击「添加」按钮来添加。';

  @override
  String get mdlEdHeaderName => 'Header 名称';

  @override
  String get mdlEdHeaderValue => 'Header 值';

  @override
  String get mdlEdEditModelProfile => '编辑模型配置';

  @override
  String get mdlEdDisplayName => '显示名称';

  @override
  String get mdlEdOptionalShownInTheUi => '可选，用于界面展示';

  @override
  String get mdlEdDescription => '模型描述';

  @override
  String get mdlEdMultimodalSupport => '多模态支持';

  @override
  String get mdlEdAutoDetect => '自动检测';

  @override
  String get mdlEdYes => '是';

  @override
  String get mdlEdNo => '否';

  @override
  String get mdlEdSupportsAttachments => '支持附件';

  @override
  String get mdlEdReasoningEcho => '携带思考内容回响';

  @override
  String get mdlEdReasoningEchoHint => '控制该模型是否把先前轮次的思考/推理内容回灌到后续 Prompt 历史中。';

  @override
  String get mdlEdSupportedModalities => '支持的模态';

  @override
  String get mdlEdText => '文本';

  @override
  String get mdlEdImage => '图片生成';

  @override
  String get mdlEdVideo => '视频生成';

  @override
  String get mdlEdAudio => '音频生成';

  @override
  String get mdlEdGenerationCapabilities => '生成能力';

  @override
  String get mdlEdPdf => 'PDF 生成';

  @override
  String get mdlEdPpt => 'PPT 生成';

  @override
  String get mdlEdTokenLimits => 'Token 限制';

  @override
  String get mdlEdContextLength => '上下文长度';

  @override
  String get mdlEdSummaryLength => '摘要长度';

  @override
  String get mdlEdOutputLength => '输出长度';

  @override
  String get mdlEdThinkingLength => '思考长度';

  @override
  String get mdlEdTokenPricingUsd1mTokensLeave =>
      'Token 单价（USD / 1M tokens，留空表示未配置）';

  @override
  String get mdlEdInput => '输入价';

  @override
  String get mdlEdOutput => '输出价';

  @override
  String get mdlEdCacheRead => '缓存读取价';

  @override
  String get mdlEdCacheWrite => '缓存写入价';

  @override
  String get mdlEdOpenRouterMetadataOverrides => 'OpenRouter 元数据覆盖';

  @override
  String get mdlEdCanonicalSlug => '规范模型标识';

  @override
  String get mdlEdHuggingFaceId => 'Hugging Face 模型标识';

  @override
  String get mdlEdKnowledgeCutoff => '知识截止日期';

  @override
  String get mdlEdExpirationDate => '过期日期';

  @override
  String get mdlEdSupportedParametersCsv => '支持的参数';

  @override
  String get mdlEdSupportedParametersCsvHint =>
      '例如 input、model、input_type、truncate';

  @override
  String get mdlEdDefaultParametersJson => '默认参数';

  @override
  String get mdlEdDefaultParametersJsonHint => '例如 encoding_format: float';

  @override
  String get mdlEdOpenRouterRawMetadata => 'OpenRouter 原始元数据';

  @override
  String get mdlEdOpenRouterRawMetadataFields =>
      '包含 id、canonical_slug、hugging_face_id、created、architecture、supported_parameters、default_parameters、supported_voices、knowledge_cutoff、expiration_date 和 links';

  @override
  String get mdlEdReset => '重置';

  @override
  String get mdlEdCancel => '取消';

  @override
  String get mdlEdOk => '确定';

  @override
  String get tlCallDir => '目录';

  @override
  String get tlCallElapsed => '耗时';

  @override
  String get tlCallExit => '退出码';

  @override
  String get tlCallToolInput => '工具入参';

  @override
  String get tlCallCommand => '命令';

  @override
  String get tlCallArguments => '入参';

  @override
  String get tlCallToolOutput => '结果输出';

  @override
  String get tlCallNoOutputYet => '暂无输出';

  @override
  String get tlCallResult => '结果';

  @override
  String get tlCallStdout => '标准输出';

  @override
  String get tlCallStderr => '标准错误';

  @override
  String get tlCallArgumentsConstructing => '参数构造中…';

  @override
  String get tlCallArgumentsConstructingHint =>
      '正在跟随模型输出实时拼装入参，参数构造完成后会自动切回正常状态。';

  @override
  String get tlCallCollectedParameters => '已采集参数';

  @override
  String get tlCallNoParametersYet => '尚未解析到入参';

  @override
  String get tlCallSubmitting => '提交中…';

  @override
  String get tlCallSubmittingHint => '已采集参数完毕，正在交给执行器';

  @override
  String get tlCallThereIsNoToolOutputYet => '当前还没有工具输出。';

  @override
  String get tlCallViewInDialog => '在弹窗里查看完整内容';

  @override
  String get tlCallEmptyContent => '内容为空';

  @override
  String get fileMutationSection => '文件变动';

  @override
  String fileMutationFilesChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个文件已更改',
    );
    return '$_temp0';
  }

  @override
  String fileMutationFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个文件',
    );
    return '$_temp0';
  }

  @override
  String get fileMutationUndoAll => '撤销全部';

  @override
  String get fileMutationRefresh => '刷新状态';

  @override
  String get fileMutationCopyAllDiff => '复制全部 diff';

  @override
  String get fileMutationCopyAllDiffDone => '全部 diff 已复制到剪贴板';

  @override
  String get fileMutationRevealLedger => '在文件管理器中查看 ledger.jsonl';

  @override
  String get fileMutationCopyPath => '复制文件路径';

  @override
  String get fileMutationPathCopied => '路径已复制';

  @override
  String fileMutationRevealMore(int count) {
    return '还有 $count 条变更未展示，点击继续展开';
  }

  @override
  String get fileMutationRevealAll => '全部展开';

  @override
  String get fileMutationHistoryInspector => '历史检查器';

  @override
  String get fileMutationHistoryInspectorTitle => '会话文件变更历史';

  @override
  String get fileMutationHistoryInspectorFilterHint => '按路径过滤…';

  @override
  String get fileMutationHistoryInspectorEmpty => '没有匹配过滤条件的文件变更。';

  @override
  String get fileMutationHistoryInspectorZoomIn => '只看该路径';

  @override
  String get fileMutationHistoryInspectorZoomOut => '返回全部路径';

  @override
  String get fileMutationUndone => '已撤销';

  @override
  String get fileMutationCascadeUndone => '级联失效';

  @override
  String get fileMutationUndoThis => '撤销此次修改';

  @override
  String get fileMutationRedo => '重做';

  @override
  String get fileMutationUndoFailed => '撤销失败';

  @override
  String get fileMutationRedoFailed => '重做失败';

  @override
  String get fileMutationSnapshotUnavailable => '内容快照不可用';

  @override
  String get tlCallTool => '工具';

  @override
  String get tlCallSkill => '技能';

  @override
  String get tlCallStopped => '已停止';

  @override
  String get tlCallStopRequest => '终止此工具调用';

  @override
  String get tlCallBlocked => '已拦截';

  @override
  String get tlCallRejected => '用户拒绝';

  @override
  String get tlCallInvalid => '参数无效';

  @override
  String get tlCallToolCall => '工具调用';

  @override
  String get tlCallRunning => '运行中';

  @override
  String get tlCallSucceeded => '执行成功';

  @override
  String get tlCallDenied => '已被禁止';

  @override
  String get tlCallTimedOut => '执行超时';

  @override
  String get tlCallFailed => '执行失败';

  @override
  String get tlCallToolIsRunningWaitingForOutput => '工具运行中，等待新的输出...';

  @override
  String get tlCallExpandToInspectToolOutput => '点击展开查看工具输出';

  @override
  String get tlCallSelfLearning => '自我学习';

  @override
  String get tlCallNudgeRecovered => '已纠正\"光说不做\"';

  @override
  String get tlCallProfileChanges => '用户画像变更';

  @override
  String get tlCallMemoryChanges => '记忆变更';

  @override
  String get tlCallSkillChanges => '技能变更';

  @override
  String get tlCallProfileDiff => '画像差异摘要';

  @override
  String get tlCallNoChanges => '无变更';

  @override
  String get tlCallUnnamed => '(未命名)';

  @override
  String get tlCallJustNow => '刚刚';

  @override
  String get sessMetaCacheHitTrend => '缓存命中率趋势';

  @override
  String get sessMetaCacheHitLast => '末轮';

  @override
  String get sessMetaCacheHitAvg => '平均';

  @override
  String get sessMetaCacheHitMax => '峰值';

  @override
  String get sessMetaCacheHitOverlayOn => '叠加另一条公式';

  @override
  String get sessMetaCacheHitOverlayOff => '隐藏叠加公式';

  @override
  String get sessMetaCacheHitFormulaClaude => 'Claude 公式';

  @override
  String get sessMetaCacheHitFormulaOpenAi => 'OpenAI 公式';

  @override
  String sessMetaCacheHitPoint(int index) {
    return '第 $index 轮';
  }

  @override
  String get sessMetaMessages => '消息总数';

  @override
  String get sessMetaPromptBuilds => 'Prompt 构建';

  @override
  String get sessMetaCompressions => '压缩次数';

  @override
  String get sessMetaTotalTokens => '总 Token';

  @override
  String get sessMetaMode => '当前模式';

  @override
  String get sessMetaRuntimeTools => '运行工具';

  @override
  String get sessMetaPending => '未展示';

  @override
  String get sessMetaCurrentSessionMetadata => '当前会话元数据';

  @override
  String get sessMetaSessionOverview => '会话概览';

  @override
  String get sessMetaExtendedMetadata => '扩展元数据';

  @override
  String get sessMetaStatistics => '统计信息';

  @override
  String get sessMetaUser => '用户';

  @override
  String get sessMetaAssistant => '助手';

  @override
  String get sessMetaTool => '工具';

  @override
  String get sessMetaSkill => '技能';

  @override
  String get sessMetaCompression => '压缩';

  @override
  String get sessMetaEnvironment => '运行环境';

  @override
  String get sessMetaCommandPolicy => '命令策略';

  @override
  String get sessMetaPromptMetadataIsNotAvailableYet => '当前还没有可展示的 prompt 元数据。';

  @override
  String get sessMetaWriteConfirmation => '写命令确认';

  @override
  String get sessMetaRequired => '需要确认';

  @override
  String get sessMetaNotRequired => '无需确认';

  @override
  String get sessMetaAllowRules => '允许规则数';

  @override
  String get sessMetaThereAreNoSurfacedAllowCommand => '当前没有已上屏的允许命令规则。';

  @override
  String get sessMetaRuntimeOrchestration => '运行时编排';

  @override
  String get sessMetaStateSource => '状态来源';

  @override
  String get sessMetaGeneratedFromTheCurrentModelMcp =>
      '根据当前模型、MCP/Skills 与 Plan 状态即时生成';

  @override
  String get sessMetaTheLastPersistedRuntimeSnapshot => '上一轮已落盘的运行时快照';

  @override
  String get sessMetaToolCatalogState => '工具目录状态';

  @override
  String get sessMetaGateReason => '门控原因';

  @override
  String get sessMetaRuntimeToolCount => '当前运行时工具数';

  @override
  String get sessMetaRefreshesNextRound => '等待下一轮刷新';

  @override
  String get sessMetaRuntimeNotices => '运行时 Notices';

  @override
  String get sessMetaCurrentRuntimeTools => '当前运行时工具';

  @override
  String get sessMetaTaskTracking => '任务跟踪';

  @override
  String get sessMetaCurrentTodos => '当前 Todo 数量';

  @override
  String get sessMetaPlanRecords => '计划记录数量';

  @override
  String get sessMetaTodowriteReminder => 'TodoWrite 强提醒';

  @override
  String get sessMetaTriggered => '已触发';

  @override
  String get sessMetaNotTriggered => '未触发';

  @override
  String get sessMetaUnavailable => '暂无数据';

  @override
  String get sessMetaReminderReason => '提醒原因';

  @override
  String get sessMetaPlanHistory => '计划历史';

  @override
  String get sessMetaRecentErrors => '最近异常';

  @override
  String get sessMetaThereAreNoSessionErrorsTo => '当前没有需要关注的会话异常。';

  @override
  String get sessMetaLastPromptMetadata => '最后一次 Prompt 元数据';

  @override
  String get sessMetaClose => '关闭';

  @override
  String get sessMetaPendingApproval => '待确认';

  @override
  String get sessMetaInProgress => '进行中';

  @override
  String get sessMetaCompleted => '已完成';

  @override
  String get sessMetaFailed => '失败';

  @override
  String get sessMetaCancelled => '已取消';

  @override
  String get sessMetaCreated => '创建';

  @override
  String get sessMetaUpdated => '更新';

  @override
  String get sessMetaErrorDetail => '错误细节';

  @override
  String get commonDetails => '详情';

  @override
  String get commonCopy => '复制';

  @override
  String get commonViewDetails => '查看详情';

  @override
  String get commonCopiedToClipboard => '已复制到剪贴板';

  @override
  String get structuredErrorWhy => '原因：';

  @override
  String get structuredErrorTry => '建议：';

  @override
  String get structuredErrorServerSays => '服务端原文：';

  @override
  String get structuredErrorRaw => '原始错误：';

  @override
  String get sessMetaPresented => '已展示';

  @override
  String get sessMetaThisSessionEndedEarlyRetryThe =>
      '当前会话已提前结束。请重试或继续发送更具体的指令。';

  @override
  String get sessMetaToolCallsStoppedForSafety => '工具调用已安全停止';

  @override
  String get sessMetaOpenhandStoppedThisSessionForSafety =>
      '本次会话连续触发了过多轮工具调用，OpenHand 已为安全起见提前停止。这次停止发生在会话控制层，并不是某个具体工具真的执行失败。你可以让助手先总结当前进展，或给出更具体的下一步指令。';

  @override
  String get sessMetaResponseInterrupted => '回答已中断';

  @override
  String get sessMetaTheResponseWasInterruptedWhileStreaming =>
      '本次回答在流式接收过程中异常中断，当前会话已停止。你可以直接重试，或继续发送下一条消息。';

  @override
  String get sessMetaRequestFailed => '请求发送失败';

  @override
  String get sessMetaTheRequestFailedBeforeTheAssistant =>
      '本次请求在发送阶段失败，当前会话未继续执行。你可以检查配置后重试，或继续发送新的消息。';

  @override
  String get sessMetaContinuationFailed => '后续请求失败';

  @override
  String get sessMetaTheSessionFailedWhileRequestingThe =>
      '本次会话在继续执行后续步骤时，请求下一轮模型响应失败。已完成的步骤与工具结果都已保留，你可以直接回复继续/重试，或检查配置后再试。';

  @override
  String get sessMetaSafetyStop => '安全停止';

  @override
  String get sessMetaStreamError => '响应中断';

  @override
  String get sessMetaRequestError => '请求失败';

  @override
  String get sessMetaContinuationError => '后续请求失败';

  @override
  String get sessMetaToolExecutionError => '工具执行失败';

  @override
  String get sessMetaCompressionError => '历史压缩失败';

  @override
  String get sessMetaPromptBlocked => '提示词被拦截';

  @override
  String get sessMetaTitleGenerationError => '标题生成失败';

  @override
  String get sessMetaSessionError => '会话异常';

  @override
  String get auditNoData => '无数据';

  @override
  String get auditCopyJson => '复制 JSON';

  @override
  String get auditCopiedToClipboard => '已复制到剪贴板';

  @override
  String get auditMessageAudit => '消息审计';

  @override
  String get auditClose => '关闭';

  @override
  String get auditOverview => '基本信息';

  @override
  String get auditMessageId => '消息 ID';

  @override
  String get auditSessionId => '会话 ID';

  @override
  String get auditRole => '角色';

  @override
  String get auditKind => '类型';

  @override
  String get auditCharacterCount => '字符数';

  @override
  String get auditStreaming => '是否流式';

  @override
  String get auditDeleted => '是否已删除';

  @override
  String get auditHasError => '是否报错';

  @override
  String get auditTiming => '时间与耗时';

  @override
  String get auditStartedCreated => '开始/创建时间';

  @override
  String get auditEnded => '结束时间';

  @override
  String get auditDurationMs => '耗时 (ms)';

  @override
  String get auditModelTokens => '模型与 Token';

  @override
  String get auditModelId => '模型 ID';

  @override
  String get auditModelLabel => '模型标签';

  @override
  String get auditTotalTokens => '总 Token';

  @override
  String get auditCacheHitRatio => '缓存命中率';

  @override
  String get auditPromptTokens => '输入 Token';

  @override
  String get auditCompletionTokens => '输出 Token';

  @override
  String get auditTokenBreakdown => 'Token 明细';

  @override
  String get auditError => '错误信息';

  @override
  String get auditContent => '消息内容';

  @override
  String get auditFullComposedPromptThatWasActually =>
      '以下为该轮用户消息触发时，程序自动拼装后最终发送给 AI 的 prompt 完全体（含系统指令 / 工具目录 / 用户记忆 / 历史上下文 / 用户输入等）。';

  @override
  String get auditWaitingForComposedPromptInjectionAuto =>
      '正在等待本轮最终组合 Prompt 注入（发送中会自动刷新）';

  @override
  String get auditUserRawInput => '用户原始输入';

  @override
  String get auditStructuredPromptTurns => '结构化 Prompt Turns';

  @override
  String get auditNone => '无';

  @override
  String get auditPromptMetadata => 'Prompt Metadata';

  @override
  String get auditRequest => '请求参数';

  @override
  String get auditMethod => '方法';

  @override
  String get auditHeaders => '请求头';

  @override
  String get auditNotCapturedEnableSettingsAiTelemetry =>
      '未捕获（请在设置 → AI → 遥测 中开启调试）';

  @override
  String get auditBodyQueryPath => '请求体 / Query / Path';

  @override
  String get auditRawAiResponse => '原始 AI 响应';

  @override
  String get auditExpandRawResponse => '展开查看原始响应';

  @override
  String get auditNotCapturedDebugDisabledOrResponse => '未捕获：调试未开启或模型未提供原始响应';

  @override
  String get auditAttachments => '附件';

  @override
  String get auditAttachmentList => '附件列表';

  @override
  String get auditNoAttachments => '无附件';

  @override
  String get auditFullMetadata => '完整元数据 (metadata)';

  @override
  String get auditMessageMetadata => '消息元数据';

  @override
  String get auditSessionEnvironment => '会话环境';

  @override
  String get auditEnvironmentSnapshot => '环境快照';

  @override
  String get auditAuditSnapshotCopied => '审计快照已复制';

  @override
  String get auditCopyAuditSnapshot => '复制审计快照';

  @override
  String get auditSessionMetadataSaved => '会话元数据已更新';

  @override
  String get auditSessionAudit => '会话审计';

  @override
  String get auditTemplate => '模板';

  @override
  String get auditCreatedAt => '创建时间';

  @override
  String get auditUpdatedAt => '更新时间';

  @override
  String get auditMessages => '消息数';

  @override
  String get auditLastModel => '最近模型';

  @override
  String get auditTitleEditable => '标题编辑';

  @override
  String get auditSessionTitle => '会话标题';

  @override
  String get auditSaveTitle => '保存标题';

  @override
  String get auditSessionMetadataEditableJson => '会话元数据 (可编辑 JSON)';

  @override
  String get auditSaveWritesBackThroughTheSession =>
      '修改后点击保存将通过会话控制器写回数据库并实时刷新 UI。删除的 key 会被清除。';

  @override
  String get auditSaveMetadata => '保存元数据';

  @override
  String get auditRuntimePromptMetadataReadOnly => '运行时 Prompt 元数据 (只读)';

  @override
  String get auditUsefulForPromptConstructionTroubleshooti =>
      '用于排查本轮消息拼装上下文；自动由系统写入。';

  @override
  String get auditLastPromptMetadata => 'last_prompt_metadata';

  @override
  String get auditNoRuntimePromptMetadataYet => '暂无运行时 Prompt 元数据';

  @override
  String get auditEnvironment => '会话环境';

  @override
  String get auditErrorList => '错误列表';

  @override
  String get auditNoErrorsRecorded => '暂无错误';

  @override
  String get auditTapARowToInspectA => '点击单条可打开消息审计弹窗；支持删除单条消息。';

  @override
  String get auditNoMessages => '暂无消息';

  @override
  String get auditAudit => '审计';

  @override
  String get auditDelete => '删除';

  @override
  String get progExpFESelectOpenedFile => '定位到已打开文件';

  @override
  String get progExpFEExpandSelected => '展开选中目录';

  @override
  String get progExpFECollapseAll => '全部折叠';

  @override
  String get progExpFETypeASymbolNameToSearch => '输入符号名后即可在当前工作区内跨文件搜索。';

  @override
  String get progExpFENoWorkspaceSymbolBackendIsAvailable =>
      '当前文件没有可用的工作区符号后端。';

  @override
  String get progExpFENoMatchingWorkspaceSymbolsWereFound => '没有找到匹配的工作区符号。';

  @override
  String get progExpFEFetchingWorkspaceSymbolsFailedConfirmTha =>
      '读取工作区符号失败，请确认对应语言服务器支持 workspace/symbol。';

  @override
  String get progExpFEThisFileIsStillInLarge =>
      '当前文件仍处于大文件预览模式，符号栏暂使用本地提取以保持响应速度。';

  @override
  String get progExpFENoLspSymbolBackendIsAvailable =>
      '当前文件没有可用的 LSP 符号后端，已回退到本地符号提取。';

  @override
  String get progExpFETheLspServerReturnedAnEmpty => 'LSP 已返回空符号列表。';

  @override
  String get progExpFEFetchingLspSymbolsFailedSoThe =>
      '读取 LSP 符号失败，已回退到本地符号提取。';

  @override
  String get progExpFERenameSymbol => '重命名符号';

  @override
  String get progExpFEReviewTheDiffForThisRename => '先查看这次重命名将影响的差异，再决定是否应用。';

  @override
  String get progExpFETheRenameWasCancelledAndNo => '已取消本次重命名，未写入任何修改。';

  @override
  String get progExpFETheSymbolAtTheCurrentCursor => '当前光标位置不支持重命名。';

  @override
  String get progExpFETheLanguageServerDidNotReturn => '语言服务器没有返回需要应用的修改。';

  @override
  String get progExpFECodeActions => '代码操作';

  @override
  String get progExpFENoCodeActionsAreAvailableAt => '当前光标位置没有可用的代码操作。';

  @override
  String get progExpFEReviewTheDiffFromThisCode => '先预览该代码操作将要写入的差异，再决定是否应用。';

  @override
  String get progExpFEIfTheLanguageServerCommandRequests =>
      '如果语言服务器命令在执行过程中请求写入修改，也会先展示差异预览。';

  @override
  String get progExpFETheCodeActionWasCancelledAnd => '已取消本次代码操作，未写入任何修改。';

  @override
  String get progExpFEExecutedTheLanguageServerCommand => '已执行语言服务器命令。';

  @override
  String get progExpFESomeLanguageServerRequestedEditsWere => '有语言服务器请求的修改被跳过。';

  @override
  String get progExpFEThisCodeActionDidNotReturn => '该代码操作没有返回可应用的编辑。';

  @override
  String get progExpFEQuickFix => '快速修复';

  @override
  String get progExpFENoQuickFixesAreAvailableFor => '当前诊断位置没有可用的快速修复。';

  @override
  String get progExpFENoCodeActionsAreAvailableFor => '当前诊断位置没有可用的代码操作。';

  @override
  String get progExpFENoQuickFixesAreAvailableFor2 => '当前诊断行没有可用的快速修复。';

  @override
  String get progExpFETheCurrentFileIsStillLoading =>
      '当前文件尚未完成加载，暂时无法执行 LSP 操作。';

  @override
  String get progExpFEThisFileIsStillInLarge2 =>
      '当前文件仍处于大文件预览模式，请先切换到完整编辑器后再执行 LSP 跳转。';

  @override
  String get progExpFETheCurrentFileIsStillLoading2 =>
      '当前文件尚未完成加载，暂时无法执行文档级编辑操作。';

  @override
  String get progExpFEThisFileIsStillInLarge3 =>
      '当前文件仍处于大文件预览模式，请先切换到完整编辑器后再执行格式化。';

  @override
  String get progExpFEFormatDocument => '格式化文档';

  @override
  String get progExpFETheCurrentFileIsNotReady => '当前文件尚未准备好，稍后再试。';

  @override
  String get progExpFETheFormatterDidNotReturnAny => '格式化器没有返回可应用的修改。';

  @override
  String get progExpFEFormattingProducedTheSameContentSo =>
      '格式化结果与当前内容一致，没有产生新的文本变更。';

  @override
  String get progExpFEGoToDefinition => '定义跳转';

  @override
  String get progExpFENoDefinitionWasFoundAtThe => '当前光标位置没有找到定义。';

  @override
  String get progExpFEMultipleDefinitionsWereFoundChooseA =>
      '找到多个定义结果，请选择要跳转的位置。';

  @override
  String get progExpFEFindReferences => '引用查找';

  @override
  String get progExpFENoReferencesWereFoundAtThe => '当前光标位置没有找到引用。';

  @override
  String get progExpFEHoverInfo => '悬浮信息';

  @override
  String get progExpFEThereIsNoHoverInformationAt => '当前光标位置没有可显示的悬浮信息。';

  @override
  String get progExpFELspBackend => 'LSP 后端';

  @override
  String get progExpFEReResolveTheBackendForThe => '重新解析当前文件后端';

  @override
  String get progExpFEInspectBackendDetails => '查看后端详情';

  @override
  String get progExpFECloseEsc => '关闭 (Esc)';

  @override
  String get progExpFEToggleComment => '切换注释';

  @override
  String get progExpFEThisLanguageDoesNotHaveA => '当前语言暂未配置注释策略，无法执行注释切换。';

  @override
  String get progExpFEGoToImplementation => '跳转到实现';

  @override
  String get progExpFESignatureHelp => '参数信息';

  @override
  String get progExpFEThereIsNoSignatureHelpAvailable => '当前光标位置没有可显示的参数签名信息。';

  @override
  String get progExpFEPreviousMatch => '上一个结果';

  @override
  String get progExpFENextMatch => '下一个结果';

  @override
  String get progExpFEMatchCase => '区分大小写';

  @override
  String get progExpFEShowReplace => '显示替换';

  @override
  String get progExpFEReplaceCurrent => '替换当前结果';

  @override
  String get progExpFEReplaceAll => '全部替换';

  @override
  String get progExpFECurrentFileSymbols => '当前文件符号';

  @override
  String get progExpFEWorkspaceSymbols => '工作区符号';

  @override
  String get progExpFERefreshDiagnostics => '刷新诊断';

  @override
  String get progExpFESymbols => '符号';

  @override
  String get progExpFESymbolNavigationShiftCmdCtrlO =>
      '符号导航 (Shift+Cmd/Ctrl+O)';

  @override
  String get progExpFEWorkspace => '全局符号';

  @override
  String get progExpFEWorkspaceSymbolSearchCmdCtrlT => '工作区符号搜索 (Cmd/Ctrl+T)';

  @override
  String get progExpFEShowDiagnosticsForTheCurrentFile => '显示当前文件诊断';

  @override
  String get progExpFEInspectTheLspBackendBoundTo => '查看当前文件绑定的 LSP 后端';

  @override
  String get progExpFEDef => '定义';

  @override
  String get progExpFEGoToDefinitionF12CmdCtrl => '定义跳转 (F12 / Cmd/Ctrl+B)';

  @override
  String get progExpFERefs => '引用';

  @override
  String get progExpFEFindReferencesShiftF12CmdCtrl =>
      '引用查找 (Shift+F12 / Cmd/Ctrl+Shift+B)';

  @override
  String get progExpFEHover => '悬浮';

  @override
  String get progExpFEHoverInfoCmdCtrlI => '悬浮信息 (Cmd/Ctrl+I)';

  @override
  String get progExpFERename => '重命名';

  @override
  String get progExpFERenameSymbolF2 => '重命名符号 (F2)';

  @override
  String get progExpFEActions => '操作';

  @override
  String get progExpFECodeActionsCmdCtrl => '代码操作 (Cmd/Ctrl+.)';

  @override
  String get progExpFEFormat => '格式化';

  @override
  String get progExpFENoImplementationWasFoundAtThe => '当前光标位置没有找到实现。';

  @override
  String get progExpFEMultipleImplementationsFoundChooseATarge =>
      '找到多个实现，请选择要跳转的位置。';

  @override
  String get progExpFERefactor => '重构';

  @override
  String get progExpFEReviewTheChangesBeforeApplying => '查看此次重构将影响的差异，再决定是否应用。';

  @override
  String get progExpFESaveFile => '保存文件';

  @override
  String get progExpFECloseEditorReturnToSession => '关闭编辑器，返回会话';

  @override
  String get progExpFEShowQuickFixesForThisDiagnostic => '显示该诊断行的快速修复';

  @override
  String get progExpFELargeFilePerformanceModeIsActive =>
      '已启用大文件性能模式：使用虚拟化只读预览，避免整篇文本布局导致卡顿。';

  @override
  String get progExpFEOpenFullEditorAnyway => '仍然打开完整编辑器';

  @override
  String get settingsShortcuts => '快捷键';

  @override
  String get settingsConfigureKeyCombinationsForCommonActions =>
      '为常用操作配置组合键。当前最多支持同时按下 4 个按键。';

  @override
  String get settingsBuiltInTools => '内建工具';

  @override
  String get settingsCrons => '定时任务';

  @override
  String get settingsControlsRetentionAndColdStartCleanup =>
      '控制定时任务执行历史的保留与冷启动清理。清理 worker 仅在冷启动后异步运行一次，带有超时兜底、独享运行锁、异常全部 silentLog，避免资源泄露与无限重试。';

  @override
  String get settingsHermesTalker => 'Hermes Talker';

  @override
  String get settingsConfigureHermesTalkerSelfLearningEvery =>
      '配置 Hermes Talker 线程模板的自主学习：每 5 分钟扫描最近 7 天的会话，在后台派发受限子 Agent 更新记忆与技能。';

  @override
  String get settingsEditor => '编辑器';

  @override
  String get settingsManagePerLanguageLspBackendsInstall =>
      '管理各编程语言的 LSP 后端、安装根路径与下载辅助配置。保存后的配置会直接用于文件编辑器内的跳转、诊断、重命名和代码操作。';

  @override
  String get settingsAppData => '应用数据';

  @override
  String get settingsPerResponseToolCallLimit => '单轮工具调用上限';

  @override
  String get settingsSaveLimit => '保存上限';

  @override
  String get settingsSequentialToolRoundLimit => '连续工具轮次上限';

  @override
  String get settingsSessionSettings => '会话设置';

  @override
  String get settingsConfigureDefaultBehaviourForNewSessions =>
      '配置新会话的默认行为，包括超时时间、标题获取、默认模式与权限。';

  @override
  String get settingsSendTimeoutS => '发送超时（秒）';

  @override
  String get settingsMaximumWaitTimeToEstablishThe =>
      '建立 HTTP 连接并完成请求发送的最大等待时间，默认 60 秒。';

  @override
  String get settingsSaveTimeout => '保存超时';

  @override
  String get settingsResponseTimeoutS => '响应超时（秒）';

  @override
  String get settingsMaximumWaitForACompleteResponse =>
      '非流式请求等待完整响应的最大时间，默认 120 秒。';

  @override
  String get settingsStreamIdleTimeoutS => '等待超时（秒）';

  @override
  String get settingsMaximumIdleWaitBetweenStreamChunks =>
      '流式响应中两次数据块之间的最大空闲等待时间，超时将中断请求并显示\"Request timed out.\"，默认 120 秒。';

  @override
  String get settingsAutoTitle => '自动获取标题';

  @override
  String get settingsWhenEnabledATitleIsAutomatically =>
      '开启后，新会话发送首条有效文本消息时将自动获取会话标题。';

  @override
  String get settingsTitleFetchMode => '获取标题方式';

  @override
  String get settingsTitleFetchModeDescription =>
      '异步不会阻塞首轮回复；同步会先获取标题，再发送首轮 AI 请求。';

  @override
  String get settingsTitleFetchModeAsync => '异步';

  @override
  String get settingsTitleFetchModeSync => '同步';

  @override
  String get settingsDefaultSessionMode => '默认会话模式';

  @override
  String get settingsDefaultInteractionModeForNewSessions =>
      '新会话的默认交互模式：对话（Chat）或规划（Plan）。';

  @override
  String get settingsChat => '对话';

  @override
  String get settingsPlan => '规划';

  @override
  String get settingsDefaultFullAccess => '默认全访问权限';

  @override
  String get settingsWhenEnabledNewSessionsStartIn =>
      '开启后，新会话将默认使用全访问权限模式，允许 AI 直接执行文件与命令操作而无需逐一确认。';

  @override
  String get settingsUserProfile => '用户画像';

  @override
  String get settingsMaintainAGlobalUserProfileLanguage =>
      '维护用于全局会话的用户画像（语言风格、关注领域、交流偏好等）。设置非空时，所有线程模板的内建系统提示词都会自动携带画像上下文，使 AI 回复更贴近你的习惯；自我学习也会增量更新这份画像。';

  @override
  String get settingsModelProviderManagement => '模型提供商管理';

  @override
  String get settingsAddSelectTestAndMaintainModel =>
      '新增、选择、测试并维护当前可用的模型提供商配置。每个提供商可包含多个模型。';

  @override
  String get settingsCompressionTrigger => '压缩触发阈值';

  @override
  String get settingsOnceTheUncompressedHistoryInA =>
      '当线程中尚未被压缩的历史消息字符总数超过这个值时，系统会生成新的摘要检查点。';

  @override
  String get settingsToolCallOutputCompressionThreshold => '工具调用输出压缩阈值';

  @override
  String get settingsWhenAToolCallReturnsMore =>
      '仅用于生成压缩检查点：超过阈值的历史工具结果会转为结构化摘要。普通对话始终向模型交付完整结果。默认 1024。';

  @override
  String get settingsDefaultsTo40IfOneAssistant =>
      '默认 40 次。一次人机对话响应过程中，如果工具调用总次数超过这个阈值，系统会追加警告消息并安全终止本轮响应。';

  @override
  String get settingsDefaultsTo24RoundsIfThe =>
      '默认 24 轮。一次会话中，如果助手在工具执行后又连续请求下一轮工具，达到这个轮次数时系统会安全停止，避免陷入无限工具回环。';

  @override
  String get settingsImageSizeLimit => '图片大小上限';

  @override
  String get settingsDefaultsTo1mbImageAttachmentsLarger =>
      '默认 1MB。用户附加的图片若超过这个大小，会在弹出图片编辑器之前先按比例自动压缩，并最终落盘到该上限以内，避免会话与提示词膨胀。';

  @override
  String get settingsCostControl => '成本控制';

  @override
  String get settingsReduceTokenCostsByFreezingThe =>
      '通过稳定 Prompt 静态前缀与协议层缓存提示来降低 token 成本。开启后：首条有效用户消息开始收到 AI 响应时，会锁定服务商、模型与推理强度；Prompt Builder 会尽量保持系统提示、工具目录、记忆、指令等稳定前置；Anthropic 协议会注入 cache_control 断点，OpenAI-compatible 请求会使用稳定缓存亲和键与 messages 末尾布局。';

  @override
  String get settingsEnableInputCache => '启用输入缓存';

  @override
  String get settingsDisabledByDefaultWhenEnabledEvery =>
      '默认开启。关闭后不会注入协议层缓存提示，也不会执行模型锁定等输入缓存保护。若要最大化命中率，请避免在会话中途频繁修改工具、技能、MCP、记忆或指令。';

  @override
  String get settingsCacheBreakpointUpdateMode => '历史候选点更新模式';

  @override
  String get settingsChooseTheSlidingUnitForThe =>
      '稳定锚、上一请求尾锚和当前尾锚会自动优先保留；此设置仅决定剩余预算如何选择历史候选点。';

  @override
  String get settingsByMessageCountUserAssistant => '按消息条数 (user+assistant)';

  @override
  String get settingsByUserMessageCountOnly => '按用户消息条数';

  @override
  String get settingsByAccumulatedTokens => '按累计 tokens';

  @override
  String get settingsCacheBreakpointUpdateInterval => '历史候选点更新间隔';

  @override
  String get settingsDefault10MeaningDependsOnThe =>
      '默认 10，仅用于自动选择历史候选点。含义随上方模式变化：消息条数 / 用户消息条数 / tokens 阈值。';

  @override
  String get settingsSave => '保存';

  @override
  String get settingsCacheBreakpointCount => '缓存断点数量';

  @override
  String get settingsDefault4Range14Anthropic =>
      '默认 4，范围 1-4。Anthropic 协议按稳定系统/工具锚、上一请求尾锚、当前尾锚、历史候选点的顺序使用预算，且每个请求最多支持 4 个 cache_control 断点。OpenAI-compatible 服务商不会注入该标记。';

  @override
  String get settingsCommandSafety => '命令安全';

  @override
  String get settingsControlWriteCommandConfirmationForBash =>
      '控制 bash 工具是否需要写命令确认，并集中管理禁止命令规则。';

  @override
  String get settingsWriteCommandConfirmation => '写命令确认';

  @override
  String get settingsEnabledByDefaultWhenTheAi =>
      '默认开启。AI 调用 bash 工具执行可能修改文件或系统状态的命令时，会先弹窗等待你确认。';

  @override
  String get settingsAllowCommandList => '允许命令列表';

  @override
  String get settingsMatchingWriteLikeBashCommandsSkip =>
      '匹配到的写类 bash 命令会跳过确认弹窗直接执行。只适合长期明确放行的稳定命令模式。';

  @override
  String get settingsAddAllowRule => '新增允许规则';

  @override
  String get settingsNoAllowRulesConfigured => '当前没有允许命令规则';

  @override
  String get settingsAddARuleToLetMatching => '新增规则后，匹配到的写命令将跳过确认弹窗。';

  @override
  String get settingsDenyCommandList => '禁止命令列表';

  @override
  String get settingsMatchingBashCommandsAreBlockedBefore =>
      '匹配到的 bash 命令将不会真正执行，而是把“被用户禁止”这一结果直接返回给模型。支持正则和简单通配写法，例如 `rm *`。';

  @override
  String get settingsAddRule => '新增规则';

  @override
  String get settingsNoDenyRulesConfigured => '当前没有禁止命令规则';

  @override
  String get settingsAddARuleToBlockMatching => '新增规则后，匹配到的 bash 命令会被直接拦截。';

  @override
  String get settingsTelemetry => '遥测';

  @override
  String get settingsWhenEnabledOpenhandCapturesRawAi =>
      '开启后会捕获每条 AI 消息的原始响应、请求参数、耗时、错误等调试数据，方便在消息/会话审计弹窗中排查问题。';

  @override
  String get settingsDebugMode => '开启调试';

  @override
  String get settingsOffByDefaultWhenEnabledEvery =>
      '默认关闭。开启后，在所有线程模板的消息卡片上鼠标悬停/聚焦时会显示【审计】按钮，会话顶部也会新增会话审计入口。';

  @override
  String get settingsCaptureRawPayload => '捕获原始响应';

  @override
  String get settingsEnabledByDefaultOnlyActiveWhen =>
      '默认开启。仅当调试开启时生效，将 AI 响应的原始 JSON/SSE 片段一并写入消息元数据，便于审计。';

  @override
  String get settingsCaptureEnvironment => '捕获环境数据';

  @override
  String get settingsOffByDefaultOnlyActiveWhen =>
      '默认关闭。仅当调试开启时生效。将工作目录、平台信息、进程环境变量（可能含敏感令牌）等写入消息元数据，便于深度排查，请谨慎开启。';

  @override
  String get settingsShortcutBindings => '快捷键绑定';

  @override
  String get settingsClickRecordThenPressTheNew =>
      '点击录制后，按下新的组合键即可更新绑定。模型切换和会话切换会自动绕圈循环。';

  @override
  String get settingsShortcutRecord => '录制';

  @override
  String get settingsShortcutResetToDefault => '恢复默认';

  @override
  String get settingsShortcutMaxKeysError => '最多支持同时按下 4 个按键。';

  @override
  String get settingsShortcutRecorderBody => '按下新的组合键即可更新绑定。最多支持同时按下 4 个按键。';

  @override
  String get settingsShortcutRecorderTip => '提示：至少需要一个非修饰键，例如 Enter、P、方向键。';

  @override
  String get settingsAutoCleanupExecutionHistory => '自动清理执行历史';

  @override
  String get settingsOnEveryColdStartAnAsync =>
      '应用每次冷启动后，会异步启动一次清理 worker，删除超过保留天数的历史记录。worker 自带 single-flight、超时兜底与异常 silentLog，绝不无限重试或阻塞 UI。';

  @override
  String get settingsEnableSelfLearning => '启用自主学习';

  @override
  String get settingsWhenOffTheSchedulerSkipsEvery =>
      '关闭后，后台调度器跳过所有 Hermes Talker 会话；系统 Cron 条目会保留但不再派发子 Agent。';

  @override
  String get settingsShowSelfLearningMessages => '显示自我学习消息';

  @override
  String get settingsWhenOffSelfLearningCardsAre =>
      '关闭后，对话中不再展示\"自我学习\"卡片（后台学习仍会运行）。默认开启。';

  @override
  String get settingsToolCatalogOverview => '工具目录总览';

  @override
  String get settingsResetAll => '重置全部';

  @override
  String get settingsEnableAll => '全部启用';

  @override
  String get settingsDisableAll => '全部禁用';

  @override
  String get settingsNoBuiltInToolConfigurations => '没有内建工具配置';

  @override
  String get settingsClickResetAllToRestoreThe => '点击\"重置全部\"恢复默认工具列表。';

  @override
  String get settingsResetBuiltInToolConfigs => '重置内建工具配置';

  @override
  String get settingsCancel => '取消';

  @override
  String get settingsReset => '重置';

  @override
  String get settingsDeleteCustomTool => '删除自定义工具';

  @override
  String get settingsDelete => '删除';

  @override
  String get settingsSendTimeoutSaved => '发送超时时间已保存。';

  @override
  String get settingsResponseTimeoutSaved => '响应超时时间已保存。';

  @override
  String get settingsStreamIdleTimeoutSaved => '等待超时时间已保存。';

  @override
  String get settingsCacheBreakpointUpdateIntervalSaved => '历史候选点更新间隔已保存';

  @override
  String get settingsCacheBreakpointCountSaved => '缓存断点数量已保存';

  @override
  String get settingsCacheBreakpointPositions => '历史缓存候选点';

  @override
  String get settingsCacheBreakpointPositionsSaved => '历史缓存候选点已保存';

  @override
  String get cacheBarTopDescription =>
      '彩色段仅用于说明 prompt 结构。P 插桩表示历史消息流中的候选位置；最右侧虚线插桩表示当前请求尾锚。协议层会先保留稳定锚和连续尾锚，剩余预算再采用候选点。';

  @override
  String get cacheBarSectionSysLabel => '[0] 系统指令';

  @override
  String get cacheBarSectionDevLabel => '[1] 开发者指令';

  @override
  String get cacheBarSectionToolsLabel => '[2] 工具目录';

  @override
  String get cacheBarSectionStateLabel => '[3s/3d] 会话状态';

  @override
  String get cacheBarSectionMemoryLabel => '[4] 用户记忆';

  @override
  String get cacheBarSectionUserInstLabel => '[4.5] 用户指令';

  @override
  String get cacheBarSectionSummaryLabel => '[5] 会话摘要';

  @override
  String get cacheBarSectionHistoryLabel => '历史消息';

  @override
  String get cacheBarSectionLatestLabel => '尾部 / 最新轮次';

  @override
  String get cacheBarSectionSysSummary =>
      '模板系统指令、工作区指令与运行时环境快照（OS / cwd / 仓库摘要）。';

  @override
  String get cacheBarSectionSysCacheHint => '缓存友好：跨轮极稳定，最适合作为第一个断点。';

  @override
  String get cacheBarSectionDevSummary => '当前提示词模板的开发者指令（行为规则与输出格式约束）。';

  @override
  String get cacheBarSectionDevCacheHint => '缓存友好：会话内极少变动。';

  @override
  String get cacheBarSectionToolsSummary =>
      '内置工具目录、MCP 能力与 Skill 加载器（含 DSML 调用约束）。';

  @override
  String get cacheBarSectionToolsCacheHint => '较稳定：除非工具注册表变化，否则可放心命中缓存。';

  @override
  String get cacheBarSectionStateSummary =>
      '当前结构中位于 history 之后的静态/动态会话状态、Focus Context 与其它易变 system tail 区块。';

  @override
  String get cacheBarSectionStateCacheHint =>
      '大多易变：计划/Todo/Focus/Reminder 的变化会打断这一尾部区域，但不会破坏更前面的稳定前缀。';

  @override
  String get cacheBarSectionMemorySummary => '长期用户记忆事实，作为已掌握的常识自然融入。';

  @override
  String get cacheBarSectionMemoryCacheHint => '相对稳定：仅在记忆条目变更时才会失效。';

  @override
  String get cacheBarSectionUserInstSummary => '用户预设的可复用指令片段（项目级权威指引）。';

  @override
  String get cacheBarSectionUserInstCacheHint => '稳定：极少修改，断点落在它后面较稳妥。';

  @override
  String get cacheBarSectionSummarySummary => '较早会话的压缩摘要 + 最近聊天纪要。';

  @override
  String get cacheBarSectionSummaryCacheHint => '缓慢演化：仅在压缩重生成时刷新。';

  @override
  String get cacheBarSectionHistorySummary => '当前会话中的历史消息（用户 / 助手 / 工具结果）。';

  @override
  String get cacheBarSectionHistoryCacheHint => '仅追加：放在历史中段的断点能跨多轮命中尾部新增内容。';

  @override
  String get cacheBarSectionLatestSummary =>
      '靠近 prompt 尾部的最新轮次载荷，包含当前用户轮次与按轮变化的 reminder 内容。';

  @override
  String get cacheBarSectionLatestCacheHint =>
      '始终变化：当前请求尾锚覆盖此区域，上一请求尾锚负责延续缓存命中。';

  @override
  String get cacheBarDynamicTooltip => '当前请求尾锚：始终跟随最新消息。';

  @override
  String get cacheBarDynamicSuffix => '（当前尾锚）';

  @override
  String get cacheBarResetEven => '重置为均匀分布';

  @override
  String get settingsAiBudgetUsdPerSession => '单会话预算（USD）';

  @override
  String get settingsAiBudgetUsdPerSessionBody =>
      '0 表示关闭。当某个会话累计估算成本超过该上限时，会话元数据对话框中会以警示色提示，仅作软提醒，不会中断对话或限制发送。';

  @override
  String get settingsAiBudgetUsdPerSessionInvalid => '请输入 0 到 100000 之间的非负数。';

  @override
  String get settingsAiBudgetUsdPerSessionSaved => '单会话预算已保存';

  @override
  String sessionMetadataOverBudgetNotice(String total, String budget) {
    return '当前会话估算成本 $total 已超出预算 $budget。仅作提醒，不影响发送。';
  }

  @override
  String get settingsEnterAToolCallLimitGreater => '请输入大于 0 的工具调用上限。';

  @override
  String get settingsThePerResponseToolCallLimit => '单轮工具调用上限已保存。';

  @override
  String get settingsEnterASequentialToolRoundLimit => '请输入大于 0 的连续工具轮次上限。';

  @override
  String get settingsTheSequentialToolRoundLimitHas => '连续工具轮次上限已保存。';

  @override
  String get settingsDeleteDenyRule => '删除禁止命令规则';

  @override
  String get settingsTheDenyCommandRuleHasBeen => '禁止命令规则已删除。';

  @override
  String get settingsDeleteAllowRule => '删除允许命令规则';

  @override
  String get settingsTheAllowCommandRuleHasBeen => '允许命令规则已删除。';

  @override
  String get settingsTheShortcutHasBeenUpdated => '快捷键已更新。';

  @override
  String get settingsTheEditorShortcutHasBeenUpdated => '编辑器快捷键已更新。';

  @override
  String get settingsSendMessage => '发送消息';

  @override
  String get settingsCollapseOrExpandComposer => '折叠或展开输入框';

  @override
  String get settingsPreviousModel => '上一个模型';

  @override
  String get settingsNextModel => '下一个模型';

  @override
  String get settingsToggleAutoFollow => '开关自动滚动';

  @override
  String get settingsPreviousSession => '上一个会话';

  @override
  String get settingsNextSession => '下一个会话';

  @override
  String get settingsSaveFile => '保存文件';

  @override
  String get settingsTriggerCompletion => '触发智能补全';

  @override
  String get settingsShowSignatureHelp => '显示签名帮助';

  @override
  String get settingsFind => '查找';

  @override
  String get settingsFindAndReplace => '查找替换';

  @override
  String get settingsGoToLine => '跳转到行';

  @override
  String get settingsDocumentSymbols => '文档符号';

  @override
  String get settingsWorkspaceSymbols => '全局符号';

  @override
  String get settingsGoToDefinition => '跳转到定义';

  @override
  String get settingsFindReferences => '查找引用';

  @override
  String get settingsGoToImplementation => '跳转到实现';

  @override
  String get settingsShowHoverInfo => '显示悬浮信息';

  @override
  String get settingsRenameSymbol => '重命名符号';

  @override
  String get settingsCodeActions => '代码操作';

  @override
  String get settingsFormatDocument => '格式化文档';

  @override
  String get settingsDefaultsToCtrlEnterAndTriggers =>
      '默认 Ctrl + Enter，仅在聊天输入框准备好时触发发送按钮。';

  @override
  String get settingsDefaultsToCtrlPForQuickly => '默认 Ctrl + P，用于快速折叠或展开输入框。';

  @override
  String get settingsDefaultsToCtrlLeftAndWraps =>
      '默认 Ctrl + ←，向前切换模型，切到头后自动绕回末尾。';

  @override
  String get settingsDefaultsToCtrlRightAndWraps =>
      '默认 Ctrl + →，向后切换模型，切到末尾后自动绕回开头。';

  @override
  String get settingsDefaultsToCtrlSForToggling => '默认 Ctrl + S，开关自动滚动模式。';

  @override
  String get settingsDefaultsToCtrlUpAndWraps => '默认 Ctrl + ↑，切换到上一个会话并支持绕圈。';

  @override
  String get settingsDefaultsToCtrlDownAndWraps => '默认 Ctrl + ↓，切换到下一个会话并支持绕圈。';

  @override
  String get settingsUndoLastFileMutation => '撤销最近一次文件变动';

  @override
  String get settingsDefaultsToCtrlShiftZForUndo =>
      '默认 Ctrl + Shift + Z，撤销当前会话 ledger 中最新一条可撤销的文件变动。';

  @override
  String get auditDeleteMessage => '删除消息';

  @override
  String get auditDeleteThisMessageThisCannotBe => '确认删除该消息？此操作不可撤销。';

  @override
  String get auditCancel => '取消';

  @override
  String get settingsManageTheBuiltInAiTools =>
      '管理应用内置的 AI 内建工具。可调整每个工具的启用状态、名称、描述、Schema、优先级、排序、加载策略和其他参数。';

  @override
  String get settingsManageTheLocalFilesAndDatabase =>
      '管理 OpenHand 在本地占用的文件与数据库体积。所有清理动作都在后台 worker 中运行，不会阻塞主线程；每个分类均需二次确认后才会真正删除。';

  @override
  String get settingsThisWillRestoreAllBuiltIn =>
      '这将把所有内建工具配置恢复为出厂默认值，包括名称、描述、Schema 覆盖、优先级、排序和加载策略。此操作不可撤销。';

  @override
  String get tlCallUnwrap => '取消换行';

  @override
  String get tlCallWrapLines => '自动换行';

  @override
  String get tlCallViewCompressedContent => '查看压缩内容';

  @override
  String get tlCallViewFullContent => '查看完整内容';

  @override
  String get tlCallPreparing => '准备执行';

  @override
  String get tlCallPreparingAlt => '准备调用';

  @override
  String get tlCallRunningAlt => '调用中';

  @override
  String get tlCallCompleted => '执行完成';

  @override
  String get tlCallCompletedAlt => '调用完成';

  @override
  String get tlCallTimedOutAlt => '调用超时';

  @override
  String get tlCallFailedAlt => '调用失败';

  @override
  String tlCallFailedToOpenFileLocationError(Object error) {
    return '打开文件位置失败：$error';
  }

  @override
  String tlCallMemoryitemsLengthMemoriesUpdated(Object memoryItems_length) {
    return '$memoryItems_length 条记忆已更新';
  }

  @override
  String tlCallProfileitemsLengthProfileChanges(Object profileItems_length) {
    return '$profileItems_length 项画像已更新';
  }

  @override
  String tlCallSkillitemsLengthSkillsUpdated(Object skillItems_length) {
    return '$skillItems_length 个技能已更新';
  }

  @override
  String get tlCallAiThinkingStreaming => 'AI 思考（生成中）';

  @override
  String get tlCallAiThinking => 'AI 思考';

  @override
  String get tlCallAiResponseStreaming => 'AI 响应（生成中）';

  @override
  String get tlCallAiResponse => 'AI 响应';

  @override
  String tlCallAndItemsLength3More(Object items_length_3, Object items_length) {
    return ' 等 $items_length 项';
  }

  @override
  String tlCallSecondsSAgo(Object seconds) {
    return '$seconds秒前';
  }

  @override
  String tlCallMinutesMAgo(Object minutes) {
    return '$minutes分钟前';
  }

  @override
  String tlCallHoursHAgo(Object hours) {
    return '$hours小时前';
  }

  @override
  String tlCallDaysDAgo(Object days) {
    return '$days天前';
  }

  @override
  String sessMetaPlanPlanindex(Object planIndex) {
    return '计划 #$planIndex';
  }

  @override
  String sessMetaTheCurrentSequentialToolRoundLimit(Object configuredLimit) {
    return ' 当前连续工具轮次上限为 $configuredLimit。';
  }

  @override
  String auditInvalidJsonErrorMessage(Object error_message) {
    return 'JSON 解析失败：$error_message';
  }

  @override
  String auditSaveFailedError(Object error) {
    return '保存失败：$error';
  }

  @override
  String auditRecentErrorsSessionRecenterrorsLength(
    Object session_recentErrors_length,
  ) {
    return '最近错误 ($session_recentErrors_length)';
  }

  @override
  String auditMessagesSessionMessagesLength(Object session_messages_length) {
    return '消息列表 ($session_messages_length)';
  }

  @override
  String progExpFEAppliedEditsLengthFormattingEdits(Object edits_length) {
    return '已应用 $edits_length 处格式化修改。';
  }

  @override
  String progExpFEFormatTheCurrentFileFormatshortcut(Object formatShortcut) {
    return '格式化当前文件 ($formatShortcut)';
  }

  @override
  String progExpFENoCodeactionkindRefactoringIsAvailableAt(
    Object codeActionKind,
  ) {
    return '当前位置没有可用的\"$codeActionKind\"重构操作。';
  }

  @override
  String get progExpFEHideFileBrowser => '隐藏文件浏览器';

  @override
  String get progExpFEShowFileBrowser => '显示文件浏览器';

  @override
  String settingsRetentionWindowRetentionDayS(Object retention) {
    return '保留天数：$retention 天';
  }

  @override
  String settingsRangeMinrMaxrDaysDefault7(Object minR, Object maxR) {
    return '范围 $minR–$maxR 天，默认 7 天。下次冷启动时生效。';
  }

  @override
  String settingsConcurrentWorkersConcurrency(Object concurrency) {
    return '并发 Worker 数：$concurrency';
  }

  @override
  String settingsCapsHowManySessionsCanBe(Object minC, Object maxC) {
    return '限制单轮 tick 同时派发的会话数 ($minC–$maxC)。默认 5。';
  }

  @override
  String settingsSortedLengthBuiltInToolsEnabledcount(
    Object sorted_length,
    Object enabledCount,
  ) {
    return '当前共 $sorted_length 个内建工具，已启用 $enabledCount 个。可调整每个工具的名称、描述、Schema、优先级、排序和加载策略等。';
  }

  @override
  String settingsAreYouSureYouWantTo(Object config_effectiveName) {
    return '确定要删除 \"$config_effectiveName\" 吗？此操作不可撤销。';
  }

  @override
  String settingsEnterAValueBetweenMinAnd(Object min, Object max) {
    return '请输入 $min–$max 之间的秒数。';
  }

  @override
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn(
    Object AppSettingsSnapshot_minAiInputCacheUpdateInterval,
    Object AppSettingsSnapshot_maxAiInputCacheUpdateInterval,
  ) {
    return '请输入 $AppSettingsSnapshot_minAiInputCacheUpdateInterval 到 $AppSettingsSnapshot_maxAiInputCacheUpdateInterval 之间的整数';
  }

  @override
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn2(
    Object AppSettingsSnapshot_minAiInputCacheBreakpointCount,
    Object AppSettingsSnapshot_maxAiInputCacheBreakpointCount,
  ) {
    return '请输入 $AppSettingsSnapshot_minAiInputCacheBreakpointCount 到 $AppSettingsSnapshot_maxAiInputCacheBreakpointCount 之间的整数';
  }

  @override
  String settingsDragTheThumbcountThumbsToPosition(Object thumbCount) {
    return '拖动 $thumbCount 个圆点设置历史消息候选位置（0%-100%）。稳定锚与连续尾锚优先占用断点预算；最右侧圆点固定为当前请求尾锚。';
  }

  @override
  String get settingsTheDenyCommandRuleHasBeen2 => '禁止命令规则已更新。';

  @override
  String get settingsTheAllowCommandRuleHasBeen2 => '允许命令规则已更新。';

  @override
  String settingsDefaultsToDefaultlabelAndSavesThe(Object defaultLabel) {
    return '默认 $defaultLabel，保存当前正在编辑的文件。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndOpensThe(Object defaultLabel) {
    return '默认 $defaultLabel，主动弹出智能补全候选列表。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsMethod(Object defaultLabel) {
    return '默认 $defaultLabel，显示当前调用位置的方法签名、参数解释和文档摘要。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe(Object defaultLabel) {
    return '默认 $defaultLabel，打开或关闭查找面板。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe2(Object defaultLabel) {
    return '默认 $defaultLabel，打开或关闭替换面板。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe3(Object defaultLabel) {
    return '默认 $defaultLabel，打开或关闭跳转到行面板。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe4(Object defaultLabel) {
    return '默认 $defaultLabel，打开或关闭当前文件的符号列表。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe5(Object defaultLabel) {
    return '默认 $defaultLabel，打开或关闭全局符号检索面板。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndJumpsTo(Object defaultLabel) {
    return '默认 $defaultLabel，跳转到当前符号定义。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndFindsReferences(Object defaultLabel) {
    return '默认 $defaultLabel，查找当前符号的引用位置。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndJumpsTo2(Object defaultLabel) {
    return '默认 $defaultLabel，跳转到当前符号的实现位置。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsType(Object defaultLabel) {
    return '默认 $defaultLabel，显示当前位置的类型或文档信息。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndStartsRename(Object defaultLabel) {
    return '默认 $defaultLabel，发起当前符号重命名。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsAvailable(Object defaultLabel) {
    return '默认 $defaultLabel，显示可用的代码操作列表。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndFormatsThe(Object defaultLabel) {
    return '默认 $defaultLabel，格式化当前编程文件；当选中多行时，Shift+Tab 仍优先执行反向缩进。';
  }

  @override
  String progExpFEResolvedLspBackendForCurrentFile(
    Object lspName,
    Object projLang,
    Object fileLang,
    Object modeLine,
    Object sdkSourceLine,
    Object lspSourceLine,
    Object rootPath,
    Object command,
  ) {
    return '当前文件已解析到 $lspName。\n项目语言：$projLang\n当前文件语言：$fileLang\n$modeLine\n$sdkSourceLine\n$lspSourceLine\n工作区：$rootPath\n命令：$command';
  }

  @override
  String get settingsReduceMotionLabel => '减少动画';

  @override
  String get settingsReduceMotionBody =>
      '开启后，自研动画与 Flutter 内建动画的时长全部归零。与系统层「减少动画」辅助功能并联生效。';

  @override
  String get mcpToolSearchReplayLastCancelAction => '重放上次取消';

  @override
  String get mcpToolSearchReplayLastCancelToastFired => '已重发上次取消的载入';

  @override
  String get mcpToolSearchReplayLastCancelToastEmpty => '当前没有可重放的取消';

  @override
  String get aiThrottleSettingsLabel => '节流参数';

  @override
  String get aiThrottleSettingsBody => '统一控制流式输出节流：开关、自动模式、字符 / 卡片速率、持续时长。';

  @override
  String get webReverseVitalsInstalling => '注入 PerformanceObserver…';

  @override
  String get webReverseVitalsResetting => '重置中…';

  @override
  String get webReverseVitalsReportCopied => '报告 JSON 已复制';

  @override
  String get webReverseVitalsTitle => 'Web Vitals 报告';

  @override
  String get webReverseVitalsSubtitle =>
      'PerformanceObserver · LCP / CLS / INP / FCP / TTFB · 实时刷新';

  @override
  String get webReverseVitalsCopyJson => '复制报告 JSON';

  @override
  String get webReverseVitalsReset => '重置采集';

  @override
  String get webReverseVitalsClose => '关闭';

  @override
  String get webReverseVitalsThresholdsHint =>
      '阈值参考 web.dev：LCP ≤2.5s 良 / ≥4s 差；CLS ≤0.1 良 / ≥0.25 差；INP ≤200ms 良 / ≥500ms 差。重置后请重新交互页面以触发 LCP / 事件采样。';

  @override
  String get webReverseIssuesCopied => '已复制 issue JSON';

  @override
  String get webReverseIssuesTitle => 'Issues 面板';

  @override
  String get webReverseIssuesSubtitle =>
      'Audits.issueAdded · 安全 / Cookie / Mixed Content / Deprecation 实时聚合';

  @override
  String get webReverseIssuesClearBuffer => '清空缓冲';

  @override
  String get webReverseIssuesClose => '关闭';

  @override
  String get webReverseIssuesFilterHint => '按 code / URL / 描述过滤…';

  @override
  String get webReverseIssuesEmptyBuffer => '当前页面尚未报告任何 issue，访问几个交互后再来看看。';

  @override
  String get webReverseIssuesNoMatch => '没有匹配的 issue。';

  @override
  String get webReverseIssuesCopyJson => '复制 JSON';

  @override
  String get webReverseIssuesCollapse => '收起';

  @override
  String get webReverseIssuesExpand => '展开';

  @override
  String get webReverseIssuesSubscribed => '已订阅 Audits.issueAdded';

  @override
  String get webReverseIssuesAuditsNotReady => 'Audits 域未就绪';

  @override
  String get webReverseRenderingResetSuccess => '已重置全部 Rendering 开关';

  @override
  String get webReverseRenderingTitle => 'Rendering 调试';

  @override
  String get webReverseRenderingSubtitle =>
      'Paint / Layout shift / Layers / FPS / 媒体仿真 / CPU 节流';

  @override
  String get webReverseRenderingResetAll => '全部重置';

  @override
  String get webReverseRenderingClose => '关闭';

  @override
  String get webReverseRenderingSectionOverlays => '可视化覆盖层';

  @override
  String get webReverseRenderingPaintFlashingDesc =>
      '高亮当帧重绘区域 · Overlay.setShowPaintRects';

  @override
  String get webReverseRenderingLayoutShiftDesc =>
      'CLS 偏移可视化 · Overlay.setShowLayoutShiftRegions';

  @override
  String get webReverseRenderingLayerBordersDesc =>
      '合成层边框 · Overlay.setShowDebugBorders';

  @override
  String get webReverseRenderingScrollBottleneckDesc =>
      '阻塞主线程的滚动区域 · setShowScrollBottleneckRects';

  @override
  String get webReverseRenderingHitTestDesc =>
      '元素命中区边框 · Overlay.setShowHitTestBorders';

  @override
  String get webReverseRenderingFpsDesc =>
      '右上角实时帧率 · Overlay.setShowFPSCounter';

  @override
  String get webReverseRenderingWebVitalsDesc =>
      'LCP / CLS / INP 浮层 · Overlay.setShowWebVitals';

  @override
  String get webReverseRenderingSectionPerf => '性能仿真';

  @override
  String get webReverseRenderingSectionMedia => '媒体仿真';

  @override
  String get webReverseRenderingLabelColorScheme => '配色方案';

  @override
  String get webReverseRenderingLabelReducedMotion => '减少动效';

  @override
  String get webReverseRenderingLabelMediaType => '媒体类型';

  @override
  String get webReverseRenderingCpuThrottling => 'CPU 节流';

  @override
  String get webReverseAnimationsTitle => 'Animations 调试';

  @override
  String get webReverseAnimationsSubtitle =>
      'CDP Animation.setPlaybackRate + document.getAnimations() 实时拉取';

  @override
  String get webReverseAnimationsCopyJson => '复制 JSON';

  @override
  String get webReverseAnimationsRefresh => '重新抓取';

  @override
  String get webReverseAnimationsGlobalRate => '全局倍速';

  @override
  String get webReverseAnimationsPauseSymbol => '⏸';

  @override
  String get webReverseAnimationsBulkPause => '全部暂停';

  @override
  String get webReverseAnimationsBulkResume => '全部继续';

  @override
  String get webReverseAnimationsBulkCancel => '全部取消';

  @override
  String get webReverseAnimationsEmptyState =>
      '没有抓到活跃 animation。先在页面上触发动画再点刷新。';

  @override
  String get webReverseAnimationsRowPause => '暂停';

  @override
  String get webReverseAnimationsRowPlay => '继续';

  @override
  String get webReverseAnimationsRowCancel => '取消';

  @override
  String get webReverseAnimationsClose => '关闭';

  @override
  String get webReverseAnimationsNoSnapshot => '页面无法返回快照';

  @override
  String get webReverseAnimationsMalformedSnapshot => '快照格式异常';

  @override
  String get webReverseAnimationsJsonCopied => 'JSON 已复制';

  @override
  String webReverseAnimationsSetFailed(String error) {
    return '设置失败: $error';
  }

  @override
  String webReverseAnimationsRateNow(String rate) {
    return '当前全局倍速 ${rate}x';
  }

  @override
  String webReverseAnimationsSetError(String error) {
    return '设置异常: $error';
  }

  @override
  String webReverseAnimationsBrowserError(String error) {
    return '浏览器侧异常: $error';
  }

  @override
  String webReverseAnimationsSnapshotCount(int count) {
    return '抓到 $count 条活跃 animation';
  }

  @override
  String webReverseAnimationsSnapshotFailed(String error) {
    return '抓取失败: $error';
  }

  @override
  String webReverseAnimationsBulkInvoked(String method, int count) {
    return '已对 $count 条 animation 执行 $method';
  }

  @override
  String webReverseAnimationsBulkError(String method, String error) {
    return '$method 异常: $error';
  }

  @override
  String get webReverseHarTitle => 'HAR 全量持久化';

  @override
  String get webReverseHarSubtitle => '立即落盘 / 反向加载 / 周期自动轮转';

  @override
  String get webReverseHarOpenSaveDialogFail => '打开保存对话框失败';

  @override
  String get webReverseHarExporting => '导出中...';

  @override
  String get webReverseHarExportFailedNoDraft => '导出失败（无 HAR 草稿）';

  @override
  String get webReverseHarExportFailed => '导出失败';

  @override
  String get webReverseHarWrotePrefix => '已写出: ';

  @override
  String get webReverseHarSaved => 'HAR 已保存';

  @override
  String get webReverseHarExportErrorShort => '导出异常';

  @override
  String get webReverseHarOpenFileDialogFail => '打开文件对话框失败';

  @override
  String get webReverseHarParsing => '解析 HAR...';

  @override
  String get webReverseHarModeMerge => '合并';

  @override
  String get webReverseHarModeReplace => '替换';

  @override
  String get webReverseHarLoaded => 'HAR 已加载';

  @override
  String get webReverseHarLoadErrorShort => '加载异常';

  @override
  String get webReverseHarSelect => '选择';

  @override
  String get webReverseHarChooseFolderFirst => '请先选择目录';

  @override
  String get webReverseHarAutoStarted => '已启动自动轮转';

  @override
  String get webReverseHarAutoStopped => '已停止自动轮转';

  @override
  String get webReverseHarSessionStatus => '当前会话状态';

  @override
  String get webReverseHarManual => '手动操作';

  @override
  String get webReverseHarSaveNow => '立即保存 HAR';

  @override
  String get webReverseHarLoadExternal => '加载外部 HAR';

  @override
  String get webReverseHarMergeLabel => '合并（不清空）';

  @override
  String get webReverseHarLastHarPrefix => '上次 HAR: ';

  @override
  String get webReverseHarAutoRotate => '周期自动轮转';

  @override
  String get webReverseHarIntervalLabel => '间隔:';

  @override
  String get webReverseHarChooseFolder => '选择目录';

  @override
  String get webReverseHarFolderNotChosen => '（未选择）';

  @override
  String get webReverseHarStart => '启动';

  @override
  String get webReverseHarStop => '停止';

  @override
  String get webReverseHarNotes => '说明';

  @override
  String get webReverseHarClose => '关闭';

  @override
  String get webReverseHarLastFilePrefix => '最近一份: ';

  @override
  String get webReverseHarNotesBody =>
      '· 立即保存：把内部 HAR 草稿复制到你选择的 .har 路径。\n· 加载外部 HAR：解析 HAR 1.2 并写回 networkRequests，可选合并到现有列表。\n· 自动轮转：每 N 分钟把当前快照写到目录下带 ISO 时间戳的 .har 文件；对话框关闭后继续运行，需手动停止。';

  @override
  String webReverseHarExportException(String error) {
    return '导出异常: $error';
  }

  @override
  String webReverseHarLoadException(String error) {
    return '加载异常: $error';
  }

  @override
  String webReverseHarLoadResult(int loaded, int skipped, String mode) {
    return '加载完成: $loaded 条 / 跳过 $skipped 条（$mode）';
  }

  @override
  String webReverseHarCapturedEntries(int count) {
    return '抓包条目: $count';
  }

  @override
  String webReverseHarRunningInfo(int rotations, String remaining) {
    return '运行中 · 已轮转 $rotations 次 · 下次 $remaining 后';
  }

  @override
  String get webReverseWaterfallTitle => '请求瀑布图';

  @override
  String get webReverseWaterfallSubtitle => '蓝段 = 等待 TTFB，绿段 = 下载；点击行复制 URL';

  @override
  String get webReverseWaterfallRefresh => '刷新';

  @override
  String get webReverseWaterfallImportHar => '导入 HAR';

  @override
  String get webReverseWaterfallExportHar => '导出 HAR';

  @override
  String get webReverseWaterfallFilterHint => 'URL 子串过滤';

  @override
  String get webReverseWaterfallOnlyXhr => '仅 XHR/Fetch';

  @override
  String get webReverseWaterfallSortTime => '时间';

  @override
  String get webReverseWaterfallSortDuration => '耗时';

  @override
  String get webReverseWaterfallSortSize => '大小';

  @override
  String get webReverseWaterfallNoRequests => '没有请求';

  @override
  String get webReverseWaterfallHeaderRequest => '请求';

  @override
  String get webReverseWaterfallUrlCopied => '已复制 URL';

  @override
  String get webReverseWaterfallClose => '关闭';

  @override
  String get webReverseWaterfallNoInitiator => '无 Initiator 信息';

  @override
  String get webReverseWaterfallInitiatorTitle => '请求发起方';

  @override
  String get webReverseWaterfallInitiatorTypeLabel => '类型';

  @override
  String get webReverseWaterfallJumpToSources => '跳到 Sources';

  @override
  String get webReverseWaterfallNoJsStack =>
      '没有 JavaScript 调用栈（parser/preflight 类型常见）';

  @override
  String get webReverseWaterfallLoadHarTitle => '加载 HAR';

  @override
  String get webReverseWaterfallCancel => '取消';

  @override
  String get webReverseWaterfallMerge => '合并';

  @override
  String get webReverseWaterfallReplace => '替换';

  @override
  String get webReverseWaterfallHarParseFailed => 'HAR 解析失败';

  @override
  String get webReverseWaterfallHarSaveFailed => 'HAR 保存失败或超时';

  @override
  String webReverseWaterfallInitiatorTooltipWithUrl(String type, String url) {
    return '发起方：$type\n$url';
  }

  @override
  String webReverseWaterfallInitiatorTooltipNoUrl(String type) {
    return '发起方：$type';
  }

  @override
  String webReverseWaterfallLoadHarPrompt(int count) {
    return '当前已有 $count 条记录，选择加载方式：';
  }

  @override
  String webReverseWaterfallLoadMergedResult(int loaded, int skipped) {
    return '合并加载 $loaded 条；跳过 $skipped 条';
  }

  @override
  String webReverseWaterfallLoadReplacedResult(int loaded, int skipped) {
    return '替换加载 $loaded 条；跳过 $skipped 条';
  }

  @override
  String webReverseWaterfallHarSavedTo(String path) {
    return 'HAR 已保存到 $path';
  }

  @override
  String get webReverseCookieEditorTitle => 'Cookie 编辑器';

  @override
  String get webReverseCookieEditorSubtitle =>
      'Network.getCookies / setCookie / deleteCookies — 精修级 CRUD';

  @override
  String get webReverseCookieEditorRefresh => '刷新';

  @override
  String get webReverseCookieEditorCopyJson => '复制 JSON';

  @override
  String get webReverseCookieEditorCopiedJson => '已复制 JSON';

  @override
  String get webReverseCookieEditorFilterHint => '过滤 name / domain / value';

  @override
  String get webReverseCookieEditorNewBtn => '新增';

  @override
  String get webReverseCookieEditorEmptyCookies => '当前 target 无 Cookie';

  @override
  String get webReverseCookieEditorEdit => '编辑';

  @override
  String get webReverseCookieEditorDelete => '删除';

  @override
  String get webReverseCookieEditorFetching => '拉取 Cookies...';

  @override
  String get webReverseCookieEditorDeleteFailed => '删除失败';

  @override
  String get webReverseCookieEditorWriteFailed => '写入失败';

  @override
  String get webReverseCookieEditorSaved => '已保存';

  @override
  String get webReverseCookieEditorNewCookie => '新增 Cookie';

  @override
  String get webReverseCookieEditorFieldName => '名称 *';

  @override
  String get webReverseCookieEditorFieldValue => '值';

  @override
  String get webReverseCookieEditorFieldDomain => '域 (domain)';

  @override
  String get webReverseCookieEditorFieldPath => '路径 (path)';

  @override
  String get webReverseCookieEditorFieldUrl => 'URL（设 domain/path 时可不填）';

  @override
  String get webReverseCookieEditorFieldExpires => '过期时间 unix 秒（留空=会话级）';

  @override
  String get webReverseCookieEditorSameSiteUnset => '未指定';

  @override
  String get webReverseCookieEditorCancel => '取消';

  @override
  String get webReverseCookieEditorSave => '保存';

  @override
  String get webReverseCookieEditorNameRequired => 'name 必填';

  @override
  String webReverseCookieEditorCookieCount(int count) {
    return '共 $count 条';
  }

  @override
  String webReverseCookieEditorDeleted(String name) {
    return '已删除 $name';
  }

  @override
  String webReverseCookieEditorEditCookie(String name) {
    return '编辑 $name';
  }

  @override
  String get webReverseInputSimTitle => '输入事件模拟';

  @override
  String get webReverseInputSimDispatchingClick => '派发鼠标点击...';

  @override
  String get webReverseInputSimDispatched => '已派发';

  @override
  String get webReverseInputSimDispatchingKey => '派发按键...';

  @override
  String get webReverseInputSimKeyDispatched => '按键已派发';

  @override
  String get webReverseInputSimInsertingText => '插入文本...';

  @override
  String get webReverseInputSimInserted => '已插入';

  @override
  String get webReverseInputSimButton => '按钮';

  @override
  String get webReverseInputSimClickCount => '点击次数';

  @override
  String get webReverseInputSimModifiers => '修饰键';

  @override
  String get webReverseInputSimClickBtn => '点击';

  @override
  String get webReverseInputSimWheelDown => '滚轮↓';

  @override
  String get webReverseInputSimWheelUp => '滚轮↑';

  @override
  String get webReverseInputSimKeyTextLabel => '文本（可空，例如 “a”）';

  @override
  String get webReverseInputSimDispatchKeyDownUp => '派发 keyDown+keyUp';

  @override
  String get webReverseInputSimInsertTextLabel => '插入文本 (Input.insertText)';

  @override
  String get webReverseInputSimInsertBtn => '插入';

  @override
  String get webReverseInputSimTabMouse => '鼠标';

  @override
  String get webReverseInputSimTabKey => '键盘';

  @override
  String get webReverseInputSimTabText => '文本';

  @override
  String get webReverseInputSimCloseBtn => '关闭';

  @override
  String webReverseInputSimClickedAt(String x, String y) {
    return '已派发点击 ($x, $y)';
  }

  @override
  String webReverseInputSimWheelDy(String dy) {
    return '滚轮 dy=$dy';
  }

  @override
  String webReverseInputSimInsertedCount(int count) {
    return '已插入 $count 字符';
  }

  @override
  String get webReverseHeadlessBatchTitle => 'Headless 批量采集';

  @override
  String get webReverseHeadlessBatchClose => '关闭';

  @override
  String get webReverseHeadlessBatchDesc =>
      '逐 URL 后台开新 tab，加载完成后保存网络响应索引 / 控制台日志 / 截图。使用当前浏览器进程，复用 cookie 与 Hook。';

  @override
  String get webReverseHeadlessBatchUrlsLabel => 'URL 列表（每行一条）';

  @override
  String get webReverseHeadlessBatchOutputDirLabel => '输出目录';

  @override
  String get webReverseHeadlessBatchNotSelected => '（未选）';

  @override
  String get webReverseHeadlessBatchChoose => '选择';

  @override
  String get webReverseHeadlessBatchNetwork => '网络';

  @override
  String get webReverseHeadlessBatchConsole => '控制台';

  @override
  String get webReverseHeadlessBatchScreenshot => '截图';

  @override
  String get webReverseHeadlessBatchStart => '开始批量';

  @override
  String get webReverseHeadlessBatchStop => '停止';

  @override
  String get webReverseHeadlessBatchNoProgress => '尚无进度';

  @override
  String get webReverseHeadlessBatchPickOutputDir => '选择输出目录';

  @override
  String get webReverseHeadlessBatchNeedUrlAndDir =>
      '请先填入至少一条 http(s):// URL，并选好输出目录';

  @override
  String get webReverseHeadlessBatchBrowserNotReady =>
      '浏览器尚未启动，请先在主面板启动会话再来批量采集';

  @override
  String get webReverseHeadlessBatchPhaseStarting => '准备';

  @override
  String get webReverseHeadlessBatchPhaseNavigating => '导航中';

  @override
  String get webReverseHeadlessBatchPhaseWaitingLoad => '等待 load';

  @override
  String get webReverseHeadlessBatchPhaseCapturingScreenshot => '截图中';

  @override
  String get webReverseHeadlessBatchPhaseDone => '完成';

  @override
  String get webReverseHeadlessBatchPhaseFailed => '失败';

  @override
  String get webReverseHeadlessBatchPhaseCancelled => '已取消';

  @override
  String webReverseHeadlessBatchFinished(int ok, int total) {
    return '批量采集结束：$ok/$total 成功';
  }

  @override
  String webReverseHeadlessBatchEventCount(int events, int total) {
    return '$events / $total 条事件';
  }

  @override
  String webReverseHeadlessBatchResultStats(int net, int log, String dir) {
    return '$net 网络 · $log 日志 · $dir';
  }

  @override
  String get webReverseResendRequestUrlEmpty => 'URL 不能为空';

  @override
  String get webReverseResendRequestUrlInvalid => 'URL 非法';

  @override
  String get webReverseResendRequestAborted => '已中止';

  @override
  String get webReverseResendRequestFooterNote =>
      '注意：本对话框走 Dart HttpClient 重发，绕过浏览器 CSP / CORS，仅供逆向调试。';

  @override
  String get webReverseResendRequestClose => '关闭';

  @override
  String get webReverseResendRequestAbort => '中止';

  @override
  String get webReverseResendRequestSend => '重放发送';

  @override
  String get webReverseResendRequestTitle => '重放 / 改包';

  @override
  String get webReverseResendRequestHeadersLabel => '请求头';

  @override
  String get webReverseResendRequestAddRow => '加一行';

  @override
  String get webReverseResendRequestRemove => '删除';

  @override
  String get webReverseResendRequestBodyLabel => '请求体';

  @override
  String get webReverseResendRequestBeautifyJson => '美化 JSON';

  @override
  String get webReverseResendRequestInvalidJson => '不是合法 JSON';

  @override
  String get webReverseResendRequestExportAs => '导出为：';

  @override
  String get webReverseResendRequestCopyResponse => '复制响应';

  @override
  String get webReverseResendRequestResponseCopied => '已复制响应体';

  @override
  String get webReverseResendRequestBase64Hint => '响应非 UTF-8，下方为 Base64 预览：';

  @override
  String get webReverseResendRequestBodyHint => '响应体：';

  @override
  String webReverseResendRequestCopiedAs(String kind) {
    return '已复制为 $kind';
  }

  @override
  String webReverseResendRequestHasNoBody(String method) {
    return '$method 不支持 body';
  }

  @override
  String webReverseResendRequestHeadersWithCount(int count) {
    return '响应头 ($count)';
  }

  @override
  String get webReverseMockRulesTitle => '本地 Mock 拦截';

  @override
  String get webReverseMockRulesSubtitle =>
      'URL 通配命中 → Fetch.fulfillRequest 直接返回假数据';

  @override
  String get webReverseMockRulesExportJson => '导出 JSON';

  @override
  String get webReverseMockRulesImportJson => '从剪贴板导入';

  @override
  String get webReverseMockRulesListLabel => '规则';

  @override
  String get webReverseMockRulesAdd => '新增';

  @override
  String get webReverseMockRulesEmptyRules => '尚无规则';

  @override
  String get webReverseMockRulesDelete => '删除';

  @override
  String get webReverseMockRulesNewRule => '新规则';

  @override
  String get webReverseMockRulesJsonCopied => '已复制 JSON';

  @override
  String get webReverseMockRulesPickRule => '左侧选择规则编辑';

  @override
  String get webReverseMockRulesHits => '命中记录';

  @override
  String get webReverseMockRulesClear => '清空';

  @override
  String get webReverseMockRulesNoHits => '尚未命中';

  @override
  String get webReverseMockRulesClose => '关闭';

  @override
  String get webReverseMockRulesSaveApply => '保存并应用';

  @override
  String get webReverseMockRulesRuleName => '规则名';

  @override
  String get webReverseMockRulesUrlPattern => 'URL 通配（* / ?）';

  @override
  String get webReverseMockRulesMethodLabel => 'Method（空=全部）';

  @override
  String get webReverseMockRulesExtraHeaders => '额外响应头（每行 Key: Value）';

  @override
  String get webReverseMockRulesResponseBody => '响应体';

  @override
  String webReverseMockRulesSavedCount(int count) {
    return '已保存 $count 条规则';
  }

  @override
  String webReverseMockRulesImportedCount(int count) {
    return '已导入 $count 条';
  }

  @override
  String webReverseMockRulesImportFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get webReverseStorageTitle => '存储管理器';

  @override
  String get webReverseStorageClose => '关闭';

  @override
  String get webReverseStorageCopied => '已复制';

  @override
  String get webReverseStorageAddCookie => '新增 Cookie';

  @override
  String get webReverseStorageCancel => '取消';

  @override
  String get webReverseStorageSave => '保存';

  @override
  String get webReverseStorageCookieSaved => 'Cookie 已保存';

  @override
  String get webReverseStorageSaveFailed => '保存失败';

  @override
  String get webReverseStorageAddEntry => '新增条目';

  @override
  String get webReverseStorageEditEntry => '编辑条目';

  @override
  String get webReverseStorageNoCookies => '没有 Cookie';

  @override
  String get webReverseStorageCopyJson => '复制 JSON';

  @override
  String get webReverseStorageDelete => '删除';

  @override
  String get webReverseStorageAdd => '新增';

  @override
  String get webReverseStorageEmpty => '空';

  @override
  String get webReverseStorageNoDatabases => '没有数据库';

  @override
  String get webReverseStoragePickDb => '选择数据库';

  @override
  String get webReverseStoragePickStore => '选择 Object Store';

  @override
  String get webReverseStorageMoreRecords => '… 还有更多记录（仅显示前 50 条）';

  @override
  String get webReverseStorageRefresh => '刷新';

  @override
  String get webReverseCorsUrlRequired => '请输入 URL';

  @override
  String get webReverseCorsBadEval => '页面返回值异常';

  @override
  String get webReverseCorsMissing => '缺失';

  @override
  String get webReverseCorsMatchOrigin => '与当前 origin 匹配';

  @override
  String get webReverseCorsAllHeadersAllowed => '所有请求头都被允许';

  @override
  String get webReverseCorsCredsRule => '需 = true 且 Allow-Origin 不能为 *';

  @override
  String get webReverseCorsCacheSeconds => '缓存时间（秒）';

  @override
  String get webReverseCorsResultCopied => '结果已复制';

  @override
  String get webReverseCorsTitle => 'CORS Preflight 测试';

  @override
  String get webReverseCorsSubtitle =>
      'OPTIONS · Allow-Origin / Methods / Headers / Credentials 诊断';

  @override
  String get webReverseCorsCopyJson => '复制 JSON';

  @override
  String get webReverseCorsTargetUrl => '目标 URL';

  @override
  String get webReverseCorsActualMethod => '实际方法';

  @override
  String get webReverseCorsOriginOverride => 'Origin 覆盖（可选，仅用于诊断显示）';

  @override
  String get webReverseCorsCustomHeaders => '自定义请求头（每行一个 K: V，仅头名参与 preflight）';

  @override
  String get webReverseCorsRunButton => '运行 Preflight';

  @override
  String get webReverseCorsDiagnostics => '诊断';

  @override
  String get webReverseCorsAllHeaders => '所有响应头';

  @override
  String get webReverseCorsClose => '关闭';

  @override
  String webReverseCorsMustInclude(String method) {
    return '需包含 $method';
  }

  @override
  String webReverseCorsMissingHeaders(String names) {
    return '缺少：$names';
  }

  @override
  String get webReverseCallgraphFetching => '获取 frame 资源...';

  @override
  String get webReverseCallgraphFetchFailed => '获取资源失败';

  @override
  String get webReverseCallgraphNoScripts => '当前页未发现 JS 脚本';

  @override
  String get webReverseCallgraphTitle => 'JS 调用图';

  @override
  String get webReverseCallgraphSubtitle => '启发式正则解析（压缩 bundle 噪点高，仅作线索）';

  @override
  String get webReverseCallgraphScanBtn => '扫描';

  @override
  String get webReverseCallgraphScriptLimit => '脚本上限';

  @override
  String get webReverseCallgraphPerScriptKb => '单脚本(KB)';

  @override
  String get webReverseCallgraphReverseHint => '反查：谁调用了 …（输入被调函数名）';

  @override
  String get webReverseCallgraphEmptyHint => '点「扫描」开始解析当前页面的 JS 资源';

  @override
  String get webReverseCallgraphFnsSuffix => '函数';

  @override
  String get webReverseCallgraphPickScript => '选择左侧脚本';

  @override
  String get webReverseCallgraphClose => '关闭';

  @override
  String get webReverseCallgraphCopyGraph => '复制脚本调用图';

  @override
  String get webReverseCallgraphGraphCopied => '已复制调用图';

  @override
  String get webReverseCallgraphCalleesSuffix => '个调用';

  @override
  String get webReverseCallgraphNoDetectedCalls => '（无识别到的调用）';

  @override
  String webReverseCallgraphParsing(int done, int total, String url) {
    return '解析中 $done/$total: $url';
  }

  @override
  String webReverseCallgraphDone(int scripts, int fns) {
    return '完成：$scripts 个脚本，$fns 个函数';
  }

  @override
  String webReverseCallgraphScriptsCount(int count) {
    return '脚本 ($count)';
  }

  @override
  String webReverseCallgraphHitsHeader(int count, String name) {
    return '反查命中 $count：包含调用「$name」的函数';
  }

  @override
  String get webReverseSwDebugFetchingRegs => '拉取注册列表...';

  @override
  String get webReverseSwDebugToggleFailed => '切换失败';

  @override
  String get webReverseSwDebugForceUpdateOn => '已开启强制更新';

  @override
  String get webReverseSwDebugForceUpdateOff => '已关闭';

  @override
  String get webReverseSwDebugTitle => 'Service Worker 调试';

  @override
  String get webReverseSwDebugSubtitle =>
      'ServiceWorker 域：启停/更新/注销/触发 sync/push';

  @override
  String get webReverseSwDebugRefresh => '刷新';

  @override
  String get webReverseSwDebugForceUpdateLabel => '每次刷新强制取新版本 SW';

  @override
  String get webReverseSwDebugEmptyList => '当前 target 无 Service Worker';

  @override
  String get webReverseSwDebugPushDataLabel => 'push 数据 (字符串)';

  @override
  String get webReverseSwDebugBtnStart => '启动';

  @override
  String get webReverseSwDebugBtnStop => '停止';

  @override
  String get webReverseSwDebugBtnUpdate => '更新';

  @override
  String get webReverseSwDebugBtnSync => '触发 sync';

  @override
  String get webReverseSwDebugBtnPush => '送 push';

  @override
  String get webReverseSwDebugBtnUnregister => '注销';

  @override
  String webReverseSwDebugWorkersCount(int count) {
    return '共 $count 个 Service Worker';
  }

  @override
  String webReverseSwDebugMethodFailed(String method, String err) {
    return '$method 失败: $err';
  }

  @override
  String webReverseSwDebugMethodOk(String method) {
    return '已执行 $method';
  }

  @override
  String get webReverseSetupTargetUrl => '目标 URL *';

  @override
  String get webReverseSetupObjective => '逆向目标 *';

  @override
  String get webReverseSetupObjectiveHint => '例如：复现壁纸下载接口，输出 curl 脚本';

  @override
  String get webReverseSetupTriggerActions => '触发动作（可选）';

  @override
  String get webReverseSetupTriggerHint => '例如：登录后点击“下载原图”按钮';

  @override
  String get webReverseSetupLoginMode => '登录态';

  @override
  String get webReverseSetupBrowser => '浏览器（已检测）';

  @override
  String get webReverseSetupProxy => '代理（可选）';

  @override
  String get webReverseSetupKeywords => '关键字（可选，逗号分隔）';

  @override
  String get webReverseSetupCreateThread => '创建线程';

  @override
  String get webReverseSetupHeaderTitle => '新建 Web 逆向会话';

  @override
  String get webReverseSetupHeaderSubtitle => '会话启动后会拉起浏览器并吸附在主窗口右侧';

  @override
  String get webReverseSetupClose => '关闭';

  @override
  String get webReverseSetupProfileDir => 'Profile 目录';

  @override
  String get webReverseSetupLockDetected =>
      '检测到 SingletonLock / lockfile 残留，可能阻止浏览器再次启动。';

  @override
  String get webReverseSetupWorking => '处理中…';

  @override
  String webReverseSetupCooldown(int seconds) {
    return '冷却中（${seconds}s）';
  }

  @override
  String get webReverseSetupResolveLock => '解决 Profile 冲突';

  @override
  String get webReverseSignatureDiffHeaderTitle => '签名字段变量定位器';

  @override
  String get webReverseSignatureDiffHeaderSubtitle =>
      '同 endpoint 多次抓包后自动识别动态字段（sign / ts / nonce）与稳定字段';

  @override
  String get webReverseSignatureDiffRefresh => '刷新';

  @override
  String get webReverseSignatureDiffSearchHint => '搜索 endpoint';

  @override
  String get webReverseSignatureDiffNoGroups => '暂无可分析的请求组（需 ≥2 次）';

  @override
  String get webReverseSignatureDiffEmptyHint =>
      '在 Network 面板里多次触发同一 API，再回来这里分析。';

  @override
  String get webReverseSignatureDiffCopyReport => '复制报告';

  @override
  String get webReverseSignatureDiffStable => '稳定';

  @override
  String get webReverseSignatureDiffDynamic => '动态';

  @override
  String get webReverseSignatureDiffIncreasing => '递增';

  @override
  String get webReverseSignatureDiffFixedHash => '定长哈希';

  @override
  String get webReverseSignatureDiffSectionQuery => 'Query 参数';

  @override
  String get webReverseSignatureDiffSectionHeaders => '请求 Header';

  @override
  String get webReverseSignatureDiffSectionBody => '请求体 JSON 字段';

  @override
  String get webReverseSignatureDiffReportTitle => '签名字段分析';

  @override
  String get webReverseSignatureDiffReportSamples => '样本数';

  @override
  String get webReverseSignatureDiffReportCopied => '报告已复制到剪贴板';

  @override
  String get webReverseCoverageStartFailed => '启动失败';

  @override
  String get webReverseCoverageCollecting => '已开始采集';

  @override
  String get webReverseCoverageTakeFailed => '采样失败';

  @override
  String get webReverseCoverageStopped => '已停止';

  @override
  String get webReverseCoverageReportCopied => '已复制报告';

  @override
  String get webReverseCoverageTitle => '代码覆盖率';

  @override
  String get webReverseCoverageSubtitle => '开始采集 → 在页面里操作 → 采样查看哪些脚本被执行';

  @override
  String get webReverseCoverageRecording => '采集中';

  @override
  String get webReverseCoverageStart => '开始';

  @override
  String get webReverseCoverageTake => '采样';

  @override
  String get webReverseCoverageStop => '停止';

  @override
  String get webReverseCoverageFilterHint => '按 URL 过滤';

  @override
  String get webReverseCoverageCopyReport => '复制报告';

  @override
  String get webReverseCoverageNoData => '尚无数据。Start → 操作页面 → Take。';

  @override
  String get webReverseCoverageClose => '关闭';

  @override
  String get webReverseCoverageCopyUrl => '复制 URL';

  @override
  String get webReverseCoverageCopied => '已复制';

  @override
  String webReverseCoverageSampledCount(int count) {
    return '采样完成 $count 个脚本';
  }

  @override
  String get webReverseDeviceEmuTitle => '设备模拟';

  @override
  String get webReverseDeviceEmuPresets => '预设';

  @override
  String get webReverseDeviceEmuCustom => '自定义';

  @override
  String get webReverseDeviceEmuWidth => '宽度';

  @override
  String get webReverseDeviceEmuHeight => '高度';

  @override
  String get webReverseDeviceEmuMobileMode => '移动模式 (touch + meta viewport)';

  @override
  String get webReverseDeviceEmuUaHint => '留空保持默认 UA';

  @override
  String get webReverseDeviceEmuApplyCustom => '应用自定义';

  @override
  String get webReverseDeviceEmuReset => '清除模拟';

  @override
  String get webReverseDeviceEmuClose => '关闭';

  @override
  String get webReverseDeviceEmuMinSize => '尺寸至少 100×100';

  @override
  String get webReverseDeviceEmuResetDone => '已恢复默认';

  @override
  String get webReverseDeviceEmuApplied => '已应用';

  @override
  String get webReverseDeviceEmuClearingOverrides => '清除设备模拟...';

  @override
  String get webReverseDeviceEmuApplyingCustom => '应用自定义尺寸...';

  @override
  String webReverseDeviceEmuApplyingPreset(String label) {
    return '应用预设 $label...';
  }

  @override
  String webReverseDeviceEmuAppliedPreset(String label) {
    return '已应用 $label';
  }

  @override
  String webReverseDeviceEmuAppliedCustomSize(int w, int h, String dpr) {
    return '已应用 $w×$h @ ${dpr}x';
  }

  @override
  String get webReverseWatchCopiedJson => '已复制 JSON';

  @override
  String get webReverseWatchTitle => '变量监视器';

  @override
  String get webReverseWatchExportJson => '导出 JSON';

  @override
  String get webReverseWatchPause => '暂停';

  @override
  String get webReverseWatchResume => '继续';

  @override
  String get webReverseWatchNoExpressions => '尚无表达式';

  @override
  String get webReverseWatchAwaiting => '等待求值…';

  @override
  String get webReverseWatchDelete => '删除';

  @override
  String get webReverseWatchNameLabel => '名称（可选）';

  @override
  String get webReverseWatchExpressionLabel => 'JS 表达式';

  @override
  String get webReverseWatchAddWatch => '添加监视';

  @override
  String get webReverseWatchPickWatch => '左侧选择监视项';

  @override
  String get webReverseWatchClose => '关闭';

  @override
  String get webReverseWatchInterval => '轮询间隔';

  @override
  String get webReverseWatchNewestFirst => '最新在上';

  @override
  String get webReverseWatchAwaitingFirst => '等待第一次求值…';

  @override
  String webReverseWatchSubtitleHint(int ms, int count) {
    return '每 ${ms}ms 跑一次 Runtime.evaluate，记录最近 $count 次结果';
  }

  @override
  String webReverseWatchHistory(int count) {
    return '历史（$count）';
  }

  @override
  String get webReverseAccountSnapTitle => '多账号会话快照';

  @override
  String get webReverseAccountSnapSubtitle =>
      '保存当前 cookies + localStorage/sessionStorage，一键切换不同账号';

  @override
  String get webReverseAccountSnapNameLabel => '为当前账号取名';

  @override
  String get webReverseAccountSnapNameHint => '如 main / test-001';

  @override
  String get webReverseAccountSnapCapture => '保存当前';

  @override
  String get webReverseAccountSnapExportAll => '导出全部到剪贴板';

  @override
  String get webReverseAccountSnapImport => '从剪贴板导入';

  @override
  String get webReverseAccountSnapClose => '关闭';

  @override
  String get webReverseAccountSnapEmptyHint => '还没有任何快照。在上方输入名字 → 点\"保存当前\"开始';

  @override
  String get webReverseAccountSnapApply => '应用';

  @override
  String get webReverseAccountSnapDelete => '删除';

  @override
  String get webReverseAccountSnapApplyFailedNoCdp => '应用失败：未连上 CDP';

  @override
  String get webReverseAccountSnapNotSnapshotJson => '剪贴板内容不是有效快照 JSON';

  @override
  String webReverseAccountSnapSavedSnapshot(String name, int count) {
    return '已保存「$name」（$count cookies）';
  }

  @override
  String webReverseAccountSnapAppliedSnapshot(String name) {
    return '已应用「$name」，建议刷新页面让 JS 重新读取';
  }

  @override
  String webReverseAccountSnapCopiedCount(int count) {
    return '已复制 $count 份快照 JSON 到剪贴板';
  }

  @override
  String webReverseAccountSnapImportedCount(int count) {
    return '已导入 $count 份快照';
  }

  @override
  String webReverseAccountSnapSnapshotsCount(int count) {
    return '共 $count 份';
  }

  @override
  String get webReverseReqBpNewBreakpoint => '新断点';

  @override
  String get webReverseReqBpTitle => '报文条件断点';

  @override
  String get webReverseReqBpSubtitle =>
      'URL/Body 子串命中即记录 + 触发 JS 表达式；需提前开启工具栏「请求拦截」';

  @override
  String get webReverseReqBpInterceptOff => '拦截未开启';

  @override
  String get webReverseReqBpAdd => '新增';

  @override
  String get webReverseReqBpEmptyHint => '点右上 + 新建第一个断点';

  @override
  String get webReverseReqBpUnnamed => '(未命名)';

  @override
  String get webReverseReqBpPickHint => '左侧选一条断点开始编辑';

  @override
  String get webReverseReqBpClear => '清空';

  @override
  String get webReverseReqBpNoHits => '暂无命中';

  @override
  String get webReverseReqBpNameField => '名称';

  @override
  String get webReverseReqBpAnyMethod => '任意方法';

  @override
  String get webReverseReqBpUrlContains => 'URL 包含';

  @override
  String get webReverseReqBpBodyContains => '请求体包含';

  @override
  String get webReverseReqBpEvalOnHit => '命中后执行（可选）';

  @override
  String get webReverseReqBpEvalHint =>
      '例如 debugger; 或 console.trace(\"hit\", new Error().stack)';

  @override
  String get webReverseReqBpDeleteBreakpoint => '删除此断点';

  @override
  String webReverseReqBpHitsCount(int count) {
    return '命中事件（最近 $count）';
  }

  @override
  String get webReverseWsInjectTitle => 'WebSocket 主动注入';

  @override
  String get webReverseWsInjectSubtitle =>
      '所有页面创建的 WebSocket 实例都会被代理 → 选择目标 → 注入任意文本帧';

  @override
  String get webReverseWsInjectProxyOn => '已注入代理';

  @override
  String get webReverseWsInjectInstallFailed => '注入安装失败';

  @override
  String get webReverseWsInjectRefresh => '刷新';

  @override
  String get webReverseWsInjectNoLive => '当前没有活跃 WebSocket。\n刷新页面让代理接管新连接。';

  @override
  String get webReverseWsInjectPayloadLabel => '要发送的文本帧 / JSON';

  @override
  String get webReverseWsInjectPaste => '粘贴';

  @override
  String get webReverseWsInjectPickTarget => '请选择目标连接';

  @override
  String get webReverseWsInjectTargetLabel => '目标';

  @override
  String get webReverseWsInjectLogEmpty => '注入日志会出现在这里';

  @override
  String get webReverseWsInjectClose => '关闭';

  @override
  String get webReverseWsInjectSend => '注入';

  @override
  String get webReverseWsInjectInjected => '注入成功';

  @override
  String get webReverseWsInjectInjectFailed => '注入失败';

  @override
  String webReverseWsInjectLiveCount(int count) {
    return '已发现 $count 个 WebSocket';
  }

  @override
  String webReverseWsInjectSentBytes(int count) {
    return '已注入 $count 字节';
  }

  @override
  String webReverseWsInjectFailedReason(String reason) {
    return '失败：$reason';
  }

  @override
  String get webReversePmTitle => 'postMessage 追踪';

  @override
  String get webReversePmSubtitle =>
      '注入 hook → ring buffer → 800ms 拉取队列；含 iframe 跨域通信';

  @override
  String get webReversePmHookInjected => '已注入 postMessage hook';

  @override
  String get webReversePmHookStopped => '已停止采集';

  @override
  String get webReversePmStop => '停止';

  @override
  String get webReversePmInject => '开始注入';

  @override
  String get webReversePmClear => '清空';

  @override
  String get webReversePmCopyJson => '复制 JSON';

  @override
  String get webReversePmFilterHint => 'origin/target/data 子串过滤';

  @override
  String get webReversePmChipSend => '发送';

  @override
  String get webReversePmChipRecv => '接收';

  @override
  String get webReversePmWaiting => '等待 postMessage…';

  @override
  String get webReversePmClickToCapture => '点击「开始注入」后页面会开始上报';

  @override
  String get webReversePmTagSend => '发送';

  @override
  String get webReversePmTagRecv => '接收';

  @override
  String get webReversePmClose => '关闭';

  @override
  String webReversePmCopiedCount(int count) {
    return '已复制 $count 条';
  }

  @override
  String get webReverseThrottleEnableNetwork => '启用 Network 域...';

  @override
  String get webReverseThrottleApplyFailed => '应用失败';

  @override
  String get webReverseThrottleConditionsApplied => '已应用网络条件';

  @override
  String get webReverseThrottleTitle => '网络条件模拟';

  @override
  String get webReverseThrottleSubtitle =>
      'Network.emulateNetworkConditions：选择预设或自定义 kbps/延迟';

  @override
  String get webReverseThrottlePresets => '预设档';

  @override
  String get webReverseThrottleCustom => '自定义';

  @override
  String get webReverseThrottleDownKbps => '下行 kbps (0=不限)';

  @override
  String get webReverseThrottleUpKbps => '上行 kbps (0=不限)';

  @override
  String get webReverseThrottleLatencyMs => '延迟 ms';

  @override
  String get webReverseThrottleOffline => '离线';

  @override
  String get webReverseThrottleDisableCache => '禁用缓存';

  @override
  String get webReverseThrottleApplyCustom => '应用自定义';

  @override
  String get webReverseThrottleReset => '重置（不限速）';

  @override
  String get webReverseThrottleNotes => '提示';

  @override
  String get webReverseThrottleNotesBody =>
      '· 限速对当前 target 整个 session 生效，关闭浏览器或调用「不限速」可恢复。\n· kbps 经 *1024/8 转换为 bytes/s 下发；离线时吞吐量参数被忽略。\n· 禁用缓存对 Fetch/Disk Cache 同时生效，便于复现首次访问。';

  @override
  String get webReverseThrottleClose => '关闭';

  @override
  String get webReverseThrottleUnknownError => '未知错误';

  @override
  String webReverseThrottleStatusFailed(String reason) {
    return '失败：$reason';
  }

  @override
  String webReverseThrottleStatusApplied(String summary) {
    return '已应用：$summary';
  }

  @override
  String get webReverseDomMutTitle => 'DOM Mutation 录制';

  @override
  String get webReverseDomMutSubtitle =>
      '注入 MutationObserver → childList/attributes/characterData → 时间线';

  @override
  String get webReverseDomMutRecordingStarted => '已开始录制 DOM 变更';

  @override
  String webReverseDomMutInstallFailed(String error) {
    return '安装失败：$error';
  }

  @override
  String webReverseDomMutCopiedRecords(int count) {
    return '已复制 $count 条变更 JSON';
  }

  @override
  String get webReverseDomMutExportJson => '导出 JSON';

  @override
  String get webReverseDomMutRecording => '录制中';

  @override
  String get webReverseDomMutStart => '开始录制';

  @override
  String get webReverseDomMutStop => '停止';

  @override
  String get webReverseDomMutClear => '清空';

  @override
  String get webReverseDomMutFilterHint => '过滤（子串）';

  @override
  String get webReverseDomMutAutoFollow => '自动跟随';

  @override
  String webReverseDomMutCounter(int count, int total) {
    return '$count/$total';
  }

  @override
  String get webReverseDomMutWaiting => '等待 DOM 变更…';

  @override
  String get webReverseDomMutPressStart => '点击开始录制';

  @override
  String get webReverseDomMutClose => '关闭';

  @override
  String get webReverseSmTitle => 'SourceMap 反解析';

  @override
  String get webReverseSmSubtitle => '压缩 file:line:col → 原始 source:line:col';

  @override
  String get webReverseSmInvalidInput => '请输入合法 URL 与行号';

  @override
  String get webReverseSmFetching => '抓取 sourcemap...';

  @override
  String webReverseSmFetchFailed(String error) {
    return '获取失败: $error';
  }

  @override
  String get webReverseSmBadEvalResult => '返回值异常';

  @override
  String get webReverseSmNoMapping => '未找到对应映射段';

  @override
  String get webReverseSmResolved => '解析成功';

  @override
  String get webReverseSmCopied => '已复制';

  @override
  String get webReverseSmUrlLabel => '压缩文件 URL';

  @override
  String get webReverseSmLineLabel => '行 (1-based)';

  @override
  String get webReverseSmColLabel => '列 (0-based)';

  @override
  String get webReverseSmResolve => '解析';

  @override
  String get webReverseSmEmptyHint => '输入文件 URL 与位置后点击解析';

  @override
  String get webReverseSmCopyTooltip => '复制';

  @override
  String get webReverseSmNameLabel => '名称';

  @override
  String get webReverseSmClose => '关闭';

  @override
  String get webReverseCssCovStarting => '启用 CSS 域并启动追踪...';

  @override
  String webReverseCssCovStartFailed(String error) {
    return '启动失败: $error';
  }

  @override
  String get webReverseCssCovTrackingActive =>
      '正在追踪 — 请在页面上交互（点击、滚动、悬浮等），然后点击「停止并统计」。';

  @override
  String get webReverseCssCovStopping => '停止并聚合结果...';

  @override
  String webReverseCssCovStopFailed(String error) {
    return '停止失败: $error';
  }

  @override
  String webReverseCssCovResultsTallied(int sheets, int rules) {
    return '已统计 $sheets 个样式表，共 $rules 条规则。';
  }

  @override
  String get webReverseCssCovJsonCopied => 'JSON 已复制';

  @override
  String get webReverseCssCovTitle => 'CSS 规则使用率';

  @override
  String get webReverseCssCovSubtitle =>
      'CSS.startRuleUsageTracking · 统计未命中的死代码';

  @override
  String get webReverseCssCovCopyJson => '复制 JSON';

  @override
  String get webReverseCssCovTracking => '追踪中';

  @override
  String get webReverseCssCovIdle => '空闲';

  @override
  String get webReverseCssCovStopAndTally => '停止并统计';

  @override
  String get webReverseCssCovStartTracking => '开始追踪';

  @override
  String get webReverseCssCovEmpty => '尚无结果。开始追踪后在页面上交互。';

  @override
  String webReverseCssCovRuleStats(
    int used,
    int total,
    String usedKb,
    String totalKb,
  ) {
    return '$used/$total 规则 · $usedKb/$totalKb KB';
  }

  @override
  String get webReverseCssCovClose => '关闭';

  @override
  String get webReverseAiCryptoStatusFetchResources => '获取 frame 资源...';

  @override
  String get webReverseAiCryptoStatusDetecting => '提取嫌疑字段...';

  @override
  String get webReverseAiCryptoStatusDone => '完成';

  @override
  String get webReverseAiCryptoCopied => '已复制到剪贴板';

  @override
  String get webReverseAiCryptoTitle => 'AI 加密参数还原';

  @override
  String get webReverseAiCryptoSubtitle =>
      '聚合 endpoint → diff 变量字段 → JS 源码定位 → 一键复制提示词';

  @override
  String get webReverseAiCryptoRefresh => '重新聚合';

  @override
  String get webReverseAiCryptoEmpty => '没有可分析的 endpoint（需要同一接口至少抓 2 次）';

  @override
  String get webReverseAiCryptoAnalyze => '分析';

  @override
  String get webReverseAiCryptoCopyPrompt => '复制提示词';

  @override
  String get webReverseAiCryptoSuspectsLabel => '嫌疑字段：';

  @override
  String get webReverseAiCryptoPromptHint => '点击「分析」生成提示词。';

  @override
  String get webReverseAiCryptoClose => '关闭';

  @override
  String webReverseAiCryptoStatusSearchProgress(int done, int total) {
    return '搜索字段 $done/$total';
  }

  @override
  String webReverseAiCryptoHits(int count) {
    return '$count 次';
  }

  @override
  String get webReverseCdpSendFailed => '调用失败（未连接？）';

  @override
  String get webReverseCdpCopied => '已复制';

  @override
  String get webReverseCdpTitle => 'CDP Raw 命令控制台';

  @override
  String get webReverseCdpMethodLabel => 'method (Domain.command)';

  @override
  String get webReverseCdpUseSession => '使用 page session';

  @override
  String get webReverseCdpSend => '发送';

  @override
  String get webReverseCdpNoHistory => '历史为空';

  @override
  String get webReverseCdpSendHint => '发送命令后在此查看响应';

  @override
  String get webReverseCdpClose => '关闭';

  @override
  String get webReverseCdpCopyResponse => '复制响应 JSON';

  @override
  String get webReverseCdpParams => '请求参数';

  @override
  String get webReverseCdpResponse => '响应';

  @override
  String get webReverseCdpError => '错误';

  @override
  String webReverseCdpInvalidJson(String error) {
    return 'JSON 解析失败：$error';
  }

  @override
  String webReverseCdpSubtitle(int count) {
    return '⌘/Ctrl+Enter 发送 · Ctrl+↑/↓ 翻历史 · 共 $count 条';
  }

  @override
  String get webReversePerfTitle => 'Performance Trace 录制';

  @override
  String get webReversePerfSubtitle =>
      'Tracing 域 → chrome-trace JSON（Perfetto / chrome://tracing 加载）';

  @override
  String get webReversePerfDuration => '时长';

  @override
  String get webReversePerfCategories => 'Trace 分类';

  @override
  String get webReversePerfCopyPath => '复制路径';

  @override
  String get webReversePerfStop => '停止录制';

  @override
  String get webReversePerfStart => '开始录制';

  @override
  String get webReversePerfClose => '关闭';

  @override
  String get webReversePerfTraceFailed => '录制失败或无数据';

  @override
  String get webReversePerfStopping => '已请求停止，正在收尾…';

  @override
  String get webReversePerfTraceSaved => 'Trace 已保存';

  @override
  String get webReversePerfPathCopied => '路径已复制';

  @override
  String webReversePerfRecording(int seconds) {
    return '正在录制（剩余 ${seconds}s）';
  }

  @override
  String webReversePerfSaved(String path, String kb) {
    return '已保存：$path ($kb KB)';
  }

  @override
  String get webReverseReplayJsonCopied => 'JSON 已复制';

  @override
  String get webReverseReplayTitle => '网络请求批量重放器';

  @override
  String get webReverseReplaySubtitle => '多选 → 顺序重发 → 对比原状态与新状态';

  @override
  String get webReverseReplayCopyResultsJson => '复制结果 JSON';

  @override
  String get webReverseReplayFilterByUrl => '按 URL 过滤';

  @override
  String get webReverseReplaySelectAll => '全选';

  @override
  String get webReverseReplayClear => '清空';

  @override
  String get webReverseReplayEmpty => '当前会话没有 HTTP 请求';

  @override
  String get webReverseReplayRunBatch => '开始重放';

  @override
  String get webReverseReplayClose => '关闭';

  @override
  String webReverseReplayDone(int ok, int total) {
    return '重放完成：$ok/$total 成功';
  }

  @override
  String webReverseReplayProgress(int done, int total) {
    return '重放中 $done / $total';
  }

  @override
  String webReverseReplaySelected(int count, int total) {
    return '已选 $count / $total';
  }

  @override
  String get webReverseGeoOverridesApplied => '已应用覆盖';

  @override
  String get webReverseGeoEnvOverridesApplied => '环境覆盖已应用';

  @override
  String get webReverseGeoOverridesCleared => '已清除覆盖';

  @override
  String get webReverseGeoEnvOverridesCleared => '已清除环境覆盖';

  @override
  String get webReverseGeoTitle => '地理 / 时区 / 语言覆盖';

  @override
  String get webReverseGeoCityPresets => '预设城市';

  @override
  String get webReverseGeoEnableGeo => '启用地理位置覆盖';

  @override
  String get webReverseGeoEnableTz => '启用时区覆盖';

  @override
  String get webReverseGeoEnableLocale => '启用语言覆盖';

  @override
  String get webReverseGeoTip =>
      '提示：覆盖在当前 target 内立即生效，刷新仍保留。需通过页面 `navigator.geolocation`、`Intl.DateTimeFormat().resolvedOptions().timeZone`、`navigator.language` 来感知效果。某些站点会缓存首次结果，建议覆盖后再硬刷新。';

  @override
  String get webReverseGeoClear => '清除';

  @override
  String get webReverseGeoWorking => '处理中…';

  @override
  String get webReverseGeoApply => '应用覆盖';

  @override
  String get webReverseCollectionExportNothing => '没有可导出的请求';

  @override
  String get webReverseCollectionExportTitle => 'API 集合导出';

  @override
  String get webReverseCollectionExportSubtitle =>
      'Postman / Insomnia / Bruno / cURL / HAR  —— 一键复制';

  @override
  String get webReverseCollectionExportName => '集合名称';

  @override
  String get webReverseCollectionExportUrlFilter => 'URL 子串过滤';

  @override
  String get webReverseCollectionExportXhrOnly => '仅 XHR/Fetch';

  @override
  String get webReverseCollectionExportPreview2 => '下方为前两条预览';

  @override
  String get webReverseCollectionExportClose => '关闭';

  @override
  String get webReverseCollectionExportCopyAction => '复制集合';

  @override
  String get webReverseCollectionExportNoMatch =>
      '// 没有匹配的请求。\n// 调整过滤条件或取消「仅 XHR/Fetch」。';

  @override
  String webReverseCollectionExportCopied(int count) {
    return '已复制 $count 条请求到剪贴板';
  }

  @override
  String webReverseCollectionExportMatchCount(int match, int total) {
    return '匹配 $match 条 · 共 $total';
  }

  @override
  String get webReverseJwtTitle => 'JWT 自动续期';

  @override
  String get webReverseJwtSubtitle =>
      '扫描 cookies/localStorage/sessionStorage 中的 JWT，临近过期自动跑刷新脚本';

  @override
  String get webReverseJwtScanNow => '立即扫描';

  @override
  String get webReverseJwtRefreshNow => '手动续期';

  @override
  String get webReverseJwtAuto => '自动续期';

  @override
  String get webReverseJwtIntervalSec => '间隔(秒)';

  @override
  String get webReverseJwtThresholdSec => '阈值(秒)';

  @override
  String get webReverseJwtRefreshExpr => '刷新表达式 (async JS)';

  @override
  String get webReverseJwtNoneFound => '尚未发现 JWT';

  @override
  String get webReverseJwtRefreshLog => '续期日志';

  @override
  String get webReverseJwtClose => '关闭';

  @override
  String webReverseJwtFoundCount(int count) {
    return '已发现 JWT ($count)';
  }

  @override
  String get webReverseWebauthnTitle => 'WebAuthn 虚拟认证器';

  @override
  String get webReverseWebauthnDisabledBody =>
      '点击右上方开关启用 WebAuthn 虚拟域，然后即可创建虚拟认证器，让站点的 navigator.credentials.create / get 在无硬件密钥时也能完成。';

  @override
  String get webReverseWebauthnAdd => '新增虚拟认证器';

  @override
  String get webReverseWebauthnAddBtn => '添加';

  @override
  String get webReverseWebauthnNone => '尚无虚拟认证器';

  @override
  String get webReverseWebauthnClose => '关闭';

  @override
  String get webReverseWebauthnRefreshCreds => '刷新凭据列表';

  @override
  String get webReverseWebauthnRemove => '移除';

  @override
  String get webReverseWebauthnUserVerified => '用户已验证 (isUserVerified)';

  @override
  String webReverseWebauthnAdded(String id) {
    return '已添加 authenticator $id';
  }

  @override
  String webReverseWebauthnCreatedCount(int count) {
    return '已创建 ($count)';
  }

  @override
  String webReverseWebauthnCredentialsCount(int count) {
    return '凭据 ($count)';
  }

  @override
  String get webReverseInstallTitle => '需要 Google Chrome（或同核浏览器）';

  @override
  String get webReverseInstallClose => '关闭';

  @override
  String get webReverseInstallBody =>
      'Web 逆向专家依赖外部 Chrome / Edge / Brave / Chromium 等同核浏览器，通过 CDP（Chrome DevTools Protocol）通道驱动调试。检测到当前系统没有可用的同核浏览器。';

  @override
  String get webReverseInstallOpen => '在浏览器打开';

  @override
  String get webReverseInstallHint =>
      '建议安装 Chrome 正式版后重试。如已安装 Edge / Brave / Chromium，点击\"我已安装，重新检测\"。';

  @override
  String get webReverseInstallInstalled => '我已安装';

  @override
  String get webReverseProfileEmptyPath => 'Profile 路径为空，未执行';

  @override
  String get webReverseProfileNoResidual => '未发现残留锁文件。如仍无法启动，请查看诊断卡片其他根因。';

  @override
  String get webReverseProfileResetTitle => '锁仍未清干净，是否重置 profile？';

  @override
  String get webReverseProfileResetConfirm => '确认重置';

  @override
  String get webReverseProfileKept => '已保留 profile，但锁仍可能阻止下次启动。';

  @override
  String webReverseProfileCleanFailed(String error) {
    return '清理失败：$error';
  }

  @override
  String webReverseProfileCleaned(int count) {
    return '已清理 $count 个锁文件，profile 已恢复';
  }

  @override
  String webReverseProfileResetBody(String path) {
    return '已尝试清理 SingletonLock 等残留，但仍检测到锁文件。\n\n继续操作会递归删除：\n$path\n\n该 profile 下的 Cookies / Login Data / 已安装扩展 / 浏览历史 等数据将全部丢失，下次启动会重建一个全新 profile。';
  }

  @override
  String webReverseProfileResetDone(String path) {
    return '已重置 profile：$path（60 秒内不可重复操作）';
  }

  @override
  String webReverseProfileResetFailed(String error) {
    return '重置失败：$error';
  }

  @override
  String get webReverseReplNoResult => '(无返回)';

  @override
  String get webReverseReplCopied => '已复制';

  @override
  String get webReverseReplTitle => 'Console REPL';

  @override
  String get webReverseReplSubtitle =>
      'Runtime.evaluate · ↑/↓ 历史 · Ctrl/⌘+Enter 执行';

  @override
  String get webReverseReplClear => '清空输出';

  @override
  String get webReverseReplEmpty => '在下方输入 JS 表达式 → Ctrl/⌘+Enter 执行';

  @override
  String get webReverseReplHint =>
      '示例: document.title  或  await fetch(\"/api\").then(r=>r.json())';

  @override
  String get webReverseReplRun => '执行';

  @override
  String get webReverseConsoleEvalFailed => '执行失败';

  @override
  String get webReverseConsoleEmpty => '暂无控制台输出。';

  @override
  String get webReverseConsolePausedHint => '调试器已暂停 · 表达式将在当前栈帧的作用域内求值';

  @override
  String get webReverseConsoleReplHint => '输入 JS 表达式回车执行；↑↓ 浏览历史';

  @override
  String get webReverseConsoleClusterCopied => '簇 JSON 已复制';

  @override
  String get webReverseConsoleClusterTitle => 'Console 错误聚类';

  @override
  String get webReverseConsoleClusterRefresh => '刷新';

  @override
  String get webReverseConsoleClusterFilterHint => '关键字过滤';

  @override
  String get webReverseConsoleClusterNoMatch => '没有匹配的 console 条目';

  @override
  String get webReverseConsoleClusterCopyJson => '复制 JSON';

  @override
  String webReverseConsoleClusterSubtitle(int entries, int clusters) {
    return '按 level + 归一化首行去重 · 共 $entries 条 / $clusters 簇';
  }

  @override
  String webReverseConsoleClusterTimes(String first, String last) {
    return '首次：$first\n末次：$last';
  }

  @override
  String webReverseConsoleClusterMore(int count) {
    return '… 还有 $count 条';
  }

  @override
  String get webReverseDomSearchTitle => 'DOM 选择器搜索';

  @override
  String get webReverseDomSearchSearching => '搜索中...';

  @override
  String get webReverseDomSearchNoMatches => '无匹配结果';

  @override
  String get webReverseDomSearchHint => '输入 selector / 文本 / XPath，回车搜索';

  @override
  String get webReverseDomSearchRun => '搜索';

  @override
  String get webReverseDomSearchExample =>
      '示例: button[data-action] · #login · //a[contains(@href,\"docs\")]';

  @override
  String get webReverseDomSearchHighlight => '在页面高亮';

  @override
  String webReverseDomSearchFailed(String error) {
    return '搜索失败: $error';
  }

  @override
  String webReverseDomSearchGetFailed(String error) {
    return '获取结果失败: $error';
  }

  @override
  String webReverseDomSearchHitCount(int total, int shown) {
    return '命中 $total 个，展示前 $shown 条';
  }

  @override
  String get webReverseFrameTreeTitle => 'Frame 树查看器';

  @override
  String get webReverseFrameTreeSubtitle =>
      'Page.getFrameTree · 主框架 + 所有 iframe 递归';

  @override
  String get webReverseFrameTreeRefresh => '刷新';

  @override
  String get webReverseFrameTreeCopyJson => '复制 JSON';

  @override
  String get webReverseFrameTreeCopied => '已复制';

  @override
  String get webReverseFrameTreeEmpty => '当前页面无 frame';

  @override
  String webReverseFrameTreeFailed(String error) {
    return '获取失败: $error';
  }

  @override
  String webReverseFrameTreeCount(int count) {
    return '共 $count 帧';
  }

  @override
  String get webReverseCpuThrottleOff => 'CPU 限速已关闭';

  @override
  String get webReverseCpuThrottleResetDone => '已恢复';

  @override
  String get webReverseCpuThrottleTitle => 'CPU 限速';

  @override
  String get webReverseCpuThrottlePresets => '常用预设';

  @override
  String get webReverseCpuThrottleNote =>
      '注意：CDP CPU 限速作用于渲染进程，不影响 GPU/网络。关闭窗口后限速仍生效，请手动选择 1×（off）或点「重置」恢复。';

  @override
  String get webReverseCpuThrottleReset => '重置 (1×)';

  @override
  String webReverseCpuThrottleApplying(String rate) {
    return '设置 CPU 限速 $rate×...';
  }

  @override
  String webReverseCpuThrottleFailed(String error) {
    return '失败: $error';
  }

  @override
  String webReverseCpuThrottleCurrent(String rate) {
    return '当前 CPU 限速 $rate×';
  }

  @override
  String webReverseCpuThrottleSliderLabel(String rate) {
    return '滑动调节 $rate×';
  }

  @override
  String webReverseCpuThrottleApplied(String rate) {
    return '已应用 $rate× 限速';
  }

  @override
  String get webReverseHeapTaking => '正在抓取 Heap Snapshot（可能耗时数秒）...';

  @override
  String get webReverseHeapFailed => '抓取失败或无数据';

  @override
  String get webReverseHeapSavedToast => 'Heap snapshot 已保存';

  @override
  String get webReverseHeapPathCopied => '路径已复制';

  @override
  String get webReverseHeapSubtitle =>
      'HeapProfiler.takeHeapSnapshot → .heapsnapshot（DevTools Memory 可加载）';

  @override
  String get webReverseHeapEmptyHint =>
      '点击下方按钮抓取当前页面的 V8 Heap Snapshot。\n大型页面可能产生 50MB+ 文件。';

  @override
  String get webReverseHeapCopyPath => '复制路径';

  @override
  String get webReverseHeapTake => '抓取快照';

  @override
  String webReverseHeapSaved(String path, String mb) {
    return '已保存：$path ($mb MB)';
  }

  @override
  String get webReverseRealtimeDirSent => '发出';

  @override
  String get webReverseRealtimeDirRecv => '收到';

  @override
  String get webReverseRealtimeDirError => '错误';

  @override
  String get webReverseRealtimePayloadCopied => '已复制载荷';

  @override
  String get webReverseRealtimeTitle => '实时连接';

  @override
  String get webReverseRealtimeEmpty =>
      '当前页面未抓到 WebSocket / EventSource。\n触发动作后此处会实时刷新。';

  @override
  String get webReverseRealtimePickPrompt => '从左侧选一个连接以查看帧流。';

  @override
  String get webReverseRealtimeFilterHint => '过滤载荷（子串）';

  @override
  String get webReverseRealtimeAutoFollow => '自动跟随';

  @override
  String get webReverseRealtimeNoMatching => '无匹配帧。';

  @override
  String webReverseRealtimeFrameCount(int count) {
    return '$count 帧';
  }

  @override
  String get webReverseMarkupTitle => '截图标注';

  @override
  String get webReverseMarkupSaveWithout => '不标注直接保存';

  @override
  String get webReverseMarkupExporting => '导出中…';

  @override
  String get webReverseMarkupDone => '完成';

  @override
  String get webReverseMarkupUndo => '撤销';

  @override
  String get webReverseMarkupClear => '清空';

  @override
  String get webReverseMarkupAddTextTitle => '添加文字注释';

  @override
  String get webReverseMarkupLabelHint => '输入标注文字';

  @override
  String get webReverseMarkupAdd => '添加';

  @override
  String get webReverseElementsLoadFailed => '加载失败：浏览器未启动或 CDP 不可用';

  @override
  String get webReverseElementsSelectorFailed => '无法生成 selector';

  @override
  String get webReverseElementsSelectorCopied => '已复制 selector';

  @override
  String get webReverseElementsXPathFailed => '无法生成 XPath';

  @override
  String get webReverseElementsXPathCopied => '已复制 XPath';

  @override
  String get webReverseElementsReloadDom => '刷新 DOM 根';

  @override
  String get webReverseElementsCopySelector => '复制 selector';

  @override
  String get webReverseElementsCopyXPath => '复制 XPath';

  @override
  String get webReverseElementsScrollIntoView => '页面定位';

  @override
  String get webReverseElementsPickElement => '从左侧 DOM 树选择一个元素';

  @override
  String get webReverseElementsNoAttrs => '该元素无属性';

  @override
  String get webReverseElementsNoComputed => '无计算样式';

  @override
  String get webReverseElementsNoListeners => '该元素无监听';

  @override
  String webReverseElementsAttrsTab(int count) {
    return '属性 ($count)';
  }

  @override
  String webReverseElementsComputedTab(int count) {
    return '计算样式 ($count)';
  }

  @override
  String webReverseElementsListenersTab(int count) {
    return '事件 ($count)';
  }

  @override
  String get webReverseCryptoSecEncode => '编解码';

  @override
  String get webReverseCryptoSecHash => '哈希';

  @override
  String get webReverseCryptoSecTime => '时间戳';

  @override
  String get webReverseCryptoClear => '清空';

  @override
  String get webReverseCryptoInputHint => '在此粘贴待处理文本…';

  @override
  String get webReverseCryptoInputLabel => '输入';

  @override
  String get webReverseCryptoCopy => '复制';

  @override
  String get webReverseCryptoUseAsInput => '回填到输入';

  @override
  String get webReverseCryptoLengthLabel => '长度';

  @override
  String get webReverseCryptoTsToIso => '时间戳 → ISO';

  @override
  String get webReverseCryptoIsoToTs => 'ISO → 时间戳';

  @override
  String get webReverseCryptoNow => '当前时间';

  @override
  String get webReverseCryptoUuidHint => '随机 UUID v4（点击复制）';

  @override
  String get webReverseCryptoRegenerate => '重新生成';

  @override
  String webReverseCryptoCopied(String label) {
    return '已复制 $label';
  }

  @override
  String webReverseCryptoLengthValue(int chars, int bytes) {
    return '字符 $chars / 字节 $bytes';
  }

  @override
  String get webReverseHooksDefaultCode => '在每个文档加载前执行；可 patch window/fetch 等';

  @override
  String get webReverseHooksSavedToast => '已保存并热重载';

  @override
  String get webReverseHooksDeleteTitle => '删除 hook？';

  @override
  String get webReverseHooksDeleteContent => '将立即卸载并不可撤销。';

  @override
  String get webReverseHooksDelete => '删除';

  @override
  String get webReverseHooksDiscardTitle => '丢弃未保存改动？';

  @override
  String get webReverseHooksKeepEditing => '继续编辑';

  @override
  String get webReverseHooksDiscardConfirm => '丢弃';

  @override
  String get webReverseHooksLibrary => 'JS Hook 库';

  @override
  String get webReverseHooksNew => '新建 hook';

  @override
  String get webReverseHooksEmpty => '暂无 hook。\n点 + 新建第一个。';

  @override
  String get webReverseHooksPickPrompt => '从左侧选一个 hook，或新建一个。';

  @override
  String get webReverseHooksNameLabel => '名称';

  @override
  String get webReverseHooksSave => '保存 (⌘S)';

  @override
  String get webReverseHooksSaved => '已保存';

  @override
  String get webReverseHooksInfo => '保存即重装。脚本在文档加载前执行；切换 tab / 刷新页面后仍生效。';

  @override
  String webReverseHooksNewName(String time) {
    return '钩子 $time';
  }

  @override
  String get webReverseSnippetsDefaultCode => '在此编写 JS，将在浏览器页面上下文执行';

  @override
  String get webReverseSnippetsNoResult => '(无返回值)';

  @override
  String get webReverseSnippetsDeleteTitle => '删除脚本？';

  @override
  String get webReverseSnippetsDeleteContent => '不可撤销。';

  @override
  String get webReverseSnippetsDelete => '删除';

  @override
  String get webReverseSnippetsTitle => '脚本注入库';

  @override
  String get webReverseSnippetsNew => '新建脚本';

  @override
  String get webReverseSnippetsEmpty => '暂无脚本。\n点 + 新建第一个。';

  @override
  String get webReverseSnippetsPickPrompt => '从左侧选一个脚本，或新建一个。';

  @override
  String get webReverseSnippetsRun => '运行 (⌘R)';

  @override
  String get webReverseSnippetsSaveDirty => '保存 *';

  @override
  String webReverseSnippetsNewName(String time) {
    return '脚本 $time';
  }

  @override
  String get servicesTitle => '服务';

  @override
  String get servicesSubtitle => '汇聚 OpenHand 自研的专业服务，提供稳定、可控、可审计的任务执行体验。';

  @override
  String get servicesProprietaryBadge => 'OpenHand 自研';

  @override
  String get servicesAiInfrastructureExposureScanTitle => 'AI 基础设施暴露面扫描';

  @override
  String get servicesAiInfrastructureExposureScanDescription =>
      '面向已授权目标，持续发现 AI 服务暴露面，识别凭证泄露与高风险配置，并沉淀可审计的处置线索。';

  @override
  String get agentsTitle => '智能体';

  @override
  String get agentsSubtitle => '统一管理 Hermes Agent 数字员工的档案、权限、任务、集群、审计与 KPI。';

  @override
  String get agentsCreateAgent => '创建智能体';

  @override
  String get agentsEditAgent => '编辑智能体';

  @override
  String get agentsLoadFailed => '智能体配置加载失败';

  @override
  String get agentsRetry => '重试';

  @override
  String get agentsEmptyTitle => '还没有智能体';

  @override
  String get agentsEmptyBody => '点击右上角创建按钮，配置第一个具备职责边界、权限、任务台和治理能力的数字员工。';

  @override
  String get agentsMentorLabel => '导师';

  @override
  String get agentsStopAgent => '停止智能体';

  @override
  String get agentsStartAgent => '启动智能体';

  @override
  String get agentsActivities => '历史活动';

  @override
  String get agentsLogs => '日志';

  @override
  String get agentsCapabilityLogs => '能力调用日志';

  @override
  String get agentsApprovals => '审批';

  @override
  String get agentsCluster => '集群';

  @override
  String get agentsMore => '更多';

  @override
  String get agentsTaskDesk => '任务台';

  @override
  String get agentsAuditReport => '审计报表';

  @override
  String get agentsKpi => 'KPI';

  @override
  String get agentsResources => '资源管理';

  @override
  String get agentsDeleteAgent => '删除智能体';

  @override
  String agentsTasksCount(int running, int total) {
    return '任务 $running/$total';
  }

  @override
  String agentsApprovalsCount(int count) {
    return '审批 $count';
  }

  @override
  String agentsWorkersCount(int count, int max) {
    return 'Worker $count/$max';
  }

  @override
  String agentsCapabilitySkillsCount(int count) {
    return '技能 $count';
  }

  @override
  String agentsCapabilityKnowledgeCount(int count) {
    return '知识库 $count';
  }

  @override
  String agentsCapabilityMemoryCount(int count) {
    return '记忆 $count';
  }

  @override
  String agentsCapabilityToolsCount(int count) {
    return '工具 $count';
  }

  @override
  String agentsCapabilityCronsCount(int count) {
    return 'Crons $count';
  }

  @override
  String agentsCapabilityHooksCount(int count) {
    return 'Hooks $count';
  }

  @override
  String get agentsSelfLearningOn => '自我学习开启';

  @override
  String get agentsNoCapabilityResources => '尚未绑定能力资源';

  @override
  String agentsDialogTitleWithName(String title, String name) {
    return '$title · $name';
  }

  @override
  String get agentsActivitiesEmptyTitle => '暂无历史活动。';

  @override
  String get agentsLogsEmptyTitle => '暂无 Skill、记忆、MCP 或工具调用日志。';

  @override
  String get agentsApprovalsEmptyTitle => '暂无待审批请求。';

  @override
  String get agentsListEmptyBody => '智能体启动并执行任务后会自动沉淀这里。';

  @override
  String agentsMinWorkersCount(int count) {
    return '最小 $count';
  }

  @override
  String agentsMaxWorkersCount(int count) {
    return '最大 $count';
  }

  @override
  String get agentsNoWorkersTitle => '暂无 Worker';

  @override
  String get agentsNoWorkersBody => '保存配置后会按最小 Worker 数自动预置本地 Worker 状态。';

  @override
  String agentsWorkerSubtitle(String status, int done, int priority) {
    return '$status · 已执行 $done · 优先级 $priority';
  }

  @override
  String get agentsPublishTask => '发布任务';

  @override
  String get agentsNoTasksTitle => '暂无任务';

  @override
  String get agentsNoTasksBody => '可以从这里发布任务，后续 Worker 会按调度策略执行并回填结果。';

  @override
  String get agentsAuditRequests => '请求量';

  @override
  String get agentsAuditCompleted => '完成任务';

  @override
  String get agentsAuditUtilization => '利用率';

  @override
  String get agentsRecentAuditEvents => '最近审计事件';

  @override
  String get agentsNoAuditData => '暂无审计数据。';

  @override
  String get agentsNoKpiTitle => '暂无 KPI';

  @override
  String get agentsNoKpiBody => '在编辑配置里录入 KPI，智能体工作循环会据此规划推进。';

  @override
  String get agentsMetricMemory => '内存';

  @override
  String get agentsMetricDisk => '磁盘';

  @override
  String get agentsMetricPersisted => '持久化';

  @override
  String get agentsMetricHandles => '句柄';

  @override
  String get agentsPublish => '发布';

  @override
  String get agentsTaskTitleLabel => '任务标题';

  @override
  String get agentsDescriptionLabel => '介绍';

  @override
  String get agentsContentLabel => '内容';

  @override
  String get agentsNoteLabel => '备注';

  @override
  String get agentsDeleteConfirmTitle => '删除智能体';

  @override
  String agentsDeleteConfirmMessage(String name) {
    return '确定删除 $name？此操作不会删除已绑定的技能、知识库或 MCP。';
  }

  @override
  String get agentsTabProfile => '档案';

  @override
  String get agentsTabCapabilities => '能力';

  @override
  String get agentsTabRuntime => '运行';

  @override
  String get agentsTabGovernance => '治理';

  @override
  String get agentsTabMetadata => '元数据';

  @override
  String get agentsFieldAvatar => '头像';

  @override
  String get agentsFieldAvatarHint => '文字、Emoji 或图片标识';

  @override
  String get agentsFieldNameRequired => '名称 *';

  @override
  String get agentsFieldPosition => '岗位';

  @override
  String get agentsFieldDepartment => '部门';

  @override
  String get agentsFieldLevel => '等级';

  @override
  String get agentsFieldIntroduction => '介绍';

  @override
  String get agentsFieldArchive => '档案';

  @override
  String get agentsFieldRouteFrontMatter => '路由信息';

  @override
  String get agentsFieldWelcomeMessage => '欢迎语';

  @override
  String get agentsFieldPersona => '人设';

  @override
  String get agentsFieldResponsibilityBoundary => '职责边界';

  @override
  String get agentsKnowledgeBase => '知识库';

  @override
  String get agentsBuiltInTools => '内建工具';

  @override
  String get agentsModelLabel => '模型';

  @override
  String get agentsEnableAgentTitle => '启用智能体';

  @override
  String get agentsEnableAgentBody => '启用后智能体工作循环和智能体内建工具可用。';

  @override
  String get agentsSelfLearningTitle => '自我学习';

  @override
  String get agentsSelfLearningBody => '依托 Hermes Agent 沉淀 Skill、记忆与经验。';

  @override
  String get agentsFieldWorkspacePath => '工作目录';

  @override
  String get agentsFieldWorkspaceScope => '工作目录范围';

  @override
  String get agentsCrons => '定时任务';

  @override
  String get agentsClusterScaling => '集群伸缩';

  @override
  String get agentsMinWorkersLabel => '最小 Worker';

  @override
  String get agentsMaxWorkersLabel => '最大 Worker';

  @override
  String get agentsMaxRetriesLabel => '最大重试';

  @override
  String get agentsSchedulerPolicyLabel => '调度策略';

  @override
  String get agentsTaskLabelsLabel => '任务标签';

  @override
  String get agentsFieldName => '名称';

  @override
  String get agentsFieldTarget => '目标';

  @override
  String get agentsMetadataInfoTitle => '权限与轮廓元数据';

  @override
  String get agentsNoOptionsAvailable => '暂无可选项。';

  @override
  String get agentExecutionModeNormal => '默认模式';

  @override
  String get agentExecutionModeFullAccess => '完全访问模式';

  @override
  String get agentLifecycleStopped => '已停止';

  @override
  String get agentLifecycleRunning => '运行中';

  @override
  String get agentLifecyclePaused => '已暂停';

  @override
  String get agentLifecycleDegraded => '降级中';

  @override
  String get agentTaskStatusBacklog => '待分配';

  @override
  String get agentTaskStatusReady => '可执行';

  @override
  String get agentTaskStatusRunning => '执行中';

  @override
  String get agentTaskStatusWaitingApproval => '待审批';

  @override
  String get agentTaskStatusPaused => '已暂停';

  @override
  String get agentTaskStatusCompleted => '已完成';

  @override
  String get agentTaskStatusFailed => '失败';

  @override
  String get agentTaskStatusCanceled => '已取消';

  @override
  String get agentApprovalStatusPending => '待审批';

  @override
  String get agentApprovalStatusApproved => '已批准';

  @override
  String get agentApprovalStatusRejected => '已拒绝';

  @override
  String get agentApprovalStatusExpired => '已过期';

  @override
  String get agentWorkerStatusIdle => '空闲';

  @override
  String get agentWorkerStatusBusy => '忙碌';

  @override
  String get agentWorkerStatusDraining => '移出中';

  @override
  String get agentWorkerStatusOffline => '离线';

  @override
  String get agentsActivityAgentStarted => '智能体已启动';

  @override
  String get agentsActivityAgentStopped => '智能体已停止';

  @override
  String get agentsActivityTaskPublished => '任务已发布';

  @override
  String get agentsActivityTaskUpdated => '任务已更新';

  @override
  String get agentsActivityTaskCanceled => '任务已取消';

  @override
  String get agentsActivityTaskPaused => '任务已暂停';

  @override
  String get agentsActivityTaskTerminated => '任务已终止';

  @override
  String get agentsActivityTaskResumed => '任务已恢复';

  @override
  String get hookEventSessionStart => '会话开始';

  @override
  String get hookEventUserPromptSubmit => '用户提交提示词';

  @override
  String get hookEventPreToolUse => '工具调用前';

  @override
  String get hookEventPostToolUse => '工具调用后';

  @override
  String get hookEventSubagentStart => '子代理启动';

  @override
  String get hookEventSubagentStop => '子代理停止';

  @override
  String get hookEventStop => '代理停止';

  @override
  String get hookEventPreCompact => '上下文压缩前';

  @override
  String get hookEventSessionEnd => '会话结束';

  @override
  String get hookEventErrorOccurred => '发生错误';

  @override
  String get builtinToolLoadStrategyEagerShort => '立即';

  @override
  String get builtinToolLoadStrategyLazy => '懒加载';

  @override
  String get builtinToolLoadStrategyDeferred => '缓加载';

  @override
  String get builtinToolLoadStrategyEagerFull => '立即加载';

  @override
  String get builtinToolCustomBadge => '自定义';

  @override
  String get builtinToolForceBadge => '强制加载';

  @override
  String get builtinToolMoveUp => '上移';

  @override
  String get builtinToolMoveDown => '下移';

  @override
  String builtinToolEditorTitle(String kind) {
    return '编辑工具 — $kind';
  }

  @override
  String get builtinToolEnableTitle => '启用工具';

  @override
  String get builtinToolEnableBody => '禁用后该工具不会出现在模型的工具目录中。';

  @override
  String get builtinToolDisplayNameLabel => '显示名称（可选）';

  @override
  String get builtinToolDisplayNameHelper => '覆盖默认工具名称，留空则使用内建默认名。';

  @override
  String get builtinToolSummaryLabel => '简介（可选）';

  @override
  String get builtinToolSummaryHelper => '用于在工具列表中快速了解工具用途。';

  @override
  String get builtinToolPromptOverrideLabel => 'Prompt 追加覆盖（可选）';

  @override
  String get builtinToolPromptOverrideHelper =>
      '追加到工具 description 末尾，可用来微调模型对该工具的使用策略。';

  @override
  String get builtinToolSchemaOverrideLabel => 'Schema 覆盖（JSON，可选）';

  @override
  String get builtinToolSchemaOverrideHelper =>
      '完整的 JSON Schema 对象，覆盖工具的输入参数定义。留空使用默认。';

  @override
  String get builtinToolPriorityLabel => '优先级 (0–9999)';

  @override
  String get builtinToolPriorityHelper => '越小越优先';

  @override
  String get builtinToolLoadStrategyLabel => '加载策略';

  @override
  String get builtinToolForceLoadTitle => '强制加载';

  @override
  String get builtinToolForceLoadBody =>
      '开启后，即使全局内建工具懒加载处于自动或开启，也会默认直接携带该工具 schema。';

  @override
  String get builtinToolMaxOutputLabel => '输出上限（字符）';

  @override
  String get builtinToolGlobalDefaultHint => '使用全局默认';

  @override
  String get builtinToolTagsLabel => '标签（逗号分隔）';

  @override
  String get builtinToolTagsHelper => '例如: io, file, dangerous';

  @override
  String get builtinToolRequireConfirmationTitle => '执行确认';

  @override
  String get builtinToolRequireConfirmationBody =>
      '是否在执行前弹窗让用户确认。选“默认”时使用工具自身的行为。';

  @override
  String get builtinToolConfirmationDefault => '默认';

  @override
  String get builtinToolConfirmationYes => '需要确认';

  @override
  String get builtinToolConfirmationNo => '无需确认';

  @override
  String get memoryTitleField => '标题（可选）';

  @override
  String get memoryTitleHint => '一句话浓缩本条记忆的主旨；留空则使用正文预览';

  @override
  String get commonRetry => '重试';

  @override
  String get commonOk => '好的';

  @override
  String get commonExport => '导出';

  @override
  String get appUpdateDialogTitle => '检查更新';

  @override
  String get appUpdateChecking => '正在检查更新...';

  @override
  String appUpdateCurrentVersion(Object version) {
    return '当前版本: $version';
  }

  @override
  String appUpdateNewVersion(Object version) {
    return '发现新版本: v$version';
  }

  @override
  String appUpdatePublished(Object date) {
    return '发布时间: $date';
  }

  @override
  String appUpdateFileSize(Object size) {
    return '文件大小: $size';
  }

  @override
  String get appUpdateAlreadyLatestTitle => '已是最新版本';

  @override
  String appUpdateAlreadyLatestBody(Object version) {
    return 'OpenHand $version 已是最新版本。';
  }

  @override
  String get appUpdateDownloadComplete => '下载完成';

  @override
  String get appUpdateDownloading => '正在下载...';

  @override
  String get appUpdateCheckFailed => '检查更新失败';

  @override
  String get appUpdateLater => '稍后';

  @override
  String get appUpdateDownload => '下载更新';

  @override
  String get exportRangeInvalid => '请输入有效区间 (1 ≤ 起始 ≤ 结束)';

  @override
  String get exportRangeStart => '起始';

  @override
  String get exportRangeEnd => '结束';

  @override
  String get exportSessionSettingsTitle => '导出会话配置';

  @override
  String exportTotalMessages(Object count) {
    return '共 $count 条消息可导出';
  }

  @override
  String get exportRolesSection => '导出 Role';

  @override
  String get exportAllRoles => '全部 role';

  @override
  String get exportMessageKindsSection => '消息类型 (kind)';

  @override
  String get exportAllKinds => '全部类型';

  @override
  String get exportMessageRangeSection => '消息区间';

  @override
  String get exportOnlyRange => '仅导出指定区间 (1-based, 包含两端)';

  @override
  String get exportOtherOptions => '其他选项';

  @override
  String get exportIncludeDeleted => '包含已删除消息';

  @override
  String get exportPickOneRole => '请至少选择一个 role。';

  @override
  String get exportPickOneMessageKind => '请至少选择一个消息类型。';

  @override
  String get exportRoleSystem => '系统 (system)';

  @override
  String get exportRoleUser => '用户 (user)';

  @override
  String get exportRoleAssistant => '助手 (assistant)';

  @override
  String get exportRoleTool => '工具 (tool)';

  @override
  String get exportKindUser => '用户消息';

  @override
  String get exportKindAssistant => '助手回复';

  @override
  String get exportKindReasoning => '思考过程';

  @override
  String get exportKindToolCall => '工具调用';

  @override
  String get exportKindTool => '工具结果';

  @override
  String get exportKindCompressionPoint => '压缩节点';

  @override
  String get exportKindMcp => 'MCP 事件';

  @override
  String get exportKindSkill => '技能事件';

  @override
  String get exportKindHook => 'Hook 事件';

  @override
  String get exportKindSelfLearning => '自学习';

  @override
  String get exportKindFileMutationSummary => '文件变动总结';

  @override
  String get exportKindStatus => '状态消息';

  @override
  String get exportPhaseLogRangeSection => '阶段日志区间';

  @override
  String exportTotalPhaseLogs(Object count) {
    return '共 $count 条阶段日志可导出';
  }

  @override
  String get modelSearchHint => '搜索模型…';

  @override
  String modelSearchResultCount(Object filtered, Object total) {
    return '$filtered / $total 个模型';
  }

  @override
  String get modelSearchNoAvailableModels => '暂无可用模型';

  @override
  String get modelSearchNoMatchingModels => '无匹配模型';

  @override
  String get modelSearchRecent => '最近使用';

  @override
  String get nativeAudioLoadFailed => '音频载入失败，可使用系统播放器打开。';

  @override
  String get nativeAudioPlaybackFailed => '播放失败，请重试或使用系统播放器。';

  @override
  String get nativeAudioBack15Seconds => '后退 15 秒';

  @override
  String get nativeAudioPause => '暂停';

  @override
  String get nativeAudioPlay => '播放';

  @override
  String get nativeAudioForward15Seconds => '快进 15 秒';

  @override
  String get nativeAudioMute => '静音';

  @override
  String get nativeAudioUnmute => '取消静音';

  @override
  String get nativeAudioSystemPlayer => '系统播放器';

  @override
  String get nativeAudioSequencePlayback => '顺序播放';

  @override
  String get nativeAudioRepeatOne => '单曲循环';

  @override
  String get nativeAudioShufflePlayback => '随机播放';

  @override
  String nativeAudioEffectTooltip(Object effect) {
    return '音效：$effect';
  }

  @override
  String get nativeAudioEffectStandard => '标准';

  @override
  String get nativeAudioEffectSpatial => '3D';

  @override
  String get nativeAudioEffectVocal => '人声';

  @override
  String get nativeAudioEffectWarm => '暖声';

  @override
  String get hooksTitle => 'Hooks';

  @override
  String get hooksSubtitle =>
      '为 AI Agent 的生命周期阶段配置要执行的脚本。每个 Hook 在对应事件触发时按顺序执行。';

  @override
  String get hooksNew => '新增 Hook';

  @override
  String get hooksDeleteTitle => '删除 Hook';

  @override
  String hooksDeleteMessage(Object label) {
    return '确定删除 \"$label\" 吗？此操作不可撤销。';
  }

  @override
  String get hooksEmptyTitle => '暂无 Hook 配置';

  @override
  String get hooksEmptyBody => '点击右上角「新增 Hook」按钮开始配置。';

  @override
  String get hooksTimeoutTooltip => '超时时间';

  @override
  String hooksInlineScriptDescription(Object firstLine) {
    return '内联脚本: $firstLine';
  }

  @override
  String get hooksNoScriptConfigured => '未配置脚本';

  @override
  String get hooksEditTitle => '编辑 Hook';

  @override
  String get hooksLabelField => '名称';

  @override
  String get hooksLabelHint => '例如: 日志记录';

  @override
  String get hooksTriggerEvent => '触发事件';

  @override
  String get hooksScriptSource => '脚本来源';

  @override
  String get hooksScriptSourceFile => '选择文件';

  @override
  String get hooksScriptSourceInline => '编写脚本';

  @override
  String get hooksScriptFilePath => '脚本文件路径';

  @override
  String get hooksScriptFileHint => '选择 .sh / .ps1 / .bat 文件';

  @override
  String get hooksBrowse => '浏览';

  @override
  String get hooksScriptContextFileHelp =>
      '上下文 JSON 通过两种方式传入（均可安全用于 jq）：\n① 临时文件: jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\"\n② stdin 原始字节: jq -r .session_id\n包含 session_id、session_file_path、environment 等字段。';

  @override
  String get hooksInlineWindowsHint => '输入 PowerShell / BAT 脚本';

  @override
  String get hooksInlineShellHint => '输入 Shell 脚本（无需 #!/bin/bash）';

  @override
  String get hooksScriptContextInlineHelp =>
      '上下文 JSON 通过两种方式传入（均可安全用于 jq）：\n① 临时文件: SID=\$(jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\")\n② stdin 原始字节: SID=\$(jq -r .session_id)\n包含 session_id、session_file_path、environment、statistics 等字段。';

  @override
  String get hooksTimeoutSeconds => '超时时间（秒）';

  @override
  String get hooksEnabled => '启用';

  @override
  String get hooksValidationLabelRequired => '请填写 Hook 名称。';

  @override
  String get hooksValidationScriptFileRequired => '请选择脚本文件。';

  @override
  String get hooksValidationInlineScriptRequired => '请填写内联脚本内容。';

  @override
  String get hooksFileTypeScripts => '脚本';

  @override
  String get hooksFileTypeShellScripts => 'Shell 脚本';

  @override
  String get hooksFileTypeAllFiles => '所有文件';

  @override
  String get commonConfirm => '确定';

  @override
  String get choiceInputCustomOptionLabel => '自定义输入';

  @override
  String get choiceInputCustomInputHint => '在此输入你的回答…';

  @override
  String get choiceInputCustomOptionDescription => '选择此项以手动填写内容';

  @override
  String get mediaPreviewImageCopied => '已复制图片到剪贴板。';

  @override
  String get mediaPreviewImageFileOrPathCopied => '已复制图片文件或路径到剪贴板。';

  @override
  String get mediaPreviewMediaFileCopied => '已复制媒体文件到剪贴板。';

  @override
  String get mediaPreviewDirectCopyUnavailablePathCopied =>
      '当前平台不支持直接复制媒体文件，已复制文件路径。';

  @override
  String get mediaPreviewMediaUrlCopied => '已复制媒体地址。';

  @override
  String get mediaPreviewDirectCopyUnavailableTempPathCopied =>
      '当前平台不支持直接复制媒体文件，已复制临时文件路径。';

  @override
  String get mediaPreviewDataCopyFailedUrlCopied => '无法复制媒体数据，已复制来源地址。';

  @override
  String mediaPreviewCopyFailed(Object error) {
    return '复制失败：$error';
  }

  @override
  String get mediaPreviewNoSource => '媒体来源不可用。';

  @override
  String get knowledgeVectorDistributionTitle => '向量分布';

  @override
  String get knowledgeVectorDistributionLoading => '正在采样并投影向量。';

  @override
  String get knowledgeVectorDistributionEmpty => '当前 collection 没有可展示的向量。';

  @override
  String get knowledgeVectorProjectionSection => '投影说明';

  @override
  String get knowledgeVectorAlgorithm => '算法';

  @override
  String get knowledgeVectorOriginalDimensions => '原始维度';

  @override
  String get knowledgeVectorVisiblePoints => '展示点数';

  @override
  String get knowledgeVectorSampled => '是否采样';

  @override
  String get knowledgeVectorDurationMs => '耗时毫秒';

  @override
  String get knowledgeVectorResample => '重新采样';

  @override
  String get qdrantStatusRefreshIncomplete => 'Qdrant 状态刷新返回的数据不完整。';

  @override
  String get qdrantStatusRawVectorEmpty => '请先输入 raw vector。';

  @override
  String qdrantStatusRawVectorInvalid(Object value) {
    return '原始向量包含无效数值：$value';
  }

  @override
  String qdrantStatusRawVectorDimensionMismatch(int actual, int expected) {
    return '原始向量维度为 $actual，当前配置要求 $expected。';
  }

  @override
  String get qdrantStatusPointIdsEmpty => '请先输入 point/chunk id。';

  @override
  String get qdrantStatusPayloadIndexesSubmitted => '常用 Payload 索引已提交创建/重建。';

  @override
  String get qdrantStatusDangerousOpsDisabled => '请先在知识库配置中启用危险管理操作。';

  @override
  String get qdrantStatusDeletePointIdsEmpty => '请先输入要删除的向量点 ID。';

  @override
  String get qdrantStatusDeletePointsTitle => '删除 Qdrant 向量点？';

  @override
  String qdrantStatusDeletePointsMessage(int count) {
    return '将从当前集合删除 $count 个向量点。此操作不可撤销。';
  }

  @override
  String get qdrantStatusDeletePointsConfirm => '删除向量点';

  @override
  String get qdrantStatusPointsDeleted => '向量点已删除。';

  @override
  String get qdrantStatusDeleteCollectionTitle => '删除 Qdrant 集合？';

  @override
  String qdrantStatusDeleteCollectionMessage(Object collection) {
    return '将删除集合“$collection”及其中所有向量点。此操作不可撤销。';
  }

  @override
  String get qdrantStatusDeleteCollectionConfirm => '删除集合';

  @override
  String get qdrantStatusCollectionDeleted => '集合已删除。';

  @override
  String get qdrantStatusDiagnosticsCopied => '诊断信息已复制。';

  @override
  String get qdrantStatusTitle => 'Qdrant 运维';

  @override
  String get qdrantStatusTabOverview => '总览监控';

  @override
  String get qdrantStatusTabCollections => '集合管理';

  @override
  String get qdrantStatusTabPoints => '向量点查询';

  @override
  String get qdrantStatusTabDiagnostics => '诊断日志';

  @override
  String get qdrantStatusRefresh => '刷新';

  @override
  String get qdrantStatusCopyDiagnostics => '复制诊断';

  @override
  String get qdrantStatusHeaderTitle => '本地向量数据库实时状态';

  @override
  String get qdrantStatusMetricCollections => '集合';

  @override
  String get qdrantStatusMetricPoints => '向量点';

  @override
  String get qdrantStatusMetricIndexedVectors => '已索引向量';

  @override
  String get qdrantStatusMetricChunks => '分块';

  @override
  String get qdrantStatusMetricPendingJobs => '待处理任务';

  @override
  String get qdrantStatusMetricWalCapacity => 'WAL 容量';

  @override
  String get qdrantStatusSmoothTrend => '平滑趋势';

  @override
  String get qdrantStatusNoCollections => '没有集合，或当前 Qdrant 服务不可用。';

  @override
  String get qdrantStatusPointsSectionTitle => '向量点查询 / 搜索 / 滚动读取';

  @override
  String get qdrantStatusPointIdsLabel => '向量点/分块 ID（空格或逗号分隔）';

  @override
  String get qdrantStatusSourceFilterLabel => '来源 ID 过滤';

  @override
  String get qdrantStatusTagFilterLabel => '标签过滤';

  @override
  String get qdrantStatusLimitLabel => '数量上限';

  @override
  String get qdrantStatusRawVectorLabel => '原始向量（逗号或空格分隔，维度必须匹配当前配置）';

  @override
  String get qdrantStatusQueryIds => '按 ID 查询';

  @override
  String get qdrantStatusScrollFilter => '滚动读取 / 过滤';

  @override
  String get qdrantStatusRawVectorSearch => '原始向量搜索';

  @override
  String get qdrantStatusRebuildPayloadIndexes => '重建 Payload 索引';

  @override
  String get qdrantStatusDeletePoints => '删除 Points';

  @override
  String get qdrantStatusOperationResult => '操作结果';

  @override
  String get qdrantStatusRawDiagnosticsJson => '原始诊断 JSON';

  @override
  String get qdrantStatusNoDiagnostics => '暂无诊断数据。';

  @override
  String get qdrantStatusLatestOperationResult => '最近操作结果';

  @override
  String get qdrantStatusOperationLog => '操作日志';

  @override
  String get qdrantStatusNoOperations => '暂无操作。';

  @override
  String get qdrantStatusCollectingSamples => '等待更多采样后展示趋势。';

  @override
  String get qdrantStatusTrendPoints => '向量点';

  @override
  String get qdrantStatusTrendChunks => '分块';

  @override
  String get qdrantStatusTrendPendingFailed => '待处理/失败';

  @override
  String qdrantStatusTrendSampleCount(int count) {
    return '$count 点';
  }

  @override
  String get qdrantSectionOverview => '总览';

  @override
  String get qdrantSectionDockerContainer => 'Docker / 容器指标';

  @override
  String get qdrantSectionApiMetrics => 'Qdrant API 指标';

  @override
  String get qdrantSectionCollectionConfig => '集合配置';

  @override
  String get qdrantSectionStorageOptimizer => '存储 / 优化器';

  @override
  String get qdrantSectionTelemetry => '遥测数据';

  @override
  String get qdrantSectionOpenHandKnowledge => 'OpenHand 知识库指标';

  @override
  String get qdrantMetricServiceStatus => '服务状态';

  @override
  String get qdrantMetricRestEndpoint => 'REST endpoint';

  @override
  String get qdrantMetricGrpcEndpoint => 'gRPC endpoint';

  @override
  String get qdrantMetricQdrantVersion => 'Qdrant 版本';

  @override
  String get qdrantMetricCurrentCollection => '当前集合';

  @override
  String get qdrantMetricCollectionStatus => '集合状态';

  @override
  String get qdrantMetricOptimizerStatus => '优化器状态';

  @override
  String get qdrantMetricLastHealthCheck => '最近健康检查时间';

  @override
  String get qdrantMetricDockerDaemon => 'Docker 守护进程';

  @override
  String get qdrantMetricContainerCpu => '容器 CPU';

  @override
  String get qdrantMetricContainerMemory => '容器内存';

  @override
  String get qdrantMetricNetworkIo => '网络收发';

  @override
  String get qdrantMetricBlockIo => '块设备 I/O';

  @override
  String get qdrantMetricRestartCount => '重启次数';

  @override
  String get qdrantMetricLatestLogSummary => '最近日志摘要';

  @override
  String get qdrantMetricCollectionsTotal => '集合总数';

  @override
  String get qdrantMetricPointsTotal => '向量点总数';

  @override
  String get qdrantMetricVectorsTotal => '向量总数';

  @override
  String get qdrantMetricIndexedVectorsTotal => '已索引向量总数';

  @override
  String get qdrantMetricSegmentsTotal => '分段数';

  @override
  String get qdrantMetricPayloadSchemaFields => 'Payload schema 字段数';

  @override
  String get qdrantMetricPayloadSchemaNames => 'Payload schema 字段';

  @override
  String get qdrantMetricVectorSize => '向量维度';

  @override
  String get qdrantMetricDistance => '距离度量';

  @override
  String get qdrantMetricSingleNodeMode => '单机模式';

  @override
  String get qdrantMetricPayloadIndexStatus => 'Payload 索引状态';

  @override
  String get qdrantMetricClusterStatus => '集群状态';

  @override
  String get qdrantMetricHnswM => 'HNSW M';

  @override
  String get qdrantMetricHnswEfConstruct => 'HNSW ef_construct';

  @override
  String get qdrantMetricHnswFullScanThreshold => 'HNSW 全扫描阈值';

  @override
  String get qdrantMetricHnswMaxIndexingThreads => 'HNSW 最大索引线程';

  @override
  String get qdrantMetricOnDiskPayload => 'Payload 磁盘存储';

  @override
  String get qdrantMetricShardNumber => '分片数';

  @override
  String get qdrantMetricReplicationFactor => '副本因子';

  @override
  String get qdrantMetricWriteConsistencyFactor => '写一致性因子';

  @override
  String get qdrantMetricReadFanOutFactor => '读取扇出因子';

  @override
  String get qdrantMetricOptimizerDeletedThreshold => '优化器删除阈值';

  @override
  String get qdrantMetricOptimizerVacuumMinVectorNumber => 'Vacuum 最小向量数';

  @override
  String get qdrantMetricOptimizerDefaultSegmentNumber => '默认分段数';

  @override
  String get qdrantMetricOptimizerMaxSegmentSize => '最大分段大小';

  @override
  String get qdrantMetricOptimizerIndexingThreshold => '索引阈值';

  @override
  String get qdrantMetricOptimizerFlushIntervalSeconds => '刷盘间隔秒数';

  @override
  String get qdrantMetricWalCapacityMb => 'WAL 容量 MB';

  @override
  String get qdrantMetricWalSegmentsAhead => 'WAL 预留段';

  @override
  String get qdrantMetricQuantization => '量化配置';

  @override
  String get qdrantMetricStrictMode => '严格模式';

  @override
  String get qdrantMetricTelemetryStatus => '遥测状态';

  @override
  String get qdrantMetricAppVersion => '应用版本';

  @override
  String get qdrantMetricAppName => '应用名称';

  @override
  String get qdrantMetricTelemetryCollections => '集合遥测';

  @override
  String get qdrantMetricTelemetryRequests => '请求遥测';

  @override
  String get qdrantMetricSourceCount => '来源数';

  @override
  String get qdrantMetricChunkCount => '分块数';

  @override
  String get qdrantMetricPendingEmbeddingJobs => '待处理嵌入任务';

  @override
  String get qdrantMetricFailedEmbeddingJobs => '失败嵌入任务';

  @override
  String get qdrantMetricEmbeddingModel => '当前嵌入模型';

  @override
  String get qdrantMetricEmbeddingDimensions => '当前向量维度';

  @override
  String get qdrantMetricRetrievalTopN => '召回 TopN';

  @override
  String get qdrantMetricRetrievalTopK => '最终 TopK';

  @override
  String get qdrantMetricMinSimilarity => '最低相似度';

  @override
  String get qdrantMetricPromptChunkBudget => 'Prompt 分块预算';

  @override
  String get qdrantMetricPromptTokenBudget => 'Prompt token 预算';

  @override
  String get qdrantValueYes => '是';

  @override
  String get qdrantValueNo => '否';

  @override
  String get qdrantValueHealthy => '健康';

  @override
  String get qdrantValueUnknown => '未知';

  @override
  String get qdrantValueLoading => '加载中';

  @override
  String get qdrantValueAvailable => '可用';

  @override
  String get qdrantValueUnavailable => '不可用';

  @override
  String get qdrantValuePluginServiceScan => '由插件服务扫描';

  @override
  String get qdrantValuePluginRuntimeMetric => '由插件运行时提供';

  @override
  String get qdrantValuePluginDetailsLogs => '可在插件详情查看';

  @override
  String get qdrantValueLocalSingleNodeOrUnavailable => '本地单机 / 不可用';

  @override
  String get qdrantValueClusterInfoAvailable => '已返回集群信息';

  @override
  String get qdrantValuePayloadSchemaConfigured => '已配置 payload schema';

  @override
  String get qdrantValuePayloadSchemaMissing => '未发现 payload schema';
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
  String get threadsLoadMore => '載入更多執行緒';

  @override
  String get composerHint => '詢問 OpenHand 任何內容，使用 / 觸發動作，使用 @ 引用上下文';

  @override
  String get composerSend => '送出';

  @override
  String get chatSending => '傳送中';

  @override
  String get chatRequestFailed => '模型請求失敗，請檢查模型配置、網路連通性或介面協議。';

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
  String get exportProgressCancelling => '正在取消…';

  @override
  String get readerFileTypeText => '純文字';

  @override
  String get readerFileTypeCode => '程式碼';

  @override
  String knowledgeReaderNoModelForType(Object type) {
    return '沒有可讀取 $type 的 reader 模型。';
  }

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
  String get mcpStdioCacheResetAction => '重置 stdio 包緩存';

  @override
  String get mcpStdioCacheResetConfirmTitle => '重置 stdio 雔離包緩存？';

  @override
  String get mcpStdioCacheResetConfirmBody =>
      '將刪除 ~/.openhand/mcp/package-cache 下的 npm/uv/pip 等雔離緩存。下次啟動 stdio MCP 服務會重新下載依賴。不影響全局 ~/.npm 。';

  @override
  String get mcpStdioCacheResetConfirm => '重置';

  @override
  String get mcpStdioCacheResetCancel => '取消';

  @override
  String get mcpStdioCacheResetDone => '雔離緩存已重置。';

  @override
  String get mcpStdioCacheResetFailed =>
      '重置失敗，請手動刪除 ~/.openhand/mcp/package-cache。';

  @override
  String get pluginServiceTitle => '插件';

  @override
  String get pluginServiceSubtitle =>
      '管理可選插件的安裝、更新與卸載。插件為 OpenHand 提供額外的執行階段能力。';

  @override
  String get pluginServiceRescan => '重新掃描';

  @override
  String get pluginServiceScanning => '正在掃描本機插件環境…';

  @override
  String get pluginServiceScanFailed => '插件掃描失敗';

  @override
  String get pluginServiceActionInstall => '安裝';

  @override
  String get pluginServiceActionUpdate => '更新';

  @override
  String get pluginServiceActionUninstall => '卸載';

  @override
  String get pluginServiceActionEnable => '啟用';

  @override
  String get pluginServiceActionDisable => '停用';

  @override
  String get pluginServiceStatusInstalled => '已安裝';

  @override
  String get pluginServiceStatusNotInstalled => '未安裝';

  @override
  String get pluginServiceStatusInstalling => '安裝中…';

  @override
  String get pluginServiceStatusUpdating => '更新中…';

  @override
  String get pluginServiceStatusUninstalling => '卸載中…';

  @override
  String get pluginServiceStatusError => '錯誤';

  @override
  String get pluginServiceCheckUpdates => '檢查更新';

  @override
  String get pluginServiceMcpService => 'MCP 服務';

  @override
  String pluginServiceInstallDependencyRequired(Object dependency) {
    return '需要先安裝 $dependency';
  }

  @override
  String pluginServiceInstallConfirmTitle(Object plugin) {
    return '安裝 $plugin？';
  }

  @override
  String pluginServiceInstallConfirmMessage(Object plugin) {
    return '將在本機安裝 $plugin，可能需要下載依賴檔案。';
  }

  @override
  String pluginServiceInstallSuccess(Object plugin) {
    return '$plugin 安裝成功';
  }

  @override
  String pluginServiceInstallFailure(Object plugin) {
    return '$plugin 安裝失敗';
  }

  @override
  String pluginServiceUpdateConfirmTitle(Object plugin) {
    return '更新 $plugin？';
  }

  @override
  String pluginServiceUpdateConfirmMessage(
    Object plugin,
    Object currentVersion,
    Object latestVersion,
  ) {
    return '將 $plugin 從 $currentVersion 更新到 $latestVersion。';
  }

  @override
  String pluginServiceUpdateSuccess(Object plugin) {
    return '$plugin 更新成功';
  }

  @override
  String pluginServiceUpdateFailure(Object plugin) {
    return '$plugin 更新失敗';
  }

  @override
  String get pluginServiceCheckUpdateFailed => '檢查更新失敗';

  @override
  String pluginServiceNewVersionAvailable(Object version) {
    return '發現新版本：$version';
  }

  @override
  String get pluginServiceNoUpdatesAvailable => '未發現新版本';

  @override
  String pluginServiceUninstallBlocked(Object dependent, Object plugin) {
    return '$dependent 依賴 $plugin，請先卸載 $dependent';
  }

  @override
  String pluginServiceUninstallConfirmTitle(Object plugin) {
    return '卸載 $plugin？';
  }

  @override
  String pluginServiceUninstallConfirmMessage(Object plugin) {
    return '將從本機卸載 $plugin，此操作無法復原。';
  }

  @override
  String pluginServiceUninstallSuccess(Object plugin) {
    return '$plugin 已卸載';
  }

  @override
  String pluginServiceUninstallFailure(Object plugin) {
    return '$plugin 卸載失敗';
  }

  @override
  String pluginServiceOperationTitle(Object action, Object plugin) {
    return '$action $plugin';
  }

  @override
  String get pluginServiceRuntimePid => 'PID';

  @override
  String get pluginServiceRuntimeOs => 'OS';

  @override
  String get pluginServiceRuntimeArch => '架構';

  @override
  String pluginServiceLogLineCount(Object count) {
    return '日誌：$count 行';
  }

  @override
  String get pluginServiceWaitingForOutput => '等待輸出…';

  @override
  String get pluginServiceExecuting => '正在執行…';

  @override
  String get pluginServiceCompleted => '操作完成';

  @override
  String get pluginServiceVersion => '版本';

  @override
  String get pluginServiceUpdateAvailable => '可更新到';

  @override
  String get pluginServiceDependsOn => '依賴';

  @override
  String get pluginServiceRequiredBy => '被依賴';

  @override
  String get pluginServiceNone => '無';

  @override
  String pluginServiceDetailTitle(Object plugin) {
    return '$plugin 詳情';
  }

  @override
  String get pluginServiceDetailBasicInfo => '基本資訊';

  @override
  String get pluginServiceDetailName => '名稱';

  @override
  String get pluginServiceDetailDescription => '描述';

  @override
  String get pluginServiceDetailStatus => '狀態';

  @override
  String get pluginServiceDetailEnvironment => '環境資訊';

  @override
  String get pluginServiceDetailFileSystem => '檔案系統';

  @override
  String get pluginServiceDetailDependencies => '依賴關係';

  @override
  String get pluginServiceThreadTemplates => '執行緒模板關聯';

  @override
  String get pluginServiceTemplates => '關聯模板';

  @override
  String get pluginServiceMcpPackage => 'MCP 套件';

  @override
  String get pluginServiceMcpBrowserDescription => '提供瀏覽器自動化能力的 MCP 服務';

  @override
  String get pluginServiceDetailProcessors => '處理器數';

  @override
  String get pluginServiceDetailInstallPath => '安裝路徑';

  @override
  String get pluginServiceDetailInstallationTarget => '安裝目標';

  @override
  String get pluginServiceDetailInstallMethod => '安裝方式';

  @override
  String get pluginServiceDetailTargetOs => '目標作業系統';

  @override
  String get pluginServiceDetailSupportedPlatforms => '支援平台';

  @override
  String get pluginServiceDetailPackageName => '套件名稱';

  @override
  String get pluginServiceDetailBinaryName => '命令名稱';

  @override
  String get pluginServiceDetailRepository => '程式碼倉庫';

  @override
  String get pluginServiceDetailDocumentation => '官方文件';

  @override
  String get pluginServiceDetailInstallCommand => '安裝命令';

  @override
  String get pluginServiceDetailUpgradeCommand => '升級命令';

  @override
  String get pluginServiceDetailUninstallCommand => '解除安裝命令';

  @override
  String get pluginServiceDetailExecutablePath => '可執行入口';

  @override
  String get pluginServiceDetailCacheDirectory => '快取目錄';

  @override
  String get pluginServiceDetailNpmGlobalRoot => 'npm 全域目錄';

  @override
  String get pluginServiceDetailCurrentVersion => '目前版本';

  @override
  String get pluginServiceDetailLatestVersion => '最新版本';

  @override
  String get pluginServiceDetailBoundPython => '綁定直譯器';

  @override
  String get pluginServiceDetailDesktopAppDetected => '偵測到桌面應用程式';

  @override
  String get pluginServiceDetailDaemonRunning => 'Daemon 執行中';

  @override
  String get pluginServiceDetailCliAvailable => 'CLI 可用';

  @override
  String get pluginServiceDetailDockerContext => 'Docker 上下文';

  @override
  String get pluginServiceDetailServerVersion => '服務端版本';

  @override
  String get pluginServiceDetailDockerOs => 'Docker OS';

  @override
  String get pluginServiceDetailDockerRootDir => 'Docker 根目錄';

  @override
  String get pluginServiceDetailDaemonName => 'Daemon 名稱';

  @override
  String get pluginServiceDetailOsType => 'OS 類型';

  @override
  String get pluginServiceDetailArchitecture => '架構';

  @override
  String get pluginServiceDetailComposeVersion => 'Compose 版本';

  @override
  String get pluginServiceDetailDockerDaemonRunning => 'Docker daemon 執行中';

  @override
  String get pluginServiceDetailOpenHandManaged => 'OpenHand 管理';

  @override
  String get pluginServiceDetailContainerId => '容器 ID';

  @override
  String get pluginServiceDetailContainerName => '容器名稱';

  @override
  String get pluginServiceDetailContainerStatus => '容器狀態';

  @override
  String get pluginServiceDetailRunning => '執行中';

  @override
  String get pluginServiceDetailStartedAt => '啟動時間';

  @override
  String get pluginServiceDetailFinishedAt => '結束時間';

  @override
  String get pluginServiceDetailRestartCount => '重啟次數';

  @override
  String get pluginServiceDetailExitCode => '結束碼';

  @override
  String get pluginServiceDetailImage => '映像';

  @override
  String get pluginServiceDetailImageId => '映像 ID';

  @override
  String get pluginServiceDetailPorts => '連接埠';

  @override
  String get pluginServiceDetailRestartPolicy => '重啟策略';

  @override
  String get pluginServiceDetailRestEndpoint => 'REST 端點';

  @override
  String get pluginServiceDetailGrpcEndpoint => 'gRPC 端點';

  @override
  String get pluginServiceDetailDataDirectory => '資料目錄';

  @override
  String get pluginServiceDetailHealthResponse => '健康回應';

  @override
  String get pluginServiceDetailHealthTitle => '健康標題';

  @override
  String get pluginServiceDetailCollectionCount => '集合數量';

  @override
  String get pluginServiceDetailRuntimeCapabilities => '執行能力';

  @override
  String get pluginServiceDetailApplicationPath => '應用程式目錄';

  @override
  String get pluginServiceDetailReleaseChannel => '發布通道';

  @override
  String get pluginServiceDetailVersionSource => '版本來源';

  @override
  String get pluginServiceDetailVersionApi => '版本 API';

  @override
  String get pluginServiceDetailBrowserKind => '瀏覽器類型';

  @override
  String get pluginServiceDetailCdpTransport => 'CDP 傳輸';

  @override
  String get pluginServiceDetailCdpEndpoint => 'CDP 端點';

  @override
  String get pluginServiceDetailProfileStrategy => '設定檔策略';

  @override
  String get pluginServiceDetailCaptureScope => '擷取範圍';

  @override
  String get pluginServiceDetailCredentialPolicy => '憑證保護';

  @override
  String get pluginServiceDetailSessionCleanup => '工作階段清理';

  @override
  String get pluginServiceDetailUpdatePolicy => '更新策略';

  @override
  String get pluginServiceDetailUninstallPolicy => '解除安裝策略';

  @override
  String get pluginServiceDetailOfficialSite => '官方網站';

  @override
  String pluginServiceMcpInstalledVersion(Object version) {
    return '已安裝 v$version';
  }

  @override
  String get pluginServiceMcpOperationTimeout => '[timeout] 操作逾時，已終止行程';

  @override
  String pluginServiceMcpOperationCompleted(Object action, Object exitCode) {
    return '✓ $action 完成 (exit code: $exitCode)';
  }

  @override
  String pluginServiceMcpOperationFailed(Object action, Object exitCode) {
    return '✗ $action 失敗 (exit code: $exitCode)';
  }

  @override
  String pluginServiceMcpOperationError(Object error) {
    return '✗ 異常：$error';
  }

  @override
  String get pluginServiceMcpVerificationFailed => 'MCP 操作後的狀態驗證失敗';

  @override
  String get pluginServiceDescriptionNodejs =>
      'JavaScript 執行階段環境，用於執行 JS/TS 腳本與工具鏈';

  @override
  String get pluginServiceDescriptionPlaywright =>
      '瀏覽器自動化測試框架，支援 Chromium / Firefox / WebKit';

  @override
  String get pluginServiceDescriptionHermesAgent =>
      'Hermes Agent 執行階段，用於智能體編排、自我學習與技能沉澱';

  @override
  String get pluginServiceDescriptionPython =>
      'Python 執行階段環境，用於執行 Python 腳本、程式庫與擴充能力';

  @override
  String get pluginServiceDescriptionPip =>
      'Python 套件管理工具，用於安裝、升級與管理 Python 程式庫';

  @override
  String get pluginServiceDescriptionJava =>
      'JDK 執行階段，用於 apktool / jadx 等 Android 靜態分析工具';

  @override
  String get pluginServiceDescriptionFrida =>
      '動態插樁與 Hook 工具鏈，用於 Android 執行階段驗證';

  @override
  String get pluginServiceDescriptionMitmproxy =>
      'HTTP(S) 代理抓包工具，用於 Web / Android 流量取證';

  @override
  String get pluginServiceDescriptionApktool => 'APK 解包與 smali 分析工具';

  @override
  String get pluginServiceDescriptionJadx => 'DEX / APK Java 反編譯工具';

  @override
  String get pluginServiceDescriptionRadare2 => '二進位靜態分析與 ELF / native so 逆向工具';

  @override
  String get pluginServiceDescriptionBlutter =>
      'Flutter Dart AOT 快速還原工具，用於 libapp.so 分析';

  @override
  String get pluginServiceDescriptionDoldrums =>
      'Flutter snapshot / ELF 輔助分析工具';

  @override
  String get pluginServiceDescriptionAnythingAnalyzer =>
      '協議分析與 MCP Server 工具，用於抓包、分析和 Agent 聯動';

  @override
  String get pluginServiceDescriptionDocker => '容器執行環境，用於執行 Qdrant 本地向量資料庫服務';

  @override
  String get pluginServiceDescriptionQdrant =>
      '本地向量資料庫，用於知識庫 embedding 向量索引與檢索';

  @override
  String get pluginServiceDescriptionDingtalkWorkspaceCli =>
      'DingTalk Workspace CLI，為 AI Agent 提供釘釘工作流能力';

  @override
  String get pluginServiceDescriptionGoogleChrome =>
      '本機 Chrome 執行階段，為論壇狩獵提供原生 CDP 頁面與網路採集';

  @override
  String get pluginServiceTemplateWebReverseExpert => 'Web 逆向專家';

  @override
  String get pluginServiceTemplateAndroidReverseExpert => 'Android 逆向專家';

  @override
  String get pluginServiceTemplateHermesTalker => 'Hermes Talker';

  @override
  String get mcpStdioMirrorModeLabel => '鏡像源模式';

  @override
  String get mcpStdioMirrorModeBody =>
      'stdio MCP 服務首次啟動時，是否注入國內鏡像源（npmmirror / 清華 PyPI）。auto = 依系統語言自判；強制開啟 / 關閉 = 無視 locale。環變 OPENHAND_MCP_MIRROR=on/off 可在運行時再覆蓋一次。';

  @override
  String get mcpStdioMirrorModeAuto => '跟隨語言';

  @override
  String get mcpStdioMirrorModeForceOn => '強制開啟';

  @override
  String get mcpStdioMirrorModeForceOff => '強制關閉';

  @override
  String get mcpStdioMirrorModeStatusInjected => '當前生效：將注入 npmmirror / 清華 PyPI';

  @override
  String get mcpStdioMirrorModeStatusBypassed => '當前生效：不注入鏡像源，走官方 registry';

  @override
  String mcpStdioMirrorModeStatusReason(Object reason) {
    return '依據：$reason';
  }

  @override
  String get mcpStdioMirrorModeReasonEnv => '環變 OPENHAND_MCP_MIRROR';

  @override
  String get mcpStdioMirrorModeReasonSetting => '設定項強制';

  @override
  String mcpStdioMirrorModeReasonLocale(Object locale) {
    return '跟隨語言 ($locale)';
  }

  @override
  String get mcpStdioMirrorModeReconnectAction => '按新設定重拉已啟用的 server';

  @override
  String get mcpStdioMirrorModeReconnectDone => '已觸發重拉，下次呼叫會用新鏡像源重新啟動進程。';

  @override
  String mcpStdioDialogLogsTitle(Object name) {
    return '$name 日誌';
  }

  @override
  String mcpStdioDialogRuntimeDetailsTitle(Object name) {
    return '$name 執行階段詳情';
  }

  @override
  String mcpStdioDialogRunningPid(Object pid) {
    return '執行中 · PID $pid';
  }

  @override
  String get mcpStdioDialogStopped => '已停止';

  @override
  String get mcpStdioDialogAutoScroll => '自動捲動';

  @override
  String get mcpStdioDialogCopyLogs => '複製日誌';

  @override
  String get mcpStdioDialogClearLogs => '清除日誌';

  @override
  String get mcpStdioDialogCopiedToClipboard => '已複製到剪貼簿';

  @override
  String get mcpStdioDialogNoLogOutput => '尚無日誌輸出';

  @override
  String mcpStdioDialogLineCount(int count) {
    return '$count 行';
  }

  @override
  String mcpStdioDialogUptime(Object uptime) {
    return '執行 $uptime';
  }

  @override
  String get mcpStdioDialogRefresh => '重新整理';

  @override
  String get settingsScraplingRuntimeActionInstall => '安裝';

  @override
  String get settingsScraplingRuntimeActionUninstall => '卸載';

  @override
  String settingsScraplingRuntimeCommand(Object action) {
    return '$action Scrapling 執行階段';
  }

  @override
  String get settingsScraplingRuntimeInstallTitle => '安裝 Scrapling 執行階段';

  @override
  String get settingsScraplingRuntimeUninstallTitle => '卸載 Scrapling 執行階段';

  @override
  String get settingsScraplingRuntimeInstalling => '安裝中…';

  @override
  String get settingsScraplingRuntimeUninstalling => '卸載中…';

  @override
  String get settingsScraplingRuntimeInstalled => '安裝完成';

  @override
  String get settingsScraplingRuntimeUninstalled => '卸載完成';

  @override
  String get settingsScraplingRuntimeFailed => '執行失敗';

  @override
  String get settingsScraplingRuntimeCertificateDiagnosis =>
      '診斷：目前環境的 Python / pip 無法驗證 PyPI 憑證鏈。請檢查系統 CA 憑證、代理攔截憑證，或為 Python 設定可用的憑證檔案。';

  @override
  String get settingsScraplingRuntimeCopiedAllLogs => '已複製全部日誌';

  @override
  String get settingsScraplingRuntimeCopyLogs => '複製日誌';

  @override
  String get mcpStdioDialogProcessStatus => '行程狀態';

  @override
  String get mcpStdioDialogServiceConfig => '服務設定';

  @override
  String get mcpStdioDialogType => '類型';

  @override
  String get mcpStdioDialogCommand => '命令';

  @override
  String get mcpStdioDialogArgs => '參數';

  @override
  String get mcpStdioDialogEnabled => '已啟用';

  @override
  String get mcpStdioDialogYes => '是';

  @override
  String get mcpStdioDialogNo => '否';

  @override
  String get mcpStdioDialogEnvironment => '環境資訊';

  @override
  String get mcpStdioDialogError => '錯誤資訊';

  @override
  String get mcpStdioDialogDepsTitle => '依賴管理';

  @override
  String get mcpStdioDialogNoDepsToManage => '此服務不是套件管理器類型（npx / uvx），無需管理依賴。';

  @override
  String mcpStdioDialogInstalledVersion(Object version) {
    return '已安裝 v$version';
  }

  @override
  String get mcpStdioDialogUnknownVersion => '?';

  @override
  String get mcpStdioDialogNotGloballyInstalled => '未全域安裝';

  @override
  String get mcpStdioDialogInstall => '安裝';

  @override
  String get mcpStdioDialogUpdate => '更新';

  @override
  String get mcpStdioDialogUninstall => '解除安裝';

  @override
  String mcpStdioDialogLatestVersion(Object version) {
    return '最新版本: $version';
  }

  @override
  String get mcpStdioDialogUpdateAvailableSuffix => '（可更新）';

  @override
  String get mcpStdioDialogOperationTimeout => '[timeout] 操作逾時，已終止行程';

  @override
  String mcpStdioDialogOperationCompleted(
    Object time,
    Object action,
    int exitCode,
  ) {
    return '[$time] ✓ $action 完成 (exit code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationFailed(
    Object time,
    Object action,
    int exitCode,
  ) {
    return '[$time] ✗ $action 失敗 (exit code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationFailedPlain(Object action, int exitCode) {
    return '$action 失敗 (exit code: $exitCode)';
  }

  @override
  String mcpStdioDialogOperationException(Object time, Object error) {
    return '[$time] ✗ 例外: $error';
  }

  @override
  String mcpStdioDialogWarmCache(Object time) {
    return '[$time] 預熱隔離快取…';
  }

  @override
  String mcpStdioDialogWarmCacheDone(Object time) {
    return '[$time] ✓ 快取預熱完成';
  }

  @override
  String mcpStdioDialogWarmCacheSkipped(Object time, Object error) {
    return '[$time] 快取預熱略過: $error';
  }

  @override
  String get mcpAutoProbeConcurrencyLabel => 'MCP 檢查/拉取並行數';

  @override
  String get mcpAutoProbeConcurrencyBody =>
      '同時執行 MCP 健康檢查或 Tools 拉取的服務數量上限。預設 5；調低可減少資源占用，調高可加速大量服務的批量刷新。';

  @override
  String get mcpAutoProbeConcurrencySave => '儲存並行數';

  @override
  String get mcpAutoProbeConcurrencySaved => 'MCP 檢查/拉取並行數已儲存。';

  @override
  String get mcpAutoProbeConcurrencyInvalid => '請輸入 1 到 32 之間的整數。';

  @override
  String get mcpProbeDetailsTitle => 'MCP 探測詳情';

  @override
  String get mcpProbePoolActive => '探測池執行中';

  @override
  String get mcpProbePoolIdle => '探測池閒置';

  @override
  String get mcpProbePoolStatusTitle => '探測池狀態';

  @override
  String mcpProbeSlots(int active, int total) {
    return '槽位 $active/$total';
  }

  @override
  String mcpProbeQueued(int count) {
    return '佇列 $count';
  }

  @override
  String get mcpProbeStateRunning => '執行中';

  @override
  String get mcpProbeStateIdle => '閒置';

  @override
  String mcpProbeToolsStatus(Object status) {
    return '工具 $status';
  }

  @override
  String mcpProbeHealthStatus(Object status) {
    return '健康 $status';
  }

  @override
  String mcpProbeLastRun(Object time) {
    return '上次 $time';
  }

  @override
  String mcpProbeNextRun(Object time) {
    return '下次 $time';
  }

  @override
  String get mcpProbeControlsTitle => '探測控制';

  @override
  String get mcpProbeForceProbe => '強制觸發探測';

  @override
  String get mcpProbeStopProbing => '中斷目前探測';

  @override
  String get mcpProbeReloadServers => '重新載入服務列表';

  @override
  String mcpProbeServerStatusTitle(int count) {
    return '服務探測狀態 ($count 個服務)';
  }

  @override
  String get mcpProbeNoServers => '暫無服務';

  @override
  String get mcpProbeHealthHealthy => '健康';

  @override
  String get mcpProbeHealthUnhealthy => '異常';

  @override
  String get mcpProbeHealthChecking => '檢測中';

  @override
  String get mcpProbeHealthIdle => '待檢測';

  @override
  String get mcpProbeDisableServerTooltip => '點擊停用此服務探測';

  @override
  String get mcpProbeEnableServerTooltip => '點擊啟用此服務探測';

  @override
  String get mcpProbeNoProbe => '不探測';

  @override
  String mcpProbeToolCount(int count) {
    return '$count 個工具';
  }

  @override
  String get mcpProbeThisServer => '探測此服務';

  @override
  String get mcpRelativeJustNow => '剛剛';

  @override
  String mcpRelativeSecondsAgo(int seconds) {
    return '$seconds 秒前';
  }

  @override
  String mcpRelativeMinutesAgo(int minutes) {
    return '$minutes 分鐘前';
  }

  @override
  String mcpRelativeHoursAgo(int hours) {
    return '$hours 小時前';
  }

  @override
  String mcpRelativeDaysAgo(int days) {
    return '$days 天前';
  }

  @override
  String get mcpRelativeImminent => '即將開始';

  @override
  String mcpRelativeInSeconds(int seconds) {
    return '約 $seconds 秒後';
  }

  @override
  String mcpRelativeInMinutes(int minutes) {
    return '約 $minutes 分鐘後';
  }

  @override
  String mcpRelativeInHours(int hours) {
    return '約 $hours 小時後';
  }

  @override
  String mcpRelativeInDays(int days) {
    return '約 $days 天後';
  }

  @override
  String get mcpKeywordIndexUpdateModeLabel => '更新關鍵字映射模式';

  @override
  String get mcpKeywordIndexUpdateModeBody =>
      '控制 MCP 工具關鍵字倒排索引的重建節奏。冷啟動模式僅在啟動時載入磁碟快取，需要手動點擊「建立關鍵字映射」；定時間隔模式按設定的「值 + 單位」週期重建並整體覆寫磁碟快取；每日定點模式在指定時刻自動重建一次。後兩者共用同一個系統 cron 任務，避免任務碎片化。';

  @override
  String get mcpKeywordIndexUpdateModeColdStart => '冷啟動';

  @override
  String get mcpKeywordIndexUpdateModeInterval => '定時間隔';

  @override
  String get mcpKeywordIndexUpdateModeScheduled => '每日定點';

  @override
  String get mcpKeywordIndexUpdateModeColdStartHint =>
      '冷啟動模式：僅在 App 啟動時載入磁碟上的關鍵字索引；如需重新整理請手動點擊「建立關鍵字映射」。系統 cron 任務保持停用。';

  @override
  String get mcpKeywordIndexIntervalValueLabel => '間隔';

  @override
  String get mcpKeywordIndexIntervalUnitLabel => '單位';

  @override
  String get mcpKeywordIndexIntervalUnitMinute => '分鐘';

  @override
  String get mcpKeywordIndexIntervalUnitHour => '小時';

  @override
  String get mcpKeywordIndexIntervalUnitDay => '天';

  @override
  String mcpKeywordIndexScheduledLabel(String time) {
    return '每日 $time 自動重建';
  }

  @override
  String get mcpKeywordIndexScheduledPickAction => '選擇時間';

  @override
  String get commonClose => '關閉';

  @override
  String get commonRunInBackground => '背景執行';

  @override
  String get mcpBuildKeywordIndex => '建立關鍵字對映';

  @override
  String get mcpKeywordIndexBuildTitle => '建立關鍵字倒排索引';

  @override
  String get mcpKeywordIndexBuildStarting => '正在準備…';

  @override
  String mcpKeywordIndexBuildProgress(
    int idx,
    int count,
    Object server,
    int tools,
  ) {
    return '$idx/$count：$server（已掃 $tools 個工具）';
  }

  @override
  String mcpKeywordIndexBuildSummary(
    int servers,
    int tools,
    int keys,
    Object sec,
  ) {
    return '已索引 $servers 個服務、$tools 個工具，關鍵字 $keys 個，用時 ${sec}s';
  }

  @override
  String mcpKeywordIndexBuildSkipped(int n) {
    return '跳過 $n 個未就緒服務';
  }

  @override
  String get mcpKeywordIndexBuildFailed => '建立失敗：';

  @override
  String get mcpLazyLoadingModeLabel => 'MCP 工具懶載入';

  @override
  String get mcpLazyLoadingModeBody =>
      '控制是否在系統提示中折疊 MCP 工具描述：關閉時全部展開；開啟時全部折疊為 ToolSearch 可按需取回；自動模式下當總 token 估算超過閾值才折疊。';

  @override
  String get mcpLazyLoadingModeDisabled => '關閉';

  @override
  String get mcpLazyLoadingModeAuto => '自動';

  @override
  String get mcpLazyLoadingModeEnabled => '開啟';

  @override
  String get mcpLazyLoadingThresholdLabel => 'MCP 工具壓縮閾值';

  @override
  String get mcpLazyLoadingThresholdBody =>
      '自動模式下 MCP 工具描述總 token 估算超過此值時啟用懶載入。';

  @override
  String get mcpLazyLoadingThresholdSave => '儲存閾值';

  @override
  String get mcpLazyLoadingThresholdSaved => 'MCP 工具懶載入閾值已儲存。';

  @override
  String get mcpLazyLoadingThresholdInvalid => '請填寫 1000 ~ 1000000 之間的整數。';

  @override
  String get settingsHarnessToolSearchHistoryCapLabel =>
      'Harness ToolSearch 歷史保留上限';

  @override
  String get settingsHarnessToolSearchHistoryCapBody =>
      'ToolSearch 已載入清單對話框保留的 Harness phase 最大個數，超出後以 LRU 淘汰。';

  @override
  String settingsHarnessToolSearchHistoryCapValue(int cap) {
    return '當前保留最近 $cap 個 phase';
  }

  @override
  String settingsHarnessToolSearchHistoryCapRange(int min, int max) {
    return '範圍：$min–$max（預設 8）';
  }

  @override
  String settingsHarnessToolSearchHistoryCapResetTooltip(int defaultCap) {
    return '重設為預設值（$defaultCap）';
  }

  @override
  String get harnessCliLoginNoOutputHint =>
      '[提示] CLI 尚未產生輸出。可能正在初始化，或需要在外部瀏覽器中完成授權。\n';

  @override
  String harnessCliLoginTimedOut(int minutes) {
    return '登入等待超過 $minutes 分鐘，已自動停止行程。';
  }

  @override
  String get harnessCliLoginTtyRequiredHint =>
      '[提示] 此 CLI 可能需要真實終端機 (TTY) 才能完成互動式登入。\n請點選下方「在終端機中開啟」按鈕，在系統終端機中完成登入流程。\n';

  @override
  String harnessCliLoginStreamError(Object error) {
    return '[串流錯誤：$error]';
  }

  @override
  String harnessCliLoginFailedToStartProcess(Object message) {
    return '無法啟動行程：$message';
  }

  @override
  String harnessCliLoginOpenTerminalError(Object error) {
    return '[無法開啟終端機：$error]';
  }

  @override
  String get harnessCliLoginStatusFailed => '啟動失敗';

  @override
  String get harnessCliLoginStatusStarting => '正在啟動登入流程...';

  @override
  String get harnessCliLoginStatusFinished => '流程已結束';

  @override
  String harnessCliLoginStatusFinishedWithExit(int exitCode) {
    return '流程已結束 · 結束碼 $exitCode';
  }

  @override
  String get harnessCliLoginStatusWaiting => '等待 CLI 互動...';

  @override
  String harnessCliLoginTitle(Object name) {
    return '$name 登入';
  }

  @override
  String get harnessCliLoginDescription =>
      '此彈窗會在應用程式內啟動互動式 CLI 登入流程。過程中 CLI 可能會自動開啟外部瀏覽器，請依提示完成授權。';

  @override
  String get harnessCliLoginCopyCommandTooltip => '複製命令';

  @override
  String get harnessCliLoginEmptyOutput => '等待 CLI 輸出...';

  @override
  String get harnessCliLoginInputLabel => '傳送輸入';

  @override
  String get harnessCliLoginInputHint => '輸入內容後按 Enter；留空可直接傳送 Enter';

  @override
  String get harnessCliLoginSend => '傳送';

  @override
  String get harnessCliLoginSendEsc => '傳送 Esc';

  @override
  String get harnessCliLoginOpenInTerminal => '在終端機中開啟';

  @override
  String get harnessCliInstallLogSuccess => '✓ 安裝成功';

  @override
  String harnessCliInstallLogSuccessWithPath(Object path) {
    return '✓ 安裝成功（路徑：$path）';
  }

  @override
  String harnessCliInstallLogFailureExitCode(int exitCode) {
    return '✗ 安裝失敗（結束碼：$exitCode）';
  }

  @override
  String harnessCliInstallLogStartProcessFailed(Object message) {
    return '✗ 無法啟動安裝行程：$message';
  }

  @override
  String harnessCliInstallLogGenericError(Object error) {
    return '✗ 發生錯誤：$error';
  }

  @override
  String get harnessCliInstallHintInstallNode =>
      '  → 請先安裝 Node.js：https://nodejs.org';

  @override
  String get harnessCliInstallHintRetryAdminButton => '  → 點選下方「以管理員權限重試」按鈕';

  @override
  String harnessCliInstallHintTrySudo(Object command) {
    return '  → 嘗試：sudo $command';
  }

  @override
  String get harnessCliInstallHintCheckNetworkDocs => '  → 請檢查網路連線或查閱官方文件';

  @override
  String get harnessCliInstallHintInstallPipx =>
      '  → 請先安裝 pipx：https://pipx.pypa.io/stable/installation/';

  @override
  String get harnessCliInstallHintUsePipInstallUserAider =>
      '    或使用：pip install --user aider-chat';

  @override
  String get harnessCliInstallHintHomebrewNoSudo =>
      '  → Homebrew 通常不應以 sudo 安裝，請檢查目錄權限';

  @override
  String get harnessCliInstallHintHomebrewFix =>
      '  → 修復建議：https://docs.brew.sh/FAQ#why-does-homebrew-say-sudo-is-not-allowed';

  @override
  String get harnessCliInstallHintInstallPython =>
      '  → 請先安裝 Python：https://www.python.org';

  @override
  String harnessCliInstallHintPipInstallUser(Object packageName) {
    return '  → 嘗試：pip install --user $packageName';
  }

  @override
  String harnessCliInstallHintOfficialDocs(Object url) {
    return '  → 官方文件：$url';
  }

  @override
  String get harnessCliInstallLogCancelled => '⚠ 安裝已取消';

  @override
  String get harnessCliInstallWindowsAdminManual =>
      '請在管理員權限的 PowerShell 中手動執行：';

  @override
  String harnessCliInstallAdminCommand(Object command) {
    return '> [管理員] $command';
  }

  @override
  String get harnessCliInstallAdminTimeout =>
      '✗ 管理員授權對話框逾時或啟動失敗，已強制結束 osascript 子行程';

  @override
  String get harnessCliInstallUserCancelledAuth => '⚠ 使用者已取消授權';

  @override
  String get harnessCliInstallAdminPermissionFailed => '✗ 無法取得管理員權限';

  @override
  String harnessCliInstallPathMissingWarning(Object executable) {
    return '⚠ 安裝完成，但未在目前 PATH 中偵測到 $executable';
  }

  @override
  String get harnessCliInstallRestartPathHint =>
      '  → 請嘗試重新啟動 OpenHand，或從終端機啟動以載入新的 PATH';

  @override
  String get harnessCliInstallTimeoutManual => '✗ 安裝逾時（超過 5 分鐘），請手動執行：';

  @override
  String harnessCliInstallOsascriptStartFailed(Object message) {
    return '✗ 無法啟動 osascript：$message';
  }

  @override
  String get harnessCliInstallLinuxSudoManual => '請在終端機手動執行（需要 root 權限）：';

  @override
  String get harnessCliInstallStatusInstalling => '安裝中...';

  @override
  String get harnessCliInstallStatusSuccess => '安裝成功';

  @override
  String get harnessCliInstallStatusCancelled => '已取消';

  @override
  String get harnessCliInstallStatusFailed => '安裝失敗';

  @override
  String harnessCliInstallTitle(Object name) {
    return '安裝 $name';
  }

  @override
  String get harnessCliInstallCopyDocUrl => '複製文件連結';

  @override
  String get harnessCliInstallCancel => '取消安裝';

  @override
  String get harnessCliInstallRetryAdmin => '以管理員權限重試';

  @override
  String get harnessCliInstallDoneContinue => '完成，繼續';

  @override
  String get settingsToolSearchReplayCancelWindowLabel => '重播後悔視窗';

  @override
  String get settingsToolSearchReplayCancelWindowBody =>
      'snackbar 送出前等待的秒數；期間按取消即可撤銷。';

  @override
  String settingsToolSearchReplayCancelWindowValue(int seconds) {
    return '視窗：$seconds 秒';
  }

  @override
  String settingsToolSearchReplayCancelWindowRange(int min, int max) {
    return '範圍：$min–$max 秒（預設 3）';
  }

  @override
  String settingsToolSearchReplayCancelWindowResetTooltip(int defaultSeconds) {
    return '重設為預設值（$defaultSeconds 秒）';
  }

  @override
  String get mcpLazyLoadingHowItWorks =>
      '懶載入啟用時：MCP 工具描述被折疊為名稱索引，模型透過內建 ToolSearch 工具按需取回完整 JSON Schema。支援三種查詢：\n• select:NAME（直接選取，可空格分隔多個）\n• 關鍵字（按 name/description 評分配對）\n• +KEYWORD（必含詞，用於過濾雜訊）\n命中後繼續透過 ToolSearch 提交精確 tool_name 和符合 Schema 的 arguments。原生工具目錄保持固定，避免破壞提示詞快取。';

  @override
  String get settingsGeneralSubtitle => '管理主題、語言與應用基礎資訊。';

  @override
  String get settingsAiSubtitle => '管理聊天模型、驗證方式與協議適配。';

  @override
  String get settingsActiveToolCallsTitle => '執行中的工具呼叫';

  @override
  String get settingsActiveToolCallsBody =>
      '即時顯示目前所有正在派發的工具，包括 PID、類別、所屬會話與已執行時長，點擊 Stop 可立即終止該呼叫。';

  @override
  String get settingsActiveToolCallsEmpty => '目前沒有正在執行的工具呼叫。';

  @override
  String get settingsActiveToolCallsCancel => '停止';

  @override
  String get settingsActiveToolKindBuiltin => '內建';

  @override
  String get settingsActiveToolKindMcp => 'MCP';

  @override
  String get settingsActiveToolKindSkill => '技能';

  @override
  String get settingsActiveToolSessionLabel => '會話';

  @override
  String get settingsToolHardeningTitle => '工具加固參數';

  @override
  String get settingsToolHardeningBody =>
      '子行程 graceful shutdown 時長、bash 輸出上限、並行工具呼叫上限。';

  @override
  String get settingsSubprocessGracefulShutdownLabel =>
      '子進程 graceful shutdown（毫秒）';

  @override
  String get settingsSubprocessGracefulShutdownBody =>
      'SIGTERM 之後等多久再升級到 SIGKILL。越大越仁慈，但 UI 取消回應也會變慢。範圍 100–5000。';

  @override
  String get settingsBashOutputMaxBytesLabel => 'Bash 擷取上限（字元）';

  @override
  String get settingsBashOutputMaxBytesBody =>
      '單次 bash 呼叫合併擷取 stdout+stderr 上限。超過從中段截斷保留頭尾。範圍 16000–4000000。';

  @override
  String get settingsMaxConcurrentToolsLabel => '並發工具呼叫上限';

  @override
  String get settingsMaxConcurrentToolsBody => '同會話內同時派發的工具呼叫最大數量。範圍 1–64。';

  @override
  String get settingsToolHardeningInvalid => '請輸入範圍內的整數';

  @override
  String get settingsSkillsSubtitle => '管理本地技能目錄、模板建立與已安裝技能展示。';

  @override
  String get settingsMemorySubtitle => '管理用戶記憶開關與持久化檔案位置。';

  @override
  String get settingsPersistenceInvalidTitle => '設定資料損壞';

  @override
  String get settingsPersistenceInvalidBody => '資料庫記錄無法解析。目前僅顯示安全預設值，不會覆寫原始資料。';

  @override
  String get settingsPersistenceLoadFailedTitle => '設定讀取失敗';

  @override
  String get settingsPersistenceLoadFailedBody =>
      '無法讀取本機資料庫。目前暫時顯示預設值並暫停儲存，以保護既有資料。';

  @override
  String get settingsPersistenceSaveFailedTitle => '設定儲存失敗';

  @override
  String get settingsPersistenceSaveFailedBody =>
      '設定資料庫寫入失敗，介面已回復到上一次有效設定，請檢查資料庫存取權限或磁碟狀態。';

  @override
  String get settingsPersistenceDismiss => '關閉提示';

  @override
  String get settingsAnimationRestoreDefaultsTitle => '恢復預設動畫';

  @override
  String get settingsAnimationRestoreDefaultsSubtitle =>
      '一鍵將彈窗、選單、頁面 / 模組、工作區面板、膠囊、列表項這六組動畫的進場 / 退場風格、時長、速率曲線全部重設為 OpenHand 推薦的預設值。';

  @override
  String get settingsAnimationRestoreDefaultsButton => '恢復預設';

  @override
  String get settingsAnimationRestoreConfirmTitle => '恢復預設動畫？';

  @override
  String get settingsAnimationRestoreConfirmMessage =>
      '將把彈窗、選單、頁面 / 模組、工作區面板、膠囊、列表項六組動畫全部重設為預設值，已自訂的設定會被覆蓋，此操作無法復原。';

  @override
  String get settingsAnimationRestoreConfirm => '恢復';

  @override
  String get settingsAnimationRestoreSuccess => '已恢復預設動畫設定';

  @override
  String get settingsDialogAnimationTitle => '彈窗動畫';

  @override
  String get settingsDialogAnimationSubtitle => '設定全域彈窗的進場動畫、退場動畫、時長和速率曲線。';

  @override
  String get settingsMenuAnimationTitle => '選單動畫';

  @override
  String get settingsMenuAnimationSubtitle =>
      '設定彈出選單、右鍵選單和下拉選單的進場動畫、退場動畫、時長和速率曲線。';

  @override
  String get settingsPanelAnimationTitle => '工作區面板動畫';

  @override
  String get settingsPanelAnimationSubtitle =>
      '設定工作區左右面板切換的進場動畫、退場動畫、時長和速率曲線，例如左側導覽與檔案瀏覽器切換、右側會話與程式碼編輯器切換。Settings、MCP、記憶等右側模組頁面切換由「頁面動畫」控制。';

  @override
  String get settingsPageAnimationTitle => '頁面 / 模組動畫';

  @override
  String get settingsPageAnimationSubtitle =>
      '設定右側主內容模組切換的進場動畫、退場動畫、時長和速率曲線，包括會話、設定、MCP、記憶、Hooks、Crons、技能、自動化等頁面之間的切換。';

  @override
  String get settingsChipAnimationTitle => '膠囊動畫';

  @override
  String get settingsChipAnimationSubtitle =>
      '設定技能、附件、專案引用、佇列訊息、編輯提示等所有可關閉膠囊（chip）的進場 / 退場動畫樣式、時長和速率曲線。點擊叉號關閉時會先播放退場動效再從版面中移除。';

  @override
  String get settingsListItemAnimationTitle => '列表項動畫';

  @override
  String get settingsListItemAnimationSubtitle =>
      '設定 MCP 伺服器、記憶條目、指令卡片、左側導覽會話、工具呼叫卡片等列表項的進場動畫樣式與時長。設為「無」則停用列表項進場動畫。';

  @override
  String get settingsAnimationEnter => '進場';

  @override
  String get settingsAnimationExit => '退場';

  @override
  String get settingsAnimationDuration => '時長';

  @override
  String get settingsAnimationCurve => '曲線';

  @override
  String get dialogAnimationStyleNone => '無動畫';

  @override
  String get dialogAnimationStyleFade => '淡入淡出';

  @override
  String get dialogAnimationStyleFadeScale => '漸顯縮放';

  @override
  String get dialogAnimationStyleSlideUp => '底部上滑';

  @override
  String get dialogAnimationStyleSlideDown => '頂部下滑';

  @override
  String get dialogAnimationStyleSlideLeft => '左側滑入';

  @override
  String get dialogAnimationStyleSlideRight => '右側滑入';

  @override
  String get dialogAnimationStyleExpand => '中心展開';

  @override
  String get dialogAnimationStyleRotateScale => '旋轉縮放';

  @override
  String get dialogAnimationStyleElastic => '彈性動畫';

  @override
  String get dialogAnimationStyleSpringScale => '彈簧縮放';

  @override
  String get dialogAnimationStyleFlipX => 'X 軸翻轉';

  @override
  String get dialogAnimationCurveEaseInOut => '緩入緩出';

  @override
  String get dialogAnimationCurveEaseOut => '緩出';

  @override
  String get dialogAnimationCurveEaseOutCubic => '緩出三次';

  @override
  String get dialogAnimationCurveEaseInOutCubicEmphasized => '三次加強';

  @override
  String get dialogAnimationCurveElasticOut => '彈性緩出';

  @override
  String get dialogAnimationCurveBounceOut => '彈跳';

  @override
  String get dialogAnimationCurveDecelerate => '減速';

  @override
  String get commonOptional => '可選';

  @override
  String get cronScriptTypeCommand => '命令';

  @override
  String get cronScriptTypeScript => '指令碼';

  @override
  String get cronScriptTypeAgent => 'Agent';

  @override
  String get cronJobStatusRunning => '執行中';

  @override
  String get cronJobStatusPaused => '已暫停';

  @override
  String get cronJobStatusFailed => '失敗';

  @override
  String get cronJobStatusError => '異常';

  @override
  String get cronJobStatusIdle => '閒置';

  @override
  String get cronNotifyTypeNone => '無';

  @override
  String get cronNotifyTypeLog => '僅記錄';

  @override
  String get cronNotifyTypeSystem => '系統通知';

  @override
  String get cronNotifyTypeAppNotification => '應用程式內通知';

  @override
  String get cronNotifySeverityInfo => '資訊';

  @override
  String get cronNotifySeveritySuccess => '成功';

  @override
  String get cronNotifySeverityWarning => '警告';

  @override
  String get cronNotifySeverityError => '錯誤';

  @override
  String get cronNotifySeverityCritical => '嚴重';

  @override
  String get cronParserFieldCountError => 'Cron 表示式需要剛好 5 個欄位（分 時 日 月 週）';

  @override
  String get cronParserFieldMinute => '分鐘';

  @override
  String get cronParserFieldHour => '小時';

  @override
  String get cronParserFieldDayOfMonth => '日';

  @override
  String get cronParserFieldDayOfMonthShort => '日';

  @override
  String get cronParserFieldMonth => '月';

  @override
  String get cronParserFieldDayOfWeek => '星期';

  @override
  String get cronParserFieldDayOfWeekShort => '周';

  @override
  String cronParserInvalidField(String field, String value) {
    return '$field欄位 \"$value\" 無效';
  }

  @override
  String get cronsViewDescription =>
      '設定和管理定時任務。支援 Cron 表示式排程、逾時控制、自動重試和執行歷史檢視。';

  @override
  String get cronsNewCronJob => '新增定時任務';

  @override
  String get cronsEditCronJob => '編輯定時任務';

  @override
  String get cronsDeleteCronJobTitle => '刪除定時任務';

  @override
  String cronsDeleteCronJobMessage(String name) {
    return '確定刪除 \"$name\" 嗎？此操作無法復原，執行歷史也會一併刪除。';
  }

  @override
  String get cronsEmptyTitle => '暫無定時任務';

  @override
  String get cronsEmptyBody => '點擊右上角「新增定時任務」按鈕開始設定。';

  @override
  String get cronsCronExpressionTooltip => 'Cron 表达式';

  @override
  String get cronsTimeoutTooltip => '逾時時間';

  @override
  String get cronsRetryCountTooltip => '重試次數';

  @override
  String get cronsMcpKeywordIndexLockedTooltip =>
      '由「全域設定 -> MCP -> 更新關鍵詞映射模式」控制，不可手動開關';

  @override
  String get cronsRunOnceNow => '立即執行一次';

  @override
  String get cronsHistory => '執行歷史';

  @override
  String cronsLastRunAt(String time) {
    return '上次: $time';
  }

  @override
  String get cronsFieldName => '任務名稱';

  @override
  String get cronsFieldNameHint => '例如: 每日備份';

  @override
  String get cronsFieldDescription => '簡介';

  @override
  String get cronsFieldType => '类型';

  @override
  String get cronsFieldScriptFilePath => '指令碼檔案路徑';

  @override
  String get cronsFieldScriptFilePathHint => '選擇 .sh / .ps1 / .bat 檔案';

  @override
  String get cronsBrowse => '浏览';

  @override
  String get cronsFieldCommand => '命令內容';

  @override
  String get cronsFieldCommandHintWindows => '輸入 PowerShell / BAT 命令';

  @override
  String get cronsFieldCommandHintShell => '輸入 Shell 命令';

  @override
  String get cronsCronSchedule => 'Cron 時間表示式';

  @override
  String get cronsCronScheduleHelper => '秒欄位已固定為 0，最小粒度為分鐘。格式: 分 時 日 月 週';

  @override
  String get cronsTimeoutSeconds => '逾時（秒）';

  @override
  String get cronsRetries => '重試次數';

  @override
  String get cronsMaxRetryDelaySeconds => '重試間隔上限（秒）';

  @override
  String get cronsRunAsUser => '執行使用者';

  @override
  String get cronsDefaultCurrentUser => '預設（目前使用者）';

  @override
  String get cronsDefault => '預設';

  @override
  String get cronsTagsCommaSeparated => '標籤（逗號分隔）';

  @override
  String get cronsTagsHint => '例如: 備份, 清理';

  @override
  String get cronsWorkingDirectory => '工作目錄';

  @override
  String get cronsWorkingDirectoryHint => '可選，預設為應用程式目錄';

  @override
  String get cronsEnvironmentVariables => '環境變數';

  @override
  String get cronsEnvironmentVariablesHint => '每行一个，格式: KEY=VALUE';

  @override
  String get cronsExecutionContextCollection => '執行上下文採集';

  @override
  String get cronsCollectAppMetadata => '採集應用程式資訊';

  @override
  String get cronsCollectAppMetadataSubtitle => '記錄應用程式版本、PID、可執行檔路徑等資訊';

  @override
  String get cronsCollectHostMetadata => '採集主機資訊';

  @override
  String get cronsCollectHostMetadataSubtitle => '記錄系統版本、主機名稱、CPU 核心數等資訊';

  @override
  String get cronsCollectEnvironmentSnapshot => '採集環境快照';

  @override
  String get cronsCollectEnvironmentSnapshotSubtitle =>
      '記錄執行時有效環境變數快照（可能包含敏感資訊）';

  @override
  String get cronsSensitive => '敏感';

  @override
  String get cronsNotificationSettings => '通知設定';

  @override
  String get cronsTestNotification => '测试通知';

  @override
  String get cronsTestSuccessNotification => '测试成功通知';

  @override
  String get cronsTestFailureNotification => '测试失败通知';

  @override
  String get cronsTestTimeoutNotification => '测试超时通知';

  @override
  String get cronsTestAllNotifications => '测试全部（顺序）';

  @override
  String get cronsNotificationSettingsHelper => '每個事件可分別設定通知渠道、嚴重程度、聲音和震動。';

  @override
  String get cronsOnSuccess => '執行成功';

  @override
  String get cronsOnFailure => '執行失敗';

  @override
  String get cronsOnTimeout => '執行逾時';

  @override
  String get cronsEnabled => '啟用';

  @override
  String get cronsCustomNotificationMessageHint => '自定义通知内容（可选）';

  @override
  String get cronsVibrationUnsupportedHint => '目前平台不支援震動，開啟後會自動忽略。';

  @override
  String get cronsValidationNameRequired => '請填寫任務名稱。';

  @override
  String get cronsValidationScriptRequired => '請選擇指令碼檔案。';

  @override
  String get cronsValidationCommandRequired => '請填寫命令內容。';

  @override
  String cronsValidationInvalidEnvironment(String lines) {
    return '環境變數格式錯誤，請檢查第 $lines 行。格式應為 KEY=VALUE。';
  }

  @override
  String get cronsNotificationSequentialStartTitle => '开始顺序测试';

  @override
  String get cronsNotificationSequentialStartBody => '将按顺序测试成功、失败、超时通知。';

  @override
  String get cronsNotificationVibrationIgnoredTitle => '震動已忽略';

  @override
  String get cronsNotificationSequentialVibrationIgnoredBody =>
      '当前平台不支持震动，顺序测试中已自动忽略震动设置。';

  @override
  String get cronsNotificationSequentialCompletedTitle => '顺序测试完成';

  @override
  String get cronsNotificationSequentialCompletedBody => '已完成成功、失败、超时三种通知测试。';

  @override
  String get cronsNotificationScenarioSuccess => '成功';

  @override
  String get cronsNotificationScenarioFailure => '失败';

  @override
  String get cronsNotificationScenarioTimeout => '超时';

  @override
  String get cronsNotificationScenarioAll => '全部';

  @override
  String cronsNotificationTestTitle(String label) {
    return '定时任务通知测试 · $label';
  }

  @override
  String get cronsNotificationTestDefaultBodySuccess => '成功场景通知测试消息。';

  @override
  String get cronsNotificationTestDefaultBodyFailure => '失败场景通知测试消息。';

  @override
  String get cronsNotificationTestDefaultBodyTimeout => '超时场景通知测试消息。';

  @override
  String get cronsNotificationNoEmitBody => '当前配置为“无”或“仅日志”，不会触发通知。';

  @override
  String get cronsSystemNotificationUnavailableTitle => '系统通知不可用';

  @override
  String get cronsSystemNotificationFallbackBody => '系统通知发送失败，已回退为应用内通知。';

  @override
  String get cronsNotificationVibrationIgnoredBody => '当前平台不支持震动，已自动忽略该配置。';

  @override
  String get cronsUnknownPlatform => '未知平台';

  @override
  String get cronsToggleOn => '已開啟';

  @override
  String get cronsToggleOff => '已關閉';

  @override
  String get cronsSupportBestEffortSystemSound => '支援（盡力觸發系統聲音）';

  @override
  String get cronsSupportSupported => '支持';

  @override
  String get cronsSupportNotSupportedOnPlatform => '目前平台不支援';

  @override
  String get cronsSupportNotSupportedWillBeIgnored => '不支援（開啟後將自動忽略）';

  @override
  String get cronsSoundLabel => '聲音';

  @override
  String get cronsVibrationLabel => '震動';

  @override
  String get cronsPlatformLabel => '平台';

  @override
  String get cronsSupportLabel => '狀態';

  @override
  String get cronsExecutionHistoryTitle => '定時任務執行歷史';

  @override
  String get cronsClearAllExecutionHistory => '清空全部執行歷史';

  @override
  String get cronsNoExecutionRecords => '暫無執行記錄';

  @override
  String get cronsClearExecutionHistoryTitle => '清空執行歷史';

  @override
  String cronsClearExecutionHistoryMessage(String name) {
    return '確定清空「$name」的全部執行歷史嗎？此操作無法復原。';
  }

  @override
  String get cronsClear => '清空';

  @override
  String get cronsDeleteExecutionRecordTitle => '刪除執行記錄';

  @override
  String get cronsDeleteExecutionRecordMessage => '確定刪除這條執行記錄嗎？';

  @override
  String get cronsExecutionStatusSuccess => '成功';

  @override
  String get cronsExecutionStatusFailed => '失败';

  @override
  String get cronsExecutionStatusTimedOut => '逾時';

  @override
  String get cronsExecutionStatusRunning => '运行中';

  @override
  String get cronsExecutionStatusKilled => '已終止';

  @override
  String get cronsTriggerManual => '手動';

  @override
  String get cronsTriggerScheduled => '排程';

  @override
  String get cronsDeleteThisRecord => '刪除此條記錄';

  @override
  String get cronsRetryAttempt => '重試次數';

  @override
  String get cronsRunAs => '執行使用者';

  @override
  String get cronsWorkingDir => '工作目錄';

  @override
  String get cronsScriptEnvironmentOverrides => '指令碼環境覆寫:';

  @override
  String get cronsEnvironmentSnapshot => '環境快照:';

  @override
  String get cronsErrorReason => '錯誤原因:';

  @override
  String get cronsStdout => '標準輸出 (stdout):';

  @override
  String get cronsStderr => '標準錯誤 (stderr):';

  @override
  String get cronsExecutionContext => '執行上下文:';

  @override
  String get cronsHermesTalkerReportTitle => 'Hermes Talker 自我学习报告';

  @override
  String get cronsHermesNoEligibleSessions => '本輪無符合條件的會話被實際學習。';

  @override
  String cronsHermesAffectedSessions(int count) {
    return '受影響的會話 ($count)';
  }

  @override
  String cronsHermesStatsLine(
    int scanned,
    int triggered,
    int skipped,
    int errors,
  ) {
    return '掃描 $scanned · 觸發 $triggered · 跳過 $skipped · 異常 $errors';
  }

  @override
  String get cronsHermesUntitledSession => '(未命名會話)';

  @override
  String cronsHermesMemoryUpdates(int count) {
    return '记忆 +$count';
  }

  @override
  String cronsHermesMemoryErrors(int count) {
    return '記憶錯誤 $count';
  }

  @override
  String cronsHermesSkillUpdates(int count) {
    return '技能 +$count';
  }

  @override
  String cronsHermesSkillErrors(int count) {
    return '技能錯誤 $count';
  }

  @override
  String cronsHermesProfileChanges(int count) {
    return '使用者輪廓 $count';
  }

  @override
  String cronsHermesToolRounds(int count) {
    return '工具輪次 $count';
  }

  @override
  String get cronsHermesModelLabel => '模型';

  @override
  String get cronsHermesProviderLabel => '渠道';

  @override
  String get cronsHermesTerminatedLabel => '結束原因';

  @override
  String get cronsHermesUserProfileChanges => '使用者輪廓變動';

  @override
  String get cronsHermesMemoryChanges => '记忆变动';

  @override
  String get cronsHermesSkillChanges => '技能变动';

  @override
  String get cronsHermesAiReasoningOnScene => '當時現場的 AI 思考';

  @override
  String get cronsHermesAiResponseOnScene => '當時現場的 AI 回應';

  @override
  String get cronsHermesNoFurtherDetails => '本會話無更多詳情。';

  @override
  String get cronsHermesStatusError => '失敗';

  @override
  String get cronsHermesStatusSkipped => '跳過';

  @override
  String get cronsHermesStatusOk => '完成';

  @override
  String get cronsHermesChangeBefore => '變更前';

  @override
  String get cronsHermesChangeAfter => '變更後';

  @override
  String get cronsHermesChangeValue => '值';

  @override
  String get cronsHermesChangeSource => '來源';

  @override
  String get cronsHermesChangeReason => '原因';

  @override
  String get cronsHermesChangeMetadata => '中繼資料';

  @override
  String get cronsHermesChangeError => '錯誤';

  @override
  String get cronsCollapse => '折疊';

  @override
  String get cronsExpand => '展開';

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
  String get aiModelOfficialWebsiteUrl => '官網地址（可選）';

  @override
  String get aiModelOfficialWebsiteUrlHint => 'https://example.com';

  @override
  String get aiModelOfficialWebsiteUrlInvalid => '請輸入有效的官網地址';

  @override
  String get aiModelOpenWebsiteFailure => '無法打開官網地址。';

  @override
  String get aiModelOpenWebsiteTooltip => '打開官網地址';

  @override
  String get aiModelAuthScheme => '驗證方式';

  @override
  String get aiModelToken => '權杖';

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
  String aiModelTestSuccess(String modelName) {
    return '$modelName 測試通過。';
  }

  @override
  String aiModelTestFailure(String modelName, String reason) {
    return '$modelName 測試失敗：$reason';
  }

  @override
  String get aiModelSelectionRequired => '請先在設定中添加并選擇一個 AI 模型提供者。';

  @override
  String get aiModelScanButton => '掃描模型';

  @override
  String get aiModelScanning => '正在掃描可用模型…';

  @override
  String get aiModelAvailableModels => '可用模型';

  @override
  String get aiModelManualIdHint => '手動輸入模型 ID';

  @override
  String get aiModelManualIdAdd => '添加';

  @override
  String aiModelCount(int count) {
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
  String get aiProtocolDots => 'Dots (小紅書)';

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
  String get aiProtocolAgnes => 'Agnes';

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
  String get skillsNoResultsTitle => '找不到符合條件的技能';

  @override
  String get skillsNoResultsBody => '請嘗試修改搜尋關鍵字，或清除搜尋後重新查看全部技能。';

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
  String get memoryPageSubtitle => '統一維護儲存在本機資料庫中的用戶記憶。';

  @override
  String get memoryRefresh => '重新整理';

  @override
  String get memoryNewEntry => '新增記憶';

  @override
  String get memoryEmptyTitle => '還沒有任何用戶記憶';

  @override
  String get memoryEmptyBody => '新增用戶記憶後，它會持久化儲存到本機資料庫。';

  @override
  String get memoryLoadFailedTitle => '記憶資料讀取失敗';

  @override
  String get memoryLoadFailedBody => '記憶資料無效或暫時無法使用，請修復或清空儲存後重試。';

  @override
  String get memoryQuotaRecoveryTitle => '記憶儲存已超出配額';

  @override
  String get memoryQuotaRecoveryBody => '目前僅顯示受限快照。請刪除項目或縮減內容直到恢復限額；期間禁止新增項目。';

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
  String get memoryTagLimitExceeded => '每條記憶最多可新增 32 個標籤。';

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
  String get userMemoryFileLabel => '記憶資料庫';

  @override
  String get memoryFileBody => '用戶記憶統一儲存在 OpenHand 本機 SQLite 資料庫中。';

  @override
  String get memoryFileDefaultPath => '資料庫位置';

  @override
  String get memoryOpenDirectory => '開啟資料庫目錄';

  @override
  String get memoryDisabledTitle => '記憶能力目前已關閉';

  @override
  String get memoryDisabledBody => '你仍然可以在這裡維護用戶記憶內容；如需在運行時啟用，請到設定頁記憶板塊打開記憶開關。';

  @override
  String get memoryCreatedAtLabel => '建立時間';

  @override
  String get memoryPersistenceSaveFailedTitle => '記憶資料儲存失敗';

  @override
  String get memoryPersistenceSaveFailedBody =>
      '記憶資料庫寫入失敗，未提交的變更未被套用，請檢查資料庫存取權限或磁碟狀態。';

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
  String mcpDeleteAlsoUninstallPackage(String packageName) {
    return '同時卸載底層套件（$packageName）';
  }

  @override
  String get mcpDeleteAlsoUninstallPackageBody => '將卸載全域套件並清理隔離快取。';

  @override
  String mcpDependencyCleanedUp(String packageName) {
    return '$packageName 依賴已清理';
  }

  @override
  String mcpDependencyCleanupFailed(String packageName, String error) {
    return '$packageName 清理失敗：$error';
  }

  @override
  String mcpDependencyCleanupError(String packageName, String error) {
    return '$packageName 清理異常：$error';
  }

  @override
  String get mcpTemplateSessionManaged => '會話託管';

  @override
  String mcpTemplateSessionOn(String status) {
    return '會話啟用 · $status';
  }

  @override
  String mcpTemplateSessionOff(String status) {
    return '會話關閉 · $status';
  }

  @override
  String get mcpTemplateNotRegistered => '未註冊';

  @override
  String mcpTemplateRuntimeEnabledCount(int count) {
    return '會話啟用 $count';
  }

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
  String get aiToolResultCompressionThresholdSave => '儲存閾值';

  @override
  String get aiToolResultCompressionThresholdSaved => '工具呼叫輸出壓縮閾值已更新。';

  @override
  String get aiToolResultCompressionThresholdInvalid => '請輸入有效的正整數閾值。';

  @override
  String get aiToolResultCompressionEnabledLabel => '啟用工具呼叫輸出壓縮';

  @override
  String get aiToolResultCompressionEnabledBody =>
      '控制產生壓縮檢查點時是否摘要過長工具輸出。普通對話始終向模型交付完整結果；關閉後檢查點也保留原文，可能增加壓縮成本。';

  @override
  String get aiMicroCompressionEnabledLabel => '微壓縮';

  @override
  String get aiMicroCompressionEnabledBody =>
      '開啟後，僅在產生摘要檢查點時將更早的已消費工具結果壓成緊湊恢復線索，降低摘要成本；正常對話歷史保持穩定，以保護輸入快取命中。關閉後仍會按上方閾值做結構化摘要。';

  @override
  String get aiMessageContentSectionLabel => '訊息內容';

  @override
  String get aiMessageContentFormatLabel => '內容格式';

  @override
  String get aiMessageContentFormatBody =>
      '控制 AI 助手訊息的展示方式。Markdown 為預設；純文字性能最佳；HTML 由第三方庫渲染，token 消耗略高，渲染失敗時依下方回退策略降級。';

  @override
  String get aiMessageContentFormatMarkdown => 'Markdown';

  @override
  String get aiMessageContentFormatPlainText => '純文字';

  @override
  String get aiMessageContentFormatHtml => 'HTML';

  @override
  String get aiMessageContentFormatHtmlTokenWarning =>
      'HTML 模式會向每輪 Prompt 注入額外約束，token 消耗略高。';

  @override
  String get aiHtmlRenderFallbackLabel => 'HTML 渲染失敗回退';

  @override
  String get aiHtmlRenderFallbackBody =>
      '當 HTML 解析或渲染異常時，依此策略降級；Markdown 會嘗試以 Markdown 解析，PlainText 則直接以純文字展示。';

  @override
  String get aiHtmlRenderFallbackMarkdown => 'Markdown';

  @override
  String get aiHtmlRenderFallbackPlainText => '純文字';

  @override
  String get aiHtmlContentRichnessLabel => 'HTML 內容豐富度';

  @override
  String get aiHtmlContentRichnessBody =>
      '控制 HTML 模式下注入給模型的視覺風格強度。適中為預設（克制黑白灰）；豐富放開色彩與卡片；多彩推到極致漸層、玻璃擬態與封面塊，token 成本最高。';

  @override
  String get aiHtmlContentRichnessBalanced => '適中';

  @override
  String get aiHtmlContentRichnessRich => '豐富';

  @override
  String get aiHtmlContentRichnessVivid => '多彩';

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
    return '留空則預設 ${seconds}s。僅作無副作用工具的執行時護欄；Task/Bash/寫入工具使用自身限制。';
  }

  @override
  String get builtinToolRetryLabel => '失敗/超時自動重試';

  @override
  String get builtinToolRetryBody =>
      '預設關閉。僅對無副作用工具的真正失敗 (failed/timed_out) 自動重試；不會重試參數錯誤、被拒絕呼叫、Task、寫入命令、檔案編輯、背景程序、技能變更或記憶寫入。';

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
  String tsmDeleteSelectedConfirm(int count) {
    return '將永久刪除 $count 個執行緒及其訊息，此操作無法復原。';
  }

  @override
  String tsmDeleteFailedCount(int count) {
    return '$count 個執行緒刪除失敗';
  }

  @override
  String get tsmSessionMissing => '工作階段不存在或已刪除';

  @override
  String get tsmExportSessionDataTitle => '匯出工作階段資料';

  @override
  String tsmExportingSession(String title) {
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
  String tsmBatchExportSubtitle(int count) {
    return '即將匯出 $count 個執行緒…';
  }

  @override
  String tsmBatchExportDone(int ok, int failed) {
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
  String tsmPreviewMessageCount(int count) {
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
  String tsmSortDisabledHint(String mode) {
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
  String tsmHeaderSubtitle(int count) {
    return '共 $count 個執行緒 · 長按或拖曳控制點可重新排序，按兩下或按右鍵可叫出更多選項';
  }

  @override
  String tsmSelectedCount(int count) {
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
      '管理內建 Web通用訊息平台的監聽、驗證、會話、Web 聊天、健康檢查、日誌與維運能力。';

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
  String get inputRepairTitle => '輸入修復';

  @override
  String get inputRepairBody =>
      '回收遺留的子行程（osascript、LSP、MCP 等），並重置 macOS 輸入法上下文，修復全域文字框無法輸入、複製、貼上或 ESC 失效的問題';

  @override
  String get inputRepairButton => '修復輸入';

  @override
  String get inputRepairDone => '已重置輸入上下文';

  @override
  String inputRepairDoneDetail(int count) {
    return '已重置輸入上下文，回收 $count 個背景子行程';
  }

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
  String proxyTestSuccess(int latency, String via) {
    return '連通成功（$latency ms，via $via）';
  }

  @override
  String proxyTestFailure(String reason) {
    return '連通失敗：$reason';
  }

  @override
  String get proxyTestEndpointLabel => '測試 URL';

  @override
  String get proxyTestEndpointHint => '預設：https://www.google.com/generate_204';

  @override
  String get proxyTestVerdictDirect => '直連';

  @override
  String proxyTestVerdictProxy(String endpoint) {
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
  String get tokenPopupCostCacheRead => '快取命中';

  @override
  String get tokenPopupCostCacheWrite => '快取寫入';

  @override
  String get tokenPopupCostTotal => '總計';

  @override
  String get tokenDialUnit => 'Token';

  @override
  String get tokenPopupInputHeading => '輸入';

  @override
  String get tokenPopupPrompt => '提示詞';

  @override
  String get tokenPopupAudioInput => '音訊輸入';

  @override
  String get tokenPopupImageInput => '圖片輸入';

  @override
  String get tokenPopupVideoInput => '影片輸入';

  @override
  String get tokenPopupCacheRead => '快取命中';

  @override
  String get tokenPopupCacheWrite => '快取寫入';

  @override
  String get tokenPopupOutputHeading => '輸出';

  @override
  String get tokenPopupCompletion => '回覆';

  @override
  String get tokenPopupReasoning => '推理';

  @override
  String get tokenPopupWebSearchHeading => '網路搜尋';

  @override
  String get tokenPopupWebSearchCalls => '呼叫次數';

  @override
  String get tokenPopupWebSearchPages => '返回頁面';

  @override
  String get tokenPopupGrandTotal => '總計';

  @override
  String get tokenPopupContextOverview => '上下文資料概覽';

  @override
  String get tokenPopupContextMeasured => '總量實測 · 分類換算';

  @override
  String get tokenPopupContextEstimated => '依請求內容估算';

  @override
  String get tokenPopupContextEmpty => '傳送下一則訊息後產生概覽';

  @override
  String get tokenPopupContextSystemPrompt => '系統 Prompt';

  @override
  String get tokenPopupContextBuiltinTools => '內建 Tool';

  @override
  String get tokenPopupContextMcp => 'MCP';

  @override
  String get tokenPopupContextInstructions => '指令';

  @override
  String get tokenPopupContextMemory => '記憶';

  @override
  String get tokenPopupContextSkills => '技能';

  @override
  String get tokenPopupContextHooks => 'Hooks';

  @override
  String get tokenPopupContextConversation => '會話';

  @override
  String get tokenPopupContextRuntime => '執行階段';

  @override
  String get tokenPopupContextWindow => '上下文視窗';

  @override
  String get tokenPopupCompactNow => '主動壓縮';

  @override
  String get tokenPopupCompacting => '正在壓縮…';

  @override
  String get tokenPopupSessionHeading => '會話累計';

  @override
  String get tokenPopupMessages => '訊息總數';

  @override
  String get tokenPopupPromptBuilds => '提示詞構建';

  @override
  String get tokenPopupPromptChars => '提示詞字元';

  @override
  String get tokenPopupCacheHitModeExcludeExpired => '不含過期異常';

  @override
  String get tokenPopupCacheHitModeIncludeExpired => '含過期異常';

  @override
  String tokenPopupExcludedRounds(int count) {
    return '已排除 $count 輪';
  }

  @override
  String get tokenPopupPrefixReuse => '前綴復用';

  @override
  String tokenPopupTooltipFreshReuse(String fresh, int reuse) {
    return '新增 $fresh · 復用 $reuse%';
  }

  @override
  String get tokenPopupFirstRequestShort => '首輪不計';

  @override
  String get tokenPopupFirstRequestNotAveraged => '不參與平均';

  @override
  String get tokenPopupTrendNoData => '尚無快取命中率資料，傳送訊息後會在此展示走勢。';

  @override
  String get tokenPopupTrendOnlyFirstIgnored => '首輪請求不參與平均，下一輪正常請求後展示趨勢。';

  @override
  String get tokenPopupTrendFirstReferenceOnly => '首輪僅作參考，不參與平均快取命中率。';

  @override
  String get tokenPopupUncached => '未快取';

  @override
  String get toolbarSessionMetadata => '會話元數據';

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
  String toolbarMcpLazyLoading(int loaded, int total) {
    return 'MCP 已載 $loaded/$total';
  }

  @override
  String snackToolSearchLoaded(int loaded, int total) {
    return 'ToolSearch 已載入 $loaded/$total 個 MCP 工具';
  }

  @override
  String get snackToolSearchLoadedAction => '檢視列表';

  @override
  String get snackToolSearchLoadedDialogTitle => 'ToolSearch 已載入的 MCP 工具';

  @override
  String get snackToolSearchLoadedDialogClose => '關閉';

  @override
  String get snackToolSearchLoadedCopyAction => '複製 select:';

  @override
  String get snackToolSearchLoadedCopiedToast => '已複製';

  @override
  String get snackToolSearchLoadedClearAction => '清空已載入清單';

  @override
  String get snackToolSearchLoadedClearedToast => '已清空已載入清單';

  @override
  String get snackToolSearchLoadedGroupOther => '其他（未識別 server）';

  @override
  String get snackToolSearchLoadedCopyGroupAction => '複製本組全部';

  @override
  String get snackToolSearchLoadedTabLoaded => '已載入';

  @override
  String get snackToolSearchLoadedTabHistory => '載入歷史';

  @override
  String get snackToolSearchLoadedHistoryEmpty => '本會話尚無 ToolSearch 載入紀錄';

  @override
  String get snackToolSearchLoadedHistoryQueryPrefix => '載入查詢：';

  @override
  String get snackToolSearchLoadedFilterHint => '依名稱過濾…';

  @override
  String get snackToolSearchLoadedHistoryFilterHint => '依名稱或查詢過濾…';

  @override
  String get snackToolSearchLoadedSourceAi => 'AI 對話';

  @override
  String get snackToolSearchLoadedSourceHarness => 'Harness 階段';

  @override
  String get snackToolSearchLoadedReplayedToast => '已重新發起 ToolSearch';

  @override
  String get snackToolSearchLoadedReplayPendingToast => '即將發起，3 秒內可點擊「撤銷」';

  @override
  String get snackToolSearchLoadedReplayCancelAction => '撤銷';

  @override
  String get snackToolSearchLoadedReplayCancelledToast => '已撤銷 — composer 已清空';

  @override
  String get snackToolSearchLoadedSourceFilterAll => '全部';

  @override
  String get snackToolSearchLoadedSourceFilterAi => '僅 AI';

  @override
  String get snackToolSearchLoadedSourceFilterHarness => '僅 Harness';

  @override
  String snackToolSearchLoadedSummary(int queries, int tools) {
    return '本對話已從 $queries 個查詢中載入 $tools 個 MCP 工具';
  }

  @override
  String get snackToolSearchLoadedHistoryReplayAction => '把本次複製為 select:…';

  @override
  String get snackToolSearchLoadedHistoryClearAction => '清空歷史';

  @override
  String get snackToolSearchLoadedHistoryExportTooltip => '匯出歷史';

  @override
  String get snackToolSearchLoadedHistoryExportCsv => '複製為 CSV';

  @override
  String get snackToolSearchLoadedHistoryExportMarkdown => '複製為 Markdown';

  @override
  String get snackToolSearchLoadedHistoryExportJson => '複製為 JSON';

  @override
  String get snackToolSearchLoadedHistoryExportSaveCsv => '另存為 CSV…';

  @override
  String get snackToolSearchLoadedHistoryExportSaveMarkdown => '另存為 Markdown…';

  @override
  String get snackToolSearchLoadedHistoryExportSaveJson => '存檔為 JSON…';

  @override
  String get snackToolSearchLoadedHistoryExportCsvHint => '適合表格軟體；一條 query 一行。';

  @override
  String get snackToolSearchLoadedHistoryExportMarkdownHint =>
      'GitHub 風格表格；貼 Issue / 文件好看。';

  @override
  String get snackToolSearchLoadedHistoryExportJsonHint =>
      '結構化資料；可被 OpenHand 重新匯入。';

  @override
  String get toolSearchLoadedHistoryImportTooltip => '匯入 JSON 轉存';

  @override
  String get toolSearchLoadedHistoryImportDialogTitle => 'ToolSearch 歷史匯入預覽';

  @override
  String toolSearchLoadedHistoryImportDialogCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 條記錄',
      zero: '無條目',
    );
    return '$_temp0';
  }

  @override
  String get toolSearchLoadedHistoryImportDialogEmpty => '檔案中未發現任何條目。';

  @override
  String get toolSearchLoadedHistoryImportDialogClose => '關閉';

  @override
  String snackToolSearchLoadedHistoryExportSavedToast(int count, String path) {
    return '已存檔 $count 條至 $path';
  }

  @override
  String snackToolSearchLoadedHistoryExportSaveFailedToast(String error) {
    return '存檔失敗：$error';
  }

  @override
  String get snackToolSearchLoadedHistoryExportRevealAction => '在訪談器中顯示';

  @override
  String get snackToolSearchLoadedHistoryExportEmptyToast => '篩選後歷史為空，無可匯出。';

  @override
  String snackToolSearchLoadedHistoryExportedToast(int count) {
    return '已複製 $count 條歷史至剪貼簿。';
  }

  @override
  String get snackToolSearchLoadedHistoryClearedToast => '載入歷史已清空';

  @override
  String get mcpLazyLoadingViewLoadedAction => '檢視本會話已載入清單';

  @override
  String get mcpToolSearchExportLastDirResetAction => '清除記憶的匯出目錄';

  @override
  String get mcpToolSearchExportLastDirResetToast => '已清除匯出目錄記憶';

  @override
  String get mcpLazyLoadingNoActiveSession => '目前沒有進行中的會話';

  @override
  String toolbarPlanStepsCompleted(int completed, int total) {
    return '已完成 $completed/$total 項';
  }

  @override
  String get mdlEdEnterAValidBaseUrlFirst => '请先输入有效的 Base URL';

  @override
  String get mdlEdNoModelsFoundFromThisProvider => '未从该提供商扫描到模型。';

  @override
  String get mdlEdProviderName => '提供商名称';

  @override
  String get mdlEdOptionalEGDeepseekLocalOllama => '可选，如 DeepSeek、本地 Ollama';

  @override
  String get mdlEdCurrentlyActiveModel => '当前活跃模型';

  @override
  String get mdlEdClickToSetAsActiveModel => '点击切换为活跃模型';

  @override
  String get mdlEdTapScanModelsToDiscoverModels => '点击「扫描模型」按钮自动发现可用模型，或手动添加。';

  @override
  String get mdlEdActiveModelId => '当前活跃模型 ID';

  @override
  String get mdlEdTheModelUsedForConversationsSelect =>
      '当前用于对话的模型。可从上方列表选择或直接输入。';

  @override
  String get mdlEdMaxContextTokens => '最大上下文 Token 上限';

  @override
  String get mdlEdOptionalLimitsTheHistorySliceUsed => '可选。用于在压缩时限制历史切片大小。';

  @override
  String get mdlEdEnterAWholeNumberGreaterThan => '请输入大于 0 的整数';

  @override
  String get mdlEdRequestMethod => '请求方式';

  @override
  String get mdlEdOutputMode => '输出模式';

  @override
  String get mdlEdStreaming => '流式输出';

  @override
  String get mdlEdNonStreaming => '非流式输出';

  @override
  String get mdlEdMaxOutputTokens => '最大输出 Token 数';

  @override
  String get mdlEdOptionalUsesAdapterDefaultIfUnset => '可选。不指定则使用适配器默认值。';

  @override
  String get mdlEdTemperature => '温度';

  @override
  String get mdlEd0020Default0 => '0.0 ~ 2.0，默认 0.7';

  @override
  String get mdlEdEnterANumberBetween00 => '请输入 0.0 到 2.0 之间的数值';

  @override
  String get mdlEdCustomHeaders => '自定义请求头';

  @override
  String get mdlEdAdd => '添加';

  @override
  String get mdlEdNoCustomHeadersTapAddTo => '暂无自定义请求头。点击「添加」按钮来添加。';

  @override
  String get mdlEdHeaderName => 'Header 名称';

  @override
  String get mdlEdHeaderValue => 'Header 值';

  @override
  String get mdlEdEditModelProfile => '编辑模型配置';

  @override
  String get mdlEdDisplayName => '显示名称';

  @override
  String get mdlEdOptionalShownInTheUi => '可选，用于界面展示';

  @override
  String get mdlEdDescription => '模型描述';

  @override
  String get mdlEdMultimodalSupport => '多模态支持';

  @override
  String get mdlEdAutoDetect => '自动检测';

  @override
  String get mdlEdYes => '是';

  @override
  String get mdlEdNo => '否';

  @override
  String get mdlEdSupportsAttachments => '支持附件';

  @override
  String get mdlEdReasoningEcho => '攜帶思考內容回響';

  @override
  String get mdlEdReasoningEchoHint => '控制該模型是否把先前輪次的思考/推理內容回灌到後續 Prompt 歷史中。';

  @override
  String get mdlEdSupportedModalities => '支持的模态';

  @override
  String get mdlEdText => '文本';

  @override
  String get mdlEdImage => '图片生成';

  @override
  String get mdlEdVideo => '视频生成';

  @override
  String get mdlEdAudio => '音频生成';

  @override
  String get mdlEdGenerationCapabilities => '生成能力';

  @override
  String get mdlEdPdf => 'PDF 生成';

  @override
  String get mdlEdPpt => 'PPT 生成';

  @override
  String get mdlEdTokenLimits => 'Token 限制';

  @override
  String get mdlEdContextLength => '上下文长度';

  @override
  String get mdlEdSummaryLength => '摘要长度';

  @override
  String get mdlEdOutputLength => '输出长度';

  @override
  String get mdlEdThinkingLength => '思考长度';

  @override
  String get mdlEdTokenPricingUsd1mTokensLeave =>
      'Token 单价（USD / 1M tokens，留空表示未配置）';

  @override
  String get mdlEdInput => '输入价';

  @override
  String get mdlEdOutput => '输出价';

  @override
  String get mdlEdCacheRead => '缓存读取价';

  @override
  String get mdlEdCacheWrite => '缓存写入价';

  @override
  String get mdlEdOpenRouterMetadataOverrides => 'OpenRouter 元資料覆寫';

  @override
  String get mdlEdCanonicalSlug => '規範模型識別';

  @override
  String get mdlEdHuggingFaceId => 'Hugging Face 模型識別';

  @override
  String get mdlEdKnowledgeCutoff => '知識截止日期';

  @override
  String get mdlEdExpirationDate => '到期日期';

  @override
  String get mdlEdSupportedParametersCsv => '支援的參數';

  @override
  String get mdlEdSupportedParametersCsvHint =>
      '例如 input、model、input_type、truncate';

  @override
  String get mdlEdDefaultParametersJson => '預設參數';

  @override
  String get mdlEdDefaultParametersJsonHint => '例如 encoding_format: float';

  @override
  String get mdlEdOpenRouterRawMetadata => 'OpenRouter 原始元資料';

  @override
  String get mdlEdOpenRouterRawMetadataFields =>
      '包含 id、canonical_slug、hugging_face_id、created、architecture、supported_parameters、default_parameters、supported_voices、knowledge_cutoff、expiration_date 與 links';

  @override
  String get mdlEdReset => '重置';

  @override
  String get mdlEdCancel => '取消';

  @override
  String get mdlEdOk => '确定';

  @override
  String get tlCallDir => '目录';

  @override
  String get tlCallElapsed => '耗时';

  @override
  String get tlCallExit => '退出码';

  @override
  String get tlCallToolInput => '工具入参';

  @override
  String get tlCallCommand => '命令';

  @override
  String get tlCallArguments => '入參';

  @override
  String get tlCallToolOutput => '结果输出';

  @override
  String get tlCallNoOutputYet => '暂无输出';

  @override
  String get tlCallResult => '結果';

  @override
  String get tlCallStdout => '標準輸出';

  @override
  String get tlCallStderr => '標準錯誤';

  @override
  String get tlCallArgumentsConstructing => '參數構造中…';

  @override
  String get tlCallArgumentsConstructingHint =>
      '正在跟隨模型輸出即時拼裝入參，參數構造完成後會自動切回正常狀態。';

  @override
  String get tlCallCollectedParameters => '已採集參數';

  @override
  String get tlCallNoParametersYet => '尚未解析到入參';

  @override
  String get tlCallSubmitting => '提交中…';

  @override
  String get tlCallSubmittingHint => '已採集參數完畢，正在交給執行器';

  @override
  String get tlCallThereIsNoToolOutputYet => '当前还没有工具输出。';

  @override
  String get tlCallViewInDialog => '在弹窗里查看完整内容';

  @override
  String get tlCallEmptyContent => '内容为空';

  @override
  String get fileMutationSection => '檔案變動';

  @override
  String fileMutationFilesChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已更改 $count 個檔案',
    );
    return '$_temp0';
  }

  @override
  String fileMutationFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個檔案',
    );
    return '$_temp0';
  }

  @override
  String get fileMutationUndoAll => '全部復原';

  @override
  String get fileMutationRefresh => '重新整理';

  @override
  String get fileMutationCopyAllDiff => '複製全部 diff';

  @override
  String get fileMutationCopyAllDiffDone => '全部 diff 已複製到剪貼簿';

  @override
  String get fileMutationRevealLedger => '於檔案管理員中查看 ledger.jsonl';

  @override
  String get fileMutationCopyPath => '複製檔案路徑';

  @override
  String get fileMutationPathCopied => '路徑已複製';

  @override
  String fileMutationRevealMore(int count) {
    return '還有 $count 條變更未展示，點擊繼續展開';
  }

  @override
  String get fileMutationRevealAll => '全部展開';

  @override
  String get fileMutationHistoryInspector => '歷史檢查器';

  @override
  String get fileMutationHistoryInspectorTitle => '會話檔案變更歷史';

  @override
  String get fileMutationHistoryInspectorFilterHint => '按路徑過濾…';

  @override
  String get fileMutationHistoryInspectorEmpty => '沒有符合過濾條件的檔案變更。';

  @override
  String get fileMutationHistoryInspectorZoomIn => '只看此路徑';

  @override
  String get fileMutationHistoryInspectorZoomOut => '返回全部路徑';

  @override
  String get fileMutationUndone => '已復原';

  @override
  String get fileMutationCascadeUndone => '連動失效';

  @override
  String get fileMutationUndoThis => '復原此次修改';

  @override
  String get fileMutationRedo => '重做';

  @override
  String get fileMutationUndoFailed => '復原失敗';

  @override
  String get fileMutationRedoFailed => '重做失敗';

  @override
  String get fileMutationSnapshotUnavailable => '內容快照不可用';

  @override
  String get tlCallTool => '工具';

  @override
  String get tlCallSkill => '技能';

  @override
  String get tlCallStopped => '已停止';

  @override
  String get tlCallStopRequest => '終止此工具調用';

  @override
  String get tlCallBlocked => '已拦截';

  @override
  String get tlCallRejected => '用户拒绝';

  @override
  String get tlCallInvalid => '参数无效';

  @override
  String get tlCallToolCall => '工具调用';

  @override
  String get tlCallRunning => '运行中';

  @override
  String get tlCallSucceeded => '执行成功';

  @override
  String get tlCallDenied => '已被禁止';

  @override
  String get tlCallTimedOut => '执行超时';

  @override
  String get tlCallFailed => '执行失败';

  @override
  String get tlCallToolIsRunningWaitingForOutput => '工具运行中，等待新的输出...';

  @override
  String get tlCallExpandToInspectToolOutput => '点击展开查看工具输出';

  @override
  String get tlCallSelfLearning => '自我学习';

  @override
  String get tlCallNudgeRecovered => '已纠正\"光说不做\"';

  @override
  String get tlCallProfileChanges => '用户画像变更';

  @override
  String get tlCallMemoryChanges => '记忆变更';

  @override
  String get tlCallSkillChanges => '技能变更';

  @override
  String get tlCallProfileDiff => '画像差异摘要';

  @override
  String get tlCallNoChanges => '无变更';

  @override
  String get tlCallUnnamed => '(未命名)';

  @override
  String get tlCallJustNow => '刚刚';

  @override
  String get sessMetaCacheHitTrend => '快取命中率趨勢';

  @override
  String get sessMetaCacheHitLast => '末輪';

  @override
  String get sessMetaCacheHitAvg => '平均';

  @override
  String get sessMetaCacheHitMax => '峰值';

  @override
  String get sessMetaCacheHitOverlayOn => '疊加另一條公式';

  @override
  String get sessMetaCacheHitOverlayOff => '隱藏疊加公式';

  @override
  String get sessMetaCacheHitFormulaClaude => 'Claude 公式';

  @override
  String get sessMetaCacheHitFormulaOpenAi => 'OpenAI 公式';

  @override
  String sessMetaCacheHitPoint(int index) {
    return '第 $index 輪';
  }

  @override
  String get sessMetaMessages => '消息总数';

  @override
  String get sessMetaPromptBuilds => 'Prompt 构建';

  @override
  String get sessMetaCompressions => '压缩次数';

  @override
  String get sessMetaTotalTokens => '总 Token';

  @override
  String get sessMetaMode => '当前模式';

  @override
  String get sessMetaRuntimeTools => '运行工具';

  @override
  String get sessMetaPending => '未展示';

  @override
  String get sessMetaCurrentSessionMetadata => '当前会话元数据';

  @override
  String get sessMetaSessionOverview => '会话概览';

  @override
  String get sessMetaExtendedMetadata => '扩展元数据';

  @override
  String get sessMetaStatistics => '统计信息';

  @override
  String get sessMetaUser => '用户';

  @override
  String get sessMetaAssistant => '助手';

  @override
  String get sessMetaTool => '工具';

  @override
  String get sessMetaSkill => '技能';

  @override
  String get sessMetaCompression => '压缩';

  @override
  String get sessMetaEnvironment => '运行环境';

  @override
  String get sessMetaCommandPolicy => '命令策略';

  @override
  String get sessMetaPromptMetadataIsNotAvailableYet => '当前还没有可展示的 prompt 元数据。';

  @override
  String get sessMetaWriteConfirmation => '写命令确认';

  @override
  String get sessMetaRequired => '需要确认';

  @override
  String get sessMetaNotRequired => '无需确认';

  @override
  String get sessMetaAllowRules => '允许规则数';

  @override
  String get sessMetaThereAreNoSurfacedAllowCommand => '当前没有已上屏的允许命令规则。';

  @override
  String get sessMetaRuntimeOrchestration => '运行时编排';

  @override
  String get sessMetaStateSource => '状态来源';

  @override
  String get sessMetaGeneratedFromTheCurrentModelMcp =>
      '根据当前模型、MCP/Skills 与 Plan 状态即时生成';

  @override
  String get sessMetaTheLastPersistedRuntimeSnapshot => '上一轮已落盘的运行时快照';

  @override
  String get sessMetaToolCatalogState => '工具目录状态';

  @override
  String get sessMetaGateReason => '门控原因';

  @override
  String get sessMetaRuntimeToolCount => '当前运行时工具数';

  @override
  String get sessMetaRefreshesNextRound => '等待下一轮刷新';

  @override
  String get sessMetaRuntimeNotices => '运行时 Notices';

  @override
  String get sessMetaCurrentRuntimeTools => '当前运行时工具';

  @override
  String get sessMetaTaskTracking => '任务跟踪';

  @override
  String get sessMetaCurrentTodos => '当前 Todo 数量';

  @override
  String get sessMetaPlanRecords => '计划记录数量';

  @override
  String get sessMetaTodowriteReminder => 'TodoWrite 强提醒';

  @override
  String get sessMetaTriggered => '已触发';

  @override
  String get sessMetaNotTriggered => '未触发';

  @override
  String get sessMetaUnavailable => '暂无数据';

  @override
  String get sessMetaReminderReason => '提醒原因';

  @override
  String get sessMetaPlanHistory => '计划历史';

  @override
  String get sessMetaRecentErrors => '最近异常';

  @override
  String get sessMetaThereAreNoSessionErrorsTo => '当前没有需要关注的会话异常。';

  @override
  String get sessMetaLastPromptMetadata => '最后一次 Prompt 元数据';

  @override
  String get sessMetaClose => '关闭';

  @override
  String get sessMetaPendingApproval => '待确认';

  @override
  String get sessMetaInProgress => '进行中';

  @override
  String get sessMetaCompleted => '已完成';

  @override
  String get sessMetaFailed => '失败';

  @override
  String get sessMetaCancelled => '已取消';

  @override
  String get sessMetaCreated => '创建';

  @override
  String get sessMetaUpdated => '更新';

  @override
  String get sessMetaErrorDetail => '错误细节';

  @override
  String get commonDetails => '詳情';

  @override
  String get commonCopy => '複製';

  @override
  String get commonViewDetails => '查看詳情';

  @override
  String get commonCopiedToClipboard => '已複製到剪貼簿';

  @override
  String get structuredErrorWhy => '原因：';

  @override
  String get structuredErrorTry => '建議：';

  @override
  String get structuredErrorServerSays => '服務端原文：';

  @override
  String get structuredErrorRaw => '原始錯誤：';

  @override
  String get sessMetaPresented => '已展示';

  @override
  String get sessMetaThisSessionEndedEarlyRetryThe =>
      '当前会话已提前结束。请重试或继续发送更具体的指令。';

  @override
  String get sessMetaToolCallsStoppedForSafety => '工具调用已安全停止';

  @override
  String get sessMetaOpenhandStoppedThisSessionForSafety =>
      '本次会话连续触发了过多轮工具调用，OpenHand 已为安全起见提前停止。这次停止发生在会话控制层，并不是某个具体工具真的执行失败。你可以让助手先总结当前进展，或给出更具体的下一步指令。';

  @override
  String get sessMetaResponseInterrupted => '回答已中断';

  @override
  String get sessMetaTheResponseWasInterruptedWhileStreaming =>
      '本次回答在流式接收过程中异常中断，当前会话已停止。你可以直接重试，或继续发送下一条消息。';

  @override
  String get sessMetaRequestFailed => '请求发送失败';

  @override
  String get sessMetaTheRequestFailedBeforeTheAssistant =>
      '本次请求在发送阶段失败，当前会话未继续执行。你可以检查配置后重试，或继续发送新的消息。';

  @override
  String get sessMetaContinuationFailed => '后续请求失败';

  @override
  String get sessMetaTheSessionFailedWhileRequestingThe =>
      '本次会话在继续执行后续步骤时，请求下一轮模型响应失败。已完成的步骤与工具结果都已保留，你可以直接回复继续/重试，或检查配置后再试。';

  @override
  String get sessMetaSafetyStop => '安全停止';

  @override
  String get sessMetaStreamError => '响应中断';

  @override
  String get sessMetaRequestError => '请求失败';

  @override
  String get sessMetaContinuationError => '后续请求失败';

  @override
  String get sessMetaToolExecutionError => '工具执行失败';

  @override
  String get sessMetaCompressionError => '历史压缩失败';

  @override
  String get sessMetaPromptBlocked => '提示词被拦截';

  @override
  String get sessMetaTitleGenerationError => '标题生成失败';

  @override
  String get sessMetaSessionError => '会话异常';

  @override
  String get auditNoData => '无数据';

  @override
  String get auditCopyJson => '复制 JSON';

  @override
  String get auditCopiedToClipboard => '已复制到剪贴板';

  @override
  String get auditMessageAudit => '消息审计';

  @override
  String get auditClose => '关闭';

  @override
  String get auditOverview => '基本信息';

  @override
  String get auditMessageId => '消息 ID';

  @override
  String get auditSessionId => '会话 ID';

  @override
  String get auditRole => '角色';

  @override
  String get auditKind => '类型';

  @override
  String get auditCharacterCount => '字符数';

  @override
  String get auditStreaming => '是否流式';

  @override
  String get auditDeleted => '是否已删除';

  @override
  String get auditHasError => '是否报错';

  @override
  String get auditTiming => '时间与耗时';

  @override
  String get auditStartedCreated => '开始/创建时间';

  @override
  String get auditEnded => '结束时间';

  @override
  String get auditDurationMs => '耗时 (ms)';

  @override
  String get auditModelTokens => '模型与 Token';

  @override
  String get auditModelId => '模型 ID';

  @override
  String get auditModelLabel => '模型标签';

  @override
  String get auditTotalTokens => '总 Token';

  @override
  String get auditCacheHitRatio => '快取命中率';

  @override
  String get auditPromptTokens => '输入 Token';

  @override
  String get auditCompletionTokens => '输出 Token';

  @override
  String get auditTokenBreakdown => 'Token 明细';

  @override
  String get auditError => '错误信息';

  @override
  String get auditContent => '消息内容';

  @override
  String get auditFullComposedPromptThatWasActually =>
      '以下为该轮用户消息触发时，程序自动拼装后最终发送给 AI 的 prompt 完全体（含系统指令 / 工具目录 / 用户记忆 / 历史上下文 / 用户输入等）。';

  @override
  String get auditWaitingForComposedPromptInjectionAuto =>
      '正在等待本轮最终组合 Prompt 注入（发送中会自动刷新）';

  @override
  String get auditUserRawInput => '用户原始输入';

  @override
  String get auditStructuredPromptTurns => '结构化 Prompt Turns';

  @override
  String get auditNone => '无';

  @override
  String get auditPromptMetadata => 'Prompt Metadata';

  @override
  String get auditRequest => '请求参数';

  @override
  String get auditMethod => '方法';

  @override
  String get auditHeaders => '请求头';

  @override
  String get auditNotCapturedEnableSettingsAiTelemetry =>
      '未捕获（请在设置 → AI → 遥测 中开启调试）';

  @override
  String get auditBodyQueryPath => '请求体 / Query / Path';

  @override
  String get auditRawAiResponse => '原始 AI 响应';

  @override
  String get auditExpandRawResponse => '展开查看原始响应';

  @override
  String get auditNotCapturedDebugDisabledOrResponse => '未捕获：调试未开启或模型未提供原始响应';

  @override
  String get auditAttachments => '附件';

  @override
  String get auditAttachmentList => '附件列表';

  @override
  String get auditNoAttachments => '无附件';

  @override
  String get auditFullMetadata => '完整元数据 (metadata)';

  @override
  String get auditMessageMetadata => '消息元数据';

  @override
  String get auditSessionEnvironment => '会话环境';

  @override
  String get auditEnvironmentSnapshot => '环境快照';

  @override
  String get auditAuditSnapshotCopied => '审计快照已复制';

  @override
  String get auditCopyAuditSnapshot => '复制审计快照';

  @override
  String get auditSessionMetadataSaved => '会话元数据已更新';

  @override
  String get auditSessionAudit => '会话审计';

  @override
  String get auditTemplate => '模板';

  @override
  String get auditCreatedAt => '创建时间';

  @override
  String get auditUpdatedAt => '更新时间';

  @override
  String get auditMessages => '消息数';

  @override
  String get auditLastModel => '最近模型';

  @override
  String get auditTitleEditable => '标题编辑';

  @override
  String get auditSessionTitle => '会话标题';

  @override
  String get auditSaveTitle => '保存标题';

  @override
  String get auditSessionMetadataEditableJson => '会话元数据 (可编辑 JSON)';

  @override
  String get auditSaveWritesBackThroughTheSession =>
      '修改后点击保存将通过会话控制器写回数据库并实时刷新 UI。删除的 key 会被清除。';

  @override
  String get auditSaveMetadata => '保存元数据';

  @override
  String get auditRuntimePromptMetadataReadOnly => '运行时 Prompt 元数据 (只读)';

  @override
  String get auditUsefulForPromptConstructionTroubleshooti =>
      '用于排查本轮消息拼装上下文；自动由系统写入。';

  @override
  String get auditLastPromptMetadata => 'last_prompt_metadata';

  @override
  String get auditNoRuntimePromptMetadataYet => '暂无运行时 Prompt 元数据';

  @override
  String get auditEnvironment => '会话环境';

  @override
  String get auditErrorList => '错误列表';

  @override
  String get auditNoErrorsRecorded => '暂无错误';

  @override
  String get auditTapARowToInspectA => '点击单条可打开消息审计弹窗；支持删除单条消息。';

  @override
  String get auditNoMessages => '暂无消息';

  @override
  String get auditAudit => '审计';

  @override
  String get auditDelete => '删除';

  @override
  String get progExpFESelectOpenedFile => '定位到已打开文件';

  @override
  String get progExpFEExpandSelected => '展开选中目录';

  @override
  String get progExpFECollapseAll => '全部折叠';

  @override
  String get progExpFETypeASymbolNameToSearch => '输入符号名后即可在当前工作区内跨文件搜索。';

  @override
  String get progExpFENoWorkspaceSymbolBackendIsAvailable =>
      '当前文件没有可用的工作区符号后端。';

  @override
  String get progExpFENoMatchingWorkspaceSymbolsWereFound => '没有找到匹配的工作区符号。';

  @override
  String get progExpFEFetchingWorkspaceSymbolsFailedConfirmTha =>
      '读取工作区符号失败，请确认对应语言服务器支持 workspace/symbol。';

  @override
  String get progExpFEThisFileIsStillInLarge =>
      '当前文件仍处于大文件预览模式，符号栏暂使用本地提取以保持响应速度。';

  @override
  String get progExpFENoLspSymbolBackendIsAvailable =>
      '当前文件没有可用的 LSP 符号后端，已回退到本地符号提取。';

  @override
  String get progExpFETheLspServerReturnedAnEmpty => 'LSP 已返回空符号列表。';

  @override
  String get progExpFEFetchingLspSymbolsFailedSoThe =>
      '读取 LSP 符号失败，已回退到本地符号提取。';

  @override
  String get progExpFERenameSymbol => '重命名符号';

  @override
  String get progExpFEReviewTheDiffForThisRename => '先查看这次重命名将影响的差异，再决定是否应用。';

  @override
  String get progExpFETheRenameWasCancelledAndNo => '已取消本次重命名，未写入任何修改。';

  @override
  String get progExpFETheSymbolAtTheCurrentCursor => '当前光标位置不支持重命名。';

  @override
  String get progExpFETheLanguageServerDidNotReturn => '语言服务器没有返回需要应用的修改。';

  @override
  String get progExpFECodeActions => '代码操作';

  @override
  String get progExpFENoCodeActionsAreAvailableAt => '当前光标位置没有可用的代码操作。';

  @override
  String get progExpFEReviewTheDiffFromThisCode => '先预览该代码操作将要写入的差异，再决定是否应用。';

  @override
  String get progExpFEIfTheLanguageServerCommandRequests =>
      '如果语言服务器命令在执行过程中请求写入修改，也会先展示差异预览。';

  @override
  String get progExpFETheCodeActionWasCancelledAnd => '已取消本次代码操作，未写入任何修改。';

  @override
  String get progExpFEExecutedTheLanguageServerCommand => '已执行语言服务器命令。';

  @override
  String get progExpFESomeLanguageServerRequestedEditsWere => '有语言服务器请求的修改被跳过。';

  @override
  String get progExpFEThisCodeActionDidNotReturn => '该代码操作没有返回可应用的编辑。';

  @override
  String get progExpFEQuickFix => '快速修复';

  @override
  String get progExpFENoQuickFixesAreAvailableFor => '当前诊断位置没有可用的快速修复。';

  @override
  String get progExpFENoCodeActionsAreAvailableFor => '当前诊断位置没有可用的代码操作。';

  @override
  String get progExpFENoQuickFixesAreAvailableFor2 => '当前诊断行没有可用的快速修复。';

  @override
  String get progExpFETheCurrentFileIsStillLoading =>
      '当前文件尚未完成加载，暂时无法执行 LSP 操作。';

  @override
  String get progExpFEThisFileIsStillInLarge2 =>
      '当前文件仍处于大文件预览模式，请先切换到完整编辑器后再执行 LSP 跳转。';

  @override
  String get progExpFETheCurrentFileIsStillLoading2 =>
      '当前文件尚未完成加载，暂时无法执行文档级编辑操作。';

  @override
  String get progExpFEThisFileIsStillInLarge3 =>
      '当前文件仍处于大文件预览模式，请先切换到完整编辑器后再执行格式化。';

  @override
  String get progExpFEFormatDocument => '格式化文档';

  @override
  String get progExpFETheCurrentFileIsNotReady => '当前文件尚未准备好，稍后再试。';

  @override
  String get progExpFETheFormatterDidNotReturnAny => '格式化器没有返回可应用的修改。';

  @override
  String get progExpFEFormattingProducedTheSameContentSo =>
      '格式化结果与当前内容一致，没有产生新的文本变更。';

  @override
  String get progExpFEGoToDefinition => '定义跳转';

  @override
  String get progExpFENoDefinitionWasFoundAtThe => '当前光标位置没有找到定义。';

  @override
  String get progExpFEMultipleDefinitionsWereFoundChooseA =>
      '找到多个定义结果，请选择要跳转的位置。';

  @override
  String get progExpFEFindReferences => '引用查找';

  @override
  String get progExpFENoReferencesWereFoundAtThe => '当前光标位置没有找到引用。';

  @override
  String get progExpFEHoverInfo => '悬浮信息';

  @override
  String get progExpFEThereIsNoHoverInformationAt => '当前光标位置没有可显示的悬浮信息。';

  @override
  String get progExpFELspBackend => 'LSP 后端';

  @override
  String get progExpFEReResolveTheBackendForThe => '重新解析当前文件后端';

  @override
  String get progExpFEInspectBackendDetails => '查看后端详情';

  @override
  String get progExpFECloseEsc => '关闭 (Esc)';

  @override
  String get progExpFEToggleComment => '切换注释';

  @override
  String get progExpFEThisLanguageDoesNotHaveA => '当前语言暂未配置注释策略，无法执行注释切换。';

  @override
  String get progExpFEGoToImplementation => '跳转到实现';

  @override
  String get progExpFESignatureHelp => '参数信息';

  @override
  String get progExpFEThereIsNoSignatureHelpAvailable => '当前光标位置没有可显示的参数签名信息。';

  @override
  String get progExpFEPreviousMatch => '上一个结果';

  @override
  String get progExpFENextMatch => '下一个结果';

  @override
  String get progExpFEMatchCase => '区分大小写';

  @override
  String get progExpFEShowReplace => '显示替换';

  @override
  String get progExpFEReplaceCurrent => '替换当前结果';

  @override
  String get progExpFEReplaceAll => '全部替换';

  @override
  String get progExpFECurrentFileSymbols => '当前文件符号';

  @override
  String get progExpFEWorkspaceSymbols => '工作区符号';

  @override
  String get progExpFERefreshDiagnostics => '刷新诊断';

  @override
  String get progExpFESymbols => '符号';

  @override
  String get progExpFESymbolNavigationShiftCmdCtrlO =>
      '符号导航 (Shift+Cmd/Ctrl+O)';

  @override
  String get progExpFEWorkspace => '全局符号';

  @override
  String get progExpFEWorkspaceSymbolSearchCmdCtrlT => '工作区符号搜索 (Cmd/Ctrl+T)';

  @override
  String get progExpFEShowDiagnosticsForTheCurrentFile => '显示当前文件诊断';

  @override
  String get progExpFEInspectTheLspBackendBoundTo => '查看当前文件绑定的 LSP 后端';

  @override
  String get progExpFEDef => '定义';

  @override
  String get progExpFEGoToDefinitionF12CmdCtrl => '定义跳转 (F12 / Cmd/Ctrl+B)';

  @override
  String get progExpFERefs => '引用';

  @override
  String get progExpFEFindReferencesShiftF12CmdCtrl =>
      '引用查找 (Shift+F12 / Cmd/Ctrl+Shift+B)';

  @override
  String get progExpFEHover => '悬浮';

  @override
  String get progExpFEHoverInfoCmdCtrlI => '悬浮信息 (Cmd/Ctrl+I)';

  @override
  String get progExpFERename => '重命名';

  @override
  String get progExpFERenameSymbolF2 => '重命名符号 (F2)';

  @override
  String get progExpFEActions => '操作';

  @override
  String get progExpFECodeActionsCmdCtrl => '代码操作 (Cmd/Ctrl+.)';

  @override
  String get progExpFEFormat => '格式化';

  @override
  String get progExpFENoImplementationWasFoundAtThe => '当前光标位置没有找到实现。';

  @override
  String get progExpFEMultipleImplementationsFoundChooseATarge =>
      '找到多个实现，请选择要跳转的位置。';

  @override
  String get progExpFERefactor => '重构';

  @override
  String get progExpFEReviewTheChangesBeforeApplying => '查看此次重构将影响的差异，再决定是否应用。';

  @override
  String get progExpFESaveFile => '保存文件';

  @override
  String get progExpFECloseEditorReturnToSession => '关闭编辑器，返回会话';

  @override
  String get progExpFEShowQuickFixesForThisDiagnostic => '显示该诊断行的快速修复';

  @override
  String get progExpFELargeFilePerformanceModeIsActive =>
      '已启用大文件性能模式：使用虚拟化只读预览，避免整篇文本布局导致卡顿。';

  @override
  String get progExpFEOpenFullEditorAnyway => '仍然打开完整编辑器';

  @override
  String get settingsShortcuts => '快捷键';

  @override
  String get settingsConfigureKeyCombinationsForCommonActions =>
      '为常用操作配置组合键。当前最多支持同时按下 4 个按键。';

  @override
  String get settingsBuiltInTools => '内建工具';

  @override
  String get settingsCrons => '定时任务';

  @override
  String get settingsControlsRetentionAndColdStartCleanup =>
      '控制定时任务执行历史的保留与冷启动清理。清理 worker 仅在冷启动后异步运行一次，带有超时兜底、独享运行锁、异常全部 silentLog，避免资源泄露与无限重试。';

  @override
  String get settingsHermesTalker => 'Hermes Talker';

  @override
  String get settingsConfigureHermesTalkerSelfLearningEvery =>
      '配置 Hermes Talker 线程模板的自主学习：每 5 分钟扫描最近 7 天的会话，在后台派发受限子 Agent 更新记忆与技能。';

  @override
  String get settingsEditor => '编辑器';

  @override
  String get settingsManagePerLanguageLspBackendsInstall =>
      '管理各编程语言的 LSP 后端、安装根路径与下载辅助配置。保存后的配置会直接用于文件编辑器内的跳转、诊断、重命名和代码操作。';

  @override
  String get settingsAppData => '应用数据';

  @override
  String get settingsPerResponseToolCallLimit => '单轮工具调用上限';

  @override
  String get settingsSaveLimit => '保存上限';

  @override
  String get settingsSequentialToolRoundLimit => '连续工具轮次上限';

  @override
  String get settingsSessionSettings => '会话设置';

  @override
  String get settingsConfigureDefaultBehaviourForNewSessions =>
      '配置新會話的預設行為，包括逾時時間、標題取得、預設模式與權限。';

  @override
  String get settingsSendTimeoutS => '发送超时（秒）';

  @override
  String get settingsMaximumWaitTimeToEstablishThe =>
      '建立 HTTP 连接并完成请求发送的最大等待时间，默认 60 秒。';

  @override
  String get settingsSaveTimeout => '保存超时';

  @override
  String get settingsResponseTimeoutS => '响应超时（秒）';

  @override
  String get settingsMaximumWaitForACompleteResponse =>
      '非流式请求等待完整响应的最大时间，默认 120 秒。';

  @override
  String get settingsStreamIdleTimeoutS => '等待超时（秒）';

  @override
  String get settingsMaximumIdleWaitBetweenStreamChunks =>
      '流式响应中两次数据块之间的最大空闲等待时间，超时将中断请求并显示\"Request timed out.\"，默认 120 秒。';

  @override
  String get settingsAutoTitle => '自動取得標題';

  @override
  String get settingsWhenEnabledATitleIsAutomatically =>
      '開啟後，新會話送出第一則有效文字訊息時會自動取得會話標題。';

  @override
  String get settingsTitleFetchMode => '取得標題方式';

  @override
  String get settingsTitleFetchModeDescription =>
      '非同步不會阻塞首輪回覆；同步會先取得標題，再送出首輪 AI 請求。';

  @override
  String get settingsTitleFetchModeAsync => '非同步';

  @override
  String get settingsTitleFetchModeSync => '同步';

  @override
  String get settingsDefaultSessionMode => '默认会话模式';

  @override
  String get settingsDefaultInteractionModeForNewSessions =>
      '新会话的默认交互模式：对话（Chat）或规划（Plan）。';

  @override
  String get settingsChat => '对话';

  @override
  String get settingsPlan => '规划';

  @override
  String get settingsDefaultFullAccess => '默认全访问权限';

  @override
  String get settingsWhenEnabledNewSessionsStartIn =>
      '开启后，新会话将默认使用全访问权限模式，允许 AI 直接执行文件与命令操作而无需逐一确认。';

  @override
  String get settingsUserProfile => '用户画像';

  @override
  String get settingsMaintainAGlobalUserProfileLanguage =>
      '维护用于全局会话的用户画像（语言风格、关注领域、交流偏好等）。设置非空时，所有线程模板的内建系统提示词都会自动携带画像上下文，使 AI 回复更贴近你的习惯；自我学习也会增量更新这份画像。';

  @override
  String get settingsModelProviderManagement => '模型提供商管理';

  @override
  String get settingsAddSelectTestAndMaintainModel =>
      '新增、选择、测试并维护当前可用的模型提供商配置。每个提供商可包含多个模型。';

  @override
  String get settingsCompressionTrigger => '压缩触发阈值';

  @override
  String get settingsOnceTheUncompressedHistoryInA =>
      '当线程中尚未被压缩的历史消息字符总数超过这个值时，系统会生成新的摘要检查点。';

  @override
  String get settingsToolCallOutputCompressionThreshold => '工具调用输出压缩阈值';

  @override
  String get settingsWhenAToolCallReturnsMore =>
      '僅用於產生壓縮檢查點：超過閾值的歷史工具結果會轉為結構化摘要。普通對話始終向模型交付完整結果。預設 1024。';

  @override
  String get settingsDefaultsTo40IfOneAssistant =>
      '默认 40 次。一次人机对话响应过程中，如果工具调用总次数超过这个阈值，系统会追加警告消息并安全终止本轮响应。';

  @override
  String get settingsDefaultsTo24RoundsIfThe =>
      '默认 24 轮。一次会话中，如果助手在工具执行后又连续请求下一轮工具，达到这个轮次数时系统会安全停止，避免陷入无限工具回环。';

  @override
  String get settingsImageSizeLimit => '图片大小上限';

  @override
  String get settingsDefaultsTo1mbImageAttachmentsLarger =>
      '默认 1MB。用户附加的图片若超过这个大小，会在弹出图片编辑器之前先按比例自动压缩，并最终落盘到该上限以内，避免会话与提示词膨胀。';

  @override
  String get settingsCostControl => '成本控制';

  @override
  String get settingsReduceTokenCostsByFreezingThe =>
      '透過穩定 Prompt 靜態前綴與協議層快取提示來降低 token 成本。開啟後：第一則有效使用者訊息開始收到 AI 回應時，會鎖定服務商、模型與推理強度；Prompt Builder 會盡量保持系統提示、工具目錄、記憶、指令等穩定前置；Anthropic 協議會注入 cache_control 斷點，OpenAI-compatible 請求會使用穩定快取親和鍵與 messages 置尾布局。';

  @override
  String get settingsEnableInputCache => '启用输入缓存';

  @override
  String get settingsDisabledByDefaultWhenEnabledEvery =>
      '預設開啟。關閉後不會注入協議層快取提示，也不會執行模型鎖定等輸入快取保護。若要最大化命中率，請避免在會話中途頻繁修改工具、技能、MCP、記憶或指令。';

  @override
  String get settingsCacheBreakpointUpdateMode => '歷史候選點更新模式';

  @override
  String get settingsChooseTheSlidingUnitForThe =>
      '穩定錨點、上一請求尾錨和目前尾錨會自動優先保留；此設定僅決定剩餘預算如何選擇歷史候選點。';

  @override
  String get settingsByMessageCountUserAssistant => '按消息条数 (user+assistant)';

  @override
  String get settingsByUserMessageCountOnly => '按用户消息条数';

  @override
  String get settingsByAccumulatedTokens => '按累计 tokens';

  @override
  String get settingsCacheBreakpointUpdateInterval => '歷史候選點更新間隔';

  @override
  String get settingsDefault10MeaningDependsOnThe =>
      '預設 10，僅用於自動選擇歷史候選點。含義隨上方模式變化：訊息數 / 使用者訊息數 / tokens 閾值。';

  @override
  String get settingsSave => '保存';

  @override
  String get settingsCacheBreakpointCount => '缓存断点数量';

  @override
  String get settingsDefault4Range14Anthropic =>
      '預設 4，範圍 1-4。Anthropic 協議依穩定系統/工具錨點、上一請求尾錨、目前尾錨、歷史候選點的順序使用預算，每個請求最多支援 4 個 cache_control 斷點。OpenAI-compatible 服務商不會注入此標記。';

  @override
  String get settingsCommandSafety => '命令安全';

  @override
  String get settingsControlWriteCommandConfirmationForBash =>
      '控制 bash 工具是否需要写命令确认，并集中管理禁止命令规则。';

  @override
  String get settingsWriteCommandConfirmation => '写命令确认';

  @override
  String get settingsEnabledByDefaultWhenTheAi =>
      '默认开启。AI 调用 bash 工具执行可能修改文件或系统状态的命令时，会先弹窗等待你确认。';

  @override
  String get settingsAllowCommandList => '允许命令列表';

  @override
  String get settingsMatchingWriteLikeBashCommandsSkip =>
      '匹配到的写类 bash 命令会跳过确认弹窗直接执行。只适合长期明确放行的稳定命令模式。';

  @override
  String get settingsAddAllowRule => '新增允许规则';

  @override
  String get settingsNoAllowRulesConfigured => '当前没有允许命令规则';

  @override
  String get settingsAddARuleToLetMatching => '新增规则后，匹配到的写命令将跳过确认弹窗。';

  @override
  String get settingsDenyCommandList => '禁止命令列表';

  @override
  String get settingsMatchingBashCommandsAreBlockedBefore =>
      '匹配到的 bash 命令将不会真正执行，而是把“被用户禁止”这一结果直接返回给模型。支持正则和简单通配写法，例如 `rm *`。';

  @override
  String get settingsAddRule => '新增规则';

  @override
  String get settingsNoDenyRulesConfigured => '当前没有禁止命令规则';

  @override
  String get settingsAddARuleToBlockMatching => '新增规则后，匹配到的 bash 命令会被直接拦截。';

  @override
  String get settingsTelemetry => '遥测';

  @override
  String get settingsWhenEnabledOpenhandCapturesRawAi =>
      '开启后会捕获每条 AI 消息的原始响应、请求参数、耗时、错误等调试数据，方便在消息/会话审计弹窗中排查问题。';

  @override
  String get settingsDebugMode => '开启调试';

  @override
  String get settingsOffByDefaultWhenEnabledEvery =>
      '默认关闭。开启后，在所有线程模板的消息卡片上鼠标悬停/聚焦时会显示【审计】按钮，会话顶部也会新增会话审计入口。';

  @override
  String get settingsCaptureRawPayload => '捕获原始响应';

  @override
  String get settingsEnabledByDefaultOnlyActiveWhen =>
      '默认开启。仅当调试开启时生效，将 AI 响应的原始 JSON/SSE 片段一并写入消息元数据，便于审计。';

  @override
  String get settingsCaptureEnvironment => '捕获环境数据';

  @override
  String get settingsOffByDefaultOnlyActiveWhen =>
      '默认关闭。仅当调试开启时生效。将工作目录、平台信息、进程环境变量（可能含敏感令牌）等写入消息元数据，便于深度排查，请谨慎开启。';

  @override
  String get settingsShortcutBindings => '快捷键绑定';

  @override
  String get settingsClickRecordThenPressTheNew =>
      '点击录制后，按下新的组合键即可更新绑定。模型切换和会话切换会自动绕圈循环。';

  @override
  String get settingsShortcutRecord => '錄製';

  @override
  String get settingsShortcutResetToDefault => '恢復預設';

  @override
  String get settingsShortcutMaxKeysError => '最多支援同時按下 4 個按鍵。';

  @override
  String get settingsShortcutRecorderBody => '按下新的組合鍵即可更新綁定。最多支援同時按下 4 個按鍵。';

  @override
  String get settingsShortcutRecorderTip => '提示：至少需要一個非修飾鍵，例如 Enter、P、方向鍵。';

  @override
  String get settingsAutoCleanupExecutionHistory => '自动清理执行历史';

  @override
  String get settingsOnEveryColdStartAnAsync =>
      '应用每次冷启动后，会异步启动一次清理 worker，删除超过保留天数的历史记录。worker 自带 single-flight、超时兜底与异常 silentLog，绝不无限重试或阻塞 UI。';

  @override
  String get settingsEnableSelfLearning => '启用自主学习';

  @override
  String get settingsWhenOffTheSchedulerSkipsEvery =>
      '关闭后，后台调度器跳过所有 Hermes Talker 会话；系统 Cron 条目会保留但不再派发子 Agent。';

  @override
  String get settingsShowSelfLearningMessages => '显示自我学习消息';

  @override
  String get settingsWhenOffSelfLearningCardsAre =>
      '关闭后，对话中不再展示\"自我学习\"卡片（后台学习仍会运行）。默认开启。';

  @override
  String get settingsToolCatalogOverview => '工具目录总览';

  @override
  String get settingsResetAll => '重置全部';

  @override
  String get settingsEnableAll => '全部启用';

  @override
  String get settingsDisableAll => '全部禁用';

  @override
  String get settingsNoBuiltInToolConfigurations => '没有内建工具配置';

  @override
  String get settingsClickResetAllToRestoreThe => '点击\"重置全部\"恢复默认工具列表。';

  @override
  String get settingsResetBuiltInToolConfigs => '重置内建工具配置';

  @override
  String get settingsCancel => '取消';

  @override
  String get settingsReset => '重置';

  @override
  String get settingsDeleteCustomTool => '删除自定义工具';

  @override
  String get settingsDelete => '删除';

  @override
  String get settingsSendTimeoutSaved => '发送超时时间已保存。';

  @override
  String get settingsResponseTimeoutSaved => '响应超时时间已保存。';

  @override
  String get settingsStreamIdleTimeoutSaved => '等待超时时间已保存。';

  @override
  String get settingsCacheBreakpointUpdateIntervalSaved => '歷史候選點更新間隔已儲存';

  @override
  String get settingsCacheBreakpointCountSaved => '缓存断点数量已保存';

  @override
  String get settingsCacheBreakpointPositions => '歷史快取候選點';

  @override
  String get settingsCacheBreakpointPositionsSaved => '歷史快取候選點已儲存';

  @override
  String get cacheBarTopDescription =>
      '彩色段僅用於說明 prompt 結構。P 插樁表示歷史訊息流中的候選位置；最右側虛線插樁表示目前請求尾錨。協議層會先保留穩定錨點和連續尾錨，剩餘預算再採用候選點。';

  @override
  String get cacheBarSectionSysLabel => '[0] 系統指令';

  @override
  String get cacheBarSectionDevLabel => '[1] 開發者指令';

  @override
  String get cacheBarSectionToolsLabel => '[2] 工具目錄';

  @override
  String get cacheBarSectionStateLabel => '[3s/3d] 會話狀態';

  @override
  String get cacheBarSectionMemoryLabel => '[4] 使用者記憶';

  @override
  String get cacheBarSectionUserInstLabel => '[4.5] 使用者指令';

  @override
  String get cacheBarSectionSummaryLabel => '[5] 會話摘要';

  @override
  String get cacheBarSectionHistoryLabel => '歷史訊息';

  @override
  String get cacheBarSectionLatestLabel => '尾部 / 最新輪次';

  @override
  String get cacheBarSectionSysSummary =>
      '模板系統指令、工作區指令與執行時環境快照（OS / cwd / 倉庫摘要）。';

  @override
  String get cacheBarSectionSysCacheHint => '快取友好：跨輪極穩定，最適合作為第一個斷點。';

  @override
  String get cacheBarSectionDevSummary => '當前提示詞模板的開發者指令（行為規則與輸出格式約束）。';

  @override
  String get cacheBarSectionDevCacheHint => '快取友好：會話內極少變動。';

  @override
  String get cacheBarSectionToolsSummary =>
      '內建工具目錄、MCP 能力與 Skill 載入器（含 DSML 呼叫約束）。';

  @override
  String get cacheBarSectionToolsCacheHint => '較穩定：除非工具註冊表變化，否則可放心命中快取。';

  @override
  String get cacheBarSectionStateSummary => '會話元資料 JSON：計數器、Todo、計畫標記、附件等。';

  @override
  String get cacheBarSectionStateCacheHint => '易變：每輪計數器都會更新，斷點放此處易失效。';

  @override
  String get cacheBarSectionMemorySummary => '長期使用者記憶事實，作為已掌握的常識自然融入。';

  @override
  String get cacheBarSectionMemoryCacheHint => '相對穩定：僅在記憶條目變更時才會失效。';

  @override
  String get cacheBarSectionUserInstSummary => '使用者預設的可複用指令片段（專案級權威指引）。';

  @override
  String get cacheBarSectionUserInstCacheHint => '穩定：極少修改，斷點落在它後面較穩妥。';

  @override
  String get cacheBarSectionSummarySummary => '較早會話的壓縮摘要 + 最近聊天紀要。';

  @override
  String get cacheBarSectionSummaryCacheHint => '緩慢演化：僅在壓縮重生成時刷新。';

  @override
  String get cacheBarSectionHistorySummary => '當前會話中的歷史訊息（使用者 / 助手 / 工具結果）。';

  @override
  String get cacheBarSectionHistoryCacheHint => '僅追加：放在歷史中段的斷點能跨多輪命中尾部新增內容。';

  @override
  String get cacheBarSectionLatestSummary => '當前正在回答的使用者訊息（含附件元資料）。';

  @override
  String get cacheBarSectionLatestCacheHint =>
      '每輪變化：目前請求尾錨覆蓋此區域，上一請求尾錨負責延續快取命中。';

  @override
  String get cacheBarDynamicTooltip => '目前請求尾錨：始終跟隨最新訊息。';

  @override
  String get cacheBarDynamicSuffix => '（目前尾錨）';

  @override
  String get cacheBarResetEven => '重設為均勻分佈';

  @override
  String get settingsAiBudgetUsdPerSession => '單會話預算（USD）';

  @override
  String get settingsAiBudgetUsdPerSessionBody =>
      '0 表示關閉。當某個會話累計估算成本超過該上限時，會話元資料對話框中會以警示色提示，僅為軟提醒，不會中斷對話或限制發送。';

  @override
  String get settingsAiBudgetUsdPerSessionInvalid => '請輸入 0 到 100000 之間的非負數。';

  @override
  String get settingsAiBudgetUsdPerSessionSaved => '單會話預算已保存';

  @override
  String sessionMetadataOverBudgetNotice(String total, String budget) {
    return '當前會話估算成本 $total 已超出預算 $budget。僅為提示，不影響發送。';
  }

  @override
  String get settingsEnterAToolCallLimitGreater => '请输入大于 0 的工具调用上限。';

  @override
  String get settingsThePerResponseToolCallLimit => '单轮工具调用上限已保存。';

  @override
  String get settingsEnterASequentialToolRoundLimit => '请输入大于 0 的连续工具轮次上限。';

  @override
  String get settingsTheSequentialToolRoundLimitHas => '连续工具轮次上限已保存。';

  @override
  String get settingsDeleteDenyRule => '删除禁止命令规则';

  @override
  String get settingsTheDenyCommandRuleHasBeen => '禁止命令规则已删除。';

  @override
  String get settingsDeleteAllowRule => '删除允许命令规则';

  @override
  String get settingsTheAllowCommandRuleHasBeen => '允许命令规则已删除。';

  @override
  String get settingsTheShortcutHasBeenUpdated => '快捷键已更新。';

  @override
  String get settingsTheEditorShortcutHasBeenUpdated => '编辑器快捷键已更新。';

  @override
  String get settingsSendMessage => '发送消息';

  @override
  String get settingsCollapseOrExpandComposer => '折叠或展开输入框';

  @override
  String get settingsPreviousModel => '上一个模型';

  @override
  String get settingsNextModel => '下一个模型';

  @override
  String get settingsToggleAutoFollow => '开关自动滚动';

  @override
  String get settingsPreviousSession => '上一个会话';

  @override
  String get settingsNextSession => '下一个会话';

  @override
  String get settingsSaveFile => '保存文件';

  @override
  String get settingsTriggerCompletion => '触发智能补全';

  @override
  String get settingsShowSignatureHelp => '显示签名帮助';

  @override
  String get settingsFind => '查找';

  @override
  String get settingsFindAndReplace => '查找替换';

  @override
  String get settingsGoToLine => '跳转到行';

  @override
  String get settingsDocumentSymbols => '文档符号';

  @override
  String get settingsWorkspaceSymbols => '全局符号';

  @override
  String get settingsGoToDefinition => '跳转到定义';

  @override
  String get settingsFindReferences => '查找引用';

  @override
  String get settingsGoToImplementation => '跳转到实现';

  @override
  String get settingsShowHoverInfo => '显示悬浮信息';

  @override
  String get settingsRenameSymbol => '重命名符号';

  @override
  String get settingsCodeActions => '代码操作';

  @override
  String get settingsFormatDocument => '格式化文档';

  @override
  String get settingsDefaultsToCtrlEnterAndTriggers =>
      '默认 Ctrl + Enter，仅在聊天输入框准备好时触发发送按钮。';

  @override
  String get settingsDefaultsToCtrlPForQuickly => '默认 Ctrl + P，用于快速折叠或展开输入框。';

  @override
  String get settingsDefaultsToCtrlLeftAndWraps =>
      '默认 Ctrl + ←，向前切换模型，切到头后自动绕回末尾。';

  @override
  String get settingsDefaultsToCtrlRightAndWraps =>
      '默认 Ctrl + →，向后切换模型，切到末尾后自动绕回开头。';

  @override
  String get settingsDefaultsToCtrlSForToggling => '默认 Ctrl + S，开关自动滚动模式。';

  @override
  String get settingsDefaultsToCtrlUpAndWraps => '默认 Ctrl + ↑，切换到上一个会话并支持绕圈。';

  @override
  String get settingsDefaultsToCtrlDownAndWraps => '默认 Ctrl + ↓，切换到下一个会话并支持绕圈。';

  @override
  String get settingsUndoLastFileMutation => '復原最近一次檔案變動';

  @override
  String get settingsDefaultsToCtrlShiftZForUndo =>
      '默認 Ctrl + Shift + Z，復原當前會話 ledger 中最新一條可復原的檔案變動。';

  @override
  String get auditDeleteMessage => '删除消息';

  @override
  String get auditDeleteThisMessageThisCannotBe => '确认删除该消息？此操作不可撤销。';

  @override
  String get auditCancel => '取消';

  @override
  String get settingsManageTheBuiltInAiTools =>
      '管理应用内置的 AI 内建工具。可调整每个工具的启用状态、名称、描述、Schema、优先级、排序、加载策略和其他参数。';

  @override
  String get settingsManageTheLocalFilesAndDatabase =>
      '管理 OpenHand 在本地占用的文件与数据库体积。所有清理动作都在后台 worker 中运行，不会阻塞主线程；每个分类均需二次确认后才会真正删除。';

  @override
  String get settingsThisWillRestoreAllBuiltIn =>
      '这将把所有内建工具配置恢复为出厂默认值，包括名称、描述、Schema 覆盖、优先级、排序和加载策略。此操作不可撤销。';

  @override
  String get tlCallUnwrap => '取消换行';

  @override
  String get tlCallWrapLines => '自动换行';

  @override
  String get tlCallViewCompressedContent => '查看压缩内容';

  @override
  String get tlCallViewFullContent => '查看完整内容';

  @override
  String get tlCallPreparing => '准备执行';

  @override
  String get tlCallPreparingAlt => '准备调用';

  @override
  String get tlCallRunningAlt => '调用中';

  @override
  String get tlCallCompleted => '执行完成';

  @override
  String get tlCallCompletedAlt => '调用完成';

  @override
  String get tlCallTimedOutAlt => '调用超时';

  @override
  String get tlCallFailedAlt => '调用失败';

  @override
  String tlCallFailedToOpenFileLocationError(Object error) {
    return '打开文件位置失败：$error';
  }

  @override
  String tlCallMemoryitemsLengthMemoriesUpdated(Object memoryItems_length) {
    return '$memoryItems_length 条记忆已更新';
  }

  @override
  String tlCallProfileitemsLengthProfileChanges(Object profileItems_length) {
    return '$profileItems_length 项画像已更新';
  }

  @override
  String tlCallSkillitemsLengthSkillsUpdated(Object skillItems_length) {
    return '$skillItems_length 个技能已更新';
  }

  @override
  String get tlCallAiThinkingStreaming => 'AI 思考（生成中）';

  @override
  String get tlCallAiThinking => 'AI 思考';

  @override
  String get tlCallAiResponseStreaming => 'AI 响应（生成中）';

  @override
  String get tlCallAiResponse => 'AI 响应';

  @override
  String tlCallAndItemsLength3More(Object items_length_3, Object items_length) {
    return ' 等 $items_length 项';
  }

  @override
  String tlCallSecondsSAgo(Object seconds) {
    return '$seconds秒前';
  }

  @override
  String tlCallMinutesMAgo(Object minutes) {
    return '$minutes分钟前';
  }

  @override
  String tlCallHoursHAgo(Object hours) {
    return '$hours小时前';
  }

  @override
  String tlCallDaysDAgo(Object days) {
    return '$days天前';
  }

  @override
  String sessMetaPlanPlanindex(Object planIndex) {
    return '计划 #$planIndex';
  }

  @override
  String sessMetaTheCurrentSequentialToolRoundLimit(Object configuredLimit) {
    return ' 当前连续工具轮次上限为 $configuredLimit。';
  }

  @override
  String auditInvalidJsonErrorMessage(Object error_message) {
    return 'JSON 解析失败：$error_message';
  }

  @override
  String auditSaveFailedError(Object error) {
    return '保存失败：$error';
  }

  @override
  String auditRecentErrorsSessionRecenterrorsLength(
    Object session_recentErrors_length,
  ) {
    return '最近错误 ($session_recentErrors_length)';
  }

  @override
  String auditMessagesSessionMessagesLength(Object session_messages_length) {
    return '消息列表 ($session_messages_length)';
  }

  @override
  String progExpFEAppliedEditsLengthFormattingEdits(Object edits_length) {
    return '已应用 $edits_length 处格式化修改。';
  }

  @override
  String progExpFEFormatTheCurrentFileFormatshortcut(Object formatShortcut) {
    return '格式化当前文件 ($formatShortcut)';
  }

  @override
  String progExpFENoCodeactionkindRefactoringIsAvailableAt(
    Object codeActionKind,
  ) {
    return '当前位置没有可用的\"$codeActionKind\"重构操作。';
  }

  @override
  String get progExpFEHideFileBrowser => '隐藏文件浏览器';

  @override
  String get progExpFEShowFileBrowser => '显示文件浏览器';

  @override
  String settingsRetentionWindowRetentionDayS(Object retention) {
    return '保留天数：$retention 天';
  }

  @override
  String settingsRangeMinrMaxrDaysDefault7(Object minR, Object maxR) {
    return '范围 $minR–$maxR 天，默认 7 天。下次冷启动时生效。';
  }

  @override
  String settingsConcurrentWorkersConcurrency(Object concurrency) {
    return '并发 Worker 数：$concurrency';
  }

  @override
  String settingsCapsHowManySessionsCanBe(Object minC, Object maxC) {
    return '限制单轮 tick 同时派发的会话数 ($minC–$maxC)。默认 5。';
  }

  @override
  String settingsSortedLengthBuiltInToolsEnabledcount(
    Object sorted_length,
    Object enabledCount,
  ) {
    return '当前共 $sorted_length 个内建工具，已启用 $enabledCount 个。可调整每个工具的名称、描述、Schema、优先级、排序和加载策略等。';
  }

  @override
  String settingsAreYouSureYouWantTo(Object config_effectiveName) {
    return '确定要删除 \"$config_effectiveName\" 吗？此操作不可撤销。';
  }

  @override
  String settingsEnterAValueBetweenMinAnd(Object min, Object max) {
    return '请输入 $min–$max 之间的秒数。';
  }

  @override
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn(
    Object AppSettingsSnapshot_minAiInputCacheUpdateInterval,
    Object AppSettingsSnapshot_maxAiInputCacheUpdateInterval,
  ) {
    return '请输入 $AppSettingsSnapshot_minAiInputCacheUpdateInterval 到 $AppSettingsSnapshot_maxAiInputCacheUpdateInterval 之间的整数';
  }

  @override
  String settingsPleaseEnterAnIntegerBetweenAppsettingssn2(
    Object AppSettingsSnapshot_minAiInputCacheBreakpointCount,
    Object AppSettingsSnapshot_maxAiInputCacheBreakpointCount,
  ) {
    return '请输入 $AppSettingsSnapshot_minAiInputCacheBreakpointCount 到 $AppSettingsSnapshot_maxAiInputCacheBreakpointCount 之间的整数';
  }

  @override
  String settingsDragTheThumbcountThumbsToPosition(Object thumbCount) {
    return '拖動 $thumbCount 個圓點設定歷史訊息候選位置（0%-100%）。穩定錨點與連續尾錨優先占用斷點預算；最右側圓點固定為目前請求尾錨。';
  }

  @override
  String get settingsTheDenyCommandRuleHasBeen2 => '禁止命令规则已更新。';

  @override
  String get settingsTheAllowCommandRuleHasBeen2 => '允许命令规则已更新。';

  @override
  String settingsDefaultsToDefaultlabelAndSavesThe(Object defaultLabel) {
    return '默认 $defaultLabel，保存当前正在编辑的文件。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndOpensThe(Object defaultLabel) {
    return '默认 $defaultLabel，主动弹出智能补全候选列表。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsMethod(Object defaultLabel) {
    return '默认 $defaultLabel，显示当前调用位置的方法签名、参数解释和文档摘要。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe(Object defaultLabel) {
    return '默认 $defaultLabel，打开或关闭查找面板。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe2(Object defaultLabel) {
    return '默认 $defaultLabel，打开或关闭替换面板。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe3(Object defaultLabel) {
    return '默认 $defaultLabel，打开或关闭跳转到行面板。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe4(Object defaultLabel) {
    return '默认 $defaultLabel，打开或关闭当前文件的符号列表。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndTogglesThe5(Object defaultLabel) {
    return '默认 $defaultLabel，打开或关闭全局符号检索面板。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndJumpsTo(Object defaultLabel) {
    return '默认 $defaultLabel，跳转到当前符号定义。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndFindsReferences(Object defaultLabel) {
    return '默认 $defaultLabel，查找当前符号的引用位置。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndJumpsTo2(Object defaultLabel) {
    return '默认 $defaultLabel，跳转到当前符号的实现位置。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsType(Object defaultLabel) {
    return '默认 $defaultLabel，显示当前位置的类型或文档信息。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndStartsRename(Object defaultLabel) {
    return '默认 $defaultLabel，发起当前符号重命名。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndShowsAvailable(Object defaultLabel) {
    return '默认 $defaultLabel，显示可用的代码操作列表。';
  }

  @override
  String settingsDefaultsToDefaultlabelAndFormatsThe(Object defaultLabel) {
    return '默认 $defaultLabel，格式化当前编程文件；当选中多行时，Shift+Tab 仍优先执行反向缩进。';
  }

  @override
  String progExpFEResolvedLspBackendForCurrentFile(
    Object lspName,
    Object projLang,
    Object fileLang,
    Object modeLine,
    Object sdkSourceLine,
    Object lspSourceLine,
    Object rootPath,
    Object command,
  ) {
    return '当前文件已解析到 $lspName。\n项目语言：$projLang\n当前文件语言：$fileLang\n$modeLine\n$sdkSourceLine\n$lspSourceLine\n工作区：$rootPath\n命令：$command';
  }

  @override
  String get settingsReduceMotionLabel => '減少動畫';

  @override
  String get settingsReduceMotionBody =>
      '開啟後，自研動畫與 Flutter 內建動畫的時長全部歸零。與系統層「減少動畫」輔助功能並聯生效。';

  @override
  String get mcpToolSearchReplayLastCancelAction => '重播上次取消';

  @override
  String get mcpToolSearchReplayLastCancelToastFired => '已重發上次取消的載入';

  @override
  String get mcpToolSearchReplayLastCancelToastEmpty => '目前沒有可重播的取消';

  @override
  String get aiThrottleSettingsLabel => '节流参数';

  @override
  String get aiThrottleSettingsBody => '统一控制流式输出节流：开关、自动模式、字符 / 卡片速率、持续时长。';

  @override
  String get webReverseVitalsInstalling => '注入 PerformanceObserver…';

  @override
  String get webReverseVitalsResetting => '重置中…';

  @override
  String get webReverseVitalsReportCopied => '报告 JSON 已复制';

  @override
  String get webReverseVitalsTitle => 'Web Vitals 报告';

  @override
  String get webReverseVitalsSubtitle =>
      'PerformanceObserver · LCP / CLS / INP / FCP / TTFB · 实时刷新';

  @override
  String get webReverseVitalsCopyJson => '复制报告 JSON';

  @override
  String get webReverseVitalsReset => '重置采集';

  @override
  String get webReverseVitalsClose => '关闭';

  @override
  String get webReverseVitalsThresholdsHint =>
      '阈值参考 web.dev：LCP ≤2.5s 良 / ≥4s 差；CLS ≤0.1 良 / ≥0.25 差；INP ≤200ms 良 / ≥500ms 差。重置后请重新交互页面以触发 LCP / 事件采样。';

  @override
  String get webReverseIssuesCopied => '已复制 issue JSON';

  @override
  String get webReverseIssuesTitle => 'Issues 面板';

  @override
  String get webReverseIssuesSubtitle =>
      'Audits.issueAdded · 安全 / Cookie / Mixed Content / Deprecation 实时聚合';

  @override
  String get webReverseIssuesClearBuffer => '清空缓冲';

  @override
  String get webReverseIssuesClose => '关闭';

  @override
  String get webReverseIssuesFilterHint => '按 code / URL / 描述过滤…';

  @override
  String get webReverseIssuesEmptyBuffer => '当前页面尚未报告任何 issue，访问几个交互后再来看看。';

  @override
  String get webReverseIssuesNoMatch => '没有匹配的 issue。';

  @override
  String get webReverseIssuesCopyJson => '复制 JSON';

  @override
  String get webReverseIssuesCollapse => '收起';

  @override
  String get webReverseIssuesExpand => '展开';

  @override
  String get webReverseIssuesSubscribed => '已订阅 Audits.issueAdded';

  @override
  String get webReverseIssuesAuditsNotReady => 'Audits 域未就绪';

  @override
  String get webReverseRenderingResetSuccess => '已重置全部 Rendering 开关';

  @override
  String get webReverseRenderingTitle => 'Rendering 调试';

  @override
  String get webReverseRenderingSubtitle =>
      'Paint / Layout shift / Layers / FPS / 媒体仿真 / CPU 节流';

  @override
  String get webReverseRenderingResetAll => '全部重置';

  @override
  String get webReverseRenderingClose => '关闭';

  @override
  String get webReverseRenderingSectionOverlays => '可视化覆盖层';

  @override
  String get webReverseRenderingPaintFlashingDesc =>
      '高亮当帧重绘区域 · Overlay.setShowPaintRects';

  @override
  String get webReverseRenderingLayoutShiftDesc =>
      'CLS 偏移可视化 · Overlay.setShowLayoutShiftRegions';

  @override
  String get webReverseRenderingLayerBordersDesc =>
      '合成层边框 · Overlay.setShowDebugBorders';

  @override
  String get webReverseRenderingScrollBottleneckDesc =>
      '阻塞主线程的滚动区域 · setShowScrollBottleneckRects';

  @override
  String get webReverseRenderingHitTestDesc =>
      '元素命中区边框 · Overlay.setShowHitTestBorders';

  @override
  String get webReverseRenderingFpsDesc =>
      '右上角实时帧率 · Overlay.setShowFPSCounter';

  @override
  String get webReverseRenderingWebVitalsDesc =>
      'LCP / CLS / INP 浮层 · Overlay.setShowWebVitals';

  @override
  String get webReverseRenderingSectionPerf => '性能仿真';

  @override
  String get webReverseRenderingSectionMedia => '媒体仿真';

  @override
  String get webReverseRenderingLabelColorScheme => '配色方案';

  @override
  String get webReverseRenderingLabelReducedMotion => '减少动效';

  @override
  String get webReverseRenderingLabelMediaType => '媒体类型';

  @override
  String get webReverseRenderingCpuThrottling => 'CPU 节流';

  @override
  String get webReverseAnimationsTitle => 'Animations 调试';

  @override
  String get webReverseAnimationsSubtitle =>
      'CDP Animation.setPlaybackRate + document.getAnimations() 实时拉取';

  @override
  String get webReverseAnimationsCopyJson => '复制 JSON';

  @override
  String get webReverseAnimationsRefresh => '重新抓取';

  @override
  String get webReverseAnimationsGlobalRate => '全局倍速';

  @override
  String get webReverseAnimationsPauseSymbol => '⏸';

  @override
  String get webReverseAnimationsBulkPause => '全部暂停';

  @override
  String get webReverseAnimationsBulkResume => '全部继续';

  @override
  String get webReverseAnimationsBulkCancel => '全部取消';

  @override
  String get webReverseAnimationsEmptyState =>
      '没有抓到活跃 animation。先在页面上触发动画再点刷新。';

  @override
  String get webReverseAnimationsRowPause => '暂停';

  @override
  String get webReverseAnimationsRowPlay => '继续';

  @override
  String get webReverseAnimationsRowCancel => '取消';

  @override
  String get webReverseAnimationsClose => '关闭';

  @override
  String get webReverseAnimationsNoSnapshot => '页面无法返回快照';

  @override
  String get webReverseAnimationsMalformedSnapshot => '快照格式异常';

  @override
  String get webReverseAnimationsJsonCopied => 'JSON 已复制';

  @override
  String webReverseAnimationsSetFailed(String error) {
    return '设置失败: $error';
  }

  @override
  String webReverseAnimationsRateNow(String rate) {
    return '当前全局倍速 ${rate}x';
  }

  @override
  String webReverseAnimationsSetError(String error) {
    return '设置异常: $error';
  }

  @override
  String webReverseAnimationsBrowserError(String error) {
    return '浏览器侧异常: $error';
  }

  @override
  String webReverseAnimationsSnapshotCount(int count) {
    return '抓到 $count 条活跃 animation';
  }

  @override
  String webReverseAnimationsSnapshotFailed(String error) {
    return '抓取失败: $error';
  }

  @override
  String webReverseAnimationsBulkInvoked(String method, int count) {
    return '已对 $count 条 animation 执行 $method';
  }

  @override
  String webReverseAnimationsBulkError(String method, String error) {
    return '$method 异常: $error';
  }

  @override
  String get webReverseHarTitle => 'HAR 全量持久化';

  @override
  String get webReverseHarSubtitle => '立即落盘 / 反向加载 / 周期自动轮转';

  @override
  String get webReverseHarOpenSaveDialogFail => '打开保存对话框失败';

  @override
  String get webReverseHarExporting => '导出中...';

  @override
  String get webReverseHarExportFailedNoDraft => '导出失败（无 HAR 草稿）';

  @override
  String get webReverseHarExportFailed => '导出失败';

  @override
  String get webReverseHarWrotePrefix => '已写出: ';

  @override
  String get webReverseHarSaved => 'HAR 已保存';

  @override
  String get webReverseHarExportErrorShort => '导出异常';

  @override
  String get webReverseHarOpenFileDialogFail => '打开文件对话框失败';

  @override
  String get webReverseHarParsing => '解析 HAR...';

  @override
  String get webReverseHarModeMerge => '合并';

  @override
  String get webReverseHarModeReplace => '替换';

  @override
  String get webReverseHarLoaded => 'HAR 已加载';

  @override
  String get webReverseHarLoadErrorShort => '加载异常';

  @override
  String get webReverseHarSelect => '选择';

  @override
  String get webReverseHarChooseFolderFirst => '请先选择目录';

  @override
  String get webReverseHarAutoStarted => '已启动自动轮转';

  @override
  String get webReverseHarAutoStopped => '已停止自动轮转';

  @override
  String get webReverseHarSessionStatus => '当前会话状态';

  @override
  String get webReverseHarManual => '手动操作';

  @override
  String get webReverseHarSaveNow => '立即保存 HAR';

  @override
  String get webReverseHarLoadExternal => '加载外部 HAR';

  @override
  String get webReverseHarMergeLabel => '合并（不清空）';

  @override
  String get webReverseHarLastHarPrefix => '上次 HAR: ';

  @override
  String get webReverseHarAutoRotate => '周期自动轮转';

  @override
  String get webReverseHarIntervalLabel => '间隔:';

  @override
  String get webReverseHarChooseFolder => '选择目录';

  @override
  String get webReverseHarFolderNotChosen => '（未选择）';

  @override
  String get webReverseHarStart => '启动';

  @override
  String get webReverseHarStop => '停止';

  @override
  String get webReverseHarNotes => '说明';

  @override
  String get webReverseHarClose => '关闭';

  @override
  String get webReverseHarLastFilePrefix => '最近一份: ';

  @override
  String get webReverseHarNotesBody =>
      '· 立即保存：把内部 HAR 草稿复制到你选择的 .har 路径。\n· 加载外部 HAR：解析 HAR 1.2 并写回 networkRequests，可选合并到现有列表。\n· 自动轮转：每 N 分钟把当前快照写到目录下带 ISO 时间戳的 .har 文件；对话框关闭后继续运行，需手动停止。';

  @override
  String webReverseHarExportException(String error) {
    return '导出异常: $error';
  }

  @override
  String webReverseHarLoadException(String error) {
    return '加载异常: $error';
  }

  @override
  String webReverseHarLoadResult(int loaded, int skipped, String mode) {
    return '加载完成: $loaded 条 / 跳过 $skipped 条（$mode）';
  }

  @override
  String webReverseHarCapturedEntries(int count) {
    return '抓包条目: $count';
  }

  @override
  String webReverseHarRunningInfo(int rotations, String remaining) {
    return '运行中 · 已轮转 $rotations 次 · 下次 $remaining 后';
  }

  @override
  String get webReverseWaterfallTitle => '请求瀑布图';

  @override
  String get webReverseWaterfallSubtitle => '蓝段 = 等待 TTFB，绿段 = 下载；点击行复制 URL';

  @override
  String get webReverseWaterfallRefresh => '刷新';

  @override
  String get webReverseWaterfallImportHar => '导入 HAR';

  @override
  String get webReverseWaterfallExportHar => '导出 HAR';

  @override
  String get webReverseWaterfallFilterHint => 'URL 子串过滤';

  @override
  String get webReverseWaterfallOnlyXhr => '仅 XHR/Fetch';

  @override
  String get webReverseWaterfallSortTime => '时间';

  @override
  String get webReverseWaterfallSortDuration => '耗时';

  @override
  String get webReverseWaterfallSortSize => '大小';

  @override
  String get webReverseWaterfallNoRequests => '没有请求';

  @override
  String get webReverseWaterfallHeaderRequest => '请求';

  @override
  String get webReverseWaterfallUrlCopied => '已复制 URL';

  @override
  String get webReverseWaterfallClose => '关闭';

  @override
  String get webReverseWaterfallNoInitiator => '无 Initiator 信息';

  @override
  String get webReverseWaterfallInitiatorTitle => '请求发起方';

  @override
  String get webReverseWaterfallInitiatorTypeLabel => '类型';

  @override
  String get webReverseWaterfallJumpToSources => '跳到 Sources';

  @override
  String get webReverseWaterfallNoJsStack =>
      '没有 JavaScript 调用栈（parser/preflight 类型常见）';

  @override
  String get webReverseWaterfallLoadHarTitle => '加载 HAR';

  @override
  String get webReverseWaterfallCancel => '取消';

  @override
  String get webReverseWaterfallMerge => '合并';

  @override
  String get webReverseWaterfallReplace => '替换';

  @override
  String get webReverseWaterfallHarParseFailed => 'HAR 解析失败';

  @override
  String get webReverseWaterfallHarSaveFailed => 'HAR 保存失败或超时';

  @override
  String webReverseWaterfallInitiatorTooltipWithUrl(String type, String url) {
    return '发起方：$type\n$url';
  }

  @override
  String webReverseWaterfallInitiatorTooltipNoUrl(String type) {
    return '发起方：$type';
  }

  @override
  String webReverseWaterfallLoadHarPrompt(int count) {
    return '当前已有 $count 条记录，选择加载方式：';
  }

  @override
  String webReverseWaterfallLoadMergedResult(int loaded, int skipped) {
    return '合并加载 $loaded 条；跳过 $skipped 条';
  }

  @override
  String webReverseWaterfallLoadReplacedResult(int loaded, int skipped) {
    return '替换加载 $loaded 条；跳过 $skipped 条';
  }

  @override
  String webReverseWaterfallHarSavedTo(String path) {
    return 'HAR 已保存到 $path';
  }

  @override
  String get webReverseCookieEditorTitle => 'Cookie 编辑器';

  @override
  String get webReverseCookieEditorSubtitle =>
      'Network.getCookies / setCookie / deleteCookies — 精修级 CRUD';

  @override
  String get webReverseCookieEditorRefresh => '刷新';

  @override
  String get webReverseCookieEditorCopyJson => '复制 JSON';

  @override
  String get webReverseCookieEditorCopiedJson => '已复制 JSON';

  @override
  String get webReverseCookieEditorFilterHint => '过滤 name / domain / value';

  @override
  String get webReverseCookieEditorNewBtn => '新增';

  @override
  String get webReverseCookieEditorEmptyCookies => '当前 target 无 Cookie';

  @override
  String get webReverseCookieEditorEdit => '编辑';

  @override
  String get webReverseCookieEditorDelete => '删除';

  @override
  String get webReverseCookieEditorFetching => '拉取 Cookies...';

  @override
  String get webReverseCookieEditorDeleteFailed => '删除失败';

  @override
  String get webReverseCookieEditorWriteFailed => '写入失败';

  @override
  String get webReverseCookieEditorSaved => '已保存';

  @override
  String get webReverseCookieEditorNewCookie => '新增 Cookie';

  @override
  String get webReverseCookieEditorFieldName => '名称 *';

  @override
  String get webReverseCookieEditorFieldValue => '值';

  @override
  String get webReverseCookieEditorFieldDomain => '域 (domain)';

  @override
  String get webReverseCookieEditorFieldPath => '路径 (path)';

  @override
  String get webReverseCookieEditorFieldUrl => 'URL（设 domain/path 时可不填）';

  @override
  String get webReverseCookieEditorFieldExpires => '过期时间 unix 秒（留空=会话级）';

  @override
  String get webReverseCookieEditorSameSiteUnset => '未指定';

  @override
  String get webReverseCookieEditorCancel => '取消';

  @override
  String get webReverseCookieEditorSave => '保存';

  @override
  String get webReverseCookieEditorNameRequired => 'name 必填';

  @override
  String webReverseCookieEditorCookieCount(int count) {
    return '共 $count 条';
  }

  @override
  String webReverseCookieEditorDeleted(String name) {
    return '已删除 $name';
  }

  @override
  String webReverseCookieEditorEditCookie(String name) {
    return '编辑 $name';
  }

  @override
  String get webReverseInputSimTitle => '输入事件模拟';

  @override
  String get webReverseInputSimDispatchingClick => '派发鼠标点击...';

  @override
  String get webReverseInputSimDispatched => '已派发';

  @override
  String get webReverseInputSimDispatchingKey => '派发按键...';

  @override
  String get webReverseInputSimKeyDispatched => '按键已派发';

  @override
  String get webReverseInputSimInsertingText => '插入文本...';

  @override
  String get webReverseInputSimInserted => '已插入';

  @override
  String get webReverseInputSimButton => '按钮';

  @override
  String get webReverseInputSimClickCount => '点击次数';

  @override
  String get webReverseInputSimModifiers => '修饰键';

  @override
  String get webReverseInputSimClickBtn => '点击';

  @override
  String get webReverseInputSimWheelDown => '滚轮↓';

  @override
  String get webReverseInputSimWheelUp => '滚轮↑';

  @override
  String get webReverseInputSimKeyTextLabel => '文本（可空，例如 “a”）';

  @override
  String get webReverseInputSimDispatchKeyDownUp => '派发 keyDown+keyUp';

  @override
  String get webReverseInputSimInsertTextLabel => '插入文本 (Input.insertText)';

  @override
  String get webReverseInputSimInsertBtn => '插入';

  @override
  String get webReverseInputSimTabMouse => '鼠标';

  @override
  String get webReverseInputSimTabKey => '键盘';

  @override
  String get webReverseInputSimTabText => '文本';

  @override
  String get webReverseInputSimCloseBtn => '关闭';

  @override
  String webReverseInputSimClickedAt(String x, String y) {
    return '已派发点击 ($x, $y)';
  }

  @override
  String webReverseInputSimWheelDy(String dy) {
    return '滚轮 dy=$dy';
  }

  @override
  String webReverseInputSimInsertedCount(int count) {
    return '已插入 $count 字符';
  }

  @override
  String get webReverseHeadlessBatchTitle => 'Headless 批量采集';

  @override
  String get webReverseHeadlessBatchClose => '关闭';

  @override
  String get webReverseHeadlessBatchDesc =>
      '逐 URL 后台开新 tab，加载完成后保存网络响应索引 / 控制台日志 / 截图。使用当前浏览器进程，复用 cookie 与 Hook。';

  @override
  String get webReverseHeadlessBatchUrlsLabel => 'URL 列表（每行一条）';

  @override
  String get webReverseHeadlessBatchOutputDirLabel => '输出目录';

  @override
  String get webReverseHeadlessBatchNotSelected => '（未选）';

  @override
  String get webReverseHeadlessBatchChoose => '选择';

  @override
  String get webReverseHeadlessBatchNetwork => '网络';

  @override
  String get webReverseHeadlessBatchConsole => '控制台';

  @override
  String get webReverseHeadlessBatchScreenshot => '截图';

  @override
  String get webReverseHeadlessBatchStart => '开始批量';

  @override
  String get webReverseHeadlessBatchStop => '停止';

  @override
  String get webReverseHeadlessBatchNoProgress => '尚无进度';

  @override
  String get webReverseHeadlessBatchPickOutputDir => '选择输出目录';

  @override
  String get webReverseHeadlessBatchNeedUrlAndDir =>
      '请先填入至少一条 http(s):// URL，并选好输出目录';

  @override
  String get webReverseHeadlessBatchBrowserNotReady =>
      '浏览器尚未启动，请先在主面板启动会话再来批量采集';

  @override
  String get webReverseHeadlessBatchPhaseStarting => '准备';

  @override
  String get webReverseHeadlessBatchPhaseNavigating => '导航中';

  @override
  String get webReverseHeadlessBatchPhaseWaitingLoad => '等待 load';

  @override
  String get webReverseHeadlessBatchPhaseCapturingScreenshot => '截图中';

  @override
  String get webReverseHeadlessBatchPhaseDone => '完成';

  @override
  String get webReverseHeadlessBatchPhaseFailed => '失败';

  @override
  String get webReverseHeadlessBatchPhaseCancelled => '已取消';

  @override
  String webReverseHeadlessBatchFinished(int ok, int total) {
    return '批量采集结束：$ok/$total 成功';
  }

  @override
  String webReverseHeadlessBatchEventCount(int events, int total) {
    return '$events / $total 条事件';
  }

  @override
  String webReverseHeadlessBatchResultStats(int net, int log, String dir) {
    return '$net 网络 · $log 日志 · $dir';
  }

  @override
  String get webReverseResendRequestUrlEmpty => 'URL 不能为空';

  @override
  String get webReverseResendRequestUrlInvalid => 'URL 非法';

  @override
  String get webReverseResendRequestAborted => '已中止';

  @override
  String get webReverseResendRequestFooterNote =>
      '注意：本对话框走 Dart HttpClient 重发，绕过浏览器 CSP / CORS，仅供逆向调试。';

  @override
  String get webReverseResendRequestClose => '关闭';

  @override
  String get webReverseResendRequestAbort => '中止';

  @override
  String get webReverseResendRequestSend => '重放发送';

  @override
  String get webReverseResendRequestTitle => '重放 / 改包';

  @override
  String get webReverseResendRequestHeadersLabel => '请求头';

  @override
  String get webReverseResendRequestAddRow => '加一行';

  @override
  String get webReverseResendRequestRemove => '删除';

  @override
  String get webReverseResendRequestBodyLabel => '请求体';

  @override
  String get webReverseResendRequestBeautifyJson => '美化 JSON';

  @override
  String get webReverseResendRequestInvalidJson => '不是合法 JSON';

  @override
  String get webReverseResendRequestExportAs => '导出为：';

  @override
  String get webReverseResendRequestCopyResponse => '复制响应';

  @override
  String get webReverseResendRequestResponseCopied => '已复制响应体';

  @override
  String get webReverseResendRequestBase64Hint => '响应非 UTF-8，下方为 Base64 预览：';

  @override
  String get webReverseResendRequestBodyHint => '响应体：';

  @override
  String webReverseResendRequestCopiedAs(String kind) {
    return '已复制为 $kind';
  }

  @override
  String webReverseResendRequestHasNoBody(String method) {
    return '$method 不支持 body';
  }

  @override
  String webReverseResendRequestHeadersWithCount(int count) {
    return '响应头 ($count)';
  }

  @override
  String get webReverseMockRulesTitle => '本地 Mock 拦截';

  @override
  String get webReverseMockRulesSubtitle =>
      'URL 通配命中 → Fetch.fulfillRequest 直接返回假数据';

  @override
  String get webReverseMockRulesExportJson => '导出 JSON';

  @override
  String get webReverseMockRulesImportJson => '从剪贴板导入';

  @override
  String get webReverseMockRulesListLabel => '规则';

  @override
  String get webReverseMockRulesAdd => '新增';

  @override
  String get webReverseMockRulesEmptyRules => '尚无规则';

  @override
  String get webReverseMockRulesDelete => '删除';

  @override
  String get webReverseMockRulesNewRule => '新规则';

  @override
  String get webReverseMockRulesJsonCopied => '已复制 JSON';

  @override
  String get webReverseMockRulesPickRule => '左侧选择规则编辑';

  @override
  String get webReverseMockRulesHits => '命中记录';

  @override
  String get webReverseMockRulesClear => '清空';

  @override
  String get webReverseMockRulesNoHits => '尚未命中';

  @override
  String get webReverseMockRulesClose => '关闭';

  @override
  String get webReverseMockRulesSaveApply => '保存并应用';

  @override
  String get webReverseMockRulesRuleName => '规则名';

  @override
  String get webReverseMockRulesUrlPattern => 'URL 通配（* / ?）';

  @override
  String get webReverseMockRulesMethodLabel => 'Method（空=全部）';

  @override
  String get webReverseMockRulesExtraHeaders => '额外响应头（每行 Key: Value）';

  @override
  String get webReverseMockRulesResponseBody => '响应体';

  @override
  String webReverseMockRulesSavedCount(int count) {
    return '已保存 $count 条规则';
  }

  @override
  String webReverseMockRulesImportedCount(int count) {
    return '已导入 $count 条';
  }

  @override
  String webReverseMockRulesImportFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get webReverseStorageTitle => '存储管理器';

  @override
  String get webReverseStorageClose => '关闭';

  @override
  String get webReverseStorageCopied => '已复制';

  @override
  String get webReverseStorageAddCookie => '新增 Cookie';

  @override
  String get webReverseStorageCancel => '取消';

  @override
  String get webReverseStorageSave => '保存';

  @override
  String get webReverseStorageCookieSaved => 'Cookie 已保存';

  @override
  String get webReverseStorageSaveFailed => '保存失败';

  @override
  String get webReverseStorageAddEntry => '新增条目';

  @override
  String get webReverseStorageEditEntry => '编辑条目';

  @override
  String get webReverseStorageNoCookies => '没有 Cookie';

  @override
  String get webReverseStorageCopyJson => '复制 JSON';

  @override
  String get webReverseStorageDelete => '删除';

  @override
  String get webReverseStorageAdd => '新增';

  @override
  String get webReverseStorageEmpty => '空';

  @override
  String get webReverseStorageNoDatabases => '没有数据库';

  @override
  String get webReverseStoragePickDb => '选择数据库';

  @override
  String get webReverseStoragePickStore => '选择 Object Store';

  @override
  String get webReverseStorageMoreRecords => '… 还有更多记录（仅显示前 50 条）';

  @override
  String get webReverseStorageRefresh => '刷新';

  @override
  String get webReverseCorsUrlRequired => '请输入 URL';

  @override
  String get webReverseCorsBadEval => '页面返回值异常';

  @override
  String get webReverseCorsMissing => '缺失';

  @override
  String get webReverseCorsMatchOrigin => '与当前 origin 匹配';

  @override
  String get webReverseCorsAllHeadersAllowed => '所有请求头都被允许';

  @override
  String get webReverseCorsCredsRule => '需 = true 且 Allow-Origin 不能为 *';

  @override
  String get webReverseCorsCacheSeconds => '缓存时间（秒）';

  @override
  String get webReverseCorsResultCopied => '结果已复制';

  @override
  String get webReverseCorsTitle => 'CORS Preflight 测试';

  @override
  String get webReverseCorsSubtitle =>
      'OPTIONS · Allow-Origin / Methods / Headers / Credentials 诊断';

  @override
  String get webReverseCorsCopyJson => '复制 JSON';

  @override
  String get webReverseCorsTargetUrl => '目标 URL';

  @override
  String get webReverseCorsActualMethod => '实际方法';

  @override
  String get webReverseCorsOriginOverride => 'Origin 覆盖（可选，仅用于诊断显示）';

  @override
  String get webReverseCorsCustomHeaders => '自定义请求头（每行一个 K: V，仅头名参与 preflight）';

  @override
  String get webReverseCorsRunButton => '运行 Preflight';

  @override
  String get webReverseCorsDiagnostics => '诊断';

  @override
  String get webReverseCorsAllHeaders => '所有响应头';

  @override
  String get webReverseCorsClose => '关闭';

  @override
  String webReverseCorsMustInclude(String method) {
    return '需包含 $method';
  }

  @override
  String webReverseCorsMissingHeaders(String names) {
    return '缺少：$names';
  }

  @override
  String get webReverseCallgraphFetching => '获取 frame 资源...';

  @override
  String get webReverseCallgraphFetchFailed => '获取资源失败';

  @override
  String get webReverseCallgraphNoScripts => '当前页未发现 JS 脚本';

  @override
  String get webReverseCallgraphTitle => 'JS 调用图';

  @override
  String get webReverseCallgraphSubtitle => '启发式正则解析（压缩 bundle 噪点高，仅作线索）';

  @override
  String get webReverseCallgraphScanBtn => '扫描';

  @override
  String get webReverseCallgraphScriptLimit => '脚本上限';

  @override
  String get webReverseCallgraphPerScriptKb => '单脚本(KB)';

  @override
  String get webReverseCallgraphReverseHint => '反查：谁调用了 …（输入被调函数名）';

  @override
  String get webReverseCallgraphEmptyHint => '点「扫描」开始解析当前页面的 JS 资源';

  @override
  String get webReverseCallgraphFnsSuffix => '函数';

  @override
  String get webReverseCallgraphPickScript => '选择左侧脚本';

  @override
  String get webReverseCallgraphClose => '关闭';

  @override
  String get webReverseCallgraphCopyGraph => '复制脚本调用图';

  @override
  String get webReverseCallgraphGraphCopied => '已复制调用图';

  @override
  String get webReverseCallgraphCalleesSuffix => '个调用';

  @override
  String get webReverseCallgraphNoDetectedCalls => '（无识别到的调用）';

  @override
  String webReverseCallgraphParsing(int done, int total, String url) {
    return '解析中 $done/$total: $url';
  }

  @override
  String webReverseCallgraphDone(int scripts, int fns) {
    return '完成：$scripts 个脚本，$fns 个函数';
  }

  @override
  String webReverseCallgraphScriptsCount(int count) {
    return '脚本 ($count)';
  }

  @override
  String webReverseCallgraphHitsHeader(int count, String name) {
    return '反查命中 $count：包含调用「$name」的函数';
  }

  @override
  String get webReverseSwDebugFetchingRegs => '拉取注册列表...';

  @override
  String get webReverseSwDebugToggleFailed => '切换失败';

  @override
  String get webReverseSwDebugForceUpdateOn => '已开启强制更新';

  @override
  String get webReverseSwDebugForceUpdateOff => '已关闭';

  @override
  String get webReverseSwDebugTitle => 'Service Worker 调试';

  @override
  String get webReverseSwDebugSubtitle =>
      'ServiceWorker 域：启停/更新/注销/触发 sync/push';

  @override
  String get webReverseSwDebugRefresh => '刷新';

  @override
  String get webReverseSwDebugForceUpdateLabel => '每次刷新强制取新版本 SW';

  @override
  String get webReverseSwDebugEmptyList => '当前 target 无 Service Worker';

  @override
  String get webReverseSwDebugPushDataLabel => 'push 数据 (字符串)';

  @override
  String get webReverseSwDebugBtnStart => '启动';

  @override
  String get webReverseSwDebugBtnStop => '停止';

  @override
  String get webReverseSwDebugBtnUpdate => '更新';

  @override
  String get webReverseSwDebugBtnSync => '触发 sync';

  @override
  String get webReverseSwDebugBtnPush => '送 push';

  @override
  String get webReverseSwDebugBtnUnregister => '注销';

  @override
  String webReverseSwDebugWorkersCount(int count) {
    return '共 $count 个 Service Worker';
  }

  @override
  String webReverseSwDebugMethodFailed(String method, String err) {
    return '$method 失败: $err';
  }

  @override
  String webReverseSwDebugMethodOk(String method) {
    return '已执行 $method';
  }

  @override
  String get webReverseSetupTargetUrl => '目标 URL *';

  @override
  String get webReverseSetupObjective => '逆向目标 *';

  @override
  String get webReverseSetupObjectiveHint => '例如：复现壁纸下载接口，输出 curl 脚本';

  @override
  String get webReverseSetupTriggerActions => '触发动作（可选）';

  @override
  String get webReverseSetupTriggerHint => '例如：登录后点击“下载原图”按钮';

  @override
  String get webReverseSetupLoginMode => '登录态';

  @override
  String get webReverseSetupBrowser => '浏览器（已检测）';

  @override
  String get webReverseSetupProxy => '代理（可选）';

  @override
  String get webReverseSetupKeywords => '關鍵字（可選，逗號分隔）';

  @override
  String get webReverseSetupCreateThread => '创建线程';

  @override
  String get webReverseSetupHeaderTitle => '新建 Web 逆向会话';

  @override
  String get webReverseSetupHeaderSubtitle => '会话启动后会拉起浏览器并吸附在主窗口右侧';

  @override
  String get webReverseSetupClose => '关闭';

  @override
  String get webReverseSetupProfileDir => 'Profile 目录';

  @override
  String get webReverseSetupLockDetected =>
      '检测到 SingletonLock / lockfile 残留，可能阻止浏览器再次启动。';

  @override
  String get webReverseSetupWorking => '处理中…';

  @override
  String webReverseSetupCooldown(int seconds) {
    return '冷却中（${seconds}s）';
  }

  @override
  String get webReverseSetupResolveLock => '解决 Profile 冲突';

  @override
  String get webReverseSignatureDiffHeaderTitle => '签名字段变量定位器';

  @override
  String get webReverseSignatureDiffHeaderSubtitle =>
      '同 endpoint 多次抓包后自动识别动态字段（sign / ts / nonce）与稳定字段';

  @override
  String get webReverseSignatureDiffRefresh => '刷新';

  @override
  String get webReverseSignatureDiffSearchHint => '搜索 endpoint';

  @override
  String get webReverseSignatureDiffNoGroups => '暂无可分析的请求组（需 ≥2 次）';

  @override
  String get webReverseSignatureDiffEmptyHint =>
      '在 Network 面板里多次触发同一 API，再回来这里分析。';

  @override
  String get webReverseSignatureDiffCopyReport => '复制报告';

  @override
  String get webReverseSignatureDiffStable => '稳定';

  @override
  String get webReverseSignatureDiffDynamic => '动态';

  @override
  String get webReverseSignatureDiffIncreasing => '递增';

  @override
  String get webReverseSignatureDiffFixedHash => '定长哈希';

  @override
  String get webReverseSignatureDiffSectionQuery => 'Query 参数';

  @override
  String get webReverseSignatureDiffSectionHeaders => '请求 Header';

  @override
  String get webReverseSignatureDiffSectionBody => '请求体 JSON 字段';

  @override
  String get webReverseSignatureDiffReportTitle => '签名字段分析';

  @override
  String get webReverseSignatureDiffReportSamples => '样本数';

  @override
  String get webReverseSignatureDiffReportCopied => '报告已复制到剪贴板';

  @override
  String get webReverseCoverageStartFailed => '启动失败';

  @override
  String get webReverseCoverageCollecting => '已开始采集';

  @override
  String get webReverseCoverageTakeFailed => '采样失败';

  @override
  String get webReverseCoverageStopped => '已停止';

  @override
  String get webReverseCoverageReportCopied => '已复制报告';

  @override
  String get webReverseCoverageTitle => '代码覆盖率';

  @override
  String get webReverseCoverageSubtitle => '开始采集 → 在页面里操作 → 采样查看哪些脚本被执行';

  @override
  String get webReverseCoverageRecording => '采集中';

  @override
  String get webReverseCoverageStart => '开始';

  @override
  String get webReverseCoverageTake => '采样';

  @override
  String get webReverseCoverageStop => '停止';

  @override
  String get webReverseCoverageFilterHint => '按 URL 过滤';

  @override
  String get webReverseCoverageCopyReport => '复制报告';

  @override
  String get webReverseCoverageNoData => '尚无数据。Start → 操作页面 → Take。';

  @override
  String get webReverseCoverageClose => '关闭';

  @override
  String get webReverseCoverageCopyUrl => '复制 URL';

  @override
  String get webReverseCoverageCopied => '已复制';

  @override
  String webReverseCoverageSampledCount(int count) {
    return '采样完成 $count 个脚本';
  }

  @override
  String get webReverseDeviceEmuTitle => '设备模拟';

  @override
  String get webReverseDeviceEmuPresets => '预设';

  @override
  String get webReverseDeviceEmuCustom => '自定义';

  @override
  String get webReverseDeviceEmuWidth => '宽度';

  @override
  String get webReverseDeviceEmuHeight => '高度';

  @override
  String get webReverseDeviceEmuMobileMode => '移动模式 (touch + meta viewport)';

  @override
  String get webReverseDeviceEmuUaHint => '留空保持默认 UA';

  @override
  String get webReverseDeviceEmuApplyCustom => '应用自定义';

  @override
  String get webReverseDeviceEmuReset => '清除模拟';

  @override
  String get webReverseDeviceEmuClose => '关闭';

  @override
  String get webReverseDeviceEmuMinSize => '尺寸至少 100×100';

  @override
  String get webReverseDeviceEmuResetDone => '已恢复默认';

  @override
  String get webReverseDeviceEmuApplied => '已应用';

  @override
  String get webReverseDeviceEmuClearingOverrides => '清除设备模拟...';

  @override
  String get webReverseDeviceEmuApplyingCustom => '应用自定义尺寸...';

  @override
  String webReverseDeviceEmuApplyingPreset(String label) {
    return '应用预设 $label...';
  }

  @override
  String webReverseDeviceEmuAppliedPreset(String label) {
    return '已应用 $label';
  }

  @override
  String webReverseDeviceEmuAppliedCustomSize(int w, int h, String dpr) {
    return '已应用 $w×$h @ ${dpr}x';
  }

  @override
  String get webReverseWatchCopiedJson => '已复制 JSON';

  @override
  String get webReverseWatchTitle => '变量监视器';

  @override
  String get webReverseWatchExportJson => '导出 JSON';

  @override
  String get webReverseWatchPause => '暂停';

  @override
  String get webReverseWatchResume => '继续';

  @override
  String get webReverseWatchNoExpressions => '尚无表达式';

  @override
  String get webReverseWatchAwaiting => '等待求值…';

  @override
  String get webReverseWatchDelete => '删除';

  @override
  String get webReverseWatchNameLabel => '名称（可选）';

  @override
  String get webReverseWatchExpressionLabel => 'JS 表达式';

  @override
  String get webReverseWatchAddWatch => '添加监视';

  @override
  String get webReverseWatchPickWatch => '左侧选择监视项';

  @override
  String get webReverseWatchClose => '关闭';

  @override
  String get webReverseWatchInterval => '轮询间隔';

  @override
  String get webReverseWatchNewestFirst => '最新在上';

  @override
  String get webReverseWatchAwaitingFirst => '等待第一次求值…';

  @override
  String webReverseWatchSubtitleHint(int ms, int count) {
    return '每 ${ms}ms 跑一次 Runtime.evaluate，记录最近 $count 次结果';
  }

  @override
  String webReverseWatchHistory(int count) {
    return '历史（$count）';
  }

  @override
  String get webReverseAccountSnapTitle => '多账号会话快照';

  @override
  String get webReverseAccountSnapSubtitle =>
      '保存当前 cookies + localStorage/sessionStorage，一键切换不同账号';

  @override
  String get webReverseAccountSnapNameLabel => '为当前账号取名';

  @override
  String get webReverseAccountSnapNameHint => '如 main / test-001';

  @override
  String get webReverseAccountSnapCapture => '保存当前';

  @override
  String get webReverseAccountSnapExportAll => '导出全部到剪贴板';

  @override
  String get webReverseAccountSnapImport => '从剪贴板导入';

  @override
  String get webReverseAccountSnapClose => '关闭';

  @override
  String get webReverseAccountSnapEmptyHint => '还没有任何快照。在上方输入名字 → 点\"保存当前\"开始';

  @override
  String get webReverseAccountSnapApply => '应用';

  @override
  String get webReverseAccountSnapDelete => '删除';

  @override
  String get webReverseAccountSnapApplyFailedNoCdp => '应用失败：未连上 CDP';

  @override
  String get webReverseAccountSnapNotSnapshotJson => '剪贴板内容不是有效快照 JSON';

  @override
  String webReverseAccountSnapSavedSnapshot(String name, int count) {
    return '已保存「$name」（$count cookies）';
  }

  @override
  String webReverseAccountSnapAppliedSnapshot(String name) {
    return '已应用「$name」，建议刷新页面让 JS 重新读取';
  }

  @override
  String webReverseAccountSnapCopiedCount(int count) {
    return '已复制 $count 份快照 JSON 到剪贴板';
  }

  @override
  String webReverseAccountSnapImportedCount(int count) {
    return '已导入 $count 份快照';
  }

  @override
  String webReverseAccountSnapSnapshotsCount(int count) {
    return '共 $count 份';
  }

  @override
  String get webReverseReqBpNewBreakpoint => '新断点';

  @override
  String get webReverseReqBpTitle => '报文条件断点';

  @override
  String get webReverseReqBpSubtitle =>
      'URL/Body 子串命中即记录 + 触发 JS 表达式；需提前开启工具栏「请求拦截」';

  @override
  String get webReverseReqBpInterceptOff => '拦截未开启';

  @override
  String get webReverseReqBpAdd => '新增';

  @override
  String get webReverseReqBpEmptyHint => '点右上 + 新建第一个断点';

  @override
  String get webReverseReqBpUnnamed => '(未命名)';

  @override
  String get webReverseReqBpPickHint => '左侧选一条断点开始编辑';

  @override
  String get webReverseReqBpClear => '清空';

  @override
  String get webReverseReqBpNoHits => '暂无命中';

  @override
  String get webReverseReqBpNameField => '名称';

  @override
  String get webReverseReqBpAnyMethod => '任意方法';

  @override
  String get webReverseReqBpUrlContains => 'URL 包含';

  @override
  String get webReverseReqBpBodyContains => '请求体包含';

  @override
  String get webReverseReqBpEvalOnHit => '命中后执行（可选）';

  @override
  String get webReverseReqBpEvalHint =>
      '例如 debugger; 或 console.trace(\"hit\", new Error().stack)';

  @override
  String get webReverseReqBpDeleteBreakpoint => '删除此断点';

  @override
  String webReverseReqBpHitsCount(int count) {
    return '命中事件（最近 $count）';
  }

  @override
  String get webReverseWsInjectTitle => 'WebSocket 主动注入';

  @override
  String get webReverseWsInjectSubtitle =>
      '所有页面创建的 WebSocket 实例都会被代理 → 选择目标 → 注入任意文本帧';

  @override
  String get webReverseWsInjectProxyOn => '已注入代理';

  @override
  String get webReverseWsInjectInstallFailed => '注入安装失败';

  @override
  String get webReverseWsInjectRefresh => '刷新';

  @override
  String get webReverseWsInjectNoLive => '当前没有活跃 WebSocket。\n刷新页面让代理接管新连接。';

  @override
  String get webReverseWsInjectPayloadLabel => '要发送的文本帧 / JSON';

  @override
  String get webReverseWsInjectPaste => '粘贴';

  @override
  String get webReverseWsInjectPickTarget => '请选择目标连接';

  @override
  String get webReverseWsInjectTargetLabel => '目标';

  @override
  String get webReverseWsInjectLogEmpty => '注入日志会出现在这里';

  @override
  String get webReverseWsInjectClose => '关闭';

  @override
  String get webReverseWsInjectSend => '注入';

  @override
  String get webReverseWsInjectInjected => '注入成功';

  @override
  String get webReverseWsInjectInjectFailed => '注入失败';

  @override
  String webReverseWsInjectLiveCount(int count) {
    return '已发现 $count 个 WebSocket';
  }

  @override
  String webReverseWsInjectSentBytes(int count) {
    return '已注入 $count 字节';
  }

  @override
  String webReverseWsInjectFailedReason(String reason) {
    return '失败：$reason';
  }

  @override
  String get webReversePmTitle => 'postMessage 追踪';

  @override
  String get webReversePmSubtitle =>
      '注入 hook → ring buffer → 800ms 拉取队列；含 iframe 跨域通信';

  @override
  String get webReversePmHookInjected => '已注入 postMessage hook';

  @override
  String get webReversePmHookStopped => '已停止採集';

  @override
  String get webReversePmStop => '停止';

  @override
  String get webReversePmInject => '开始注入';

  @override
  String get webReversePmClear => '清空';

  @override
  String get webReversePmCopyJson => '复制 JSON';

  @override
  String get webReversePmFilterHint => 'origin/target/data 子串过滤';

  @override
  String get webReversePmChipSend => '发送';

  @override
  String get webReversePmChipRecv => '接收';

  @override
  String get webReversePmWaiting => '等待 postMessage…';

  @override
  String get webReversePmClickToCapture => '点击「开始注入」后页面会开始上报';

  @override
  String get webReversePmTagSend => '发送';

  @override
  String get webReversePmTagRecv => '接收';

  @override
  String get webReversePmClose => '关闭';

  @override
  String webReversePmCopiedCount(int count) {
    return '已复制 $count 条';
  }

  @override
  String get webReverseThrottleEnableNetwork => '启用 Network 域...';

  @override
  String get webReverseThrottleApplyFailed => '应用失败';

  @override
  String get webReverseThrottleConditionsApplied => '已应用网络条件';

  @override
  String get webReverseThrottleTitle => '网络条件模拟';

  @override
  String get webReverseThrottleSubtitle =>
      'Network.emulateNetworkConditions：选择预设或自定义 kbps/延迟';

  @override
  String get webReverseThrottlePresets => '预设档';

  @override
  String get webReverseThrottleCustom => '自定义';

  @override
  String get webReverseThrottleDownKbps => '下行 kbps (0=不限)';

  @override
  String get webReverseThrottleUpKbps => '上行 kbps (0=不限)';

  @override
  String get webReverseThrottleLatencyMs => '延迟 ms';

  @override
  String get webReverseThrottleOffline => '离线';

  @override
  String get webReverseThrottleDisableCache => '禁用缓存';

  @override
  String get webReverseThrottleApplyCustom => '应用自定义';

  @override
  String get webReverseThrottleReset => '重置（不限速）';

  @override
  String get webReverseThrottleNotes => '提示';

  @override
  String get webReverseThrottleNotesBody =>
      '· 限速对当前 target 整个 session 生效，关闭浏览器或调用「不限速」可恢复。\n· kbps 经 *1024/8 转换为 bytes/s 下发；离线时吞吐量参数被忽略。\n· 禁用缓存对 Fetch/Disk Cache 同时生效，便于复现首次访问。';

  @override
  String get webReverseThrottleClose => '关闭';

  @override
  String get webReverseThrottleUnknownError => '未知错误';

  @override
  String webReverseThrottleStatusFailed(String reason) {
    return '失败：$reason';
  }

  @override
  String webReverseThrottleStatusApplied(String summary) {
    return '已应用：$summary';
  }

  @override
  String get webReverseDomMutTitle => 'DOM Mutation 录制';

  @override
  String get webReverseDomMutSubtitle =>
      '注入 MutationObserver → childList/attributes/characterData → 时间线';

  @override
  String get webReverseDomMutRecordingStarted => '已开始录制 DOM 变更';

  @override
  String webReverseDomMutInstallFailed(String error) {
    return '安装失败：$error';
  }

  @override
  String webReverseDomMutCopiedRecords(int count) {
    return '已复制 $count 条变更 JSON';
  }

  @override
  String get webReverseDomMutExportJson => '导出 JSON';

  @override
  String get webReverseDomMutRecording => '录制中';

  @override
  String get webReverseDomMutStart => '开始录制';

  @override
  String get webReverseDomMutStop => '停止';

  @override
  String get webReverseDomMutClear => '清空';

  @override
  String get webReverseDomMutFilterHint => '过滤（子串）';

  @override
  String get webReverseDomMutAutoFollow => '自动跟随';

  @override
  String webReverseDomMutCounter(int count, int total) {
    return '$count/$total';
  }

  @override
  String get webReverseDomMutWaiting => '等待 DOM 变更…';

  @override
  String get webReverseDomMutPressStart => '点击开始录制';

  @override
  String get webReverseDomMutClose => '关闭';

  @override
  String get webReverseSmTitle => 'SourceMap 反解析';

  @override
  String get webReverseSmSubtitle => '压缩 file:line:col → 原始 source:line:col';

  @override
  String get webReverseSmInvalidInput => '请输入合法 URL 与行号';

  @override
  String get webReverseSmFetching => '抓取 sourcemap...';

  @override
  String webReverseSmFetchFailed(String error) {
    return '获取失败: $error';
  }

  @override
  String get webReverseSmBadEvalResult => '返回值异常';

  @override
  String get webReverseSmNoMapping => '未找到对应映射段';

  @override
  String get webReverseSmResolved => '解析成功';

  @override
  String get webReverseSmCopied => '已复制';

  @override
  String get webReverseSmUrlLabel => '压缩文件 URL';

  @override
  String get webReverseSmLineLabel => '行 (1-based)';

  @override
  String get webReverseSmColLabel => '列 (0-based)';

  @override
  String get webReverseSmResolve => '解析';

  @override
  String get webReverseSmEmptyHint => '输入文件 URL 与位置后点击解析';

  @override
  String get webReverseSmCopyTooltip => '复制';

  @override
  String get webReverseSmNameLabel => '名称';

  @override
  String get webReverseSmClose => '关闭';

  @override
  String get webReverseCssCovStarting => '启用 CSS 域并启动追踪...';

  @override
  String webReverseCssCovStartFailed(String error) {
    return '启动失败: $error';
  }

  @override
  String get webReverseCssCovTrackingActive =>
      '正在追踪 — 请在页面上交互（点击、滚动、悬浮等），然后点击「停止并统计」。';

  @override
  String get webReverseCssCovStopping => '停止并聚合结果...';

  @override
  String webReverseCssCovStopFailed(String error) {
    return '停止失败: $error';
  }

  @override
  String webReverseCssCovResultsTallied(int sheets, int rules) {
    return '已统计 $sheets 个样式表，共 $rules 条规则。';
  }

  @override
  String get webReverseCssCovJsonCopied => 'JSON 已复制';

  @override
  String get webReverseCssCovTitle => 'CSS 规则使用率';

  @override
  String get webReverseCssCovSubtitle =>
      'CSS.startRuleUsageTracking · 统计未命中的死代码';

  @override
  String get webReverseCssCovCopyJson => '复制 JSON';

  @override
  String get webReverseCssCovTracking => '追踪中';

  @override
  String get webReverseCssCovIdle => '空闲';

  @override
  String get webReverseCssCovStopAndTally => '停止并统计';

  @override
  String get webReverseCssCovStartTracking => '开始追踪';

  @override
  String get webReverseCssCovEmpty => '尚无结果。开始追踪后在页面上交互。';

  @override
  String webReverseCssCovRuleStats(
    int used,
    int total,
    String usedKb,
    String totalKb,
  ) {
    return '$used/$total 规则 · $usedKb/$totalKb KB';
  }

  @override
  String get webReverseCssCovClose => '关闭';

  @override
  String get webReverseAiCryptoStatusFetchResources => '获取 frame 资源...';

  @override
  String get webReverseAiCryptoStatusDetecting => '提取嫌疑字段...';

  @override
  String get webReverseAiCryptoStatusDone => '完成';

  @override
  String get webReverseAiCryptoCopied => '已复制到剪贴板';

  @override
  String get webReverseAiCryptoTitle => 'AI 加密参数还原';

  @override
  String get webReverseAiCryptoSubtitle =>
      '聚合 endpoint → diff 变量字段 → JS 源码定位 → 一键复制提示词';

  @override
  String get webReverseAiCryptoRefresh => '重新聚合';

  @override
  String get webReverseAiCryptoEmpty => '没有可分析的 endpoint（需要同一接口至少抓 2 次）';

  @override
  String get webReverseAiCryptoAnalyze => '分析';

  @override
  String get webReverseAiCryptoCopyPrompt => '复制提示词';

  @override
  String get webReverseAiCryptoSuspectsLabel => '嫌疑字段：';

  @override
  String get webReverseAiCryptoPromptHint => '点击「分析」生成提示词。';

  @override
  String get webReverseAiCryptoClose => '关闭';

  @override
  String webReverseAiCryptoStatusSearchProgress(int done, int total) {
    return '搜索字段 $done/$total';
  }

  @override
  String webReverseAiCryptoHits(int count) {
    return '$count 次';
  }

  @override
  String get webReverseCdpSendFailed => '调用失败（未连接？）';

  @override
  String get webReverseCdpCopied => '已复制';

  @override
  String get webReverseCdpTitle => 'CDP Raw 命令控制台';

  @override
  String get webReverseCdpMethodLabel => 'method (Domain.command)';

  @override
  String get webReverseCdpUseSession => '使用 page session';

  @override
  String get webReverseCdpSend => '发送';

  @override
  String get webReverseCdpNoHistory => '历史为空';

  @override
  String get webReverseCdpSendHint => '发送命令后在此查看响应';

  @override
  String get webReverseCdpClose => '关闭';

  @override
  String get webReverseCdpCopyResponse => '复制响应 JSON';

  @override
  String get webReverseCdpParams => '请求参数';

  @override
  String get webReverseCdpResponse => '响应';

  @override
  String get webReverseCdpError => '错误';

  @override
  String webReverseCdpInvalidJson(String error) {
    return 'JSON 解析失败：$error';
  }

  @override
  String webReverseCdpSubtitle(int count) {
    return '⌘/Ctrl+Enter 发送 · Ctrl+↑/↓ 翻历史 · 共 $count 条';
  }

  @override
  String get webReversePerfTitle => 'Performance Trace 录制';

  @override
  String get webReversePerfSubtitle =>
      'Tracing 域 → chrome-trace JSON（Perfetto / chrome://tracing 加载）';

  @override
  String get webReversePerfDuration => '时长';

  @override
  String get webReversePerfCategories => 'Trace 分类';

  @override
  String get webReversePerfCopyPath => '复制路径';

  @override
  String get webReversePerfStop => '停止录制';

  @override
  String get webReversePerfStart => '开始录制';

  @override
  String get webReversePerfClose => '关闭';

  @override
  String get webReversePerfTraceFailed => '录制失败或无数据';

  @override
  String get webReversePerfStopping => '已请求停止，正在收尾…';

  @override
  String get webReversePerfTraceSaved => 'Trace 已保存';

  @override
  String get webReversePerfPathCopied => '路径已复制';

  @override
  String webReversePerfRecording(int seconds) {
    return '正在录制（剩余 ${seconds}s）';
  }

  @override
  String webReversePerfSaved(String path, String kb) {
    return '已保存：$path ($kb KB)';
  }

  @override
  String get webReverseReplayJsonCopied => 'JSON 已复制';

  @override
  String get webReverseReplayTitle => '网络请求批量重放器';

  @override
  String get webReverseReplaySubtitle => '多选 → 顺序重发 → 对比原状态与新状态';

  @override
  String get webReverseReplayCopyResultsJson => '复制结果 JSON';

  @override
  String get webReverseReplayFilterByUrl => '按 URL 过滤';

  @override
  String get webReverseReplaySelectAll => '全选';

  @override
  String get webReverseReplayClear => '清空';

  @override
  String get webReverseReplayEmpty => '当前会话没有 HTTP 请求';

  @override
  String get webReverseReplayRunBatch => '开始重放';

  @override
  String get webReverseReplayClose => '关闭';

  @override
  String webReverseReplayDone(int ok, int total) {
    return '重放完成：$ok/$total 成功';
  }

  @override
  String webReverseReplayProgress(int done, int total) {
    return '重放中 $done / $total';
  }

  @override
  String webReverseReplaySelected(int count, int total) {
    return '已选 $count / $total';
  }

  @override
  String get webReverseGeoOverridesApplied => '已应用覆盖';

  @override
  String get webReverseGeoEnvOverridesApplied => '环境覆盖已应用';

  @override
  String get webReverseGeoOverridesCleared => '已清除覆盖';

  @override
  String get webReverseGeoEnvOverridesCleared => '已清除环境覆盖';

  @override
  String get webReverseGeoTitle => '地理 / 时区 / 语言覆盖';

  @override
  String get webReverseGeoCityPresets => '预设城市';

  @override
  String get webReverseGeoEnableGeo => '启用地理位置覆盖';

  @override
  String get webReverseGeoEnableTz => '启用时区覆盖';

  @override
  String get webReverseGeoEnableLocale => '启用语言覆盖';

  @override
  String get webReverseGeoTip =>
      '提示：覆盖在当前 target 内立即生效，刷新仍保留。需通过页面 `navigator.geolocation`、`Intl.DateTimeFormat().resolvedOptions().timeZone`、`navigator.language` 来感知效果。某些站点会缓存首次结果，建议覆盖后再硬刷新。';

  @override
  String get webReverseGeoClear => '清除';

  @override
  String get webReverseGeoWorking => '处理中…';

  @override
  String get webReverseGeoApply => '应用覆盖';

  @override
  String get webReverseCollectionExportNothing => '没有可导出的请求';

  @override
  String get webReverseCollectionExportTitle => 'API 集合导出';

  @override
  String get webReverseCollectionExportSubtitle =>
      'Postman / Insomnia / Bruno / cURL / HAR  —— 一键复制';

  @override
  String get webReverseCollectionExportName => '集合名称';

  @override
  String get webReverseCollectionExportUrlFilter => 'URL 子串过滤';

  @override
  String get webReverseCollectionExportXhrOnly => '仅 XHR/Fetch';

  @override
  String get webReverseCollectionExportPreview2 => '下方为前两条预览';

  @override
  String get webReverseCollectionExportClose => '关闭';

  @override
  String get webReverseCollectionExportCopyAction => '复制集合';

  @override
  String get webReverseCollectionExportNoMatch =>
      '// 没有匹配的请求。\n// 调整过滤条件或取消「仅 XHR/Fetch」。';

  @override
  String webReverseCollectionExportCopied(int count) {
    return '已复制 $count 条请求到剪贴板';
  }

  @override
  String webReverseCollectionExportMatchCount(int match, int total) {
    return '匹配 $match 条 · 共 $total';
  }

  @override
  String get webReverseJwtTitle => 'JWT 自动续期';

  @override
  String get webReverseJwtSubtitle =>
      '扫描 cookies/localStorage/sessionStorage 中的 JWT，临近过期自动跑刷新脚本';

  @override
  String get webReverseJwtScanNow => '立即扫描';

  @override
  String get webReverseJwtRefreshNow => '手动续期';

  @override
  String get webReverseJwtAuto => '自动续期';

  @override
  String get webReverseJwtIntervalSec => '间隔(秒)';

  @override
  String get webReverseJwtThresholdSec => '阈值(秒)';

  @override
  String get webReverseJwtRefreshExpr => '刷新表达式 (async JS)';

  @override
  String get webReverseJwtNoneFound => '尚未发现 JWT';

  @override
  String get webReverseJwtRefreshLog => '续期日志';

  @override
  String get webReverseJwtClose => '关闭';

  @override
  String webReverseJwtFoundCount(int count) {
    return '已发现 JWT ($count)';
  }

  @override
  String get webReverseWebauthnTitle => 'WebAuthn 虚拟认证器';

  @override
  String get webReverseWebauthnDisabledBody =>
      '点击右上方开关启用 WebAuthn 虚拟域，然后即可创建虚拟认证器，让站点的 navigator.credentials.create / get 在无硬件密钥时也能完成。';

  @override
  String get webReverseWebauthnAdd => '新增虚拟认证器';

  @override
  String get webReverseWebauthnAddBtn => '添加';

  @override
  String get webReverseWebauthnNone => '尚无虚拟认证器';

  @override
  String get webReverseWebauthnClose => '关闭';

  @override
  String get webReverseWebauthnRefreshCreds => '刷新凭据列表';

  @override
  String get webReverseWebauthnRemove => '移除';

  @override
  String get webReverseWebauthnUserVerified => '用户已验证 (isUserVerified)';

  @override
  String webReverseWebauthnAdded(String id) {
    return '已添加 authenticator $id';
  }

  @override
  String webReverseWebauthnCreatedCount(int count) {
    return '已创建 ($count)';
  }

  @override
  String webReverseWebauthnCredentialsCount(int count) {
    return '凭据 ($count)';
  }

  @override
  String get webReverseInstallTitle => '需要 Google Chrome（或同核浏览器）';

  @override
  String get webReverseInstallClose => '关闭';

  @override
  String get webReverseInstallBody =>
      'Web 逆向专家依赖外部 Chrome / Edge / Brave / Chromium 等同核浏览器，通过 CDP（Chrome DevTools Protocol）通道驱动调试。检测到当前系统没有可用的同核浏览器。';

  @override
  String get webReverseInstallOpen => '在浏览器打开';

  @override
  String get webReverseInstallHint =>
      '建议安装 Chrome 正式版后重试。如已安装 Edge / Brave / Chromium，点击\"我已安装，重新检测\"。';

  @override
  String get webReverseInstallInstalled => '我已安装';

  @override
  String get webReverseProfileEmptyPath => 'Profile 路径为空，未执行';

  @override
  String get webReverseProfileNoResidual => '未发现残留锁文件。如仍无法启动，请查看诊断卡片其他根因。';

  @override
  String get webReverseProfileResetTitle => '锁仍未清干净，是否重置 profile？';

  @override
  String get webReverseProfileResetConfirm => '确认重置';

  @override
  String get webReverseProfileKept => '已保留 profile，但锁仍可能阻止下次启动。';

  @override
  String webReverseProfileCleanFailed(String error) {
    return '清理失败：$error';
  }

  @override
  String webReverseProfileCleaned(int count) {
    return '已清理 $count 个锁文件，profile 已恢复';
  }

  @override
  String webReverseProfileResetBody(String path) {
    return '已尝试清理 SingletonLock 等残留，但仍检测到锁文件。\n\n继续操作会递归删除：\n$path\n\n该 profile 下的 Cookies / Login Data / 已安装扩展 / 浏览历史 等数据将全部丢失，下次启动会重建一个全新 profile。';
  }

  @override
  String webReverseProfileResetDone(String path) {
    return '已重置 profile：$path（60 秒内不可重复操作）';
  }

  @override
  String webReverseProfileResetFailed(String error) {
    return '重置失败：$error';
  }

  @override
  String get webReverseReplNoResult => '(无返回)';

  @override
  String get webReverseReplCopied => '已复制';

  @override
  String get webReverseReplTitle => 'Console REPL';

  @override
  String get webReverseReplSubtitle =>
      'Runtime.evaluate · ↑/↓ 历史 · Ctrl/⌘+Enter 执行';

  @override
  String get webReverseReplClear => '清空输出';

  @override
  String get webReverseReplEmpty => '在下方输入 JS 表达式 → Ctrl/⌘+Enter 执行';

  @override
  String get webReverseReplHint =>
      '示例: document.title  或  await fetch(\"/api\").then(r=>r.json())';

  @override
  String get webReverseReplRun => '执行';

  @override
  String get webReverseConsoleEvalFailed => '执行失败';

  @override
  String get webReverseConsoleEmpty => '暂无控制台输出。';

  @override
  String get webReverseConsolePausedHint => '调试器已暂停 · 表达式将在当前栈帧的作用域内求值';

  @override
  String get webReverseConsoleReplHint => '输入 JS 表达式回车执行；↑↓ 浏览历史';

  @override
  String get webReverseConsoleClusterCopied => '簇 JSON 已复制';

  @override
  String get webReverseConsoleClusterTitle => 'Console 错误聚类';

  @override
  String get webReverseConsoleClusterRefresh => '刷新';

  @override
  String get webReverseConsoleClusterFilterHint => '关键字过滤';

  @override
  String get webReverseConsoleClusterNoMatch => '没有匹配的 console 条目';

  @override
  String get webReverseConsoleClusterCopyJson => '复制 JSON';

  @override
  String webReverseConsoleClusterSubtitle(int entries, int clusters) {
    return '按 level + 归一化首行去重 · 共 $entries 条 / $clusters 簇';
  }

  @override
  String webReverseConsoleClusterTimes(String first, String last) {
    return '首次：$first\n末次：$last';
  }

  @override
  String webReverseConsoleClusterMore(int count) {
    return '… 还有 $count 条';
  }

  @override
  String get webReverseDomSearchTitle => 'DOM 选择器搜索';

  @override
  String get webReverseDomSearchSearching => '搜索中...';

  @override
  String get webReverseDomSearchNoMatches => '无匹配结果';

  @override
  String get webReverseDomSearchHint => '输入 selector / 文本 / XPath，回车搜索';

  @override
  String get webReverseDomSearchRun => '搜索';

  @override
  String get webReverseDomSearchExample =>
      '示例: button[data-action] · #login · //a[contains(@href,\"docs\")]';

  @override
  String get webReverseDomSearchHighlight => '在页面高亮';

  @override
  String webReverseDomSearchFailed(String error) {
    return '搜索失败: $error';
  }

  @override
  String webReverseDomSearchGetFailed(String error) {
    return '获取结果失败: $error';
  }

  @override
  String webReverseDomSearchHitCount(int total, int shown) {
    return '命中 $total 个，展示前 $shown 条';
  }

  @override
  String get webReverseFrameTreeTitle => 'Frame 树查看器';

  @override
  String get webReverseFrameTreeSubtitle =>
      'Page.getFrameTree · 主框架 + 所有 iframe 递归';

  @override
  String get webReverseFrameTreeRefresh => '刷新';

  @override
  String get webReverseFrameTreeCopyJson => '复制 JSON';

  @override
  String get webReverseFrameTreeCopied => '已复制';

  @override
  String get webReverseFrameTreeEmpty => '当前页面无 frame';

  @override
  String webReverseFrameTreeFailed(String error) {
    return '获取失败: $error';
  }

  @override
  String webReverseFrameTreeCount(int count) {
    return '共 $count 帧';
  }

  @override
  String get webReverseCpuThrottleOff => 'CPU 限速已关闭';

  @override
  String get webReverseCpuThrottleResetDone => '已恢复';

  @override
  String get webReverseCpuThrottleTitle => 'CPU 限速';

  @override
  String get webReverseCpuThrottlePresets => '常用预设';

  @override
  String get webReverseCpuThrottleNote =>
      '注意：CDP CPU 限速作用于渲染进程，不影响 GPU/网络。关闭窗口后限速仍生效，请手动选择 1×（off）或点「重置」恢复。';

  @override
  String get webReverseCpuThrottleReset => '重置 (1×)';

  @override
  String webReverseCpuThrottleApplying(String rate) {
    return '设置 CPU 限速 $rate×...';
  }

  @override
  String webReverseCpuThrottleFailed(String error) {
    return '失败: $error';
  }

  @override
  String webReverseCpuThrottleCurrent(String rate) {
    return '当前 CPU 限速 $rate×';
  }

  @override
  String webReverseCpuThrottleSliderLabel(String rate) {
    return '滑动调节 $rate×';
  }

  @override
  String webReverseCpuThrottleApplied(String rate) {
    return '已应用 $rate× 限速';
  }

  @override
  String get webReverseHeapTaking => '正在抓取 Heap Snapshot（可能耗时数秒）...';

  @override
  String get webReverseHeapFailed => '抓取失败或无数据';

  @override
  String get webReverseHeapSavedToast => 'Heap snapshot 已保存';

  @override
  String get webReverseHeapPathCopied => '路径已复制';

  @override
  String get webReverseHeapSubtitle =>
      'HeapProfiler.takeHeapSnapshot → .heapsnapshot（DevTools Memory 可加载）';

  @override
  String get webReverseHeapEmptyHint =>
      '点击下方按钮抓取当前页面的 V8 Heap Snapshot。\n大型页面可能产生 50MB+ 文件。';

  @override
  String get webReverseHeapCopyPath => '复制路径';

  @override
  String get webReverseHeapTake => '抓取快照';

  @override
  String webReverseHeapSaved(String path, String mb) {
    return '已保存：$path ($mb MB)';
  }

  @override
  String get webReverseRealtimeDirSent => '发出';

  @override
  String get webReverseRealtimeDirRecv => '收到';

  @override
  String get webReverseRealtimeDirError => '错误';

  @override
  String get webReverseRealtimePayloadCopied => '已复制载荷';

  @override
  String get webReverseRealtimeTitle => '实时连接';

  @override
  String get webReverseRealtimeEmpty =>
      '当前页面未抓到 WebSocket / EventSource。\n触发动作后此处会实时刷新。';

  @override
  String get webReverseRealtimePickPrompt => '从左侧选一个连接以查看帧流。';

  @override
  String get webReverseRealtimeFilterHint => '过滤载荷（子串）';

  @override
  String get webReverseRealtimeAutoFollow => '自动跟随';

  @override
  String get webReverseRealtimeNoMatching => '无匹配帧。';

  @override
  String webReverseRealtimeFrameCount(int count) {
    return '$count 帧';
  }

  @override
  String get webReverseMarkupTitle => '截图标注';

  @override
  String get webReverseMarkupSaveWithout => '不标注直接保存';

  @override
  String get webReverseMarkupExporting => '导出中…';

  @override
  String get webReverseMarkupDone => '完成';

  @override
  String get webReverseMarkupUndo => '撤销';

  @override
  String get webReverseMarkupClear => '清空';

  @override
  String get webReverseMarkupAddTextTitle => '添加文字注释';

  @override
  String get webReverseMarkupLabelHint => '输入标注文字';

  @override
  String get webReverseMarkupAdd => '添加';

  @override
  String get webReverseElementsLoadFailed => '加载失败：浏览器未启动或 CDP 不可用';

  @override
  String get webReverseElementsSelectorFailed => '无法生成 selector';

  @override
  String get webReverseElementsSelectorCopied => '已复制 selector';

  @override
  String get webReverseElementsXPathFailed => '无法生成 XPath';

  @override
  String get webReverseElementsXPathCopied => '已复制 XPath';

  @override
  String get webReverseElementsReloadDom => '刷新 DOM 根';

  @override
  String get webReverseElementsCopySelector => '复制 selector';

  @override
  String get webReverseElementsCopyXPath => '复制 XPath';

  @override
  String get webReverseElementsScrollIntoView => '页面定位';

  @override
  String get webReverseElementsPickElement => '从左侧 DOM 树选择一个元素';

  @override
  String get webReverseElementsNoAttrs => '该元素无属性';

  @override
  String get webReverseElementsNoComputed => '无计算样式';

  @override
  String get webReverseElementsNoListeners => '该元素无监听';

  @override
  String webReverseElementsAttrsTab(int count) {
    return '属性 ($count)';
  }

  @override
  String webReverseElementsComputedTab(int count) {
    return '计算样式 ($count)';
  }

  @override
  String webReverseElementsListenersTab(int count) {
    return '事件 ($count)';
  }

  @override
  String get webReverseCryptoSecEncode => '编解码';

  @override
  String get webReverseCryptoSecHash => '哈希';

  @override
  String get webReverseCryptoSecTime => '时间戳';

  @override
  String get webReverseCryptoClear => '清空';

  @override
  String get webReverseCryptoInputHint => '在此粘贴待处理文本…';

  @override
  String get webReverseCryptoInputLabel => '输入';

  @override
  String get webReverseCryptoCopy => '复制';

  @override
  String get webReverseCryptoUseAsInput => '回填到输入';

  @override
  String get webReverseCryptoLengthLabel => '长度';

  @override
  String get webReverseCryptoTsToIso => '时间戳 → ISO';

  @override
  String get webReverseCryptoIsoToTs => 'ISO → 时间戳';

  @override
  String get webReverseCryptoNow => '当前时间';

  @override
  String get webReverseCryptoUuidHint => '随机 UUID v4（点击复制）';

  @override
  String get webReverseCryptoRegenerate => '重新生成';

  @override
  String webReverseCryptoCopied(String label) {
    return '已复制 $label';
  }

  @override
  String webReverseCryptoLengthValue(int chars, int bytes) {
    return '字符 $chars / 字节 $bytes';
  }

  @override
  String get webReverseHooksDefaultCode => '在每个文档加载前执行；可 patch window/fetch 等';

  @override
  String get webReverseHooksSavedToast => '已保存并热重载';

  @override
  String get webReverseHooksDeleteTitle => '删除 hook？';

  @override
  String get webReverseHooksDeleteContent => '将立即卸载并不可撤销。';

  @override
  String get webReverseHooksDelete => '删除';

  @override
  String get webReverseHooksDiscardTitle => '丢弃未保存改动？';

  @override
  String get webReverseHooksKeepEditing => '继续编辑';

  @override
  String get webReverseHooksDiscardConfirm => '丢弃';

  @override
  String get webReverseHooksLibrary => 'JS Hook 库';

  @override
  String get webReverseHooksNew => '新建 hook';

  @override
  String get webReverseHooksEmpty => '暂无 hook。\n点 + 新建第一个。';

  @override
  String get webReverseHooksPickPrompt => '从左侧选一个 hook，或新建一个。';

  @override
  String get webReverseHooksNameLabel => '名称';

  @override
  String get webReverseHooksSave => '保存 (⌘S)';

  @override
  String get webReverseHooksSaved => '已保存';

  @override
  String get webReverseHooksInfo => '保存即重装。脚本在文档加载前执行；切换 tab / 刷新页面后仍生效。';

  @override
  String webReverseHooksNewName(String time) {
    return '钩子 $time';
  }

  @override
  String get webReverseSnippetsDefaultCode => '在此编写 JS，将在浏览器页面上下文执行';

  @override
  String get webReverseSnippetsNoResult => '(无返回值)';

  @override
  String get webReverseSnippetsDeleteTitle => '删除脚本？';

  @override
  String get webReverseSnippetsDeleteContent => '不可撤销。';

  @override
  String get webReverseSnippetsDelete => '删除';

  @override
  String get webReverseSnippetsTitle => '脚本注入库';

  @override
  String get webReverseSnippetsNew => '新建脚本';

  @override
  String get webReverseSnippetsEmpty => '暂无脚本。\n点 + 新建第一个。';

  @override
  String get webReverseSnippetsPickPrompt => '从左侧选一个脚本，或新建一个。';

  @override
  String get webReverseSnippetsRun => '运行 (⌘R)';

  @override
  String get webReverseSnippetsSaveDirty => '保存 *';

  @override
  String webReverseSnippetsNewName(String time) {
    return '脚本 $time';
  }

  @override
  String get servicesTitle => '服務';

  @override
  String get servicesSubtitle => '匯聚 OpenHand 自研的專業服務，提供穩定、可控、可稽核的任務執行體驗。';

  @override
  String get servicesProprietaryBadge => 'OpenHand 自研';

  @override
  String get servicesAiInfrastructureExposureScanTitle => 'AI 基礎設施暴露面掃描';

  @override
  String get servicesAiInfrastructureExposureScanDescription =>
      '面向已授權目標，持續發現 AI 服務暴露面，識別憑證洩漏與高風險設定，並沉澱可稽核的處置線索。';

  @override
  String get agentsTitle => '智慧體';

  @override
  String get agentsSubtitle => '統一管理 Hermes Agent 數位員工的檔案、權限、任務、叢集、稽核與 KPI。';

  @override
  String get agentsCreateAgent => '建立智慧體';

  @override
  String get agentsEditAgent => '編輯智慧體';

  @override
  String get agentsLoadFailed => '智慧體設定載入失敗';

  @override
  String get agentsRetry => '重試';

  @override
  String get agentsEmptyTitle => '尚無智慧體';

  @override
  String get agentsEmptyBody => '點擊右上角建立按鈕，設定第一個具備職責邊界、權限、任務台與治理能力的數位員工。';

  @override
  String get agentsMentorLabel => '導師';

  @override
  String get agentsStopAgent => '停止智慧體';

  @override
  String get agentsStartAgent => '啟動智慧體';

  @override
  String get agentsActivities => '歷史活動';

  @override
  String get agentsLogs => '日誌';

  @override
  String get agentsCapabilityLogs => '能力呼叫日誌';

  @override
  String get agentsApprovals => '審批';

  @override
  String get agentsCluster => '叢集';

  @override
  String get agentsMore => '更多';

  @override
  String get agentsTaskDesk => '任務台';

  @override
  String get agentsAuditReport => '稽核報表';

  @override
  String get agentsKpi => 'KPI';

  @override
  String get agentsResources => '資源管理';

  @override
  String get agentsDeleteAgent => '刪除智慧體';

  @override
  String agentsTasksCount(int running, int total) {
    return '任務 $running/$total';
  }

  @override
  String agentsApprovalsCount(int count) {
    return '審批 $count';
  }

  @override
  String agentsWorkersCount(int count, int max) {
    return 'Worker $count/$max';
  }

  @override
  String agentsCapabilitySkillsCount(int count) {
    return '技能 $count';
  }

  @override
  String agentsCapabilityKnowledgeCount(int count) {
    return '知識庫 $count';
  }

  @override
  String agentsCapabilityMemoryCount(int count) {
    return '記憶 $count';
  }

  @override
  String agentsCapabilityToolsCount(int count) {
    return '工具 $count';
  }

  @override
  String agentsCapabilityCronsCount(int count) {
    return 'Crons $count';
  }

  @override
  String agentsCapabilityHooksCount(int count) {
    return 'Hooks $count';
  }

  @override
  String get agentsSelfLearningOn => '自我學習已開啟';

  @override
  String get agentsNoCapabilityResources => '尚未綁定能力資源';

  @override
  String agentsDialogTitleWithName(String title, String name) {
    return '$title · $name';
  }

  @override
  String get agentsActivitiesEmptyTitle => '暫無歷史活動。';

  @override
  String get agentsLogsEmptyTitle => '暫無 Skill、記憶、MCP 或工具呼叫日誌。';

  @override
  String get agentsApprovalsEmptyTitle => '暫無待審批請求。';

  @override
  String get agentsListEmptyBody => '智慧體啟動並執行任務後會自動沉澱於此。';

  @override
  String agentsMinWorkersCount(int count) {
    return '最小 $count';
  }

  @override
  String agentsMaxWorkersCount(int count) {
    return '最大 $count';
  }

  @override
  String get agentsNoWorkersTitle => '暫無 Worker';

  @override
  String get agentsNoWorkersBody => '儲存設定後會依最小 Worker 數自動預置本地 Worker 狀態。';

  @override
  String agentsWorkerSubtitle(String status, int done, int priority) {
    return '$status · 已執行 $done · 優先級 $priority';
  }

  @override
  String get agentsPublishTask => '發布任務';

  @override
  String get agentsNoTasksTitle => '暫無任務';

  @override
  String get agentsNoTasksBody => '可從這裡發布任務，後續 Worker 會按調度策略執行並回填結果。';

  @override
  String get agentsAuditRequests => '請求量';

  @override
  String get agentsAuditCompleted => '完成任務';

  @override
  String get agentsAuditUtilization => '利用率';

  @override
  String get agentsRecentAuditEvents => '最近稽核事件';

  @override
  String get agentsNoAuditData => '暫無稽核資料。';

  @override
  String get agentsNoKpiTitle => '暫無 KPI';

  @override
  String get agentsNoKpiBody => '在編輯設定中輸入 KPI，智慧體工作循環會據此規劃推進。';

  @override
  String get agentsMetricMemory => '記憶體';

  @override
  String get agentsMetricDisk => '磁碟';

  @override
  String get agentsMetricPersisted => '持久化';

  @override
  String get agentsMetricHandles => '控制代碼';

  @override
  String get agentsPublish => '發布';

  @override
  String get agentsTaskTitleLabel => '任務標題';

  @override
  String get agentsDescriptionLabel => '介紹';

  @override
  String get agentsContentLabel => '內容';

  @override
  String get agentsNoteLabel => '備註';

  @override
  String get agentsDeleteConfirmTitle => '刪除智慧體';

  @override
  String agentsDeleteConfirmMessage(String name) {
    return '確定刪除 $name？此操作不會刪除已綁定的技能、知識庫或 MCP。';
  }

  @override
  String get agentsTabProfile => '檔案';

  @override
  String get agentsTabCapabilities => '能力';

  @override
  String get agentsTabRuntime => '執行';

  @override
  String get agentsTabGovernance => '治理';

  @override
  String get agentsTabMetadata => '中繼資料';

  @override
  String get agentsFieldAvatar => '頭像';

  @override
  String get agentsFieldAvatarHint => '文字、Emoji 或圖片標識';

  @override
  String get agentsFieldNameRequired => '名稱 *';

  @override
  String get agentsFieldPosition => '職位';

  @override
  String get agentsFieldDepartment => '部門';

  @override
  String get agentsFieldLevel => '等級';

  @override
  String get agentsFieldIntroduction => '介紹';

  @override
  String get agentsFieldArchive => '檔案';

  @override
  String get agentsFieldRouteFrontMatter => '路由資訊';

  @override
  String get agentsFieldWelcomeMessage => '歡迎語';

  @override
  String get agentsFieldPersona => '角色設定';

  @override
  String get agentsFieldResponsibilityBoundary => '職責邊界';

  @override
  String get agentsKnowledgeBase => '知識庫';

  @override
  String get agentsBuiltInTools => '内建工具';

  @override
  String get agentsModelLabel => '模型';

  @override
  String get agentsEnableAgentTitle => '啟用智慧體';

  @override
  String get agentsEnableAgentBody => '啟用後智慧體工作循環與智慧體內建工具可用。';

  @override
  String get agentsSelfLearningTitle => '自我學習';

  @override
  String get agentsSelfLearningBody => '依託 Hermes Agent 沉澱 Skill、記憶與經驗。';

  @override
  String get agentsFieldWorkspacePath => '工作目錄';

  @override
  String get agentsFieldWorkspaceScope => '工作目錄範圍';

  @override
  String get agentsCrons => '定時任務';

  @override
  String get agentsClusterScaling => '叢集伸縮';

  @override
  String get agentsMinWorkersLabel => '最小 Worker';

  @override
  String get agentsMaxWorkersLabel => '最大 Worker';

  @override
  String get agentsMaxRetriesLabel => '最大重試';

  @override
  String get agentsSchedulerPolicyLabel => '調度策略';

  @override
  String get agentsTaskLabelsLabel => '任務標籤';

  @override
  String get agentsFieldName => '名稱';

  @override
  String get agentsFieldTarget => '目標';

  @override
  String get agentsMetadataInfoTitle => '權限與輪廓中繼資料';

  @override
  String get agentsNoOptionsAvailable => '暫無可選項。';

  @override
  String get agentExecutionModeNormal => '預設模式';

  @override
  String get agentExecutionModeFullAccess => '完全存取模式';

  @override
  String get agentLifecycleStopped => '已停止';

  @override
  String get agentLifecycleRunning => '執行中';

  @override
  String get agentLifecyclePaused => '已暫停';

  @override
  String get agentLifecycleDegraded => '降級中';

  @override
  String get agentTaskStatusBacklog => '待分配';

  @override
  String get agentTaskStatusReady => '可執行';

  @override
  String get agentTaskStatusRunning => '執行中';

  @override
  String get agentTaskStatusWaitingApproval => '待審批';

  @override
  String get agentTaskStatusPaused => '已暫停';

  @override
  String get agentTaskStatusCompleted => '已完成';

  @override
  String get agentTaskStatusFailed => '失敗';

  @override
  String get agentTaskStatusCanceled => '已取消';

  @override
  String get agentApprovalStatusPending => '待審批';

  @override
  String get agentApprovalStatusApproved => '已核准';

  @override
  String get agentApprovalStatusRejected => '已拒絕';

  @override
  String get agentApprovalStatusExpired => '已過期';

  @override
  String get agentWorkerStatusIdle => '閒置';

  @override
  String get agentWorkerStatusBusy => '忙碌';

  @override
  String get agentWorkerStatusDraining => '移出中';

  @override
  String get agentWorkerStatusOffline => '離線';

  @override
  String get agentsActivityAgentStarted => '智慧體已啟動';

  @override
  String get agentsActivityAgentStopped => '智慧體已停止';

  @override
  String get agentsActivityTaskPublished => '任務已發布';

  @override
  String get agentsActivityTaskUpdated => '任務已更新';

  @override
  String get agentsActivityTaskCanceled => '任務已取消';

  @override
  String get agentsActivityTaskPaused => '任務已暫停';

  @override
  String get agentsActivityTaskTerminated => '任務已終止';

  @override
  String get agentsActivityTaskResumed => '任務已恢復';

  @override
  String get hookEventSessionStart => '會話開始';

  @override
  String get hookEventUserPromptSubmit => '使用者提交提示詞';

  @override
  String get hookEventPreToolUse => '工具呼叫前';

  @override
  String get hookEventPostToolUse => '工具呼叫後';

  @override
  String get hookEventSubagentStart => '子代理啟動';

  @override
  String get hookEventSubagentStop => '子代理停止';

  @override
  String get hookEventStop => '代理停止';

  @override
  String get hookEventPreCompact => '上下文壓縮前';

  @override
  String get hookEventSessionEnd => '會話結束';

  @override
  String get hookEventErrorOccurred => '發生錯誤';

  @override
  String get builtinToolLoadStrategyEagerShort => '立即';

  @override
  String get builtinToolLoadStrategyLazy => '懶載入';

  @override
  String get builtinToolLoadStrategyDeferred => '緩載入';

  @override
  String get builtinToolLoadStrategyEagerFull => '立即載入';

  @override
  String get builtinToolCustomBadge => '自訂';

  @override
  String get builtinToolForceBadge => '強制載入';

  @override
  String get builtinToolMoveUp => '上移';

  @override
  String get builtinToolMoveDown => '下移';

  @override
  String builtinToolEditorTitle(String kind) {
    return '編輯工具 — $kind';
  }

  @override
  String get builtinToolEnableTitle => '啟用工具';

  @override
  String get builtinToolEnableBody => '停用後，此工具不會出現在模型的工具目錄中。';

  @override
  String get builtinToolDisplayNameLabel => '顯示名稱（可選）';

  @override
  String get builtinToolDisplayNameHelper => '覆寫預設工具名稱；留空則使用內建預設名稱。';

  @override
  String get builtinToolSummaryLabel => '簡介（可選）';

  @override
  String get builtinToolSummaryHelper => '用於在工具清單中快速了解工具用途。';

  @override
  String get builtinToolPromptOverrideLabel => 'Prompt 追加覆寫（可選）';

  @override
  String get builtinToolPromptOverrideHelper =>
      '追加到工具 description 末尾，可用於微調模型對此工具的使用策略。';

  @override
  String get builtinToolSchemaOverrideLabel => 'Schema 覆寫（JSON，可選）';

  @override
  String get builtinToolSchemaOverrideHelper =>
      '完整的 JSON Schema 物件，用於覆寫工具輸入參數定義。留空使用預設。';

  @override
  String get builtinToolPriorityLabel => '優先級 (0–9999)';

  @override
  String get builtinToolPriorityHelper => '越小越優先';

  @override
  String get builtinToolLoadStrategyLabel => '載入策略';

  @override
  String get builtinToolForceLoadTitle => '強制載入';

  @override
  String get builtinToolForceLoadBody =>
      '開啟後，即使全域內建工具懶載入處於自動或開啟，也會預設直接攜帶此工具 schema。';

  @override
  String get builtinToolMaxOutputLabel => '輸出上限（字元）';

  @override
  String get builtinToolGlobalDefaultHint => '使用全域預設';

  @override
  String get builtinToolTagsLabel => '標籤（逗號分隔）';

  @override
  String get builtinToolTagsHelper => '例如: io, file, dangerous';

  @override
  String get builtinToolRequireConfirmationTitle => '執行確認';

  @override
  String get builtinToolRequireConfirmationBody =>
      '是否在執行前彈窗讓使用者確認。選「預設」時使用工具自身行為。';

  @override
  String get builtinToolConfirmationDefault => '預設';

  @override
  String get builtinToolConfirmationYes => '需要確認';

  @override
  String get builtinToolConfirmationNo => '無需確認';

  @override
  String get memoryTitleField => '標題（可選）';

  @override
  String get memoryTitleHint => '用一句話濃縮此記憶主旨；留空則使用正文預覽';

  @override
  String get commonRetry => '重試';

  @override
  String get commonOk => '好的';

  @override
  String get commonExport => '匯出';

  @override
  String get appUpdateDialogTitle => '檢查更新';

  @override
  String get appUpdateChecking => '正在檢查更新...';

  @override
  String appUpdateCurrentVersion(Object version) {
    return '目前版本: $version';
  }

  @override
  String appUpdateNewVersion(Object version) {
    return '發現新版本: v$version';
  }

  @override
  String appUpdatePublished(Object date) {
    return '發布時間: $date';
  }

  @override
  String appUpdateFileSize(Object size) {
    return '檔案大小: $size';
  }

  @override
  String get appUpdateAlreadyLatestTitle => '已是最新版本';

  @override
  String appUpdateAlreadyLatestBody(Object version) {
    return 'OpenHand $version 已是最新版本。';
  }

  @override
  String get appUpdateDownloadComplete => '下載完成';

  @override
  String get appUpdateDownloading => '正在下載...';

  @override
  String get appUpdateCheckFailed => '檢查更新失敗';

  @override
  String get appUpdateLater => '稍後';

  @override
  String get appUpdateDownload => '下載更新';

  @override
  String get exportRangeInvalid => '請輸入有效區間 (1 ≤ 起始 ≤ 結束)';

  @override
  String get exportRangeStart => '起始';

  @override
  String get exportRangeEnd => '結束';

  @override
  String get exportSessionSettingsTitle => '匯出會話設定';

  @override
  String exportTotalMessages(Object count) {
    return '共 $count 則訊息可匯出';
  }

  @override
  String get exportRolesSection => '匯出 Role';

  @override
  String get exportAllRoles => '全部 role';

  @override
  String get exportMessageKindsSection => '訊息類型 (kind)';

  @override
  String get exportAllKinds => '全部類型';

  @override
  String get exportMessageRangeSection => '訊息區間';

  @override
  String get exportOnlyRange => '僅匯出指定區間 (1-based, 包含兩端)';

  @override
  String get exportOtherOptions => '其他選項';

  @override
  String get exportIncludeDeleted => '包含已刪除訊息';

  @override
  String get exportPickOneRole => '請至少選擇一個 role。';

  @override
  String get exportPickOneMessageKind => '請至少選擇一個訊息類型。';

  @override
  String get exportRoleSystem => '系統 (system)';

  @override
  String get exportRoleUser => '使用者 (user)';

  @override
  String get exportRoleAssistant => '助手 (assistant)';

  @override
  String get exportRoleTool => '工具 (tool)';

  @override
  String get exportKindUser => '使用者訊息';

  @override
  String get exportKindAssistant => '助手回覆';

  @override
  String get exportKindReasoning => '思考過程';

  @override
  String get exportKindToolCall => '工具呼叫';

  @override
  String get exportKindTool => '工具結果';

  @override
  String get exportKindCompressionPoint => '壓縮節點';

  @override
  String get exportKindMcp => 'MCP 事件';

  @override
  String get exportKindSkill => '技能事件';

  @override
  String get exportKindHook => 'Hook 事件';

  @override
  String get exportKindSelfLearning => '自學習';

  @override
  String get exportKindFileMutationSummary => '檔案變動摘要';

  @override
  String get exportKindStatus => '狀態訊息';

  @override
  String get exportPhaseLogRangeSection => '階段日誌區間';

  @override
  String exportTotalPhaseLogs(Object count) {
    return '共 $count 則階段日誌可匯出';
  }

  @override
  String get modelSearchHint => '搜尋模型…';

  @override
  String modelSearchResultCount(Object filtered, Object total) {
    return '$filtered / $total 個模型';
  }

  @override
  String get modelSearchNoAvailableModels => '暫無可用模型';

  @override
  String get modelSearchNoMatchingModels => '沒有相符模型';

  @override
  String get modelSearchRecent => '最近使用';

  @override
  String get nativeAudioLoadFailed => '音訊載入失敗，可使用系統播放器開啟。';

  @override
  String get nativeAudioPlaybackFailed => '播放失敗，請重試或使用系統播放器。';

  @override
  String get nativeAudioBack15Seconds => '倒退 15 秒';

  @override
  String get nativeAudioPause => '暫停';

  @override
  String get nativeAudioPlay => '播放';

  @override
  String get nativeAudioForward15Seconds => '快轉 15 秒';

  @override
  String get nativeAudioMute => '靜音';

  @override
  String get nativeAudioUnmute => '取消靜音';

  @override
  String get nativeAudioSystemPlayer => '系統播放器';

  @override
  String get nativeAudioSequencePlayback => '順序播放';

  @override
  String get nativeAudioRepeatOne => '單曲循環';

  @override
  String get nativeAudioShufflePlayback => '隨機播放';

  @override
  String nativeAudioEffectTooltip(Object effect) {
    return '音效：$effect';
  }

  @override
  String get nativeAudioEffectStandard => '標準';

  @override
  String get nativeAudioEffectSpatial => '3D';

  @override
  String get nativeAudioEffectVocal => '人聲';

  @override
  String get nativeAudioEffectWarm => '暖聲';

  @override
  String get hooksTitle => 'Hooks';

  @override
  String get hooksSubtitle =>
      '為 AI Agent 的生命週期階段配置要執行的腳本。每個 Hook 會在對應事件觸發時依序執行。';

  @override
  String get hooksNew => '新增 Hook';

  @override
  String get hooksDeleteTitle => '刪除 Hook';

  @override
  String hooksDeleteMessage(Object label) {
    return '確定刪除「$label」嗎？此操作無法復原。';
  }

  @override
  String get hooksEmptyTitle => '暫無 Hook 配置';

  @override
  String get hooksEmptyBody => '點擊右上角「新增 Hook」按鈕開始配置。';

  @override
  String get hooksTimeoutTooltip => '逾時時間';

  @override
  String hooksInlineScriptDescription(Object firstLine) {
    return '內嵌腳本: $firstLine';
  }

  @override
  String get hooksNoScriptConfigured => '未配置腳本';

  @override
  String get hooksEditTitle => '編輯 Hook';

  @override
  String get hooksLabelField => '名稱';

  @override
  String get hooksLabelHint => '例如: 日誌記錄';

  @override
  String get hooksTriggerEvent => '觸發事件';

  @override
  String get hooksScriptSource => '腳本來源';

  @override
  String get hooksScriptSourceFile => '選擇檔案';

  @override
  String get hooksScriptSourceInline => '編寫腳本';

  @override
  String get hooksScriptFilePath => '腳本檔案路徑';

  @override
  String get hooksScriptFileHint => '選擇 .sh / .ps1 / .bat 檔案';

  @override
  String get hooksBrowse => '瀏覽';

  @override
  String get hooksScriptContextFileHelp =>
      '上下文 JSON 會透過兩種方式傳入（均可安全用於 jq）：\n① 臨時檔案: jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\"\n② stdin 原始位元組: jq -r .session_id\n包含 session_id、session_file_path、environment 等欄位。';

  @override
  String get hooksInlineWindowsHint => '輸入 PowerShell / BAT 腳本';

  @override
  String get hooksInlineShellHint => '輸入 Shell 腳本（無需 #!/bin/bash）';

  @override
  String get hooksScriptContextInlineHelp =>
      '上下文 JSON 會透過兩種方式傳入（均可安全用於 jq）：\n① 臨時檔案: SID=\$(jq -r .session_id \"\$OPENHAND_HOOK_CONTEXT_FILE\")\n② stdin 原始位元組: SID=\$(jq -r .session_id)\n包含 session_id、session_file_path、environment、statistics 等欄位。';

  @override
  String get hooksTimeoutSeconds => '逾時時間（秒）';

  @override
  String get hooksEnabled => '啟用';

  @override
  String get hooksValidationLabelRequired => '請填寫 Hook 名稱。';

  @override
  String get hooksValidationScriptFileRequired => '請選擇腳本檔案。';

  @override
  String get hooksValidationInlineScriptRequired => '請填寫內嵌腳本內容。';

  @override
  String get hooksFileTypeScripts => '腳本';

  @override
  String get hooksFileTypeShellScripts => 'Shell 腳本';

  @override
  String get hooksFileTypeAllFiles => '所有檔案';

  @override
  String get commonConfirm => '確定';

  @override
  String get choiceInputCustomOptionLabel => '自訂輸入';

  @override
  String get choiceInputCustomInputHint => '在此輸入你的回答…';

  @override
  String get choiceInputCustomOptionDescription => '選擇此項以手動填寫內容';

  @override
  String get mediaPreviewImageCopied => '已複製圖片到剪貼簿。';

  @override
  String get mediaPreviewImageFileOrPathCopied => '已複製圖片檔案或路徑到剪貼簿。';

  @override
  String get mediaPreviewMediaFileCopied => '已複製媒體檔案到剪貼簿。';

  @override
  String get mediaPreviewDirectCopyUnavailablePathCopied =>
      '目前平台不支援直接複製媒體檔案，已複製檔案路徑。';

  @override
  String get mediaPreviewMediaUrlCopied => '已複製媒體位址。';

  @override
  String get mediaPreviewDirectCopyUnavailableTempPathCopied =>
      '目前平台不支援直接複製媒體檔案，已複製臨時檔案路徑。';

  @override
  String get mediaPreviewDataCopyFailedUrlCopied => '無法複製媒體資料，已複製來源位址。';

  @override
  String mediaPreviewCopyFailed(Object error) {
    return '複製失敗：$error';
  }

  @override
  String get mediaPreviewNoSource => '媒體來源不可用。';

  @override
  String get knowledgeVectorDistributionTitle => '向量分布';

  @override
  String get knowledgeVectorDistributionLoading => '正在取樣並投影向量。';

  @override
  String get knowledgeVectorDistributionEmpty => '目前 collection 沒有可展示的向量。';

  @override
  String get knowledgeVectorProjectionSection => '投影說明';

  @override
  String get knowledgeVectorAlgorithm => '演算法';

  @override
  String get knowledgeVectorOriginalDimensions => '原始維度';

  @override
  String get knowledgeVectorVisiblePoints => '展示點數';

  @override
  String get knowledgeVectorSampled => '是否取樣';

  @override
  String get knowledgeVectorDurationMs => '耗時毫秒';

  @override
  String get knowledgeVectorResample => '重新取樣';

  @override
  String get qdrantStatusRefreshIncomplete => 'Qdrant 狀態重新整理返回的資料不完整。';

  @override
  String get qdrantStatusRawVectorEmpty => '請先輸入 raw vector。';

  @override
  String qdrantStatusRawVectorInvalid(Object value) {
    return '原始向量包含無效數值：$value';
  }

  @override
  String qdrantStatusRawVectorDimensionMismatch(int actual, int expected) {
    return '原始向量維度為 $actual，目前設定要求 $expected。';
  }

  @override
  String get qdrantStatusPointIdsEmpty => '請先輸入 point/chunk id。';

  @override
  String get qdrantStatusPayloadIndexesSubmitted => '常用 Payload 索引已提交建立/重建。';

  @override
  String get qdrantStatusDangerousOpsDisabled => '請先在知識庫設定中啟用危險管理操作。';

  @override
  String get qdrantStatusDeletePointIdsEmpty => '請先輸入要刪除的向量點 ID。';

  @override
  String get qdrantStatusDeletePointsTitle => '刪除 Qdrant 向量點？';

  @override
  String qdrantStatusDeletePointsMessage(int count) {
    return '將從目前集合刪除 $count 個向量點。此操作無法復原。';
  }

  @override
  String get qdrantStatusDeletePointsConfirm => '刪除向量點';

  @override
  String get qdrantStatusPointsDeleted => '向量點已刪除。';

  @override
  String get qdrantStatusDeleteCollectionTitle => '刪除 Qdrant 集合？';

  @override
  String qdrantStatusDeleteCollectionMessage(Object collection) {
    return '將刪除集合「$collection」及其中所有向量點。此操作無法復原。';
  }

  @override
  String get qdrantStatusDeleteCollectionConfirm => '刪除集合';

  @override
  String get qdrantStatusCollectionDeleted => '集合已刪除。';

  @override
  String get qdrantStatusDiagnosticsCopied => '診斷資訊已複製。';

  @override
  String get qdrantStatusTitle => 'Qdrant 維運';

  @override
  String get qdrantStatusTabOverview => '總覽監控';

  @override
  String get qdrantStatusTabCollections => '集合管理';

  @override
  String get qdrantStatusTabPoints => '向量點查詢';

  @override
  String get qdrantStatusTabDiagnostics => '診斷日誌';

  @override
  String get qdrantStatusRefresh => '重新整理';

  @override
  String get qdrantStatusCopyDiagnostics => '複製診斷';

  @override
  String get qdrantStatusHeaderTitle => '本機向量資料庫即時狀態';

  @override
  String get qdrantStatusMetricCollections => '集合';

  @override
  String get qdrantStatusMetricPoints => '向量点';

  @override
  String get qdrantStatusMetricIndexedVectors => '已索引向量';

  @override
  String get qdrantStatusMetricChunks => '分块';

  @override
  String get qdrantStatusMetricPendingJobs => '待處理任務';

  @override
  String get qdrantStatusMetricWalCapacity => 'WAL 容量';

  @override
  String get qdrantStatusSmoothTrend => '平滑趋势';

  @override
  String get qdrantStatusNoCollections => '沒有集合，或目前 Qdrant 服務不可用。';

  @override
  String get qdrantStatusPointsSectionTitle => '向量点查询 / 搜索 / 滚动读取';

  @override
  String get qdrantStatusPointIdsLabel => '向量點/分塊 ID（空格或逗號分隔）';

  @override
  String get qdrantStatusSourceFilterLabel => '來源 ID 篩選';

  @override
  String get qdrantStatusTagFilterLabel => '標籤篩選';

  @override
  String get qdrantStatusLimitLabel => '數量上限';

  @override
  String get qdrantStatusRawVectorLabel => '原始向量（逗號或空格分隔，維度必須符合目前設定）';

  @override
  String get qdrantStatusQueryIds => '依 ID 查詢';

  @override
  String get qdrantStatusScrollFilter => '捲動讀取 / 篩選';

  @override
  String get qdrantStatusRawVectorSearch => '原始向量搜尋';

  @override
  String get qdrantStatusRebuildPayloadIndexes => '重建 Payload 索引';

  @override
  String get qdrantStatusDeletePoints => '删除 Points';

  @override
  String get qdrantStatusOperationResult => '操作結果';

  @override
  String get qdrantStatusRawDiagnosticsJson => '原始診斷 JSON';

  @override
  String get qdrantStatusNoDiagnostics => '尚無診斷資料。';

  @override
  String get qdrantStatusLatestOperationResult => '最近操作結果';

  @override
  String get qdrantStatusOperationLog => '操作日誌';

  @override
  String get qdrantStatusNoOperations => '尚無操作。';

  @override
  String get qdrantStatusCollectingSamples => '等待更多取樣後顯示趨勢。';

  @override
  String get qdrantStatusTrendPoints => '向量点';

  @override
  String get qdrantStatusTrendChunks => '分块';

  @override
  String get qdrantStatusTrendPendingFailed => '待處理/失敗';

  @override
  String qdrantStatusTrendSampleCount(int count) {
    return '$count 點';
  }

  @override
  String get qdrantSectionOverview => '總覽';

  @override
  String get qdrantSectionDockerContainer => 'Docker / 容器指標';

  @override
  String get qdrantSectionApiMetrics => 'Qdrant API 指標';

  @override
  String get qdrantSectionCollectionConfig => '集合設定';

  @override
  String get qdrantSectionStorageOptimizer => '儲存 / 優化器';

  @override
  String get qdrantSectionTelemetry => '遙測資料';

  @override
  String get qdrantSectionOpenHandKnowledge => 'OpenHand 知識庫指標';

  @override
  String get qdrantMetricServiceStatus => '服務狀態';

  @override
  String get qdrantMetricRestEndpoint => 'REST 端點';

  @override
  String get qdrantMetricGrpcEndpoint => 'gRPC 端點';

  @override
  String get qdrantMetricQdrantVersion => 'Qdrant 版本';

  @override
  String get qdrantMetricCurrentCollection => '目前集合';

  @override
  String get qdrantMetricCollectionStatus => '集合狀態';

  @override
  String get qdrantMetricOptimizerStatus => '優化器狀態';

  @override
  String get qdrantMetricLastHealthCheck => '最近健康檢查時間';

  @override
  String get qdrantMetricDockerDaemon => 'Docker 守護行程';

  @override
  String get qdrantMetricContainerCpu => '容器 CPU';

  @override
  String get qdrantMetricContainerMemory => '容器記憶體';

  @override
  String get qdrantMetricNetworkIo => '網路收發';

  @override
  String get qdrantMetricBlockIo => '块设备 I/O';

  @override
  String get qdrantMetricRestartCount => '重新啟動次數';

  @override
  String get qdrantMetricLatestLogSummary => '最近日誌摘要';

  @override
  String get qdrantMetricCollectionsTotal => '集合總數';

  @override
  String get qdrantMetricPointsTotal => '向量點總數';

  @override
  String get qdrantMetricVectorsTotal => '向量總數';

  @override
  String get qdrantMetricIndexedVectorsTotal => '已索引向量總數';

  @override
  String get qdrantMetricSegmentsTotal => '分段數';

  @override
  String get qdrantMetricPayloadSchemaFields => 'Payload schema 欄位數';

  @override
  String get qdrantMetricPayloadSchemaNames => 'Payload schema 欄位';

  @override
  String get qdrantMetricVectorSize => '向量維度';

  @override
  String get qdrantMetricDistance => '距離度量';

  @override
  String get qdrantMetricSingleNodeMode => '單機模式';

  @override
  String get qdrantMetricPayloadIndexStatus => 'Payload 索引狀態';

  @override
  String get qdrantMetricClusterStatus => '叢集狀態';

  @override
  String get qdrantMetricHnswM => 'HNSW M';

  @override
  String get qdrantMetricHnswEfConstruct => 'HNSW ef_construct';

  @override
  String get qdrantMetricHnswFullScanThreshold => 'HNSW 全掃描閾值';

  @override
  String get qdrantMetricHnswMaxIndexingThreads => 'HNSW 最大索引執行緒';

  @override
  String get qdrantMetricOnDiskPayload => 'Payload 磁碟儲存';

  @override
  String get qdrantMetricShardNumber => '分片數';

  @override
  String get qdrantMetricReplicationFactor => '副本因子';

  @override
  String get qdrantMetricWriteConsistencyFactor => '寫入一致性因子';

  @override
  String get qdrantMetricReadFanOutFactor => '讀取扇出因子';

  @override
  String get qdrantMetricOptimizerDeletedThreshold => '優化器刪除閾值';

  @override
  String get qdrantMetricOptimizerVacuumMinVectorNumber => 'Vacuum 最小向量數';

  @override
  String get qdrantMetricOptimizerDefaultSegmentNumber => '預設分段數';

  @override
  String get qdrantMetricOptimizerMaxSegmentSize => '最大分段大小';

  @override
  String get qdrantMetricOptimizerIndexingThreshold => '索引閾值';

  @override
  String get qdrantMetricOptimizerFlushIntervalSeconds => '刷盤間隔秒數';

  @override
  String get qdrantMetricWalCapacityMb => 'WAL 容量 MB';

  @override
  String get qdrantMetricWalSegmentsAhead => 'WAL 預留段';

  @override
  String get qdrantMetricQuantization => '量化設定';

  @override
  String get qdrantMetricStrictMode => '嚴格模式';

  @override
  String get qdrantMetricTelemetryStatus => '遙測狀態';

  @override
  String get qdrantMetricAppVersion => '應用程式版本';

  @override
  String get qdrantMetricAppName => '應用程式名稱';

  @override
  String get qdrantMetricTelemetryCollections => '集合遙測';

  @override
  String get qdrantMetricTelemetryRequests => '請求遙測';

  @override
  String get qdrantMetricSourceCount => '來源數';

  @override
  String get qdrantMetricChunkCount => '分塊數';

  @override
  String get qdrantMetricPendingEmbeddingJobs => '待處理嵌入任務';

  @override
  String get qdrantMetricFailedEmbeddingJobs => '失敗嵌入任務';

  @override
  String get qdrantMetricEmbeddingModel => '目前嵌入模型';

  @override
  String get qdrantMetricEmbeddingDimensions => '目前向量維度';

  @override
  String get qdrantMetricRetrievalTopN => '召回 TopN';

  @override
  String get qdrantMetricRetrievalTopK => '最終 TopK';

  @override
  String get qdrantMetricMinSimilarity => '最低相似度';

  @override
  String get qdrantMetricPromptChunkBudget => 'Prompt 分塊預算';

  @override
  String get qdrantMetricPromptTokenBudget => 'Prompt token 預算';

  @override
  String get qdrantValueYes => '是';

  @override
  String get qdrantValueNo => '否';

  @override
  String get qdrantValueHealthy => '健康';

  @override
  String get qdrantValueUnknown => '未知';

  @override
  String get qdrantValueLoading => '載入中';

  @override
  String get qdrantValueAvailable => '可用';

  @override
  String get qdrantValueUnavailable => '不可用';

  @override
  String get qdrantValuePluginServiceScan => '由插件服務掃描';

  @override
  String get qdrantValuePluginRuntimeMetric => '由插件執行階段提供';

  @override
  String get qdrantValuePluginDetailsLogs => '可在插件詳情查看';

  @override
  String get qdrantValueLocalSingleNodeOrUnavailable => '本機單機 / 不可用';

  @override
  String get qdrantValueClusterInfoAvailable => '已返回叢集資訊';

  @override
  String get qdrantValuePayloadSchemaConfigured => '已設定 payload schema';

  @override
  String get qdrantValuePayloadSchemaMissing => '未發現 payload schema';
}
